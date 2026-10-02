class_name Profile
extends RefCounted
## Профиль пользователя (REQ-PRF-01, REQ-PRF-02): FTP, вес, максимальный пульс,
## зоны, настройки тренировки по умолчанию.
##
## Диапазоны (REQ-PRF-02 крит. 1, «Открытые решения» п. 5): FTP 50–600 Вт,
## вес 20.0–250.0 кг с шагом 0.1, имя 1–40 символов после обрезки пробелов,
## `max_hr` 100–220 уд/мин или 0 = не задан (тогда зоны пульса недоступны,
## REQ-PRF-02 крит. 4).
##
## Зоны: `power_zones == null` означает «7 зон Coggan от текущего FTP»,
## `hr_zones == null` — «5 зон 60/70/80/90 % от `max_hr`» (если он задан).
## Пользовательские зоны в % хранят только границы: FTP и max_hr всегда берутся
## из профиля, поэтому смена FTP автоматически сдвигает границы в ваттах.
## Зоны пульса могут быть абсолютными (`HrZones.custom_bpm`, уд/мин — так они
## приходят из Intervals.icu): тогда они доступны и без `max_hr` (REQ-PRF-02 крит. 3, 4).
##
## `validate()` возвращает коды ошибок — стабильные строки вида `"ftp_out_of_range"`,
## пригодные как ключи переводов (без русских литералов в домене).

const MIN_FTP_W: int = 50
const MAX_FTP_W: int = 600
const MIN_WEIGHT_KG: float = 20.0
const MAX_WEIGHT_KG: float = 250.0
const WEIGHT_STEP_KG: float = 0.1
const MIN_MAX_HR: int = 100
const MAX_MAX_HR: int = 220
const MAX_HR_NOT_SET: int = 0
const MIN_NAME_LENGTH: int = 1
const MAX_NAME_LENGTH: int = 40
## Множитель интенсивности, % (REQ-WRK-07, «Открытые решения» п. 8).
const MIN_INTENSITY_PCT: int = 50
const MAX_INTENSITY_PCT: int = 150
## Уровень сопротивления вне ERG, % (REQ-WRK-04, «Открытые решения» п. 9).
const MIN_RESISTANCE_PCT: int = 0
const MAX_RESISTANCE_PCT: int = 100

## Коды ошибок валидации.
const ERR_ID_EMPTY: String = "id_empty"
const ERR_NAME_EMPTY: String = "name_empty"
const ERR_NAME_TOO_LONG: String = "name_too_long"
const ERR_FTP_OUT_OF_RANGE: String = "ftp_out_of_range"
const ERR_WEIGHT_OUT_OF_RANGE: String = "weight_out_of_range"
const ERR_MAX_HR_OUT_OF_RANGE: String = "max_hr_out_of_range"
const ERR_INTENSITY_OUT_OF_RANGE: String = "intensity_out_of_range"
const ERR_RESISTANCE_OUT_OF_RANGE: String = "resistance_out_of_range"
const ERR_POWER_ZONES_INVALID: String = "power_zones_invalid"
const ERR_HR_ZONES_INVALID: String = "hr_zones_invalid"

## Версия схемы `to_dict()`.
const SCHEMA_VERSION: int = 1

## Уникальный идентификатор (UUID v4 в текстовом виде). Генерируется один раз.
var id: String = ""
var name: String = ""
var ftp_w: int = 200
var weight_kg: float = 75.0
## Максимальный пульс, уд/мин; 0 — не задан.
var max_hr: int = MAX_HR_NOT_SET
## Пользовательские зоны мощности; null — Coggan от `ftp_w`.
var power_zones: PowerZones = null
## Пользовательские зоны пульса; null — 5 зон от `max_hr`.
var hr_zones: HrZones = null
## Множитель интенсивности по умолчанию, %.
var intensity_default: int = 100
## Уровень сопротивления вне ERG по умолчанию, %.
var resistance_level_default: int = 50
## Время создания, unix-секунды.
var created_at: int = 0


## Новый профиль с именем, свежим id и временем создания.
static func create(profile_name: String) -> Profile:
	var p := Profile.new()
	p.id = generate_id()
	p.name = profile_name.strip_edges()
	p.created_at = int(Time.get_unix_time_from_system())
	return p


## UUID v4 в виде `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`.
static func generate_id() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	bytes[8] = (bytes[8] & 0x3F) | 0x80
	var hex: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


