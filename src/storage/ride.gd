class_name Ride
extends RefCounted
## Заезд — единица хранения истории (REQ-LOC-01, REQ-LOC-07, REQ-STR-05).
##
## Собирается из `WorkoutSession` и `Profile` (`from_session`): план в виде
## словаря `WorkoutSerializer.to_dict` (название и источник плана — LOC-01 крит. 1),
## метаданные сессии (`WorkoutSession.metadata()`: FTP, вес, множитель,
## `speed_source` по В-8, досрочность) плюс `max_hr` и границы зон профиля на
## момент заезда (чтобы сводка и восстановление считали зоны «как тогда»,
## LOC-04 крит. 5), журнал событий (пауза/пропуск/ERG/обрыв — LOC-01 крит. 4),
## поток сэмплов и сводка.
##
## Статус выгрузки в Strava (`upload`, REQ-STR-05 крит. 1): `strava_status` ∈
## `UPLOAD_STATUSES`, `strava_activity_id`, `last_error`, `attempts`.
##
## Флаги жизненного цикла в `metadata`: `in_progress` — заезд пишется
## (LOC-07), `recovered` — восстановлен после сбоя при следующем запуске.
##
## Тип заезда `metadata.ride_type` (REQ-FRD-07 крит. 3): `workout` (по плану) или
## `free_ride` (свободная езда). У свободной езды плана нет (`workout` пуст, `name` пуст,
## `workout_name` отсутствует), `speed_source = model`, в метаданных — `route_id`,
## `sim_steepness_start_pct` (крутизна SIM на старте, %), `total_distance_m` и
## `total_ascent_m` (набор — по сэмплам, `SampleStream.total_ascent_m`). Заезды,
## записанные до появления типа, читаются как `workout` (миграция не нужна).
##
## Источник станка `metadata.trainer_source` (T-160, Н-59): `ble` — реальное устройство,
## `emulator` — эмулятор станка; пишет сессия по `TrainerDevice.trainer_source()`.
## Это ось «откуда данные»; режим управления станком (будущий `trainer_mode`, T-152) — отдельное
## поле. Заезды без поля (записанные до T-160) и с неизвестным значением — `ble`: угадывать
## источник задним числом нельзя. Заезд на эмуляторе в Strava сам не выгружается (`StravaService`).
##
## Источник заезда (`from_session`) — `WorkoutSession` или сессия свободной езды с тем же
## контрактом записи: свойства `samples: SampleStream`, `events: Array[Dictionary]`,
## `started_at_unix: int` и метод `metadata() -> Dictionary` (для свободной езды — с
## `ride_type = free_ride`, `route_id`, `sim_steepness_start_pct`; см. `free_ride_metadata`).

const SCHEMA_VERSION: int = 1

const RIDE_TYPE_WORKOUT: String = "workout"
const RIDE_TYPE_FREE_RIDE: String = "free_ride"
const KEY_RIDE_TYPE: String = "ride_type"
const KEY_ROUTE_ID: String = "route_id"
const KEY_SIM_STEEPNESS_START_PCT: String = "sim_steepness_start_pct"
const KEY_TOTAL_DISTANCE_M: String = "total_distance_m"
const KEY_TOTAL_ASCENT_M: String = "total_ascent_m"
const KEY_TRAINER_SOURCE: String = WorkoutSession.META_TRAINER_SOURCE
const TRAINER_SOURCE_BLE: String = TrainerDevice.SOURCE_BLE
const TRAINER_SOURCE_EMULATOR: String = TrainerDevice.SOURCE_EMULATOR

const UPLOAD_NONE: String = "none"
const UPLOAD_QUEUED: String = "queued"
const UPLOAD_UPLOADING: String = "uploading"
const UPLOAD_DONE: String = "done"
const UPLOAD_FAILED: String = "failed"
const UPLOAD_DUPLICATE: String = "duplicate"
const UPLOAD_STATUSES: Array[String] = [UPLOAD_NONE, UPLOAD_QUEUED, UPLOAD_UPLOADING, UPLOAD_DONE, UPLOAD_FAILED, UPLOAD_DUPLICATE]

var id: String = ""
var profile_id: String = ""
var started_at_unix: int = 0
## Название заезда (по умолчанию — название плана; пусто → UI подставит «Тренировка <дата>»).
var name: String = ""
var description: String = ""
## План тренировки (`WorkoutSerializer.to_dict`).
var workout: Dictionary = {}
## Метаданные сессии и профиля на момент заезда.
var metadata: Dictionary = {}
## Журнал событий сессии `{type, at_sec, value, ...}`.
var events: Array[Dictionary] = []
var samples := SampleStream.new()
var summary := RideSummary.new()
var upload: Dictionary = default_upload()


