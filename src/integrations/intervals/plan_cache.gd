class_name PlanCache
extends RefCounted
## Кэш плана на дату (REQ-INT-07 крит. 1–3, REQ-NFR-03 крит. 1, 2).
##
## Файл `<dir>/intervals_cache_<profile_id>/<YYYY-MM-DD>.json`:
## `{schema, date, loaded_at, workouts: [{event_id, name, start_date_local, type,
## duration_sec, training_load, workout: WorkoutSerializer.to_dict}]}`.
## TTL нет: запись заменяется при каждой успешной загрузке; при сохранении файлы
## других дат удаляются (крит. 3 — кэш другой даты никогда не предлагается:
## `get_today()` читает только файл сегодняшней даты). Пустой список тренировок
## тоже кэшируется — без сети статус «на сегодня тренировок нет» воспроизводится.
## Чтение из кэша не делает сетевых запросов (крит. 4). Запись атомарная (`AtomicFile`).

const DEFAULT_DIR: String = "user://plans/"
const SCHEMA_VERSION: int = 1

var _dir_path: String


func _init(dir_path: String = DEFAULT_DIR) -> void:
	_dir_path = dir_path if dir_path.ends_with("/") else dir_path + "/"


func dir_path() -> String:
	return _dir_path


func profile_dir(profile_id: String) -> String:
	return _dir_path + "intervals_cache_%s/" % profile_id


func file_path(profile_id: String, date: String) -> String:
	return profile_dir(profile_id) + date + ".json"


## Сохранить план на дату. `workouts` — записи `IntervalsIcuClient.entry_from_event`
## (поле `workout: Workout|null`); записи без плана пропускаются.
func save(profile_id: String, date: String, workouts: Array, loaded_at: int = 0) -> bool:
	if profile_id.strip_edges().is_empty() or not _is_date(date):
		return false
	var items: Array = []
	for w in workouts:
		if not (w is Dictionary):
			continue
		var entry: Dictionary = w
		var workout: Variant = entry.get("workout")
		if not (workout is Workout):
			continue
		items.append({
			"event_id": str(entry.get("event_id", "")),
			"name": str(entry.get("name", "")),
			"start_date_local": str(entry.get("start_date_local", "")),
			"type": str(entry.get("type", "")),
			"duration_sec": int(entry.get("duration_sec", (workout as Workout).total_duration_sec())),
			"training_load": int(entry.get("training_load", 0)),
			"workout": WorkoutSerializer.to_dict(workout),
		})
	var record := {
		"schema": SCHEMA_VERSION,
		"date": date,
		"loaded_at": loaded_at if loaded_at > 0 else int(Time.get_unix_time_from_system()),
		"workouts": items,
	}
	var dir := profile_dir(profile_id)
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if err != OK and err != ERR_ALREADY_EXISTS:
		return false
	if AtomicFile.write_text(file_path(profile_id, date), JSON.stringify(record, "\t")) != OK:
		return false
	_prune_other_dates(profile_id, date)
	return true


## Кэш на дату: `{date, loaded_at, workouts: Array[Dictionary]}` с восстановленными
## `Workout`, или пустой словарь, если кэша нет/он повреждён.
func load_date(profile_id: String, date: String) -> Dictionary:
	if not _is_date(date):
		return {}
	var path := file_path(profile_id, date)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK or not (json.data is Dictionary):
		return {}
	var data: Dictionary = json.data
	if str(data.get("date", "")) != date or not (data.get("workouts") is Array):
		return {}
	var workouts: Array[Dictionary] = []
	for item in data["workouts"]:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		var w: Workout = WorkoutSerializer.from_dict(entry.get("workout", {})) if entry.get("workout") is Dictionary else null
		if w == null:
			continue
		workouts.append({
			"event_id": str(entry.get("event_id", "")),
			"name": str(entry.get("name", "")),
			"start_date_local": str(entry.get("start_date_local", "")),
			"type": str(entry.get("type", "")),
			"duration_sec": int(entry.get("duration_sec", w.total_duration_sec())),
			"training_load": int(entry.get("training_load", 0)),
			"workout": w,
			"parse_result": null,
		})
	return {
		"date": date,
		"loaded_at": int(data.get("loaded_at", 0)),
		"workouts": workouts,
	}


func has(profile_id: String, date: String) -> bool:
	return FileAccess.file_exists(file_path(profile_id, date))


## Кэш именно на сегодня (REQ-INT-07 крит. 2, 3); кэш другой даты → пустой словарь.
func get_today(profile_id: String, today: String = "") -> Dictionary:
	var date := today if not today.is_empty() else IntervalsIcuClient.local_date()
	return load_date(profile_id, date)


## Удалить кэш профиля (каскад при удалении профиля). Возвращает число файлов.
func clear(profile_id: String) -> int:
	var abs_dir := ProjectSettings.globalize_path(profile_dir(profile_id))
	if not DirAccess.dir_exists_absolute(abs_dir):
		return 0
	var d := DirAccess.open(abs_dir)
	if d == null:
		return 0
	var removed := 0
	for f in d.get_files():
		if DirAccess.remove_absolute(abs_dir.path_join(f)) == OK:
			removed += 1
	DirAccess.remove_absolute(abs_dir)
	return removed


func attach_to_profiles(repo: ProfileRepository) -> void:
	if not repo.profile_deleted.is_connected(_on_profile_deleted):
		repo.profile_deleted.connect(_on_profile_deleted)


func _on_profile_deleted(profile_id: String) -> void:
	clear(profile_id)


## Пометка для UI: «из кэша, загружен <ЧЧ:ММ>» в локальном времени устройства
## (дата добавляется, если не сегодня).
static func cache_label(loaded_at: int, today: String = "") -> String:
	if loaded_at <= 0:
		return "из кэша"
	var dt := local_datetime(loaded_at)
	var date := today if not today.is_empty() else IntervalsIcuClient.local_date()
	var loaded_date := "%04d-%02d-%02d" % [dt["year"], dt["month"], dt["day"]]
	var time := "%02d:%02d" % [dt["hour"], dt["minute"]]
	if loaded_date == date:
		return "из кэша, загружен %s" % time
	return "из кэша, загружен %s %s" % [loaded_date, time]


## Локальные дата/время для unix-секунд (смещение часового пояса системы).
static func local_datetime(unix_sec: int) -> Dictionary:
	var bias_min := int(Time.get_time_zone_from_system().get("bias", 0))
	return Time.get_datetime_dict_from_unix_time(unix_sec + bias_min * 60)


func _prune_other_dates(profile_id: String, keep_date: String) -> void:
	var abs_dir := ProjectSettings.globalize_path(profile_dir(profile_id))
	var d := DirAccess.open(abs_dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".json") and f.get_basename() != keep_date:
			DirAccess.remove_absolute(abs_dir.path_join(f))


static func _is_date(date: String) -> bool:
	return RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$").search(date) != null
