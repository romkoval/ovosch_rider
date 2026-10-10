extends GutTest
## T-170: приоритет источника мощности в режиме `smart` (REQ-DEV-05 п.2, У-32) и плавная остановка
## без источника мощности (REQ-D3D-02 п.7, У-33; спуск — до ответа Н-74 без наката).
## План с ERG на `FakeTrainer` + симулятор CPS через `SensorHub`; свободная езда (SIM) — тот же хаб.

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


func _trainer() -> FakeTrainer:
	var t := FakeTrainer.new(7)
	t.connect_delay_sec = 0.0
	t.power_noise_w = 0.0
	t.cadence_noise_rpm = 0.0
	t.power_tau_sec = 0.001
	# Скорость станка до T-169 ещё может стать источником скорости плана; здесь — модель.
	t.emit_speed = false
	t.set_rider_power(180)
	t.connect_device("fake")
	return t


## Хаб `smart`: управляемый станок + симулятор CPS (200 Вт).
func _hub(t: FakeTrainer) -> SensorHub:
	var pm := FakePowerMeter.new()
	pm.set_power(200)
	_disposables.append(pm)
	var hub := SensorHub.new(t)
	hub.set_power_meter(pm)
	pm.connect_device("pm")
	_disposables.push_front(hub)
	return hub


func _pm(hub: SensorHub) -> FakePowerMeter:
	return hub.power_meter as FakePowerMeter


# ---------------------------------------------------------------------------
# REQ-DEV-05 п.2 — первый прогон: CPS отваливается и возвращается
# ---------------------------------------------------------------------------

func test_req_dev_05_c2_erg_plan_power_meter_over_trainer_with_fallback_and_return() -> void:
	var t := _trainer()
	var hub := _hub(t)
	var s := WorkoutSession.new(Workout.make("300", [WorkoutStep.watts(300, 180.0)] as Array[WorkoutStep]), hub, FTP)
	assert_eq(s.trainer_mode, TrainerDevice.MODE_SMART)
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		if s.executor.elapsed_sec() == 100:
			_pm(hub).inject_dropout(30.0)
		s.tick(1.0)
	var st := s.samples
	assert_almost_eq(st.size(), 300, 1)
	for k in range(3, st.size() + 1):
		var w: int = st.power_w[k - 1]
		assert_true(st.has_power[k - 1], "сэмпл %d: мощность есть всегда" % k)
		if k <= 100:
			assert_eq(w, 200, "сэмпл %d: измеритель главнее станка" % k)
		elif k >= 102 and k <= 130:
			assert_eq(w, 180, "сэмпл %d: измеритель отвалился — станок" % k)
		elif k >= 132:
			assert_eq(w, 200, "сэмпл %d: измеритель вернулся — снова он" % k)
	var targets: Array[int] = []
	for c in t.commands:
		if str(c.get("type", "")) == "target_power":
			targets.append(int(c.get("value", -1)))
	assert_true(targets.has(180), "Set Target Power уходит на станок как без измерителя: %s" % str(t.commands.slice(0, 4)))
	assert_eq(s.get_state(), WorkoutSession.State.FINISHED, "сессия не останавливалась")


func test_req_dev_05_c2b_power_meter_silence_switches_to_trainer_within_5s() -> void:
	var t := _trainer()
	var hub := _hub(t)
	var s := WorkoutSession.new(Workout.make("60", [WorkoutStep.watts(60, 180.0)] as Array[WorkoutStep]), hub, FTP)
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		if s.executor.elapsed_sec() == 20:
			_pm(hub).inject_silence(20.0)
		s.tick(1.0)
	var st := s.samples
	assert_eq(st.power_w[19], 200, "до тишины — измеритель")
	for k in range(26, 40):
		assert_eq(st.power_w[k - 1], 180, "сэмпл %d: не позже 5 с после последнего пакета — станок" % k)
	assert_eq(st.power_w[st.size() - 1], 200, "пакеты пошли — снова измеритель")


# ---------------------------------------------------------------------------
# REQ-DEV-05 п.2 — второй прогон: молчат оба (D3D-02 п.7)
# ---------------------------------------------------------------------------

