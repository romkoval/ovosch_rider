extends GutTest
## Тесты little-endian помощников.


func test_read_unsigned_and_signed() -> void:
	var b := BleBytes.from_hex("FA 00 06 FF 01 02 03 04")
	assert_eq(BleBytes.u8(b, 0), 0xFA)
	assert_eq(BleBytes.u16(b, 0), 250)
	assert_eq(BleBytes.s16(b, 0), 250)
	assert_eq(BleBytes.s16(b, 2), -250, "06 FF = -250 в дополнительном коде")
	assert_eq(BleBytes.u24(b, 4), 0x030201)
	assert_eq(BleBytes.u32(b, 4), 0x04030201)


func test_out_of_range_reads_give_zero() -> void:
	var b := BleBytes.from_hex("01")
	assert_false(BleBytes.has(b, 0, 2))
	assert_eq(BleBytes.u16(b, 0), 0)
	assert_eq(BleBytes.u8(b, 5), 0)
	assert_false(BleBytes.has(b, -1, 1))


func test_put_s16_two_complement_and_clamp() -> void:
	var out := PackedByteArray()
	BleBytes.put_s16(out, 250)
	BleBytes.put_s16(out, -1)
	BleBytes.put_s16(out, 40000)
	assert_eq(BleBytes.to_hex(out), "FA 00 FF FF FF 7F")


func test_hex_roundtrip() -> void:
	assert_eq(BleBytes.to_hex(PackedByteArray([5, 250, 0])), "05 FA 00")
	assert_eq(BleBytes.from_hex("05FA00"), PackedByteArray([5, 250, 0]))
	assert_eq(BleBytes.from_hex("05:fa:00"), PackedByteArray([5, 250, 0]))
	assert_eq(BleBytes.from_hex("").size(), 0)
