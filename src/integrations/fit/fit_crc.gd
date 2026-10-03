class_name FitCrc
extends RefCounted
## CRC-16 файла FIT (Garmin FIT SDK, раздел «CRC»; эквивалент CRC-16/ARC:
## полином 0x8005 отражённый = 0xA001, начальное значение 0, без финального XOR).
## Известный вектор: "123456789" → 0xBB3D. Используется для CRC заголовка
## (первые 12 байт) и CRC всего файла (REQ-LOC-05 крит. 1).

const CRC_TABLE: Array[int] = [
	0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
	0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
]


## Обновить CRC одним байтом (алгоритм из SDK: два полубайта по таблице).
static func update(crc: int, byte: int) -> int:
	var tmp: int = CRC_TABLE[crc & 0xF]
	crc = (crc >> 4) & 0x0FFF
	crc = crc ^ tmp ^ CRC_TABLE[byte & 0xF]
	tmp = CRC_TABLE[crc & 0xF]
	crc = (crc >> 4) & 0x0FFF
	crc = crc ^ tmp ^ CRC_TABLE[(byte >> 4) & 0xF]
	return crc & 0xFFFF


## CRC участка `bytes[from, from + length)`; `length < 0` — до конца.
static func compute(bytes: PackedByteArray, from: int = 0, length: int = -1, initial: int = 0) -> int:
	var end: int = bytes.size() if length < 0 else mini(from + length, bytes.size())
	var crc: int = initial
	for i in range(from, end):
		crc = update(crc, bytes[i])
	return crc
