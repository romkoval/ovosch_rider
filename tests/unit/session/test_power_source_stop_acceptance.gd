extends GutTest
## Приёмка T-170 (tester): приоритет источника мощности в `smart` и остановка без источника.
## REQ-DEV-05 п.2 (тест и второй прогон), REQ-D3D-02 п.7 (тесты 1–3), У-32, У-33, У-34
## (без источника — только шаг модели при 0 Вт: на ровном и в подъём остановка, на спуске накат без срока).
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
	_check_second_run(st, "план", false)
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
	_check_second_run(st, "свободная езда", true)
	var sims := 0
	for c in t.commands:
		if str(c.get("type", "")) == "simulation":
			sims += 1
	assert_gt(sims, 0, "SIM уходит на станок")


## Общие проверки второго прогона (DEV-05 п.2 в редакции У-34, D3D-02 п.7).
## `route_grade` — уклон шага брать из сэмпла (свободная езда); иначе 0 % (план без трассы).
func _check_second_run(st: SampleStream, what: String, route_grade: bool) -> void:
	var first_none := -1
	for k in range(200, 232):
		if not st.has_power[k - 1]:
			first_none = k
			break
	gut.p("%s: первый сэмпл «нет данных» — %d (последний пакет — 199-я секунда)" % [what, first_none])
	assert_true(first_none >= 203 and first_none <= 205, "%s: «нет данных» с 204-го (±1 с), удержание 5 с (WRK-08 п.4)" % what)
	for k in range(200, first_none):
		assert_true(st.has_power[k - 1] and st.power_w[k - 1] == 200, "%s, сэмпл %d: удержание последнего значения" % [what, k])
	for k in range(first_none, 231):
		assert_false(st.has_power[k - 1], "%s, сэмпл %d: мощность «нет данных», не 0" % [what, k])
	assert_gt(st.speed_kmh[first_none - 1], 0.0, "%s: первый сэмпл без источника — не мгновенный ноль" % what)
	var ref := SpeedModel.new()
	for k in range(first_none, 231):
		ref.reset(st.speed_kmh[k - 2])
		var g: float = st.grade_pct[k - 2] if route_grade else 0.0
		assert_almost_eq(st.speed_kmh[k - 1], ref.step(0.0, WEIGHT, 1.0, g), 0.1, "%s, сэмпл %d: шаг модели при 0 Вт" % [what, k])
		if st.speed_kmh[k - 1] == 0.0:
			assert_almost_eq(st.distance_m[k - 1], st.distance_m[k - 2], 0.01, "%s, сэмпл %d: скорость 0 — дистанция стоит" % [what, k])
	# С 231-й (±1 с) — снова 200 Вт и скорость по модели от 200 Вт.
	assert_true(st.has_power[232 - 1] and st.power_w[232 - 1] == 200, "%s: сэмпл 232 — снова 200 Вт" % what)
	ref.reset(st.speed_kmh[231 - 1])
	var g2: float = st.grade_pct[231 - 1] if route_grade else 0.0
	assert_almost_eq(st.speed_kmh[232 - 1], ref.step(200.0, WEIGHT, 1.0, g2), 0.1, "%s: скорость по модели от 200 Вт" % what)
	assert_gt(st.speed_kmh[233 - 1], 0.0, "%s: движение" % what)


# ===========================================================================
# REQ-D3D-02 п.7 — тесты 1–3 (У-34)
# ===========================================================================

## Устройство без управляемого станка: только симулятор CPS (обрыв — `disconnected`, «нет данных»
## со следующего сэмпла, без удержания) — «ни одного источника с данными» начинается ровно в момент
## обрыва, и скорость на входе в молчание известна точно.
func _pm_only(watts: int) -> UncontrolledTrainer:
	var b := StubBleBridge.new()
	_disposables.append(b)
	var pm := FakePowerMeter.new(b)
	pm.set_power(watts)
	_disposables.append(pm)
	var hub := SensorHub.new(null)
	hub.set_power_meter(pm)
	pm.connect_device("cps")
	var dev := UncontrolledTrainer.new(hub, SensorHub.SOURCE_POWER_METER)
	_disposables.push_front(dev)
	return dev


static func _pm_of(dev: UncontrolledTrainer) -> FakePowerMeter:
	return dev.hub.power_meter as FakePowerMeter


## Трасса из опорных точек (коллинеарные соседи — PCHIP линейна на участке).
static func _position(points: Array[Vector2], start_s: float) -> RoutePosition:
	return RoutePosition.new(RouteProfile.from_points(PackedVector2Array(points)), start_s)


