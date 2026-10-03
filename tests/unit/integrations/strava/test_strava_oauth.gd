extends GutTest
## Тесты StravaOAuth (REQ-STR-01 крит. 1–8; REQ-PRF-03 крит. 1, 2; REQ-NFR-05 крит. 1, 2).

const PROFILE: String = "profile-a"
const BASE: String = "https://mock.strava.test"
const ACCESS: String = "fixture-access-token-aaaa"
const REFRESH: String = "fixture-refresh-token-rrrr"
const NEW_ACCESS: String = "fixture-access-token-bbbb"
const NEW_REFRESH: String = "fixture-refresh-token-ssss"
const NOW: int = 1_800_000_000

var _mock: MockHttpTransport
var _store: MemorySecureStore
var _cfg: StravaConfig
var _oauth: StravaOAuth
var _now: int = NOW


func before_each() -> void:
	_mock = MockHttpTransport.new()
	_store = MemorySecureStore.new()
	_cfg = StravaConfig.from_values("4242", "fixture-client-secret-value")
	_oauth = _make(PROFILE)
	_now = NOW


func after_each() -> void:
	_oauth.stop_listener()


func _make(profile_id: String) -> StravaOAuth:
	var o := StravaOAuth.new(_mock, _store, profile_id, _cfg)
	o.base_url = BASE
	o.clock_fn = func() -> int: return _now
	return o


func _token_payload(access: String, refresh: String, expires_at: int) -> Dictionary:
	return {"token_type": "Bearer", "access_token": access, "refresh_token": refresh, "expires_at": expires_at, "expires_in": expires_at - NOW,
			"athlete": {"id": 99001, "firstname": "Test", "lastname": "Rider"}}


func _seed_tokens(expires_at: int) -> void:
	_store.set_secret(_oauth.secret_key(SecureStore.ITEM_ACCESS_TOKEN), ACCESS)
	_store.set_secret(_oauth.secret_key(SecureStore.ITEM_REFRESH_TOKEN), REFRESH)
	_store.set_secret(_oauth.secret_key(SecureStore.ITEM_EXPIRES_AT), str(expires_at))


static func _form(body: PackedByteArray) -> Dictionary:
	var out := {}
	for pair in body.get_string_from_utf8().split("&", false):
		var eq := pair.find("=")
		out[pair.substr(0, eq).uri_decode()] = pair.substr(eq + 1).uri_decode()
	return out


# ---------------------------------------------------------------------------
# URL авторизации (крит. 1)
# ---------------------------------------------------------------------------

func test_authorize_url_has_required_params() -> void:
	var url := _oauth.authorize_url("state-xyz", "http://127.0.0.1:50000/callback")
	assert_true(url.begins_with(BASE + "/oauth/authorize?"))
	assert_string_contains(url, "client_id=4242", "REQ-STR-01 крит. 1")
	assert_string_contains(url, "redirect_uri=http%3A%2F%2F127.0.0.1%3A50000%2Fcallback")
	assert_string_contains(url, "response_type=code")
	assert_string_contains(url, "scope=activity%3Awrite%2Cread", "scope с activity:write")
	assert_string_contains(url, "state=state-xyz")
	assert_false(url.contains("fixture-client-secret-value"), "секрет не в URL")
	assert_eq(_oauth.expected_state, "state-xyz")


func test_authorize_url_generates_state_and_uses_mobile_redirect_by_default() -> void:
	var url := _oauth.authorize_url()
	assert_eq(_oauth.expected_state.length(), 32, "state сгенерирован")
	assert_string_contains(url, "redirect_uri=ovoschrider%3A%2F%2Fstrava", "без loopback — мобильная схема")
	assert_eq(_oauth.current_redirect_uri(), StravaOAuth.MOBILE_REDIRECT_URI)


# ---------------------------------------------------------------------------
# Loopback-сервер (крит. 7)
# ---------------------------------------------------------------------------

func _connect_client(port: int) -> StreamPeerTCP:
	var client := StreamPeerTCP.new()
	assert_eq(client.connect_to_host("127.0.0.1", port), OK)
	for i in 200:
		client.poll()
		if client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
		await get_tree().process_frame
	assert_eq(client.get_status(), StreamPeerTCP.STATUS_CONNECTED, "клиент подключился к loopback")
	return client


