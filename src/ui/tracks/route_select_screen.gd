class_name RouteSelectScreen
extends Control
## Выбор трассы свободной езды (REQ-FRD-02 крит. 1–3, REQ-FRD-03 крит. 4–6, REQ-FRD-05 крит. 1 —
## UI, REQ-UIX-03 крит. 2, 3, 5 — трасса, REQ-D3D-08 крит. 1 — названия; `docs/game/ui.md`
## п. 8.4, макет `docs/game/shots/2026-10-03-ui-mockups/tracks_1280.png`).
##
## Раскладка regular (ширина холста ≥ 1100 lp): AppBar «Свободная езда»; слева (60 %) сетка
## 2 × 2 карточек трасс каталога (`RouteCard`: полоса настроения, название, тип, миниатюра
## `RoutePreview`, три цифры), справа (40 %) деталь выбранной: H2 название, Secondary
## «тип» на языке интерфейса, крупный профиль (≈ 38 % высоты панели), три цифры, блок
## «Крутизна SIM» (слайдер 0–100 % с шагом 5) и основная кнопка «Поехать».
## Compact (телефон, < 1100 lp): сетка 2 × 2 сохраняется (с прокруткой по вертикали, если
## не помещается), деталь уезжает в лист снизу по нажатию на карточку (профиль 120 lp, цифры
## и слайдер в один ряд); системный «назад» и нажатие на вуаль закрывают лист.
##
## Ровно одна карточка выбрана (`ButtonGroup`). Предвыбор — `profile.last_route_id`
## (неизвестный id → `RouteCatalog.DEFAULT_ID`), крутизна — `profile.sim_steepness_pct`.
## Выбор трассы и крутизна сохраняются в активном профиле сразу при изменении; «Поехать»
## отдаёт `start_requested(route_id, steepness_pct)` — запуск делает оболочка (T-084).

## «Поехать»: выбранная трасса каталога и крутизна SIM, % (0–100, шаг 5).
signal start_requested(route_id: String, steepness_pct: int)

const STAT_SCENE: PackedScene = preload("res://src/ui/common/stat_view.tscn")

const KEY_TITLE: String = "ui.tracks.title"
const KEY_STEEPNESS: String = "ui.tracks.steepness"
const KEY_START: String = "ui.tracks.start"

## Брейкпоинт compact по ширине холста, lp (`ui.md` п. 3) — тот же, что у AppBar.
const COMPACT_MAX_WIDTH: float = AppBar.COMPACT_MAX_WIDTH
## Контент экрана не шире 1216 lp (`ui.md` п. 3).
const CONTENT_MAX_WIDTH: float = 1216.0
## Карточек в ряду сетки.
const GRID_COLUMNS: int = 2
## Доля высоты панели детали под крупный профиль (`ui.md` п. 8.4) и высота профиля в листе.
const LARGE_PREVIEW_FRACTION: float = 0.38
const SHEET_PREVIEW_HEIGHT: float = 120.0
## Полоса настроения карточки, lp (`ui.md` п. 8.4).
const MOOD_BAR_SIZE: Vector2 = Vector2(6, 22)
## Отступ листа от верхнего края холста, lp.
const SHEET_TOP_GAP: float = 16.0

## Подписи цифр по id стата модели превью: ключ единицы и ключ подписи.
const STAT_KEYS: Dictionary = {
	RoutePreviewModel.STAT_LENGTH: [RoutePreviewModel.KEY_UNIT_KM, RoutePreviewModel.KEY_STAT_LAP],
	RoutePreviewModel.STAT_ASCENT: [RoutePreviewModel.KEY_UNIT_M, RoutePreviewModel.KEY_STAT_ASCENT],
	RoutePreviewModel.STAT_MAX_GRADE: [RoutePreviewModel.KEY_UNIT_PCT, RoutePreviewModel.KEY_STAT_MAX_GRADE],
}


