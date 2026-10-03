class_name PlanScreen
extends Control
## Экран выбора тренировки и предпросмотра (`AppState.Screen.PLAN`):
## REQ-INT-04 крит. 1–3, REQ-INT-05 крит. 1–4, REQ-INT-07 крит. 2–5, REQ-IMP-03 крит. 2,
## REQ-IMP-04 крит. 3, REQ-IMP-05 крит. 1, REQ-NFR-03.
##
## Секции: «Intervals.icu сегодня» (список событий: название, длительность, нагрузка;
## статусы загрузки / из кэша с временем / нет тренировки / требуется ключ или повторная
## авторизация; ключ — общий `IntervalsKeyDialog` (`src/ui/common/`, вместе с экраном настроек)
## → `verify_key` → `IntervalsSync.sync_profile`),
## «Библиотека» (импортированные тренировки, «Импортировать файл…» → `FileDialog`
## с фильтрами `*.zwo, *.erg, *.mrc`; ошибка — `AcceptDialog` с текстом по ключу ошибки
## `ParseResult` → `ui.plan.import.error.*` на языке интерфейса, REQ-IMP-05 крит. 1),
## предпросмотр (название, описание, длительность, `WorkoutChart`) и «Начать».
## Экран не запускает сессию сам — испускает `workout_chosen(workout)`; владелец (`main.gd`)
## решает, какой станок использовать, и при отсутствии станка просит экран показать выбор
## «эмулятор / подключить устройства» (`show_trainer_choice()`).
## Зависимости — через `setup()`; сетевой транспорт и хранилища инъецируются (тесты — мок).
## Все строки — ключи `ui.plan.*`.

const SOURCE_INTERVALS: String = "intervals"
const SOURCE_LIBRARY: String = "library"
## Фильтры диалога импорта: маска и описание. Описания — названия форматов файлов
## (Zwift Workout, ERG, MRC), собственные имена — не локализуются.
const FILE_FILTERS: PackedStringArray = ["*.zwo ; Zwift Workout", "*.erg ; ERG", "*.mrc ; MRC"]
## Префикс ключей локализации ошибок разбора: `ui.plan.import.error.<ParseResult key>`.
const IMPORT_ERROR_KEY_PREFIX: String = "ui.plan.import.error."
## Действие кнопки «Эмулятор» в `%TrainerDialog`.
const TRAINER_ACTION_EMULATOR: StringName = &"emulator"

## Пользователь выбрал тренировку и нажал «Начать».
signal workout_chosen(workout: Workout, source: String)
## Выбор при отсутствии станка (см. `show_trainer_choice`).
signal emulator_chosen()
signal devices_chosen()
## План загружен/обновлён (для тестов и владельца).
signal plan_loaded(result: ApiResult)
## Профиль изменён синхронизацией с Intervals.icu — владелец сохраняет.
signal profile_updated(profile: Profile)

## Дата «сегодня» (YYYY-MM-DD); пусто — локальная дата. Для тестов.
var today: String = ""

var _app_state: AppState
var _repo: ProfileRepository
var _secure_store: SecureStore
var _transport: HttpTransport
var _cache: PlanCache
var _library: WorkoutLibrary
var _profile: Profile = null
var _client: IntervalsIcuClient = null
var _service: IntervalsPlanService = null
var _last_result: ApiResult = null
## Профиль, для которого получен `_last_result` (план одного профиля не показывается другому).
var _last_result_profile_id: String = ""
## Поколение загрузок: смена профиля его увеличивает, и ответы, запрошенные раньше, отбрасываются.
var _load_generation: int = 0
## Элементы списка: `{source, name, duration_sec, training_load, workout, error, id}`.
var _items: Array[Dictionary] = []
var _selected: int = -1
var _loading: bool = false
var _trainer_choice_pending: bool = false
## Кнопка «Эмулятор», добавленная в `%TrainerDialog` из кода (текст обновляется при смене языка).
var _emulator_button: Button = null

