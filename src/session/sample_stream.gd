class_name SampleStream
extends RefCounted
## Поток сэмплов 1 Гц сессии (REQ-WRK-08, REQ-DEV-08 крит. 2).
##
## Колонки одинаковой длины; строка i — секунда `time_sec[i]` активного
## времени (с от старта, монотонно, шаг 1). Ровно один слот на секунду:
## если за секунду телеметрия не пришла, слот всё равно добавляется с
## `has_* == false` («нет данных», а не 0). Если пришло несколько сэмплов —
## записывается последний (REQ-WRK-08 крит. 3; выбор делает `WorkoutSession`).
##
## Возраст данных `*_age_sec` — сколько секунд назад источник последний раз
## присылал значение (0 — в этой секунде, -1 — ни разу). Для HUD: значение
## старше `STALE_AFTER_SEC` считается «нет данных» (REQ-WRK-08 крит. 4); сам
## поток строже — слот без телеметрии уже «нет данных».
##
## Скорость — только расчётная по модели с уклоном (`SpeedModel`, `speed_source` = "model",
## REQ-WRK-08 п.5, D3D-02 п.6, решение У-30): сессии всегда передают скорость модели, поле
## скорости станка в их поток не попадает. Старые заезды со `speed_source` = "trainer"
## (`Ride.SPEED_SOURCE_TRAINER_LEGACY`) читаются как есть, без пересчёта. `distance_m` —
## интеграл скорости по секундам.
##
## Свободная езда (REQ-FRD-07 крит. 4): сэмпл дополнительно несёт позицию на трассе —
## накопленную дистанцию от старта (её даёт сессия по `RoutePosition`, она заменяет
## интеграл скорости), высоту h(s) `altitude_m` и уклон трассы `grade_pct`. Признак
## `has_route[i]`; у заездов по плану он `false`, высота и уклон — 0 (поля отсутствуют).

const SPEED_SOURCE_MODEL: String = "model"
## Порог «данные устарели» для HUD, с.
const STALE_AFTER_SEC: int = 5
const SCHEMA_VERSION: int = 1

var time_sec := PackedInt32Array()
var power_w := PackedInt32Array()
var has_power: Array[bool] = []
var cadence_rpm := PackedInt32Array()
var has_cadence: Array[bool] = []
var speed_kmh := PackedFloat32Array()
var has_speed: Array[bool] = []
var heart_rate_bpm := PackedInt32Array()
var has_heart_rate: Array[bool] = []
## Целевая мощность исполнителя в этот момент, Вт (0 — нет цели).
var target_w := PackedInt32Array()
## Номер шага плана (-1 — вне плана).
var step_index := PackedInt32Array()
var erg_enabled: Array[bool] = []
## Возраст данных по источникам, с (0 — свежие, -1 — ещё не было).
var power_age_sec := PackedInt32Array()
var cadence_age_sec := PackedInt32Array()
var heart_rate_age_sec := PackedInt32Array()
## Пройденное расстояние к концу секунды, м (интеграл скорости).
var distance_m := PackedFloat32Array()
## Высота трассы h(s) к концу секунды, м (свободная езда; иначе 0).
var altitude_m := PackedFloat32Array()
## Уклон трассы g(s), % (свободная езда; иначе 0).
var grade_pct := PackedFloat32Array()
## Сэмпл несёт позицию на трассе (дистанция от трассы, высота, уклон) — свободная езда.
var has_route: Array[bool] = []
## "model" у новых потоков; у старых заездов — как записано ("trainer" | "model" | "").
var speed_source: String = ""


func size() -> int:
	return time_sec.size()


