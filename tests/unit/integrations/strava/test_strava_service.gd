extends GutTest
## Тесты StravaService и адаптера к RideRepository (T-049: REQ-STR-02 крит. 1, REQ-STR-03 крит. 1–3,
## REQ-STR-04 крит. 5, 6, REQ-STR-05 крит. 2, 3, REQ-LOC-06 крит. 3, REQ-PRF-03 крит. 2, REQ-STR-01 крит. 7, 8).

const NOW: int = 1_800_000_000
## 2026-10-02 12:00 UTC — дата заезда для проверки названия по умолчанию (REQ-STR-03 крит. 1).
const STARTED: int = 1_790_942_400

var _dir: String
var _mock: MockHttpTransport
var _store: MemorySecureStore
var _rides: FileRideRepository
var _profile: Profile
var _service: StravaService
var _now: int = NOW
var _status_events: Array[String] = []
var _auth_events: Array[bool] = []


func before_each() -> void:
	_dir = "user://test_strava_service_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_now = NOW
	_status_events = []
	_auth_events = []
	_mock = MockHttpTransport.new()
	_store = MemorySecureStore.new()
	_rides = FileRideRepository.new(_dir + "rides/")
	_profile = Profile.create("Даша")
	_service = _make_service()


func after_each() -> void:
	_service.dispose()
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


func _make_service(config: StravaConfig = StravaConfig.from_values("4242", "fixture-client-secret-value")) -> StravaService:
	var s := StravaService.new(_profile, _mock, _store, _rides, config, func() -> int: return _now, _dir)
	s.oauth.base_url = "https://mock.strava.test"
	s.uploader.api_base = "https://mock.strava.test/api/v3"
	s.uploader.wait_fn = func(_sec: float) -> void: pass
	s.attach()
	s.status_changed.connect(func(id: String) -> void: _status_events.append(id))
	s.authorized_changed.connect(func(a: bool) -> void: _auth_events.append(a))
	return s


func _authorize() -> void:
	_store.set_secret(_service.oauth.secret_key(SecureStore.ITEM_ACCESS_TOKEN), "fixture-access-token-aaaa")
	_store.set_secret(_service.oauth.secret_key(SecureStore.ITEM_REFRESH_TOKEN), "fixture-refresh-token-rrrr")
	_store.set_secret(_service.oauth.secret_key(SecureStore.ITEM_EXPIRES_AT), str(NOW + 99999))


## Завершённый заезд с синтетическим потоком (как в тестах FitEncoder).
func _ride(name: String = "Sweet Spot", n: int = 6, started: int = STARTED, in_progress: bool = false) -> Ride:
	var r := Ride.new()
	r.id = Ride.generate_id(started)
	r.profile_id = _profile.id
	r.started_at_unix = started
	r.name = name
	r.description = "3x10 sweet spot" if not name.is_empty() else ""
	r.workout = Workout.make(name, [WorkoutStep.watts(3, 200.0), WorkoutStep.watts(3, 250.0)] as Array[WorkoutStep]).to_dict()
	r.metadata = {"ftp_w": 200, "weight_kg": 75.0, "max_hr": 185, "speed_source": Ride.SPEED_SOURCE_TRAINER_LEGACY,
		"stopped_early": false, "elapsed_sec": n, "paused_total_sec": 0.0, "in_progress": in_progress, "recovered": false}
	r.samples.speed_source = Ride.SPEED_SOURCE_TRAINER_LEGACY
	for i in n:
		r.samples.append(i, TrainerSample.full(float(i + 1), 200 + i * 10, 85 + i % 30, 36.0), 140 + i % 40, 200, i / 3, true)
	r.events = [{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0}]
	r.compute_summary()
	return r


func _ok_upload(upload_id: int, activity_id: int) -> void:
	_mock.enqueue_json("POST", "/uploads", 201, {"id": upload_id, "activity_id": activity_id, "error": null})


# ---------------------------------------------------------------------------
# Автопостановка (REQ-STR-02 крит. 1, REQ-STR-04 крит. 1)
# ---------------------------------------------------------------------------

