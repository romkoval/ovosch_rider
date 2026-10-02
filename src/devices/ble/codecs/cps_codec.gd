class_name CpsCodec
extends RefCounted
## Кодек Cycling Power Service (CPS v1.1 §3.2; GSS, Cycling Power Measurement `2A63`):
## REQ-DEV-05 крит. 1, 3.
##
## Флаги uint16; мгновенная мощность — sint16 LE по смещению 2 всегда
## (`00 00 FA 00` → 250 Вт). Далее по флагам: бит 0 — Pedal Power Balance (uint8, 0.5 %),
## бит 2 — Accumulated Torque (uint16, 1/32 Н·м), бит 4 — Wheel Revolution Data
## (uint32 + uint16 время 1/2048 с), бит 5 — Crank Revolution Data (uint16 + uint16
## время 1/1024 с), бит 6 — Extreme Force (2 × sint16), бит 7 — Extreme Torque
## (2 × sint16), бит 8 — Extreme Angles (uint24), бит 9/10 — Top/Bottom Dead Spot
## (uint16), бит 11 — Accumulated Energy (uint16, кДж).
## Crank data возвращается с теми же ключами, что у `CscCodec`, — каденс считает
## `CscCadenceCalculator`.

const FLAG_PEDAL_BALANCE: int = 1 << 0
const FLAG_PEDAL_BALANCE_REFERENCE: int = 1 << 1
const FLAG_ACCUMULATED_TORQUE: int = 1 << 2
const FLAG_ACCUMULATED_TORQUE_SOURCE: int = 1 << 3
const FLAG_WHEEL_REV: int = 1 << 4
const FLAG_CRANK_REV: int = 1 << 5
const FLAG_EXTREME_FORCE: int = 1 << 6
const FLAG_EXTREME_TORQUE: int = 1 << 7
const FLAG_EXTREME_ANGLES: int = 1 << 8
const FLAG_TOP_DEAD_SPOT: int = 1 << 9
const FLAG_BOTTOM_DEAD_SPOT: int = 1 << 10
const FLAG_ACCUMULATED_ENERGY: int = 1 << 11
const FLAG_OFFSET_COMPENSATION: int = 1 << 12

## Частота счётчика времени колеса в CPS (отличается от CSC!).
const WHEEL_EVENT_TIME_HZ: float = 2048.0


## `{ok, flags, power_w, has_balance, pedal_balance_pct, has_torque, accumulated_torque_nm,
## has_wheel, wheel_revolutions, wheel_event_time, has_crank, crank_revolutions, crank_event_time, ...}`.
static func decode_cycling_power_measurement(bytes: PackedByteArray) -> Dictionary:
	var r: Dictionary = {
		"ok": false, "flags": 0, "power_w": 0,
		"has_balance": false, "pedal_balance_pct": 0.0,
		"has_torque": false, "accumulated_torque_nm": 0.0,
		"has_wheel": false, "wheel_revolutions": 0, "wheel_event_time": 0,
		"has_crank": false, "crank_revolutions": 0, "crank_event_time": 0,
	}
	if bytes.size() < 4:
		return r
	var flags: int = BleBytes.u16(bytes, 0)
	r["flags"] = flags
	r["power_w"] = BleBytes.s16(bytes, 2)
	var off: int = 4
	if flags & FLAG_PEDAL_BALANCE:
		if not BleBytes.has(bytes, off, 1):
			return r
		r["has_balance"] = true
		r["pedal_balance_pct"] = BleBytes.u8(bytes, off) * 0.5
		off += 1
	if flags & FLAG_ACCUMULATED_TORQUE:
		if not BleBytes.has(bytes, off, 2):
			return r
		r["has_torque"] = true
		r["accumulated_torque_nm"] = BleBytes.u16(bytes, off) / 32.0
		off += 2
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
	if flags & FLAG_EXTREME_FORCE:
		if not BleBytes.has(bytes, off, 4):
			return r
		r["max_force_n"] = BleBytes.s16(bytes, off)
		r["min_force_n"] = BleBytes.s16(bytes, off + 2)
		off += 4
	if flags & FLAG_EXTREME_TORQUE:
		if not BleBytes.has(bytes, off, 4):
			return r
		r["max_torque_nm"] = BleBytes.s16(bytes, off) / 32.0
		r["min_torque_nm"] = BleBytes.s16(bytes, off + 2) / 32.0
		off += 4
	if flags & FLAG_EXTREME_ANGLES:
		if not BleBytes.has(bytes, off, 3):
			return r
		var packed: int = BleBytes.u24(bytes, off)
		r["max_angle_deg"] = packed & 0xFFF
		r["min_angle_deg"] = (packed >> 12) & 0xFFF
		off += 3
	if flags & FLAG_TOP_DEAD_SPOT:
		if not BleBytes.has(bytes, off, 2):
			return r
		r["top_dead_spot_deg"] = BleBytes.u16(bytes, off)
		off += 2
	if flags & FLAG_BOTTOM_DEAD_SPOT:
		if not BleBytes.has(bytes, off, 2):
			return r
		r["bottom_dead_spot_deg"] = BleBytes.u16(bytes, off)
		off += 2
	if flags & FLAG_ACCUMULATED_ENERGY:
		if not BleBytes.has(bytes, off, 2):
			return r
		r["accumulated_energy_kj"] = BleBytes.u16(bytes, off)
		off += 2
	r["ok"] = true
	return r


## Для эмуляторов/тестов: мощность и (опционально) crank data.
static func encode_cycling_power_measurement(power_w: int, crank_revolutions: int = -1,
		crank_event_time: int = 0) -> PackedByteArray:
	var flags: int = FLAG_CRANK_REV if crank_revolutions >= 0 else 0
	var out := PackedByteArray()
	BleBytes.put_u16(out, flags)
	BleBytes.put_s16(out, power_w)
	if crank_revolutions >= 0:
		BleBytes.put_u16(out, crank_revolutions & 0xFFFF)
		BleBytes.put_u16(out, crank_event_time & 0xFFFF)
	return out
