extends GutTest
## T-165: модель экрана «BLE-отладка» на заглушке моста (инструмент для REQ-DEV-01, REQ-DEV-02,
## REQ-DEV-03, REQ-DEV-07): скан без фильтра и с фильтром приложения, накопление UUID рекламы,
## connect → discover_services → дерево с именами, чтение, подписка, запись hex и пресеты
## (байты — в журнале вызовов заглушки), расшифровка значений, журнал событий и ошибки.

const NEO: String = "NEO-ID-11565"
const QUARQ: String = "QUARQ-ID"
const FEC_SERVICE: String = "6E40FEC1-B5A3-F393-E0A9-E50E24DCCA9E"
const FEC_NOTIFY: String = "6E40FEC2-B5A3-F393-E0A9-E50E24DCCA9E"
const FEC_WRITE: String = "6E40FEC3-B5A3-F393-E0A9-E50E24DCCA9E"

var _bridge: StubBleBridge
var _model: BleDebugModel
var _now: float = 1_000_000.0


func before_each() -> void:
	_now = 1_000_000.0
	_bridge = StubBleBridge.new()
	_model = BleDebugModel.new(_bridge)
	_model.clock = _clock
	_model.utc_offset_sec = 0


func after_each() -> void:
	_model.dispose(false)
	_bridge.dispose()


func _clock() -> float:
	return _now


## Сервисы Tacx Neo 11565 из журнала владельца (2026-10-05): FTMS нет.
func _neo_services() -> Dictionary:
	return {
		"180A": ["2A29", "2A24", "2A26", "2A28"],
		"1816": ["2A5B", "2A5C"],
		"1818": ["2A63", "2A65"],
		"669AA501-0C08-969E-E211-86AD5062675F": ["669AA502-0C08-969E-E211-86AD5062675F"],
		FEC_SERVICE: [FEC_NOTIFY, FEC_WRITE],
	}


func _connect_neo(services: Dictionary = {}) -> void:
	_bridge.set_device_services(NEO, services if not services.is_empty() else _neo_services())
	_model.start_scan()
	_bridge.emit_device_found(NEO, "Tacx Neo 11565", -55, PackedStringArray(["1816"]))
	_model.connect_device(NEO)
	_bridge.pump()


# ---------------------------------------------------------------------------
# Сканирование
# ---------------------------------------------------------------------------

func test_scan_without_filter_by_default_and_with_app_filter_on_toggle() -> void:
	assert_true(_model.start_scan())
	var scans := _bridge.calls_of("start_scan")
	assert_eq(scans.size(), 1)
	assert_eq(Array(scans[0]["service_uuids"]), [], "пустой фильтр — все устройства")
	_model.set_use_app_filter(true)
	scans = _bridge.calls_of("start_scan")
	assert_eq(scans.size(), 2, "идущий скан перезапущен с фильтром")
	assert_eq(Array(scans[1]["service_uuids"]), Array(BleUuids.SCAN_SERVICES))
	_model.stop_scan()
	assert_false(_bridge.scanning)
	assert_false(_model.scanning)


func test_unavailable_bridge_does_not_scan_and_logs() -> void:
	_bridge.set_available(false)
	assert_false(_model.start_scan())
	assert_eq(_bridge.calls_of("start_scan").size(), 0)
	assert_eq(_model.entries_of("scan_unavailable").size(), 1)


func test_devices_accumulate_union_of_advertised_uuids_and_kind() -> void:
	_model.start_scan()
	var full_csc := "00001816-0000-1000-8000-00805f9b34fb"
	_bridge.emit_device_found(NEO, "Tacx Neo 11565", -60, PackedStringArray([full_csc]))
	var d := _model.device(NEO)
	assert_eq(Array(d["raw"]), [full_csc], "UUID как пришли")
	assert_eq(Array(d["norm"]), ["1816"], "нормализованные")
	assert_eq(d["kind"], RememberedDevices.KIND_CADENCE)
	_now += 0.2
	_bridge.emit_device_found(NEO, "", -50, PackedStringArray(["1818", "1826"]))
	d = _model.device(NEO)
	assert_eq(d["name"], "Tacx Neo 11565", "пустое имя не затирает известное")
	assert_eq(int(d["rssi"]), -50)
	assert_eq(Array(d["norm"]), ["1818", "1826"], "последний пакет")
	assert_eq(Array(d["union"]), ["1816", "1818", "1826"], "объединение за сеанс")
	assert_eq(d["kind"], RememberedDevices.KIND_TRAINER, "тип по объединению — BleScanner.kind_from_services")
	assert_eq(int(d["packets"]), 2)
	_bridge.emit_device_found(QUARQ, "Quarq", -70, PackedStringArray(["1818"]))
	assert_eq(_model.device_ids(), [NEO, QUARQ] as Array[String], "по убыванию RSSI")
	_model.start_scan()
	assert_eq(_model.devices.size(), 0, "новый сеанс скана — список заново")


