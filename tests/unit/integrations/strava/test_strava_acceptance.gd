extends GutTest
## Независимая приёмка Strava (коммит ce85da4): `StravaConfig`, `StravaOAuth`, `StravaUploader`,
## `UploadResult`, `UploadQueue`, `MemoryUploadStatusStore`, `StravaBranding`.
## Критерии: REQ-STR-01 к1–8 (`[авто]`); REQ-STR-02 к1–4; REQ-STR-03 к1–3; REQ-STR-04 к1–6;
## REQ-STR-05 к1–3 (к2 — только контракт словаря статусов, адаптер к `RideRepository` — T-049);
## REQ-PRF-03 к1–2; REQ-NFR-05 к1–2; REQ-NFR-03 к3.
## Не принимаются здесь (T-049): `strava_service.gd`, `ride_repository_upload_store.gd` — автопостановка
## заезда в очередь (STR-04 к1, первая часть), запись статуса в метаданные заезда (STR-05 к2),
## действие в карточке истории (STR-04 к5, UI), локализованный шаблон названия (STR-03 к1, UI).
## В тестах только фиктивные значения (не похожие на реальные секреты); `check_secrets.sh` сканирует
## `src`/`tests/fixtures`, но и здесь реальных ключей нет.

const A: String = "profile-a"
const B: String = "profile-b"
const BASE: String = "https://mock.strava.test"
const API: String = BASE + "/api/v3"
const CLIENT_ID: String = "4242"
const CLIENT_SECRET_VALUE: String = "fixture-client-secret-value-acc"
const ACCESS_A: String = "fixture-access-token-A-acc"
const REFRESH_A: String = "fixture-refresh-token-A-acc"
const ACCESS_B: String = "fixture-access-token-B-acc"
const REFRESH_B: String = "fixture-refresh-token-B-acc"
const NOW: int = 1_800_000_000
const PORT_FROM: int = 49500
const PORT_TO: int = 49550
var FIT: PackedByteArray = PackedByteArray([0x0E, 0x10, 0x5A, 0x08, 0x2E, 0x46, 0x49, 0x54, 0xDE, 0xAD, 0xBE, 0xEF, 0x0D, 0x0A, 0x2D, 0x2D])

var _dir: String
var _mock: MockHttpTransport
var _store: MemorySecureStore
var _config: StravaConfig
var _oauth: StravaOAuth
var _uploader: StravaUploader
var _status: MemoryUploadStatusStore
var _queue: UploadQueue
var _now: int = NOW
var _waits: Array[float] = []
var _code_signals: Array[String] = []
var _fail_signals: Array[String] = []


func before_each() -> void:
	_dir = "user://test_strava_acc_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_now = NOW
	_waits = []
	_code_signals = []
	_fail_signals = []
	_mock = MockHttpTransport.new()
	_store = MemorySecureStore.new()
	_config = StravaConfig.from_values(CLIENT_ID, CLIENT_SECRET_VALUE)
	_oauth = _make_oauth(A)
	_uploader = StravaUploader.new(_mock, _oauth)
	_uploader.api_base = API
	_uploader.wait_fn = func(sec: float) -> void: _waits.append(sec)
	_status = MemoryUploadStatusStore.new()
	_queue = _make_queue()


func after_each() -> void:
	if _oauth != null:
		_oauth.stop_listener()
	var abs := ProjectSettings.globalize_path(_dir)
	if DirAccess.dir_exists_absolute(abs):
		var d := DirAccess.open(abs)
		for f in d.get_files():
			DirAccess.remove_absolute(abs.path_join(f))
		DirAccess.remove_absolute(abs)


func _make_oauth(profile_id: String) -> StravaOAuth:
	var o := StravaOAuth.new(_mock, _store, profile_id, _config)
	o.base_url = BASE
	o.clock_fn = func() -> int: return _now
	o.authorization_code_received.connect(func(c: String) -> void: _code_signals.append(c))
	o.authorization_failed.connect(func(r: String) -> void: _fail_signals.append(r))
	return o


func _make_queue() -> UploadQueue:
	var q := UploadQueue.new(_uploader, _status, func() -> int: return _now, A, _dir)
	q.fit_provider = func(_ride_id: String) -> PackedByteArray: return FIT
	return q


func _seed_tokens(oauth: StravaOAuth, access: String, refresh: String, expires_at: int) -> void:
	_store.set_secret(oauth.secret_key(SecureStore.ITEM_ACCESS_TOKEN), access)
	_store.set_secret(oauth.secret_key(SecureStore.ITEM_REFRESH_TOKEN), refresh)
	_store.set_secret(oauth.secret_key(SecureStore.ITEM_EXPIRES_AT), str(expires_at))


func _token_payload(access: String, refresh: String, expires_at: int, athlete: Dictionary = {}) -> Dictionary:
	var p := {"token_type": "Bearer", "access_token": access, "refresh_token": refresh, "expires_at": expires_at,
		"expires_in": expires_at - NOW, "scope": "read,activity:write"}
	if not athlete.is_empty():
		p["athlete"] = athlete
	return p


## Тело application/x-www-form-urlencoded → словарь.
static func _form(body: PackedByteArray) -> Dictionary:
	var out := {}
	for pair in body.get_string_from_utf8().split("&", false):
		var eq := pair.find("=")
		out[pair.substr(0, eq).uri_decode()] = pair.substr(eq + 1).uri_decode()
	return out


## Параметры запроса URL → словарь.
static func _query(url: String) -> Dictionary:
	var out := {}
	var q := url.find("?")
	if q == -1:
		return out
	for pair in url.substr(q + 1).split("&", false):
		var eq := pair.find("=")
		out[pair.substr(0, eq).uri_decode()] = pair.substr(eq + 1).uri_decode()
	return out


## Независимый разбор multipart/form-data: `boundary` из Content-Type; части →
## `[{name, filename, content_type, body: PackedByteArray}]`.
static func _parse_multipart(body: PackedByteArray, content_type: String) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var marker := "boundary="
	var idx := content_type.find(marker)
	if idx == -1:
		return parts
	var boundary := content_type.substr(idx + marker.length()).strip_edges()
	var delim := ("\r\n--" + boundary).to_utf8_buffer()
	var first := ("--" + boundary).to_utf8_buffer()
	if body.slice(0, first.size()) != first:
		return parts
	var pos := first.size()
	while true:
		# После разделителя: "\r\n" (ещё часть) или "--" (конец).
		if body.slice(pos, pos + 2) == "--".to_utf8_buffer():
			break
		if body.slice(pos, pos + 2) != "\r\n".to_utf8_buffer():
			break
		pos += 2
		var header_end := _find_bytes(body, "\r\n\r\n".to_utf8_buffer(), pos)
		if header_end == -1:
			break
		var headers := body.slice(pos, header_end).get_string_from_utf8()
		var body_start := header_end + 4
		var next := _find_bytes(body, delim, body_start)
		if next == -1:
			break
		var part := {"name": "", "filename": "", "content_type": "", "body": body.slice(body_start, next), "headers": headers}
		var re_name := RegEx.create_from_string("name=\"([^\"]*)\"")
		var re_file := RegEx.create_from_string("filename=\"([^\"]*)\"")
		var re_ct := RegEx.create_from_string("Content-Type:\\s*([^\\r\\n]+)")
		var m := re_name.search(headers)
		if m != null:
			part["name"] = m.get_string(1)
		m = re_file.search(headers)
		if m != null:
			part["filename"] = m.get_string(1)
		m = re_ct.search(headers)
		if m != null:
			part["content_type"] = m.get_string(1).strip_edges()
		parts.append(part)
		pos = next + delim.size()
	return parts


static func _find_bytes(hay: PackedByteArray, needle: PackedByteArray, from: int) -> int:
	var n := needle.size()
	var i := from
	while i + n <= hay.size():
		if hay.slice(i, i + n) == needle:
			return i
		i += 1
	return -1


static func _part(parts: Array[Dictionary], name: String) -> Dictionary:
	for p in parts:
		if p["name"] == name:
			return p
	return {}


static func _text(parts: Array[Dictionary], name: String) -> String:
	var p := _part(parts, name)
	return (p["body"] as PackedByteArray).get_string_from_utf8() if not p.is_empty() else ""


# ---------------------------------------------------------------------------
# Loopback-клиент для приёма redirect
# ---------------------------------------------------------------------------

func _connect_client(port: int) -> StreamPeerTCP:
	var client := StreamPeerTCP.new()
	assert_eq(client.connect_to_host("127.0.0.1", port), OK)
	for i in 300:
		client.poll()
		if client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
		await get_tree().process_frame
	assert_eq(client.get_status(), StreamPeerTCP.STATUS_CONNECTED, "клиент подключился к loopback-серверу")
	return client


## Отправить запрос на слушатель, крутить poll_listener до результата, собрать HTTP-ответ.
func _drive(request_line: String) -> Dictionary:
	var client: StreamPeerTCP = await _connect_client(_oauth.listener_port())
	client.put_data((request_line + "\r\nHost: 127.0.0.1\r\nUser-Agent: acceptance\r\nAccept: text/html\r\n\r\n").to_utf8_buffer())
	var result := {}
	for i in 300:
		result = _oauth.poll_listener()
		if not result.is_empty():
			break
		await get_tree().process_frame
	var response := ""
	for i in 100:
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


## Транспорт, который «висит» на запросе до `release` — для проверки одновременности (REQ-STR-04 крит. 4).
class BlockingTransport:
	extends HttpTransport
	signal release
	var inner: MockHttpTransport
	var in_flight: int = 0
	var max_in_flight: int = 0

	func _init(wrapped: MockHttpTransport) -> void:
		inner = wrapped

	func request(method: String, url: String, headers: Dictionary,
			body: PackedByteArray = PackedByteArray(), timeout_sec: float = DEFAULT_TIMEOUT_SEC) -> HttpResponse:
		in_flight += 1
		max_in_flight = maxi(max_in_flight, in_flight)
		await release
		in_flight -= 1
		return inner.request(method, url, headers, body, timeout_sec)


