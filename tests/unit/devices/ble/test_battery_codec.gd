extends GutTest
## Тесты кодека Battery Level 2A19 (REQ-DEV-07 крит. 2; BAS v1.0 §3.1: uint8 0..100).


func test_decode_levels() -> void:
	assert_eq(BatteryCodec.decode_level(PackedByteArray([0x64]))["level_pct"], 100)
	assert_eq(BatteryCodec.decode_level(PackedByteArray([0x32]))["level_pct"], 50)
	assert_eq(BatteryCodec.decode_level(PackedByteArray([0x00]))["level_pct"], 0)
	assert_true(BatteryCodec.decode_level(PackedByteArray([0x32]))["ok"])


func test_reserved_and_empty_not_ok() -> void:
	assert_false(BatteryCodec.decode_level(PackedByteArray([101]))["ok"], "101..255 зарезервированы")
	assert_false(BatteryCodec.decode_level(PackedByteArray([0xFF]))["ok"])
	assert_false(BatteryCodec.decode_level(PackedByteArray())["ok"])


func test_extra_bytes_ignored_and_encode_clamps() -> void:
	assert_eq(BatteryCodec.decode_level(PackedByteArray([0x55, 0xAA]))["level_pct"], 85)
	assert_eq(BatteryCodec.encode_level(120), PackedByteArray([100]))
	assert_eq(BatteryCodec.encode_level(-3), PackedByteArray([0]))
	assert_eq(BatteryCodec.decode_level(BatteryCodec.encode_level(42))["level_pct"], 42)