func test_device_found_is_logged_at_most_once_per_second_unless_new_uuids() -> void:
	_model.start_scan()
	for i in 5:
		_bridge.emit_device_found(NEO, "Neo", -60, PackedStringArray(["1816"]))
		_now += 0.1
	assert_eq(_model.entries_of("device_found").size(), 1, "5 пакетов за 0.5 с — одна запись")
	_bridge.emit_device_found(NEO, "Neo", -60, PackedStringArray(["FE59"]))
	assert_eq(_model.entries_of("device_found").size(), 2, "новый UUID — запись сразу")
	_now += 1.0
	_bridge.emit_device_found(NEO, "Neo", -60, PackedStringArray(["1816"]))
	assert_eq(_model.entries_of("device_found").size(), 3, "через секунду — снова")
	var text: String = _model.entries_of("device_found")[2]["text"]
	assert_string_contains(text, NEO, "полный id в журнале экрана")
	assert_string_contains(text, "union [1816, FE59]")


func test_events_after_stop_scan_are_ignored() -> void:
	_model.start_scan()
	_model.stop_scan()
	_bridge.emit_device_found(NEO, "Neo", -60, PackedStringArray(["1816"]))
	assert_eq(_model.devices.size(), 0)


# ---------------------------------------------------------------------------
# Подключение и дерево
# ---------------------------------------------------------------------------

func test_connect_discovers_services_and_builds_named_tree() -> void:
	_connect_neo()
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1)
	assert_eq(_bridge.calls_of("discover_services").size(), 1, "после connected — discover_services")
	assert_eq(_bridge.calls_of("discover_services")[0]["id"], NEO)
	assert_true(_model.is_ready())
	assert_eq(_model.link_state, BleDebugModel.LinkState.READY)
	var tree := _model.service_tree()
	assert_eq(tree.size(), 5)
	var by_uuid: Dictionary = {}
	for s in tree:
		by_uuid[s["uuid"]] = s
	assert_eq(by_uuid["180A"]["name"], "Device Information")
	assert_eq(by_uuid["1818"]["name"], "Cycling Power")
	assert_eq(by_uuid["1816"]["name"], "Cycling Speed and Cadence")
	assert_eq(by_uuid[FEC_SERVICE]["name"], "FE-C over BLE")
	assert_eq(by_uuid["669AA501-0C08-969E-E211-86AD5062675F"]["name"], "", "неизвестный — как есть")
	var fec_chars: Array = by_uuid[FEC_SERVICE]["chars"]
	assert_eq(fec_chars[0]["uuid"], FEC_NOTIFY)
	assert_eq(fec_chars[0]["name"], "FE-C notify (FEC2)")
	assert_eq(fec_chars[1]["name"], "FE-C write (FEC3)")
	assert_eq(BleDebugModel.char_name("2AD2"), "Indoor Bike Data")
	assert_eq(BleDebugModel.char_name("2AD9"), "Fitness Machine Control Point")
	for c in ["2AD2", "2AD9", "2ADA", "2ACC", "2AD8", "2AD6", "2AD5", "2A63", "2A5B", "2A37", "2A19"]:
		assert_false(BleDebugModel.char_name(c).is_empty(), "имя %s" % c)
	assert_eq(_model.service_of(FEC_WRITE), FEC_SERVICE)
	var services_log: String = _model.entries_of("services_discovered")[0]["text"]
	assert_string_contains(services_log, "180A (Device Information)")
	assert_string_contains(services_log, FEC_SERVICE)


func test_disconnect_and_link_loss() -> void:
	_connect_neo()
	_model.disconnect_device()
	assert_eq(_bridge.calls_of("disconnect_peripheral").size(), 1)
	assert_eq(_model.link_state, BleDebugModel.LinkState.IDLE)
	_bridge.pump()
	assert_string_contains(_model.entries_of("disconnected")[0]["text"], "reason requested")
	_connect_neo()
	_bridge.emit_disconnected(NEO, BleBridge.DisconnectReason.LINK_LOSS)
	assert_false(_model.is_ready())
	assert_string_contains(_model.entries_of("disconnected")[1]["text"], "reason link_loss")