@onready var _status_label: Label = %StatusLabel
@onready var _key_button: Button = %KeyButton
@onready var _reload_button: Button = %ReloadButton
@onready var _key_dialog: IntervalsKeyDialog = %KeyDialog
@onready var _list: ItemList = %WorkoutList
@onready var _import_button: Button = %ImportButton
@onready var _library_status_label: Label = %LibraryStatusLabel
@onready var _file_dialog: FileDialog = %ImportDialog
@onready var _import_error_dialog: AcceptDialog = %ImportErrorDialog
@onready var _preview_name: Label = %PreviewName
@onready var _preview_description: Label = %PreviewDescription
@onready var _preview_duration: Label = %PreviewDuration
@onready var _chart: WorkoutChart = %Chart
@onready var _start_button: Button = %StartButton
@onready var _back_button: Button = %BackButton
@onready var _trainer_dialog: ConfirmationDialog = %TrainerDialog


func setup(app_state: AppState, repo: ProfileRepository, secure_store: SecureStore,
		transport: HttpTransport, cache: PlanCache, library: WorkoutLibrary) -> void:
	_app_state = app_state
	_repo = repo
	_secure_store = secure_store
	_transport = transport
	_cache = cache
	_library = library
	if is_node_ready():
		refresh()


func _ready() -> void:
	_key_button.pressed.connect(open_key_form)
	_reload_button.pressed.connect(func() -> void: load_today())
	_key_dialog.submitted.connect(func(aid: String, key: String) -> void: submit_key(aid, key))
	_list.item_selected.connect(select_index)
	_list.item_activated.connect(func(_i: int) -> void: start_selected())
	_import_button.pressed.connect(open_import_dialog)
	_file_dialog.filters = FILE_FILTERS
	_file_dialog.file_selected.connect(on_import_file_selected)
	_start_button.pressed.connect(start_selected)
	_back_button.pressed.connect(func() -> void: _navigate(AppState.Screen.HOME))
	_trainer_dialog.confirmed.connect(func() -> void: _choose_devices())
	_trainer_dialog.custom_action.connect(func(action: StringName) -> void:
		if action == TRAINER_ACTION_EMULATOR:
			choose_emulator())
	_emulator_button = _trainer_dialog.add_button(tr("ui.plan.trainer_choice.emulator"), true, TRAINER_ACTION_EMULATOR)
	_chart.set_workout(null, 200)
	refresh()


func _notification(what: int) -> void:
	# Смена языка интерфейса: тексты, заданные из кода (а не из сцены), обновляются вручную.
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_texts()


# ---------------------------------------------------------------------------
# Состояние
# ---------------------------------------------------------------------------

## Перечитать профиль, библиотеку и кэш (без сети). Сеть — `load_today()`.
func refresh() -> void:
	if not is_node_ready() or _repo == null:
		return
	_refresh_texts()
	_profile = _repo.get_active()
	var profile_id := _profile.id if _profile != null else ""
	if profile_id != _last_result_profile_id:
		# Сменился активный профиль: план, выбор и незавершённая загрузка прежнего профиля
		# к новому не относятся.
		_last_result = null
		_last_result_profile_id = profile_id
		_selected = -1
		_loading = false
		_load_generation += 1
	_client = null
	_service = null
	if _profile != null and _transport != null:
		_client = IntervalsIcuClient.for_profile(_transport, _secure_store, _profile)
		_service = IntervalsPlanService.new(_client, _cache)
	if _service != null and _last_result == null:
		var cached := _service.cached_today(today)
		if cached.ok:
			_last_result = cached
	_rebuild_items()
	_update_status()
	_render_preview()


## Загрузить план на сегодня из сети (с откатом на кэш внутри сервиса).
## Профиль и сервис фиксируются до `await`: если за время запроса активный профиль сменился,
## ответ на экран не попадает (результат возвращается вызывающему, но отбрасывается).
func load_today() -> ApiResult:
	if _service == null or not _is_current_profile(_profile):
		refresh()
	if _service == null:
		_set_status(tr("ui.plan.status.no_profile"))
		return ApiResult.failure(ApiResult.CODE_NOT_CONFIGURED, "no profile")
	var profile := _profile
	var client := _client
	var service := _service
	if not client.is_configured():
		_last_result = ApiResult.failure(ApiResult.CODE_NOT_CONFIGURED, "")
		_last_result_profile_id = profile.id
		_rebuild_items()
		_update_status()
		plan_loaded.emit(_last_result)
		return _last_result
	_load_generation += 1
	var generation := _load_generation
	_loading = true
	_set_status(tr("ui.plan.status.loading"))
	var result: ApiResult = await service.load_today(today)
	if generation != _load_generation or not _is_current_profile(profile):
		# Ответ устарел: профиль сменился (или запущена более новая загрузка).
		if generation == _load_generation:
			_loading = false
		return result
	_loading = false
	_last_result = result
	_last_result_profile_id = profile.id
	_rebuild_items()
	_update_status()
	_render_preview()
	plan_loaded.emit(result)
	return result


