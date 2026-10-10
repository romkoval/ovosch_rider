extends GutTest
## Приёмка T-152 (tester): тренировка без управляемого станка — сессия и устройства.
## Источник истины — `docs/requirements.md`: REQ-WRK-09 п.1, 3, 4, 6 (а)–(в), 7, 8, 11, 12;
## REQ-DEV-05 п.2 (в режиме `power_meter`), п.5; REQ-DEV-08 (примечание); REQ-DEV-10 п.4;
## REQ-DEV-11 п.2 (общее правило сессии); REQ-WRK-01 п.6; REQ-LOC-01 п.1.
## Независимо от тестов разработчика: фикстуры `StubBleBridge`, симулятор CPS `FakePowerMeter`,
## эмулятор `TrainerFactory.create_power_meter_emulator()`, `FakeTrainer` для режима `smart`.

const FTP: int = 200
const CONNECTED: int = TrainerDevice.ConnectionState.CONNECTED

var _dir: String = ""
var _disposables: Array = []
var _cm: ConnectionManager = null


func before_each() -> void:
	_dir = "user://acc_t152_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_disposables = []
	_cm = null


func after_each() -> void:
	if _cm != null:
		_cm.dispose()
		_cm = null
	for d: Variant in _disposables:
		if d != null and (d as Object).has_method("dispose"):
			(d as Object).call("dispose")
	_disposables = []
	_remove_tree(ProjectSettings.globalize_path(_dir))


static func _remove_tree(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var d := DirAccess.open(abs_path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)


# ---------------------------------------------------------------------------
# Фикстуры
# ---------------------------------------------------------------------------

func _bridge() -> StubBleBridge:
	var b := StubBleBridge.new()
	_disposables.append(b)
	return b


func _manager(bridge: StubBleBridge, kind: String = TrainerFactory.KIND_BLE) -> ConnectionManager:
	_cm = ConnectionManager.new(bridge, RememberedDevices.new(_dir + "devices/"), kind)
	_cm.set_profile("p")
	return _cm


func _ftms_fixture(bridge: StubBleBridge, id: String, with_cp: bool) -> void:
	var chars := PackedStringArray([BleUuids.INDOOR_BIKE_DATA, BleUuids.FTMS_STATUS])
	if with_cp:
		chars.append(BleUuids.FTMS_CONTROL_POINT)
	bridge.set_device_services(id, {BleUuids.FTMS_SERVICE: chars})


func _cps_fixture(bridge: StubBleBridge, id: String) -> void:
	bridge.set_device_services(id, {BleUuids.CPS_SERVICE: PackedStringArray([BleUuids.CYCLING_POWER_MEASUREMENT])})


func _cps_packet(bridge: StubBleBridge, id: String, watts: int) -> void:
	bridge.emit_notification(id, BleUuids.CYCLING_POWER_MEASUREMENT, CpsCodec.encode_cycling_power_measurement(watts))


func _ibd_packet(bridge: StubBleBridge, id: String, watts: int, speed_kmh: float = 50.0, cadence: float = 80.0) -> void:
	bridge.emit_notification(id, BleUuids.INDOOR_BIKE_DATA, FtmsCodec.encode_indoor_bike_data(speed_kmh, cadence, watts))


func _fake_trainer(power: int = 200, cadence: int = 90, controllable: bool = true) -> FakeTrainer:
	var t := FakeTrainer.new(7)
	t.connect_delay_sec = 0.0
	t.power_noise_w = 0.0
	t.cadence_noise_rpm = 0.0
	t.power_tau_sec = 0.001
	t.emit_speed = false
	t.controllable = controllable
	t.set_rider_power(power)
	t.set_rider_cadence(cadence)
	t.connect_device("fake")
	_disposables.append(t)
	return t


## `power_meter`-устройство: хаб (станок `hub_trainer` или без станка) + симулятор CPS на `bridge`.
func _pm_device(bridge: StubBleBridge, watts: int, cadence: int, hub_trainer: TrainerDevice = null,
		source: String = SensorHub.SOURCE_POWER_METER) -> UncontrolledTrainer:
	var pm := FakePowerMeter.new(bridge)
	pm.set_power(watts)
	pm.set_cadence(cadence)
	var hub := SensorHub.new(hub_trainer)
	hub.set_power_meter(pm)
	pm.connect_device("cps")
	var dev := UncontrolledTrainer.new(hub, source)
	_disposables.push_front(dev)
	_disposables.append(pm)
	return dev


func _pm_of(dev: UncontrolledTrainer) -> FakePowerMeter:
	return dev.hub.power_meter as FakePowerMeter


func _emulator() -> UncontrolledTrainer:
	var dev := TrainerFactory.create_power_meter_emulator() as UncontrolledTrainer
	_disposables.push_front(dev)
	return dev


static func _plan_p3() -> Workout:
	return Workout.make("WRK-09 п.3", [
		WorkoutStep.watts(60, 150.0),
		WorkoutStep.percent(60, 65.0),
		WorkoutStep.ramp_watts(60, 100.0, 200.0),
		WorkoutStep.free_ride(60),
	] as Array[WorkoutStep])


## Действия п.3: пауза 20 с на 70-й секунде, множитель 110 % со 100-й, пропуск шага 3 на его
## 30-й секунде (шаг 3 начинается на 120-й → 150-я). `try` — попытки ERG/сопротивления (п.4).
func _drive_p3(s: WorkoutSession, try: bool) -> void:
	s.start()
	var paused := false
	var guard := 0
	while s.get_state() != WorkoutSession.State.FINISHED and guard < 1000:
		guard += 1
		var t := s.executor.elapsed_sec()
		if t == 70 and not paused:
			paused = true
			s.pause()
			if try:
				s.toggle_erg()
				s.set_resistance_level(90)
			for i in 20:
				s.tick(1.0)
			s.resume()
		if t == 100 and is_equal_approx(s.intensity(), 1.0):
			s.set_intensity(1.1)
		if try and (t == 30 or t == 130 or t == 200):
			s.toggle_erg()
			s.set_erg_enabled(true)
			s.set_resistance_level(10 + t % 50)
		if t == 150 and s.executor.current_step_index() == 2:
			s.skip_step()
		s.tick(1.0)


static func _events(s: Object) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in s.get("events"):
		out.append("%s@%.3f=%s" % [e["type"], float(e["at_sec"]), str(e["value"])])
	return out


static func _event_types(s: Object) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in s.get("events"):
		out.append(str(e["type"]))
	return out


## Записи и подписки на управление в журнале моста (WRK-09 п.4, DEV-10 п.4, DEV-05 п.5).
static func _control_calls(bridge: StubBleBridge) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in bridge.calls:
		if c["method"] == "write":
			out.append(c)
		elif c["method"] == "subscribe" and (c["char"] == BleUuids.FTMS_CONTROL_POINT or c["char"] == "2A66"):
			out.append(c)
	return out


# ---------------------------------------------------------------------------
# REQ-WRK-09 п.1 — режим по устройствам «подключено»; неизменность режима в сессии
# ---------------------------------------------------------------------------

func test_req_wrk_09_c1_mode_by_fixtures_cps_ftms_without_cp_controllable_and_none() -> void:
	# Только CPS → power_meter, источник — измеритель.
	var b1 := _bridge()
	var cm1 := _manager(b1)
	_cps_fixture(b1, "quarq")
	cm1.connect_sensor("quarq", RememberedDevices.KIND_POWER)
	b1.pump()
	var c1 := cm1.start_check()
	assert_true(c1["allowed"], "только CPS — старт разрешён")
	assert_eq(c1["mode"], TrainerDevice.MODE_POWER_METER, "только CPS → power_meter")
	assert_eq(c1["power_source"], SensorHub.SOURCE_POWER_METER)
	cm1.dispose()
	_cm = null
	# FTMS без 2AD9 → power_meter, источник — станок.
	var b2 := _bridge()
	var cm2 := _manager(b2)
	_ftms_fixture(b2, "kickr", false)
	cm2.connect_trainer("kickr")
	b2.pump()
	var c2 := cm2.start_check()
	assert_eq(c2["mode"], TrainerDevice.MODE_POWER_METER, "FTMS без 2AD9 → power_meter")
	assert_eq(c2["power_source"], SensorHub.SOURCE_TRAINER, "источник — станок без канала управления")
	# FTMS без 2AD9 и CPS → power_meter по измерителю (если оба — измеритель).
	_cps_fixture(b2, "quarq")
	cm2.connect_sensor("quarq", RememberedDevices.KIND_POWER)
	b2.pump()
	var c2b := cm2.start_check()
	assert_eq(c2b["mode"], TrainerDevice.MODE_POWER_METER)
	assert_eq(c2b["power_source"], SensorHub.SOURCE_POWER_METER, "оба источника → измеритель мощности")
	cm2.dispose()
	_cm = null
	# FTMS с 2AD9 и CPS → smart.
	var b3 := _bridge()
	var cm3 := _manager(b3)
	_ftms_fixture(b3, "neo", true)
	cm3.connect_trainer("neo")
	_cps_fixture(b3, "quarq")
	cm3.connect_sensor("quarq", RememberedDevices.KIND_POWER)
	b3.pump()
	var c3 := cm3.start_check()
	assert_eq(c3["mode"], TrainerDevice.MODE_SMART, "FTMS с 2AD9 и CPS → smart")
	assert_true(cm3.session_device() == cm3.hub, "в smart устройство сессии — хаб, как прежде")
	cm3.dispose()
	_cm = null
	# Только HRS и CSC → сессии нет; ничего → сессии нет.
	var b4 := _bridge()
	var cm4 := _manager(b4)
	assert_false(cm4.start_check()["allowed"], "ничего → сессии нет")
	assert_null(cm4.session_device(), "ничего → устройства сессии нет")
	b4.set_device_services("hrs", {BleUuids.HRS_SERVICE: PackedStringArray([BleUuids.HEART_RATE_MEASUREMENT])})
	b4.set_device_services("csc", {BleUuids.CSC_SERVICE: PackedStringArray([BleUuids.CSC_MEASUREMENT])})
	cm4.connect_sensor("hrs", RememberedDevices.KIND_HR)
	cm4.connect_sensor("csc", RememberedDevices.KIND_CADENCE)
	b4.pump()
	assert_false(cm4.start_check()["allowed"], "только HRS и CSC → сессии нет")
	assert_null(cm4.session_device())


func test_req_wrk_09_c1_dev_11_c2_fake_trainer_without_control_channel_is_power_meter_no_commands() -> void:
	# Общее правило «станок без канала управления» на фейке (FE-C без FEC3 — T-167).
	var b := _bridge()
	var cm := _manager(b, TrainerFactory.KIND_FAKE)
	var fake := cm.trainer as FakeTrainer
	assert_not_null(fake, "предусловие: станок менеджера — FakeTrainer")
	fake.controllable = false
	fake.connect_delay_sec = 0.0
	fake.power_noise_w = 0.0
	fake.power_tau_sec = 0.001
	fake.set_rider_power(170)
	cm.connect_trainer("fake")
	for i in 3:
		fake.tick(0.5)
	assert_eq(fake.get_connection_state(), CONNECTED)
	var check := cm.start_check()
	assert_eq(check["mode"], TrainerDevice.MODE_POWER_METER, "станок без канала управления → power_meter")
	assert_eq(check["power_source"], SensorHub.SOURCE_TRAINER, "источник мощности — станок")
	var dev := cm.session_device()
	var s := WorkoutSession.new(Workout.make("fec", [WorkoutStep.watts(20, 250.0), WorkoutStep.watts(20, 150.0)] as Array[WorkoutStep]), dev, FTP)
	assert_eq(s.trainer_mode, TrainerDevice.MODE_POWER_METER)
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		if s.executor.elapsed_sec() == 10:
			s.toggle_erg()
			s.set_resistance_level(60)
		s.tick(1.0)
	assert_eq(fake.commands.size(), 0, "ни одной команды на станок без канала управления")
	assert_eq(s.samples.power_w[s.samples.size() - 1], 170, "мощность — от станка")
	cm.release_session_device()


func test_req_wrk_09_c1_c4_controllable_trainer_joining_mid_session_stays_data_only() -> void:
	var b := _bridge()
	var cm := _manager(b)
	_cps_fixture(b, "quarq")
	cm.connect_sensor("quarq", RememberedDevices.KIND_POWER)
	b.pump()
	var dev := cm.session_device()
	assert_eq(dev.trainer_mode(), TrainerDevice.MODE_POWER_METER, "предусловие: power_meter")
	var s := WorkoutSession.new(_plan_p3(), dev, FTP)
	b.clear_calls()
	s.start()
	var guard := 0
	while s.get_state() != WorkoutSession.State.FINISHED and guard < 400:
		guard += 1
		var t := s.executor.elapsed_sec()
		if t == 30:
			_ftms_fixture(b, "neo", true)
			cm.connect_trainer("neo")
			b.pump()
		if t > 30:
			_ibd_packet(b, "neo", 150)
		if t == 40 or t == 130:
			s.toggle_erg()
			s.set_erg_enabled(true)
			s.set_resistance_level(70)
		if t == 100:
			s.set_intensity(1.05)
		if t == 150:
			s.skip_step()
		_cps_packet(b, "quarq", 220)
		s.tick(1.0)
		b.pump()
	assert_eq(s.get_state(), WorkoutSession.State.FINISHED)
	assert_eq(cm.trainer.get_connection_state(), CONNECTED, "станок подключился посреди сессии")
	assert_false(cm.trainer.has_control(), "…как источник данных, без управления")
	assert_eq(_control_calls(b), [] as Array[Dictionary], "до конца сессии ни одного write и subscribe 2AD9")
	assert_eq(s.trainer_mode, TrainerDevice.MODE_POWER_METER, "режим не изменился")
	assert_eq(s.samples.power_w[s.samples.size() - 1], 220, "мощность — от измерителя (приоритет DEV-05 п.2)")
	for i in s.samples.size():
		assert_false(s.samples.erg_enabled[i], "ERG «выкл» во всех сэмплах")
	cm.release_session_device()


func test_req_wrk_09_c1_c4_trainer_connecting_at_start_gets_no_write_during_session() -> void:
	# Станок в «подключение» (Request Control в полёте) — неподключённый (п.2 (д)); сессия
	# power_meter. Отказ записи Request Control, доставленный уже в сессии, не должен давать
	# повторной записи: «до конца сессии ни одного write» (п.1, п.4).
	var b := _bridge()
	var cm := _manager(b)
	_cps_fixture(b, "quarq")
	cm.connect_sensor("quarq", RememberedDevices.KIND_POWER)
	b.pump()
	_ftms_fixture(b, "neo", true)
	b.auto_control_point_response = false
	b.fail_next_write()
	cm.connect_trainer("neo")
	var guard := 0
	while b.calls_of("write").is_empty() and not b.pending.is_empty() and guard < 50:
		guard += 1
		var cb: Callable = b.pending.pop_front()
		cb.call()
	assert_eq(b.calls_of("write").size(), 1, "предусловие: Request Control записан до сессии")
	assert_eq(cm.trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTING, "предусловие: станок подключается")
	var check := cm.start_check()
	assert_eq(check["mode"], TrainerDevice.MODE_POWER_METER, "подключающийся станок — неподключённый")
	var dev := cm.session_device()
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(30, 200.0)] as Array[WorkoutStep]), dev, FTP)
	s.start()
	b.clear_calls()
	b.pump()  # приходит write_done(ok = false) записи, сделанной до сессии
	while s.get_state() != WorkoutSession.State.FINISHED:
		_cps_packet(b, "quarq", 200)
		s.tick(1.0)
		b.pump()
	assert_eq(b.calls_of("write"), [] as Array[Dictionary], "за сессию power_meter ни одного write")
	cm.release_session_device()


