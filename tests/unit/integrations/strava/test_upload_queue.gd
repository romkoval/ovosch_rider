extends GutTest
## Тесты UploadQueue (REQ-STR-04 крит. 1–6; REQ-STR-05 крит. 1–3; REQ-NFR-03 крит. 3).

const PROFILE: String = "profile-a"
const API: String = "https://mock.strava.test/api/v3"
const NOW: int = 1_800_000_000
var FIT: PackedByteArray = PackedByteArray([0x0E, 0x10, 0x5A, 0x08, 0x2E, 0x46, 0x49, 0x54])

var _dir: String
var _mock: MockHttpTransport
var _store: MemorySecureStore
var _oauth: StravaOAuth
var _uploader: StravaUploader
var _status: MemoryUploadStatusStore
var _queue: UploadQueue
var _now: int = NOW
var _provided: Array[String] = []


func before_each() -> void:
	_dir = "user://test_queue_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_now = NOW
	_provided = []
	_mock = MockHttpTransport.new()
	_store = MemorySecureStore.new()
	_oauth = StravaOAuth.new(_mock, _store, PROFILE, StravaConfig.from_values("4242", "fixture-client-secret-value"))
	_oauth.base_url = "https://mock.strava.test"
	_oauth.clock_fn = func() -> int: return _now
	_store.set_secret(_oauth.secret_key(SecureStore.ITEM_ACCESS_TOKEN), "fixture-access-token-aaaa")
	_store.set_secret(_oauth.secret_key(SecureStore.ITEM_REFRESH_TOKEN), "fixture-refresh-token-rrrr")
	_store.set_secret(_oauth.secret_key(SecureStore.ITEM_EXPIRES_AT), str(NOW + 999999))
	_uploader = StravaUploader.new(_mock, _oauth)
	_uploader.api_base = API
	_uploader.wait_fn = func(_sec: float) -> void: pass
	_status = MemoryUploadStatusStore.new()
	_queue = _make_queue()


func after_each() -> void:
	var abs := ProjectSettings.globalize_path(_dir)
	var d := DirAccess.open(abs)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(abs.path_join(f))
	DirAccess.remove_absolute(abs)


func _make_queue() -> UploadQueue:
	var q := UploadQueue.new(_uploader, _status, func() -> int: return _now, PROFILE, _dir)
	q.fit_provider = func(ride_id: String) -> PackedByteArray:
		_provided.append(ride_id)
		return FIT
	return q


func _provider() -> Callable:
	return func(ride_id: String) -> PackedByteArray:
		_provided.append(ride_id)
		return FIT


func _ok_upload(upload_id: int, activity_id: int) -> void:
	_mock.enqueue_json("POST", "/uploads", 201, {"id": upload_id, "activity_id": activity_id, "error": null})


# ---------------------------------------------------------------------------
# Постановка, порядок, статусы (крит. 1, 4, 5; STR-05 крит. 1, 2)
# ---------------------------------------------------------------------------

func test_enqueue_sets_queued_status_and_persists() -> void:
	_queue.enqueue("ride-1", _provider(), "Name", "Desc", NOW - 100)
	assert_eq(_queue.size(), 1)
	assert_true(_queue.has("ride-1"))
	assert_eq(str(_status.get_upload_status("ride-1")["status"]), UploadResult.STATUS_QUEUED, "REQ-STR-05 крит. 1: в очереди")
	assert_true(FileAccess.file_exists(_queue.file_path()), "REQ-STR-04 крит. 1: очередь на диске")
	var item := _queue.get_item("ride-1")
	assert_eq(str(item["name"]), "Name")
	assert_eq(int(item["attempts"]), 0)
	assert_eq(int(item["next_attempt_at"]), NOW, "попытка сразу")
	_queue.enqueue("", _provider(), "x", "y")
	assert_eq(_queue.size(), 1, "пустой id игнорируется")