func last_result() -> ApiResult:
	return _last_result


func items() -> Array[Dictionary]:
	return _items.duplicate()


## Записи Intervals.icu в списке.
func intervals_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in _items:
		if it["source"] == SOURCE_INTERVALS:
			out.append(it)
	return out


func library_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in _items:
		if it["source"] == SOURCE_LIBRARY:
			out.append(it)
	return out


func status_text() -> String:
	return _status_label.text


func key_error_text() -> String:
	return _key_dialog.error_text()


func is_key_form_open() -> bool:
	return _key_dialog.visible


func key_dialog() -> IntervalsKeyDialog:
	return _key_dialog


func import_error_text() -> String:
	return _import_error_dialog.dialog_text


func library_status_text() -> String:
	return _library_status_label.text


# ---------------------------------------------------------------------------
# Выбор и предпросмотр
# ---------------------------------------------------------------------------

func select_index(index: int) -> void:
	if index < 0 or index >= _items.size():
		_selected = -1
	else:
		_selected = index
		if not _list.is_selected(index) and _list.is_item_selectable(index):
			_list.select(index)
	_render_preview()


func selected_index() -> int:
	return _selected


func selected_workout() -> Workout:
	if _selected < 0 or _selected >= _items.size():
		return null
	return _items[_selected]["workout"]


func selected_item() -> Dictionary:
	return _items[_selected] if _selected >= 0 and _selected < _items.size() else {}


func preview_points() -> PackedVector2Array:
	return _chart.points()


func chart() -> WorkoutChart:
	return _chart


func preview_name_text() -> String:
	return _preview_name.text


func preview_duration_text() -> String:
	return _preview_duration.text


## «Начать»: испустить `workout_chosen`. false — ничего не выбрано.
func start_selected() -> bool:
	var w := selected_workout()
	if w == null:
		return false
	workout_chosen.emit(w, str(_items[_selected]["source"]))
	return true


# ---------------------------------------------------------------------------
# Ключ API Intervals.icu
# ---------------------------------------------------------------------------

func open_key_form() -> void:
	_key_dialog.open(_profile.intervals_athlete_id if _profile != null else "")


func close_key_form() -> void:
	_key_dialog.hide()


## Проверить ключ: при успехе — сохранить (внутри клиента), синхронизировать профиль, загрузить план.
## Профиль и клиент фиксируются до `await` (как в `SettingsScreen.submit_key`): если за время
## проверки активный профиль сменился, ответ на экран не попадает и в другой профиль не пишется.
## Ключ при этом уже сохранён клиентом под прежним профилем — его Athlete ID и данные атлета
## записываются в тот же (прежний) профиль из репозитория, чтобы привязка была согласованной.
func submit_key(athlete_id: String, key: String) -> ApiResult:
	if _client == null or not _is_current_profile(_profile):
		refresh()
	if _client == null:
		return ApiResult.failure(ApiResult.CODE_NOT_CONFIGURED, "no profile")
	var profile := _profile
	var client := _client
	var result: ApiResult = await client.verify_key(athlete_id, key)
	if not _is_current_profile(profile):
		if result.ok:
			var stored := _repo.get_by_id(profile.id)
			if stored != null:
				var updated := stored.duplicate_profile()
				updated.intervals_athlete_id = athlete_id.strip_edges()
				IntervalsSync.sync_profile(updated, result.data, today)
				_repo.save(updated)
		return result
	if not result.ok:
		match result.code:
			ApiResult.CODE_AUTH_FAILED, ApiResult.CODE_REAUTH_REQUIRED:
				_show_key_error(tr("ui.plan.key.rejected"))
			ApiResult.CODE_NOT_CONFIGURED:
				_show_key_error(tr("ui.plan.key.fill_both"))
			_:
				# Причина — по коду (общие с экраном настроек тексты), не `ApiResult.message`:
				# тот — русский текст для логов (REQ-NFR-08 крит. 1).
				_show_key_error(tr("ui.plan.key.failed").format({"reason": api_error_text(result.code)}))
		return result
	var athlete: Dictionary = result.data
	profile.intervals_athlete_id = athlete_id.strip_edges()
	IntervalsSync.sync_profile(profile, athlete, today)
	_repo.save(profile)
	profile_updated.emit(profile)
	close_key_form()
	var athlete_name := str(athlete.get("name", ""))
	_set_status(tr("ui.plan.key.verified").format({"name": athlete_name if not athlete_name.is_empty() else athlete_id}))
	_last_result = null
	await load_today()
	return result