## Карточка трассы (`CardButton`, `toggle_mode`): содержимое — дочерняя раскладка без приёма
## мыши, поэтому нажатие, наведение, фокус и Enter работают у самой кнопки.
class RouteCard extends Button:
	var route_id: String = ""
	var model: RoutePreviewModel = null
	var preview: RoutePreview = null
	var stats: Array[StatView] = []
	var mood_bar: ColorRect = null
	var title_label: Label = null
	var kind_label: Label = null
	var _content: MarginContainer = null
	var _touch: TouchTarget = null

	func _init(route: RouteCatalog.RouteDef) -> void:
		route_id = route.id
		model = RoutePreviewModel.for_route(route)
		name = "Card_" + route.id
		text = ""
		theme_type_variation = &"CardButton"
		toggle_mode = true
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		_content = MarginContainer.new()
		_content.theme_type_variation = &"CardMargin"
		_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_content)
		var box := VBoxContainer.new()
		box.theme_type_variation = &"Stack12"
		_content.add_child(box)
		var header := HBoxContainer.new()
		header.theme_type_variation = &"Row8"
		box.add_child(header)
		mood_bar = ColorRect.new()
		mood_bar.color = model.mood_color
		mood_bar.custom_minimum_size = MOOD_BAR_SIZE
		mood_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header.add_child(mood_bar)
		title_label = _label(&"TitleLabel")
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Название трассы — данные каталога: длинное сокращается «…» (UIX-05 крит. 3).
		title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title_label.clip_text = true
		header.add_child(title_label)
		kind_label = _label(&"CaptionLabel")
		header.add_child(kind_label)
		preview = RoutePreview.new()
		preview.name = "Preview"
		preview.mode = RoutePreviewModel.Mode.THUMB
		preview.model = model
		preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(preview)
		var row := HBoxContainer.new()
		row.theme_type_variation = &"Row24"
		box.add_child(row)
		stats = RouteSelectScreen.add_stats(row, model)
		_ignore_mouse(_content)
		apply_texts()

	func _ready() -> void:
		_touch = TouchTarget.attach(self, TouchTarget.Kind.UI)
		_content.minimum_size_changed.connect(_update_min_size)
		_update_min_size()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_TRANSLATION_CHANGED:
			apply_texts()

	## Тексты на языке интерфейса (название и тип — `track.<id>.name` / `.kind`).
	func apply_texts() -> void:
		if title_label == null:
			return
		title_label.text = tr(model.name_key)
		kind_label.text = tr(model.kind_key)
		RouteSelectScreen.apply_stats(stats, model)

	func is_selected() -> bool:
		return button_pressed

	func _update_min_size() -> void:
		if _touch != null:
			_touch.set_floor(_content.get_combined_minimum_size())

	static func _label(variation: StringName) -> Label:
		var label := Label.new()
		label.theme_type_variation = variation
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return label

	static func _ignore_mouse(node: Node) -> void:
		var control := node as Control
		if control != null:
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in node.get_children():
			_ignore_mouse(child)


var _repo: ProfileRepository
var _app_state: AppState
var _cards: Array[RouteCard] = []
var _group: ButtonGroup = ButtonGroup.new()
var _selected_id: String = ""
var _detail_stats: Array[StatView] = []
var _compact: bool = false
var _sheet_open: bool = false
var _last_save_errors: Array[String] = []

@onready var _root: VBoxContainer = %Root
@onready var _app_bar: AppBar = %AppBar
@onready var _margin: MarginContainer = %Margin
@onready var _body: HBoxContainer = %Body
@onready var _grid: VBoxContainer = %Grid
@onready var _detail: PanelContainer = %Detail
@onready var _route_name: Label = %RouteName
@onready var _route_subtitle: Label = %RouteSubtitle
@onready var _large_preview: RoutePreview = %LargePreview
@onready var _detail_box: VBoxContainer = %DetailBox
@onready var _detail_content: VBoxContainer = %DetailContent
@onready var _info: BoxContainer = %Info
@onready var _detail_stats_row: HBoxContainer = %DetailStats
@onready var _steepness_title: Label = %SteepnessTitle
@onready var _steepness_value: Label = %SteepnessValue
@onready var _slider: HSlider = %SteepnessSlider
@onready var _start_button: Button = %StartButton
@onready var _sheet: Control = %Sheet
@onready var _scrim: ColorRect = %Scrim
@onready var _sheet_slot: VBoxContainer = %SheetSlot


func setup(repo: ProfileRepository, app_state: AppState) -> void:
	_repo = repo
	_app_state = app_state
	if is_node_ready():
		_app_bar.setup(app_state)


