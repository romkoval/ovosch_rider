extends GutTest
## Приёмка T-165 (tester): модель «BLE-отладки» — независимые проверки по п.1–5 файла задачи
## (инструмент для REQ-DEV-01, REQ-DEV-02, REQ-DEV-03, REQ-DEV-07). Заглушка моста; границы
## (ровно 1 с между пакетами рекламы, нечётный hex, плохая XOR-сумма, 0 и предельная мощность
## FE-C), ответ станка на 0x31 (страница 0x47), обрыв связи с подпиской, DiagLog без id
## (включая сообщение ошибки и запись hex).

const NEO: String = "F2A1C3D4-0000-4E1B-9C2D-ACCEPT165NEO"
const HRM: String = "HRM-ACCEPT-165"
const FEC_SERVICE: String = "6E40FEC1-B5A3-F393-E0A9-E50E24DCCA9E"
const FEC_NOTIFY: String = "6E40FEC2-B5A3-F393-E0A9-E50E24DCCA9E"
const FEC_WRITE: String = "6E40FEC3-B5A3-F393-E0A9-E50E24DCCA9E"

var _bridge: StubBleBridge
var _model: BleDebugModel
var _now: float = 2_000_000.0


func before_each() -> void:
	_now = 2_000_000.0
	_bridge = StubBleBridge.new()
	_model = BleDebugModel.new(_bridge)
	_model.clock = func() -> float: return _now
	_model.utc_offset_sec = 0


func after_each() -> void:
	_model.dispose(false)
	_bridge.dispose()
	DiagLog.uninstall()


func _neo_services() -> Dictionary:
	return {
		"0000180A-0000-1000-8000-00805F9B34FB": ["00002A29-0000-1000-8000-00805F9B34FB", "2A24", "2A26"],
		"1818": ["2A63"],
		"180F": ["2A19"],
		"1826": ["2AD2", "2AD9", "2ADA", "2ACC", "2AD8", "2AD6", "2AD5"],
		"1816": ["2A5B"],
		"180D": ["2A37"],
		"6e40fec1-b5a3-f393-e0a9-e50e24dcca9e": ["6e40fec2-b5a3-f393-e0a9-e50e24dcca9e", "6e40fec3-b5a3-f393-e0a9-e50e24dcca9e"],
		"669AA501-0C08-969E-E211-86AD5062675F": ["669AAC01-0C08-969E-E211-86AD5062675F"],
	}


func _connect_neo() -> void:
	_bridge.set_device_services(NEO, _neo_services())
	_model.start_scan()
	_bridge.emit_device_found(NEO, "Tacx Neo 11565", -60, PackedStringArray(["1816"]))
	_model.connect_device(NEO)
	_bridge.pump()


# --- п.1: скан, UUID, тип ---------------------------------------------------

func test_p1_scan_no_filter_then_app_filter_restarts_running_scan() -> void:
	_model.start_scan()
	assert_eq(Array(_bridge.calls_of("start_scan")[0]["service_uuids"]), [], "по умолчанию — без фильтра")
	_bridge.emit_device_found(NEO, "Tacx Neo 11565", -60, PackedStringArray(["1816"]))
	_model.set_use_app_filter(true)
	var scans := _bridge.calls_of("start_scan")
	assert_eq(scans.size(), 2, "идущий скан перезапущен")
	assert_eq(Array(scans[1]["service_uuids"]), Array(BleUuids.SCAN_SERVICES))
	assert_eq(_model.devices.size(), 0, "новый сеанс — список сброшен")
	_model.set_use_app_filter(false)
	assert_eq(Array(_bridge.calls_of("start_scan")[2]["service_uuids"]), [], "снова без фильтра")


