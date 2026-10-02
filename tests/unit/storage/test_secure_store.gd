extends GutTest
## Тесты SecureStore и его реализаций (REQ-NFR-05 крит. 1, 2; REQ-PRF-03 крит. 1, 2, 3).

const PROFILE_A: String = "11111111-1111-4111-8111-111111111111"
const PROFILE_B: String = "22222222-2222-4222-8222-222222222222"
const TOKEN_A: String = "strava-access-token-AAA-very-secret-0123456789"
const TOKEN_B: String = "strava-access-token-BBB-other-secret-9876543210"
const PASSWORD: String = "test-password"

var _dir: String


func before_each() -> void:
	_dir = "user://test_secure_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]


func after_each() -> void:
	_remove_tree(ProjectSettings.globalize_path(_dir))
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir)))


static func _remove_tree(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var d := DirAccess.open(abs_path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)


## Обе реализации, прогоняемые через общие проверки.
func _stores() -> Array[SecureStore]:
	return [MemorySecureStore.new(), EncryptedFileSecureStore.new(_dir, PASSWORD)]


func _k(profile: String, service: String, item: String) -> String:
	return SecureStore.key_for(profile, service, item)


## Содержит ли файл подстроку (поиск по hex-представлению байтов, без зависимости от кодировки).
static func _file_contains(path: String, needle: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(path)
	return bytes.hex_encode().find(needle.to_utf8_buffer().hex_encode()) != -1


# ---------------------------------------------------------------------------
# Ключи
# ---------------------------------------------------------------------------

func test_key_for_builds_profile_service_item() -> void:
	assert_eq(_k(PROFILE_A, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN),
		PROFILE_A + "/strava/access_token")


func test_is_valid_key_rejects_empty_segments() -> void:
	assert_true(SecureStore.is_valid_key("a/b/c"))
	assert_true(SecureStore.is_valid_key("single"))
	assert_false(SecureStore.is_valid_key(""))
	assert_false(SecureStore.is_valid_key("/a/b"))
	assert_false(SecureStore.is_valid_key("a//b"))
	assert_false(SecureStore.is_valid_key("a/b/"))


func test_invalid_key_or_empty_value_is_rejected_by_both_implementations() -> void:
	for s in _stores():
		assert_false(s.set_secret("", "x"), "%s: пустой ключ" % s.get_class())
		assert_false(s.set_secret("a//b", "x"))
		assert_false(s.set_secret("a/b", ""), "пустое значение — не секрет")
		assert_eq(s.list_keys().size(), 0)


# ---------------------------------------------------------------------------
# Базовые операции (обе реализации)
# ---------------------------------------------------------------------------

func test_set_get_has_delete_roundtrip() -> void:
	for s in _stores():
		var key := _k(PROFILE_A, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY)
		assert_false(s.has_secret(key))
		assert_eq(s.get_secret(key), "", "нет секрета → пустая строка")
		assert_true(s.set_secret(key, "k-123"))
		assert_true(s.has_secret(key))
		assert_eq(s.get_secret(key), "k-123")
		assert_true(s.set_secret(key, "k-456"), "перезапись")
		assert_eq(s.get_secret(key), "k-456")
		assert_true(s.delete_secret(key))
		assert_false(s.delete_secret(key), "повторное удаление → false")
		assert_false(s.has_secret(key))
		assert_eq(s.get_secret(key), "")


func test_list_keys_filters_by_prefix_and_is_sorted() -> void:
	for s in _stores():
		s.set_secret(_k(PROFILE_B, "strava", "refresh_token"), "r")
		s.set_secret(_k(PROFILE_A, "strava", "access_token"), "a")
		s.set_secret(_k(PROFILE_A, "intervals", "api_key"), "i")
		assert_eq(s.list_keys(PROFILE_A + "/"), [PROFILE_A + "/intervals/api_key", PROFILE_A + "/strava/access_token"])
		assert_eq(s.list_keys().size(), 3)
		assert_eq(s.list_keys("zzz").size(), 0)


func test_secrets_of_two_profiles_are_isolated() -> void:
	for s in _stores():
		s.set_secret(_k(PROFILE_A, "strava", "access_token"), TOKEN_A)
		s.set_secret(_k(PROFILE_B, "strava", "access_token"), TOKEN_B)
		assert_eq(s.get_secret(_k(PROFILE_A, "strava", "access_token")), TOKEN_A)
		assert_eq(s.get_secret(_k(PROFILE_B, "strava", "access_token")), TOKEN_B, "REQ-PRF-03 крит. 1")
		assert_eq(s.get_secret(_k(PROFILE_B, "intervals", "api_key")), "", "чужой/отсутствующий ключ не виден")


func test_delete_service_secrets_removes_only_that_profile_and_service() -> void:
	for s in _stores():
		s.set_secret(_k(PROFILE_A, "strava", "access_token"), "a1")
		s.set_secret(_k(PROFILE_A, "strava", "refresh_token"), "a2")
		s.set_secret(_k(PROFILE_A, "intervals", "api_key"), "a3")
		s.set_secret(_k(PROFILE_B, "strava", "access_token"), "b1")
		assert_eq(s.delete_service_secrets(PROFILE_A, "strava"), 2, "REQ-PRF-03 крит. 2")
		assert_false(s.has_secret(_k(PROFILE_A, "strava", "access_token")))
		assert_false(s.has_secret(_k(PROFILE_A, "strava", "refresh_token")))
		assert_eq(s.get_secret(_k(PROFILE_A, "intervals", "api_key")), "a3", "другой сервис не тронут")
		assert_eq(s.get_secret(_k(PROFILE_B, "strava", "access_token")), "b1", "другой профиль не тронут")


func test_delete_profile_secrets_removes_everything_of_that_profile_only() -> void:
	for s in _stores():
		s.set_secret(_k(PROFILE_A, "strava", "access_token"), "a1")
		s.set_secret(_k(PROFILE_A, "intervals", "api_key"), "a2")
		s.set_secret(_k(PROFILE_B, "strava", "access_token"), "b1")
		assert_eq(s.delete_profile_secrets(PROFILE_A), 2)
		assert_eq(s.list_keys(PROFILE_A + "/").size(), 0)
		assert_eq(s.list_keys(), [PROFILE_B + "/strava/access_token"])
		assert_eq(s.delete_profile_secrets(""), 0, "пустой id ничего не удаляет")
		assert_eq(s.delete_profile_secrets(PROFILE_A), 0)


func test_delete_prefix_returns_count() -> void:
	var s := MemorySecureStore.new()
	s.set_secret("p/x/1", "1")
	s.set_secret("p/x/2", "2")
	s.set_secret("q/x/1", "3")
	assert_eq(s.delete_prefix("p/"), 2)
	assert_eq(s.size(), 1)
	assert_eq(s.delete_prefix("none"), 0)


# ---------------------------------------------------------------------------
# Зашифрованный файл
# ---------------------------------------------------------------------------

func test_encrypted_store_persists_across_instances_with_same_password() -> void:
	var s := EncryptedFileSecureStore.new(_dir, PASSWORD)
	assert_true(s.set_secret(_k(PROFILE_A, "strava", "access_token"), TOKEN_A))
	assert_true(FileAccess.file_exists(s.file_path()))
	var again := EncryptedFileSecureStore.new(_dir, PASSWORD)
	assert_true(again.loaded_ok())
	assert_eq(again.get_secret(_k(PROFILE_A, "strava", "access_token")), TOKEN_A)
	again.delete_secret(_k(PROFILE_A, "strava", "access_token"))
	assert_false(EncryptedFileSecureStore.new(_dir, PASSWORD).has_secret(_k(PROFILE_A, "strava", "access_token")))


func test_encrypted_store_with_wrong_password_is_empty_and_does_not_crash() -> void:
	var s := EncryptedFileSecureStore.new(_dir, PASSWORD)
	s.set_secret(_k(PROFILE_A, "strava", "access_token"), TOKEN_A)
	var wrong := EncryptedFileSecureStore.new(_dir, "other-password")
	assert_engine_error("ERR_FILE_CORRUPT", "ядро сообщает о неверном ключе — ожидаемо")
	assert_push_warning("не удалось расшифровать")
	assert_false(wrong.loaded_ok())
	assert_eq(wrong.get_secret(_k(PROFILE_A, "strava", "access_token")), "")
	assert_eq(wrong.list_keys().size(), 0)
	assert_false(wrong.set_secret(_k(PROFILE_B, "strava", "access_token"), TOKEN_B), "запись из нерасшифрованного экземпляра отклонена")
	assert_push_warning("refusing to overwrite")
	assert_false(wrong.delete_secret(_k(PROFILE_A, "strava", "access_token")))
	assert_push_warning("refusing to overwrite")
	assert_eq(EncryptedFileSecureStore.new(_dir, PASSWORD).get_secret(_k(PROFILE_A, "strava", "access_token")), TOKEN_A, "исходные секреты целы")
	wrong.reset_store()
	assert_true(wrong.loaded_ok())
	assert_true(wrong.set_secret(_k(PROFILE_B, "strava", "access_token"), TOKEN_B), "после явного сброса запись возможна")
	assert_eq(EncryptedFileSecureStore.new(_dir, "other-password").get_secret(_k(PROFILE_B, "strava", "access_token")), TOKEN_B)


func test_encrypted_file_does_not_contain_plaintext_secret_or_key() -> void:
	var s := EncryptedFileSecureStore.new(_dir, PASSWORD)
	var key := _k(PROFILE_A, "strava", "access_token")
	s.set_secret(key, TOKEN_A)
	assert_false(_file_contains(s.file_path(), TOKEN_A), "REQ-NFR-05 крит. 2: токена нет в открытом виде")
	assert_false(_file_contains(s.file_path(), PROFILE_A), "идентификатор профиля тоже скрыт")
	assert_false(_file_contains(s.file_path(), "access_token"))
	# Контроль метода поиска: в открытом файле тот же токен находится.
	var plain_path := _dir + "plain.json"
	var f := FileAccess.open(plain_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({key: TOKEN_A}))
	f.close()
	assert_true(_file_contains(plain_path, TOKEN_A), "контроль: поиск находит открытый текст")


func test_memory_store_writes_no_files() -> void:
	var s := MemorySecureStore.new()
	s.set_secret(_k(PROFILE_A, "strava", "access_token"), TOKEN_A)
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir)))
	assert_eq(s.size(), 1)


