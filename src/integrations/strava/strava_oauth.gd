class_name StravaOAuth
extends RefCounted
## OAuth 2.0 Strava: URL авторизации, приём redirect, обмен кода, обновление и отзыв
## токенов (REQ-STR-01 крит. 1–8; REQ-PRF-03 крит. 1, 2; REQ-NFR-05 крит. 1, 2).
##
## Токены живут только в `SecureStore` под ключами
## `SecureStore.key_for(profile_id, SERVICE_STRAVA, ITEM_ACCESS_TOKEN|ITEM_REFRESH_TOKEN|ITEM_EXPIRES_AT)`;
## в полях класса не хранятся, в сообщениях и `_to_string()` не появляются.
##
## Redirect (решение В-6): на десктопе — loopback `http://127.0.0.1:<port>/callback` через
## временный сервер на `TCPServer` (`start_loopback_listener` → `poll_listener` раз в кадр →
## `stop_listener`); он принимает один запрос `GET /callback?code=&state=`, отвечает страницей
## «можно закрыть окно», проверяет `state` и останавливается сразу после кода или через 60 с.
## На мобильных — схема `ovoschrider://strava`; URL из системы передаётся в
## `handle_redirect_url(url)`.
##
## Обновление токена: если до `expires_at` меньше 60 с (решение 18) — `grant_type=refresh_token`,
## новые токены перезаписывают старые. 401 при обновлении → `reauth_required`
## (привязка «требуется повторный вход»), токены остаются до отзыва/повторного входа.
## `is_connected` занят `Object`, поэтому состояние привязки — `is_authorized()`.

const DEFAULT_BASE_URL: String = "https://www.strava.com"
const AUTHORIZE_PATH: String = "oauth/authorize"
const TOKEN_PATH: String = "oauth/token"
const DEAUTHORIZE_PATH: String = "oauth/deauthorize"
const SCOPE: String = "activity:write,read"
const MOBILE_REDIRECT_URI: String = "ovoschrider://strava"
const LOOPBACK_HOST: String = "127.0.0.1"
const LOOPBACK_PATH: String = "/callback"
const LOOPBACK_TIMEOUT_SEC: int = 60
const DEFAULT_PORT_FROM: int = 49152
const DEFAULT_PORT_TO: int = 49252
## Обновлять токен, если до истечения осталось меньше этого (решение 18).
const REFRESH_MARGIN_SEC: int = 60
const TIMEOUT_SEC: float = 15.0
const MAX_REQUEST_BYTES: int = 16384

## Код авторизации принят loopback-сервером или из URL схемы.
signal authorization_code_received(code: String)
## Приём redirect не удался: `state_mismatch`, `access_denied`, `timeout`, `bad_request`.
signal authorization_failed(reason: String)

var base_url: String = DEFAULT_BASE_URL
## Часы `func() -> int` (unix-секунды) — подменяются в тестах.
var clock_fn: Callable
## Ожидаемый `state` (из последнего `authorize_url`).
var expected_state: String = ""

var _transport: HttpTransport
var _store: SecureStore
var _profile_id: String
var _config: StravaConfig
var _server: TCPServer = null
var _peer: StreamPeerTCP = null
var _buffer: PackedByteArray = PackedByteArray()
var _port: int = 0
var _listener_started_at: int = 0


func _init(transport: HttpTransport, secure_store: SecureStore, profile_id: String, config: StravaConfig) -> void:
	_transport = transport
	_store = secure_store
	_profile_id = profile_id
	_config = config
	clock_fn = func() -> int: return int(Time.get_unix_time_from_system())


func profile_id() -> String:
	return _profile_id


func config() -> StravaConfig:
	return _config


# ---------------------------------------------------------------------------
# Ключи хранилища и состояние
# ---------------------------------------------------------------------------

func secret_key(item: String) -> String:
	return SecureStore.key_for(_profile_id, SecureStore.SERVICE_STRAVA, item)


## Привязка есть: сохранён refresh_token (REQ-STR-01 крит. 2).
func is_authorized() -> bool:
	return _store.has_secret(secret_key(SecureStore.ITEM_REFRESH_TOKEN))


## Время истечения access_token (unix-секунды); 0 — нет.
func expires_at() -> int:
	var raw := _store.get_secret(secret_key(SecureStore.ITEM_EXPIRES_AT))
	return raw.to_int() if raw.is_valid_int() else 0


## Текущий access_token без проверки свежести (для заголовка после `ensure_fresh_token`).
func access_token() -> String:
	return _store.get_secret(secret_key(SecureStore.ITEM_ACCESS_TOKEN))