## Все `.gd` под каталогом (рекурсивно), пути `res://…`.
static func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				out.append_array(_gd_files(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


## Строки кода файла без комментариев (строка целиком — комментарий → пропуск; хвостовой `#` отрезан грубо).
static func _code_lines(path: String) -> Array[String]:
	var out: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var t: String = line.strip_edges()
		if t.is_empty() or t.begins_with("#"):
			continue
		out.append(line)
	return out


## Минимальный заезд с сэмплами для `FitEncoder.encode` (REQ-STR-02 крит. 2).
func _ride_with_samples(n: int) -> Ride:
	var s := SampleStream.new()
	s.speed_source = Ride.SPEED_SOURCE_TRAINER_LEGACY
	for i in n:
		var smp := TrainerSample.new()
		smp.has_power = true
		smp.power_w = 200 + i
		smp.has_cadence = true
		smp.cadence_rpm = 90
		smp.has_speed = true
		smp.speed_kmh = 30.0
		s.append(i, smp, 140 + i, 200, 0, true)
	var ride := Ride.new()
	ride.id = Ride.generate_id(NOW - 3600)
	ride.profile_id = A
	ride.started_at_unix = NOW - 3600
	ride.name = "Threshold 3x5"
	ride.workout = {"name": "Threshold 3x5", "source": "zwo", "steps": []}
	ride.events = [{"type": "start", "at_sec": 0.0, "value": 0}]
	ride.metadata = {"ftp_w": 250, "weight_kg": 70.0, "max_hr": 185, "intensity": 1.0, "stopped_early": false,
		"paused_total_sec": 0.0, "speed_source": s.speed_source, "in_progress": false, "recovered": false}
	ride.samples = s
	ride.compute_summary()
	return ride


# ===========================================================================
# REQ-STR-01 — OAuth 2.0 и токены
# ===========================================================================

func test_req_str_01_c1_authorize_url_has_client_id_redirect_response_type_scope_and_state() -> void:
	var url := _oauth.authorize_url("st-acc-1", "http://127.0.0.1:49999/callback")
	assert_true(url.begins_with(BASE + "/oauth/authorize?"), url)
	var q := _query(url)
	assert_eq(q["client_id"], CLIENT_ID)
	assert_eq(q["redirect_uri"], "http://127.0.0.1:49999/callback")
	assert_eq(q["response_type"], "code")
	assert_eq(q["scope"], "activity:write,read", "scope содержит activity:write")
	assert_true(str(q["scope"]).contains("activity:write"))
	assert_eq(q["state"], "st-acc-1")
	assert_eq(_oauth.expected_state, "st-acc-1")
	assert_false(url.contains(CLIENT_SECRET_VALUE), "секрет в URL авторизации не передаётся")
	# Пустой state генерируется (непустой, случайный), redirect по умолчанию — мобильная схема.
	var url2 := _oauth.authorize_url()
	var q2 := _query(url2)
	assert_false(str(q2["state"]).is_empty())
	assert_true(str(q2["state"]).length() >= 16)
	assert_eq(q2["redirect_uri"], StravaOAuth.MOBILE_REDIRECT_URI)
	assert_ne(_query(_oauth.authorize_url())["state"], q2["state"], "state каждый раз новый")


func test_req_str_01_c7_loopback_listener_accepts_code_responds_close_page_and_stops() -> void:
	var uri := _oauth.start_loopback_listener(PORT_FROM, PORT_TO)
	assert_true(_oauth.is_listening())
	var port := _oauth.listener_port()
	assert_true(port >= PORT_FROM and port <= PORT_TO, "порт из диапазона: %d" % port)
	assert_eq(uri, "http://127.0.0.1:%d/callback" % port, "redirect_uri = фактический порт")
	var url := _oauth.authorize_url("state-ok")
	assert_eq(_query(url)["redirect_uri"], uri, "URL авторизации использует loopback с тем же портом")
	var r: Dictionary = await _drive("GET /callback?state=state-ok&code=code-xyz&scope=read%2Cactivity%3Awrite HTTP/1.1")
	assert_eq(str(r.get("code", "")), "code-xyz", "код принят: %s" % str(r))
	assert_eq(str(r.get("state", "")), "state-ok")
	assert_false(r.has("error"))
	assert_eq(_code_signals, ["code-xyz"] as Array[String], "сигнал authorization_code_received")
	assert_eq(_fail_signals.size(), 0)
	var response: String = r["_response"]
	assert_true(response.begins_with("HTTP/1.1 200 OK"), "HTTP 200: %s" % response.substr(0, 40))
	assert_string_contains(response.to_lower(), "content-type: text/html")
	assert_string_contains(response, "закрыть")
	assert_string_contains(response, "</html>")
	assert_false(_oauth.is_listening(), "сервер остановлен сразу после кода")
	assert_eq(_oauth.listener_port(), 0)
	assert_eq(_oauth.poll_listener(), {}, "после остановки опрос пуст")
	assert_eq(_oauth.current_redirect_uri(), StravaOAuth.MOBILE_REDIRECT_URI)
	# Порт освобождён — повторный запуск на том же диапазоне возможен.
	var uri2 := _oauth.start_loopback_listener(PORT_FROM, PORT_TO)
	assert_false(uri2.is_empty())
	_oauth.stop_listener()


func test_req_str_01_c7_loopback_rejects_wrong_state_and_access_denied_and_times_out() -> void:
	_oauth.start_loopback_listener(PORT_FROM, PORT_TO)
	_oauth.authorize_url("expected-state")
	var bad: Dictionary = await _drive("GET /callback?state=forged&code=code-xyz HTTP/1.1")
	assert_eq(str(bad.get("error", "")), "state_mismatch", "неверный state → отказ")
	assert_false(bad.has("code"))
	assert_eq(_code_signals.size(), 0, "код с чужим state не принят")
	assert_eq(_fail_signals, ["state_mismatch"] as Array[String])
	assert_false(_oauth.is_listening())
	# Пользователь отказал.
	_oauth.start_loopback_listener(PORT_FROM, PORT_TO)
	_oauth.authorize_url("expected-state")
	var denied: Dictionary = await _drive("GET /callback?error=access_denied&state=expected-state HTTP/1.1")
	assert_eq(str(denied.get("error", "")), "access_denied")
	assert_eq(_fail_signals.back(), "access_denied")
	assert_false(_oauth.is_listening())
	# Без кода — bad_request.
	_oauth.start_loopback_listener(PORT_FROM, PORT_TO)
	var nocode: Dictionary = await _drive("GET /callback?state=expected-state HTTP/1.1")
	assert_eq(str(nocode.get("error", "")), "bad_request")
	assert_false(_oauth.is_listening())
	# Таймаут 60 с по подменяемым часам.
	_oauth.start_loopback_listener(PORT_FROM, PORT_TO)
	_now += 59
	assert_eq(_oauth.poll_listener(), {}, "59 с — ещё ждём")
	assert_true(_oauth.is_listening())
	_now += 1
	var t := _oauth.poll_listener()
	assert_eq(str(t.get("error", "")), "timeout", "ровно 60 с → остановка")
	assert_false(_oauth.is_listening())
	assert_eq(_fail_signals.back(), "timeout")
	assert_eq(_code_signals.size(), 0)


func test_req_str_01_c7_mobile_scheme_and_parse_redirect() -> void:
	_oauth.authorize_url("m-state")
	var r := _oauth.handle_redirect_url("ovoschrider://strava?state=m-state&code=mob-code")
	assert_eq(r.get("code", ""), "mob-code")
	assert_eq(_code_signals, ["mob-code"] as Array[String])
	var p := StravaOAuth.parse_redirect("http://127.0.0.1:49500/callback?code=a%20b&state=s#frag")
	assert_eq(p["path"], "/callback")
	assert_eq(p["query"]["code"], "a b", "uri-decode")
	assert_eq(p["query"]["state"], "s")
	var bad := _oauth.handle_redirect_url("ovoschrider://strava?state=other&code=x")
	assert_eq(bad.get("error", ""), "state_mismatch")
	var denied := _oauth.handle_redirect_url("ovoschrider://strava?error=access_denied")
	assert_eq(denied.get("error", ""), "access_denied")


func test_req_str_01_c2_exchange_code_posts_form_and_stores_tokens_per_profile() -> void:
	_mock.enqueue_json("POST", "/oauth/token", 200,
		_token_payload(ACCESS_A, REFRESH_A, NOW + 21600, {"id": 777001, "firstname": "Acc", "lastname": "Rider"}))
	var r: ApiResult = await _oauth.exchange_code(" code-xyz ")
	assert_true(r.ok, r.message)
	var req := _mock.last_request()
	assert_eq(req["method"], "POST")
	assert_eq(req["url"], BASE + "/oauth/token")
	assert_eq(str(req["headers"]["Content-Type"]), "application/x-www-form-urlencoded")
	var form := _form(req["body"])
	assert_eq(form["grant_type"], "authorization_code")
	assert_eq(form["code"], "code-xyz", "код без пробелов")
	assert_eq(form["client_id"], CLIENT_ID)
	assert_eq(form["client_secret"], CLIENT_SECRET_VALUE, "секрет уходит только в тело запроса к Strava")
	assert_false(req["headers"].has("Authorization"), "обмен кода — без Bearer")
	# Токены — в SecureStore профиля A под ключами с id профиля.
	assert_eq(_store.get_secret("profile-a/strava/access_token"), ACCESS_A)
	assert_eq(_store.get_secret("profile-a/strava/refresh_token"), REFRESH_A)
	assert_eq(_store.get_secret("profile-a/strava/expires_at"), str(NOW + 21600))
	assert_eq(_oauth.expires_at(), NOW + 21600)
	assert_true(_oauth.is_authorized())
	assert_eq(_store.list_keys("profile-b/"), [] as Array[String], "у профиля B ничего нет")
	assert_eq(r.data["athlete_id"], "777001")
	assert_eq(r.data["athlete_name"], "Acc Rider")
	assert_eq(r.data["expires_at"], NOW + 21600)
	assert_string_contains(str(r.data["scope"]), "activity:write")
	# Профиль B — свои токены, A не затронут.
	var oauth_b := _make_oauth(B)
	_mock.enqueue_json("POST", "/oauth/token", 200, _token_payload(ACCESS_B, REFRESH_B, NOW + 100))
	var rb: ApiResult = await oauth_b.exchange_code("code-b")
	assert_true(rb.ok)
	assert_eq(_store.get_secret("profile-b/strava/access_token"), ACCESS_B)
	assert_eq(_store.get_secret("profile-a/strava/access_token"), ACCESS_A)
	assert_eq(_store.size(), 6)


func test_req_str_01_c2_edge_exchange_code_400_and_malformed_store_nothing() -> void:
	_mock.enqueue_json("POST", "/oauth/token", 400, {"message": "Bad Request", "errors": [{"code": "invalid"}]})
	var r: ApiResult = await _oauth.exchange_code("stale-code")
	assert_false(r.ok)
	assert_eq(r.code, ApiResult.CODE_AUTH_FAILED, "400 на обмен — код не принят")
	assert_string_contains(r.message, "не приняла")
	assert_false(_oauth.is_authorized(), "токены не сохранены")
	assert_eq(_store.size(), 0)
	_mock.enqueue_json("POST", "/oauth/token", 401, {"message": "Unauthorized"})
	var r401: ApiResult = await _oauth.exchange_code("x")
	assert_eq(r401.code, ApiResult.CODE_AUTH_FAILED)
	_mock.enqueue_json("POST", "/oauth/token", 200, {"token_type": "Bearer"})
	var r_no: ApiResult = await _oauth.exchange_code("x")
	assert_eq(r_no.code, ApiResult.CODE_BAD_RESPONSE, "ответ без токенов")
	assert_false(_oauth.is_authorized())
	_mock.enqueue("POST", "/oauth/token", HttpResponse.make(200, "<html>"))
	var r_html: ApiResult = await _oauth.exchange_code("x")
	assert_eq(r_html.code, ApiResult.CODE_BAD_RESPONSE)
	_mock.offline = true
	var r_off: ApiResult = await _oauth.exchange_code("x")
	assert_eq(r_off.code, ApiResult.CODE_NETWORK)
	assert_true(r_off.can_retry)
	_mock.offline = false
	var n := _mock.requests.size()
	var empty: ApiResult = await _oauth.exchange_code("   ")
	assert_false(empty.ok)
	assert_eq(_mock.requests.size(), n, "пустой код — без запроса")
	assert_eq(_store.size(), 0)


func test_req_str_01_c3_refresh_when_less_than_60s_left_and_exact_boundary() -> void:
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 60)
	var exact: ApiResult = await _oauth.ensure_fresh_token()
	assert_true(exact.ok)
	assert_eq(str(exact.data), ACCESS_A, "ровно 60 с до истечения — обновление не нужно")
	assert_eq(_mock.requests.size(), 0, "без запроса")
	_now += 1  # осталось 59 с
	_mock.enqueue_json("POST", "/oauth/token", 200, _token_payload("fixture-access-token-A2", "fixture-refresh-token-A2", _now + 21600))
	var refreshed: ApiResult = await _oauth.ensure_fresh_token()
	assert_true(refreshed.ok)
	assert_eq(str(refreshed.data), "fixture-access-token-A2", "новый access_token")
	var form := _form(_mock.last_request()["body"])
	assert_eq(form["grant_type"], "refresh_token")
	assert_eq(form["refresh_token"], REFRESH_A, "обновление по прежнему refresh_token")
	assert_eq(form["client_id"], CLIENT_ID)
	assert_eq(form["client_secret"], CLIENT_SECRET_VALUE)
	assert_eq(_store.get_secret(_oauth.secret_key(SecureStore.ITEM_ACCESS_TOKEN)), "fixture-access-token-A2", "новые токены перезаписали старые")
	assert_eq(_store.get_secret(_oauth.secret_key(SecureStore.ITEM_REFRESH_TOKEN)), "fixture-refresh-token-A2")
	assert_eq(_oauth.expires_at(), _now + 21600)
	assert_eq(_mock.requests.size(), 1)
	# Далеко до истечения — без запросов; уже истёк — обновление.
	var fresh: ApiResult = await _oauth.ensure_fresh_token()
	assert_eq(_mock.requests.size(), 1)
	assert_eq(str(fresh.data), "fixture-access-token-A2")
	_now += 30000
	_mock.enqueue_json("POST", "/oauth/token", 200, _token_payload("fixture-access-token-A3", "fixture-refresh-token-A3", _now + 21600))
	var expired: ApiResult = await _oauth.ensure_fresh_token()
	assert_eq(str(expired.data), "fixture-access-token-A3", "просроченный токен обновлён")
	# Принудительно — тоже обновление.
	_mock.enqueue_json("POST", "/oauth/token", 200, _token_payload("fixture-access-token-A4", "fixture-refresh-token-A4", _now + 21600))
	var forced: ApiResult = await _oauth.ensure_fresh_token(true)
	assert_eq(str(forced.data), "fixture-access-token-A4")


func test_req_str_01_c3_c4_refresh_401_is_reauth_required_and_without_refresh_token_no_request() -> void:
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 10)
	_mock.enqueue_json("POST", "/oauth/token", 401, {"message": "Unauthorized"})
	var r: ApiResult = await _oauth.ensure_fresh_token()
	assert_false(r.ok)
	assert_eq(r.code, ApiResult.CODE_REAUTH_REQUIRED, "401 на refresh → требуется повторный вход")
	assert_false(r.can_retry)
	assert_string_contains(r.message, "повторный вход")
	assert_true(_oauth.is_authorized(), "токены не стираются сами — до отзыва/повторного входа")
	_mock.enqueue_json("POST", "/oauth/token", 400, {"message": "Bad Request"})
	var r400: ApiResult = await _oauth.ensure_fresh_token()
	assert_eq(r400.code, ApiResult.CODE_REAUTH_REQUIRED, "400 (отозванный refresh_token) → повторный вход")
	_mock.enqueue_json("POST", "/oauth/token", 503, {})
	var r503: ApiResult = await _oauth.ensure_fresh_token()
	assert_eq(r503.code, ApiResult.CODE_NETWORK)
	assert_true(r503.can_retry, "5xx при обновлении — временная ошибка")
	_mock.enqueue_json("POST", "/oauth/token", 429, {}, {"Retry-After": "11"})
	var r429: ApiResult = await _oauth.ensure_fresh_token()
	assert_eq(r429.code, ApiResult.CODE_RATE_LIMITED)
	assert_eq(r429.retry_after_sec, 11)
	# Без refresh_token (нет привязки) — без запроса.
	_store.delete_service_secrets(A, SecureStore.SERVICE_STRAVA)
	var n := _mock.requests.size()
	var none: ApiResult = await _oauth.ensure_fresh_token()
	assert_eq(none.code, ApiResult.CODE_REAUTH_REQUIRED)
	assert_eq(_mock.requests.size(), n, "нет привязки — запросов нет")
	var direct: ApiResult = await _oauth.refresh_token()
	assert_eq(direct.code, ApiResult.CODE_REAUTH_REQUIRED)
	assert_eq(_mock.requests.size(), n)
	# Только access_token без refresh_token — тоже «не привязано».
	_store.set_secret(_oauth.secret_key(SecureStore.ITEM_ACCESS_TOKEN), ACCESS_A)
	assert_false(_oauth.is_authorized())
	var only_access: ApiResult = await _oauth.ensure_fresh_token()
	assert_eq(only_access.code, ApiResult.CODE_REAUTH_REQUIRED)
	assert_eq(_mock.requests.size(), n)


