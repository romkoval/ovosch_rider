extends GutTest
## Тесты PlanCache и IntervalsPlanService (REQ-INT-07 крит. 1–4, REQ-NFR-03 крит. 1, 2,
## REQ-INT-02 крит. 3, 4, REQ-INT-04 крит. 2 — формат длительности).

const FIXTURES: String = "res://tests/fixtures/intervals/"
const PROFILE: String = "profile-1"
const TODAY: String = "2026-10-02"
const YESTERDAY: String = "2026-10-01"
const KEY: String = "fixture-api-key-9f8e7d6c"

var _dir: String
var _cache: PlanCache
var _mock: MockHttpTransport
var _client: IntervalsIcuClient
var _service: IntervalsPlanService


func before_each() -> void:
	_dir = "user://test_plans_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_cache = PlanCache.new(_dir)
	_mock = MockHttpTransport.new()
	var store := MemorySecureStore.new()
	_client = IntervalsIcuClient.new(_mock, store, PROFILE)
	_client.base_url = "https://mock.intervals.test"
	_client.athlete_id = "i12345"
	_client.wait_fn = func(_sec: float) -> void: pass
	store.set_secret(_client.secret_key(), KEY)
	_service = IntervalsPlanService.new(_client, _cache)


func after_each() -> void:
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


static func _events() -> Array:
	var json := JSON.new()
	assert(json.parse(FileAccess.get_file_as_string(FIXTURES + "events_today.json")) == OK)
	return json.data


static func _entries() -> Array:
	var out: Array = []
	for e in _events():
		if IntervalsIcuClient.is_bike_workout(e):
			out.append(IntervalsIcuClient.entry_from_event(e))
	return out


# ---------------------------------------------------------------------------
# PlanCache
# ---------------------------------------------------------------------------

func test_save_and_load_round_trip() -> void:
	assert_true(_cache.save(PROFILE, TODAY, _entries(), 1_759_400_000), "REQ-INT-07 крит. 1")
	assert_true(_cache.has(PROFILE, TODAY))
	assert_true(FileAccess.file_exists(_cache.file_path(PROFILE, TODAY)))
	var cached := _cache.load_date(PROFILE, TODAY)
	assert_eq(str(cached["date"]), TODAY)
	assert_eq(int(cached["loaded_at"]), 1_759_400_000, "REQ-INT-07 крит. 1: время загрузки сохранено")
	var workouts: Array = cached["workouts"]
	assert_eq(workouts.size(), 2)
	assert_eq(str(workouts[0]["event_id"]), "2001")
	assert_eq(str(workouts[0]["name"]), "Threshold 3x5")
	assert_eq(int(workouts[0]["training_load"]), 65)
	var w: Workout = workouts[0]["workout"]
	assert_eq(w.steps.size(), 8)
	assert_eq(w.total_duration_sec(), 2340)
	assert_eq(w.source, "intervals_icu")
	assert_eq(w.target_watts_at(650.0, 200), 200, "цель 100 % при FTP 200 восстановлена")
	assert_eq((workouts[1]["workout"] as Workout).total_duration_sec(), 2100)


func test_cache_of_other_date_is_not_offered_as_today() -> void:
	_cache.save(PROFILE, YESTERDAY, _entries(), 100)
	assert_eq(_cache.get_today(PROFILE, TODAY), {}, "REQ-INT-07 крит. 3")
	assert_false(_cache.has(PROFILE, TODAY))
	assert_eq(_cache.get_today(PROFILE, YESTERDAY).size(), 3, "на свою дату кэш доступен")


func test_save_replaces_and_prunes_other_dates() -> void:
	_cache.save(PROFILE, YESTERDAY, _entries(), 100)
	_cache.save(PROFILE, TODAY, _entries(), 200)
	assert_false(_cache.has(PROFILE, YESTERDAY), "кэш другой даты удалён")
	_cache.save(PROFILE, TODAY, [], 300)
	var cached := _cache.load_date(PROFILE, TODAY)
	assert_eq(int(cached["loaded_at"]), 300, "успешная загрузка заменяет кэш (TTL нет)")
	assert_eq((cached["workouts"] as Array).size(), 0, "пустой план на сегодня тоже кэшируется")


func test_entries_without_workout_are_skipped_and_bad_input_rejected() -> void:
	var entries := _entries()
	entries.append({"event_id": "9", "name": "broken", "workout": null})
	assert_true(_cache.save(PROFILE, TODAY, entries))
	assert_eq((_cache.load_date(PROFILE, TODAY)["workouts"] as Array).size(), 2)
	assert_false(_cache.save("", TODAY, entries))
	assert_false(_cache.save(PROFILE, "today", entries), "дата не в формате YYYY-MM-DD")
	assert_eq(_cache.load_date(PROFILE, "../etc"), {})


func test_corrupted_cache_file_is_ignored() -> void:
	_cache.save(PROFILE, TODAY, _entries())
	var f := FileAccess.open(_cache.file_path(PROFILE, TODAY), FileAccess.WRITE)
	f.store_string("{ broken")
	f.close()
	assert_eq(_cache.get_today(PROFILE, TODAY), {})


func test_clear_and_profile_cascade() -> void:
	_cache.save(PROFILE, TODAY, _entries())
	_cache.save("profile-2", TODAY, _entries())
	assert_eq(_cache.clear(PROFILE), 1)
	assert_false(_cache.has(PROFILE, TODAY))
	assert_true(_cache.has("profile-2", TODAY), "кэш другого профиля цел")
	assert_eq(_cache.clear("nobody"), 0)
	var repo := ProfileRepository.new(_dir + "profiles/")
	var a := repo.create("A")
	repo.create("B")
	_cache.attach_to_profiles(repo)
	_cache.attach_to_profiles(repo)
	_cache.save(a.id, TODAY, _entries())
	assert_eq(repo.delete(a.id), "")
	assert_false(_cache.has(a.id, TODAY), "каскад при удалении профиля")


