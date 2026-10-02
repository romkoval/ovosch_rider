class_name WorkoutLibrary
extends RefCounted
## Библиотека импортированных тренировок профиля (REQ-IMP-03 крит. 1, REQ-IMP-04, REQ-IMP-05).
##
## Хранение: один JSON на запись в `<dir>/library_<profile_id>/<uuid>.json`
## (план через `WorkoutSerializer`). Каталог задаётся конструктором: в приложении
## `user://workouts/`, в тестах — временный. Библиотеки профилей изолированы
## каталогом (REQ-IMP-04 крит. 2).
##
## Запись (`Dictionary`): `{id, name, duration_sec, source, source_file, imported_at,
## content_hash, metadata}`; план отдельно через `get_workout()` (REQ-IMP-04 крит. 1).
##
## Повторный импорт (открытое решение 20): файл с тем же содержимым (SHA-256 текста)
## заменяет существующую запись (id сохраняется) с предупреждением `duplicate_replaced`;
## файл с тем же названием, но другим содержимым создаёт отдельную запись
## (REQ-IMP-04 крит. 4). До подтверждения владельцем правило может измениться —
## менять в `_find_by_hash`/`import_text`.
##
## Удаление записи не затрагивает заезды — библиотека о них не знает (REQ-IMP-04 крит. 5).
## Каскад с профилями: `attach_to_profiles(repo)` подписывается на
## `ProfileRepository.profile_deleted` и удаляет каталог профиля.
##
## Системный диалог и «Открыть в…» — в UI (T-039/T-040), сюда приходит уже путь.

const DEFAULT_DIR: String = "user://workouts/"
const SCHEMA_VERSION: int = 1
const SUPPORTED_EXTENSIONS: Array[String] = ["zwo", "erg", "mrc"]

## Запись добавлена, заменена или удалена.
signal library_changed(profile_id: String)

var _dir_path: String


func _init(dir_path: String = DEFAULT_DIR) -> void:
	_dir_path = dir_path if dir_path.ends_with("/") else dir_path + "/"


func dir_path() -> String:
	return _dir_path


## Каталог библиотеки профиля.
func profile_dir(profile_id: String) -> String:
	return _dir_path + "library_%s/" % profile_id


## Расширение поддерживается (без учёта регистра)?
static func is_supported_extension(path: String) -> bool:
	return SUPPORTED_EXTENSIONS.has(path.get_extension().to_lower())


## Разобрать текст файла парсером по расширению `file_name` (REQ-IMP-03 крит. 1).
## Имя файла попадает в `metadata.file_name`; пустое имя плана → имя файла без расширения.
static func parse_text(text: String, file_name: String) -> ParseResult:
	var ext := file_name.get_extension().to_lower()
	var result: ParseResult
	match ext:
		"zwo":
			result = ZwoParser.parse(text)
		"erg", "mrc":
			result = ErgMrcParser.parse(text, ext)
		_:
			result = ParseResult.new()
			var shown := ext if not ext.is_empty() else "(нет)"
			result.add_error("расширение .%s не поддерживается (ожидается .zwo, .erg или .mrc)" % shown, 0, 0, file_name.get_file(), "unsupported_extension")
	result.metadata["file_name"] = file_name.get_file()
	if result.workout != null and result.workout.name.strip_edges().is_empty():
		result.workout.name = file_name.get_file().get_basename()
	return result


## Импорт файла по пути в библиотеку профиля. Возвращает результат разбора;
## при `ok()` в `metadata.entry_id` — id записи.
func import_file(profile_id: String, path: String) -> ParseResult:
	if not FileAccess.file_exists(path):
		var r := ParseResult.new()
		r.add_error("файл не найден", 0, 0, path.get_file(), "file_not_found")
		r.metadata["file_name"] = path.get_file()
		return r
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var r := ParseResult.new()
		r.add_error("не удалось открыть файл", 0, 0, path.get_file(), "file_open_failed")
		r.metadata["file_name"] = path.get_file()
		return r
	var text := file.get_as_text()
	file.close()
	return import_text(profile_id, text, path.get_file())


## Импорт содержимого файла (для «Открыть в…»/Share, где есть только байты и имя).
func import_text(profile_id: String, text: String, file_name: String) -> ParseResult:
	var result := parse_text(text, file_name)
	if profile_id.strip_edges().is_empty():
		result.add_error("не выбран профиль", 0, 0, "", "no_profile")
	if not result.ok():
		return result
	var hash := text.sha256_text()
	var entry_id := ""
	var existing := _find_by_hash(profile_id, hash)
	if not existing.is_empty():
		entry_id = str(existing["id"])
		result.add_warning("файл с таким содержимым уже импортирован — запись '%s' заменена" % str(existing.get("name", "")),
				0, 0, file_name, "duplicate_replaced")
	else:
		entry_id = _generate_id()
	var w: Workout = result.workout
	var record := {
		"schema": SCHEMA_VERSION,
		"id": entry_id,
		"name": w.name,
		"duration_sec": w.total_duration_sec(),
		"source": w.source,
		"source_file": file_name,
		"imported_at": int(Time.get_unix_time_from_system()),
		"content_hash": hash,
		"metadata": result.metadata.duplicate(),
		"workout": WorkoutSerializer.to_dict(w),
	}
	if not _write_record(profile_id, record):
		result.add_error("не удалось сохранить тренировку в библиотеку", 0, 0, file_name, "storage_write_failed")
		return result
	result.metadata["entry_id"] = entry_id
	library_changed.emit(profile_id)
	return result


