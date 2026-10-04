class_name PlanScreen
extends Control
## Экран выбора тренировки и предпросмотра (`AppState.Screen.PLAN`, `docs/game/ui.md` п. 8.3):
## REQ-UIX-03 крит. 1, 3, 4 (тренировка), REQ-INT-04 крит. 1–3, REQ-INT-05 крит. 1–4,
## REQ-INT-07 крит. 2–5, REQ-IMP-03 крит. 2, REQ-IMP-04 крит. 3, REQ-IMP-05 крит. 1, REQ-NFR-03.
##
## Раскладка: `AppBar` «Тренировка по плану» («назад» → `AppState.go_back()`; действия «Импорт
## файла» и «Обновить»). Слева (40 %) — карточки тренировок (`ListRow` с вариацией `CardButton`:
## миниатюра `PlanPreview`, название, «38:00 · 12 шагов · макс. 300 Вт · нагрузка 42», источник)
## в разделах «Сегодня в Intervals.icu» (статус загрузки; без ключа или при отказе ключа — баннер с действием
## «Указать ключ» → общий `IntervalsKeyDialog` → `verify_key` → `IntervalsSync.sync_profile`) и
## «Библиотека» (пусто — пустое состояние с импортом). Справа (60 %) — предпросмотр выбранной:
## название, описание (3 строки и «Ещё»), крупное превью (`PlanPreview` с `detailed = true`:
## шкала времени, пунктир FTP), длительность, шагов, макс. цель, время в зонах
## и «Начать»; в отладочной сборке (`dev_tools_enabled`, как на главном) под ней — «На эмуляторе»
## (`emulator_workout_requested`). Ровно одна карточка «выбрано» (или ни одной, пока выбора нет).
## Compact (холст уже 1100 lp, телефон): список во всю ширину, предпросмотр — лист снизу по
## нажатию на карточку (Esc или нажатие вне листа закрывают его). Контент — не шире 1216 lp,
## отступы безопасной зоны — по `UiScale.safe_margins()`.
##
## Импорт: «Импорт файла» → `FileDialog` с фильтрами `*.zwo, *.erg, *.mrc`; ошибка — `AcceptDialog`
## с текстом по ключу ошибки `ParseResult` → `ui.plan.import.error.*` на языке интерфейса
## (REQ-IMP-05 крит. 1).
## Экран не запускает сессию сам — испускает `workout_chosen(workout)`; владелец (`main.gd`)
## решает, какой станок использовать, и при отсутствии станка просит экран показать выбор
## «эмулятор / подключить устройства» (`show_trainer_choice()`).
## Зависимости — через `setup()`; сетевой транспорт и хранилища инъецируются (тесты — мок).
## Все строки — ключи `ui.plan.*` (новые ключи T-082 и T-095 — в `strings_menu_lists.csv`).

const SOURCE_INTERVALS: String = "intervals"
const SOURCE_LIBRARY: String = "library"
## Фильтры диалога импорта: маска и описание. Описания — названия форматов файлов
## (Zwift Workout, ERG, MRC), собственные имена — не локализуются.
const FILE_FILTERS: PackedStringArray = ["*.zwo ; Zwift Workout", "*.erg ; ERG", "*.mrc ; MRC"]
## Префикс ключей локализации ошибок разбора: `ui.plan.import.error.<ParseResult key>`.
const IMPORT_ERROR_KEY_PREFIX: String = "ui.plan.import.error."
## Действие кнопки «Эмулятор» в `%TrainerDialog`.
const TRAINER_ACTION_EMULATOR: StringName = &"emulator"

const ROW_SCENE: PackedScene = preload("res://src/ui/common/list_row.tscn")

## Ключи строк экрана (T-082, `strings_menu_lists.csv`).
const KEY_BAR_TITLE: String = "ui.plan.bar.title"
const KEY_BAR_IMPORT: String = "ui.plan.bar.import"
const KEY_BAR_RELOAD: String = "ui.plan.reload"
const KEY_SECTION_TODAY: String = "ui.plan.section.today"
const KEY_BANNER_CONNECT: String = "ui.plan.banner.connect"
const KEY_BANNER_ACTION: String = "ui.plan.banner.key_action"
const KEY_STEPS: Dictionary = {
	"one": "ui.plan.card.steps.one",
	"few": "ui.plan.card.steps.few",
	"many": "ui.plan.card.steps.many",
}
const KEY_MAX_TARGET: String = "ui.plan.card.max_target"
## Целевая нагрузка Intervals.icu (`icu_training_load`) в строке карточки (REQ-INT-04 крит. 2).
const KEY_LOAD: String = "ui.plan.card.load"
const KEY_ZONES_TITLE: String = "ui.plan.zones.title"
const KEY_ZONE_SHARE: String = "ui.plan.zones.share"
const KEY_ZONE_FREE: String = "ui.plan.zones.free"
const KEY_MORE: String = "ui.plan.preview.more"
const KEY_LESS: String = "ui.plan.preview.less"
const KEY_SHEET_CLOSE: String = "ui.plan.sheet.close"
const KEY_EMPTY_TITLE: String = "ui.plan.empty.library_title"
const KEY_EMPTY_TEXT: String = "ui.plan.empty.library_text"
const KEY_SOURCE_INTERVALS: String = "ui.plan.source_intervals"
const KEY_SOURCE_LIBRARY: String = "ui.plan.source_library"
const KEY_UNPARSED: String = "ui.plan.item.unparsed"
## Разделитель ключевых цифр карточки.
const DOT: String = " · "