func test_saved_finished_ride_is_enqueued_when_authorized_and_auto_upload() -> void:
	_authorize()
	var ride := _ride()
	_rides.save(ride)
	assert_true(_service.queue.has(ride.id), "REQ-STR-02 крит. 1: заезд в очереди после сохранения")
	assert_eq(str(_rides.get_ride(ride.id).upload["strava_status"]), Ride.UPLOAD_QUEUED, "REQ-STR-05 крит. 2: статус в репозитории")
	assert_eq(_status_events, [ride.id], "сигнал status_changed")
	var item := _service.queue.get_item(ride.id)
	assert_eq(str(item["name"]), "Sweet Spot", "REQ-STR-03 крит. 1: название плана")
	assert_string_contains(str(item["description"]), "3x10 sweet spot", "REQ-STR-03 крит. 2")
	assert_string_contains(str(item["description"]), "ovosch-rider")
	assert_eq(int(item["ride_date"]), STARTED)


func test_not_enqueued_without_authorization() -> void:
	var ride := _ride()
	_rides.save(ride)
	assert_false(_service.queue.has(ride.id))
	assert_eq(str(_rides.get_ride(ride.id).upload["strava_status"]), Ride.UPLOAD_NONE)


func test_not_enqueued_when_auto_upload_disabled() -> void:
	_authorize()
	_profile.strava_auto_upload = false
	var ride := _ride()
	_rides.save(ride)
	assert_false(_service.queue.has(ride.id), "автовыгрузка выключена")
	assert_true(_service.upload_now(ride.id), "REQ-STR-04 крит. 5: ручная выгрузка доступна")
	assert_true(_service.queue.has(ride.id))


func test_in_progress_save_is_ignored_until_finished() -> void:
	_authorize()
	var ride := _ride("Live", 6, STARTED, true)
	_rides.save(ride)
	assert_false(_service.queue.has(ride.id), "заезд ещё пишется — не ставим")
	ride.metadata["in_progress"] = false
	_rides.save(ride)
	assert_true(_service.queue.has(ride.id), "после завершения — в очереди")


func test_already_uploaded_ride_is_not_requeued_and_other_profile_ignored() -> void:
	_authorize()
	var done := _ride("Done")
	done.upload["strava_status"] = Ride.UPLOAD_DONE
	done.upload["strava_activity_id"] = "1"
	_rides.save(done)
	assert_false(_service.queue.has(done.id))
	assert_false(_service.upload_now(done.id), "выгруженный — ручная выгрузка недоступна")
	var other := _ride("Other")
	other.profile_id = "someone-else"
	_rides.save(other)
	assert_false(_service.queue.has(other.id), "чужой профиль")


func test_default_name_without_plan_uses_template_with_date() -> void:
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	var ride := _ride("")
	assert_eq(_service.default_name(ride), "Тренировка 2026-10-02", "REQ-STR-03 крит. 1")
	assert_eq(_service.default_description(ride), "Записано в ovosch-rider", "REQ-STR-03 крит. 2: без описания — строка приложения")
	# Язык интерфейса сменился на лету — перевод берётся в момент вызова.
	TranslationServer.set_locale("en")
	assert_eq(_service.default_name(ride), "Workout 2026-10-02", "REQ-STR-03 крит. 1: текущий язык")
	assert_eq(_service.default_description(ride), "Recorded in ovosch-rider", "REQ-STR-03 крит. 2: текущий язык")
	# Явный шаблон важнее перевода.
	_service.name_template = "Ride %s"
	_service.description_app_line = "via app"
	assert_eq(_service.default_name(ride), "Ride 2026-10-02")
	assert_eq(_service.default_description(ride), "via app")
	TranslationServer.set_locale(previous)


func test_enqueue_takes_translation_at_enqueue_time() -> void:
	var previous := TranslationServer.get_locale()
	_authorize()
	TranslationServer.set_locale("ru")
	var first := _ride("")
	_rides.save(first)
	assert_eq(str(_service.queue.get_item(first.id)["name"]), "Тренировка 2026-10-02")
	TranslationServer.set_locale("en")
	var second := _ride("")
	second.id = Ride.generate_id(STARTED + 60)
	_rides.save(second)
	assert_eq(str(_service.queue.get_item(second.id)["name"]), "Workout 2026-10-02", "REQ-STR-03 крит. 1: язык на момент постановки")
	assert_eq(str(_service.queue.get_item(second.id)["description"]), "Recorded in ovosch-rider", "REQ-STR-03 крит. 2")
	TranslationServer.set_locale(previous)


