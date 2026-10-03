class_name StravaService
extends RefCounted
## Связка Strava с приложением для одного профиля (T-049): OAuth + выгрузка + очередь +
## статусы заезда (REQ-STR-01 крит. 7, REQ-STR-02 крит. 1, REQ-STR-03 крит. 1–3,
## REQ-STR-04 крит. 5, 6, REQ-STR-05 крит. 2, REQ-LOC-06 крит. 3, REQ-PRF-03 крит. 2).
##
## Жизненный цикл: создаётся оболочкой при выборе профиля, `attach()` подписывает на
## `RideRepository.ride_saved` (автопостановка в очередь завершённого заезда, если есть
## привязка и в профиле включена `strava_auto_upload`), `tick(delta)` из `_process`
## двигает очередь раз в `QUEUE_TICK_INTERVAL_SEC` и опрашивает loopback-слушатель во время
## входа; `dispose()` при смене профиля/выходе. Подписки — связанными методами (без лямбд).
##
## Вход: `connect_flow_start()` запускает loopback-сервер и возвращает URL авторизации
## (открыть в браузере — задача UI, например `LinkButton.uri`); код приходит через
## `tick()` → `exchange_code` → `authorized_changed(true)`. Мобильная схема —
## `handle_redirect_url(url)`. `disconnect_strava()` — отзыв токенов, очистка очереди,
## статусы ожидавших заездов → `none` (`disconnect` занято `Object`).

const QUEUE_TICK_INTERVAL_SEC: float = 5.0
## Шаблон названия без плана (REQ-STR-03 крит. 1) — запасной, если перевода нет.
const DEFAULT_NAME_TEMPLATE: String = "Тренировка %s"
## Ключи перевода названия «Тренировка <дата>» (`%s` — дата) и строки приложения в описании
## (REQ-STR-03 крит. 1, 2). Перевод берётся на текущем языке интерфейса в момент постановки
## в очередь, поэтому смена языка на лету сразу действует на новые выгрузки.
const KEY_DEFAULT_NAME: String = "ui.strava.default_name"
const KEY_DEFAULT_DESCRIPTION: String = "ui.strava.default_description"

## Статус выгрузки заезда изменился (уже записан в `RideRepository`).
signal status_changed(ride_id: String)
## Привязка появилась/снята.
signal authorized_changed(authorized: bool)
## Ход входа: `state` ∈ `idle | waiting | exchanging | done | failed`, `message` — для UI.
signal connect_flow_changed(state: String, message: String)

var oauth: StravaOAuth
var uploader: StravaUploader
var queue: UploadQueue
var status_store: UploadStatusStore
var config: StravaConfig
## Явный шаблон названия заезда без плана (`%s` — дата). Пусто (по умолчанию) — перевод
## `KEY_DEFAULT_NAME` на текущем языке интерфейса в момент постановки в очередь.
var name_template: String = ""
## Явная строка приложения в описании (REQ-STR-03 крит. 2). Пусто — перевод `KEY_DEFAULT_DESCRIPTION`.
var description_app_line: String = ""

var _profile: Profile
var _rides: RideRepository
var _clock_fn: Callable
var _since_tick: float = 0.0
var _ticking: bool = false
var _exchanging: bool = false
var _attached: bool = false
var _flow_state: String = "idle"
## Код причины последнего `failed` (см. `flow_error_code`).
var _flow_error_code: String = ""


func _init(profile: Profile, transport: HttpTransport, secure_store: SecureStore,
		ride_repository: RideRepository, strava_config: StravaConfig,
		clock_fn: Callable = Callable(), dir_path: String = UploadQueue.DEFAULT_DIR) -> void:
	_profile = profile
	_rides = ride_repository
	config = strava_config
	_clock_fn = clock_fn if clock_fn.is_valid() else func() -> int: return int(Time.get_unix_time_from_system())
	oauth = StravaOAuth.new(transport, secure_store, profile.id, strava_config)
	oauth.clock_fn = _clock_fn
	uploader = StravaUploader.new(transport, oauth)
	status_store = RideRepositoryUploadStore.new(ride_repository)
	queue = UploadQueue.new(uploader, status_store, _clock_fn, profile.id, dir_path)
	queue.fit_provider = _fit_for_ride
	queue.item_changed.connect(_on_item_changed)


