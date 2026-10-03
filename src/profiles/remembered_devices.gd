class_name RememberedDevices
extends RefCounted
## Реестр запомненных устройств (REQ-PRF-04 крит. 2–4, REQ-DEV-06 крит. 1 — хранение).
##
## Датчики (пульс, каденс, мощность) принадлежат профилю и лежат в
## `<dir>/devices_<profile_id>.json`; станок один на устройство — `<dir>/trainer.json`,
## доступен всем профилям. Удаление профиля (каскад через `attach_to_profiles`)
## стирает только файл его датчиков, станок остаётся (REQ-PRF-01 крит. 4).
##
## Запись устройства — словарь `{id, name, kind, last_seen_at, auto_connect}`:
## `kind` ∈ `"trainer"|"hr"|"cadence"|"power"`, `last_seen_at` — unix-секунды,
## `auto_connect` — предлагать ли автоподключение (REQ-DEV-06).

const KIND_TRAINER: String = "trainer"
const KIND_HR: String = "hr"
const KIND_CADENCE: String = "cadence"
const KIND_POWER: String = "power"
const KINDS: Array[String] = [KIND_TRAINER, KIND_HR, KIND_CADENCE, KIND_POWER]

const DEFAULT_DIR: String = "user://devices/"
const TRAINER_FILE: String = "trainer.json"
const PROFILE_FILE_PREFIX: String = "devices_"
const SCHEMA_VERSION: int = 1

## Любое изменение реестра (для обновления списков в UI).
signal changed()

var _dir_path: String
var _trainer: Dictionary = {}
## profile_id → Array[Dictionary] (кэш загруженных файлов).
var _sensors: Dictionary = {}


func _init(dir_path: String = DEFAULT_DIR) -> void:
	_dir_path = dir_path if dir_path.ends_with("/") else dir_path + "/"
	_load_trainer()


## Собрать запись устройства; `last_seen_at` 0 → текущее время.
static func make_device(id: String, name: String, kind: String, auto_connect: bool = true, last_seen_at: int = 0) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"kind": kind,
		"last_seen_at": last_seen_at if last_seen_at > 0 else int(Time.get_unix_time_from_system()),
		"auto_connect": auto_connect,
	}


## Запись корректна: непустой id и известный kind.
static func is_valid_device(device: Dictionary) -> bool:
	return not str(device.get("id", "")).is_empty() and KINDS.has(str(device.get("kind", "")))


func dir_path() -> String:
	return _dir_path


func trainer_file_path() -> String:
	return _dir_path + TRAINER_FILE


func profile_file_path(profile_id: String) -> String:
	return _dir_path + PROFILE_FILE_PREFIX + sanitize_id(profile_id) + ".json"


## Идентификатор в безопасное имя файла: допустимы только `[A-Za-z0-9_-]`, прочее → `_`
## (никаких разделителей пути и `..`; файл всегда лежит прямо в каталоге устройств).
static func sanitize_id(profile_id: String) -> String:
	var re := RegEx.create_from_string("[^A-Za-z0-9_-]")
	var safe := re.sub(profile_id, "_", true)
	return safe if not safe.is_empty() else "_"


## Запомнить устройство. Станок (`kind == "trainer"`) становится общим независимо
## от `profile_id`; датчик пишется в файл профиля (замена по id). false — запись некорректна.
func remember(profile_id: String, device: Dictionary) -> bool:
	if not is_valid_device(device):
		return false
	if str(device["kind"]) == KIND_TRAINER:
		return set_trainer(device)
	if profile_id.is_empty():
		return false
	var sensors: Array[Dictionary] = _sensors_of(profile_id)
	var record: Dictionary = _normalize(device)
	var replaced: bool = false
	for i in sensors.size():
		if str(sensors[i]["id"]) == str(record["id"]):
			sensors[i] = record
			replaced = true
			break
	if not replaced:
		sensors.append(record)
	var ok: bool = _save_sensors(profile_id)
	if ok:
		changed.emit()
	return ok


## Забыть устройство: датчик — из профиля; если id совпадает с общим станком — забыть станок.
## true, если что-то удалено.
func forget(profile_id: String, device_id: String) -> bool:
	var removed: bool = false
	if not _trainer.is_empty() and str(_trainer["id"]) == device_id:
		clear_trainer()
		removed = true
	if not profile_id.is_empty():
		var sensors: Array[Dictionary] = _sensors_of(profile_id)
		for i in range(sensors.size() - 1, -1, -1):
			if str(sensors[i]["id"]) == device_id:
				sensors.remove_at(i)
				removed = true
		if removed:
			_save_sensors(profile_id)
	if removed:
		changed.emit()
	return removed


