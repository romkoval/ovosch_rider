extends GutTest
## Независимая приёмка T-032/T-033/T-034/T-036 (коммит ad5b364): `MockHttpTransport`,
## `IntervalsIcuClient`, `IntervalsSync`, `PlanCache`, `IntervalsPlanService`, поля Intervals в `Profile`.
## Критерии: REQ-INT-01 к1–3; REQ-INT-02 к1–5; REQ-INT-04 к1–2 (данные); REQ-INT-06 к1–6, 8;
## REQ-INT-07 к1–6; REQ-NFR-03 к1–2; REQ-PRF-03 к1–3. Фикстуры — tests/fixtures/intervals/ (синтетические),
## дополнительные ответы собираются в тестах по публичной документации API.

const FIXTURES: String = "res://tests/fixtures/intervals/"
const A: String = "profile-a"
const B: String = "profile-b"
const ATHLETE: String = "i12345"
const KEY: String = "acc-key-7Hq2zX9pLm4sVb1n"
const KEY_B: String = "acc-key-B-0a1b2c3d4e5f"
const BASE: String = "https://mock.intervals.test"
const TODAY: String = "2026-10-02"
const YESTERDAY: String = "2026-10-01"
const ATHLETE_URL: String = "*/athlete/" + ATHLETE
const EVENTS_URL: String = "/events?"

var _dir: String
var _mock: MockHttpTransport
var _store: MemorySecureStore
var _client: IntervalsIcuClient
var _cache: PlanCache
var _service: IntervalsPlanService
var _errors: Array[Array] = []
var _waited: Array[float] = []


func before_each() -> void:
	_dir = "user://test_intervals_acc_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_mock = MockHttpTransport.new()
	_store = MemorySecureStore.new()
	_client = IntervalsIcuClient.new(_mock, _store, A)
	_client.base_url = BASE
	_client.athlete_id = ATHLETE
	_errors = []
	_waited = []
	_client.wait_fn = func(sec: float) -> void: _waited.append(sec)
	_client.error.connect(func(code: String, message: String) -> void: _errors.append([code, message]))
	_store.set_secret(_client.secret_key(), KEY)
	_cache = PlanCache.new(_dir + "plans/")
	_service = IntervalsPlanService.new(_client, _cache)


func after_each() -> void:
	_remove_tree(ProjectSettings.globalize_path(_dir))


static func _remove_tree(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var d := DirAccess.open(abs_path)
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)


static func _fixture(name: String) -> Variant:
	var json := JSON.new()
	var err := json.parse(FileAccess.get_file_as_string(FIXTURES + name))
	assert(err == OK)
	return json.data


func _expected_auth(key: String = KEY) -> String:
	return "Basic " + Marshalls.utf8_to_base64("API_KEY:" + key)


func _events_today() -> void:
	_mock.enqueue_json("GET", EVENTS_URL, 200, _fixture("events_today.json"))


func _bike_event(id: int, name: String, description: String, moving_time: int = 0, load: int = 0,
		type: String = "Ride") -> Dictionary:
	var e := {"id": id, "start_date_local": TODAY + "T00:00:00", "category": "WORKOUT", "type": type,
		"name": name, "description": description}
	if moving_time > 0:
		e["moving_time"] = moving_time
	if load > 0:
		e["icu_training_load"] = load
	return e


func _athlete_json(ftp: Variant, power_zones: Variant, hr_zones: Variant, max_hr: Variant,
		power_names: Variant = null, hr_names: Variant = null, bike_types: Array = ["Ride", "VirtualRide"]) -> Dictionary:
	var settings := {"id": 1, "types": bike_types, "ftp": ftp, "max_hr": max_hr}
	if power_zones != null:
		settings["power_zones"] = power_zones
	if power_names != null:
		settings["power_zone_names"] = power_names
	if hr_zones != null:
		settings["hr_zones"] = hr_zones
	if hr_names != null:
		settings["hr_zone_names"] = hr_names
	return {"id": ATHLETE, "name": "Acc Athlete", "sportSettings": [settings]}


func _profile(ftp: int = 200) -> Profile:
	var p := Profile.create("Rider")
	p.ftp_w = ftp
	return p