## Брейкпоинт compact и предел ширины контента, lp (`ui.md` п. 3).
const COMPACT_MAX_WIDTH: float = 1100.0
const CONTENT_MAX_WIDTH: float = 1216.0
## Миниатюра в карточке (`ui.md` п. 8.3, решение ред. 2: 128×52, поля 6) и высоты крупного
## превью, lp.
const THUMB_SIZE: Vector2 = PlanPreview.ROW_THUMB_SIZE
const CHART_HEIGHT: float = 240.0
const CHART_HEIGHT_COMPACT: float = 140.0
const CHART_MIN_HEIGHT: float = 140.0
## Описание в предпросмотре — до 3 строк, дальше «Ещё».
const DESCRIPTION_LINES: int = 3
## Полоса «время в зонах», lp.
const ZONE_BAR_HEIGHT: float = 8.0

## Пользователь выбрал тренировку и нажал «Начать».
signal workout_chosen(workout: Workout, source: String)
## «На эмуляторе» (только `dev_tools_enabled`): выбранная тренировка — сразу на эмуляторе станка.
signal emulator_workout_requested(workout: Workout)
## Выбор при отсутствии станка (см. `show_trainer_choice`).
signal emulator_chosen()
signal devices_chosen()
## План загружен/обновлён (для тестов и владельца).
signal plan_loaded(result: ApiResult)
## Профиль изменён синхронизацией с Intervals.icu — владелец сохраняет.
signal profile_updated(profile: Profile)


## Полоса «время в зонах» (`ui.md` п. 8.3): доли зон плана цветами `ZonePalette`, «свободно» —
## цветом `hud.free`. Данные — `PlanScreen.zone_shares()`.
class ZoneShareBar extends Control:
	var shares: Array[Dictionary] = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, ZONE_BAR_HEIGHT)

	func set_shares(value: Array[Dictionary]) -> void:
		shares = value
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiTokens.INSET)
		var total := 0.0
		for s in shares:
			total += float(s["sec"])
		if total <= 0.0:
			return
		var x := 0.0
		for s in shares:
			var w := float(s["sec"]) / total * size.x
			draw_rect(Rect2(x, 0.0, w, size.y), PlanScreen.share_color(s))
			x += w


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
## Карточки по индексам `_items`.
var _cards: Array[ListRow] = []
var _selected: int = -1
var _loading: bool = false
var _trainer_choice_pending: bool = false
var _compact: bool = false
var _description_expanded: bool = false
## Кнопка «Эмулятор», добавленная в `%TrainerDialog` из кода (текст обновляется при смене языка).
var _emulator_button: Button = null
var _zone_bar: ZoneShareBar = null

## Инструменты разработчика (кнопка «На эмуляторе» и вариант «Эмулятор» в диалоге выбора станка):
## оболочка включает их в отладочной сборке (`AppMain.is_debug_build()`).
var dev_tools_enabled: bool = false:
	set(value):
		dev_tools_enabled = value
		if is_node_ready():
			_emulator_start_button.visible = value
			_apply_trainer_choice_texts()

