extends GutTest
## Устойчивость Strava-интеграции (финальное ревью): loopback-сервер с «зависшими»
## соединениями, одноразовый `state`, страница по результату, сбой SecureStore при сохранении
## токенов, гонки отвязки/удаления с идущей выгрузкой, окончательные 4xx при опросе,
## тайм-аут загрузки, id активности у дубликата, атомарная запись очереди
## (REQ-STR-01 крит. 2, 3, 7, 8; REQ-STR-02 крит. 3, 4; REQ-STR-04 крит. 1, 2; REQ-NFR-05).

const PROFILE: String = "profile-h"
const BASE: String = "https://mock.strava.test"
const API: String = "https://mock.strava.test/api/v3"
const ACCESS: String = "fixture-access-token-hhhh"
const REFRESH: String = "fixture-refresh-token-hhhh"
const NEW_ACCESS: String = "fixture-access-token-nnnn"
const NEW_REFRESH: String = "fixture-refresh-token-nnnn"
const NOW: int = 1_800_000_000
const PORT_FROM: int = 49460
const PORT_TO: int = 49499
var FIT: PackedByteArray = PackedByteArray([0x0E, 0x10, 0x5A, 0x08, 0x2E, 0x46, 0x49, 0x54])

var _mock: MockHttpTransport
var _store: MemorySecureStore
var _cfg: StravaConfig
var _oauth: StravaOAuth
var _now: int = NOW
var _dir: String
var _clients: Array[StreamPeerTCP] = []


## Транспорт, задерживающий запросы с `pattern` в URL до сигнала `release`; остальные — сразу в мок.
class GateTransport:
	extends HttpTransport
	signal release
	var inner: MockHttpTransport
	var pattern: String
	var waiting: int = 0

	func _init(wrapped: MockHttpTransport, gate_pattern: String) -> void:
		inner = wrapped
		pattern = gate_pattern

	func request(method: String, url: String, headers: Dictionary,
			body: PackedByteArray = PackedByteArray(), timeout_sec: float = DEFAULT_TIMEOUT_SEC) -> HttpResponse:
		if url.contains(pattern):
			waiting += 1
			await release
			waiting -= 1
		return inner.request(method, url, headers, body, timeout_sec)


## Хранилище, которое отказывает в записи (как не прочитанный/не записываемый файл).
class FailingStore:
	extends MemorySecureStore
	var fail_from_call: int = 0
	var calls: int = 0

	func set_secret(key: String, value: String) -> bool:
		calls += 1
		if calls > fail_from_call:
			return false
		return super.set_secret(key, value)

	func last_error() -> Error:
		return ERR_FILE_CANT_WRITE


func before_each() -> void:
	_now = NOW
	_mock = MockHttpTransport.new()
	_store = MemorySecureStore.new()
	_cfg = StravaConfig.from_values("4242", "fixture-client-secret-value")
	_oauth = _make_oauth(_mock, _store)
	_dir = "user://test_strava_hardening_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_clients = []


func after_each() -> void:
	for c in _clients:
		c.disconnect_from_host()
	_oauth.stop_listener()
	AtomicFile.simulate_write_error_prefix = ""
	var abs := ProjectSettings.globalize_path(_dir)
	var d := DirAccess.open(abs)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(abs.path_join(f))
		DirAccess.remove_absolute(abs)


func _make_oauth(transport: HttpTransport, store: SecureStore) -> StravaOAuth:
	var o := StravaOAuth.new(transport, store, PROFILE, _cfg)
	o.base_url = BASE
	o.clock_fn = func() -> int: return _now
	return o


func _seed_tokens(store: SecureStore, oauth: StravaOAuth, expires_at: int) -> void:
	store.set_secret(oauth.secret_key(SecureStore.ITEM_ACCESS_TOKEN), ACCESS)
	store.set_secret(oauth.secret_key(SecureStore.ITEM_REFRESH_TOKEN), REFRESH)
	store.set_secret(oauth.secret_key(SecureStore.ITEM_EXPIRES_AT), str(expires_at))


func _token_payload(access: String, refresh: String) -> Dictionary:
	return {"token_type": "Bearer", "access_token": access, "refresh_token": refresh, "expires_at": NOW + 21600,
			"athlete": {"id": 5, "firstname": "H", "lastname": "R"}}


# ---------------------------------------------------------------------------
# Loopback: зависшие соединения не блокируют настоящий callback
# ---------------------------------------------------------------------------