## Имя для сравнения уникальности: без краевых пробелов, без учёта регистра.
static func normalized_name(raw: String) -> String:
	return raw.strip_edges().to_lower()


func has_max_hr() -> bool:
	return max_hr > MAX_HR_NOT_SET


## Доступны ли зоны пульса (REQ-PRF-02 крит. 4): задан `max_hr` или переопределены абсолютные границы.
func has_hr_zones() -> bool:
	return has_max_hr() or _has_absolute_hr_zones()


func _has_absolute_hr_zones() -> bool:
	return hr_zones != null and hr_zones.is_absolute()


## Действующие зоны мощности: пользовательские границы или Coggan, всегда от `ftp_w`.
func effective_power_zones() -> PowerZones:
	if power_zones == null:
		return PowerZones.coggan(ftp_w)
	return PowerZones.custom(ftp_w, power_zones.boundaries_pct)


## Действующие зоны пульса или null, если они недоступны (нет `max_hr` и нет абсолютных границ).
func effective_hr_zones() -> HrZones:
	if _has_absolute_hr_zones():
		return HrZones.custom_bpm(hr_zones.boundaries_bpm)
	if not has_max_hr():
		return null
	if hr_zones == null:
		return HrZones.five_zone(max_hr)
	return HrZones.custom(max_hr, hr_zones.boundaries_pct)


## Зона мощности 1..7 (0 при некорректном FTP).
func power_zone_of(power_w: int) -> int:
	return effective_power_zones().zone_of(power_w)


## Зона пульса 1..5; 0 — «нет зоны» (max_hr не задан или bpm ≤ 0).
func hr_zone_of(bpm: int) -> int:
	var zones := effective_hr_zones()
	if zones == null:
		return 0
	return zones.zone_of(bpm)


## Привести поля к хранимому виду: имя без краевых пробелов, вес с шагом 0.1
## (19.96 → 20.0). Вызывается репозиторием перед валидацией и записью, чтобы
## введённое и сохранённое совпадали.
func normalize() -> void:
	name = name.strip_edges()
	weight_kg = snappedf(weight_kg, WEIGHT_STEP_KG)


## Коды ошибок; пустой массив — профиль корректен. Вес проверяется с шагом 0.1.
func validate() -> Array[String]:
	var errors: Array[String] = []
	if id.is_empty():
		errors.append(ERR_ID_EMPTY)
	var trimmed: String = name.strip_edges()
	if trimmed.length() < MIN_NAME_LENGTH:
		errors.append(ERR_NAME_EMPTY)
	elif trimmed.length() > MAX_NAME_LENGTH:
		errors.append(ERR_NAME_TOO_LONG)
	if ftp_w < MIN_FTP_W or ftp_w > MAX_FTP_W:
		errors.append(ERR_FTP_OUT_OF_RANGE)
	var weight_snapped: float = snappedf(weight_kg, WEIGHT_STEP_KG)
	if weight_snapped < MIN_WEIGHT_KG - 1e-9 or weight_snapped > MAX_WEIGHT_KG + 1e-9:
		errors.append(ERR_WEIGHT_OUT_OF_RANGE)
	if max_hr != MAX_HR_NOT_SET and (max_hr < MIN_MAX_HR or max_hr > MAX_MAX_HR):
		errors.append(ERR_MAX_HR_OUT_OF_RANGE)
	if intensity_default < MIN_INTENSITY_PCT or intensity_default > MAX_INTENSITY_PCT:
		errors.append(ERR_INTENSITY_OUT_OF_RANGE)
	if resistance_level_default < MIN_RESISTANCE_PCT or resistance_level_default > MAX_RESISTANCE_PCT:
		errors.append(ERR_RESISTANCE_OUT_OF_RANGE)
	if power_zones != null and not _boundaries_valid(power_zones.boundaries_pct):
		errors.append(ERR_POWER_ZONES_INVALID)
	if hr_zones != null:
		var hr_ok: bool = _bpm_boundaries_valid(hr_zones.boundaries_bpm) if hr_zones.is_absolute() \
				else _boundaries_valid(hr_zones.boundaries_pct)
		if not hr_ok:
			errors.append(ERR_HR_ZONES_INVALID)
	return errors


func is_valid() -> bool:
	return validate().is_empty()