func test_queue_survives_restart() -> void:
	_queue.enqueue("ride-1", _provider(), "Name", "Desc", NOW - 100)
	_queue.enqueue("ride-2", _provider(), "Second", "", NOW - 50)
	var restored := _make_queue()
	assert_eq(restored.size(), 2, "REQ-STR-04 крит. 1: переживает перезапуск")
	assert_eq(str(restored.items()[0]["ride_id"]), "ride-1")
	assert_eq(str(restored.get_item("ride-2")["name"]), "Second")
	_ok_upload(1, 101)
	var processed: String = await restored.tick(NOW)
	assert_eq(processed, "ride-1", "FIT после перезапуска — через общий fit_provider")
	assert_eq(_provided, ["ride-1"])
	assert_eq(str(_status.get_upload_status("ride-1")["activity_id"]), "101")


func test_tick_processes_in_ride_date_order_one_at_a_time() -> void:
	_queue.enqueue("ride-late", _provider(), "L", "", NOW - 10)
	_queue.enqueue("ride-early", _provider(), "E", "", NOW - 1000)
	_ok_upload(1, 101)
	_ok_upload(2, 102)
	var first: String = await _queue.tick(NOW)
	assert_eq(first, "ride-early", "REQ-STR-04 крит. 4: порядок по дате заезда")
	assert_eq(_mock.request_count(), 1, "REQ-STR-04 крит. 4: одна выгрузка за tick")
	assert_eq(_queue.size(), 1)
	var second: String = await _queue.tick(NOW)
	assert_eq(second, "ride-late")
	assert_eq(_queue.size(), 0)
	assert_eq(await _queue.tick(NOW), "", "пусто — ничего")


func test_successful_upload_sets_done_with_activity_id_and_removes_item() -> void:
	_queue.enqueue("ride-1", _provider(), "Name", "Desc", NOW - 100)
	var finished: Array = []
	_queue.upload_finished.connect(func(id: String, act: String) -> void: finished.append([id, act]))
	_ok_upload(1, 777)
	await _queue.tick(NOW)
	var s := _status.get_upload_status("ride-1")
	assert_eq(str(s["status"]), UploadResult.STATUS_DONE, "REQ-STR-05 крит. 1: выгружено")
	assert_eq(str(s["activity_id"]), "777")
	assert_eq(_status.status_sequence("ride-1"), ["queued", "uploading", "done"], "REQ-STR-05 крит. 1: переходы")
	assert_false(_queue.has("ride-1"))
	assert_eq(finished, [["ride-1", "777"]])
	assert_eq(StravaBranding.activity_url(str(s["activity_id"])), "https://www.strava.com/activities/777", "REQ-STR-05 крит. 3")
	var body := (_mock.last_request()["body"] as PackedByteArray).get_string_from_utf8()
	assert_string_contains(body, "name=\"external_id\"\r\n\r\nride-1\r\n", "external_id = id заезда")
	assert_string_contains(body, "name=\"name\"\r\n\r\nName\r\n")


func test_duplicate_is_final_without_retries() -> void:
	_queue.enqueue("ride-1", _provider(), "N", "", NOW)
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 5, "error": "duplicate of activity 1", "activity_id": null})
	await _queue.tick(NOW)
	assert_eq(str(_status.get_upload_status("ride-1")["status"]), UploadResult.STATUS_DUPLICATE, "REQ-STR-02 крит. 4")
	assert_false(_queue.has("ride-1"))
	assert_eq(await _queue.tick(NOW + 100000), "", "повторов нет")


# ---------------------------------------------------------------------------
# Повторы (крит. 2, 3)
# ---------------------------------------------------------------------------