## Переведённая причина отказа `ApiResult` по коду (никогда не сырой код и не `message`).
func api_error_text(code: String) -> String:
	return tr(str(SettingsScreen.API_ERROR_KEYS.get(code, SettingsScreen.API_ERROR_UNKNOWN_KEY)))


# ---------------------------------------------------------------------------
# Импорт файлов (REQ-IMP-03 крит. 2, REQ-IMP-05 крит. 1)
# ---------------------------------------------------------------------------

func open_import_dialog() -> void:
	_file_dialog.popup_centered_ratio(0.8)


## Хук для системного диалога и «Открыть в…» (платформенная часть передаёт путь).
func import_path(path: String) -> ParseResult:
	return on_import_file_selected(path)


func on_import_file_selected(path: String) -> ParseResult:
	if _profile == null or _library == null:
		return null
	var result := _library.import_file(_profile.id, path)
	if result == null or not result.ok():
		var message := localized_errors(result, path.get_file()) if result != null else path.get_file()
		_import_error_dialog.dialog_text = message
		if not _import_error_dialog.visible:
			_import_error_dialog.popup_centered()
		_library_status_label.text = tr("ui.plan.import.failed")
		return result
	var replaced: bool = false
	for w in result.warnings:
		if str(w.get("key", "")) == "duplicate_replaced":
			replaced = true
	_library_status_label.text = tr("ui.plan.import.updated") if replaced else tr("ui.plan.import.done").format({"name": result.workout.name})
	_rebuild_items()
	_update_status()
	# `WorkoutLibrary.import_file` кладёт id записи в `metadata.entry_id` (не `id`).
	var imported_id := str(result.metadata.get("entry_id", ""))
	for i in _items.size():
		if _items[i]["source"] == SOURCE_LIBRARY and str(_items[i]["id"]) == imported_id:
			select_index(i)
			return result
	# Фолбэк на случай, если библиотека не вернула id (не должно случаться): по имени,
	# иначе при одинаковых именах выбиралась бы старая запись (REQ-IMP-04 крит. 4).
	if imported_id.is_empty():
		for i in _items.size():
			if _items[i]["source"] == SOURCE_LIBRARY and _items[i]["name"] == result.workout.name:
				select_index(i)
				break
	return result


# ---------------------------------------------------------------------------
# Ошибки разбора на языке интерфейса (REQ-IMP-05 крит. 1, 3)
# ---------------------------------------------------------------------------

## Текст одной записи `ParseResult.errors`: `<файл>: <тип проблемы> (элемент X, строка N)`.
## Тип проблемы — по ключу `key` через `ui.plan.import.error.<key>`; неизвестный ключ →
## `ui.plan.import.error.parse_error`. Имя элемента и номер строки — из записи; имя файла
## добавляется один раз (не повторяется, если элемент — это сам файл).
func localized_error(entry: Dictionary, file_name: String = "") -> String:
	var key := str(entry.get("key", ""))
	var tr_key := IMPORT_ERROR_KEY_PREFIX + key
	var text := tr(tr_key) if not key.is_empty() else tr_key
	if text == tr_key:
		text = tr(IMPORT_ERROR_KEY_PREFIX + "parse_error")
	var element := str(entry.get("element", ""))
	var line := int(entry.get("line", 0))
	var column := int(entry.get("column", 0))
	var parts: Array[String] = []
	if text.contains("{element}"):
		text = text.format({"element": element})
	elif not element.is_empty() and element != file_name and not text.contains(element):
		parts.append(tr("ui.plan.import.error.at_element").format({"element": element}))
	if line > 0:
		if column > 0:
			parts.append(tr("ui.plan.import.error.at_line_col").format({"line": line, "column": column}))
		else:
			parts.append(tr("ui.plan.import.error.at_line").format({"line": line}))
	if not parts.is_empty():
		text += " (" + ", ".join(parts) + ")"
	if not file_name.is_empty():
		text = tr("ui.plan.import.error.in_file").format({"file": file_name, "text": text})
	return text


