class_name ApiResult
extends RefCounted
## Результат операции клиента Intervals.icu / сервиса плана (REQ-INT-01, REQ-INT-02, REQ-INT-07).
##
## `ok` — операция удалась (включая «на сегодня тренировок нет» и «из кэша»).
## `code` — стабильный код для UI/локализации; `message` — текст на русском без
## секретов (REQ-INT-01 крит. 2). `data` — полезная нагрузка (зависит от метода).

const CODE_OK: String = "ok"
## Запрос удался, но тренировок на сегодня нет (REQ-INT-02 крит. 3).
const CODE_NO_WORKOUT_TODAY: String = "no_workout_today"
## План отдан из кэша из-за недоступной сети (REQ-INT-07 крит. 2).
const CODE_FROM_CACHE: String = "from_cache"
## Ключ не принят: 401/403 (REQ-INT-01 крит. 3).
const CODE_AUTH_FAILED: String = "auth_failed"
## Сеть/таймаут/5xx — «не удалось загрузить план», можно повторить (REQ-INT-02 крит. 4).
const CODE_NETWORK: String = "network"
## 429 и после повтора снова 429 — повторить не раньше `retry_after_sec` (REQ-INT-02 крит. 5).
const CODE_RATE_LIMITED: String = "rate_limited"
## Нет ключа API или Athlete ID — запросы не выполняются.
const CODE_NOT_CONFIGURED: String = "not_configured"
## Ответ сервера не разобран (не JSON, неожиданная структура, прочие 4xx).
const CODE_BAD_RESPONSE: String = "bad_response"
## Привязка требует повторного входа: обновление токена отклонено (REQ-STR-01 крит. 4).
const CODE_REAUTH_REQUIRED: String = "reauth_required"
## Защищённое хранилище не приняло секрет (не прочитано — `SecureStore.loaded_ok() == false`,
## или ошибка записи на диск — `SecureStore.last_error()`). Привязка не состоялась.
const CODE_STORAGE_FAILED: String = "storage_failed"

var ok: bool = false
var code: String = CODE_OK
var message: String = ""
## HTTP-статус последнего ответа (0 — ответа не было).
var status: int = 0
var data: Variant = null
## Для `rate_limited`: через сколько секунд повторять.
var retry_after_sec: int = 0
## Имеет смысл кнопка «повторить».
var can_retry: bool = false
## Данные взяты из кэша.
var from_cache: bool = false
## Время загрузки данных (unix-секунды) — для пометки «загружен <время>».
var loaded_at: int = 0


static func success(payload: Variant, result_code: String = CODE_OK, text: String = "") -> ApiResult:
	var r := ApiResult.new()
	r.ok = true
	r.code = result_code
	r.message = text
	r.data = payload
	return r


static func failure(result_code: String, text: String, http_status: int = 0, retry: bool = false) -> ApiResult:
	var r := ApiResult.new()
	r.ok = false
	r.code = result_code
	r.message = text
	r.status = http_status
	r.can_retry = retry
	return r


func _to_string() -> String:
	return "ApiResult(%s, ok=%s, status=%d)" % [code, str(ok), status]
