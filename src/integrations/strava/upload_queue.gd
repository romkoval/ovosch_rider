class_name UploadQueue
extends RefCounted
## Очередь выгрузки заездов в Strava с повторами (REQ-STR-04 крит. 1–6, REQ-STR-05 крит. 1–2,
## REQ-NFR-03 крит. 3).
##
## Элемент: `{ride_id, name, description, ride_date, enqueued_at, attempts, next_attempt_at,
## last_error, upload_id}`. Очередь хранится в `<dir>/upload_queue_<profile_id>.json`
## и переживает перезапуск (крит. 1). FIT не хранится: его отдаёт `fit_provider`
## (`func(ride_id: String) -> PackedByteArray`) — для элемента через `enqueue(...)` или общий
## `fit_provider` очереди (после перезапуска).
##
## `tick(now_sec)`: если нет активной сессии (`session_active`, крит. 6 / NFR-03) и нет
## текущей выгрузки (крит. 4 — не более одной), берётся первый «созревший» элемент в порядке
## даты заезда; результат:
## - `done`/`duplicate`/окончательная ошибка → статус в `UploadStatusStore`, элемент удалён;
## - сеть/5xx → `attempts += 1`, следующая попытка через 60, 300, 900, 3600 с, далее каждые
##   3600 с (решение 18; крит. 2) — попытки не исчерпываются;
## - 429 → не раньше `Retry-After` (крит. 3);
## - `uploading` (Strava ещё обрабатывает) → повтор опроса через `poll_retry_sec`.
## Статусы заезда: `queued` при постановке, `uploading` на время попытки, затем
## `done|failed|duplicate` или снова `queued` с `last_error`; ручная отмена (`remove`) —
## `none` (REQ-STR-05 крит. 1).

const RETRY_DELAYS_SEC: Array[int] = [60, 300, 900, 3600]
const DEFAULT_DIR: String = "user://"
const SCHEMA_VERSION: int = 1

## Статус элемента изменился (`status` — словарь `UploadResult.to_status_dict`).
signal item_changed(ride_id: String, status: Dictionary)
## Элемент выгружен (`activity_id`).
signal upload_finished(ride_id: String, activity_id: String)

## Активная тренировка — очередь стоит (REQ-STR-04 крит. 6).
var session_active: bool = false
## Общий поставщик FIT `func(ride_id) -> PackedByteArray` (после перезапуска).
var fit_provider: Callable
## Пауза перед повторным опросом незавершённой обработки Strava, с.
var poll_retry_sec: int = 30

var _uploader: StravaUploader
var _status_store: UploadStatusStore
var _clock_fn: Callable
var _profile_id: String
var _dir_path: String
var _items: Array[Dictionary] = []
var _providers: Dictionary = {}
var _busy: bool = false


func _init(uploader: StravaUploader, status_store: UploadStatusStore, clock_fn: Callable,
		profile_id: String, dir_path: String = DEFAULT_DIR) -> void:
	_uploader = uploader
	_status_store = status_store
	_clock_fn = clock_fn if clock_fn.is_valid() else func() -> int: return int(Time.get_unix_time_from_system())
	_profile_id = profile_id
	_dir_path = dir_path if dir_path.ends_with("/") else dir_path + "/"
	load_from_disk()


func file_path() -> String:
	return _dir_path + "upload_queue_%s.json" % _profile_id


# ---------------------------------------------------------------------------
# Управление очередью
# ---------------------------------------------------------------------------

## Поставить заезд в очередь (REQ-STR-04 крит. 1, 5). Повторная постановка обновляет
## название/описание и делает попытку немедленной. `ride_date` — unix-время заезда (порядок).
func enqueue(ride_id: String, fit_provider_for_ride: Callable, name: String, description: String,
		ride_date: int = 0) -> void:
	if ride_id.strip_edges().is_empty():
		return
	var now := _now()
	if fit_provider_for_ride.is_valid():
		_providers[ride_id] = fit_provider_for_ride
	var item := _find(ride_id)
	if item.is_empty():
		item = {
			"ride_id": ride_id,
			"name": name,
			"description": description,
			"ride_date": ride_date if ride_date > 0 else now,
			"enqueued_at": now,
			"attempts": 0,
			"next_attempt_at": now,
			"last_error": "",
			"upload_id": "",
		}
		_items.append(item)
	else:
		item["name"] = name
		item["description"] = description
		item["next_attempt_at"] = now
	_sort()
	_set_status(ride_id, _queued_result(str(item["last_error"])), int(item["attempts"]))
	save()


