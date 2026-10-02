class_name HrsCodec
extends RefCounted
## Кодек Heart Rate Service (HRS v1.0 §3.1; GATT Specification Supplement,
## Heart Rate Measurement `2A37`): REQ-DEV-03 крит. 1, 2.
##
## Флаги (uint8): бит 0 — формат значения (0: uint8, 1: uint16); биты 1–2 —
## контакт датчика (бит 2: поддерживается, бит 1: обнаружен); бит 3 — Energy
## Expended (uint16, кДж); бит 4 — RR-интервалы (uint16 × 1/1024 с, несколько).
## `00 48` → 72 уд/мин; `01 48 00` → 72 уд/мин.

## Состояние контакта датчика.
enum SensorContact { NOT_SUPPORTED, NOT_DETECTED, DETECTED }

const FLAG_FORMAT_UINT16: int = 1 << 0
const FLAG_CONTACT_DETECTED: int = 1 << 1
const FLAG_CONTACT_SUPPORTED: int = 1 << 2
const FLAG_ENERGY_EXPENDED: int = 1 << 3
const FLAG_RR_INTERVALS: int = 1 << 4


## `{ok, bpm, sensor_contact (SensorContact), contact_ok, has_energy, energy_kj,
## rr_intervals_ms: Array[float]}`. `contact_ok == false` только при
## «поддерживается, но не обнаружен» — тогда пульс недостоверен (REQ-DEV-03 крит. 2).
static func decode_heart_rate_measurement(bytes: PackedByteArray) -> Dictionary:
	var rr: Array[float] = []
	var r: Dictionary = {
		"ok": false, "bpm": 0, "sensor_contact": SensorContact.NOT_SUPPORTED, "contact_ok": true,
		"has_energy": false, "energy_kj": 0, "rr_intervals_ms": rr,
	}
	if bytes.size() < 2:
		return r
	var flags: int = bytes[0]
	var off: int = 1
	if flags & FLAG_FORMAT_UINT16:
		if not BleBytes.has(bytes, off, 2):
			return r
		r["bpm"] = BleBytes.u16(bytes, off)
		off += 2
	else:
		r["bpm"] = BleBytes.u8(bytes, off)
		off += 1
	if flags & FLAG_CONTACT_SUPPORTED:
		if flags & FLAG_CONTACT_DETECTED:
			r["sensor_contact"] = SensorContact.DETECTED
		else:
			r["sensor_contact"] = SensorContact.NOT_DETECTED
			r["contact_ok"] = false
	if flags & FLAG_ENERGY_EXPENDED:
		if not BleBytes.has(bytes, off, 2):
			return r
		r["has_energy"] = true
		r["energy_kj"] = BleBytes.u16(bytes, off)
		off += 2
	if flags & FLAG_RR_INTERVALS:
		while BleBytes.has(bytes, off, 2):
			rr.append(BleBytes.u16(bytes, off) * 1000.0 / 1024.0)
			off += 2
	r["ok"] = true
	return r


## Для эмуляторов/тестов: собрать измерение с заданным контактом.
static func encode_heart_rate_measurement(bpm: int, contact: SensorContact = SensorContact.NOT_SUPPORTED) -> PackedByteArray:
	var flags: int = 0
	if bpm > 255:
		flags |= FLAG_FORMAT_UINT16
	match contact:
		SensorContact.DETECTED:
			flags |= FLAG_CONTACT_SUPPORTED | FLAG_CONTACT_DETECTED
		SensorContact.NOT_DETECTED:
			flags |= FLAG_CONTACT_SUPPORTED
		_:
			pass
	var out := PackedByteArray([flags])
	if flags & FLAG_FORMAT_UINT16:
		BleBytes.put_u16(out, bpm)
	else:
		BleBytes.put_u8(out, bpm)
	return out