func test_network_failures_back_off_1_5_15_60_then_60_minutes() -> void:
	_queue.enqueue("ride-1", _provider(), "N", "", NOW)
	_mock.offline = true
	var expected_delays := [60, 300, 900, 3600, 3600, 3600]
	var t := NOW
	for i in expected_delays.size():
		var processed: String = await _queue.tick(t)
		assert_eq(processed, "ride-1", "попытка %d выполнена" % (i + 1))
		var item := _queue.get_item("ride-1")
		assert_eq(int(item["attempts"]), i + 1)
		assert_eq(int(item["next_attempt_at"]) - t, expected_delays[i], "REQ-STR-04 крит. 2: задержка после попытки %d" % (i + 1))
		assert_eq(str(_status.get_upload_status("ride-1")["status"]), UploadResult.STATUS_QUEUED, "остаётся в очереди")
		assert_false(str(item["last_error"]).is_empty())
		assert_eq(await _queue.tick(t + expected_delays[i] - 1), "", "раньше срока попытки нет")
		t += expected_delays[i]
	assert_true(_queue.has("ride-1"), "offline не исчерпывает попытки")
	assert_eq(_mock.request_count(), expected_delays.size())
	_mock.offline = false
	_ok_upload(1, 5)
	await _queue.tick(t)
	assert_eq(str(_status.get_upload_status("ride-1")["status"]), UploadResult.STATUS_DONE, "после появления сети — выгружено (REQ-NFR-03 крит. 3)")


func test_5xx_is_retried_like_network() -> void:
	_queue.enqueue("ride-1", _provider(), "N", "", NOW)
	_mock.enqueue_json("POST", "/uploads", 502, {})
	await _queue.tick(NOW)
	var item := _queue.get_item("ride-1")
	assert_eq(int(item["attempts"]), 1)
	assert_eq(int(item["next_attempt_at"]), NOW + 60)
	assert_string_contains(str(item["last_error"]), "502")


func test_429_waits_retry_after() -> void:
	_queue.enqueue("ride-1", _provider(), "N", "", NOW)
	_mock.enqueue("POST", "/uploads", HttpResponse.json_response(429, {}, {"Retry-After": "900"}))
	await _queue.tick(NOW)
	assert_eq(int(_queue.get_item("ride-1")["next_attempt_at"]), NOW + 900, "REQ-STR-04 крит. 3: не раньше Retry-After")
	assert_eq(await _queue.tick(NOW + 899), "")
	_ok_upload(1, 9)
	assert_eq(await _queue.tick(NOW + 900), "ride-1")


func test_retry_now_makes_item_due_immediately() -> void:
	_queue.enqueue("ride-1", _provider(), "N", "", NOW)
	_mock.offline = true
	await _queue.tick(NOW)
	assert_eq(await _queue.tick(NOW + 1), "", "ждём 60 с")
	assert_true(_queue.retry_now("ride-1"), "REQ-STR-04 крит. 5: ручной повтор")
	assert_false(_queue.retry_now("nope"))
	_mock.offline = false
	_ok_upload(1, 3)
	assert_eq(await _queue.tick(NOW + 1), "ride-1")
	assert_eq(str(_status.get_upload_status("ride-1")["status"]), UploadResult.STATUS_DONE)


func test_reenqueue_updates_name_and_makes_due() -> void:
	_queue.enqueue("ride-1", _provider(), "Old", "", NOW)
	_mock.offline = true
	await _queue.tick(NOW)
	_queue.enqueue("ride-1", _provider(), "New name", "New desc", NOW)
	assert_eq(_queue.size(), 1, "без дубликатов")
	assert_eq(str(_queue.get_item("ride-1")["name"]), "New name", "REQ-STR-03 крит. 3: правки попадают в запрос")
	_mock.offline = false
	_ok_upload(1, 3)
	await _queue.tick(NOW + 1)
	assert_string_contains((_mock.last_request()["body"] as PackedByteArray).get_string_from_utf8(), "New name")


# ---------------------------------------------------------------------------
# Окончательные ошибки, сессия, удаление (крит. 6; STR-05 крит. 1)
# ---------------------------------------------------------------------------