func test_req_wrk_09_c1_dev_05_c2a_cps_joining_mid_session_overrides_data_only_trainer() -> void:
	# Сессия power_meter стартовала со станком без 2AD9 (источник — станок); посреди сессии
	# подключился измеритель. Источник мощности в любом режиме — приоритет DEV-05 п.2:
	# подключены оба → мощность от измерителя.
	var b := _bridge()
	var cm := _manager(b)
	_ftms_fixture(b, "kickr", false)
	cm.connect_trainer("kickr")
	b.pump()
	var dev := cm.session_device()
	assert_eq(dev.trainer_mode(), TrainerDevice.MODE_POWER_METER)
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(60, 200.0)] as Array[WorkoutStep]), dev, FTP)
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		var t := s.executor.elapsed_sec()
		if t == 20:
			_cps_fixture(b, "quarq")
			cm.connect_sensor("quarq", RememberedDevices.KIND_POWER)
			b.pump()
		if t >= 20:
			_cps_packet(b, "quarq", 250)
		_ibd_packet(b, "kickr", 180)
		s.tick(1.0)
	assert_eq(s.samples.power_w[10], 180, "до измерителя — мощность станка")
	assert_eq(s.samples.power_w[30], 250, "подключены оба → мощность измерителя (DEV-05 п.2 (а))")
	assert_eq(s.samples.power_w[59], 250)
	cm.release_session_device()


# ---------------------------------------------------------------------------
# Повтор приёмки после aaf9845 (Д-1, Д-2): граничные случаи исправления
# ---------------------------------------------------------------------------