func test_p1_device_record_raw_and_normalized_uuids_union_and_kind_change() -> void:
	_model.start_scan()
	var full_csc := "00001816-0000-1000-8000-00805f9b34fb"
	_bridge.emit_device_found(NEO, "", -70, PackedStringArray([full_csc]))
	var d := _model.device(NEO)
	assert_eq(str(d["id"]), NEO, "полный id")
	assert_eq(Array(d["raw"]), [full_csc], "UUID как пришли")
	assert_eq(Array(d["norm"]), ["1816"], "нормализованные")
	assert_eq(str(d["kind"]), BleScanner.kind_from_services(PackedStringArray(["1816"])))
	_bridge.emit_device_found(NEO, "Tacx Neo 11565", -58, PackedStringArray(["1826"]))
	d = _model.device(NEO)
	assert_eq(str(d["name"]), "Tacx Neo 11565")
	assert_eq(int(d["rssi"]), -58)
	assert_eq(Array(d["norm"]), ["1826"], "последний пакет")
	assert_eq(Array(d["union"]), ["1816", "1826"], "объединение за сеанс")
	assert_eq(str(d["kind"]), BleScanner.kind_from_services(PackedStringArray(["1816", "1826"])),
			"тип — по объединению, сменился на станок")
	assert_eq(str(d["kind"]), RememberedDevices.KIND_TRAINER)
	_bridge.emit_device_found(NEO, "", -59, PackedStringArray())
	assert_eq(str(_model.device(NEO)["name"]), "Tacx Neo 11565", "пакет без имени не стирает имя")


func test_p5_device_found_throttle_boundaries_per_device() -> void:
	_model.start_scan()
	_bridge.emit_device_found(NEO, "Neo", -60, PackedStringArray(["1816"]))
	_bridge.emit_device_found(HRM, "HRM", -70, PackedStringArray(["180D"]))
	assert_eq(_model.entries_of("device_found").size(), 2, "первый пакет каждого устройства")
	_now += 0.999
	_bridge.emit_device_found(NEO, "Neo", -61, PackedStringArray(["1816"]))
	assert_eq(_model.entries_of("device_found").size(), 2, "0.999 с — не пишется")
	_bridge.emit_device_found(NEO, "Neo", -61, PackedStringArray(["1818"]))
	assert_eq(_model.entries_of("device_found").size(), 3, "новый UUID — пишется сразу")
	_now += 0.5
	_bridge.emit_device_found(NEO, "Neo", -61, PackedStringArray(["1816", "1818"]))
	assert_eq(_model.entries_of("device_found").size(), 3, "0.5 с после записи — нет")
	_now += 0.5
	_bridge.emit_device_found(NEO, "Neo", -61, PackedStringArray(["1816"]))
	assert_eq(_model.entries_of("device_found").size(), 4, "ровно 1 с — пишется")
	_bridge.emit_device_found(HRM, "HRM", -70, PackedStringArray(["180D"]))
	assert_eq(_model.entries_of("device_found").size(), 5, "интервал — на устройство, а не общий")


# --- п.2: дерево ------------------------------------------------------------

func test_p2_tree_normalizes_full_uuids_and_names_all_listed_services() -> void:
	_connect_neo()
	assert_eq(_bridge.calls_of("discover_services").size(), 1, "discover после connected")
	assert_true(_model.is_ready())
	var names: Dictionary = {}
	for s in _model.service_tree():
		names[s["uuid"]] = s["name"]
		for c in s["chars"]:
			names[c["uuid"]] = c["name"]
	for u in ["1826", "2AD2", "2AD9", "2ADA", "2ACC", "2AD8", "2AD6", "2AD5", "1818", "2A63", "1816", "2A5B",
			"180D", "2A37", "180F", "2A19", "180A", "2A29", FEC_SERVICE, FEC_NOTIFY, FEC_WRITE]:
		assert_true(names.has(u), "в дереве %s (нормализован)" % u)
		assert_ne(str(names.get(u, "")), "", "у %s есть имя" % u)
	assert_true(names.has("669AA501-0C08-969E-E211-86AD5062675F"), "неизвестный сервис — как есть")
	assert_eq(str(names["669AA501-0C08-969E-E211-86AD5062675F"]), "")


