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
## `stop_listener`); он принимает один запрос `GET /callback?code=&state=`, проверяет `state`,
## отвечает страницей по результату («Strava подключена» только при успехе) и
## останавливается сразу после `/callback` или через 60 с. Соединения обслуживаются
## параллельно: «зависшее» (не дослало заголовки, закрылось, молчит дольше 5 с) сбрасывается
## и не мешает настоящему `GET /callback` от браузера (предварительные соединения, favicon).
## На мобильных — схема `ovoschrider://strava`; URL из системы передаётся в
## `handle_redirect_url(url)`.
##
## `state` обязателен: пустой `expected_state` (вход не начинали) — отказ `state_mismatch`;
## после принятого кода или отказа провайдера `state` очищается (повтор того же redirect — отказ).
##
## Обновление токена: если до `expires_at` меньше 60 с (решение 18) — `grant_type=refresh_token`,
## новые токены перезаписывают старые. 401 при обновлении → `reauth_required`
## (привязка «требуется повторный вход»), токены остаются до отзыва/повторного входа.
## `is_connected` занят `Object`, поэтому состояние привязки — `is_authorized()`.
##
## Сбой `SecureStore` при сохранении токенов — `CODE_STORAGE_FAILED` (не success): привязка не
## считается состоявшейся; `SecureStore.loaded_ok()`/`reset_store()` — для UI.
## Отвязка увеличивает поколение (`_unlink_generation`): ответ обмена/обновления токена,
## пришедший после начала `revoke()`, токены не записывает.

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
## Соединение loopback, не приславшее полный запрос за это время (с), сбрасывается.
const PEER_IDLE_TIMEOUT_SEC: int = 5
## Не больше стольких незавершённых соединений одновременно (при переполнении сбрасывается старейшее).
const MAX_PENDING_PEERS: int = 8

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
## Незавершённые соединения: `{peer: StreamPeerTCP, buffer: PackedByteArray, last_activity: int}`.
var _peers: Array[Dictionary] = []
var _port: int = 0
var _listener_started_at: int = 0
## Поколение отвязки: растёт в `revoke()`; ответы, начатые в прошлом поколении, не пишут токены.
var _unlink_generation: int = 0


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
	for entry in _peers:
		(entry["peer"] as StreamPeerTCP).disconnect_from_host()
	_peers.clear()
	if _server != null:
		_server.stop()
		_server = null
	_port = 0


## Число принятых соединений, ещё не приславших полный запрос (диагностика и тесты).
func pending_connection_count() -> int:
	return _peers.size()


## Байт, принятых от незавершённых соединений (диагностика и тесты: дочитаны ли уже
## отправленные клиентом данные — от их прихода отсчитывается простой соединения).
func pending_request_bytes() -> int:
	var total: int = 0
	for entry in _peers:
		total += (entry["buffer"] as PackedByteArray).size()
	return total


## Опрос слушателя (вызывать каждый кадр). Пустой словарь — ждём; `{code, state}` — код
## принят (сервер остановлен); `{error}` — отказ (`timeout`, `state_mismatch`,
## `access_denied`, `bad_request`), сервер остановлен. Чужие пути (`/favicon.ico`) получают
## 404, не-GET — 400; слушатель при этом продолжает ждать.
func poll_listener() -> Dictionary:
	if _server == null:
		return {}
	var now := int(clock_fn.call())
	if now - _listener_started_at >= LOOPBACK_TIMEOUT_SEC:
		stop_listener()
		authorization_failed.emit("timeout")
		return {"error": "timeout"}
	_take_new_connections(now)
	for entry in _peers.duplicate():
		var request := _read_request(entry, now)
		if request.is_empty():
			continue
		_peers.erase(entry)
		var peer: StreamPeerTCP = entry["peer"]
		var request_line := request.split("\n")[0].strip_edges()
		var parts := request_line.split(" ")
		if parts.size() < 2 or parts[0] != "GET":
			_respond(peer, 400, _message_page("Неверный запрос."))
			continue
		var parsed := parse_redirect(parts[1])
		if str(parsed["path"]) != LOOPBACK_PATH:
			_respond(peer, 404, _message_page("Не найдено."))
			continue
		var result := _evaluate(parsed["query"])
		_respond(peer, 200 if result.has("code") or str(result.get("error", "")) == "access_denied" else 400,
				_result_page(result))
		stop_listener()
		_finish_accept(result)
		return result
	return {}


## Принять все ожидающие соединения; при переполнении сбрасывается самое старое.
func _take_new_connections(now: int) -> void:
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer == null:
			break
		if _peers.size() >= MAX_PENDING_PEERS:
			_drop_peer(_peers[0])
		_peers.append({"peer": peer, "buffer": PackedByteArray(), "last_activity": now})