func test_req_wrk_09_c1_c4_retest_d1_after_session_trainer_takes_control_next_start_smart() -> void:
	# Д-1: отказ Request Control, доставленный в сессии power_meter, не повторяется. После сессии
	# управляемый станок (2AD9 есть) не должен остаться «только данные»: следующий старт — smart
	# (п.1: «управляемый станок подключён → smart»).
	var b := _bridge()
	var cm := _manager(b)
	_cps_fixture(b, "quarq")
	cm.connect_sensor("quarq", RememberedDevices.KIND_POWER)
	b.pump()
	_ftms_fixture(b, "neo", true)
	b.auto_control_point_response = false
	b.fail_next_write()
	cm.connect_trainer("neo")
	var guard := 0
	while b.calls_of("write").is_empty() and not b.pending.is_empty() and guard < 50:
		guard += 1
		var cb: Callable = b.pending.pop_front()
		cb.call()
	assert_eq(cm.trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTING, "предусловие: станок подключается")
	var dev := cm.session_device()
	assert_eq(dev.trainer_mode(), TrainerDevice.MODE_POWER_METER)
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(20, 200.0)] as Array[WorkoutStep]), dev, FTP)
	s.start()
	b.clear_calls()
	b.pump()
	while s.get_state() != WorkoutSession.State.FINISHED:
		_cps_packet(b, "quarq", 200)
		_ibd_packet(b, "neo", 170)
		s.toggle_erg()
		s.set_resistance_level(40)
		s.tick(1.0)
		cm.tick(1.0)
		b.pump()
	assert_eq(b.calls_of("write"), [] as Array[Dictionary], "за сессию ни одного write")
	assert_eq(s.samples.power_w[s.samples.size() - 1], 200, "мощность — от измерителя")
	b.auto_control_point_response = true
	cm.release_session_device()
	b.pump()
	for i in 3:
		cm.tick(1.0)
		b.pump()
	assert_eq(cm.trainer.get_connection_state(), CONNECTED, "станок подключён")
	assert_true(cm.trainer.has_control(), "после сессии станок с 2AD9 снова управляемый")
	assert_eq(cm.start_check()["mode"], TrainerDevice.MODE_SMART, "следующий старт — smart")


func test_req_wrk_09_c1_dev_05_c2_retest_d2_cps_joins_drops_returns_trainer_fallback() -> void:
	# Д-2: сессия по станку без 2AD9; CPS подключился (→ CPS), оборвался (→ станок со следующего
	# сэмпла, без «нет данных»), вернулся (→ CPS). Режим и ни одного write.
	var b := _bridge()
	var cm := _manager(b)
	_ftms_fixture(b, "kickr", false)
	cm.connect_trainer("kickr")
	b.pump()
	var dev := cm.session_device()
	assert_eq(dev.trainer_mode(), TrainerDevice.MODE_POWER_METER)
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(90, 200.0)] as Array[WorkoutStep]), dev, FTP)
	s.start()
	b.clear_calls()
	while s.get_state() != WorkoutSession.State.FINISHED:
		var t := s.executor.elapsed_sec()
		if t == 20:
			_cps_fixture(b, "quarq")
			cm.connect_sensor("quarq", RememberedDevices.KIND_POWER)
			b.pump()
		if t == 40:
			b.auto_connect = false
			b.emit_disconnected("quarq", BleBridge.DisconnectReason.LINK_LOSS)
			b.pump()
		if t == 60:
			b.auto_connect = true
			b.emit_connected("quarq")
			b.pump()
		if (t >= 20 and t < 40) or t >= 60:
			_cps_packet(b, "quarq", 250)
		_ibd_packet(b, "kickr", 180)
		s.tick(1.0)
		cm.tick(1.0)
		b.pump()
	var st := s.samples
	assert_eq(st.size(), 90)
	for k in st.size():
		assert_true(st.has_power[k], "сэмпл %d: мощность есть" % (k + 1))
	assert_eq(st.power_w[10], 180, "до CPS — станок")
	assert_eq(st.power_w[30], 250, "CPS подключился → CPS")
	assert_eq(st.power_w[40], 180, "CPS оборвался на 40-й с → 41-й сэмпл уже от станка")
	assert_eq(st.power_w[55], 180)
	assert_eq(st.power_w[65], 250, "CPS вернулся → снова CPS")
	assert_eq(st.power_w[89], 250)
	assert_eq(s.trainer_mode, TrainerDevice.MODE_POWER_METER, "режим не изменился")
	assert_eq(dev.get_connection_state(), CONNECTED, "источник сессии (станок) подключён всё время")
	assert_eq(_control_calls(b), [] as Array[Dictionary], "ни одного write и subscribe 2AD9")
	cm.release_session_device()


# ---------------------------------------------------------------------------
# REQ-WRK-09 п.3, REQ-WRK-01 п.6 — план по таймеру, эквивалентность smart
# ---------------------------------------------------------------------------

func test_req_wrk_09_c3_wrk_01_c6_equivalence_smart_vs_emulator_power_meter() -> void:
	var smart := WorkoutSession.new(_plan_p3(), _fake_trainer(200, 90), FTP)
	var dev := _emulator()
	var pm := TrainerFactory.power_meter_emulator_sensor(dev)
	assert_not_null(pm, "у эмулятора есть симулятор CPS")
	pm.set_power(200)
	pm.set_cadence(90)
	var pmode := WorkoutSession.new(_plan_p3(), dev, FTP)
	assert_eq(smart.trainer_mode, TrainerDevice.MODE_SMART)
	assert_eq(pmode.trainer_mode, TrainerDevice.MODE_POWER_METER)
	var tr_smart: Array[String] = []
	var tr_pm: Array[String] = []
	smart.executor.step_changed.connect(func(i: int, st: WorkoutStep) -> void: tr_smart.append("%d/%d" % [i, st.duration_sec]))
	pmode.executor.step_changed.connect(func(i: int, st: WorkoutStep) -> void: tr_pm.append("%d/%d" % [i, st.duration_sec]))
	var fin_smart: Array[int] = []
	var fin_pm: Array[int] = []
	var ex_smart := smart.executor
	var ex_pm := pmode.executor
	var on_fin_smart := func() -> void: fin_smart.append(ex_smart.elapsed_sec())
	var on_fin_pm := func() -> void: fin_pm.append(ex_pm.elapsed_sec())
	ex_smart.finished.connect(on_fin_smart)
	ex_pm.finished.connect(on_fin_pm)
	_drive_p3(smart, false)
	_drive_p3(pmode, true)
	ex_smart.finished.disconnect(on_fin_smart)
	ex_pm.finished.disconnect(on_fin_pm)
	assert_eq(pmode.get_state(), WorkoutSession.State.FINISHED)
	assert_eq(tr_pm, tr_smart, "одинаковые переходы шагов (номер, длительность)")
	assert_eq(fin_pm.size(), 1, "завершение — один раз")
	assert_eq(fin_pm, fin_smart, "одинаковое время завершения")
	assert_eq(_events(pmode), _events(smart), "одинаковые события старта, паузы, множителя, пропуска, финиша")
	assert_eq(pmode.samples.size(), smart.samples.size())
	var diff_step := -1
	var diff_target := -1
	for i in smart.samples.size():
		if diff_step < 0 and smart.samples.step_index[i] != pmode.samples.step_index[i]:
			diff_step = i
		if diff_target < 0 and smart.samples.target_w[i] != pmode.samples.target_w[i]:
			diff_target = i
		assert_false(pmode.samples.erg_enabled[i], "флаг ERG «выкл» в каждом сэмпле power_meter")
	assert_eq(diff_step, -1, "номера шагов сэмплов совпадают")
	assert_eq(diff_target, -1, "цели сэмплов совпадают")
	assert_true(pmode.samples.target_w.has(130), "65 %% FTP при FTP 200 → 130 Вт")
	assert_true(pmode.samples.target_w.has(143), "130 × 1.1 → 143 Вт")
	for t in _event_types(pmode):
		assert_false(t in [WorkoutSession.EVENT_ERG_ON, WorkoutSession.EVENT_ERG_OFF, WorkoutSession.EVENT_RESISTANCE],
			"события переключения ERG / сопротивления в power_meter нет: %s" % t)


func test_req_wrk_09_c3_multiplier_150w_at_110_is_165_next_sample_and_ramp_per_second() -> void:
	var dev := _emulator()
	var s := WorkoutSession.new(Workout.make("m", [WorkoutStep.watts(30, 150.0), WorkoutStep.ramp_watts(10, 100.0, 200.0)] as Array[WorkoutStep]), dev, FTP)
	s.start()
	for i in 5:
		s.tick(1.0)
	assert_eq(s.samples.target_w[s.samples.size() - 1], 150)
	s.set_intensity(1.1)
	s.tick(1.0)
	assert_eq(s.samples.target_w[s.samples.size() - 1], 165, "150 Вт при 110 % → 165 не позже следующего сэмпла")
	s.set_intensity(1.0)
	while s.executor.current_step_index() == 0:
		s.tick(1.0)
	var ramp: Array[int] = []
	while s.get_state() != WorkoutSession.State.FINISHED:
		s.tick(1.0)
		ramp.append(s.samples.target_w[s.samples.size() - 1])
	var distinct := {}
	for w in ramp:
		distinct[w] = true
	assert_gt(distinct.size(), 5, "у рампы цель пересчитывается каждую секунду: %s" % str(ramp))


