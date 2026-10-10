extends GutTest
## T-161: возможности FTMS-станка — от самого станка (REQ-DEV-10 п.2–8, REQ-DEV-02 п.1; Н-61 (а) —
## запасной диапазон по предложению). `BleTrainer` на `StubBleBridge` с фикстурами характеристик.

const DEV: String = "trainer"
const FULL: Array[String] = ["2AD2", "2AD9", "2ADA"]

var _bridge: StubBleBridge
var _t: BleTrainer
var _errors: Array[int] = []
var _caps_changed: int = 0


func before_each() -> void:
	_bridge = StubBleBridge.new()
	_t = null
	_errors = []
	_caps_changed = 0


func after_each() -> void:
	if _t != null:
		_t.dispose()
	_bridge.dispose()


## FTMS-станок с характеристиками `chars` и ответами `reads` (char → hex), подключён.
func _connect(chars: Array, reads: Dictionary = {}) -> BleTrainer:
	_bridge.set_device_services(DEV, {"1826": PackedStringArray(chars)})
	for c: String in reads:
		_bridge.set_read_value(c, BleBytes.from_hex(str(reads[c])))
	_t = BleTrainer.new(_bridge)
	_t.error.connect(func(code: int, _m: String) -> void: _errors.append(code))
	_t.capabilities_changed.connect(func() -> void: _caps_changed += 1)
	_t.connect_device(DEV)
	for i in 4:
		_bridge.pump()
	return _t


func _cp_writes() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	for c in _bridge.calls_of("write"):
		if BleUuids.normalize(str(c["char"])) == BleUuids.FTMS_CONTROL_POINT:
			out.append(c["bytes"])
	return out


func _last_target() -> PackedByteArray:
	var w := _cp_writes()
	for i in range(w.size() - 1, -1, -1):
		if w[i][0] == FtmsCodec.OP_SET_TARGET_POWER:
			return w[i]
	return PackedByteArray()


# ---------------------------------------------------------------------------
# REQ-DEV-10 п.6, 7 — диапазон цели
# ---------------------------------------------------------------------------

func test_req_dev_10_c6_c7_power_range_from_trainer_and_fallback() -> void:
	_connect(FULL + ["2AD8"] as Array[String], {"2AD8": "0000C4090100"})
	assert_eq(_t.target_power_range(), {"min_w": 0, "max_w": 2500, "increment_w": 1})
	_t.set_target_power(2400)
	assert_eq(_last_target(), BleBytes.from_hex("056009"), "2400 Вт уходит как 2400 при 0..2500")
	_t.dispose()
	_bridge.dispose()
	_bridge = StubBleBridge.new()
	_connect(FULL + ["2AD8"] as Array[String], {"2AD8": "1900DC050500"})
	for pair: Array in [[10, "051900"], [132, "058200"], [1600, "05DC05"], [300, "052C01"]]:
		_t.set_target_power(pair[0])
		_bridge.pump()  # Control Point: следующая команда — после ответа на предыдущую
		assert_eq(_last_target(), BleBytes.from_hex(pair[1]), "%d Вт при 25..1500 шаг 5" % pair[0])
		assert_eq(_t.target_power_w, BleBytes.u16(BleBytes.from_hex(pair[1]), 1))
	assert_eq(_t.applied_target_power(1600), 1500, "фактическая цель — через интерфейс")
	_t.dispose()
	_bridge.dispose()
	_bridge = StubBleBridge.new()
	_connect(FULL)
	_t.set_target_power(2400)
	assert_eq(_last_target(), BleBytes.from_hex("05D007"), "без 2AD8 — запасной 0..2000")
	assert_eq(_bridge.calls_of("read_characteristic").filter(func(c: Dictionary) -> bool: return c["char"] == "2AD8").size(), 0,
		"не заявлена — не читается")


func test_clamp_target_to_range_rounds_to_increment() -> void:
	var r := {"min_w": 25, "max_w": 1500, "increment_w": 5}
	assert_eq(TrainerDevice.clamp_target_to_range(133, r), 135)
	assert_eq(TrainerDevice.clamp_target_to_range(1499, r), 1500)
	assert_eq(TrainerDevice.clamp_target_to_range(-5, r), 25)
	assert_eq(FtmsCodec.decode_supported_power_range(BleBytes.from_hex("1900DC050500")),
		{"ok": true, "min_w": 25, "max_w": 1500, "increment_w": 5})


func test_fake_trainer_emulated_range() -> void:
	var f := FakeTrainer.new()
	f.connect_delay_sec = 0.0
	f.power_range = {"min_w": 25, "max_w": 1500, "increment_w": 5}
	f.connect_device("f")
	f.tick(0.1)
	f.set_target_power(1600)
	assert_eq(f.target_power_w, 1500)
	assert_eq(f.applied_target_power(132), 130)


# ---------------------------------------------------------------------------
# REQ-DEV-10 п.5 — бит 3 и `80 05 02`
# ---------------------------------------------------------------------------

func test_req_dev_10_c5_bit3_zero_no_target_power_commands() -> void:
	# Target Setting Features: бит 2 (сопротивление) и 13 (SIM), без бита 3.
	var tsf: int = FtmsCodec.TSF_RESISTANCE | FtmsCodec.TSF_INDOOR_BIKE_SIMULATION
	_connect(FULL + ["2ACC"] as Array[String], {"2ACC": BleBytes.to_hex(FtmsCodec.encode_fitness_machine_feature(0, tsf)).replace(" ", "")})
	assert_false(_t.is_erg_available(), "ERG недоступен")
	assert_gt(_caps_changed, 0, "возможности изменились")
	var s := WorkoutSession.new(Workout.make("3", [WorkoutStep.watts(5, 150.0), WorkoutStep.watts(5, 200.0), WorkoutStep.watts(5, 250.0)] as Array[WorkoutStep]), _t, 200)
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		s.tick(1.0)
		_bridge.pump()
	assert_eq(_last_target(), PackedByteArray(), "в журнале нет 0x05")


