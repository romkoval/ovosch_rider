extends GutTest
## T-152: устройства режима без управляемого станка (REQ-WRK-09 п.1, 2, 4, 6, 11, 12;
## REQ-DEV-05 п.5; REQ-DEV-08 примечание; REQ-DEV-10 п.4). Правило старта и режим сессии
## (`ConnectionManager.start_check`), `UncontrolledTrainer` (ни одной команды на мост),
## станок «только данные» (`BleTrainer` без 2AD9), симулятор CPS `FakePowerMeter`,
## приоритет «измеритель > станок» с переключением туда и обратно.

const CONNECTED: int = TrainerDevice.ConnectionState.CONNECTED

var _dir: String
var _bridge: StubBleBridge
var _cm: ConnectionManager
var _disposables: Array = []


func before_each() -> void:
	_dir = "user://test_pm_mode_dev_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_bridge = StubBleBridge.new()
	_cm = null
	_disposables = []


func after_each() -> void:
	if _cm != null:
		_cm.dispose()
		_cm = null
	for d: Variant in _disposables:
		if d != null and (d as Object).has_method("dispose"):
			(d as Object).call("dispose")
	_disposables = []
	if _bridge != null:
		_bridge.dispose()
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


func _manager() -> ConnectionManager:
	_cm = ConnectionManager.new(_bridge, RememberedDevices.new(_dir), TrainerFactory.KIND_BLE)
	_cm.set_profile("p")
	return _cm


## FTMS-станок `id`: с Control Point или без (только данные, DEV-10 п.4).
func _ftms(id: String, with_control_point: bool) -> void:
	var chars := PackedStringArray([BleUuids.INDOOR_BIKE_DATA, BleUuids.FTMS_STATUS])
	if with_control_point:
		chars.append(BleUuids.FTMS_CONTROL_POINT)
	_bridge.set_device_services(id, {BleUuids.FTMS_SERVICE: chars})


func _connect_trainer(id: String, with_control_point: bool) -> void:
	_ftms(id, with_control_point)
	_cm.connect_trainer(id)
	_bridge.pump()


func _connect_sensor(id: String, kind: String, service: String, ch: String) -> void:
	_bridge.set_device_services(id, {service: PackedStringArray([ch])})
	_cm.connect_sensor(id, kind)
	_bridge.pump()


func _connect_pm(id: String = "pm") -> void:
	_connect_sensor(id, RememberedDevices.KIND_POWER, BleUuids.CPS_SERVICE, BleUuids.CYCLING_POWER_MEASUREMENT)


## Записи и подписки на характеристики управления в журнале моста.
func _control_calls(bridge: StubBleBridge) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in bridge.calls:
		if c["method"] == "write":
			out.append(c)
		elif c["method"] == "subscribe" and (c["char"] == BleUuids.FTMS_CONTROL_POINT or c["char"] == "2A66"):
			out.append(c)
	return out


# ---------------------------------------------------------------------------
# WRK-09 п.1, 2 — правило старта на фикстурах
# ---------------------------------------------------------------------------

func test_req_wrk_09_c1_only_cps_gives_power_meter_mode() -> void:
	_manager()
	_connect_pm()
	var check := _cm.start_check()
	assert_true(check["allowed"], "WRK-09 п.2 (б): с измерителем мощности старт разрешён")
	assert_eq(check["mode"], TrainerDevice.MODE_POWER_METER)
	assert_eq(check["power_source"], SensorHub.SOURCE_POWER_METER)
	assert_eq(check["reason"], ConnectionManager.START_OK)
	var dev := _cm.session_device()
	assert_true(dev is UncontrolledTrainer, "устройство сессии — без управления")
	assert_eq(dev.trainer_mode(), TrainerDevice.MODE_POWER_METER)
	assert_eq(dev.get_connection_state(), CONNECTED, "состояние — источника мощности")


