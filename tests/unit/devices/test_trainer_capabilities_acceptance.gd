extends GutTest
## Приёмка T-161 (tester): возможности FTMS-станка — от самого станка.
## REQ-DEV-10 п.2–8, REQ-DEV-02 п.1. `BleTrainer` поверх `StubBleBridge`; фикстуры станков — набор
## характеристик FTMS и байты ответов `read_characteristic` из текста критериев.

const ID: String = "ftms-acc"
const FTMS: String = "1826"

var _bridge: StubBleBridge
var _disposables: Array = []


func before_each() -> void:
	_bridge = StubBleBridge.new()
	_disposables = []


func after_each() -> void:
	for d: Variant in _disposables:
		if d != null and is_instance_valid(d) and (d as Object).has_method("dispose"):
			(d as Object).call("dispose")
	_disposables = []
	_bridge.dispose()


static func _hex(s: String) -> PackedByteArray:
	var out := PackedByteArray()
	for part in s.split(" ", false):
		out.append(part.hex_to_int())
	return out


static func _to_hex(b: PackedByteArray) -> String:
	var parts: Array[String] = []
	for x in b:
		parts.append("%02X" % x)
	return " ".join(parts)


## FTMS-станок: характеристики `chars`, ответы `reads` {char: hex}.
func _fixture(bridge: StubBleBridge, id: String, chars: Array, reads: Dictionary = {}, extra: Dictionary = {}) -> void:
	var svc: Dictionary = {FTMS: PackedStringArray(chars)}
	for k in extra:
		svc[k] = PackedStringArray(extra[k])
	bridge.set_device_services(id, svc)
	for ch in reads:
		bridge.set_read_value(str(ch), _hex(str(reads[ch])))


func _connect(chars: Array, reads: Dictionary = {}, bridge: StubBleBridge = null, id: String = ID) -> BleTrainer:
	var b := bridge if bridge != null else _bridge
	_fixture(b, id, chars, reads)
	var t := BleTrainer.new(b)
	_disposables.push_front(t)
	t.connect_device(id)
	for i in 4:
		b.pump()
		t.tick(0.1)
	return t


const FULL: Array = ["2AD2", "2AD9", "2ADA"]


## Записи Set Target Power (0x05) в Control Point, hex.
func _target_writes(bridge: StubBleBridge = null) -> Array[String]:
	var out: Array[String] = []
	for w in (bridge if bridge != null else _bridge).writes_to("2AD9"):
		var b: PackedByteArray = w["bytes"]
		if b.size() > 0 and b[0] == 0x05:
			out.append(_to_hex(b))
	return out


func _send(t: BleTrainer, watts: int, bridge: StubBleBridge = null) -> void:
	t.set_target_power(watts)
	for i in 4:
		(bridge if bridge != null else _bridge).pump()
		t.tick(0.3)


# ===========================================================================
# REQ-DEV-02 п.1 — порядок; Control Point только при наличии
# ===========================================================================