## Ручной повтор: попытка при следующем `tick` (REQ-STR-04 крит. 5).
func retry_now(ride_id: String) -> bool:
	var item := _find(ride_id)
	if item.is_empty():
		return false
	item["next_attempt_at"] = _now()
	save()
	return true


## Удалить элемент (ручная отмена, удаление заезда). Заезд, ожидавший выгрузки
## (`queued`/`failed`/`uploading`), становится «не выгружен» (`none`) — он больше не в очереди
## (REQ-STR-04 крит. 2, REQ-STR-05 крит. 1); `done`/`duplicate` не трогаются. Если элемент
## убран во время идущей выгрузки, её результат отбрасывается (см. `tick`).
func remove(ride_id: String) -> bool:
	var item := _find(ride_id)
	if item.is_empty():
		return false
	_items.erase(item)
	_providers.erase(ride_id)
	var current := str(_status_store.get_upload_status(ride_id).get("status", UploadResult.STATUS_NONE))
	if current == UploadResult.STATUS_QUEUED or current == UploadResult.STATUS_FAILED or current == UploadResult.STATUS_UPLOADING:
		_set_status(ride_id, UploadResult.new(), int(item["attempts"]))
	save()
	return true


func has(ride_id: String) -> bool:
	return not _find(ride_id).is_empty()


func size() -> int:
	return _items.size()


func is_busy() -> bool:
	return _busy


## Копии элементов в порядке обработки.
func items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in _items:
		out.append(i.duplicate())
	return out


func get_item(ride_id: String) -> Dictionary:
	return _find(ride_id).duplicate()


## Элемент, который `tick` взял бы сейчас (пустой — нечего делать).
func next_due(now_sec: int = -1) -> Dictionary:
	var now := now_sec if now_sec >= 0 else _now()
	for item in _items:
		if int(item["next_attempt_at"]) <= now:
			return item
	return {}


## Шаг очереди: не более одной выгрузки за вызов. Возвращает `ride_id` обработанного
## элемента или "" (нечего/нельзя). Асинхронный — вызывать через `await`.
func tick(now_sec: int = -1) -> String:
	if session_active or _busy:
		return ""
	var now := now_sec if now_sec >= 0 else _now()
	var item := next_due(now)
	if item.is_empty():
		return ""
	var ride_id := str(item["ride_id"])
	var fit := _fit_for(ride_id)
	if fit.is_empty():
		_finish(item, UploadResult.failed("нет FIT-файла заезда", ApiResult.CODE_BAD_RESPONSE), now)
		return ride_id
	_busy = true
	_set_status(ride_id, UploadResult.uploading(str(item["upload_id"])), int(item["attempts"]))
	var result: UploadResult
	if not str(item["upload_id"]).is_empty():
		result = await _uploader.poll_upload(str(item["upload_id"]))
	else:
		result = await _uploader.upload_fit(fit, str(item["name"]), str(item["description"]), ride_id)
	_busy = false
	if not _contains(item):
		# Пока шла выгрузка, элемент убрали (`remove`, удаление заезда, отвязка Strava):
		# статус заезда уже выставлен тем, кто убрал, — результат устаревшей попытки не пишется.
		return ride_id
	_apply_result(item, result, now)
	return ride_id


## Задержка перед попыткой номер `attempt` (1-based): 60, 300, 900, 3600, далее 3600.
static func retry_delay_sec(attempt: int) -> int:
	var idx := clampi(attempt - 1, 0, RETRY_DELAYS_SEC.size() - 1)
	return RETRY_DELAYS_SEC[idx]


# ---------------------------------------------------------------------------
# Персистентность (REQ-STR-04 крит. 1)
# ---------------------------------------------------------------------------

