extends GutTest
## Тесты BLE-датчиков на StubBleBridge (REQ-DEV-03 крит. 1, 2; REQ-DEV-04 крит. 1–3;
## REQ-DEV-05 крит. 1, 3; REQ-DEV-07 крит. 2, 3; REQ-DEV-08 крит. 1).

const ID: String = "sensor-1"

var _bridge: StubBleBridge
var _created: Array[SensorDevice] = []


func before_each() -> void:
	_bridge = StubBleBridge.new()
	_created = []


func after_each() -> void:
	for s in _created:
		if s.has_method("dispose"):
			s.call("dispose")
	_created = []
	if _bridge != null:
		_bridge.dispose()


func _connect(sensor: SensorDevice) -> void:
	_created.append(sensor)
	sensor.connect_device(ID)
	_bridge.pump()


# ---------------------------------------------------------------------------
# Общий жизненный цикл
# ---------------------------------------------------------------------------

func test_heart_rate_sensor_connect_sequence_with_battery() -> void:
	_bridge.set_device_services(ID, {"180D": ["2A37"], "180F": ["2A19"]})
	_bridge.set_read_value("2A19", BatteryCodec.encode_level(77))
	var s := BleHeartRateSensor.new(_bridge)
	var levels: Array[int] = []
	s.battery_level.connect(func(p: int) -> void: levels.append(p))
	var states: Array[int] = []
	s.connection_state_changed.connect(func(st: int) -> void: states.append(st))
	_connect(s)
	assert_eq(s.kind(), SensorDevice.KIND_HEART_RATE)
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(states, [TrainerDevice.ConnectionState.CONNECTING, TrainerDevice.ConnectionState.CONNECTED] as Array[int])
	var subs := _bridge.calls_of("subscribe")
	assert_eq(subs.size(), 2)
	assert_eq(subs[0]["service"], "180D")
	assert_eq(subs[0]["char"], "2A37")
	assert_eq(subs[1]["char"], "2A19", "подписка на Battery Level")
	var reads := _bridge.calls_of("read_characteristic")
	assert_eq(reads.size(), 1)
	assert_eq(reads[0]["service"], "180F")
	assert_eq(reads[0]["char"], "2A19", "REQ-DEV-07 крит. 2: read_characteristic(180F, 2A19)")
	assert_eq(levels, [77] as Array[int])
	assert_eq(s.get_battery_level(), 77)
	_bridge.emit_notification(ID, "2A19", BatteryCodec.encode_level(76))
	assert_eq(s.get_battery_level(), 76, "обновление по нотификации")


func test_sensor_without_battery_service_shows_dash_not_error() -> void:
	_bridge.set_device_services(ID, {"180D": ["2A37"]})
	var s := BleHeartRateSensor.new(_bridge)
	var errors: Array[int] = []
	s.error.connect(func(c: int, _m: String) -> void: errors.append(c))
	_connect(s)
	assert_eq(_bridge.calls_of("read_characteristic").size(), 0, "180F нет — не читаем")
	assert_eq(s.get_battery_level(), -1, "REQ-DEV-07 крит. 3: «—»")
	assert_eq(errors.size(), 0)


func test_sensor_unknown_services_tries_battery_and_tolerates_missing() -> void:
	var s := BleCadenceSensor.new(_bridge)
	var errors: Array[int] = []
	s.error.connect(func(c: int, _m: String) -> void: errors.append(c))
	_connect(s)
	assert_eq(_bridge.calls_of("read_characteristic").size(), 1)
	assert_eq(s.get_battery_level(), -1)
	assert_eq(errors.size(), 0, "CHARACTERISTIC_NOT_FOUND не ошибка датчика")
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)


func test_sensor_connection_failed_and_disconnect() -> void:
	var s := BleHeartRateSensor.new(_bridge)
	var errors: Array[int] = []
	s.error.connect(func(c: int, _m: String) -> void: errors.append(c))
	_bridge.fail_next_connect()
	_connect(s)
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(errors, [SensorDevice.ErrorCode.CONNECTION_FAILED] as Array[int])
	_connect(s)
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	s.disconnect_device()
	_bridge.pump()
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	s.tick(10.0)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 2, "по запросу — без переподключения")


func test_sensor_link_loss_reconnects_every_5s_and_resubscribes() -> void:
	var s := BlePowerMeter.new(_bridge)
	_connect(s)
	_bridge.auto_connect = false
	_bridge.clear_calls()
	_bridge.emit_disconnected(ID, BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1)
	for i in 5:
		s.tick(1.0)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 2, "REQ-DEV-08 крит. 1: каждые 5 с")
	assert_eq(s.reconnect_attempts(), 2)
	_bridge.auto_connect = true
	_bridge.clear_calls()
	s.tick(5.0)
	_bridge.pump()
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_bridge.calls_of("subscribe")[0]["char"], "2A63", "подписка заново")
	assert_eq(s.reconnect_attempts(), 0, "серия завершена — счётчик сброшен")


