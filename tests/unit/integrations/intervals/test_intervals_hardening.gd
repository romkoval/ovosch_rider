extends GutTest
## Устойчивость Intervals.icu (финальное ревью): ожидание по `Retry-After` не дольше 60 с,
## атомарная запись кэша плана (REQ-INT-02 крит. 5, REQ-INT-07 крит. 1).

const PROFILE: String = "profile-i"
const ATHLETE: String = "i12345"
const TODAY: String = "2026-10-03"

var _mock: MockHttpTransport
var _store: MemorySecureStore
var _client: IntervalsIcuClient
var _dir: String


func before_each() -> void:
	_mock = MockHttpTransport.new()
	_store = MemorySecureStore.new()
	_client = IntervalsIcuClient.new(_mock, _store, PROFILE)
	_client.athlete_id = ATHLETE
	_client.wait_fn = func(_sec: float) -> void: pass
	_store.set_secret(_client.secret_key(), "fixture-intervals-key-value")
	_dir = "user://test_intervals_hardening_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]


func after_each() -> void:
	AtomicFile.simulate_write_error_prefix = ""
	var cache := PlanCache.new(_dir)
	cache.clear(PROFILE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir))


func test_retry_after_over_60s_returns_rate_limited_without_waiting() -> void:
	_mock.enqueue_json("GET", "/athlete/", 429, {}, {"Retry-After": "3600"})
	var r: ApiResult = await _client.get_athlete()
	assert_false(r.ok)
	assert_eq(r.code, ApiResult.CODE_RATE_LIMITED)
	assert_eq(r.retry_after_sec, 3600)
	assert_eq(_client.waits, [] as Array[int], "не ждём час внутри запроса")
	assert_eq(_mock.request_count(), 1, "без повтора")


func test_retry_after_up_to_60s_still_waits_and_retries() -> void:
	_mock.enqueue_json("GET", "/athlete/", 429, {}, {"Retry-After": "60"})
	_mock.enqueue_json("GET", "/athlete/", 200, {"id": ATHLETE, "icu_ftp": 250})
	var r: ApiResult = await _client.get_athlete()
	assert_true(r.ok, r.message)
	assert_eq(_client.waits, [60] as Array[int])
	assert_eq(IntervalsIcuClient.MAX_RETRY_WAIT_SEC, 60)


func test_plan_cache_write_error_keeps_previous_cache() -> void:
	var cache := PlanCache.new(_dir)
	assert_true(cache.save(PROFILE, TODAY, [], 100))
	var path := cache.file_path(PROFILE, TODAY)
	var before := FileAccess.get_file_as_string(path)
	AtomicFile.simulate_write_error_prefix = path
	assert_false(cache.save(PROFILE, TODAY, [], 200), "ошибка записи кэша не теряется")
	assert_push_error("AtomicFile")
	assert_eq(FileAccess.get_file_as_string(path), before, "прежний кэш цел")
	assert_false(FileAccess.file_exists(AtomicFile.tmp_path(path)))
	AtomicFile.simulate_write_error_prefix = ""
	assert_eq(int(cache.load_date(PROFILE, TODAY).get("loaded_at", 0)), 100)
