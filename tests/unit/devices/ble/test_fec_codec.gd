extends GutTest
## T-167: кодек FE-C over BLE (`FecCodec`) — REQ-DEV-11 п.3 (приём и отбрасывание), п.4 (0x19),
## п.5 (0x10). Байты — из фикстуры `tests/fixtures/fec/neo_fec.json` (числа критериев).

const FIXTURE: String = "res://tests/fixtures/fec/neo_fec.json"

var _fx: Dictionary = {}


func before_all() -> void:
	_fx = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))


func _bytes(key: String) -> PackedByteArray:
	return BleBytes.from_hex(str(_fx[key]).replace(" ", ""))


func test_req_dev_11_c4_a_250w_90rpm() -> void:
	var m := FecCodec.decode_message(_bytes("trainer_data_250w_90rpm"))
	assert_true(m["ok"])
	assert_eq(m["page_number"], FecCodec.PAGE_TRAINER_DATA)
	var d := FecCodec.decode_trainer_data(m["page"])
	assert_true(d["has_power"])
	assert_eq(d["power_w"], 250)
	assert_true(d["has_cadence"])
	assert_eq(d["cadence_rpm"], 90)


func test_req_dev_11_c4_b_1234w_status_bits_ignored_80rpm() -> void:
	var d := FecCodec.decode_trainer_data(FecCodec.decode_message(_bytes("trainer_data_1234w_80rpm"))["page"])
	assert_eq(d["power_w"], 1234, "0x4D2: старшие 4 бита байта 6 — статус, в мощность не входят")
	assert_eq(d["trainer_status"], 1)
	assert_eq(d["cadence_rpm"], 80)


func test_req_dev_11_c4_c_no_data_is_not_zero() -> void:
	var msg := FecCodec.encode_message(_bytes("trainer_data_no_data_page"), FecCodec.ANT_BROADCAST_DATA)
	var m := FecCodec.decode_message(msg)
	assert_true(m["ok"], "CS верная")
	var d := FecCodec.decode_trainer_data(m["page"])
	assert_false(d["has_power"], "0xFFF — нет данных")
	assert_false(d["has_cadence"], "FF — нет данных")


func test_req_dev_11_c3_invalid_messages_are_discarded() -> void:
	var good := _bytes("trainer_data_250w_90rpm")
	var bad_cs := good.duplicate()
	bad_cs[12] = 0x58
	var bad_len_byte := good.duplicate()
	bad_len_byte[1] = 0x08
	var truncated := good.slice(0, 12)
	var bad_sync := good.duplicate()
	bad_sync[0] = 0xA5
	var bad_id := FecCodec.encode_message(good.slice(4, 12), 0x40)
	for pair: Array in [[bad_cs, "CS 58"], [bad_len_byte, "байт 1 = 08"], [truncated, "12 байт"],
			[bad_sync, "байт 0 = A5"], [bad_id, "ID 40"], [PackedByteArray(), "пусто"]]:
		assert_false(FecCodec.decode_message(pair[0])["ok"], "отброшено: %s" % pair[1])
	var other_channel := FecCodec.encode_message(good.slice(4, 12), FecCodec.ANT_BROADCAST_DATA, 0x02)
	assert_true(FecCodec.decode_message(other_channel)["ok"], "номер канала не проверяется")


func test_req_dev_11_c5_speed_and_heart_rate() -> void:
	var g := FecCodec.decode_general_fe(FecCodec.decode_message(_bytes("general_fe_28_80kmh"))["page"])
	assert_true(g["has_speed"])
	assert_almost_eq(g["speed_kmh"], 28.80, 0.01)
	assert_false(g["has_heart_rate"], "FF — пульса нет")
	var p36 := FecCodec.decode_general_fe(PackedByteArray([0x10, 0x19, 0, 0, 0x10, 0x27, 0x8C, 0x34]))
	assert_almost_eq(p36["speed_kmh"], 36.00, 0.01)
	assert_true(p36["has_heart_rate"])
	assert_eq(p36["heart_rate_bpm"], 140)
	var none := FecCodec.decode_general_fe(PackedByteArray([0x10, 0x19, 0, 0, 0xFF, 0xFF, 0xFF, 0x34]))
	assert_false(none["has_speed"], "FF FF — нет данных")


func test_target_power_message_matches_criterion_and_debug_preset() -> void:
	assert_eq(FecCodec.encode_target_power(150), _bytes("target_power_150w"))
	assert_eq(BleDebugModel.fec_target_power_message(150), _bytes("target_power_150w"), "«BLE-отладка» — тот же кодек")
	assert_string_contains(BleDebugModel.decode_fec(_bytes("trainer_data_250w_90rpm")), "power 250 W")
