extends GutTest
## T-152: сессии без управляемого станка (REQ-WRK-09 п.3, 4, 6, 7, 8; REQ-WRK-01 п.6; REQ-LOC-01 п.1;
## REQ-DEV-08 примечание; REQ-WRK-08 п.1–4). Эквивалентность `smart` (FakeTrainer) и `power_meter`
## (симулятор CPS), журнал моста без записей, сэмплы и «нет данных» при обрыве, переподключение,
## свободная езда по модели с уклоном, `trainer_mode` в метаданных, сводке и FIT.

const FTP: int = 200
const STARTED: int = 1_790_000_000

var _dir: String = ""
var _disposables: Array = []


func before_each() -> void:
	_dir = ""
	_disposables = []


func after_each() -> void:
	for d: Variant in _disposables:
		if d != null and (d as Object).has_method("dispose"):
			(d as Object).call("dispose")
	_disposables = []
	if not _dir.is_empty():
		_remove_tree(ProjectSettings.globalize_path(_dir))


static func _remove_tree(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var d := DirAccess.open(abs_path)
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)


# ---------------------------------------------------------------------------
# Устройства
# ---------------------------------------------------------------------------

func _fake_trainer(power: int = 200, cadence: int = 90) -> FakeTrainer:
	var t := FakeTrainer.new(11)
	t.connect_delay_sec = 0.0
	t.power_noise_w = 0.0
	t.cadence_noise_rpm = 0.0
	t.power_tau_sec = 0.001
	t.emit_speed = false
	t.set_rider_power(power)
	t.set_rider_cadence(cadence)
	t.connect_device("fake")
	return t


## Устройство `power_meter` поверх хаба с симулятором CPS на мосте `bridge` (+ станок хаба).
func _pm_device(bridge: StubBleBridge, power: int = 200, cadence: int = 90,
		hub_trainer: TrainerDevice = null) -> UncontrolledTrainer:
	var pm := FakePowerMeter.new(bridge)
	pm.set_power(power)
	pm.set_cadence(cadence)
	var hub := SensorHub.new(hub_trainer)
	hub.set_power_meter(pm)
	pm.connect_device("pm")
	var dev := UncontrolledTrainer.new(hub)
	_disposables.append(dev)
	_disposables.append(pm)
	return dev


func _pm_of(dev: UncontrolledTrainer) -> FakePowerMeter:
	return dev.hub.power_meter as FakePowerMeter


static func _plan_wrk_09() -> Workout:
	return Workout.make("WRK-09 п.3", [
		WorkoutStep.watts(60, 150.0),
		WorkoutStep.percent(60, 65.0),
		WorkoutStep.ramp_watts(60, 100.0, 200.0),
		WorkoutStep.free_ride(60),
	] as Array[WorkoutStep])


## Сценарий п.3: пауза 20 с на 70-й секунде, множитель 110 % со 100-й, пропуск шага 3 на его
## 30-й секунде (шаг 3 начинается на 120-й), плюс попытки ERG/сопротивления (`try_controls`).
func _drive_plan(s: WorkoutSession, try_controls: bool = false) -> void:
	s.start()
	var paused := false
	var guard := 0
	while s.get_state() != WorkoutSession.State.FINISHED and guard < 2000:
		guard += 1
		var t := s.executor.elapsed_sec()
		if t == 70 and not paused:
			paused = true
			s.pause()
			if try_controls:
				s.toggle_erg()
				s.set_resistance_level(80)
			for i in 20:
				s.tick(1.0)
			s.resume()
		if t == 100 and is_equal_approx(s.intensity(), 1.0):
			s.set_intensity(1.1)
			if try_controls:
				s.toggle_erg()
				s.set_resistance_level(30)
		if t == 150 and s.executor.current_step_index() == 2:
			s.skip_step()
		s.tick(1.0)


static func _event_keys(s: WorkoutSession) -> Array[String]:
	var out: Array[String] = []
	for e in s.events:
		out.append("%s@%.3f=%s" % [e["type"], float(e["at_sec"]), str(e["value"])])
	return out


# ---------------------------------------------------------------------------
# WRK-09 п.3, WRK-01 п.6 — эквивалентность smart и power_meter
# ---------------------------------------------------------------------------

