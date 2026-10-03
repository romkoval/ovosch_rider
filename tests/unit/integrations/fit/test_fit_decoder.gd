extends GutTest
## Тестовый декодер FIT: отказ на мусоре, обе архитектуры, invalid-значения
## (REQ-LOC-05 крит. 1, 3 — инструмент проверок; REQ-NFR-09 крит. 1).

const D = preload("res://src/integrations/fit/fit_definitions.gd")


func _header(data_size: int) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(14)
	b.put_u8(0x20)
	b.put_u16(2160)
	b.put_u32(data_size)
	b.put_data(".FIT".to_ascii_buffer())
	b.put_u16(FitCrc.compute(b.data_array, 0, 12))
	return b.data_array


func _finish(body: PackedByteArray) -> PackedByteArray:
	var out := _header(body.size())
	out.append_array(body)
	var crc := FitCrc.compute(out)
	out.append(crc & 0xFF)
	out.append((crc >> 8) & 0xFF)
	return out


func test_rejects_short_input_and_bad_signature() -> void:
	assert_false(FitDecoder.decode(PackedByteArray([1, 2, 3])).ok)
	var bytes := FitEncoder.encode(Ride.new())
	bytes[8] = 0x58  # 'X' вместо '.'
	var res := FitDecoder.decode(bytes)
	assert_false(res.ok)
	assert_string_contains(res.error, ".FIT")


func test_rejects_data_without_definition() -> void:
	var body := PackedByteArray([0x03, 0x01, 0x02])  # данные локального типа 3 без определения
	var res := FitDecoder.decode(_finish(body))
	assert_false(res.ok)
	assert_string_contains(res.error, "без определения")


func test_parses_big_endian_definition() -> void:
	var b := StreamPeerBuffer.new()
	b.put_u8(0x40)      # определение, локальный тип 0
	b.put_u8(0)
	b.put_u8(1)         # big-endian
	b.put_u8(0)
	b.put_u8(20)        # global 20 = record (big-endian)
	b.put_u8(2)         # 2 поля
	b.put_data(PackedByteArray([D.RECORD_POWER, 2, D.T_UINT16]))
	b.put_data(PackedByteArray([D.RECORD_HEART_RATE, 1, D.T_UINT8]))
	b.put_u8(0x00)      # данные
	b.put_u8(0x01)
	b.put_u8(0x2C)      # 300 big-endian
	b.put_u8(0xFF)      # пульс invalid
	var res := FitDecoder.decode(_finish(b.data_array))
	assert_true(res.ok, res.error)
	assert_eq(res.count(D.MSG_RECORD), 1)
	assert_eq(res.first_field(D.MSG_RECORD, D.RECORD_POWER), 300)
	assert_null(res.first_field(D.MSG_RECORD, D.RECORD_HEART_RATE))


func test_invalid_values_decode_as_null_and_strings_trim_at_zero() -> void:
	var b := StreamPeerBuffer.new()
	b.put_u8(0x41)      # определение, локальный тип 1
	b.put_u8(0)
	b.put_u8(0)         # little-endian
	b.put_u16(0)        # file_id
	b.put_u8(4)
	b.put_data(PackedByteArray([D.FILE_ID_TYPE, 1, D.T_ENUM]))
	b.put_data(PackedByteArray([D.FILE_ID_MANUFACTURER, 2, D.T_UINT16]))
	b.put_data(PackedByteArray([D.FILE_ID_SERIAL_NUMBER, 4, D.T_UINT32Z]))
	b.put_data(PackedByteArray([D.FILE_ID_PRODUCT_NAME, 6, D.T_STRING]))
	b.put_u8(0x01)      # данные
	b.put_u8(0xFF)      # enum invalid
	b.put_u16(0xFFFF)   # uint16 invalid
	b.put_u32(0)        # uint32z invalid = 0
	b.put_data("ab".to_ascii_buffer())
	b.put_data(PackedByteArray([0, 0, 0, 0]))
	var res := FitDecoder.decode(_finish(b.data_array))
	assert_true(res.ok, res.error)
	assert_null(res.first_field(D.MSG_FILE_ID, D.FILE_ID_TYPE))
	assert_null(res.first_field(D.MSG_FILE_ID, D.FILE_ID_MANUFACTURER))
	assert_null(res.first_field(D.MSG_FILE_ID, D.FILE_ID_SERIAL_NUMBER))
	assert_eq(res.first_field(D.MSG_FILE_ID, D.FILE_ID_PRODUCT_NAME), "ab")


func test_skips_developer_fields_in_definition_and_data() -> void:
	var b := StreamPeerBuffer.new()
	b.put_u8(0x60)      # определение с developer-данными, локальный тип 0
	b.put_u8(0)
	b.put_u8(0)
	b.put_u16(20)
	b.put_u8(1)
	b.put_data(PackedByteArray([D.RECORD_POWER, 2, D.T_UINT16]))
	b.put_u8(1)         # одно developer-поле
	b.put_data(PackedByteArray([0, 3, 0]))  # номер 0, размер 3, dev index 0
	b.put_u8(0x00)      # данные
	b.put_u16(250)
	b.put_data(PackedByteArray([9, 9, 9]))  # developer-данные пропускаются
	var res := FitDecoder.decode(_finish(b.data_array))
	assert_true(res.ok, res.error)
	assert_eq(res.first_field(D.MSG_RECORD, D.RECORD_POWER), 250)


func test_header_crc_zero_is_accepted() -> void:
	var bytes := FitEncoder.encode(Ride.new())
	bytes[12] = 0
	bytes[13] = 0
	# Перепишем CRC файла под изменённый заголовок.
	var crc := FitCrc.compute(bytes, 0, bytes.size() - 2)
	bytes[bytes.size() - 2] = crc & 0xFF
	bytes[bytes.size() - 1] = (crc >> 8) & 0xFF
	var res := FitDecoder.decode(bytes)
	assert_true(res.header_crc_ok, "CRC заголовка 0 допустим по спецификации")
	assert_true(res.ok, res.error)