func test_req_dev_05_c2d_both_silent_no_data_smooth_stop_plan_goes_on() -> void:
	var t := _trainer()
	var hub := _hub(t)
	var plan := Workout.make("300", [WorkoutStep.watts(210, 180.0), WorkoutStep.watts(90, 150.0)] as Array[WorkoutStep])
	var s := WorkoutSession.new(plan, hub, FTP)
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		if s.executor.elapsed_sec() == 199:
			_pm(hub).inject_silence(31.0)
			t.inject_silence(31.0)
		s.tick(1.0)
	var st := s.samples
	assert_eq(st.power_w[198], 200)
	var riding: float = st.speed_kmh[198]
	assert_gt(riding, 25.0, "до тишины едет")
	# Хаб держит последнее значение 5 с (WRK-08 п.4), дальше — «нет данных», не 0.
	for k in range(206, 231):
		assert_false(st.has_power[k - 1], "сэмпл %d: мощность «нет данных»" % k)
	var first_without: int = -1
	for k in range(200, 232):
		if not st.has_power[k - 1]:
			first_without = k
			break
	assert_gt(first_without, 0)
	assert_gt(st.speed_kmh[first_without - 1], 0.0, "первый сэмпл без источника — не мгновенный ноль")
	for k in range(first_without, 231):
		var drop: float = st.speed_kmh[k - 2] - st.speed_kmh[k - 1]
		assert_true(drop >= -0.001 and drop <= 5.0 + 0.001, "сэмпл %d: убывает не больше 5 км/ч (%.2f)" % [k, drop])
	assert_eq(st.speed_kmh[mini(first_without + 29, 230) - 1], 0.0, "0 не позже 30 с без источника")
	assert_eq(st.target_w[215], 150, "шаги плана сменяются по времени")
	assert_true(st.has_power[233] and st.power_w[233] == 200, "источник вернулся — 200 Вт")
	assert_gt(st.speed_kmh[234], 0.0, "и движение")


func test_req_dev_05_c2d_free_ride_sim_same_priority_and_smooth_stop() -> void:
	var t := _trainer()
	var hub := _hub(t)
	var s := FreeRideSession.new(hub, RouteCatalog.FLAT, 50, WEIGHT)
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
	assert_eq(st.power_w[50], 200, "свободная езда: измеритель главнее")
	assert_eq(st.power_w[115], 180, "измеритель отвалился — станок")
	assert_eq(st.power_w[150], 200, "вернулся — снова он")
	assert_false(st.has_power[210])
	assert_gt(st.speed_kmh[205], 0.0, "остановка плавная")
	assert_eq(st.speed_kmh[229], 0.0, "остановился")
	assert_almost_eq(st.distance_m[229], st.distance_m[225], 0.01, "стоит — дистанция не растёт")
	assert_gt(st.speed_kmh[240], 0.0, "источник вернулся — едет")
	var sim_cmds := 0
	for c in t.commands:
		if str(c.get("type", "")) == "simulation":
			sim_cmds += 1
	assert_gt(sim_cmds, 0, "SIM уходит на станок, от источника мощности не зависит")


# ---------------------------------------------------------------------------
# REQ-D3D-02 п.7 — модель без источника мощности
# ---------------------------------------------------------------------------

func test_req_d3d_02_c7_test1_flat_smooth_stop_and_restart() -> void:
	var m := SpeedModel.new()
	m.reset(30.0)
	var ref := SpeedModel.new()
	ref.reset(30.0)
	var v1: float = m.step_without_power(WEIGHT, 1.0, 0.0)
	assert_gt(v1, 0.0, "не мгновенный ноль")
	assert_almost_eq(v1, ref.step(0.0, WEIGHT, 1.0, 0.0), 0.1, "равна модели при 0 Вт")
	var prev: float = v1
	var stopped_at: int = -1
	for n in range(2, 31):
		var v: float = m.step_without_power(WEIGHT, 1.0, 0.0)
		assert_true(v <= prev + 1e-6 and prev - v <= 5.0 + 1e-6, "сэмпл %d: монотонно, ≤ 5 км/ч" % n)
		if v == 0.0 and stopped_at < 0:
			stopped_at = n
		prev = v
	assert_true(stopped_at > 0 and stopped_at <= 30, "0 не позже 30-го сэмпла (%d)" % stopped_at)
	for n in 30:
		assert_eq(m.step_without_power(WEIGHT, 1.0, 0.0), 0.0, "стоит — дистанция не растёт")
	assert_gt(m.step(200.0, WEIGHT, 1.0, 0.0), 0.0, "источник вернулся — со следующего сэмпла едет")


