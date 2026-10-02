class_name BatteryCodec
extends RefCounted
## Кодек Battery Service (BAS v1.0 §3.1, Battery Level `2A19`): REQ-DEV-07 крит. 2.
## Значение — uint8 0..100 %; 101..255 зарезервированы → `ok == false`.


## `{ok, level_pct}`: `64` → 100; `32` → 50; пусто или > 100 → ok false.
static func decode_level(bytes: PackedByteArray) -> Dictionary:
	var r: Dictionary = {"ok": false, "level_pct": 0}
	if bytes.is_empty():
		return r
	var v: int = bytes[0]
	if v > 100:
		return r
	r["ok"] = true
	r["level_pct"] = v
	return r


static func encode_level(level_pct: int) -> PackedByteArray:
	return PackedByteArray([clampi(level_pct, 0, 100)])