func test_req_str_01_c8_revoke_calls_deauthorize_and_deletes_only_this_profiles_strava_tokens() -> void:
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 1000)
	var oauth_b := _make_oauth(B)
	_seed_tokens(oauth_b, ACCESS_B, REFRESH_B, NOW + 1000)
	_store.set_secret(SecureStore.key_for(A, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY), "fixture-intervals-key-A")
	assert_eq(_store.size(), 7)
	_mock.enqueue_json("POST", "/oauth/deauthorize", 200, {"access_token": ACCESS_A})
	var r: ApiResult = await _oauth.revoke()
	assert_true(r.ok)
	var req := _mock.last_request()
	assert_eq(req["method"], "POST")
	assert_eq(req["url"], BASE + "/oauth/deauthorize")
	assert_eq(_form(req["body"])["access_token"], ACCESS_A, "отзывается текущий access_token")
	assert_false(_oauth.is_authorized(), "привязка снята")
	assert_eq(_store.list_keys("profile-a/strava/"), [] as Array[String], "все токены Strava профиля A удалены")
	assert_true(oauth_b.is_authorized(), "профиль B не тронут")
	assert_eq(_store.get_secret("profile-b/strava/access_token"), ACCESS_B)
	assert_eq(_store.get_secret(SecureStore.key_for(A, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY)), "fixture-intervals-key-A", "Intervals A не тронут (PRF-03 крит. 2)")
	assert_eq(_store.size(), 4)
	# Отзыв без сети — локально привязка всё равно снимается.
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 1000)
	_mock.offline = true
	var off: ApiResult = await _oauth.revoke()
	assert_false(_oauth.is_authorized(), "токены удалены даже при недоступной сети")
	assert_eq(off.code, ApiResult.CODE_NETWORK, "но пользователь узнаёт, что Strava не уведомлена")
	_mock.offline = false
	# Отзыв без токенов — без запроса, успех.
	var n := _mock.requests.size()
	var none: ApiResult = await _oauth.revoke()
	assert_true(none.ok)
	assert_eq(_mock.requests.size(), n)


func test_req_str_01_c5_secret_and_tokens_never_in_strings_or_messages() -> void:
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 10)
	assert_false(str(_config).contains(CLIENT_SECRET_VALUE), "str(config) маскирует секрет")
	assert_true(str(_config).contains("***"))
	assert_string_contains(str(_config), CLIENT_ID)
	var s := str(_oauth)
	assert_false(s.contains(ACCESS_A) or s.contains(REFRESH_A) or s.contains(CLIENT_SECRET_VALUE), "str(oauth) без токенов и секрета")
	var messages: Array[String] = []
	_mock.enqueue_json("POST", "/oauth/token", 401, {"message": "Unauthorized"})
	messages.append((await _oauth.ensure_fresh_token()).message)
	_mock.enqueue_json("POST", "/oauth/token", 500, {})
	messages.append((await _oauth.ensure_fresh_token()).message)
	_mock.enqueue("POST", "/oauth/token", HttpResponse.make(200, "garbage"))
	messages.append((await _oauth.ensure_fresh_token()).message)
	_mock.offline = true
	messages.append((await _oauth.ensure_fresh_token()).message)
	messages.append((await _oauth.revoke()).message)
	_mock.offline = false
	_mock.enqueue_json("POST", "/oauth/token", 400, {"message": "bad"})
	messages.append((await _oauth.exchange_code("c")).message)
	messages.append(StravaConfig.from_values("", "").unavailable_message())
	for m in messages:
		assert_false(m.contains(ACCESS_A) or m.contains(REFRESH_A) or m.contains(CLIENT_SECRET_VALUE), "сообщение без секретов: «%s»" % m)
	# Выгрузка: сообщения результата тоже без секретов.
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 99999)
	_mock.enqueue_json("POST", "/uploads", 401, {"message": "Authorization Error"})
	_mock.enqueue_json("POST", "/oauth/token", 401, {"message": "Unauthorized"})
	var up: UploadResult = await _uploader.upload_fit(FIT, "n", "d", "ride-1")
	assert_false(up.error.contains(ACCESS_A) or up.error.contains(REFRESH_A) or up.error.contains(CLIENT_SECRET_VALUE))
	assert_false(str(up).contains(ACCESS_A))


