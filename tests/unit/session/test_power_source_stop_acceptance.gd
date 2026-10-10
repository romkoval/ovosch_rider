extends GutTest
## Приёмка T-170 (tester): приоритет источника мощности в `smart` и остановка без источника.
## REQ-DEV-05 п.2 (тест и второй прогон), REQ-D3D-02 п.7 (тест 1, тест 2), У-32, У-33.
##
## Станок — `FakeTrainer` (180 Вт, ERG), измеритель — симулятор CPS `FakePowerMeter` на
## `StubBleBridge`, объединяет их `SensorHub` — так же, как в приложении в режиме `smart`.
## Номер сэмпла k (с 1) — слот секунды k; сэмпл k закрывается тиком на k-й секунде.

const FTP: int = 200
const WEIGHT: float = 75.0

var _disposables: Array = []


func before_each() -> void:
	_disposables = []


func after_each() -> void:
	for d: Variant in _disposables:
		if d != null and (d as Object).has_method("dispose"):
			(d as Object).call("dispose")
	_disposables = []


func _trainer(watts: int = 180) -> FakeTrainer:
	var t := FakeTrainer.new(21)
	t.connect_delay_sec = 0.0
	t.power_noise_w = 0.0
	t.cadence_noise_rpm = 0.0
	t.power_tau_sec = 0.001
	t.set_rider_power(watts)
	t.connect_device("fake")
	return t


func _hub(t: FakeTrainer, pm_watts: int = 200) -> SensorHub:
	var pm := FakePowerMeter.new()
	pm.set_power(pm_watts)
	_disposables.append(pm)
	var hub := SensorHub.new(t)
	hub.set_power_meter(pm)
	pm.connect_device("cps")
	_disposables.push_front(hub)
	return hub


static func _pm(hub: SensorHub) -> FakePowerMeter:
	return hub.power_meter as FakePowerMeter


static func _target_cmds(t: FakeTrainer) -> Array[int]:
	var out: Array[int] = []
	for c in t.commands:
		if str(c.get("type", "")) == "target_power":
			out.append(int(c.get("value", -1)))
	return out


# ===========================================================================
# REQ-DEV-05 п.2 — тест: CPS `disconnected` на 100-й, `connected` и пакеты с 131-й
# ===========================================================================

func test_req_dev_05_c2_plan_300s_erg_cps_disconnect_100_back_131() -> void:
	var t := _trainer()
	var hub := _hub(t)
	var s := WorkoutSession.new(Workout.make("300", [WorkoutStep.watts(150, 180.0), WorkoutStep.watts(150, 220.0)] as Array[WorkoutStep]), hub, FTP)
	assert_eq(s.trainer_mode, TrainerDevice.MODE_SMART, "предусловие: smart (ERG)")
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		if s.executor.elapsed_sec() == 100:
			_pm(hub).inject_dropout(30.0)
		s.tick(1.0)
	var st := s.samples
	assert_almost_eq(st.size(), 300, 1, "300 сэмплов")
	var lines: Array[String] = []
	for k in [1, 2, 99, 100, 101, 102, 129, 130, 131, 132, 133]:
		lines.append("%d:%s" % [k, str(st.power_w[k - 1]) if st.has_power[k - 1] else "—"])
	gut.p("границы: %s" % ", ".join(lines))
	for k in range(1, st.size() + 1):
		assert_true(st.has_power[k - 1], "сэмпл %d: мощность есть всё время (сессия не останавливалась)" % k)
		var w: int = st.power_w[k - 1]
		if k >= 2 and k <= 99:
			assert_eq(w, 200, "сэмпл %d: подключены оба → измеритель" % k)
		elif k >= 102 and k <= 129:
			assert_eq(w, 180, "сэмпл %d: измеритель отвалился → станок" % k)
		elif k >= 132:
			assert_eq(w, 200, "сэмпл %d: измеритель вернулся → снова он" % k)
		elif k in [100, 101, 130, 131]:
			assert_true(w == 200 or w == 180, "сэмпл %d (граница ±1 с): 200 или 180" % k)
	# Set Target Power — на станок как без измерителя (WRK-02): цели шагов 180 и 220.
	var tp := _target_cmds(t)
	assert_true(tp.has(180) and tp.has(220), "Set Target Power шагов ушёл на станок: %s" % str(tp))
	var t2 := _trainer()
	var s2 := WorkoutSession.new(Workout.make("300", [WorkoutStep.watts(150, 180.0), WorkoutStep.watts(150, 220.0)] as Array[WorkoutStep]), t2, FTP)
	s2.start()
	while s2.get_state() != WorkoutSession.State.FINISHED:
		s2.tick(1.0)
	assert_eq(tp, _target_cmds(t2), "команды цели те же, что без измерителя")


