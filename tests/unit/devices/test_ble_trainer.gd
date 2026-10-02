extends GutTest
## Тесты BleTrainer на StubBleBridge (REQ-DEV-02 крит. 1, 3–5; REQ-DEV-08 крит. 1, 3;
## REQ-NFR-01 крит. 2; REQ-WRK-03 крит. 3; REQ-WRK-04 крит. 2).

const DEV: String = "tacx-neo"

var _bridge: StubBleBridge
var _t: BleTrainer
var _states: Array[int] = []
var _errors: Array[Dictionary] = []
var _samples: Array[TrainerSample] = []
var _hr: Array[int] = []


func before_each() -> void:
	_states = []
	_errors = []
	_samples = []
	_hr = []
	_bridge = StubBleBridge.new()
	_t = BleTrainer.new(_bridge)
	_t.connection_state_changed.connect(func(s: int) -> void: _states.append(s))
	_t.error.connect(func(c: int, m: String) -> void: _errors.append({"code": c, "message": m}))
	_t.telemetry.connect(func(s: TrainerSample) -> void: _samples.append(s))
	_t.heart_rate.connect(func(b: int) -> void: _hr.append(b))


func after_each() -> void:
	if _t != null:
		_t.dispose()


## Подключает до CONNECTED (connect → discover → subscribe → Request Control → 80 00 01).
func _connect() -> void:
	_t.connect_device(DEV)
	_bridge.pump()


func _methods() -> Array[String]:
	var out: Array[String] = []
	for c in _bridge.calls:
		out.append(c["method"])
	return out


# ---------------------------------------------------------------------------
# Подключение
# ---------------------------------------------------------------------------

func test_connect_sequence_req_dev_02_c1() -> void:
	_bridge.set_read_value("2AD6", BleBytes.from_hex("00 00 C8 00 0A 00"))
	_t.connect_device(DEV)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTING)
	assert_eq(_bridge.pump(), 6, "connected → services → write_done + индикация CP + 2AD6 + ошибка чтения 2A19")
	var m := _methods()
	assert_eq(m[0], "connect_peripheral")
	assert_eq(m[1], "discover_services")
	assert_eq(m.slice(2, 5), ["subscribe", "subscribe", "subscribe"] as Array[String])
	assert_eq(_bridge.calls[2]["char"], "2AD2")
	assert_eq(_bridge.calls[3]["char"], "2ADA")
	assert_eq(_bridge.calls[4]["char"], "2AD9")
	assert_eq(m[5], "write")
	assert_eq(_bridge.calls[5]["bytes"], PackedByteArray([0x00]), "Request Control после подписок")
	assert_true(_bridge.calls[5]["with_response"])
	assert_eq(m[6], "read_characteristic", "2AD6 читается при неизвестном списке сервисов")
	assert_eq(_bridge.calls[6]["char"], "2AD6")
	assert_eq(m[7], "read_characteristic", "батарея читается при неизвестном списке сервисов")
	assert_eq(_bridge.calls[7]["char"], "2A19")
	assert_eq(m[8], "subscribe")
	assert_eq(_bridge.calls[8]["char"], "2A19")
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_true(_t.control_granted)
	assert_eq(_states, [TrainerDevice.ConnectionState.CONNECTING, TrainerDevice.ConnectionState.CONNECTED] as Array[int])


func test_connected_only_after_request_control_response() -> void:
	_bridge.auto_control_point_response = false
	_t.connect_device(DEV)
	_bridge.pump()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTING, "без 80 00 01 — ещё не CONNECTED")
	assert_false(_t.control_granted)
	_bridge.emit_notification(DEV, "2AD9", BleBytes.from_hex("80 00 01"))
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)


func test_request_control_rejected_is_error_and_disconnect() -> void:
	_bridge.fail_next_control_point(FtmsCodec.RESULT_CONTROL_NOT_PERMITTED)
	_connect()
	assert_eq(_errors.size(), 1)
	assert_eq(_errors[0]["code"], TrainerDevice.ErrorCode.CONTROL_POINT_REJECTED)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(_bridge.calls_of("disconnect_peripheral").size(), 1)
	_bridge.pump()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED, "без переподключения")


