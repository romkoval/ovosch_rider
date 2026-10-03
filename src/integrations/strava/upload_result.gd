class_name UploadResult
extends RefCounted
## Результат выгрузки в Strava и словарь статусов заезда (REQ-STR-02 крит. 3, 4; REQ-STR-05 крит. 1).
##
## Статусы заезда (`STATUS_*`): `none` — не выгружен, `queued` — в очереди,
## `uploading` — обрабатывается (отправлен или ждёт обработки на стороне Strava),
## `done` — выгружено (`activity_id`), `failed` — ошибка (`error`), `duplicate` — дубликат.
## `code` — причина для очереди: `network`/`rate_limited` → повтор, `reauth_required`,
## `bad_response`, `not_configured` → без повтора.

const STATUS_NONE: String = "none"
const STATUS_QUEUED: String = "queued"
const STATUS_UPLOADING: String = "uploading"
const STATUS_DONE: String = "done"
const STATUS_FAILED: String = "failed"
const STATUS_DUPLICATE: String = "duplicate"
const STATUSES: Array[String] = [STATUS_NONE, STATUS_QUEUED, STATUS_UPLOADING, STATUS_DONE, STATUS_FAILED, STATUS_DUPLICATE]

var status: String = STATUS_NONE
## Идентификатор загрузки Strava (`/uploads/{id}`), пока активность не создана.
var upload_id: String = ""
## Идентификатор активности при `done`.
var activity_id: String = ""
## Текст ошибки для пользователя (без токенов).
var error: String = ""
## Код причины (`ApiResult.CODE_*`), пустой при успехе. UI строит текст причины по коду.
var code: String = ""
## Текст ответа Strava как есть (поле `error`/`message`), если причина пришла от Strava;
## UI показывает его только как деталь после переведённой причины.
var detail: String = ""
## Повтор имеет смысл (сеть, 5xx, 429).
var can_retry: bool = false
## Для 429 — через сколько секунд повторять.
var retry_after_sec: int = 0


static func done(activity: String, upload: String = "") -> UploadResult:
	var r := UploadResult.new()
	r.status = STATUS_DONE
	r.activity_id = activity
	r.upload_id = upload
	return r


## (`duplicate` занято `Resource.duplicate` у объекта скрипта — поэтому `duplicate_of`.)
static func duplicate_of(message: String, upload: String = "") -> UploadResult:
	var r := UploadResult.new()
	r.status = STATUS_DUPLICATE
	r.error = message
	r.detail = message
	r.upload_id = upload
	return r


static func uploading(upload: String) -> UploadResult:
	var r := UploadResult.new()
	r.status = STATUS_UPLOADING
	r.upload_id = upload
	r.can_retry = true
	r.code = ApiResult.CODE_NETWORK
	return r


static func failed(message: String, reason_code: String, retry: bool = false, upload: String = "") -> UploadResult:
	var r := UploadResult.new()
	r.status = STATUS_FAILED
	r.error = message
	r.code = reason_code
	r.can_retry = retry
	r.upload_id = upload
	return r


func is_final() -> bool:
	return status == STATUS_DONE or status == STATUS_DUPLICATE or (status == STATUS_FAILED and not can_retry)


## Ссылка на активность для `done` (REQ-STR-05 крит. 3), иначе "".
func activity_url() -> String:
	return StravaBranding.activity_url(activity_id) if status == STATUS_DONE and not activity_id.is_empty() else ""


## Словарь для `UploadStatusStore` / метаданных заезда.
func to_status_dict(attempts: int = 0, updated_at: int = 0) -> Dictionary:
	return {
		"status": status,
		"activity_id": activity_id,
		"upload_id": upload_id,
		"error": error,
		"code": code,
		"detail": detail,
		"attempts": attempts,
		"updated_at": updated_at,
	}


func _to_string() -> String:
	return "UploadResult(%s%s%s)" % [status, ", activity=" + activity_id if not activity_id.is_empty() else "", ", " + error if not error.is_empty() else ""]