@onready var _layout: VBoxContainer = %Layout
@onready var _app_bar: AppBar = %AppBar
@onready var _body: MarginContainer = %Body
@onready var _columns: HBoxContainer = %Columns
@onready var _status_label: Label = %StatusLabel
@onready var _today_header: Label = %TodayHeader
@onready var _key_banner: Banner = %KeyBanner
@onready var _today_cards: VBoxContainer = %TodayCards
@onready var _library_cards: VBoxContainer = %LibraryCards
@onready var _library_empty: EmptyState = %LibraryEmpty
@onready var _reload_button: Button = %ReloadButton
@onready var _key_dialog: IntervalsKeyDialog = %KeyDialog
@onready var _import_button: Button = %ImportButton
@onready var _library_status_label: Label = %LibraryStatusLabel
@onready var _file_dialog: FileDialog = %ImportDialog
@onready var _import_error_dialog: AcceptDialog = %ImportErrorDialog
@onready var _preview_slot: PanelContainer = %PreviewSlot
@onready var _preview: VBoxContainer = %Preview
@onready var _preview_name: Label = %PreviewName
@onready var _preview_description: Label = %PreviewDescription
@onready var _more_button: Button = %MoreButton
@onready var _preview_duration: Label = %PreviewDuration
@onready var _chart: PlanPreview = %Chart
@onready var _stats: HBoxContainer = %Stats
@onready var _stat_duration: StatView = %StatDuration
@onready var _stat_steps: StatView = %StatSteps
@onready var _stat_max: StatView = %StatMaxTarget
@onready var _zones: VBoxContainer = %Zones
@onready var _zones_title: Label = %ZonesTitle
@onready var _zone_captions: HFlowContainer = %ZoneCaptions
@onready var _start_button: Button = %StartButton
@onready var _emulator_start_button: Button = %EmulatorStartButton
@onready var _sheet: Control = %Sheet
@onready var _scrim: ColorRect = %Scrim
@onready var _sheet_panel: PanelContainer = %SheetPanel
@onready var _sheet_close: Button = %SheetClose
@onready var _sheet_scroll: ScrollContainer = %SheetScroll
@onready var _sheet_footer: HBoxContainer = %SheetFooter
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
		_app_bar.setup(app_state)
		refresh()


func _ready() -> void:
	_app_bar.setup(_app_state)
	# Действия экрана — в слот AppBar (узлы объявлены в сцене экрана, чтобы `%ImportButton` и
	# `%ReloadButton` оставались уникальными именами экрана).
	for button: Button in [_import_button, _reload_button]:
		button.reparent(_app_bar.actions_slot(), false)
		TouchTarget.attach(button, TouchTarget.Kind.UI)
	_import_button.icon = UiIcons.icon("upload")
	_reload_button.icon = UiIcons.icon("refresh-cw")
	_reload_button.pressed.connect(_on_reload_pressed)
	_import_button.pressed.connect(open_import_dialog)
	_key_banner.action_pressed.connect(open_key_form)
	_library_empty.action_pressed.connect(open_import_dialog)
	_key_dialog.submitted.connect(_on_key_submitted)
	_file_dialog.filters = FILE_FILTERS
	_file_dialog.file_selected.connect(on_import_file_selected)
	_more_button.pressed.connect(_on_more_pressed)
	_start_button.pressed.connect(start_selected)
	TouchTarget.attach(_start_button, TouchTarget.Kind.BUTTON)
	_emulator_start_button.pressed.connect(start_selected_on_emulator)
	_emulator_start_button.visible = dev_tools_enabled
	TouchTarget.attach(_emulator_start_button, TouchTarget.Kind.BUTTON)
	TouchTarget.attach(_more_button, TouchTarget.Kind.UI)
	_sheet_close.icon = UiIcons.icon("x")
	_sheet_close.pressed.connect(close_preview_sheet)
	TouchTarget.attach(_sheet_close, TouchTarget.Kind.UI)
	_scrim.color = UiTokens.SCRIM
	_scrim.gui_input.connect(_on_scrim_input)
	_trainer_dialog.confirmed.connect(_choose_devices)
	_trainer_dialog.custom_action.connect(_on_trainer_action)
	_emulator_button = _trainer_dialog.add_button(tr("ui.plan.trainer_choice.emulator"), true, TRAINER_ACTION_EMULATOR)
	_apply_trainer_choice_texts()
	DialogLayout.attach_all(self)
	_zone_bar = ZoneShareBar.new()
	_zones.add_child(_zone_bar)
	_zones.move_child(_zone_bar, _zone_captions.get_index())
	_chart.set_workout(null, 200)
	resized.connect(_update_layout)
	_preview_slot.resized.connect(_fit_chart)
	_update_layout()
	refresh()


func _notification(what: int) -> void:
	# Смена языка интерфейса: тексты, заданные из кода (а не из сцены), обновляются вручную.
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_texts()


func _unhandled_input(event: InputEvent) -> void:
	# Esc при открытом листе предпросмотра закрывает лист, а не уводит с экрана.
	if is_visible_in_tree() and _sheet.visible and event.is_action_pressed("ui_cancel", false, true):
		close_preview_sheet()
		get_viewport().set_input_as_handled()


