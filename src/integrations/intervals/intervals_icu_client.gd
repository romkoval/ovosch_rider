class_name IntervalsIcuClient
extends RefCounted
## Клиент Intervals.icu по персональному API-ключу (REQ-INT-01, REQ-INT-02, REQ-INT-04 крит. 1–2
## данные, REQ-PRF-03 крит. 1).
##
## Авторизация: `Authorization: Basic base64("API_KEY:<ключ>")` в каждом запросе
## (REQ-INT-01 крит. 1). Ключ живёт только в `SecureStore` под
## `SecureStore.key_for(profile_id, SERVICE_INTERVALS, ITEM_API_KEY)`; клиент не хранит
## его в полях, не логирует и не включает в сообщения об ошибках (крит. 2) —
## `_to_string()` маскирует.
##
## Проверка ключа `verify_key(athlete_id, key)`: запрос профиля атлета с ещё не
## сохранённым ключом; 401/403 → `auth_failed` «ключ не принят», ключ не сохраняется
## (крит. 3); успех → ключ записывается в `SecureStore`, `athlete_id` запоминается.
##
## Ошибки без падений (REQ-INT-02 крит. 4, 5): транспортная ошибка/таймаут/5xx →
## `network` с `can_retry`; 429 → ожидание `Retry-After` (нет заголовка — 60 с,
## открытое решение 19) и один повтор, повторный 429 → `rate_limited`
## с `retry_after_sec`. Ожидание — через `wait_fn(sec)` (в тестах подменяется).
## Таймаут запроса 15 с.
##
## Формат ответов — по публичной документации API (синтетические фикстуры до
## получения реальных, открытое решение 19 / блокер Б-3).

const DEFAULT_BASE_URL: String = "https://intervals.icu"
const TIMEOUT_SEC: float = 15.0
const RETRY_AFTER_DEFAULT_SEC: int = 60
const CATEGORY_WORKOUT: String = "WORKOUT"
## Велосипедные типы событий Intervals.icu (REQ-INT-02 крит. 2).
const BIKE_TYPES: Array[String] = ["Ride", "VirtualRide", "GravelRide", "MountainBikeRide", "EBikeRide", "EMountainBikeRide", "Velomobile", "Handcycle"]

## Ошибка запроса: `code` — из `ApiResult.CODE_*`, `message` без секретов.
signal error(code: String, message: String)

## Базовый URL (для моков и тестовых серверов).
var base_url: String = DEFAULT_BASE_URL
## Athlete ID Intervals.icu (например `i12345`); хранится в профиле, здесь — копия.
var athlete_id: String = ""
## Ожидание `sec` секунд при 429: `func(sec: float) -> void` (может быть корутиной).
var wait_fn: Callable
## Ожидания при 429 (секунды) — для диагностики и тестов.
var waits: Array[int] = []

var _transport: HttpTransport
var _store: SecureStore
var _profile_id: String


func _init(transport: HttpTransport, secure_store: SecureStore, profile_id: String) -> void:
	_transport = transport
	_store = secure_store
	_profile_id = profile_id
	wait_fn = _default_wait


## Клиент для профиля: Athlete ID берётся из `profile.intervals_athlete_id`.
static func for_profile(transport: HttpTransport, secure_store: SecureStore, profile: Profile) -> IntervalsIcuClient:
	var c := IntervalsIcuClient.new(transport, secure_store, profile.id)
	c.athlete_id = profile.intervals_athlete_id
	return c


func profile_id() -> String:
	return _profile_id


## Ключ хранилища для API-ключа этого профиля (REQ-PRF-03 крит. 1).
func secret_key() -> String:
	return SecureStore.key_for(_profile_id, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY)


func has_api_key() -> bool:
	return _store.has_secret(secret_key())


## Привязка к Intervals.icu есть (ключ сохранён) — синоним для UI без упоминания секретов (REQ-NFR-05).
func is_linked() -> bool:
	return has_api_key()


## Клиент готов к запросам: есть ключ и Athlete ID.
func is_configured() -> bool:
	return has_api_key() and not athlete_id.strip_edges().is_empty()


## Удалить привязку: только ключ Intervals.icu этого профиля (REQ-PRF-03 крит. 2).
func forget_key() -> void:
	_store.delete_service_secrets(_profile_id, SecureStore.SERVICE_INTERVALS)


