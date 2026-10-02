extends GutTest
## Независимая приёмка T-015/T-016 (коммит 03cce42): контракт `BleBridge`, `StubBleBridge`,
## `NativeBleBridge`, `BleUuids`, кодеки FTMS/HRS/CSC/CPS/BAS.
## Критерии: REQ-DEV-01 к1; REQ-DEV-02 к2–5; REQ-DEV-03 к1, 2; REQ-DEV-04 к1–3; REQ-DEV-05 к1, 3;
## REQ-DEV-07 к2, 3; REQ-WRK-04 к2; REQ-NFR-06 к1, 5.
## Байтовые векторы собраны по спецификациям Bluetooth SIG (FTMS v1.0, HRS v1.0, CSC v1.0,
## CPS v1.1, BAS v1.0) независимо от кодеков; hex-помощник свой.

const DEV: String = "neo-42"

var _stub: StubBleBridge
var _events: Array[Dictionary] = []


func before_each() -> void:
	_events = []
	_stub = StubBleBridge.new()
	_stub.device_found.connect(func(id: String, n: String, rssi: int, svc: PackedStringArray) -> void:
		_events.append({"sig": "found", "id": id, "name": n, "rssi": rssi, "services": svc}))
	_stub.connected.connect(func(id: String) -> void: _events.append({"sig": "connected", "id": id}))
	_stub.disconnected.connect(func(id: String, r: int) -> void:
		_events.append({"sig": "disconnected", "id": id, "reason": r}))
	_stub.services_discovered.connect(func(id: String, s: Dictionary) -> void:
		_events.append({"sig": "services", "id": id, "services": s}))
	_stub.notification.connect(func(id: String, c: String, b: PackedByteArray) -> void:
		_events.append({"sig": "notify", "id": id, "char": c, "bytes": b}))
	_stub.characteristic_read.connect(func(id: String, c: String, b: PackedByteArray) -> void:
		_events.append({"sig": "read", "id": id, "char": c, "bytes": b}))
	_stub.write_done.connect(func(id: String, c: String, ok: bool) -> void:
		_events.append({"sig": "write_done", "id": id, "char": c, "ok": ok}))
	_stub.error.connect(func(id: String, code: int, m: String) -> void:
		_events.append({"sig": "error", "id": id, "code": code, "message": m}))


