class_name RideSummary
extends RefCounted
## Сводка заезда (REQ-LOC-04) и строка списка истории (REQ-LOC-02 крит. 1).
##
## Метрики считаются `compute()` по потоку `SampleStream` и зонам профиля
## на момент заезда (REQ-LOC-04 крит. 5):
## - средняя мощность — среднее по сэмплам с данными, нули учитываются (крит. 1);
## - NP по Coggan (строгая форма TrainingPeaks/GoldenCheetah): только полные
##   30-с окна скользящего среднего → 4-я степень → среднее → корень 4-й степени
##   (крит. 2); для потоков короче 30 с окно одно — весь поток (NP = средней).
##   Итог не опускается ниже средней: краевой эффект окон на коротких заездах
##   не должен нарушать свойство NP ≥ средняя (крит. 2);
## - работа = Σ P · 1 с / 1000 кДж (крит. 3);
## - средний пульс/каденс — по сэмплам с данными, каденс 0 учитывается (крит. 4);
## - время в зонах — секунды по зонам профиля; сумма = число сэмплов с данными (крит. 5).
##
## «Нет данных» для средних и максимумов — `NO_DATA` (-1), а не 0: заезд без
## пульса отображается как «—» (крит. 6), в FIT уходит invalid-значение (LOC-05 крит. 3).
##
## Поля «шапки» (`ride_id`, `started_at_unix`, `name`, статус Strava, флаги)
## заполняет хранилище из `Ride` — чтобы `RideRepository.list()` отдавал всё
## нужное списку без чтения потоков.

const NO_DATA: int = -1
## Окно скользящего среднего для NP, с.
const NP_WINDOW_SEC: int = 30
const SCHEMA_VERSION: int = 1

# --- Шапка (из Ride) ---
var ride_id: String = ""
var profile_id: String = ""
var started_at_unix: int = 0
var name: String = ""
var workout_source: String = ""
var strava_status: String = "none"
var strava_activity_id: String = ""
var stopped_early: bool = false
var in_progress: bool = false
var recovered: bool = false

# --- Метрики ---
## Активное время, с (число сэмплов).
var duration_sec: int = 0
var distance_m: float = 0.0
var avg_power_w: int = NO_DATA
var normalized_power_w: int = NO_DATA
var max_power_w: int = NO_DATA
var avg_hr: int = NO_DATA
var max_hr: int = NO_DATA
var avg_cadence: int = NO_DATA
var max_cadence: int = NO_DATA
var work_kj: float = 0.0
## Секунды в зонах мощности 1..N (индекс 0 — Z1).
var time_in_power_zones := PackedInt32Array()
## Секунды в зонах пульса 1..N; пусто, если зоны пульса недоступны.
var time_in_hr_zones := PackedInt32Array()
var power_sample_count: int = 0
var hr_sample_count: int = 0
var cadence_sample_count: int = 0


## Сводка по потоку. `hr_zones` может быть null (max_hr не задан, REQ-LOC-04 крит. 6).
static func compute(samples: SampleStream, _ftp_w: int, zones: PowerZones, hr_zones: HrZones) -> RideSummary:
	var s := RideSummary.new()
	var n: int = samples.size()
	s.duration_sec = n
	s.distance_m = samples.total_distance_m()
	if zones != null:
		s.time_in_power_zones.resize(zones.zone_count())
		s.time_in_power_zones.fill(0)
	if hr_zones != null:
		s.time_in_hr_zones.resize(hr_zones.zone_count())
		s.time_in_hr_zones.fill(0)

	var power_sum: int = 0
	var hr_sum: int = 0
	var cadence_sum: int = 0
	var max_p: int = NO_DATA
	var max_h: int = NO_DATA
	var max_c: int = NO_DATA
	for i in n:
		if samples.has_power[i]:
			var p: int = samples.power_w[i]
			s.power_sample_count += 1
			power_sum += p
			max_p = maxi(max_p, p)
			if zones != null:
				var z: int = zones.zone_of(p)
				if z >= 1 and z <= s.time_in_power_zones.size():
					s.time_in_power_zones[z - 1] += 1
		if samples.has_heart_rate[i]:
			var h: int = samples.heart_rate_bpm[i]
			s.hr_sample_count += 1
			hr_sum += h
			max_h = maxi(max_h, h)
			if hr_zones != null:
				var hz: int = hr_zones.zone_of(h)
				if hz >= 1 and hz <= s.time_in_hr_zones.size():
					s.time_in_hr_zones[hz - 1] += 1
		if samples.has_cadence[i]:
			var c: int = samples.cadence_rpm[i]
			s.cadence_sample_count += 1
			cadence_sum += c
			max_c = maxi(max_c, c)

	s.work_kj = float(power_sum) / 1000.0
	if s.power_sample_count > 0:
		s.avg_power_w = roundi(float(power_sum) / float(s.power_sample_count))
		s.max_power_w = max_p
		s.normalized_power_w = maxi(normalized_power(samples), s.avg_power_w)
	if s.hr_sample_count > 0:
		s.avg_hr = roundi(float(hr_sum) / float(s.hr_sample_count))
		s.max_hr = max_h
	if s.cadence_sample_count > 0:
		s.avg_cadence = roundi(float(cadence_sum) / float(s.cadence_sample_count))
		s.max_cadence = max_c
	return s


