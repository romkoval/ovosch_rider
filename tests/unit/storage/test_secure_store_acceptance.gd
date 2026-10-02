extends GutTest
## Независимые приёмочные тесты защищённого хранилища (тестировщик, T-010).
## Покрытие: REQ-PRF-03 крит. 1, 2, 3; REQ-NFR-05 крит. 1, 2; каскад с REQ-PRF-01 крит. 4
## (часть «токены удаляются», остальное — n/a до T-011).
##
## Заявленная семантика: ключ `"<profile_id>/<service>/<item>"` (`SecureStore.key_for`);
## `secrets.bin` зашифрован, `loaded_ok()==false` при неверном пароле;
## `SecureStore.attach_to_profiles(repo)` → удаление профиля стирает его ключи.

const PID_A: String = "aaaaaaaa-0000-4000-8000-000000000001"
const PID_B: String = "aaaaaaaa-0000-4000-8000-000000000002"
const TOKENS: Array[String] = [
	"tok-ACCESS-7f3a9c1e2b4d6f8a0c2e4b6d8f0a2c4e",
	"tok-REFRESH-19b8e7d6c5a4f3e2d1c0b9a8f7e6d5c4",
	"icu-APIKEY-zz9yy8xx7ww6vv5uu4tt3ss2rr1qq0pp",
]
const PASSWORD: String = "acceptance-pass"

var _dir: String


func before_each() -> void:
	_dir = "user://test_acc_secure_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]


func after_each() -> void:
	_remove_tree(ProjectSettings.globalize_path(_dir))
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir)), "временный каталог удалён")


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


func _k(pid: String, service: String, item: String) -> String:
	return SecureStore.key_for(pid, service, item)


func _stores() -> Array[SecureStore]:
	return [MemorySecureStore.new(), EncryptedFileSecureStore.new(_dir + "enc/", PASSWORD)]


## Поиск подстроки по hex-представлению байтов файла (без зависимости от кодировки).
static func _file_contains(path: String, needle: String) -> bool:
	return FileAccess.get_file_as_bytes(path).hex_encode().find(needle.to_utf8_buffer().hex_encode()) != -1


