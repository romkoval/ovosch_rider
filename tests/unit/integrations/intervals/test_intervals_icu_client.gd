extends GutTest
## Тесты IntervalsIcuClient на моке транспорта (REQ-INT-01 крит. 1–3, REQ-INT-02 крит. 1–5,
## REQ-PRF-03 крит. 1, 2, REQ-NFR-03 крит. 2).

const FIXTURES: String = "res://tests/fixtures/intervals/"
const PROFILE: String = "profile-1"
const ATHLETE: String = "i12345"
const KEY: String = "fixture-api-key-9f8e7d6c"
const BASE: String = "https://mock.intervals.test"

var _mock: MockHttpTransport
var _store: MemorySecureStore
var _client: IntervalsIcuClient
var _errors: Array[Array] = []


func before_each() -> void:
	_mock = MockHttpTransport.new()
	_store = MemorySecureStore.new()
	_client = IntervalsIcuClient.new(_mock, _store, PROFILE)
	_client.base_url = BASE
	_client.athlete_id = ATHLETE
	_client.wait_fn = func(_sec: float) -> void: pass
	_errors = []
	_client.error.connect(func(code: String, message: String) -> void: _errors.append([code, message]))
	_store.set_secret(_client.secret_key(), KEY)


static func _fixture(name: String) -> Variant:
	var json := JSON.new()
	assert(json.parse(FileAccess.get_file_as_string(FIXTURES + name)) == OK)
	return json.data


func _expected_auth() -> String:
	return "Basic " + Marshalls.utf8_to_base64("API_KEY:" + KEY)


# ---------------------------------------------------------------------------
# Авторизация и хранение ключа (REQ-INT-01 крит. 1, 2; REQ-PRF-03 крит. 1, 2)
# ---------------------------------------------------------------------------

func test_every_request_has_basic_api_key_header_and_timeout() -> void:
	_mock.enqueue_json("GET", "/athlete/", 200, _fixture("athlete.json"))
	var r: ApiResult = await _client.get_athlete()
	assert_true(r.ok, r.message)
	var req := _mock.last_request()
	assert_eq(str(req["headers"]["Authorization"]), _expected_auth(), "REQ-INT-01 крит. 1")
	assert_eq(str(req["headers"]["Accept"]), "application/json")
	assert_eq(float(req["timeout_sec"]), 15.0, "таймаут 15 с")
	assert_eq(str(req["url"]), BASE + "/api/v1/athlete/" + ATHLETE)


func test_key_lives_in_secure_store_under_profile_key() -> void:
	assert_eq(_client.secret_key(), "profile-1/intervals/api_key", "REQ-PRF-03 крит. 1")
	assert_true(_client.has_api_key())
	assert_true(_client.is_configured())
	var other := IntervalsIcuClient.new(_mock, _store, "profile-2")
	assert_false(other.has_api_key(), "REQ-PRF-03 крит. 1: ключ профиля A недоступен профилю B")


func test_without_key_no_request_is_made() -> void:
	_store.delete_secret(_client.secret_key())
	var r: ApiResult = await _client.get_athlete()
	assert_false(r.ok)
	assert_eq(r.code, ApiResult.CODE_NOT_CONFIGURED)
	assert_eq(_mock.request_count(), 0, "REQ-NFR-03 крит. 2: без ключа нет запросов")
	_store.set_secret(_client.secret_key(), KEY)
	_client.athlete_id = ""
	var r2: ApiResult = await _client.get_events("2026-10-02", "2026-10-02")
	assert_eq(r2.code, ApiResult.CODE_NOT_CONFIGURED)
	assert_eq(_mock.request_count(), 0)


func test_errors_and_to_string_never_contain_the_key() -> void:
	_mock.enqueue_json("GET", "/athlete/", 401, _fixture("error_401.json"))
	_mock.enqueue_json("GET", "/events", 500, {"error": "boom"})
	_mock.enqueue("GET", "/athlete/", HttpResponse.make(200, "not json"))
	var results: Array[ApiResult] = [
		await _client.get_athlete(),
		await _client.get_events("2026-10-02", "2026-10-02"),
		await _client.get_athlete(),
	]
	for r in results:
		assert_false(r.ok)
		assert_false(r.message.contains(KEY), "REQ-INT-01 крит. 2: '%s' без ключа" % r.message)
		assert_false(r.message.contains(Marshalls.utf8_to_base64("API_KEY:" + KEY)), "и без base64 ключа")
		assert_gt(r.message.length(), 0)
	assert_false(str(_client).contains(KEY), "str(client) маскирует ключ: %s" % str(_client))
	assert_string_contains(str(_client), "***")
	for e in _errors:
		assert_false(str(e[1]).contains(KEY), "сигнал error без ключа")
	assert_eq(_errors.size(), 3, "сигнал error на каждую ошибку")


