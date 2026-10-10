class_name FecCodec
extends RefCounted
## Кодек FE-C over BLE (REQ-DEV-11 п.3–5): ANT-сообщения с FE-C страницами в характеристиках
## FEC2 (нотификации станка) и FEC3 (запись на станок).
##
## Сообщение — 13 байт `A4 09 <ID> <канал> <страница: 8 байт> <CS>`: синхробайт `A4`, длина
## данных `09`, ID `4E` (broadcast data) или `4F` (acknowledged data), канал, страница (байт 0 —
## номер страницы), CS — XOR всех предыдущих байт. `decode_message` отбрасывает сообщение
## (`ok == false`, без ошибки), если байт 0 ≠ `A4`, байт 1 ≠ `09`, длина ≠ байт 1 + 4, ID ≠ `4E`
## и ≠ `4F` или CS не совпадает (п.3); номер канала не проверяется.
##
## Страницы данных:
## - 0x19 (данные велостанка): каденс — байт 2, об/мин (`FF` — нет данных); мгновенная мощность —
##   12 бит: байт 5 — младшие 8 бит, младшие 4 бита байта 6 — старшие (`0xFFF` — нет данных);
##   старшие 4 бита байта 6 — статус станка, в мощность не входят (п.4);
## - 0x10 (общие данные тренажёра): скорость — байты 4–5, uint16 LE, 0.001 м/с (`FF FF` — нет
##   данных); пульс — байт 6 (`FF` — нет данных) (п.5).
## `describe()` — текст для журнала «BLE-отладки».

const ANT_SYNC: int = 0xA4
const ANT_DATA_LENGTH: int = 0x09
const ANT_BROADCAST_DATA: int = 0x4E
const ANT_ACKNOWLEDGED_DATA: int = 0x4F
## Канал, в который пишутся страницы на FEC3.
const ANT_CHANNEL: int = 0x05
## Длина сообщения: синхробайт, длина, ID, канал, 8 байт страницы, CS.
const MESSAGE_LENGTH: int = 13
const PAGE_LENGTH: int = 8

const PAGE_GENERAL_FE: int = 0x10
const PAGE_GENERAL_SETTINGS: int = 0x11
const PAGE_TRAINER_DATA: int = 0x19
const PAGE_BASIC_RESISTANCE: int = 0x30
const PAGE_TARGET_POWER: int = 0x31
const PAGE_CAPABILITIES: int = 0x36
const PAGE_REQUEST: int = 0x46
const PAGE_COMMAND_STATUS: int = 0x47
const PAGE_MANUFACTURER: int = 0x50
const PAGE_PRODUCT: int = 0x51
## Страницы, которые станок обрабатывает (п.3); остальные игнорируются без ошибки.
const HANDLED_PAGES: Array[int] = [PAGE_GENERAL_FE, PAGE_TRAINER_DATA, PAGE_CAPABILITIES, PAGE_COMMAND_STATUS]

## «Нет данных» в полях страниц.
const NO_POWER: int = 0xFFF
const NO_BYTE: int = 0xFF
const NO_SPEED: int = 0xFFFF


## Контрольная сумма ANT: XOR всех байт.
static func checksum(bytes: PackedByteArray) -> int:
	var x: int = 0
	for b in bytes:
		x ^= b
	return x


## ANT-сообщение со страницей `page` (недостающие байты страницы — `FF`).
static func encode_message(page: PackedByteArray, msg_id: int = ANT_ACKNOWLEDGED_DATA,
		channel: int = ANT_CHANNEL) -> PackedByteArray:
	var out := PackedByteArray([ANT_SYNC, ANT_DATA_LENGTH, msg_id & 0xFF, channel & 0xFF])
	for i in PAGE_LENGTH:
		out.append(page[i] if i < page.size() else 0xFF)
	out.append(checksum(out))
	return out