# --- п.3: чтение, подписка, значения ---------------------------------------

func test_p3_read_device_info_reads_text_and_decodes_utf8() -> void:
	_connect_neo()
	_bridge.clear_calls()
	assert_eq(_model.read_device_info(), 3)
	var chars: Array = []
	for c in _bridge.calls_of("read_characteristic"):
		chars.append(c.get("char", ""))
	_bridge.emit_characteristic_read(NEO, "2A29", "Tacx".to_utf8_buffer())
	var v := _model.value_of("2A29")
	assert_eq(str(v["hex"]), "54 61 63 78")
	assert_string_contains(str(v["decoded"]), "Tacx")
	assert_eq(str(v["source"]), "read")


func test_p3_link_loss_clears_subscriptions_and_rejects_actions() -> void:
	_connect_neo()
	assert_true(_model.set_subscribed(FEC_SERVICE, FEC_NOTIFY, true))
	assert_true(_bridge.is_subscribed(NEO, FEC_SERVICE, FEC_NOTIFY))
	_bridge.emit_disconnected(NEO, BleBridge.DisconnectReason.LINK_LOSS)
	assert_false(_model.is_ready())
	assert_false(_model.is_subscribed(FEC_SERVICE, FEC_NOTIFY), "подписка сброшена при обрыве")
	assert_string_contains(_model.log_text(), "reason link_loss")
	_bridge.clear_calls()
	assert_false(_model.write_preset(BleDebugModel.PRESET_FEC_TARGET_POWER_150))
	assert_eq(_bridge.calls_of("write").size(), 0, "без связи в мост ничего не пишется")
	# Восстановление: снова подключиться — дерево собирается заново.
	_model.connect_device(NEO)
	_bridge.pump()
	assert_true(_model.is_ready(), "повторное подключение после обрыва")
	assert_true(_model.has_service(FEC_SERVICE))


func test_p3_write_hex_boundaries_and_with_response_choice() -> void:
	_connect_neo()
	_bridge.clear_calls()
	assert_false(_model.write_hex(FEC_SERVICE, FEC_WRITE, "A4 0"), "нечётное число цифр")
	assert_false(_model.write_hex(FEC_SERVICE, FEC_WRITE, "ZZ"), "не hex")
	assert_false(_model.write_hex(FEC_SERVICE, FEC_WRITE, "   "), "пусто")
	assert_eq(_bridge.calls_of("write").size(), 0, "неверный hex в мост не уходит")
	assert_true(_model.write_hex(FEC_SERVICE, FEC_WRITE, "0xA4,0x09", false))
	var w := _bridge.calls_of("write")
	assert_eq(w.size(), 1)
	assert_eq(BleBytes.to_hex(w[0]["bytes"]), "A4 09")
	assert_false(bool(w[0]["with_response"]), "«без ответа» передан мосту")
	assert_true(_model.write_hex(FEC_SERVICE, FEC_WRITE, "a4:09", true))
	assert_true(bool(_bridge.calls_of("write")[1]["with_response"]), "«с ответом» передан мосту")


# --- п.4: пресеты -----------------------------------------------------------

func test_p4_ftms_presets_exact_bytes_to_control_point_with_response() -> void:
	_connect_neo()
	var expected := {
		BleDebugModel.PRESET_FTMS_REQUEST_CONTROL: "00",
		BleDebugModel.PRESET_FTMS_START: "07",
		BleDebugModel.PRESET_FTMS_TARGET_POWER_150: "05 96 00",
		BleDebugModel.PRESET_FTMS_RESET: "01",
	}
	for id: String in expected:
		_bridge.clear_calls()
		assert_true(_model.write_preset(id, false))
		var w := _bridge.calls_of("write")
		assert_eq(w.size(), 1, id)
		assert_eq(str(w[0]["service"]), "1826", id)
		assert_eq(str(w[0]["char"]), "2AD9", id)
		assert_eq(BleBytes.to_hex(w[0]["bytes"]), expected[id], id)
		assert_true(bool(w[0]["with_response"]), "%s: Control Point — с ответом" % id)


