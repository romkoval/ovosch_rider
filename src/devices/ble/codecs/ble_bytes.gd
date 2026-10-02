class_name BleBytes
extends RefCounted
## Чтение/запись little-endian полей из `PackedByteArray` для кодеков BLE.
## Все `read_*` возвращают 0 при выходе за границы; проверяйте `has(bytes, offset, size)`.


static func has(bytes: PackedByteArray, offset: int, size: int) -> bool:
	return offset >= 0 and offset + size <= bytes.size()


static func u8(bytes: PackedByteArray, offset: int) -> int:
	return bytes[offset] if has(bytes, offset, 1) else 0


static func u16(bytes: PackedByteArray, offset: int) -> int:
	if not has(bytes, offset, 2):
		return 0
	return bytes[offset] | (bytes[offset + 1] << 8)


static func s16(bytes: PackedByteArray, offset: int) -> int:
	var v: int = u16(bytes, offset)
	return v - 0x10000 if v >= 0x8000 else v


static func u24(bytes: PackedByteArray, offset: int) -> int:
	if not has(bytes, offset, 3):
		return 0
	return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16)


static func u32(bytes: PackedByteArray, offset: int) -> int:
	if not has(bytes, offset, 4):
		return 0
	return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)


static func put_u8(out: PackedByteArray, value: int) -> void:
	out.append(value & 0xFF)


static func put_u16(out: PackedByteArray, value: int) -> void:
	out.append(value & 0xFF)
	out.append((value >> 8) & 0xFF)


## sint16 LE в дополнительном коде; значение клампится в [-32768; 32767].
static func put_s16(out: PackedByteArray, value: int) -> void:
	var v: int = clampi(value, -32768, 32767)
	if v < 0:
		v += 0x10000
	put_u16(out, v)


## Шестнадцатеричная строка "05 FA 00" — для сообщений и тестов.
static func to_hex(bytes: PackedByteArray) -> String:
	var parts: PackedStringArray = []
	for b in bytes:
		parts.append("%02X" % b)
	return " ".join(parts)


## Обратное к `to_hex`: "05 FA 00" или "05FA00" → байты.
static func from_hex(hex: String) -> PackedByteArray:
	var clean: String = hex.replace(" ", "").replace(":", "")
	var out := PackedByteArray()
	var i: int = 0
	while i + 1 < clean.length():
		out.append(clean.substr(i, 2).hex_to_int())
		i += 2
	return out
