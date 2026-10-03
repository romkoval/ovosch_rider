class_name ProfileRepository
extends RefCounted
## Хранилище профилей в одном JSON-файле `<dir>/profiles.json` (REQ-PRF-01).
##
## Каталог задаётся конструктором: в приложении `user://profiles/`, в тестах —
## временный `user://test_profiles_<rand>/`. Файл содержит список профилей и
## идентификатор активного; оба сохраняются между запусками (REQ-PRF-01 крит. 6).
##
## Правила:
## - Хранилище хранит снимки: `save()` кладёт копию переданного объекта, а
##   `get_by_id()/list()/get_active()` возвращают копии. Правка объекта у вызывающего
##   попадает на диск только через успешный `save()` — отклонённая правка не может
##   «протечь» в файл при следующей записи другого профиля.
## - `save()` валидирует профиль (`Profile.validate()`) и уникальность имени без
##   учёта регистра (REQ-PRF-01 крит. 1, 2); при ошибках ничего не пишет.
## - `delete()` отказывает удалять последний профиль (REQ-PRF-01 крит. 5).
## - `save()`, `delete()` и `set_active()` меняют состояние в памяти только после успешной
##   записи на диск: при сбое возвращают `storage_write_failed`, список и активный профиль
##   прежние, сигналы и каскадные хуки не вызываются.
## - Удаление каскадно: сначала вызываются хуки `add_on_delete_hook`, затем
##   испускается `profile_deleted(id)` — на них подписываются хранилища секретов,
##   датчиков и заездов (T-010/T-011/T-041), сам модуль профилей о них не знает.
## - Секреты (токены, ключи API) в этом файле не хранятся — только в `SecureStore`.
## - Запись атомарная (`AtomicFile`: временный файл → rename). Повреждённый файл при
##   загрузке не затирается: он переименовывается в `profiles.json.<метка>.corrupt`
##   (см. `_quarantine_corrupted`), в журнал уходит предупреждение, хранилище пустое.

const FILE_NAME: String = "profiles.json"
const SCHEMA_VERSION: int = 1
const DEFAULT_DIR: String = "user://profiles/"
## Суффикс копии повреждённого файла (`profiles.json.<метка времени>.corrupt`).
const CORRUPT_SUFFIX: String = ".corrupt"

## Коды ошибок операций хранилища (в дополнение к кодам `Profile.validate()`).
const ERR_NAME_NOT_UNIQUE: String = "name_not_unique"
const ERR_PROFILE_NOT_FOUND: String = "profile_not_found"
const ERR_LAST_PROFILE: String = "last_profile"
const ERR_STORAGE_WRITE_FAILED: String = "storage_write_failed"

## Профиль сохранён (создан или обновлён).
signal profile_saved(id: String)
## Профиль удалён; подписчики каскадно чистят его данные.
signal profile_deleted(id: String)
## Сменился активный профиль (пустая строка — активного нет).
signal active_profile_changed(id: String)

## Идентификатор активного профиля. Присвоение несуществующего id или неудачная запись
## игнорируются с ошибкой в `last_errors`; код ошибки возвращает `set_active()`.
var active_profile_id: String = "":
	set(value):
		set_active(value)
	get:
		return _active_id

## Ошибки последней операции (`save`/`create`/`delete`).
var last_errors: Array[String] = []

var _dir_path: String
var _profiles: Array[Profile] = []
var _active_id: String = ""
var _on_delete_hooks: Array[Callable] = []


func _init(dir_path: String = DEFAULT_DIR) -> void:
	_dir_path = dir_path if dir_path.ends_with("/") else dir_path + "/"
	load_from_disk()


## Путь к файлу хранилища.
func file_path() -> String:
	return _dir_path + FILE_NAME


func dir_path() -> String:
	return _dir_path


## Профили в порядке создания (копии).
func list() -> Array[Profile]:
	var out: Array[Profile] = []
	for p in _profiles:
		out.append(p.duplicate_profile())
	out.sort_custom(func(a: Profile, b: Profile) -> bool:
		if a.created_at != b.created_at:
			return a.created_at < b.created_at
		return a.name.naturalnocasecmp_to(b.name) < 0)
	return out


func count() -> int:
	return _profiles.size()