func test_profile_file_never_contains_secret_values() -> void:
	# REQ-PRF-03 крит. 3: секреты не попадают в файлы данных профиля.
	var repo := ProfileRepository.new(_dir + "profiles/")
	var p := repo.create("Даша")
	var store := EncryptedFileSecureStore.new(_dir + "secure/", PASSWORD)
	store.set_secret(_k(p.id, "intervals", "api_key"), TOKEN_A)
	p.ftp_w = 210
	repo.save(p)
	assert_false(_file_contains(repo.file_path(), TOKEN_A))
	assert_false(_file_contains(store.file_path(), TOKEN_A))
	assert_true(_file_contains(repo.file_path(), "Даша"), "контроль: файл профилей читаем")


func test_create_default_returns_encrypted_file_store_with_device_password() -> void:
	var s := SecureStore.create_default(_dir)
	assert_true(s is EncryptedFileSecureStore)
	assert_true(s.set_secret(_k(PROFILE_A, "strava", "access_token"), TOKEN_A))
	assert_eq(SecureStore.create_default(_dir).get_secret(_k(PROFILE_A, "strava", "access_token")), TOKEN_A)
	assert_false(_file_contains((s as EncryptedFileSecureStore).file_path(), TOKEN_A))


func test_derive_device_password_is_stable_sha256_hex() -> void:
	var a := SecureStore.derive_device_password()
	assert_eq(a.length(), 64)
	assert_eq(a, SecureStore.derive_device_password())
	assert_not_null(RegEx.create_from_string("^[0-9a-f]{64}$").search(a))