## Дочитать соединение. Полный запрос (заголовки до пустой строки) — его текст; иначе "".
## Закрытое клиентом, ошибочное (`get_available_bytes() < 0`), переполненное или молчащее
## дольше `PEER_IDLE_TIMEOUT_SEC` соединение сбрасывается.
func _read_request(entry: Dictionary, now: int) -> String:
	var peer: StreamPeerTCP = entry["peer"]
	peer.poll()
	# Закрытое клиентом соединение ядро закрывает в `poll()` только когда непрочитанных данных
	# не осталось, поэтому читать его уже нечего (и `get_available_bytes()` на нём — ошибка).
	var available := peer.get_available_bytes() if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED else -1
	var buffer: PackedByteArray = entry["buffer"]
	if available > 0:
		var chunk: Array = peer.get_data(available)
		if int(chunk[0]) == OK and (chunk[1] as PackedByteArray).size() > 0:
			buffer.append_array(chunk[1])
			entry["buffer"] = buffer
			entry["last_activity"] = now
	# Запрос — ASCII (параметры URL-кодированы): без разбора UTF-8 по частичным байтам.
	var text := buffer.get_string_from_ascii()
	if text.contains("\r\n\r\n") or text.contains("\n\n"):
		return text
	var dead := available < 0 or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED
	if dead or buffer.size() > MAX_REQUEST_BYTES or now - int(entry["last_activity"]) >= PEER_IDLE_TIMEOUT_SEC:
		_drop_peer(entry)
	return ""


func _drop_peer(entry: Dictionary) -> void:
	(entry["peer"] as StreamPeerTCP).disconnect_from_host()
	_peers.erase(entry)


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
	var result := _evaluate(parse_redirect(url)["query"])
	_finish_accept(result)
	return result


## Решение по параметрам redirect без побочных эффектов: `{code, state}` или `{error}`.
## Пустой `expected_state` (вход не начинали или `state` уже использован) — `state_mismatch`.
func _evaluate(query: Dictionary) -> Dictionary:
	if query.has("error"):
		return {"error": str(query["error"])}
	var code := str(query.get("code", "")).strip_edges()
	var state := str(query.get("state", ""))
	if code.is_empty():
		return {"error": "bad_request"}
	if expected_state.is_empty() or state != expected_state:
		return {"error": "state_mismatch"}
	return {"code": code, "state": state}


## Сигналы и одноразовость `state`: после принятого кода или отказа провайдера `state` очищается.
func _finish_accept(result: Dictionary) -> void:
	if result.has("code"):
		expected_state = ""
		authorization_code_received.emit(str(result["code"]))
		return
	var reason := str(result.get("error", "bad_request"))
	if reason != "state_mismatch" and reason != "bad_request":
		expected_state = ""
	authorization_failed.emit(reason)


func _respond(peer: StreamPeerTCP, status: int, html: String) -> void:
	var reason := "OK" if status == 200 else ("Not Found" if status == 404 else "Bad Request")
	var body := html.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, reason, body.size()]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(body)
	peer.poll()
	peer.disconnect_from_host()


## Страница браузеру по результату `/callback`: «Strava подключена» — только при принятом коде.
static func _result_page(result: Dictionary) -> String:
	if result.has("code"):
		return _page("Strava подключена", "Можно закрыть это окно и вернуться в ovosch-rider.")
	match str(result.get("error", "")):
		"access_denied":
			return _page("Вход в Strava отменён", "Strava не подключена. Можно закрыть это окно и вернуться в ovosch-rider.")
		"state_mismatch":
			return _page("Strava не подключена", "Ответ не относится к текущему входу. Можно закрыть это окно и начать вход в ovosch-rider заново.")
		_:
			return _page("Strava не подключена", "Ответ Strava не распознан. Можно закрыть это окно и начать вход в ovosch-rider заново.")


static func _message_page(text: String) -> String:
	return "<html><body><p>%s</p></body></html>" % text


static func _page(title: String, text: String) -> String:
	return "<!doctype html><html lang=\"ru\"><head><meta charset=\"utf-8\"><title>ovosch-rider</title></head>" \
			+ "<body style=\"font-family:sans-serif;text-align:center;padding:3em\">" \
			+ "<h1>%s</h1><p>%s</p></body></html>" % [title, text]


# ---------------------------------------------------------------------------
# Токены
# ---------------------------------------------------------------------------