## Все файлы под каталогом (абсолютные пути).
static func _all_files(abs_dir: String, out: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(abs_dir):
		return
	var d := DirAccess.open(abs_dir)
	for f in d.get_files():
		out.append(abs_dir.path_join(f))
	for sub in d.get_directories():
		_all_files(abs_dir.path_join(sub), out)


# ===========================================================================
# REQ-INT-01 — авторизация по API-ключу
# ===========================================================================

func test_req_int_01_c1_every_request_carries_basic_api_key_header() -> void:
	_mock.enqueue_json("GET", ATHLETE_URL, 200, _fixture("athlete.json"))
	_events_today()
	var r1: ApiResult = await _client.get_athlete()
	var r2: ApiResult = await _client.get_today_workouts(TODAY)
	assert_true(r1.ok and r2.ok)
	assert_eq(_mock.requests.size(), 2)
	for req in _mock.requests:
		assert_eq(str(req["headers"]["Authorization"]), _expected_auth(), "Authorization: Basic base64(API_KEY:<ключ>)")
		assert_eq(str(req["method"]), "GET")
		assert_true(str(req["url"]).begins_with(BASE + "/api/v1/athlete/" + ATHLETE))
	# Декодируется обратно ровно в API_KEY:<ключ>.
	var token: String = str(_mock.requests[0]["headers"]["Authorization"]).trim_prefix("Basic ")
	assert_eq(Marshalls.base64_to_utf8(token), "API_KEY:" + KEY)
	# При проверке ещё не сохранённого ключа используется именно он.
	_mock.enqueue_json("GET", "*/athlete/i777", 200, _athlete_json(260, [55, 75, 90, 105, 120, 150, 999], null, 185))
	var other := IntervalsIcuClient.new(_mock, _store, B)
	other.base_url = BASE
	var v: ApiResult = await other.verify_key("i777", "brand-new-key-XYZ")
	assert_true(v.ok, v.message)
	assert_eq(str(_mock.last_request()["headers"]["Authorization"]), _expected_auth("brand-new-key-XYZ"))


func test_req_int_01_c2_key_only_in_secure_store_and_never_in_text() -> void:
	assert_eq(_client.secret_key(), "profile-a/intervals/api_key", "ключ хранилища включает id профиля (PRF-03)")
	assert_eq(_store.list_keys(), ["profile-a/intervals/api_key"] as Array[String])
	assert_false(str(_client).contains(KEY), "str(client) маскирует ключ")
	assert_true(str(_client).contains("***"))
	# Сообщения всех видов ошибок и сигнал error — без подстроки ключа.
	_mock.enqueue_json("GET", ATHLETE_URL, 401, _fixture("error_401.json"))
	_mock.enqueue_json("GET", ATHLETE_URL, 503, {"error": "down"})
	_mock.enqueue("GET", ATHLETE_URL, HttpResponse.make(200, "<html>not json</html>"))
	_mock.enqueue_failure("GET", ATHLETE_URL, HttpResponse.ERR_TIMEOUT)
	_mock.enqueue_json("GET", ATHLETE_URL, 429, {}, {"Retry-After": "3"}, 2)
	var results: Array[ApiResult] = []
	for i in 5:
		results.append(await _client.get_athlete())
	assert_eq(results.size(), 5)
	for r in results:
		assert_false(r.ok)
		assert_false(r.message.contains(KEY), "сообщение «%s» без ключа" % r.message)
		assert_false(str(r).contains(KEY))
	assert_gt(_errors.size(), 0, "сигнал error испускался")
	for e in _errors:
		assert_false(str(e[1]).contains(KEY), "сигнал error без ключа")
		assert_false(str(e[0]).contains(KEY))
	# Клиент не держит ключ в своих полях: после удаления из хранилища запросы прекращаются.
	_store.delete_secret(_client.secret_key())
	var before := _mock.requests.size()
	var r: ApiResult = await _client.get_athlete()
	assert_eq(r.code, ApiResult.CODE_NOT_CONFIGURED)
	assert_eq(_mock.requests.size(), before, "без ключа в хранилище запрос не уходит — копии ключа у клиента нет")


func test_req_int_01_c3_rejected_key_is_reported_and_not_stored() -> void:
	var fresh := IntervalsIcuClient.new(_mock, _store, B)
	fresh.base_url = BASE
	for status in [401, 403]:
		_mock.enqueue_json("GET", "*/athlete/i999", status, _fixture("error_401.json"))
		var r: ApiResult = await fresh.verify_key("i999", "bad-key-" + str(status))
		assert_false(r.ok)
		assert_eq(r.code, ApiResult.CODE_AUTH_FAILED, "HTTP %d → auth_failed" % status)
		assert_eq(r.message, "ключ не принят")
		assert_eq(r.status, status)
		assert_false(r.message.contains("bad-key"))
		assert_false(fresh.has_api_key(), "ключ не сохранён")
		assert_eq(fresh.athlete_id, "", "Athlete ID не запомнен")
	assert_eq(_store.list_keys(B), [] as Array[String])
	# Успешная проверка — ключ сохраняется, данные атлета разобраны.
	_mock.enqueue_json("GET", "*/athlete/i999", 200, _fixture("athlete.json"))
	var ok: ApiResult = await fresh.verify_key(" i999 ", " good-key-123 ")
	assert_true(ok.ok, ok.message)
	assert_eq(_store.get_secret("profile-b/intervals/api_key"), "good-key-123", "ключ (без пробелов) сохранён под профилем B")
	assert_eq(fresh.athlete_id, "i999")
	assert_eq(ok.data["ftp"], 250, "данные атлета разобраны")
	assert_true(fresh.is_configured())
	# Пустые входы — ничего не отправляем.
	var n := _mock.requests.size()
	var empty: ApiResult = await fresh.verify_key("", "x")
	assert_eq(empty.code, ApiResult.CODE_NOT_CONFIGURED)
	empty = await fresh.verify_key("i1", "  ")
	assert_eq(empty.code, ApiResult.CODE_NOT_CONFIGURED)
	assert_eq(_mock.requests.size(), n)
	# 401 на обычном запросе после сохранения — тоже auth_failed, ключ при этом остаётся (чинит пользователь).
	_mock.enqueue_json("GET", ATHLETE_URL, 401, _fixture("error_401.json"))
	var later: ApiResult = await _client.get_athlete()
	assert_eq(later.code, ApiResult.CODE_AUTH_FAILED)
	assert_string_contains(later.message, "ключ не принят")
	assert_false(later.can_retry, "повтор без смены ключа бессмыслен")


# ===========================================================================
# REQ-INT-02 — события календаря за сегодня
# ===========================================================================

func test_req_int_02_c1_events_url_limited_to_local_today_with_workout_category() -> void:
	_events_today()
	var r: ApiResult = await _client.get_today_workouts(TODAY)
	assert_true(r.ok)
	var url: String = str(_mock.last_request()["url"])
	assert_true(url.begins_with(BASE + "/api/v1/athlete/" + ATHLETE + "/events?"), url)
	assert_string_contains(url, "oldest=" + TODAY)
	assert_string_contains(url, "newest=" + TODAY)
	assert_string_contains(url, "category=WORKOUT")
	# Без явной даты — локальная дата устройства.
	_events_today()
	var r2: ApiResult = await _client.get_today_workouts()
	assert_true(r2.ok)
	var today := Time.get_date_string_from_system(false)
	assert_eq(IntervalsIcuClient.local_date(), today, "локальная, не UTC")
	var url2: String = str(_mock.last_request()["url"])
	assert_string_contains(url2, "oldest=" + today)
	assert_string_contains(url2, "newest=" + today)
	# get_events с диапазоном — те же параметры.
	_mock.enqueue_json("GET", EVENTS_URL, 200, [])
	var r3: ApiResult = await _client.get_events("2026-09-01", "2026-09-07")
	assert_true(r3.ok)
	assert_string_contains(str(_mock.last_request()["url"]), "oldest=2026-09-01&newest=2026-09-07&category=WORKOUT")


func test_req_int_02_c2_only_bike_workouts_are_selected() -> void:
	_events_today()
	var r: ApiResult = await _client.get_today_workouts(TODAY)
	assert_true(r.ok)
	assert_eq(r.code, ApiResult.CODE_OK)
	var entries: Array = r.data
	assert_eq(entries.size(), 2, "из 5 событий — 2 велотренировки")
	assert_eq(entries[0]["event_id"], "2001")
	assert_eq(entries[0]["type"], "Ride")
	assert_eq(entries[1]["event_id"], "2002")
	assert_eq(entries[1]["type"], "VirtualRide")
	for e in entries:
		assert_false(["2003", "2004", "2005"].has(e["event_id"]), "заметка, бег и гонка без плана исключены")
	# Правила отбора на уровне события.
	assert_true(IntervalsIcuClient.is_bike_workout({"category": "WORKOUT", "type": "GravelRide"}))
	assert_true(IntervalsIcuClient.is_bike_workout({"category": "WORKOUT", "type": "MountainBikeRide"}))
	assert_false(IntervalsIcuClient.is_bike_workout({"category": "WORKOUT", "type": "Run"}), "другой вид спорта")
	assert_false(IntervalsIcuClient.is_bike_workout({"category": "WORKOUT", "type": "Swim"}))
	assert_false(IntervalsIcuClient.is_bike_workout({"category": "NOTE", "type": "Ride"}), "заметка")
	assert_false(IntervalsIcuClient.is_bike_workout({"category": "RACE_A", "type": "Ride"}), "гонка без плана")
	assert_false(IntervalsIcuClient.is_bike_workout({"category": "WORKOUT"}), "без типа")
	assert_false(IntervalsIcuClient.is_bike_workout({"type": "Ride"}), "без категории")
	assert_false(IntervalsIcuClient.is_bike_workout({"category": "WORKOUT", "type": null}))
	# Мусор в списке событий пропускается без падения.
	_mock.enqueue_json("GET", EVENTS_URL, 200, [1, "x", null, _bike_event(7, "Ok", "- 10m 65%")])
	var r2: ApiResult = await _client.get_today_workouts(TODAY)
	assert_true(r2.ok)
	assert_eq((r2.data as Array).size(), 1)


func test_req_int_02_c3_empty_response_is_no_workout_today_without_error() -> void:
	_mock.enqueue_json("GET", EVENTS_URL, 200, _fixture("events_empty.json"))
	var r: ApiResult = await _client.get_today_workouts(TODAY)
	assert_true(r.ok, "пустой ответ — не ошибка")
	assert_eq(r.code, ApiResult.CODE_NO_WORKOUT_TODAY)
	assert_eq((r.data as Array).size(), 0)
	assert_eq(_errors.size(), 0, "сигнал error не испускался")
	# Только не-велосипедные события — тоже «на сегодня тренировок нет».
	_mock.enqueue_json("GET", EVENTS_URL, 200, [{"id": 1, "category": "WORKOUT", "type": "Run", "name": "run"},
		{"id": 2, "category": "NOTE", "name": "note"}])
	var r2: ApiResult = await _client.get_today_workouts(TODAY)
	assert_true(r2.ok)
	assert_eq(r2.code, ApiResult.CODE_NO_WORKOUT_TODAY)


func test_req_int_02_c4_5xx_and_transport_errors_are_retryable_without_crash() -> void:
	for status in [500, 502, 503, 504]:
		_mock.enqueue_json("GET", EVENTS_URL, status, {"error": "boom"})
		var r: ApiResult = await _client.get_today_workouts(TODAY)
		assert_false(r.ok)
		assert_eq(r.code, ApiResult.CODE_NETWORK, "HTTP %d → network" % status)
		assert_true(r.can_retry, "есть кнопка «повторить»")
		assert_string_contains(r.message, "не удалось загрузить план")
		assert_eq(r.status, status)
	_mock.offline = true
	var off: ApiResult = await _client.get_today_workouts(TODAY)
	assert_eq(off.code, ApiResult.CODE_NETWORK)
	assert_true(off.can_retry)
	assert_string_contains(off.message, "не удалось загрузить план")
	assert_eq(off.status, 0)
	_mock.offline = false
	_mock.enqueue_failure("GET", EVENTS_URL, HttpResponse.ERR_TIMEOUT)
	var to: ApiResult = await _client.get_today_workouts(TODAY)
	assert_eq(to.code, ApiResult.CODE_NETWORK)
	assert_true(to.can_retry)
	assert_string_contains(to.message, "время ожидания")
	_mock.enqueue_failure("GET", EVENTS_URL, HttpResponse.ERR_NETWORK)
	var net: ApiResult = await _client.get_today_workouts(TODAY)
	assert_eq(net.code, ApiResult.CODE_NETWORK)
	assert_eq(_errors.size(), 7, "каждая ошибка — одним сигналом error")
	for e in _errors:
		assert_eq(e[0], ApiResult.CODE_NETWORK)
	assert_eq(_waited.size(), 0, "ожиданий (как при 429) не было")


func test_req_int_02_c5_429_waits_retry_after_and_retries_once() -> void:
	_mock.enqueue_json("GET", EVENTS_URL, 429, {}, {"Retry-After": "7"})
	_events_today()
	var r: ApiResult = await _client.get_today_workouts(TODAY)
	assert_true(r.ok, "после ожидания повтор удался")
	assert_eq(_waited, [7.0] as Array[float], "ожидание ровно Retry-After = 7 с")
	assert_eq(_client.waits, [7] as Array[int])
	assert_eq(_mock.request_count("GET", EVENTS_URL), 2, "ровно один повтор")
	assert_eq(_errors.size(), 0, "успешный повтор — без ошибки пользователю")
	# Повторный 429 → rate_limited с retry_after_sec второго ответа, третьего запроса нет.
	_mock.clear()
	_waited.clear()
	_mock.enqueue_json("GET", EVENTS_URL, 429, {}, {"Retry-After": "7"})
	_mock.enqueue_json("GET", EVENTS_URL, 429, {}, {"Retry-After": "12"})
	var r2: ApiResult = await _client.get_today_workouts(TODAY)
	assert_false(r2.ok)
	assert_eq(r2.code, ApiResult.CODE_RATE_LIMITED)
	assert_eq(r2.retry_after_sec, 12, "повторять не раньше чем через Retry-After второго ответа")
	assert_true(r2.can_retry)
	assert_eq(r2.status, 429)
	assert_eq(_waited, [7.0] as Array[float], "ждали один раз")
	assert_eq(_mock.request_count(), 2, "третьей попытки нет")
	assert_string_contains(r2.message, "12")
	assert_eq(_errors.size(), 1)
	assert_eq(_errors[0][0], ApiResult.CODE_RATE_LIMITED)


func test_req_int_02_c5_429_without_header_or_http_date_waits_60() -> void:
	_mock.enqueue_json("GET", EVENTS_URL, 429, {})
	_events_today()
	var r: ApiResult = await _client.get_today_workouts(TODAY)
	assert_true(r.ok)
	assert_eq(_waited, [60.0] as Array[float], "без Retry-After — 60 с")
	_waited.clear()
	_mock.clear()
	_mock.enqueue_json("GET", EVENTS_URL, 429, {}, {"Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"})
	_events_today()
	var r2: ApiResult = await _client.get_today_workouts(TODAY)
	assert_true(r2.ok)
	assert_eq(_waited, [60.0] as Array[float], "Retry-After датой HTTP — запасные 60 с")
	_waited.clear()
	_mock.clear()
	_mock.enqueue_json("GET", EVENTS_URL, 429, {}, {"retry-after": "2.5"})
	_mock.enqueue_json("GET", EVENTS_URL, 429, {})
	var r3: ApiResult = await _client.get_today_workouts(TODAY)
	assert_eq(_waited, [3.0] as Array[float], "дробное значение округляется вверх; имя заголовка без учёта регистра")
	assert_eq(r3.code, ApiResult.CODE_RATE_LIMITED)
	assert_eq(r3.retry_after_sec, 60, "второй 429 без заголовка → 60")
	# 429, затем 5xx — обычная сетевая ошибка.
	_waited.clear()
	_mock.clear()
	_mock.enqueue_json("GET", EVENTS_URL, 429, {}, {"Retry-After": "1"})
	_mock.enqueue_json("GET", EVENTS_URL, 500, {})
	var r4: ApiResult = await _client.get_today_workouts(TODAY)
	assert_eq(r4.code, ApiResult.CODE_NETWORK)
	assert_true(r4.can_retry)


func test_req_int_02_edge_malformed_bodies_are_bad_response_not_crash() -> void:
	_mock.enqueue("GET", EVENTS_URL, HttpResponse.make(200, "<html>oops</html>"))
	var r: ApiResult = await _client.get_today_workouts(TODAY)
	assert_false(r.ok)
	assert_eq(r.code, ApiResult.CODE_BAD_RESPONSE, "не-JSON")
	_mock.enqueue_json("GET", EVENTS_URL, 200, {"events": []})
	var r2: ApiResult = await _client.get_today_workouts(TODAY)
	assert_eq(r2.code, ApiResult.CODE_BAD_RESPONSE, "объект вместо массива событий")
	_mock.enqueue_json("GET", ATHLETE_URL, 200, [1, 2, 3])
	var r3: ApiResult = await _client.get_athlete()
	assert_eq(r3.code, ApiResult.CODE_BAD_RESPONSE, "массив вместо объекта атлета")
	_mock.enqueue("GET", ATHLETE_URL, HttpResponse.make(200, ""))
	var r4: ApiResult = await _client.get_athlete()
	assert_eq(r4.code, ApiResult.CODE_BAD_RESPONSE, "пустое тело")
	var r5: ApiResult = await _client.get_athlete()  # без заготовки → 404 по умолчанию
	assert_eq(r5.code, ApiResult.CODE_BAD_RESPONSE)
	assert_eq(r5.status, 404)
	assert_false(r5.can_retry)
	for e in _errors:
		assert_false(str(e[1]).contains(KEY))


# ===========================================================================
# REQ-INT-04 крит. 1–2 — данные для списка тренировок
# ===========================================================================

func test_req_int_04_c1_c2_entries_have_name_duration_and_load() -> void:
	_events_today()
	var r: ApiResult = await _client.get_today_workouts(TODAY)
	var e0: Dictionary = r.data[0]
	assert_eq(e0["name"], "Threshold 3x5")
	assert_eq(e0["duration_sec"], 2340, "длительность плана 10m + 3×(5m+3m) + 5m = 39:00")
	assert_eq(e0["training_load"], 65, "целевая нагрузка из ответа")
	assert_true(e0["workout"] is Workout)
	assert_eq((e0["workout"] as Workout).total_duration_sec(), 2340)
	assert_eq((e0["workout"] as Workout).source, "intervals_icu")
	assert_eq((e0["workout"] as Workout).name, "Threshold 3x5")
	var e1: Dictionary = r.data[1]
	assert_eq(e1["name"], "Endurance text")
	assert_eq(e1["duration_sec"], 2100, "текстовое описание: 10m + 20m + 5m")
	assert_eq(e1["training_load"], 40)
	assert_eq(IntervalsPlanService.format_duration(2340), "39:00", "мм:сс до часа")
	assert_eq(IntervalsPlanService.format_duration(2100), "35:00")
	assert_eq(IntervalsPlanService.format_duration(59), "00:59")
	assert_eq(IntervalsPlanService.format_duration(3600), "1:00:00", "ч:мм:сс от часа")
	assert_eq(IntervalsPlanService.format_duration(3725), "1:02:05")
	assert_eq(IntervalsPlanService.format_duration(-5), "00:00")
	# Одна тренировка → одна запись (UI «без списка» — T-040, n/a).
	_mock.enqueue_json("GET", EVENTS_URL, 200, [_bike_event(1, "Solo", "- 20m 70%", 1200, 30)])
	var one: ApiResult = await _client.get_today_workouts(TODAY)
	assert_eq((one.data as Array).size(), 1)
	assert_eq(one.data[0]["duration_sec"], 1200)
	assert_eq(one.data[0]["training_load"], 30)


func test_req_int_04_edge_event_with_parse_error_stays_in_list_without_workout() -> void:
	_mock.enqueue_json("GET", EVENTS_URL, 200, [
		_bike_event(11, "Good", "- 10m 65%", 600, 20),
		_bike_event(12, "HR based", "- 30m 140bpm", 1800, 35),
		_bike_event(13, "No load", "- 5m 50%"),
	])
	var r: ApiResult = await _client.get_today_workouts(TODAY)
	assert_true(r.ok, "одна битая тренировка не валит весь список")
	var entries: Array = r.data
	assert_eq(entries.size(), 3, "запись с ошибкой разбора остаётся в списке")
	var bad: Dictionary = entries[1]
	assert_null(bad["workout"], "workout == null")
	assert_eq(bad["name"], "HR based")
	assert_eq(bad["duration_sec"], 1800, "длительность — из moving_time события")
	assert_eq(bad["training_load"], 35)
	var pr: ParseResult = bad["parse_result"]
	assert_false(pr.ok())
	assert_gt(pr.error_messages().size(), 0, "причина ошибки доступна для UI")
	assert_eq(entries[2]["training_load"], 0, "нет нагрузки в ответе → 0")
	assert_eq(entries[2]["duration_sec"], 300)


# ===========================================================================
# REQ-INT-06 — FTP и зоны из Intervals.icu
# ===========================================================================

func test_req_int_06_c1_fixture_athlete_ftp_and_power_zones_written_to_profile() -> void:
	var athlete := IntervalsSync.parse_athlete(_fixture("athlete.json"))
	assert_eq(athlete["id"], ATHLETE)
	assert_eq(athlete["ftp"], 250, "FTP из велосипедных sportSettings, не из беговых (null)")
	assert_eq(athlete["indoor_ftp"], 245)
	assert_eq(athlete["max_hr"], 192)
	assert_eq(athlete["power_zones_pct"], [55.0, 75.0, 90.0, 105.0, 120.0, 150.0] as Array[float], "открытая 999 отброшена")
	assert_eq(athlete["power_zone_count"], 7)
	assert_false((athlete["warnings"] as Array).has(IntervalsSync.WARN_NO_BIKE_SETTINGS))
	var p := _profile(200)
	var warnings := IntervalsSync.apply_athlete_to_profile(p, athlete, false, TODAY)
	assert_eq(warnings, [] as Array[String], "фикстура применяется без предупреждений")
	assert_eq(p.ftp_w, 250)
	assert_eq(p.ftp_source, "intervals:" + TODAY, "источник FTP — Intervals с датой")
	assert_eq(p.zones_source, "intervals:" + TODAY)
	assert_eq(p.intervals_athlete_id, ATHLETE)
	assert_not_null(p.power_zones)
	assert_eq(p.power_zones.zone_count(), 7)
	assert_eq(p.power_zones.ftp_w, 250)
	assert_eq(p.power_zones.boundaries_pct, [55.0, 75.0, 90.0, 105.0, 120.0, 150.0] as Array[float])
	assert_eq(p.power_zone_of(137), 1, "55 % от 250 = 137.5: 137 → Z1")
	assert_eq(p.power_zone_of(138), 2)
	assert_eq(p.power_zone_of(376), 7)
	assert_eq(p.validate(), [] as Array[String], "профиль валиден после синхронизации")
	# Через клиента — тот же результат.
	_mock.enqueue_json("GET", ATHLETE_URL, 200, _fixture("athlete.json"))
	var r: ApiResult = await _client.get_athlete()
	assert_true(r.ok)
	var p2 := _profile(200)
	IntervalsSync.sync_profile(p2, r.data, TODAY)
	assert_eq(p2.ftp_w, 250)
	assert_eq(p2.power_zones.zone_count(), 7)
	# Через to_dict/from_dict зоны и источники сохраняются.
	var restored := Profile.from_dict(p2.to_dict())
	assert_eq(restored.ftp_source, "intervals:" + TODAY)
	assert_eq(restored.power_zones.zone_count(), 7)
	assert_eq(restored.power_zone_of(138), 2)


func test_req_int_06_c2_power_zones_in_watts_convert_to_rounded_percent_of_same_ftp() -> void:
	# Ватты с открытой верхней границей (≥ 10 × FTP) — автоопределение по порогу 250.
	assert_eq(IntervalsSync.power_zones_to_pct([138, 188, 225, 263, 300, 375, 2500], 250),
		[55.0, 75.0, 90.0, 105.0, 120.0, 150.0] as Array[float], "138/250 = 55.2 → 55 …")
	# Ватты без открытой границы — все значения остаются.
	assert_eq(IntervalsSync.power_zones_to_pct([138, 188, 225, 263, 300, 375], 250),
		[55.0, 75.0, 90.0, 105.0, 120.0, 150.0] as Array[float])
	# Явные единицы.
	assert_eq(IntervalsSync.power_zones_to_pct([110, 150, 180], 200, "watts"), [55.0, 75.0, 90.0] as Array[float])
	assert_eq(IntervalsSync.power_zones_to_pct([55, 75, 90], 200, "percent"), [55.0, 75.0, 90.0] as Array[float])
	# Округление до целого процента относительно FTP того же ответа.
	assert_eq(IntervalsSync.power_zones_to_pct([137, 189], 250, "watts"), [55.0, 76.0] as Array[float], "54.8 → 55, 75.6 → 76")
	# Ватты при FTP 0 — непригодны (явные единицы и автоопределение по значению > 250).
	assert_eq(IntervalsSync.power_zones_to_pct([138, 188, 300], 0, "watts"), [] as Array[float])
	assert_eq(IntervalsSync.power_zones_to_pct([138, 188, 300, 400], 0), [] as Array[float])
	# Наблюдение (граница эвристики): без значения > 250 среди не-последних список трактуется как
	# проценты — для FTP < ~170 ваттовые зоны автоопределением не распознаются.
	assert_eq(IntervalsSync.power_zones_to_pct([138, 188, 300], 0), [138.0, 188.0] as Array[float],
		"ambiguous: прочитано как 138 %, 188 % + открытая 300")
	# Нечисловые / невозрастающие — непригодны.
	assert_eq(IntervalsSync.power_zones_to_pct([55, "x", 90], 250), [] as Array[float])
	assert_eq(IntervalsSync.power_zones_to_pct([75, 55, 90], 250), [] as Array[float])
	assert_eq(IntervalsSync.power_zones_to_pct([55, 55, 90], 250), [] as Array[float])
	assert_eq(IntervalsSync.power_zones_to_pct([0, 55], 250), [] as Array[float])
	assert_eq(IntervalsSync.power_zones_to_pct([], 250), [] as Array[float])
	# Применение к профилю: 7 зон из ватт, зона считается по новому числу зон.
	var p := _profile(200)
	var athlete := IntervalsSync.parse_athlete(_athlete_json(250, [138, 188, 225, 263, 300, 375, 2500], null, 190))
	assert_eq(athlete["power_zones_pct"], [55.0, 75.0, 90.0, 105.0, 120.0, 150.0] as Array[float])
	var w := IntervalsSync.apply_athlete_to_profile(p, athlete, false, TODAY)
	assert_false(w.has(IntervalsSync.WARN_POWER_ZONES_COUNT))
	assert_eq(p.power_zones.zone_count(), 7)
	assert_eq(p.power_zone_of(375), 6)
	assert_eq(p.power_zone_of(376), 7)


func test_req_int_06_c2_zone_count_from_1_to_9_and_rejections() -> void:
	# 2 зоны (одна граница) и 9 зон (8 границ) принимаются.
	var p2 := _profile(200)
	IntervalsSync.apply_athlete_to_profile(p2, IntervalsSync.parse_athlete(_athlete_json(200, [60], null, 180)), false, TODAY)
	assert_eq(p2.power_zones.zone_count(), 2, "одна граница → 2 зоны")
	assert_eq(p2.power_zone_of(120), 1)
	assert_eq(p2.power_zone_of(121), 2)
	var p9 := _profile(200)
	var w9 := IntervalsSync.apply_athlete_to_profile(p9,
		IntervalsSync.parse_athlete(_athlete_json(200, [10, 20, 30, 40, 50, 60, 70, 80], null, 180)), false, TODAY)
	assert_eq(p9.power_zones.zone_count(), 9, "8 границ → 9 зон")
	assert_eq(p9.power_zone_of(161), 9)
	assert_false(w9.has(IntervalsSync.WARN_POWER_ZONES_COUNT))
	# 10 элементов (11 зон) → предупреждение, зоны профиля не меняются.
	var p10 := _profile(200)
	var before := p10.effective_power_zones().boundaries_pct.duplicate()
	var w10 := IntervalsSync.apply_athlete_to_profile(p10,
		IntervalsSync.parse_athlete(_athlete_json(200, [10, 20, 30, 40, 50, 60, 70, 80, 90, 100], null, 180)), false, TODAY)
	assert_true(w10.has(IntervalsSync.WARN_POWER_ZONES_COUNT), "> 9 зон — предупреждение")
	assert_null(p10.power_zones, "зоны профиля не изменены")
	assert_eq(p10.effective_power_zones().boundaries_pct, before)
	assert_eq(p10.ftp_w, 200, "FTP при этом применён")
	# Пустой список → предупреждение «нет зон», зоны не меняются.
	var p0 := _profile(200)
	var w0 := IntervalsSync.apply_athlete_to_profile(p0, IntervalsSync.parse_athlete(_athlete_json(200, [], null, 180)), false, TODAY)
	assert_true(w0.has(IntervalsSync.WARN_POWER_ZONES_MISSING))
	assert_null(p0.power_zones)
	# Один элемент — только открытая граница (999 с одним именем) → 0 границ → предупреждение.
	var p1 := _profile(200)
	var a1 := IntervalsSync.parse_athlete(_athlete_json(200, [999], null, 180, ["Z1"]))
	assert_true((a1["warnings"] as Array).has(IntervalsSync.WARN_POWER_ZONES_INVALID))
	var w1 := IntervalsSync.apply_athlete_to_profile(p1, a1, false, TODAY)
	assert_true(w1.has(IntervalsSync.WARN_POWER_ZONES_COUNT))
	assert_null(p1.power_zones)
	# Прежние пользовательские зоны при отказе сохраняются как были.
	var pk := _profile(200)
	pk.power_zones = PowerZones.custom(200, [50.0, 100.0] as Array[float])
	IntervalsSync.apply_athlete_to_profile(pk, IntervalsSync.parse_athlete(_athlete_json(200, [75, 55], null, 180)), false, TODAY)
	assert_eq(pk.power_zones.boundaries_pct, [50.0, 100.0] as Array[float], "невалидный список не трогает существующие зоны")


func test_req_int_06_c3_hr_zones_from_sport_settings_else_from_max_hr() -> void:
	# Фикстура: верхние границы [115,134,153,172,182,192] (192 = max HR, открытая) → нижние +1.
	assert_eq(IntervalsSync.hr_zones_to_bpm([115, 134, 153, 172, 182, 192], 192, ["Z1", "Z2", "Z3", "Z4", "Z5", "Z6"]),
		[116, 135, 154, 173, 183] as Array[int])
	var athlete := IntervalsSync.parse_athlete(_fixture("athlete.json"))
	assert_eq(athlete["hr_zones_bpm"], [116, 135, 154, 173, 183] as Array[int])
	assert_eq(athlete["hr_zone_count"], 6)
	var p := _profile(200)
	IntervalsSync.apply_athlete_to_profile(p, athlete, false, TODAY)
	assert_true(p.has_hr_zones())
	assert_true(p.hr_zones.is_absolute(), "границы в уд/мин")
	assert_eq(p.max_hr, 192)
	assert_eq(p.hr_zone_of(115), 1)
	assert_eq(p.hr_zone_of(116), 2, "верхняя граница 115 → с 116 начинается Z2")
	assert_eq(p.hr_zone_of(134), 2)
	assert_eq(p.hr_zone_of(135), 3)
	assert_eq(p.hr_zone_of(183), 6)
	assert_eq(p.hr_zone_of(200), 6)
	assert_eq(p.hr_zone_of(0), 0, "нет данных → нет зоны")
	# Без зон пульса — профиль считает зоны от max_hr (PRF-02.3).
	var p2 := _profile(200)
	var w2 := IntervalsSync.apply_athlete_to_profile(p2, IntervalsSync.parse_athlete(_athlete_json(250, [55, 75, 90, 105, 120, 150, 999], null, 180)), false, TODAY)
	assert_true(w2.has(IntervalsSync.WARN_HR_ZONES_MISSING))
	assert_null(p2.hr_zones)
	assert_eq(p2.max_hr, 180)
	assert_eq(p2.hr_zone_of(107), 1, "60 % от 180 = 108 → 107 Z1")
	assert_eq(p2.hr_zone_of(108), 2)
	assert_eq(p2.hr_zone_of(162), 5)
	# Зоны пульса без max_hr: без признака открытой границы все значения — границы.
	assert_eq(IntervalsSync.hr_zones_to_bpm([120, 140, 155, 170], 0), [121, 141, 156, 171] as Array[int])
	var p3 := _profile(200)
	var w3 := IntervalsSync.apply_athlete_to_profile(p3, IntervalsSync.parse_athlete(_athlete_json(250, [55, 75, 999], [120, 140, 155, 170], null)), false, TODAY)
	assert_true(p3.has_hr_zones(), "зоны доступны и без max_hr (абсолютные границы)")
	assert_eq(p3.hr_zone_of(171), 5)
	assert_false(w3.has(IntervalsSync.WARN_MAX_HR_MISSING))
	# Ни зон, ни max_hr → предупреждения, зон пульса нет.
	var p4 := _profile(200)
	var w4 := IntervalsSync.apply_athlete_to_profile(p4, IntervalsSync.parse_athlete(_athlete_json(250, [55, 75, 999], null, null)), false, TODAY)
	assert_true(w4.has(IntervalsSync.WARN_HR_ZONES_MISSING) and w4.has(IntervalsSync.WARN_MAX_HR_MISSING))
	assert_false(p4.has_hr_zones())
	assert_eq(p4.hr_zone_of(140), 0)
	# Невалидные зоны пульса — предупреждение разбора.
	var bad := IntervalsSync.parse_athlete(_athlete_json(250, [55, 75, 999], [150, 120], 190))
	assert_true((bad["warnings"] as Array).has(IntervalsSync.WARN_HR_ZONES_INVALID))
	assert_eq(IntervalsSync.hr_zones_to_bpm([120, "x"], 190), [] as Array[int])


func test_req_int_06_c5_c6_local_override_blocks_sync_and_resync_updates_otherwise() -> void:
	var p := _profile(200)
	p.max_hr = 175
	p.power_zones = PowerZones.custom(200, [50.0, 100.0] as Array[float])
	p.intervals_override_local = true
	var athlete := IntervalsSync.parse_athlete(_fixture("athlete.json"))
	var w := IntervalsSync.sync_profile(p, athlete, TODAY)
	assert_eq(w, [IntervalsSync.WARN_LOCAL_OVERRIDE] as Array[String])
	assert_eq(p.ftp_w, 200, "FTP не изменён")
	assert_eq(p.max_hr, 175, "max_hr не изменён")
	assert_eq(p.power_zones.boundaries_pct, [50.0, 100.0] as Array[float], "зоны мощности не изменены")
	assert_null(p.hr_zones, "зоны пульса не изменены")
	assert_eq(p.ftp_source, Profile.SOURCE_LOCAL)
	assert_eq(p.zones_source, Profile.SOURCE_LOCAL)
	assert_eq(p.intervals_athlete_id, "", "ничего не записано")
	# Снимаем переопределение — повторная синхронизация обновляет всё.
	p.intervals_override_local = false
	var w2 := IntervalsSync.sync_profile(p, athlete, TODAY)
	assert_eq(w2, [] as Array[String])
	assert_eq(p.ftp_w, 250)
	assert_eq(p.max_hr, 192)
	assert_eq(p.power_zones.zone_count(), 7)
	assert_true(p.hr_zones.is_absolute())
	assert_eq(p.ftp_source, "intervals:" + TODAY)
	# Ещё одна синхронизация с новыми значениями — обновляет (крит. 5).
	var newer := IntervalsSync.parse_athlete(_athlete_json(265, [50, 70, 90, 110, 999], [120, 150, 170, 195], 195,
		["Z1", "Z2", "Z3", "Z4", "Z5"], ["A", "B", "C", "D"]))
	var w3 := IntervalsSync.sync_profile(p, newer, "2026-10-03")
	assert_eq(w3, [] as Array[String])
	assert_eq(p.ftp_w, 265)
	assert_eq(p.ftp_source, "intervals:2026-10-03", "дата обновилась")
	assert_eq(p.power_zones.zone_count(), 5)
	assert_eq(p.power_zones.boundaries_pct, [50.0, 70.0, 90.0, 110.0] as Array[float])
	assert_eq(p.hr_zones.boundaries_bpm, [121, 151, 171] as Array[int])
	assert_eq(p.max_hr, 195)
	# И снова включённое переопределение останавливает изменения.
	p.intervals_override_local = true
	IntervalsSync.sync_profile(p, athlete, "2026-10-04")
	assert_eq(p.ftp_w, 265)
	assert_eq(p.ftp_source, "intervals:2026-10-03")
	assert_true(p.is_valid())


func test_req_int_06_c8_missing_or_out_of_range_ftp_keeps_local_value_with_warning() -> void:
	var p := _profile(210)
	var no_ftp := IntervalsSync.parse_athlete(_athlete_json(null, [55, 75, 90, 105, 120, 150, 999], null, 185))
	assert_true((no_ftp["warnings"] as Array).has(IntervalsSync.WARN_FTP_MISSING))
	var w := IntervalsSync.apply_athlete_to_profile(p, no_ftp, false, TODAY)
	assert_true(w.has(IntervalsSync.WARN_FTP_MISSING), "предупреждение пользователю")
	assert_eq(p.ftp_w, 210, "локальный FTP сохранён")
	assert_eq(p.ftp_source, Profile.SOURCE_LOCAL, "источник FTP остаётся локальным")
	assert_eq(p.power_zones.zone_count(), 7, "зоны в % применены относительно локального FTP")
	assert_eq(p.power_zones.ftp_w, 210)
	# FTP 0 и зоны в ваттах — зоны непригодны, FTP локальный.
	var p0 := _profile(210)
	var zero := IntervalsSync.parse_athlete(_athlete_json(0, [138, 188, 225, 263, 300, 375], null, 185))
	assert_true((zero["warnings"] as Array).has(IntervalsSync.WARN_FTP_MISSING))
	assert_true((zero["warnings"] as Array).has(IntervalsSync.WARN_POWER_ZONES_INVALID))
	var w0 := IntervalsSync.apply_athlete_to_profile(p0, zero, false, TODAY)
	assert_true(w0.has(IntervalsSync.WARN_FTP_MISSING))
	assert_eq(p0.ftp_w, 210)
	assert_null(p0.power_zones, "ваттовые зоны без FTP не применяются")
	# FTP вне диапазона профиля (50–600) — локальное значение, предупреждение.
	var big := _profile(210)
	var wb := IntervalsSync.apply_athlete_to_profile(big, IntervalsSync.parse_athlete(_athlete_json(700, null, null, 185)), false, TODAY)
	assert_true(wb.has(IntervalsSync.WARN_FTP_OUT_OF_RANGE))
	assert_eq(big.ftp_w, 210)
	assert_true(big.is_valid())
	# sportSettings без велотипа — предупреждение, берётся первая запись.
	var run_only := IntervalsSync.parse_athlete({"id": ATHLETE, "sportSettings": [{"types": ["Run"], "ftp": 300, "max_hr": 190}]})
	assert_true((run_only["warnings"] as Array).has(IntervalsSync.WARN_NO_BIKE_SETTINGS))
	assert_eq(run_only["ftp"], 300)
	var none := IntervalsSync.parse_athlete({"id": ATHLETE})
	assert_true((none["warnings"] as Array).has(IntervalsSync.WARN_NO_BIKE_SETTINGS))
	assert_eq(none["ftp"], 0)
	var pn := _profile(210)
	IntervalsSync.apply_athlete_to_profile(pn, none, false, TODAY)
	assert_eq(pn.ftp_w, 210)
	assert_true(pn.is_valid())


# ===========================================================================
# REQ-INT-07 — кэш плана; REQ-NFR-03 — работа без сети
# ===========================================================================

func test_req_int_07_c1_successful_load_saves_plan_with_date_and_time() -> void:
	_mock.enqueue_json("GET", EVENTS_URL, 200, [
		_bike_event(2001, "Threshold", "- 10m 65%\n- 20m 95%", 1800, 60),
		_bike_event(2002, "Broken", "- 30m Z2", 1800, 30),
	])
	var before := int(Time.get_unix_time_from_system())
	var r: ApiResult = await _service.load_today(TODAY)
	assert_true(r.ok)
	assert_eq(r.code, ApiResult.CODE_OK)
	assert_false(r.from_cache)
	assert_eq((r.data as Array).size(), 2, "в сетевой выдаче — обе записи (одна без плана)")
	assert_true(r.loaded_at >= before)
	var path := _cache.file_path(A, TODAY)
	assert_true(FileAccess.file_exists(path), "план сохранён в кэш профиля")
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(path)), OK)
	var rec: Dictionary = json.data
	assert_eq(rec["date"], TODAY, "дата")
	assert_true(int(rec["loaded_at"]) >= before, "время загрузки")
	assert_eq((rec["workouts"] as Array).size(), 1, "запись с ошибкой разбора в кэш не попадает")
	assert_eq(rec["workouts"][0]["event_id"], "2001")
	assert_eq(int(rec["workouts"][0]["duration_sec"]), 1800)
	assert_eq(int(rec["workouts"][0]["training_load"]), 60)
	assert_true(_cache.has(A, TODAY))
	assert_false(_cache.has(B, TODAY), "кэш — в профиле")


