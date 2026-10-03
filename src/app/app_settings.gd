class_name AppSettings
extends RefCounted
## Настройки приложения, не относящиеся к профилю (REQ-NFR-08 крит. 3, 4): язык интерфейса.
## Хранятся в `user://settings.json` (в тестах — временный путь). Пустой `locale` —
## язык не выбран, действует `AppLocale.detect()`.

const DEFAULT_PATH: String = "user://settings.json"
const SCHEMA_VERSION: int = 1

var locale: String = ""

var _path: String


func _init(path: String = DEFAULT_PATH) -> void:
	_path = path


func path() -> String:
	return _path


## Прочитать настройки с диска; отсутствующий или повреждённый файл → значения по умолчанию.
static func load_from(path: String = DEFAULT_PATH) -> AppSettings:
	var s := AppSettings.new(path)
	if not FileAccess.file_exists(path):
		return s
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("AppSettings: cannot open %s" % path)
		return s
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK or not (json.data is Dictionary):
		push_warning("AppSettings: %s is corrupted, using defaults" % path)
		return s
	var data: Dictionary = json.data
	var loc := str(data.get("locale", ""))
	s.locale = loc if AppLocale.SUPPORTED_LOCALES.has(loc) else ""
	return s


func save() -> bool:
	var dir := _path.get_base_dir()
	if not dir.is_empty():
		var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		if err != OK and err != ERR_ALREADY_EXISTS:
			push_error("AppSettings: cannot create directory %s (%s)" % [dir, error_string(err)])
			return false
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_error("AppSettings: cannot write %s (%s)" % [_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify({"schema": SCHEMA_VERSION, "locale": locale}, "\t"))
	file.close()
	return true


## Язык для применения при старте: сохранённый, иначе системный (REQ-NFR-08 крит. 3).
func effective_locale() -> String:
	return locale if AppLocale.SUPPORTED_LOCALES.has(locale) else AppLocale.detect()


func has_locale() -> bool:
	return AppLocale.SUPPORTED_LOCALES.has(locale)