func _drive(path: String) -> Dictionary:
	var client: StreamPeerTCP = await _connect_client(_oauth.listener_port())
	client.put_data(("GET %s HTTP/1.1\r\nHost: 127.0.0.1\r\nUser-Agent: test\r\n\r\n" % path).to_utf8_buffer())
	var result := {}
	for i in 200:
		result = _oauth.poll_listener()
		if not result.is_empty():
			break
		await get_tree().process_frame
	var response := ""
	for i in 50:
		client.poll()
		var n := client.get_available_bytes()
		if n > 0:
			response += client.get_utf8_string(n)
		if response.contains("</html>"):
			break
		await get_tree().process_frame
	client.disconnect_from_host()
	result["_response"] = response
	return result


func test_loopback_listener_receives_code_and_responds_with_close_page() -> void:
	var uri := _oauth.start_loopback_listener(49400, 49450)
	assert_true(uri.begins_with("http://127.0.0.1:"), "REQ-STR-01 крит. 7: loopback redirect")
	assert_true(uri.ends_with("/callback"))
	assert_eq(uri, "http://127.0.0.1:%d/callback" % _oauth.listener_port(), "redirect_uri совпадает с фактическим портом")
	assert_true(_oauth.is_listening())
	var url := _oauth.authorize_url("st4te")
	assert_string_contains(url, "redirect_uri=" + uri.uri_encode(), "URL авторизации использует loopback-порт")
	var received: Array[String] = []
	_oauth.authorization_code_received.connect(func(c: String) -> void: received.append(c))
	var r: Dictionary = await _drive("/callback?state=st4te&code=abc123&scope=read,activity:write")
	assert_eq(str(r.get("code", "")), "abc123", "код разобран: %s" % str(r))
	assert_eq(str(r.get("state", "")), "st4te")
	assert_eq(received, ["abc123"])
	assert_string_contains(str(r["_response"]), "HTTP/1.1 200 OK")
	assert_string_contains(str(r["_response"]), "закрыть")
	assert_false(_oauth.is_listening(), "сервер остановлен сразу после кода")
	assert_eq(_oauth.current_redirect_uri(), StravaOAuth.MOBILE_REDIRECT_URI)


func test_loopback_state_mismatch_and_access_denied_are_errors() -> void:
	_oauth.start_loopback_listener(49400, 49450)
	_oauth.authorize_url("expected")
	var failures: Array[String] = []
	_oauth.authorization_failed.connect(func(reason: String) -> void: failures.append(reason))
	var r: Dictionary = await _drive("/callback?state=other&code=abc")
	assert_eq(str(r.get("error", "")), "state_mismatch")
	assert_false(_oauth.is_listening())
	_oauth.start_loopback_listener(49400, 49450)
	var denied: Dictionary = await _drive("/callback?error=access_denied&state=expected")
	assert_eq(str(denied.get("error", "")), "access_denied")
	assert_eq(failures, ["state_mismatch", "access_denied"])


func test_loopback_times_out_after_60s_and_stops() -> void:
	_oauth.start_loopback_listener(49400, 49450)
	assert_eq(_oauth.poll_listener(), {}, "пока ничего")
	_now = NOW + 59
	assert_eq(_oauth.poll_listener(), {})
	_now = NOW + 60
	var r := _oauth.poll_listener()
	assert_eq(str(r.get("error", "")), "timeout", "REQ-STR-01 крит. 7: остановка не позже 60 с")
	assert_false(_oauth.is_listening())
	assert_eq(_oauth.poll_listener(), {}, "после остановки опрос пуст")


func test_parse_redirect_and_mobile_scheme() -> void:
	var p := StravaOAuth.parse_redirect("ovoschrider://strava?code=m0bile&state=s1&scope=read")
	assert_eq(str(p["path"]), "/")
	assert_eq(str(p["query"]["code"]), "m0bile")
	var q := StravaOAuth.parse_redirect("http://127.0.0.1:49400/callback?code=a%20b&state=x#frag")
	assert_eq(str(q["path"]), "/callback")
	assert_eq(str(q["query"]["code"]), "a b", "uri_decode")
	_oauth.authorize_url("s1")
	assert_eq(str(_oauth.handle_redirect_url("ovoschrider://strava?code=m0bile&state=s1")["code"]), "m0bile")
	assert_eq(str(_oauth.handle_redirect_url("ovoschrider://strava?state=s1")["error"]), "bad_request")


# ---------------------------------------------------------------------------
# Обмен кода и хранение (крит. 2; REQ-PRF-03 крит. 1)
# ---------------------------------------------------------------------------