# ---------------------------------------------------------------------------
# Каскад с профилями (REQ-PRF-01 крит. 4)
# ---------------------------------------------------------------------------

func test_attach_to_profiles_deletes_secrets_when_profile_is_deleted() -> void:
	var repo := ProfileRepository.new(_dir + "profiles/")
	var a := repo.create("Алиса")
	var b := repo.create("Боб")
	var mem := MemorySecureStore.new()
	var enc := EncryptedFileSecureStore.new(_dir, PASSWORD)
	for s in [mem, enc]:
		(s as SecureStore).attach_to_profiles(repo)
		(s as SecureStore).set_secret(_k(a.id, "strava", "access_token"), TOKEN_A)
		(s as SecureStore).set_secret(_k(b.id, "strava", "access_token"), TOKEN_B)
	assert_eq(repo.delete(b.id), "")
	assert_eq(mem.get_secret(_k(b.id, "strava", "access_token")), "", "секреты удалённого профиля стёрты")
	assert_eq(mem.get_secret(_k(a.id, "strava", "access_token")), TOKEN_A, "секреты оставшегося профиля целы")
	assert_eq(enc.get_secret(_k(b.id, "strava", "access_token")), "")
	assert_eq(enc.get_secret(_k(a.id, "strava", "access_token")), TOKEN_A)
	assert_eq(EncryptedFileSecureStore.new(_dir, PASSWORD).list_keys(b.id + "/").size(), 0, "и на диске тоже")
	assert_eq(repo.delete(a.id), ProfileRepository.ERR_LAST_PROFILE)
	assert_eq(mem.get_secret(_k(a.id, "strava", "access_token")), TOKEN_A, "отказ удаления не трогает секреты")
