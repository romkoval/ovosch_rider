class_name DiagLog
extends RefCounted
## Диагностический журнал (T-116a): файл на запуск в `user://logs/`, ротация, предел объёма,
## фильтр секретов, экспорт одним файлом. Ядро для журнала кадров (T-116a) и BLE (T-116b).
##
## Слой — `src/storage/` (REQ-NFR-06 п.3): журнал — файлы в `user://`, как заезды и профили;
## фильтру нужен `SecureStore` того же слоя; писать в журнал могут и нижние слои (устройства
## в T-116b), и интерфейс — оба могут зависеть от `src/storage/`, а сам журнал ни от кого
## выше не зависит.
##
## Формат — JSON Lines, одна запись на строку:
## `{"t":"2026-10-04T12:34:56.789Z","up_ms":1234,"cat":"frames","ev":"ride_stats","data":{…}}`.
## `t` — время UTC, `up_ms` — миллисекунды с запуска движка (для интервалов между событиями),
## `cat` — категория (`CAT_*`; `ble` — T-154, T-116b), `ev` — событие, `data` — поля события.
## Каждая строка до записи проходит `SecureStoreFilter`, после записи — `flush()` (журнал полезен
## и после падения).
##
## Файлы: `ovosch-<ГГГГММДД-ЧЧММСС-мс>-pNNN.log` — запуск и номер части; имена сортируются
## по времени. Часть закрывается, когда следующая строка не помещается в `max_file_bytes`;
## при открытии и при каждой новой части старые файлы удаляются, пока их больше `max_files`
## или суммарный объём больше `max_total_bytes` (текущая часть не удаляется никогда), поэтому
## каталог журнала не превышает `max_total_bytes` (при `max_file_bytes` ≤ `max_total_bytes`).
##
## Общий журнал приложения — `DiagLog.install(log)` (оболочка при запуске); писать в него —
## `DiagLog.event(…)` откуда угодно: без установленного журнала вызов ничего не делает.

const DEFAULT_DIR: String = "user://logs/"
const FILE_PREFIX: String = "ovosch-"
const FILE_SUFFIX: String = ".log"
const FORMAT_VERSION: int = 1
## Пределы по умолчанию: часть 2 МиБ, каталог 16 МиБ, не больше 20 файлов.
const DEFAULT_MAX_FILE_BYTES: int = 2 * 1024 * 1024
const DEFAULT_MAX_TOTAL_BYTES: int = 16 * 1024 * 1024
const DEFAULT_MAX_FILES: int = 20

const CAT_APP: String = "app"
const CAT_FRAMES: String = "frames"
const CAT_SETTINGS: String = "settings"
## BLE: события подключения датчиков (T-154); пакеты, станок и Control Point — T-116b.
const CAT_BLE: String = "ble"

## Общий журнал приложения (null — не установлен).
static var _shared: DiagLog = null

var max_file_bytes: int = DEFAULT_MAX_FILE_BYTES
var max_total_bytes: int = DEFAULT_MAX_TOTAL_BYTES
var max_files: int = DEFAULT_MAX_FILES

var _dir: String
var _filter: SecureStoreFilter = SecureStoreFilter.new()
var _file: FileAccess = null
var _path: String = ""
var _stamp: String = ""
var _part: int = 0
var _size: int = 0
var _lines: int = 0
var _last_error: Error = OK


func _init(dir_path: String = DEFAULT_DIR, file_limit: int = DEFAULT_MAX_FILE_BYTES,
		total_limit: int = DEFAULT_MAX_TOTAL_BYTES, files_limit: int = DEFAULT_MAX_FILES) -> void:
	_dir = dir_path if dir_path.ends_with("/") else dir_path + "/"
	max_file_bytes = maxi(file_limit, 256)
	max_total_bytes = maxi(total_limit, max_file_bytes)
	max_files = maxi(files_limit, 1)


# ---------------------------------------------------------------------------
# Общий журнал
# ---------------------------------------------------------------------------

## Сделать журнал общим для приложения (`event`, `shared`).
static func install(journal: DiagLog) -> void:
	_shared = journal


## Снять общий журнал, если установлен именно этот (null — любой).
static func uninstall(journal: DiagLog = null) -> void:
	if journal == null or _shared == journal:
		_shared = null


static func shared() -> DiagLog:
	return _shared


## Записать событие в общий журнал; без журнала — ничего.
static func event(category: String, name: String, data: Dictionary = {}) -> void:
	if _shared != null:
		_shared.write(category, name, data)


# ---------------------------------------------------------------------------
# Файл
# ---------------------------------------------------------------------------

## Открыть новый файл запуска. `OK` или код ошибки (журнал тогда молча ничего не пишет).
func open() -> Error:
	close()
	var mk := DirAccess.make_dir_recursive_absolute(_dir)
	if mk != OK and not DirAccess.dir_exists_absolute(_dir):
		_last_error = mk
		return mk
	_stamp = _unique_stamp()
	_part = 0
	return _open_part()


func is_open() -> bool:
	return _file != null


func close() -> void:
	if _file != null:
		_file.flush()
		_file.close()
		_file = null


func dir_path() -> String:
	return _dir


## Путь текущей части ("" — журнал не открыт).
func file_path() -> String:
	return _path if _file != null else ""