## Прогон: разгон до `v0` км/ч на мощности `ride_w`, затем обрыв единственного источника на
## `silent_sec` с; возвращает {first, grades, session}. `grades[i]` — уклон перед шагом сэмпла i.
func _silent_run(pos: RoutePosition, v0: float, ride_w: int, silent_sec: int, back_w: int = -1) -> Dictionary:
	var dev := _pm_only(ride_w)
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(900, 150.0)] as Array[WorkoutStep]), dev, FTP, 1.0, WEIGHT)
	if pos != null:
		s.position = pos
	s.start()
	var grades: Array[float] = []
	var guard := 0
	while guard < 60 and (s.samples.size() == 0 or absf(s.samples.speed_kmh[s.samples.size() - 1] - v0) > 0.05):
		guard += 1
		grades.append(s.position.grade_pct())
		s.tick(1.0)
		if s.samples.speed_kmh[s.samples.size() - 1] > v0 + 0.05:
			break
	var first := s.samples.size()
	_pm_of(dev).inject_dropout(float(silent_sec) + 1.0)
	for i in silent_sec:
		grades.append(s.position.grade_pct())
		s.tick(1.0)
	if back_w >= 0:
		_pm_of(dev).set_power(back_w)
		for i in 4:
			grades.append(s.position.grade_pct())
			s.tick(1.0)
	return {"first": first, "grades": grades, "session": s}


## Каждый сэмпл без источника — шаг модели при 0 Вт от предыдущего с уклоном перед шагом (±0.1).
func _assert_steps(st: SampleStream, grades: Array[float], from: int, to: int, what: String) -> int:
	var bad := 0
	var ref := SpeedModel.new()
	var lines: Array[String] = []
	for i in range(from, to):
		ref.reset(st.speed_kmh[i - 1])
		var want := ref.step(0.0, WEIGHT, 1.0, grades[i])
		if absf(st.speed_kmh[i] - want) > 0.1:
			bad += 1
			if lines.size() < 6:
				lines.append("%d: %.2f≠%.2f" % [i - from + 1, st.speed_kmh[i], want])
		assert_false(st.has_power[i], "%s, сэмпл %d: «нет данных»" % [what, i - from + 1])
	assert_eq(bad, 0, "%s: каждый сэмпл без источника = шаг модели при 0 Вт (±0.1): %s" % [what, ", ".join(lines)])
	return bad


func test_req_d3d_02_c7_test1_flat_30kmh_silent_60s_then_200w() -> void:
	var r := _silent_run(null, 30.0, _power_for_30(), 60, 200)
	var s: WorkoutSession = r["session"]
	var st := s.samples
	var first: int = r["first"]
	assert_almost_eq(st.speed_kmh[first - 1], 30.0, 0.05, "предусловие: 30 км/ч на 0 %%")
	assert_gt(st.speed_kmh[first], 0.0, "первый сэмпл без источника > 0")
	_assert_steps(st, r["grades"], first, first + 60, "ровный 0 %")
	var zero_at := -1
	for i in range(first, first + 60):
		assert_true(st.speed_kmh[i] <= st.speed_kmh[i - 1] + 1e-4, "не больше предыдущего (%d)" % (i - first + 1))
		if zero_at < 0 and st.speed_kmh[i] == 0.0:
			zero_at = i
	assert_true(zero_at >= 0 and zero_at - first + 1 <= 30, "0 не позже 30-го сэмпла (%d)" % (zero_at - first + 1))
	for i in range(zero_at + 1, first + 60):
		assert_almost_eq(st.distance_m[i], st.distance_m[zero_at], 0.01, "после остановки дистанция стоит (%d)" % (i - first + 1))
	var k := first + 60
	assert_true(st.has_power[k] or st.has_power[k + 1], "источник вернулся")
	var back := k if st.has_power[k] else k + 1
	assert_gt(st.speed_kmh[back], 0.0, "со следующего сэмпла скорость > 0")


func test_req_d3d_02_c7_test1_uphill_5pct_15kmh() -> void:
	var up: Array[Vector2] = [Vector2(0, 0), Vector2(1000, 50), Vector2(2000, 100), Vector2(3000, 150), Vector2(6000, 0)]
	var pos := _position(up, 1100.0)
	assert_almost_eq(pos.grade_pct(), 5.0, 0.01, "предусловие: подъём 5 %%")
	var p15 := roundi(SpeedModel.power_required_w(15.0 / 3.6, WEIGHT + SpeedModel.BIKE_MASS_KG, 5.0))
	var r := _silent_run(pos, 15.0, p15, 45)
	var st: SampleStream = (r["session"] as WorkoutSession).samples
	var first: int = r["first"]
	assert_almost_eq(st.speed_kmh[first - 1], 15.0, 0.1, "предусловие: 15 км/ч")
	_assert_steps(st, r["grades"], first, first + 45, "подъём 5 %")
	var zero_at := -1
	for i in range(first, first + 45):
		assert_true(st.speed_kmh[i] <= st.speed_kmh[i - 1] + 1e-4, "подъём: не растёт")
		if zero_at < 0 and st.speed_kmh[i] == 0.0:
			zero_at = i
	assert_true(zero_at >= 0 and zero_at - first + 1 <= 30, "подъём: 0 не позже 30-го сэмпла")
	for i in range(zero_at + 1, first + 45):
		assert_almost_eq(st.distance_m[i], st.distance_m[zero_at], 0.01, "подъём: дистанция стоит")