func test_req_int_07_c2_network_failure_falls_back_to_today_cache_with_label() -> void:
	_events_today()
	var online: ApiResult = await _service.load_today(TODAY)
	assert_true(online.ok)
	var loaded_at := online.loaded_at
	# Сеть недоступна на «следующем запуске».
	_mock.offline = true
	var r: ApiResult = await _service.load_today(TODAY)
	assert_true(r.ok, "кэш выдан как успешный результат")
	assert_true(r.from_cache)
	assert_eq(r.code, ApiResult.CODE_FROM_CACHE)
	assert_true(r.message.begins_with("из кэша, загружен "), r.message)
	assert_eq(r.loaded_at, loaded_at, "время загрузки — исходное")
	assert_true(r.can_retry)
	# Метка — в локальном поясе пользователя (как форматирует PlanCache), не в UTC.
	var dt := PlanCache.local_datetime(loaded_at)
	assert_string_contains(r.message, "%02d:%02d" % [dt["hour"], dt["minute"]], "время загрузки ЧЧ:ММ в локальном поясе")
	var entries: Array = r.data
	assert_eq(entries.size(), 2)
	assert_true(entries[0]["workout"] is Workout, "план восстановлен из кэша")
	assert_eq((entries[0]["workout"] as Workout).total_duration_sec(), 2340)
	assert_eq(entries[0]["name"], "Threshold 3x5")
	assert_eq(entries[0]["training_load"], 65)
	assert_eq((entries[1]["workout"] as Workout).total_duration_sec(), 2100)
	# 5xx и двойной 429 — тоже из кэша.
	_mock.offline = false
	_mock.enqueue_json("GET", EVENTS_URL, 503, {})
	var r5: ApiResult = await _service.load_today(TODAY)
	assert_true(r5.ok and r5.from_cache, "5xx → кэш")
	_mock.enqueue_json("GET", EVENTS_URL, 429, {}, {"Retry-After": "5"}, 2)
	var r429: ApiResult = await _service.load_today(TODAY)
	assert_true(r429.ok and r429.from_cache, "429 после повтора → кэш")
	assert_eq(_waited, [5.0] as Array[float])
	# REQ-INT-07 крит. 3: 401 — кэш не подменяет ошибку ключа.
	_mock.enqueue_json("GET", EVENTS_URL, 401, _fixture("error_401.json"))
	var r401: ApiResult = await _service.load_today(TODAY)
	assert_false(r401.ok)
	assert_eq(r401.code, ApiResult.CODE_AUTH_FAILED, "REQ-INT-07 крит. 3: 401 не подменяется кэшем")
	assert_false(r401.from_cache)
	# Не настроено — тоже без кэша.
	_store.delete_secret(_client.secret_key())
	var rnc: ApiResult = await _service.load_today(TODAY)
	assert_eq(rnc.code, ApiResult.CODE_NOT_CONFIGURED)
	assert_false(rnc.from_cache)