## Заголовки запроса к API с токеном (единственное место формирования `Authorization`
## для Strava). `extra` — дополнительные заголовки (например Content-Type multipart).
static func bearer_headers(token: String, extra: Dictionary = {}) -> Dictionary:
	var headers := {"Authorization": "Bearer " + token, "Accept": "application/json"}
	for k in extra.keys():
		headers[k] = extra[k]
	return headers


# ---------------------------------------------------------------------------
# URL авторизации и приём redirect
# ---------------------------------------------------------------------------

## URL авторизации (REQ-STR-01 крит. 1). `redirect_uri` по умолчанию — активный loopback
## либо мобильная схема. Пустой `state` → генерируется.
func authorize_url(state: String = "", redirect_uri: String = "") -> String:
	expected_state = state if not state.is_empty() else generate_state()
	var uri := redirect_uri if not redirect_uri.is_empty() else current_redirect_uri()
	return HttpTransport.build_url(base_url, AUTHORIZE_PATH, {
		"client_id": _config.client_id,
		"redirect_uri": uri,
		"response_type": "code",
		"approval_prompt": "auto",
		"scope": SCOPE,
		"state": expected_state,
	})


## Действующий redirect_uri: loopback, если слушатель запущен, иначе мобильная схема.
func current_redirect_uri() -> String:
	if _server != null and _port > 0:
		return "http://%s:%d%s" % [LOOPBACK_HOST, _port, LOOPBACK_PATH]
	return MOBILE_REDIRECT_URI


static func generate_state() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


## Запустить временный HTTP-сервер на первом свободном порту диапазона; возвращает
## redirect_uri (REQ-STR-01 крит. 7) или "" при неудаче.
func start_loopback_listener(port_from: int = DEFAULT_PORT_FROM, port_to: int = DEFAULT_PORT_TO) -> String:
	stop_listener()
	var server := TCPServer.new()
	for port in range(port_from, port_to + 1):
		if server.listen(port, LOOPBACK_HOST) == OK:
			_server = server
			_port = port
			_listener_started_at = int(clock_fn.call())
			return current_redirect_uri()
	return ""


func is_listening() -> bool:
	return _server != null


func listener_port() -> int:
	return _port


func stop_listener() -> void:
	if _peer != null:
		_peer.disconnect_from_host()
		_peer = null
	if _server != null:
		_server.stop()
		_server = null
	_port = 0
	_buffer = PackedByteArray()


## Опрос слушателя (вызывать каждый кадр). Пустой словарь — ждём; `{code, state}` — код
## принят (сервер остановлен); `{error}` — отказ (`timeout`, `state_mismatch`,
## `access_denied`, `bad_request`), сервер остановлен.
func poll_listener() -> Dictionary:
	if _server == null:
		return {}
	var now := int(clock_fn.call())
	if now - _listener_started_at >= LOOPBACK_TIMEOUT_SEC:
		stop_listener()
		authorization_failed.emit("timeout")
		return {"error": "timeout"}
	if _peer == null:
		if not _server.is_connection_available():
			return {}
		_peer = _server.take_connection()
		_buffer = PackedByteArray()
	_peer.poll()
	var available := _peer.get_available_bytes()
	if available > 0:
		var chunk: Array = _peer.get_data(available)
		if int(chunk[0]) == OK:
			_buffer.append_array(chunk[1])
	var text := _buffer.get_string_from_utf8()
	if not text.contains("\r\n\r\n") and not text.contains("\n\n"):
		if _buffer.size() > MAX_REQUEST_BYTES or _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED and available == 0:
			_peer.disconnect_from_host()
			_peer = null
		return {}
	var request_line := text.split("\n")[0].strip_edges()
	var parts := request_line.split(" ")
	if parts.size() < 2 or parts[0] != "GET":
		_respond(400, "<html><body><p>Неверный запрос.</p></body></html>")
		return {}
	var parsed := parse_redirect(parts[1])
	if str(parsed["path"]) != LOOPBACK_PATH:
		_respond(404, "<html><body><p>Не найдено.</p></body></html>")
		return {}
	_respond(200, _success_page())
	stop_listener()
	return _accept(parsed["query"])


## Разбор URL/пути redirect: `{path, query: Dictionary}`. Понимает `http://…/callback?code=…`,
## `/callback?code=…` и `ovoschrider://strava?code=…`.
static func parse_redirect(url: String) -> Dictionary:
	var rest := url
	# Фрагмент (`#…`) не входит ни в путь, ни в параметры (RFC 3986) — отрезаем заранее.
	var frag_idx := rest.find("#")
	if frag_idx != -1:
		rest = rest.substr(0, frag_idx)
	var scheme_idx := rest.find("://")
	if scheme_idx != -1:
		rest = rest.substr(scheme_idx + 3)
		var slash := rest.find("/")
		var q := rest.find("?")
		if slash == -1 or (q != -1 and q < slash):
			rest = ("/" + rest.substr(q)) if q != -1 else "/"
		else:
			rest = rest.substr(slash)
	var query := {}
	var path := rest
	var qidx := rest.find("?")
	if qidx != -1:
		path = rest.substr(0, qidx)
		for pair in rest.substr(qidx + 1).split("&", false):
			var eq := pair.find("=")
			var k := pair.substr(0, eq).uri_decode() if eq != -1 else pair.uri_decode()
			var v := pair.substr(eq + 1).uri_decode() if eq != -1 else ""
			query[k] = v
	return {"path": path, "query": query}


