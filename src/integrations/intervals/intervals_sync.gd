class_name IntervalsSync
extends RefCounted
## Применение данных атлета Intervals.icu к профилю (REQ-INT-06 крит. 1–5, 7).
##
## `parse_athlete(json)` нормализует ответ `GET /api/v1/athlete/{id}`: берётся
## запись `sportSettings[]`, у которой `types` содержит велосипедный тип
## (`IntervalsIcuClient.BIKE_TYPES`), иначе первая. Поля: `ftp`, `indoor_ftp`,
## `lthr`, `max_hr`, `power_zones`, `hr_zones` (+ `*_zone_names`).
##
## Зоны мощности (крит. 2, решение В-5). Intervals.icu отдаёт список верхних границ
## зон; последняя — «открытая» (например 999 % или ≥ 10 × FTP) и отбрасывается, если
## число значений равно числу имён зон или значение явно открытое. Единицы:
## `units` = "percent" | "watts" | "auto"; в "auto" значения считаются % FTP
## (формат документации), а если какое-то значение (кроме открытого) > 250 — ваттами. Ватты переводятся
## в % FTP относительно FTP того же ответа с округлением до целого процента.
## Итог — 2–9 зон (`PowerZones.custom`); 0 зон, 1 зона (без границ — модель
## `Profile` не допускает пустых границ) или > 9 зон → предупреждение, зоны профиля
## не меняются.
##
## Зоны пульса (крит. 3). `hr_zones` — верхние границы в уд/мин (последняя = max HR,
## отбрасывается). `HrZones.custom_bpm` принимает нижние границы зон 2..N
## («значение, равное границе, — верхняя зона»), поэтому к каждой верхней границе
## прибавляется 1. Если зон пульса нет — в профиль пишется `max_hr`, зоны считаются
## от него (PRF-02.3).
##
## Локальное переопределение (крит. 4, 5): при `override_local` профиль не меняется;
## иначе FTP и зоны обновляются, `ftp_source`/`zones_source` = `intervals:<дата>`.
## Нет FTP в ответе → локальное значение остаётся, предупреждение `ftp_missing` (крит. 7).

const SOURCE_LOCAL: String = Profile.SOURCE_LOCAL
const SOURCE_INTERVALS_PREFIX: String = Profile.SOURCE_INTERVALS_PREFIX
const MAX_ZONES: int = 9
const MIN_ZONES: int = 2
## Порог авто-распознавания: граница (кроме открытой) > 250 считается ваттами —
## процентные границы Coggan не превышают 150 %, а ваттовые при FTP ≥ 170 дают ≥ 255.
const AUTO_WATTS_THRESHOLD: float = 250.0
## Открытая верхняя граница в процентах (999 в Intervals.icu).
const OPEN_PERCENT_BOUND: float = 300.0
## Открытая верхняя граница в ваттах — кратно FTP.
const OPEN_WATTS_FACTOR: float = 10.0

const WARN_LOCAL_OVERRIDE: String = "local_override"
const WARN_FTP_MISSING: String = "ftp_missing"
const WARN_FTP_OUT_OF_RANGE: String = "ftp_out_of_range"
const WARN_POWER_ZONES_MISSING: String = "power_zones_missing"
const WARN_POWER_ZONES_COUNT: String = "power_zones_count"
const WARN_POWER_ZONES_INVALID: String = "power_zones_invalid"
const WARN_HR_ZONES_MISSING: String = "hr_zones_missing"
const WARN_HR_ZONES_INVALID: String = "hr_zones_invalid"
const WARN_MAX_HR_MISSING: String = "max_hr_missing"
const WARN_NO_BIKE_SETTINGS: String = "no_bike_settings"