func test_req_wrk_09_c1_dev_10_c4_ftms_without_control_point_is_data_only_power_meter_mode() -> void:
	_manager()
	_connect_trainer("kickr", false)
	assert_eq(_cm.trainer.get_connection_state(), CONNECTED, "станок без 2AD9 подключён как источник данных")
	assert_false(_cm.trainer.has_control(), "канала управления нет")
	assert_eq(_control_calls(_bridge), [], "DEV-10 п.4: ни одного write и subscribe на 2AD9")
	assert_true(_bridge.is_subscribed("kickr", BleUuids.FTMS_SERVICE, BleUuids.INDOOR_BIKE_DATA), "подписка 2AD2")
	assert_true(_bridge.is_subscribed("kickr", BleUuids.FTMS_SERVICE, BleUuids.FTMS_STATUS), "подписка 2ADA")
	var check := _cm.start_check()
	assert_true(check["allowed"])
	assert_eq(check["mode"], TrainerDevice.MODE_POWER_METER, "FTMS без 2AD9 → power_meter")
	assert_eq(check["power_source"], SensorHub.SOURCE_TRAINER, "источник мощности — станок (WRK-09 п.1 (б))")
	# Команды станку без управления в мост не уходят (ERG, сопротивление, SIM).
	_cm.trainer.set_erg_enabled(false)
	_cm.trainer.set_resistance_level(40)
	_cm.trainer.set_target_power(200)
	_cm.trainer.set_simulation(3.0)
	_bridge.pump()
	assert_eq(_bridge.calls_of("write"), [], "команды не создают записей")


func test_req_wrk_09_c1_controllable_trainer_with_cps_is_smart() -> void:
	_manager()
	_connect_trainer("neo", true)
	_connect_pm()
	assert_true(_cm.trainer.has_control())
	var check := _cm.start_check()
	assert_true(check["allowed"])
	assert_eq(check["mode"], TrainerDevice.MODE_SMART, "FTMS с 2AD9 и CPS → smart")
	assert_eq(_cm.session_device(), _cm.hub, "в smart — хаб, как прежде")


func test_req_wrk_09_c1_c2_only_hrs_and_csc_or_nothing_no_session() -> void:
	_manager()
	var empty := _cm.start_check()
	assert_false(empty["allowed"], "ничего → сессии нет")
	assert_eq(empty["reason"], ConnectionManager.START_NO_POWER_SOURCE)
	assert_eq(empty["mode"], "")
	_connect_sensor("hrs", RememberedDevices.KIND_HR, BleUuids.HRS_SERVICE, BleUuids.HEART_RATE_MEASUREMENT)
	_connect_sensor("csc", RememberedDevices.KIND_CADENCE, BleUuids.CSC_SERVICE, BleUuids.CSC_MEASUREMENT)
	var sensors_only := _cm.start_check()
	assert_false(sensors_only["allowed"], "только HRS и CSC → сессии нет (WRK-09 п.2 (в))")
	assert_eq(sensors_only["reason"], ConnectionManager.START_NO_POWER_SOURCE)
	assert_null(_cm.session_device(), "устройство сессии не создаётся")


func test_req_wrk_09_c2_g_connecting_or_reconnecting_source_counts_as_not_connected() -> void:
	_manager()
	_bridge.auto_connect = false
	_cm.connect_sensor("pm", RememberedDevices.KIND_POWER)
	_bridge.pump()
	var check := _cm.start_check()
	assert_false(check["allowed"], "измеритель в «подключении» — не подключён")
	assert_true(check["connecting"], "для пояснения: источник подключается")
	_bridge.auto_connect = true
	_bridge.emit_connected("pm")
	_bridge.pump()
	assert_true(_cm.start_check()["allowed"])
	_bridge.emit_disconnected("pm")
	var again := _cm.start_check()
	assert_false(again["allowed"], "измеритель в «переподключении» — не подключён")
	assert_true(again["connecting"])


func test_req_wrk_09_c1_c4_controllable_trainer_connecting_mid_session_gets_no_writes() -> void:
	_manager()
	_connect_pm()
	var dev := _cm.session_device()
	assert_eq(dev.trainer_mode(), TrainerDevice.MODE_POWER_METER)
	_bridge.clear_calls()
	_connect_trainer("neo", true)
	assert_eq(_cm.trainer.get_connection_state(), CONNECTED, "станок подключился посреди сессии")
	assert_eq(_control_calls(_bridge), [], "до конца сессии ни одного write и subscribe на 2AD9")
	assert_eq(dev.trainer_mode(), TrainerDevice.MODE_POWER_METER, "режим сессии не меняется")
	dev.set_erg_enabled(true)
	dev.set_target_power(250)
	_bridge.pump()
	assert_eq(_bridge.calls_of("write"), [], "команды через устройство сессии тоже никуда не уходят")
	# После сессии станок берёт управление, следующая сессия — smart.
	_cm.release_session_device()
	_bridge.pump()
	assert_eq(_bridge.writes_to(BleUuids.FTMS_CONTROL_POINT).size(), 1, "после сессии — Request Control")
	assert_true(_cm.trainer.has_control())
	assert_eq(_cm.start_check()["mode"], TrainerDevice.MODE_SMART)


# ---------------------------------------------------------------------------
# WRK-09 п.4, DEV-05 п.5 — устройство без управления не пишет в мост
# ---------------------------------------------------------------------------