func test_req_str_01_c6_config_sources_priority_placeholders_and_unavailable_message() -> void:
	# Файл имеет приоритет над окружением.
	var cfg_path := _dir + "secrets.cfg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	var cfg := ConfigFile.new()
	cfg.set_value("strava", "client_id", "1111")
	cfg.set_value("strava", "client_secret", "fixture-secret-from-file")
	assert_eq(cfg.save(cfg_path), OK)
	var env := {StravaConfig.ENV_CLIENT_ID: "2222", StravaConfig.ENV_CLIENT_SECRET: "fixture-secret-from-env"}
	var lookup := func(name: String) -> String: return str(env.get(name, ""))
	var from_file := StravaConfig.load(cfg_path, lookup)
	assert_true(from_file.is_configured())
	assert_eq(from_file.source, StravaConfig.SOURCE_CONFIG_FILE)
	assert_eq(from_file.client_id, "1111")
	assert_eq(from_file.client_secret(), "fixture-secret-from-file")
	# Нет файла → окружение.
	var from_env := StravaConfig.load(_dir + "missing.cfg", lookup)
	assert_true(from_env.is_configured())
	assert_eq(from_env.source, StravaConfig.SOURCE_ENVIRONMENT)
	assert_eq(from_env.client_id, "2222")
	# Файл с плейсхолдерами из примера — игнорируется, берётся окружение.
	var example := StravaConfig.load("res://secrets.example.cfg.txt", lookup)
	assert_eq(example.source, StravaConfig.SOURCE_ENVIRONMENT, "плейсхолдеры примера не считаются настройкой")
	var example_only := StravaConfig.load("res://secrets.example.cfg.txt")
	assert_false(example_only.is_configured(), "только пример → не настроено")
	assert_eq(example_only.source, StravaConfig.SOURCE_NONE)
	# Частично заполненный файл (только id) — не настроено, падения нет.
	var half := ConfigFile.new()
	half.set_value("strava", "client_id", "3333")
	half.save(_dir + "half.cfg")
	var from_half := StravaConfig.load(_dir + "half.cfg")
	assert_false(from_half.is_configured())
	# Нет ни одного источника (без окружения и без настроек проекта) — понятное сообщение, не падает.
	var none := StravaConfig.load(_dir + "missing.cfg", func(_n: String) -> String: return "")
	assert_false(none.is_configured())
	assert_eq(none.source, StravaConfig.SOURCE_NONE)
	assert_string_contains(none.unavailable_message(), "недоступна")
	assert_string_contains(none.unavailable_message(), StravaConfig.ENV_CLIENT_ID)
	assert_eq(none.client_secret(), "")
	# Без секрета: exchange/refresh не ходят в сеть и отвечают понятным кодом.
	var oauth_none := StravaOAuth.new(_mock, _store, A, none)
	oauth_none.base_url = BASE
	var r: ApiResult = await oauth_none.exchange_code("code")
	assert_eq(r.code, ApiResult.CODE_NOT_CONFIGURED)
	assert_string_contains(r.message, "недоступна")
	_seed_tokens(oauth_none, ACCESS_A, REFRESH_A, NOW)
	var rr: ApiResult = await oauth_none.refresh_token()
	assert_eq(rr.code, ApiResult.CODE_NOT_CONFIGURED)
	assert_eq(_mock.requests.size(), 0, "без client_secret запросов нет")
	# Плейсхолдеры в значениях из любого источника.
	assert_false(StravaConfig.from_values("YOUR_CLIENT_ID", "fixture").is_configured())
	assert_false(StravaConfig.from_values("1", "<secret>").is_configured() if false else StravaConfig.load(_dir + "missing.cfg",
		func(n: String) -> String: return "<secret>" if n == StravaConfig.ENV_CLIENT_SECRET else "1").is_configured())
	# В репозитории — только пример с плейсхолдерами (REQ-STR-01 крит. 5 / INF-03.5).
	var example_text := FileAccess.get_file_as_string("res://secrets.example.cfg.txt")
	assert_string_contains(example_text, "PLACEHOLDER")
	assert_false(FileAccess.file_exists("res://secrets.cfg"), "реального secrets.cfg в проекте нет")
	assert_false(FileAccess.file_exists("res://user/secrets.cfg"))


func test_req_str_01_c7_loopback_ignores_foreign_path_with_404_and_keeps_waiting() -> void:
	_oauth.start_loopback_listener(PORT_FROM, PORT_TO)
	_oauth.authorize_url("st-404")
	var client: StreamPeerTCP = await _connect_client(_oauth.listener_port())
	client.put_data("GET /favicon.ico HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".to_utf8_buffer())
	var response := ""
	for i in 120:
		_oauth.poll_listener()
		client.poll()
		var n := client.get_available_bytes()
		if n > 0:
			response += client.get_utf8_string(n)
		if response.contains("</html>"):
			break
		await get_tree().process_frame
	assert_true(response.begins_with("HTTP/1.1 404"), "чужой путь → 404: %s" % response.substr(0, 40))
	assert_true(_oauth.is_listening(), "слушатель продолжает ждать callback")
	assert_eq(_code_signals.size(), 0)
	assert_eq(_fail_signals.size(), 0)
	client.disconnect_from_host()
	# Настоящий callback после этого принимается тем же слушателем и останавливает его.
	var r: Dictionary = await _drive("GET /callback?state=st-404&code=after-404 HTTP/1.1")
	assert_eq(str(r.get("code", "")), "after-404", str(r))
	assert_false(_oauth.is_listening(), "один запрос с code — и сервер остановлен")


func test_req_str_01_c4_poll_401_refreshes_once_and_retries_second_401_is_reauth() -> void:
	# Крит. 4: «Ответ 401 на запрос API приводит к одному обновлению токена и повтору запроса;
	# повторный 401 — статус привязки «требуется повторный вход»». Опрос GET /uploads/{id} — запрос API.
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 99999)
	_mock.enqueue_json("GET", "/uploads/90101", 401, {"message": "Authorization Error"})
	_mock.enqueue_json("POST", "/oauth/token", 200, _token_payload("fixture-access-token-A7", "fixture-refresh-token-A7", NOW + 99999))
	_mock.enqueue_json("GET", "/uploads/90101", 200, {"id": 90101, "activity_id": 555101})
	var r: UploadResult = await _uploader.poll_upload("90101")
	assert_eq(r.status, UploadResult.STATUS_DONE, "401 при опросе → обновление токена и повтор опроса: %s" % str(r))
	assert_eq(_mock.request_count("POST", "/oauth/token"), 1, "ровно одно обновление токена")
	assert_eq(_mock.request_count("GET", "/uploads/90101"), 2, "один повтор опроса")
	if _mock.requests.size() >= 3:
		assert_eq(str(_mock.requests[2]["headers"]["Authorization"]), "Bearer fixture-access-token-A7", "повтор — с новым токеном")
	# Повторный 401 → «требуется повторный вход», третьей попытки нет.
	_mock.clear()
	_mock.enqueue_json("GET", "/uploads/90102", 401, {"message": "Authorization Error"}, {}, -1)
	_mock.enqueue_json("POST", "/oauth/token", 200, _token_payload("fixture-access-token-A8", "fixture-refresh-token-A8", NOW + 99999))
	var r2: UploadResult = await _uploader.poll_upload("90102")
	assert_eq(r2.status, UploadResult.STATUS_FAILED)
	assert_eq(r2.code, ApiResult.CODE_REAUTH_REQUIRED, "повторный 401 — требуется повторный вход")
	assert_false(r2.can_retry)
	assert_eq(_mock.request_count("GET", "/uploads/90102"), 2, "ровно один повтор, не max_polls")


func test_req_str_01_c4_poll_after_401_refresh_uses_refreshed_token() -> void:
	# После 401 → обновление → повтор POST; последующие опросы статуса идут с НОВЫМ токеном.
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 99999)
	_mock.enqueue_json("POST", "/uploads", 401, {"message": "Authorization Error"})
	_mock.enqueue_json("POST", "/oauth/token", 200, _token_payload("fixture-access-token-A9", "fixture-refresh-token-A9", NOW + 99999))
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 90103, "activity_id": null, "error": null})
	_mock.enqueue_json("GET", "/uploads/90103", 200, {"id": 90103, "activity_id": 555103})
	var r: UploadResult = await _uploader.upload_fit(FIT, "n", "d", "ride-10")
	assert_eq(r.status, UploadResult.STATUS_DONE, str(r))
	var poll_auth: Array[String] = []
	for req in _mock.requests:
		if req["method"] == "GET":
			poll_auth.append(str(req["headers"]["Authorization"]))
	assert_eq(poll_auth, ["Bearer fixture-access-token-A9"] as Array[String], "опрос — с обновлённым токеном, не со старым %s" % ACCESS_A)
	assert_eq(_store.get_secret(_oauth.secret_key(SecureStore.ITEM_ACCESS_TOKEN)), "fixture-access-token-A9")


func test_req_str_01_c5_strava_sources_do_not_log_secrets_and_src_has_no_secret_literals() -> void:
	# «не логируется»: в коде интеграции нет print/push_* со словами secret/token.
	var log_re := RegEx.create_from_string("(?i)(print|printerr|print_debug|push_error|push_warning)\\(.*(secret|token)")
	for path in _gd_files("res://src/integrations/strava"):
		for line in _code_lines(path):
			assert_null(log_re.search(line), "%s: логирование секрета/токена: «%s»" % [path, line.strip_edges()])
	# «не хранится в репозитории»: шаблоны check_secrets.sh по src/ (код, без плейсхолдеров).
	var secret_re := RegEx.create_from_string("(^|[^A-Za-z0-9_])sk_[A-Za-z0-9_-]{8,}|client_secret\\s*[=:]\\s*\"[^\"]+\"|Bearer [A-Za-z0-9._-]{8,}|api_key\\s*[=:]\\s*\"[^\"]+\"|refresh_token\\s*[=:]\\s*\"[^\"]+\"")
	var allow_re := RegEx.create_from_string("PLACEHOLDER|placeholder|EXAMPLE|example\\.com|<token>|<secret>|<key>|dummy|xxx+|\\.\\.\\.")
	var hits: Array[String] = []
	for path in _gd_files("res://src"):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if secret_re.search(line) != null and allow_re.search(line) == null:
				hits.append("%s: %s" % [path, line.strip_edges()])
	assert_eq(hits, [] as Array[String], "в src/ нет строк, похожих на секреты")
	# Секрет приложения не попадает ни в URL авторизации, ни в заголовки запросов к API.
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 99999)
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 1, "activity_id": 1})
	await _uploader.upload_fit(FIT, "n", "d", "r")
	for req in _mock.requests:
		assert_false(str(req["url"]).contains(CLIENT_SECRET_VALUE), "секрет не в URL")
		assert_false(JSON.stringify(req["headers"]).contains(CLIENT_SECRET_VALUE), "секрет не в заголовках")
		if str(req["url"]).contains("/api/v3/"):
			assert_false((req["body"] as PackedByteArray).get_string_from_utf8().contains(CLIENT_SECRET_VALUE), "секрет не в теле запросов к API")


# ===========================================================================
# REQ-STR-02 / REQ-STR-03 — выгрузка FIT, multipart, название/описание
# ===========================================================================