func test_forget_key_removes_only_intervals_secret_of_profile() -> void:
	_store.set_secret(SecureStore.key_for(PROFILE, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN), "strava-token-fixture")
	_store.set_secret(SecureStore.key_for("profile-2", SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY), "other-fixture-key")
	_client.forget_key()
	assert_false(_client.has_api_key())
	assert_true(_store.has_secret(SecureStore.key_for(PROFILE, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN)), "REQ-PRF-03 крит. 2: Strava цела")
	assert_true(_store.has_secret(SecureStore.key_for("profile-2", SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY)), "другой профиль цел")


# ---------------------------------------------------------------------------
# verify_key (REQ-INT-01 крит. 3)
# ---------------------------------------------------------------------------

func test_verify_key_success_stores_key_and_athlete_id() -> void:
	var fresh := IntervalsIcuClient.new(_mock, _store, "profile-new")
	fresh.base_url = BASE
	_mock.enqueue_json("GET", "/athlete/i777", 200, _fixture("athlete.json"))
	var r: ApiResult = await fresh.verify_key(" i777 ", KEY)
	assert_true(r.ok, r.message)
	assert_eq(_store.get_secret(fresh.secret_key()), KEY, "ключ сохранён после успешной проверки")
	assert_eq(fresh.athlete_id, "i777")
	assert_eq(str(_mock.last_request()["headers"]["Authorization"]), _expected_auth(), "проверочный запрос с тем же заголовком")
	assert_eq(int(r.data["ftp"]), 250, "данные атлета возвращены")
	assert_eq(str(r.data["name"]), "Test Athlete", "REQ-INT-01 крит. 4 (данные для имени атлета)")


func test_verify_key_rejected_401_not_stored() -> void:
	var fresh := IntervalsIcuClient.new(_mock, _store, "profile-new")
	fresh.base_url = BASE
	_mock.enqueue_json("GET", "/athlete/", 401, _fixture("error_401.json"))
	var r: ApiResult = await fresh.verify_key("i777", "wrong-fixture-key")
	assert_false(r.ok)
	assert_eq(r.code, ApiResult.CODE_AUTH_FAILED)
	assert_eq(r.message, "ключ не принят", "REQ-INT-01 крит. 3")
	assert_false(fresh.has_api_key(), "REQ-INT-01 крит. 3: ключ не сохранён")
	assert_eq(fresh.athlete_id, "")
	_mock.enqueue_json("GET", "/athlete/", 403, {})
	var r403: ApiResult = await fresh.verify_key("i777", "wrong-fixture-key")
	assert_eq(r403.code, ApiResult.CODE_AUTH_FAILED, "403 — тоже «ключ не принят»")
	assert_false(fresh.has_api_key())


func test_verify_key_requires_both_inputs_and_survives_network_error() -> void:
	var fresh := IntervalsIcuClient.new(_mock, _store, "profile-new")
	var empty: ApiResult = await fresh.verify_key("", KEY)
	assert_eq(empty.code, ApiResult.CODE_NOT_CONFIGURED)
	assert_eq(_mock.request_count(), 0)
	_mock.offline = true
	var off: ApiResult = await fresh.verify_key("i777", KEY)
	assert_eq(off.code, ApiResult.CODE_NETWORK)
	assert_true(off.can_retry)
	assert_false(fresh.has_api_key(), "при сетевой ошибке ключ не сохраняется")


# ---------------------------------------------------------------------------
# Профиль атлета и события (REQ-INT-02 крит. 1–3)
# ---------------------------------------------------------------------------