## «Назад» внутри экрана: открытый лист предпросмотра закрывается. true — обработано.
func handle_back() -> bool:
	if _sheet.visible:
		close_preview_sheet()
		return true
	return false


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
	close_preview_sheet()
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
	_reload_button.disabled = true
	_set_status(tr("ui.plan.status.loading"))
	var result: ApiResult = await service.load_today(today)
	if generation != _load_generation or not _is_current_profile(profile):
		# Ответ устарел: профиль сменился (или запущена более новая загрузка).
		if generation == _load_generation:
			_loading = false
			_reload_button.disabled = false
		return result
	_loading = false
	_reload_button.disabled = false
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


## Баннер «Подключите Intervals.icu» (без ключа или при отказе ключа).
func key_banner() -> Banner:
	return _key_banner


## Пустое состояние библиотеки.
func library_empty_state() -> EmptyState:
	return _library_empty


func app_bar() -> AppBar:
	return _app_bar


# ---------------------------------------------------------------------------
# Карточки (REQ-UIX-03 крит. 1, 3)
# ---------------------------------------------------------------------------

## Карточки по индексам `items()`.
func cards() -> Array[ListRow]:
	return _cards.duplicate()


## Карточки в состоянии «выбрано» (не больше одной).
func selected_cards() -> Array[ListRow]:
	var out: Array[ListRow] = []
	for card in _cards:
		if card.is_selected():
			out.append(card)
	return out


## Ключевые цифры тренировки «38:00 · 12 шагов · макс. 300 Вт · нагрузка 42» (длительность —
## мм:сс или ч:мм:сс, INT-04 крит. 2; макс. цель с учётом FTP, множителя и зон профиля; без целей —
## без неё; нагрузка — `icu_training_load` из ответа Intervals.icu, если она есть, INT-04 крит. 2).
func card_numbers(workout: Workout, training_load: int = 0) -> String:
	var model := _model_for(workout)
	var parts: Array[String] = [
		IntervalsPlanService.format_duration(workout.total_duration_sec()),
		steps_text(workout.steps.size()),
	]
	var top := model.max_target_w()
	if top > 0:
		parts.append(tr(KEY_MAX_TARGET).format({"watts": top}))
	if training_load > 0:
		parts.append(tr(KEY_LOAD).format({"load": training_load}))
	return DOT.join(parts)


## «12 шагов» по правилам множественного числа языка интерфейса.
func steps_text(count: int) -> String:
	var form := plural_form(count, TranslationServer.get_locale())
	return tr(str(KEY_STEPS[form])).format({"count": count})


## Форма множественного числа: `one` / `few` / `many` (ru — три формы, остальные — две).
static func plural_form(count: int, locale: String) -> String:
	var n := absi(count)
	if locale.begins_with("ru"):
		var n10 := n % 10
		var n100 := n % 100
		if n10 == 1 and n100 != 11:
			return "one"
		if n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14):
			return "few"
		return "many"
	return "one" if n == 1 else "many"


## Время в зонах плана по кускам модели HUD-10.1 (рампа — по зонам кусков): по возрастанию
## зоны, «свободно» (`zone = 0`, `free = true`) — последним. `{zone, free, sec, pct}`,
## `pct` — округлённая доля длительности плана.
static func zone_shares(model: PlanChartModel) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if model == null or model.total_sec() <= 0:
		return out
	var by_zone: Dictionary = {}
	for piece in model.pieces():
		var zone := 0 if bool(piece["free"]) else int(piece["zone"])
		by_zone[zone] = float(by_zone.get(zone, 0.0)) + float(piece["end_sec"]) - float(piece["start_sec"])
	var zones: Array = by_zone.keys()
	zones.sort()
	if zones.has(0):
		zones.erase(0)
		zones.append(0)
	for zone: int in zones:
		var sec := float(by_zone[zone])
		if sec <= 0.0:
			continue
		out.append({"zone": zone, "free": zone == 0, "sec": sec,
			"pct": roundi(sec * 100.0 / float(model.total_sec()))})
	return out


## Цвет доли «время в зонах»: зона — `ZonePalette`, «свободно» — `hud.free`.
static func share_color(share: Dictionary) -> Color:
	if bool(share.get("free", false)):
		return UiTokens.HUD_FREE
	return ZonePalette.color(ZonePalette.power_token(int(share["zone"])))


# ---------------------------------------------------------------------------
# Выбор и предпросмотр
# ---------------------------------------------------------------------------

## Выбрать карточку (нажатие, импорт, тесты). Выбор запускаемой тренировки запоминается в
## профиле (`last_workout_id`, T-098): после перезапуска она снова предвыбрана.
func select_index(index: int) -> void:
	if index < 0 or index >= _items.size():
		_selected = -1
	else:
		_selected = index
	_sync_card_selection()
	_render_preview()
	_remember_selection()


func selected_index() -> int:
	return _selected


