extends GutTest
## Кодек SIM FTMS: команда 0x11, Supported Inclination Range 2AD5, бит SIM
## в Fitness Machine Feature 2ACC (REQ-FRD-04 крит. 1, 3, 6).
##
## Байтовые примеры команды — из REQ-FRD-04 крит. 1; раскладка 2AD5 и 2ACC — FTMS v1.0
## §4.4 (min/max sint16 ×0.1 %, increment uint16) и §4.3 (uint32 + uint32, бит 13
## Target Setting Features — Indoor Bike Simulation Parameters Supported).


func _hex(s: String) -> PackedByteArray:
	return BleBytes.from_hex(s)


func _sim(wind: float, grade: float, crr: float = 0.004, cw: float = 0.20) -> String:
	return BleBytes.to_hex(FtmsCodec.encode_indoor_bike_simulation(wind, grade, crr, cw))


# ---------------------------------------------------------------------------
# Команда 0x11 — байтовые примеры REQ-FRD-04 крит. 1
# ---------------------------------------------------------------------------

func test_req_frd_04_c1_grade_5_percent() -> void:
	assert_eq(_sim(0.0, 5.0), "11 00 00 F4 01 28 14")


func test_req_frd_04_c1_grade_minus_3_percent() -> void:
	assert_eq(_sim(0.0, -3.0), "11 00 00 D4 FE 28 14")


func test_req_frd_04_c1_grade_zero() -> void:
	assert_eq(_sim(0.0, 0.0), "11 00 00 00 00 28 14")


func test_req_frd_04_c1_grade_12_34_field() -> void:
	var b := FtmsCodec.encode_indoor_bike_simulation(0.0, 12.34, 0.004, 0.20)
	assert_eq(BleBytes.to_hex(b.slice(3, 5)), "D2 04")


func test_req_frd_04_c1_wind_1_5_mps_field() -> void:
	var b := FtmsCodec.encode_indoor_bike_simulation(1.5, 0.0, 0.004, 0.20)
	assert_eq(BleBytes.to_hex(b.slice(1, 3)), "DC 05")


func test_req_frd_04_c1_crr_and_cw_fields() -> void:
	var b := FtmsCodec.encode_indoor_bike_simulation(0.0, 0.0, 0.004, 0.20)
	assert_eq(b.size(), 7, "опкод + 2 + 2 + 1 + 1")
	assert_eq(b[0], FtmsCodec.OP_SET_INDOOR_BIKE_SIMULATION)
	assert_eq(b[5], 0x28, "Crr 0.004 → 40")
	assert_eq(b[6], 0x14, "Cw 0.20 → 20")


func test_req_frd_05_c1_half_steepness_example() -> void:
	# g = 8 %, k = 50 % → 4.00 % → `… 90 01 …` (REQ-FRD-05 крит. 1).
	assert_eq(_sim(0.0, 4.0), "11 00 00 90 01 28 14")
	assert_eq(_sim(0.0, -2.0), "11 00 00 38 FF 28 14")


func test_boundaries_are_encoded() -> void:
	assert_eq(_sim(0.0, 327.67), "11 00 00 FF 7F 28 14")
	assert_eq(_sim(0.0, -327.67), "11 00 00 01 80 28 14")
	assert_eq(_sim(-32.767, 0.0, 0.0255, 2.55), "11 01 80 00 00 FF FF")
	assert_eq(_sim(0.0, 0.0, 0.0, 0.0), "11 00 00 00 00 00 00")


# ---------------------------------------------------------------------------
# Значения вне диапазона типов — отклоняются, байтов нет
# ---------------------------------------------------------------------------

func test_req_frd_04_c1_out_of_range_rejected() -> void:
	var bad: Array = [
		[0.0, 327.68, 0.004, 0.20],
		[0.0, -327.68, 0.004, 0.20],
		[0.0, 1000.0, 0.004, 0.20],
		[0.0, 0.0, 0.0256, 0.20],
		[0.0, 0.0, -0.0001, 0.20],
		[0.0, 0.0, 0.004, 2.56],
		[0.0, 0.0, 0.004, -0.01],
		[32.768, 0.0, 0.004, 0.20],
		[-40.0, 0.0, 0.004, 0.20],
		[0.0, NAN, 0.004, 0.20],
		[INF, 0.0, 0.004, 0.20],
	]
	for p in bad:
		var b := FtmsCodec.encode_indoor_bike_simulation(p[0], p[1], p[2], p[3])
		assert_true(b.is_empty(), "без байтов: %s" % str(p))
		assert_ne(FtmsCodec.simulation_params_error(p[0], p[1], p[2], p[3]), "", "есть причина: %s" % str(p))