func filter() -> SecureStoreFilter:
	return _filter


## Число записанных строк за время жизни журнала.
func line_count() -> int:
	return _lines


func last_error() -> Error:
	return _last_error


## Записать событие. Секреты маскируются (`SecureStoreFilter`), длинная строка уходит в новую
## часть. false — журнал не открыт или запись не удалась.
func write(category: String, name: String, data: Dictionary = {}) -> bool:
	if _file == null:
		return false
	# Категория и имя события фильтруются до сборки записи: из них же собирается пометка
	# обрезанной записи.
	var safe_category := _filter.redact(category)
	var safe_name := _filter.redact(name)
	var record := {
		"t": _utc_now(),
		"up_ms": Time.get_ticks_msec(),
		"cat": safe_category,
		"ev": safe_name,
		"data": _filter.redact_value(data),
	}
	var line: String = _filter.redact(JSON.stringify(record, "", false))
	var bytes: int = line.to_utf8_buffer().size() + 1
	if _size > 0 and _size + bytes > max_file_bytes:
		_roll()
		if _file == null:
			return false
	if bytes > max_file_bytes:
		# Одна запись больше части — обрезается, чтобы предел объёма соблюдался.
		line = _filter.redact(JSON.stringify({"t": record["t"], "up_ms": record["up_ms"],
				"cat": safe_category, "ev": safe_name, "truncated_bytes": bytes}, "", false))
		bytes = line.to_utf8_buffer().size() + 1
	if not _file.store_line(line):
		_last_error = _file.get_error()
		return false
	_file.flush()
	_size += bytes
	_lines += 1
	return true


## Файлы журнала в каталоге, от старых к новым (полные пути).
func files() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(_dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.begins_with(FILE_PREFIX) and f.ends_with(FILE_SUFFIX):
			out.append(_dir + f)
	out.sort()
	return out


## Суммарный объём файлов журнала, байт.
func total_bytes() -> int:
	var total := 0
	for path in files():
		total += _file_size(path)
	return total


## Сохранить журнал одним файлом в `path` (выбран пользователем): все файлы каталога от
## старых к новым, перед каждым — строка-заголовок с его именем. `OK` или код ошибки.
func export_to(path: String) -> Error:
	if _file != null:
		_file.flush()
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		var err := FileAccess.get_open_error()
		return err if err != OK else ERR_FILE_CANT_OPEN
	for src in files():
		out.store_line("# --- %s ---" % src.get_file())
		var bytes := FileAccess.get_file_as_bytes(src)
		if not bytes.is_empty():
			out.store_buffer(bytes)
	out.flush()
	var io := out.get_error()
	out.close()
	return OK if io == OK or io == ERR_FILE_EOF else ERR_FILE_CANT_WRITE


## Имя файла для экспорта по умолчанию: `ovosch-log-<ГГГГММДД-ЧЧММСС>.log`.
static func export_file_name() -> String:
	var d := Time.get_datetime_dict_from_system(true)
	return "ovosch-log-%04d%02d%02d-%02d%02d%02d%s" % [d["year"], d["month"], d["day"],
			d["hour"], d["minute"], d["second"], FILE_SUFFIX]


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _open_part() -> Error:
	_part += 1
	_path = "%s%s%s-p%03d%s" % [_dir, FILE_PREFIX, _stamp, _part, FILE_SUFFIX]
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		_last_error = FileAccess.get_open_error()
		_path = ""
		return _last_error if _last_error != OK else ERR_FILE_CANT_OPEN
	_size = 0
	_last_error = OK
	_prune()
	return OK


func _roll() -> void:
	close()
	_open_part()


## Удалить старые файлы сверх предела числа и объёма (кроме текущей части): объём считается
## с запасом на целую текущую часть, чтобы она могла дорасти до `max_file_bytes`.
func _prune() -> void:
	var all := files()
	all.erase(_path)
	var sizes: Array[int] = []
	var total := 0
	for path in all:
		var size := _file_size(path)
		sizes.append(size)
		total += size
	var i := 0
	while i < all.size() and (all.size() - i + 1 > max_files or total + max_file_bytes > max_total_bytes):
		DirAccess.remove_absolute(all[i])
		total -= sizes[i]
		i += 1


func _unique_stamp() -> String:
	var unix_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var names: Array[String] = []
	for path in files():
		names.append(path.get_file())
	var stamp := _stamp_for(unix_ms)
	while _stamp_taken(names, stamp):
		unix_ms += 1
		stamp = _stamp_for(unix_ms)
	return stamp


static func _stamp_taken(names: Array[String], stamp: String) -> bool:
	for name in names:
		if name.begins_with(FILE_PREFIX + stamp):
			return true
	return false


static func _stamp_for(unix_ms: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix_ms / 1000)
	return "%04d%02d%02d-%02d%02d%02d-%03d" % [d["year"], d["month"], d["day"],
			d["hour"], d["minute"], d["second"], unix_ms % 1000]


static func _utc_now() -> String:
	var unix: float = Time.get_unix_time_from_system()
	return "%s.%03dZ" % [Time.get_datetime_string_from_unix_time(int(unix)), int(fmod(unix, 1.0) * 1000.0)]


static func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n