func _connect_client() -> StreamPeerTCP:
	var client := StreamPeerTCP.new()
	assert_eq(client.connect_to_host("127.0.0.1", _oauth.listener_port()), OK)
	for i in 300:
		client.poll()
		if client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
		await get_tree().process_frame
	assert_eq(client.get_status(), StreamPeerTCP.STATUS_CONNECTED, "клиент подключился")
	_clients.append(client)
	return client


## Крутить `poll_listener`, пока не появится результат (или до лимита кадров).
func _poll_until_result(frames: int = 120) -> Dictionary:
	for i in frames:
		var r := _oauth.poll_listener()
		if not r.is_empty():
			return r
		await get_tree().process_frame
	return {}


## Дождаться, пока слушатель примет соединения (число незавершённых ≥ n).
func _poll_until_pending(n: int) -> void:
	for i in 120:
		_oauth.poll_listener()
		if _oauth.pending_connection_count() >= n:
			return
		await get_tree().process_frame


func _read_response(client: StreamPeerTCP) -> String:
	var response := ""
	for i in 100:
		client.poll()
		var n := client.get_available_bytes()
		if n > 0:
			response += client.get_utf8_string(n)
		if response.contains("</html>"):
			break
		await get_tree().process_frame
	return response


func test_stalled_connection_does_not_block_real_callback() -> void:
	_oauth.start_loopback_listener(PORT_FROM, PORT_TO)
	_oauth.authorize_url("st-stall")
	var stalled: StreamPeerTCP = await _connect_client()
	stalled.put_data("GET /callb".to_utf8_buffer())  # заголовки так и не приходят
	await _poll_until_pending(1)
	var real: StreamPeerTCP = await _connect_client()
	real.put_data("GET /callback?state=st-stall&code=real-code HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".to_utf8_buffer())
	var r: Dictionary = await _poll_until_result()
	assert_eq(str(r.get("code", "")), "real-code", "настоящий callback принят, несмотря на зависшее соединение: %s" % str(r))
	assert_false(_oauth.is_listening(), "слушатель остановлен после callback")
	assert_string_contains(await _read_response(real), "Strava подключена")


func test_connection_closed_before_headers_is_dropped_and_callback_still_works() -> void:
	_oauth.start_loopback_listener(PORT_FROM, PORT_TO)
	_oauth.authorize_url("st-closed")
	var gone: StreamPeerTCP = await _connect_client()
	gone.put_data("GET /call".to_utf8_buffer())
	await _poll_until_pending(1)
	gone.disconnect_from_host()
	for i in 120:
		_oauth.poll_listener()
		if _oauth.pending_connection_count() == 0:
			break
		await get_tree().process_frame
	assert_eq(_oauth.pending_connection_count(), 0, "закрытое клиентом соединение сброшено")
	assert_true(_oauth.is_listening())
	var real: StreamPeerTCP = await _connect_client()
	real.put_data("GET /callback?state=st-closed&code=c2 HTTP/1.1\r\n\r\n".to_utf8_buffer())
	var r: Dictionary = await _poll_until_result()
	assert_eq(str(r.get("code", "")), "c2", str(r))


func test_idle_connection_is_dropped_after_5_seconds() -> void:
	_oauth.start_loopback_listener(PORT_FROM, PORT_TO)
	_oauth.authorize_url("st-idle")
	var idle: StreamPeerTCP = await _connect_client()
	idle.put_data("GET /".to_utf8_buffer())
	await _poll_until_pending(1)
	assert_eq(_oauth.pending_connection_count(), 1)
	_now = NOW + StravaOAuth.PEER_IDLE_TIMEOUT_SEC - 1
	_oauth.poll_listener()
	assert_eq(_oauth.pending_connection_count(), 1, "4 с простоя — ещё ждём")
	_now = NOW + StravaOAuth.PEER_IDLE_TIMEOUT_SEC
	_oauth.poll_listener()
	assert_eq(_oauth.pending_connection_count(), 0, "5 с простоя — соединение сброшено")
	assert_true(_oauth.is_listening(), "сам слушатель продолжает ждать (до 60 с)")
	assert_eq(StravaOAuth.PEER_IDLE_TIMEOUT_SEC, 5)


# ---------------------------------------------------------------------------
# Страница браузеру по результату (п. 10)
# ---------------------------------------------------------------------------

