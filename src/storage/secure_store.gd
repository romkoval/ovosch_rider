class_name SecureStore
extends RefCounted
## Интерфейс защищённого хранилища секретов (REQ-NFR-05, REQ-PRF-03).
##
## Единственная точка записи и чтения токенов и API-ключей в приложении.
## Ключи имеют вид `"<profile_id>/<service>/<item>"` (см. `key_for`), поэтому
## записи профиля A недоступны при чтении для профиля B, а удаление профиля —
## это `delete_profile_secrets(profile_id)` (REQ-PRF-03 крит. 1, 2).
##
## Реализации:
## - `MemorySecureStore` — только память; для тестов и dev-режима.
## - `EncryptedFileSecureStore` — переносимый зашифрованный файл в `user://`.
##   ВРЕМЕННОЕ решение до нативных модулей (Keychain на macOS/iOS, Android
##   Keystore, libsecret / Credential Manager); на магазинных платформах НЕ
##   считается выполнением REQ-NFR-05 крит. 1/3 — см. `create_default()`.
##
## Платформозависимые вызовы допустимы только в `src/storage/secure_store*`
## (REQ-NFR-06 крит. 1) — поэтому вывод ключа устройства живёт здесь.

const SERVICE_INTERVALS: String = "intervals"
const SERVICE_STRAVA: String = "strava"

const ITEM_API_KEY: String = "api_key"
const ITEM_ACCESS_TOKEN: String = "access_token"
const ITEM_REFRESH_TOKEN: String = "refresh_token"
const ITEM_EXPIRES_AT: String = "expires_at"

const KEY_SEPARATOR: String = "/"
## Каталог зашифрованного файла по умолчанию.
const DEFAULT_DIR: String = "user://secure/"
## Соль вывода ключа устройства (см. `derive_device_password`).
const DEVICE_KEY_SALT: String = "ovosch-rider/secure-store/v1"


## Платформы, где на файл секретов ставятся права 0600, а на его каталог — 0700.
const OWNER_ONLY_PLATFORMS: Array[String] = ["Linux", "macOS"]
## Права файла секретов: rw------- (0600).
const FILE_MODE_OWNER_ONLY: int = FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER
## Права каталога секретов: rwx------ (0700).
const DIR_MODE_OWNER_ONLY: int = FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER | FileAccess.UNIX_EXECUTE_OWNER


## Хранилище прочитано и доступно для записи. false — файл существует, но не расшифрован
## (другой ключ устройства, повреждение): чтение даёт пустые значения, запись отклоняется,
## чтобы не уничтожить секреты. Выход — `reset_store()` по явному действию пользователя.
func loaded_ok() -> bool:
	return true


## Код последней неудачной операции записи/удаления (`OK` — ошибок не было или последняя
## операция удалась). `ERR_FILE_CORRUPT` — хранилище не прочитано (`loaded_ok() == false`);
## `ERR_FILE_CANT_WRITE`/`ERR_FILE_CANT_OPEN`/… — сбой записи на диск.
func last_error() -> Error:
	return OK


## Стереть все секреты (и файл хранилища, если он есть) и начать с пустого; после этого
## `loaded_ok() == true`. Действие «сбросить привязки» в UI.
func reset_store() -> void:
	delete_prefix("")


## Сохранить секрет. Пустой ключ или пустое значение → false (пустое значение = удаление через `delete_secret`).
## false при сбое хранилища — причина в `last_error()`.
func set_secret(_key: String, _value: String) -> bool:
	push_error("SecureStore.set_secret: not implemented")
	return false


## Прочитать секрет; "" если его нет.
func get_secret(_key: String) -> String:
	push_error("SecureStore.get_secret: not implemented")
	return ""


## Удалить секрет; true, если он существовал.
func delete_secret(_key: String) -> bool:
	push_error("SecureStore.delete_secret: not implemented")
	return false


func has_secret(_key: String) -> bool:
	push_error("SecureStore.has_secret: not implemented")
	return false


## Все ключи, начинающиеся с `prefix` (пустой — все), отсортированные.
func list_keys(_prefix: String = "") -> Array[String]:
	push_error("SecureStore.list_keys: not implemented")
	return []


## Удалить все секреты с данным префиксом; возвращает число удалённых.
func delete_prefix(prefix: String) -> int:
	var removed: int = 0
	for key in list_keys(prefix):
		if delete_secret(key):
			removed += 1
	return removed