## Redirect из системы (мобильная схема или вставленный вручную URL): `{code, state}` или `{error}`.
func handle_redirect_url(url: String) -> Dictionary:
	return _accept(parse_redirect(url)["query"])


func _accept(query: Dictionary) -> Dictionary:
	if query.has("error"):
		var reason := str(query["error"])
		authorization_failed.emit(reason)
		return {"error": reason}
	var code := str(query.get("code", "")).strip_edges()
	var state := str(query.get("state", ""))
	if code.is_empty():
		authorization_failed.emit("bad_request")
		return {"error": "bad_request"}
	if not expected_state.is_empty() and state != expected_state:
		authorization_failed.emit("state_mismatch")
		return {"error": "state_mismatch"}
	authorization_code_received.emit(code)
	return {"code": code, "state": state}


func _respond(status: int, html: String) -> void:
	if _peer == null:
		return
	var reason := "OK" if status == 200 else ("Not Found" if status == 404 else "Bad Request")
	var body := html.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, reason, body.size()]
	_peer.put_data(head.to_utf8_buffer())
	_peer.put_data(body)
	_peer.poll()
	_peer.disconnect_from_host()
	_peer = null
	_buffer = PackedByteArray()


static func _success_page() -> String:
	return "<!doctype html><html lang=\"ru\"><head><meta charset=\"utf-8\"><title>ovosch-rider</title></head>" \
			+ "<body style=\"font-family:sans-serif;text-align:center;padding:3em\">" \
			+ "<h1>Strava подключена</h1><p>Можно закрыть это окно и вернуться в ovosch-rider.</p></body></html>"


# ---------------------------------------------------------------------------
# Токены
# ---------------------------------------------------------------------------

## Обмен кода на токены (REQ-STR-01 крит. 2). `data`: `{athlete_id, athlete_name, expires_at, scope}`.
func exchange_code(code: String) -> ApiResult:
	if not _config.is_configured():
		return ApiResult.failure(ApiResult.CODE_NOT_CONFIGURED, _config.unavailable_message())
	if code.strip_edges().is_empty():
		return ApiResult.failure(ApiResult.CODE_BAD_RESPONSE, "пустой код авторизации")
	var result: ApiResult = await _post_form(TOKEN_PATH, {
		"client_id": _config.client_id,
		"client_secret": _config.client_secret(),
		"code": code.strip_edges(),
		"grant_type": "authorization_code",
	})
	if not result.ok:
		if result.code == ApiResult.CODE_AUTH_FAILED or result.status == 400:
			return ApiResult.failure(ApiResult.CODE_AUTH_FAILED, "Strava не приняла код авторизации", result.status)
		return result
	if not _store_tokens(result.data):
		return ApiResult.failure(ApiResult.CODE_BAD_RESPONSE, "в ответе Strava нет токенов", result.status)
	var payload: Dictionary = result.data
	var athlete: Variant = payload.get("athlete", {})
	var info := {
		"athlete_id": _id_text((athlete as Dictionary).get("id", "")) if athlete is Dictionary else "",
		"athlete_name": ("%s %s" % [str((athlete as Dictionary).get("firstname", "")), str((athlete as Dictionary).get("lastname", ""))]).strip_edges() if athlete is Dictionary else "",
		"expires_at": expires_at(),
		"scope": str(payload.get("scope", "")),
	}
	return ApiResult.success(info)


## Свежий access_token (REQ-STR-01 крит. 3): `data` — токен. Обновление, если до истечения
## < 60 с. Нет привязки → `reauth_required`; 401/400 при обновлении → `reauth_required`;
## сеть → `network`.
func ensure_fresh_token(force_refresh: bool = false) -> ApiResult:
	if not is_authorized():
		return ApiResult.failure(ApiResult.CODE_REAUTH_REQUIRED, "Strava не привязана — выполните вход")
	var now := int(clock_fn.call())
	var token := access_token()
	if not force_refresh and not token.is_empty() and expires_at() - now >= REFRESH_MARGIN_SEC:
		return ApiResult.success(token)
	return await refresh_token()


