extends GutTest
## Приёмка T-116a (tester): ядро журнала, фильтр секретов и статистика кадров — независимые
## проверки по карточке T-116a (п.1–3), регрессия REQ-NFR-05 п.1, 2.
##
## - ротация с пределами по умолчанию 2 МиБ / 16 МиБ / 20 файлов: части и каталог не превышают
##   пределов при любом числе запусков, текущая часть не удаляется, чужие файлы каталога целы;
## - секреты в форме, в которой их отдают сами модули приложения: заголовки Intervals.icu
##   (`Authorization: Basic base64("API_KEY:<ключ>")`) и Strava (`Bearer`), разбор redirect
##   OAuth (`StravaOAuth.parse_redirect`, `handle_redirect_url` — словарь `{code, state}`),
##   тело обмена кода (`code=…&client_secret=…`), ответ с токенами; строкой (`str`/`JSON`) и
##   словарём — значения в файл журнала не попадают;
## - статистика кадров на серии с известным ответом и на границах 16.7 / 33 мс.

const SECRET_KEY: String = "fixture-accept-intervals-key-T116a"
const SECRET_TOKEN: String = "fixture-accept-strava-access-T116a"
const SECRET_REFRESH: String = "fixture-accept-strava-refresh-T116a"
const SECRET_CODE: String = "fixture-accept-oauth-code-T116a"
const CLIENT_SECRET: String = "fixture-accept-client-secret-T116a"
const PROFILE: String = "p-accept"

var _dir: String


func before_each() -> void:
	_dir = "user://test_t116a_accept_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]


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


func _logs_dir() -> String:
	return _dir + "logs/"


func _all_text() -> String:
	var text := ""
	var d := DirAccess.open(_logs_dir())
	if d == null:
		return text
	for f in d.get_files():
		text += FileAccess.get_file_as_string(_logs_dir() + f)
	return text


func _store() -> MemorySecureStore:
	var store := MemorySecureStore.new()
	store.set_secret(SecureStore.key_for(PROFILE, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY), SECRET_KEY)
	store.set_secret(SecureStore.key_for(PROFILE, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN), SECRET_TOKEN)
	store.set_secret(SecureStore.key_for(PROFILE, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_REFRESH_TOKEN), SECRET_REFRESH)
	return store


## Журнал приложения с подключённым хранилищем — как в `AppMain._open_journal`.
func _journal(store: SecureStore) -> DiagLog:
	var journal := DiagLog.new(_logs_dir())
	journal.filter().set_store(store)
	assert_eq(journal.open(), OK, "журнал открыт")
	return journal


## Заголовок Intervals.icu в том виде, в каком его строит клиент (`intervals_icu_client.gd`).
static func _intervals_basic() -> String:
	return Marshalls.utf8_to_base64("API_KEY:" + SECRET_KEY)


func _write_files(count: int, size_bytes: int, stamp_prefix: String) -> void:
	DirAccess.make_dir_recursive_absolute(_logs_dir())
	var chunk := "z".repeat(size_bytes)
	for i in count:
		var path := "%s%s%s-%03d-p001%s" % [_logs_dir(), DiagLog.FILE_PREFIX, stamp_prefix, i, DiagLog.FILE_SUFFIX]
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(chunk)
		f.close()


# ---------------------------------------------------------------------------
# п.1 — файл на запуск, ротация 2 МиБ / 16 МиБ / 20 файлов
# ---------------------------------------------------------------------------

func test_default_limits_are_2_mib_part_16_mib_dir_20_files() -> void:
	var journal := DiagLog.new(_logs_dir())
	assert_eq(journal.max_file_bytes, 2 * 1024 * 1024, "часть — 2 МиБ")
	assert_eq(journal.max_total_bytes, 16 * 1024 * 1024, "каталог — 16 МиБ")
	assert_eq(journal.max_files, 20, "не больше 20 файлов")
	assert_eq(DiagLog.DEFAULT_DIR, "user://logs/", "каталог по умолчанию — user://logs/")