## Добавить слот секунды `t`. `sample` может быть null (нет телеметрии за секунду);
## `hr_bpm < 0` — нет пульса. `model_speed_kmh >= 0` — расчётная скорость модели (так пишут
## сессии); < 0 — скорость берётся из `sample` как есть (готовые потоки: фикстуры, импорт).
## `ages` — `{power, cadence, heart_rate}` в секундах.
## `route` — позиция на трассе для свободной езды (REQ-FRD-07 крит. 4):
## `{distance_m, altitude_m, grade_pct}`; `distance_m` (накопленная от старта) заменяет
## интеграл скорости. Пустой словарь — сэмпл без позиции (тренировка по плану).
func append(t: int, sample: TrainerSample, hr_bpm: int, target: int, step: int, erg: bool,
		model_speed_kmh: float = -1.0, ages: Dictionary = {}, route: Dictionary = {}) -> void:
	time_sec.append(t)
	var p_ok: bool = sample != null and sample.has_power
	var c_ok: bool = sample != null and sample.has_cadence
	var s_ok: bool = sample != null and sample.has_speed
	power_w.append(sample.power_w if p_ok else 0)
	has_power.append(p_ok)
	cadence_rpm.append(sample.cadence_rpm if c_ok else 0)
	has_cadence.append(c_ok)
	var speed: float = 0.0
	var speed_ok: bool = false
	if model_speed_kmh >= 0.0:
		speed = model_speed_kmh
		speed_ok = true
	elif s_ok:
		speed = sample.speed_kmh
		speed_ok = true
	speed_kmh.append(speed)
	has_speed.append(speed_ok)
	heart_rate_bpm.append(hr_bpm if hr_bpm >= 0 else 0)
	has_heart_rate.append(hr_bpm >= 0)
	target_w.append(target)
	step_index.append(step)
	erg_enabled.append(erg)
	power_age_sec.append(0 if p_ok else int(ages.get("power", -1)))
	cadence_age_sec.append(0 if c_ok else int(ages.get("cadence", -1)))
	heart_rate_age_sec.append(0 if hr_bpm >= 0 else int(ages.get("heart_rate", -1)))
	var prev_distance: float = distance_m[distance_m.size() - 1] if distance_m.size() > 0 else 0.0
	var route_ok: bool = not route.is_empty()
	var dist: Variant = route.get("distance_m")
	if route_ok and (dist is float or dist is int):
		distance_m.append(float(dist))
	else:
		distance_m.append(prev_distance + (speed / 3.6 if speed_ok else 0.0))
	altitude_m.append(_num(route.get("altitude_m"), 0.0) if route_ok else 0.0)
	grade_pct.append(_num(route.get("grade_pct"), 0.0) if route_ok else 0.0)
	has_route.append(route_ok)


## Строка i словарём — для тестов, HUD и отладки.
func row(i: int) -> Dictionary:
	return {
		"time_sec": time_sec[i],
		"power_w": power_w[i], "has_power": has_power[i], "power_age_sec": power_age_sec[i],
		"cadence_rpm": cadence_rpm[i], "has_cadence": has_cadence[i], "cadence_age_sec": cadence_age_sec[i],
		"speed_kmh": speed_kmh[i], "has_speed": has_speed[i],
		"heart_rate_bpm": heart_rate_bpm[i], "has_heart_rate": has_heart_rate[i], "heart_rate_age_sec": heart_rate_age_sec[i],
		"target_w": target_w[i], "step_index": step_index[i], "erg_enabled": erg_enabled[i],
		"distance_m": distance_m[i],
		"altitude_m": altitude_m[i], "grade_pct": grade_pct[i], "has_route": has_route[i],
	}


func last_row() -> Dictionary:
	return row(size() - 1) if size() > 0 else {}


## Метки времени идут подряд с шагом 1 с.
func is_monotonic() -> bool:
	for i in range(1, time_sec.size()):
		if time_sec[i] != time_sec[i - 1] + 1:
			return false
	return true


func count_with_power() -> int:
	var n: int = 0
	for ok in has_power:
		if ok:
			n += 1
	return n


## Пройденное расстояние, м.
func total_distance_m() -> float:
	return distance_m[distance_m.size() - 1] if distance_m.size() > 0 else 0.0


## Есть ли в потоке позиция на трассе (свободная езда, REQ-FRD-07 крит. 4).
func has_route_data() -> bool:
	return has_route.has(true)


## Набор высоты, м (REQ-FRD-07 крит. 4): сумма положительных приращений `altitude_m`
## между соседними сэмплами с позицией на трассе. Без позиции — 0.
func total_ascent_m() -> float:
	var ascent: float = 0.0
	var prev: float = NAN
	for i in size():
		if not has_route[i]:
			continue
		var h: float = altitude_m[i]
		if not is_nan(prev) and h > prev:
			ascent += h - prev
		prev = h
	return ascent


## Устарели ли данные с данным возрастом (для HUD, REQ-WRK-08 крит. 4).
static func is_stale(age_sec: int) -> bool:
	return age_sec < 0 or age_sec >= STALE_AFTER_SEC