func _of(sig: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _events:
		if e["sig"] == sig:
			out.append(e)
	return out


## Свой hex → байты ("44 00 48 0D"), чтобы не зависеть от BleBytes.
func _hex(s: String) -> PackedByteArray:
	var clean := s.replace(" ", "")
	var out := PackedByteArray()
	var i := 0
	while i + 1 < clean.length():
		out.append(("0x" + clean.substr(i, 2)).hex_to_int())
		i += 2
	return out


func _hex_of(bytes: PackedByteArray) -> String:
	var parts: PackedStringArray = []
	for b in bytes:
		parts.append("%02X" % b)
	return " ".join(parts)


# ---------------------------------------------------------------------------
# REQ-DEV-01 крит. 1 — фильтр сканирования
# ---------------------------------------------------------------------------

func test_req_dev_01_c1_scan_filter_is_ftms_hrs_csc_cps() -> void:
	var expected := ["1826", "180D", "1816", "1818"]
	assert_eq(BleUuids.SCAN_SERVICES.size(), 4, "ровно четыре сервиса")
	for u in expected:
		assert_true(BleUuids.SCAN_SERVICES.has(u), "в фильтре сканирования есть %s" % u)
	# Аргументы вызова моста журналируются заглушкой.
	_stub.start_scan(BleUuids.SCAN_SERVICES)
	var calls := _stub.calls_of("start_scan")
	assert_eq(calls.size(), 1)
	var arg: PackedStringArray = calls[0]["service_uuids"]
	assert_eq(arg.size(), 4)
	for u in expected:
		assert_true(arg.has(u), "мост получил %s" % u)
	assert_true(_stub.scanning)
	_stub.stop_scan()
	assert_false(_stub.scanning)
	assert_eq(_stub.calls_of("stop_scan").size(), 1)
	# Тип устройства по сервисам рекламы (для списка DEV-01 крит. 2, здесь — вспомогательно).
	assert_eq(BleUuids.device_kind(PackedStringArray(["0000180d-0000-1000-8000-00805f9b34fb"])), "heart_rate")
	assert_eq(BleUuids.device_kind(PackedStringArray(["1816", "180F"])), "cadence")
	assert_eq(BleUuids.device_kind(PackedStringArray(["1818"])), "power")
	assert_eq(BleUuids.device_kind(PackedStringArray(["1818", "1826"])), "trainer", "FTMS приоритетнее CPS")
	assert_eq(BleUuids.device_kind(PackedStringArray()), "unknown")


# ---------------------------------------------------------------------------
# REQ-DEV-02 крит. 2 — Indoor Bike Data 2AD2 по флагам
# ---------------------------------------------------------------------------

func test_req_dev_02_c2_ibd_speed_cadence_power_more_data_clear() -> void:
	# Flags 0x0044: бит0 (More Data) = 0 → скорость присутствует; бит2 каденс; бит6 мощность.
	# speed 3400 (34.00 км/ч) = 48 0D; cadence 180 (90.0 rpm) = B4 00; power 250 = FA 00.
	var r := FtmsCodec.decode_indoor_bike_data(_hex("44 00 48 0D B4 00 FA 00"))
	assert_true(r["ok"])
	assert_true(r["has_speed"], "More Data = 0 → поле скорости есть")
	assert_almost_eq(float(r["speed_kmh"]), 34.0, 1e-6)
	assert_true(r["has_cadence"])
	assert_almost_eq(float(r["cadence_rpm"]), 90.0, 1e-6, "180 × 0.5 rpm")
	assert_true(r["has_power"])
	assert_eq(r["power_w"], 250)
	assert_false(r["has_heart_rate"])


func test_req_dev_02_c2_ibd_more_data_set_means_no_speed_field() -> void:
	# Flags 0x0045: бит0 = 1 → поля скорости НЕТ; далее сразу каденс и мощность.
	var r := FtmsCodec.decode_indoor_bike_data(_hex("45 00 B4 00 FA 00"))
	assert_true(r["ok"])
	assert_false(r["has_speed"], "More Data = 1 → скорости нет (бит инвертирован)")
	assert_almost_eq(float(r["cadence_rpm"]), 90.0, 1e-6, "каденс читается со смещения 2")
	assert_eq(r["power_w"], 250, "мощность со смещения 4")
	# Тот же пакет без бита More Data трактовался бы иначе — убеждаемся, что кодек различает.
	var r2 := FtmsCodec.decode_indoor_bike_data(_hex("44 00 B4 00 FA 00"))
	assert_true(r2["has_speed"])
	assert_almost_eq(float(r2["speed_kmh"]), 1.80, 1e-6, "180 × 0.01 км/ч — байты ушли в скорость")
	assert_false(r2["has_power"], "мощности не хватило → пакет неполный")
	assert_false(r2["ok"])


func test_req_dev_02_c2_ibd_only_power_minimal_packet() -> void:
	# Flags 0x0041: More Data = 1, только мощность.
	var r := FtmsCodec.decode_indoor_bike_data(_hex("41 00 C8 00"))
	assert_true(r["ok"])
	assert_false(r["has_speed"])
	assert_false(r["has_cadence"])
	assert_true(r["has_power"])
	assert_eq(r["power_w"], 200)
	# Flags 0x0001: More Data и ничего больше — валидный пустой пакет.
	var r0 := FtmsCodec.decode_indoor_bike_data(_hex("01 00"))
	assert_true(r0["ok"])
	assert_false(r0["has_power"])
	# Flags 0x0000: скорость обещана, но байтов нет → не ok.
	var r1 := FtmsCodec.decode_indoor_bike_data(_hex("00 00"))
	assert_false(r1["ok"])
	assert_false(r1["has_speed"])


func test_req_dev_02_c2_ibd_heart_rate_uint8_when_flag_set() -> void:
	# Flags 0x0244: скорость, каденс, мощность, пульс (бит9). HR 0x48 = 72.
	var r := FtmsCodec.decode_indoor_bike_data(_hex("44 02 48 0D B4 00 FA 00 48"))
	assert_true(r["ok"])
	assert_true(r["has_heart_rate"])
	assert_eq(r["heart_rate_bpm"], 72)
	assert_eq(r["power_w"], 250)
	# Без флага пульса последний байт не читается как пульс.
	var r2 := FtmsCodec.decode_indoor_bike_data(_hex("44 00 48 0D B4 00 FA 00 48"))
	assert_true(r2["ok"], "лишние байты в хвосте не ломают разбор")
	assert_false(r2["has_heart_rate"])


func test_req_dev_02_c2_ibd_negative_power_sint16() -> void:
	var r := FtmsCodec.decode_indoor_bike_data(_hex("41 00 FA FF"))
	assert_true(r["ok"])
	assert_eq(r["power_w"], -6, "FA FF = −6 (sint16)")
	assert_eq(FtmsCodec.decode_indoor_bike_data(_hex("41 00 18 FC"))["power_w"], -1000)
	assert_eq(FtmsCodec.decode_indoor_bike_data(_hex("41 00 00 80"))["power_w"], -32768)
	assert_eq(FtmsCodec.decode_indoor_bike_data(_hex("41 00 FF 7F"))["power_w"], 32767)
	assert_eq(FtmsCodec.decode_indoor_bike_data(_hex("41 00 D0 07"))["power_w"], 2000)


func test_req_dev_02_c2_ibd_all_fields_in_spec_order() -> void:
	# Flags 0x1FFE: бит0 = 0 (скорость есть) и биты 1..12 — все поля по порядку §4.9:
	# speed 3400 | avg speed 3000 | cadence 180 | avg cadence 170 | distance 123456 (uint24)
	# | resistance −5 (sint16) | power 250 | avg power 240 | energy total 500, /h 600, /min 10
	# | HR 72 | MET 85 (8.5) | elapsed 3600 | remaining 1800
	var pkt := _hex("FE 1F" + " 48 0D" + " B8 0B" + " B4 00" + " AA 00" + " 40 E2 01" + " FB FF"
		+ " FA 00" + " F0 00" + " F4 01 58 02 0A" + " 48" + " 55" + " 10 0E" + " 08 07")
	assert_eq(pkt.size(), 30)
	var r := FtmsCodec.decode_indoor_bike_data(pkt)
	assert_true(r["ok"])
	assert_almost_eq(float(r["speed_kmh"]), 34.0, 1e-6)
	assert_almost_eq(float(r["average_speed_kmh"]), 30.0, 1e-6)
	assert_almost_eq(float(r["cadence_rpm"]), 90.0, 1e-6)
	assert_almost_eq(float(r["average_cadence_rpm"]), 85.0, 1e-6)
	assert_eq(r["distance_m"], 123456, "Total Distance uint24")
	assert_eq(r["resistance_level"], -5, "Resistance Level sint16")
	assert_eq(r["power_w"], 250)
	assert_eq(r["average_power_w"], 240)
	assert_eq(r["energy_total_kcal"], 500)
	assert_eq(r["energy_per_hour_kcal"], 600)
	assert_eq(r["energy_per_minute_kcal"], 10)
	assert_eq(r["heart_rate_bpm"], 72)
	assert_almost_eq(float(r["metabolic_equivalent"]), 8.5, 1e-6)
	assert_eq(r["elapsed_sec"], 3600)
	assert_eq(r["remaining_sec"], 1800)


func test_req_dev_02_c2_ibd_truncated_packets_do_not_crash() -> void:
	var r := FtmsCodec.decode_indoor_bike_data(_hex("44 00 48 0D B4 00 FA"))
	assert_false(r["ok"], "мощность обрезана → ok false")
	assert_true(r["has_speed"], "уже разобранные поля остаются")
	assert_true(r["has_cadence"])
	assert_false(r["has_power"], "обрезанное поле не помечено как присутствующее")
	assert_eq(r["power_w"], 0)
	for h in ["", "44", "44 00", "44 00 48", "FE 1F 48 0D"]:
		var t := FtmsCodec.decode_indoor_bike_data(_hex(h))
		assert_false(t["ok"], "обрезанный пакет «%s» → ok false" % h)
		assert_false(t["has_power"])


# ---------------------------------------------------------------------------
# REQ-DEV-02 крит. 3 — ответ Control Point
# ---------------------------------------------------------------------------

func test_req_dev_02_c3_control_point_response_success_and_errors() -> void:
	var ok := FtmsCodec.decode_control_point_response(_hex("80 05 01"))
	assert_true(ok["ok"])
	assert_true(ok["success"], "80 05 01 — успех")
	assert_eq(ok["request_opcode"], 0x05)
	assert_eq(ok["result"], 0x01)
	var table := {"80 05 02": "not_supported", "80 05 03": "invalid_parameter", "80 05 04": "operation_failed",
		"80 00 05": "control_not_permitted"}
	for h in table:
		var r := FtmsCodec.decode_control_point_response(_hex(h))
		assert_true(r["ok"], "%s — распознан как ответ" % h)
		assert_false(r["success"], "%s — result != 0x01 → ошибка команды" % h)
		assert_eq(FtmsCodec.result_name(r["result"]), table[h])
	# Не ответ / короткий пакет — не ok, не падает.
	assert_false(FtmsCodec.decode_control_point_response(_hex("80 05"))["ok"])
	assert_false(FtmsCodec.decode_control_point_response(_hex("05 FA 00"))["ok"])
	assert_false(FtmsCodec.decode_control_point_response(_hex(""))["ok"])
	assert_false(FtmsCodec.decode_control_point_response(_hex("80 05"))["success"])
	# Ответ с параметрами.
	var p := FtmsCodec.decode_control_point_response(_hex("80 00 01 AA BB"))
	assert_true(p["success"])
	assert_eq(_hex_of(p["parameters"]), "AA BB")


func test_req_dev_02_c3_control_point_error_arrives_as_indication_via_stub() -> void:
	_stub.fail_next_control_point(FtmsCodec.RESULT_INVALID_PARAMETER)
	_stub.write(DEV, "1826", "2AD9", FtmsCodec.encode_set_target_power(250), true)
	assert_eq(_events.size(), 0, "до pump() ничего не пришло — асинхронно")
	_stub.pump()
	var done := _of("write_done")
	assert_eq(done.size(), 1)
	assert_true(done[0]["ok"], "сама запись прошла")
	var ind := _of("notify")
	assert_eq(ind.size(), 1, "индикация Control Point")
	assert_eq(ind[0]["char"], "2AD9")
	assert_eq(_hex_of(ind[0]["bytes"]), "80 05 03")
	var r := FtmsCodec.decode_control_point_response(ind[0]["bytes"])
	assert_false(r["success"], "фиксируется как ошибка команды")
	# Следующая запись — снова успех (сценарий одноразовый).
	_events.clear()
	_stub.write(DEV, "1826", "2AD9", FtmsCodec.encode_set_target_power(200), true)
	_stub.pump()
	assert_eq(_hex_of(_of("notify")[0]["bytes"]), "80 05 01")


# ---------------------------------------------------------------------------
# REQ-DEV-02 крит. 4, 5 — кодирование команд
# ---------------------------------------------------------------------------

func test_req_dev_02_c4_set_target_power_bytes() -> void:
	assert_eq(_hex_of(FtmsCodec.encode_set_target_power(250)), "05 FA 00", "250 Вт → 05 FA 00")
	assert_eq(_hex_of(FtmsCodec.encode_set_target_power(0)), "05 00 00")
	assert_eq(_hex_of(FtmsCodec.encode_set_target_power(1000)), "05 E8 03")
	assert_eq(_hex_of(FtmsCodec.encode_set_target_power(32767)), "05 FF 7F")
	assert_eq(_hex_of(FtmsCodec.encode_set_target_power(-10)), "05 F6 FF", "отрицательная цель — sint16 в доп. коде")
	assert_eq(_hex_of(FtmsCodec.encode_set_target_power(-32768)), "05 00 80")
	assert_eq(_hex_of(FtmsCodec.encode_set_target_power(40000)), "05 FF 7F", "вне sint16 — клампится, не переполняется")
	assert_eq(_hex_of(FtmsCodec.encode_set_target_power(-40000)), "05 00 80")
	assert_eq(_hex_of(FtmsCodec.encode_request_control()), "00")


func test_req_dev_02_c5_set_target_resistance_level_bytes() -> void:
	assert_eq(_hex_of(FtmsCodec.encode_set_resistance_level(5.0)), "04 32", "уровень 5.0 → 04 32")
	assert_eq(_hex_of(FtmsCodec.encode_set_resistance_level(0.0)), "04 00")
	assert_eq(_hex_of(FtmsCodec.encode_set_resistance_level(0.3)), "04 03", "0.3 / 0.1 = 3 (без ошибки float)")
	assert_eq(_hex_of(FtmsCodec.encode_set_resistance_level(10.0)), "04 64")
	assert_eq(_hex_of(FtmsCodec.encode_set_resistance_level(25.5)), "04 FF", "максимум uint8")
	assert_eq(_hex_of(FtmsCodec.encode_set_resistance_level(-3.0)), "04 00", "отрицательный — 0")
	assert_eq(_hex_of(FtmsCodec.encode_set_resistance_level(99.0)), "04 FF", "выше 25.5 — клампится")


# ---------------------------------------------------------------------------
# REQ-DEV-03 — HRS 2A37
# ---------------------------------------------------------------------------

func test_req_dev_03_c1_heart_rate_uint8_and_uint16_formats() -> void:
	var r8 := HrsCodec.decode_heart_rate_measurement(_hex("00 48"))
	assert_true(r8["ok"])
	assert_eq(r8["bpm"], 72, "00 48 → 72")
	var r16 := HrsCodec.decode_heart_rate_measurement(_hex("01 48 00"))
	assert_true(r16["ok"])
	assert_eq(r16["bpm"], 72, "01 48 00 → 72")
	assert_eq(HrsCodec.decode_heart_rate_measurement(_hex("01 2C 01"))["bpm"], 300, "uint16 > 255")
	assert_eq(HrsCodec.decode_heart_rate_measurement(_hex("00 FF"))["bpm"], 255)
	assert_eq(HrsCodec.decode_heart_rate_measurement(_hex("00 00"))["bpm"], 0)
	# Подписка на 2A37 через мост нормализует UUID.
	_stub.subscribe(DEV, "0000180d-0000-1000-8000-00805f9b34fb", "0x2a37")
	assert_true(_stub.is_subscribed(DEV, "180D", "2A37"))
	var c := _stub.calls_of("subscribe")[0]
	assert_eq(c["service"], "180D")
	assert_eq(c["char"], "2A37")


func test_req_dev_03_c1_heart_rate_optional_fields_and_truncation() -> void:
	# Энергия (бит3) uint16 кДж: 08 48 10 27 → 72, 10000 кДж.
	var e := HrsCodec.decode_heart_rate_measurement(_hex("08 48 10 27"))
	assert_true(e["ok"])
	assert_eq(e["bpm"], 72)
	assert_true(e["has_energy"])
	assert_eq(e["energy_kj"], 10000)
	# RR (бит4): 10 48 00 04 00 02 → RR 1024 → 1000 мс, 512 → 500 мс.
	var rr := HrsCodec.decode_heart_rate_measurement(_hex("10 48 00 04 00 02"))
	assert_true(rr["ok"])
	var intervals: Array = rr["rr_intervals_ms"]
	assert_eq(intervals.size(), 2)
	assert_almost_eq(float(intervals[0]), 1000.0, 1e-6)
	assert_almost_eq(float(intervals[1]), 500.0, 1e-6)
	# Всё вместе: uint16 + энергия + RR → 19 48 00 10 27 00 04.
	var all := HrsCodec.decode_heart_rate_measurement(_hex("19 48 00 10 27 00 04"))
	assert_true(all["ok"])
	assert_eq(all["bpm"], 72)
	assert_eq(all["energy_kj"], 10000)
	assert_eq((all["rr_intervals_ms"] as Array).size(), 1)
	# Обрезанные пакеты не роняют.
	for h in ["", "00", "01", "01 48", "08 48 10"]:
		var t := HrsCodec.decode_heart_rate_measurement(_hex(h))
		assert_false(t["ok"], "обрезанный «%s» → ok false" % h)


func test_req_dev_03_c2_sensor_contact_flags() -> void:
	# Биты 1–2: значение 2 (бит2=1, бит1=0 → 0x04) — поддерживается, контакта нет;
	# 3 (0x06) — контакт есть; 0/1 (0x00/0x02) — не поддерживается.
	var no_contact := HrsCodec.decode_heart_rate_measurement(_hex("04 48"))
	assert_true(no_contact["ok"])
	assert_eq(no_contact["sensor_contact"], HrsCodec.SensorContact.NOT_DETECTED)
	assert_false(no_contact["contact_ok"], "нет контакта → пульс недостоверен, в поток не писать")
	assert_eq(no_contact["bpm"], 72, "значение всё же разобрано (для диагностики)")
	var contact := HrsCodec.decode_heart_rate_measurement(_hex("06 48"))
	assert_eq(contact["sensor_contact"], HrsCodec.SensorContact.DETECTED)
	assert_true(contact["contact_ok"])
	var unsupported := HrsCodec.decode_heart_rate_measurement(_hex("00 48"))
	assert_eq(unsupported["sensor_contact"], HrsCodec.SensorContact.NOT_SUPPORTED)
	assert_true(unsupported["contact_ok"], "функция контакта не поддерживается → пульс считается достоверным")
	var unsupported2 := HrsCodec.decode_heart_rate_measurement(_hex("02 48"))
	assert_eq(unsupported2["sensor_contact"], HrsCodec.SensorContact.NOT_SUPPORTED, "значение 1 поля контакта = не поддерживается")
	assert_true(unsupported2["contact_ok"])
	# Контакт + uint16-формат: 05 48 00 → поддерживается, нет контакта.
	var mixed := HrsCodec.decode_heart_rate_measurement(_hex("05 48 00"))
	assert_false(mixed["contact_ok"])
	assert_eq(mixed["bpm"], 72)


# ---------------------------------------------------------------------------
# REQ-DEV-04 — CSC 2A5B и каденс
# ---------------------------------------------------------------------------

func test_req_dev_04_c1_csc_crank_pair_gives_90_rpm() -> void:
	# Флаг 0x02 — crank data: обороты uint16, время uint16 (1/1024 с).
	var m1 := CscCodec.decode_csc_measurement(_hex("02 0A 00 00 08"))  # rev 10, t 2048
	var m2 := CscCodec.decode_csc_measurement(_hex("02 0D 00 00 10"))  # rev 13, t 4096
	assert_true(m1["ok"] and m2["ok"])
	assert_true(m1["has_crank"])
	assert_false(m1["has_wheel"])
	assert_eq(m1["crank_revolutions"], 10)
	assert_eq(m1["crank_event_time"], 2048)
	assert_eq(m2["crank_revolutions"], 13)
	assert_eq(m2["crank_event_time"], 4096)
	assert_almost_eq(CscCodec.cadence_from_pair(m1, m2), 90.0, 1e-6, "Δrev 3 / (Δt 2048/1024) × 60 = 90")
	var calc := CscCadenceCalculator.new()
	assert_eq(calc.push(m1, 0.0), -1, "первое измерение — ещё нет пары")
	assert_eq(calc.push(m2, 2.0), 90, "вторая фикстура → 90 rpm")
	# Другие соотношения.
	var a := CscCodec.decode_csc_measurement(_hex("02 00 00 00 00"))
	var b := CscCodec.decode_csc_measurement(_hex("02 01 00 00 02"))  # 1 оборот за 512/1024 = 0.5 с → 120
	assert_almost_eq(CscCodec.cadence_from_pair(a, b), 120.0, 1e-6)


func test_req_dev_04_c1_csc_wheel_and_crank_layout_and_truncation() -> void:
	# Флаги 0x03: wheel uint32 (1000) + uint16 (512), затем crank uint16 (20) + uint16 (1024).
	var m := CscCodec.decode_csc_measurement(_hex("03 E8 03 00 00 00 02 14 00 00 04"))
	assert_true(m["ok"])
	assert_true(m["has_wheel"])
	assert_eq(m["wheel_revolutions"], 1000)
	assert_eq(m["wheel_event_time"], 512)
	assert_true(m["has_crank"])
	assert_eq(m["crank_revolutions"], 20)
	assert_eq(m["crank_event_time"], 1024)
	# Только wheel (0x01), 32-битный счётчик с старшими байтами.
	var w := CscCodec.decode_csc_measurement(_hex("01 01 00 01 00 00 00"))
	assert_eq(w["wheel_revolutions"], 65537)
	assert_false(w["has_crank"])
	# Обрезанные: не ok, не падают.
	for h in ["", "02", "02 0A 00", "02 0A 00 00", "03 E8 03 00 00 00 02 14 00", "01 E8 03"]:
		var t := CscCodec.decode_csc_measurement(_hex(h))
		assert_false(t["ok"], "обрезанный «%s» → ok false" % h)
	var t2 := CscCodec.decode_csc_measurement(_hex("03 E8 03 00 00 00 02 14 00"))
	assert_true(t2["has_wheel"], "wheel разобран до обрыва")
	assert_false(t2["has_crank"], "crank обрезан — не помечен присутствующим")


func test_req_dev_04_c2_uint16_rollover_of_time_and_revolutions_is_positive() -> void:
	# Время 65535 → 10 (Δt = 11), обороты 65534 → 1 (Δrev = 3).
	var prev := {"crank_revolutions": 65534, "crank_event_time": 65535}
	var cur := {"crank_revolutions": 1, "crank_event_time": 10}
	var rpm := CscCodec.cadence_from_pair(prev, cur)
	assert_gt(rpm, 0.0, "переполнение не даёт отрицательных значений")
	assert_almost_eq(rpm, 3.0 / (11.0 / 1024.0) * 60.0, 1e-6)
	# Реалистичный: Δt = 2048 через переполнение времени, Δrev = 3 через переполнение оборотов → 90.
	var p2 := {"crank_revolutions": 65534, "crank_event_time": 65000}
	var c2 := {"crank_revolutions": 1, "crank_event_time": (65000 + 2048) % 65536}
	assert_almost_eq(CscCodec.cadence_from_pair(p2, c2), 90.0, 1e-6)
	# Байтовый уровень: FF FF → 0A 00.
	var b1 := CscCodec.decode_csc_measurement(_hex("02 FE FF FF FF"))
	var b2 := CscCodec.decode_csc_measurement(_hex("02 01 00 0A 00"))
	assert_gt(CscCodec.cadence_from_pair(b1, b2), 0.0)
	var calc := CscCadenceCalculator.new()
	calc.push(b1, 0.0)
	assert_gt(calc.push(b2, 1.0), 0, "калькулятор: после переполнения каденс положительный")
	# Переполнение колеса uint32 тоже положительно.
	var wp := {"wheel_revolutions": 4294967295, "wheel_event_time": 1000}
	var wc := {"wheel_revolutions": 1, "wheel_event_time": 2024}
	assert_gt(CscCodec.wheel_speed_from_pair(wp, wc, 2100.0), 0.0)


func test_req_dev_04_c2_delta_time_zero_is_no_data_not_division_by_zero() -> void:
	var m := {"has_crank": true, "crank_revolutions": 10, "crank_event_time": 2048}
	assert_eq(CscCodec.cadence_from_pair(m, m), -1.0, "Δt = 0 → нет данных, без деления на ноль")
	var m_rev := {"has_crank": true, "crank_revolutions": 11, "crank_event_time": 2048}
	assert_eq(CscCodec.cadence_from_pair(m, m_rev), -1.0, "Δt = 0 при Δrev > 0 — тоже нет данных")
	assert_eq(CscCodec.wheel_speed_from_pair({"wheel_revolutions": 1, "wheel_event_time": 5},
		{"wheel_revolutions": 2, "wheel_event_time": 5}, 2100.0), -1.0)


func test_req_dev_04_c3_no_new_revolutions_for_3s_after_valid_cadence_gives_zero() -> void:
	var calc := CscCadenceCalculator.new()
	var m1 := {"has_crank": true, "crank_revolutions": 10, "crank_event_time": 2048}
	var m2 := {"has_crank": true, "crank_revolutions": 13, "crank_event_time": 4096}
	calc.push(m1, 0.0)
	assert_eq(calc.push(m2, 2.0), 90)
	assert_eq(calc.push(m2, 3.0), 90, "1 с без оборотов — держим последнее")
	assert_eq(calc.push(m2, 4.9), 90, "2.9 с — ещё держим")
	assert_eq(calc.push(m2, 5.0), 0, "3 с подряд без новых оборотов → 0")
	assert_eq(calc.current(10.0), 0)
	assert_eq(calc.push(m2, 12.0), 0)
	# Новый оборот — каденс снова считается.
	var m3 := {"has_crank": true, "crank_revolutions": 14, "crank_event_time": 4096 + 1024}
	assert_eq(calc.push(m3, 13.0), 60, "1 оборот за 1 с → 60 rpm")
	# Измерение без crank data не портит состояние.
	assert_eq(calc.push({"has_crank": false}, 13.5), 60)
	calc.reset()
	assert_eq(calc.current(14.0), -1, "после reset — нет данных")


func test_req_dev_04_c3_identical_measurements_from_start_give_zero_after_3s() -> void:
	# Датчик подключён, педали не крутятся: все измерения одинаковы с самого начала.
	# REQ-DEV-04 крит. 3 безусловен: нет новых оборотов 3 с подряд → каденс 0.
	var calc := CscCadenceCalculator.new()
	var m := {"has_crank": true, "crank_revolutions": 10, "crank_event_time": 2048}
	assert_eq(calc.push(m, 0.0), -1, "первое измерение — нет пары")
	calc.push(m, 1.0)
	calc.push(m, 2.0)
	assert_eq(calc.push(m, 3.0), 0, "3 с одинаковых измерений (нет новых оборотов) → 0, а не «нет данных»")
	assert_eq(calc.current(4.0), 0)


# ---------------------------------------------------------------------------
# REQ-DEV-05 — CPS 2A63
# ---------------------------------------------------------------------------

func test_req_dev_05_c1_cps_instant_power_sint16_at_offset_2() -> void:
	var r := CpsCodec.decode_cycling_power_measurement(_hex("00 00 FA 00"))
	assert_true(r["ok"])
	assert_eq(r["power_w"], 250, "00 00 FA 00 → 250 Вт")
	assert_false(r["has_crank"])
	assert_eq(CpsCodec.decode_cycling_power_measurement(_hex("00 00 06 FF"))["power_w"], -250, "sint16: 06 FF = −250")
	assert_eq(CpsCodec.decode_cycling_power_measurement(_hex("00 00 00 80"))["power_w"], -32768)
	# Флаги не влияют на смещение мощности: баланс педалей (бит0) идёт ПОСЛЕ мощности.
	var b := CpsCodec.decode_cycling_power_measurement(_hex("01 00 FA 00 64"))
	assert_eq(b["power_w"], 250)
	assert_true(b["has_balance"])
	assert_almost_eq(float(b["pedal_balance_pct"]), 50.0, 1e-6, "100 × 0.5 %")
	# Обрезанные.
	for h in ["", "00", "00 00", "00 00 FA", "01 00 FA 00", "20 00 FA 00 0A 00 00"]:
		var t := CpsCodec.decode_cycling_power_measurement(_hex(h))
		assert_false(t["ok"], "обрезанный «%s» → ok false" % h)
	var t3 := CpsCodec.decode_cycling_power_measurement(_hex("00 00 FA"))
	assert_eq(t3["power_w"], 0, "мощность обрезана — не читается мусор")


func test_req_dev_05_c3_cps_crank_data_feeds_cadence_calculator() -> void:
	# Флаг 0x0020 — Crank Revolution Data: uint16 обороты + uint16 время 1/1024 с.
	var m1 := CpsCodec.decode_cycling_power_measurement(_hex("20 00 FA 00 0A 00 00 08"))
	var m2 := CpsCodec.decode_cycling_power_measurement(_hex("20 00 FA 00 0D 00 00 10"))
	assert_true(m1["ok"] and m2["ok"])
	assert_true(m1["has_crank"])
	assert_eq(m1["crank_revolutions"], 10)
	assert_eq(m1["crank_event_time"], 2048)
	assert_eq(m2["power_w"], 250)
	var calc := CscCadenceCalculator.new()
	calc.push(m1, 0.0)
	assert_eq(calc.push(m2, 2.0), 90, "каденс из CPS crank data — 90 rpm")
	# Порядок полей по флагам: торк (бит2) и колесо (бит4) идут до crank (бит5).
	# 34 00 = биты 2, 4, 5: power 250 | torque 320 (10 Н·м) | wheel 1000 + 512 | crank 13 + 4096
	var full := CpsCodec.decode_cycling_power_measurement(_hex("34 00 FA 00 40 01 E8 03 00 00 00 02 0D 00 00 10"))
	assert_true(full["ok"])
	assert_true(full["has_torque"])
	assert_almost_eq(float(full["accumulated_torque_nm"]), 10.0, 1e-6)
	assert_true(full["has_wheel"])
	assert_eq(full["wheel_revolutions"], 1000)
	assert_eq(full["wheel_event_time"], 512)
	assert_true(full["has_crank"])
	assert_eq(full["crank_revolutions"], 13)
	assert_eq(full["crank_event_time"], 4096)
	# Поля после crank (бит11 — энергия) читаются после него.
	var en := CpsCodec.decode_cycling_power_measurement(_hex("20 08 FA 00 0D 00 00 10 2C 01"))
	assert_true(en["ok"])
	assert_eq(en["accumulated_energy_kj"], 300)


# ---------------------------------------------------------------------------
# REQ-DEV-07 крит. 2, 3 — заряд батареи через read_characteristic
# ---------------------------------------------------------------------------

func test_req_dev_07_c2_battery_level_read_via_bridge_and_notification() -> void:
	_stub.set_read_value("2A19", _hex("64"))
	_stub.read_characteristic(DEV, "180F", "2A19")
	var calls := _stub.calls_of("read_characteristic")
	assert_eq(calls.size(), 1, "вызов журналируется")
	assert_eq(calls[0]["id"], DEV)
	assert_eq(calls[0]["service"], "180F")
	assert_eq(calls[0]["char"], "2A19")
	assert_eq(_of("read").size(), 0, "ответ асинхронный — до pump() нет")
	assert_eq(_stub.pump(), 1)
	var reads := _of("read")
	assert_eq(reads.size(), 1)
	assert_eq(reads[0]["char"], "2A19")
	var lvl := BatteryCodec.decode_level(reads[0]["bytes"])
	assert_true(lvl["ok"])
	assert_eq(lvl["level_pct"], 100)
	# Обновление по нотификации Battery Level.
	_stub.emit_notification(DEV, "0x2a19", _hex("32"))
	var n := _of("notify")
	assert_eq(n.size(), 1)
	assert_eq(n[0]["char"], "2A19", "UUID нормализован")
	assert_eq(BatteryCodec.decode_level(n[0]["bytes"])["level_pct"], 50)
	assert_eq(BatteryCodec.decode_level(_hex("00"))["level_pct"], 0)
	assert_true(BatteryCodec.decode_level(_hex("00"))["ok"])


func test_req_dev_07_c3_missing_battery_service_is_error_not_crash_and_invalid_values_not_ok() -> void:
	_stub.read_characteristic(DEV, "180F", "2A19")
	_stub.pump()
	assert_eq(_of("read").size(), 0, "ответа с байтами нет")
	var errs := _of("error")
	assert_eq(errs.size(), 1, "ошибка сигналом, без падения")
	assert_eq(errs[0]["code"], BleBridge.ErrorCode.CHARACTERISTIC_NOT_FOUND)
	assert_eq(errs[0]["id"], DEV)
	# Невалидные значения → ok false («—», а не 255 %).
	assert_false(BatteryCodec.decode_level(_hex("FF"))["ok"], "255 — зарезервировано")
	assert_false(BatteryCodec.decode_level(_hex("65"))["ok"], "101 — вне диапазона")
	assert_false(BatteryCodec.decode_level(_hex(""))["ok"], "пусто")
	assert_true(BatteryCodec.decode_level(_hex("64 FF"))["ok"], "лишний хвост не мешает")
	assert_eq(BatteryCodec.decode_level(_hex("64 FF"))["level_pct"], 100)


# ---------------------------------------------------------------------------
# REQ-WRK-04 крит. 2 — перевод процента в уровень по 2AD6
# ---------------------------------------------------------------------------

func test_req_wrk_04_c2_resistance_range_decode_and_percent_translation() -> void:
	# 2AD6: min sint16 0, max sint16 1000 (100.0), increment uint16 10 (1.0).
	var rng := FtmsCodec.decode_resistance_range(_hex("00 00 E8 03 0A 00"))
	assert_true(rng["ok"])
	assert_almost_eq(float(rng["min_level"]), 0.0, 1e-9)
	assert_almost_eq(float(rng["max_level"]), 100.0, 1e-9)
	assert_almost_eq(float(rng["increment"]), 1.0, 1e-9)
	# Решение В-11 (уточнение WRK-04 крит. 2): проценты масштабируются на кодируемый
	# в uint8 ×0.1 поддиапазон [max(min,0); min(max,25.5)] с привязкой к increment.
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(50, rng), 13.0, 1e-9, "0..100.0 шаг 1.0: 50 % → 12.75 → 13.0")
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(0, rng), 0.0, 1e-9)
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(100, rng), 25.5, 1e-9, "100 % → потолок 25.5")
	var rng01 := FtmsCodec.decode_resistance_range(_hex("00 00 E8 03 01 00"))  # 0..100.0 шаг 0.1 (Neo)
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(50, rng01), 12.8, 1e-9, "50 % → 12.75 → 12.8")
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(33, rng01), 8.4, 1e-9, "33 % → 8.415 → 8.4")
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(100, rng01), 25.5, 1e-9)
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(0, rng01), 0.0, 1e-9)
	assert_eq(_hex_of(FtmsCodec.encode_set_resistance_level(FtmsCodec.percent_to_resistance_level(50, rng01))), "04 80")
	assert_eq(_hex_of(FtmsCodec.encode_set_resistance_level(FtmsCodec.percent_to_resistance_level(100, rng01))), "04 FF")
	assert_eq(_hex_of(FtmsCodec.encode_set_resistance_level(FtmsCodec.percent_to_resistance_level(0, rng01))), "04 00")
	# Монотонность: больший процент — не меньший уровень, уровни 25 % / 50 % / 100 % различимы.
	var prev_level := -1.0
	for pct in range(0, 101, 5):
		var lv := FtmsCodec.percent_to_resistance_level(pct, rng01)
		assert_true(lv >= prev_level, "монотонно: %d %% → %.1f" % [pct, lv])
		prev_level = lv
	assert_true(FtmsCodec.percent_to_resistance_level(25, rng01) < FtmsCodec.percent_to_resistance_level(50, rng01))
	assert_true(FtmsCodec.percent_to_resistance_level(50, rng01) < FtmsCodec.percent_to_resistance_level(100, rng01))
	# Диапазон с ненулевым min и шагом 0.5: 1.0..11.0, inc 0.5 → 50 % → 6.0; 33 % → 4.3 → 4.5.
	var rng2 := FtmsCodec.decode_resistance_range(_hex("0A 00 6E 00 05 00"))
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(50, rng2), 6.0, 1e-9)
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(33, rng2), 4.5, 1e-9, "привязка к шагу")
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(-5, rng2), 1.0, 1e-9, "процент клампится к 0")
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(150, rng2), 11.0, 1e-9)
	# Отрицательный min (sint16): −5.0..5.0 → кодируемый поддиапазон 0..5.0 → 50 % = 2.5.
	var rng3 := FtmsCodec.decode_resistance_range(_hex("CE FF 32 00 01 00"))
	assert_almost_eq(float(rng3["min_level"]), -5.0, 1e-9, "декодирование 2AD6 без изменений")
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(50, rng3), 2.5, 1e-9)
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(0, rng3), 0.0, 1e-9)
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(100, rng3), 5.0, 1e-9)