static func default_upload() -> Dictionary:
	return {"strava_status": UPLOAD_NONE, "strava_activity_id": "", "last_error": "", "attempts": 0}


## Идентификатор заезда: unix-время старта + 8 случайных hex-символов
## (сортируется по времени как строка, уникален в рамках устройства).
static func generate_id(started_at: int = int(Time.get_unix_time_from_system())) -> String:
	var rand: PackedByteArray = Crypto.new().generate_random_bytes(4)
	return "%d-%s" % [started_at, rand.hex_encode()]


## Метаданные свободной езды для `metadata()` сессии (REQ-FRD-07 крит. 3): тип, трасса,
## крутизна SIM на старте (%), источник скорости — модель.
static func free_ride_metadata(route: String, sim_steepness_start_pct: float) -> Dictionary:
	return {
		KEY_RIDE_TYPE: RIDE_TYPE_FREE_RIDE,
		KEY_ROUTE_ID: route,
		KEY_SIM_STEEPNESS_START_PCT: sim_steepness_start_pct,
		"speed_source": SampleStream.SPEED_SOURCE_MODEL,
	}


## Заезд из текущего состояния сессии и профиля. `session.samples` используется
## по ссылке (один и тот же поток, который сессия продолжает наполнять).
## `session` — `WorkoutSession` или сессия свободной езды (контракт — в шапке класса).
static func from_session(session: Object, profile: Profile, ride_id: String = "") -> Ride:
	var r := Ride.new()
	var started: int = _int(session.get("started_at_unix"), 0)
	r.started_at_unix = started if started > 0 else int(Time.get_unix_time_from_system())
	r.id = ride_id if not ride_id.is_empty() else generate_id(r.started_at_unix)
	r.profile_id = profile.id if profile != null else ""
	if session is WorkoutSession:
		var ws := session as WorkoutSession
		r.workout = WorkoutSerializer.to_dict(ws.executor.workout)
		r.name = ws.executor.workout.name
		r.description = ws.executor.workout.description
	r.samples = session.get("samples") as SampleStream
	if r.samples == null:
		r.samples = SampleStream.new()
	r.events = _events_of(session)
	r.metadata = _session_metadata(session)
	r._normalize_ride_type()
	r.metadata["in_progress"] = false
	r.metadata["recovered"] = false
	if profile != null:
		r.metadata["max_hr"] = profile.max_hr
		r.metadata["power_zone_bounds_pct"] = _bounds_to_array(profile.effective_power_zones().boundaries_pct)
		var hz := profile.effective_hr_zones()
		if hz == null:
			r.metadata["hr_zone_bounds_pct"] = null
			r.metadata["hr_zone_bounds_bpm"] = null
		elif hz.is_absolute():
			r.metadata["hr_zone_bounds_pct"] = null
			r.metadata["hr_zone_bounds_bpm"] = Array(hz.boundaries_bpm)
		else:
			r.metadata["hr_zone_bounds_pct"] = _bounds_to_array(hz.boundaries_pct)
			r.metadata["hr_zone_bounds_bpm"] = null
	else:
		r.metadata["max_hr"] = 0
	return r


## Обновить метаданные и журнал из сессии, сохранив поля профиля и флаги жизненного цикла.
func refresh_from_session(session: Object) -> void:
	var fresh: Dictionary = _session_metadata(session)
	for key in fresh.keys():
		metadata[key] = fresh[key]
	events = _events_of(session)
	var stream: SampleStream = session.get("samples") as SampleStream
	if stream != null:
		samples = stream
	_normalize_ride_type()


static func _session_metadata(session: Object) -> Dictionary:
	if session is WorkoutSession:
		return (session as WorkoutSession).metadata()
	if session != null and session.has_method("metadata"):
		var m: Variant = session.call("metadata")
		if m is Dictionary:
			return (m as Dictionary).duplicate(true)
	return {}


## Журнал сессии по ссылке (сессия продолжает его наполнять).
static func _events_of(session: Object) -> Array[Dictionary]:
	if session is WorkoutSession:
		return (session as WorkoutSession).events
	var ev: Variant = session.get("events") if session != null else null
	if ev is Array and (ev as Array).get_typed_builtin() == TYPE_DICTIONARY:
		return ev
	var out: Array[Dictionary] = []
	if ev is Array:
		for item in ev:
			if item is Dictionary:
				out.append(item)
	return out


