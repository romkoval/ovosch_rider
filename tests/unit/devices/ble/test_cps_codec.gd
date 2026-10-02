extends GutTest
## Тесты кодека CPS (REQ-DEV-05 крит. 1, 3). Вектор `00 00 FA 00` — из requirements.md;
## остальные собраны по раскладке CPS v1.1 §3.2 / GSS §Cycling Power Measurement.


func _hex(s: String) -> PackedByteArray:
	return BleBytes.from_hex(s)


func test_power_only_00_00_fa_00_is_250() -> void:
	var r := CpsCodec.decode_cycling_power_measurement(_hex("00 00 FA 00"))
	assert_true(r["ok"])
	assert_eq(r["power_w"], 250, "REQ-DEV-05 крит. 1")
	assert_false(r["has_crank"])
	assert_false(r["has_wheel"])
	assert_false(r["has_balance"])


func test_negative_power_sint16() -> void:
	assert_eq(CpsCodec.decode_cycling_power_measurement(_hex("00 00 06 FF"))["power_w"], -250)


func test_crank_data_for_cadence() -> void:
	# flags 0x0020: crank; power 250; revs 10; time 1024.
	var a := CpsCodec.decode_cycling_power_measurement(_hex("20 00 FA 00 0A 00 00 04"))
	assert_true(a["has_crank"])
	assert_eq(a["crank_revolutions"], 10)
	assert_eq(a["crank_event_time"], 1024)
	var b := CpsCodec.decode_cycling_power_measurement(_hex("20 00 FA 00 0D 00 00 0C"))
	assert_almost_eq(CscCodec.cadence_from_pair(a, b), 90.0, 1e-9, "REQ-DEV-05 крит. 3: каденс из CPS теми же ключами")
	var calc := CscCadenceCalculator.new()
	calc.push(a, 0.0)
	assert_eq(calc.push(b, 2.0), 90)


func test_pedal_balance_and_torque_precede_crank() -> void:
	# flags 0x0025: balance (бит 0) + torque (бит 2) + crank (бит 5).
	# balance 0x64 = 100 → 50.0 %; torque 0x0040 = 64 → 2.0 Н·м; crank 10 / 1024.
	var r := CpsCodec.decode_cycling_power_measurement(_hex("25 00 FA 00 64 40 00 0A 00 00 04"))
	assert_true(r["ok"])
	assert_true(r["has_balance"])
	assert_almost_eq(r["pedal_balance_pct"], 50.0, 1e-9)
	assert_true(r["has_torque"])
	assert_almost_eq(r["accumulated_torque_nm"], 2.0, 1e-9)
	assert_eq(r["crank_revolutions"], 10)
	assert_eq(r["crank_event_time"], 1024)


func test_wheel_data_uses_uint32_and_precedes_crank() -> void:
	# flags 0x0030: wheel (бит 4) + crank (бит 5). wheel revs 0x000186A0 = 100000, time 0x0800.
	var r := CpsCodec.decode_cycling_power_measurement(_hex("30 00 FA 00 A0 86 01 00 00 08 0A 00 00 04"))
	assert_true(r["ok"])
	assert_true(r["has_wheel"])
	assert_eq(r["wheel_revolutions"], 100000)
	assert_eq(r["wheel_event_time"], 2048)
	assert_eq(r["crank_revolutions"], 10)
	assert_almost_eq(CpsCodec.WHEEL_EVENT_TIME_HZ, 2048.0, 1e-9, "в CPS время колеса 1/2048 с")


func test_extreme_and_energy_fields() -> void:
	# flags 0x0FC0: extreme force (бит 6), torque (бит 7), angles (бит 8), top (9), bottom (10), energy (11).
	var r := CpsCodec.decode_cycling_power_measurement(_hex("C0 0F FA 00" +
		" 2C 01 0A 00" +   # force max 300, min 10
		" 40 00 20 00" +   # torque max 2.0, min 1.0
		" 5A 00 0B" +      # angles: packed 0x0B005A → max 0x05A = 90, min 0x0B0 = 176
		" B4 00" +         # top dead spot 180
		" 00 00" +         # bottom dead spot 0
		" E8 03"))         # energy 1000 kJ
	assert_true(r["ok"])
	assert_eq(r["max_force_n"], 300)
	assert_eq(r["min_force_n"], 10)
	assert_almost_eq(r["max_torque_nm"], 2.0, 1e-9)
	assert_almost_eq(r["min_torque_nm"], 1.0, 1e-9)
	assert_eq(r["max_angle_deg"], 90)
	assert_eq(r["min_angle_deg"], 176)
	assert_eq(r["top_dead_spot_deg"], 180)
	assert_eq(r["bottom_dead_spot_deg"], 0)
	assert_eq(r["accumulated_energy_kj"], 1000)


func test_truncated_not_ok_but_power_kept() -> void:
	var r := CpsCodec.decode_cycling_power_measurement(_hex("20 00 FA 00 0A 00"))
	assert_false(r["ok"])
	assert_eq(r["power_w"], 250, "мощность уже разобрана")
	assert_false(r["has_crank"])
	assert_false(CpsCodec.decode_cycling_power_measurement(_hex("00 00 FA"))["ok"])


func test_encode_roundtrip() -> void:
	assert_eq(BleBytes.to_hex(CpsCodec.encode_cycling_power_measurement(250)), "00 00 FA 00")
	var b := CpsCodec.encode_cycling_power_measurement(250, 10, 1024)
	assert_eq(BleBytes.to_hex(b), "20 00 FA 00 0A 00 00 04")
	var r := CpsCodec.decode_cycling_power_measurement(b)
	assert_eq(r["power_w"], 250)
	assert_eq(r["crank_revolutions"], 10)
