extends GutTest
## Тесты кодека FTMS (REQ-DEV-02 крит. 2–5, REQ-WRK-04 крит. 2).
##
## Байтовые векторы собраны по раскладке полей FTMS v1.0 (§4.9 Indoor Bike Data,
## §4.16 Control Point, §4.5 Supported Resistance Level Range, §4.17 Machine Status):
## спецификация задаёт форматы, а не примеры; литеральные примеры `05 FA 00` и
## `04 32` — из requirements.md.


func _hex(s: String) -> PackedByteArray:
	return BleBytes.from_hex(s)


# ---------------------------------------------------------------------------
# Indoor Bike Data
# ---------------------------------------------------------------------------

func test_ibd_speed_cadence_power() -> void:
	# flags 0x0044: бит 0 = 0 → скорость есть; бит 2 каденс; бит 6 мощность.
	# speed 0x0D60 = 3424 → 34.24 км/ч; cadence 0x00B4 = 180 → 90 rpm; power 0x00FA = 250.
	var r := FtmsCodec.decode_indoor_bike_data(_hex("44 00 60 0D B4 00 FA 00"))
	assert_true(r["ok"])
	assert_true(r["has_speed"])
	assert_almost_eq(r["speed_kmh"], 34.24, 1e-6)
	assert_true(r["has_cadence"])
	assert_almost_eq(r["cadence_rpm"], 90.0, 1e-9)
	assert_true(r["has_power"])
	assert_eq(r["power_w"], 250)
	assert_false(r["has_heart_rate"])


func test_ibd_with_heart_rate_flag() -> void:
	# flags 0x0244 = 0x0044 | бит 9 (пульс): + uint8 0x48 = 72.
	var r := FtmsCodec.decode_indoor_bike_data(_hex("44 02 60 0D B4 00 FA 00 48"))
	assert_true(r["ok"])
	assert_true(r["has_heart_rate"])
	assert_eq(r["heart_rate_bpm"], 72)
	assert_eq(r["power_w"], 250)


func test_ibd_more_data_bit_means_no_speed_field() -> void:
	# flags 0x0045: бит 0 = 1 → поля скорости нет; каденс и мощность следуют сразу.
	var r := FtmsCodec.decode_indoor_bike_data(_hex("45 00 B4 00 FA 00"))
	assert_true(r["ok"])
	assert_false(r["has_speed"])
	assert_almost_eq(r["cadence_rpm"], 90.0, 1e-9)
	assert_eq(r["power_w"], 250)


func test_ibd_negative_power_and_half_rpm() -> void:
	# power 0xFF06 = -250; cadence 0x00B5 = 181 → 90.5 rpm.
	var r := FtmsCodec.decode_indoor_bike_data(_hex("44 00 00 00 B5 00 06 FF"))
	assert_eq(r["power_w"], -250, "sint16")
	assert_almost_eq(r["cadence_rpm"], 90.5, 1e-9, "разрешение 0.5 rpm")
	assert_almost_eq(r["speed_kmh"], 0.0, 1e-9)


func test_ibd_all_optional_fields_in_spec_order() -> void:
	# flags 0x1FFE: все биты 1..12 (бит 0 = 0 → скорость есть).
	var b := _hex("FE 1F" +
		" 60 0D" +      # speed 34.24
		" 50 0D" +      # avg speed 34.08
		" B4 00" +      # cadence 90
		" B0 00" +      # avg cadence 88
		" 10 27 00" +   # distance 10000 m
		" 05 00" +      # resistance 5
		" FA 00" +      # power 250
		" F0 00" +      # avg power 240
		" 2C 01 90 01 0A" +  # energy total 300, per hour 400, per minute 10
		" 48" +         # HR 72
		" 55" +         # MET 8.5
		" 58 02" +      # elapsed 600
		" 2C 01")       # remaining 300
	var r := FtmsCodec.decode_indoor_bike_data(b)
	assert_true(r["ok"])
	assert_almost_eq(r["average_speed_kmh"], 34.08, 1e-6)
	assert_almost_eq(r["average_cadence_rpm"], 88.0, 1e-9)
	assert_eq(r["distance_m"], 10000)
	assert_eq(r["resistance_level"], 5)
	assert_eq(r["power_w"], 250)
	assert_eq(r["average_power_w"], 240)
	assert_eq(r["energy_total_kcal"], 300)
	assert_eq(r["energy_per_hour_kcal"], 400)
	assert_eq(r["energy_per_minute_kcal"], 10)
	assert_eq(r["heart_rate_bpm"], 72)
	assert_almost_eq(r["metabolic_equivalent"], 8.5, 1e-9)
	assert_eq(r["elapsed_sec"], 600)
	assert_eq(r["remaining_sec"], 300)