## Все файлы под каталогом (рекурсивно), пути res/user.
static func _all_files(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			_all_files(full, out)
		else:
			out.append(full)
		name = d.get_next()
	d.list_dir_end()


# ===========================================================================
# REQ-PRF-03 крит. 1 — ключи включают id профиля; A недоступен для B
# ===========================================================================

func test_req_prf_03_c1_key_for_contains_profile_id_service_item() -> void:
	var key := _k(PID_A, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY)
	assert_eq(key, PID_A + "/intervals/api_key")
	assert_true(key.begins_with(PID_A + SecureStore.KEY_SEPARATOR))
	assert_eq(_k(PID_B, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_REFRESH_TOKEN), PID_B + "/strava/refresh_token")
	assert_true(SecureStore.is_valid_key(key))


func test_req_prf_03_c1_profile_a_secrets_not_readable_through_profile_b_keys() -> void:
	for s in _stores():
		var cls: String = s.get_script().get_global_name()
		assert_true(s.set_secret(_k(PID_A, "intervals", "api_key"), TOKENS[2]))
		assert_true(s.set_secret(_k(PID_A, "strava", "access_token"), TOKENS[0]))
		assert_true(s.set_secret(_k(PID_A, "strava", "refresh_token"), TOKENS[1]))
		for item in ["api_key", "access_token", "refresh_token", "expires_at"]:
			for service in ["intervals", "strava"]:
				assert_eq(s.get_secret(_k(PID_B, service, item)), "", "%s: B не видит %s/%s" % [cls, service, item])
				assert_false(s.has_secret(_k(PID_B, service, item)))
		assert_eq(s.list_keys(PID_B + "/"), [], "%s: у B нет ключей" % cls)
		assert_eq(s.list_keys(PID_A + "/").size(), 3)
		assert_eq(s.get_secret(_k(PID_A, "strava", "access_token")), TOKENS[0])


func test_req_prf_03_c1_same_item_for_two_profiles_holds_distinct_values() -> void:
	for s in _stores():
		s.set_secret(_k(PID_A, "strava", "access_token"), TOKENS[0])
		s.set_secret(_k(PID_B, "strava", "access_token"), TOKENS[1])
		assert_eq(s.get_secret(_k(PID_A, "strava", "access_token")), TOKENS[0])
		assert_eq(s.get_secret(_k(PID_B, "strava", "access_token")), TOKENS[1])
		s.set_secret(_k(PID_A, "strava", "access_token"), "new-A")
		assert_eq(s.get_secret(_k(PID_B, "strava", "access_token")), TOKENS[1], "перезапись A не трогает B")


func test_req_prf_03_c1_profile_id_prefix_collision_is_not_a_match() -> void:
	# «abc» и «abcd»: префикс «abc/» не должен задевать «abcd/...».
	for s in _stores():
		s.set_secret(_k("abc", "strava", "access_token"), "short")
		s.set_secret(_k("abcd", "strava", "access_token"), "long")
		assert_eq(s.list_keys("abc/"), ["abc/strava/access_token"])
		assert_eq(s.delete_profile_secrets("abc"), 1)
		assert_eq(s.get_secret(_k("abcd", "strava", "access_token")), "long")


# ===========================================================================
# REQ-PRF-03 крит. 2 — удаление привязки: только этот профиль и этот сервис
# ===========================================================================

func test_req_prf_03_c2_delete_service_secrets_scope() -> void:
	for s in _stores():
		var cls: String = s.get_script().get_global_name()
		s.set_secret(_k(PID_A, "strava", "access_token"), "a-s-1")
		s.set_secret(_k(PID_A, "strava", "refresh_token"), "a-s-2")
		s.set_secret(_k(PID_A, "strava", "expires_at"), "1800000000")
		s.set_secret(_k(PID_A, "intervals", "api_key"), "a-i-1")
		s.set_secret(_k(PID_B, "strava", "access_token"), "b-s-1")
		s.set_secret(_k(PID_B, "intervals", "api_key"), "b-i-1")
		assert_eq(s.delete_service_secrets(PID_A, "strava"), 3, cls)
		assert_eq(s.list_keys(PID_A + "/strava/"), [])
		assert_eq(s.get_secret(_k(PID_A, "intervals", "api_key")), "a-i-1", "%s: другой сервис A цел" % cls)
		assert_eq(s.get_secret(_k(PID_B, "strava", "access_token")), "b-s-1", "%s: тот же сервис B цел" % cls)
		assert_eq(s.get_secret(_k(PID_B, "intervals", "api_key")), "b-i-1")
		assert_eq(s.list_keys().size(), 3)
		assert_eq(s.delete_service_secrets(PID_A, "strava"), 0, "повторное удаление — 0")
		assert_eq(s.delete_service_secrets("", "strava"), 0)
		assert_eq(s.delete_service_secrets(PID_B, ""), 0, "пустой сервис не удаляет всё подряд")
		assert_eq(s.list_keys().size(), 3)


func test_req_prf_03_c2_delete_profile_secrets_of_a_does_not_touch_b_and_persists() -> void:
	var enc := EncryptedFileSecureStore.new(_dir + "enc/", PASSWORD)
	enc.set_secret(_k(PID_A, "strava", "access_token"), TOKENS[0])
	enc.set_secret(_k(PID_A, "intervals", "api_key"), TOKENS[2])
	enc.set_secret(_k(PID_B, "strava", "access_token"), TOKENS[1])
	assert_eq(enc.delete_profile_secrets(PID_A), 2)
	var again := EncryptedFileSecureStore.new(_dir + "enc/", PASSWORD)
	assert_true(again.loaded_ok())
	assert_eq(again.list_keys(), [PID_B + "/strava/access_token"])
	assert_eq(again.get_secret(_k(PID_B, "strava", "access_token")), TOKENS[1])


func test_req_prf_03_c2_service_name_with_separator_is_accepted_and_nested_under_parent() -> void:
	# Документируем поведение: разделитель в имени сервиса делает ключ вложенным;
	# удаление «родительского» сервиса захватывает и вложенный.
	var s := MemorySecureStore.new()
	assert_true(s.set_secret(_k(PID_A, "strava/legacy", "access_token"), "nested"))
	assert_true(s.set_secret(_k(PID_A, "strava", "access_token"), "plain"))
	assert_eq(s.list_keys(PID_A + "/strava/").size(), 2)
	assert_eq(s.delete_service_secrets(PID_A, "strava"), 2, "вложенный сервис удаляется вместе с родительским")


# ===========================================================================
# Базовые операции и границы ключей/значений
# ===========================================================================

func test_req_prf_03_empty_key_and_invalid_segments_rejected_without_side_effects() -> void:
	for s in _stores():
		var cls: String = s.get_script().get_global_name()
		assert_false(s.set_secret("", "v"), "%s: пустой ключ" % cls)
		assert_false(s.set_secret("/", "v"))
		assert_false(s.set_secret("a//b", "v"))
		assert_false(s.set_secret("/a/b/c", "v"))
		assert_false(s.set_secret("a/b/c/", "v"))
		assert_false(s.set_secret(SecureStore.key_for("", "strava", "x"), "v"), "key_for с пустым profile_id даёт невалидный ключ")
		assert_eq(s.list_keys(), [])
		assert_eq(s.get_secret(""), "")
		assert_false(s.has_secret(""))
		assert_false(s.delete_secret(""))
	assert_false(FileAccess.file_exists(_dir + "enc/" + EncryptedFileSecureStore.FILE_NAME), "отклонённые записи не создают файл")


func test_req_prf_03_empty_value_is_rejected_and_keeps_existing_secret() -> void:
	for s in _stores():
		var key := _k(PID_A, "strava", "access_token")
		assert_false(s.set_secret(key, ""), "пустое значение до записи")
		assert_false(s.has_secret(key))
		assert_true(s.set_secret(key, TOKENS[0]))
		assert_false(s.set_secret(key, ""), "пустое значение — не способ удаления")
		assert_eq(s.get_secret(key), TOKENS[0], "существующий секрет не затёрт пустым")
		assert_true(s.delete_secret(key), "удаление — явной операцией")
		assert_eq(s.get_secret(key), "")


func test_req_prf_03_overwrite_keeps_single_key_and_returns_latest_after_reload() -> void:
	var enc := EncryptedFileSecureStore.new(_dir + "enc/", PASSWORD)
	var key := _k(PID_A, "strava", "access_token")
	assert_true(enc.set_secret(key, "v1"))
	assert_true(enc.set_secret(key, "v2"))
	assert_true(enc.set_secret(key, "v3"))
	assert_eq(enc.list_keys().size(), 1)
	assert_eq(enc.get_secret(key), "v3")
	assert_eq(EncryptedFileSecureStore.new(_dir + "enc/", PASSWORD).get_secret(key), "v3")
	assert_false(_file_contains(enc.file_path(), "v1"), "старое значение не остаётся в файле открытым текстом")


func test_req_prf_03_get_unknown_returns_empty_and_delete_unknown_false() -> void:
	for s in _stores():
		assert_eq(s.get_secret(_k(PID_A, "strava", "nope")), "")
		assert_false(s.delete_secret(_k(PID_A, "strava", "nope")))
		assert_eq(s.delete_prefix("nothing/"), 0)
		assert_eq(s.list_keys("nothing/"), [])


func test_req_prf_03_values_with_unicode_and_json_special_chars_roundtrip() -> void:
	var weird := "тока\"н {\\} \n\t ✓ 🚴 /slash/ ="
	for s in _stores():
		var key := _k(PID_A, "strava", "access_token")
		assert_true(s.set_secret(key, weird))
		assert_eq(s.get_secret(key), weird)
	assert_eq(EncryptedFileSecureStore.new(_dir + "enc/", PASSWORD).get_secret(_k(PID_A, "strava", "access_token")), weird)


func test_req_prf_03_list_keys_sorted_and_prefix_filtered() -> void:
	for s in _stores():
		s.set_secret("z/strava/a", "1")
		s.set_secret("a/strava/z", "2")
		s.set_secret("a/intervals/api_key", "3")
		s.set_secret("m/x/y", "4")
		assert_eq(s.list_keys(), ["a/intervals/api_key", "a/strava/z", "m/x/y", "z/strava/a"])
		assert_eq(s.list_keys("a/"), ["a/intervals/api_key", "a/strava/z"])
		assert_eq(s.list_keys("a/strava/"), ["a/strava/z"])


# ===========================================================================
# REQ-PRF-03 крит. 3 / REQ-NFR-05 крит. 2 — токены не лежат в файлах `user://`
# ===========================================================================

func test_req_prf_03_c3_three_tokens_absent_from_every_file_after_profile_and_secret_save() -> void:
	var repo := ProfileRepository.new(_dir + "profiles/")
	var p := repo.create("Даша")
	var enc := EncryptedFileSecureStore.new(_dir + "secure/", PASSWORD)
	enc.set_secret(_k(p.id, "strava", "access_token"), TOKENS[0])
	enc.set_secret(_k(p.id, "strava", "refresh_token"), TOKENS[1])
	enc.set_secret(_k(p.id, "intervals", "api_key"), TOKENS[2])
	p.ftp_w = 222
	assert_eq(repo.save(p), [])
	var files: Array[String] = []
	_all_files(_dir, files)
	assert_eq(files.size(), 2, "ровно два файла: profiles.json и secrets.bin; факт %s" % str(files))
	for f in files:
		for t in TOKENS:
			assert_false(_file_contains(f, t), "файл %s содержит токен %s" % [f, t.substr(0, 12)])
		assert_false(_file_contains(f, p.id) and f.ends_with(EncryptedFileSecureStore.FILE_NAME), "id профиля в secrets.bin скрыт")
	assert_true(_file_contains(repo.file_path(), "Даша"), "контроль метода: имя в profiles.json находится")
	assert_true(_file_contains(repo.file_path(), p.id), "контроль метода: id в profiles.json находится")


func test_req_prf_03_c3_profiles_json_has_no_secret_fields_even_if_profile_edited_many_times() -> void:
	var repo := ProfileRepository.new(_dir + "profiles/")
	var p := repo.create("A")
	var mem := MemorySecureStore.new()
	mem.set_secret(_k(p.id, "intervals", "api_key"), TOKENS[2])
	for i in 5:
		p.ftp_w = 200 + i
		repo.save(p)
	var text := FileAccess.get_file_as_string(repo.file_path())
	for t in TOKENS:
		assert_false(text.contains(t))
	for field in ["access_token", "refresh_token", "api_key", "token", "secret"]:
		assert_false(text.to_lower().contains(field), "поле «%s» в файле профилей" % field)


func test_req_nfr_05_c2_memory_store_writes_nothing_to_user_dir() -> void:
	# Самодостаточно: смотрим только в собственный временный каталог теста.
	# Профиль сохраняется в <_dir>/profiles/, секреты — только в память; после этого
	# в каталоге ровно один файл (profiles.json), в нём нет токенов, каталога secure/ нет.
	var repo := ProfileRepository.new(_dir + "profiles/")
	var p := repo.create("Mem")
	var mem := MemorySecureStore.new()
	for i in 50:
		assert_true(mem.set_secret(_k(p.id, "strava", "t%d" % i), TOKENS[i % 3]))
	assert_eq(mem.size(), 50)
	p.ftp_w = 210
	assert_eq(repo.save(p), [])
	var files: Array[String] = []
	_all_files(_dir, files)
	assert_eq(files, [_dir + "profiles/profiles.json"], "в каталоге данных только файл профилей; факт: %s" % str(files))
	for f in files:
		for t in TOKENS:
			assert_false(_file_contains(f, t), "файл %s содержит токен" % f)
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir + "secure/")), "MemorySecureStore не создаёт каталог секретов")
	var default_file := SecureStore.DEFAULT_DIR + EncryptedFileSecureStore.FILE_NAME
	if FileAccess.file_exists(default_file):
		for t in TOKENS:
			assert_false(_file_contains(default_file, t), "токены из памяти не попали в файл по умолчанию")