## Принудительное обновление по refresh_token (REQ-STR-01 крит. 3, 4).
func refresh_token() -> ApiResult:
	if not _config.is_configured():
		return ApiResult.failure(ApiResult.CODE_NOT_CONFIGURED, _config.unavailable_message())
	var refresh := _store.get_secret(secret_key(SecureStore.ITEM_REFRESH_TOKEN))
	if refresh.is_empty():
		return ApiResult.failure(ApiResult.CODE_REAUTH_REQUIRED, "Strava не привязана — выполните вход")
	var result: ApiResult = await _post_form(TOKEN_PATH, {
		"client_id": _config.client_id,
		"client_secret": _config.client_secret(),
		"grant_type": "refresh_token",
		"refresh_token": refresh,
	})
	if not result.ok:
		if result.code == ApiResult.CODE_AUTH_FAILED or result.status == 400:
			return ApiResult.failure(ApiResult.CODE_REAUTH_REQUIRED, "требуется повторный вход в Strava", result.status)
		return result
	if not _store_tokens(result.data):
		return ApiResult.failure(ApiResult.CODE_BAD_RESPONSE, "в ответе Strava нет токенов", result.status)
	return ApiResult.success(access_token())


## Отвязка (REQ-STR-01 крит. 8): `POST /oauth/deauthorize`, затем удаление всех токенов
## профиля независимо от ответа сети (локально привязка снимается всегда).
func revoke() -> ApiResult:
	var token := access_token()
	var result := ApiResult.success(null)
	if not token.is_empty():
		result = await _post_form(DEAUTHORIZE_PATH, {"access_token": token})
	_store.delete_service_secrets(_profile_id, SecureStore.SERVICE_STRAVA)
	if result.ok or result.code == ApiResult.CODE_AUTH_FAILED:
		return ApiResult.success(null)
	return result


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _store_tokens(payload: Variant) -> bool:
	if not (payload is Dictionary):
		return false
	var p: Dictionary = payload
	var access := str(p.get("access_token", ""))
	var refresh := str(p.get("refresh_token", ""))
	var exp: Variant = p.get("expires_at", 0)
	if access.is_empty() or refresh.is_empty():
		return false
	var exp_sec := roundi(float(exp)) if (exp is float or exp is int) else (str(exp).to_int() if str(exp).is_valid_int() else 0)
	_store.set_secret(secret_key(SecureStore.ITEM_ACCESS_TOKEN), access)
	_store.set_secret(secret_key(SecureStore.ITEM_REFRESH_TOKEN), refresh)
	_store.set_secret(secret_key(SecureStore.ITEM_EXPIRES_AT), str(exp_sec))
	return true


func _post_form(path: String, fields: Dictionary) -> ApiResult:
	var parts: Array[String] = []
	for k in fields.keys():
		parts.append("%s=%s" % [str(k).uri_encode(), str(fields[k]).uri_encode()])
	var body := "&".join(parts).to_utf8_buffer()
	var headers := {"Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"}
	var response: HttpResponse = await _transport.request("POST", HttpTransport.build_url(base_url, path), headers, body, TIMEOUT_SEC)
	if response.is_transport_error():
		return ApiResult.failure(ApiResult.CODE_NETWORK, "нет связи со Strava", 0, true)
	if response.status == 401 or response.status == 403:
		return ApiResult.failure(ApiResult.CODE_AUTH_FAILED, "Strava отклонила запрос (HTTP %d)" % response.status, response.status)
	if response.status == 429:
		var r := ApiResult.failure(ApiResult.CODE_RATE_LIMITED, "слишком много запросов к Strava", 429, true)
		r.retry_after_sec = _retry_after(response)
		return r
	if response.status >= 500:
		return ApiResult.failure(ApiResult.CODE_NETWORK, "Strava недоступна (HTTP %d)" % response.status, response.status, true)
	var data: Variant = response.json()
	if not response.ok():
		return ApiResult.failure(ApiResult.CODE_BAD_RESPONSE, "неожиданный ответ Strava (HTTP %d)" % response.status, response.status)
	if data == null:
		return ApiResult.failure(ApiResult.CODE_BAD_RESPONSE, "ответ Strava не является JSON", response.status)
	var ok := ApiResult.success(data)
	ok.status = response.status
	return ok


static func _retry_after(response: HttpResponse) -> int:
	var raw := response.header("retry-after").strip_edges()
	if raw.is_valid_int():
		return maxi(raw.to_int(), 1)
	return 60


static func _id_text(v: Variant) -> String:
	if v is float:
		return str(int(v))
	return str(v)


func _to_string() -> String:
	return "StravaOAuth(profile=%s, authorized=%s, tokens=***)" % [_profile_id, str(is_authorized())]