func test_req_dev_10_c5_not_supported_response_disables_erg() -> void:
	_connect(FULL)
	_bridge.fail_next_control_point(FtmsCodec.RESULT_NOT_SUPPORTED)
	_t.set_target_power(150)
	_bridge.pump()
	assert_has(_errors, TrainerDevice.ErrorCode.CONTROL_POINT_REJECTED, "пользователю — ошибка команды")
	assert_false(_t.is_erg_available())
	var n := _cp_writes().size()
	_t.set_target_power(200)
	_t.set_erg_enabled(false)
	_t.set_erg_enabled(true)
	var targets := _cp_writes().slice(n).filter(func(b: PackedByteArray) -> bool: return b[0] == FtmsCodec.OP_SET_TARGET_POWER)
	assert_eq(targets.size(), 0, "дальше 0x05 не уходит")


# ---------------------------------------------------------------------------
# REQ-DEV-10 п.3, 4, DEV-02 п.1 — обязательные характеристики; пустой список
# ---------------------------------------------------------------------------

func test_req_dev_10_c3_without_indoor_bike_data_not_connected() -> void:
	_connect(["2AD9", "2ADA"] as Array[String])
	assert_ne(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_has(_errors, TrainerDevice.ErrorCode.CONNECTION_FAILED)
	assert_eq(_bridge.calls_of("subscribe").size(), 0, "нет подписок")
	assert_eq(_bridge.calls_of("write").size(), 0, "нет записей в 2AD9")
	assert_eq(_t.last_failure(), SensorDevice.FailureReason.NO_SERVICE)


func test_req_dev_10_c4_without_control_point_data_only_regression() -> void:
	_connect(["2AD2", "2ADA"] as Array[String])
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_false(_t.has_control())
	assert_false(_t.is_erg_available())
	_t.set_erg_enabled(false)
	_t.set_resistance_level(40)
	_t.set_erg_enabled(true)
	_t.set_target_power(200)
	for c in _bridge.calls:
		assert_ne(BleUuids.normalize(str(c.get("char", ""))), BleUuids.FTMS_CONTROL_POINT, "ни subscribe, ни write на 2AD9")


func test_empty_service_list_is_not_connected_like_sensor() -> void:
	_bridge.set_device_services(DEV, {})
	_t = BleTrainer.new(_bridge)
	_t.connect_device(DEV)
	_bridge.pump()
	_bridge.pump()
	assert_ne(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "пустой список — «нет сервиса»")
	assert_eq(_t.last_failure(), SensorDevice.FailureReason.NO_SERVICE)
	assert_eq(_bridge.calls_of("subscribe").size(), 0)


func test_connection_manager_does_not_remember_trainer_with_empty_services() -> void:
	var dir := "user://test_caps_%d/" % Time.get_ticks_usec()
	var cm := ConnectionManager.new(_bridge, RememberedDevices.new(dir), TrainerFactory.KIND_BLE)
	cm.set_profile("p")
	_bridge.set_device_services("x", {})
	cm.connect_trainer("x")
	_bridge.pump()
	_bridge.pump()
	assert_ne(cm.state_of("x"), TrainerDevice.ConnectionState.CONNECTED)
	assert_true(cm.remembered.trainer().is_empty(), "не запоминается")
	cm.dispose()
	_bridge = StubBleBridge.new()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


# ---------------------------------------------------------------------------
# REQ-DEV-10 п.8 — диапазон сопротивления
# ---------------------------------------------------------------------------

func test_req_dev_10_c8_resistance_range_0_20_step_1() -> void:
	_connect(FULL + ["2AD6"] as Array[String], {"2AD6": "0000C8000A00"})
	_t.set_erg_enabled(false)
	_t.set_resistance_level(50)
	_bridge.pump()
	assert_eq(_cp_writes().back(), BleBytes.from_hex("0464"))
	_t.set_resistance_level(100)
	_bridge.pump()
	assert_eq(_cp_writes().back(), BleBytes.from_hex("04C8"))


# ---------------------------------------------------------------------------
# REQ-DEV-10 п.2 — без названий моделей и производителей
# ---------------------------------------------------------------------------

func test_req_dev_10_c2_no_model_or_vendor_names_in_string_literals() -> void:
	var offenders: Array[String] = []
	for root in ["res://src/devices/", "res://src/session/"]:
		_scan(root, offenders)
	assert_eq(offenders, [] as Array[String])


func _scan(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	var re := RegEx.create_from_string("\"([^\"\\\\]|\\\\.)*\"")
	for f in d.get_files():
		if not f.ends_with(".gd"):
			continue
		var n := 0
		for line in FileAccess.get_file_as_string(dir_path.path_join(f)).split("\n"):
			n += 1
			if line.strip_edges().begins_with("#"):
				continue
			for m in re.search_all(line):
				var lit := m.get_string().to_lower()
				for needle in ["tacx", "neo", "wahoo", "kickr", "elite", "saris", "jetblack", "wattbike"]:
					if lit.contains(needle):
						out.append("%s:%d %s" % [f, n, line.strip_edges()])
	for sub in d.get_directories():
		_scan(dir_path.path_join(sub), out)