func test_ibd_truncated_packet_keeps_parsed_fields_and_flags_not_ok() -> void:
	var r := FtmsCodec.decode_indoor_bike_data(_hex("44 00 60 0D B4 00 FA"))
	assert_false(r["ok"], "мощность обрезана")
	assert_true(r["has_speed"])
	assert_true(r["has_cadence"])
	assert_false(r["has_power"])
	assert_false(FtmsCodec.decode_indoor_bike_data(_hex("44"))["ok"])
	assert_false(FtmsCodec.decode_indoor_bike_data(PackedByteArray())["ok"])


func test_ibd_encode_roundtrip() -> void:
	var b := FtmsCodec.encode_indoor_bike_data(34.24, 90.0, 250, 72)
	assert_eq(BleBytes.to_hex(b), "44 02 60 0D B4 00 FA 00 48")
	var r := FtmsCodec.decode_indoor_bike_data(b)
	assert_eq(r["power_w"], 250)
	assert_eq(r["heart_rate_bpm"], 72)
	var no_speed := FtmsCodec.encode_indoor_bike_data(-1.0, 90.0, 250)
	assert_eq(BleBytes.to_hex(no_speed), "45 00 B4 00 FA 00")


# ---------------------------------------------------------------------------
# Control Point
# ---------------------------------------------------------------------------

func test_encode_set_target_power_250_is_05_fa_00() -> void:
	assert_eq(BleBytes.to_hex(FtmsCodec.encode_set_target_power(250)), "05 FA 00", "REQ-DEV-02 крит. 4")
	assert_eq(BleBytes.to_hex(FtmsCodec.encode_set_target_power(0)), "05 00 00")
	assert_eq(BleBytes.to_hex(FtmsCodec.encode_set_target_power(1000)), "05 E8 03")
	assert_eq(BleBytes.to_hex(FtmsCodec.encode_set_target_power(-10)), "05 F6 FF", "sint16")


func test_encode_set_resistance_level_5_0_is_04_32() -> void:
	assert_eq(BleBytes.to_hex(FtmsCodec.encode_set_resistance_level(5.0)), "04 32", "REQ-DEV-02 крит. 5")
	assert_eq(BleBytes.to_hex(FtmsCodec.encode_set_resistance_level(0.0)), "04 00")
	assert_eq(BleBytes.to_hex(FtmsCodec.encode_set_resistance_level(10.0)), "04 64")
	assert_eq(BleBytes.to_hex(FtmsCodec.encode_set_resistance_level(99.0)), "04 FF", "кламп в uint8")


func test_encode_simple_opcodes() -> void:
	assert_eq(BleBytes.to_hex(FtmsCodec.encode_request_control()), "00")
	assert_eq(BleBytes.to_hex(FtmsCodec.encode_reset()), "01")
	assert_eq(BleBytes.to_hex(FtmsCodec.encode_start()), "07")
	assert_eq(BleBytes.to_hex(FtmsCodec.encode_stop()), "08 01")
	assert_eq(BleBytes.to_hex(FtmsCodec.encode_pause()), "08 02")


func test_decode_control_point_response_success_and_failure() -> void:
	var ok := FtmsCodec.decode_control_point_response(_hex("80 05 01"))
	assert_true(ok["ok"])
	assert_eq(ok["request_opcode"], FtmsCodec.OP_SET_TARGET_POWER)
	assert_eq(ok["result"], FtmsCodec.RESULT_SUCCESS)
	assert_true(ok["success"])
	var fail := FtmsCodec.decode_control_point_response(_hex("80 00 05"))
	assert_true(fail["ok"])
	assert_false(fail["success"], "REQ-DEV-02 крит. 3: result != 0x01 — ошибка команды")
	assert_eq(fail["result"], FtmsCodec.RESULT_CONTROL_NOT_PERMITTED)
	assert_eq(FtmsCodec.result_name(fail["result"]), "control_not_permitted")
	assert_eq(FtmsCodec.opcode_name(fail["request_opcode"]), "request_control")


func test_decode_control_point_response_rejects_non_response_and_short() -> void:
	assert_false(FtmsCodec.decode_control_point_response(_hex("05 FA 00"))["ok"], "это запрос, не ответ")
	assert_false(FtmsCodec.decode_control_point_response(_hex("80 05"))["ok"])
	assert_false(FtmsCodec.decode_control_point_response(PackedByteArray())["ok"])
	var with_params := FtmsCodec.decode_control_point_response(_hex("80 05 01 AA BB"))
	assert_eq(with_params["parameters"], PackedByteArray([0xAA, 0xBB]))