func test_req_wrk_09_c3_no_trainer_range_clamp_in_power_meter() -> void:
	# DEV-10 п.6 не применяется: станка нет, цель плана не ограничивается диапазоном станка.
	var dev := _emulator()
	var s := WorkoutSession.new(Workout.make("big", [WorkoutStep.watts(10, 2400.0)] as Array[WorkoutStep]), dev, FTP)
	s.start()
	for i in 3:
		s.tick(1.0)
	assert_eq(s.current_target_watts(), 2400, "цель 2400 Вт без ограничения")
	assert_eq(s.samples.target_w[s.samples.size() - 1], 2400, "в сэмпле — 2400")


func test_req_wrk_01_c6_plan_60_30_90_finishes_at_180_with_step_events_in_power_meter() -> void:
	var dev := _emulator()
	var s := WorkoutSession.new(Workout.make("w", [WorkoutStep.watts(60, 120.0), WorkoutStep.watts(30, 250.0),
		WorkoutStep.watts(90, 180.0)] as Array[WorkoutStep]), dev, FTP)
	var transitions: Array[String] = []
	var ex := s.executor
	var on_step := func(i: int, st: WorkoutStep) -> void:
		transitions.append("%d@%d:%d/%d" % [i, ex.elapsed_sec(), st.target_watts_at(0.0, FTP), st.duration_sec])
	ex.step_changed.connect(on_step)
	var finished := [0]
	var on_fin := func() -> void: finished[0] += 1
	ex.finished.connect(on_fin)
	s.start()
	var ticks := 0
	while s.get_state() != WorkoutSession.State.FINISHED and ticks < 400:
		s.tick(1.0)
		ticks += 1
	ex.step_changed.disconnect(on_step)
	ex.finished.disconnect(on_fin)
	assert_eq(ticks, 180, "план «60, 30, 90» завершается на тике 180")
	assert_eq(finished[0], 1, "событие завершения — один раз")
	assert_eq(transitions, ["0@0:120/60", "1@60:250/30", "2@90:180/90"] as Array[String],
		"событие перехода с номером, целью и длительностью — на тике, когда прошло время шага")


# ---------------------------------------------------------------------------
# REQ-WRK-09 п.4, REQ-DEV-05 п.5 — ни одной команды
# ---------------------------------------------------------------------------

func test_req_wrk_09_c4_dev_05_c5_full_scenario_on_shared_bridge_no_writes() -> void:
	var b := _bridge()
	var dev := _pm_device(b, 200, 90)
	var hrs := BleHeartRateSensor.new(b)
	_disposables.append(hrs)
	b.set_device_services("hrs", {BleUuids.HRS_SERVICE: PackedStringArray([BleUuids.HEART_RATE_MEASUREMENT])})
	dev.hub.set_heart_rate_sensor(hrs)
	hrs.connect_device("hrs")
	var csc := BleCadenceSensor.new(b)
	_disposables.append(csc)
	b.set_device_services("csc", {BleUuids.CSC_SERVICE: PackedStringArray([BleUuids.CSC_MEASUREMENT])})
	dev.hub.set_cadence_sensor(csc)
	csc.connect_device("csc")
	b.pump()
	# План со всеми действиями п.3 и попытками ERG / сопротивления.
	var s := WorkoutSession.new(_plan_p3(), dev, FTP)
	_drive_p3(s, true)
	assert_eq(s.get_state(), WorkoutSession.State.FINISHED)
	# Переподключение источника мощности (п.6 (в)).
	var s2 := WorkoutSession.new(Workout.make("r", [WorkoutStep.watts(60, 150.0)] as Array[WorkoutStep]), dev, FTP)
	s2.start()
	for i in 10:
		s2.tick(1.0)
	_pm_of(dev).inject_dropout(17.0)
	while s2.get_state() != WorkoutSession.State.FINISHED:
		s2.tick(1.0)
	assert_true(_event_types(s2).has(WorkoutSession.EVENT_RECONNECT), "предусловие: было переподключение")
	# Свободная езда 600 с на «горах» с попытками крутизны, SIM ↔ сопротивление и уровня.
	var fr := FreeRideSession.new(dev, RouteCatalog.MOUNTAINS, 50, 75.0, FTP)
	_disposables.push_front(fr)
	fr.start()
	for i in 600:
		if i % 120 == 60:
			fr.set_steepness(100 - i % 100)
			fr.toggle_mode()
			fr.set_mode(SimController.Mode.SIM)
			fr.set_resistance_level(75)
		fr.tick(1.0)
	fr.stop()
	assert_eq(b.calls_of("write"), [] as Array[Dictionary], "ни одного write ни к одному устройству")
	var allowed := [BleUuids.CYCLING_POWER_MEASUREMENT, BleUuids.HEART_RATE_MEASUREMENT, BleUuids.CSC_MEASUREMENT,
		BleUuids.BATTERY_LEVEL]
	var subs := 0
	for c in b.calls_of("subscribe"):
		subs += 1
		assert_true(allowed.has(c["char"]), "subscribe только на характеристики данных, не %s" % c["char"])
	assert_gt(subs, 0, "подписки на данные были")
	assert_eq(_control_calls(b), [] as Array[Dictionary], "ни одного subscribe на 2AD9 и 2A66")


func test_req_wrk_09_c4_emulator_scenario_no_writes_in_its_bridge() -> void:
	var dev := _emulator()
	var pm := TrainerFactory.power_meter_emulator_sensor(dev)
	var s := WorkoutSession.new(_plan_p3(), dev, FTP)
	_drive_p3(s, true)
	var fr := FreeRideSession.new(dev, RouteCatalog.MOUNTAINS, 100, 75.0, FTP)
	_disposables.push_front(fr)
	fr.start()
	for i in 120:
		fr.set_steepness(i % 100)
		fr.tick(1.0)
	fr.stop()
	assert_eq(pm.stub.calls_of("write"), [] as Array[Dictionary], "в журнале моста симулятора ни одного write")
	for c in pm.stub.calls_of("subscribe"):
		assert_eq(c["char"], BleUuids.CYCLING_POWER_MEASUREMENT, "подписка только на 2A63")


# ---------------------------------------------------------------------------
# REQ-DEV-10 п.4 — станок без Control Point
# ---------------------------------------------------------------------------

func test_req_dev_10_c4_ftms_without_cp_data_only_parsed_and_commands_are_noop() -> void:
	var b := _bridge()
	var t := TrainerFactory.create_ble(b) as BleTrainer
	_disposables.push_front(t)
	_ftms_fixture(b, "suito", false)
	t.connect_device("suito")
	b.pump()
	assert_eq(t.get_connection_state(), CONNECTED, "состояние «подключено» как источник данных")
	assert_false(t.has_control(), "возможность «нет управления» видна через TrainerDevice")
	assert_true(b.is_subscribed("suito", BleUuids.FTMS_SERVICE, BleUuids.INDOOR_BIKE_DATA), "подписка 2AD2")
	assert_true(b.is_subscribed("suito", BleUuids.FTMS_SERVICE, BleUuids.FTMS_STATUS), "подписка 2ADA (есть у фикстуры)")
	var got: Array[TrainerSample] = []
	t.telemetry.connect(func(x: TrainerSample) -> void: got.append(x))
	_ibd_packet(b, "suito", 234, 31.5, 88.0)
	t.tick(1.0)
	assert_gt(got.size(), 0, "телеметрия идёт")
	var last: TrainerSample = got[got.size() - 1]
	assert_eq(last.power_w, 234, "мощность разобрана")
	assert_eq(last.cadence_rpm, 88, "каденс разобран")
	assert_almost_eq(last.speed_kmh, 31.5, 0.01, "скорость разобрана (DEV-02.2)")
	t.set_erg_enabled(true)
	t.set_target_power(200)
	t.set_erg_enabled(false)
	t.set_resistance_level(40)
	t.set_simulation(4.0)
	t.set_control_allowed(true)
	for i in 5:
		t.tick(1.0)
	b.pump()
	assert_eq(_control_calls(b), [] as Array[Dictionary], "за всё подключение ни одного write и subscribe на 2AD9")
	for c in b.calls_of("read_characteristic"):
		assert_ne(c.get("char", ""), BleUuids.FTMS_CONTROL_POINT)


# ---------------------------------------------------------------------------
# REQ-WRK-09 п.6 (а) — сэмплы
# ---------------------------------------------------------------------------

func _hrs_on(b: StubBleBridge, hub: SensorHub) -> void:
	var hrs := BleHeartRateSensor.new(b)
	_disposables.append(hrs)
	b.set_device_services("hrs", {BleUuids.HRS_SERVICE: PackedStringArray([BleUuids.HEART_RATE_MEASUREMENT])})
	hub.set_heart_rate_sensor(hrs)
	hrs.connect_device("hrs")
	b.pump()