## Тип заезда и обязательные поля свободной езды (REQ-FRD-07 крит. 3).
func _normalize_ride_type() -> void:
	if str(metadata.get(KEY_RIDE_TYPE, "")) != RIDE_TYPE_FREE_RIDE:
		metadata[KEY_RIDE_TYPE] = RIDE_TYPE_WORKOUT
		return
	metadata["speed_source"] = SampleStream.SPEED_SOURCE_MODEL
	metadata.erase("workout_name")
	if not metadata.has(KEY_ROUTE_ID):
		metadata[KEY_ROUTE_ID] = ""
	if not metadata.has(KEY_SIM_STEEPNESS_START_PCT):
		metadata[KEY_SIM_STEEPNESS_START_PCT] = 0.0
	workout = {}
	name = ""
	update_route_totals()


## Итоговая дистанция и набор высоты свободной езды по сэмплам (REQ-FRD-07 крит. 3, 4).
func update_route_totals() -> void:
	if not is_free_ride():
		return
	metadata[KEY_TOTAL_DISTANCE_M] = samples.total_distance_m()
	metadata[KEY_TOTAL_ASCENT_M] = samples.total_ascent_m()


## `workout` или `free_ride`; заезды без поля (записанные до FRD-07) — `workout`.
func ride_type() -> String:
	var t := str(metadata.get(KEY_RIDE_TYPE, RIDE_TYPE_WORKOUT))
	return RIDE_TYPE_FREE_RIDE if t == RIDE_TYPE_FREE_RIDE else RIDE_TYPE_WORKOUT


func is_free_ride() -> bool:
	return ride_type() == RIDE_TYPE_FREE_RIDE


## Идентификатор трассы свободной езды ("" у тренировки по плану).
func route_id() -> String:
	return str(metadata.get(KEY_ROUTE_ID, "")) if is_free_ride() else ""


## Крутизна SIM на старте, % (0 у тренировки по плану).
func sim_steepness_start_pct() -> float:
	return _float(metadata.get(KEY_SIM_STEEPNESS_START_PCT), 0.0)


## Итоговая дистанция, м: из метаданных свободной езды, иначе по потоку.
func total_distance_m() -> float:
	var v: Variant = metadata.get(KEY_TOTAL_DISTANCE_M)
	return float(v) if v is int or v is float else samples.total_distance_m()


## Набор высоты, м: из метаданных свободной езды, иначе по потоку (0 без позиции на трассе).
func total_ascent_m() -> float:
	var v: Variant = metadata.get(KEY_TOTAL_ASCENT_M)
	return float(v) if v is int or v is float else samples.total_ascent_m()


## Источник станка: `TRAINER_SOURCE_EMULATOR` или `TRAINER_SOURCE_BLE` (без поля — `ble`).
func trainer_source() -> String:
	var v := str(metadata.get(KEY_TRAINER_SOURCE, TRAINER_SOURCE_BLE))
	return TRAINER_SOURCE_EMULATOR if v == TRAINER_SOURCE_EMULATOR else TRAINER_SOURCE_BLE


## Заезд записан на эмуляторе (данные не настоящие, T-160).
func is_emulator() -> bool:
	return trainer_source() == TRAINER_SOURCE_EMULATOR


func ftp_w() -> int:
	return _int(metadata.get("ftp_w"), 0)


func max_hr() -> int:
	return _int(metadata.get("max_hr"), 0)


func speed_source() -> String:
	return str(metadata.get("speed_source", ""))


func stopped_early() -> bool:
	return _bool(metadata.get("stopped_early"))


func is_in_progress() -> bool:
	return _bool(metadata.get("in_progress"))


func is_recovered() -> bool:
	return _bool(metadata.get("recovered"))


func paused_total_sec() -> float:
	var v: Variant = metadata.get("paused_total_sec", 0.0)
	return float(v) if v is int or v is float else 0.0


## Зоны мощности на момент заезда (границы из метаданных, иначе Coggan от FTP).
func power_zones() -> PowerZones:
	var bounds: Variant = metadata.get("power_zone_bounds_pct")
	if bounds is Array and not (bounds as Array).is_empty():
		return PowerZones.custom(ftp_w(), _array_to_bounds(bounds))
	return PowerZones.coggan(ftp_w())