## Профиль по id (копия) или null.
func get_by_id(id: String) -> Profile:
	var stored := _find_stored(id)
	return stored.duplicate_profile() if stored != null else null


func _find_stored(id: String) -> Profile:
	for p in _profiles:
		if p.id == id:
			return p
	return null


## Активный профиль или null.
func get_active() -> Profile:
	return get_by_id(_active_id)


## Создать и сохранить профиль с именем; null при ошибке (см. `last_errors`).
func create(profile_name: String) -> Profile:
	var p := Profile.create(profile_name)
	if not save(p).is_empty():
		return null
	return p


## Сохранить новый или изменённый профиль. Возвращает коды ошибок; пустой — успех.
## Первый сохранённый профиль становится активным.
func save(profile: Profile) -> Array[String]:
	profile.normalize()
	var errors: Array[String] = profile.validate()
	if errors.is_empty() and not _is_name_unique(profile.name, profile.id):
		errors.append(ERR_NAME_NOT_UNIQUE)
	if not errors.is_empty():
		last_errors = errors
		return errors
	var snapshot := profile.duplicate_profile()
	var previous_profiles := _profiles.duplicate()
	var previous_active := _active_id
	var existing := _find_stored(profile.id)
	if existing == null:
		_profiles.append(snapshot)
	else:
		_profiles[_profiles.find(existing)] = snapshot
	if _active_id.is_empty():
		_active_id = profile.id
	if not _persist():
		# Файл не записан — память возвращается к прежнему состоянию (новый профиль не
		# появляется, изменённый — прежний, активный — прежний), сигналы не испускаются.
		_profiles = previous_profiles
		_active_id = previous_active
		errors.append(ERR_STORAGE_WRITE_FAILED)
		last_errors = errors
		return errors
	last_errors = errors
	if _active_id != previous_active:
		active_profile_changed.emit(_active_id)
	profile_saved.emit(profile.id)
	return errors


## Запомнить выбранную трассу свободной езды в профиле (REQ-FRD-02 крит. 3): правка одного
## поля поверх сохранённого снимка, остальные поля не трогаются. Идентификатор неверного
## формата сохраняется как "" (трасса по умолчанию, `Profile.normalize`). Коды ошибок — как
## у `save()`, плюс `profile_not_found`; пустой массив — сохранено на диск.
func set_last_route_id(profile_id: String, route_id: String) -> Array[String]:
	var profile := get_by_id(profile_id)
	if profile == null:
		last_errors = [ERR_PROFILE_NOT_FOUND]
		return last_errors.duplicate()
	profile.last_route_id = route_id
	return save(profile)


## Сохранить крутизну SIM профиля (REQ-FRD-05 крит. 1: 0–100 % с шагом 5, между сессиями).
## Значение приводится `Profile.normalize` (ограничение 0–100, округление до шага 5 %).
func set_sim_steepness_pct(profile_id: String, pct: int) -> Array[String]:
	var profile := get_by_id(profile_id)
	if profile == null:
		last_errors = [ERR_PROFILE_NOT_FOUND]
		return last_errors.duplicate()
	profile.sim_steepness_pct = pct
	return save(profile)


## Удалить профиль. Возвращает "" при успехе или код ошибки
## (`profile_not_found`, `last_profile`, `storage_write_failed`). Каскад: хуки, затем
## `profile_deleted`. Если файл не записан — профиль остаётся в памяти, активный не меняется,
## каскад не запускается (иначе секреты и заезды удалились бы у «живого» после перезапуска профиля).
func delete(id: String) -> String:
	var p := _find_stored(id)
	if p == null:
		last_errors = [ERR_PROFILE_NOT_FOUND]
		return ERR_PROFILE_NOT_FOUND
	if _profiles.size() <= 1:
		last_errors = [ERR_LAST_PROFILE]
		return ERR_LAST_PROFILE
	var previous_profiles := _profiles.duplicate()
	var previous_active := _active_id
	_profiles.erase(p)
	if _active_id == id:
		_active_id = list()[0].id
	if not _persist():
		_profiles = previous_profiles
		_active_id = previous_active
		last_errors = [ERR_STORAGE_WRITE_FAILED]
		return ERR_STORAGE_WRITE_FAILED
	if _active_id != previous_active:
		active_profile_changed.emit(_active_id)
	for hook in _on_delete_hooks:
		if hook.is_valid():
			hook.call(id)
	profile_deleted.emit(id)
	last_errors = []
	return ""