func test_req_wrk_04_c2_without_range_falls_back_to_linear_0_100_units() -> void:
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(50), 5.0, 1e-9, "без диапазона: 50 % → 5.0 (50 ед. 0.1)")
	assert_eq(_hex_of(FtmsCodec.encode_set_resistance_level(FtmsCodec.percent_to_resistance_level(50))), "04 32")
	assert_eq(_hex_of(FtmsCodec.encode_set_resistance_level(FtmsCodec.percent_to_resistance_level(100))), "04 64", "100 % → 100 ед.")
	assert_eq(_hex_of(FtmsCodec.encode_set_resistance_level(FtmsCodec.percent_to_resistance_level(0))), "04 00")
	# Невалидные/обрезанные ответы 2AD6 → тот же запасной вариант.
	var bad := FtmsCodec.decode_resistance_range(_hex("00 00 E8 03"))
	assert_false(bad["ok"], "обрезанный 2AD6 → not ok")
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(50, bad), 5.0, 1e-9)
	var flat := FtmsCodec.decode_resistance_range(_hex("64 00 64 00 0A 00"))
	assert_false(flat["ok"], "max == min → not ok")
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(50, flat), 5.0, 1e-9)
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(50, {}), 5.0, 1e-9)


func test_req_wrk_04_c2_range_read_through_stub_then_translated() -> void:
	_stub.set_read_value("2AD6", _hex("00 00 C8 00 0A 00"))  # 0..20.0 шаг 1.0
	_stub.read_characteristic(DEV, "1826", "2AD6")
	_stub.pump()
	var reads := _of("read")
	assert_eq(reads.size(), 1)
	assert_eq(reads[0]["char"], "2AD6")
	var rng := FtmsCodec.decode_resistance_range(reads[0]["bytes"])
	assert_true(rng["ok"])
	assert_almost_eq(float(rng["max_level"]), 20.0, 1e-9)
	var level := FtmsCodec.percent_to_resistance_level(50, rng)
	assert_almost_eq(level, 10.0, 1e-9)
	assert_eq(_hex_of(FtmsCodec.encode_set_resistance_level(level)), "04 64", "10.0 → 100 ед. → 04 64")
	# Ошибка чтения (fail_next_read) → error READ_FAILED, одноразово.
	_events.clear()
	_stub.fail_next_read()
	_stub.read_characteristic(DEV, "1826", "2AD6")
	_stub.pump()
	assert_eq(_of("read").size(), 0)
	assert_eq(_of("error")[0]["code"], BleBridge.ErrorCode.READ_FAILED)
	_events.clear()
	_stub.read_characteristic(DEV, "1826", "2AD6")
	_stub.pump()
	assert_eq(_of("read").size(), 1, "следующее чтение снова успешно")