func test_resistance_range_read_from_2ad6_and_skipped_when_absent() -> void:
	_bridge.set_read_value("2AD6", BleBytes.from_hex("00 00 C8 00 0A 00"))
	_connect()
	assert_true(_t.resistance_range["ok"])
	assert_almost_eq(_t.resistance_range["max_level"], 20.0, 1e-9)
	# Второй станок без 2AD6 в списке сервисов — чтения нет.
	var b2 := StubBleBridge.new()
	b2.set_device_services("x", {"1826": ["2AD2", "2AD9", "2ADA"]})
	var t2 := BleTrainer.new(b2)
	t2.connect_device("x")
	b2.pump()
	assert_eq(b2.calls_of("read_characteristic").size(), 0)
	assert_eq(t2.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_true(t2.resistance_range.is_empty())


func test_missing_2ad6_read_error_is_not_a_trainer_error() -> void:
	_connect()
	assert_eq(_errors.size(), 0, "CHARACTERISTIC_NOT_FOUND для необязательного чтения — только предупреждение")
	assert_true(_t.resistance_range.is_empty())


func test_connection_failed_goes_disconnected_with_error() -> void:
	_bridge.fail_next_connect()
	_connect()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(_errors[0]["code"], TrainerDevice.ErrorCode.CONNECTION_FAILED)


func test_connect_twice_ignored_and_disconnect_device() -> void:
	_connect()
	_t.connect_device(DEV)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1)
	_t.disconnect_device()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(_bridge.calls_of("disconnect_peripheral").size(), 1)
	_bridge.pump()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	_t.tick(10.0)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1, "по запросу — без переподключения")


func test_events_for_other_device_ignored() -> void:
	_connect()
	_bridge.emit_notification("other", "2AD2", FtmsCodec.encode_indoor_bike_data(30.0, 90.0, 200))
	assert_eq(_samples.size(), 0)
	_bridge.emit_disconnected("other")
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)


# ---------------------------------------------------------------------------
# Команды
# ---------------------------------------------------------------------------

func test_set_target_power_writes_05_fa_00_with_response() -> void:
	_connect()
	_bridge.clear_calls()
	_t.set_target_power(250)
	var w := _bridge.writes_to("2AD9")
	assert_eq(w.size(), 1)
	assert_eq(BleBytes.to_hex(w[0]["bytes"]), "05 FA 00", "REQ-DEV-02 крит. 4")
	assert_true(w[0]["with_response"])
	assert_eq(w[0]["service"], "1826")
	_bridge.pump()
	assert_eq(_errors.size(), 0)


func test_set_target_power_clamped_and_stored_when_not_connected() -> void:
	_t.set_target_power(5000)
	assert_eq(_t.target_power_w, 2000)
	assert_eq(_bridge.calls.size(), 0, "не подключён — на станок ничего")
	_connect()
	_bridge.clear_calls()
	_t.set_target_power(130)
	assert_eq(BleBytes.to_hex(_bridge.writes_to("2AD9")[0]["bytes"]), "05 82 00")


func test_erg_off_writes_resistance_by_default_mapping() -> void:
	_connect()
	_bridge.clear_calls()
	_t.set_resistance_level(50)
	assert_eq(_bridge.writes_to("2AD9").size(), 0, "REQ-WRK-04 крит. 3: в ERG уровень только запоминается")
	_t.set_erg_enabled(false)
	var w := _bridge.writes_to("2AD9")
	assert_eq(w.size(), 1)
	assert_eq(BleBytes.to_hex(w[0]["bytes"]), "04 32", "50 % без 2AD6 → уровень 5.0 → 04 32")
	_t.set_resistance_level(100)
	assert_eq(BleBytes.to_hex(_bridge.writes_to("2AD9")[1]["bytes"]), "04 64")