func test_cache_label() -> void:
	var dt := {"year": 2026, "month": 10, "day": 2, "hour": 7, "minute": 5, "second": 0}
	var ts := Time.get_unix_time_from_datetime_dict(dt)
	var label := PlanCache.cache_label(ts, TODAY)
	assert_string_contains(label, "из кэша, загружен", "REQ-INT-07 крит. 2")
	assert_true(RegEx.create_from_string("\\d{2}:\\d{2}$").search(label) != null, "время ЧЧ:ММ: %s" % label)
	assert_string_contains(PlanCache.cache_label(ts, "2026-10-03"), "2026-10-02", "другая дата — с датой")
	assert_eq(PlanCache.cache_label(0), "из кэша")


# ---------------------------------------------------------------------------
# IntervalsPlanService (REQ-INT-07 крит. 2, 4; REQ-NFR-03)
# ---------------------------------------------------------------------------

func test_online_load_saves_cache_then_offline_uses_it() -> void:
	_mock.enqueue_json("GET", "/events", 200, _events())
	var online: ApiResult = await _service.load_today(TODAY)
	assert_true(online.ok, online.message)
	assert_eq(online.code, ApiResult.CODE_OK)
	assert_false(online.from_cache)
	assert_true(_cache.has(PROFILE, TODAY), "REQ-INT-07 крит. 1: после успешной загрузки план в кэше")
	assert_eq(_mock.request_count(), 1)
	_mock.offline = true
	var offline: ApiResult = await _service.load_today(TODAY)
	assert_true(offline.ok, "REQ-INT-07 крит. 2: без сети план из кэша")
	assert_true(offline.from_cache)
	assert_eq(offline.code, ApiResult.CODE_FROM_CACHE)
	assert_string_contains(offline.message, "из кэша, загружен")
	assert_eq((offline.data as Array).size(), 2)
	assert_true((offline.data as Array)[0]["workout"] is Workout)
	assert_eq(offline.loaded_at, online.loaded_at)
	assert_true(offline.can_retry)
	assert_eq(_mock.request_count(), 2, "одна неудачная попытка сети, затем кэш")


func test_cached_today_makes_no_network_requests() -> void:
	_cache.save(PROFILE, TODAY, _entries(), 123)
	_mock.offline = true
	var r: ApiResult = await _service.cached_today(TODAY)
	assert_true(r.ok)
	assert_true(r.from_cache)
	assert_eq((r.data as Array).size(), 2)
	assert_eq(_mock.request_count(), 0, "REQ-INT-07 крит. 4 / REQ-NFR-03 крит. 2: 0 запросов")
	var w: Workout = (r.data as Array)[0]["workout"]
	assert_true(w.is_valid(), "план из кэша готов к WorkoutSession")
	var none: ApiResult = await _service.cached_today(YESTERDAY)
	assert_false(none.ok)
	assert_true(none.can_retry)


func test_offline_without_cache_is_retryable_network_error() -> void:
	_mock.offline = true
	var r: ApiResult = await _service.load_today(TODAY)
	assert_false(r.ok)
	assert_eq(r.code, ApiResult.CODE_NETWORK, "REQ-INT-02 крит. 4")
	assert_true(r.can_retry)
	assert_false(r.from_cache)


func test_5xx_falls_back_to_cache_but_401_does_not() -> void:
	_cache.save(PROFILE, TODAY, _entries(), 50)
	_mock.enqueue_json("GET", "/events", 502, {})
	var r: ApiResult = await _service.load_today(TODAY)
	assert_true(r.ok)
	assert_true(r.from_cache, "5xx → кэш")
	_mock.enqueue_json("GET", "/events", 401, {"error": "Unauthorized"})
	var auth: ApiResult = await _service.load_today(TODAY)
	assert_false(auth.ok)
	assert_eq(auth.code, ApiResult.CODE_AUTH_FAILED, "ключ не принят — кэш не подменяет ошибку")


func test_cache_of_other_date_not_used_by_service() -> void:
	_cache.save(PROFILE, YESTERDAY, _entries(), 50)
	_mock.offline = true
	var r: ApiResult = await _service.load_today(TODAY)
	assert_false(r.ok, "REQ-INT-07 крит. 3: вчерашний кэш не предлагается")
	assert_eq(r.code, ApiResult.CODE_NETWORK)


func test_empty_plan_is_explicit_status_online_and_from_cache() -> void:
	_mock.enqueue_json("GET", "/events", 200, [])
	var online: ApiResult = await _service.load_today(TODAY)
	assert_true(online.ok)
	assert_eq(online.code, ApiResult.CODE_NO_WORKOUT_TODAY, "REQ-INT-02 крит. 3")
	assert_true(_cache.has(PROFILE, TODAY))
	_mock.offline = true
	var offline: ApiResult = await _service.load_today(TODAY)
	assert_true(offline.ok, "без сети статус «нет тренировок» воспроизводится, не ошибка")
	assert_eq(offline.code, ApiResult.CODE_NO_WORKOUT_TODAY)
	assert_true(offline.from_cache)


func test_format_duration_for_list() -> void:
	assert_eq(IntervalsPlanService.format_duration(600), "10:00", "REQ-INT-04 крит. 2: мм:сс")
	assert_eq(IntervalsPlanService.format_duration(59), "00:59")
	assert_eq(IntervalsPlanService.format_duration(3600), "1:00:00", "REQ-INT-04 крит. 2: ч:мм:сс")
	assert_eq(IntervalsPlanService.format_duration(3661), "1:01:01")
	assert_eq(IntervalsPlanService.format_duration(-5), "00:00")