func test_req_dev_02_c1_order_subscribe_2ad2_2ada_2ad9_then_request_control() -> void:
	var t := _connect(FULL)
	assert_eq(t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	var seq: Array[String] = []
	for c in _bridge.calls:
		var m := str(c["method"])
		if m == "subscribe":
			seq.append("sub:" + str(c["char"]))
		elif m == "write":
			seq.append("w:" + _to_hex(c["bytes"]))
		elif m in ["connect_peripheral", "discover_services"]:
			seq.append(m)
	gut.p("журнал: %s" % str(seq))
	assert_eq(seq.slice(0, 6), ["connect_peripheral", "discover_services", "sub:2AD2", "sub:2ADA", "sub:2AD9", "w:00"],
		"connected → discover → 2AD2, 2ADA, 2AD9 → Request Control")


# ===========================================================================
# REQ-DEV-10 п.3, п.4 — без 2AD2; без 2AD9
# ===========================================================================

func test_req_dev_10_c3_without_indoor_bike_data_not_connected_error_no_cp() -> void:
	var errors: Array[int] = []
	_fixture(_bridge, ID, ["2AD9", "2ADA"])
	var t := BleTrainer.new(_bridge)
	_disposables.push_front(t)
	t.error.connect(func(c: int, _m: String) -> void: errors.append(c))
	t.connect_device(ID)
	for i in 4:
		_bridge.pump()
		t.tick(0.1)
	assert_ne(t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "без 2AD2 — не «подключено»")
	assert_has(errors, TrainerDevice.ErrorCode.CONNECTION_FAILED, "ошибка подключения")
	assert_ne(t.last_failure(), SensorDevice.FailureReason.NONE, "причина для экрана устройств")
	for m in ["subscribe", "write"]:
		for c in _bridge.calls_of(m):
			assert_ne(str(c.get("char", "")), "2AD9", "нет %s в 2AD9" % m)


func test_req_dev_10_c4_without_control_point_data_only_no_commands() -> void:
	var t := _connect(["2AD2", "2ADA"])
	assert_eq(t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "источник данных — подключён")
	assert_false(t.has_control())
	assert_false(t.is_erg_available())
	t.set_erg_enabled(true)
	_send(t, 200)
	t.set_resistance_level(40)
	_bridge.pump()
	for m in ["subscribe", "write"]:
		for c in _bridge.calls_of(m):
			assert_ne(str(c.get("char", "")), "2AD9", "нет %s в 2AD9" % m)
	var got: Array[TrainerSample] = []
	t.telemetry.connect(func(s: TrainerSample) -> void: got.append(s))
	_bridge.emit_notification(ID, "2AD2", FtmsCodec.encode_indoor_bike_data(30.0, 88.0, 210))
	t.tick(1.0)
	assert_false(got.is_empty())
	if not got.is_empty():
		assert_eq(got.back().power_w, 210, "телеметрия разбирается")


func test_dev_10_empty_service_list_not_connected_not_remembered() -> void:
	var cm := ConnectionManager.new(_bridge, RememberedDevices.new("user://acc_t161_%d/" % Time.get_ticks_usec()))
	cm.set_profile("p")
	_disposables.push_front(cm)
	_bridge.set_device_services(ID, {})
	cm.connect_trainer(ID)
	for i in 4:
		_bridge.pump()
	assert_ne(cm.state_of(ID), TrainerDevice.ConnectionState.CONNECTED, "пустой список — не «подключено»")
	assert_eq(cm.failure_of(ID), SensorDevice.FailureReason.NO_SERVICE)
	assert_false(cm.remembered.has_trainer(), "не запомнен")
	_bridge.emit_error(ID, BleBridge.ErrorCode.SERVICE_NOT_FOUND, "service 1826 not found")
	_bridge.pump()
	assert_ne(cm.state_of(ID), TrainerDevice.ConnectionState.CONNECTED)


# ===========================================================================
# REQ-DEV-10 п.5 — бит 3 2ACC, 80 05 02
# ===========================================================================

## 2ACC: Fitness Machine Features (uint32) + Target Setting Features (uint32), бит 3 — мощность.
static func _features(target_bits: int) -> String:
	return "00 00 00 00 %02X %02X %02X %02X" % [target_bits & 0xFF, (target_bits >> 8) & 0xFF,
		(target_bits >> 16) & 0xFF, (target_bits >> 24) & 0xFF]


func test_req_dev_10_c5_bit3_zero_plan_of_three_steps_no_05() -> void:
	var t := _connect(FULL + ["2ACC"], {"2ACC": _features(0x2004)})  # бит 2 и 13, без бита 3
	assert_true(_bridge.calls_of("read_characteristic").any(func(c: Dictionary) -> bool: return str(c["char"]) == "2ACC"),
		"read_characteristic(2ACC) после подключения")
	assert_false(t.is_erg_available(), "ERG недоступен")
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(5, 150.0), WorkoutStep.watts(5, 250.0),
		WorkoutStep.watts(5, 180.0)] as Array[WorkoutStep]), t, 200)
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		s.tick(1.0)
		_bridge.pump()
	assert_eq(_target_writes(), [] as Array[String], "в журнале нет 0x05")
	assert_false(s.erg_available(), "сессия знает: ERG недоступен")


func test_req_dev_10_c5_bit3_one_erg_available() -> void:
	var t := _connect(FULL + ["2ACC"], {"2ACC": _features(0x0008)})
	assert_true(t.is_erg_available())
	_send(t, 200)
	assert_eq(_target_writes(), ["05 C8 00"])


func test_req_dev_10_c5_80_05_02_no_more_05_and_error_to_user() -> void:
	var t := _connect(FULL)
	var errors: Array[int] = []
	t.error.connect(func(c: int, _m: String) -> void: errors.append(c))
	assert_true(t.is_erg_available(), "без 2ACC — по наличию 2AD9")
	_bridge.fail_next_control_point(FtmsCodec.RESULT_NOT_SUPPORTED)
	_send(t, 200)
	assert_eq(_target_writes().size(), 1)
	assert_has(errors, TrainerDevice.ErrorCode.CONTROL_POINT_REJECTED, "ошибка команды (DEV-02 п.3)")
	assert_false(t.is_erg_available(), "ERG недоступен до конца подключения")
	_send(t, 220)
	_send(t, 240)
	assert_eq(_target_writes().size(), 1, "дальше 0x05 не уходит")


# ===========================================================================
# REQ-DEV-10 п.6, п.7 — диапазон мощности
# ===========================================================================

func test_req_dev_10_c6_range_0_2500_target_2400_unchanged() -> void:
	var t := _connect(FULL + ["2AD8"], {"2AD8": "00 00 C4 09 01 00"})
	assert_true(_bridge.calls_of("read_characteristic").any(func(c: Dictionary) -> bool: return str(c["char"]) == "2AD8"),
		"read_characteristic(2AD8)")
	_send(t, 2400)
	assert_eq(_target_writes().back(), "05 60 09", "2400 Вт уходит как 2400 (п.7 — без констант модели)")