func test_req_wrk_09_c3_wrk_01_c6_smart_and_power_meter_run_the_plan_identically() -> void:
	var smart := WorkoutSession.new(_plan_wrk_09(), _fake_trainer(), FTP)
	var bridge := StubBleBridge.new()
	_disposables.append(bridge)
	var pmode := WorkoutSession.new(_plan_wrk_09(), _pm_device(bridge), FTP)
	assert_eq(smart.trainer_mode, TrainerDevice.MODE_SMART)
	assert_eq(pmode.trainer_mode, TrainerDevice.MODE_POWER_METER)
	var steps_smart: Array[int] = []
	var steps_pm: Array[int] = []
	smart.executor.step_changed.connect(func(i: int, _s: WorkoutStep) -> void: steps_smart.append(i))
	pmode.executor.step_changed.connect(func(i: int, _s: WorkoutStep) -> void: steps_pm.append(i))
	_drive_plan(smart)
	_drive_plan(pmode, true)
	assert_eq(pmode.get_state(), WorkoutSession.State.FINISHED, "план завершился по таймеру")
	assert_eq(steps_pm, steps_smart, "одинаковые переходы шагов")
	assert_eq(pmode.executor.elapsed_sec(), smart.executor.elapsed_sec(), "одинаковое время завершения")
	assert_eq(_event_keys(pmode), _event_keys(smart), "одинаковые события паузы, множителя, пропуска, финиша")
	assert_eq(pmode.samples.size(), smart.samples.size())
	var same_steps := true
	var same_targets := true
	for i in smart.samples.size():
		same_steps = same_steps and smart.samples.step_index[i] == pmode.samples.step_index[i]
		same_targets = same_targets and smart.samples.target_w[i] == pmode.samples.target_w[i]
		assert_false(pmode.samples.erg_enabled[i], "флаг ERG в power_meter — «выкл» во всех сэмплах")
	assert_true(same_steps, "номера шагов сэмплов совпадают")
	assert_true(same_targets, "цели сэмплов совпадают (65 % FTP, рампа, ×1.1, FreeRide — 0)")
	# Цель шага 2 (65 % FTP при FTP 200 → 130) с множителем 110 % — 143.
	assert_eq(pmode.samples.target_w[pmode.samples.size() - 1], 0, "шаг FreeRide — цели нет")
	assert_true(pmode.samples.target_w.has(130), "65 %% FTP → 130 Вт")
	assert_true(pmode.samples.target_w.has(143), "130 × 1.1 → 143 Вт")
	assert_eq(pmode.metadata()[WorkoutSession.META_TRAINER_MODE], TrainerDevice.MODE_POWER_METER)
	assert_eq(smart.metadata()[WorkoutSession.META_TRAINER_MODE], TrainerDevice.MODE_SMART)
	var erg_events := 0
	for e in pmode.events:
		if e["type"] in [WorkoutSession.EVENT_ERG_ON, WorkoutSession.EVENT_ERG_OFF, WorkoutSession.EVENT_RESISTANCE]:
			erg_events += 1
	assert_eq(erg_events, 0, "WRK-09 п.8: событий ERG и сопротивления в power_meter нет")


func test_req_wrk_09_c3_intensity_changes_target_within_one_sample() -> void:
	var bridge := StubBleBridge.new()
	_disposables.append(bridge)
	var s := WorkoutSession.new(Workout.make("150", [WorkoutStep.watts(60, 150.0)] as Array[WorkoutStep]),
		_pm_device(bridge), FTP)
	s.start()
	for i in 5:
		s.tick(1.0)
	s.set_intensity(1.1)
	assert_eq(s.current_target_watts(), 165, "цель с множителем — сразу")
	s.tick(1.0)
	assert_eq(s.samples.target_w[s.samples.size() - 1], 165, "в сэмпле — не позже следующей секунды")


# ---------------------------------------------------------------------------
# WRK-09 п.4 — журнал моста: ни одного write, подписки только на данные
# ---------------------------------------------------------------------------