func test_state_mismatch_page_does_not_claim_success() -> void:
	_oauth.start_loopback_listener(PORT_FROM, PORT_TO)
	_oauth.authorize_url("expected")
	var client: StreamPeerTCP = await _connect_client()
	client.put_data("GET /callback?state=forged&code=x HTTP/1.1\r\n\r\n".to_utf8_buffer())
	var r: Dictionary = await _poll_until_result()
	assert_eq(str(r.get("error", "")), "state_mismatch")
	var page: String = await _read_response(client)
	assert_true(page.contains("</html>"), "страница получена: %s" % page.substr(0, 60))
	assert_false(page.contains("Strava подключена"), "при отказе успех не показывается")
	assert_string_contains(page, "Strava не подключена")
	assert_false(page.begins_with("HTTP/1.1 200"), "отказ — не 200")


func test_access_denied_page_does_not_claim_success() -> void:
	_oauth.start_loopback_listener(PORT_FROM, PORT_TO)
	_oauth.authorize_url("expected")
	var client: StreamPeerTCP = await _connect_client()
	client.put_data("GET /callback?state=expected&error=access_denied HTTP/1.1\r\n\r\n".to_utf8_buffer())
	var r: Dictionary = await _poll_until_result()
	assert_eq(str(r.get("error", "")), "access_denied")
	var page: String = await _read_response(client)
	assert_false(page.contains("Strava подключена"))
	assert_string_contains(page, "отменён")


# ---------------------------------------------------------------------------
# state: обязателен и одноразов (п. 9)
# ---------------------------------------------------------------------------

func test_empty_expected_state_rejects_redirect() -> void:
	assert_eq(_oauth.expected_state, "", "вход не начинали")
	var r := _oauth.handle_redirect_url("ovoschrider://strava?state=anything&code=c")
	assert_eq(str(r.get("error", "")), "state_mismatch", "без ожидаемого state код не принимается")
	var r2 := _oauth.handle_redirect_url("ovoschrider://strava?code=c")
	assert_eq(str(r2.get("error", "")), "state_mismatch", "и без state в URL тоже")


func test_state_is_cleared_after_use_and_replay_is_rejected() -> void:
	_oauth.authorize_url("one-time")
	var ok := _oauth.handle_redirect_url("ovoschrider://strava?state=one-time&code=c1")
	assert_eq(str(ok.get("code", "")), "c1")
	assert_eq(_oauth.expected_state, "", "state очищен после использования")
	var replay := _oauth.handle_redirect_url("ovoschrider://strava?state=one-time&code=c1")
	assert_eq(str(replay.get("error", "")), "state_mismatch", "повтор того же redirect отклонён")


# ---------------------------------------------------------------------------
# Сбой SecureStore при сохранении токенов (п. 2)
# ---------------------------------------------------------------------------

func test_exchange_code_fails_with_storage_code_when_store_rejects_tokens() -> void:
	var store := FailingStore.new()
	var oauth := _make_oauth(_mock, store)
	_mock.enqueue_json("POST", "/oauth/token", 200, _token_payload(ACCESS, REFRESH))
	var r: ApiResult = await oauth.exchange_code("code-1")
	assert_false(r.ok, "ошибка сохранения — не success")
	assert_eq(r.code, ApiResult.CODE_STORAGE_FAILED)
	assert_string_contains(r.message, "защищённое хранилище")
	assert_false(oauth.is_authorized())
	assert_false(r.message.contains(ACCESS) or r.message.contains(REFRESH), "токены не в сообщении")


func test_exchange_code_partial_store_failure_leaves_no_tokens() -> void:
	var store := FailingStore.new()
	store.fail_from_call = 1  # access записан, refresh — нет
	var oauth := _make_oauth(_mock, store)
	_mock.enqueue_json("POST", "/oauth/token", 200, _token_payload(ACCESS, REFRESH))
	var r: ApiResult = await oauth.exchange_code("code-2")
	assert_eq(r.code, ApiResult.CODE_STORAGE_FAILED)
	assert_eq(store.list_keys(PROFILE + "/strava/"), [] as Array[String], "частично записанные токены удалены")


func test_refresh_fails_with_storage_code_when_store_rejects_tokens() -> void:
	var store := FailingStore.new()
	store.fail_from_call = 3
	var oauth := _make_oauth(_mock, store)
	_seed_tokens(store, oauth, NOW + 10)
	_mock.enqueue_json("POST", "/oauth/token", 200, _token_payload(NEW_ACCESS, NEW_REFRESH))
	var r: ApiResult = await oauth.refresh_token()
	assert_false(r.ok)
	assert_eq(r.code, ApiResult.CODE_STORAGE_FAILED)


