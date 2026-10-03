class_name EncryptedFileSecureStore
extends SecureStore
## Секреты в одном зашифрованном файле `<dir>/secrets.bin`
## (`FileAccess.open_encrypted_with_pass`, AES-256 из ядра Godot).
##
## ВРЕМЕННАЯ переносимая реализация до нативных модулей (Keychain / Keystore /
## libsecret). Стойкость определяется паролем: по умолчанию его выводит
## `SecureStore.derive_device_password()` из идентификатора устройства и соли,
## что защищает от чтения файла «как есть», но не от атакующего с доступом к
## устройству. На магазинных платформах НЕ считается выполнением REQ-NFR-05
## крит. 1/3; критерий 2 (секреты не лежат в `user://` открытым текстом) выполняется.
##
## Неверный пароль или повреждённый файл: ядро сообщает ошибку (ERR_FILE_CORRUPT /
## ERR_FILE_UNRECOGNIZED), хранилище даёт `loaded_ok() == false`, пустой список
## секретов и БЛОКИРУЕТ запись — иначе один сбой пароля уничтожил бы все токены.
## Явный сброс — `reset_store()` (для действия «сбросить привязки» в UI).
## Отсутствие файла — не ошибка: пустое хранилище, `loaded_ok() == true`.
##
## Весь словарь перезаписывается при каждом изменении атомарно: зашифрованный временный
## `secrets.bin.tmp` → проверка записи → rename (`AtomicFile`), поэтому сбой посреди записи
## не портит прежний файл. Неудачная запись откатывает изменение в памяти, `set_secret`/
## `delete_secret` возвращают false, код — в `last_error()`. Чтение — из памяти после загрузки
## в конструкторе.
##
## Права: на Linux и macOS файл — 0600, каталог — 0700 (`SecureStore.restrict_to_owner`).

const FILE_NAME: String = "secrets.bin"

var _dir_path: String
var _password: String
var _secrets: Dictionary = {}
var _loaded_ok: bool = true
var _last_error: Error = OK


func _init(dir_path: String = SecureStore.DEFAULT_DIR, password: String = "") -> void:
	_dir_path = dir_path if dir_path.ends_with("/") else dir_path + "/"
	_password = password if not password.is_empty() else SecureStore.derive_device_password()
	_load()


func file_path() -> String:
	return _dir_path + FILE_NAME


## false, если файл существовал, но не расшифровался (другой ключ или повреждение).
## В этом состоянии `set_secret`/`delete_secret` возвращают false и файл не трогают.
func loaded_ok() -> bool:
	return _loaded_ok


func last_error() -> Error:
	return _last_error


## Стереть файл хранилища и начать с пустого (`loaded_ok()` снова true).
func reset_store() -> void:
	_secrets = {}
	_loaded_ok = true
	_last_error = OK
	var path := file_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func set_secret(key: String, value: String) -> bool:
	if not SecureStore.is_valid_key(key) or value.is_empty():
		return false
	if not _refuse_if_not_loaded():
		return false
	var had := _secrets.has(key)
	var previous: Variant = _secrets.get(key)
	_secrets[key] = value
	if _persist():
		return true
	# Память должна совпадать с диском: неудачная запись откатывается.
	if had:
		_secrets[key] = previous
	else:
		_secrets.erase(key)
	return false


func get_secret(key: String) -> String:
	return str(_secrets.get(key, ""))


## true — секрет был и удалён с диска; false — его не было, хранилище не прочитано или
## запись не удалась (тогда секрет остаётся, код в `last_error()`).
func delete_secret(key: String) -> bool:
	if not _refuse_if_not_loaded() or not _secrets.has(key):
		return false
	var previous: Variant = _secrets[key]
	_secrets.erase(key)
	if _persist():
		return true
	_secrets[key] = previous
	return false


func has_secret(key: String) -> bool:
	return _secrets.has(key)


func list_keys(prefix: String = "") -> Array[String]:
	var out: Array[String] = []
	for k in _secrets.keys():
		var key: String = k
		if prefix.is_empty() or key.begins_with(prefix):
			out.append(key)
	out.sort()
	return out


## true — писать можно; false — файл не расшифрован, запись отклонена (предупреждение).
func _refuse_if_not_loaded() -> bool:
	if _loaded_ok:
		return true
	_last_error = ERR_FILE_CORRUPT
	push_warning("EncryptedFileSecureStore: secure store not loaded, refusing to overwrite %s (см. reset_store)" % file_path())
	return false


func _load() -> void:
	_secrets = {}
	_loaded_ok = true
	var path := file_path()
	if not FileAccess.file_exists(path):
		return
	# Файлы прежних версий могли остаться с правами по umask — ужесточаем при чтении.
	SecureStore.restrict_to_owner(_dir_path, true)
	SecureStore.restrict_to_owner(path, false)
	var file := FileAccess.open_encrypted_with_pass(path, FileAccess.READ, _password)
	if file == null:
		_loaded_ok = false
		push_warning("EncryptedFileSecureStore: не удалось расшифровать %s (%s); хранилище пустое, запись заблокирована" % [path, error_string(FileAccess.get_open_error())])
		return
	var json := JSON.new()
	var parse_err := json.parse(file.get_as_text())
	file.close()
	if parse_err == OK and json.data is Dictionary:
		var parsed: Dictionary = json.data
		for k in parsed.keys():
			_secrets[str(k)] = str(parsed[k])
	else:
		_loaded_ok = false
		push_warning("EncryptedFileSecureStore: не удалось расшифровать %s (содержимое не распознано); хранилище пустое, запись заблокирована" % path)


## Атомарная запись: зашифрованный временный файл (права 0600 сразу после создания) →
## проверка записи → rename. Каталог — 0700. Результат и код — в `_last_error`.
func _persist() -> bool:
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir_path))
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("EncryptedFileSecureStore: не удалось создать каталог %s (%s)" % [_dir_path, error_string(err)])
		_last_error = err
		return false
	SecureStore.restrict_to_owner(_dir_path, true)
	var path := file_path()
	var tmp := AtomicFile.tmp_path(path)
	var file := FileAccess.open_encrypted_with_pass(tmp, FileAccess.WRITE, _password)
	if file == null:
		var open_err := FileAccess.get_open_error()
		push_error("EncryptedFileSecureStore: не удалось записать %s (%s)" % [tmp, error_string(open_err)])
		_last_error = open_err if open_err != OK else ERR_FILE_CANT_OPEN
		return false
	SecureStore.restrict_to_owner(tmp, false)
	_last_error = AtomicFile.commit(file, file.store_string(JSON.stringify(_secrets)), path)
	if _last_error != OK:
		return false
	SecureStore.restrict_to_owner(path, false)
	return true