func test_req_str_02_c1_str_03_c1_c3_multipart_has_fit_data_type_virtual_ride_name_description() -> void:
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 99999)
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 90001, "external_id": "ride-42", "status": "Your activity is still being processed.", "error": null, "activity_id": null})
	_mock.enqueue_json("GET", "/uploads/90001", 200, {"id": 90001, "status": "Your activity is ready.", "error": null, "activity_id": 555001})
	var r: UploadResult = await _uploader.upload_fit(FIT, "Моя тренировка", "Описание плана\n\nЗаписано в ovosch-rider", "ride-42")
	assert_eq(r.status, UploadResult.STATUS_DONE, str(r))
	var req: Dictionary = _mock.requests[0]
	assert_eq(req["method"], "POST")
	assert_eq(req["url"], API + "/uploads")
	assert_eq(str(req["headers"]["Authorization"]), "Bearer " + ACCESS_A)
	var ct := str(req["headers"]["Content-Type"])
	assert_true(ct.begins_with("multipart/form-data; boundary="), ct)
	var parts := _parse_multipart(req["body"], ct)
	assert_gt(parts.size(), 5, "multipart разобран независимо: %d частей" % parts.size())
	assert_eq(_text(parts, "data_type"), "fit", "data_type=fit")
	assert_eq(_text(parts, "external_id"), "ride-42", "external_id = идентификатор заезда")
	assert_eq(_text(parts, "sport_type"), "VirtualRide")
	assert_eq(_text(parts, "activity_type"), "VirtualRide")
	assert_eq(_text(parts, "trainer"), "1")
	assert_eq(_text(parts, "name"), "Моя тренировка", "REQ-STR-03 крит. 1/3: название из аргумента")
	assert_eq(_text(parts, "description"), "Описание плана\n\nЗаписано в ovosch-rider", "REQ-STR-03 крит. 2/3")
	var file := _part(parts, "file")
	assert_false(file.is_empty(), "есть поле file")
	assert_eq(file["body"], FIT, "байты FIT в теле без изменений (включая 0x0D0A и «--»)")
	assert_eq(file["filename"], "ride-42.fit")
	assert_eq(file["content_type"], "application/octet-stream")
	# Границы: тело начинается с --boundary, заканчивается --boundary--CRLF, boundary не встречается внутри FIT.
	var boundary := ct.substr(ct.find("boundary=") + 9)
	var body: PackedByteArray = req["body"]
	assert_true(body.slice(0, boundary.length() + 2) == ("--" + boundary).to_utf8_buffer())
	var tail := ("\r\n--" + boundary + "--\r\n").to_utf8_buffer()
	assert_true(body.slice(body.size() - tail.size()) == tail, "закрывающий разделитель")
	assert_eq(_find_bytes(FIT, boundary.to_utf8_buffer(), 0), -1, "boundary не содержится в данных файла")
	assert_true(boundary.length() >= 20, "boundary достаточно длинный и случайный")
	# Собственная сборка build_multipart даёт тот же разбор.
	var b2 := StravaUploader.build_multipart({"a": "1", "b": "два"}, "file", "x.fit", FIT, "----acc-boundary")
	var parts2 := _parse_multipart(b2, "multipart/form-data; boundary=----acc-boundary")
	assert_eq(parts2.size(), 3)
	assert_eq(_text(parts2, "b"), "два")
	assert_eq(_part(parts2, "file")["body"], FIT)


func test_req_str_02_c3_poll_until_activity_id_and_error_text() -> void:
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 99999)
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 90002, "status": "Your activity is still being processed.", "activity_id": null, "error": null})
	_mock.enqueue_json("GET", "/uploads/90002", 200, {"id": 90002, "status": "Your activity is still being processed.", "activity_id": null, "error": null}, {}, 2)
	_mock.enqueue_json("GET", "/uploads/90002", 200, {"id": 90002, "status": "Your activity is ready.", "activity_id": 555002, "error": null})
	var r: UploadResult = await _uploader.upload_fit(FIT, "n", "d", "ride-2")
	assert_eq(r.status, UploadResult.STATUS_DONE, "опрос до activity_id")
	assert_eq(r.activity_id, "555002")
	assert_eq(r.upload_id, "90002")
	assert_eq(r.activity_url(), "https://www.strava.com/activities/555002", "REQ-STR-05 крит. 3")
	assert_eq(_mock.request_count("GET", "/uploads/90002"), 3, "три опроса")
	assert_eq(_waits.size(), 2, "пауза между опросами (не перед первым)")
	for req in _mock.requests.slice(1):
		assert_eq(str(req["headers"]["Authorization"]), "Bearer " + ACCESS_A, "опрос — с тем же токеном")
	assert_true(r.is_final())
	# Ошибка обработки — статус «ошибка» с текстом Strava, без повтора.
	_mock.clear()
	_waits.clear()
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 90003, "status": "processing", "activity_id": null, "error": null})
	_mock.enqueue_json("GET", "/uploads/90003", 200, {"id": 90003, "status": "There was an error processing your activity.", "activity_id": null, "error": "The file is malformed"})
	var bad: UploadResult = await _uploader.upload_fit(FIT, "n", "d", "ride-3")
	assert_eq(bad.status, UploadResult.STATUS_FAILED)
	assert_eq(bad.error, "The file is malformed", "текст ошибки Strava")
	assert_false(bad.can_retry, "без повторов")
	assert_true(bad.is_final())
	assert_eq(bad.upload_id, "90003")
	assert_eq(bad.activity_url(), "")
	# Готово сразу в ответе на POST — без опроса.
	_mock.clear()
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 90004, "status": "ready", "activity_id": 555004})
	var instant: UploadResult = await _uploader.upload_fit(FIT, "n", "d", "ride-4")
	assert_eq(instant.status, UploadResult.STATUS_DONE)
	assert_eq(_mock.request_count("GET"), 0)


func test_req_str_02_c4_duplicate_is_separate_final_status_without_retries() -> void:
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 99999)
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 90005, "status": "There was an error processing your activity.", "activity_id": null,
		"error": "ride-5.fit duplicate of activity 555000"})
	var r: UploadResult = await _uploader.upload_fit(FIT, "n", "d", "ride-5")
	assert_eq(r.status, UploadResult.STATUS_DUPLICATE, "дубликат — отдельный статус")
	assert_true(r.is_final())
	assert_false(r.can_retry)
	assert_string_contains(r.error, "duplicate")
	assert_eq(_mock.request_count(), 1, "без повторных запросов")
	# В очереди дубликат — финал: элемент удалён, статус duplicate, повторов нет.
	_mock.clear()
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 90006, "activity_id": null, "error": "duplicate of activity 1"})
	_queue.enqueue("ride-dup", Callable(), "n", "d", NOW - 100)
	var id: String = await _queue.tick(_now)
	assert_eq(id, "ride-dup")
	assert_eq(_status.get_upload_status("ride-dup")["status"], UploadResult.STATUS_DUPLICATE)
	assert_false(_queue.has("ride-dup"), "элемент удалён из очереди")
	_now += 100000
	assert_eq(await _queue.tick(_now), "", "повторов нет")
	assert_eq(_mock.request_count(), 1)
	assert_eq(_status.status_sequence("ride-dup"), ["queued", "uploading", "duplicate"] as Array[String])


func test_req_str_02_edge_no_auth_or_empty_fit_no_request_and_max_polls_exhausted_is_uploading() -> void:
	var no_auth: UploadResult = await _uploader.upload_fit(FIT, "n", "d", "ride-x")
	assert_eq(no_auth.status, UploadResult.STATUS_FAILED)
	assert_eq(no_auth.code, ApiResult.CODE_REAUTH_REQUIRED)
	assert_eq(_mock.request_count(), 0, "без авторизации — 0 запросов")
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 99999)
	var empty: UploadResult = await _uploader.upload_fit(PackedByteArray(), "n", "d", "ride-x")
	assert_eq(empty.status, UploadResult.STATUS_FAILED)
	assert_false(empty.can_retry)
	assert_eq(_mock.request_count(), 0, "пустой FIT — 0 запросов")
	# max_polls исчерпан — статус uploading с upload_id (очередь опросит позже).
	_uploader.max_polls = 3
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 90007, "activity_id": null, "error": null})
	_mock.enqueue_json("GET", "/uploads/90007", 200, {"id": 90007, "activity_id": null, "error": null}, {}, -1)
	var still: UploadResult = await _uploader.upload_fit(FIT, "n", "d", "ride-7")
	assert_eq(still.status, UploadResult.STATUS_UPLOADING)
	assert_eq(still.upload_id, "90007")
	assert_false(still.is_final())
	assert_eq(_mock.request_count("GET", "/uploads/90007"), 3, "ровно max_polls опросов")
	assert_eq(_waits.size(), 2)
	# poll_upload напрямую: без upload_id — ошибка; с токеном из хранилища — работает.
	var no_id: UploadResult = await _uploader.poll_upload("")
	assert_eq(no_id.status, UploadResult.STATUS_FAILED)
	_mock.clear()
	_mock.enqueue_json("GET", "/uploads/90007", 200, {"id": 90007, "activity_id": 555007})
	var later: UploadResult = await _uploader.poll_upload("90007")
	assert_eq(later.status, UploadResult.STATUS_DONE)
	assert_eq(later.activity_id, "555007")


func test_req_str_01_c4_upload_401_refreshes_once_and_retries_second_401_is_reauth() -> void:
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 99999)
	_mock.enqueue_json("POST", "/uploads", 401, {"message": "Authorization Error"})
	_mock.enqueue_json("POST", "/oauth/token", 200, _token_payload("fixture-access-token-A5", "fixture-refresh-token-A5", NOW + 99999))
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 90008, "activity_id": 555008})
	var r: UploadResult = await _uploader.upload_fit(FIT, "n", "d", "ride-8")
	assert_eq(r.status, UploadResult.STATUS_DONE, "после обновления токена повтор удался")
	assert_eq(_mock.requests.size(), 3)
	assert_eq(_form(_mock.requests[1]["body"])["grant_type"], "refresh_token", "одно обновление токена")
	assert_eq(str(_mock.requests[2]["headers"]["Authorization"]), "Bearer fixture-access-token-A5", "повтор — с новым токеном")
	assert_eq(_store.get_secret(_oauth.secret_key(SecureStore.ITEM_ACCESS_TOKEN)), "fixture-access-token-A5")
	# Повторный 401 → требуется повторный вход, третьей попытки нет.
	_mock.clear()
	_mock.enqueue_json("POST", "/uploads", 401, {"message": "Authorization Error"}, {}, -1)
	_mock.enqueue_json("POST", "/oauth/token", 200, _token_payload("fixture-access-token-A6", "fixture-refresh-token-A6", NOW + 99999))
	var r2: UploadResult = await _uploader.upload_fit(FIT, "n", "d", "ride-9")
	assert_eq(r2.status, UploadResult.STATUS_FAILED)
	assert_eq(r2.code, ApiResult.CODE_REAUTH_REQUIRED, "повторный 401 — статус «требуется повторный вход»")
	assert_false(r2.can_retry)
	assert_eq(_mock.request_count("POST", "/uploads"), 2, "ровно один повтор")


func test_req_str_03_c1_c2_default_name_and_description_templates() -> void:
	assert_eq(StravaUploader.default_name("Threshold 3x5", "2026-10-03"), "Threshold 3x5", "название плана")
	assert_eq(StravaUploader.default_name("", "2026-10-03"), "Тренировка 2026-10-03", "без плана — «Тренировка <дата>»")
	assert_eq(StravaUploader.default_name("   ", "2026-10-03"), "Тренировка 2026-10-03")
	assert_eq(StravaUploader.default_name("", "2026-10-03", "Workout %s"), "Workout 2026-10-03", "шаблон на языке интерфейса")
	var d := StravaUploader.default_description("Разминка и 3 интервала")
	assert_true(d.begins_with("Разминка и 3 интервала"), "описание плана первым")
	assert_string_contains(d, "ovosch-rider", "строка с названием приложения")
	assert_eq(StravaUploader.default_description(""), "Записано в ovosch-rider", "без описания — только строка приложения")
	assert_eq(StravaUploader.default_description("x", "Recorded with ovosch-rider"), "x\n\nRecorded with ovosch-rider")
	assert_eq(StravaUploader.SPORT_TYPE, "VirtualRide")
	assert_eq(StravaUploader.DATA_TYPE_FIT, "fit")