## Атомарная запись очереди (`AtomicFile`: временный файл → rename): сбой не портит прежний файл.
func save() -> bool:
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir_path))
	if err != OK and err != ERR_ALREADY_EXISTS:
		return false
	var path := file_path()
	var file := FileAccess.open(AtomicFile.tmp_path(path), FileAccess.WRITE)
	if file == null:
		return false
	var text := JSON.stringify({"schema": SCHEMA_VERSION, "profile_id": _profile_id, "items": _items}, "\t")
	return AtomicFile.commit(file, file.store_string(text), path) == OK


func load_from_disk() -> void:
	_items = []
	var path := file_path()
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK or not (json.data is Dictionary) or not ((json.data as Dictionary).get("items") is Array):
		return
	for raw in (json.data as Dictionary)["items"]:
		if not (raw is Dictionary) or str((raw as Dictionary).get("ride_id", "")).is_empty():
			continue
		var r: Dictionary = raw
		_items.append({
			"ride_id": str(r["ride_id"]),
			"name": str(r.get("name", "")),
			"description": str(r.get("description", "")),
			"ride_date": int(r.get("ride_date", 0)),
			"enqueued_at": int(r.get("enqueued_at", 0)),
			"attempts": int(r.get("attempts", 0)),
			"next_attempt_at": int(r.get("next_attempt_at", 0)),
			"last_error": str(r.get("last_error", "")),
			"upload_id": str(r.get("upload_id", "")),
		})
	_sort()


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _apply_result(item: Dictionary, result: UploadResult, now: int) -> void:
	var ride_id := str(item["ride_id"])
	match result.status:
		UploadResult.STATUS_DONE:
			_finish(item, result, now)
			upload_finished.emit(ride_id, result.activity_id)
		UploadResult.STATUS_DUPLICATE:
			_finish(item, result, now)
		UploadResult.STATUS_UPLOADING:
			item["upload_id"] = result.upload_id
			item["last_error"] = result.error
			item["next_attempt_at"] = now + maxi(poll_retry_sec, result.retry_after_sec)
			_set_status(ride_id, result, int(item["attempts"]))
			save()
		_:
			if not result.can_retry:
				_finish(item, result, now)
				return
			if not result.upload_id.is_empty():
				item["upload_id"] = result.upload_id
			item["attempts"] = int(item["attempts"]) + 1
			item["last_error"] = result.error
			var delay := result.retry_after_sec if result.code == ApiResult.CODE_RATE_LIMITED and result.retry_after_sec > 0 \
					else retry_delay_sec(int(item["attempts"]))
			item["next_attempt_at"] = now + delay
			_set_status(ride_id, _queued_result(result.error), int(item["attempts"]))
			save()


func _finish(item: Dictionary, result: UploadResult, _now: int) -> void:
	var ride_id := str(item["ride_id"])
	_items.erase(item)
	_providers.erase(ride_id)
	_set_status(ride_id, result, int(item["attempts"]))
	save()


func _set_status(ride_id: String, result: UploadResult, attempts: int) -> void:
	var status := result.to_status_dict(attempts, _now())
	_status_store.update_upload_status(ride_id, status)
	item_changed.emit(ride_id, status)


static func _queued_result(last_error: String) -> UploadResult:
	var r := UploadResult.new()
	r.status = UploadResult.STATUS_QUEUED
	r.error = last_error
	r.can_retry = true
	return r


func _fit_for(ride_id: String) -> PackedByteArray:
	var provider: Callable = _providers.get(ride_id, Callable())
	if not provider.is_valid():
		provider = fit_provider
	if not provider.is_valid():
		return PackedByteArray()
	var v: Variant = provider.call(ride_id)
	return v if v is PackedByteArray else PackedByteArray()


## Тот же объект элемента всё ещё в очереди (сравнение по ссылке, не по содержимому).
func _contains(item: Dictionary) -> bool:
	for i in _items:
		if is_same(i, item):
			return true
	return false


func _find(ride_id: String) -> Dictionary:
	for item in _items:
		if str(item["ride_id"]) == ride_id:
			return item
	return {}


func _sort() -> void:
	_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["ride_date"]) != int(b["ride_date"]):
			return int(a["ride_date"]) < int(b["ride_date"])
		return int(a["enqueued_at"]) < int(b["enqueued_at"]))


func _now() -> int:
	return int(_clock_fn.call())
