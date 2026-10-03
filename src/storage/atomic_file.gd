class_name AtomicFile
extends RefCounted
## Атомарная запись файла: данные пишутся во временный `<path>.tmp`, ошибка записи
## проверяется до переименования, затем `rename` поверх целевого файла.
##
## Гарантия: при любой ошибке (не открылся временный файл, запись не удалась, не удалось
## переименовать) целевой файл остаётся прежним, временный удаляется. Сбой посреди записи
## (падение приложения, отключение питания) оставляет либо старый, либо новый файл целиком.
##
## Используется всеми JSON/бинарными хранилищами в `user://`: профили, заезды, очередь
## выгрузки Strava, кэш плана, зашифрованное хранилище секретов.

const TMP_SUFFIX: String = ".tmp"

## Только для тестов: имитация ошибки записи («диск полон») для путей с этим префиксом
## (абсолютных или `user://`, как их передаёт вызывающий). Пусто — выключено. Тест обязан
## вернуть "" в `after_each`.
static var simulate_write_error_prefix: String = ""


## Записать текст (UTF-8). `OK` или код ошибки; при ошибке целевой файл не тронут.
static func write_text(path: String, text: String) -> Error:
	return write_bytes(path, text.to_utf8_buffer())


## Записать байты. `OK` или код ошибки; при ошибке целевой файл не тронут.
static func write_bytes(path: String, bytes: PackedByteArray) -> Error:
	var tmp := tmp_path(path)
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		var open_err := FileAccess.get_open_error()
		push_error("AtomicFile: не удалось открыть временный файл %s (%s)" % [tmp, error_string(open_err)])
		return open_err if open_err != OK else ERR_FILE_CANT_OPEN
	return commit(file, file.store_buffer(bytes), path)


## Завершить запись во временный файл, открытый вызывающим (например, зашифрованный
## `FileAccess.open_encrypted_with_pass(tmp_path(path), WRITE, …)`): проверить ошибку записи,
## закрыть, переименовать поверх `path`. `stored` — результат `store_*`. При ошибке
## временный файл удаляется, `path` не трогается.
static func commit(file: FileAccess, stored: bool, path: String) -> Error:
	var tmp := tmp_path(path)
	file.flush()
	var io_err := file.get_error()
	file.close()
	if _simulated_failure(path):
		stored = false
	if not stored or (io_err != OK and io_err != ERR_FILE_EOF):
		_remove(tmp)
		push_error("AtomicFile: не удалось записать %s (%s), прежний файл сохранён" % [tmp, error_string(io_err if io_err != OK else ERR_FILE_CANT_WRITE)])
		return ERR_FILE_CANT_WRITE
	var rename_err := DirAccess.rename_absolute(tmp, path)
	if rename_err != OK:
		_remove(tmp)
		push_error("AtomicFile: не удалось переименовать %s → %s (%s)" % [tmp, path, error_string(rename_err)])
		return rename_err
	return OK


## Путь временного файла для `path`.
static func tmp_path(path: String) -> String:
	return path + TMP_SUFFIX


static func _simulated_failure(path: String) -> bool:
	return not simulate_write_error_prefix.is_empty() and path.begins_with(simulate_write_error_prefix)


static func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