func test_req_wrk_09_c6a_250w_90rpm_140bpm_model_speed_and_csc_85() -> void:
	var b := _bridge()
	var dev := _pm_device(b, 250, 90)
	_hrs_on(b, dev.hub)
	var s := WorkoutSession.new(Workout.make("a", [WorkoutStep.watts(40, 200.0)] as Array[WorkoutStep]), dev, FTP, 1.0, 75.0)
	s.start()
	var model := SpeedModel.new()
	while s.get_state() != WorkoutSession.State.FINISHED:
		b.emit_notification("hrs", BleUuids.HEART_RATE_MEASUREMENT, HrsCodec.encode_heart_rate_measurement(140))
		s.tick(1.0)
	var st := s.samples
	assert_eq(st.size(), 40)
	assert_eq(s.metadata().get("speed_source"), SampleStream.SPEED_SOURCE_MODEL, "speed_source = модель")
	for i in st.size():
		assert_eq(st.power_w[i], 250, "мощность — CPS")
		assert_eq(st.heart_rate_bpm[i], 140, "пульс — HRS")
		var expected := model.step(250.0, 75.0, 1.0, 0.0)
		assert_almost_eq(st.speed_kmh[i], expected, 0.1, "скорость = модель при 250 Вт, 75 кг (±0.1)")
	assert_eq(st.cadence_rpm[st.size() - 1], 90, "каденс — обороты шатуна CPS")
	assert_almost_eq(st.speed_kmh[st.size() - 1], SpeedModel.steady_speed_kmh(250.0, 75.0, 0.0), 0.5, "сходится к установившейся")
	# С CSC 85 об/мин — каденс CSC.
	var csc := BleCadenceSensor.new(b)
	_disposables.append(csc)
	b.set_device_services("csc", {BleUuids.CSC_SERVICE: PackedStringArray([BleUuids.CSC_MEASUREMENT])})
	dev.hub.set_cadence_sensor(csc)
	csc.connect_device("csc")
	b.pump()
	var s2 := WorkoutSession.new(Workout.make("a", [WorkoutStep.watts(12, 200.0)] as Array[WorkoutStep]), dev, FTP)
	s2.start()
	var revs := 0
	var phase := 0.0
	for i in 12:
		phase += 85.0 / 60.0
		var whole := floori(phase)
		if whole > revs:
			revs = whole
		var ev: int = roundi((float(i + 1) - (phase - float(revs)) / (85.0 / 60.0)) * 1024.0) & 0xFFFF
		b.emit_notification("csc", BleUuids.CSC_MEASUREMENT, CscCodec.encode_crank_measurement(revs, ev))
		s2.tick(1.0)
	assert_eq(s2.samples.cadence_rpm[s2.samples.size() - 1], 85, "с CSC 85 об/мин — каденс 85 (CSC > CPS)")


func test_req_wrk_09_c6a_data_only_trainer_speed_field_ignored_model_used() -> void:
	# Станок без управления с полем скорости 50 км/ч — скорость сэмпла по модели (У-30).
	var b := _bridge()
	var t := TrainerFactory.create_ble(b)
	_disposables.append(t)
	_ftms_fixture(b, "kickr", false)
	t.connect_device("kickr")
	b.pump()
	var hub := SensorHub.new(t)
	var dev := UncontrolledTrainer.new(hub, SensorHub.SOURCE_TRAINER)
	_disposables.push_front(dev)
	var s := WorkoutSession.new(Workout.make("a", [WorkoutStep.watts(30, 200.0)] as Array[WorkoutStep]), dev, FTP, 1.0, 75.0)
	assert_eq(s.trainer_mode, TrainerDevice.MODE_POWER_METER)
	s.start()
	var model := SpeedModel.new()
	while s.get_state() != WorkoutSession.State.FINISHED:
		_ibd_packet(b, "kickr", 200, 50.0, 85.0)
		s.tick(1.0)
	for i in s.samples.size():
		assert_eq(s.samples.power_w[i], 200, "мощность — от станка без управления")
		assert_almost_eq(s.samples.speed_kmh[i], model.step(200.0, 75.0, 1.0, 0.0), 0.1, "скорость — модель, не 50")
	assert_eq(s.samples.cadence_rpm[s.samples.size() - 1], 85, "каденс — станок (нет CSC и CPS)")


# ---------------------------------------------------------------------------
# REQ-WRK-09 п.6 (б) — обрыв: запасной станок, «нет данных», аватар стоит
# ---------------------------------------------------------------------------

func test_req_wrk_09_c6b_dev_05_c2bc_cps_dropout_falls_back_to_data_only_trainer_and_back() -> void:
	var b := _bridge()
	var t := TrainerFactory.create_ble(b)
	_disposables.append(t)
	_ftms_fixture(b, "kickr", false)
	t.connect_device("kickr")
	b.pump()
	var dev := _pm_device(b, 200, 90, t)
	var s := WorkoutSession.new(Workout.make("300", [WorkoutStep.watts(150, 150.0), WorkoutStep.watts(150, 200.0)] as Array[WorkoutStep]), dev, FTP)
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		if s.executor.elapsed_sec() == 100:
			_pm_of(dev).inject_dropout(30.0)
		_ibd_packet(b, "kickr", 180)
		s.tick(1.0)
	var st := s.samples
	assert_almost_eq(st.size(), 300, 1)
	for k in range(1, st.size() + 1):
		var w: int = st.power_w[k - 1]
		assert_true(st.has_power[k - 1], "сэмпл %d: мощность есть всегда (запасной источник)" % k)
		if k <= 100:
			assert_eq(w, 200, "сэмпл %d: CPS" % k)
		elif k >= 101 and k <= 130:
			assert_eq(w, 180, "сэмпл %d: со следующего сэмпла — станок" % k)
		elif k >= 132:
			assert_eq(w, 200, "сэмпл %d: CPS вернулся — снова CPS" % k)
	assert_eq(st.target_w[st.size() - 1], 200, "шаги сменились по времени")
	assert_false(_event_types(s).has(WorkoutSession.EVENT_PAUSE), "автопаузы нет")


func test_req_wrk_09_c6b_cps_silence_5s_falls_back_to_data_only_trainer() -> void:
	var b := _bridge()
	var t := TrainerFactory.create_ble(b)
	_disposables.append(t)
	_ftms_fixture(b, "kickr", false)
	t.connect_device("kickr")
	b.pump()
	var dev := _pm_device(b, 200, 90, t)
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(60, 200.0)] as Array[WorkoutStep]), dev, FTP)
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		if s.executor.elapsed_sec() == 20:
			_pm_of(dev).inject_silence(20.0)
		_ibd_packet(b, "kickr", 180)
		s.tick(1.0)
	var st := s.samples
	assert_eq(st.power_w[19], 200, "последний пакет CPS — сэмпл 20")
	var switched_at := -1
	for k in range(21, 41):
		if st.power_w[k - 1] == 180 and switched_at < 0:
			switched_at = k
		assert_true(st.has_power[k - 1], "сэмпл %d: мощность есть" % k)
	assert_between(switched_at, 21, 25, "переключение на станок не позже 5 с после последнего пакета")
	assert_eq(st.power_w[59], 200, "после тишины — снова CPS")


func test_req_wrk_09_c6b_only_cps_dropout_no_data_not_zero_avatar_stops_plan_continues() -> void:
	var b := _bridge()
	var dev := _pm_device(b, 250, 90)
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(60, 200.0), WorkoutStep.watts(60, 220.0)] as Array[WorkoutStep]), dev, FTP, 1.0, 75.0)
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		if s.executor.elapsed_sec() == 40:
			_pm_of(dev).inject_dropout(60.0)
		s.tick(1.0)
	var st := s.samples
	assert_eq(st.size(), 120, "запись не прерывается, таймер идёт")
	for k in range(41, 100):
		assert_false(st.has_power[k - 1], "сэмпл %d: мощность «нет данных», а не 0" % k)
		assert_false(st.has_cadence[k - 1] and st.cadence_rpm[k - 1] > 0, "сэмпл %d: каденс CPS не держится" % k)
	var zero_at := -1
	for k in range(41, 100):
		if st.speed_kmh[k - 1] <= 0.0:
			zero_at = k
			break
	assert_between(zero_at, 41, 70, "скорость равна 0 не позже 30 с")
	assert_eq(st.target_w[70], 220, "шаг сменился по времени во время обрыва")
	assert_false(_event_types(s).has(WorkoutSession.EVENT_PAUSE), "автопаузы нет")
	assert_true(st.has_power[st.size() - 1], "источник вернулся — мощность снова есть")
	assert_gt(st.speed_kmh[st.size() - 1], 5.0, "и движение со следующих сэмплов")