## Обрыв по тишине: переключение не позже 5 с после последнего пакета (±1 с на границе).
func test_req_dev_05_c2b_cps_silence_switches_within_5s_of_last_packet() -> void:
	var t := _trainer()
	var hub := _hub(t)
	var s := WorkoutSession.new(Workout.make("120", [WorkoutStep.watts(120, 180.0)] as Array[WorkoutStep]), hub, FTP)
	s.start()
	var last_packet_sec := -1
	while s.get_state() != WorkoutSession.State.FINISHED:
		if s.executor.elapsed_sec() == 50:
			_pm(hub).inject_silence(30.0)
		var before := _pm(hub).packets_sent
		s.tick(1.0)
		if _pm(hub).packets_sent > before and s.executor.elapsed_sec() <= 60:
			last_packet_sec = s.executor.elapsed_sec()
	var st := s.samples
	var first_trainer := -1
	for k in range(last_packet_sec + 1, 80):
		if st.power_w[k - 1] == 180:
			first_trainer = k
			break
	gut.p("последний пакет CPS — секунда %d, первый сэмпл станка — %d" % [last_packet_sec, first_trainer])
	assert_gt(first_trainer, 0, "переключение на станок было")
	assert_lte(first_trainer, last_packet_sec + 5 + 1, "не позже 5 с после последнего пакета (±1 с)")
	for k in range(first_trainer, 80):
		assert_eq(st.power_w[k - 1], 180, "сэмпл %d: станок до возврата пакетов" % k)


# ===========================================================================
# REQ-DEV-05 п.2 — второй прогон: с 200-й по 230-ю молчат и CPS, и станок
# ===========================================================================

func test_req_dev_05_c2_second_run_both_silent_200_230_plan() -> void:
	var t := _trainer()
	var hub := _hub(t)
	var plan := Workout.make("300", [WorkoutStep.watts(210, 180.0), WorkoutStep.watts(90, 150.0)] as Array[WorkoutStep])
	var s := WorkoutSession.new(plan, hub, FTP, 1.0, WEIGHT)
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		if s.executor.elapsed_sec() == 199:
			_pm(hub).inject_silence(31.0)  # пакетов нет в секунды 200..230
			t.inject_silence(31.0)
		s.tick(1.0)
	var st := s.samples
	var row: Array[String] = []
	for k in range(198, 236):
		row.append("%d:%s/%.1f" % [k, str(st.power_w[k - 1]) if st.has_power[k - 1] else "—", st.speed_kmh[k - 1]])
	gut.p("сэмпл:мощность/скорость: %s" % ", ".join(row))
	_check_second_run(st, "план")
	assert_eq(st.target_w[205 - 1], 180, "шаг 1 до 210-й")
	assert_eq(st.target_w[215 - 1], 150, "шаги плана сменяются по времени и в тишине")
	assert_eq(st.step_index[215 - 1], 1)
	assert_eq(s.get_state(), WorkoutSession.State.FINISHED, "план дошёл до конца")


