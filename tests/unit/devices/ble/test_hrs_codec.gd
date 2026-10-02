extends GutTest
## Тесты кодека HRS (REQ-DEV-03 крит. 1, 2). Векторы `00 48`, `01 48 00` — из
## requirements.md; остальные собраны по раскладке GSS §Heart Rate Measurement.


func _hex(s: String) -> PackedByteArray:
	return BleBytes.from_hex(s)


func test_uint8_format_00_48_is_72() -> void:
	var r := HrsCodec.decode_heart_rate_measurement(_hex("00 48"))
	assert_true(r["ok"])
	assert_eq(r["bpm"], 72, "REQ-DEV-03 крит. 1")
	assert_eq(r["sensor_contact"], HrsCodec.SensorContact.NOT_SUPPORTED)
	assert_true(r["contact_ok"], "контакт не поддерживается — пульс считаем достоверным")


func test_uint16_format_01_48_00_is_72() -> void:
	var r := HrsCodec.decode_heart_rate_measurement(_hex("01 48 00"))
	assert_true(r["ok"])
	assert_eq(r["bpm"], 72, "REQ-DEV-03 крит. 1")
	var big := HrsCodec.decode_heart_rate_measurement(_hex("01 2C 01"))
	assert_eq(big["bpm"], 300, "uint16 > 255")


func test_sensor_contact_detected_and_not_detected() -> void:
	# 0x06 = биты 1,2: поддерживается и обнаружен.
	var det := HrsCodec.decode_heart_rate_measurement(_hex("06 48"))
	assert_eq(det["sensor_contact"], HrsCodec.SensorContact.DETECTED)
	assert_true(det["contact_ok"])
	# 0x04 = бит 2: поддерживается, не обнаружен → недостоверно (REQ-DEV-03 крит. 2).
	var nd := HrsCodec.decode_heart_rate_measurement(_hex("04 48"))
	assert_eq(nd["sensor_contact"], HrsCodec.SensorContact.NOT_DETECTED)
	assert_false(nd["contact_ok"])
	assert_eq(nd["bpm"], 72, "значение всё равно разобрано")


func test_energy_expended_and_rr_intervals() -> void:
	# 0x18 = биты 3,4: энергия uint16 (0x2710 = 10000 кДж) + RR 0x0400 = 1024 → 1000 мс, 0x0200 → 500 мс.
	var r := HrsCodec.decode_heart_rate_measurement(_hex("18 48 10 27 00 04 00 02"))
	assert_true(r["ok"])
	assert_true(r["has_energy"])
	assert_eq(r["energy_kj"], 10000)
	var rr: Array[float] = r["rr_intervals_ms"]
	assert_eq(rr.size(), 2)
	assert_almost_eq(rr[0], 1000.0, 1e-6)
	assert_almost_eq(rr[1], 500.0, 1e-6)


func test_truncated_packets_not_ok() -> void:
	assert_false(HrsCodec.decode_heart_rate_measurement(_hex("00"))["ok"])
	assert_false(HrsCodec.decode_heart_rate_measurement(_hex("01 48"))["ok"], "uint16 обрезан")
	assert_false(HrsCodec.decode_heart_rate_measurement(_hex("08 48 10"))["ok"], "энергия обрезана")
	assert_false(HrsCodec.decode_heart_rate_measurement(PackedByteArray())["ok"])


func test_encode_roundtrip() -> void:
	assert_eq(BleBytes.to_hex(HrsCodec.encode_heart_rate_measurement(72)), "00 48")
	assert_eq(BleBytes.to_hex(HrsCodec.encode_heart_rate_measurement(72, HrsCodec.SensorContact.DETECTED)), "06 48")
	assert_eq(BleBytes.to_hex(HrsCodec.encode_heart_rate_measurement(72, HrsCodec.SensorContact.NOT_DETECTED)), "04 48")
	assert_eq(BleBytes.to_hex(HrsCodec.encode_heart_rate_measurement(300)), "01 2C 01")
	assert_eq(HrsCodec.decode_heart_rate_measurement(HrsCodec.encode_heart_rate_measurement(300))["bpm"], 300)
