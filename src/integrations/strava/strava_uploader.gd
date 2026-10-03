class_name StravaUploader
extends RefCounted
## Выгрузка FIT в Strava (REQ-STR-02 крит. 1, 3, 4; REQ-STR-03 крит. 1–3; REQ-STR-01 крит. 4).
##
## `upload_fit(bytes, name, description, external_id)`:
## 1. свежий токен через `StravaOAuth.ensure_fresh_token()`;
## 2. multipart `POST /api/v3/uploads`: поля `file` (FIT), `data_type=fit`, `name`,
##    `description`, `external_id`, `trainer=1`, `sport_type=VirtualRide`,
##    `activity_type=VirtualRide`;
## 3. 401 → принудительное обновление токена и один повтор; повторный 401 →
##    `reauth_required` (REQ-STR-01 крит. 4 — для каждого запроса API, включая опрос);
## 4. ответ 201/200 `{id, status, error, activity_id}` → опрос `GET /api/v3/uploads/{id}`
##    (до `max_polls` раз с паузой `poll_interval_sec` через `wait_fn`) до `activity_id`
##    (`done`) или `error` (`failed` с текстом; «duplicate» → `duplicate`, без повторов).
##    Опрос идёт с тем токеном, которым принят POST (после обновления — с новым).
##    Если обработка не завершилась — `uploading` с `upload_id` (очередь опросит позже).
## Сетевые ошибки/5xx → `failed` с `can_retry`; 429 → `can_retry` и `retry_after_sec`
## (в том числе 429 на обновлении токена — REQ-STR-04 крит. 3).

const DEFAULT_API_BASE: String = "https://www.strava.com/api/v3"
const UPLOADS_PATH: String = "uploads"
const DATA_TYPE_FIT: String = "fit"
const SPORT_TYPE: String = "VirtualRide"
const APP_NAME: String = "ovosch-rider"
const TIMEOUT_SEC: float = 30.0
const DEFAULT_MAX_POLLS: int = 10
const DEFAULT_POLL_INTERVAL_SEC: float = 2.0

var api_base: String = DEFAULT_API_BASE
var max_polls: int = DEFAULT_MAX_POLLS
var poll_interval_sec: float = DEFAULT_POLL_INTERVAL_SEC
## Ожидание между опросами `func(sec: float)`; в тестах подменяется.
var wait_fn: Callable

var _transport: HttpTransport
var _oauth: StravaOAuth


func _init(transport: HttpTransport, oauth: StravaOAuth) -> void:
	_transport = transport
	_oauth = oauth
	wait_fn = _default_wait


## Выгрузить FIT. `external_id` — идентификатор заезда (REQ-STR-02 крит. 1).
func upload_fit(fit_bytes: PackedByteArray, name: String, description: String, external_id: String) -> UploadResult:
	if fit_bytes.is_empty():
		return UploadResult.failed("пустой FIT-файл", ApiResult.CODE_BAD_RESPONSE)
	var token_result: ApiResult = await _oauth.ensure_fresh_token()
	if not token_result.ok:
		return _token_failure(token_result)
	var access := str(token_result.data)
	var boundary := make_boundary()
	var fields := {
		"data_type": DATA_TYPE_FIT,
		"name": name,
		"description": description,
		"external_id": external_id,
		"trainer": "1",
		"sport_type": SPORT_TYPE,
		"activity_type": SPORT_TYPE,
	}
	var body := build_multipart(fields, "file", external_id + ".fit", fit_bytes, boundary)
	var url := HttpTransport.build_url(api_base, UPLOADS_PATH)
	var response: HttpResponse = await _transport.request("POST", url, _upload_headers(access, boundary), body, TIMEOUT_SEC)
	if response.status == 401:
		var refreshed: ApiResult = await _oauth.ensure_fresh_token(true)
		if not refreshed.ok:
			return _token_failure(refreshed)
		access = str(refreshed.data)
		response = await _transport.request("POST", url, _upload_headers(access, boundary), body, TIMEOUT_SEC)
		if response.status == 401:
			return UploadResult.failed("требуется повторный вход в Strava", ApiResult.CODE_REAUTH_REQUIRED)
	var failure := _http_failure(response)
	if failure != null:
		return failure
	var payload: Variant = response.json()
	if not (payload is Dictionary):
		return UploadResult.failed("неожиданный ответ Strava на выгрузку", ApiResult.CODE_BAD_RESPONSE)
	var first := interpret_upload_status(payload)
	if first.is_final():
		return first
	return await poll_upload(first.upload_id, access)