func selected_workout() -> Workout:
	if _selected < 0 or _selected >= _items.size():
		return null
	return _items[_selected]["workout"]


func selected_item() -> Dictionary:
	return _items[_selected] if _selected >= 0 and _selected < _items.size() else {}


## Крупное превью предпросмотра (`PlanPreview` с `detailed = true`).
func chart() -> PlanPreview:
	return _chart


func preview_name_text() -> String:
	return _preview_name.text


func preview_duration_text() -> String:
	return _preview_duration.text


## Подписи «время в зонах» предпросмотра («Z2 35 %»).
func zone_caption_texts() -> Array[String]:
	var out: Array[String] = []
	for child in _zone_captions.get_children():
		for label in child.get_children():
			if label is Label:
				out.append((label as Label).text)
	return out


## Значения статов предпросмотра: длительность, шагов, макс. цель.
func preview_stat_values() -> Array[String]:
	return [_stat_duration.value, _stat_steps.value, _stat_max.value]


## «Начать»: испустить `workout_chosen`. false — ничего не выбрано.
func start_selected() -> bool:
	var w := selected_workout()
	if w == null:
		return false
	workout_chosen.emit(w, str(_items[_selected]["source"]))
	return true


## «На эмуляторе» (отладка): выбранная тренировка — на эмулятор станка. false — ничего не
## выбрано или инструменты разработчика выключены.
func start_selected_on_emulator() -> bool:
	var w := selected_workout()
	if w == null or not dev_tools_enabled:
		return false
	emulator_workout_requested.emit(w)
	return true


## Кнопка «На эмуляторе» (видна только в отладочной сборке).
func emulator_start_button() -> Button:
	return _emulator_start_button


## Раскладка compact (телефон): предпросмотр — листом снизу.
func is_compact() -> bool:
	return _compact


## Открыть лист предпросмотра (compact). false — не compact или ничего не выбрано.
func open_preview_sheet() -> bool:
	if not _compact or selected_workout() == null:
		return false
	_sheet.visible = true
	_sheet_scroll.scroll_vertical = 0
	_start_button.grab_focus.call_deferred()
	return true


func close_preview_sheet() -> void:
	if _sheet == null or not _sheet.visible:
		return
	_sheet.visible = false
	if _selected >= 0 and _selected < _cards.size() and _cards[_selected].is_inside_tree():
		_cards[_selected].grab_focus.call_deferred()


func is_preview_sheet_open() -> bool:
	return _sheet.visible


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
		_set_library_status(tr("ui.plan.import.failed"))
		return result
	var replaced: bool = false
	for w in result.warnings:
		if str(w.get("key", "")) == "duplicate_replaced":
			replaced = true
	_set_library_status(tr("ui.plan.import.updated") if replaced else tr("ui.plan.import.done").format({"name": result.workout.name}))
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

## Станок не подключён: предложить экран устройств, а в отладочной сборке — ещё и эмулятор.
func show_trainer_choice() -> void:
	_trainer_choice_pending = true
	_apply_trainer_choice_texts()
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


## Тексты диалога выбора станка: «Эмулятор» — только в отладочной сборке (`dev_tools_enabled`,
## `ui.md` п. 8.2), в релизе текст зовёт только подключить устройства.
func _apply_trainer_choice_texts() -> void:
	if _emulator_button == null:
		return
	_emulator_button.text = tr("ui.plan.trainer_choice.emulator")
	_emulator_button.visible = dev_tools_enabled
	_trainer_dialog.dialog_text = tr("ui.plan.trainer_choice.text" if dev_tools_enabled else "ui.plan.trainer_choice.text_release")


func _on_trainer_action(action: StringName) -> void:
	if action == TRAINER_ACTION_EMULATOR and dev_tools_enabled:
		choose_emulator()


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _navigate(screen: int) -> void:
	if _app_state != null:
		_app_state.navigate(screen)


func _on_reload_pressed() -> void:
	load_today()


func _on_key_submitted(athlete_id: String, key: String) -> void:
	submit_key(athlete_id, key)


func _on_card_pressed(index: int) -> void:
	select_index(index)
	if _compact:
		open_preview_sheet()


func _on_more_pressed() -> void:
	_description_expanded = not _description_expanded
	_update_description()


func _on_scrim_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		close_preview_sheet()
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		close_preview_sheet()


func _set_status(text: String) -> void:
	_status_label.text = text


func _set_library_status(text: String) -> void:
	_library_status_label.text = text
	_library_status_label.visible = not text.is_empty()


## `profile` — по-прежнему активный профиль и профиль экрана (после `await` это не гарантировано).
func _is_current_profile(profile: Profile) -> bool:
	return profile != null and _repo != null and _repo.active_profile_id == profile.id \
		and _profile != null and _profile.id == profile.id