func test_reauth_required_is_failed_and_removed() -> void:
	_queue.enqueue("ride-1", _provider(), "N", "", NOW)
	_mock.enqueue_json("POST", "/uploads", 401, {}, {}, -1)
	_mock.enqueue_json("POST", "/oauth/token", 401, {})
	await _queue.tick(NOW)
	var s := _status.get_upload_status("ride-1")
	assert_eq(str(s["status"]), UploadResult.STATUS_FAILED, "REQ-STR-05 крит. 1: ошибка с текстом")
	assert_eq(str(s["code"]), ApiResult.CODE_REAUTH_REQUIRED)
	assert_string_contains(str(s["error"]), "вход")
	assert_false(_queue.has("ride-1"))


func test_processing_error_text_is_failed_and_missing_fit_is_failed() -> void:
	_queue.enqueue("ride-1", _provider(), "N", "", NOW)
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 7, "error": "The file is malformed", "activity_id": null})
	await _queue.tick(NOW)
	assert_eq(str(_status.get_upload_status("ride-1")["error"]), "The file is malformed")
	assert_false(_queue.has("ride-1"))
	var no_fit := UploadQueue.new(_uploader, _status, func() -> int: return _now, "profile-nofit", _dir)
	no_fit.enqueue("ride-x", Callable(), "N", "", NOW)
	await no_fit.tick(NOW)
	assert_eq(str(_status.get_upload_status("ride-x")["status"]), UploadResult.STATUS_FAILED)
	assert_eq(_mock.request_count(), 1, "без FIT запросов нет")


func test_still_processing_is_polled_later_with_upload_id() -> void:
	_uploader.max_polls = 1
	_queue.poll_retry_sec = 30
	_queue.enqueue("ride-1", _provider(), "N", "", NOW)
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 900, "activity_id": null, "error": null})
	_mock.enqueue_json("GET", "/uploads/900", 200, {"id": 900, "activity_id": null, "error": null})
	await _queue.tick(NOW)
	var item := _queue.get_item("ride-1")
	assert_eq(str(item["upload_id"]), "900")
	assert_eq(int(item["next_attempt_at"]), NOW + 30)
	assert_eq(str(_status.get_upload_status("ride-1")["status"]), UploadResult.STATUS_UPLOADING, "REQ-STR-05 крит. 1: обрабатывается")
	_mock.enqueue_json("GET", "/uploads/900", 200, {"id": 900, "activity_id": 4321, "error": null})
	await _queue.tick(NOW + 30)
	assert_eq(_mock.request_count("POST"), 1, "повторной выгрузки нет — только опрос")
	assert_eq(str(_status.get_upload_status("ride-1")["activity_id"]), "4321")


func test_no_uploads_during_active_session() -> void:
	_queue.enqueue("ride-1", _provider(), "N", "", NOW)
	_queue.session_active = true
	assert_eq(await _queue.tick(NOW), "", "REQ-STR-04 крит. 6 / REQ-NFR-03: во время тренировки не выгружаем")
	assert_eq(_mock.request_count(), 0)
	_queue.session_active = false
	_ok_upload(1, 1)
	assert_eq(await _queue.tick(NOW), "ride-1")


func test_remove_drops_item_and_resets_queued_status_to_none() -> void:
	# REQ-STR-04 крит. 2 (ручная отмена), REQ-STR-05 крит. 1: отменённый заезд — «не выгружен».
	var changes: Array[String] = []
	_queue.item_changed.connect(func(_id: String, s: Dictionary) -> void: changes.append(str(s["status"])))
	_queue.enqueue("ride-1", _provider(), "N", "", NOW)
	_mock.offline = true
	await _queue.tick(NOW)
	assert_eq(str(_status.get_upload_status("ride-1")["status"]), UploadResult.STATUS_QUEUED)
	assert_true(_queue.remove("ride-1"))
	assert_false(_queue.has("ride-1"))
	assert_false(_queue.remove("ride-1"))
	var st := _status.get_upload_status("ride-1")
	assert_eq(str(st["status"]), UploadResult.STATUS_NONE, "после отмены — «не выгружен»")
	assert_eq(int(st["attempts"]), 1, "число попыток сохраняется")
	assert_eq(changes, ["queued", "uploading", "queued", "none"], "сигнал об отмене")
	assert_eq(_make_queue().size(), 0, "удаление сохранено")
	assert_eq(await _queue.tick(NOW + 60), "", "отменённый элемент не выгружается")


