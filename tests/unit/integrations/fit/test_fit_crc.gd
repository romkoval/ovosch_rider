extends GutTest
## CRC-16 FIT (REQ-LOC-05 крит. 1; REQ-NFR-09 крит. 1 — генератор FIT).


func test_known_vector_123456789_is_0xBB3D() -> void:
	assert_eq(FitCrc.compute("123456789".to_ascii_buffer()), 0xBB3D, "CRC-16/ARC: check value 0xBB3D")


func test_empty_input_is_zero() -> void:
	assert_eq(FitCrc.compute(PackedByteArray()), 0)


func test_incremental_update_matches_compute() -> void:
	var data := "The quick brown fox".to_ascii_buffer()
	var crc: int = 0
	for b in data:
		crc = FitCrc.update(crc, b)
	assert_eq(crc, FitCrc.compute(data))
	assert_eq(FitCrc.compute(data, 4, -1, FitCrc.compute(data, 0, 4)), FitCrc.compute(data), "продолжение с initial")


func test_crc_over_data_plus_its_crc_is_zero() -> void:
	var data := "ovosch-rider".to_ascii_buffer()
	var crc: int = FitCrc.compute(data)
	data.append(crc & 0xFF)
	data.append((crc >> 8) & 0xFF)
	assert_eq(FitCrc.compute(data), 0, "свойство CRC: CRC(данные ‖ CRC) = 0")


func test_single_bit_change_changes_crc() -> void:
	var a := "123456789".to_ascii_buffer()
	var b := a.duplicate()
	b[3] ^= 0x01
	assert_ne(FitCrc.compute(a), FitCrc.compute(b))