## Страница 0x31 Target Power: байты 1–5 `FF`, 6–7 — мощность в 0.25 Вт, uint16 LE.
## 150 Вт → `A4 09 4F 05 31 FF FF FF FF FF 58 02 73`.
static func encode_target_power(watts: int) -> PackedByteArray:
	var v: int = clampi(watts * 4, 0, 0xFFFF)
	return encode_message(PackedByteArray([PAGE_TARGET_POWER, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, v & 0xFF, (v >> 8) & 0xFF]))


## `{ok, msg_id, channel, page_number, page}`; `ok == false` — сообщение отброшено (п.3).
static func decode_message(bytes: PackedByteArray) -> Dictionary:
	var r: Dictionary = {"ok": false, "msg_id": 0, "channel": 0, "page_number": -1, "page": PackedByteArray()}
	if bytes.size() < 4 or bytes[0] != ANT_SYNC or bytes[1] != ANT_DATA_LENGTH:
		return r
	if bytes.size() != bytes[1] + 4:
		return r
	if bytes[2] != ANT_BROADCAST_DATA and bytes[2] != ANT_ACKNOWLEDGED_DATA:
		return r
	if checksum(bytes.slice(0, bytes.size() - 1)) != bytes[bytes.size() - 1]:
		return r
	r["ok"] = true
	r["msg_id"] = bytes[2]
	r["channel"] = bytes[3]
	r["page"] = bytes.slice(4, 4 + PAGE_LENGTH)
	r["page_number"] = bytes[4]
	return r


## Страница 0x19: `{ok, has_power, power_w, has_cadence, cadence_rpm, trainer_status}`.
static func decode_trainer_data(page: PackedByteArray) -> Dictionary:
	var r: Dictionary = {"ok": false, "has_power": false, "power_w": 0, "has_cadence": false,
		"cadence_rpm": 0, "trainer_status": 0}
	if page.size() < PAGE_LENGTH or page[0] != PAGE_TRAINER_DATA:
		return r
	r["ok"] = true
	var power: int = page[5] | ((page[6] & 0x0F) << 8)
	r["has_power"] = power != NO_POWER
	r["power_w"] = power if r["has_power"] else 0
	r["has_cadence"] = page[2] != NO_BYTE
	r["cadence_rpm"] = page[2] if r["has_cadence"] else 0
	r["trainer_status"] = (page[6] >> 4) & 0x0F
	return r


## Страница 0x10: `{ok, has_speed, speed_kmh, has_heart_rate, heart_rate_bpm}`.
static func decode_general_fe(page: PackedByteArray) -> Dictionary:
	var r: Dictionary = {"ok": false, "has_speed": false, "speed_kmh": 0.0, "has_heart_rate": false,
		"heart_rate_bpm": 0}
	if page.size() < PAGE_LENGTH or page[0] != PAGE_GENERAL_FE:
		return r
	r["ok"] = true
	var raw: int = BleBytes.u16(page, 4)
	r["has_speed"] = raw != NO_SPEED
	r["speed_kmh"] = raw * 0.0036 if r["has_speed"] else 0.0
	r["has_heart_rate"] = page[6] != NO_BYTE
	r["heart_rate_bpm"] = page[6] if r["has_heart_rate"] else 0
	return r


# ---------------------------------------------------------------------------
# Текст для журнала
# ---------------------------------------------------------------------------

## Разбор ANT-сообщения (или голой 8-байтной страницы) для журнала: заголовок, контрольная сумма,
## страницы 0x10, 0x11, 0x19, 0x30, 0x31, 0x47, 0x50, 0x51; остальные — номер страницы.
static func describe(bytes: PackedByteArray) -> String:
	var page := PackedByteArray()
	var prefix := ""
	if bytes.size() >= MESSAGE_LENGTH and bytes[0] == ANT_SYNC:
		var length: int = bytes[1]
		var total: int = length + 4
		if bytes.size() < total or length < 9:
			return "ANT: short message"
		var cs_ok := checksum(bytes.slice(0, total - 1)) == bytes[total - 1]
		var kind := "broadcast" if bytes[2] == ANT_BROADCAST_DATA else ("ack" if bytes[2] == ANT_ACKNOWLEDGED_DATA else "msg 0x%02X" % bytes[2])
		prefix = "ANT %s ch%d%s, " % [kind, bytes[3], "" if cs_ok else " CHECKSUM BAD"]
		page = bytes.slice(4, 12)
	elif bytes.size() == PAGE_LENGTH:
		page = bytes
	else:
		return ""
	return prefix + describe_page(page)