func test_connection_failure_returns_to_idle_and_logs_error_code() -> void:
	_model.start_scan()
	_bridge.emit_device_found(NEO, "Neo", -60, PackedStringArray(["1816"]))
	_bridge.fail_next_connect()
	_model.connect_device(NEO)
	_bridge.pump()
	assert_eq(_model.link_state, BleDebugModel.LinkState.IDLE)
	var err: Dictionary = _model.entries_of("error")[0]
	assert_string_contains(err["text"], "code %d CONNECTION_FAILED" % BleBridge.ErrorCode.CONNECTION_FAILED)


func test_actions_without_connection_are_rejected_and_logged() -> void:
	assert_false(_model.read("180A", "2A26"))
	assert_false(_model.write_preset(BleDebugModel.PRESET_FTMS_START))
	assert_eq(_bridge.calls_of("write").size(), 0)
	assert_eq(_model.entries_of("action_rejected").size(), 2)


# ---------------------------------------------------------------------------
# Характеристики
# ---------------------------------------------------------------------------

func test_read_device_information_strings() -> void:
	_connect_neo()
	_bridge.set_read_value("2A26", "4.2.1".to_utf8_buffer())
	_bridge.set_read_value("2A24", "NEO 2T".to_utf8_buffer())
	_bridge.set_read_value("2A29", "Tacx".to_utf8_buffer())
	_bridge.set_read_value("2A28", "1.0".to_utf8_buffer())
	assert_eq(_model.read_device_info(), 4)
	_bridge.pump()
	assert_eq(_bridge.calls_of("read_characteristic").size(), 4)
	var fw := _model.value_of("2A26")
	assert_eq(fw["source"], "read")
	assert_eq(fw["decoded"], "\"4.2.1\"")
	assert_eq(_model.value_of("2A24")["decoded"], "\"NEO 2T\"")
	assert_eq(_model.entries_of("characteristic_read").size(), 4)


func test_read_error_is_logged() -> void:
	_connect_neo()
	_bridge.fail_next_read()
	assert_true(_model.read("180A", "2A26"))
	_bridge.pump()
	assert_string_contains(_model.entries_of("error")[0]["text"], "READ_FAILED")


func test_subscribe_unsubscribe_and_notification_values_with_decoding() -> void:
	_connect_neo()
	assert_true(_model.set_subscribed("1818", "2A63", true))
	assert_true(_bridge.is_subscribed(NEO, "1818", "2A63"))
	assert_true(_model.is_subscribed("1818", "2A63"))
	_now += 0.5
	_bridge.emit_notification(NEO, "2A63", CpsCodec.encode_cycling_power_measurement(150))
	var v := _model.value_of("2A63")
	assert_eq(v["source"], "notify")
	assert_eq(v["hex"], BleBytes.to_hex(CpsCodec.encode_cycling_power_measurement(150)))
	assert_string_contains(str(v["decoded"]), "power 150 W")
	assert_eq(v["time"], "13:46:40.500", "метка времени с миллисекундами")
	assert_true(_model.set_subscribed("1818", "2A63", false))
	assert_false(_bridge.is_subscribed(NEO, "1818", "2A63"))
	assert_eq(_bridge.calls_of("unsubscribe").size(), 1)
	assert_eq(_model.entries_of("notification").size(), 1)


func test_codecs_decode_ftms_csc_hr_battery() -> void:
	assert_string_contains(BleDebugModel.decode("2AD2", FtmsCodec.encode_indoor_bike_data(30.0, 90.0, 200)), "power 200 W")
	assert_string_contains(BleDebugModel.decode("2A5B", CscCodec.encode_crank_measurement(10, 2048)), "crank 10 @ 2048")
	assert_string_contains(BleDebugModel.decode("2A37", HrsCodec.encode_heart_rate_measurement(142)), "HR 142 bpm")
	assert_eq(BleDebugModel.decode("2A19", BatteryCodec.encode_level(87)), "battery 87 %")
	assert_string_contains(BleDebugModel.decode("2AD9", PackedByteArray([0x80, 0x05, 0x01])), "set_target_power: success")
	assert_eq(BleDebugModel.decode("ABCD", PackedByteArray([1, 2])), "", "без кодека — пусто")