## Сегодняшняя локальная дата устройства `YYYY-MM-DD` (REQ-INT-02 крит. 1).
static func local_date() -> String:
	return Time.get_date_string_from_system(false)


# ---------------------------------------------------------------------------
# Публичные операции
# ---------------------------------------------------------------------------

## Проверить ключ запросом профиля атлета. Успех → ключ сохранён в `SecureStore`,
## `data` — разобранный атлет (`IntervalsSync.parse_athlete`). 401/403 → `auth_failed`,
## ключ не сохраняется (REQ-INT-01 крит. 3).
func verify_key(new_athlete_id: String, key: String) -> ApiResult:
	var aid := new_athlete_id.strip_edges()
	var k := key.strip_edges()
	if aid.is_empty() or k.is_empty():
		return ApiResult.failure(ApiResult.CODE_NOT_CONFIGURED, "введите Athlete ID и ключ API")
	var result: ApiResult = await _request_get("api/v1/athlete/%s" % aid, {}, k)
	if result.code == ApiResult.CODE_AUTH_FAILED:
		result.message = "ключ не принят"
		return result
	if not result.ok:
		return result
	if not (result.data is Dictionary):
		return ApiResult.failure(ApiResult.CODE_BAD_RESPONSE, "неожиданный ответ сервера", result.status)
	if not _store.set_secret(secret_key(), k):
		return ApiResult.failure(ApiResult.CODE_BAD_RESPONSE, "не удалось сохранить ключ в защищённое хранилище")
	athlete_id = aid
	result.data = IntervalsSync.parse_athlete(result.data)
	return result


## Профиль атлета: `data` — словарь `IntervalsSync.parse_athlete` (FTP, зоны, max_hr…).
func get_athlete() -> ApiResult:
	var result: ApiResult = await _request_get("api/v1/athlete/%s" % athlete_id)
	if result.ok:
		if not (result.data is Dictionary):
			return ApiResult.failure(ApiResult.CODE_BAD_RESPONSE, "неожиданный ответ сервера", result.status)
		result.data = IntervalsSync.parse_athlete(result.data)
	return result


## События календаря за период (включительно), категория WORKOUT: `data` — массив словарей.
func get_events(date_from: String, date_to: String) -> ApiResult:
	var result: ApiResult = await _request_get("api/v1/athlete/%s/events" % athlete_id,
			{"oldest": date_from, "newest": date_to, "category": CATEGORY_WORKOUT})
	if result.ok and not (result.data is Array):
		return ApiResult.failure(ApiResult.CODE_BAD_RESPONSE, "неожиданный ответ сервера: ожидался список событий", result.status)
	return result


## Велосипедные тренировки на сегодня (REQ-INT-02 крит. 1–3), разобранные в `Workout`.
## `data` — `Array[Dictionary]` `{event_id, name, start_date_local, type, duration_sec,
## training_load, workout: Workout|null, parse_result: ParseResult}`; записи с ошибкой
## разбора остаются в списке с `workout == null`, чтобы UI показал причину.
## Пустой список → `ok`, `code == no_workout_today`.
func get_today_workouts(today: String = "") -> ApiResult:
	var date := today if not today.is_empty() else local_date()
	var result: ApiResult = await get_events(date, date)
	if not result.ok:
		return result
	var entries: Array[Dictionary] = []
	for item in result.data:
		if not (item is Dictionary):
			continue
		var event: Dictionary = item
		if not is_bike_workout(event):
			continue
		entries.append(entry_from_event(event))
	if entries.is_empty():
		return ApiResult.success(entries, ApiResult.CODE_NO_WORKOUT_TODAY, "на сегодня тренировок нет")
	return ApiResult.success(entries)


## Событие — запланированная велотренировка (REQ-INT-02 крит. 2).
static func is_bike_workout(event: Dictionary) -> bool:
	if str(event.get("category", "")).to_upper() != CATEGORY_WORKOUT:
		return false
	return BIKE_TYPES.has(str(event.get("type", "")))


## Запись списка тренировок из события календаря.
static func entry_from_event(event: Dictionary) -> Dictionary:
	var parsed := IntervalsIcuWorkoutParser.parse(event)
	var duration := 0
	if parsed.workout != null:
		duration = parsed.workout.total_duration_sec()
	elif event.get("moving_time") is float or event.get("moving_time") is int:
		duration = roundi(float(event["moving_time"]))
	var load: Variant = event.get("icu_training_load")
	return {
		"event_id": _id_text(event.get("id", "")),
		"name": str(event.get("name", "")),
		"start_date_local": str(event.get("start_date_local", "")),
		"type": str(event.get("type", "")),
		"duration_sec": duration,
		"training_load": roundi(float(load)) if (load is float or load is int) else 0,
		"workout": parsed.workout,
		"parse_result": parsed,
	}