# ---------------------------------------------------------------------------
# HRS
# ---------------------------------------------------------------------------

func test_heart_rate_emitted_for_both_formats_and_contact_ok() -> void:
	var s := BleHeartRateSensor.new(_bridge)
	var bpm: Array[int] = []
	s.heart_rate.connect(func(b: int) -> void: bpm.append(b))
	_connect(s)
	_bridge.emit_notification(ID, "2A37", BleBytes.from_hex("00 48"))
	_bridge.emit_notification(ID, "2A37", BleBytes.from_hex("01 48 00"))
	_bridge.emit_notification(ID, "2A37", BleBytes.from_hex("06 50"))
	assert_eq(bpm, [72, 72, 80] as Array[int], "REQ-DEV-03 крит. 1")
	assert_true(s.contact_ok)
	assert_eq(s.last_bpm, 80)


func test_heart_rate_without_contact_is_no_data() -> void:
	var s := BleHeartRateSensor.new(_bridge)
	var bpm: Array[int] = []
	s.heart_rate.connect(func(b: int) -> void: bpm.append(b))
	_connect(s)
	_bridge.emit_notification(ID, "2A37", BleBytes.from_hex("04 48"))
	assert_eq(bpm.size(), 0, "REQ-DEV-03 крит. 2: нет контакта → не эмитится")
	assert_false(s.contact_ok)
	_bridge.emit_notification(ID, "2A37", BleBytes.from_hex("06 48"))
	assert_eq(bpm, [72] as Array[int])
	assert_true(s.contact_ok)
	_bridge.emit_notification(ID, "2A37", BleBytes.from_hex("01"))
	assert_eq(bpm.size(), 1, "обрезанный пакет игнорируется")


# ---------------------------------------------------------------------------
# CSC
# ---------------------------------------------------------------------------

func test_cadence_sensor_90_rpm_from_two_measurements() -> void:
	var s := BleCadenceSensor.new(_bridge)
	var rpm: Array[int] = []
	s.cadence.connect(func(r: int) -> void: rpm.append(r))
	_connect(s)
	_bridge.emit_notification(ID, "2A5B", CscCodec.encode_crank_measurement(10, 1024))
	assert_eq(rpm.size(), 0, "одного измерения мало")
	s.tick(2.0)
	_bridge.emit_notification(ID, "2A5B", CscCodec.encode_crank_measurement(13, 3072))
	assert_eq(rpm, [90] as Array[int], "REQ-DEV-04 крит. 1")
	s.tick(1.0)
	_bridge.emit_notification(ID, "2A5B", CscCodec.encode_crank_measurement(13, 3072))
	assert_eq(rpm, [90, 90] as Array[int], "повтор измерения без новых оборотов — значение удерживается и переиздаётся (датчик жив)")


func test_cadence_sensor_zero_after_3s_without_revolutions() -> void:
	var s := BleCadenceSensor.new(_bridge)
	var rpm: Array[int] = []
	s.cadence.connect(func(r: int) -> void: rpm.append(r))
	_connect(s)
	_bridge.emit_notification(ID, "2A5B", CscCodec.encode_crank_measurement(10, 1024))
	s.tick(2.0)
	_bridge.emit_notification(ID, "2A5B", CscCodec.encode_crank_measurement(13, 3072))
	var same := CscCodec.encode_crank_measurement(13, 3072)
	s.tick(1.0)
	_bridge.emit_notification(ID, "2A5B", same)
	s.tick(1.9)
	_bridge.emit_notification(ID, "2A5B", same)
	assert_eq(rpm, [90, 90, 90] as Array[int], "пакеты без оборотов < 3 с — держим 90")
	s.tick(0.1)
	_bridge.emit_notification(ID, "2A5B", same)
	assert_eq(rpm, [90, 90, 90, 0] as Array[int], "REQ-DEV-04 крит. 3: пакеты идут, обороты стоят 3 с → 0")
	assert_eq(s.current_cadence(s.get_time_sec()), 0)
	s.tick(5.0)
	assert_eq(rpm.size(), 4, "Н-4: при тишине датчик ничего не испускает")
	assert_eq(s.current_cadence(s.get_time_sec()), -1, "тишина → нет данных")


func test_cadence_sensor_overflow_and_wheel_only_packets() -> void:
	var s := BleCadenceSensor.new(_bridge)
	var rpm: Array[int] = []
	s.cadence.connect(func(r: int) -> void: rpm.append(r))
	_connect(s)
	_bridge.emit_notification(ID, "2A5B", CscCodec.encode_crank_measurement(0xFFFF, 0xFF00))
	s.tick(1.0)
	_bridge.emit_notification(ID, "2A5B", CscCodec.encode_crank_measurement(0x0002, 0x0100))
	assert_eq(rpm, [360] as Array[int], "REQ-DEV-04 крит. 2: переполнение без отрицательных")
	_bridge.emit_notification(ID, "2A5B", BleBytes.from_hex("01 E8 03 00 00 00 08"))
	assert_eq(rpm.size(), 1, "пакет только с колесом — каденс не трогает")