func test_write_hex_into_selected_characteristic_and_invalid_hex() -> void:
	_connect_neo()
	assert_true(_model.write_hex(FEC_SERVICE, FEC_WRITE, "a4 09 4f", false))
	var w := _bridge.writes_to(FEC_WRITE)
	assert_eq(w.size(), 1)
	assert_eq(w[0]["bytes"], PackedByteArray([0xA4, 0x09, 0x4F]))
	assert_false(w[0]["with_response"])
	assert_eq(w[0]["service"], FEC_SERVICE)
	_bridge.pump()
	assert_string_contains(_model.entries_of("write_done")[0]["text"], "ok")
	assert_false(_model.write_hex(FEC_SERVICE, FEC_WRITE, "0G"))
	assert_false(_model.write_hex(FEC_SERVICE, FEC_WRITE, "123"))
	assert_eq(_bridge.writes_to(FEC_WRITE).size(), 1, "неверный hex не пишется")
	assert_eq(_model.entries_of("write_rejected").size(), 2)
	_bridge.fail_next_write()
	_model.write_hex(FEC_SERVICE, FEC_WRITE, "01")
	_bridge.pump()
	assert_string_contains(_model.entries_of("write_done")[1]["text"], "FAILED")


func test_parse_hex_accepts_common_separators() -> void:
	assert_eq(BleDebugModel.parse_hex("05 96 00")["bytes"], PackedByteArray([5, 0x96, 0]))
	assert_eq(BleDebugModel.parse_hex("059600")["bytes"], PackedByteArray([5, 0x96, 0]))
	assert_eq(BleDebugModel.parse_hex("0x05, 0x96:00")["bytes"], PackedByteArray([5, 0x96, 0]))
	assert_false(BleDebugModel.parse_hex("")["ok"])
	assert_false(BleDebugModel.parse_hex("zz")["ok"])


func test_ftms_control_point_presets_bytes_target_and_response() -> void:
	var ftms := {"1826": ["2AD2", "2AD9", "2ADA", "2ACC"]}
	_connect_neo(ftms)
	var expected := {
		BleDebugModel.PRESET_FTMS_REQUEST_CONTROL: PackedByteArray([0x00]),
		BleDebugModel.PRESET_FTMS_START: PackedByteArray([0x07]),
		BleDebugModel.PRESET_FTMS_TARGET_POWER_150: PackedByteArray([0x05, 0x96, 0x00]),
		BleDebugModel.PRESET_FTMS_RESET: PackedByteArray([0x01]),
	}
	for id: String in expected:
		assert_true(_model.write_preset(id, false))
	var w := _bridge.writes_to("2AD9")
	assert_eq(w.size(), 4)
	var i := 0
	for id: String in expected:
		assert_eq(w[i]["bytes"], expected[id], id)
		assert_eq(w[i]["service"], "1826")
		assert_true(w[i]["with_response"], "Control Point FTMS — всегда с ответом")
		i += 1
	_bridge.pump()
	var responses := _model.entries_of("notification")
	assert_eq(responses.size(), 4, "индикации Control Point в журнале")
	assert_string_contains(responses[2]["text"], "set_target_power: success")
	assert_string_contains(_model.entries_of("write")[2]["text"], "set_target_power 150 W")


func test_fec_target_power_preset_is_ant_message_with_xor_checksum() -> void:
	var msg := BleDebugModel.fec_target_power_message(150)
	assert_eq(BleBytes.to_hex(msg), "A4 09 4F 05 31 FF FF FF FF FF 58 02 73")
	assert_eq(BleDebugModel.ant_checksum(msg.slice(0, 12)), 0x73)
	_connect_neo()
	assert_true(_model.write_preset(BleDebugModel.PRESET_FEC_TARGET_POWER_150, false))
	var w := _bridge.writes_to(FEC_WRITE)
	assert_eq(w.size(), 1)
	assert_eq(w[0]["bytes"], msg)
	assert_eq(w[0]["service"], FEC_SERVICE)
	assert_false(w[0]["with_response"], "FE-C — режим записи по выбору экрана")
	assert_string_contains(_model.entries_of("write")[0]["text"], "page 0x31 Target Power: 150.00 W")


func test_presets_write_even_when_service_is_missing_with_note() -> void:
	_connect_neo({"1818": ["2A63"]})
	assert_true(_model.write_preset(BleDebugModel.PRESET_FTMS_START))
	assert_eq(_model.entries_of("note").size(), 1, "сервиса 1826 нет — пометка в журнале")


