class_name CscCodec
extends RefCounted
## Кодек Cycling Speed and Cadence (CSC v1.0 §3.1; GSS, CSC Measurement `2A5B`):
## REQ-DEV-04 крит. 1, 2.
##
## Флаги (uint8): бит 0 — Wheel Revolution Data (uint32 обороты + uint16 время
## 1/1024 с), бит 1 — Crank Revolution Data (uint16 обороты + uint16 время 1/1024 с).
## Каденс = Δоборотов / (Δвремени / 1024) × 60; счётчики — по модулю (uint16/uint32),
## переполнение даёт положительную дельту. Расчёт по двум измерениям — в
## `cadence_from_pair`; с учётом времени и таймаута — в `CscCadenceCalculator`.

const FLAG_WHEEL_REV: int = 1 << 0
const FLAG_CRANK_REV: int = 1 << 1
## Частота счётчика времени событий, Гц.
const EVENT_TIME_HZ: float = 1024.0


## `{ok, has_wheel, wheel_revolutions, wheel_event_time, has_crank, crank_revolutions, crank_event_time}`.
static func decode_csc_measurement(bytes: PackedByteArray) -> Dictionary:
	var r: Dictionary = {
		"ok": false, "has_wheel": false, "wheel_revolutions": 0, "wheel_event_time": 0,
		"has_crank": false, "crank_revolutions": 0, "crank_event_time": 0,
	}
	if bytes.is_empty():
		return r
	var flags: int = bytes[0]
	var off: int = 1
	if flags & FLAG_WHEEL_REV:
		if not BleBytes.has(bytes, off, 6):
			return r
		r["has_wheel"] = true
		r["wheel_revolutions"] = BleBytes.u32(bytes, off)
		r["wheel_event_time"] = BleBytes.u16(bytes, off + 4)
		off += 6
	if flags & FLAG_CRANK_REV:
		if not BleBytes.has(bytes, off, 4):
			return r
		r["has_crank"] = true
		r["crank_revolutions"] = BleBytes.u16(bytes, off)
		r["crank_event_time"] = BleBytes.u16(bytes, off + 2)
		off += 4
	r["ok"] = true
	return r


## Для эмуляторов/тестов: измерение только с crank data.
static func encode_crank_measurement(revolutions: int, event_time: int) -> PackedByteArray:
	var out := PackedByteArray([FLAG_CRANK_REV])
	BleBytes.put_u16(out, revolutions & 0xFFFF)
	BleBytes.put_u16(out, event_time & 0xFFFF)
	return out


## Каденс (rpm) по двум последовательным измерениям с crank data
## (словари с `crank_revolutions`, `crank_event_time`, как у `decode_csc_measurement`
## и `CpsCodec.decode_cycling_power_measurement`). Переполнение uint16 учитывается.
## Δвремени == 0 (нет нового события) → -1.0 («нет данных»); Δоборотов 3 при
## Δвремени 2048 → 90.0.
static func cadence_from_pair(prev: Dictionary, cur: Dictionary) -> float:
	var d_rev: int = (int(cur["crank_revolutions"]) - int(prev["crank_revolutions"])) & 0xFFFF
	var d_time: int = (int(cur["crank_event_time"]) - int(prev["crank_event_time"])) & 0xFFFF
	if d_time == 0:
		return -1.0
	return float(d_rev) / (float(d_time) / EVENT_TIME_HZ) * 60.0


## Скорость колеса (км/ч) по двум измерениям с wheel data и длине окружности в мм.
## Счётчик оборотов uint32, времени uint16. Δвремени == 0 → -1.0.
static func wheel_speed_from_pair(prev: Dictionary, cur: Dictionary, circumference_mm: float) -> float:
	var d_rev: int = (int(cur["wheel_revolutions"]) - int(prev["wheel_revolutions"])) & 0xFFFFFFFF
	var d_time: int = (int(cur["wheel_event_time"]) - int(prev["wheel_event_time"])) & 0xFFFF
	if d_time == 0:
		return -1.0
	var meters: float = float(d_rev) * circumference_mm / 1000.0
	return meters / (float(d_time) / EVENT_TIME_HZ) * 3.6
