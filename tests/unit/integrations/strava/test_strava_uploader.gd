extends GutTest
## Тесты StravaUploader (REQ-STR-02 крит. 1, 3, 4; REQ-STR-03 крит. 1–3; REQ-STR-01 крит. 4; REQ-STR-05 крит. 3).

const PROFILE: String = "profile-a"
const API: String = "https://mock.strava.test/api/v3"
const ACCESS: String = "fixture-access-token-aaaa"
const NEW_ACCESS: String = "fixture-access-token-bbbb"
const NOW: int = 1_800_000_000
var FIT: PackedByteArray = PackedByteArray([0x0E, 0x10, 0x5A, 0x08, 0x2A, 0x00, 0x00, 0x00, 0x2E, 0x46, 0x49, 0x54, 0xFF, 0x00])

var _mock: MockHttpTransport
var _store: MemorySecureStore
var _oauth: StravaOAuth
var _uploader: StravaUploader
var _waits: Array[float] = []


func before_each() -> void:
	_mock = MockHttpTransport.new()
	_store = MemorySecureStore.new()
	_oauth = StravaOAuth.new(_mock, _store, PROFILE, StravaConfig.from_values("4242", "fixture-client-secret-value"))
	_oauth.base_url = "https://mock.strava.test"
	_oauth.clock_fn = func() -> int: return NOW
	_store.set_secret(_oauth.secret_key(SecureStore.ITEM_ACCESS_TOKEN), ACCESS)
	_store.set_secret(_oauth.secret_key(SecureStore.ITEM_REFRESH_TOKEN), "fixture-refresh-token-rrrr")
	_store.set_secret(_oauth.secret_key(SecureStore.ITEM_EXPIRES_AT), str(NOW + 3600))
	_uploader = StravaUploader.new(_mock, _oauth)
	_uploader.api_base = API
	_waits = []
	_uploader.wait_fn = func(sec: float) -> void: _waits.append(sec)


func _upload() -> UploadResult:
	return await _uploader.upload_fit(FIT, "Sweet Spot", "Описание", "ride-42")


# ---------------------------------------------------------------------------
# Multipart (REQ-STR-02 крит. 1)
# ---------------------------------------------------------------------------

func test_build_multipart_has_fields_file_and_boundaries() -> void:
	var body := StravaUploader.build_multipart({"data_type": "fit", "name": "N"}, "file", "ride-42.fit", FIT, "BOUNDARY")
	var text := body.get_string_from_utf8()
	assert_string_contains(text, "--BOUNDARY\r\nContent-Disposition: form-data; name=\"data_type\"\r\n\r\nfit\r\n")
	assert_string_contains(text, "Content-Disposition: form-data; name=\"name\"\r\n\r\nN\r\n")
	assert_string_contains(text, "Content-Disposition: form-data; name=\"file\"; filename=\"ride-42.fit\"\r\nContent-Type: application/octet-stream\r\n\r\n")
	var tail := "\r\n--BOUNDARY--\r\n".to_utf8_buffer()
	assert_eq(body.slice(body.size() - tail.size()), tail, "закрывающая граница (байты FIT не UTF-8, поэтому сравниваем байты)")
	# байты FIT присутствуют целиком
	var marker := "Content-Type: application/octet-stream\r\n\r\n".to_utf8_buffer()
	var idx := _find_bytes(body, marker)
	assert_gt(idx, 0)
	assert_eq(body.slice(idx + marker.size(), idx + marker.size() + FIT.size()), FIT, "байты FIT без изменений")


static func _find_bytes(hay: PackedByteArray, needle: PackedByteArray) -> int:
	for i in range(0, hay.size() - needle.size() + 1):
		if hay.slice(i, i + needle.size()) == needle:
			return i
	return -1


func test_upload_request_headers_fields_and_virtual_ride() -> void:
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 555, "status": "Your activity is still being processed.", "activity_id": null, "error": null})
	_mock.enqueue_json("GET", "/uploads/555", 200, {"id": 555, "status": "Your activity is ready.", "activity_id": 777001, "error": null})
	var r: UploadResult = await _upload()
	assert_eq(r.status, UploadResult.STATUS_DONE, r.error)
	var post := _mock.requests[0]
	assert_eq(str(post["method"]), "POST")
	assert_eq(str(post["url"]), API + "/uploads")
	assert_eq(str(post["headers"]["Authorization"]), "Bearer " + ACCESS)
	var ct := str(post["headers"]["Content-Type"])
	assert_true(ct.begins_with("multipart/form-data; boundary="), ct)
	var boundary := ct.substr("multipart/form-data; boundary=".length())
	var text := (post["body"] as PackedByteArray).get_string_from_utf8()
	assert_string_contains(text, "--" + boundary + "\r\n")
	for pair in [["data_type", "fit"], ["external_id", "ride-42"], ["name", "Sweet Spot"], ["description", "Описание"], ["trainer", "1"], ["sport_type", "VirtualRide"], ["activity_type", "VirtualRide"]]:
		assert_string_contains(text, "name=\"%s\"\r\n\r\n%s\r\n" % [pair[0], pair[1]], "REQ-STR-02 крит. 1 / REQ-STR-03 крит. 3: поле %s" % pair[0])
	assert_string_contains(text, "filename=\"ride-42.fit\"")
	assert_eq(float(post["timeout_sec"]), 30.0)