## WRK-09 п.6 (б) в редакции У-34: на спуске без источника аватар катится накатом по модели при 0 Вт,
## принудительной остановки по сроку нет; дистанция растёт, пока скорость > 0.
func test_req_wrk_09_c6b_d3d_02_c7_free_ride_downhill_no_sources_coasts_by_model() -> void:
	var b := _bridge()
	var dev := _pm_device(b, 300, 90)
	var fr := FreeRideSession.new(dev, RouteCatalog.MOUNTAINS, 50, 75.0, FTP)
	_disposables.push_front(fr)
	fr.start()
	var guard := 0
	while guard < 7200 and not (fr.position.grade_pct() <= -3.0 and fr.speed_kmh() > 25.0):
		fr.tick(1.0)
		guard += 1
	assert_lt(guard, 7200, "предусловие: доехали до спуска")
	_pm_of(dev).inject_dropout(200.0)
	var first := fr.samples.size()
	var grades: Array[float] = []
	for i in 70:
		grades.append(fr.position.grade_pct())
		fr.tick(1.0)
	var st := fr.samples
	var ref := SpeedModel.new()
	var bad: Array[String] = []
	for n in 70:
		var i := first + n
		assert_false(st.has_power[i], "«нет данных», а не 0")
		ref.reset(st.speed_kmh[i - 1])
		var want := ref.step(0.0, 75.0, 1.0, grades[n])
		if absf(st.speed_kmh[i] - want) > 0.1:
			bad.append("%d: %.2f≠%.2f" % [n + 1, st.speed_kmh[i], want])
		if grades[n] <= -1.0:
			assert_gt(st.speed_kmh[i], 0.0, "сэмпл %d на спуске %.1f %%: накат, не остановка" % [n + 1, grades[n]])
		if st.speed_kmh[i] > 0.0:
			assert_gt(st.distance_m[i], st.distance_m[i - 1], "едет — дистанция растёт")
		else:
			assert_almost_eq(st.distance_m[i], st.distance_m[i - 1], 0.01, "стоит — дистанция не растёт")
	assert_eq(bad, [] as Array[String], "каждый сэмпл — шаг модели при 0 Вт (±0.1)")


# ---------------------------------------------------------------------------
# REQ-WRK-09 п.6 (в), REQ-DEV-08 (примечание) — переподключение
# ---------------------------------------------------------------------------

func test_req_wrk_09_c6c_dev_08_note_reconnect_300s_plan() -> void:
	var b := _bridge()
	var dev := _pm_device(b, 210, 90)
	var pm := _pm_of(dev)
	var s := WorkoutSession.new(Workout.make("300", [WorkoutStep.watts(100, 150.0), WorkoutStep.watts(100, 200.0),
		WorkoutStep.watts(100, 180.0)] as Array[WorkoutStep]), dev, FTP)
	s.start()
	var connect_at: Array[float] = []
	while s.get_state() != WorkoutSession.State.FINISHED:
		var t := s.executor.elapsed_sec()
		if t == 100:
			b.clear_calls()
			pm.inject_dropout(30.0)  # disconnected на 100-й, connected на 130-й, пакеты с 131-й
		var before := b.calls_of("connect_peripheral").size()
		s.tick(1.0)
		if b.calls_of("connect_peripheral").size() > before:
			connect_at.append(float(s.executor.elapsed_sec()))
	var st := s.samples
	assert_almost_eq(st.size(), 300, 1, "300 ± 1 сэмплов")
	for k in range(1, st.size() + 1):
		if k >= 102 and k <= 129:
			assert_false(st.has_power[k - 1], "сэмпл %d: «нет данных»" % k)
		elif k <= 100 or k >= 132:
			assert_true(st.has_power[k - 1], "сэмпл %d: значение симулятора" % k)
			assert_eq(st.power_w[k - 1], 210)
	assert_gte(connect_at.size(), 5, "попытки connect_peripheral во время обрыва: %s" % str(connect_at))
	for i in range(1, connect_at.size()):
		assert_almost_eq(connect_at[i] - connect_at[i - 1], 5.0, 1.0, "попытки каждые 5 с: %s" % str(connect_at))
	assert_eq(b.calls_of("discover_services").size(), 1, "после connected — discover_services")
	var subs := b.calls_of("subscribe")
	assert_eq(subs.size(), 1, "повторная подписка")
	if subs.size() > 0:
		assert_eq(subs[0]["char"], BleUuids.CYCLING_POWER_MEASUREMENT, "…на 2A63")
	assert_eq(b.calls_of("write"), [] as Array[Dictionary], "ни одного write")
	# DEV-08 п.4: сэмплы до обрыва — в сохранённом заезде.
	var repo := FileRideRepository.new(_dir + "rides/")
	var ride := Ride.from_session(s, Profile.create("R"))
	ride.compute_summary()
	repo.save(ride)
	var loaded := repo.get_ride(ride.id)
	assert_eq(loaded.samples.size(), st.size(), "все сэмплы в сохранённом заезде")
	for i in 100:
		assert_eq(loaded.samples.power_w[i], 210)
		assert_true(loaded.samples.has_power[i])


# ---------------------------------------------------------------------------
# REQ-WRK-09 п.7 — свободная езда по модели с уклоном
# ---------------------------------------------------------------------------

func test_req_wrk_09_c7_free_ride_mountains_600s_equivalence_and_speeds() -> void:
	var trainer := _fake_trainer(200, 90)
	var smart := FreeRideSession.new(trainer, RouteCatalog.MOUNTAINS, 50, 75.0, FTP)
	_disposables.push_front(smart)
	var b := _bridge()
	var dev := _pm_device(b, 200, 90)
	var pmode := FreeRideSession.new(dev, RouteCatalog.MOUNTAINS, 50, 75.0, FTP)
	_disposables.push_front(pmode)
	assert_eq(pmode.trainer_mode, TrainerDevice.MODE_POWER_METER)
	smart.start()
	pmode.start()
	for i in 600:
		smart.tick(1.0)
		pmode.tick(1.0)
	var md := 0.0
	var mh := 0.0
	var mg := 0.0
	for i in 600:
		md = maxf(md, absf(smart.samples.distance_m[i] - pmode.samples.distance_m[i]))
		mh = maxf(mh, absf(smart.samples.altitude_m[i] - pmode.samples.altitude_m[i]))
		mg = maxf(mg, absf(smart.samples.grade_pct[i] - pmode.samples.grade_pct[i]))
	assert_lte(md, 0.01, "дистанция ±0.01 м")
	assert_lte(mh, 0.01, "высота ±0.01 м")
	assert_lte(mg, 0.01, "уклон ±0.01 %")
	assert_almost_eq(pmode.ascent_m(), smart.ascent_m(), 0.01, "одинаковый набор высоты")
	assert_eq(b.calls_of("write"), [] as Array[Dictionary], "журнал моста без write")
	assert_almost_eq(SpeedModel.steady_speed_kmh(200.0, 75.0, 5.0), 15.2, 1.5, "модель: 5 % → 15.2 ± 1.5 км/ч")
	var on5 := 0
	for i in range(15, 600):
		var steady := true
		for k in range(i - 15, i + 1):
			if absf(pmode.samples.grade_pct[k] - 5.0) > 0.3:
				steady = false
				break
		if steady:
			on5 += 1
			assert_almost_eq(pmode.samples.speed_kmh[i], 15.2, 1.5, "t=%d: на 5 %% скорость 15.2 ± 1.5" % i)
	gut.p("сэмплов на установившемся участке 5 %%: %d" % on5)
	# Ровная трасса: 34 ± 3 км/ч.
	var b2 := _bridge()
	var flat := FreeRideSession.new(_pm_device(b2, 200, 90), RouteCatalog.FLAT, 50, 75.0, FTP)
	_disposables.push_front(flat)
	flat.start()
	for i in 120:
		flat.tick(1.0)
	var g := flat.samples.grade_pct[flat.samples.size() - 1]
	assert_almost_eq(flat.samples.speed_kmh[flat.samples.size() - 1], SpeedModel.steady_speed_kmh(200.0, 75.0, g), 0.5,
		"скорость — модель при уклоне трассы g(s)")
	if absf(g) < 0.5:
		assert_almost_eq(flat.samples.speed_kmh[flat.samples.size() - 1], 34.0, 3.0, "на ровном 34 ± 3 км/ч")