func test_req_int_07_c2_offline_without_cache_is_retryable_error_and_cache_errors_tolerated() -> void:
	_mock.offline = true
	var r: ApiResult = await _service.load_today(TODAY)
	assert_false(r.ok)
	assert_eq(r.code, ApiResult.CODE_NETWORK)
	assert_true(r.can_retry)
	assert_false(r.from_cache)
	var c: ApiResult = await _service.cached_today(TODAY)
	assert_false(c.ok)
	assert_true(c.can_retry)
	# Битый файл кэша — игнорируется, без падения.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_cache.profile_dir(A)))
	var f := FileAccess.open(_cache.file_path(A, TODAY), FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	assert_true(_cache.has(A, TODAY))
	assert_eq(_cache.get_today(A, TODAY), {})
	var rb: ApiResult = await _service.load_today(TODAY)
	assert_eq(rb.code, ApiResult.CODE_NETWORK, "битый кэш не предлагается")
	# Файл с чужой датой внутри — тоже не кэш на сегодня.
	var f2 := FileAccess.open(_cache.file_path(A, TODAY), FileAccess.WRITE)
	f2.store_string(JSON.stringify({"schema": 1, "date": YESTERDAY, "loaded_at": 1, "workouts": []}))
	f2.close()
	assert_eq(_cache.get_today(A, TODAY), {})
	# Пустой план кэшируется и воспроизводится без сети как «тренировок нет».
	_mock.offline = false
	_mock.enqueue_json("GET", EVENTS_URL, 200, [])
	var empty_online: ApiResult = await _service.load_today(TODAY)
	assert_true(empty_online.ok)
	assert_eq(empty_online.code, ApiResult.CODE_NO_WORKOUT_TODAY)
	_mock.offline = true
	var empty_cached: ApiResult = await _service.load_today(TODAY)
	assert_true(empty_cached.ok and empty_cached.from_cache)
	assert_eq(empty_cached.code, ApiResult.CODE_NO_WORKOUT_TODAY)


func test_req_int_07_c4_cache_of_other_date_is_not_offered_as_today() -> void:
	_mock.enqueue_json("GET", EVENTS_URL, 200, [_bike_event(1, "Yesterday", "- 10m 65%", 600, 20)])
	var y: ApiResult = await _service.load_today(YESTERDAY)
	assert_true(y.ok)
	assert_true(_cache.has(A, YESTERDAY))
	_mock.offline = true
	var r: ApiResult = await _service.load_today(TODAY)
	assert_false(r.ok, "REQ-INT-07 крит. 4: вчерашний кэш не предлагается как план на сегодня")
	assert_eq(r.code, ApiResult.CODE_NETWORK)
	assert_false(r.from_cache)
	var c: ApiResult = await _service.cached_today(TODAY)
	assert_false(c.ok)
	assert_eq(_cache.get_today(A, TODAY), {})
	assert_eq(_cache.load_date(A, YESTERDAY)["workouts"].size(), 1, "но по своей дате он читается")
	# Сохранение на сегодня вытесняет кэш других дат.
	_mock.offline = false
	_events_today()
	var t: ApiResult = await _service.load_today(TODAY)
	assert_true(t.ok)
	assert_true(_cache.has(A, TODAY))
	assert_false(_cache.has(A, YESTERDAY), "кэш другой даты удалён")
	assert_eq(_cache.load_date(A, "not-a-date"), {})
	assert_false(_cache.save(A, "02.10.2026", []), "некорректная дата не сохраняется")
	assert_false(_cache.save("", TODAY, []))


func test_req_int_07_c6_nfr_03_cached_plan_runs_full_session_with_zero_requests() -> void:
	_events_today()
	var online: ApiResult = await _service.load_today(TODAY)
	assert_true(online.ok)
	# «Следующий запуск»: сеть недоступна, план берём только из кэша.
	_mock.offline = true
	_mock.requests.clear()
	var cached: ApiResult = await _service.cached_today(TODAY)
	assert_true(cached.ok)
	assert_true(cached.from_cache)
	assert_eq(_mock.request_count(), 0, "cached_today — 0 сетевых запросов")
	var workout: Workout = cached.data[0]["workout"]
	assert_true(workout.is_valid())
	assert_eq(workout.total_duration_sec(), 2340)
	# Прогон тренировки на FakeTrainer: старт, пауза, возобновление, пропуск, финиш.
	var trainer := FakeTrainer.new(3)
	trainer.connect_delay_sec = 0.0
	trainer.connect_device("fake")
	var session := WorkoutSession.new(workout, trainer, 250)
	var finished: Array[int] = [0]  # массив: лямбда захватывает локальные значения копией
	session.session_finished.connect(func() -> void: finished[0] += 1)
	session.start()
	for i in 120:
		session.tick(1.0)
	session.pause()
	for i in 10:
		session.tick(1.0)
	session.resume()
	for i in 60:
		session.tick(1.0)
	session.set_intensity(0.9)
	session.skip_step()
	while session.get_state() != WorkoutSession.State.FINISHED:
		session.tick(1.0)
	assert_eq(finished[0], 1, "тренировка завершена")
	assert_eq(session.samples.size(), session.executor.elapsed_sec(), "сэмплы записаны за всё активное время")
	assert_gt(session.samples.size(), 180)
	assert_eq(_mock.request_count(), 0, "REQ-INT-07 крит. 6 / NFR-03 крит. 2: ни одного запроса от старта до финиша")
	assert_eq(trainer.commands.size() > 3, true, "команды на станок шли")
	# Повторный «запуск» без сети: тот же кэш, по-прежнему 0 запросов.
	var again: ApiResult = await _service.cached_today(TODAY)
	assert_true(again.ok)
	assert_eq(_mock.request_count(), 0)
	# NFR-03 крит. 1: load_today при offline тоже даёт план (из кэша), и после этого сессия идёт без сети.
	var fallback: ApiResult = await _service.load_today(TODAY)
	assert_true(fallback.ok and fallback.from_cache)
	assert_eq(_mock.request_count(), 1, "единственный запрос — попытка обновления, отклонённая офлайн")


# ===========================================================================
# REQ-PRF-03 — раздельные привязки профилей
# ===========================================================================

func test_req_prf_03_c1_key_of_profile_a_is_not_visible_to_profile_b() -> void:
	var client_b := IntervalsIcuClient.new(_mock, _store, B)
	client_b.base_url = BASE
	client_b.athlete_id = "i555"
	assert_true(_client.has_api_key())
	assert_false(client_b.has_api_key(), "ключ A недоступен B")
	assert_eq(_store.get_secret(SecureStore.key_for(B, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY)), "")
	var r: ApiResult = await client_b.get_athlete()
	assert_eq(r.code, ApiResult.CODE_NOT_CONFIGURED)
	assert_eq(_mock.request_count(), 0, "B без своего ключа запросов не делает (и не использует ключ A)")
	_store.set_secret(client_b.secret_key(), KEY_B)
	_mock.enqueue_json("GET", "*/athlete/i555", 200, _athlete_json(230, [55, 75, 999], null, 180))
	var rb: ApiResult = await client_b.get_athlete()
	assert_true(rb.ok)
	assert_eq(str(_mock.last_request()["headers"]["Authorization"]), _expected_auth(KEY_B), "B ходит со своим ключом")
	assert_eq(_store.list_keys(), ["profile-a/intervals/api_key", "profile-b/intervals/api_key"] as Array[String])


func test_req_prf_03_c2_forget_key_removes_only_intervals_of_this_profile() -> void:
	_store.set_secret(SecureStore.key_for(A, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN), "strava-access-A")
	_store.set_secret(SecureStore.key_for(A, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_REFRESH_TOKEN), "strava-refresh-A")
	_store.set_secret(SecureStore.key_for(B, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY), KEY_B)
	assert_eq(_store.size(), 4)
	_client.forget_key()
	assert_false(_client.has_api_key(), "ключ Intervals профиля A удалён")
	assert_eq(_store.get_secret(SecureStore.key_for(A, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN)), "strava-access-A", "Strava A не тронута")
	assert_eq(_store.get_secret(SecureStore.key_for(A, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_REFRESH_TOKEN)), "strava-refresh-A")
	assert_eq(_store.get_secret(SecureStore.key_for(B, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY)), KEY_B, "Intervals B не тронут")
	assert_eq(_store.size(), 3)
	var r: ApiResult = await _client.get_athlete()
	assert_eq(r.code, ApiResult.CODE_NOT_CONFIGURED, "после отвязки запросы не идут")
	_client.forget_key()
	assert_eq(_store.size(), 3, "повторная отвязка — без побочных эффектов")


func test_req_prf_03_c3_secrets_never_land_in_profile_or_cache_files() -> void:
	var repo := ProfileRepository.new(_dir + "profiles/")
	var p := repo.create("Rider A")
	p.intervals_athlete_id = ATHLETE
	_mock.enqueue_json("GET", ATHLETE_URL, 200, _fixture("athlete.json"))
	var r: ApiResult = await _client.get_athlete()
	IntervalsSync.sync_profile(p, r.data, TODAY)
	assert_eq(repo.save(p), [] as Array[String])
	_events_today()
	var plan: ApiResult = await _service.load_today(TODAY)
	assert_true(plan.ok)
	var dict_json := JSON.stringify(p.to_dict())
	assert_false(dict_json.contains(KEY), "Profile.to_dict() без ключа")
	assert_false(dict_json.to_lower().contains("api_key"), "и без поля для ключа")
	assert_true(dict_json.contains(ATHLETE), "Athlete ID — не секрет, хранится")
	var files: Array[String] = []
	_all_files(ProjectSettings.globalize_path(_dir), files)
	assert_gt(files.size(), 1, "есть файл профиля и файл кэша")
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.contains(KEY), "файл %s не содержит ключ" % path)
		assert_false(text.contains(Marshalls.utf8_to_base64("API_KEY:" + KEY)), "и его base64-форму")
	assert_eq(_store.get_secret(_client.secret_key()), KEY, "ключ только в SecureStore")