func test_get_athlete_returns_parsed_bike_settings() -> void:
	_mock.enqueue_json("GET", "/athlete/", 200, _fixture("athlete.json"))
	var r: ApiResult = await _client.get_athlete()
	assert_true(r.ok)
	assert_eq(int(r.data["ftp"]), 250)
	assert_eq(int(r.data["max_hr"]), 192)
	assert_eq(r.data["power_zones_pct"], [55.0, 75.0, 90.0, 105.0, 120.0, 150.0])
	assert_eq(int(r.data["power_zone_count"]), 7)
	assert_eq(r.status, 200)
	assert_gt(r.loaded_at, 0)


func test_get_events_url_has_dates_and_workout_category() -> void:
	_mock.enqueue_json("GET", "/events", 200, _fixture("events_today.json"))
	var r: ApiResult = await _client.get_events("2026-10-02", "2026-10-02")
	assert_true(r.ok)
	assert_eq(str(_mock.last_request()["url"]),
			BASE + "/api/v1/athlete/i12345/events?oldest=2026-10-02&newest=2026-10-02&category=WORKOUT",
			"REQ-INT-02 крит. 1: oldest = newest = дата")
	assert_eq((r.data as Array).size(), 5, "события отданы как есть")


func test_today_workouts_keeps_only_bike_workouts_and_parses_them() -> void:
	_mock.enqueue_json("GET", "/events", 200, _fixture("events_today.json"))
	var r: ApiResult = await _client.get_today_workouts("2026-10-02")
	assert_true(r.ok, r.message)
	assert_eq(r.code, ApiResult.CODE_OK)
	var list: Array = r.data
	assert_eq(list.size(), 2, "REQ-INT-02 крит. 2: заметка, бег и гонка отфильтрованы")
	assert_eq(str(list[0]["event_id"]), "2001")
	assert_eq(str(list[0]["name"]), "Threshold 3x5")
	assert_eq(int(list[0]["duration_sec"]), 2340)
	assert_eq(int(list[0]["training_load"]), 65, "REQ-INT-04 крит. 2: нагрузка из ответа")
	assert_true(list[0]["workout"] is Workout)
	assert_eq((list[0]["workout"] as Workout).steps.size(), 1 + 6 + 1)
	assert_eq(str(list[1]["event_id"]), "2002")
	assert_eq((list[1]["workout"] as Workout).total_duration_sec(), 2100, "описание без workout_doc разобрано")
	assert_true((list[1]["parse_result"] as ParseResult).ok())