func test_req_nfr_05_c2_encrypted_file_hides_tokens_keys_and_structure() -> void:
	var enc := EncryptedFileSecureStore.new(_dir + "enc/", PASSWORD)
	for i in 3:
		enc.set_secret(_k(PID_A, "strava", "item%d" % i), TOKENS[i])
	var path := enc.file_path()
	assert_true(FileAccess.file_exists(path))
	for t in TOKENS:
		assert_false(_file_contains(path, t), "токен %s… в файле" % t.substr(0, 10))
	for plain in [PID_A, "strava", "item0", "access_token"]:
		assert_false(_file_contains(path, plain), "«%s» видно в файле" % plain)
	assert_gt(FileAccess.get_file_as_bytes(path).size(), 0)


# ===========================================================================
# REQ-NFR-05 крит. 1 — единственная точка работы с секретами в src/
# ===========================================================================

func test_req_nfr_05_c1_secret_identifiers_only_in_secure_store_module() -> void:
	var offenders: Array[String] = []
	var regex := RegEx.create_from_string("access_token|refresh_token|api_key|client_secret|Bearer ")
	_scan(regex, "res://src", offenders)
	assert_eq(offenders, [], "обращения к токенам/ключам вне src/storage/secure_store*: %s" % str(offenders))


func _scan(regex: RegEx, dir_path: String, offenders: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				_scan(regex, full, offenders)
		elif name.ends_with(".gd") and not full.begins_with("res://src/storage/secure_store"):
			var source := FileAccess.get_file_as_string(full)
			# REQ-NFR-05 крит. 1: интеграции, использующие интерфейс SecureStore, допустимы.
			if full.begins_with("res://src/integrations/") and source.contains("SecureStore"):
				name = dir.get_next()
				continue
			var n := 0
			for line in source.split("\n"):
				n += 1
				if line.strip_edges().begins_with("#"):
					continue
				if regex.search(line) != null:
					offenders.append("%s:%d" % [full, n])
		name = d.get_next()
	d.list_dir_end()


func test_req_nfr_05_c1_base_interface_methods_are_abstract_and_default_store_is_encrypted() -> void:
	var dflt := SecureStore.create_default(_dir + "default/")
	assert_true(dflt is EncryptedFileSecureStore)
	assert_true(dflt.set_secret(_k(PID_A, "strava", "access_token"), TOKENS[0]))
	var reopened := SecureStore.create_default(_dir + "default/")
	assert_true((reopened as EncryptedFileSecureStore).loaded_ok())
	assert_eq(reopened.get_secret(_k(PID_A, "strava", "access_token")), TOKENS[0], "пароль устройства стабилен в рамках процесса")
	assert_false(_file_contains((dflt as EncryptedFileSecureStore).file_path(), TOKENS[0]))
	var wrong := EncryptedFileSecureStore.new(_dir + "default/", "not-the-device-password")
	assert_engine_error("ERR_FILE_CORRUPT", "ядро сообщает о неверном ключе — ожидаемо")
	assert_push_warning("не удалось расшифровать")
	assert_false(wrong.loaded_ok(), "с чужим паролем файл по умолчанию не читается")


# ===========================================================================
# Зашифрованный файл — неверный пароль, повреждение
# ===========================================================================

func test_req_nfr_05_wrong_password_gives_loaded_ok_false_and_empty_store() -> void:
	var enc := EncryptedFileSecureStore.new(_dir + "enc/", PASSWORD)
	enc.set_secret(_k(PID_A, "strava", "access_token"), TOKENS[0])
	var wrong := EncryptedFileSecureStore.new(_dir + "enc/", "wrong")
	assert_engine_error("ERR_FILE_CORRUPT", "ядро сообщает о неверном ключе — ожидаемо")
	assert_push_warning("не удалось расшифровать")
	assert_false(wrong.loaded_ok())
	assert_eq(wrong.list_keys(), [])
	assert_eq(wrong.get_secret(_k(PID_A, "strava", "access_token")), "")
	assert_true(EncryptedFileSecureStore.new(_dir + "enc/", PASSWORD).loaded_ok(), "верный пароль по-прежнему читает")


func test_req_nfr_05_store_that_failed_to_decrypt_must_not_destroy_existing_secrets_on_write() -> void:
	# Негатив: экземпляр с неверным паролем не расшифровал файл; запись в него не
	# должна затирать чужие секреты (иначе один сбой пароля = потеря всех токенов).
	var enc := EncryptedFileSecureStore.new(_dir + "enc/", PASSWORD)
	enc.set_secret(_k(PID_A, "strava", "access_token"), TOKENS[0])
	enc.set_secret(_k(PID_B, "strava", "access_token"), TOKENS[1])
	var wrong := EncryptedFileSecureStore.new(_dir + "enc/", "wrong")
	assert_engine_error("ERR_FILE_CORRUPT", "ядро сообщает о неверном ключе — ожидаемо (ровно один раз)")
	assert_push_warning("не удалось расшифровать")
	assert_false(wrong.loaded_ok())
	wrong.set_secret(_k(PID_A, "intervals", "api_key"), TOKENS[2])
	var original := EncryptedFileSecureStore.new(_dir + "enc/", PASSWORD)
	assert_true(original.loaded_ok(), "файл всё ещё читается исходным паролем")
	assert_eq(original.get_secret(_k(PID_A, "strava", "access_token")), TOKENS[0], "ранее сохранённые секреты не уничтожены записью из нерасшифрованного экземпляра")
	assert_eq(original.get_secret(_k(PID_B, "strava", "access_token")), TOKENS[1])


func test_req_nfr_05_corrupted_secrets_file_gives_loaded_ok_false_without_crash() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir + "enc/"))
	var f := FileAccess.open(_dir + "enc/" + EncryptedFileSecureStore.FILE_NAME, FileAccess.WRITE)
	f.store_string("definitely not an encrypted godot file")
	f.close()
	var enc := EncryptedFileSecureStore.new(_dir + "enc/", PASSWORD)
	assert_engine_error("ERR_FILE_UNRECOGNIZED", "ядро не узнаёт формат — ожидаемо")
	assert_push_warning("не удалось расшифровать")
	assert_false(enc.loaded_ok())
	assert_eq(enc.list_keys(), [])