func test_resistance_uses_2ad6_range_req_wrk_04_c2() -> void:
	_bridge.set_read_value("2AD6", BleBytes.from_hex("00 00 C8 00 0A 00"))  # 0..20.0 шаг 1.0
	_connect()
	_bridge.clear_calls()
	_t.set_erg_enabled(false)
	_t.set_resistance_level(50)
	var w := _bridge.writes_to("2AD9")
	assert_eq(BleBytes.to_hex(w.back()["bytes"]), "04 64", "50 % от 0..20 → 10.0 → 100 единиц")


func test_target_power_outside_erg_applied_when_erg_enabled() -> void:
	_connect()
	_t.set_erg_enabled(false)
	_bridge.clear_calls()
	_t.set_target_power(200)
	assert_eq(_bridge.writes_to("2AD9").size(), 0, "вне ERG цель не пишется")
	_t.set_erg_enabled(true)
	assert_eq(BleBytes.to_hex(_bridge.writes_to("2AD9")[0]["bytes"]), "05 C8 00", "REQ-WRK-03 крит. 3")


func test_control_point_rejection_of_command_is_error() -> void:
	_connect()
	_bridge.fail_next_control_point(FtmsCodec.RESULT_INVALID_PARAMETER)
	_t.set_target_power(250)
	_bridge.pump()
	assert_eq(_errors.size(), 1)
	assert_eq(_errors[0]["code"], TrainerDevice.ErrorCode.CONTROL_POINT_REJECTED, "REQ-DEV-02 крит. 3")
	assert_string_contains(_errors[0]["message"], "invalid_parameter")
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "соединение сохраняется")


func test_write_failure_retried_once_within_same_second() -> void:
	_connect()
	_bridge.clear_calls()
	_bridge.fail_next_write()
	_t.set_target_power(250)
	_bridge.pump()
	var w := _bridge.writes_to("2AD9")
	assert_eq(w.size(), 2, "REQ-NFR-01 крит. 2: один повтор")
	assert_eq(w[1]["bytes"], w[0]["bytes"], "те же байты")
	assert_eq(_errors.size(), 0, "повтор успешен — ошибки нет")


func test_second_write_failure_is_write_failed_error() -> void:
	_connect()
	_bridge.clear_calls()
	_t.set_target_power(100)
	_bridge.pending.clear()
	_bridge.write_done.emit(DEV, "2AD9", false)  # первая неудача → повтор
	assert_eq(_bridge.writes_to("2AD9").size(), 2)
	_bridge.pending.clear()
	_bridge.write_done.emit(DEV, "2AD9", false)  # вторая неудача
	assert_eq(_errors.size(), 1)
	assert_eq(_errors[0]["code"], TrainerDevice.ErrorCode.WRITE_FAILED)
	assert_eq(_bridge.writes_to("2AD9").size(), 2, "третьей попытки нет")
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)


# ---------------------------------------------------------------------------
# Телеметрия
# ---------------------------------------------------------------------------

func test_indoor_bike_data_becomes_trainer_sample_with_flags() -> void:
	_connect()
	_t.tick(12.5)
	_bridge.emit_notification(DEV, "2AD2", FtmsCodec.encode_indoor_bike_data(34.24, 90.5, 250, 72))
	assert_eq(_samples.size(), 1)
	var s := _samples[0]
	assert_true(s.has_power)
	assert_eq(s.power_w, 250)
	assert_true(s.has_cadence)
	assert_eq(s.cadence_rpm, 91, "90.5 → округление до целого")
	assert_true(s.has_speed)
	assert_almost_eq(s.speed_kmh, 34.24, 1e-6)
	assert_almost_eq(s.timestamp_sec, 12.5, 1e-9)
	assert_eq(_hr, [72] as Array[int], "пульс из Indoor Bike Data → heart_rate")


func test_indoor_bike_data_without_speed_and_hr() -> void:
	_connect()
	_bridge.emit_notification(DEV, "2AD2", FtmsCodec.encode_indoor_bike_data(-1.0, 85.0, 200))
	var s := _samples[0]
	assert_false(s.has_speed)
	assert_true(s.has_cadence)
	assert_eq(_hr.size(), 0)
	_bridge.emit_notification(DEV, "2AD2", BleBytes.from_hex("44 00 60"))
	assert_eq(_samples.size(), 1, "обрезанный пакет отброшен")