func test_encode_control_point_response_roundtrip() -> void:
	var b := FtmsCodec.encode_control_point_response(FtmsCodec.OP_SET_TARGET_POWER, FtmsCodec.RESULT_OPERATION_FAILED)
	assert_eq(BleBytes.to_hex(b), "80 05 04")
	assert_false(FtmsCodec.decode_control_point_response(b)["success"])


func test_result_and_opcode_names_for_unknown() -> void:
	assert_eq(FtmsCodec.result_name(0x02), "not_supported")
	assert_eq(FtmsCodec.result_name(0x03), "invalid_parameter")
	assert_eq(FtmsCodec.result_name(0x04), "operation_failed")
	assert_eq(FtmsCodec.result_name(0x77), "unknown_0x77")
	assert_eq(FtmsCodec.opcode_name(0x04), "set_target_resistance_level")
	assert_eq(FtmsCodec.opcode_name(0x42), "opcode_0x42")


# ---------------------------------------------------------------------------
# Supported Resistance Level Range 2AD6, Machine Status 2ADA
# ---------------------------------------------------------------------------

func test_decode_resistance_range() -> void:
	# min 0, max 0x00C8 = 200 → 20.0, inc 0x000A = 10 → 1.0.
	var r := FtmsCodec.decode_resistance_range(_hex("00 00 C8 00 0A 00"))
	assert_true(r["ok"])
	assert_almost_eq(r["min_level"], 0.0, 1e-9)
	assert_almost_eq(r["max_level"], 20.0, 1e-9)
	assert_almost_eq(r["increment"], 1.0, 1e-9)
	var neg := FtmsCodec.decode_resistance_range(_hex("CE FF 32 00 01 00"))
	assert_almost_eq(neg["min_level"], -5.0, 1e-9, "sint16 min")
	assert_almost_eq(neg["increment"], 0.1, 1e-9)
	assert_false(FtmsCodec.decode_resistance_range(_hex("00 00 C8 00"))["ok"], "короткий пакет")
	assert_false(FtmsCodec.decode_resistance_range(_hex("C8 00 00 00 0A 00"))["ok"], "max <= min")


func test_percent_to_resistance_level_with_and_without_range() -> void:
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(50), 5.0, 1e-9, "без 2AD6: линейно в 0..100 единиц 0.1")
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(100), 10.0, 1e-9)
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(-5), 0.0, 1e-9)
	assert_eq(BleBytes.to_hex(FtmsCodec.encode_set_resistance_level(FtmsCodec.percent_to_resistance_level(50))), "04 32")
	var range := FtmsCodec.decode_resistance_range(_hex("00 00 C8 00 0A 00"))
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(50, range), 10.0, 1e-9, "50 % от 0..20")
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(33, range), 7.0, 1e-9, "6.6 → шаг 1.0 → 7.0")
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(100, range), 20.0, 1e-9)
	var bad: Dictionary = {"ok": false}
	assert_almost_eq(FtmsCodec.percent_to_resistance_level(50, bad), 5.0, 1e-9, "невалидный диапазон → по умолчанию")


func test_decode_machine_status() -> void:
	var tp := FtmsCodec.decode_machine_status(_hex("08 FA 00"))
	assert_true(tp["ok"])
	assert_eq(tp["name"], "target_power_changed")
	assert_eq(tp["value"], 250)
	var sp := FtmsCodec.decode_machine_status(_hex("02 02"))
	assert_eq(sp["name"], "stopped_or_paused_by_user")
	assert_eq(sp["value"], 2)
	var rl := FtmsCodec.decode_machine_status(_hex("07 32"))
	assert_eq(rl["name"], "target_resistance_changed")
	assert_almost_eq(rl["value"], 5.0, 1e-9)
	assert_eq(FtmsCodec.decode_machine_status(_hex("FF"))["name"], "control_permission_lost")
	assert_eq(FtmsCodec.decode_machine_status(_hex("04"))["name"], "started_or_resumed_by_user")
	assert_eq(FtmsCodec.decode_machine_status(_hex("01"))["name"], "reset")
	assert_eq(FtmsCodec.decode_machine_status(_hex("0E"))["name"], "status_0x0E")
	assert_false(FtmsCodec.decode_machine_status(PackedByteArray())["ok"])