func test_secure_store_failure_api_is_available_on_interface() -> void:
	var s: SecureStore = MemorySecureStore.new()
	assert_true(s.loaded_ok())
	assert_eq(s.last_error(), OK)
	s.set_secret("p/strava/access_token", "x")
	s.reset_store()
	assert_eq(s.list_keys(), [] as Array[String], "reset_store очищает хранилище")


# ---------------------------------------------------------------------------
# Гонки с отвязкой (п. 6)
# ---------------------------------------------------------------------------

var _refresh_result: ApiResult = null


func _run_refresh(oauth: StravaOAuth) -> void:
	_refresh_result = await oauth.refresh_token()


func test_refresh_response_after_revoke_does_not_restore_tokens() -> void:
	var gate := GateTransport.new(_mock, "/oauth/token")
	var oauth := _make_oauth(gate, _store)
	_seed_tokens(_store, oauth, NOW + 10)
	_mock.enqueue_json("POST", "/oauth/token", 200, _token_payload(NEW_ACCESS, NEW_REFRESH))
	_mock.enqueue_json("POST", "/oauth/deauthorize", 200, {"access_token": ACCESS})
	_refresh_result = null
	_run_refresh(oauth)
	assert_eq(gate.waiting, 1, "обновление токена в полёте")
	var revoked: ApiResult = await oauth.revoke()
	assert_true(revoked.ok)
	assert_false(oauth.is_authorized(), "после отвязки токенов нет")
	gate.release.emit()
	for i in 5:
		if _refresh_result != null:
			break
		await get_tree().process_frame
	assert_not_null(_refresh_result, "обновление завершилось")
	assert_false(_refresh_result.ok, "ответ после отвязки не считается успехом")
	assert_false(oauth.is_authorized(), "поздний ответ refresh_token не вернул привязку")
	assert_eq(_store.list_keys(PROFILE + "/strava/"), [] as Array[String], "токены не записаны снова")


func _make_queue(transport: HttpTransport, status: MemoryUploadStatusStore) -> UploadQueue:
	var oauth := _make_oauth(transport, _store)
	_seed_tokens(_store, oauth, NOW + 999999)
	var uploader := StravaUploader.new(transport, oauth)
	uploader.api_base = API
	uploader.wait_fn = func(_sec: float) -> void: pass
	var q := UploadQueue.new(uploader, status, func() -> int: return _now, PROFILE, _dir)
	q.fit_provider = func(_ride_id: String) -> PackedByteArray: return FIT
	return q


func test_remove_during_upload_does_not_write_stale_result() -> void:
	var gate := GateTransport.new(_mock, "/uploads")
	var status := MemoryUploadStatusStore.new()
	var queue := _make_queue(gate, status)
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 501, "activity_id": 9001, "error": null})
	var finished: Array[String] = []
	queue.upload_finished.connect(func(id: String, _a: String) -> void: finished.append(id))
	queue.enqueue("ride-r", Callable(), "N", "D", NOW)
	queue.tick()
	assert_true(queue.is_busy(), "выгрузка идёт")
	assert_eq(str(status.get_upload_status("ride-r")["status"]), UploadResult.STATUS_UPLOADING)
	assert_true(queue.remove("ride-r"))
	assert_eq(str(status.get_upload_status("ride-r")["status"]), UploadResult.STATUS_NONE, "отмена → «не выгружен»")
	gate.release.emit()
	await get_tree().process_frame
	assert_false(queue.is_busy())
	assert_eq(str(status.get_upload_status("ride-r")["status"]), UploadResult.STATUS_NONE,
			"результат выгрузки после удаления из очереди не записан: %s" % str(status.status_sequence("ride-r")))
	assert_eq(finished, [] as Array[String])
	assert_false(queue.has("ride-r"))


# ---------------------------------------------------------------------------
# Опрос: 404/4xx — окончательная ошибка (п. 11); тайм-аут и дубликат (п. 12)
# ---------------------------------------------------------------------------

func _uploader() -> StravaUploader:
	_seed_tokens(_store, _oauth, NOW + 999999)
	var u := StravaUploader.new(_mock, _oauth)
	u.api_base = API
	u.wait_fn = func(_sec: float) -> void: pass
	return u


