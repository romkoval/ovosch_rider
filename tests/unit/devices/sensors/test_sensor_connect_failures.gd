extends GutTest
## T-154: срыв подключения датчика на `StubBleBridge` — три сценария карточки (успех; отказ или
## мгновенный разрыв; нет сервиса датчика), причина срыва (`SensorDevice.FailureReason`),
## устойчивое сравнение UUID и журнал событий подключения (`DiagLog`, категория `ble`).
## REQ-DEV-07 крит. 1 («не подключено» с сообщением), REQ-DEV-03 (без `0x180D` не «подключено»,
## Н-55 (б)), регрессия REQ-DEV-08 крит. 1, REQ-NFR-05 крит. 1.

const ID: String = "AB12CD34-0000-4000-8000-00000000F154"
const NAME: String = "MARQ Aviat"
const SECRET_KEY: String = "fixture-intervals-key-T154-sensors"

var _bridge: StubBleBridge
var _created: Array[SensorDevice] = []
var _dir: String
var _journal: DiagLog


func before_each() -> void:
	_bridge = StubBleBridge.new()
	_created = []
	_dir = "user://test_t154_sensors_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_journal = DiagLog.new(_dir + "logs/")
	assert_eq(_journal.open(), OK)
	var store := MemorySecureStore.new()
	store.set_secret(SecureStore.key_for("p1", SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY), SECRET_KEY)
	_journal.filter().set_store(store)
	DiagLog.install(_journal)


func after_each() -> void:
	for s in _created:
		if s.has_method("dispose"):
			s.call("dispose")
	_created = []
	if _bridge != null:
		_bridge.dispose()
	DiagLog.uninstall(_journal)
	_journal.close()
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


func _hr() -> BleHeartRateSensor:
	var s := BleHeartRateSensor.new(_bridge)
	s.device_name = NAME
	_created.append(s)
	return s


func _track(s: SensorDevice) -> Dictionary:
	var rec := {"states": [] as Array[int], "errors": [] as Array[int], "messages": [] as Array[String]}
	s.connection_state_changed.connect(func(st: int) -> void: (rec["states"] as Array[int]).append(st))
	s.error.connect(func(c: int, m: String) -> void:
		(rec["errors"] as Array[int]).append(c)
		(rec["messages"] as Array[String]).append(m))
	return rec


## Записи журнала категории `ble` (по порядку).
func _ble_records() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line in FileAccess.get_file_as_string(_journal.file_path()).split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary and str(parsed["cat"]) == DiagLog.CAT_BLE:
			out.append(parsed)
	return out


func _events() -> Array[String]:
	var out: Array[String] = []
	for r in _ble_records():
		out.append(str(r["ev"]))
	return out


func _first(ev: String) -> Dictionary:
	for r in _ble_records():
		if str(r["ev"]) == ev:
			return r
	return {}


# ---------------------------------------------------------------------------
# (а) Успех
# ---------------------------------------------------------------------------

func test_a_success_connecting_to_connected_heart_rate_flows_and_log_has_steps() -> void:
	_bridge.set_device_services(ID, {"180D": ["2A37"], "180F": ["2A19"]})
	_bridge.set_read_value("2A19", BatteryCodec.encode_level(80))
	var s := _hr()
	var rec := _track(s)
	var bpm: Array[int] = []
	s.heart_rate.connect(func(b: int) -> void: bpm.append(b))
	s.connect_device(ID)
	_bridge.pump()
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(rec["states"], [TrainerDevice.ConnectionState.CONNECTING, TrainerDevice.ConnectionState.CONNECTED] as Array[int])
	assert_eq(s.last_failure(), SensorDevice.FailureReason.NONE)
	assert_eq((rec["errors"] as Array).size(), 0)
	_bridge.emit_notification(ID, "2A37", PackedByteArray([0x00, 72]))
	assert_eq(bpm, [72] as Array[int], "пульс идёт")
	var events := _events()
	for ev in ["sensor_connect", "sensor_link_up", "sensor_services", "sensor_subscribe", "sensor_state"]:
		assert_true(events.has(ev), "в журнале есть %s: %s" % [ev, str(events)])
	assert_true(events.find("sensor_connect") < events.find("sensor_link_up"))
	assert_true(events.find("sensor_link_up") < events.find("sensor_services"))
	assert_true(events.find("sensor_services") < events.find("sensor_subscribe"))
	var connect := _first("sensor_connect")
	assert_eq(connect["data"]["sensor"], SensorDevice.KIND_HEART_RATE)
	assert_eq(connect["data"]["name"], NAME, "имя устройства в журнале допустимо")
	var services := _first("sensor_services")
	assert_eq(Array(services["data"]["services"]), ["180D", "180F"])
	assert_eq(services["data"]["has_required"], true)
	var last: Dictionary = _ble_records()[-1]
	assert_eq(last["ev"], "sensor_state")
	assert_eq(last["data"]["to"], "connected")