## Тексты, заданные из кода (сцена переводится движком сама).
func _refresh_texts() -> void:
	_app_bar.set_title(KEY_BAR_TITLE)
	_apply_bar_actions()
	_today_header.text = tr(KEY_SECTION_TODAY)
	_zones_title.text = tr(KEY_ZONES_TITLE)
	_sheet_close.tooltip_text = tr(KEY_SHEET_CLOSE)
	_library_empty.setup("upload", KEY_EMPTY_TITLE, KEY_EMPTY_TEXT, KEY_BAR_IMPORT)
	_apply_trainer_choice_texts()
	if not _items.is_empty():
		for i in mini(_items.size(), _cards.size()):
			_apply_card_texts(_cards[i], _items[i])
		_render_preview()


func _show_key_error(text: String) -> void:
	if not text.is_empty():
		_key_dialog.show_error(text)


## Модель превью с FTP, множителем и зонами профиля (как у сессии и HUD).
func _model_for(workout: Workout) -> PlanChartModel:
	return PlanChartModel.new(workout, _ftp(), _intensity(), _zones_of_profile())


func _ftp() -> int:
	return _profile.ftp_w if _profile != null else 200


func _intensity() -> float:
	return float(_profile.intensity_default) / 100.0 if _profile != null else 1.0


func _zones_of_profile() -> PowerZones:
	return _profile.effective_power_zones() if _profile != null else null


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
	_rebuild_cards()
	_selected = -1
	if not previous_id.is_empty():
		for i in _items.size():
			if _items[i]["id"] == previous_id:
				_selected = i
	# T-098 (REQ-UIX-03 крит. 3, У-14): последняя выбранная в профиле, если она есть в списке
	# и запускается; нет — правило REQ-INT-04 крит. 1.
	if _selected < 0:
		_selected = remembered_index()
	# REQ-INT-04 крит. 1: единственная тренировка на сегодня предлагается к запуску сразу.
	if _selected < 0:
		var runnable := _runnable_intervals_indices()
		if runnable.size() == 1:
			_selected = runnable[0]
	_sync_card_selection()
	_library_empty.visible = _profile != null and library_items().is_empty()


## Карточки по `_items`: Intervals.icu — в первый раздел, библиотека — во второй.
func _rebuild_cards() -> void:
	for container: VBoxContainer in [_today_cards, _library_cards]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	_cards = []
	for i in _items.size():
		var it: Dictionary = _items[i]
		var card: ListRow = ROW_SCENE.instantiate()
		var container := _today_cards if it["source"] == SOURCE_INTERVALS else _library_cards
		container.add_child(card)
		card.theme_type_variation = &"CardButton"
		card.row_id = str(it["id"])
		card.selectable = true
		card.show_chevron = false
		var workout: Workout = it["workout"]
		if workout != null:
			var thumb := PlanPreview.new()
			thumb.row_thumb = true
			thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			thumb.set_workout(workout, _ftp(), _intensity(), _zones_of_profile())
			card.add_leading(thumb)
		else:
			card.disabled = true
			card.tooltip_text = str(it["error"])
			card.set_icon("circle-alert")
		var source := Label.new()
		source.theme_type_variation = &"CaptionLabel"
		source.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		source.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		source.name = "Source"
		card.add_trailing(source)
		_apply_card_texts(card, it)
		card.pressed.connect(_on_card_pressed.bind(i))
		_cards.append(card)


func _apply_card_texts(card: ListRow, it: Dictionary) -> void:
	var workout: Workout = it["workout"]
	var numbers := card_numbers(workout, int(it["training_load"])) if workout != null else tr(KEY_UNPARSED)
	card.set_texts(str(it["name"]), numbers)
	var source := card.trailing_slot().get_node_or_null("Source") as Label
	if source != null:
		source.text = tr(KEY_SOURCE_LIBRARY if it["source"] == SOURCE_LIBRARY else KEY_SOURCE_INTERVALS)


## Ровно одна карточка «выбрано» — выбранная (или ни одной).
func _sync_card_selection() -> void:
	for i in _cards.size():
		_cards[i].set_selected(i == _selected)


## Индекс тренировки, запомненной в профиле (`last_workout_id`), или -1: не выбиралась, нет в
## списке (удалена, план другого дня) или не разобралась.
func remembered_index() -> int:
	var remembered := _profile.last_workout_id if _profile != null else ""
	if remembered.is_empty():
		return -1
	for i in _items.size():
		if str(_items[i]["id"]) == remembered and _items[i]["workout"] != null:
			return i
	return -1