func test_fec_pages_decoded_from_notifications() -> void:
	# 0x19 Specific Trainer Data: события 7, каденс 85, накопленная 1000 Вт, мгновенная 250 Вт, состояние in_use.
	var trainer := BleDebugModel.fec_message(PackedByteArray([0x19, 7, 85, 0xE8, 0x03, 0xFA, 0x00, 0x30]),
			BleDebugModel.ANT_BROADCAST_DATA)
	var text := BleDebugModel.decode(FEC_NOTIFY, trainer)
	assert_string_contains(text, "ANT broadcast ch5")
	assert_string_contains(text, "page 0x19 Trainer Data: cadence 85 rpm, power 250 W, accumulated 1000 W, events 7")
	assert_string_contains(text, "state in_use")
	# 0x10 General FE Data: тренажёр, 10 с, 100 м, 8.333 м/с = 30 км/ч, пульса нет, ready.
	var general := BleDebugModel.fec_message(PackedByteArray([0x10, 25, 40, 100, 0x8D, 0x20, 0xFF, 0x20]),
			BleDebugModel.ANT_BROADCAST_DATA)
	text = BleDebugModel.decode(FEC_NOTIFY, general)
	assert_string_contains(text, "page 0x10 General FE: type trainer, elapsed 10.00 s, distance 100 m, speed 30.00 km/h, HR n/a, state ready")
	var status := BleDebugModel.fec_message(PackedByteArray([0x47, 0x31, 3, 0, 0xFF, 0xFF, 0x58, 0x02]))
	assert_string_contains(BleDebugModel.decode(FEC_NOTIFY, status), "last command 0x31, sequence 3, status pass")
	var broken := trainer.duplicate()
	broken[12] = broken[12] ^ 0xFF
	assert_string_contains(BleDebugModel.decode(FEC_NOTIFY, broken), "CHECKSUM BAD")
	_connect_neo()
	_model.set_subscribed(FEC_SERVICE, FEC_NOTIFY, true)
	_bridge.emit_notification(NEO, FEC_NOTIFY, trainer)
	assert_string_contains(_model.value_of(FEC_NOTIFY)["decoded"], "power 250 W")


# ---------------------------------------------------------------------------
# Журнал
# ---------------------------------------------------------------------------

func test_log_has_timestamps_all_bridge_events_and_copy_text() -> void:
	_bridge.set_adapter_state(BleBridge.AdapterState.POWERED_OFF)
	_bridge.set_adapter_state(BleBridge.AdapterState.POWERED_ON)
	_connect_neo()
	_bridge.emit_error(NEO, BleBridge.ErrorCode.SUBSCRIBE_FAILED, "boom " + NEO)
	var events: Array[String] = []
	for e in _model.log_entries():
		if not events.has(str(e["event"])):
			events.append(str(e["event"]))
	for ev in ["adapter_state_changed", "scan_started", "device_found", "connect_requested", "connected",
			"services_discovered", "error"]:
		assert_has(events, ev)
	var text := _model.log_text()
	assert_string_contains(text, "13:46:40.000 adapter_state_changed powered_off")
	assert_string_contains(text, "SUBSCRIBE_FAILED: boom " + NEO)
	assert_eq(text.split("\n").size(), _model.log_size())
	_model.clear_log()
	assert_eq(_model.log_size(), 0)


func test_events_go_to_diag_log_with_device_tag_instead_of_id() -> void:
	var dir := "user://test_ble_debug_diag_%d/" % Time.get_ticks_usec()
	var journal := DiagLog.new(dir)
	assert_eq(journal.open(), OK)
	DiagLog.install(journal)
	_connect_neo()
	_bridge.emit_error(NEO, BleBridge.ErrorCode.READ_FAILED, "read failed for " + NEO)
	DiagLog.uninstall(journal)
	var path := journal.file_path()
	journal.close()
	var content := FileAccess.get_file_as_string(path)
	assert_string_contains(content, "\"cat\":\"ble_debug\"")
	assert_string_contains(content, "\"ev\":\"services_discovered\"")
	assert_string_contains(content, BleDebugModel.device_tag(NEO))
	assert_string_contains(content, "Tacx Neo 11565", "имя устройства — можно")
	assert_false(content.contains(NEO), "id устройства в DiagLog не попадает")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func test_dispose_stops_scan_disconnects_and_unhooks_bridge() -> void:
	_connect_neo()
	_model.dispose()
	assert_eq(_bridge.calls_of("stop_scan").size(), 1)
	assert_eq(_bridge.calls_of("disconnect_peripheral").size(), 1)
	assert_false(_bridge.device_found.is_connected(_model._on_device_found))
	assert_false(_bridge.notification.is_connected(_model._on_notification))