## Обмен кода на токены (REQ-STR-01 крит. 2). `data`: `{athlete_id, athlete_name, expires_at, scope}`.
func exchange_code(code: String) -> ApiResult:
	if not _config.is_configured():
		return ApiResult.failure(ApiResult.CODE_NOT_CONFIGURED, _config.unavailable_message())
	if code.strip_edges().is_empty():
		return ApiResult.failure(ApiResult.CODE_BAD_RESPONSE, "пустой код авторизации")
	var generation := _unlink_generation
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
	if generation != _unlink_generation:
		return ApiResult.failure(ApiResult.CODE_REAUTH_REQUIRED, "вход прерван отвязкой Strava", result.status)
	var stored := _store_tokens(result.data)
	if stored == STORE_BAD_PAYLOAD:
		return ApiResult.failure(ApiResult.CODE_BAD_RESPONSE, "в ответе Strava нет токенов", result.status)
	if stored == STORE_FAILED:
		# Частично записанные токены не должны изображать привязку.
		_store.delete_service_secrets(_profile_id, SecureStore.SERVICE_STRAVA)
		return _storage_failure(result.status)
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
	var generation := _unlink_generation
	var result: ApiResult = await _post_form(TOKEN_PATH, {
		"client_id": _config.client_id,
		"client_secret": _config.client_secret(),
		"grant_type": "refresh_token",
		"refresh_token": refresh,
	})
	if generation != _unlink_generation:
		# Пока шёл запрос, привязку сняли (`revoke`): новые токены не записываются.
		return ApiResult.failure(ApiResult.CODE_REAUTH_REQUIRED, "Strava отвязана — выполните вход", result.status)
	if not result.ok:
		if result.code == ApiResult.CODE_AUTH_FAILED or result.status == 400:
			return ApiResult.failure(ApiResult.CODE_REAUTH_REQUIRED, "требуется повторный вход в Strava", result.status)
		return result
	var stored := _store_tokens(result.data)
	if stored == STORE_BAD_PAYLOAD:
		return ApiResult.failure(ApiResult.CODE_BAD_RESPONSE, "в ответе Strava нет токенов", result.status)
	if stored == STORE_FAILED:
		return _storage_failure(result.status)
	return ApiResult.success(access_token())


## Отвязка (REQ-STR-01 крит. 8): `POST /oauth/deauthorize`, затем удаление всех токенов
## профиля независимо от ответа сети (локально привязка снимается всегда).
func revoke() -> ApiResult:
	# Новое поколение до сетевого запроса: обмен/обновление, начатые раньше, токены не запишут.
	_unlink_generation += 1
	var token := access_token()
	var result := ApiResult.success(null)
	if not token.is_empty():
		result = await _post_form(DEAUTHORIZE_PATH, {"access_token": token})
	_store.delete_service_secrets(_profile_id, SecureStore.SERVICE_STRAVA)
	# И после удаления: обновление, начатое во время запроса отзыва, тоже не воскресит токены.
	_unlink_generation += 1
	if result.ok or result.code == ApiResult.CODE_AUTH_FAILED:
		return ApiResult.success(null)
	return result


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

## Результат `_store_tokens`.
const STORE_OK: int = 0
const STORE_BAD_PAYLOAD: int = 1
const STORE_FAILED: int = 2


## Записать токены из ответа Strava. `STORE_FAILED` — `SecureStore` отказал (не прочитан,
## ошибка диска; код — `_store.last_error()`).
func _store_tokens(payload: Variant) -> int:
	if not (payload is Dictionary):
		return STORE_BAD_PAYLOAD
	var p: Dictionary = payload
	var access := str(p.get("access_token", ""))
	var refresh := str(p.get("refresh_token", ""))
	var exp: Variant = p.get("expires_at", 0)
	if access.is_empty() or refresh.is_empty():
		return STORE_BAD_PAYLOAD
	var exp_sec := roundi(float(exp)) if (exp is float or exp is int) else (str(exp).to_int() if str(exp).is_valid_int() else 0)
	if not _store.set_secret(secret_key(SecureStore.ITEM_ACCESS_TOKEN), access):
		return STORE_FAILED
	if not _store.set_secret(secret_key(SecureStore.ITEM_REFRESH_TOKEN), refresh):
		return STORE_FAILED
	if not _store.set_secret(secret_key(SecureStore.ITEM_EXPIRES_AT), str(exp_sec)):
		return STORE_FAILED
	return STORE_OK


## Ошибка сохранения токенов: код `storage_failed`, текст с кодом ошибки хранилища.
func _storage_failure(status: int) -> ApiResult:
	var why := "хранилище не прочитано" if not _store.loaded_ok() else error_string(_store.last_error())
	return ApiResult.failure(ApiResult.CODE_STORAGE_FAILED,
			"не удалось сохранить токены Strava в защищённое хранилище (%s)" % why, status)


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