func test_req_wrk_09_c4_dev_05_c5_uncontrolled_commands_never_reach_bridge() -> void:
	var trainer := TrainerFactory.create_ble(_bridge)
	_disposables.append(trainer)
	var pm := FakePowerMeter.new(_bridge)
	_disposables.append(pm)
	var hub := SensorHub.new(trainer)
	hub.set_power_meter(pm)
	pm.connect_device("pm")
	var dev := UncontrolledTrainer.new(hub)
	_disposables.push_front(dev)
	for i in 3:
		dev.set_erg_enabled(i % 2 == 0)
		dev.set_target_power(150 + i)
		dev.set_resistance_level(30 + i)
		dev.set_simulation(2.0 * i)
		dev.tick(1.0)
	assert_eq(_bridge.calls_of("write"), [], "ни одного write")
	assert_false(dev.is_erg_enabled())
	assert_false(dev.has_control())
	assert_eq(dev.simulation_support(), TrainerDevice.SimulationSupport.UNSUPPORTED)
	var subs: Array[String] = []
	for c in _bridge.calls_of("subscribe"):
		subs.append(str(c["char"]))
	assert_eq(subs, [BleUuids.CYCLING_POWER_MEASUREMENT] as Array[String], "subscribe — только 2A63 (без 2A66)")


# ---------------------------------------------------------------------------
# WRK-09 п.12 — симулятор CPS
# ---------------------------------------------------------------------------

func test_req_wrk_09_c12_cps_simulator_power_and_crank_cadence_at_1hz() -> void:
	var pm := FakePowerMeter.new()
	_disposables.append(pm)
	pm.set_power(250)
	pm.set_cadence(90)
	var powers: Array[int] = []
	var cadences: Array[int] = []
	pm.power.connect(func(w: int) -> void: powers.append(w))
	pm.cadence.connect(func(r: int) -> void: cadences.append(r))
	pm.connect_device("pm")
	assert_eq(pm.get_connection_state(), CONNECTED, "симулятор подключается сразу")
	assert_true(pm.is_emulator(), "источник — эмулятор (T-160)")
	for i in 10:
		pm.tick(0.5)
		pm.tick(0.5)
	assert_eq(powers.size(), 10, "одна нотификация 2A63 в секунду")
	assert_eq(powers.back(), 250)
	assert_eq(cadences.size(), 9, "каденс со второго пакета (нужна пара оборотов)")
	for c in cadences:
		assert_eq(c, 90, "каденс по оборотам шатуна")
	assert_eq(pm.stub.calls_of("write"), [], "симулятор ничего не пишет")


func test_req_wrk_09_c12_cps_simulator_scenarios_jumps_zero_cadence_silence_dropout() -> void:
	var pm := FakePowerMeter.new()
	_disposables.append(pm)
	var powers: Array[int] = []
	var cadences: Array[int] = []
	pm.power.connect(func(w: int) -> void: powers.append(w))
	pm.cadence.connect(func(r: int) -> void: cadences.append(r))
	pm.connect_device("pm")
	pm.set_power_sequence([100, 400, 100, 400] as Array[int])
	for i in 4:
		pm.tick(1.0)
	assert_eq(powers, [100, 400, 100, 400] as Array[int], "рывки по сценарию")
	pm.set_zero_cadence()
	for i in 5:
		pm.tick(1.0)
	assert_eq(powers.back(), 0, "педали стоят — мощность 0")
	assert_eq(cadences.back(), 0, "обороты не растут ≥ 3 с при приходящих пакетах — каденс 0 (DEV-05 п.3)")
	var before := powers.size()
	pm.inject_silence(3.0)
	for i in 3:
		pm.tick(1.0)
	assert_eq(powers.size(), before, "пропуск пакетов: связь есть, данных нет")
	assert_eq(pm.get_connection_state(), CONNECTED)
	pm.tick(1.0)
	assert_eq(powers.size(), before + 1, "пакеты вернулись")
	pm.set_power(200)
	pm.inject_dropout(10.0)
	assert_eq(pm.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING, "обрыв → переподключение")
	before = powers.size()
	for i in 10:
		pm.tick(1.0)
	assert_eq(powers.size(), before, "в обрыве пакетов нет")
	assert_eq(pm.get_connection_state(), CONNECTED, "восстановление через 10 с")
	pm.tick(1.0)
	assert_eq(powers.back(), 200, "после восстановления — снова данные")
	assert_eq(pm.stub.calls_of("write"), [], "ни одного write")