# ---------------------------------------------------------------------------
# Ручная выгрузка, удаление, статусы (REQ-STR-04 крит. 5, REQ-LOC-06 крит. 3, REQ-STR-05)
# ---------------------------------------------------------------------------

func test_upload_now_with_custom_name_and_description_reaches_request() -> void:
	_authorize()
	_profile.strava_auto_upload = false
	var ride := _ride()
	_rides.save(ride)
	assert_true(_service.upload_now(ride.id, "My title", "My notes"))
	_ok_upload(1, 777)
	await _service.step_queue()
	var body := (_mock.last_request()["body"] as PackedByteArray).get_string_from_utf8()
	assert_string_contains(body, "name=\"name\"\r\n\r\nMy title\r\n", "REQ-STR-03 крит. 3")
	assert_string_contains(body, "name=\"description\"\r\n\r\nMy notes\r\n")
	assert_string_contains(body, "name=\"external_id\"\r\n\r\n%s\r\n" % ride.id)
	assert_string_contains(body, "name=\"data_type\"\r\n\r\nfit\r\n")
	var saved := _rides.get_ride(ride.id)
	assert_eq(str(saved.upload["strava_status"]), Ride.UPLOAD_DONE, "REQ-STR-05 крит. 2")
	assert_eq(str(saved.upload["strava_activity_id"]), "777")
	assert_eq(_rides.list(_profile.id)[0].strava_status, Ride.UPLOAD_DONE, "статус виден в списке")
	assert_eq(StravaBranding.activity_url(str(saved.upload["strava_activity_id"])), "https://www.strava.com/activities/777", "REQ-STR-05 крит. 3")
	assert_false(_service.queue.has(ride.id))


func test_upload_now_without_authorization_or_unknown_ride_is_false() -> void:
	assert_false(_service.upload_now("nope"))
	_authorize()
	assert_false(_service.upload_now("nope"))
	assert_eq(_mock.request_count(), 0)


func test_fit_bytes_from_repository_are_valid_fit() -> void:
	_authorize()
	var ride := _ride()
	_rides.save(ride)
	_ok_upload(1, 5)
	await _service.step_queue()
	var body: PackedByteArray = _mock.last_request()["body"]
	var marker := "Content-Type: application/octet-stream\r\n\r\n".to_utf8_buffer()
	var idx := -1
	for i in range(0, body.size() - marker.size()):
		if body.slice(i, i + marker.size()) == marker:
			idx = i
			break
	assert_gt(idx, 0, "в теле есть файл")
	var fit := body.slice(idx + marker.size(), idx + marker.size() + 14)
	assert_eq(fit[0], 14, "заголовок FIT: размер 14")
	assert_eq(fit.slice(8, 12).get_string_from_ascii(), ".FIT", "сигнатура .FIT")
	var expected := FitEncoder.encode(_rides.get_ride(ride.id))
	assert_eq(body.slice(idx + marker.size(), idx + marker.size() + expected.size()), expected, "байты FIT = FitEncoder.encode(ride)")


func test_deleted_ride_leaves_queue() -> void:
	_authorize()
	var ride := _ride()
	_rides.save(ride)
	assert_true(_service.queue.has(ride.id))
	_rides.delete(ride.id)
	_service.on_ride_deleted(ride.id)
	assert_false(_service.queue.has(ride.id), "REQ-LOC-06 крит. 3")
	assert_eq(await _service.step_queue(), null)
	assert_eq(_mock.request_count(), 0)


