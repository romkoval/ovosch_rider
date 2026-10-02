extends GutTest
## Тесты контракта BleBridge, заглушки StubBleBridge и обёртки NativeBleBridge
## (REQ-DEV-01..08 контракт, REQ-NFR-06 крит. 1, 5, REQ-DEV-07 крит. 2, REQ-WRK-04 крит. 2).

const DEV: String = "tacx-1"

var _stub: StubBleBridge
var _events: Array[Dictionary] = []


func before_each() -> void:
	_events = []
	_stub = StubBleBridge.new()
	_stub.adapter_state_changed.connect(func(s: int) -> void: _events.append({"sig": "adapter", "state": s}))
	_stub.device_found.connect(func(id: String, n: String, rssi: int, svc: PackedStringArray) -> void:
		_events.append({"sig": "found", "id": id, "name": n, "rssi": rssi, "services": svc}))
	_stub.connected.connect(func(id: String) -> void: _events.append({"sig": "connected", "id": id}))
	_stub.disconnected.connect(func(id: String, r: int) -> void: _events.append({"sig": "disconnected", "id": id, "reason": r}))
	_stub.services_discovered.connect(func(id: String, s: Dictionary) -> void: _events.append({"sig": "services", "id": id, "services": s}))
	_stub.notification.connect(func(id: String, c: String, b: PackedByteArray) -> void: _events.append({"sig": "notify", "id": id, "char": c, "bytes": b}))
	_stub.characteristic_read.connect(func(id: String, c: String, b: PackedByteArray) -> void: _events.append({"sig": "read", "id": id, "char": c, "bytes": b}))
	_stub.write_done.connect(func(id: String, c: String, ok: bool) -> void: _events.append({"sig": "write_done", "id": id, "char": c, "ok": ok}))
	_stub.error.connect(func(id: String, code: int, m: String) -> void: _events.append({"sig": "error", "id": id, "code": code, "message": m}))