func test_valid_params_have_no_error() -> void:
	assert_eq(FtmsCodec.simulation_params_error(0.0, 5.0, 0.004, 0.20), "")
	assert_eq(FtmsCodec.simulation_params_error(32.767, -327.67, 0.0255, 2.55), "")


func test_opcode_name() -> void:
	assert_eq(FtmsCodec.opcode_name(0x11), "set_indoor_bike_simulation")


# ---------------------------------------------------------------------------
# Supported Inclination Range 2AD5 (REQ-FRD-04 крит. 3)
# ---------------------------------------------------------------------------

func test_req_frd_04_c3_decode_inclination_range() -> void:
	# min −100 (0xFF9C) → −10.0 %; max 200 (0x00C8) → 20.0 %; inc 5 → 0.5 %.
	var r := FtmsCodec.decode_supported_inclination_range(_hex("9C FF C8 00 05 00"))
	assert_true(r["ok"])
	assert_almost_eq(float(r["min_pct"]), -10.0, 1e-9)
	assert_almost_eq(float(r["max_pct"]), 20.0, 1e-9)
	assert_almost_eq(float(r["increment_pct"]), 0.5, 1e-9)


func test_decode_inclination_range_wide_and_bad() -> void:
	var wide := FtmsCodec.decode_supported_inclination_range(_hex("38 FF 90 01 01 00"))
	assert_true(wide["ok"])
	assert_almost_eq(float(wide["min_pct"]), -20.0, 1e-9)
	assert_almost_eq(float(wide["max_pct"]), 40.0, 1e-9)
	assert_false(FtmsCodec.decode_supported_inclination_range(_hex("9C FF C8 00 05"))["ok"], "короче 6 байт")
	assert_false(FtmsCodec.decode_supported_inclination_range(_hex("C8 00 9C FF 05 00"))["ok"], "max ≤ min")


# ---------------------------------------------------------------------------
# Fitness Machine Feature 2ACC (REQ-FRD-04 крит. 6)
# ---------------------------------------------------------------------------

func test_req_frd_04_c6_simulation_bit_set() -> void:
	# Target Setting Features 0x0000200C: бит 2 сопротивление, бит 3 мощность, бит 13 SIM.
	var r := FtmsCodec.decode_fitness_machine_feature(_hex("83 40 00 00 0C 20 00 00"))
	assert_true(r["ok"])
	assert_eq(r["machine_features"], 0x4083)
	assert_eq(r["target_settings"], 0x200C)
	assert_true(r["simulation_supported"])
	assert_true(r["resistance_supported"])
	assert_true(r["power_supported"])
	assert_false(r["inclination_supported"])


func test_req_frd_04_c6_simulation_bit_clear() -> void:
	var r := FtmsCodec.decode_fitness_machine_feature(_hex("83 40 00 00 0C 00 00 00"))
	assert_true(r["ok"])
	assert_false(r["simulation_supported"])
	assert_true(r["power_supported"])


func test_fitness_machine_feature_short_packet() -> void:
	var r := FtmsCodec.decode_fitness_machine_feature(_hex("83 40 00 00 0C 20 00"))
	assert_false(r["ok"])
	assert_false(r["simulation_supported"])


func test_fitness_machine_feature_roundtrip() -> void:
	var b := FtmsCodec.encode_fitness_machine_feature(0x00014083, FtmsCodec.TSF_INDOOR_BIKE_SIMULATION | 0x80000000)
	assert_eq(BleBytes.to_hex(b), "83 40 01 00 00 20 00 80")
	var r := FtmsCodec.decode_fitness_machine_feature(b)
	assert_eq(r["machine_features"], 0x00014083)
	assert_true(r["simulation_supported"])
	assert_eq(r["target_settings"], 0x80002000)


func test_uuid_constants() -> void:
	assert_eq(BleUuids.FITNESS_MACHINE_FEATURE, "2ACC")
	assert_eq(BleUuids.SUPPORTED_INCLINATION_RANGE, "2AD5")