## Записать выбранную тренировку в профиль (только запускаемую и только при смене).
func _remember_selection() -> void:
	var item := selected_item()
	if item.is_empty() or item["workout"] == null or _repo == null or not _is_current_profile(_profile):
		return
	var id := str(item["id"])
	if id.is_empty() or id == _profile.last_workout_id:
		return
	if _repo.set_last_workout_id(_profile.id, id).is_empty():
		_profile.last_workout_id = id


func _runnable_intervals_indices() -> Array[int]:
	var out: Array[int] = []
	for i in _items.size():
		if _items[i]["source"] == SOURCE_INTERVALS and _items[i]["workout"] != null:
			out.append(i)
	return out


func _update_status() -> void:
	_key_banner.visible = false
	if _profile == null:
		_set_status(tr("ui.plan.status.no_profile"))
		_status_label.visible = true
		_reload_button.visible = false
		return
	_reload_button.visible = true
	if _loading:
		return
	if _client != null and not _client.is_configured():
		_set_status(tr("ui.plan.status.not_configured"))
		_show_key_banner(Banner.Kind.INFO, KEY_BANNER_CONNECT)
		return
	_status_label.visible = true
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
			_show_key_banner(Banner.Kind.WARN, "ui.plan.status.reauth_required")
		ApiResult.CODE_NOT_CONFIGURED:
			_set_status(tr("ui.plan.status.not_configured"))
			_show_key_banner(Banner.Kind.INFO, KEY_BANNER_CONNECT)
		ApiResult.CODE_NETWORK:
			_set_status(tr("ui.plan.status.network_error"))
		ApiResult.CODE_RATE_LIMITED:
			_set_status(tr("ui.plan.status.rate_limited"))
		_:
			_set_status(tr("ui.plan.status.bad_response"))


## Баннер вместо строки статуса: ключ не задан или не принят (`ui.md` п. 8.3).
func _show_key_banner(kind: Banner.Kind, text_key: String) -> void:
	_key_banner.show_banner(kind, text_key, KEY_BANNER_ACTION, UiIcons.BANNER_INFO if kind == Banner.Kind.INFO else UiIcons.BANNER_WARN)
	_key_banner.visible = true
	_status_label.visible = false


## Время загрузки «ЧЧ:ММ» в локальном часовом поясе устройства (как `PlanCache.local_datetime`).
static func _format_time(unix: int) -> String:
	if unix <= 0:
		return "—"
	var dt := PlanCache.local_datetime(unix)
	return "%02d:%02d" % [dt["hour"], dt["minute"]]


func _render_preview() -> void:
	var w := selected_workout()
	var ftp := _ftp()
	# REQ-INT-05 крит. 3 / REQ-HUD-03 крит. 1: цвета сегментов — по зонам профиля, как в HUD.
	var zones := _zones_of_profile()
	_description_expanded = false
	if w == null:
		_preview_name.text = tr("ui.plan.preview.empty")
		_preview_description.text = ""
		_preview_duration.text = ""
		_chart.set_workout(null, ftp)
		_chart.visible = false
		_preview_duration.visible = false
		_stats.visible = false
		_zones.visible = false
		_start_button.disabled = true
		_emulator_start_button.disabled = true
		_update_description()
		close_preview_sheet()
		return
	_preview_name.text = w.name
	_preview_description.text = w.description
	_preview_duration.text = tr("ui.plan.preview.duration").format({"duration": IntervalsPlanService.format_duration(w.total_duration_sec()), "ftp": ftp})
	_chart.set_workout(w, ftp, _intensity(), zones)
	_chart.visible = true
	_preview_duration.visible = true
	var model := _chart.plan_model()
	_stats.visible = true
	_stat_duration.value = IntervalsPlanService.format_duration(w.total_duration_sec())
	_stat_steps.value = str(w.steps.size())
	var top := model.max_target_w() if model != null else 0
	_stat_max.value = str(top) if top > 0 else "—"
	_render_zone_shares(zone_shares(model))
	_start_button.disabled = false
	_emulator_start_button.disabled = false
	_update_description()


func _render_zone_shares(shares: Array[Dictionary]) -> void:
	for child in _zone_captions.get_children():
		_zone_captions.remove_child(child)
		child.queue_free()
	_zones.visible = not shares.is_empty()
	_zone_bar.set_shares(shares)
	for s in shares:
		# Подпись доли: цветная метка зоны и «Z2 35 %»; разрыв между подписями — вариация `Flow16`.
		var item := HBoxContainer.new()
		item.theme_type_variation = &"Row8"
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var swatch := ColorRect.new()
		swatch.color = share_color(s)
		swatch.custom_minimum_size = Vector2(ZONE_BAR_HEIGHT, ZONE_BAR_HEIGHT)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(swatch)
		var label := Label.new()
		label.theme_type_variation = &"CaptionNumLabel"
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		if bool(s["free"]):
			label.text = tr(KEY_ZONE_FREE).format({"pct": s["pct"]})
		else:
			label.text = tr(KEY_ZONE_SHARE).format({"zone": s["zone"], "pct": s["pct"]})
		item.add_child(label)
		_zone_captions.add_child(item)