func test_today_workouts_default_date_is_local_today() -> void:
	_mock.enqueue_json("GET", "/events", 200, [])
	await _client.get_today_workouts()
	var today := IntervalsIcuClient.local_date()
	assert_true(RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$").search(today) != null)
	assert_string_contains(str(_mock.last_request()["url"]), "oldest=%s&newest=%s" % [today, today], "REQ-INT-02 крит. 1")


func test_empty_events_is_no_workout_today_not_error() -> void:
	_mock.enqueue_json("GET", "/events", 200, _fixture("events_empty.json"))
	var r: ApiResult = await _client.get_today_workouts("2026-10-02")
	assert_true(r.ok, "REQ-INT-02 крит. 3")
	assert_eq(r.code, ApiResult.CODE_NO_WORKOUT_TODAY)
	assert_eq((r.data as Array).size(), 0)
	assert_eq(_errors.size(), 0)


func test_workout_with_parse_error_stays_in_list_without_workout() -> void:
	_mock.enqueue_json("GET", "/events", 200, [
		{"id": 1, "category": "WORKOUT", "type": "Ride", "name": "HR based", "description": "- 20m 140-150bpm"},
	])
	var r: ApiResult = await _client.get_today_workouts("2026-10-02")
	assert_true(r.ok)
	var list: Array = r.data
	assert_eq(list.size(), 1)
	assert_null(list[0]["workout"], "REQ-INT-03 крит. 9: план с ошибкой не запускается")
	assert_gt((list[0]["parse_result"] as ParseResult).errors.size(), 0)


func test_is_bike_workout_rules() -> void:
	assert_true(IntervalsIcuClient.is_bike_workout({"category": "WORKOUT", "type": "Ride"}))
	assert_true(IntervalsIcuClient.is_bike_workout({"category": "workout", "type": "VirtualRide"}))
	assert_false(IntervalsIcuClient.is_bike_workout({"category": "WORKOUT", "type": "Run"}))
	assert_false(IntervalsIcuClient.is_bike_workout({"category": "NOTE", "type": "Ride"}))
	assert_false(IntervalsIcuClient.is_bike_workout({"category": "WORKOUT"}))


# ---------------------------------------------------------------------------
# Ошибки (REQ-INT-02 крит. 4, 5)
# ---------------------------------------------------------------------------

func test_5xx_is_network_error_with_retry() -> void:
	_mock.enqueue_json("GET", "/events", 503, {"error": "unavailable"})
	var r: ApiResult = await _client.get_today_workouts("2026-10-02")
	assert_false(r.ok)
	assert_eq(r.code, ApiResult.CODE_NETWORK, "REQ-INT-02 крит. 4")
	assert_true(r.can_retry, "кнопка «повторить»")
	assert_eq(r.status, 503)
	assert_string_contains(r.message, "не удалось загрузить план")


func test_transport_errors_offline_and_timeout() -> void:
	_mock.offline = true
	var off: ApiResult = await _client.get_athlete()
	assert_eq(off.code, ApiResult.CODE_NETWORK, "REQ-INT-02 крит. 4: сеть недоступна")
	assert_true(off.can_retry)
	assert_eq(_mock.request_count(), 1)
	_mock.offline = false
	_mock.enqueue_failure("GET", "/athlete/", HttpResponse.ERR_TIMEOUT)
	var to: ApiResult = await _client.get_athlete()
	assert_eq(to.code, ApiResult.CODE_NETWORK)
	assert_string_contains(to.message, "время ожидания")


func test_429_waits_retry_after_and_retries_once() -> void:
	var waited: Array[float] = []
	_client.wait_fn = func(sec: float) -> void: waited.append(sec)
	_mock.enqueue("GET", "/events", HttpResponse.json_response(429, {}, {"Retry-After": "7"}))
	_mock.enqueue_json("GET", "/events", 200, _fixture("events_today.json"))
	var r: ApiResult = await _client.get_today_workouts("2026-10-02")
	assert_true(r.ok, "после ожидания повтор удался")
	assert_eq(waited, [7.0], "REQ-INT-02 крит. 5: ожидание ровно Retry-After")
	assert_eq(_client.waits, [7])
	assert_eq(_mock.request_count(), 2, "ровно один повтор")


func test_429_without_header_waits_60_and_second_429_is_rate_limited() -> void:
	_mock.enqueue("GET", "/events", HttpResponse.json_response(429, {}), -1)
	var r: ApiResult = await _client.get_today_workouts("2026-10-02")
	assert_false(r.ok)
	assert_eq(r.code, ApiResult.CODE_RATE_LIMITED)
	assert_eq(r.retry_after_sec, 60, "REQ-INT-02 крит. 5: по умолчанию 60 с")
	assert_eq(_client.waits, [60])
	assert_true(r.can_retry)
	assert_eq(_mock.request_count(), 2, "не более одного повтора")
	assert_eq(r.status, 429)


func test_malformed_bodies_are_bad_response_not_crash() -> void:
	_mock.enqueue("GET", "/athlete/", HttpResponse.make(200, "<html>"))
	var a: ApiResult = await _client.get_athlete()
	assert_eq(a.code, ApiResult.CODE_BAD_RESPONSE)
	_mock.enqueue_json("GET", "/events", 200, {"not": "a list"})
	var e: ApiResult = await _client.get_events("2026-10-02", "2026-10-02")
	assert_eq(e.code, ApiResult.CODE_BAD_RESPONSE)
	_mock.enqueue_json("GET", "/athlete/", 200, [1, 2])
	var l: ApiResult = await _client.get_athlete()
	assert_eq(l.code, ApiResult.CODE_BAD_RESPONSE)
	_mock.enqueue_json("GET", "/athlete/", 404, {})
	var nf: ApiResult = await _client.get_athlete()
	assert_eq(nf.code, ApiResult.CODE_BAD_RESPONSE)
	assert_eq(nf.status, 404)


func test_for_profile_takes_athlete_id_from_profile() -> void:
	var p := Profile.create("Даша")
	p.intervals_athlete_id = "i999"
	var c := IntervalsIcuClient.for_profile(_mock, _store, p)
	assert_eq(c.athlete_id, "i999")
	assert_eq(c.profile_id(), p.id)
	assert_false(c.is_configured(), "ключа у нового профиля нет")