func test_poll_404_is_final_failure_not_uploading() -> void:
	var u := _uploader()
	_mock.enqueue_json("GET", "/uploads/404404", 404, {"message": "Record Not Found"})
	var r: UploadResult = await u.poll_upload("404404")
	assert_eq(r.status, UploadResult.STATUS_FAILED, "404 при опросе — не «обрабатывается»")
	assert_false(r.can_retry, "окончательная ошибка")
	assert_true(r.is_final())
	assert_eq(r.upload_id, "404404")
	assert_eq(_mock.request_count("GET", "/uploads/404404"), 1, "без повторных опросов")


func test_poll_other_4xx_is_final_but_429_and_5xx_are_not() -> void:
	var u := _uploader()
	_mock.enqueue_json("GET", "/uploads/7", 403, {"message": "Forbidden"})
	var forbidden: UploadResult = await u.poll_upload("7")
	assert_eq(forbidden.status, UploadResult.STATUS_FAILED)
	assert_false(forbidden.can_retry)
	_mock.enqueue_json("GET", "/uploads/8", 429, {"message": "Rate"}, {"Retry-After": "30"})
	var limited: UploadResult = await u.poll_upload("8")
	assert_eq(limited.status, UploadResult.STATUS_UPLOADING, "429 — опросим позже")
	_mock.enqueue_json("GET", "/uploads/9", 503, {})
	var down: UploadResult = await u.poll_upload("9")
	assert_eq(down.status, UploadResult.STATUS_UPLOADING, "5xx — опросим позже")


func test_queue_finishes_item_on_poll_404() -> void:
	var status := MemoryUploadStatusStore.new()
	var queue := _make_queue(_mock, status)
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 600, "activity_id": null, "error": null, "status": "Your activity is still being processed."})
	_mock.enqueue_json("GET", "/uploads/600", 404, {"message": "Record Not Found"})
	queue.enqueue("ride-404", Callable(), "N", "D", NOW)
	await queue.tick()
	assert_false(queue.has("ride-404"), "элемент снят с очереди")
	assert_eq(str(status.get_upload_status("ride-404")["status"]), UploadResult.STATUS_FAILED)


func test_upload_post_uses_long_timeout() -> void:
	var u := _uploader()
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 1, "activity_id": 2, "error": null})
	await u.upload_fit(FIT, "n", "d", "ride-t")
	var post: Dictionary = _mock.requests.filter(func(q: Dictionary) -> bool: return q["method"] == "POST")[0]
	assert_eq(float(post["timeout_sec"]), 120.0, "тайм-аут загрузки файла 120 с")


func test_duplicate_extracts_activity_id_from_strava_error() -> void:
	var text := "ride-1.fit duplicate of <a href='/activities/1234567890' target='_blank'>Morning Ride</a>"
	var r := StravaUploader.interpret_upload_status({"id": 77, "error": text, "activity_id": null})
	assert_eq(r.status, UploadResult.STATUS_DUPLICATE)
	assert_eq(r.activity_id, "1234567890", "id существующей активности из текста ошибки")
	assert_eq(StravaUploader.duplicate_activity_id("x duplicate of activity 42"), "42")
	var plain := StravaUploader.interpret_upload_status({"id": 78, "error": "duplicate upload"})
	assert_eq(plain.status, UploadResult.STATUS_DUPLICATE)
	assert_eq(plain.activity_id, "", "нет ссылки — id пуст, поведение прежнее")


# ---------------------------------------------------------------------------
# Атомарная запись очереди (п. 15)
# ---------------------------------------------------------------------------

func test_queue_save_is_atomic_and_keeps_previous_file_on_write_error() -> void:
	var status := MemoryUploadStatusStore.new()
	var queue := _make_queue(_mock, status)
	queue.enqueue("ride-a", Callable(), "A", "", NOW)
	var before := FileAccess.get_file_as_string(queue.file_path())
	assert_string_contains(before, "ride-a")
	AtomicFile.simulate_write_error_prefix = queue.file_path()
	queue.enqueue("ride-b", Callable(), "B", "", NOW + 1)
	assert_push_error("AtomicFile")
	AtomicFile.simulate_write_error_prefix = ""
	assert_eq(FileAccess.get_file_as_string(queue.file_path()), before, "прежний файл очереди цел")
	assert_false(FileAccess.file_exists(AtomicFile.tmp_path(queue.file_path())), "временный файл удалён")
	assert_false(queue.save() == false, "запись снова работает")
	assert_string_contains(FileAccess.get_file_as_string(queue.file_path()), "ride-b")