func test_p4_fec_target_power_message_and_checksum_independent() -> void:
	_connect_neo()
	_bridge.clear_calls()
	assert_true(_model.write_preset(BleDebugModel.PRESET_FEC_TARGET_POWER_150, false))
	var w := _bridge.calls_of("write")
	assert_eq(str(w[0]["char"]), FEC_WRITE)
	var bytes: PackedByteArray = w[0]["bytes"]
	assert_eq(BleBytes.to_hex(bytes), "A4 09 4F 05 31 FF FF FF FF FF 58 02 73")
	assert_false(bool(w[0]["with_response"]), "FE-C: выбор «с ответом» с экрана передан")
	var x := 0
	for i in bytes.size() - 1:
		x ^= bytes[i]
	assert_eq(x, bytes[bytes.size() - 1], "XOR-сумма считана независимо")
	# Границы мощности: 0 Вт и 4000 Вт (0.25 Вт на единицу, 16 бит).
	var zero := BleDebugModel.fec_target_power_message(0)
	assert_eq(BleBytes.to_hex(zero.slice(10, 12)), "00 00")
	var top := BleDebugModel.fec_target_power_message(4000)
	assert_eq(BleBytes.to_hex(top.slice(10, 12)), "80 3E", "4000 Вт = 16000 × 0.25")
	for msg in [zero, top]:
		var y := 0
		for i in msg.size() - 1:
			y ^= msg[i]
		assert_eq(y, msg[msg.size() - 1])


func test_p3_fec_decoding_bad_checksum_and_command_status_for_0x31() -> void:
	_connect_neo()
	var ok_msg := BleDebugModel.fec_target_power_message(150)
	assert_string_contains(BleDebugModel.decode_fec(ok_msg), "page 0x31 Target Power: 150.00 W")
	assert_false(BleDebugModel.decode_fec(ok_msg).contains("CHECKSUM BAD"))
	var bad := ok_msg.duplicate()
	bad[12] = bad[12] ^ 0x01
	assert_string_contains(BleDebugModel.decode_fec(bad), "CHECKSUM BAD", "плохая сумма видна")
	# Ответ станка: Command Status (0x47) на 0x31, статус pass, данные — 58 02 мощности.
	var status := BleDebugModel.fec_message(PackedByteArray([0x47, 0x31, 0x05, 0x00, 0xFF, 0xFF, 0x58, 0x02]),
			BleDebugModel.ANT_BROADCAST_DATA)
	_bridge.emit_notification(NEO, FEC_NOTIFY, status)
	var v := _model.value_of(FEC_NOTIFY)
	assert_string_contains(str(v["decoded"]), "last command 0x31")
	assert_string_contains(str(v["decoded"]), "status pass")
	assert_string_contains(str(v["decoded"]), "broadcast")
	# 0x10 General FE: тип trainer (25), скорость 10 м/с = 36 км/ч, состояние in_use.
	var gen := BleDebugModel.fec_message(PackedByteArray([0x10, 25, 8, 100, 0x10, 0x27, 0xFF, 0x30]))
	var g := BleDebugModel.decode_fec(gen)
	assert_string_contains(g, "type trainer")
	assert_string_contains(g, "speed 36.00 km/h")
	assert_string_contains(g, "HR n/a")
	assert_string_contains(g, "state in_use")
	# 0x19: мощность 12 бит (0xFFF — n/a), каденс 0xFF — n/a.
	var na := BleDebugModel.decode_fec(PackedByteArray([0x19, 0, 0xFF, 0, 0, 0xFF, 0x0F, 0x20]))
	assert_string_contains(na, "cadence n/a")
	assert_string_contains(na, "power n/a")
	var p := BleDebugModel.decode_fec(PackedByteArray([0x19, 0, 90, 0, 0, 0xE8, 0x03, 0x30]))
	assert_string_contains(p, "power 1000 W", "12-битная мощность: 0x3E8")
	# Остальные страницы ТЗ — с номером и смыслом.
	assert_string_contains(BleDebugModel.decode_fec(PackedByteArray([0x11, 0xFF, 0xFF, 0, 0xF4, 0x01, 40, 0x30])), "incline 5.00 %")
	assert_string_contains(BleDebugModel.decode_fec(PackedByteArray([0x30, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 100])), "50.0 %")
	assert_string_contains(BleDebugModel.decode_fec(PackedByteArray([0x50, 0xFF, 0xFF, 3, 89, 0, 0x0A, 0x28])), "manufacturer 89")
	assert_string_contains(BleDebugModel.decode_fec(PackedByteArray([0x51, 0xFF, 7, 4, 0x39, 0x30, 0, 0])), "serial 12345")