func _of(sig: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _events:
		if e["sig"] == sig:
			out.append(e)
	return out


# ---------------------------------------------------------------------------
# Контракт и фабрика
# ---------------------------------------------------------------------------

func test_stub_overrides_every_contract_method() -> void:
	var base_methods: Array[String] = ["is_available", "start_scan", "stop_scan", "connect_peripheral",
		"disconnect_peripheral", "discover_services", "subscribe", "unsubscribe", "write",
		"read_characteristic", "get_adapter_state"]
	var stub_script: Script = StubBleBridge
	var native_script: Script = NativeBleBridge
	for m in base_methods:
		assert_true(stub_script.get_script_method_list().any(func(d: Dictionary) -> bool: return d["name"] == m),
			"StubBleBridge переопределяет %s" % m)
		assert_true(native_script.get_script_method_list().any(func(d: Dictionary) -> bool: return d["name"] == m),
			"NativeBleBridge переопределяет %s" % m)


func test_contract_signals_exist() -> void:
	var b := BleBridge.new()
	for s in ["adapter_state_changed", "device_found", "connected", "disconnected", "services_discovered",
			"notification", "characteristic_read", "write_done", "error"]:
		assert_true(b.has_signal(s), "сигнал %s" % s)
	assert_false(b.is_available(), "базовый контракт сам по себе недоступен")
	assert_true(_stub is BleBridge)
	assert_true(_stub.is_available())


func test_native_bridge_unavailable_without_gdextension() -> void:
	assert_false(NativeBleBridge.is_native_available(), "в headless-контейнере GDExtension OvoschBle нет")
	var n := NativeBleBridge.new()
	assert_false(n.is_available())
	assert_eq(n.get_adapter_state(), BleBridge.AdapterState.UNSUPPORTED)
	var errors: Array[Dictionary] = []
	n.error.connect(func(id: String, code: int, m: String) -> void: errors.append({"id": id, "code": code, "m": m}))
	n.start_scan(BleUuids.SCAN_SERVICES)
	n.connect_peripheral(DEV)
	n.write(DEV, "1826", "2AD9", FtmsCodec.encode_request_control(), true)
	n.read_characteristic(DEV, "180F", "2A19")
	assert_eq(errors.size(), 4, "каждый вызов без модуля — error(ADAPTER_UNAVAILABLE), без падения")
	assert_eq(errors[1]["code"], BleBridge.ErrorCode.ADAPTER_UNAVAILABLE)
	assert_eq(errors[1]["id"], DEV)


func test_create_default_falls_back_to_stub() -> void:
	var b := BleBridge.create_default()
	assert_not_null(b)
	assert_true(b is StubBleBridge, "без нативного модуля — заглушка (REQ-NFR-06 крит. 1: выбор только здесь)")
	assert_true(b.is_available())
	assert_eq(BleBridge.adapter_state_name(BleBridge.AdapterState.POWERED_ON), "powered_on")
	assert_eq(BleBridge.adapter_state_name(99), "unknown")


# ---------------------------------------------------------------------------
# Сканирование, подключение
# ---------------------------------------------------------------------------

func test_scan_logs_service_filter_and_device_found_is_scripted() -> void:
	_stub.start_scan(BleUuids.SCAN_SERVICES)
	assert_true(_stub.scanning)
	var calls := _stub.calls_of("start_scan")
	assert_eq(calls.size(), 1)
	assert_eq(calls[0]["service_uuids"], PackedStringArray(["1826", "180D", "1816", "1818"]), "REQ-DEV-01 крит. 1")
	_stub.emit_device_found(DEV, "Tacx Neo 2T", -60, PackedStringArray(["1826"]))
	assert_eq(_of("found").size(), 1)
	assert_eq(_of("found")[0]["rssi"], -60)
	_stub.stop_scan()
	assert_false(_stub.scanning)
	assert_eq(_stub.calls.back()["method"], "stop_scan")


func test_connect_is_async_until_pump() -> void:
	_stub.connect_peripheral(DEV)
	assert_eq(_of("connected").size(), 0, "ответ приходит асинхронно")
	assert_eq(_stub.pending.size(), 1)
	assert_eq(_stub.pump(), 1)
	assert_eq(_of("connected").size(), 1)
	assert_eq(_of("connected")[0]["id"], DEV)
	assert_true(_stub.connected_ids.has(DEV))
	_stub.disconnect_peripheral(DEV)
	_stub.pump()
	assert_eq(_of("disconnected")[0]["reason"], BleBridge.DisconnectReason.REQUESTED)
	assert_false(_stub.connected_ids.has(DEV))


func test_fail_next_connect_emits_error_once() -> void:
	_stub.fail_next_connect()
	_stub.connect_peripheral(DEV)
	_stub.pump()
	assert_eq(_of("connected").size(), 0)
	assert_eq(_of("error").size(), 1)
	assert_eq(_of("error")[0]["code"], BleBridge.ErrorCode.CONNECTION_FAILED)
	_stub.connect_peripheral(DEV)
	_stub.pump()
	assert_eq(_of("connected").size(), 1, "следующая попытка успешна")


func test_auto_connect_off_lets_test_control_connected() -> void:
	_stub.auto_connect = false
	_stub.connect_peripheral(DEV)
	assert_eq(_stub.pump(), 0)
	_stub.emit_connected(DEV)
	assert_eq(_of("connected").size(), 1)
	_stub.emit_disconnected(DEV)
	assert_eq(_of("disconnected")[0]["reason"], BleBridge.DisconnectReason.LINK_LOSS, "обрыв по умолчанию")


func test_discover_services_returns_configured_services_normalized() -> void:
	_stub.set_device_services(DEV, {"1826": ["2ad2", "2AD9", "2ADA", "2AD6"], "0000180f-0000-1000-8000-00805f9b34fb": ["2A19"]})
	_stub.discover_services(DEV)
	_stub.pump()
	var s: Dictionary = _of("services")[0]["services"]
	assert_true(s.has("1826"))
	assert_true(s.has("180F"), "полный UUID нормализован к короткому")
	assert_eq(s["1826"], PackedStringArray(["2AD2", "2AD9", "2ADA", "2AD6"]))
	_stub.discover_services("unknown")
	_stub.pump()
	assert_eq((_of("services")[1]["services"] as Dictionary).size(), 0, "неизвестное устройство — пустой список")


func test_subscribe_and_unsubscribe_tracked() -> void:
	_stub.subscribe(DEV, "1826", "2ad2")
	_stub.subscribe(DEV, "1826", "2AD9")
	_stub.subscribe(DEV, "1826", "2AD9")
	assert_true(_stub.is_subscribed(DEV, "1826", "2AD2"))
	assert_true(_stub.is_subscribed(DEV, "1826", "2AD9"))
	assert_eq((_stub.subscriptions[DEV] as Array).size(), 2, "повторная подписка не дублируется")
	assert_eq(_stub.calls_of("subscribe").size(), 3)
	assert_eq(_stub.calls_of("subscribe")[0]["char"], "2AD2", "в журнале UUID нормализован")
	_stub.unsubscribe(DEV, "1826", "2AD2")
	assert_false(_stub.is_subscribed(DEV, "1826", "2AD2"))
	_stub.emit_disconnected(DEV)
	assert_false(_stub.is_subscribed(DEV, "1826", "2AD9"), "обрыв сбрасывает подписки")


# ---------------------------------------------------------------------------
# Запись, Control Point, чтение
# ---------------------------------------------------------------------------

func test_write_logs_bytes_and_reports_done() -> void:
	var bytes := FtmsCodec.encode_set_target_power(250)
	_stub.write(DEV, "1826", "2AD9", bytes, true)
	var w := _stub.writes_to("2ad9")
	assert_eq(w.size(), 1)
	assert_eq(w[0]["bytes"], PackedByteArray([0x05, 0xFA, 0x00]))
	assert_true(w[0]["with_response"])
	assert_eq(w[0]["service"], "1826")
	_stub.pump()
	var done := _of("write_done")
	assert_eq(done.size(), 1)
	assert_true(done[0]["ok"])
	assert_eq(done[0]["char"], "2AD9")


func test_control_point_write_gets_0x80_indication_with_success() -> void:
	_stub.write(DEV, "1826", "2AD9", FtmsCodec.encode_set_target_power(250), true)
	_stub.pump()
	var n := _of("notify")
	assert_eq(n.size(), 1)
	assert_eq(n[0]["char"], "2AD9")
	assert_eq(BleBytes.to_hex(n[0]["bytes"]), "80 05 01", "REQ-DEV-02 крит. 3: 0x80 opcode result")
	var resp := FtmsCodec.decode_control_point_response(n[0]["bytes"])
	assert_true(resp["success"])
	assert_eq(resp["request_opcode"], FtmsCodec.OP_SET_TARGET_POWER)


func test_fail_next_control_point_gives_error_result_once() -> void:
	_stub.fail_next_control_point(FtmsCodec.RESULT_CONTROL_NOT_PERMITTED)
	_stub.write(DEV, "1826", "2AD9", FtmsCodec.encode_request_control(), true)
	_stub.write(DEV, "1826", "2AD9", FtmsCodec.encode_set_target_power(100), true)
	_stub.pump()
	var n := _of("notify")
	assert_eq(n.size(), 2)
	assert_eq(BleBytes.to_hex(n[0]["bytes"]), "80 00 05")
	assert_eq(BleBytes.to_hex(n[1]["bytes"]), "80 05 01", "следующая команда — успех")
	assert_true(_of("write_done")[0]["ok"], "транспортная запись при этом успешна")


func test_fail_next_write_gives_write_done_false_and_no_indication() -> void:
	_stub.fail_next_write()
	_stub.write(DEV, "1826", "2AD9", FtmsCodec.encode_set_target_power(100), true)
	_stub.pump()
	assert_false(_of("write_done")[0]["ok"], "REQ-NFR-01 крит. 2: write_result = false")
	assert_eq(_of("notify").size(), 0, "станок не ответил на неудавшуюся запись")


func test_non_control_point_write_has_no_indication() -> void:
	_stub.write(DEV, "180D", "2A39", PackedByteArray([0x01]), false)
	_stub.pump()
	assert_eq(_of("write_done").size(), 1)
	assert_eq(_of("notify").size(), 0)
	_stub.auto_control_point_response = false
	_stub.write(DEV, "1826", "2AD9", FtmsCodec.encode_request_control(), true)
	_stub.pump()
	assert_eq(_of("notify").size(), 0, "авто-ответ выключен")


func test_read_characteristic_battery_level_and_resistance_range() -> void:
	_stub.set_read_value("2A19", BatteryCodec.encode_level(85))
	_stub.set_read_value("2ad6", BleBytes.from_hex("00 00 C8 00 0A 00"))
	_stub.read_characteristic(DEV, "180F", "2A19")
	_stub.read_characteristic(DEV, "1826", "2AD6")
	assert_eq(_of("read").size(), 0, "REQ-NFR-06 крит. 5: ответ асинхронно")
	assert_eq(_stub.calls_of("read_characteristic").size(), 2, "вызов журналируется")
	assert_eq(_stub.calls_of("read_characteristic")[0]["service"], "180F")
	_stub.pump()
	var reads := _of("read")
	assert_eq(reads.size(), 2)
	assert_eq(reads[0]["char"], "2A19")
	assert_eq(BatteryCodec.decode_level(reads[0]["bytes"])["level_pct"], 85, "REQ-DEV-07 крит. 2")
	assert_eq(reads[1]["char"], "2AD6")
	assert_almost_eq(FtmsCodec.decode_resistance_range(reads[1]["bytes"])["max_level"], 20.0, 1e-9, "REQ-WRK-04 крит. 2")


func test_read_unknown_characteristic_is_error_not_crash() -> void:
	_stub.read_characteristic(DEV, "180F", "2A19")
	_stub.pump()
	assert_eq(_of("read").size(), 0)
	assert_eq(_of("error").size(), 1)
	assert_eq(_of("error")[0]["code"], BleBridge.ErrorCode.CHARACTERISTIC_NOT_FOUND, "REQ-DEV-07 крит. 3: нет сервиса — не падение")
	_stub.set_read_value("2A19", BatteryCodec.encode_level(50))
	_stub.fail_next_read()
	_stub.read_characteristic(DEV, "180F", "2A19")
	_stub.pump()
	assert_eq(_of("error")[1]["code"], BleBridge.ErrorCode.READ_FAILED)


func test_notification_and_adapter_state_helpers() -> void:
	_stub.emit_notification(DEV, "2ad2", FtmsCodec.encode_indoor_bike_data(34.24, 90.0, 250))
	assert_eq(_of("notify")[0]["char"], "2AD2")
	assert_eq(FtmsCodec.decode_indoor_bike_data(_of("notify")[0]["bytes"])["power_w"], 250)
	_stub.emit_characteristic_read(DEV, "2a19", PackedByteArray([42]))
	assert_eq(_of("read")[0]["char"], "2A19")
	_stub.emit_error(DEV, BleBridge.ErrorCode.TIMEOUT, "t/o")
	assert_eq(_of("error")[0]["code"], BleBridge.ErrorCode.TIMEOUT)
	assert_eq(_stub.get_adapter_state(), BleBridge.AdapterState.POWERED_ON)
	_stub.set_adapter_state(BleBridge.AdapterState.POWERED_OFF)
	_stub.set_adapter_state(BleBridge.AdapterState.POWERED_OFF)
	assert_eq(_of("adapter").size(), 1, "повтор того же состояния не эмитится")
	assert_eq(_stub.get_adapter_state(), BleBridge.AdapterState.POWERED_OFF)


func test_pump_delivers_events_queued_during_pump_and_clear_calls() -> void:
	_stub.connected.connect(func(id: String) -> void: _stub.discover_services(id))
	_stub.connect_peripheral(DEV)
	assert_eq(_stub.pump(), 2, "services_discovered, поставленный внутри обработчика connected, тоже доставлен")
	assert_eq(_of("services").size(), 1)
	assert_eq(_stub.pending.size(), 0)
	_stub.clear_calls()
	assert_eq(_stub.calls.size(), 0)


func test_ftms_connect_sequence_req_dev_02_c1_can_be_verified_on_stub() -> void:
	# Имитируем то, что сделает BleTrainer (T-017): подписки и Request Control после connected.
	_stub.connected.connect(func(id: String) -> void:
		_stub.subscribe(id, "1826", "2AD2")
		_stub.subscribe(id, "1826", "2ADA")
		_stub.subscribe(id, "1826", "2AD9")
		_stub.write(id, "1826", "2AD9", FtmsCodec.encode_request_control(), true))
	_stub.connect_peripheral(DEV)
	_stub.pump()
	var methods: Array[String] = []
	for c in _stub.calls:
		methods.append(c["method"])
	assert_eq(methods, ["connect_peripheral", "subscribe", "subscribe", "subscribe", "write"] as Array[String])
	assert_eq(_stub.calls[1]["char"], "2AD2")
	assert_eq(_stub.calls[2]["char"], "2ADA")
	assert_eq(_stub.calls[3]["char"], "2AD9")
	assert_eq(_stub.calls[4]["bytes"], PackedByteArray([0x00]))
	assert_eq(BleBytes.to_hex(_of("notify")[0]["bytes"]), "80 00 01", "станок подтвердил Request Control")