## Зоны пульса на момент заезда или null, если недоступны.
func hr_zones() -> HrZones:
	var bpm: Variant = metadata.get("hr_zone_bounds_bpm")
	if bpm is Array and not (bpm as Array).is_empty():
		var out: Array[int] = []
		for v in bpm:
			out.append(_int(v, 0))
		return HrZones.custom_bpm(out)
	if max_hr() <= 0:
		return null
	var pct: Variant = metadata.get("hr_zone_bounds_pct")
	if pct is Array and not (pct as Array).is_empty():
		return HrZones.custom(max_hr(), _array_to_bounds(pct))
	return HrZones.five_zone(max_hr())


## Пересчитать сводку по текущему потоку и зонам заезда; шапка синхронизируется.
func compute_summary() -> RideSummary:
	update_route_totals()
	summary = RideSummary.compute(samples, ftp_w(), power_zones(), hr_zones())
	sync_summary_header()
	return summary


## Перенести в сводку поля шапки (id, дата, название, статус Strava, флаги).
func sync_summary_header() -> void:
	summary.ride_id = id
	summary.profile_id = profile_id
	summary.started_at_unix = started_at_unix
	summary.name = name
	summary.workout_source = str(workout.get("source", metadata.get("workout_source", "")))
	summary.strava_status = str(upload.get("strava_status", UPLOAD_NONE))
	summary.strava_activity_id = str(upload.get("strava_activity_id", ""))
	summary.stopped_early = stopped_early()
	summary.in_progress = is_in_progress()
	summary.recovered = is_recovered()
	summary.ride_type = ride_type()
	summary.route_id = route_id()
	summary.trainer_source = trainer_source()


## События паузы `{at_sec, duration_sec}` (для FIT и истории). Пауза без
## возобновления (сессия завершена на паузе) имеет `duration_sec` 0.
func pause_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		if str(e.get("type", "")) == WorkoutSession.EVENT_PAUSE:
			out.append({
				"at_sec": _float(e.get("at_sec"), 0.0),
				"duration_sec": _float(e.get("duration_sec"), 0.0),
				"resumed": e.has("duration_sec"),
			})
	return out


## Всё, кроме потока сэмплов, — содержимое `meta.json`.
func to_meta_dict() -> Dictionary:
	sync_summary_header()
	return {
		"schema": SCHEMA_VERSION,
		"id": id,
		"profile_id": profile_id,
		"started_at_unix": started_at_unix,
		"name": name,
		"description": description,
		"workout": workout.duplicate(true),
		"metadata": metadata.duplicate(true),
		"events": events.duplicate(true),
		"upload": upload.duplicate(true),
		"summary": summary.to_dict(),
	}


## Заезд из `meta.json` (без потока). null, если нет `id`.
static func from_meta_dict(data: Dictionary) -> Ride:
	var ride_id: String = str(data.get("id", ""))
	if ride_id.is_empty():
		return null
	var r := Ride.new()
	r.id = ride_id
	r.profile_id = str(data.get("profile_id", ""))
	r.started_at_unix = _int(data.get("started_at_unix"), 0)
	r.name = str(data.get("name", ""))
	r.description = str(data.get("description", ""))
	var w: Variant = data.get("workout")
	r.workout = (w as Dictionary).duplicate(true) if w is Dictionary else {}
	var m: Variant = data.get("metadata")
	r.metadata = (m as Dictionary).duplicate(true) if m is Dictionary else {}
	var ev: Variant = data.get("events")
	if ev is Array:
		for item in ev:
			if item is Dictionary:
				r.events.append((item as Dictionary).duplicate(true))
	r.upload = default_upload()
	var up: Variant = data.get("upload")
	if up is Dictionary:
		for key in (up as Dictionary).keys():
			r.upload[key] = up[key]
	r.upload["attempts"] = _int(r.upload.get("attempts"), 0)
	var sm: Variant = data.get("summary")
	r.summary = RideSummary.from_dict(sm) if sm is Dictionary else RideSummary.new()
	r.sync_summary_header()
	return r


static func _bounds_to_array(bounds: Array[float]) -> Array:
	var out: Array = []
	for b in bounds:
		out.append(b)
	return out


static func _array_to_bounds(values: Array) -> Array[float]:
	var out: Array[float] = []
	for v in values:
		out.append(_float(v, 0.0))
	return out


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