func test_req_wrk_09_c4_whole_scenario_has_no_writes_and_no_control_subscriptions() -> void:
	var bridge := StubBleBridge.new()
	_disposables.append(bridge)
	var trainer := TrainerFactory.create_ble(bridge)
	_disposables.append(trainer)
	var dev := _pm_device(bridge, 200, 90, trainer)
	var hrs := BleHeartRateSensor.new(bridge)
	_disposables.append(hrs)
	bridge.set_device_services("hrs", {BleUuids.HRS_SERVICE: PackedStringArray([BleUuids.HEART_RATE_MEASUREMENT])})
	dev.hub.set_heart_rate_sensor(hrs)
	hrs.connect_device("hrs")
	bridge.pump()
	# План со всеми действиями п.3 и попытками ERG/сопротивления.
	var s := WorkoutSession.new(_plan_wrk_09(), dev, FTP)
	_drive_plan(s, true)
	assert_eq(s.get_state(), WorkoutSession.State.FINISHED)
	# Переподключение источника мощности (п.6 (в)).
	var s2 := WorkoutSession.new(Workout.make("r", [WorkoutStep.watts(60, 150.0)] as Array[WorkoutStep]), dev, FTP)
	s2.start()
	for i in 10:
		s2.tick(1.0)
	_pm_of(dev).inject_dropout(12.0)
	while s2.get_state() != WorkoutSession.State.FINISHED:
		s2.tick(1.0)
	# Свободная езда 600 с на «горах» с попытками SIM, крутизны и сопротивления.
	var fr := FreeRideSession.new(dev, RouteCatalog.MOUNTAINS, 50, 75.0, FTP)
	_disposables.push_front(fr)
	fr.start()
	for i in 600:
		if i == 100:
			fr.set_steepness(100)
			fr.toggle_mode()
			fr.set_resistance_level(80)
		fr.tick(1.0)
	fr.stop()
	assert_eq(bridge.calls_of("write"), [] as Array[Dictionary], "ни одного write ни к одному устройству")
	var allowed := [BleUuids.CYCLING_POWER_MEASUREMENT, BleUuids.HEART_RATE_MEASUREMENT, BleUuids.CSC_MEASUREMENT,
		BleUuids.BATTERY_LEVEL]
	for c in bridge.calls_of("subscribe"):
		assert_true(allowed.has(c["char"]), "subscribe только на данные, не %s" % c["char"])
	assert_eq(fr.metadata()[WorkoutSession.META_TRAINER_MODE], TrainerDevice.MODE_POWER_METER)
	var fr_events: Array[String] = []
	for e in fr.events:
		fr_events.append(str(e["type"]))
	assert_false(fr_events.has(FreeRideSession.EVENT_SIM_UNAVAILABLE), "сообщения «станок не поддерживает SIM» нет")
	assert_false(fr_events.has(SimController.EVENT_STEEPNESS), "крутизна SIM ни на что не влияет")


# ---------------------------------------------------------------------------
# WRK-09 п.6 — сэмплы, обрыв, переподключение
# ---------------------------------------------------------------------------

## Пульсометр на мосте: нотификация пульса каждую секунду перед тиком.
func _hrs(bridge: StubBleBridge, hub: SensorHub) -> BleHeartRateSensor:
	var hrs := BleHeartRateSensor.new(bridge)
	_disposables.append(hrs)
	bridge.set_device_services("hrs", {BleUuids.HRS_SERVICE: PackedStringArray([BleUuids.HEART_RATE_MEASUREMENT])})
	hub.set_heart_rate_sensor(hrs)
	hrs.connect_device("hrs")
	bridge.pump()
	return hrs