static func describe_page(p: PackedByteArray) -> String:
	var n: int = p[0]
	match n:
		PAGE_GENERAL_FE:
			var speed_raw: int = BleBytes.u16(p, 4)
			var hr: int = p[6]
			return "page 0x10 General FE: type %s, elapsed %.2f s, distance %d m, speed %.2f km/h, HR %s, state %s" % [
				_equipment(p[1] & 0x1F), p[2] * 0.25, p[3], speed_raw * 0.001 * 3.6,
				"n/a" if hr == 0xFF else str(hr), _state((p[7] >> 4) & 0x07)]
		PAGE_GENERAL_SETTINGS:
			return "page 0x11 General Settings: incline %.2f %%, resistance %.1f %%, state %s" % [
				BleBytes.s16(p, 4) * 0.01, p[6] * 0.5, _state((p[7] >> 4) & 0x07)]
		PAGE_TRAINER_DATA:
			var power: int = p[5] | ((p[6] & 0x0F) << 8)
			return "page 0x19 Trainer Data: cadence %s rpm, power %s W, accumulated %d W, events %d, status 0x%X, target %s, state %s" % [
				"n/a" if p[2] == 0xFF else str(p[2]), "n/a" if power == 0xFFF else str(power), BleBytes.u16(p, 3),
				p[1], (p[6] >> 4) & 0x0F, _target_flag(p[7] & 0x03), _state((p[7] >> 4) & 0x07)]
		PAGE_BASIC_RESISTANCE:
			return "page 0x30 Basic Resistance: %.1f %%" % (p[7] * 0.5)
		PAGE_TARGET_POWER:
			return "page 0x31 Target Power: %.2f W" % (BleBytes.u16(p, 6) * 0.25)
		PAGE_COMMAND_STATUS:
			return "page 0x47 Command Status: last command 0x%02X, sequence %d, status %s, data %s" % [
				p[1], p[2], _command_status(p[3]), BleBytes.to_hex(p.slice(4, 8))]
		PAGE_MANUFACTURER:
			return "page 0x50 Manufacturer: HW rev %d, manufacturer %d, model %d" % [p[3], BleBytes.u16(p, 4), BleBytes.u16(p, 6)]
		PAGE_PRODUCT:
			return "page 0x51 Product: SW rev %d.%d, serial %d" % [p[3], p[2], BleBytes.u32(p, 4)]
	return "page 0x%02X" % n


static func _equipment(t: int) -> String:
	match t:
		16:
			return "general"
		19:
			return "treadmill"
		20:
			return "elliptical"
		22:
			return "rower"
		23:
			return "climber"
		24:
			return "nordic_skier"
		25:
			return "trainer"
	return str(t)


static func _state(s: int) -> String:
	match s:
		1:
			return "asleep"
		2:
			return "ready"
		3:
			return "in_use"
		4:
			return "finished"
	return "reserved_%d" % s


static func _target_flag(f: int) -> String:
	match f:
		0:
			return "at_target"
		1:
			return "speed_too_low"
		2:
			return "speed_too_high"
	return "limit_reached"


static func _command_status(s: int) -> String:
	match s:
		0:
			return "pass"
		1:
			return "fail"
		2:
			return "not_supported"
		3:
			return "rejected"
		4:
			return "pending"
		0xFF:
			return "uninitialized"
	return "0x%02X" % s