func test_req_wrk_09_c7_sim_steepness_and_mode_change_nothing() -> void:
	var b1 := _bridge()
	var a := FreeRideSession.new(_pm_device(b1, 230, 90), RouteCatalog.HILLS, 0, 75.0, FTP)
	_disposables.push_front(a)
	var b2 := _bridge()
	var c := FreeRideSession.new(_pm_device(b2, 230, 90), RouteCatalog.HILLS, 100, 75.0, FTP,
		SimController.Mode.FIXED, 90)
	_disposables.push_front(c)
	a.start()
	c.start()
	for i in 300:
		if i == 50:
			c.set_steepness(25)
			c.toggle_mode()
			c.set_resistance_level(5)
		a.tick(1.0)
		c.tick(1.0)
	for i in 300:
		assert_almost_eq(c.samples.distance_m[i], a.samples.distance_m[i], 0.01, "крутизна SIM ни на что не влияет")
		assert_almost_eq(c.samples.speed_kmh[i], a.samples.speed_kmh[i], 0.01)
	for t in _event_types(c):
		assert_false(t == SimController.EVENT_STEEPNESS or t == SimController.EVENT_MODE or t == FreeRideSession.EVENT_SIM_UNAVAILABLE,
			"событий SIM в power_meter нет: %s" % t)
	assert_eq(b1.calls_of("write").size() + b2.calls_of("write").size(), 0, "станку ничего не уходит")


# ---------------------------------------------------------------------------
# REQ-WRK-09 п.8, REQ-LOC-01 п.1 — сохранение, сводка, FIT
# ---------------------------------------------------------------------------

func test_req_wrk_09_c8_loc_01_c1_get_ride_trainer_mode_fit_records_power_invalid_laps() -> void:
	var b := _bridge()
	var dev := _pm_device(b, 205, 88)
	var s := WorkoutSession.new(_plan_p3(), dev, FTP)
	_drive_p3_with_dropout(s, dev)
	var repo := FileRideRepository.new(_dir + "rides/")
	var profile := Profile.create("R")
	var ride := Ride.from_session(s, profile)
	ride.compute_summary()
	repo.save(ride)
	var loaded := repo.get_ride(ride.id)
	assert_not_null(loaded)
	assert_eq(loaded.metadata.get(Ride.KEY_TRAINER_MODE), Ride.TRAINER_MODE_POWER_METER, "meta: trainer_mode = power_meter")
	assert_eq(loaded.trainer_mode(), Ride.TRAINER_MODE_POWER_METER)
	assert_eq(loaded.speed_source(), SampleStream.SPEED_SOURCE_MODEL, "LOC-01 п.1: speed_source = модель")
	assert_eq(loaded.trainer_source(), Ride.TRAINER_SOURCE_EMULATOR, "симулятор CPS → trainer_source = emulator")
	assert_eq(repo.list(profile.id)[0].trainer_mode, Ride.TRAINER_MODE_POWER_METER, "режим в сводке списка")
	for k in ["started_at_unix", "workout_name", "workout_source", "ftp_w", "weight_kg", "max_hr", "intensity",
			"stopped_early", "paused_total_sec"]:
		assert_true(loaded.metadata.has(k), "LOC-01 п.1: в метаданных есть %s" % k)
	assert_eq(loaded.samples.size(), s.samples.size(), "все сэмплы")
	for t in _event_types(loaded):
		assert_false(t in [WorkoutSession.EVENT_ERG_ON, WorkoutSession.EVENT_ERG_OFF], "событий ERG нет")
	var fit := FitDecoder.decode(FitEncoder.encode(loaded))
	assert_true(fit.ok, fit.error)
	var records: Array[Dictionary] = []
	var laps := 0
	for m in fit.messages:
		if m["global"] == FitDefinitions.MSG_RECORD:
			records.append(m)
		elif m["global"] == FitDefinitions.MSG_LAP:
			laps += 1
	assert_eq(records.size(), loaded.samples.size(), "число record = число сэмплов")
	var invalid := 0
	for i in mini(records.size(), loaded.samples.size()):
		var f: Dictionary = records[i]["fields"]
		if loaded.samples.has_power[i]:
			assert_eq(f.get(FitDefinitions.RECORD_POWER), loaded.samples.power_w[i], "power совпадает, i=%d" % i)
		else:
			invalid += 1
			assert_null(f.get(FitDefinitions.RECORD_POWER), "«нет данных» → invalid, i=%d" % i)
	assert_gt(invalid, 0, "в заезде есть «нет данных»")
	var steps_seen := {}
	for i in loaded.samples.size():
		steps_seen[loaded.samples.step_index[i]] = true
	assert_eq(laps, steps_seen.size(), "lap — по шагам плана")


func _drive_p3_with_dropout(s: WorkoutSession, dev: UncontrolledTrainer) -> void:
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		if s.executor.elapsed_sec() == 30:
			_pm_of(dev).inject_dropout(15.0)
		if s.executor.elapsed_sec() == 150 and s.executor.current_step_index() == 2:
			s.skip_step()
		s.tick(1.0)


func test_req_wrk_09_c8_loc_01_c1_free_ride_power_meter_saved_with_mode() -> void:
	var b := _bridge()
	var fr := FreeRideSession.new(_pm_device(b, 200, 90), RouteCatalog.HILLS, 50, 75.0, FTP)
	_disposables.push_front(fr)
	fr.start()
	for i in 90:
		fr.tick(1.0)
	fr.stop()
	var repo := FileRideRepository.new(_dir + "rides/")
	var ride := Ride.from_session(fr, Profile.create("R"))
	ride.compute_summary()
	repo.save(ride)
	var loaded := repo.get_ride(ride.id)
	assert_true(loaded.is_free_ride())
	assert_eq(loaded.trainer_mode(), Ride.TRAINER_MODE_POWER_METER)
	var fit := FitDecoder.decode(FitEncoder.encode(loaded))
	assert_true(fit.ok, fit.error)
	var records := 0
	for m in fit.messages:
		if m["global"] == FitDefinitions.MSG_RECORD:
			records += 1
	assert_eq(records, loaded.samples.size(), "FIT свободной езды: record = сэмплы")


func test_req_wrk_09_c8_loc_01_c1_legacy_ride_fixture_reads_as_smart() -> void:
	var dst := ProjectSettings.globalize_path(_dir + "legacy/")
	_copy_tree(ProjectSettings.globalize_path("res://tests/fixtures/rides_v1/"), dst)
	var repo := FileRideRepository.new(_dir + "legacy/")
	var ride := repo.get_ride("1700000000-0a1b2c3d")
	assert_not_null(ride, "старый заезд читается")
	assert_false(ride.metadata.has(Ride.KEY_TRAINER_MODE), "предусловие: поля нет")
	assert_eq(ride.trainer_mode(), Ride.TRAINER_MODE_SMART, "заезд без поля → smart")
	var listed := repo.list("legacy-profile")
	assert_eq(listed.size(), 1)
	assert_eq(listed[0].trainer_mode, Ride.TRAINER_MODE_SMART, "сводка без поля → smart")


static func _copy_tree(src: String, dst: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst)
	var d := DirAccess.open(src)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.copy_absolute(src.path_join(f), dst.path_join(f))
	for sub in d.get_directories():
		_copy_tree(src.path_join(sub), dst.path_join(sub))


func test_req_wrk_09_c8_smart_ride_has_trainer_mode_smart() -> void:
	var s := WorkoutSession.new(Workout.make("s", [WorkoutStep.watts(5, 150.0)] as Array[WorkoutStep]), _fake_trainer(), FTP)
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		s.tick(1.0)
	assert_eq(s.metadata().get(WorkoutSession.META_TRAINER_MODE), TrainerDevice.MODE_SMART, "у smart-заезда — smart")


# ---------------------------------------------------------------------------
# REQ-WRK-09 п.11 — изоляция
# ---------------------------------------------------------------------------

func test_req_wrk_09_c11_no_cps_uuid_literals_in_session_domain_ui() -> void:
	var hits: Array[String] = []
	for root in ["res://src/session/", "res://src/domain/", "res://src/ui/"]:
		_scan_literals(root, hits)
	assert_eq(hits, [] as Array[String], "в строковых литералах нет 0x1818 / 2a63 / 2a66")