func test_remove_resets_failed_but_keeps_done_and_duplicate() -> void:
	# `failed` в хранилище (например, выставлен владельцем заезда) → `none`; `done`/`duplicate` неизменны.
	_queue.enqueue("ride-f", _provider(), "N", "", NOW)
	_status.update_upload_status("ride-f", UploadResult.failed("x", ApiResult.CODE_BAD_RESPONSE).to_status_dict(2, NOW))
	assert_true(_queue.remove("ride-f"))
	assert_eq(str(_status.get_upload_status("ride-f")["status"]), UploadResult.STATUS_NONE)
	_queue.enqueue("ride-d", _provider(), "N", "", NOW)
	_status.update_upload_status("ride-d", UploadResult.done("77").to_status_dict(1, NOW))
	assert_true(_queue.remove("ride-d"))
	assert_eq(str(_status.get_upload_status("ride-d")["status"]), UploadResult.STATUS_DONE, "done не трогаем")
	assert_eq(str(_status.get_upload_status("ride-d")["activity_id"]), "77")
	_queue.enqueue("ride-u", _provider(), "N", "", NOW)
	_status.update_upload_status("ride-u", UploadResult.duplicate_of("duplicate").to_status_dict(1, NOW))
	assert_true(_queue.remove("ride-u"))
	assert_eq(str(_status.get_upload_status("ride-u")["status"]), UploadResult.STATUS_DUPLICATE, "duplicate не трогаем")


func test_429_on_token_refresh_waits_retry_after() -> void:
	# REQ-STR-04 крит. 3: 429 на обновлении токена перед выгрузкой — пауза по Retry-After, не 60 с.
	_store.set_secret(_oauth.secret_key(SecureStore.ITEM_EXPIRES_AT), str(NOW + 10))
	_queue.enqueue("ride-1", _provider(), "N", "", NOW)
	_mock.enqueue_json("POST", "/oauth/token", 429, {"message": "Rate Limit Exceeded"}, {"Retry-After": "900"})
	assert_eq(await _queue.tick(NOW), "ride-1")
	assert_eq(_mock.request_count("POST", "/uploads"), 0)
	assert_true(_queue.has("ride-1"))
	assert_eq(str(_status.get_upload_status("ride-1")["status"]), UploadResult.STATUS_QUEUED)
	assert_eq(int(_queue.get_item("ride-1")["attempts"]), 1)
	assert_eq(int(_queue.get_item("ride-1")["next_attempt_at"]), NOW + 900)
	assert_eq(await _queue.tick(NOW + 899), "")


func test_retry_delay_table_and_item_changed_signal() -> void:
	assert_eq(UploadQueue.retry_delay_sec(1), 60)
	assert_eq(UploadQueue.retry_delay_sec(2), 300)
	assert_eq(UploadQueue.retry_delay_sec(3), 900)
	assert_eq(UploadQueue.retry_delay_sec(4), 3600)
	assert_eq(UploadQueue.retry_delay_sec(9), 3600)
	assert_eq(UploadQueue.retry_delay_sec(0), 60)
	var changes: Array[String] = []
	_queue.item_changed.connect(func(_id: String, s: Dictionary) -> void: changes.append(str(s["status"])))
	_queue.enqueue("ride-1", _provider(), "N", "", NOW)
	_ok_upload(1, 1)
	await _queue.tick(NOW)
	assert_eq(changes, ["queued", "uploading", "done"])