func _ready() -> void:
	_app_bar.setup(_app_state)
	_app_bar.set_title(KEY_TITLE)
	_expose_back_button()
	_slider.min_value = Profile.MIN_SIM_STEEPNESS_PCT
	_slider.max_value = Profile.MAX_SIM_STEEPNESS_PCT
	_slider.step = Profile.SIM_STEEPNESS_STEP_PCT
	_slider.value_changed.connect(_on_slider_changed)
	_start_button.pressed.connect(start)
	_scrim.color = UiTokens.SCRIM
	_scrim.gui_input.connect(_on_scrim_input)
	_detail.resized.connect(_update_preview_height)
	resized.connect(_update_content_width)
	_build_cards()
	_detail_stats = add_stats(_detail_stats_row, null)
	TouchTarget.attach(_start_button, TouchTarget.Kind.BUTTON)
	TouchTarget.attach_all(self)
	_large_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_select(preselected_route_id(), false)
	_set_slider(preselected_sim_steepness_pct())
	_apply_texts()
	_update_layout()


func _enter_tree() -> void:
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_update_layout):
		viewport.size_changed.connect(_update_layout)
	var scale_source := TouchTarget.default_runtime()
	if scale_source != null and not scale_source.scale_changed.is_connected(_on_scale_changed):
		scale_source.scale_changed.connect(_on_scale_changed)