func test_req_d3d_02_c7b_test2_descent_minus5_silent_120s_coasts_to_steady() -> void:
	var down: Array[Vector2] = [Vector2(0, 500), Vector2(1000, 450), Vector2(2000, 400), Vector2(3000, 350),
		Vector2(4000, 300), Vector2(5000, 250), Vector2(7500, 500)]
	var pos := _position(down, 1100.0)
	assert_almost_eq(pos.grade_pct(), -5.0, 0.01, "предусловие: спуск −5 %%")
	var r := _silent_run(pos, 30.0, 0, 120, 200)
	var s: WorkoutSession = r["session"]
	var st := s.samples
	var first: int = r["first"]
	assert_almost_eq(st.speed_kmh[first - 1], 30.0, 0.05, "предусловие: 30 км/ч на −5 %%")
	_assert_steps(st, r["grades"], first, first + 120, "спуск −5 %")
	var steady := SpeedModel.steady_speed_kmh(0.0, WEIGHT, -5.0)
	assert_almost_eq(steady, 49.8, 3.0, "опорная точка модели")
	for n in range(61, 121):
		var i := first + n - 1
		assert_almost_eq(st.speed_kmh[i], steady, 0.1, "сэмпл %d: установившаяся скорость наката" % n)
	for n in range(1, 121):
		var i := first + n - 1
		assert_gt(st.speed_kmh[i], 0.0, "сэмпл %d: не 0 — принудительной остановки нет" % n)
		assert_gt(st.distance_m[i], st.distance_m[i - 1], "сэмпл %d: дистанция растёт" % n)
	var back := first + 120
	if not st.has_power[back]:
		back += 1
	assert_true(st.has_power[back], "источник вернулся")
	var ref := SpeedModel.new()
	ref.reset(st.speed_kmh[back - 1])
	assert_almost_eq(st.speed_kmh[back], ref.step(200.0, WEIGHT, 1.0, (r["grades"] as Array[float])[back]), 0.1,
		"со следующего сэмпла — модель от 200 Вт")


func test_req_d3d_02_c7b_test3_descent_500m_then_flat_stops_after_transition() -> void:
	var pts: Array[Vector2] = [Vector2(0, 100), Vector2(250, 87.5), Vector2(500, 75), Vector2(1500, 75), Vector2(2500, 75),
		Vector2(3500, 75), Vector2(4000, 100), Vector2(5000, 100)]
	var pos := _position(pts, 0.0)
	var r := _silent_run(pos, 30.0, 0, 150)
	var s: WorkoutSession = r["session"]
	var st := s.samples
	var first: int = r["first"]
	var grades: Array[float] = r["grades"]
	_assert_steps(st, grades, first, first + 150, "спуск → ровный")
	# «Переход на ровный» — первый сэмпл, где уклон уже не даёт наката (установившаяся скорость при
	# 0 Вт = 0): профиль PCHIP сглаживает излом, и на пологом хвосте спуска (> −0.4 %) накат кончается.
	var transition := -1
	for i in range(first, first + 150):
		if transition < 0 and SpeedModel.steady_speed_kmh(0.0, WEIGHT, grades[i]) == 0.0 and i > first:
			transition = i
		if transition < 0:
			assert_gt(st.speed_kmh[i], 0.0, "на спуске скорость не 0 (сэмпл %d)" % (i - first + 1))
	gut.p("переход на ровный: сэмпл %d без источника, скорость %.1f" % [transition - first + 1, st.speed_kmh[maxi(transition, 0)]])
	assert_gt(transition, first, "доехал до ровного участка")
	var zero_at := -1
	for i in range(transition, first + 150):
		assert_true(st.speed_kmh[i] <= st.speed_kmh[i - 1] + 1e-4, "ровный: не растёт (%d)" % (i - transition + 1))
		if zero_at < 0 and st.speed_kmh[i] == 0.0:
			zero_at = i
	assert_true(zero_at >= 0 and zero_at - transition + 1 <= 30, "0 не позже 30-го сэмпла после перехода (%d)" % (zero_at - transition + 1))
	for i in range(zero_at + 1, first + 150):
		assert_almost_eq(st.distance_m[i], st.distance_m[zero_at], 0.01, "после остановки дистанция стоит")


## Мощность, при которой установившаяся скорость на 0 % — 30 км/ч.
static func _power_for_30() -> int:
	return roundi(SpeedModel.power_required_w(30.0 / 3.6, WEIGHT + SpeedModel.BIKE_MASS_KG, 0.0))