func test_failed_upload_status_and_retry_reach_repository() -> void:
	_authorize()
	var ride := _ride()
	_rides.save(ride)
	_mock.offline = true
	await _service.step_queue()
	var saved := _rides.get_ride(ride.id)
	assert_eq(str(saved.upload["strava_status"]), Ride.UPLOAD_QUEUED, "сеть недоступна — остаётся в очереди")
	assert_eq(int(saved.upload["attempts"]), 1)
	assert_string_contains(str(saved.upload["last_error"]), "Strava")
	assert_true(_service.queue.has(ride.id))
	_mock.offline = false
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 9, "error": "duplicate of activity 1", "activity_id": null})
	_now = NOW + 60
	await _service.step_queue()
	assert_eq(str(_rides.get_ride(ride.id).upload["strava_status"]), Ride.UPLOAD_DUPLICATE, "REQ-STR-05 крит. 1: дубликат")


func test_tick_drives_queue_every_five_seconds_and_not_during_session() -> void:
	_authorize()
	var ride := _ride()
	_rides.save(ride)
	_ok_upload(1, 3)
	_service.set_session_active(true)
	for i in 10:
		_service.tick(1.0)
	assert_eq(_mock.request_count(), 0, "REQ-STR-04 крит. 6: во время тренировки очередь стоит")
	_service.set_session_active(false)
	_service.tick(4.0)
	assert_eq(_mock.request_count(), 0, "до 5 с тика нет")
	_service.tick(1.0)
	assert_eq(_mock.request_count(), 1, "шаг очереди раз в 5 с")
	assert_eq(str(_rides.get_ride(ride.id).upload["strava_status"]), Ride.UPLOAD_DONE)


func test_step_queue_without_authorization_makes_no_requests() -> void:
	_service.queue.enqueue("ride-x", Callable(), "n", "", NOW)
	await _service.step_queue()
	assert_eq(_mock.request_count(), 0)


# ---------------------------------------------------------------------------
# Вход и отвязка (REQ-STR-01 крит. 7, 8; REQ-PRF-03 крит. 2)
# ---------------------------------------------------------------------------

func test_connect_flow_start_returns_authorize_url_with_loopback_redirect() -> void:
	var flow: Array = []
	_service.connect_flow_changed.connect(func(s: String, m: String) -> void: flow.append([s, m]))
	var url := _service.connect_flow_start()
	assert_true(url.begins_with("https://mock.strava.test/oauth/authorize?"), url)
	assert_string_contains(url, "client_id=4242")
	assert_string_contains(url, "redirect_uri=http%3A%2F%2F127.0.0.1%3A", "REQ-STR-01 крит. 7: loopback")
	assert_string_contains(url, "scope=activity%3Awrite%2Cread")
	assert_true(_service.oauth.is_listening())
	assert_eq(_service.flow_state(), "waiting")
	assert_eq(str(flow[0][0]), "waiting")
	_service.connect_flow_cancel()
	assert_false(_service.oauth.is_listening())
	assert_eq(_service.flow_state(), "idle")


func test_connect_flow_unavailable_without_config() -> void:
	_service.dispose()
	_service = _make_service(StravaConfig.load("user://nonexistent_fixture_secrets.cfg"))
	assert_false(_service.is_configured())
	var url := _service.connect_flow_start()
	assert_eq(url, "", "REQ-STR-01 крит. 6: без client_id/secret входа нет")
	assert_eq(_service.flow_state(), "failed")
	assert_false(_service.oauth.is_listening())


func test_redirect_code_is_exchanged_and_authorized_changed() -> void:
	_service.connect_flow_start()
	_mock.enqueue_json("POST", "/oauth/token", 200, {"access_token": "fixture-access-token-aaaa", "refresh_token": "fixture-refresh-token-rrrr",
			"expires_at": NOW + 21600, "athlete": {"id": 1, "firstname": "Test", "lastname": "Rider"}})
	_service.handle_redirect_url("ovoschrider://strava?code=c0de&state=" + _service.oauth.expected_state)
	await get_tree().process_frame
	assert_true(_service.is_authorized(), "REQ-STR-01 крит. 2")
	assert_eq(_auth_events, [true])
	assert_eq(_service.flow_state(), "done")
	var bad := _make_service()
	bad.handle_redirect_url("ovoschrider://strava?error=access_denied")
	assert_eq(bad.flow_state(), "failed")
	bad.dispose()