func test_many_old_launches_with_default_limits_keep_dir_under_16_mib_and_20_files() -> void:
	# 30 старых запусков по 1.5 МиБ (45 МиБ) — от прошлых версий или аварий.
	_write_files(30, 1536 * 1024, "20200101-000000")
	var journal := _journal(MemorySecureStore.new())
	assert_true(journal.write(DiagLog.CAT_APP, "fresh_launch"))
	var files := journal.files()
	assert_true(files.size() <= 20, "файлов %d ≤ 20" % files.size())
	assert_true(files.has(journal.file_path()), "текущая часть на месте")
	# С учётом того, что текущая часть может дорасти до 2 МиБ.
	assert_true(journal.total_bytes() - FileAccess.get_file_as_bytes(journal.file_path()).size() + journal.max_file_bytes
			<= journal.max_total_bytes, "каталог с запасом под текущую часть не больше 16 МиБ: %d" % journal.total_bytes())
	assert_true(_all_text().contains("fresh_launch"), "запись нового запуска на месте")


func test_current_part_survives_even_with_single_file_limit() -> void:
	_write_files(3, 100, "20200101-000000")
	var journal := DiagLog.new(_logs_dir(), 1024, 4096, 1)
	assert_eq(journal.open(), OK)
	journal.write(DiagLog.CAT_APP, "only_current")
	assert_eq(journal.files(), [journal.file_path()] as Array[String], "остался только текущий файл")
	# Ротация внутри запуска при пределе в 1 файл: старая часть удаляется, новая пишется.
	for i in 40:
		journal.write(DiagLog.CAT_APP, "spam", {"i": i, "pad": "q".repeat(80)})
	assert_eq(journal.files().size(), 1, "один файл")
	assert_true(FileAccess.file_exists(journal.file_path()), "текущая часть существует")
	assert_true(FileAccess.get_file_as_string(journal.file_path()).contains("\"i\":39"), "последняя запись в текущей части")


func test_rotation_never_exceeds_part_and_dir_limits_across_relaunches() -> void:
	var file_limit := 2048
	var total_limit := 8 * 1024
	for launch in 6:
		var journal := DiagLog.new(_logs_dir(), file_limit, total_limit, 20)
		assert_eq(journal.open(), OK)
		for i in 60:
			journal.write(DiagLog.CAT_FRAMES, "tick", {"launch": launch, "i": i, "pad": "w".repeat(60)})
			assert_true(journal.total_bytes() <= total_limit, "запуск %d, запись %d: каталог %d ≤ %d" % [launch, i, journal.total_bytes(), total_limit])
		for path in journal.files():
			assert_true(FileAccess.get_file_as_bytes(path).size() <= file_limit, "часть %s ≤ %d" % [path.get_file(), file_limit])
		journal.close()


func test_foreign_files_in_logs_dir_are_not_deleted() -> void:
	DirAccess.make_dir_recursive_absolute(_logs_dir())
	var foreign := _logs_dir() + "README.txt"
	var f := FileAccess.open(foreign, FileAccess.WRITE)
	f.store_string("не журнал")
	f.close()
	var journal := DiagLog.new(_logs_dir(), 1024, 2048, 2)
	assert_eq(journal.open(), OK)
	for i in 100:
		journal.write(DiagLog.CAT_APP, "spam", {"i": i, "pad": "e".repeat(50)})
	assert_true(FileAccess.file_exists(foreign), "чужой файл каталога не удалён ротацией")


func test_each_line_is_json_with_utc_time_category_event() -> void:
	var journal := _journal(MemorySecureStore.new())
	journal.write(DiagLog.CAT_FRAMES, "probe", {"n": 1})
	var lines := FileAccess.get_file_as_string(journal.file_path()).split("\n", false)
	assert_eq(lines.size(), 1)
	var rec: Variant = JSON.parse_string(lines[0])
	assert_true(rec is Dictionary, "строка — JSON-объект")
	var r: Dictionary = rec
	var t := str(r.get("t", ""))
	var re := RegEx.new()
	re.compile("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$")
	assert_not_null(re.search(t), "время UTC ISO 8601 с мс: %s" % t)
	assert_eq(r.get("cat"), DiagLog.CAT_FRAMES)
	assert_eq(r.get("ev"), "probe")


# ---------------------------------------------------------------------------
# п.2 — секреты в форме, которую отдают модули приложения
# ---------------------------------------------------------------------------