func test_req_d3d_02_c7_uphill_stops_by_model() -> void:
	var m := SpeedModel.new()
	m.reset(20.0)
	for n in 30:
		m.step_without_power(WEIGHT, 1.0, 6.0)
	assert_eq(m.speed_kmh, 0.0, "подъём: модель сводит скорость к 0")


## До ответа Н-74 наката нет: на спуске скорость не растёт и убывает ≤ 5 км/ч за сэмпл до 0
## не позже 30 с (правило У-32, приёмка T-153).
func test_req_d3d_02_c7b_descent_without_power_no_coasting_until_n74() -> void:
	var m := SpeedModel.new()
	assert_eq(m.coast_limit_sec, 0.0, "по умолчанию наката нет (Н-74 не решён)")
	m.reset(30.0)
	var prev: float = m.speed_kmh
	var zero_at: int = -1
	for n in range(1, 41):
		var v: float = m.step_without_power(WEIGHT, 1.0, -5.0)
		assert_true(v <= prev + 1e-6 and prev - v <= 5.0 + 1e-6, "сэмпл %d: не растёт, ≤ 5 км/ч" % n)
		if v == 0.0 and zero_at < 0:
			zero_at = n
		prev = v
	assert_true(zero_at > 0 and zero_at <= 30, "0 не позже 30-го сэмпла (%d)" % zero_at)


## Предложение реестра Н-74 (D3D-02 п.7 (б), тест 2) — при пределе наката 30 с.
func test_req_d3d_02_c7b_test2_proposal_descent_coasts_30s_then_stops_by_60th_sample() -> void:
	var m := SpeedModel.new()
	m.coast_limit_sec = 30.0
	m.reset(30.0)
	var ref := SpeedModel.new()
	ref.reset(30.0)
	for n in range(1, 31):
		var v: float = m.step_without_power(WEIGHT, 1.0, -5.0)
		assert_almost_eq(v, ref.step(0.0, WEIGHT, 1.0, -5.0), 0.1, "сэмпл %d: накат по модели при 0 Вт" % n)
	assert_gt(m.speed_kmh, 30.0, "на спуске накат разгоняет")
	var prev: float = m.speed_kmh
	var zero_at: int = -1
	for n in range(31, 71):
		var v: float = m.step_without_power(WEIGHT, 1.0, -5.0)
		assert_true(v <= prev + 1e-6 and prev - v <= 5.0 + 1e-6, "сэмпл %d: не растёт, ≤ 5 км/ч" % n)
		if v == 0.0 and zero_at < 0:
			zero_at = n
		prev = v
	assert_true(zero_at > 0 and zero_at <= 60, "0 не позже 60-го сэмпла (%d)" % zero_at)
	assert_eq(m.speed_kmh, 0.0, "до конца молчания стоит")


func test_req_d3d_02_c7b_free_ride_descent_distance_stops_growing() -> void:
	var t := _trainer()
	var hub := _hub(t)
	var s := FreeRideSession.new(hub, RouteCatalog.FLAT, 50, WEIGHT)
	_disposables.push_front(s)
	s.start()
	for i in 10:
		s.tick(1.0)
	_pm(hub).inject_silence(200.0)
	t.inject_silence(200.0)
	for i in 80:
		s.tick(1.0)
	var st := s.samples
	var last := st.size() - 1
	assert_false(st.has_power[last])
	assert_eq(st.speed_kmh[last], 0.0, "без источника аватар остановился")
	assert_almost_eq(st.distance_m[last], st.distance_m[last - 15], 0.01, "дистанция не растёт")
