extends GutTest
## Диагностический журнал `DiagLog` и фильтр `SecureStoreFilter` (T-116a, п.1, 2, 6): файл на запуск
## в `logs/`, JSON Lines, ротация в пределах объёма, экспорт одним файлом, общий журнал;
## секреты (значения `SecureStore`, `Authorization`, коды OAuth) в файл не попадают
## (регрессия REQ-NFR-05 п.1, 2).

## Значения тестовых секретов (префикс `fixture-` — белый список `scripts/check_secrets.sh`).
const SECRET_KEY: String = "fixture-intervals-key-7Q2"
const SECRET_TOKEN: String = "fixture-strava-access-9Z4"
const SECRET_REFRESH: String = "fixture-strava-refresh-3K8"
const SECRET_CODE: String = "fixture-oauth-code-5M1"

var _dir: String


func before_each() -> void:
	_dir = "user://test_diag_log_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]


func after_each() -> void:
	DiagLog.uninstall()
	_remove_tree(ProjectSettings.globalize_path(_dir))


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


func _log(file_limit: int = DiagLog.DEFAULT_MAX_FILE_BYTES, total_limit: int = DiagLog.DEFAULT_MAX_TOTAL_BYTES,
		files_limit: int = DiagLog.DEFAULT_MAX_FILES) -> DiagLog:
	var journal := DiagLog.new(_dir + "logs/", file_limit, total_limit, files_limit)
	assert_eq(journal.open(), OK, "журнал открыт")
	return journal


