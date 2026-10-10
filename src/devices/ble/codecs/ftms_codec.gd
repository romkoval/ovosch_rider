class_name FtmsCodec
extends RefCounted
## Кодек Fitness Machine Service (Bluetooth SIG FTMS v1.0): REQ-DEV-02 крит. 2–5,
## REQ-WRK-04 крит. 2, REQ-DEV-08 крит. 3.
##
## Разбираемые характеристики:
## - Indoor Bike Data `2AD2` (FTMS §4.9): флаги uint16, далее поля по флагам;
## - Fitness Machine Control Point `2AD9` (FTMS §4.16): запросы и ответ 0x80;
## - Supported Resistance Level Range `2AD6` (FTMS §4.5): min/max sint16, inc uint16, ед. 0.1;
## - Supported Inclination Range `2AD5` (FTMS §4.4): min/max sint16, inc uint16, ед. 0.1 %;
## - Fitness Machine Feature `2ACC` (FTMS §4.3): Fitness Machine Features uint32 +
##   Target Setting Features uint32 (REQ-FRD-04 крит. 6);
## - Fitness Machine Status `2ADA` (FTMS §4.17).
## Команда SIM Set Indoor Bike Simulation Parameters `0x11` (FTMS §4.16.2.18,
## REQ-FRD-04 крит. 1): ветер sint16 ×0.001 м/с, уклон sint16 ×0.01 %,
## Crr uint8 ×0.0001, Cw uint8 ×0.01 кг/м.
## Все функции статические, без состояния. `decode_*` возвращают словарь с
## `ok: bool`; при обрезанном пакете разбор останавливается, присутствующие
## поля остаются, `ok == false`.

# --- Опкоды Control Point (FTMS §4.16.1) ---
const OP_REQUEST_CONTROL: int = 0x00
const OP_RESET: int = 0x01
const OP_SET_TARGET_RESISTANCE: int = 0x04
const OP_SET_TARGET_POWER: int = 0x05
const OP_START_RESUME: int = 0x07
const OP_STOP_PAUSE: int = 0x08
const OP_SET_INDOOR_BIKE_SIMULATION: int = 0x11
const OP_RESPONSE_CODE: int = 0x80
## Параметр Stop or Pause.
const STOP_PARAM_STOP: int = 0x01
const STOP_PARAM_PAUSE: int = 0x02

# --- Коды результата ответа Control Point (FTMS §4.16.2.22) ---
const RESULT_SUCCESS: int = 0x01
const RESULT_NOT_SUPPORTED: int = 0x02
const RESULT_INVALID_PARAMETER: int = 0x03
const RESULT_OPERATION_FAILED: int = 0x04
const RESULT_CONTROL_NOT_PERMITTED: int = 0x05

# --- Флаги Indoor Bike Data (FTMS §4.9.1.1) ---
const IBD_MORE_DATA: int = 1 << 0
const IBD_AVERAGE_SPEED: int = 1 << 1
const IBD_INSTANT_CADENCE: int = 1 << 2
const IBD_AVERAGE_CADENCE: int = 1 << 3
const IBD_TOTAL_DISTANCE: int = 1 << 4
const IBD_RESISTANCE_LEVEL: int = 1 << 5
const IBD_INSTANT_POWER: int = 1 << 6
const IBD_AVERAGE_POWER: int = 1 << 7
const IBD_EXPENDED_ENERGY: int = 1 << 8
const IBD_HEART_RATE: int = 1 << 9
const IBD_METABOLIC_EQUIVALENT: int = 1 << 10
const IBD_ELAPSED_TIME: int = 1 << 11
const IBD_REMAINING_TIME: int = 1 << 12