## Опрос статуса загрузки до результата или `max_polls` попыток (REQ-STR-02 крит. 3).
## 401 на опросе → одно обновление токена и повтор того же запроса; повторный 401 →
## `reauth_required` (REQ-STR-01 крит. 4).
func poll_upload(upload_id: String, token: String = "") -> UploadResult:
	if upload_id.is_empty():
		return UploadResult.failed("Strava не вернула идентификатор загрузки", ApiResult.CODE_BAD_RESPONSE)
	var access := token
	if access.is_empty():
		var t: ApiResult = await _oauth.ensure_fresh_token()
		if not t.ok:
			return _token_failure(t, upload_id)
		access = str(t.data)
	var url := HttpTransport.build_url(api_base, UPLOADS_PATH + "/" + upload_id)
	var headers := StravaOAuth.bearer_headers(access)
	var refreshed_once := false
	for i in max_polls:
		if i > 0:
			await wait_fn.call(poll_interval_sec)
		var response: HttpResponse = await _transport.request("GET", url, headers, PackedByteArray(), TIMEOUT_SEC)
		if response.status == 401 and not refreshed_once:
			refreshed_once = true
			var refreshed: ApiResult = await _oauth.ensure_fresh_token(true)
			if not refreshed.ok:
				return _token_failure(refreshed, upload_id)
			headers = StravaOAuth.bearer_headers(str(refreshed.data))
			response = await _transport.request("GET", url, headers, PackedByteArray(), TIMEOUT_SEC)
		var failure := _http_failure(response)
		if failure != null:
			failure.upload_id = upload_id
			if failure.code == ApiResult.CODE_REAUTH_REQUIRED:
				return failure
			# Выгрузка уже принята (201 с `id`): ошибка HTTP при опросе — не вердикт Strava,
			# заезд остаётся «обрабатывается», очередь опросит по `upload_id` позже
			# (REQ-STR-02 крит. 3, REQ-STR-05 крит. 1); повторного POST не будет.
			return _still_processing(upload_id, failure.error, failure.retry_after_sec)
		var payload: Variant = response.json()
		if not (payload is Dictionary):
			return _still_processing(upload_id, "неожиданный ответ Strava о статусе загрузки", 0)
		var result := interpret_upload_status(payload)
		if result.is_final():
			return result
	return UploadResult.uploading(upload_id)


## Ответ `/uploads` → статус: `activity_id` → done; `error` с «duplicate» → duplicate;
## иной `error` → failed (без повтора); иначе uploading (REQ-STR-02 крит. 3, 4).
static func interpret_upload_status(payload: Dictionary) -> UploadResult:
	var upload_id := _id_text(payload.get("id", ""))
	var error := str(payload.get("error", "")) if payload.get("error") != null else ""
	var activity: Variant = payload.get("activity_id")
	if activity != null and not _id_text(activity).is_empty() and _id_text(activity) != "0":
		return UploadResult.done(_id_text(activity), upload_id)
	if not error.is_empty():
		if error.to_lower().contains("duplicate"):
			return UploadResult.duplicate_of(error, upload_id)
		var rejected := UploadResult.failed(error, ApiResult.CODE_BAD_RESPONSE, false, upload_id)
		rejected.detail = error
		return rejected
	return UploadResult.uploading(upload_id)