func test_req_prf_03_cascade_profile_deletion_clears_key_and_cache_of_that_profile_only() -> void:
	var repo := ProfileRepository.new(_dir + "profiles/")
	var pa := repo.create("A")
	var pb := repo.create("B")
	_store.attach_to_profiles(repo)
	_cache.attach_to_profiles(repo)
	var key_a := SecureStore.key_for(pa.id, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY)
	var key_b := SecureStore.key_for(pb.id, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY)
	_store.set_secret(key_a, "key-A")
	_store.set_secret(key_b, "key-B")
	_store.set_secret(SecureStore.key_for(pa.id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN), "strava-A")
	var entry := IntervalsIcuClient.entry_from_event(_bike_event(1, "W", "- 10m 65%", 600, 20))
	assert_true(_cache.save(pa.id, TODAY, [entry]))
	assert_true(_cache.save(pb.id, TODAY, [entry]))
	assert_eq(repo.delete(pa.id), "", "профиль A удалён")
	assert_false(_store.has_secret(key_a), "ключ Intervals A удалён каскадом")
	assert_false(_store.has_secret(SecureStore.key_for(pa.id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN)), "и Strava A")
	assert_true(_store.has_secret(key_b), "ключ B остался")
	assert_false(_cache.has(pa.id, TODAY), "кэш A удалён")
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_cache.profile_dir(pa.id))))
	assert_true(_cache.has(pb.id, TODAY), "кэш B остался")
	assert_eq(_cache.load_date(pb.id, TODAY)["workouts"].size(), 1)