## Подписаться на репозиторий заездов (автопостановка, REQ-STR-02 крит. 1).
func attach() -> void:
	if _attached:
		return
	_attached = true
	_rides.ride_saved.connect(on_ride_saved)


func dispose() -> void:
	if _attached and _rides.ride_saved.is_connected(on_ride_saved):
		_rides.ride_saved.disconnect(on_ride_saved)
	_attached = false
	oauth.stop_listener()
	if queue.item_changed.is_connected(_on_item_changed):
		queue.item_changed.disconnect(_on_item_changed)


func profile_id() -> String:
	return _profile.id


## Профиль обновили (например, флаг автовыгрузки) — заменить снимок.
func set_profile(profile: Profile) -> void:
	if profile != null and profile.id == _profile.id:
		_profile = profile


func is_configured() -> bool:
	return config.is_configured()


func is_authorized() -> bool:
	return oauth.is_authorized()


func flow_state() -> String:
	return _flow_state


## Код причины последнего перехода входа в `failed` (пусто в остальных состояниях): `ApiResult.CODE_*`
## (`not_configured`, `auth_failed`, `network`, …) или отказ redirect от `StravaOAuth`
## (`timeout`, `access_denied`, `bad_request`, `state_mismatch`). UI строит текст по коду;
## `message` сигнала `connect_flow_changed` — русский текст для логов.
func flow_error_code() -> String:
	return _flow_error_code


## Активная тренировка — очередь стоит (REQ-STR-04 крит. 6).
func set_session_active(active: bool) -> void:
	queue.session_active = active


# ---------------------------------------------------------------------------
# Заезды
# ---------------------------------------------------------------------------

## Заезд записан: завершённый, ещё не выгруженный → в очередь (при привязке и автовыгрузке).
func on_ride_saved(ride_id: String) -> void:
	if not is_authorized() or not _profile.strava_auto_upload:
		return
	var ride := _rides.get_ride(ride_id)
	if ride == null or ride.profile_id != _profile.id or ride.is_in_progress():
		return
	var status := str(ride.upload.get("strava_status", Ride.UPLOAD_NONE))
	if status != Ride.UPLOAD_NONE:
		return
	_enqueue_ride(ride, "", "")


## Ручная выгрузка из истории (REQ-STR-04 крит. 5, REQ-STR-03 крит. 3): название и описание
## пользователя попадают в запрос. false — нет привязки или заезда / он уже выгружен.
func upload_now(ride_id: String, name: String = "", description: String = "") -> bool:
	if not is_authorized():
		return false
	var ride := _rides.get_ride(ride_id)
	if ride == null or ride.is_in_progress():
		return false
	if str(ride.upload.get("strava_status", Ride.UPLOAD_NONE)) == Ride.UPLOAD_DONE:
		return false
	_enqueue_ride(ride, name, description)
	return true


## Заезд удалён — элемент очереди убирается (REQ-LOC-06 крит. 3).
func on_ride_deleted(ride_id: String) -> void:
	queue.remove(ride_id)


## Название по умолчанию (REQ-STR-03 крит. 1): план или «Тренировка <дата>» на текущем языке.
func default_name(ride: Ride) -> String:
	return compose_default_name(ride, current_name_template())


## Описание по умолчанию (REQ-STR-03 крит. 2): описание плана + строка приложения на текущем языке.
func default_description(ride: Ride) -> String:
	return compose_default_description(ride, current_app_line())


## Шаблон названия, действующий сейчас: явный `name_template` или перевод `KEY_DEFAULT_NAME`.
func current_name_template() -> String:
	if not name_template.is_empty():
		return name_template
	var translated := tr(KEY_DEFAULT_NAME)
	return translated if translated != KEY_DEFAULT_NAME and translated.contains("%s") else DEFAULT_NAME_TEMPLATE


## Строка приложения, действующая сейчас: явная `description_app_line` или перевод.
func current_app_line() -> String:
	if not description_app_line.is_empty():
		return description_app_line
	var translated := tr(KEY_DEFAULT_DESCRIPTION)
	return translated if translated != KEY_DEFAULT_DESCRIPTION else "Записано в " + StravaUploader.APP_NAME