## Нормализованная мощность по Coggan (REQ-LOC-04 крит. 2) без клампа к средней:
## только полные 30-с окна; поток короче 30 с — одно окно на весь поток.
## Сэмплы без данных мощности в окно не входят (окно — по сэмплам с данными).
## `NO_DATA`, если данных нет.
static func normalized_power(samples: SampleStream) -> int:
	var values := PackedInt32Array()
	for i in samples.size():
		if samples.has_power[i]:
			values.append(samples.power_w[i])
	var n: int = values.size()
	if n == 0:
		return NO_DATA
	var window: int = mini(n, NP_WINDOW_SEC)
	var window_sum: float = 0.0
	var fourth_sum: float = 0.0
	var windows: int = 0
	for i in n:
		window_sum += float(values[i])
		if i >= window:
			window_sum -= float(values[i - window])
		if i >= window - 1:
			var avg: float = window_sum / float(window)
			fourth_sum += avg * avg * avg * avg
			windows += 1
	return roundi(pow(fourth_sum / float(windows), 0.25))


func has_power() -> bool:
	return power_sample_count > 0


func has_heart_rate() -> bool:
	return hr_sample_count > 0


func has_cadence() -> bool:
	return cadence_sample_count > 0


## Сумма секунд по зонам мощности (должна равняться `power_sample_count`).
func total_power_zone_sec() -> int:
	var total: int = 0
	for v in time_in_power_zones:
		total += v
	return total


func total_hr_zone_sec() -> int:
	var total: int = 0
	for v in time_in_hr_zones:
		total += v
	return total


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"ride_id": ride_id,
		"profile_id": profile_id,
		"started_at_unix": started_at_unix,
		"name": name,
		"workout_source": workout_source,
		"strava_status": strava_status,
		"strava_activity_id": strava_activity_id,
		"stopped_early": stopped_early,
		"in_progress": in_progress,
		"recovered": recovered,
		"duration_sec": duration_sec,
		"distance_m": distance_m,
		"avg_power_w": avg_power_w,
		"normalized_power_w": normalized_power_w,
		"max_power_w": max_power_w,
		"avg_hr": avg_hr,
		"max_hr": max_hr,
		"avg_cadence": avg_cadence,
		"max_cadence": max_cadence,
		"work_kj": work_kj,
		"time_in_power_zones": Array(time_in_power_zones),
		"time_in_hr_zones": Array(time_in_hr_zones),
		"power_sample_count": power_sample_count,
		"hr_sample_count": hr_sample_count,
		"cadence_sample_count": cadence_sample_count,
	}


## Восстановление из словаря (числа из JSON приходят как float). Не падает на мусоре.
static func from_dict(data: Dictionary) -> RideSummary:
	var s := RideSummary.new()
	s.ride_id = str(data.get("ride_id", ""))
	s.profile_id = str(data.get("profile_id", ""))
	s.started_at_unix = _int(data.get("started_at_unix"), 0)
	s.name = str(data.get("name", ""))
	s.workout_source = str(data.get("workout_source", ""))
	s.strava_status = str(data.get("strava_status", "none"))
	s.strava_activity_id = str(data.get("strava_activity_id", ""))
	s.stopped_early = _bool(data.get("stopped_early"))
	s.in_progress = _bool(data.get("in_progress"))
	s.recovered = _bool(data.get("recovered"))
	s.duration_sec = _int(data.get("duration_sec"), 0)
	s.distance_m = _float(data.get("distance_m"), 0.0)
	s.avg_power_w = _int(data.get("avg_power_w"), NO_DATA)
	s.normalized_power_w = _int(data.get("normalized_power_w"), NO_DATA)
	s.max_power_w = _int(data.get("max_power_w"), NO_DATA)
	s.avg_hr = _int(data.get("avg_hr"), NO_DATA)
	s.max_hr = _int(data.get("max_hr"), NO_DATA)
	s.avg_cadence = _int(data.get("avg_cadence"), NO_DATA)
	s.max_cadence = _int(data.get("max_cadence"), NO_DATA)
	s.work_kj = _float(data.get("work_kj"), 0.0)
	s.time_in_power_zones = _int_array(data.get("time_in_power_zones"))
	s.time_in_hr_zones = _int_array(data.get("time_in_hr_zones"))
	s.power_sample_count = _int(data.get("power_sample_count"), 0)
	s.hr_sample_count = _int(data.get("hr_sample_count"), 0)
	s.cadence_sample_count = _int(data.get("cadence_sample_count"), 0)
	return s


static func _int(v: Variant, default: int) -> int:
	if v is int or v is float:
		return int(v)
	if v is bool:
		return 1 if v else 0
	return default


static func _float(v: Variant, default: float) -> float:
	if v is int or v is float:
		return float(v)
	return default


static func _bool(v: Variant) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return float(v) != 0.0
	return false


static func _int_array(v: Variant) -> PackedInt32Array:
	var out := PackedInt32Array()
	if v is Array:
		for item in v:
			out.append(_int(item, 0))
	return out