func test_req_wrk_09_c6a_samples_power_cadence_hr_and_model_speed() -> void:
	var bridge := StubBleBridge.new()
	_disposables.append(bridge)
	var dev := _pm_device(bridge, 250, 90)
	_hrs(bridge, dev.hub)
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(30, 200.0)] as Array[WorkoutStep]), dev, FTP, 1.0, 75.0)
	s.start()
	var model := SpeedModel.new()
	for i in 30:
		bridge.emit_notification("hrs", BleUuids.HEART_RATE_MEASUREMENT, HrsCodec.encode_heart_rate_measurement(140))
		s.tick(1.0)
	var st := s.samples
	assert_eq(st.size(), 30, "сэмплы 1 Гц")
	assert_eq(st.speed_source, SampleStream.SPEED_SOURCE_MODEL, "скорость — модель")
	for i in st.size():
		assert_true(st.has_power[i])
		assert_eq(st.power_w[i], 250, "мощность от CPS")
		assert_eq(st.heart_rate_bpm[i], 140, "пульс от HRS")
		assert_false(st.erg_enabled[i])
		var expected: float = model.step(250.0, 75.0, 1.0)
		assert_almost_eq(st.speed_kmh[i], expected, 0.1, "скорость = модель D3D-02 при 250 Вт и 75 кг")
		if i >= 2:
			assert_eq(st.cadence_rpm[i], 90, "каденс по оборотам шатуна CPS")
	# С CSC 85 об/мин — каденс CSC (приоритет CSC > CPS).
	var csc := BleCadenceSensor.new(bridge)
	_disposables.append(csc)
	bridge.set_device_services("csc", {BleUuids.CSC_SERVICE: PackedStringArray([BleUuids.CSC_MEASUREMENT])})
	dev.hub.set_cadence_sensor(csc)
	csc.connect_device("csc")
	bridge.pump()
	var s2 := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(10, 200.0)] as Array[WorkoutStep]), dev, FTP)
	s2.start()
	var phase := 0.0
	for i in 10:
		phase += 85.0 / 60.0
		var revs := floori(phase)
		var event_ticks: int = roundi((float(i) + 1.0 - (phase - float(revs)) / (85.0 / 60.0)) * 1024.0) & 0xFFFF
		bridge.emit_notification("csc", BleUuids.CSC_MEASUREMENT, CscCodec.encode_crank_measurement(revs, event_ticks))
		s2.tick(1.0)
	assert_eq(s2.samples.cadence_rpm[s2.samples.size() - 1], 85, "с CSC 85 об/мин — каденс 85")


func test_req_wrk_09_c6b_c6c_dev_08_dropout_is_no_data_plan_continues_reconnect_resubscribes() -> void:
	var bridge := StubBleBridge.new()
	_disposables.append(bridge)
	var dev := _pm_device(bridge, 180, 90)
	var pm := _pm_of(dev)
	var s := WorkoutSession.new(Workout.make("300", [WorkoutStep.watts(150, 150.0), WorkoutStep.watts(150, 200.0)] as Array[WorkoutStep]),
		dev, FTP)
	s.start()
	for i in 100:
		s.tick(1.0)
	bridge.clear_calls()
	pm.inject_dropout(30.0)
	while s.get_state() != WorkoutSession.State.FINISHED:
		s.tick(1.0)
	var st := s.samples
	assert_almost_eq(st.size(), 300, 1, "300 ± 1 сэмплов: запись не прерывается")
	for i in st.size():
		var t: int = st.time_sec[i]
		if t >= 101 and t <= 129:
			assert_false(st.has_power[i], "t=%d: мощность «нет данных», а не 0" % t)
		elif t <= 98 or t >= 132:
			assert_true(st.has_power[i], "t=%d: мощность симулятора" % t)
	assert_eq(st.target_w[st.size() - 1], 200, "план шёл по таймеру и сменил шаг")
	var types: Array[String] = []
	for e in s.events:
		types.append(str(e["type"]))
	assert_true(types.has(WorkoutSession.EVENT_DISCONNECT), "обрыв в журнале заезда")
	assert_true(types.has(WorkoutSession.EVENT_RECONNECT), "восстановление в журнале заезда")
	var attempts := bridge.calls_of("connect_peripheral").size()
	assert_between(attempts, 6, 8, "попытки connect_peripheral каждые 5 с за 30 с обрыва")
	assert_eq(bridge.calls_of("discover_services").size(), 1, "после connected — discover_services")
	assert_eq(bridge.calls_of("subscribe").size(), 1, "и повторная подписка на 2A63")
	assert_eq(bridge.calls_of("subscribe")[0]["char"], BleUuids.CYCLING_POWER_MEASUREMENT)
	assert_eq(bridge.calls_of("write"), [] as Array[Dictionary], "ни одного write")
	# DEV-08 п.4: сэмплы до обрыва — в сохранённом заезде.
	_dir = "user://test_pm_session_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	var repo := FileRideRepository.new(_dir)
	var profile := Profile.create("Rider")
	var ride := Ride.from_session(s, profile)
	ride.compute_summary()
	repo.save(ride)
	var loaded := repo.get_ride(ride.id)
	assert_eq(loaded.samples.size(), st.size(), "все сэмплы сохранены")
	for i in 100:
		assert_eq(loaded.samples.power_w[i], st.power_w[i])
		assert_eq(loaded.samples.has_power[i], st.has_power[i])