## Все ошибки результата, по одной на строку.
func localized_errors(result: ParseResult, file_name: String = "") -> String:
	var lines: Array[String] = []
	for e in result.errors:
		lines.append(localized_error(e, file_name))
	if lines.is_empty():
		lines.append(tr("ui.plan.import.error.in_file").format({"file": file_name, "text": tr(IMPORT_ERROR_KEY_PREFIX + "parse_error")}) if not file_name.is_empty() else tr(IMPORT_ERROR_KEY_PREFIX + "parse_error"))
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# Выбор станка при старте без подключённого устройства
# ---------------------------------------------------------------------------

## Станок не подключён: предложить эмулятор или экран устройств.
func show_trainer_choice() -> void:
	_trainer_choice_pending = true
	_trainer_dialog.dialog_text = tr("ui.plan.trainer_choice.text")
	if not _trainer_dialog.visible:
		_trainer_dialog.popup_centered()


func is_trainer_choice_pending() -> bool:
	return _trainer_choice_pending


func choose_emulator() -> void:
	_trainer_choice_pending = false
	_trainer_dialog.hide()
	emulator_chosen.emit()


func _choose_devices() -> void:
	_trainer_choice_pending = false
	devices_chosen.emit()
	_navigate(AppState.Screen.DEVICES)


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _navigate(screen: int) -> void:
	if _app_state != null:
		_app_state.navigate(screen)


func _set_status(text: String) -> void:
	_status_label.text = text


## `profile` — по-прежнему активный профиль и профиль экрана (после `await` это не гарантировано).
func _is_current_profile(profile: Profile) -> bool:
	return profile != null and _repo != null and _repo.active_profile_id == profile.id \
		and _profile != null and _profile.id == profile.id


## Тексты, заданные из кода (сцена переводится движком сама).
func _refresh_texts() -> void:
	if _emulator_button != null:
		_emulator_button.text = tr("ui.plan.trainer_choice.emulator")
	if _trainer_choice_pending:
		_trainer_dialog.dialog_text = tr("ui.plan.trainer_choice.text")


func _show_key_error(text: String) -> void:
	if not text.is_empty():
		_key_dialog.show_error(text)


func _rebuild_items() -> void:
	var previous_id := str(selected_item().get("id", ""))
	_items = []
	if _last_result != null and _last_result.ok and _last_result.data is Array:
		for entry in _last_result.data:
			var e: Dictionary = entry
			var pr: ParseResult = e.get("parse_result", null)
			var error_text := ""
			if e.get("workout", null) == null:
				error_text = localized_errors(pr) if pr != null else tr("ui.plan.item.no_plan")
			_items.append({
				"source": SOURCE_INTERVALS, "id": "icu:" + str(e.get("event_id", "")),
				"name": str(e.get("name", "")), "duration_sec": int(e.get("duration_sec", 0)),
				"training_load": int(e.get("training_load", 0)), "workout": e.get("workout", null),
				"error": error_text,
			})
	if _library != null and _profile != null:
		for entry in _library.list(_profile.id):
			_items.append({
				"source": SOURCE_LIBRARY, "id": str(entry["id"]), "name": str(entry["name"]),
				"duration_sec": int(entry["duration_sec"]), "training_load": 0,
				"workout": _library.get_workout(_profile.id, str(entry["id"])), "error": "",
				"source_file": str(entry.get("source_file", "")),
			})
	_list.clear()
	for it in _items:
		var text := _item_text(it)
		var idx := _list.add_item(text)
		if it["workout"] == null:
			_list.set_item_disabled(idx, true)
			_list.set_item_tooltip(idx, str(it["error"]))
	_selected = -1
	if not previous_id.is_empty():
		for i in _items.size():
			if _items[i]["id"] == previous_id:
				_selected = i
	# REQ-INT-04 крит. 1: единственная тренировка на сегодня предлагается к запуску сразу.
	if _selected < 0:
		var runnable := _runnable_intervals_indices()
		if runnable.size() == 1:
			_selected = runnable[0]
	if _selected >= 0 and _list.is_item_selectable(_selected):
		_list.select(_selected)