func test_req_dev_05_c2_second_run_both_silent_200_230_free_ride_sim() -> void:
	var t := _trainer()
	var hub := _hub(t)
	var s := FreeRideSession.new(hub, RouteCatalog.FLAT, 50, WEIGHT, FTP)
	_disposables.push_front(s)
	s.start()
	for i in 260:
		if s.elapsed_sec() == 100:
			_pm(hub).inject_dropout(30.0)
		if s.elapsed_sec() == 199:
			_pm(hub).inject_silence(31.0)
			t.inject_silence(31.0)
		s.tick(1.0)
	var st := s.samples
	for k in range(2, 100):
		assert_eq(st.power_w[k - 1], 200, "свободная езда, сэмпл %d: измеритель" % k)
	for k in range(102, 130):
		assert_eq(st.power_w[k - 1], 180, "свободная езда, сэмпл %d: станок" % k)
	for k in range(132, 199):
		assert_eq(st.power_w[k - 1], 200, "свободная езда, сэмпл %d: снова измеритель" % k)
	_check_second_run(st, "свободная езда")
	var sims := 0
	for c in t.commands:
		if str(c.get("type", "")) == "simulation":
			sims += 1
	assert_gt(sims, 0, "SIM уходит на станок")


## Общие проверки второго прогона (DEV-05 п.2, D3D-02 п.7).
func _check_second_run(st: SampleStream, what: String) -> void:
	var first_none := -1
	for k in range(200, 232):
		if not st.has_power[k - 1]:
			first_none = k
			break
	gut.p("%s: первый сэмпл «нет данных» — %d (последний пакет — 199-я секунда)" % [what, first_none])
	assert_gt(first_none, 0, "%s: «нет данных» наступает" % what)
	# Сэмплы до порога — удержанное значение источника (WRK-08 п.4), не 0.
	for k in range(200, first_none):
		assert_true(st.has_power[k - 1] and st.power_w[k - 1] > 0, "%s, сэмпл %d: удержание последнего значения, не 0" % [what, k])
	# Порог WRK-08 п.4 / DEV-05 п.2 (б): «нет данных» не позже 5 с после последнего пакета (±1 с).
	assert_lte(first_none, 199 + 5 + 1, "%s: «нет данных» не позже 5 с после последнего пакета (±1 с)" % what)
	for k in range(first_none, 231):
		assert_false(st.has_power[k - 1], "%s, сэмпл %d: мощность «нет данных», не 0" % [what, k])
	# Тяги нет — скорость убывает по модели плавно (D3D-02 п.7).
	var v_before: float = st.speed_kmh[first_none - 2]
	assert_gt(st.speed_kmh[first_none - 1], 0.0, "%s: первый сэмпл без источника — не мгновенный ноль" % what)
	assert_lt(st.speed_kmh[first_none - 1], v_before, "%s: и уже убывает" % what)
	var zero_at := -1
	for k in range(first_none, 231):
		var drop: float = st.speed_kmh[k - 2] - st.speed_kmh[k - 1]
		assert_true(drop >= -1e-4, "%s, сэмпл %d: скорость не растёт" % [what, k])
		assert_lte(drop, 5.0 + 1e-4, "%s, сэмпл %d: убывает не больше 5 км/ч" % [what, k])
		if zero_at < 0 and st.speed_kmh[k - 1] == 0.0:
			zero_at = k
	assert_gt(zero_at, 0, "%s: скорость дошла до 0" % what)
	assert_lte(zero_at - first_none + 1, 30, "%s: 0 не больше чем через 30 с" % what)
	assert_lte(zero_at, 230, "%s: 0 до конца молчания" % what)
	# С 231-й (±1 с) — снова 200 Вт и движение.
	assert_true(st.has_power[232 - 1] and st.power_w[232 - 1] == 200, "%s: сэмпл 232 — снова 200 Вт" % what)
	assert_gt(st.speed_kmh[233 - 1], 0.0, "%s: и движение" % what)


# ===========================================================================
# REQ-D3D-02 п.7 — тест 1: ровный участок 0 %, 30 км/ч, оба источника молчат
# ===========================================================================

## Мощность, при которой установившаяся скорость на 0 % — 30 км/ч.
static func _power_for_30() -> int:
	return roundi(SpeedModel.power_required_w(30.0 / 3.6, WEIGHT + SpeedModel.BIKE_MASS_KG, 0.0))