# ---------------------------------------------------------------------------
# (б) Отказ или мгновенный разрыв
# ---------------------------------------------------------------------------

func test_b_refused_connection_failed_error_goes_disconnected_with_reason_and_log_order() -> void:
	var s := _hr()
	var rec := _track(s)
	_bridge.auto_connect = false
	s.connect_device(ID)
	_bridge.emit_error(ID, BleBridge.ErrorCode.CONNECTION_FAILED,
		"CoreBluetooth: connect failed: Peer removed pairing information (CBErrorDomain 14) " + ID)
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED, "REQ-DEV-07 крит. 1")
	assert_eq(rec["errors"], [SensorDevice.ErrorCode.CONNECTION_FAILED] as Array[int], "сообщение передано")
	assert_eq(s.last_failure(), SensorDevice.FailureReason.REFUSED)
	assert_string_contains(s.last_failure_message(), "Peer removed pairing")
	assert_eq(_bridge.calls_of("disconnect_peripheral").size(), 0, "попытка в мосте уже завершена — отмена не нужна")
	# Журнал: попытка → ошибка с кодом → срыв → переход в «не подключено», по порядку.
	var events := _events()
	var i_connect := events.find("sensor_connect")
	var i_error := events.find("sensor_error")
	var i_failed := events.find("sensor_failed")
	var i_state := events.rfind("sensor_state")
	assert_true(i_connect >= 0 and i_connect < i_error and i_error < i_failed and i_failed < i_state, str(events))
	var err := _first("sensor_error")
	assert_eq(err["data"]["code"], "connection_failed")
	assert_string_contains(str(err["data"]["message"]), "Peer removed pairing")
	assert_eq(_first("sensor_failed")["data"]["reason"], "refused")
	var to_state: Dictionary = _ble_records()[i_state]
	assert_eq(to_state["data"]["to"], "disconnected")
	assert_eq(to_state["data"]["reason"], "refused")
	var text := FileAccess.get_file_as_string(_journal.file_path())
	assert_false(text.contains(ID), "id устройства в журнал не пишется (только метка)")


func test_b_bridge_timeout_and_unknown_device_mean_no_response() -> void:
	for code in [BleBridge.ErrorCode.TIMEOUT, BleBridge.ErrorCode.DEVICE_NOT_FOUND]:
		var s := _hr()
		_bridge.auto_connect = false
		s.connect_device(ID)
		_bridge.emit_error(ID, code, "no answer")
		assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED, "код %d" % code)
		assert_eq(s.last_failure(), SensorDevice.FailureReason.NO_RESPONSE, "код %d" % code)
		s.dispose()


func test_b_adapter_unavailable_while_connecting_means_bluetooth_off() -> void:
	var s := _hr()
	_bridge.auto_connect = false
	s.connect_device(ID)
	_bridge.emit_error("", BleBridge.ErrorCode.ADAPTER_UNAVAILABLE, "Bluetooth is unavailable")
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(s.last_failure(), SensorDevice.FailureReason.BLUETOOTH_OFF)


func test_b_own_connect_timeout_means_no_response() -> void:
	var s := _hr()
	_bridge.auto_connect = false
	s.connect_device(ID)
	s.tick(BleSensorBase.CONNECT_TIMEOUT_SEC)
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(s.last_failure(), SensorDevice.FailureReason.NO_RESPONSE)
	assert_eq(_first("sensor_failed")["data"]["reason"], "no_response")