func test_req_str_02_c2_file_part_is_encoder_fit_with_sport_cycling_sub_sport_virtual_activity() -> void:
	# Крит. 1 («содержимое FIT из LOC-05») + крит. 2: байты FitEncoder проходят в поле `file` без изменений,
	# в `session` — sport=2, sub_sport=58.
	var ride := _ride_with_samples(5)
	var fit := FitEncoder.encode(ride)
	assert_gt(fit.size(), 14, "кодировщик выдал FIT")
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 99999)
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 90201, "activity_id": 555201})
	var r: UploadResult = await _uploader.upload_fit(fit, StravaUploader.default_name(ride.name, "2026-10-03"),
		StravaUploader.default_description(ride.description), ride.id)
	assert_eq(r.status, UploadResult.STATUS_DONE, str(r))
	var req: Dictionary = _mock.requests[0]
	var parts := _parse_multipart(req["body"], str(req["headers"]["Content-Type"]))
	var file := _part(parts, "file")
	assert_false(file.is_empty())
	assert_eq(file["body"], fit, "байты FIT кодировщика переданы без изменений")
	assert_eq(_text(parts, "external_id"), ride.id, "external_id = идентификатор заезда")
	assert_eq(_text(parts, "data_type"), "fit")
	assert_eq(_text(parts, "name"), "Threshold 3x5")
	var dec := FitDecoder.decode(file["body"])
	assert_true(dec.ok, dec.error)
	assert_true(dec.header_crc_ok and dec.file_crc_ok, "CRC заголовка и файла верны")
	assert_eq(int(dec.first_field(FitDefinitions.MSG_SESSION, FitDefinitions.SESSION_SPORT)), 2, "session.sport = cycling (2)")
	assert_eq(int(dec.first_field(FitDefinitions.MSG_SESSION, FitDefinitions.SESSION_SUB_SPORT)), 58, "session.sub_sport = virtual_activity (58)")
	assert_eq(dec.count(FitDefinitions.MSG_RECORD), 5, "все сэмплы в record")


func test_req_str_02_c3_edge_http_error_on_poll_keeps_processing_without_second_post() -> void:
	# Выгрузка принята (201 с id); HTTP-ошибка при опросе — не вердикт Strava: заезд остаётся
	# «обрабатывается», очередь опрашивает по upload_id позже; 429 — не раньше Retry-After (STR-04 крит. 3).
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 999999)
	_uploader.max_polls = 1
	_queue.enqueue("ride-pe", Callable(), "n", "d", NOW - 10)
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 77, "activity_id": null, "error": null})
	_mock.enqueue_json("GET", "/uploads/77", 429, {"message": "Rate Limit Exceeded"}, {"Retry-After": "300"})
	assert_eq(await _queue.tick(_now), "ride-pe")
	assert_eq(_status.get_upload_status("ride-pe")["status"], UploadResult.STATUS_UPLOADING, "429 при опросе → по-прежнему «обрабатывается»")
	assert_eq(_queue.get_item("ride-pe")["upload_id"], "77")
	assert_eq(int(_queue.get_item("ride-pe")["next_attempt_at"]), _now + 300, "следующий опрос не раньше Retry-After")
	_mock.enqueue_json("GET", "/uploads/77", 503, {})
	assert_eq(await _queue.tick(_now + 300), "ride-pe")
	assert_eq(_status.get_upload_status("ride-pe")["status"], UploadResult.STATUS_UPLOADING, "5xx при опросе → «обрабатывается»")
	assert_eq(int(_queue.get_item("ride-pe")["next_attempt_at"]), _now + 300 + _queue.poll_retry_sec)
	_mock.offline = true
	assert_eq(await _queue.tick(_now + 300 + _queue.poll_retry_sec), "ride-pe")
	assert_eq(_status.get_upload_status("ride-pe")["status"], UploadResult.STATUS_UPLOADING, "нет сети при опросе → «обрабатывается»")
	_mock.offline = false
	_mock.enqueue_json("GET", "/uploads/77", 200, {"id": 77, "activity_id": 7777})
	assert_eq(await _queue.tick(_now + 300 + 2 * _queue.poll_retry_sec), "ride-pe")
	assert_eq(_status.get_upload_status("ride-pe")["status"], UploadResult.STATUS_DONE)
	assert_eq(_status.get_upload_status("ride-pe")["activity_id"], "7777")
	assert_eq(_mock.request_count("POST", "/uploads"), 1, "один POST на заезд — повторной выгрузки (и дубликата) нет")
	assert_false(_queue.has("ride-pe"))


# ===========================================================================
# REQ-STR-04 / REQ-STR-05 / REQ-NFR-03 крит. 3 — очередь выгрузки
# ===========================================================================

func test_req_str_04_c1_enqueue_persists_and_survives_restart() -> void:
	_queue.enqueue("ride-1", Callable(), "Имя 1", "Описание 1", NOW - 3600)
	assert_true(_queue.has("ride-1"))
	assert_eq(_queue.size(), 1)
	assert_eq(_status.get_upload_status("ride-1")["status"], UploadResult.STATUS_QUEUED, "REQ-STR-05: «в очереди»")
	assert_true(FileAccess.file_exists(_queue.file_path()), "очередь на диске")
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(_queue.file_path())), OK)
	assert_eq((json.data["items"] as Array).size(), 1)
	assert_eq(json.data["items"][0]["ride_id"], "ride-1")
	assert_eq(json.data["items"][0]["name"], "Имя 1")
	# «Перезапуск»: новый экземпляр на том же каталоге продолжает с того же места.
	var restarted := _make_queue()
	assert_eq(restarted.size(), 1)
	var item := restarted.get_item("ride-1")
	assert_eq(item["name"], "Имя 1")
	assert_eq(item["description"], "Описание 1")
	assert_eq(int(item["ride_date"]), NOW - 3600)
	assert_eq(int(item["attempts"]), 0)
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 1, "activity_id": 555001})
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 99999)
	assert_eq(await restarted.tick(_now), "ride-1", "после перезапуска выгрузка выполнена через общий fit_provider")
	assert_eq(_status.get_upload_status("ride-1")["status"], UploadResult.STATUS_DONE)
	assert_eq(_status.get_upload_status("ride-1")["activity_id"], "555001")
	assert_false(restarted.has("ride-1"))
	var again := _make_queue()
	assert_eq(again.size(), 0, "выгруженный элемент не возвращается после перезапуска")
	# Пустой/некорректный ride_id игнорируется.
	_queue.enqueue("", Callable(), "n", "d")
	assert_eq(_queue.size(), 1)


func test_req_str_04_c1_edge_corrupted_queue_file_is_ignored_and_overwritten() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	var f := FileAccess.open(_queue.file_path(), FileAccess.WRITE)
	f.store_string("{ not json at all")
	f.close()
	var q := _make_queue()
	assert_eq(q.size(), 0, "битый файл → пустая очередь, без падения")
	q.enqueue("ride-ok", Callable(), "n", "d")
	var q2 := _make_queue()
	assert_eq(q2.size(), 1, "после сохранения файл снова валиден")
	# Элементы без ride_id пропускаются.
	var f2 := FileAccess.open(_queue.file_path(), FileAccess.WRITE)
	f2.store_string(JSON.stringify({"schema": 1, "items": [{"name": "no id"}, {"ride_id": "r2", "ride_date": 5}, 42]}))
	f2.close()
	var q3 := _make_queue()
	assert_eq(q3.size(), 1)
	assert_eq(q3.items()[0]["ride_id"], "r2")


func test_req_str_04_c2_network_and_5xx_back_off_1_5_15_60_min_then_hourly_without_exhaustion() -> void:
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 999999)
	_queue.enqueue("ride-net", Callable(), "n", "d", NOW - 10)
	_mock.offline = true
	assert_eq(await _queue.tick(_now), "ride-net", "попытка 1 (offline)")
	var item := _queue.get_item("ride-net")
	assert_eq(int(item["attempts"]), 1)
	assert_eq(int(item["next_attempt_at"]), _now + 60, "следующая через 1 мин")
	assert_eq(_status.get_upload_status("ride-net")["status"], UploadResult.STATUS_QUEUED, "снова «в очереди»")
	assert_false(str(_status.get_upload_status("ride-net")["error"]).is_empty(), "с текстом последней ошибки")
	assert_eq(await _queue.tick(_now + 59), "", "до срока — не трогаем")
	var expected_delays := [300, 900, 3600, 3600, 3600, 3600]
	var t := _now + 60
	for i in expected_delays.size():
		if i % 2 == 0:
			_mock.offline = true
		else:
			_mock.offline = false
			_mock.enqueue_json("POST", "/uploads", 503, {"message": "Service Unavailable"})
		assert_eq(await _queue.tick(t), "ride-net", "попытка %d" % (i + 2))
		item = _queue.get_item("ride-net")
		assert_eq(int(item["attempts"]), i + 2)
		assert_eq(int(item["next_attempt_at"]), t + expected_delays[i], "задержка после попытки %d = %d с" % [i + 2, expected_delays[i]])
		t += expected_delays[i]
	assert_true(_queue.has("ride-net"), "попытки не исчерпываются (7 неудач)")
	assert_eq(_status.get_upload_status("ride-net")["status"], UploadResult.STATUS_QUEUED)
	# Сеть появилась — выгрузка проходит (REQ-NFR-03 крит. 3).
	_mock.offline = false
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 7, "activity_id": 555777})
	assert_eq(await _queue.tick(t), "ride-net")
	assert_eq(_status.get_upload_status("ride-net")["status"], UploadResult.STATUS_DONE)
	assert_eq(_status.get_upload_status("ride-net")["activity_id"], "555777")
	assert_eq(int(_status.get_upload_status("ride-net")["attempts"]), 7, "число попыток сохранено в статусе")
	assert_false(_queue.has("ride-net"))
	# Таблица задержек.
	assert_eq(UploadQueue.retry_delay_sec(1), 60)
	assert_eq(UploadQueue.retry_delay_sec(2), 300)
	assert_eq(UploadQueue.retry_delay_sec(3), 900)
	assert_eq(UploadQueue.retry_delay_sec(4), 3600)
	assert_eq(UploadQueue.retry_delay_sec(50), 3600)
	assert_eq(UploadQueue.retry_delay_sec(0), 60)


func test_req_str_04_c3_429_waits_retry_after_seconds_http_date_or_missing_is_60() -> void:
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 999999)
	_queue.enqueue("ride-429", Callable(), "n", "d", NOW - 10)
	_mock.enqueue_json("POST", "/uploads", 429, {"message": "Rate Limit Exceeded"}, {"Retry-After": "900"})
	await _queue.tick(_now)
	assert_eq(int(_queue.get_item("ride-429")["next_attempt_at"]), _now + 900, "повтор не раньше Retry-After (900 с)")
	assert_eq(int(_queue.get_item("ride-429")["attempts"]), 1)
	_now += 900
	_mock.enqueue_json("POST", "/uploads", 429, {"message": "Rate Limit Exceeded"}, {"Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"})
	await _queue.tick(_now)
	assert_eq(int(_queue.get_item("ride-429")["next_attempt_at"]), _now + 60, "HTTP-дата → 60 с")
	_now += 60
	_mock.enqueue_json("POST", "/uploads", 429, {"message": "Rate Limit Exceeded"})
	await _queue.tick(_now)
	assert_eq(int(_queue.get_item("ride-429")["next_attempt_at"]), _now + 60, "без заголовка → 60 с")
	_now += 60
	_mock.enqueue_json("POST", "/uploads", 429, {}, {"retry-after": "5"})
	await _queue.tick(_now)
	assert_eq(int(_queue.get_item("ride-429")["next_attempt_at"]), _now + 5, "имя заголовка без учёта регистра")
	assert_eq(_status.get_upload_status("ride-429")["status"], UploadResult.STATUS_QUEUED)
	assert_true(_queue.has("ride-429"))
	# Уровень uploader: 429 → can_retry + retry_after_sec.
	_mock.enqueue_json("POST", "/uploads", 429, {}, {"Retry-After": "7"})
	var r: UploadResult = await _uploader.upload_fit(FIT, "n", "d", "r")
	assert_eq(r.code, ApiResult.CODE_RATE_LIMITED)
	assert_true(r.can_retry)
	assert_eq(r.retry_after_sec, 7)
	assert_false(r.is_final())