## Сериализация для JSON. Вес округляется до 0.1 кг.
func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"id": id,
		"name": name,
		"ftp_w": ftp_w,
		"weight_kg": snappedf(weight_kg, WEIGHT_STEP_KG),
		"max_hr": max_hr,
		"power_zone_bounds_pct": _bounds_to_array(power_zones.boundaries_pct) if power_zones != null else null,
		"hr_zone_bounds_pct": _bounds_to_array(hr_zones.boundaries_pct) if hr_zones != null and not hr_zones.is_absolute() else null,
		"hr_zone_bounds_bpm": Array(hr_zones.boundaries_bpm) if _has_absolute_hr_zones() else null,
		"intensity_default": intensity_default,
		"resistance_level_default": resistance_level_default,
		"created_at": created_at,
	}


## Восстановление из словаря (в т.ч. из JSON, где числа приходят как float).
## Отсутствующие поля (или null) получают значения по умолчанию; значения
## неподходящего типа приводятся к 0/"" — так `validate()` их отклонит, а не
## подменит умолчанием. Не падает ни на каких входных типах.
static func from_dict(data: Dictionary) -> Profile:
	var p := Profile.new()
	p.id = _to_text(data.get("id", ""))
	p.name = _to_text(data.get("name", ""))
	p.ftp_w = _to_int(data.get("ftp_w", null), p.ftp_w)
	p.weight_kg = snappedf(_to_float(data.get("weight_kg", null), p.weight_kg), WEIGHT_STEP_KG)
	p.max_hr = _to_int(data.get("max_hr", null), MAX_HR_NOT_SET)
	p.intensity_default = _to_int(data.get("intensity_default", null), p.intensity_default)
	p.resistance_level_default = _to_int(data.get("resistance_level_default", null), p.resistance_level_default)
	p.created_at = _to_int(data.get("created_at", null), 0)
	var pz: Variant = data.get("power_zone_bounds_pct", null)
	if pz is Array:
		p.power_zones = PowerZones.custom(p.ftp_w, _array_to_bounds(pz))
	var hz_bpm: Variant = data.get("hr_zone_bounds_bpm", null)
	var hz: Variant = data.get("hr_zone_bounds_pct", null)
	if hz_bpm is Array and not (hz_bpm as Array).is_empty():
		p.hr_zones = HrZones.custom_bpm(_array_to_int_bounds(hz_bpm))
	elif hz is Array:
		p.hr_zones = HrZones.custom(p.max_hr, _array_to_bounds(hz))
	return p


## Глубокая копия (для редактирования с отменой).
func duplicate_profile() -> Profile:
	return Profile.from_dict(to_dict())


static func _boundaries_valid(bounds: Array[float]) -> bool:
	if bounds.is_empty():
		return false
	for i in bounds.size():
		if bounds[i] <= 0.0:
			return false
		if i > 0 and bounds[i] <= bounds[i - 1]:
			return false
	return true


static func _bpm_boundaries_valid(bounds: Array[int]) -> bool:
	if bounds.is_empty():
		return false
	for i in bounds.size():
		if bounds[i] <= 0:
			return false
		if i > 0 and bounds[i] <= bounds[i - 1]:
			return false
	return true


## null → default; числа/bool → int; строка → число или 0, если не разбирается; иное → 0.
static func _to_int(value: Variant, default: int) -> int:
	match typeof(value):
		TYPE_NIL:
			return default
		TYPE_INT:
			return value
		TYPE_FLOAT:
			return int(value)
		TYPE_BOOL:
			return 1 if value else 0
		TYPE_STRING, TYPE_STRING_NAME:
			var s: String = str(value).strip_edges()
			if s.is_valid_int():
				return s.to_int()
			if s.is_valid_float():
				return int(s.to_float())
			return 0
	return 0


static func _to_float(value: Variant, default: float) -> float:
	match typeof(value):
		TYPE_NIL:
			return default
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		TYPE_BOOL:
			return 1.0 if value else 0.0
		TYPE_STRING, TYPE_STRING_NAME:
			var s: String = str(value).strip_edges()
			return s.to_float() if s.is_valid_float() else 0.0
	return 0.0


static func _to_text(value: Variant) -> String:
	return "" if value == null else str(value)


static func _bounds_to_array(bounds: Array[float]) -> Array:
	var out: Array = []
	for b in bounds:
		out.append(b)
	return out


static func _array_to_bounds(values: Array) -> Array[float]:
	var out: Array[float] = []
	for v in values:
		out.append(_to_float(v, 0.0))
	return out


static func _array_to_int_bounds(values: Array) -> Array[int]:
	var out: Array[int] = []
	for v in values:
		out.append(_to_int(v, 0))
	return out