## Нормализованный атлет: `{id, name, weight_kg, ftp, indoor_ftp, lthr, max_hr,
## power_zones_pct: Array[float], power_zone_count, hr_zones_bpm: Array[int],
## hr_zone_count, warnings: Array[String]}`. Отсутствующие числа — 0, списки пустые.
static func parse_athlete(json: Dictionary, units: String = "auto") -> Dictionary:
	var warnings: Array[String] = []
	var settings := bike_sport_settings(json)
	if not has_bike_sport_settings(json):
		warnings.append(WARN_NO_BIKE_SETTINGS)
	var ftp := _to_int(settings.get("ftp"))
	var indoor_ftp := _to_int(settings.get("indoor_ftp"))
	var max_hr := _to_int(settings.get("max_hr"))
	var power_pct: Array[float] = []
	var raw_power: Variant = settings.get("power_zones")
	if raw_power is Array and not (raw_power as Array).is_empty():
		var names: Variant = settings.get("power_zone_names")
		power_pct = power_zones_to_pct(raw_power, ftp, units, names if names is Array else [])
		if power_pct.is_empty():
			warnings.append(WARN_POWER_ZONES_INVALID)
	else:
		warnings.append(WARN_POWER_ZONES_MISSING)
	var hr_bpm: Array[int] = []
	var raw_hr: Variant = settings.get("hr_zones")
	if raw_hr is Array and not (raw_hr as Array).is_empty():
		var hr_names: Variant = settings.get("hr_zone_names")
		hr_bpm = hr_zones_to_bpm(raw_hr, max_hr, hr_names if hr_names is Array else [])
		if hr_bpm.is_empty():
			warnings.append(WARN_HR_ZONES_INVALID)
	else:
		warnings.append(WARN_HR_ZONES_MISSING)
	if ftp <= 0:
		warnings.append(WARN_FTP_MISSING)
	var name := str(json.get("name", "")).strip_edges()
	if name.is_empty():
		name = ("%s %s" % [str(json.get("firstname", "")), str(json.get("lastname", ""))]).strip_edges()
	return {
		"id": str(json.get("id", "")),
		"name": name,
		"weight_kg": _to_float(json.get("icu_weight", json.get("weight"))),
		"ftp": ftp,
		"indoor_ftp": indoor_ftp,
		"lthr": _to_int(settings.get("lthr")),
		"max_hr": max_hr,
		"power_zones_pct": power_pct,
		"power_zones_present": raw_power is Array and not (raw_power as Array).is_empty(),
		"power_zone_count": power_pct.size() + 1 if not power_pct.is_empty() else 0,
		"hr_zones_bpm": hr_bpm,
		"hr_zone_count": hr_bpm.size() + 1 if not hr_bpm.is_empty() else 0,
		"warnings": warnings,
	}


## Есть ли в `sportSettings` запись с велосипедным типом.
static func has_bike_sport_settings(json: Dictionary) -> bool:
	var list: Variant = json.get("sportSettings", json.get("sport_settings"))
	if not (list is Array):
		return false
	for item in list:
		if item is Dictionary and (item as Dictionary).get("types") is Array:
			for t in (item as Dictionary)["types"]:
				if IntervalsIcuClient.BIKE_TYPES.has(str(t)):
					return true
	return false


## Запись `sportSettings` для велосипеда (или первая, или пустой словарь).
static func bike_sport_settings(json: Dictionary) -> Dictionary:
	var list: Variant = json.get("sportSettings", json.get("sport_settings"))
	if not (list is Array):
		return {}
	var first: Dictionary = {}
	for item in list:
		if not (item is Dictionary):
			continue
		if first.is_empty():
			first = item
		var types: Variant = (item as Dictionary).get("types", [])
		if types is Array:
			for t in types:
				if IntervalsIcuClient.BIKE_TYPES.has(str(t)):
					return item
	return first


## Верхние границы зон мощности → границы `PowerZones.boundaries_pct` (строго возрастающие
## целые проценты FTP). Пустой массив — список непригоден (см. шапку).
static func power_zones_to_pct(values: Array, ftp: int, units: String = "auto", names: Array = []) -> Array[float]:
	var nums: Array[float] = []
	for v in values:
		if not (v is float or v is int):
			return []
		nums.append(float(v))
	if nums.is_empty():
		return []
	var in_watts := units == "watts"
	if units == "auto":
		for n in nums.slice(0, nums.size() - 1):
			if n > AUTO_WATTS_THRESHOLD:
				in_watts = true
				break
		if nums.size() == 1 and nums[0] > AUTO_WATTS_THRESHOLD:
			in_watts = true
	var last := nums[nums.size() - 1]
	var open_top := (names.size() == nums.size()) \
			or (in_watts and ftp > 0 and last >= OPEN_WATTS_FACTOR * float(ftp)) \
			or (not in_watts and last >= OPEN_PERCENT_BOUND)
	if open_top:
		nums.remove_at(nums.size() - 1)
	if in_watts:
		if ftp <= 0:
			return []
		var pct: Array[float] = []
		for w in nums:
			pct.append(float(roundi(w / float(ftp) * 100.0)))
		nums = pct
	else:
		for i in nums.size():
			nums[i] = float(roundi(nums[i]))
	for i in nums.size():
		if nums[i] <= 0.0 or (i > 0 and nums[i] <= nums[i - 1]):
			return []
	return nums