func test_b_link_drop_before_services_is_failure_not_endless_reconnect() -> void:
	var s := _hr()
	var rec := _track(s)
	_bridge.auto_connect = false
	s.connect_device(ID)
	_bridge.emit_connected(ID)  # → discover_services, ответ ещё в очереди
	_bridge.emit_disconnected(ID, BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED, "REQ-DEV-07 крит. 1")
	assert_eq(s.last_failure(), SensorDevice.FailureReason.LINK_LOST)
	assert_eq(rec["errors"], [SensorDevice.ErrorCode.CONNECTION_FAILED] as Array[int])
	_bridge.pump()  # запоздалый services_discovered
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED, "запоздалые сервисы не подключают")
	var attempts := _bridge.calls_of("connect_peripheral").size()
	s.tick(12.0)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), attempts, "переподключения нет — устройство не подключалось")
	var disc := _first("sensor_disconnected")
	assert_eq(disc["data"]["reason"], "link_loss")
	assert_eq(disc["data"]["state"], "connecting")


func test_b_link_drop_timeout_reason_before_services_means_no_response() -> void:
	var s := _hr()
	_bridge.auto_connect = false
	s.connect_device(ID)
	_bridge.emit_disconnected(ID, BleBridge.DisconnectReason.TIMEOUT)
	assert_eq(s.last_failure(), SensorDevice.FailureReason.NO_RESPONSE)


func test_b_not_connected_on_discovery_means_link_lost_and_cancels() -> void:
	var s := _hr()
	_bridge.auto_connect = false
	s.connect_device(ID)
	_bridge.emit_error(ID, BleBridge.ErrorCode.NOT_CONNECTED, "peripheral is not connected")
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(s.last_failure(), SensorDevice.FailureReason.LINK_LOST)
	assert_eq(_bridge.calls_of("disconnect_peripheral").size(), 1, "подключение отменено в мосте")


func test_b_link_drop_right_after_connected_is_reconnecting_with_link_lost_regression_dev_08() -> void:
	_bridge.set_device_services(ID, {"180D": ["2A37"]})
	var s := _hr()
	s.connect_device(ID)
	_bridge.pump()
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	_bridge.auto_connect = false
	_bridge.emit_disconnected(ID, BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING, "REQ-DEV-08 крит. 1")
	assert_eq(s.last_failure(), SensorDevice.FailureReason.LINK_LOST, "причина обрыва сохранена")
	_bridge.auto_connect = true
	s.tick(5.0)
	_bridge.pump()
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(s.last_failure(), SensorDevice.FailureReason.NONE, "подключение сбрасывает причину")


func test_b_reason_kept_until_next_attempt_and_cleared_by_manual_disconnect() -> void:
	var s := _hr()
	_bridge.fail_next_connect()
	s.connect_device(ID)
	_bridge.pump()
	assert_eq(s.last_failure(), SensorDevice.FailureReason.REFUSED)
	s.tick(30.0)
	assert_eq(s.last_failure(), SensorDevice.FailureReason.REFUSED, "держится до следующей попытки")
	_bridge.auto_connect = false
	s.connect_device(ID)
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.CONNECTING)
	assert_eq(s.last_failure(), SensorDevice.FailureReason.NONE, "новая попытка — без старой причины")
	_bridge.emit_error(ID, BleBridge.ErrorCode.CONNECTION_FAILED, "x")
	s.disconnect_device()
	assert_eq(s.last_failure(), SensorDevice.FailureReason.NONE, "ручное отключение снимает причину")


# ---------------------------------------------------------------------------
# (в) Нет сервиса датчика
# ---------------------------------------------------------------------------

func test_c_heart_rate_without_180d_is_not_connected_with_no_service_and_bridge_disconnects() -> void:
	# Часы отдают свои сервисы, но не Heart Rate Service (трансляция пульса выключена).
	_bridge.set_device_services(ID, {"1800": ["2A00"], "180A": ["2A29"], "6A4E2401-667B-11E3-949A-0800200C9A66": ["6A4E2402-667B-11E3-949A-0800200C9A66"]})
	var s := _hr()
	var rec := _track(s)
	s.connect_device(ID)
	_bridge.pump()
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED, "REQ-DEV-03: без 0x180D не «подключено»")
	assert_false((rec["states"] as Array[int]).has(TrainerDevice.ConnectionState.CONNECTED), "CONNECTED не было ни на миг")
	assert_eq(s.last_failure(), SensorDevice.FailureReason.NO_SERVICE)
	assert_eq(rec["errors"], [SensorDevice.ErrorCode.CONNECTION_FAILED] as Array[int])
	assert_eq(_bridge.calls_of("subscribe").size(), 0, "подписок нет")
	assert_eq(_bridge.calls_of("disconnect_peripheral").size(), 1, "мост отключается")
	var svc := _first("sensor_services")
	assert_eq(svc["data"]["has_required"], false)
	assert_eq(svc["data"]["required"], "180D")
	assert_true(Array(svc["data"]["services"]).has("180A"), "список UUID в журнале")
	assert_eq(_first("sensor_failed")["data"]["reason"], "no_service")