# ===========================================================================
# Уточнения 3e2258d: REQ-INT-06 крит. 2–4 (В-13), REQ-INT-02 крит. 5, REQ-INT-07 крит. 5
# ===========================================================================

func test_req_int_06_c2_v13_percent_vector_with_open_999_at_ftp_200() -> void:
	# Тест из требования: [55, 75, 90, 105, 120, 150, 999] при FTP 200 → 7 зон 55/75/90/105/120/150 %.
	var athlete := IntervalsSync.parse_athlete(_athlete_json(200, [55, 75, 90, 105, 120, 150, 999], null, 185))
	assert_eq(athlete["power_zones_pct"], [55.0, 75.0, 90.0, 105.0, 120.0, 150.0] as Array[float])
	assert_eq(athlete["power_zone_count"], 7)
	var p := _profile(180)
	var w := IntervalsSync.apply_athlete_to_profile(p, athlete, false, TODAY)
	assert_false(w.has(IntervalsSync.WARN_POWER_ZONES_COUNT))
	assert_eq(p.ftp_w, 200)
	assert_eq(p.power_zones.zone_count(), 7)
	assert_eq(p.power_zones.boundaries_pct, [55.0, 75.0, 90.0, 105.0, 120.0, 150.0] as Array[float])
	assert_eq(p.power_zone_of(110), 1, "PRF-02.6 при FTP 200: 110 → Z1")
	assert_eq(p.power_zone_of(111), 2)
	assert_eq(p.power_zone_of(301), 7)