# --- Опкоды Fitness Machine Status (FTMS §4.17.1) ---
const STATUS_RESET: int = 0x01
const STATUS_STOPPED_OR_PAUSED_BY_USER: int = 0x02
const STATUS_STOPPED_BY_SAFETY_KEY: int = 0x03
const STATUS_STARTED_OR_RESUMED_BY_USER: int = 0x04
const STATUS_TARGET_SPEED_CHANGED: int = 0x05
const STATUS_TARGET_INCLINE_CHANGED: int = 0x06
const STATUS_TARGET_RESISTANCE_CHANGED: int = 0x07
const STATUS_TARGET_POWER_CHANGED: int = 0x08
const STATUS_TARGET_HEART_RATE_CHANGED: int = 0x09
const STATUS_CONTROL_PERMISSION_LOST: int = 0xFF

# --- Target Setting Features в Fitness Machine Feature 2ACC (FTMS §4.3.1.2) ---
const TSF_INCLINATION: int = 1 << 1
const TSF_RESISTANCE: int = 1 << 2
const TSF_POWER: int = 1 << 3
const TSF_INDOOR_BIKE_SIMULATION: int = 1 << 13

# --- Параметры SIM 0x11: разрешение и пределы представимых значений ---
## Ветер: sint16, разрешение 0.001 м/с.
const SIM_WIND_UNIT: float = 0.001
const SIM_WIND_MAX_MPS: float = 32.767
## Уклон: sint16, разрешение 0.01 %; диапазон симметричный ±327.67 % (REQ-FRD-04 крит. 1).
const SIM_GRADE_UNIT: float = 0.01
const SIM_GRADE_MAX_PCT: float = 327.67
## Crr: uint8, разрешение 0.0001.
const SIM_CRR_UNIT: float = 0.0001
const SIM_CRR_MAX: float = 0.0255
## Cw: uint8, разрешение 0.01 кг/м.
const SIM_CW_UNIT: float = 0.01
const SIM_CW_MAX: float = 2.55
## Допуск сравнения с пределом (погрешность float на границе вроде 327.67).
const SIM_LIMIT_EPSILON: float = 1e-9

## Единица уклона в Supported Inclination Range 2AD5, %.
const INCLINATION_UNIT: float = 0.1

## Единица уровня сопротивления в Control Point и 2AD6.
const RESISTANCE_UNIT: float = 0.1
## Диапазон уровня по умолчанию, если 2AD6 не прочитан (REQ-WRK-04 крит. 2): 0..100 единиц 0.1.
const DEFAULT_RESISTANCE_MAX_LEVEL: float = 10.0
## Максимальный уровень, представимый в параметре Set Target Resistance Level
## (uint8 в единицах 0.1 → 25.5).
const CONTROL_POINT_MAX_LEVEL: float = 25.5

## Предупреждение о диапазоне 2AD6 шире кодируемого выдаётся один раз.
static var _range_cap_warned: bool = false


# ---------------------------------------------------------------------------
# Indoor Bike Data 2AD2
# ---------------------------------------------------------------------------