func test_req_nfr_05_empty_dir_store_loads_ok_and_has_no_file_until_first_write() -> void:
	var enc := EncryptedFileSecureStore.new(_dir + "enc/", PASSWORD)
	assert_true(enc.loaded_ok())
	assert_false(FileAccess.file_exists(enc.file_path()))
	assert_eq(enc.list_keys(), [])
	assert_false(enc.delete_secret("a/b/c"), "удаление из пустого — false, файл не создаётся")
	assert_false(FileAccess.file_exists(enc.file_path()))


# ===========================================================================
# Каскад REQ-PRF-01 крит. 4 (часть «токены») через attach_to_profiles
# ===========================================================================

func test_req_prf_01_c4_attach_to_profiles_deletes_only_deleted_profiles_secrets_in_both_impls() -> void:
	var repo := ProfileRepository.new(_dir + "profiles/")
	var a := repo.create("A")
	var b := repo.create("B")
	var c := repo.create("C")
	var mem := MemorySecureStore.new()
	var enc := EncryptedFileSecureStore.new(_dir + "secure/", PASSWORD)
	for s in [mem, enc]:
		var store := s as SecureStore
		store.attach_to_profiles(repo)
		for pid in [a.id, b.id, c.id]:
			store.set_secret(_k(pid, "strava", "access_token"), "s-" + pid)
			store.set_secret(_k(pid, "intervals", "api_key"), "i-" + pid)
	assert_eq(repo.delete(b.id), "")
	for s in [mem, enc]:
		var store := s as SecureStore
		assert_eq(store.list_keys(b.id + "/"), [], "ключи B стёрты")
		assert_eq(store.list_keys(a.id + "/").size(), 2, "A цел")
		assert_eq(store.list_keys(c.id + "/").size(), 2, "C цел")
		assert_eq(store.list_keys().size(), 4)
	assert_eq(EncryptedFileSecureStore.new(_dir + "secure/", PASSWORD).list_keys().size(), 4, "и на диске")