func test_req_int_06_c2_v13_watts_vector_with_open_999_at_ftp_200_gives_same_percents() -> void:
	# Тест из требования: [110, 150, 180, 210, 240, 300, 999] при FTP 200 → те же проценты
	# (значения выглядят как ватты: 300 > 250; открытая 999 отбрасывается).
	var pct := IntervalsSync.power_zones_to_pct([110, 150, 180, 210, 240, 300, 999], 200)
	assert_eq(pct, [55.0, 75.0, 90.0, 105.0, 120.0, 150.0] as Array[float],
		"ваттовый список с открытой 999 → 55/75/90/105/120/150 %% (факт %s)" % str(pct))
	var athlete := IntervalsSync.parse_athlete(_athlete_json(200, [110, 150, 180, 210, 240, 300, 999], null, 185))
	assert_eq(athlete["power_zone_count"], 7, "7 зон, а не 8 с границей 500 %")
	var p := _profile(180)
	var w := IntervalsSync.apply_athlete_to_profile(p, athlete, false, TODAY)
	assert_false(w.has(IntervalsSync.WARN_POWER_ZONES_COUNT))
	assert_not_null(p.power_zones)
	if p.power_zones != null:
		assert_eq(p.power_zones.zone_count(), 7)
		assert_eq(p.power_zone_of(301), 7, "выше 150 % — последняя зона Z7")
	# С именами зон (как в фикстуре) открытая граница распознаётся по числу имён — для сравнения.
	var with_names := IntervalsSync.power_zones_to_pct([110, 150, 180, 210, 240, 300, 999], 200, "auto",
		["Z1", "Z2", "Z3", "Z4", "Z5", "Z6", "Z7"])
	assert_eq(with_names, [55.0, 75.0, 90.0, 105.0, 120.0, 150.0] as Array[float])