func test_req_wrk_04_c2_observation_level_above_25_5_saturates_in_uint8_command() -> void:
	# Решение В-11: при 2AD6 шире кодируемого (uint8 ×0.1, макс. 25.5) проценты
	# масштабируются на [max(min,0); min(max,25.5)] — команда больше не насыщается молча.
	var rng := FtmsCodec.decode_resistance_range(_hex("00 00 E8 03 01 00"))  # 0..100.0 шаг 0.1
	var level := FtmsCodec.percent_to_resistance_level(50, rng)
	assert_almost_eq(level, 12.8, 1e-9, "50 % от кодируемого 0..25.5 → 12.8")
	assert_eq(_hex_of(FtmsCodec.encode_set_resistance_level(level)), "04 80", "12.8 → 128 ед. → 04 80")
	assert_true(level <= 25.5, "ни один уровень не выходит за кодируемый максимум")
	for pct in [1, 10, 49, 51, 90, 99, 100]:
		assert_true(FtmsCodec.percent_to_resistance_level(pct, rng) <= 25.5 + 1e-9, "%d %% в пределах 25.5" % pct)
	# Диапазон целиком выше кодируемого (30.0..40.0): отдаём максимум 25.5 для любого процента.
	var high := FtmsCodec.decode_resistance_range(_hex("2C 01 90 01 01 00"))
	assert_true(high["ok"], "сам 2AD6 валиден")
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(50, high), 25.5, 1e-9, "30..40 → 25.5")
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(0, high), 25.5, 1e-9)
	assert_eq(_hex_of(FtmsCodec.encode_set_resistance_level(FtmsCodec.percent_to_resistance_level(100, high))), "04 FF")
	# Диапазон внутри кодируемого (0..20.0 шаг 1.0) — масштабирование не вмешивается.
	var inner := FtmsCodec.decode_resistance_range(_hex("00 00 C8 00 0A 00"))
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(50, inner), 10.0, 1e-9)
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(100, inner), 20.0, 1e-9)