## Название по умолчанию с заданным шаблоном (карточка заезда строит его тем же правилом).
static func compose_default_name(ride: Ride, template: String) -> String:
	return StravaUploader.default_name(ride.name, _date_text(ride.started_at_unix), template)


## Описание по умолчанию с заданной строкой приложения.
static func compose_default_description(ride: Ride, app_line: String) -> String:
	return StravaUploader.default_description(ride.description, app_line)


func _enqueue_ride(ride: Ride, name: String, description: String) -> void:
	var n := name.strip_edges() if not name.strip_edges().is_empty() else default_name(ride)
	var d := description if not description.strip_edges().is_empty() else default_description(ride)
	queue.enqueue(ride.id, _fit_for_ride, n, d, ride.started_at_unix)


func _fit_for_ride(ride_id: String) -> PackedByteArray:
	var ride := _rides.get_ride(ride_id)
	return FitEncoder.encode(ride) if ride != null else PackedByteArray()


func _on_item_changed(ride_id: String, _status: Dictionary) -> void:
	status_changed.emit(ride_id)


# ---------------------------------------------------------------------------
# Вход / отвязка
# ---------------------------------------------------------------------------

## Начать вход: loopback-сервер + URL авторизации (REQ-STR-01 крит. 1, 7). "" — не настроено.
func connect_flow_start() -> String:
	if not config.is_configured():
		_set_flow("failed", config.unavailable_message(), ApiResult.CODE_NOT_CONFIGURED)
		return ""
	var redirect := oauth.start_loopback_listener()
	var url := oauth.authorize_url("")
	_set_flow("waiting", redirect)
	return url


func connect_flow_cancel() -> void:
	oauth.stop_listener()
	_set_flow("idle", "")


## Redirect из мобильной схемы / вставленный вручную.
func handle_redirect_url(url: String) -> void:
	var r := oauth.handle_redirect_url(url)
	if r.has("code"):
		_exchange(str(r["code"]))
	elif r.has("error"):
		_set_flow("failed", str(r["error"]), str(r["error"]))


func _exchange(code: String) -> void:
	if _exchanging:
		return
	_exchanging = true
	_set_flow("exchanging", "")
	var result: ApiResult = await oauth.exchange_code(code)
	_exchanging = false
	if result.ok:
		_set_flow("done", str((result.data as Dictionary).get("athlete_name", "")))
		authorized_changed.emit(true)
	else:
		_set_flow("failed", result.message, result.code)


## Отвязка (REQ-STR-01 крит. 8, REQ-PRF-03 крит. 2): отзыв токенов, очистка очереди профиля,
## статусы ожидавших заездов → `none`.
func disconnect_strava() -> ApiResult:
	oauth.stop_listener()
	var waiting: Array[String] = []
	for item in queue.items():
		waiting.append(str(item["ride_id"]))
	for ride_id in waiting:
		queue.remove(ride_id)
		var reset := UploadResult.new()
		reset.status = UploadResult.STATUS_NONE
		status_store.update_upload_status(ride_id, reset.to_status_dict(0, int(_clock_fn.call())))
		status_changed.emit(ride_id)
	var result: ApiResult = await oauth.revoke()
	_set_flow("idle", "")
	authorized_changed.emit(false)
	return result


# ---------------------------------------------------------------------------
# Такт
# ---------------------------------------------------------------------------

## Из `_process`: опрос loopback во время входа и шаг очереди раз в 5 с.
func tick(delta: float) -> void:
	if oauth.is_listening():
		var r := oauth.poll_listener()
		if r.has("code"):
			_exchange(str(r["code"]))
		elif r.has("error"):
			_set_flow("failed", str(r["error"]), str(r["error"]))
	_since_tick += delta
	if _since_tick >= QUEUE_TICK_INTERVAL_SEC:
		_since_tick = 0.0
		step_queue()


## Один шаг очереди немедленно (тесты и ручной повтор).
func step_queue() -> void:
	if _ticking or not is_authorized():
		return
	_ticking = true
	await queue.tick()
	_ticking = false


func _set_flow(state: String, message: String, error_code: String = "") -> void:
	_flow_state = state
	_flow_error_code = error_code if state == "failed" else ""
	connect_flow_changed.emit(state, message)


static func _date_text(unix: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(unix + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	return "%04d-%02d-%02d" % [dt["year"], dt["month"], dt["day"]]