func _runnable_intervals_indices() -> Array[int]:
	var out: Array[int] = []
	for i in _items.size():
		if _items[i]["source"] == SOURCE_INTERVALS and _items[i]["workout"] != null:
			out.append(i)
	return out


func _item_text(it: Dictionary) -> String:
	var parts: Array[String] = [str(it["name"]), IntervalsPlanService.format_duration(int(it["duration_sec"]))]
	if int(it["training_load"]) > 0:
		parts.append(tr("ui.plan.item.load").format({"load": it["training_load"]}))
	if it["source"] == SOURCE_LIBRARY:
		parts.append(tr("ui.plan.source_library"))
	else:
		parts.append(tr("ui.plan.source_intervals"))
	if it["workout"] == null:
		parts.append(tr("ui.plan.item.unparsed"))
	return " · ".join(parts)


func _update_status() -> void:
	if _profile == null:
		_set_status(tr("ui.plan.status.no_profile"))
		_key_button.visible = false
		return
	_key_button.visible = true
	if _loading:
		return
	if _client != null and not _client.is_configured():
		_set_status(tr("ui.plan.status.not_configured"))
		return
	if _last_result == null:
		_set_status(tr("ui.plan.status.idle"))
		return
	var r := _last_result
	if r.ok:
		var base := ""
		if r.code == ApiResult.CODE_NO_WORKOUT_TODAY or (r.data is Array and (r.data as Array).is_empty()):
			base = tr("ui.plan.status.no_workout_today")
		else:
			base = tr("ui.plan.status.ok").format({"count": (r.data as Array).size()})
		if r.from_cache:
			base += " · " + tr("ui.plan.status.from_cache").format({"time": _format_time(r.loaded_at)})
		_set_status(base)
		return
	match r.code:
		ApiResult.CODE_AUTH_FAILED, ApiResult.CODE_REAUTH_REQUIRED:
			_set_status(tr("ui.plan.status.reauth_required"))
		ApiResult.CODE_NOT_CONFIGURED:
			_set_status(tr("ui.plan.status.not_configured"))
		ApiResult.CODE_NETWORK:
			_set_status(tr("ui.plan.status.network_error"))
		ApiResult.CODE_RATE_LIMITED:
			_set_status(tr("ui.plan.status.rate_limited"))
		_:
			_set_status(tr("ui.plan.status.bad_response"))


## Время загрузки «ЧЧ:ММ» в локальном часовом поясе устройства (как `PlanCache.local_datetime`).
static func _format_time(unix: int) -> String:
	if unix <= 0:
		return "—"
	var dt := PlanCache.local_datetime(unix)
	return "%02d:%02d" % [dt["hour"], dt["minute"]]


func _render_preview() -> void:
	var w := selected_workout()
	var ftp: int = _profile.ftp_w if _profile != null else 200
	var intensity: float = float(_profile.intensity_default) / 100.0 if _profile != null else 1.0
	# REQ-INT-05 крит. 3 / REQ-HUD-03 крит. 1: цвета сегментов — по зонам профиля, как в HUD.
	var zones: PowerZones = _profile.effective_power_zones() if _profile != null else null
	if w == null:
		_preview_name.text = tr("ui.plan.preview.empty")
		_preview_description.text = ""
		_preview_duration.text = ""
		_chart.set_workout(null, ftp)
		_start_button.disabled = true
		return
	_preview_name.text = w.name
	_preview_description.text = w.description
	_preview_duration.text = tr("ui.plan.preview.duration").format({"duration": IntervalsPlanService.format_duration(w.total_duration_sec()), "ftp": ftp})
	_chart.set_workout(w, ftp, intensity, zones)
	_start_button.disabled = false