## Описание: до 3 строк, длиннее — кнопка «Ещё» / «Свернуть».
func _update_description() -> void:
	_preview_description.visible = not _preview_description.text.is_empty()
	_preview_description.max_lines_visible = -1 if _description_expanded else DESCRIPTION_LINES
	_more_button.text = tr(KEY_LESS if _description_expanded else KEY_MORE)
	_check_description_overflow.call_deferred()
	_fit_chart.call_deferred()


func _check_description_overflow() -> void:
	if not is_inside_tree():
		return
	_more_button.visible = _preview_description.visible and \
		(_description_expanded or _preview_description.get_line_count() > DESCRIPTION_LINES)


# ---------------------------------------------------------------------------
# Раскладка: compact / regular, ширина контента, безопасная зона, высота превью
# ---------------------------------------------------------------------------

func _update_layout() -> void:
	if not is_node_ready():
		return
	var canvas := get_viewport_rect().size
	var compact := canvas.x < COMPACT_MAX_WIDTH
	var safe := _safe_margins()
	for control: Control in [_layout, _sheet_panel]:
		control.offset_left = safe.x
		control.offset_right = -safe.z
		control.offset_bottom = -safe.w
	_layout.offset_top = safe.y
	_body.theme_type_variation = &"ScreenMarginCompact" if compact else &"ScreenMargin"
	var margin := _body.get_theme_constant("margin_left") + _body.get_theme_constant("margin_right")
	var inner := size.x - safe.x - safe.z - float(margin)
	if inner > CONTENT_MAX_WIDTH:
		_columns.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_columns.custom_minimum_size.x = CONTENT_MAX_WIDTH
	else:
		_columns.size_flags_horizontal = Control.SIZE_FILL
		_columns.custom_minimum_size.x = 0.0
	if compact != _compact:
		_compact = compact
		_apply_bar_actions()
		if compact:
			# Лист: прокручиваемый предпросмотр, «Начать» закреплена внизу рядом с «Закрыть».
			_preview.reparent(_sheet_scroll, false)
			_start_button.reparent(_sheet_footer, false)
			_sheet_footer.move_child(_start_button, 0)
			_emulator_start_button.reparent(_sheet_footer, false)
			_sheet_footer.move_child(_emulator_start_button, 1)
		else:
			_sheet.visible = false
			_preview.reparent(_preview_slot, false)
			_start_button.reparent(_preview, false)
			_emulator_start_button.reparent(_preview, false)
	_preview_slot.visible = not compact
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_emulator_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fit_chart()


## Действия AppBar «Импорт файла» и «Обновить»: на compact — только иконки с подсказкой (на
## телефоне подписи рядом с H1 не помещаются, UIX-05 крит. 3), иначе иконка и подпись.
func _apply_bar_actions() -> void:
	for pair: Array in [[_import_button, KEY_BAR_IMPORT], [_reload_button, KEY_BAR_RELOAD]]:
		var button: Button = pair[0]
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.text = "" if _compact else tr(pair[1])
		button.tooltip_text = tr(pair[1])


## Высота крупного превью: 240 lp (compact — 140), но столько, сколько помещается в панель
## предпросмотра без переполнения, и не меньше `CHART_MIN_HEIGHT`.
func _fit_chart() -> void:
	if not is_node_ready():
		return
	var target := CHART_HEIGHT_COMPACT if _compact else CHART_HEIGHT
	if not _compact and _preview_slot.size.y > 0.0:
		var panel := _preview_slot.get_theme_stylebox("panel")
		var inner := _preview_slot.size.y - (panel.get_minimum_size().y if panel != null else 0.0)
		var others := _preview.get_combined_minimum_size().y - _chart.custom_minimum_size.y
		target = clampf(inner - others, CHART_MIN_HEIGHT, CHART_HEIGHT)
	if not is_equal_approx(_chart.custom_minimum_size.y, target):
		_chart.custom_minimum_size.y = target


## Отступы безопасной зоны (lp): `UiScale` из автозагрузки, без неё — нули.
func _safe_margins() -> Vector4:
	var runtime := TouchTarget.default_runtime()
	return runtime.safe_margins() if runtime != null else Vector4.ZERO