func test_intervals_basic_header_as_dict_and_header_list_is_masked() -> void:
	var journal := _journal(_store())
	var b64 := _intervals_basic()
	journal.write("net", "request_dict", {"headers": {"Authorization": "Basic " + b64}})
	journal.write("net", "request_list", {"headers": PackedStringArray(["Accept: application/json", "Authorization: Basic " + b64])})
	var text := _all_text()
	assert_true(text.contains("request_dict") and text.contains("request_list"), "события записаны")
	assert_false(text.contains(b64), "base64 ключа Intervals.icu не в журнале")


func test_intervals_basic_header_logged_as_json_string_is_masked() -> void:
	# Так заголовки выглядят, если их записать строкой: JSON.stringify(headers) или str(headers).
	var journal := _journal(_store())
	var b64 := _intervals_basic()
	var headers := {"Authorization": "Basic " + b64, "Accept": "application/json"}
	journal.write("net", "request_json", {"headers": JSON.stringify(headers)})
	journal.write("net", "request_str", {"headers": str(headers)})
	var text := _all_text()
	assert_true(text.contains("request_json") and text.contains("request_str"), "события записаны")
	assert_false(text.contains(b64), "Authorization: Basic (base64 ключа) из строки заголовков не в журнале")


func test_strava_bearer_header_and_token_response_are_masked() -> void:
	var journal := _journal(_store())
	var headers := {"Authorization": "Bearer " + SECRET_TOKEN}
	journal.write("net", "api_headers_str", {"headers": str(headers)})
	var body := JSON.stringify({"token_type": "Bearer", "access_token": SECRET_TOKEN,
		"refresh_token": SECRET_REFRESH, "expires_at": 1767225600})
	journal.write("net", "token_response", {"body": body})
	var text := _all_text()
	assert_false(text.contains(SECRET_TOKEN), "access token не в журнале")
	assert_false(text.contains(SECRET_REFRESH), "refresh token не в журнале")


func test_oauth_exchange_form_body_is_masked() -> void:
	var journal := _journal(_store())
	# Тело обмена кода — как `StravaOAuth._post_form`.
	var body := "client_id=4242&client_secret=%s&code=%s&grant_type=authorization_code" % [CLIENT_SECRET, SECRET_CODE]
	journal.write("net", "token_exchange", {"body": body})
	var text := _all_text()
	assert_false(text.contains(SECRET_CODE), "код OAuth из тела обмена не в журнале")
	assert_false(text.contains(CLIENT_SECRET), "client_secret не в журнале")


func test_oauth_code_from_redirect_parse_result_is_masked() -> void:
	# `StravaOAuth.parse_redirect` — `{path, query: {code, state}}`: естественный кандидат
	# в журнал событий OAuth (T-116b, T-125).
	var journal := _journal(_store())
	var parsed := StravaOAuth.parse_redirect("ovoschrider://strava?state=s1&code=%s&scope=activity:write" % SECRET_CODE)
	assert_eq(str((parsed["query"] as Dictionary).get("code", "")), SECRET_CODE, "разбор как в приложении")
	journal.write("strava", "oauth_redirect", parsed)
	var text := _all_text()
	assert_true(text.contains("oauth_redirect"), "событие записано")
	assert_false(text.contains(SECRET_CODE), "код OAuth из разобранного redirect не в журнале: %s" % text.strip_edges())


func test_oauth_code_from_handle_redirect_result_is_masked() -> void:
	var journal := _journal(_store())
	var oauth := StravaOAuth.new(MockHttpTransport.new(), _store(), PROFILE, StravaConfig.from_values("4242", CLIENT_SECRET))
	oauth.expected_state = "st-accept"
	var result := oauth.handle_redirect_url("ovoschrider://strava?state=st-accept&code=%s" % SECRET_CODE)
	assert_eq(str(result.get("code", "")), SECRET_CODE, "код принят, как в приложении")
	journal.write("strava", "oauth_result", result)
	var text := _all_text()
	assert_true(text.contains("oauth_result"), "событие записано")
	assert_false(text.contains(SECRET_CODE), "код OAuth из результата redirect {code, state} не в журнале: %s" % text.strip_edges())


func test_secret_in_event_name_and_category_is_masked() -> void:
	var journal := _journal(_store())
	journal.write("cat_" + SECRET_KEY, "ev_" + SECRET_TOKEN)
	var text := _all_text()
	assert_false(text.contains(SECRET_KEY), "ключ в категории замаскирован")
	assert_false(text.contains(SECRET_TOKEN), "токен в имени события замаскирован")