func test_control_permission_lost_status_requests_control_again() -> void:
	_connect()
	_bridge.clear_calls()
	_bridge.emit_notification(DEV, "2ADA", PackedByteArray([0xFF]))
	assert_false(_t.control_granted)
	assert_eq(_bridge.writes_to("2AD9")[0]["bytes"], PackedByteArray([0x00]))
	_bridge.pump()
	assert_true(_t.control_granted)


# ---------------------------------------------------------------------------
# Переподключение (REQ-DEV-08)
# ---------------------------------------------------------------------------

func test_link_loss_goes_reconnecting_and_retries_every_5s() -> void:
	_connect()
	_bridge.auto_connect = false
	_bridge.clear_calls()
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1, "первая попытка сразу")
	for i in 4:
		_t.tick(1.0)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1)
	_t.tick(1.0)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 2, "через 5 с — вторая")
	for i in 20:
		_t.tick(1.0)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 6, "каждые 5 с без лимита (решение 12)")
	assert_eq(_t.reconnect_attempts(), 6)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING)


func test_reconnect_redoes_discover_subscribe_request_control() -> void:
	_connect()
	_bridge.auto_connect = false
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	_bridge.clear_calls()
	_t.tick(5.0)
	_bridge.emit_connected(DEV)
	_bridge.pump()
	var m := _methods()
	assert_eq(m[0], "connect_peripheral")
	assert_eq(m[1], "discover_services")
	assert_eq(m.slice(2, 5), ["subscribe", "subscribe", "subscribe"] as Array[String])
	assert_eq(_bridge.calls[5]["bytes"], PackedByteArray([0x00]), "Request Control заново")
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_states, [TrainerDevice.ConnectionState.CONNECTING, TrainerDevice.ConnectionState.CONNECTED,
		TrainerDevice.ConnectionState.RECONNECTING, TrainerDevice.ConnectionState.CONNECTED] as Array[int])
	_t.tick(30.0)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1, "после восстановления попытки прекращены")


func test_reconnect_failed_attempt_keeps_reconnecting() -> void:
	_connect()
	_bridge.fail_next_connect()
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	_bridge.pump()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING, "ошибка попытки не роняет в DISCONNECTED")
	assert_eq(_errors.size(), 0)
	_t.tick(5.0)
	_bridge.pump()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)


func test_disconnect_device_during_reconnecting_stops_attempts() -> void:
	_connect()
	_bridge.auto_connect = false
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	_t.disconnect_device()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	var n: int = _bridge.calls_of("connect_peripheral").size()
	_t.tick(20.0)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), n)


func test_commands_during_reconnecting_are_stored_not_written() -> void:
	_connect()
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	_bridge.clear_calls()
	_t.set_target_power(180)
	assert_eq(_bridge.writes_to("2AD9").size(), 0)
	assert_eq(_t.target_power_w, 180, "сессия повторит цель после CONNECTED (REQ-DEV-08 крит. 3)")


# ---------------------------------------------------------------------------
# Фабрика
# ---------------------------------------------------------------------------

func test_factory_create_ble_with_explicit_bridge_and_default_without_native() -> void:
	var dev := TrainerFactory.create_ble(_bridge)
	assert_true(dev is BleTrainer)
	assert_true(dev is TrainerDevice)
	assert_null(TrainerFactory.create(TrainerFactory.KIND_BLE), "без нативного модуля — null, не BleTrainer на заглушке")


func test_ble_trainer_overrides_every_interface_method() -> void:
	var script: Script = BleTrainer as Script
	var own: Array[String] = []
	for m in script.get_script_method_list():
		own.append(m["name"])
	for name in ["connect_device", "disconnect_device", "set_target_power", "set_erg_enabled",
			"set_resistance_level", "get_connection_state", "tick"]:
		assert_true(own.has(name), "BleTrainer переопределяет %s" % name)