func test_req_d3d_02_c7_test1_flat_30kmh_both_silent_smooth_stop_then_restart() -> void:
	var p30 := _power_for_30()
	var t := _trainer(p30)
	var hub := _hub(t, p30)
	# План без трассы — уклон 0 % (ровный участок).
	var s := WorkoutSession.new(Workout.make("flat", [WorkoutStep.watts(300, float(p30))] as Array[WorkoutStep]), hub, FTP, 1.0, WEIGHT)
	s.start()
	for i in 60:
		s.tick(1.0)
	var st := s.samples
	var v0: float = st.speed_kmh[st.size() - 1]
	assert_almost_eq(v0, 30.0, 0.3, "предусловие: 30 км/ч на 0 %% (P = %d Вт)" % p30)
	_pm(hub).inject_dropout(150.0)  # `disconnected` CPS — без удержания
	t.inject_silence(100.0)
	# Станок держит последнее значение до 5 с (WRK-08 п.4) — ищем первый сэмпл без источника.
	var first := -1
	for i in 10:
		s.tick(1.0)
		if first < 0 and not st.has_power[st.size() - 1]:
			first = st.size() - 1
	assert_gt(first, 0, "источников нет — «нет данных»")
	for i in 70:
		s.tick(1.0)
	var v_prev: float = st.speed_kmh[first - 1]
	var ref := SpeedModel.new()
	ref.reset(v_prev)
	var v1: float = st.speed_kmh[first]
	assert_gt(v1, 0.0, "первый сэмпл без источника — больше 0 (не мгновенный ноль)")
	assert_almost_eq(v1, ref.step(0.0, WEIGHT, 1.0, 0.0), 0.1, "и равен модели при 0 Вт для той же скорости и массы")
	var zero_at := -1
	for i in range(first + 1, first + 40):
		var drop: float = st.speed_kmh[i - 1] - st.speed_kmh[i]
		assert_true(drop >= -1e-4 and drop <= 5.0 + 1e-4, "сэмпл %d без источника: не больше предыдущего, ≤ 5 км/ч" % (i - first + 1))
		if zero_at < 0 and st.speed_kmh[i] == 0.0:
			zero_at = i - first + 1
	assert_true(zero_at > 0 and zero_at <= 30, "0 не позже 30-го сэмпла без источника (%d)" % zero_at)
	var stop_idx: int = first + zero_at - 1
	for i in range(stop_idx + 1, stop_idx + 31):
		assert_almost_eq(st.distance_m[i], st.distance_m[stop_idx], 0.01, "30 сэмплов после остановки дистанция стоит (%d)" % i)
	# Источник вернулся (200 Вт) — со следующего сэмпла скорость больше 0.
	t.set_rider_power(200)
	var n_before := st.size()
	var moved_at := -1
	for i in 40:
		s.tick(1.0)
		var k := st.size() - 1
		if st.has_power[k]:
			assert_gt(st.speed_kmh[k], 0.0, "сэмпл с мощностью после возврата — скорость больше 0")
			moved_at = k
			break
	assert_gt(moved_at, n_before - 1, "станок вернулся")


func test_req_d3d_02_c7a_uphill_stops_by_model_distance_stays() -> void:
	var m := SpeedModel.new()
	m.reset(25.0)
	var prev := 25.0
	var zero_at := -1
	for n in range(1, 31):
		var v := m.step_without_power(WEIGHT, 1.0, 6.0)
		assert_true(v <= prev + 1e-6 and prev - v <= 5.0 + 1e-6, "подъём, сэмпл %d: монотонно, ≤ 5 км/ч" % n)
		if zero_at < 0 and v == 0.0:
			zero_at = n
		prev = v
	assert_gt(zero_at, 0, "подъём: модель сводит скорость к 0 (%d)" % zero_at)


# ===========================================================================
# REQ-D3D-02 п.7 (б) — тест 2: спуск −5 %, 30 км/ч, оба источника молчат 70 с
# ===========================================================================

## Трасса с прямым спуском −5 % на 1000–4000 м (коллинеарные опорные точки — PCHIP линейна).
static func _descent_position(start_s: float) -> RoutePosition:
	var prof := RouteProfile.from_points(PackedVector2Array([
		Vector2(0, 500), Vector2(1000, 450), Vector2(2000, 400), Vector2(3000, 350), Vector2(4000, 300),
		Vector2(5000, 400), Vector2(6000, 500)]))
	return RoutePosition.new(prof, start_s)