# ---------------------------------------------------------------------------
# Опрос статуса, duplicate, ошибки (REQ-STR-02 крит. 3, 4)
# ---------------------------------------------------------------------------

func test_poll_until_activity_id_with_waits_between_polls() -> void:
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 555, "status": "processing", "activity_id": null, "error": null})
	_mock.enqueue_json("GET", "/uploads/555", 200, {"id": 555, "status": "processing", "activity_id": null, "error": null}, {}, 2)
	_mock.enqueue_json("GET", "/uploads/555", 200, {"id": 555, "status": "ready", "activity_id": 777001, "error": null})
	var r: UploadResult = await _upload()
	assert_eq(r.status, UploadResult.STATUS_DONE, "REQ-STR-02 крит. 3")
	assert_eq(r.activity_id, "777001")
	assert_eq(r.upload_id, "555")
	assert_eq(r.activity_url(), "https://www.strava.com/activities/777001", "REQ-STR-05 крит. 3")
	assert_eq(_mock.request_count("GET", "/uploads/555"), 3)
	assert_eq(_waits, [2.0, 2.0], "пауза между опросами (не перед первым)")
	assert_eq(str(_mock.last_request()["headers"]["Authorization"]), "Bearer " + ACCESS)
	assert_true(r.is_final())


func test_processing_error_is_failed_with_text() -> void:
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 556, "status": "processing", "activity_id": null, "error": null})
	_mock.enqueue_json("GET", "/uploads/556", 200, {"id": 556, "status": "There was an error processing your activity.", "activity_id": null, "error": "The file is malformed"})
	var r: UploadResult = await _upload()
	assert_eq(r.status, UploadResult.STATUS_FAILED, "REQ-STR-02 крит. 3: ошибка с текстом")
	assert_eq(r.error, "The file is malformed")
	assert_false(r.can_retry, "ошибка обработки — без повтора")
	assert_true(r.is_final())


func test_duplicate_is_separate_final_status_without_retries() -> void:
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 557, "status": "error", "activity_id": null, "error": "ride-42.fit duplicate of activity 123456"})
	var r: UploadResult = await _upload()
	assert_eq(r.status, UploadResult.STATUS_DUPLICATE, "REQ-STR-02 крит. 4")
	assert_true(r.is_final())
	assert_false(r.can_retry)
	assert_eq(_mock.request_count(), 1, "опроса нет — статус известен сразу")
	var late := StravaUploader.interpret_upload_status({"id": 1, "error": "Duplicate activity"})
	assert_eq(late.status, UploadResult.STATUS_DUPLICATE)


func test_still_processing_after_max_polls_is_uploading_with_upload_id() -> void:
	_uploader.max_polls = 3
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 558, "status": "processing", "activity_id": null, "error": null})
	_mock.enqueue_json("GET", "/uploads/558", 200, {"id": 558, "status": "processing", "activity_id": null, "error": null}, {}, -1)
	var r: UploadResult = await _upload()
	assert_eq(r.status, UploadResult.STATUS_UPLOADING, "обрабатывается — опросить позже")
	assert_eq(r.upload_id, "558")
	assert_false(r.is_final())
	assert_eq(_mock.request_count("GET"), 3)
	_mock.clear()
	_mock.enqueue_json("GET", "/uploads/558", 200, {"id": 558, "activity_id": 9, "error": null})
	var later: UploadResult = await _uploader.poll_upload("558")
	assert_eq(later.status, UploadResult.STATUS_DONE)
	assert_eq(later.activity_id, "9")


# ---------------------------------------------------------------------------
# 401 → refresh → повтор (REQ-STR-01 крит. 4), 429, сеть
# ---------------------------------------------------------------------------

func test_401_refreshes_token_once_and_retries() -> void:
	_mock.enqueue_json("POST", "/uploads", 401, {"message": "Authorization Error"})
	_mock.enqueue_json("POST", "/oauth/token", 200, {"access_token": NEW_ACCESS, "refresh_token": "fixture-refresh-token-ssss", "expires_at": NOW + 20000})
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 600, "activity_id": 42, "error": null})
	var r: UploadResult = await _upload()
	assert_eq(r.status, UploadResult.STATUS_DONE, r.error)
	assert_eq(_mock.request_count(), 3, "выгрузка, обновление, повтор")
	assert_eq(str(_mock.requests[1]["url"]), "https://mock.strava.test/oauth/token")
	assert_eq(str(_mock.requests[2]["headers"]["Authorization"]), "Bearer " + NEW_ACCESS, "повтор с новым токеном")
	assert_eq(_oauth.access_token(), NEW_ACCESS)