## Идентификатор события как текст: из JSON числа приходят float (2001.0 → "2001").
static func _id_text(v: Variant) -> String:
	if v is float:
		return str(int(v)) if is_equal_approx(v, floorf(v)) else str(v)
	return str(v) if v != null else ""


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

## GET с авторизацией, обработкой 401/403, 429 (один повтор), 5xx и транспортных ошибок.
## `key_override` — ещё не сохранённый ключ при проверке.
func _request_get(path: String, query: Dictionary = {}, key_override: String = "") -> ApiResult:
	var key := key_override if not key_override.is_empty() else _store.get_secret(secret_key())
	if key.is_empty():
		return _fail(ApiResult.CODE_NOT_CONFIGURED, "ключ API Intervals.icu не задан")
	if key_override.is_empty() and athlete_id.strip_edges().is_empty():
		return _fail(ApiResult.CODE_NOT_CONFIGURED, "Athlete ID Intervals.icu не задан")
	var url := HttpTransport.build_url(base_url, path, query)
	var headers := {
		"Authorization": "Basic " + Marshalls.utf8_to_base64("API_KEY:" + key),
		"Accept": "application/json",
	}
	var response: HttpResponse = await _transport.request("GET", url, headers, PackedByteArray(), TIMEOUT_SEC)
	if response.status == 429:
		var wait_sec := _retry_after(response)
		waits.append(wait_sec)
		await wait_fn.call(float(wait_sec))
		response = await _transport.request("GET", url, headers, PackedByteArray(), TIMEOUT_SEC)
		if response.status == 429:
			var again := _retry_after(response)
			var limited := _fail(ApiResult.CODE_RATE_LIMITED, "слишком много запросов, повторите через %d с" % again, 429, true)
			limited.retry_after_sec = again
			return limited
	return _to_result(response)


func _to_result(response: HttpResponse) -> ApiResult:
	if response.is_transport_error():
		var why := "превышено время ожидания" if response.error == HttpResponse.ERR_TIMEOUT else "сеть недоступна"
		return _fail(ApiResult.CODE_NETWORK, "не удалось загрузить план: %s" % why, 0, true)
	if response.status == 401 or response.status == 403:
		return _fail(ApiResult.CODE_AUTH_FAILED, "ключ не принят (HTTP %d)" % response.status, response.status)
	if response.status >= 500:
		return _fail(ApiResult.CODE_NETWORK, "не удалось загрузить план: сервер недоступен (HTTP %d)" % response.status, response.status, true)
	if not response.ok():
		return _fail(ApiResult.CODE_BAD_RESPONSE, "неожиданный ответ сервера (HTTP %d)" % response.status, response.status)
	var data: Variant = response.json()
	if data == null:
		return _fail(ApiResult.CODE_BAD_RESPONSE, "ответ сервера не является JSON", response.status)
	var result := ApiResult.success(data)
	result.status = response.status
	result.loaded_at = int(Time.get_unix_time_from_system())
	return result


func _fail(code: String, message: String, status: int = 0, retry: bool = false) -> ApiResult:
	error.emit(code, message)
	return ApiResult.failure(code, message, status, retry)


## Значение `Retry-After` (секунды) или 60 по умолчанию (открытое решение 19).
static func _retry_after(response: HttpResponse) -> int:
	var raw := response.header("retry-after").strip_edges()
	if raw.is_valid_int():
		return maxi(raw.to_int(), 1)
	if raw.is_valid_float():
		return maxi(ceili(raw.to_float()), 1)
	return RETRY_AFTER_DEFAULT_SEC


## Ожидание по умолчанию: таймер главного цикла, если он есть; иначе без ожидания.
func _default_wait(sec: float) -> void:
	var loop := Engine.get_main_loop()
	if loop is SceneTree and sec > 0.0:
		await (loop as SceneTree).create_timer(sec).timeout


func _to_string() -> String:
	return "IntervalsIcuClient(profile=%s, athlete=%s, key=%s)" % [_profile_id, athlete_id, "***" if has_api_key() else "нет"]