func test_battery_read_and_notification_when_service_present() -> void:
	_bridge.set_device_services(DEV, {"1826": ["2AD2", "2AD9", "2ADA"], "180F": ["2A19"]})
	_bridge.set_read_value("2A19", BatteryCodec.encode_level(55))
	var levels: Array[int] = []
	_t.battery_level.connect(func(p: int) -> void: levels.append(p))
	_connect()
	assert_eq(levels, [55] as Array[int], "REQ-DEV-07 крит. 2: read_characteristic(180F, 2A19)")
	assert_eq(_t.battery_percent, 55)
	assert_true(_bridge.is_subscribed(DEV, "180F", "2A19"))
	_bridge.emit_notification(DEV, "2A19", BatteryCodec.encode_level(54))
	assert_eq(_t.battery_percent, 54)


func test_battery_skipped_without_service() -> void:
	_bridge.set_device_services(DEV, {"1826": ["2AD2", "2AD9", "2ADA", "2AD6"]})
	_connect()
	assert_eq(_t.battery_percent, -1, "REQ-DEV-07 крит. 3")
	for c in _bridge.calls:
		assert_ne(str(c.get("char", "")), "2A19", "2A19 не трогаем без 180F")
	assert_eq(_errors.size(), 0)


func test_bridge_error_write_failed_also_retries_once() -> void:
	_connect()
	_bridge.clear_calls()
	_bridge.auto_control_point_response = false
	_t.set_target_power(250)
	_bridge.pending.clear()
	_bridge.emit_error(DEV, BleBridge.ErrorCode.WRITE_FAILED, "write failed")
	assert_eq(_bridge.writes_to("2AD9").size(), 2, "REQ-NFR-01 крит. 2: error(WRITE_FAILED) → один повтор")
	assert_eq(_errors.size(), 0)
	_bridge.pending.clear()
	_bridge.emit_error(DEV, BleBridge.ErrorCode.WRITE_FAILED, "write failed again")
	assert_eq(_bridge.writes_to("2AD9").size(), 2)
	assert_eq(_errors.size(), 1)
	assert_eq(_errors[0]["code"], TrainerDevice.ErrorCode.WRITE_FAILED)
	_bridge.emit_error(DEV, BleBridge.ErrorCode.WRITE_FAILED, "no pending write")
	assert_eq(_errors.size(), 2, "без ожидающей записи — сразу ошибка")


func test_set_erg_enabled_same_value_is_noop_dedup_after_reconnect() -> void:
	_connect()
	_t.set_target_power(130)
	_bridge.pump()
	_bridge.clear_calls()
	_t.set_erg_enabled(true)
	assert_eq(_bridge.writes_to("2AD9").size(), 0, "ERG уже включён — цель не дублируется")
	_t.set_target_power(130)
	assert_eq(_bridge.writes_to("2AD9").size(), 1, "явная цель — пишется")
	_t.set_erg_enabled(false)
	assert_eq(_bridge.writes_to("2AD9").size(), 2, "выключение — уровень")
	_t.set_erg_enabled(false)
	assert_eq(_bridge.writes_to("2AD9").size(), 2, "повтор выключения — no-op")


func test_repeated_link_loss_does_not_restart_reconnect_series() -> void:
	_connect()
	_bridge.auto_connect = false
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	_t.tick(4.0)
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 2, "повторный обрыв не даёт немедленной попытки")
	_t.tick(1.0)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 3, "серия идёт по старому расписанию: 5 с от первой попытки")
	assert_eq(_t.reconnect_attempts(), 2)


func test_dispose_detaches_from_bridge() -> void:
	_connect()
	_t.dispose()
	assert_null(_t.bridge)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	_bridge.emit_notification(DEV, "2AD2", FtmsCodec.encode_indoor_bike_data(30.0, 90.0, 200))
	assert_eq(_samples.size(), 0, "после dispose события моста не доходят")
	_t.set_target_power(100)
	_t.tick(10.0)
	_t.connect_device(DEV)
	_t.dispose()
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1, "методы после dispose — no-op")