func test_req_wrk_09_c6_no_power_source_means_no_data_and_avatar_stops() -> void:
	var bridge := StubBleBridge.new()
	_disposables.append(bridge)
	var dev := _pm_device(bridge, 250, 90)
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(60, 200.0)] as Array[WorkoutStep]), dev, FTP)
	s.start()
	for i in 20:
		s.tick(1.0)
	var riding: float = s.samples.speed_kmh[s.samples.size() - 1]
	assert_gt(riding, 10.0, "едет")
	_pm_of(dev).inject_dropout(30.0)
	s.tick(1.0)
	s.tick(1.0)
	var last := s.samples.size() - 1
	assert_false(s.samples.has_power[last], "источников нет — «нет данных»")
	# Тяги нет — остановка плавная по модели, не мгновенный ноль (D3D-02 п.7, У-33).
	assert_gt(s.samples.speed_kmh[last], 0.0, "не мгновенный ноль")
	assert_lt(s.samples.speed_kmh[last], riding, "скорость убывает")
	for i in 28:
		s.tick(1.0)
	last = s.samples.size() - 1
	assert_false(s.samples.has_power[last])
	assert_eq(s.samples.speed_kmh[last], 0.0, "аватар остановился не позже 30 с")
	assert_eq(s.get_state(), WorkoutSession.State.RUNNING, "таймер плана идёт")


# ---------------------------------------------------------------------------
# WRK-09 п.7 — свободная езда: модель с уклоном, эквивалентность smart
# ---------------------------------------------------------------------------

func test_req_wrk_09_c7_free_ride_equivalent_to_smart_on_mountains() -> void:
	var trainer := _fake_trainer(200, 90)
	var smart := FreeRideSession.new(trainer, RouteCatalog.MOUNTAINS, 50, 75.0, FTP)
	_disposables.append(smart)
	var bridge := StubBleBridge.new()
	_disposables.append(bridge)
	var pmode := FreeRideSession.new(_pm_device(bridge, 200, 90), RouteCatalog.MOUNTAINS, 50, 75.0, FTP)
	_disposables.push_front(pmode)
	smart.start()
	pmode.start()
	for i in 600:
		smart.tick(1.0)
		pmode.tick(1.0)
	assert_gt(trainer.commands.size(), 0, "в smart SIM уходит на станок")
	assert_eq(smart.samples.size(), 600)
	assert_eq(pmode.samples.size(), 600)
	var max_d := 0.0
	var max_h := 0.0
	var max_g := 0.0
	for i in 600:
		max_d = maxf(max_d, absf(smart.samples.distance_m[i] - pmode.samples.distance_m[i]))
		max_h = maxf(max_h, absf(smart.samples.altitude_m[i] - pmode.samples.altitude_m[i]))
		max_g = maxf(max_g, absf(smart.samples.grade_pct[i] - pmode.samples.grade_pct[i]))
	assert_lt(max_d, 0.01, "дистанция совпадает (±0.01 м)")
	assert_lt(max_h, 0.01, "высота совпадает (±0.01 м)")
	assert_lt(max_g, 0.01, "уклон совпадает (±0.01 %)")
	assert_almost_eq(pmode.ascent_m(), smart.ascent_m(), 0.01, "набор высоты совпадает")
	# На участке ~5 % скорость сходится к 15.2 ± 1.5 км/ч (FRD-04 п.7).
	var checked := 0
	for i in range(10, 600):
		var steady := true
		for k in range(i - 10, i + 1):
			if absf(pmode.samples.grade_pct[k] - 5.0) > 0.5:
				steady = false
				break
		if steady:
			checked += 1
			assert_almost_eq(pmode.samples.speed_kmh[i], 15.2, 1.5, "t=%d: скорость на 5 %%" % i)
	if checked == 0:
		assert_almost_eq(SpeedModel.steady_speed_kmh(200.0, 75.0, 5.0), 15.2, 1.5, "модель на 5 %")
	assert_eq(pmode.metadata()["speed_source"], SampleStream.SPEED_SOURCE_MODEL)
	assert_eq(pmode.metadata()[WorkoutSession.META_TRAINER_MODE], TrainerDevice.MODE_POWER_METER)