func _scan_literals(dir_path: String, hits: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if not f.ends_with(".gd"):
			continue
		var path := dir_path.path_join(f)
		var lines := FileAccess.get_file_as_string(path).split("\n")
		var str_re := RegEx.new()
		str_re.compile("\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'")
		for i in lines.size():
			for m in str_re.search_all(lines[i]):
				var lit := m.get_string().to_lower()
				# Литерал до символа комментария вне строки — код; после «#» — комментарий.
				var hash_pos := lines[i].find("#")
				if hash_pos >= 0 and hash_pos < m.get_start() and lines[i].substr(0, hash_pos).count("\"") % 2 == 0:
					continue
				for needle in ["0x1818", "2a63", "2a66"]:
					if lit.contains(needle):
						hits.append("%s:%d %s" % [path, i + 1, lit])
	for sub in d.get_directories():
		_scan_literals(dir_path.path_join(sub), hits)


# ---------------------------------------------------------------------------
# REQ-WRK-09 п.12 — симулятор CPS
# ---------------------------------------------------------------------------

func test_req_wrk_09_c12_simulator_scenarios_constant_jumps_zero_cadence_skip_dropout() -> void:
	var b := _bridge()
	var dev := _pm_device(b, 200, 90)
	var pm := _pm_of(dev)
	var s := WorkoutSession.new(Workout.make("sim", [WorkoutStep.watts(120, 200.0)] as Array[WorkoutStep]), dev, FTP)
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		var t := s.executor.elapsed_sec()
		if t == 10:
			pm.set_power_sequence([100, 400, 150, 600] as Array[int])
		if t == 20:
			pm.set_power(250)
			pm.set_zero_cadence()
		if t == 35:
			pm.set_power(220)
			pm.set_cadence(80)
		if t == 50:
			pm.inject_silence(8.0)
		if t == 70:
			pm.inject_dropout(12.0)
		s.tick(1.0)
	var st := s.samples
	assert_eq(st.size(), 120)
	# Постоянная мощность и каденс (1 Гц).
	assert_eq(st.power_w[5], 200)
	assert_eq(st.cadence_rpm[5], 90, "каденс по оборотам шатуна")
	# Рывки: по значению в секунду.
	assert_eq([st.power_w[10], st.power_w[11], st.power_w[12], st.power_w[13], st.power_w[14]],
		[100, 400, 150, 600, 600], "рывки мощности по секундам")
	# Нулевой каденс: пакеты идут, обороты не растут → 0 не позже 3 с (DEV-05 п.3), мощность 0 есть.
	assert_true(st.has_power[30], "педали стоят — пакеты идут")
	assert_eq(st.power_w[30], 0)
	assert_true(st.has_cadence[30] and st.cadence_rpm[30] == 0, "нулевой каденс — 0, а не «нет данных»")
	# Пропуск пакетов 8 с: мощность «нет данных» с 5-й секунды тишины, каденс — с 3-й.
	assert_true(st.has_power[51], "в начале тишины мощность ещё свежая")
	assert_false(st.has_power[56], "тишина ≥ 5 с — «нет данных»")
	assert_false(st.has_cadence[54], "каденс CPS — «нет данных» через 3 с")
	assert_true(st.has_power[62], "пакеты вернулись")
	# Обрыв и восстановление.
	assert_false(st.has_power[72], "обрыв — «нет данных»")
	assert_true(st.has_power[st.size() - 1], "восстановление")
	assert_eq(st.power_w[st.size() - 1], 220)


func test_req_wrk_09_c12_injected_clock_fractional_ticks_equal_whole() -> void:
	var a := _emulator()
	var c := _emulator()
	var sa := WorkoutSession.new(Workout.make("c", [WorkoutStep.watts(30, 200.0)] as Array[WorkoutStep]), a, FTP)
	var sc := WorkoutSession.new(Workout.make("c", [WorkoutStep.watts(30, 200.0)] as Array[WorkoutStep]), c, FTP)
	TrainerFactory.power_meter_emulator_sensor(a).set_power_sequence([150, 180, 210, 240, 270] as Array[int])
	TrainerFactory.power_meter_emulator_sensor(c).set_power_sequence([150, 180, 210, 240, 270] as Array[int])
	sa.start()
	sc.start()
	while sa.get_state() != WorkoutSession.State.FINISHED:
		sa.tick(1.0)
	var guard := 0
	while sc.get_state() != WorkoutSession.State.FINISHED and guard < 1000:
		sc.tick(0.25)
		guard += 1
	assert_eq(sc.samples.size(), sa.samples.size())
	assert_eq(Array(sc.samples.power_w), Array(sa.samples.power_w), "инъекция часов: дробные тики дают те же сэмплы")
	assert_eq(Array(sc.samples.cadence_rpm), Array(sa.samples.cadence_rpm))


func test_req_wrk_09_c12_emulator_is_uncontrolled_and_marked_emulator() -> void:
	var dev := _emulator()
	assert_eq(dev.trainer_mode(), TrainerDevice.MODE_POWER_METER)
	assert_false(dev.has_control())
	assert_true(dev.is_emulator())
	assert_eq(dev.trainer_source(), TrainerDevice.SOURCE_EMULATOR, "trainer_source = emulator (WRK-09 п.8)")
	assert_eq(dev.get_connection_state(), CONNECTED, "подключён сразу")


# ---------------------------------------------------------------------------
# Д-4 (T-171, отложено из приёмки T-152; У-33): WRK-09 п.6 (б) → D3D-02 п.7, тест 1 на ровном
# ---------------------------------------------------------------------------

func test_req_wrk_09_c6b_d3d_02_c7_avatar_slows_down_at_most_5_kmh_per_sample() -> void:
	# WRK-09 п.6 (б): обрыв единственного CPS → «нет данных», тяги нет, аватар останавливается
	# плавно (D3D-02 п.7): первый сэмпл без источника > 0 и равен модели при 0 Вт (±0.1 км/ч),
	# дальше не растёт, ≤ 5 км/ч за сэмпл, 0 не позже 30-го сэмпла, затем дистанция стоит.
	# План — без трассы (уклон 0 %, ровный участок теста 1); свободная езда — `flat`.
	var b := _bridge()
	var dev := _pm_device(b, 250, 90)
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(120, 200.0)] as Array[WorkoutStep]), dev, FTP, 1.0, 75.0)
	s.start()
	var cut := -1
	while s.get_state() != WorkoutSession.State.FINISHED:
		if s.executor.elapsed_sec() == 40:
			_pm_of(dev).inject_dropout(100.0)
			cut = s.samples.size()
		s.tick(1.0)
	var st := s.samples
	assert_true(st.has_power[cut - 1], "до обрыва мощность есть")
	assert_false(st.has_power[cut], "первый сэмпл после `disconnected` — «нет данных»")
	var ref := SpeedModel.new()
	ref.reset(st.speed_kmh[cut - 1])
	assert_gt(st.speed_kmh[cut], 0.0, "план: не мгновенный ноль (было %.1f → %.1f)" % [st.speed_kmh[cut - 1], st.speed_kmh[cut]])
	assert_almost_eq(st.speed_kmh[cut], ref.step(0.0, 75.0, 1.0, 0.0), 0.1, "план: первый сэмпл = модель при 0 Вт")
	var max_drop := 0.0
	var zero_at := -1
	for i in range(cut, st.size()):
		max_drop = maxf(max_drop, st.speed_kmh[i - 1] - st.speed_kmh[i])
		assert_true(st.speed_kmh[i] <= st.speed_kmh[i - 1] + 1e-4, "план, сэмпл %d без источника: не растёт" % (i - cut + 1))
		if zero_at < 0 and st.speed_kmh[i] == 0.0:
			zero_at = i - cut + 1
	assert_lte(max_drop, 5.0 + 1e-3, "план: падение скорости за сэмпл ≤ 5 км/ч (было %.2f)" % max_drop)
	assert_true(zero_at > 0 and zero_at <= 30, "план: 0 не позже 30-го сэмпла без источника (%d)" % zero_at)
	var stop_idx := cut + zero_at - 1
	for i in range(stop_idx + 1, mini(stop_idx + 31, st.size())):
		assert_almost_eq(st.distance_m[i], st.distance_m[stop_idx], 0.01, "план: после остановки дистанция стоит")
	assert_eq(s.get_state(), WorkoutSession.State.FINISHED, "таймер плана шёл")
	var b2 := _bridge()
	var dev2 := _pm_device(b2, 250, 90)
	var fr := FreeRideSession.new(dev2, RouteCatalog.FLAT, 50, 75.0, FTP)
	_disposables.push_front(fr)
	fr.start()
	for i in 60:
		fr.tick(1.0)
	var cut2 := fr.samples.size()
	_pm_of(dev2).inject_dropout(100.0)
	for i in 40:
		fr.tick(1.0)
	var fst := fr.samples
	assert_false(fst.has_power[cut2], "свободная езда: «нет данных»")
	assert_gt(fst.speed_kmh[cut2], 0.0, "свободная езда: не мгновенный ноль (было %.1f → %.1f)" % [fst.speed_kmh[cut2 - 1], fst.speed_kmh[cut2]])
	# Трасса `flat` не строго ровная (уклон −0.7…+1 %): по У-34 каждый сэмпл — шаг модели при 0 Вт с
	# уклоном перед шагом (уклон предыдущего сэмпла).
	var ref2 := SpeedModel.new()
	var max_drop_fr := 0.0
	for i in range(cut2, fst.size()):
		max_drop_fr = maxf(max_drop_fr, fst.speed_kmh[i - 1] - fst.speed_kmh[i])
		ref2.reset(fst.speed_kmh[i - 1])
		assert_almost_eq(fst.speed_kmh[i], ref2.step(0.0, 75.0, 1.0, fst.grade_pct[i - 1]), 0.1, "свободная езда, сэмпл %d: шаг модели при 0 Вт" % (i - cut2 + 1))
	assert_lte(max_drop_fr, 5.0 + 1e-3, "свободная езда: падение скорости за сэмпл ≤ 5 км/ч (было %.2f)" % max_drop_fr)