func test_req_dev_10_c6_range_25_1500_step5_bytes() -> void:
	var t := _connect(FULL + ["2AD8"], {"2AD8": "19 00 DC 05 05 00"})
	var want := {10: "05 19 00", 132: "05 82 00", 1600: "05 DC 05", 300: "05 2C 01", 133: "05 87 00", 1498: "05 DC 05"}
	for w in want:
		_send(t, int(w))
		assert_eq(_target_writes().back(), want[w], "цель %d Вт" % w)
	assert_eq(t.applied_target_power(1600), 1500, "applied_target_power — то же значение для сессии")


func test_req_dev_10_c7_without_2ad8_or_unanswered_fallback_0_2000() -> void:
	var t := _connect(FULL)
	_send(t, 2400)
	assert_eq(_target_writes().back(), "05 D0 07", "без 2AD8 — запасной 0..2000")
	var b2 := StubBleBridge.new()
	_disposables.append(b2)
	_fixture(b2, "t2", FULL + ["2AD8"])  # заявлена, но ответа нет
	b2.fail_next_read()
	var t2 := BleTrainer.new(b2)
	_disposables.push_front(t2)
	t2.connect_device("t2")
	for i in 4:
		b2.pump()
		t2.tick(0.1)
	_send(t2, 2400, b2)
	assert_eq(_target_writes(b2).back(), "05 D0 07", "2AD8 не прочитана — запасной диапазон")


func test_req_dev_10_c6_c7_range_of_previous_trainer_not_carried_to_next() -> void:
	var t := _connect(FULL + ["2AD8"], {"2AD8": "19 00 DC 05 05 00"})
	_send(t, 1600)
	assert_eq(_target_writes().back(), "05 DC 05")
	t.disconnect_device()
	_bridge.pump()
	_bridge.read_values.erase("2AD8")
	_fixture(_bridge, "other", FULL)
	t.connect_device("other")
	for i in 4:
		_bridge.pump()
		t.tick(0.1)
	assert_eq(t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	_send(t, 1600)
	assert_eq(_target_writes().back(), "05 40 06", "другой станок без 2AD8 — 1600 в запасном диапазоне, не 1500")


# ===========================================================================
# REQ-DEV-10 п.8 — диапазон сопротивления 2AD6
# ===========================================================================

func test_req_dev_10_c8_resistance_range_0_20_step_1() -> void:
	var t := _connect(FULL + ["2AD6"], {"2AD6": "00 00 C8 00 0A 00"})
	t.set_erg_enabled(false)
	var got: Array[String] = []
	for pct in [50, 100]:
		t.set_resistance_level(pct)
		for i in 4:
			_bridge.pump()
			t.tick(0.3)
		var last := ""
		for w in _bridge.writes_to("2AD9"):
			var b: PackedByteArray = w["bytes"]
			if b.size() > 0 and b[0] == 0x04:
				last = _to_hex(b)
		got.append(last)
	assert_eq(got, ["04 64", "04 C8"], "50 % → 04 64, 100 % → 04 C8")


# ===========================================================================
# REQ-DEV-10 п.2 — одинаковый журнал для разных имён и 0x2A29
# ===========================================================================

func _journal_run(dev_name: String, manufacturer: String) -> Array:
	var b := StubBleBridge.new()
	_disposables.append(b)
	var cm := ConnectionManager.new(b, RememberedDevices.new("user://acc_t161_j_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]))
	cm.set_profile("p")
	_disposables.push_front(cm)
	var svc := {FTMS: PackedStringArray(FULL + ["2AD6", "2AD8"])}
	if manufacturer != "<none>":
		svc["180A"] = PackedStringArray(["2A29"])
		b.set_read_value("2A29", manufacturer.to_utf8_buffer())
	b.set_device_services("dev", svc)
	b.set_read_value("2AD6", _hex("00 00 E8 03 0A 00"))
	b.set_read_value("2AD8", _hex("00 00 D0 07 01 00"))
	cm.scanner.start()
	b.emit_device_found("dev", dev_name, -60, PackedStringArray(["1826"]))
	cm.connect_trainer("dev")
	for i in 4:
		b.pump()
		cm.tick(0.1)
	var t := cm.trainer
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(3, 150.0), WorkoutStep.watts(3, 250.0)] as Array[WorkoutStep]), t, 200)
	s.start()
	for i in 3:
		s.tick(1.0)
		b.pump()
	s.set_erg_enabled(false)
	s.set_resistance_level(60)
	for i in 3:
		s.tick(1.0)
		b.pump()
	var out: Array = []
	for c in b.calls:
		var m := str(c["method"])
		if m in ["start_scan", "stop_scan"]:
			continue
		var e: Dictionary = c.duplicate()
		e.erase("id")
		out.append(e)
	return out


func test_req_dev_10_c2_same_bridge_journal_for_names_and_manufacturer_strings() -> void:
	var base := _journal_run("Tacx Neo 2T", "<none>")
	assert_gt(base.size(), 5)
	for pair in [["KICKR CORE 1A2B", "Wahoo Fitness"], ["SUITO-T", "Tacx"], ["", "Elite"], ["Tacx Neo 2T", ""]]:
		var j := _journal_run(str(pair[0]), str(pair[1]))
		assert_eq(j, base, "журнал «%s» / 2A29 «%s» совпадает с эталоном" % [pair[0], pair[1]])