# ---------------------------------------------------------------------------
# CPS
# ---------------------------------------------------------------------------

func test_power_meter_power_and_cadence_from_crank_data() -> void:
	var s := BlePowerMeter.new(_bridge)
	var pw: Array[int] = []
	var rpm: Array[int] = []
	s.power.connect(func(w: int) -> void: pw.append(w))
	s.cadence.connect(func(r: int) -> void: rpm.append(r))
	_connect(s)
	_bridge.emit_notification(ID, "2A63", BleBytes.from_hex("00 00 FA 00"))
	assert_eq(pw, [250] as Array[int], "REQ-DEV-05 крит. 1")
	assert_eq(rpm.size(), 0, "без crank data каденса нет")
	_bridge.emit_notification(ID, "2A63", CpsCodec.encode_cycling_power_measurement(260, 10, 1024))
	s.tick(2.0)
	_bridge.emit_notification(ID, "2A63", CpsCodec.encode_cycling_power_measurement(270, 13, 3072))
	assert_eq(pw, [250, 260, 270] as Array[int])
	assert_eq(rpm, [90] as Array[int], "REQ-DEV-05 крит. 3")
	assert_eq(s.last_power_w, 270)
	s.tick(3.0)
	assert_eq(rpm, [90] as Array[int], "Н-4: тишина — без событий")
	assert_eq(s.current_cadence(s.get_time_sec()), -1)
	_bridge.emit_notification(ID, "2A63", CpsCodec.encode_cycling_power_measurement(270, 13, 3072))
	assert_eq(rpm, [90, 0] as Array[int], "пакет без новых оборотов спустя 3 с → 0")


func test_power_meter_ignores_truncated_and_other_chars() -> void:
	var s := BlePowerMeter.new(_bridge)
	var pw: Array[int] = []
	s.power.connect(func(w: int) -> void: pw.append(w))
	_connect(s)
	_bridge.emit_notification(ID, "2A63", BleBytes.from_hex("00 00 FA"))
	_bridge.emit_notification(ID, "2A37", BleBytes.from_hex("00 48"))
	assert_eq(pw.size(), 0)
	assert_eq(s.kind(), SensorDevice.KIND_POWER)


func test_sensor_dispose_detaches_from_bridge() -> void:
	var s := BleHeartRateSensor.new(_bridge)
	var bpm: Array[int] = []
	s.heart_rate.connect(func(b: int) -> void: bpm.append(b))
	_connect(s)
	s.dispose()
	assert_null(s.bridge)
	_bridge.emit_notification(ID, "2A37", BleBytes.from_hex("00 48"))
	assert_eq(bpm.size(), 0, "после dispose измерения не доходят")
	s.connect_device(ID)
	s.tick(10.0)
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)


# ---------------------------------------------------------------------------
# Регрессии финального ревью (п.5: CONNECTING без тайм-аута)
# ---------------------------------------------------------------------------

func test_sensor_connecting_times_out_after_15s_and_cancels_in_bridge() -> void:
	var s := BleHeartRateSensor.new(_bridge)
	_created.append(s)
	var errors: Array[int] = []
	s.error.connect(func(c: int, _m: String) -> void: errors.append(c))
	_bridge.auto_connect = false
	s.tick(3.0)
	s.connect_device(ID)
	s.tick(14.5)
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.CONNECTING)
	s.tick(0.5)
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED, "REQ-DEV-07 крит. 1")
	assert_eq(errors, [SensorDevice.ErrorCode.CONNECTION_FAILED] as Array[int])
	assert_eq(_bridge.calls_of("disconnect_peripheral").size(), 1, "подключение отменено в мосте")
	_bridge.emit_connected(ID)
	assert_eq(_bridge.calls_of("discover_services").size(), 0, "запоздалый connected игнорируется")


func test_sensor_not_connected_error_in_connecting_disconnects() -> void:
	var s := BleCadenceSensor.new(_bridge)
	_created.append(s)
	var errors: Array[int] = []
	s.error.connect(func(c: int, _m: String) -> void: errors.append(c))
	_bridge.auto_connect = false
	s.connect_device(ID)
	_bridge.emit_error(ID, BleBridge.ErrorCode.NOT_CONNECTED, "peripheral is not connected")
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(errors, [SensorDevice.ErrorCode.CONNECTION_FAILED] as Array[int])
	assert_eq(_bridge.calls_of("disconnect_peripheral").size(), 1)