## Разбор Indoor Bike Data. Ключи: `has_speed/speed_kmh` (0.01 км/ч),
## `has_cadence/cadence_rpm` (0.5 rpm → float), `has_power/power_w` (sint16 Вт),
## `has_heart_rate/heart_rate_bpm`, а также average_*, `distance_m`,
## `resistance_level`, `energy_total_kcal`, `elapsed_sec`, `remaining_sec`, `flags`.
## Мгновенная скорость присутствует, когда флаг More Data (бит 0) сброшен.
static func decode_indoor_bike_data(bytes: PackedByteArray) -> Dictionary:
	var r: Dictionary = {
		"ok": false, "flags": 0,
		"has_speed": false, "speed_kmh": 0.0,
		"has_cadence": false, "cadence_rpm": 0.0,
		"has_power": false, "power_w": 0,
		"has_heart_rate": false, "heart_rate_bpm": 0,
	}
	if not BleBytes.has(bytes, 0, 2):
		return r
	var flags: int = BleBytes.u16(bytes, 0)
	r["flags"] = flags
	var off: int = 2
	if flags & IBD_MORE_DATA == 0:
		if not BleBytes.has(bytes, off, 2):
			return r
		r["has_speed"] = true
		r["speed_kmh"] = BleBytes.u16(bytes, off) * 0.01
		off += 2
	if flags & IBD_AVERAGE_SPEED:
		if not BleBytes.has(bytes, off, 2):
			return r
		r["average_speed_kmh"] = BleBytes.u16(bytes, off) * 0.01
		off += 2
	if flags & IBD_INSTANT_CADENCE:
		if not BleBytes.has(bytes, off, 2):
			return r
		r["has_cadence"] = true
		r["cadence_rpm"] = BleBytes.u16(bytes, off) * 0.5
		off += 2
	if flags & IBD_AVERAGE_CADENCE:
		if not BleBytes.has(bytes, off, 2):
			return r
		r["average_cadence_rpm"] = BleBytes.u16(bytes, off) * 0.5
		off += 2
	if flags & IBD_TOTAL_DISTANCE:
		if not BleBytes.has(bytes, off, 3):
			return r
		r["distance_m"] = BleBytes.u24(bytes, off)
		off += 3
	if flags & IBD_RESISTANCE_LEVEL:
		if not BleBytes.has(bytes, off, 2):
			return r
		r["resistance_level"] = BleBytes.s16(bytes, off)
		off += 2
	if flags & IBD_INSTANT_POWER:
		if not BleBytes.has(bytes, off, 2):
			return r
		r["has_power"] = true
		r["power_w"] = BleBytes.s16(bytes, off)
		off += 2
	if flags & IBD_AVERAGE_POWER:
		if not BleBytes.has(bytes, off, 2):
			return r
		r["average_power_w"] = BleBytes.s16(bytes, off)
		off += 2
	if flags & IBD_EXPENDED_ENERGY:
		if not BleBytes.has(bytes, off, 5):
			return r
		r["energy_total_kcal"] = BleBytes.u16(bytes, off)
		r["energy_per_hour_kcal"] = BleBytes.u16(bytes, off + 2)
		r["energy_per_minute_kcal"] = BleBytes.u8(bytes, off + 4)
		off += 5
	if flags & IBD_HEART_RATE:
		if not BleBytes.has(bytes, off, 1):
			return r
		r["has_heart_rate"] = true
		r["heart_rate_bpm"] = BleBytes.u8(bytes, off)
		off += 1
	if flags & IBD_METABOLIC_EQUIVALENT:
		if not BleBytes.has(bytes, off, 1):
			return r
		r["metabolic_equivalent"] = BleBytes.u8(bytes, off) * 0.1
		off += 1
	if flags & IBD_ELAPSED_TIME:
		if not BleBytes.has(bytes, off, 2):
			return r
		r["elapsed_sec"] = BleBytes.u16(bytes, off)
		off += 2
	if flags & IBD_REMAINING_TIME:
		if not BleBytes.has(bytes, off, 2):
			return r
		r["remaining_sec"] = BleBytes.u16(bytes, off)
		off += 2
	r["ok"] = true
	return r


## Обратная операция для тестов и эмуляторов: собрать Indoor Bike Data из
## скорости/каденса/мощности/пульса (отрицательный или null-параметр — поле отсутствует).
static func encode_indoor_bike_data(speed_kmh: float, cadence_rpm: float, power_w: int,
		heart_rate_bpm: int = -1) -> PackedByteArray:
	var flags: int = 0
	if speed_kmh < 0.0:
		flags |= IBD_MORE_DATA
	if cadence_rpm >= 0.0:
		flags |= IBD_INSTANT_CADENCE
	flags |= IBD_INSTANT_POWER
	if heart_rate_bpm >= 0:
		flags |= IBD_HEART_RATE
	var out := PackedByteArray()
	BleBytes.put_u16(out, flags)
	if speed_kmh >= 0.0:
		BleBytes.put_u16(out, roundi(speed_kmh / 0.01))
	if cadence_rpm >= 0.0:
		BleBytes.put_u16(out, roundi(cadence_rpm / 0.5))
	BleBytes.put_s16(out, power_w)
	if heart_rate_bpm >= 0:
		BleBytes.put_u8(out, heart_rate_bpm)
	return out