## Датчики профиля + общий станок (станок первым). Копии записей.
func list(profile_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _trainer.is_empty():
		out.append(_trainer.duplicate())
	for d in sensors(profile_id):
		out.append(d)
	return out


## Только датчики профиля, по имени. Копии записей.
func sensors(profile_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if profile_id.is_empty():
		return out
	for d in _sensors_of(profile_id):
		out.append(d.duplicate())
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	return out


## Устройства профиля (включая станок) с `auto_connect == true` (REQ-DEV-06 крит. 2).
func auto_connect_candidates(profile_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in list(profile_id):
		if bool(d.get("auto_connect", false)):
			out.append(d)
	return out


## Найти запись по id среди устройств профиля и станка; {} если нет.
func find(profile_id: String, device_id: String) -> Dictionary:
	for d in list(profile_id):
		if str(d["id"]) == device_id:
			return d
	return {}


## Включить/выключить автоподключение устройства. false — устройство не найдено.
func set_auto_connect(profile_id: String, device_id: String, enabled: bool) -> bool:
	var d := find(profile_id, device_id)
	if d.is_empty():
		return false
	d["auto_connect"] = enabled
	return remember(profile_id, d)


## Отметить, что устройство видели сейчас (или в `seen_at`).
func mark_seen(profile_id: String, device_id: String, seen_at: int = 0) -> bool:
	var d := find(profile_id, device_id)
	if d.is_empty():
		return false
	d["last_seen_at"] = seen_at if seen_at > 0 else int(Time.get_unix_time_from_system())
	return remember(profile_id, d)


## Общий станок; {} если не запомнен. Копия записи.
func trainer() -> Dictionary:
	return _trainer.duplicate()


func has_trainer() -> bool:
	return not _trainer.is_empty()


## Запомнить общий станок (kind принудительно `"trainer"`).
func set_trainer(device: Dictionary) -> bool:
	if str(device.get("id", "")).is_empty():
		return false
	var record: Dictionary = _normalize(device)
	record["kind"] = KIND_TRAINER
	_trainer = record
	var ok: bool = _save_trainer()
	if ok:
		changed.emit()
	return ok


func clear_trainer() -> void:
	if _trainer.is_empty():
		return
	_trainer = {}
	var path := trainer_file_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	changed.emit()


## Есть ли у профиля файл датчиков.
func has_profile_devices(profile_id: String) -> bool:
	return FileAccess.file_exists(profile_file_path(profile_id))


## Удалить все датчики профиля (каскад при удалении профиля). Станок не трогается.
func delete_profile_devices(profile_id: String) -> void:
	if profile_id.is_empty():
		return
	_sensors.erase(profile_id)
	var path := profile_file_path(profile_id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	changed.emit()


## Подписаться на удаление профилей: `repo.profile_deleted` → `delete_profile_devices`.
## Связанный метод, не лямбда (лямбда держала бы реестр сильной ссылкой); повторный вызов — no-op.
func attach_to_profiles(repo: ProfileRepository) -> void:
	if not repo.profile_deleted.is_connected(_on_profile_deleted):
		repo.profile_deleted.connect(_on_profile_deleted)


## Отписаться от удаления профилей.
func detach_from_profiles(repo: ProfileRepository) -> void:
	if repo.profile_deleted.is_connected(_on_profile_deleted):
		repo.profile_deleted.disconnect(_on_profile_deleted)


func _on_profile_deleted(profile_id: String) -> void:
	delete_profile_devices(profile_id)


# ---------------------------------------------------------------------------

func _normalize(device: Dictionary) -> Dictionary:
	return {
		"id": str(device["id"]),
		"name": str(device.get("name", "")),
		"kind": str(device.get("kind", "")),
		"last_seen_at": int(device.get("last_seen_at", 0)),
		"auto_connect": bool(device.get("auto_connect", true)),
	}


func _sensors_of(profile_id: String) -> Array[Dictionary]:
	if not _sensors.has(profile_id):
		_sensors[profile_id] = _load_sensors(profile_id)
	return _sensors[profile_id]


func _load_sensors(profile_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var data := _read_json(profile_file_path(profile_id))
	var items: Variant = data.get("devices", [])
	if items is Array:
		for item in items:
			if item is Dictionary and is_valid_device(item) and str(item["kind"]) != KIND_TRAINER:
				out.append(_normalize(item))
	return out


func _save_sensors(profile_id: String) -> bool:
	var items: Array = []
	for d in _sensors_of(profile_id):
		items.append(d)
	return _write_json(profile_file_path(profile_id), {"schema": SCHEMA_VERSION, "profile_id": profile_id, "devices": items})


func _load_trainer() -> void:
	_trainer = {}
	var data := _read_json(trainer_file_path())
	var t: Variant = data.get("trainer", {})
	if t is Dictionary and not str((t as Dictionary).get("id", "")).is_empty():
		_trainer = _normalize(t)
		_trainer["kind"] = KIND_TRAINER


func _save_trainer() -> bool:
	return _write_json(trainer_file_path(), {"schema": SCHEMA_VERSION, "trainer": _trainer})


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("RememberedDevices: не удалось открыть %s" % path)
		return {}
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK or not (json.data is Dictionary):
		push_warning("RememberedDevices: файл %s повреждён (%s), игнорируется" % [path, json.get_error_message()])
		return {}
	return json.data


func _write_json(path: String, data: Dictionary) -> bool:
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir_path))
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("RememberedDevices: не удалось создать каталог %s (%s)" % [_dir_path, error_string(err)])
		return false
	var write_err := AtomicFile.write_text(path, JSON.stringify(data, "\t"))
	if write_err != OK:
		push_error("RememberedDevices: не удалось записать %s (%s)" % [path, error_string(write_err)])
		return false
	return true