# ---------------------------------------------------------------------------
# WRK-09 п.8, LOC-01 п.1 — trainer_mode в метаданных, сводке, FIT
# ---------------------------------------------------------------------------

func test_req_wrk_09_c8_loc_01_c1_trainer_mode_saved_summary_and_fit() -> void:
	var bridge := StubBleBridge.new()
	_disposables.append(bridge)
	var dev := _pm_device(bridge, 210, 88)
	_hrs(bridge, dev.hub)
	var s := WorkoutSession.new(_plan_wrk_09(), dev, FTP)
	s.start()
	var guard := 0
	while s.get_state() != WorkoutSession.State.FINISHED and guard < 400:
		guard += 1
		bridge.emit_notification("hrs", BleUuids.HEART_RATE_MEASUREMENT, HrsCodec.encode_heart_rate_measurement(135))
		if s.executor.elapsed_sec() == 50:
			_pm_of(dev).inject_silence(8.0)
		s.tick(1.0)
	_dir = "user://test_pm_session_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	var repo := FileRideRepository.new(_dir)
	var profile := Profile.create("Rider")
	var ride := Ride.from_session(s, profile)
	ride.started_at_unix = STARTED
	ride.compute_summary()
	repo.save(ride)
	var loaded := repo.get_ride(ride.id)
	assert_eq(loaded.trainer_mode(), Ride.TRAINER_MODE_POWER_METER, "trainer_mode = power_meter")
	assert_true(loaded.is_power_meter_mode())
	assert_eq(loaded.trainer_source(), Ride.TRAINER_SOURCE_EMULATOR, "источник мощности — симулятор CPS")
	assert_eq(loaded.summary.trainer_mode, Ride.TRAINER_MODE_POWER_METER, "режим — в сводке")
	var listed := repo.list(profile.id)
	assert_eq(listed.size(), 1)
	assert_true(listed[0].is_power_meter_mode(), "режим — в сводке списка")
	var fit := FitDecoder.decode(FitEncoder.encode(loaded))
	assert_true(fit.ok, fit.error)
	var records: Array[Dictionary] = []
	var laps := 0
	for m in fit.messages:
		if m["global"] == FitDefinitions.MSG_RECORD:
			records.append(m)
		elif m["global"] == FitDefinitions.MSG_LAP:
			laps += 1
	assert_eq(records.size(), loaded.samples.size(), "record на каждый сэмпл")
	var no_data_seen := false
	for i in records.size():
		var f: Dictionary = records[i]["fields"]
		if loaded.samples.has_power[i]:
			assert_eq(f.get(FitDefinitions.RECORD_POWER), loaded.samples.power_w[i], "мощность в FIT")
		else:
			no_data_seen = true
			assert_null(f.get(FitDefinitions.RECORD_POWER), "«нет данных» — invalid")
		if loaded.samples.has_heart_rate[i]:
			assert_eq(f.get(FitDefinitions.RECORD_HEART_RATE), 135, "пульс в FIT")
		if loaded.samples.has_cadence[i]:
			assert_eq(f.get(FitDefinitions.RECORD_CADENCE), loaded.samples.cadence_rpm[i], "каденс в FIT")
	assert_true(no_data_seen, "в заезде есть секунды без мощности")
	assert_eq(laps, 4, "lap — по шагу плана")


func test_req_wrk_09_c8_legacy_ride_without_field_reads_as_smart() -> void:
	var r := Ride.new()
	r.metadata = {"ftp_w": 200}
	assert_eq(r.trainer_mode(), Ride.TRAINER_MODE_SMART, "заезд без поля — smart")
	r.metadata[Ride.KEY_TRAINER_MODE] = "bananas"
	assert_eq(r.trainer_mode(), Ride.TRAINER_MODE_SMART)
	var summary := RideSummary.from_dict({"ride_id": "x"})
	assert_eq(summary.trainer_mode, Ride.TRAINER_MODE_SMART, "сводка без поля — smart")
	var pm_summary := RideSummary.from_dict({"ride_id": "x", "trainer_mode": "power_meter"})
	assert_true(pm_summary.is_power_meter_mode())
	assert_eq(RideSummary.from_dict(pm_summary.to_dict()).trainer_mode, Ride.TRAINER_MODE_POWER_METER, "round-trip")