func test_req_prf_01_c4_refused_deletion_of_last_profile_keeps_secrets() -> void:
	var repo := ProfileRepository.new(_dir + "profiles/")
	var only := repo.create("Solo")
	var mem := MemorySecureStore.new()
	mem.attach_to_profiles(repo)
	mem.set_secret(_k(only.id, "strava", "access_token"), TOKENS[0])
	assert_eq(repo.delete(only.id), ProfileRepository.ERR_LAST_PROFILE)
	assert_eq(mem.get_secret(_k(only.id, "strava", "access_token")), TOKENS[0])
	assert_eq(repo.delete("ghost"), ProfileRepository.ERR_PROFILE_NOT_FOUND)
	assert_eq(mem.size(), 1)


func test_req_prf_01_c4_attach_twice_is_harmless_and_delete_hook_order_before_signal() -> void:
	var repo := ProfileRepository.new(_dir + "profiles/")
	var a := repo.create("A")
	var b := repo.create("B")
	var mem := MemorySecureStore.new()
	mem.attach_to_profiles(repo)
	mem.attach_to_profiles(repo)
	mem.set_secret(_k(b.id, "strava", "access_token"), TOKENS[0])
	mem.set_secret(_k(a.id, "strava", "access_token"), TOKENS[1])
	assert_eq(repo.delete(b.id), "")
	assert_eq(mem.size(), 1)
	assert_eq(mem.get_secret(_k(a.id, "strava", "access_token")), TOKENS[1])


func test_req_prf_01_c4_secrets_written_before_attach_are_also_removed() -> void:
	var repo := ProfileRepository.new(_dir + "profiles/")
	var a := repo.create("A")
	var b := repo.create("B")
	var enc := EncryptedFileSecureStore.new(_dir + "secure/", PASSWORD)
	enc.set_secret(_k(b.id, "strava", "access_token"), TOKENS[0])
	enc.attach_to_profiles(repo)
	assert_eq(repo.delete(b.id), "")
	assert_false(enc.has_secret(_k(b.id, "strava", "access_token")))
	assert_eq(repo.get_active().id, a.id)