func _exit_tree() -> void:
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_update_layout):
		viewport.size_changed.disconnect(_update_layout)
	var scale_source := TouchTarget.default_runtime()
	if scale_source != null and scale_source.scale_changed.is_connected(_on_scale_changed):
		scale_source.scale_changed.disconnect(_on_scale_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_texts()


## Перечитать профиль при входе на экран: предвыбрать трассу и крутизну, закрыть лист.
func refresh() -> void:
	if not is_node_ready():
		return
	close_sheet()
	_select(preselected_route_id(), false)
	_set_slider(preselected_sim_steepness_pct())
	_update_layout()


## Трасса, предвыбранная при открытии экрана (REQ-FRD-02 крит. 3): последняя выбранная
## в активном профиле, при первом запуске — `Profile.DEFAULT_ROUTE_ID`; id, которого нет
## в каталоге, — трасса каталога по умолчанию.
func preselected_route_id() -> String:
	var active: Profile = _repo.get_active() if _repo != null else null
	return RouteCatalog.resolve_id(active.effective_route_id() if active != null else Profile.DEFAULT_ROUTE_ID)


## Крутизна SIM активного профиля, % (REQ-FRD-05 крит. 1) — начальное значение слайдера.
func preselected_sim_steepness_pct() -> int:
	var active: Profile = _repo.get_active() if _repo != null else null
	return active.sim_steepness_pct if active != null else Profile.DEFAULT_SIM_STEEPNESS_PCT


## Системный «назад» (Esc, Android): открытый лист детали закрывается (true); иначе решает
## стек `AppState` (false).
func handle_back() -> bool:
	if _sheet_open:
		close_sheet()
		return true
	return false


## Кнопка «назад»: на экран, с которого пришли (REQ-UIX-04 крит. 1).
func back() -> void:
	_app_bar.press_back()


## «Поехать»: сохранить выбор в профиле и отдать трассу и крутизну оболочке.
func start() -> void:
	_save_route(_selected_id)
	_save_steepness(steepness_pct())
	close_sheet()
	start_requested.emit(_selected_id, steepness_pct())


## Выбрать трассу (как нажатием на карточку): сохраняется в профиле, на compact открывается лист.
func select_route(route_id: String) -> void:
	_select(RouteCatalog.resolve_id(route_id), true)
	if _compact:
		open_sheet()


func selected_route_id() -> String:
	return _selected_id


## Крутизна SIM на слайдере, %.
func steepness_pct() -> int:
	return int(_slider.value)


## Задать крутизну (как слайдером): приводится к 0–100 с шагом 5 и сохраняется в профиле.
func set_steepness_pct(pct: int) -> void:
	_slider.value = Profile.snap_sim_steepness(pct)


func cards() -> Array[RouteCard]:
	return _cards.duplicate()


func card_for(route_id: String) -> RouteCard:
	for card in _cards:
		if card.route_id == route_id:
			return card
	return null


## Число выбранных карточек (REQ-UIX-03 крит. 3: ровно одна).
func selected_card_count() -> int:
	var count := 0
	for card in _cards:
		if card.is_selected():
			count += 1
	return count


func start_button() -> Button:
	return _start_button


func steepness_slider() -> HSlider:
	return _slider


func steepness_value_text() -> String:
	return _steepness_value.text


func detail_panel() -> PanelContainer:
	return _detail


func large_preview() -> RoutePreview:
	return _large_preview


func detail_name_text() -> String:
	return _route_name.text


func detail_subtitle_text() -> String:
	return _route_subtitle.text


func detail_stats() -> Array[StatView]:
	return _detail_stats.duplicate()


func app_bar() -> AppBar:
	return _app_bar


func is_compact() -> bool:
	return _compact


func is_sheet_open() -> bool:
	return _sheet_open


## Коды ошибок последнего сохранения выбора в профиле (пусто — сохранено).
func last_save_errors() -> Array[String]:
	return _last_save_errors.duplicate()


## Открыть лист детали (только compact). С клавиатурой фокус уходит в лист («Поехать»),
## чтобы обход не шёл по карточкам под вуалью; на сенсорном экране кольцо фокуса не нужно.
func open_sheet() -> void:
	if not _compact:
		return
	_sheet_open = true
	_sheet.visible = true
	if is_visible_in_tree() and not _is_touch_device():
		_start_button.grab_focus()


## Закрыть лист; фокус возвращается на выбранную карточку.
func close_sheet() -> void:
	var was_open := _sheet_open
	_sheet_open = false
	_sheet.visible = false
	if was_open and is_visible_in_tree() and not _is_touch_device():
		var card := card_for(_selected_id)
		if card != null:
			card.grab_focus()


static func _is_touch_device() -> bool:
	var scale_source := TouchTarget.default_runtime()
	return scale_source != null and scale_source.device != UiScale.Device.DESKTOP


# ---------------------------------------------------------------------------
# Цифры (общие для карточки и детали)
# ---------------------------------------------------------------------------

## Три `StatView` (длина, набор, макс. уклон) в `row`; `model` — сразу заполнить.
static func add_stats(row: HBoxContainer, model: RoutePreviewModel) -> Array[StatView]:
	var out: Array[StatView] = []
	for i in STAT_KEYS.size():
		var stat: StatView = STAT_SCENE.instantiate()
		stat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(stat)
		out.append(stat)
	if model != null:
		apply_stats(out, model)
	return out


## Цифры модели превью в статы: значение — данные, единица и подпись — ключи перевода.
static func apply_stats(stats: Array[StatView], model: RoutePreviewModel) -> void:
	var values := model.stats()
	for i in mini(values.size(), stats.size()):
		var item: Dictionary = values[i]
		var keys: Array = STAT_KEYS[item["id"]]
		stats[i].set_stat(str(item["value"]), str(keys[0]), str(keys[1]))


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _build_cards() -> void:
	var row: HBoxContainer = null
	for route in RouteCatalog.all():
		if row == null or row.get_child_count() >= GRID_COLUMNS:
			row = HBoxContainer.new()
			row.theme_type_variation = &"Row16"
			row.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_grid.add_child(row)
		var card := RouteCard.new(route)
		card.button_group = _group
		card.pressed.connect(select_route.bind(card.route_id))
		row.add_child(card)
		_cards.append(card)


func _select(route_id: String, save: bool) -> void:
	_selected_id = route_id
	for card in _cards:
		card.set_pressed_no_signal(card.route_id == route_id)
	var card := card_for(route_id)
	_large_preview.model = card.model if card != null else null
	_apply_detail_texts()
	if save:
		_save_route(route_id)


func _set_slider(pct: int) -> void:
	_slider.set_value_no_signal(Profile.snap_sim_steepness(pct))
	_apply_steepness_text()


func _on_slider_changed(value: float) -> void:
	var pct := Profile.snap_sim_steepness(value)
	if not is_equal_approx(value, pct):
		_slider.set_value_no_signal(pct)
	_apply_steepness_text()
	_save_steepness(pct)


func _save_route(route_id: String) -> void:
	var active: Profile = _repo.get_active() if _repo != null else null
	if active == null or active.last_route_id == route_id:
		return
	_last_save_errors = _repo.set_last_route_id(active.id, route_id)


func _save_steepness(pct: int) -> void:
	var active: Profile = _repo.get_active() if _repo != null else null
	if active == null or active.sim_steepness_pct == pct:
		return
	_last_save_errors = _repo.set_sim_steepness_pct(active.id, pct)


func _apply_texts() -> void:
	_steepness_title.text = tr(KEY_STEEPNESS)
	_start_button.text = tr(KEY_START)
	_apply_detail_texts()
	_apply_steepness_text()


func _apply_detail_texts() -> void:
	var card := card_for(_selected_id)
	if card == null:
		return
	_route_name.text = tr(card.model.name_key)
	_route_subtitle.text = _subtitle_for(card.model)
	apply_stats(_detail_stats, card.model)


## Вторая строка детали — только тип трассы на языке интерфейса («горы»): второе название на
## другом языке убрано (`ui.md` п. 8.4, решение ред. 2).
func _subtitle_for(model: RoutePreviewModel) -> String:
	return tr(model.kind_key)


func _apply_steepness_text() -> void:
	_steepness_value.text = "%d %s" % [steepness_pct(), tr(RoutePreviewModel.KEY_UNIT_PCT)]


## Кнопка «назад» AppBar доступна экрану как `%BackButton` (контракт заготовки T-061 и тестов
## навигации): узел переименовывается и переходит во владение экрана.
func _expose_back_button() -> void:
	var back_button := _app_bar.back_button()
	back_button.name = "BackButton"
	back_button.owner = self
	back_button.unique_name_in_owner = true


func _on_scale_changed(_scale: float) -> void:
	_update_layout()


func _on_scrim_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	var mouse := event as InputEventMouseButton
	if (touch != null and touch.pressed) or (mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT):
		close_sheet()
		accept_event()


## Раскладка по ширине холста: regular — деталь справа, compact — деталь в листе снизу.
## Отступы корня — безопасная зона (`UiScale.safe_margins`, UIX-05 крит. 2).
func _update_layout() -> void:
	if not is_node_ready() or not is_inside_tree():
		return
	var safe := Vector4.ZERO
	var scale_source := TouchTarget.default_runtime()
	if scale_source != null:
		safe = scale_source.safe_margins()
	_root.offset_left = safe.x
	_root.offset_top = safe.y
	_root.offset_right = -safe.z
	_root.offset_bottom = -safe.w
	_sheet_slot.offset_left = safe.x
	_sheet_slot.offset_top = safe.y + SHEET_TOP_GAP
	_sheet_slot.offset_right = -safe.z
	_sheet_slot.offset_bottom = -safe.w
	var compact := get_viewport_rect().size.x < COMPACT_MAX_WIDTH
	if compact != _compact or _detail.get_parent() == null:
		_compact = compact
		_margin.theme_type_variation = &"ScreenMarginCompact" if compact else &"ScreenMargin"
		# Лист на телефоне низкий (холст ≈ 400 lp): отступы плотнее, цифры и слайдер в один ряд.
		_detail_box.theme_type_variation = &"Stack12" if compact else &"Stack16"
		_detail_content.theme_type_variation = &"Stack12" if compact else &"Stack16"
		_info.vertical = not compact
		_info.theme_type_variation = &"Row24" if compact else &"Stack16"
		# В листе снизу — стиль листа (`SheetPanel`: скругление только сверху, тень), рядом с сеткой — панель.
		_detail.theme_type_variation = &"SheetPanel" if compact else &""
		var target: Container = _sheet_slot if compact else _body
		if _detail.get_parent() != target:
			_detail.reparent(target, false)
		if not compact:
			close_sheet()
	_update_preview_height()
	_update_content_width()


func _update_preview_height() -> void:
	if _large_preview == null:
		return
	var height: float = SHEET_PREVIEW_HEIGHT if _compact else roundf(_detail.size.y * LARGE_PREVIEW_FRACTION)
	_large_preview.custom_minimum_size.y = maxf(height, RoutePreview.LARGE_MIN_HEIGHT)


## Ширина контента — не больше `CONTENT_MAX_WIDTH`, по центру. Считается от размера экрана
## (он задан якорями, а не содержимым), чтобы минимальная ширина не замыкалась сама на себя.
func _update_content_width() -> void:
	var inner: float = size.x + _root.offset_right - _root.offset_left \
			- float(_margin.get_theme_constant("margin_left") + _margin.get_theme_constant("margin_right"))
	_body.custom_minimum_size.x = clampf(inner, 0.0, CONTENT_MAX_WIDTH)