func test_second_401_is_reauth_required() -> void:
	_mock.enqueue_json("POST", "/uploads", 401, {}, {}, -1)
	_mock.enqueue_json("POST", "/oauth/token", 200, {"access_token": NEW_ACCESS, "refresh_token": "r2", "expires_at": NOW + 20000})
	var r: UploadResult = await _upload()
	assert_eq(r.status, UploadResult.STATUS_FAILED)
	assert_eq(r.code, ApiResult.CODE_REAUTH_REQUIRED, "REQ-STR-01 крит. 4: повторный 401 → повторный вход")
	assert_false(r.can_retry)
	assert_eq(_mock.request_count("POST", "/uploads"), 2, "не более одного повтора")


func test_refresh_failure_during_401_is_reauth_required() -> void:
	_mock.enqueue_json("POST", "/uploads", 401, {})
	_mock.enqueue_json("POST", "/oauth/token", 401, {})
	var r: UploadResult = await _upload()
	assert_eq(r.code, ApiResult.CODE_REAUTH_REQUIRED)
	assert_eq(_mock.request_count("POST", "/uploads"), 1)


func test_rate_limit_and_network_are_retryable() -> void:
	_mock.enqueue("POST", "/uploads", HttpResponse.json_response(429, {}, {"Retry-After": "120"}))
	var limited: UploadResult = await _upload()
	assert_eq(limited.status, UploadResult.STATUS_FAILED)
	assert_eq(limited.code, ApiResult.CODE_RATE_LIMITED)
	assert_true(limited.can_retry)
	assert_eq(limited.retry_after_sec, 120, "REQ-STR-04 крит. 3")
	_mock.enqueue_json("POST", "/uploads", 503, {})
	var srv: UploadResult = await _upload()
	assert_eq(srv.code, ApiResult.CODE_NETWORK)
	assert_true(srv.can_retry)
	_mock.offline = true
	var off: UploadResult = await _upload()
	assert_eq(off.code, ApiResult.CODE_NETWORK)
	assert_true(off.can_retry)
	assert_false(off.is_final())


func test_without_authorization_or_fit_no_request() -> void:
	var empty: UploadResult = await _uploader.upload_fit(PackedByteArray(), "n", "d", "r")
	assert_eq(empty.status, UploadResult.STATUS_FAILED)
	assert_eq(_mock.request_count(), 0)
	_store.delete_service_secrets(PROFILE, SecureStore.SERVICE_STRAVA)
	var r: UploadResult = await _upload()
	assert_eq(r.code, ApiResult.CODE_REAUTH_REQUIRED, "без привязки — вход, запросов нет")
	assert_eq(_mock.request_count(), 0)


func test_400_with_message_is_failed_without_retry() -> void:
	_mock.enqueue_json("POST", "/uploads", 400, {"message": "Bad Request", "errors": []})
	var r: UploadResult = await _upload()
	assert_eq(r.status, UploadResult.STATUS_FAILED)
	assert_string_contains(r.error, "Bad Request")
	assert_false(r.can_retry)


# ---------------------------------------------------------------------------
# Название и описание (REQ-STR-03 крит. 1, 2)
# ---------------------------------------------------------------------------

func test_default_name_and_description() -> void:
	assert_eq(StravaUploader.default_name("Sweet Spot", "2026-10-03"), "Sweet Spot", "REQ-STR-03 крит. 1: название плана")
	assert_eq(StravaUploader.default_name("  ", "2026-10-03"), "Тренировка 2026-10-03", "REQ-STR-03 крит. 1: без плана")
	assert_eq(StravaUploader.default_name("", "03.10", "Workout %s"), "Workout 03.10", "шаблон на языке интерфейса")
	var d := StravaUploader.default_description("3x10 sweet spot")
	assert_string_contains(d, "3x10 sweet spot", "REQ-STR-03 крит. 2: описание плана")
	assert_string_contains(d, "ovosch-rider", "REQ-STR-03 крит. 2: название приложения")
	assert_eq(StravaUploader.default_description(""), "Записано в ovosch-rider")
	assert_eq(StravaUploader.activity_url("5"), "https://www.strava.com/activities/5")
	var s := UploadResult.done("12").to_status_dict(2, 100)
	assert_eq(str(s["status"]), "done")
	assert_eq(str(s["activity_id"]), "12")
	assert_eq(int(s["attempts"]), 2)