# ---------------------------------------------------------------------------
# Источник мощности: измеритель > станок, туда и обратно; без источников — «нет данных»
# ---------------------------------------------------------------------------

func test_req_wrk_09_c1_power_meter_preferred_over_data_only_trainer_with_fallback_and_return() -> void:
	var trainer := FakeTrainer.new(3)
	trainer.controllable = false
	trainer.connect_delay_sec = 0.0
	trainer.power_noise_w = 0.0
	trainer.emit_speed = false
	trainer.set_rider_power(150)
	trainer.connect_device("t")
	var pm := FakePowerMeter.new()
	_disposables.append(pm)
	pm.set_power(250)
	var hub := SensorHub.new(trainer)
	hub.set_power_meter(pm)
	pm.connect_device("pm")
	var dev := UncontrolledTrainer.new(hub, SensorHub.SOURCE_POWER_METER)
	_disposables.push_front(dev)
	var got: Array[TrainerSample] = []
	dev.telemetry.connect(func(s: TrainerSample) -> void: got.append(s))
	for i in 3:
		dev.tick(1.0)
	assert_eq(got.back().power_w, 250, "оба подключены → мощность измерителя")
	assert_eq(hub.power_source_in_use(), SensorHub.SOURCE_POWER_METER)
	pm.inject_dropout(5.0)
	dev.tick(1.0)
	assert_true(got.back().has_power)
	assert_eq(got.back().power_w, 150, "измеритель отвалился → сразу мощность станка")
	assert_eq(hub.power_source_in_use(), SensorHub.SOURCE_TRAINER)
	for i in 6:
		dev.tick(1.0)
	assert_eq(got.back().power_w, 250, "измеритель вернулся → снова он")
	assert_eq(hub.power_source_in_use(), SensorHub.SOURCE_POWER_METER)
	trainer.disconnect_device()
	pm.inject_dropout(30.0)
	for i in 6:
		dev.tick(1.0)
	assert_false(got.back().has_power, "источников нет → «нет данных», не 0")
	dev.dispose()
	assert_eq(hub.power_source, SensorHub.SOURCE_TRAINER, "после сессии хабу возвращён прежний выбор")


func test_req_wrk_09_c12_factory_power_meter_emulator_is_uncontrolled_emulator() -> void:
	var dev := TrainerFactory.create_power_meter_emulator()
	assert_eq(dev.trainer_mode(), TrainerDevice.MODE_POWER_METER)
	assert_true(dev.is_emulator(), "trainer_source = emulator (WRK-09 п.8)")
	assert_eq(dev.trainer_source(), TrainerDevice.SOURCE_EMULATOR)
	assert_eq(dev.get_connection_state(), CONNECTED)
	var sim := TrainerFactory.power_meter_emulator_sensor(dev)
	assert_not_null(sim)
	sim.set_power(180)
	var got: Array[int] = []
	dev.telemetry.connect(func(s: TrainerSample) -> void: got.append(s.power_w if s.has_power else -1))
	for i in 3:
		dev.tick(1.0)
	assert_eq(got.back(), 180)
	(dev as UncontrolledTrainer).dispose()
	assert_eq(sim.stub, null, "обёртка-владелец освободила датчик и мост")


# ---------------------------------------------------------------------------
# WRK-09 п.11 — изоляция
# ---------------------------------------------------------------------------

func test_req_wrk_09_c11_no_cps_uuids_in_session_domain_ui_string_literals() -> void:
	var offenders: Array[String] = []
	var str_re := RegEx.create_from_string("\"[^\"]*\"|'[^']*'")
	for dir in ["res://src/session", "res://src/domain", "res://src/ui"]:
		for path in _gd_files(dir):
			var n := 0
			for line in FileAccess.get_file_as_string(path).split("\n"):
				n += 1
				var code := _strip_comment(line)
				for m in str_re.search_all(code):
					var lit := m.get_string().to_lower()
					if lit.contains("0x1818") or lit.contains("2a63") or lit.contains("2a66"):
						offenders.append("%s:%d" % [path, n])
	assert_eq(offenders, [] as Array[String], "UUID CPS в строковых литералах вне src/devices/")


static func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for sub in d.get_directories():
		out.append_array(_gd_files(dir_path.path_join(sub)))
	return out


## Строка без комментария (`#` вне строкового литерала).
static func _strip_comment(line: String) -> String:
	var quote := ""
	for i in line.length():
		var ch := line[i]
		if quote.is_empty():
			if ch == "#":
				return line.substr(0, i)
			if ch == "\"" or ch == "'":
				quote = ch
		elif ch == quote:
			quote = ""
	return line