## Записи профиля (без плана), по времени импорта, затем по имени.
func list(profile_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for record in _read_all(profile_id):
		out.append(_summary(record))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["imported_at"]) != int(b["imported_at"]):
			return int(a["imported_at"]) < int(b["imported_at"])
		return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	return out


func count(profile_id: String) -> int:
	return _read_all(profile_id).size()


## Запись по id (без плана) или пустой словарь.
func get_entry(profile_id: String, id: String) -> Dictionary:
	var record := _read_record(profile_id, id)
	return _summary(record) if not record.is_empty() else {}


## План по id записи или null.
func get_workout(profile_id: String, id: String) -> Workout:
	var record := _read_record(profile_id, id)
	if record.is_empty() or not (record.get("workout") is Dictionary):
		return null
	return WorkoutSerializer.from_dict(record["workout"])


## Удалить запись. false — записи нет.
func delete(profile_id: String, id: String) -> bool:
	var path := _record_path(profile_id, id)
	if not _is_safe_id(id) or not FileAccess.file_exists(path):
		return false
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
		return false
	library_changed.emit(profile_id)
	return true


## Удалить всю библиотеку профиля (каскад при удалении профиля). Возвращает число записей.
func delete_all(profile_id: String) -> int:
	var abs_dir := ProjectSettings.globalize_path(profile_dir(profile_id))
	if not DirAccess.dir_exists_absolute(abs_dir):
		return 0
	var d := DirAccess.open(abs_dir)
	if d == null:
		return 0
	var removed := 0
	for f in d.get_files():
		if DirAccess.remove_absolute(abs_dir.path_join(f)) == OK and f.ends_with(".json"):
			removed += 1
	DirAccess.remove_absolute(abs_dir)
	library_changed.emit(profile_id)
	return removed


## Подписаться на удаление профилей: библиотека удалённого профиля стирается.
func attach_to_profiles(repo: ProfileRepository) -> void:
	if not repo.profile_deleted.is_connected(_on_profile_deleted):
		repo.profile_deleted.connect(_on_profile_deleted)


func _on_profile_deleted(profile_id: String) -> void:
	delete_all(profile_id)


# ---------------------------------------------------------------------------
# Файлы
# ---------------------------------------------------------------------------

func _record_path(profile_id: String, id: String) -> String:
	return profile_dir(profile_id) + id + ".json"


static func _is_safe_id(id: String) -> bool:
	return not id.is_empty() and id.is_valid_filename() and not id.contains("/") and not id.contains("..")


func _summary(record: Dictionary) -> Dictionary:
	return {
		"id": str(record.get("id", "")),
		"name": str(record.get("name", "")),
		"duration_sec": int(record.get("duration_sec", 0)),
		"source": str(record.get("source", "")),
		"source_file": str(record.get("source_file", "")),
		"imported_at": int(record.get("imported_at", 0)),
		"content_hash": str(record.get("content_hash", "")),
		"metadata": record.get("metadata", {}) if record.get("metadata") is Dictionary else {},
	}


func _find_by_hash(profile_id: String, hash: String) -> Dictionary:
	for record in _read_all(profile_id):
		if str(record.get("content_hash", "")) == hash:
			return record
	return {}


func _read_all(profile_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var abs_dir := ProjectSettings.globalize_path(profile_dir(profile_id))
	if not DirAccess.dir_exists_absolute(abs_dir):
		return out
	var d := DirAccess.open(abs_dir)
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(".json"):
			continue
		var record := _read_record(profile_id, f.get_basename())
		if not record.is_empty():
			out.append(record)
	return out


func _read_record(profile_id: String, id: String) -> Dictionary:
	if not _is_safe_id(id):
		return {}
	var path := _record_path(profile_id, id)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK or not (json.data is Dictionary):
		return {}  # повреждённая запись пропускается молча (REQ-IMP-05 крит. 4: без ошибок движка)
	var data: Dictionary = json.data
	if str(data.get("id", "")) != id:
		data["id"] = id
	return data


func _write_record(profile_id: String, record: Dictionary) -> bool:
	var dir := profile_dir(profile_id)
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("WorkoutLibrary: не удалось создать каталог %s (%s)" % [dir, error_string(err)])
		return false
	var path := _record_path(profile_id, str(record["id"]))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("WorkoutLibrary: не удалось записать %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(record, "\t"))
	file.close()
	return true


## UUID v4 `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`.
static func _generate_id() -> String:
	var hex := "0123456789abcdef"
	var out := ""
	for i in 32:
		var c: String
		if i == 12:
			c = "4"
		elif i == 16:
			c = hex[8 + randi() % 4]
		else:
			c = hex[randi() % 16]
		if i in [8, 12, 16, 20]:
			out += "-"
		out += c
	return out