## Удалить все секреты профиля (каскад при удалении профиля, REQ-PRF-01 крит. 4).
func delete_profile_secrets(profile_id: String) -> int:
	if profile_id.is_empty():
		return 0
	return delete_prefix(profile_id + KEY_SEPARATOR)


## Удалить привязку одного сервиса у одного профиля (REQ-PRF-03 крит. 2).
func delete_service_secrets(profile_id: String, service: String) -> int:
	if profile_id.is_empty() or service.is_empty():
		return 0
	return delete_prefix(profile_id + KEY_SEPARATOR + service + KEY_SEPARATOR)


## Подписать хранилище на удаление профилей: `repo.profile_deleted` → `delete_profile_secrets`.
## Связанный метод, не лямбда (лямбда держала бы хранилище сильной ссылкой); повторный вызов — no-op.
func attach_to_profiles(repo: ProfileRepository) -> void:
	if not repo.profile_deleted.is_connected(_on_profile_deleted):
		repo.profile_deleted.connect(_on_profile_deleted)


## Отписаться от удаления профилей.
func detach_from_profiles(repo: ProfileRepository) -> void:
	if repo.profile_deleted.is_connected(_on_profile_deleted):
		repo.profile_deleted.disconnect(_on_profile_deleted)


func _on_profile_deleted(profile_id: String) -> void:
	delete_profile_secrets(profile_id)


## Ключ вида `"<profile_id>/<service>/<item>"`.
static func key_for(profile_id: String, service: String, item: String) -> String:
	return profile_id + KEY_SEPARATOR + service + KEY_SEPARATOR + item


## Ключ корректен: непустой, без пустых сегментов (`"a//b"`, `"/a"` недопустимы).
static func is_valid_key(key: String) -> bool:
	if key.is_empty():
		return false
	for segment in key.split(KEY_SEPARATOR):
		if segment.is_empty():
			return false
	return true


## Реализация по умолчанию для текущей сборки.
## СЕЙЧАС: `EncryptedFileSecureStore` с ключом из `derive_device_password()`.
## Это временная переносимая заглушка: ключ выводится из идентификатора
## устройства и соли, т.е. защищает от случайного чтения файла, но не от
## злоумышленника с доступом к устройству. До появления нативных модулей
## (Keychain/Keystore/libsecret) данная реализация НЕ закрывает REQ-NFR-05
## крит. 1 и 3 на магазинных платформах.
static func create_default(dir_path: String = DEFAULT_DIR) -> SecureStore:
	return EncryptedFileSecureStore.new(dir_path, derive_device_password())


## Переменная окружения (пустая строка — не задана). Единственное разрешённое место
## платформенного вызова для чтения окружения (REQ-NFR-06 крит. 1): используется
## `StravaConfig.load(..., SecureStore.read_env)` для `client_id`/`client_secret` в dev-сборках.
static func read_env(name: String) -> String:
	return OS.get_environment(name)


## Пароль файла из идентификатора устройства и соли (SHA-256, hex).
## `OS.get_unique_id()` может быть пустым на некоторых платформах — тогда
## используется только соль (ещё слабее; задокументировано как временное).
static func derive_device_password() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((OS.get_unique_id() + "|" + DEVICE_KEY_SALT).to_utf8_buffer())
	return ctx.finish().hex_encode()


## Права «только владелец» на файл (0600) или каталог (0700) секретов — на Linux и macOS
## (REQ-NFR-05; платформенная проверка допустима только здесь, REQ-NFR-06 крит. 1).
## На остальных платформах — `OK` без действий (там изоляцию даёт песочница/ACL).
static func restrict_to_owner(path: String, is_dir: bool) -> Error:
	if not (OS.get_name() in OWNER_ONLY_PLATFORMS):
		return OK
	var target := ProjectSettings.globalize_path(path).trim_suffix("/") if is_dir else ProjectSettings.globalize_path(path)
	var err := FileAccess.set_unix_permissions(target, DIR_MODE_OWNER_ONLY if is_dir else FILE_MODE_OWNER_ONLY)
	if err != OK:
		push_warning("SecureStore: не удалось ограничить права %s (%s)" % [target, error_string(err)])
	return err


## Применяются ли права «только владелец» на текущей платформе.
static func owner_only_permissions_supported() -> bool:
	return OS.get_name() in OWNER_ONLY_PLATFORMS