# ---------------------------------------------------------------------------
# Control Point 2AD9
# ---------------------------------------------------------------------------

static func encode_request_control() -> PackedByteArray:
	return PackedByteArray([OP_REQUEST_CONTROL])


static func encode_reset() -> PackedByteArray:
	return PackedByteArray([OP_RESET])


## Set Target Power: `05 <sint16 LE Вт>`; 250 → `05 FA 00` (REQ-DEV-02 крит. 4).
static func encode_set_target_power(watts: int) -> PackedByteArray:
	var out := PackedByteArray([OP_SET_TARGET_POWER])
	BleBytes.put_s16(out, watts)
	return out


## Set Target Resistance Level: `04 <uint8, ед. 0.1>`; уровень 5.0 → `04 32`
## (REQ-DEV-02 крит. 5). Уровень клампится в 0..25.5.
static func encode_set_resistance_level(level: float) -> PackedByteArray:
	var units: int = clampi(roundi(level / RESISTANCE_UNIT), 0, 255)
	return PackedByteArray([OP_SET_TARGET_RESISTANCE, units])


## Set Indoor Bike Simulation Parameters (REQ-FRD-04 крит. 1):
## `11 <wind sint16 LE ×0.001> <grade sint16 LE ×0.01> <crr uint8 ×0.0001> <cw uint8 ×0.01>`;
## (0, 5.0, 0.004, 0.20) → `11 00 00 F4 01 28 14`. Значение вне диапазона типа
## (см. `simulation_params_error`) — пустой массив: команда не формируется.
static func encode_indoor_bike_simulation(wind_mps: float, grade_pct: float, crr: float,
		cw: float) -> PackedByteArray:
	if simulation_params_error(wind_mps, grade_pct, crr, cw) != "":
		return PackedByteArray()
	var out := PackedByteArray([OP_SET_INDOOR_BIKE_SIMULATION])
	BleBytes.put_s16(out, roundi(wind_mps / SIM_WIND_UNIT))
	BleBytes.put_s16(out, roundi(grade_pct / SIM_GRADE_UNIT))
	BleBytes.put_u8(out, clampi(roundi(crr / SIM_CRR_UNIT), 0, 255))
	BleBytes.put_u8(out, clampi(roundi(cw / SIM_CW_UNIT), 0, 255))
	return out


## Причина, по которой параметры SIM не кодируются, или "" — если кодируются:
## |ветер| ≤ 32.767 м/с, |уклон| ≤ 327.67 %, 0 ≤ Crr ≤ 0.0255, 0 ≤ Cw ≤ 2.55, все конечны.
static func simulation_params_error(wind_mps: float, grade_pct: float, crr: float, cw: float) -> String:
	if not (is_finite(wind_mps) and is_finite(grade_pct) and is_finite(crr) and is_finite(cw)):
		return "параметр SIM не является конечным числом"
	if absf(wind_mps) > SIM_WIND_MAX_MPS + SIM_LIMIT_EPSILON:
		return "ветер %.3f м/с вне ±%.3f" % [wind_mps, SIM_WIND_MAX_MPS]
	if absf(grade_pct) > SIM_GRADE_MAX_PCT + SIM_LIMIT_EPSILON:
		return "уклон %.2f %% вне ±%.2f" % [grade_pct, SIM_GRADE_MAX_PCT]
	if crr < -SIM_LIMIT_EPSILON or crr > SIM_CRR_MAX + SIM_LIMIT_EPSILON:
		return "Crr %.5f вне 0..%.4f" % [crr, SIM_CRR_MAX]
	if cw < -SIM_LIMIT_EPSILON or cw > SIM_CW_MAX + SIM_LIMIT_EPSILON:
		return "Cw %.3f вне 0..%.2f" % [cw, SIM_CW_MAX]
	return ""