## Сериализация для хранилища заездов (LOC-01).
func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"speed_source": speed_source,
		"time_sec": Array(time_sec),
		"power_w": Array(power_w), "has_power": has_power.duplicate(),
		"cadence_rpm": Array(cadence_rpm), "has_cadence": has_cadence.duplicate(),
		"speed_kmh": Array(speed_kmh), "has_speed": has_speed.duplicate(),
		"heart_rate_bpm": Array(heart_rate_bpm), "has_heart_rate": has_heart_rate.duplicate(),
		"target_w": Array(target_w), "step_index": Array(step_index), "erg_enabled": erg_enabled.duplicate(),
		"power_age_sec": Array(power_age_sec), "cadence_age_sec": Array(cadence_age_sec),
		"heart_rate_age_sec": Array(heart_rate_age_sec),
		"distance_m": Array(distance_m),
		"altitude_m": Array(altitude_m), "grade_pct": Array(grade_pct), "has_route": has_route.duplicate(),
	}


## Восстановление из словаря (в т.ч. из JSON: числа могут быть float). Колонки
## разной длины обрезаются до самой короткой; отсутствующие — заполняются «нет данных».
static func from_dict(data: Dictionary) -> SampleStream:
	var s := SampleStream.new()
	s.speed_source = str(data.get("speed_source", ""))
	var n: int = _len(data.get("time_sec", []))
	for key in ["power_w", "cadence_rpm", "speed_kmh", "heart_rate_bpm", "target_w", "step_index"]:
		n = mini(n, _len(data.get(key, []))) if data.has(key) else n
	for i in n:
		s.time_sec.append(_int_at(data, "time_sec", i, i))
		s.power_w.append(_int_at(data, "power_w", i, 0))
		s.has_power.append(_bool_at(data, "has_power", i, false))
		s.cadence_rpm.append(_int_at(data, "cadence_rpm", i, 0))
		s.has_cadence.append(_bool_at(data, "has_cadence", i, false))
		s.speed_kmh.append(_float_at(data, "speed_kmh", i, 0.0))
		s.has_speed.append(_bool_at(data, "has_speed", i, false))
		s.heart_rate_bpm.append(_int_at(data, "heart_rate_bpm", i, 0))
		s.has_heart_rate.append(_bool_at(data, "has_heart_rate", i, false))
		s.target_w.append(_int_at(data, "target_w", i, 0))
		s.step_index.append(_int_at(data, "step_index", i, -1))
		s.erg_enabled.append(_bool_at(data, "erg_enabled", i, true))
		s.power_age_sec.append(_int_at(data, "power_age_sec", i, 0 if s.has_power[i] else -1))
		s.cadence_age_sec.append(_int_at(data, "cadence_age_sec", i, 0 if s.has_cadence[i] else -1))
		s.heart_rate_age_sec.append(_int_at(data, "heart_rate_age_sec", i, 0 if s.has_heart_rate[i] else -1))
		var prev: float = s.distance_m[i - 1] if i > 0 else 0.0
		s.distance_m.append(_float_at(data, "distance_m", i, prev + (s.speed_kmh[i] / 3.6 if s.has_speed[i] else 0.0)))
		# Позиция на трассе — только у свободной езды; старые потоки без колонок → «нет».
		s.altitude_m.append(_float_at(data, "altitude_m", i, 0.0))
		s.grade_pct.append(_float_at(data, "grade_pct", i, 0.0))
		s.has_route.append(_bool_at(data, "has_route", i, false))
	return s


static func _num(v: Variant, default: float) -> float:
	return float(v) if v is float or v is int else default


static func _len(v: Variant) -> int:
	return (v as Array).size() if v is Array else 0


static func _int_at(data: Dictionary, key: String, i: int, default: int) -> int:
	var arr: Variant = data.get(key, null)
	if arr is Array and i < (arr as Array).size():
		var v: Variant = arr[i]
		if v is int or v is float:
			return int(v)
	return default


static func _float_at(data: Dictionary, key: String, i: int, default: float) -> float:
	var arr: Variant = data.get(key, null)
	if arr is Array and i < (arr as Array).size():
		var v: Variant = arr[i]
		if v is int or v is float:
			return float(v)
	return default


static func _bool_at(data: Dictionary, key: String, i: int, default: bool) -> bool:
	var arr: Variant = data.get(key, null)
	if arr is Array and i < (arr as Array).size():
		var v: Variant = arr[i]
		if v is bool:
			return v
		if v is int or v is float:
			return float(v) != 0.0
	return default