func test_req_int_06_c3_v13_hr_zones_upper_bounds_to_lower_plus_one_and_max_hr_from_response() -> void:
	# Тест из требования: hr_zones [120, 140, 160, 175, 190] → нижние границы зон 2..5 = 121, 141, 161, 176;
	# max_hr = значение ответа (190).
	assert_eq(IntervalsSync.hr_zones_to_bpm([120, 140, 160, 175, 190], 190), [121, 141, 161, 176] as Array[int])
	var athlete := IntervalsSync.parse_athlete(_athlete_json(200, [55, 75, 90, 105, 120, 150, 999], [120, 140, 160, 175, 190], 190))
	assert_eq(athlete["hr_zones_bpm"], [121, 141, 161, 176] as Array[int])
	assert_eq(athlete["hr_zone_count"], 5)
	assert_eq(athlete["max_hr"], 190)
	var p := _profile(200)
	var w := IntervalsSync.apply_athlete_to_profile(p, athlete, false, TODAY)
	assert_false(w.has(IntervalsSync.WARN_HR_ZONES_MISSING))
	assert_eq(p.max_hr, 190, "max_hr из sportSettings")
	assert_true(p.hr_zones.is_absolute())
	assert_eq(p.hr_zones.boundaries_bpm, [121, 141, 161, 176] as Array[int])
	assert_eq(p.hr_zone_of(120), 1, "верхняя граница Z1 включительно")
	assert_eq(p.hr_zone_of(121), 2)
	assert_eq(p.hr_zone_of(140), 2)
	assert_eq(p.hr_zone_of(141), 3)
	assert_eq(p.hr_zone_of(175), 4)
	assert_eq(p.hr_zone_of(176), 5)
	assert_eq(p.hr_zone_of(190), 5)
	assert_eq(p.hr_zone_of(0), 0)
	assert_eq(p.zones_source, "intervals:" + TODAY)
	assert_true(p.is_valid())


func test_req_int_06_c4_v13_sources_format_default_local_and_intervals_date_after_sync() -> void:
	var p := _profile(200)
	assert_eq(p.ftp_source, "local", "по умолчанию — local")
	assert_eq(p.zones_source, "local")
	assert_false(p.intervals_override_local)
	assert_true(Profile.is_valid_source("local"))
	assert_true(Profile.is_valid_source("intervals:2026-10-02"))
	assert_false(Profile.is_valid_source("strava"))
	assert_false(Profile.is_valid_source(""))
	var athlete := IntervalsSync.parse_athlete(_fixture("athlete.json"))
	IntervalsSync.sync_profile(p, athlete, TODAY)
	assert_eq(p.ftp_source, "intervals:" + TODAY, "после синхронизации без переопределения — intervals:<дата>")
	assert_eq(p.zones_source, "intervals:" + TODAY)
	var d := p.to_dict()
	assert_eq(d["ftp_source"], "intervals:" + TODAY)
	assert_eq(d["zones_source"], "intervals:" + TODAY)
	assert_eq(d["intervals_override_local"], false)
	p.intervals_override_local = true
	var restored := Profile.from_dict(p.to_dict())
	assert_true(restored.intervals_override_local, "флаг переопределения сохраняется")
	assert_eq(restored.ftp_source, "intervals:" + TODAY)
	assert_true(restored.is_valid())
	# Мусор в источнике отклоняется валидацией, пустое → local.
	var bad := Profile.from_dict({"id": "x", "name": "N", "ftp_source": "garbage"})
	assert_true(bad.validate().has(Profile.ERR_SOURCE_INVALID))
	var empty := Profile.from_dict({"id": "x", "name": "N", "ftp_source": ""})
	assert_eq(empty.ftp_source, "local")
	# Дата синхронизации по умолчанию — сегодняшняя локальная.
	var p2 := _profile(200)
	IntervalsSync.sync_profile(p2, athlete)
	assert_eq(p2.ftp_source, "intervals:" + Time.get_date_string_from_system(false))


func test_req_int_02_c5_v13_unparseable_retry_after_falls_back_to_60() -> void:
	_mock.enqueue_json("GET", EVENTS_URL, 429, {}, {"Retry-After": "soon"})
	_events_today()
	var r: ApiResult = await _client.get_today_workouts(TODAY)
	assert_true(r.ok)
	assert_eq(_waited, [60.0] as Array[float], "нечитаемое значение → 60 с")
	_waited.clear()
	_mock.enqueue_json("GET", EVENTS_URL, 429, {}, {"Retry-After": "30"})
	_events_today()
	var r2: ApiResult = await _client.get_today_workouts(TODAY)
	assert_true(r2.ok)
	assert_eq(_waited, [30.0] as Array[float], "Retry-After: 30 → 30 с")
	_waited.clear()
	_mock.enqueue_json("GET", EVENTS_URL, 429, {}, {"Retry-After": ""})
	_events_today()
	var r3: ApiResult = await _client.get_today_workouts(TODAY)
	assert_true(r3.ok)
	assert_eq(_waited, [60.0] as Array[float], "пустой заголовок → 60 с")


func test_req_int_07_c5_unparsed_entries_in_network_list_but_absent_from_cache_load() -> void:
	_mock.enqueue_json("GET", EVENTS_URL, 200, [
		_bike_event(31, "Good", "- 10m 65%\n- 5m 50%", 900, 25),
		_bike_event(32, "Pace based", "- 20m 4:30/km", 1200, 30),
		_bike_event(33, "Also good", "- 15m 75%", 900, 28),
	])
	var online: ApiResult = await _service.load_today(TODAY)
	assert_true(online.ok)
	var entries: Array = online.data
	assert_eq(entries.size(), 3, "в сетевой выдаче — все три")
	assert_null(entries[1]["workout"], "битая запись — workout == null")
	var pr: ParseResult = entries[1]["parse_result"]
	assert_false(pr.ok())
	assert_false(pr.user_message().is_empty(), "сообщение об ошибке разбора для UI")
	assert_gt(pr.error_messages().size(), 0)
	_mock.offline = true
	var cached: ApiResult = await _service.load_today(TODAY)
	assert_true(cached.ok and cached.from_cache)
	var from_cache: Array = cached.data
	assert_eq(from_cache.size(), 2, "при следующей загрузке из кэша битой записи нет")
	for e in from_cache:
		assert_true(e["workout"] is Workout, "в кэше — только разобранные планы")
		assert_ne(e["event_id"], "32")
	assert_eq(from_cache[0]["event_id"], "31")
	assert_eq(from_cache[1]["event_id"], "33")
	assert_eq(from_cache[1]["training_load"], 28)