static func encode_start() -> PackedByteArray:
	return PackedByteArray([OP_START_RESUME])


static func encode_stop() -> PackedByteArray:
	return PackedByteArray([OP_STOP_PAUSE, STOP_PARAM_STOP])


static func encode_pause() -> PackedByteArray:
	return PackedByteArray([OP_STOP_PAUSE, STOP_PARAM_PAUSE])


## Ответ станка `80 <opcode> <result>` — для эмуляторов.
static func encode_control_point_response(request_opcode: int, result: int) -> PackedByteArray:
	return PackedByteArray([OP_RESPONSE_CODE, request_opcode & 0xFF, result & 0xFF])


## Разбор индикации Control Point: `{ok, request_opcode, result, success}`.
## `ok == false`, если это не ответ 0x80 или пакет короче 3 байт
## (REQ-DEV-02 крит. 3: `success == false` при result != 0x01).
static func decode_control_point_response(bytes: PackedByteArray) -> Dictionary:
	var r: Dictionary = {"ok": false, "request_opcode": -1, "result": -1, "success": false}
	if bytes.size() < 3 or bytes[0] != OP_RESPONSE_CODE:
		return r
	r["ok"] = true
	r["request_opcode"] = bytes[1]
	r["result"] = bytes[2]
	r["success"] = bytes[2] == RESULT_SUCCESS
	if bytes.size() > 3:
		r["parameters"] = bytes.slice(3)
	return r


static func result_name(result: int) -> String:
	match result:
		RESULT_SUCCESS:
			return "success"
		RESULT_NOT_SUPPORTED:
			return "not_supported"
		RESULT_INVALID_PARAMETER:
			return "invalid_parameter"
		RESULT_OPERATION_FAILED:
			return "operation_failed"
		RESULT_CONTROL_NOT_PERMITTED:
			return "control_not_permitted"
	return "unknown_0x%02X" % result


static func opcode_name(opcode: int) -> String:
	match opcode:
		OP_REQUEST_CONTROL:
			return "request_control"
		OP_RESET:
			return "reset"
		OP_SET_TARGET_RESISTANCE:
			return "set_target_resistance_level"
		OP_SET_TARGET_POWER:
			return "set_target_power"
		OP_START_RESUME:
			return "start_or_resume"
		OP_STOP_PAUSE:
			return "stop_or_pause"
		OP_SET_INDOOR_BIKE_SIMULATION:
			return "set_indoor_bike_simulation"
		OP_RESPONSE_CODE:
			return "response_code"
	return "opcode_0x%02X" % opcode


# ---------------------------------------------------------------------------
# Supported Resistance Level Range 2AD6
# ---------------------------------------------------------------------------

## `{ok, min_level, max_level, increment}` в уровнях (ед. 0.1 → float):
## `00 00 C8 00 0A 00` → 0.0 .. 20.0 шаг 1.0.
static func decode_resistance_range(bytes: PackedByteArray) -> Dictionary:
	var r: Dictionary = {"ok": false, "min_level": 0.0, "max_level": 0.0, "increment": 0.0}
	if bytes.size() < 6:
		return r
	r["min_level"] = BleBytes.s16(bytes, 0) * RESISTANCE_UNIT
	r["max_level"] = BleBytes.s16(bytes, 2) * RESISTANCE_UNIT
	r["increment"] = BleBytes.u16(bytes, 4) * RESISTANCE_UNIT
	r["ok"] = r["max_level"] > r["min_level"]
	return r


# ---------------------------------------------------------------------------
# Supported Inclination Range 2AD5, Fitness Machine Feature 2ACC
# ---------------------------------------------------------------------------