## Тело multipart/form-data: текстовые поля, затем файл (REQ-STR-02 крит. 1).
static func build_multipart(fields: Dictionary, file_field: String, file_name: String,
		file_bytes: PackedByteArray, boundary: String) -> PackedByteArray:
	var out := PackedByteArray()
	for k in fields.keys():
		out.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % [boundary, str(k), str(fields[k])]).to_utf8_buffer())
	out.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: application/octet-stream\r\n\r\n" % [boundary, file_field, file_name]).to_utf8_buffer())
	out.append_array(file_bytes)
	out.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	return out


static func make_boundary() -> String:
	return "----ovoschrider" + Crypto.new().generate_random_bytes(12).hex_encode()


## Название активности (REQ-STR-03 крит. 1): название плана или «Тренировка <дата>».
static func default_name(plan_name: String, date_text: String, template: String = "Тренировка %s") -> String:
	var n := plan_name.strip_edges()
	return n if not n.is_empty() else template % date_text


## Описание (REQ-STR-03 крит. 2): описание плана + строка с названием приложения.
static func default_description(plan_description: String, app_line: String = "Записано в " + APP_NAME) -> String:
	var d := plan_description.strip_edges()
	return (d + "\n\n" + app_line) if not d.is_empty() else app_line


static func activity_url(activity_id: String) -> String:
	return StravaBranding.activity_url(activity_id)


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

static func _upload_headers(token: String, boundary: String) -> Dictionary:
	return StravaOAuth.bearer_headers(token, {"Content-Type": "multipart/form-data; boundary=" + boundary})


## Ошибка получения токена → `failed` с сохранением `retry_after_sec` (429 на обновлении —
## REQ-STR-04 крит. 3).
static func _token_failure(t: ApiResult, upload_id: String = "") -> UploadResult:
	var r := UploadResult.failed(t.message, t.code, t.can_retry, upload_id)
	r.retry_after_sec = t.retry_after_sec
	return r


## Ошибка HTTP → UploadResult или null, если ответ пригоден для разбора.
static func _http_failure(response: HttpResponse) -> UploadResult:
	if response.is_transport_error():
		return UploadResult.failed("нет связи со Strava", ApiResult.CODE_NETWORK, true)
	if response.status == 401:
		return UploadResult.failed("требуется повторный вход в Strava", ApiResult.CODE_REAUTH_REQUIRED)
	if response.status == 429:
		var r := UploadResult.failed("слишком много запросов к Strava", ApiResult.CODE_RATE_LIMITED, true)
		var raw := response.header("retry-after").strip_edges()
		r.retry_after_sec = maxi(raw.to_int(), 1) if raw.is_valid_int() else 60
		return r
	if response.status >= 500:
		return UploadResult.failed("Strava недоступна (HTTP %d)" % response.status, ApiResult.CODE_NETWORK, true)
	if not response.ok():
		var payload: Variant = response.json()
		var text := "Strava отклонила выгрузку (HTTP %d)" % response.status
		var server_message := ""
		if payload is Dictionary and (payload as Dictionary).has("message"):
			server_message = str((payload as Dictionary)["message"])
			text += ": " + server_message
		var rejected := UploadResult.failed(text, ApiResult.CODE_BAD_RESPONSE)
		rejected.detail = server_message
		return rejected
	return null


## `uploading` с текстом последней ошибки опроса и паузой по `Retry-After` (429).
static func _still_processing(upload_id: String, error: String, retry_after_sec: int) -> UploadResult:
	var r := UploadResult.uploading(upload_id)
	r.error = error
	r.retry_after_sec = retry_after_sec
	return r


static func _id_text(v: Variant) -> String:
	if v is float:
		return str(int(v))
	return str(v) if v != null else ""


func _default_wait(sec: float) -> void:
	var loop := Engine.get_main_loop()
	if loop is SceneTree and sec > 0.0:
		await (loop as SceneTree).create_timer(sec).timeout