func test_req_str_04_c4_one_upload_at_a_time_in_ride_date_order() -> void:
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 999999)
	_queue.enqueue("ride-late", Callable(), "late", "", NOW - 100)
	_queue.enqueue("ride-early", Callable(), "early", "", NOW - 5000)
	_queue.enqueue("ride-mid", Callable(), "mid", "", NOW - 2000)
	var order: Array[String] = []
	for it in _queue.items():
		order.append(str(it["ride_id"]))
	assert_eq(order, ["ride-early", "ride-mid", "ride-late"] as Array[String], "порядок — по дате заезда, не постановки")
	assert_eq(_queue.next_due(_now)["ride_id"], "ride-early")
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 1, "activity_id": 1001})
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 2, "activity_id": 1002})
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 3, "activity_id": 1003})
	assert_eq(await _queue.tick(_now), "ride-early", "за один tick — одна выгрузка")
	assert_eq(_mock.request_count("POST", "/uploads"), 1, "ровно один запрос выгрузки")
	assert_eq(_queue.size(), 2)
	assert_eq(_status.get_upload_status("ride-mid")["status"], UploadResult.STATUS_QUEUED, "остальные ждут")
	assert_eq(await _queue.tick(_now), "ride-mid")
	assert_eq(await _queue.tick(_now), "ride-late")
	assert_eq(await _queue.tick(_now), "", "очередь пуста")
	var names: Array[String] = []
	for req in _mock.requests:
		names.append(_text(_parse_multipart(req["body"], str(req["headers"]["Content-Type"])), "name"))
	assert_eq(names, ["early", "mid", "late"] as Array[String], "выгружены в порядке даты заезда")
	assert_eq(_status.get_upload_status("ride-late")["activity_id"], "1003")
	assert_false(_queue.is_busy())


func test_req_str_04_c5_retry_now_and_reenqueue_from_history_make_item_due_immediately() -> void:
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 999999)
	_queue.enqueue("ride-r", Callable(), "n", "d", NOW - 10)
	_mock.offline = true
	await _queue.tick(_now)
	assert_eq(int(_queue.get_item("ride-r")["next_attempt_at"]), _now + 60)
	assert_eq(await _queue.tick(_now + 1), "", "до срока — ничего")
	assert_true(_queue.retry_now("ride-r"), "ручной повтор из карточки заезда")
	assert_eq(int(_queue.get_item("ride-r")["next_attempt_at"]), _now)
	_mock.offline = false
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 1, "activity_id": 2001})
	assert_eq(await _queue.tick(_now + 1), "ride-r", "выгружен немедленно")
	assert_eq(_status.get_upload_status("ride-r")["status"], UploadResult.STATUS_DONE)
	assert_false(_queue.retry_now("ride-r"), "уже не в очереди")
	assert_false(_queue.retry_now("ghost"), "несуществующий → false")
	# Заезд без статуса «выгружено» ставится в очередь из истории с изменёнными названием/описанием (STR-03 крит. 3).
	_queue.enqueue("ride-h", Callable(), "Старое", "d", NOW - 10)
	_queue.enqueue("ride-h", Callable(), "Новое название", "Новое описание", NOW - 10)
	assert_eq(_queue.size(), 1, "повторная постановка не дублирует элемент (ride-r уже выгружен и удалён)")
	assert_true(_queue.has("ride-h"))
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 2, "activity_id": 2002})
	assert_eq(await _queue.tick(_now + 2), "ride-h")
	var parts := _parse_multipart(_mock.last_request()["body"], str(_mock.last_request()["headers"]["Content-Type"]))
	assert_eq(_text(parts, "name"), "Новое название", "изменённое название ушло в запрос")
	assert_eq(_text(parts, "description"), "Новое описание")
	# remove несуществующего и существующего.
	assert_false(_queue.remove("nope"))
	_queue.enqueue("ride-rm", Callable(), "n", "d")
	assert_true(_queue.remove("ride-rm"))
	assert_false(_queue.has("ride-rm"))
	assert_false(_queue.remove("ride-rm"), "повторное удаление → false")


func test_req_str_04_c6_nfr_03_c3_no_upload_during_active_session_then_resumes() -> void:
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 999999)
	_queue.enqueue("ride-s", Callable(), "n", "d", NOW - 10)
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 1, "activity_id": 3001})
	_queue.session_active = true
	for i in 5:
		assert_eq(await _queue.tick(_now + i * 1000), "", "во время тренировки очередь стоит")
	assert_eq(_mock.request_count(), 0, "0 сетевых запросов за время сессии")
	assert_eq(_status.get_upload_status("ride-s")["status"], UploadResult.STATUS_QUEUED)
	assert_true(_queue.has("ride-s"))
	_queue.session_active = false
	assert_eq(await _queue.tick(_now + 5000), "ride-s", "после завершения — выгрузка")
	assert_eq(_status.get_upload_status("ride-s")["status"], UploadResult.STATUS_DONE)
	# NFR-03 крит. 3: офлайн — в очереди; появилась сеть — выгружено (без ручных действий).
	_mock.offline = true
	_queue.enqueue("ride-off", Callable(), "n", "d", NOW)
	await _queue.tick(_now + 6000)
	assert_eq(_status.get_upload_status("ride-off")["status"], UploadResult.STATUS_QUEUED, "без сети остаётся в очереди")
	_mock.offline = false
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 2, "activity_id": 3002})
	assert_eq(await _queue.tick(_now + 6000 + 60), "ride-off", "сеть появилась — выгружено по расписанию")
	assert_eq(_status.get_upload_status("ride-off")["activity_id"], "3002")


func test_req_str_05_c1_c3_status_transitions_and_activity_link() -> void:
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 999999)
	assert_eq(UploadResult.STATUSES, ["none", "queued", "uploading", "done", "failed", "duplicate"] as Array[String])
	assert_eq(_status.get_upload_status("unknown"), {}, "без выгрузок — пусто («не выгружен»)")
	# queued → uploading → queued (ошибка сети) → uploading → done.
	_queue.enqueue("ride-t", Callable(), "n", "d", NOW - 10)
	_mock.offline = true
	await _queue.tick(_now)
	_mock.offline = false
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 10, "activity_id": null, "error": null})
	_mock.enqueue_json("GET", "/uploads/10", 200, {"id": 10, "activity_id": 4001})
	await _queue.tick(_now + 60)
	assert_eq(_status.status_sequence("ride-t"), ["queued", "uploading", "queued", "uploading", "done"] as Array[String])
	var done := _status.get_upload_status("ride-t")
	assert_eq(done["activity_id"], "4001", "«выгружено» с activity_id")
	assert_eq(done["error"], "")
	assert_eq(StravaBranding.activity_url(str(done["activity_id"])), "https://www.strava.com/activities/4001", "REQ-STR-05 крит. 3")
	assert_eq(UploadResult.done("4001").activity_url(), "https://www.strava.com/activities/4001")
	# queued → uploading → failed (ошибка обработки с текстом), без повтора.
	_queue.enqueue("ride-f", Callable(), "n", "d", NOW - 10)
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 11, "activity_id": null, "error": "The file is malformed"})
	await _queue.tick(_now + 60)
	assert_eq(_status.status_sequence("ride-f"), ["queued", "uploading", "failed"] as Array[String])
	assert_eq(_status.get_upload_status("ride-f")["error"], "The file is malformed")
	assert_false(_queue.has("ride-f"))
	# «обрабатывается» между опросами: Strava ещё обрабатывает после max_polls опросов —
	# uploading с upload_id сохраняется и опрашивается позже по upload_id.
	_uploader.max_polls = 1
	_queue.enqueue("ride-p", Callable(), "n", "d", NOW - 10)
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 12, "activity_id": null, "error": null})
	_mock.enqueue_json("GET", "/uploads/12", 200, {"id": 12, "status": "Your activity is still being processed.", "activity_id": null, "error": null})
	await _queue.tick(_now + 60)
	assert_eq(_status.get_upload_status("ride-p")["status"], UploadResult.STATUS_UPLOADING, "«обрабатывается»")
	assert_eq(_status.get_upload_status("ride-p")["upload_id"], "12")
	assert_eq(_queue.get_item("ride-p")["upload_id"], "12")
	assert_eq(int(_queue.get_item("ride-p")["next_attempt_at"]), _now + 60 + _queue.poll_retry_sec, "следующий опрос через poll_retry_sec")
	var posts_before := _mock.request_count("POST", "/uploads")
	_mock.enqueue_json("GET", "/uploads/12", 200, {"id": 12, "activity_id": 4012})
	assert_eq(await _queue.tick(_now + 60 + _queue.poll_retry_sec), "ride-p", "позже — опрос по upload_id, не повторная выгрузка")
	assert_eq(_mock.request_count("POST", "/uploads"), posts_before, "повторного POST для ride-p не было")
	assert_eq(_status.status_sequence("ride-p"), ["queued", "uploading", "uploading", "uploading", "done"] as Array[String])
	assert_eq(_status.get_upload_status("ride-p")["status"], UploadResult.STATUS_DONE)
	# reauth_required — финальная ошибка, без повторов.
	_store.delete_service_secrets(A, SecureStore.SERVICE_STRAVA)
	_queue.enqueue("ride-na", Callable(), "n", "d", NOW - 10)
	await _queue.tick(_now + 100)
	assert_eq(_status.get_upload_status("ride-na")["status"], UploadResult.STATUS_FAILED)
	assert_eq(_status.get_upload_status("ride-na")["code"], ApiResult.CODE_REAUTH_REQUIRED)
	assert_false(_queue.has("ride-na"))


