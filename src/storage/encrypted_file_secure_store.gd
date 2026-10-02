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
## Весь словарь перезаписывается при каждом изменении; чтение — из памяти
## после загрузки в конструкторе.

const FILE_NAME: String = "secrets.bin"

var _dir_path: String
var _password: String
var _secrets: Dictionary = {}
var _loaded_ok: bool = true


func _init(dir_path: String = SecureStore.DEFAULT_DIR, password: String = "") -> void:
	_dir_path = dir_path if dir_path.ends_with("/") else dir_path + "/"
	_password = password if not password.is_empty() else SecureStore.derive_device_password()
	_load()


func file_path() -> String:
	return _dir_path + FILE_NAME


## false, если файл существовал, но не расшифровался (другой ключ или повреждение).
func loaded_ok() -> bool:
	return _loaded_ok


func set_secret(key: String, value: String) -> bool:
	if not SecureStore.is_valid_key(key) or value.is_empty():
		return false
	_secrets[key] = value
	return _persist()


func get_secret(key: String) -> String:
	return str(_secrets.get(key, ""))


func delete_secret(key: String) -> bool:
	if not _secrets.erase(key):
		return false
	_persist()
	return true


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


func _load() -> void:
	_secrets = {}
	_loaded_ok = true
	var path := file_path()
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open_encrypted_with_pass(path, FileAccess.READ, _password)
	if file == null:
		_loaded_ok = false
		push_warning("EncryptedFileSecureStore: не удалось расшифровать %s (%s); хранилище пустое" % [path, error_string(FileAccess.get_open_error())])
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
		push_warning("EncryptedFileSecureStore: содержимое %s не распознано; хранилище пустое" % path)


func _persist() -> bool:
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir_path))
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("EncryptedFileSecureStore: не удалось создать каталог %s (%s)" % [_dir_path, error_string(err)])
		return false
	var file := FileAccess.open_encrypted_with_pass(file_path(), FileAccess.WRITE, _password)
	if file == null:
		push_error("EncryptedFileSecureStore: не удалось записать %s (%s)" % [file_path(), error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(_secrets))
	file.close()
	return true