## Зарегистрировать каскадную очистку при удалении: `callable(id: String)`.
func add_on_delete_hook(callable: Callable) -> void:
	_on_delete_hooks.append(callable)


## Свободно ли имя (без учёта регистра); `exclude_id` — профиль, который переименовывают.
func is_name_available(profile_name: String, exclude_id: String = "") -> bool:
	return _is_name_unique(profile_name, exclude_id)


## Перечитать файл с диска (вызывается конструктором).
func load_from_disk() -> void:
	_profiles = []
	_active_id = ""
	var path := file_path()
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("ProfileRepository: не удалось открыть %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	var json := JSON.new()
	var parse_err := json.parse(file.get_as_text())
	file.close()
	if parse_err != OK or not (json.data is Dictionary):
		var why := json.get_error_message() if parse_err != OK else "ожидался JSON-объект"
		var backup := _quarantine_corrupted(path)
		push_warning("ProfileRepository: файл %s повреждён (%s), начинаем с пустого списка; копия: %s" \
				% [path, why, backup if not backup.is_empty() else "не сохранена"])
		return
	var data: Dictionary = json.data
	var raw_profiles: Variant = data.get("profiles", [])
	if raw_profiles is Array:
		for item in raw_profiles:
			if item is Dictionary:
				var p := Profile.from_dict(item)
				if not p.id.is_empty():
					_profiles.append(p)
	var active: String = str(data.get("active_profile_id", ""))
	if _find_stored(active) != null:
		_active_id = active
	elif not _profiles.is_empty():
		_active_id = list()[0].id


## Сделать профиль активным и записать это на диск. "" — успех (или профиль уже активен),
## иначе код: `profile_not_found` или `storage_write_failed` (активный профиль прежний).
func set_active(id: String) -> String:
	if id == _active_id:
		return ""
	if _find_stored(id) == null:
		push_error("ProfileRepository: профиль '%s' не найден, активный не изменён" % id)
		last_errors = [ERR_PROFILE_NOT_FOUND]
		return ERR_PROFILE_NOT_FOUND
	var previous := _active_id
	_active_id = id
	if not _persist():
		_active_id = previous
		last_errors = [ERR_STORAGE_WRITE_FAILED]
		return ERR_STORAGE_WRITE_FAILED
	last_errors = []
	active_profile_changed.emit(id)
	return ""


func _is_name_unique(profile_name: String, exclude_id: String) -> bool:
	var wanted: String = Profile.normalized_name(profile_name)
	for p in _profiles:
		if p.id != exclude_id and Profile.normalized_name(p.name) == wanted:
			return false
	return true


func _persist() -> bool:
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir_path))
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("ProfileRepository: не удалось создать каталог %s (%s)" % [_dir_path, error_string(err)])
		return false
	var items: Array = []
	for p in list():
		items.append(p.to_dict())  # list() уже отсортирован
	var data := {
		"schema": SCHEMA_VERSION,
		"active_profile_id": _active_id,
		"profiles": items,
	}
	var write_err := AtomicFile.write_text(file_path(), JSON.stringify(data, "\t"))
	if write_err != OK:
		push_error("ProfileRepository: не удалось записать %s (%s)" % [file_path(), error_string(write_err)])
		return false
	return true


## Повреждённый файл не затирается: переименовывается в `<file>.<ГГГГММДД-ЧЧММСС>.corrupt`
## (при совпадении имени добавляется номер). Возвращает новый путь или "" при неудаче.
func _quarantine_corrupted(path: String) -> String:
	var stamp := Time.get_datetime_string_from_system(false, false).replace("-", "").replace(":", "").replace("T", "-")
	var target := "%s.%s%s" % [path, stamp, CORRUPT_SUFFIX]
	var n := 1
	while FileAccess.file_exists(target):
		target = "%s.%s-%d%s" % [path, stamp, n, CORRUPT_SUFFIX]
		n += 1
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(target))
	if err != OK:
		push_error("ProfileRepository: не удалось отложить повреждённый %s (%s)" % [path, error_string(err)])
		return ""
	return target