func test_c_cadence_and_power_without_own_service_fail_the_same_way() -> void:
	var cases: Array = [[BleCadenceSensor, "1816"], [BlePowerMeter, "1818"]]
	for c in cases:
		var b := StubBleBridge.new()
		b.set_device_services(ID, {"180D": ["2A37"], "180F": ["2A19"]})
		var s: BleSensorBase = (c[0] as GDScript).new(b)
		s.connect_device(ID)
		b.pump()
		assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED, "%s: без %s" % [s.kind(), c[1]])
		assert_eq(s.last_failure(), SensorDevice.FailureReason.NO_SERVICE, s.kind())
		s.dispose()
		b.dispose()


func test_c_service_not_found_error_while_connecting_means_no_service() -> void:
	var s := _hr()
	_bridge.auto_connect = false
	s.connect_device(ID)
	_bridge.emit_error(ID, BleBridge.ErrorCode.SERVICE_NOT_FOUND, "discoverServices failed")
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(s.last_failure(), SensorDevice.FailureReason.NO_SERVICE)


func test_c_empty_service_list_is_unknown_and_still_connects() -> void:
	var s := _hr()
	s.connect_device(ID)
	_bridge.pump()
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "список не получен — не повод отказать")


# ---------------------------------------------------------------------------
# UUID от моста: короткая и полная форма, любой регистр
# ---------------------------------------------------------------------------

func test_full_128_bit_lowercase_service_uuids_are_recognised() -> void:
	var s := _hr()
	s.connect_device(ID)
	_bridge.auto_connect = false
	# Ответ моста подменяется: полный UUID в нижнем регистре (как мог бы отдать другой бэкенд).
	_bridge.pending.clear()
	_bridge.emit_connected(ID)
	_bridge.pending.clear()
	_bridge.services_discovered.emit(ID, {
		"0000180d-0000-1000-8000-00805f9b34fb": PackedStringArray(["00002a37-0000-1000-8000-00805f9b34fb"]),
		"0x180f": PackedStringArray(["2a19"]),
	})
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "0000180d-…-00805f9b34fb == 180D")
	assert_true(s.services.has("180D"))
	assert_true(s.services.has("180F"))
	assert_eq(_bridge.calls_of("read_characteristic").size(), 1, "батарея найдена по 0x180f")


func test_normalized_services_static_helper() -> void:
	var n := BleSensorBase.normalized_services({"0000180D-0000-1000-8000-00805F9B34FB": ["00002A37-0000-1000-8000-00805F9B34FB"], "180f": PackedStringArray(["2a19"])})
	assert_eq(n.keys().size(), 2)
	assert_eq(Array(n["180D"]), ["2A37"])
	assert_eq(Array(n["180F"]), ["2A19"])


# ---------------------------------------------------------------------------
# Журнал: без секретов и без id
# ---------------------------------------------------------------------------

func test_log_has_no_test_secret_and_no_device_id() -> void:
	var s := _hr()
	_bridge.auto_connect = false
	s.connect_device(ID)
	# Сообщение моста по ошибке содержит и секрет, и id устройства.
	_bridge.emit_error(ID, BleBridge.ErrorCode.CONNECTION_FAILED, "failed %s key=%s" % [ID, SECRET_KEY])
	var text := FileAccess.get_file_as_string(_journal.file_path())
	assert_true(text.contains("sensor_failed"))
	assert_false(text.contains(SECRET_KEY), "REQ-NFR-05 крит. 1: секрета в журнале нет")
	assert_false(text.contains(ID), "id устройства заменён меткой")
	var tag: String = _first("sensor_connect")["data"]["dev"]
	assert_eq(tag.length(), BleSensorBase.LOG_DEVICE_TAG_LENGTH)
	assert_eq(tag, ID.sha256_text().substr(0, BleSensorBase.LOG_DEVICE_TAG_LENGTH))


func test_no_log_installed_is_silent() -> void:
	DiagLog.uninstall(_journal)
	var s := _hr()
	_bridge.fail_next_connect()
	s.connect_device(ID)
	_bridge.pump()
	assert_eq(s.last_failure(), SensorDevice.FailureReason.REFUSED, "без журнала логика та же")