func test_oversized_record_with_secret_does_not_leak_through_truncation_stub() -> void:
	var journal := DiagLog.new(_logs_dir(), 512, 4096, 5)
	journal.filter().set_store(_store())
	assert_eq(journal.open(), OK)
	journal.write("c_" + SECRET_KEY, "big", {"pad": "p".repeat(2000)})
	assert_false(_all_text().contains(SECRET_KEY), "в пометке обрезанной записи секрета нет")


func test_export_contains_no_secrets() -> void:
	var store := _store()
	var journal := _journal(store)
	journal.write("net", "leak", {"auth": "Authorization: Bearer " + SECRET_TOKEN, "k": SECRET_KEY})
	var target := ProjectSettings.globalize_path(_dir + "export.log")
	assert_eq(journal.export_to(target), OK)
	var text := FileAccess.get_file_as_string(target)
	assert_true(text.contains("leak"), "экспорт содержит запись")
	assert_false(text.contains(SECRET_TOKEN) or text.contains(SECRET_KEY), "в экспорте секретов нет")


# ---------------------------------------------------------------------------
# п.3 — статистика кадров
# ---------------------------------------------------------------------------

func test_frame_stats_hand_computed_series() -> void:
	# 990 × 10 мс + 10 × 50 мс: 1000 кадров за 10.4 с.
	var series := PackedFloat32Array()
	for i in 990:
		series.append(10.0)
	for i in 10:
		series.append(50.0)
	var s := FrameStats.from_frame_times_ms(series).summary()
	assert_eq(int(s["frames"]), 1000)
	assert_almost_eq(float(s["avg_fps"]), 1000.0 / 10.4, 0.01, "средний FPS = кадры / время")
	assert_almost_eq(float(s["low_1pct_fps"]), 20.0, 0.01, "1 % low: 10 худших по 50 мс → 20 FPS")
	assert_almost_eq(float(s["p50_ms"]), 10.0, 1e-3)
	assert_almost_eq(float(s["p95_ms"]), 10.0, 1e-3)
	assert_almost_eq(float(s["p99_ms"]), 10.0, 1e-3, "990-й по рангу — 10 мс")
	assert_almost_eq(float(s["share_over_16_7_ms"]), 0.01, 1e-6)
	assert_almost_eq(float(s["share_over_33_ms"]), 0.01, 1e-6)
	assert_almost_eq(float(s["duration_s"]), 10.4, 0.01)


func test_frame_stats_thresholds_are_strictly_longer_than() -> void:
	# Кадры подаются как в приложении — в микросекундах (`FrameStatsProbe` → `add_frame_usec`).
	var stats := FrameStats.new()
	for usec in [16700, 16710, 33000, 33010, 10000]:
		stats.add_frame_usec(usec)
	var s := stats.summary()
	# «Длиннее 16.7 мс»: 16.71, 33.0, 33.01; «длиннее 33 мс»: 33.01.
	assert_eq(int(s["frames_over_16_7_ms"]), 3, "ровно 16.7 мс — не долгий кадр")
	assert_eq(int(s["frames_over_33_ms"]), 1, "ровно 33 мс — не долгий кадр")
	assert_almost_eq(float(s["share_over_33_ms"]), 0.2, 1e-6)


func test_d3d05_threshold_one_percent_long_frames_is_representable() -> void:
	# Критерий D3D-05 п.1: доля > 33 мс ≤ 1 % — на 20 мин при 60 FPS (72 000 кадров) 1 % = 720.
	var stats := FrameStats.new()
	for i in 72000 - 720:
		stats.add_frame_ms(16.6)
	for i in 720:
		stats.add_frame_ms(40.0)
	var s := stats.summary()
	assert_eq(int(s["frames"]), 72000)
	assert_almost_eq(float(s["share_over_33_ms"]), 0.01, 1e-6)
	assert_almost_eq(float(s["low_1pct_fps"]), 25.0, 0.01)
	assert_almost_eq(float(s["p99_ms"]), 16.6, 1e-3, "72000·0.99 = 71280-й кадр — ещё 16.6 мс")