## `{ok, min_pct, max_pct, increment_pct}` (ед. 0.1 % → float; REQ-FRD-04 крит. 3):
## `9C FF C8 00 05 00` → −10.0 .. 20.0 %, шаг 0.5 %. `ok == false` при пакете
## короче 6 байт или max ≤ min.
static func decode_supported_inclination_range(bytes: PackedByteArray) -> Dictionary:
	var r: Dictionary = {"ok": false, "min_pct": 0.0, "max_pct": 0.0, "increment_pct": 0.0}
	if bytes.size() < 6:
		return r
	r["min_pct"] = BleBytes.s16(bytes, 0) * INCLINATION_UNIT
	r["max_pct"] = BleBytes.s16(bytes, 2) * INCLINATION_UNIT
	r["increment_pct"] = BleBytes.u16(bytes, 4) * INCLINATION_UNIT
	r["ok"] = r["max_pct"] > r["min_pct"]
	return r


## `{ok, machine_features, target_settings, simulation_supported, resistance_supported,
## power_supported, inclination_supported}` (REQ-FRD-04 крит. 6). Бит 13 Target Setting
## Features — «Indoor Bike Simulation Parameters Supported». `ok == false` при пакете
## короче 8 байт (оба поля uint32 обязательны), флаги поддержки тогда false.
static func decode_fitness_machine_feature(bytes: PackedByteArray) -> Dictionary:
	var r: Dictionary = {
		"ok": false, "machine_features": 0, "target_settings": 0,
		"simulation_supported": false, "resistance_supported": false,
		"power_supported": false, "inclination_supported": false,
	}
	if bytes.size() < 8:
		return r
	var ts: int = BleBytes.u32(bytes, 4)
	r["machine_features"] = BleBytes.u32(bytes, 0)
	r["target_settings"] = ts
	r["simulation_supported"] = ts & TSF_INDOOR_BIKE_SIMULATION != 0
	r["resistance_supported"] = ts & TSF_RESISTANCE != 0
	r["power_supported"] = ts & TSF_POWER != 0
	r["inclination_supported"] = ts & TSF_INCLINATION != 0
	r["ok"] = true
	return r


## Supported Power Range `0x2AD8` (REQ-DEV-10 п.6): min, max — sint16 LE, Вт; increment — uint16 LE,
## Вт. `{ok, min_w, max_w, increment_w}`; `ok == false` — короче 6 байт или max ≤ min.
## `00 00 C4 09 01 00` → 0..2500 Вт, шаг 1; `19 00 DC 05 05 00` → 25..1500 Вт, шаг 5.
static func decode_supported_power_range(bytes: PackedByteArray) -> Dictionary:
	var r: Dictionary = {"ok": false, "min_w": 0, "max_w": 0, "increment_w": 1}
	if bytes.size() < 6:
		return r
	r["min_w"] = BleBytes.s16(bytes, 0)
	r["max_w"] = BleBytes.s16(bytes, 2)
	r["increment_w"] = maxi(BleBytes.u16(bytes, 4), 1)
	r["ok"] = int(r["max_w"]) > int(r["min_w"])
	return r


## Цель Set Target Power в диапазоне `0x2AD8` (без него — запасной, DEV-10 п.7).
static func clamp_target_power(watts: int, power_range: Dictionary = {}) -> int:
	var range: Dictionary = power_range if power_range.get("ok", false) else TrainerDevice.fallback_power_range()
	return TrainerDevice.clamp_target_to_range(watts, range)


## Обратная операция для тестов и эмуляторов.
static func encode_fitness_machine_feature(machine_features: int, target_settings: int) -> PackedByteArray:
	var out := PackedByteArray()
	BleBytes.put_u16(out, machine_features & 0xFFFF)
	BleBytes.put_u16(out, (machine_features >> 16) & 0xFFFF)
	BleBytes.put_u16(out, target_settings & 0xFFFF)
	BleBytes.put_u16(out, (target_settings >> 16) & 0xFFFF)
	return out