func test_req_str_04_c3_429_on_token_refresh_during_upload_honours_retry_after() -> void:
	# Крит. 3: «Ответ 429 — повтор не раньше Retry-After». Обновление токена перед выгрузкой — часть
	# попытки; 429 с Retry-After=900 на нём не должен превращаться в повтор через 1 мин.
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 10)  # < 60 с → обновление перед выгрузкой (крит. STR-01.3)
	_queue.enqueue("ride-429r", Callable(), "n", "d", NOW - 10)
	_mock.enqueue_json("POST", "/oauth/token", 429, {"message": "Rate Limit Exceeded"}, {"Retry-After": "900"})
	assert_eq(await _queue.tick(_now), "ride-429r")
	assert_eq(_mock.request_count("POST", "/uploads"), 0, "без свежего токена выгрузка не отправлялась")
	assert_true(_queue.has("ride-429r"), "429 — временная ошибка, элемент остаётся в очереди")
	assert_eq(_status.get_upload_status("ride-429r")["status"], UploadResult.STATUS_QUEUED)
	assert_eq(int(_queue.get_item("ride-429r")["attempts"]), 1)
	assert_eq(int(_queue.get_item("ride-429r")["next_attempt_at"]), _now + 900, "повтор не раньше Retry-After (900 с), а не 60 с по таблице")
	assert_eq(await _queue.tick(_now + 899), "", "до Retry-After — не трогаем")


func test_req_str_04_c4_second_tick_while_upload_in_flight_is_rejected() -> void:
	# Крит. 4: «Одновременно выполняется не более одной выгрузки» — при незавершённом HTTP-запросе
	# повторный tick ничего не берёт, даже если другой элемент созрел.
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 999999)
	var blocking := BlockingTransport.new(_mock)
	var uploader2 := StravaUploader.new(blocking, _oauth)
	uploader2.api_base = API
	uploader2.wait_fn = func(sec: float) -> void: _waits.append(sec)
	var q := UploadQueue.new(uploader2, _status, func() -> int: return _now, "profile-conc", _dir)
	q.fit_provider = func(_ride_id: String) -> PackedByteArray: return FIT
	q.enqueue("ride-a", Callable(), "a", "", NOW - 5000)
	q.enqueue("ride-b", Callable(), "b", "", NOW - 1000)
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 1, "activity_id": 9001})
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 2, "activity_id": 9002})
	q.tick(_now)  # без await: выполняется до «зависшего» запроса
	assert_true(q.is_busy(), "выгрузка ride-a в полёте")
	assert_eq(blocking.in_flight, 1)
	assert_eq(_status.get_upload_status("ride-a")["status"], UploadResult.STATUS_UPLOADING)
	var second: String = await q.tick(_now)
	assert_eq(second, "", "второй tick во время выгрузки ничего не берёт")
	assert_eq(blocking.in_flight, 1, "второго запроса нет")
	assert_eq(_status.get_upload_status("ride-b")["status"], UploadResult.STATUS_QUEUED, "ride-b ждёт")
	assert_eq(_mock.request_count(), 0, "до release ни один запрос не дошёл до сети")
	blocking.release.emit()
	assert_false(q.is_busy(), "после ответа — свободна")
	assert_eq(_status.get_upload_status("ride-a")["status"], UploadResult.STATUS_DONE)
	assert_eq(_status.get_upload_status("ride-a")["activity_id"], "9001")
	assert_eq(_mock.request_count("POST", "/uploads"), 1)
	q.tick(_now)
	assert_true(q.is_busy())
	blocking.release.emit()
	assert_eq(_status.get_upload_status("ride-b")["status"], UploadResult.STATUS_DONE)
	assert_eq(blocking.max_in_flight, 1, "ни разу не было двух запросов одновременно")
	assert_eq(q.size(), 0)


func test_req_str_05_c1_edge_cancelled_item_is_not_reported_as_queued() -> void:
	# STR-04 крит. 2: повторы «до успеха или ручной отмены»; STR-05 крит. 1: переходы соответствуют STR-04.
	# После ручной отмены заезд не в очереди — статус «в очереди» для него неверен.
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 999999)
	_queue.enqueue("ride-c", Callable(), "n", "d", NOW - 10)
	_mock.offline = true
	await _queue.tick(_now)
	assert_eq(_status.get_upload_status("ride-c")["status"], UploadResult.STATUS_QUEUED)
	assert_true(_queue.remove("ride-c"), "ручная отмена")
	assert_false(_queue.has("ride-c"))
	var st := str(_status.get_upload_status("ride-c").get("status", UploadResult.STATUS_NONE))
	assert_ne(st, UploadResult.STATUS_QUEUED, "после отмены заезд не должен значиться «в очереди» (ожидаем «не выгружен»)")
	assert_eq(await _queue.tick(_now + 60), "", "отменённый элемент не выгружается")


func test_req_str_05_c2_status_vocabulary_matches_ride_metadata_contract() -> void:
	# Адаптер к RideRepository — T-049 (не принимается здесь); проверяем контракт: словарь статусов очереди
	# совпадает со статусами метаданных заезда, интерфейс хранилища принимает статус выгрузки.
	assert_eq(UploadResult.STATUSES, Ride.UPLOAD_STATUSES, "одни и те же шесть статусов (STR-05 крит. 1)")
	var upload := Ride.default_upload()
	assert_eq(str(upload["strava_status"]), UploadResult.STATUS_NONE, "новый заезд — «не выгружен»")
	assert_true(upload.has("strava_activity_id") and upload.has("last_error") and upload.has("attempts"))
	assert_true(RideRepository.new().has_method("update_upload_status"), "RideRepository.update_upload_status есть")
	var dict := UploadResult.done("4001", "12").to_status_dict(3, NOW)
	for key in ["status", "activity_id", "upload_id", "error", "code", "attempts", "updated_at"]:
		assert_true(dict.has(key), "ключ %s в словаре статуса" % key)
	assert_eq(dict["attempts"], 3)
	assert_eq(dict["updated_at"], NOW)


# ===========================================================================
# REQ-PRF-03 крит. 1–2, REQ-NFR-05 крит. 1–2
# ===========================================================================

func test_req_prf_03_c1_c2_tokens_per_profile_and_service_separation() -> void:
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 999999)
	var oauth_b := _make_oauth(B)
	assert_false(oauth_b.is_authorized(), "токены A недоступны B")
	assert_eq(oauth_b.access_token(), "")
	var rb: ApiResult = await oauth_b.ensure_fresh_token()
	assert_eq(rb.code, ApiResult.CODE_REAUTH_REQUIRED)
	assert_eq(_mock.request_count(), 0, "B не использует токены A")
	for key in _store.list_keys():
		assert_true(str(key).begins_with("profile-a/strava/"), "ключи содержат id профиля и сервис: %s" % key)
	# Удаление привязки Intervals профиля A не трогает Strava A (крит. 2).
	_store.set_secret(SecureStore.key_for(A, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY), "fixture-intervals-key-A")
	_store.delete_service_secrets(A, SecureStore.SERVICE_INTERVALS)
	assert_true(_oauth.is_authorized())
	assert_eq(_store.size(), 3)


func test_req_nfr_05_c1_c2_secrets_only_via_secure_store_and_never_on_disk() -> void:
	# Файлы в user:// после работы очереди/конфига не содержат токенов и секрета.
	_seed_tokens(_oauth, ACCESS_A, REFRESH_A, NOW + 999999)
	_queue.enqueue("ride-disk", Callable(), "n", "d", NOW - 10)
	_mock.offline = true
	await _queue.tick(_now)
	_mock.offline = false
	_mock.enqueue_json("POST", "/uploads", 201, {"id": 1, "activity_id": null, "error": null})
	_uploader.max_polls = 1
	await _queue.tick(_now + 60)
	var abs := ProjectSettings.globalize_path(_dir)
	var files: Array[String] = []
	var d := DirAccess.open(abs)
	for f in d.get_files():
		files.append(abs.path_join(f))
	assert_gt(files.size(), 0, "файл очереди записан")
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		for secret in [ACCESS_A, REFRESH_A, CLIENT_SECRET_VALUE]:
			assert_false(text.contains(secret), "файл %s без значения секрета" % path)
	# Статус заезда (метаданные) — тоже без секретов.
	var status_json := JSON.stringify(_status.get_upload_status("ride-disk"))
	assert_false(status_json.contains(ACCESS_A) or status_json.contains(REFRESH_A))
	# Код Strava-интеграции обращается к токенам только через интерфейс SecureStore
	# (нет собственных файловых записей токенов): FileAccess.WRITE — только для файла очереди.
	var strava_dir := "res://src/integrations/strava/"
	var dir := DirAccess.open(strava_dir)
	var writers: Array[String] = []
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string(strava_dir + f)
		if src.contains("FileAccess.WRITE"):
			writers.append(f)
		if f != "upload_queue.gd":
			assert_false(src.contains("FileAccess.WRITE"), "%s не пишет файлы" % f)
		if f == "strava_oauth.gd":
			for item in ["ITEM_ACCESS_TOKEN", "ITEM_REFRESH_TOKEN", "ITEM_EXPIRES_AT"]:
				assert_true(src.contains(item), "токены адресуются через константы SecureStore (%s)" % item)
			assert_true(src.contains("_store.set_secret") and src.contains("_store.get_secret"), "чтение/запись — через SecureStore")
	assert_eq(writers, ["upload_queue.gd"] as Array[String], "единственный файл на диске — очередь (без токенов)")
	# MemorySecureStore — только память: на диске нет файла хранилища.
	assert_eq(_store.size(), 3)
	assert_false(FileAccess.file_exists(_dir + "secure_store.json"))


func test_req_nfr_05_c1_environment_and_secret_access_only_in_storage_and_integrations() -> void:
	# Крит. 1: «Единственная точка записи/чтения секретов — src/storage/secure_store.gd; поиск по src/
	# обращений к ключам/токенам вне этого модуля и интеграций, использующих его интерфейс, пуст».
	# Решение этапа 6: окружение читается только через SecureStore.read_env().
	var env_hits: Array[String] = []
	var secret_api_hits: Array[String] = []
	var token_key_hits: Array[String] = []
	var api_re := RegEx.create_from_string("\\b(set_secret|get_secret|has_secret|delete_secret|delete_service_secrets|delete_profile_secrets|list_keys)\\(")
	var key_re := RegEx.create_from_string("ITEM_ACCESS_TOKEN|ITEM_REFRESH_TOKEN|ITEM_API_KEY|ITEM_EXPIRES_AT|\"(access_token|refresh_token|client_secret)\"")
	for path in _gd_files("res://src"):
		var in_store := path.begins_with("res://src/storage/secure_store") or path.begins_with("res://src/storage/memory_secure_store") \
				or path.begins_with("res://src/storage/encrypted_file_secure_store")
		var in_integrations := path.begins_with("res://src/integrations/")
		for line in _code_lines(path):
			if line.contains("OS.get_environment(") and path != "res://src/storage/secure_store.gd":
				env_hits.append("%s: %s" % [path, line.strip_edges()])
			if not in_store and not in_integrations:
				if api_re.search(line) != null:
					secret_api_hits.append("%s: %s" % [path, line.strip_edges()])
				if key_re.search(line) != null:
					token_key_hits.append("%s: %s" % [path, line.strip_edges()])
	assert_eq(env_hits, [] as Array[String], "OS.get_environment — только в secure_store.gd")
	assert_eq(secret_api_hits, [] as Array[String], "вызовы SecureStore — только в storage/ и integrations/")
	assert_eq(token_key_hits, [] as Array[String], "ключи токенов — только в storage/ и integrations/")
	assert_true(FileAccess.file_exists("res://src/storage/secure_store.gd"))
	assert_true(_gd_files("res://src/integrations/strava").size() >= 8, "каталог интеграции найден сканером")