static func _records(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		if line.begins_with("#"):
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			out.append(parsed)
	return out


static func _all_text(dir_path: String) -> String:
	var text := ""
	var d := DirAccess.open(dir_path)
	if d == null:
		return text
	for f in d.get_files():
		text += FileAccess.get_file_as_string(dir_path.path_join(f))
	return text


func _store_with_secrets() -> SecureStore:
	var store := MemorySecureStore.new()
	store.set_secret(SecureStore.key_for("p1", SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY), SECRET_KEY)
	store.set_secret(SecureStore.key_for("p1", SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN), SECRET_TOKEN)
	store.set_secret(SecureStore.key_for("p1", SecureStore.SERVICE_STRAVA, SecureStore.ITEM_REFRESH_TOKEN), SECRET_REFRESH)
	store.set_secret(SecureStore.key_for("p1", SecureStore.SERVICE_STRAVA, SecureStore.ITEM_EXPIRES_AT), "1767225600")
	return store


# ---------------------------------------------------------------------------
# Файл и формат
# ---------------------------------------------------------------------------

func test_open_creates_one_file_per_launch_in_logs_dir() -> void:
	var first := _log()
	var first_path := first.file_path()
	assert_true(first_path.begins_with(_dir + "logs/" + DiagLog.FILE_PREFIX), first_path)
	assert_true(first_path.ends_with(DiagLog.FILE_SUFFIX))
	assert_true(FileAccess.file_exists(first_path))
	first.close()
	var second := _log()
	assert_ne(second.file_path(), first_path, "новый запуск — новый файл, даже в ту же миллисекунду")
	assert_eq(second.files(), [first_path, second.file_path()], "файлы сортируются по времени запуска")


func test_write_appends_json_lines_with_time_category_event_and_data() -> void:
	var journal := _log()
	assert_true(journal.write(DiagLog.CAT_APP, "app_started", {"version": "0.2.0", "n": 3}))
	assert_true(journal.write(DiagLog.CAT_FRAMES, "ride_frame_stats", {"avg_fps": 59.9}))
	var records := _records(journal.file_path())
	assert_eq(records.size(), 2)
	assert_eq(records[0]["cat"], DiagLog.CAT_APP)
	assert_eq(records[0]["ev"], "app_started")
	assert_eq(records[0]["data"]["version"], "0.2.0")
	assert_eq(int(records[0]["data"]["n"]), 3)
	assert_true(str(records[0]["t"]).ends_with("Z"), "время UTC: %s" % records[0]["t"])
	assert_true(records[0].has("up_ms"))
	assert_eq(records[1]["data"]["avg_fps"], 59.9)
	assert_eq(journal.line_count(), 2)


func test_closed_or_unopened_log_writes_nothing() -> void:
	var journal := DiagLog.new(_dir + "logs/")
	assert_false(journal.write(DiagLog.CAT_APP, "x"), "не открыт — запись не идёт")
	assert_eq(journal.file_path(), "")


func test_shared_event_is_noop_without_install_and_writes_after_install() -> void:
	DiagLog.uninstall()
	DiagLog.event(DiagLog.CAT_APP, "nobody_listens")
	var journal := _log()
	DiagLog.install(journal)
	assert_eq(DiagLog.shared(), journal)
	DiagLog.event(DiagLog.CAT_SETTINGS, "fps_limit", {"max_fps": 15})
	var records := _records(journal.file_path())
	assert_eq(records.size(), 1)
	assert_eq(records[0]["ev"], "fps_limit")
	var other := DiagLog.new(_dir + "other/")
	DiagLog.uninstall(other)
	assert_eq(DiagLog.shared(), journal, "чужой журнал общий не снимает")
	DiagLog.uninstall(journal)
	assert_null(DiagLog.shared())


# ---------------------------------------------------------------------------
# Ротация и предел объёма
# ---------------------------------------------------------------------------

func test_rotation_splits_into_parts_and_keeps_total_under_limit() -> void:
	var file_limit := 4 * 1024
	var total_limit := 16 * 1024
	var journal := _log(file_limit, total_limit, 50)
	var payload := "x".repeat(200)
	for i in 600:
		journal.write(DiagLog.CAT_APP, "spam", {"i": i, "payload": payload})
		assert_true(journal.total_bytes() <= total_limit, "после записи %d объём %d ≤ %d" % [i, journal.total_bytes(), total_limit])
	var files := journal.files()
	assert_gt(files.size(), 1, "запись разбита на части")
	for path in files:
		assert_true(FileAccess.get_file_as_bytes(path).size() <= file_limit, "часть %s не больше предела" % path)
	assert_eq(files[files.size() - 1], journal.file_path(), "текущая часть — последняя")
	var last := _records(journal.file_path())
	assert_eq(int(last[last.size() - 1]["data"]["i"]), 599, "последняя запись не потеряна")


func test_old_launch_files_are_pruned_by_count() -> void:
	for i in 5:
		var j := _log(DiagLog.DEFAULT_MAX_FILE_BYTES, DiagLog.DEFAULT_MAX_TOTAL_BYTES, 3)
		j.write(DiagLog.CAT_APP, "launch", {"i": i})
		j.close()
	var journal := _log(DiagLog.DEFAULT_MAX_FILE_BYTES, DiagLog.DEFAULT_MAX_TOTAL_BYTES, 3)
	assert_eq(journal.files().size(), 3, "не больше 3 файлов, текущий сохранён")
	assert_true(journal.files().has(journal.file_path()))


func test_oversized_record_is_truncated_not_exceeding_part_limit() -> void:
	var journal := _log(1024, 8 * 1024, 10)
	assert_true(journal.write(DiagLog.CAT_APP, "huge", {"payload": "y".repeat(5000)}))
	var records := _records(journal.file_path())
	assert_eq(records.size(), 1)
	assert_true(records[0].has("truncated_bytes"), "запись больше части заменена пометкой")
	assert_true(FileAccess.get_file_as_bytes(journal.file_path()).size() <= 1024)


# ---------------------------------------------------------------------------
# Экспорт
# ---------------------------------------------------------------------------

func test_export_copies_all_log_files_oldest_first_to_chosen_path() -> void:
	var old := _log()
	old.write(DiagLog.CAT_APP, "first_launch")
	old.close()
	var journal := _log()
	journal.write(DiagLog.CAT_APP, "second_launch")
	var target := _dir + "export/saved.log"
	DirAccess.make_dir_recursive_absolute(_dir + "export/")
	assert_eq(journal.export_to(target), OK)
	var text := FileAccess.get_file_as_string(target)
	assert_true(text.contains("first_launch") and text.contains("second_launch"), "в экспорте оба запуска")
	assert_lt(text.find("first_launch"), text.find("second_launch"), "старые раньше новых")
	assert_true(text.contains("# --- " + journal.file_path().get_file()), "заголовок с именем файла")
	assert_eq(_records(target).size(), 2, "строки журнала разбираются как JSON")
	assert_true(journal.write(DiagLog.CAT_APP, "after_export"), "журнал пишет и после экспорта")


func test_export_to_unwritable_path_returns_error() -> void:
	var journal := _log()
	assert_ne(journal.export_to(_dir + "no_such_dir/deeper/saved.log"), OK)


func test_export_file_name_is_dated_log() -> void:
	var name := DiagLog.export_file_name()
	assert_true(name.begins_with("ovosch-log-") and name.ends_with(".log"), name)


# ---------------------------------------------------------------------------
# Секреты (REQ-NFR-05 п.1, 2)
# ---------------------------------------------------------------------------

func test_secure_store_values_auth_headers_and_oauth_codes_never_reach_the_file() -> void:
	var journal := _log()
	journal.filter().set_store(_store_with_secrets())
	journal.filter().add_secret(SECRET_CODE)
	journal.write(DiagLog.CAT_APP, "http", {
		"url": "https://www.strava.com/oauth/token?client_id=1&code=%s&grant_type=authorization_code" % SECRET_CODE,
		"headers": {"Authorization": "Bearer " + SECRET_TOKEN, "Accept": "application/json"},
		"note": "key %s in text" % SECRET_KEY,
		"expires": "1767225600",
	})
	journal.write(DiagLog.CAT_APP, "nested", {"items": [SECRET_REFRESH, {"access_token": SECRET_TOKEN}]})
	journal.write(DiagLog.CAT_APP, "raw_header", {"line": "Authorization: Basic Zml4dHVyZS1rZXk="})
	journal.write(DiagLog.CAT_APP, "callback", {"line": "GET /callback?state=s1&code=fixture-unregistered-code HTTP/1.1"})
	journal.write(DiagLog.CAT_APP, SECRET_KEY, {SECRET_TOKEN: 1})
	var text := _all_text(_dir + "logs/")
	for secret in [SECRET_KEY, SECRET_TOKEN, SECRET_REFRESH, SECRET_CODE, "fixture-unregistered-code", "Zml4dHVyZS1rZXk="]:
		assert_false(text.contains(secret), "секрет %s не попал в журнал" % secret)
	assert_true(text.contains(SecureStoreFilter.MASK), "на месте секретов — маска")
	assert_true(text.contains("application/json"), "несекретные поля сохранены")
	assert_true(text.contains("1767225600"), "срок действия токена — не секрет, остаётся как есть")


func test_secret_added_to_store_after_open_is_masked_immediately() -> void:
	var store := MemorySecureStore.new()
	var journal := _log()
	journal.filter().set_store(store)
	store.set_secret(SecureStore.key_for("p2", SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY), SECRET_KEY)
	journal.write(DiagLog.CAT_APP, "late", {"value": "prefix-" + SECRET_KEY})
	assert_false(_all_text(_dir + "logs/").contains(SECRET_KEY))


func test_filter_redacts_sensitive_keys_and_patterns() -> void:
	var f := SecureStoreFilter.new()
	var out: Dictionary = f.redact_value({"refresh_token": 1234, "api_key": "abc", "strava.access_token": "z",
			"code": "auth_failed", "token_type": "Bearer"})
	assert_eq(out["refresh_token"], SecureStoreFilter.MASK, "значение секретного поля любого типа")
	assert_eq(out["api_key"], SecureStoreFilter.MASK)
	assert_eq(out["strava.access_token"], SecureStoreFilter.MASK)
	assert_eq(out["code"], "auth_failed", "код ошибки ApiResult — не секрет")
	assert_eq(f.redact("password=fixture-pass-1&x=1"), "password=***&x=1")
	assert_eq(f.redact("{\"access_token\":\"fixture-tok-2\",\"x\":1}"), "{\"access_token\":\"***\",\"x\":1}")
	assert_eq(f.redact("short secrets ok"), "short secrets ok", "обычный текст не трогается")
	f.add_secret("abc")
	assert_eq(f.redact("abc"), "abc", "значения короче MIN_SECRET_LENGTH секретами не считаются")
	f.add_secret(SECRET_CODE)
	assert_eq(f.redact("x" + SECRET_CODE), "x***")
	f.forget_secret(SECRET_CODE)
	assert_eq(f.redact(SECRET_CODE), SECRET_CODE)