func test_exchange_code_posts_form_and_stores_tokens_per_profile() -> void:
	_mock.enqueue_json("POST", "/oauth/token", 200, _token_payload(ACCESS, REFRESH, NOW + 21600))
	var r: ApiResult = await _oauth.exchange_code("c0de")
	assert_true(r.ok, r.message)
	var req := _mock.last_request()
	assert_eq(str(req["url"]), BASE + "/oauth/token")
	assert_eq(str(req["headers"]["Content-Type"]), "application/x-www-form-urlencoded")
	var form := _form(req["body"])
	assert_eq(str(form["grant_type"]), "authorization_code", "REQ-STR-01 крит. 2")
	assert_eq(str(form["code"]), "c0de")
	assert_eq(str(form["client_id"]), "4242")
	assert_eq(str(form["client_secret"]), "fixture-client-secret-value")
	assert_eq(_store.get_secret("profile-a/strava/access_token"), ACCESS, "REQ-PRF-03 крит. 1: ключ с id профиля")
	assert_eq(_store.get_secret("profile-a/strava/refresh_token"), REFRESH)
	assert_eq(_store.get_secret("profile-a/strava/expires_at"), str(NOW + 21600))
	assert_true(_oauth.is_authorized())
	assert_eq(_oauth.expires_at(), NOW + 21600)
	assert_eq(str(r.data["athlete_id"]), "99001")
	assert_eq(str(r.data["athlete_name"]), "Test Rider")
	var other := _make("profile-b")
	assert_false(other.is_authorized(), "REQ-PRF-03 крит. 1: токены профиля A недоступны профилю B")
	assert_eq(other.access_token(), "")


func test_exchange_code_rejected_stores_nothing() -> void:
	_mock.enqueue_json("POST", "/oauth/token", 400, {"message": "Bad Request", "errors": [{"code": "invalid"}]})
	var r: ApiResult = await _oauth.exchange_code("bad")
	assert_false(r.ok)
	assert_eq(r.code, ApiResult.CODE_AUTH_FAILED)
	assert_false(_oauth.is_authorized())
	assert_eq(_store.size(), 0)
	var empty: ApiResult = await _oauth.exchange_code("  ")
	assert_false(empty.ok)
	assert_eq(_mock.request_count(), 1, "пустой код не отправляется")
	_mock.offline = true
	var off: ApiResult = await _oauth.exchange_code("c")
	assert_eq(off.code, ApiResult.CODE_NETWORK)
	assert_true(off.can_retry)


func test_exchange_code_without_config_is_not_configured() -> void:
	var unconfigured := StravaOAuth.new(_mock, _store, PROFILE, StravaConfig.load("user://nonexistent_fixture.cfg"))
	var r: ApiResult = await unconfigured.exchange_code("c0de")
	assert_eq(r.code, ApiResult.CODE_NOT_CONFIGURED, "REQ-STR-01 крит. 6: понятное поведение без секрета")
	assert_string_contains(r.message, "недоступна")
	assert_eq(_mock.request_count(), 0)


# ---------------------------------------------------------------------------
# Обновление (крит. 3, 4) и отзыв (крит. 8)
# ---------------------------------------------------------------------------

func test_ensure_fresh_token_returns_current_without_request_when_far_from_expiry() -> void:
	_seed_tokens(NOW + 3600)
	var r: ApiResult = await _oauth.ensure_fresh_token()
	assert_true(r.ok)
	assert_eq(str(r.data), ACCESS)
	assert_eq(_mock.request_count(), 0, "обновление не нужно")
	_now = NOW + 3600 - 60
	var edge: ApiResult = await _oauth.ensure_fresh_token()
	assert_eq(str(edge.data), ACCESS, "ровно 60 с до истечения — ещё без обновления")
	assert_eq(_mock.request_count(), 0)


func test_ensure_fresh_token_refreshes_when_less_than_60s_left() -> void:
	_seed_tokens(NOW + 59)
	_mock.enqueue_json("POST", "/oauth/token", 200, _token_payload(NEW_ACCESS, NEW_REFRESH, NOW + 21600))
	var r: ApiResult = await _oauth.ensure_fresh_token()
	assert_true(r.ok, r.message)
	assert_eq(str(r.data), NEW_ACCESS, "REQ-STR-01 крит. 3: новый токен")
	var form := _form(_mock.last_request()["body"])
	assert_eq(str(form["grant_type"]), "refresh_token")
	assert_eq(str(form["refresh_token"]), REFRESH)
	assert_eq(str(form["client_secret"]), "fixture-client-secret-value")
	assert_eq(_oauth.access_token(), NEW_ACCESS, "новые токены перезаписали старые")
	assert_eq(_store.get_secret(_oauth.secret_key(SecureStore.ITEM_REFRESH_TOKEN)), NEW_REFRESH)
	assert_eq(_oauth.expires_at(), NOW + 21600)
	assert_eq(_mock.request_count(), 1)