func test_disconnect_revokes_tokens_clears_queue_and_resets_statuses() -> void:
	_authorize()
	var ride := _ride()
	_rides.save(ride)
	assert_true(_service.queue.has(ride.id))
	_store.set_secret(SecureStore.key_for(_profile.id, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY), "intervals-fixture-key")
	_mock.enqueue_json("POST", "/oauth/deauthorize", 200, {})
	var r: ApiResult = await _service.disconnect_strava()
	assert_true(r.ok)
	assert_false(_service.is_authorized(), "REQ-STR-01 крит. 8")
	assert_eq(_service.queue.size(), 0, "REQ-PRF-03 крит. 2: очередь профиля очищена")
	assert_eq(str(_rides.get_ride(ride.id).upload["strava_status"]), Ride.UPLOAD_NONE, "ожидавший заезд снова «не выгружен»")
	assert_true(_store.has_secret(SecureStore.key_for(_profile.id, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY)), "Intervals цел")
	assert_eq(_auth_events, [false])
	assert_eq(_make_service().queue.size(), 0, "очередь очищена и на диске")


func test_adapter_maps_queue_status_to_ride_upload_and_back() -> void:
	var up := RideRepositoryUploadStore.to_ride_upload(UploadResult.done("55").to_status_dict(2, 1))
	assert_eq(up, {"strava_status": "done", "strava_activity_id": "55", "last_error": "", "last_error_code": "",
		"last_error_detail": "", "attempts": 2})
	var rejected := StravaUploader.interpret_upload_status({"id": 7, "error": "Improperly formatted data.", "activity_id": null})
	var failed_up := RideRepositoryUploadStore.to_ride_upload(rejected.to_status_dict(1, 1))
	assert_eq(str(failed_up["last_error_code"]), ApiResult.CODE_BAD_RESPONSE, "код причины в метаданных заезда")
	assert_eq(str(failed_up["last_error_detail"]), "Improperly formatted data.", "ответ Strava — отдельной деталью")
	var back := RideRepositoryUploadStore.from_ride_upload({"strava_status": "failed", "strava_activity_id": "",
		"last_error": "нет связи со Strava", "last_error_code": ApiResult.CODE_NETWORK, "attempts": 3})
	assert_eq(str(back["status"]), "failed")
	assert_eq(str(back["error"]), "нет связи со Strava")
	assert_eq(str(back["code"]), ApiResult.CODE_NETWORK)
	assert_eq(str(back["detail"]), "")
	assert_eq(int(back["attempts"]), 3)
	var ride := _ride()
	_rides.save(ride)
	var adapter := RideRepositoryUploadStore.new(_rides)
	adapter.update_upload_status(ride.id, UploadResult.failed("err", ApiResult.CODE_BAD_RESPONSE).to_status_dict(1, 0))
	assert_eq(str(adapter.get_upload_status(ride.id)["status"]), "failed")
	assert_eq(str(_rides.get_ride(ride.id).upload["last_error"]), "err")
	assert_eq(str(_rides.get_ride(ride.id).upload["last_error_code"]), ApiResult.CODE_BAD_RESPONSE, "код сохранён на диске")
	assert_eq(str(adapter.get_upload_status(ride.id)["code"]), ApiResult.CODE_BAD_RESPONSE)
	assert_eq(adapter.get_upload_status("missing"), {})


func test_dispose_unsubscribes_from_repository() -> void:
	_authorize()
	_service.dispose()
	var ride := _ride()
	_rides.save(ride)
	assert_false(_service.queue.has(ride.id), "после dispose подписки нет")
	_service = _make_service()


func test_profile_strava_auto_upload_round_trip_default_true() -> void:
	var p := Profile.create("x")
	assert_true(p.strava_auto_upload, "по умолчанию включена")
	p.strava_auto_upload = false
	assert_false(Profile.from_dict(p.to_dict()).strava_auto_upload)
	assert_true(Profile.from_dict({"id": "a", "name": "old"}).strava_auto_upload, "старые файлы → true")
	assert_eq(SecureStore.read_env("OVOSCH_RIDER_SURELY_UNSET_VARIABLE_FIXTURE"), "", "read_env: нет переменной → пусто")