func test_req_d3d_02_c7b_test2_descent_minus5_both_silent_70s() -> void:
	var pos := _descent_position(1100.0)
	assert_almost_eq(pos.grade_pct(), -5.0, 0.01, "предусловие: уклон −5 %")
	var t := _trainer(0)
	var hub := _hub(t, 0)
	var s := WorkoutSession.new(Workout.make("d", [WorkoutStep.watts(300, 100.0)] as Array[WorkoutStep]), hub, FTP, 1.0, WEIGHT)
	s.position = pos
	# Разгон до 30 км/ч на спуске при 0 Вт (накат с данными источника, ≤ 5 км/ч за сэмпл), затем
	# обрыв обоих источников; сравнение — от скорости последнего сэмпла с источником.
	s.start()
	var st := s.samples
	var guard := 0
	while (st.size() == 0 or st.speed_kmh[st.size() - 1] < 30.0 - 1e-3) and guard < 20:
		guard += 1
		s.tick(1.0)
	assert_almost_eq(st.speed_kmh[st.size() - 1], 30.0, 0.01, "предусловие: 30 км/ч на −5 %")
	t.inject_dropout(200.0)
	_pm(hub).inject_dropout(200.0)
	var first := -1
	for i in 10:
		s.tick(1.0)
		if first < 0 and not st.has_power[st.size() - 1]:
			first = st.size() - 1
	assert_gt(first, 0)
	for i in 75:
		s.tick(1.0)
	var ref := SpeedModel.new()
	ref.reset(st.speed_kmh[first - 1])
	var ref_pos := _descent_position(1100.0 + st.distance_m[first - 1])
	var lines: Array[String] = []
	var mismatches := 0
	for n in range(1, 31):
		var i := first + n - 1
		var want := ref.step(0.0, WEIGHT, 1.0, ref_pos.grade_pct())
		ref_pos.advance(want, 1.0)
		lines.append("%d:%.1f/%.1f" % [n, st.speed_kmh[i], want])
		if absf(st.speed_kmh[i] - want) > 0.1:
			mismatches += 1
	gut.p("спуск, сэмпл:факт/модель при 0 Вт: %s" % ", ".join(lines))
	assert_eq(mismatches, 0, "спуск: в сэмплах 1–30 без источника скорость = модель при 0 Вт ±0.1 (накат); расхождений: %d — %s"
		% [mismatches, ", ".join(lines.slice(0, 8))])
	var zero_at := -1
	for n in range(31, 71):
		var i := first + n - 1
		var drop: float = st.speed_kmh[i - 1] - st.speed_kmh[i]
		assert_true(drop >= -1e-4 and drop <= 5.0 + 1e-4, "спуск, сэмпл %d: не растёт, ≤ 5 км/ч" % n)
		if zero_at < 0 and st.speed_kmh[i] == 0.0:
			zero_at = n
	assert_true(zero_at > 0 and zero_at <= 60, "спуск: 0 не позже 60-го сэмпла (%d)" % zero_at)
	if zero_at > 0:
		var stop_idx := first + zero_at - 1
		for i in range(stop_idx + 1, first + 70):
			assert_almost_eq(st.distance_m[i], st.distance_m[stop_idx], 0.01, "после остановки дистанция стоит")


## Модель отдельно: 30 км/ч на −5 %, без источника — первые 30 с по модели при 0 Вт (накат).
func test_req_d3d_02_c7b_test2_model_level_descent_from_30kmh() -> void:
	var m := SpeedModel.new()
	m.reset(30.0)
	var ref := SpeedModel.new()
	ref.reset(30.0)
	var got: Array[String] = []
	var bad := 0
	for n in range(1, 31):
		var v := m.step_without_power(WEIGHT, 1.0, -5.0)
		var want := ref.step(0.0, WEIGHT, 1.0, -5.0)
		got.append("%.1f/%.1f" % [v, want])
		if absf(v - want) > 0.1:
			bad += 1
	gut.p("факт/модель: %s" % ", ".join(got))
	assert_eq(bad, 0, "−5 %%, 30 км/ч: сэмплы 1–30 без источника = модель при 0 Вт ±0.1; расхождений %d — %s"
		% [bad, ", ".join(got.slice(0, 8))])