## Верхние границы зон пульса (уд/мин) → нижние границы зон 2..N для `HrZones.custom_bpm`.
static func hr_zones_to_bpm(values: Array, max_hr: int, names: Array = []) -> Array[int]:
	var nums: Array[int] = []
	for v in values:
		if not (v is float or v is int):
			return []
		nums.append(roundi(float(v)))
	if nums.is_empty():
		return []
	var last := nums[nums.size() - 1]
	var open_top := names.size() == nums.size() or (max_hr > 0 and last >= max_hr)
	if open_top:
		nums.remove_at(nums.size() - 1)
	var out: Array[int] = []
	for i in nums.size():
		var lower := nums[i] + 1
		if lower <= 1 or (i > 0 and lower <= out[i - 1]):
			return []
		out.append(lower)
	return out


## Применить атлета к профилю. Возвращает коды предупреждений (пусто — всё применено).
## `override_local == true` → профиль не меняется (`local_override`), REQ-INT-06 крит. 4.
## `synced_on` — дата синхронизации для `ftp_source`/`zones_source` (по умолчанию сегодня).
static func apply_athlete_to_profile(profile: Profile, athlete: Dictionary, override_local: bool,
		synced_on: String = "") -> Array[String]:
	var warnings: Array[String] = []
	if override_local:
		warnings.append(WARN_LOCAL_OVERRIDE)
		return warnings
	var date := synced_on if not synced_on.is_empty() else IntervalsIcuClient.local_date()
	var source := "%s:%s" % [SOURCE_INTERVALS_PREFIX, date]
	var athlete_id := str(athlete.get("id", ""))
	if not athlete_id.is_empty():
		profile.intervals_athlete_id = athlete_id

	var ftp := _to_int(athlete.get("ftp"))
	if ftp <= 0:
		warnings.append(WARN_FTP_MISSING)
	elif ftp < Profile.MIN_FTP_W or ftp > Profile.MAX_FTP_W:
		warnings.append(WARN_FTP_OUT_OF_RANGE)
	else:
		profile.ftp_w = ftp
		profile.ftp_source = source

	var zones_changed := false
	var pct: Variant = athlete.get("power_zones_pct", [])
	var bounds: Array[float] = []
	if pct is Array:
		for v in pct:
			bounds.append(float(v))
	if bounds.is_empty():
		var raw: Variant = athlete.get("power_zones")
		var present := (raw is Array and not (raw as Array).is_empty()) or bool(athlete.get("power_zones_present", false))
		warnings.append(WARN_POWER_ZONES_COUNT if present else WARN_POWER_ZONES_MISSING)
	elif bounds.size() + 1 > MAX_ZONES or bounds.size() + 1 < MIN_ZONES:
		warnings.append(WARN_POWER_ZONES_COUNT)
	else:
		profile.power_zones = PowerZones.custom(profile.ftp_w, bounds)
		zones_changed = true

	var hr_raw: Variant = athlete.get("hr_zones_bpm", [])
	var hr_bounds: Array[int] = []
	if hr_raw is Array:
		for v in hr_raw:
			hr_bounds.append(int(v))
	var max_hr := _to_int(athlete.get("max_hr"))
	if not hr_bounds.is_empty() and hr_bounds.size() + 1 <= MAX_ZONES:
		profile.hr_zones = HrZones.custom_bpm(hr_bounds)
		if max_hr >= Profile.MIN_MAX_HR and max_hr <= Profile.MAX_MAX_HR:
			profile.max_hr = max_hr
		zones_changed = true
	elif max_hr >= Profile.MIN_MAX_HR and max_hr <= Profile.MAX_MAX_HR:
		profile.max_hr = max_hr
		profile.hr_zones = null
		warnings.append(WARN_HR_ZONES_MISSING)
		zones_changed = true
	else:
		warnings.append(WARN_HR_ZONES_MISSING)
		if max_hr <= 0:
			warnings.append(WARN_MAX_HR_MISSING)
	if zones_changed:
		profile.zones_source = source
	return warnings


## Удобная обёртка: флаг переопределения берётся из профиля.
static func sync_profile(profile: Profile, athlete: Dictionary, synced_on: String = "") -> Array[String]:
	return apply_athlete_to_profile(profile, athlete, profile.intervals_override_local, synced_on)


static func _to_int(v: Variant) -> int:
	if v is int:
		return v
	if v is float:
		return roundi(v)
	if v is String and str(v).is_valid_float():
		return roundi(str(v).to_float())
	return 0


static func _to_float(v: Variant) -> float:
	if v is int or v is float:
		return float(v)
	if v is String and str(v).is_valid_float():
		return str(v).to_float()
	return 0.0