func test_p3_ftms_control_point_response_decoded() -> void:
	_connect_neo()
	_model.set_subscribed("1826", "2AD9", true)
	_model.write_preset(BleDebugModel.PRESET_FTMS_TARGET_POWER_150)
	_bridge.pump()
	var v := _model.value_of("2AD9")
	assert_false(v.is_empty(), "ответ Control Point сохранён")
	assert_string_contains(str(v["decoded"]), "response to")
	assert_eq(_model.entries_of("write_done").size(), 1, "write_done в журнале")


# --- п.5: журнал и DiagLog без id -------------------------------------------

func test_p5_diag_log_never_contains_full_device_id() -> void:
	var dir := "user://test_t165_accept_diag_%d/" % Time.get_ticks_usec()
	var journal := DiagLog.new(dir)
	assert_eq(journal.open(), OK)
	DiagLog.install(journal)
	_connect_neo()
	_model.set_subscribed(FEC_SERVICE, FEC_NOTIFY, true)
	_model.write_preset(BleDebugModel.PRESET_FEC_TARGET_POWER_150)
	_model.write_hex(FEC_SERVICE, FEC_WRITE, "nothex")
	_bridge.emit_notification(NEO, FEC_NOTIFY, BleDebugModel.fec_target_power_message(100))
	_bridge.emit_error(NEO, BleBridge.ErrorCode.WRITE_FAILED, "CBError for peripheral %s: busy" % NEO)
	_bridge.pump()
	_model.disconnect_device()
	_bridge.pump()
	DiagLog.uninstall(journal)
	var path := journal.file_path()
	journal.close()
	var content := FileAccess.get_file_as_string(path)
	for ev in ["scan_started", "device_found", "connect_requested", "connected", "services_discovered", "subscribe",
			"write", "write_rejected", "notification", "error", "write_done", "disconnected"]:
		assert_string_contains(content, "\"ev\":\"%s\"" % ev, "событие %s в DiagLog" % ev)
	assert_string_contains(content, BleDebugModel.device_tag(NEO))
	assert_eq(BleDebugModel.device_tag(NEO), NEO.sha256_text().substr(0, BleDebugModel.device_tag(NEO).length()),
			"метка — префикс SHA-256")
	assert_false(content.contains(NEO), "полный id в DiagLog не попадает")
	assert_string_contains(content, "Tacx Neo 11565", "имя — как есть")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func test_p5_copy_text_contains_every_entry_with_timestamp() -> void:
	_connect_neo()
	_bridge.set_adapter_state(BleBridge.AdapterState.POWERED_OFF)
	var lines := _model.log_text().split("\n")
	assert_eq(lines.size(), _model.log_size())
	var re := RegEx.create_from_string("^\\d{2}:\\d{2}:\\d{2}\\.\\d{3} \\S+")
	for l in lines:
		assert_not_null(re.search(l), "строка с меткой времени: %s" % l)
	assert_string_contains(_model.log_text(), "adapter_state_changed")