# ---------------------------------------------------------------------------
# REQ-NFR-06 крит. 1 — платформенные вызовы только в разрешённых файлах
# ---------------------------------------------------------------------------

func _collect_gd_files(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_collect_gd_files(full, out)
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


func _platform_call_violations() -> Array[String]:
	# REQ-NFR-06 крит. 1 (уточнение daf4ca8): три разрешённых места — `src/storage/secure_store*`,
	# каталог `src/devices/ble/` (прежде всего native_ble_bridge.gd), `src/app/locale.gd`.
	var allowed_prefixes := ["res://src/storage/secure_store", "res://src/devices/ble/"]
	var allowed_files := ["res://src/app/locale.gd"]
	var re := RegEx.new()
	re.compile("(\\bOS\\.|has_feature\\s*\\(|get_architecture_name\\s*\\()")
	var files: Array[String] = []
	_collect_gd_files("res://src", files)
	assert_gt(files.size(), 10, "в src/ найдены .gd файлы (%d)" % files.size())
	var violations: Array[String] = []
	for f in files:
		var allowed := allowed_files.has(f)
		for p in allowed_prefixes:
			if f.begins_with(p):
				allowed = true
		var text := FileAccess.get_file_as_string(f)
		var lines := text.split("\n")
		for i in lines.size():
			var line: String = lines[i]
			if line.strip_edges().begins_with("#"):
				continue
			if re.search(line) != null and not allowed:
				violations.append("%s:%d: %s" % [f, i + 1, line.strip_edges()])
	return violations


func test_req_nfr_06_c1_platform_calls_only_in_secure_store_and_native_ble_bridge() -> void:
	var violations := _platform_call_violations()
	assert_eq(violations.size(), 0,
		"платформенные вызовы вне src/storage/secure_store*, src/devices/ble/ и src/app/locale.gd: %s" % str(violations))


func test_req_nfr_06_c1_ble_layer_itself_has_no_platform_branching() -> void:
	# Внутри BLE-слоя (кроме native_ble_bridge.gd) и кодеков — ни одного платформенного вызова.
	var re := RegEx.new()
	re.compile("(\\bOS\\.|has_feature|get_architecture_name|get_name\\(\\))")
	var files: Array[String] = []
	_collect_gd_files("res://src/devices/ble", files)
	assert_gt(files.size(), 8)
	for f in files:
		if f == "res://src/devices/ble/native_ble_bridge.gd":
			continue
		var text := FileAccess.get_file_as_string(f)
		for line in text.split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			assert_null(re.search(line), "%s: платформенный вызов: %s" % [f, line.strip_edges()])
	# Сам NativeBleBridge лишь проверяет наличие класса — без ветвлений по платформе.
	var native_text := FileAccess.get_file_as_string("res://src/devices/ble/native_ble_bridge.gd")
	assert_false(native_text.contains("OS."), "в обёртке нет вызовов OS")
	assert_true(native_text.contains("ClassDB.class_exists"), "проверка — только наличие нативного класса")


# ---------------------------------------------------------------------------
# REQ-NFR-06 крит. 5 — чтение характеристик только через BleBridge.read_characteristic
# ---------------------------------------------------------------------------

func test_req_nfr_06_c5_read_path_exists_only_in_devices_layer() -> void:
	var files: Array[String] = []
	_collect_gd_files("res://src", files)
	var outside: Array[String] = []
	for f in files:
		if f.begins_with("res://src/devices/"):
			continue
		var text := FileAccess.get_file_as_string(f)
		if text.contains("read_characteristic") or text.contains("characteristic_read"):
			outside.append(f)
	assert_eq(outside.size(), 0, "вне src/devices/ нет пути чтения характеристик: %s" % str(outside))
	# В контракте операция и сигнал есть; у заглушки и нативной обёртки — реализованы.
	assert_true(BleBridge.new().has_method("read_characteristic"))
	assert_true(BleBridge.new().has_signal("characteristic_read"))
	for script_path in ["res://src/devices/ble/stub_ble_bridge.gd", "res://src/devices/ble/native_ble_bridge.gd"]:
		var src := FileAccess.get_file_as_string(script_path)
		assert_true(src.contains("func read_characteristic("), "%s реализует read_characteristic" % script_path)


func test_req_nfr_06_c5_stub_read_is_async_journaled_and_returns_configured_bytes() -> void:
	_stub.set_read_value("0x2ad6", _hex("00 00 C8 00 0A 00"))
	_stub.set_read_value("2A19", _hex("5A"))
	_stub.read_characteristic(DEV, "1826", "00002ad6-0000-1000-8000-00805f9b34fb")
	_stub.read_characteristic(DEV, "180F", "2A19")
	assert_eq(_stub.calls_of("read_characteristic").size(), 2, "оба вызова в журнале")
	assert_eq(_stub.calls_of("read_characteristic")[0]["char"], "2AD6", "UUID в журнале нормализован")
	assert_eq(_of("read").size(), 0, "ответов до pump() нет")
	assert_eq(_stub.pump(), 2, "pump доставил два ответа")
	var reads := _of("read")
	assert_eq(reads.size(), 2)
	assert_eq(reads[0]["char"], "2AD6")
	assert_eq(_hex_of(reads[0]["bytes"]), "00 00 C8 00 0A 00")
	assert_eq(reads[1]["char"], "2A19")
	assert_eq(_hex_of(reads[1]["bytes"]), "5A")
	assert_eq(_stub.pump(), 0, "очередь пуста")
	# Байты ответа — копия: правка внешнего массива не меняет заготовку.
	var src := _hex("64")
	_stub.set_read_value("2A19", src)
	src[0] = 0
	_events.clear()
	_stub.read_characteristic(DEV, "180F", "2A19")
	_stub.pump()
	assert_eq(_hex_of(_of("read")[0]["bytes"]), "64")


# ---------------------------------------------------------------------------
# Контракт моста (вводный абзац раздела DEV) и заглушка
# ---------------------------------------------------------------------------

func test_req_nfr_06_contract_operations_and_events_present_on_bridge_and_stub() -> void:
	# Операции контракта: start_scan, stop_scan, connect, disconnect, subscribe, write,
	# read_characteristic. Имена connect/disconnect заняты Object → connect_peripheral/
	# disconnect_peripheral; события value → notification, write_result → write_done (см. отчёт).
	var ops := {"start_scan": "start_scan", "stop_scan": "stop_scan", "connect": "connect_peripheral",
		"disconnect": "disconnect_peripheral", "subscribe": "subscribe", "write": "write",
		"read_characteristic": "read_characteristic"}
	var sigs := {"device_found": "device_found", "connected": "connected", "disconnected": "disconnected",
		"value": "notification", "characteristic_read": "characteristic_read", "write_result": "write_done"}
	var base := BleBridge.new()
	for op in ops:
		assert_true(base.has_method(ops[op]), "операция %s → %s есть в контракте" % [op, ops[op]])
		assert_true(_stub.has_method(ops[op]))
	for s in sigs:
		assert_true(base.has_signal(sigs[s]), "событие %s → %s есть в контракте" % [s, sigs[s]])
	# Сигнатуры событий по контракту.
	var sig_args := {}
	for info in base.get_signal_list():
		sig_args[info["name"]] = (info["args"] as Array).size()
	assert_eq(sig_args["device_found"], 4, "device_found(id, name, rssi, service_uuids)")
	assert_eq(sig_args["connected"], 1)
	assert_eq(sig_args["disconnected"], 2, "disconnected(id, reason)")
	assert_eq(sig_args["notification"], 3, "value(id, char_uuid, bytes)")
	assert_eq(sig_args["characteristic_read"], 3)
	assert_eq(sig_args["write_done"], 3, "write_result(id, char_uuid, ok)")
	# Заглушка переопределяет каждый метод контракта (базовые — push_error).
	for m in ["is_available", "start_scan", "stop_scan", "connect_peripheral", "disconnect_peripheral",
			"discover_services", "subscribe", "unsubscribe", "write", "read_characteristic", "get_adapter_state"]:
		var own := false
		for info in (_stub.get_script() as Script).get_script_method_list():
			if info["name"] == m:
				own = true
		assert_true(own, "StubBleBridge переопределяет %s" % m)
	assert_true(_stub.is_available())
	assert_eq(_stub.get_adapter_state(), BleBridge.AdapterState.POWERED_ON)


func test_req_nfr_06_create_default_without_gdextension_is_stub_and_native_is_safe() -> void:
	assert_false(NativeBleBridge.is_native_available(), "в контейнере GDExtension нет")
	var bridge := BleBridge.create_default()
	assert_true(bridge is StubBleBridge, "мост по умолчанию — заглушка")
	assert_true(bridge.is_available())
	var native := NativeBleBridge.new()
	assert_false(native.is_available())
	assert_eq(native.get_adapter_state(), BleBridge.AdapterState.UNSUPPORTED)
	var errs: Array[int] = []
	native.error.connect(func(_id: String, code: int, _m: String) -> void: errs.append(code))
	native.start_scan(BleUuids.SCAN_SERVICES)
	native.connect_peripheral(DEV)
	native.subscribe(DEV, "1826", "2AD2")
	native.write(DEV, "1826", "2AD9", _hex("00"), true)
	native.read_characteristic(DEV, "180F", "2A19")
	native.stop_scan()
	native.disconnect_peripheral(DEV)
	assert_eq(errs.size(), 7, "каждый вызов без модуля — error(ADAPTER_UNAVAILABLE), без падения")
	for c in errs:
		assert_eq(c, BleBridge.ErrorCode.ADAPTER_UNAVAILABLE)


func test_stub_connect_disconnect_async_journal_and_failure_injection() -> void:
	_stub.connect_peripheral(DEV)
	assert_eq(_stub.calls_of("connect_peripheral")[0]["id"], DEV)
	assert_eq(_of("connected").size(), 0, "connected приходит только после pump()")
	assert_false(_stub.connected_ids.has(DEV))
	_stub.pump()
	assert_eq(_of("connected").size(), 1)
	assert_true(_stub.connected_ids.has(DEV))
	_stub.subscribe(DEV, "1826", "2AD2")
	assert_true(_stub.is_subscribed(DEV, "1826", "2AD2"))
	_stub.disconnect_peripheral(DEV)
	_stub.pump()
	var d := _of("disconnected")
	assert_eq(d.size(), 1)
	assert_eq(d[0]["reason"], BleBridge.DisconnectReason.REQUESTED)
	assert_false(_stub.connected_ids.has(DEV))
	assert_false(_stub.is_subscribed(DEV, "1826", "2AD2"), "подписки сброшены при отключении")
	# Ошибка подключения — одноразовая.
	_events.clear()
	_stub.fail_next_connect()
	_stub.connect_peripheral(DEV)
	_stub.pump()
	assert_eq(_of("connected").size(), 0)
	assert_eq(_of("error")[0]["code"], BleBridge.ErrorCode.CONNECTION_FAILED)
	_events.clear()
	_stub.connect_peripheral(DEV)
	_stub.pump()
	assert_eq(_of("connected").size(), 1, "следующее подключение успешно")
	# Обрыв по сценарию.
	_stub.emit_disconnected(DEV)
	assert_eq(_of("disconnected")[0]["reason"], BleBridge.DisconnectReason.LINK_LOSS)


func test_stub_write_journal_fail_next_write_and_service_discovery() -> void:
	var bytes := FtmsCodec.encode_set_target_power(250)
	_stub.write(DEV, "0x1826", "0x2ad9", bytes, true)
	var w := _stub.writes_to("2AD9")
	assert_eq(w.size(), 1)
	assert_eq(_hex_of(w[0]["bytes"]), "05 FA 00", "байты записи в журнале")
	assert_true(w[0]["with_response"])
	assert_eq(w[0]["service"], "1826")
	bytes[1] = 0x00
	assert_eq(_hex_of(w[0]["bytes"]), "05 FA 00", "журнал хранит копию байтов")
	_stub.pump()
	assert_true(_of("write_done")[0]["ok"])
	assert_eq(_of("notify").size(), 1, "успешная запись в CP → индикация 80 05 01")
	# fail_next_write: write_done false и без индикации.
	_events.clear()
	_stub.fail_next_write()
	_stub.write(DEV, "1826", "2AD9", FtmsCodec.encode_request_control(), true)
	_stub.pump()
	assert_false(_of("write_done")[0]["ok"])
	assert_eq(_of("notify").size(), 0, "при неудачной записи индикации нет")
	# Запись не в Control Point — без индикации.
	_events.clear()
	_stub.write(DEV, "1818", "2A66", _hex("0C"), false)
	_stub.pump()
	assert_true(_of("write_done")[0]["ok"])
	assert_eq(_of("notify").size(), 0)
	# discover_services отдаёт нормализованные сервисы асинхронно.
	_stub.set_device_services(DEV, {"0x1826": ["0x2ad2", "0x2ad9", "2ADA", "2AD6"], "180f": ["2a19"]})
	_stub.discover_services(DEV)
	assert_eq(_of("services").size(), 0)
	_stub.pump()
	var svc: Dictionary = _of("services")[0]["services"]
	assert_true(svc.has("1826"))
	assert_true(svc.has("180F"))
	assert_true((svc["1826"] as PackedStringArray).has("2AD6"))
	assert_true((svc["180F"] as PackedStringArray).has("2A19"))
	# Неизвестное устройство — пустой словарь, не падение.
	_events.clear()
	_stub.discover_services("ghost")
	_stub.pump()
	assert_eq((_of("services")[0]["services"] as Dictionary).size(), 0)


func test_ble_uuids_normalize_forms() -> void:
	assert_eq(BleUuids.normalize("2ad2"), "2AD2")
	assert_eq(BleUuids.normalize("0x2AD2"), "2AD2")
	assert_eq(BleUuids.normalize(" 0x2ad2 "), "2AD2")
	assert_eq(BleUuids.normalize("00002ad2-0000-1000-8000-00805f9b34fb"), "2AD2", "полный Base UUID → короткий")
	assert_eq(BleUuids.normalize("00002AD2"), "2AD2")
	assert_eq(BleUuids.to_full("2AD2"), "00002AD2-0000-1000-8000-00805F9B34FB")
	var custom := "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
	assert_eq(BleUuids.normalize(custom), custom.to_upper(), "128-битный не на базе SIG — целиком")
	assert_eq(BleUuids.to_full(custom), custom.to_upper())
	assert_true(BleUuids.equals("0x2ad9", "00002AD9-0000-1000-8000-00805F9B34FB"))
	assert_false(BleUuids.equals("2AD9", "2ADA"))