func test_refresh_rejected_is_reauth_required_and_network_is_retryable() -> void:
	_seed_tokens(NOW - 10)
	_mock.enqueue_json("POST", "/oauth/token", 401, {"message": "Authorization Error"})
	var r: ApiResult = await _oauth.ensure_fresh_token()
	assert_false(r.ok)
	assert_eq(r.code, ApiResult.CODE_REAUTH_REQUIRED, "REQ-STR-01 крит. 4: требуется повторный вход")
	assert_true(_oauth.is_authorized(), "токены остаются до отзыва")
	_mock.offline = true
	var off: ApiResult = await _oauth.ensure_fresh_token()
	assert_eq(off.code, ApiResult.CODE_NETWORK)
	assert_true(off.can_retry)
	var none: ApiResult = await _make("profile-none").ensure_fresh_token()
	assert_eq(none.code, ApiResult.CODE_REAUTH_REQUIRED, "без привязки — вход")
	assert_eq(_mock.request_count(), 2)


func test_force_refresh_ignores_expiry() -> void:
	_seed_tokens(NOW + 36000)
	_mock.enqueue_json("POST", "/oauth/token", 200, _token_payload(NEW_ACCESS, NEW_REFRESH, NOW + 50000))
	var r: ApiResult = await _oauth.ensure_fresh_token(true)
	assert_eq(str(r.data), NEW_ACCESS)
	assert_eq(_mock.request_count(), 1)


func test_revoke_posts_deauthorize_and_deletes_only_this_profiles_strava_tokens() -> void:
	_seed_tokens(NOW + 3600)
	_store.set_secret(SecureStore.key_for(PROFILE, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY), "intervals-fixture-key")
	_store.set_secret(SecureStore.key_for("profile-b", SecureStore.SERVICE_STRAVA, SecureStore.ITEM_REFRESH_TOKEN), "other-fixture")
	_mock.enqueue_json("POST", "/oauth/deauthorize", 200, {"access_token": ACCESS})
	var r: ApiResult = await _oauth.revoke()
	assert_true(r.ok)
	assert_eq(str(_mock.last_request()["url"]), BASE + "/oauth/deauthorize")
	assert_eq(str(_form(_mock.last_request()["body"])["access_token"]), ACCESS)
	assert_false(_oauth.is_authorized(), "REQ-STR-01 крит. 8: токены удалены")
	assert_eq(_oauth.access_token(), "")
	assert_eq(_oauth.expires_at(), 0)
	assert_true(_store.has_secret(SecureStore.key_for(PROFILE, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY)), "REQ-PRF-03 крит. 2: Intervals цел")
	assert_true(_store.has_secret(SecureStore.key_for("profile-b", SecureStore.SERVICE_STRAVA, SecureStore.ITEM_REFRESH_TOKEN)), "другой профиль цел")


func test_revoke_offline_still_clears_local_tokens() -> void:
	_seed_tokens(NOW + 3600)
	_mock.offline = true
	var r: ApiResult = await _oauth.revoke()
	assert_false(r.ok, "сеть недоступна — об этом сообщается")
	assert_eq(r.code, ApiResult.CODE_NETWORK)
	assert_false(_oauth.is_authorized(), "локально привязка снята всегда")
	var again: ApiResult = await _oauth.revoke()
	assert_true(again.ok, "без токенов — нечего отзывать")
	assert_eq(_mock.request_count(), 1)


func test_tokens_and_secret_never_appear_in_messages_or_to_string() -> void:
	_seed_tokens(NOW - 1)
	_mock.enqueue_json("POST", "/oauth/token", 500, {})
	var r: ApiResult = await _oauth.ensure_fresh_token()
	for text in [r.message, str(_oauth), str(_cfg)]:
		for secret in [ACCESS, REFRESH, "fixture-client-secret-value"]:
			assert_false(text.contains(secret), "REQ-STR-01 крит. 5 / REQ-NFR-05: '%s' без секрета" % text)
	assert_string_contains(str(_oauth), "***")
	var headers := StravaOAuth.bearer_headers("tok", {"X": "1"})
	assert_eq(str(headers["Authorization"]), "Bearer tok")
	assert_eq(str(headers["X"]), "1")