## Процент 0..100 → уровень сопротивления станка (REQ-WRK-04 крит. 2).
## Без диапазона (`range` пуст или `ok == false`) — линейно в 0..10.0 (0..100 единиц 0.1).
## С диапазоном 2AD6 — линейно в **фактически кодируемом** поддиапазоне
## `[max(min, 0); min(max, 25.5)]` с привязкой к шагу `increment`. Причина:
## 2AD6 отдаёт sint16 (у Tacx Neo 0..100.0), а параметр команды 0x04 — uint8
## в единицах 0.1, т.е. максимум 25.5; без этого ограничения все уровни выше
## 25 % сливались бы в `04 FF`. Если max 2AD6 > 25.5, один раз выдаётся
## предупреждение.
static func percent_to_resistance_level(percent: int, range: Dictionary = {}) -> float:
	var p: float = clampi(percent, 0, 100) / 100.0
	if range.is_empty() or not range.get("ok", false):
		return p * DEFAULT_RESISTANCE_MAX_LEVEL
	var raw_lo: float = range["min_level"]
	var raw_hi: float = range["max_level"]
	if raw_hi > CONTROL_POINT_MAX_LEVEL and not _range_cap_warned:
		_range_cap_warned = true
		push_warning("FtmsCodec: диапазон 2AD6 до %.1f шире кодируемого в Set Target Resistance Level (uint8 ×0.1, макс %.1f); проценты масштабируются на 0..%.1f" % [
			raw_hi, CONTROL_POINT_MAX_LEVEL, CONTROL_POINT_MAX_LEVEL])
	var lo: float = maxf(raw_lo, 0.0)
	var hi: float = minf(raw_hi, CONTROL_POINT_MAX_LEVEL)
	if hi <= lo:
		return clampf(lo, 0.0, CONTROL_POINT_MAX_LEVEL)
	var inc: float = range.get("increment", 0.0)
	var level: float = lo + (hi - lo) * p
	if inc > 0.0:
		level = lo + roundf((level - lo) / inc) * inc
	return clampf(level, lo, hi)


# ---------------------------------------------------------------------------
# Fitness Machine Status 2ADA
# ---------------------------------------------------------------------------

## `{ok, opcode, name}` + `value` для статусов с параметром:
## `08 FA 00` → target_power_changed, value 250; `02 02` → stopped_or_paused, value 2 (pause);
## `07 32` → target_resistance_changed, value 5.0; `FF` → control_permission_lost.
static func decode_machine_status(bytes: PackedByteArray) -> Dictionary:
	var r: Dictionary = {"ok": false, "opcode": -1, "name": "unknown"}
	if bytes.is_empty():
		return r
	var op: int = bytes[0]
	r["opcode"] = op
	r["ok"] = true
	match op:
		STATUS_RESET:
			r["name"] = "reset"
		STATUS_STOPPED_OR_PAUSED_BY_USER:
			r["name"] = "stopped_or_paused_by_user"
			r["value"] = BleBytes.u8(bytes, 1)
		STATUS_STOPPED_BY_SAFETY_KEY:
			r["name"] = "stopped_by_safety_key"
		STATUS_STARTED_OR_RESUMED_BY_USER:
			r["name"] = "started_or_resumed_by_user"
		STATUS_TARGET_SPEED_CHANGED:
			r["name"] = "target_speed_changed"
			r["value"] = BleBytes.u16(bytes, 1) * 0.01
		STATUS_TARGET_INCLINE_CHANGED:
			r["name"] = "target_incline_changed"
			r["value"] = BleBytes.s16(bytes, 1) * 0.1
		STATUS_TARGET_RESISTANCE_CHANGED:
			r["name"] = "target_resistance_changed"
			r["value"] = BleBytes.u8(bytes, 1) * RESISTANCE_UNIT
		STATUS_TARGET_POWER_CHANGED:
			r["name"] = "target_power_changed"
			r["value"] = BleBytes.s16(bytes, 1)
		STATUS_TARGET_HEART_RATE_CHANGED:
			r["name"] = "target_heart_rate_changed"
			r["value"] = BleBytes.u8(bytes, 1)
		STATUS_CONTROL_PERMISSION_LOST:
			r["name"] = "control_permission_lost"
		_:
			r["name"] = "status_0x%02X" % op
	return r
