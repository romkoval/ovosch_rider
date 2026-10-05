class_name HistoryScreen
extends Control
## Экран истории заездов (`AppState.Screen.HISTORY`; `docs/game/ui.md` п. 8.5): REQ-UIX-04
## крит. 1, 3, 4 (история), REQ-FRD-07 крит. 6 (свободная езда наравне с тренировками),
## REQ-LOC-02 крит. 1, 2, REQ-PRF-04 крит. 1, REQ-LOC-06, REQ-STR-05 крит. 2.
##
## Раскладка: `AppBar` «История» («назад» → `AppState.go_back()`, справа фильтр-фишки
## «Все / План / Свободная»), под ним список заездов активного профиля (`RideRepository.list`,
## новые сверху) группами по месяцам («ОКТЯБРЬ 2026»). Строка — `ListRow` (вариация темы
## `ListRowButton`): слева метка режима «ПЛАН» (`accent`) / «SIM» (`sim`), у заезда на эмуляторе
## рядом — метка «ЭМУЛЯТОР» (Overline `text2`, T-160), дата и отметка
## (Caption) над названием (Title; у свободной езды без названия — «Свободная езда — <трасса>»),
## справа колонки фиксированной ширины с `tnum` — время, км, ср. Вт, NP, набор (у свободной
## езды; единицы — в заголовке колонок над списком), значок статуса Strava, шеврон; внизу строки
## полоса времени в зонах 4 lp. Compact (холст уже 1100 lp) — три колонки: время, км, ср. Вт.
## Пустая история — `EmptyState` (иконка `history`, «Заездов пока нет», «На главный»).
## Контент — не шире 1216 lp по центру, отступы безопасной зоны — `UiScale.safe_margins()`.
##
## Строки создаются страницами по `PAGE_SIZE` по мере прокрутки (500 заездов — ≤ 1 с,
## LOC-02 крит. 2); данные списка (`summaries()`, `rows()`) — все заезды под фильтром сразу.
## `rows()` — строка заезда текстом (`row_text`, ключ `ui.history.row`): для тестов и
## доступности, на экране не показывается.
## Выбор строки открывает карточку `RideDetail`; её «назад» и Esc возвращают к списку, удаление
## — к списку с сигналом владельцу. Строки — ключи `ui.history.*`.

## Пользователь запросил выгрузку заезда в Strava (из карточки) с названием и описанием
## из её полей (REQ-STR-03 крит. 3; пустые — значения по умолчанию).
signal upload_requested(ride_id: String, ride_name: String, description: String)
## Заезд удалён из хранилища через карточку (REQ-LOC-06 крит. 1): владелец убирает
## элемент очереди Strava, если он был.
signal ride_deleted(ride_id: String)

const ROW_SCENE: PackedScene = preload("res://src/ui/common/list_row.tscn")
## Брейкпоинт compact и предел ширины контента, lp (`ui.md` п. 3).
const COMPACT_MAX_WIDTH: float = AppBar.COMPACT_MAX_WIDTH
const CONTENT_MAX_WIDTH: float = 1216.0
## Строк за один раз (первая страница и догрузка при прокрутке к концу).
const PAGE_SIZE: int = 40
## Догружать, когда до конца прокрутки осталось меньше стольких lp.
const LOAD_MORE_THRESHOLD: float = 600.0
## Ширина метки режима слева в строке, lp (заголовок колонок выровнен по ней).
const MODE_LABEL_WIDTH: float = 44.0
## Значок статуса Strava, lp.
const STRAVA_ICON_SIZE: float = 20.0
## Полоса времени в зонах внизу строки, lp.
const ROW_ZONE_BAR_HEIGHT: float = 4.0
## Заголовок группы: отступ сверху (24) + строка Overline (16), текст прижат к низу, lp.
const MONTH_HEADER_HEIGHT: float = 40.0
const FILTER_KEYS: Dictionary = {
	HistoryFormat.Filter.ALL: "ui.history.filter.all",
	HistoryFormat.Filter.PLAN: "ui.history.filter.plan",
	HistoryFormat.Filter.FREE: "ui.history.filter.free",
}
const KEY_EMPTY_TITLE: String = "ui.history.empty.title"
const KEY_EMPTY_TEXT: String = "ui.history.empty.text"
const KEY_EMPTY_ACTION: String = "ui.history.empty.action"
const KEY_FILTERED_TITLE: String = "ui.history.empty.filtered_title"
const KEY_FILTERED_TEXT: String = "ui.history.empty.filtered_text"
const KEY_FILTERED_ACTION: String = "ui.history.empty.filtered_action"

var _rides: RideRepository = null
var _profiles: ProfileRepository = null
var _app_state: AppState = null
## Все заезды активного профиля (новые сверху) и те, что под фильтром.
var _all: Array[RideSummary] = []
var _summaries: Array[RideSummary] = []
var _filter: HistoryFormat.Filter = HistoryFormat.Filter.ALL
var _strava_linked: bool = false
var _compact: bool = false
## Созданные строки (по порядку `_summaries`) и последняя группа месяца.
var _row_nodes: Array[ListRow] = []
var _group_rows: VBoxContainer = null
var _group_month: int = -1
var _filter_chips: Dictionary = {}
## Догрузка страницы уже запрошена (отложенный вызов) — не дублировать.
var _page_pending: bool = false
var _filter_group := ButtonGroup.new()

@onready var _list_panel: Control = %ListPanel
@onready var _app_bar: AppBar = %AppBar
@onready var _margin: MarginContainer = %Margin
@onready var _column: VBoxContainer = %Column
@onready var _scroll: ScrollContainer = %Scroll
@onready var _column_header: MarginContainer = %ColumnHeader
@onready var _column_titles: HBoxContainer = %ColumnTitles
@onready var _groups: VBoxContainer = %Groups
@onready var _empty: EmptyState = %Empty
@onready var _detail: RideDetail = %Detail


func setup(rides: RideRepository, profiles: ProfileRepository, app_state: AppState) -> void:
	if _rides != null and _rides.rides_changed.is_connected(_on_rides_changed):
		_rides.rides_changed.disconnect(_on_rides_changed)
	_rides = rides
	_profiles = profiles
	_app_state = app_state
	if _rides != null:
		_rides.rides_changed.connect(_on_rides_changed)
	if is_node_ready():
		_app_bar.setup(app_state)
		refresh()


func _ready() -> void:
	_app_bar.setup(_app_state)
	_expose_back_button()
	_build_filter_chips()
	_empty.action_pressed.connect(_on_empty_action)
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scroll_changed)
	_scroll.resized.connect(_on_scroll_changed.bind(0.0))
	_detail.back_requested.connect(back_to_list)
	_detail.deleted.connect(_on_ride_deleted)
	_detail.upload_requested.connect(_on_detail_upload_requested)
	_detail.set_strava_linked(_strava_linked)
	resized.connect(_update_content_width)
	_update_layout()
	if _rides != null:
		refresh()
	else:
		back_to_list()


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
		_apply_filter_texts()
		_rebuild_list()


## Перечитать список заездов активного профиля и показать его.
func refresh() -> void:
	if not is_node_ready():
		return
	_all = []
	var profile: Profile = _profiles.get_active() if _profiles != null else null
	if _rides != null and profile != null:
		_all = _rides.list(profile.id)
	_apply_filter()
	# Если открытая карточка ещё в списке — перечитываем заезд (статус Strava
	# и т.п., REQ-STR-05 крит. 2) и оставляем её; иначе — к списку.
	var shown := _detail.ride()
	if shown != null and _find_index(shown.id) >= 0 and _detail.visible and _detail.reload():
		return
	back_to_list()


## Строка списка текстом (REQ-LOC-02 крит. 1): для тестов и доступности.
func row_text(s: RideSummary) -> String:
	var flags: String = ""
	if s.in_progress:
		flags = tr("ui.history.row.in_progress")
	elif s.recovered:
		flags = tr("ui.history.detail.recovered")
	elif s.stopped_early:
		flags = tr("ui.history.detail.stopped_early")
	return tr("ui.history.row").format({
		"date": format_date_time(s.started_at_unix),
		"name": HistoryFormat.summary_title(s),
		"time": HudModel.format_elapsed(s.duration_sec),
		"distance": "%.1f" % (s.distance_m / 1000.0),
		"avg": RideDetail.number_text(s.avg_power_w),
		"np": RideDetail.number_text(s.normalized_power_w),
		"strava": tr(strava_status_key(s.strava_status)),
		"flags": flags,
	}).strip_edges()


## Строки всех заездов под фильтром текстом (`row_text`), по порядку списка.
func rows() -> Array[String]:
	var out: Array[String] = []
	for s in _summaries:
		out.append(row_text(s))
	return out


## Заезды под фильтром, новые сверху.
func summaries() -> Array[RideSummary]:
	return _summaries


func row_count() -> int:
	return _summaries.size()


## Созданные на экране строки (`ListRow`) по порядку списка; остальные — при прокрутке.
func row_nodes() -> Array[ListRow]:
	return _row_nodes


## Строка заезда на экране (null — заезда нет под фильтром или строка ещё не создана).
func row_for(ride_id: String) -> ListRow:
	for row in _row_nodes:
		if row.row_id == ride_id:
			return row
	return null


## Текст метки «Эмулятор» в строке заезда ("" — метки нет или строка не создана; T-160).
func row_emulator_text(ride_id: String) -> String:
	var row := row_for(ride_id)
	if row == null:
		return ""
	var label := row.leading_slot().get_node_or_null(^"EmulatorLabel") as Label
	return label.text if label != null else ""


## Создать строки до индекса `index` включительно (как прокрутка к нему).
func ensure_row(index: int) -> ListRow:
	while _row_nodes.size() <= index and _row_nodes.size() < _summaries.size():
		_render_page()
	return _row_nodes[index] if index >= 0 and index < _row_nodes.size() else null


## Подписи заголовков колонок (единицы).
func column_titles() -> Array[String]:
	var out: Array[String] = []
	for child in _column_titles.get_children():
		out.append((child as Label).text)
	return out


## Открыть карточку заезда по индексу строки.
func select_index(index: int) -> void:
	if index < 0 or index >= _summaries.size():
		return
	show_ride(_summaries[index].ride_id)


## Открыть карточку заезда по id. false — заезда нет.
func show_ride(ride_id: String) -> bool:
	if _rides == null:
		return false
	var ride := _rides.get_ride(ride_id)
	if ride == null:
		return false
	_detail.show_ride(ride, _rides)
	_detail.visible = true
	_list_panel.visible = false
	return true


## Закрыть карточку и вернуться к списку; фокус клавиатуры — на строку открытого заезда.
func back_to_list() -> void:
	var had_focus: bool = false
	var focus_owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus_owner != null and _detail.is_ancestor_of(focus_owner):
		had_focus = true
	var shown := _detail.ride()
	_detail.close_menu()
	_detail.visible = false
	_list_panel.visible = true
	if had_focus and shown != null:
		var row := row_for(shown.id)
		if row != null:
			row.grab_focus()


## Системный «назад» (Esc, Android): открытая карточка закрывается (true); иначе решает
## стек `AppState` (false).
func handle_back() -> bool:
	if _detail.visible:
		back_to_list()
		return true
	return false


func detail() -> RideDetail:
	return _detail


func app_bar() -> AppBar:
	return _app_bar


func empty_state() -> EmptyState:
	return _empty


func is_detail_visible() -> bool:
	return _detail.visible


## Видно ли пустое состояние (заездов нет — или нет под фильтром).
func is_empty_label_visible() -> bool:
	return _empty.visible


func is_compact() -> bool:
	return _compact


## Фильтр списка: все, по плану, свободная езда.
func set_filter(value: HistoryFormat.Filter) -> void:
	_filter = value
	var chip: Button = _filter_chips.get(value)
	if chip != null:
		chip.set_pressed_no_signal(true)
	_apply_filter()


func filter() -> HistoryFormat.Filter:
	return _filter


func filter_chip(value: HistoryFormat.Filter) -> Button:
	return _filter_chips.get(value)


func set_strava_linked(linked: bool) -> void:
	_strava_linked = linked
	if is_node_ready():
		_detail.set_strava_linked(linked)


## «На главный» из пустого состояния.
func go_home() -> void:
	if _app_state != null:
		_app_state.navigate(AppState.Screen.HOME)


## Дата и время старта в локальном времени: `ГГГГ-ММ-ДД ЧЧ:ММ`.
static func format_date_time(unix: int) -> String:
	var d := HistoryFormat.local_datetime(unix)
	return "%04d-%02d-%02d %02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"]]


## Ключ перевода статуса Strava (REQ-STR-05 крит. 1).
static func strava_status_key(status: String) -> String:
	return "ui.history.strava." + (status if Ride.UPLOAD_STATUSES.has(status) else Ride.UPLOAD_NONE)


# ---------------------------------------------------------------------------
# Список
# ---------------------------------------------------------------------------

func _apply_filter() -> void:
	_summaries = []
	for s in _all:
		if HistoryFormat.matches(s, _filter):
			_summaries.append(s)
	_rebuild_list()


func _rebuild_list() -> void:
	if not is_node_ready():
		return
	# Строки — свои узлы, пересборка не вызывается из их сигналов: освобождаем сразу.
	for child in _groups.get_children():
		_groups.remove_child(child)
		child.free()
	_row_nodes = []
	_group_rows = null
	_group_month = -1
	_build_column_titles()
	var has_rows: bool = not _summaries.is_empty()
	_scroll.visible = has_rows
	_empty.visible = not has_rows
	if _all.is_empty():
		_empty.setup("history", KEY_EMPTY_TITLE, KEY_EMPTY_TEXT, KEY_EMPTY_ACTION)
	else:
		_empty.setup("history", KEY_FILTERED_TITLE, KEY_FILTERED_TEXT, KEY_FILTERED_ACTION)
	_scroll.scroll_vertical = 0
	if has_rows:
		_render_page()


## Следующая страница строк (с заголовками месяцев).
func _render_page() -> void:
	var first: int = _row_nodes.size()
	var last: int = mini(first + PAGE_SIZE, _summaries.size())
	for i in range(first, last):
		var s := _summaries[i]
		var month := HistoryFormat.month_key(s.started_at_unix)
		if month != _group_month or _group_rows == null:
			if not _row_nodes.is_empty():
				_row_nodes[_row_nodes.size() - 1].divider = false
			_add_group(s)
			_group_month = month
		var row := _make_row(s, _group_rows)
		row.divider = true
		_row_nodes.append(row)
	if _row_nodes.size() == _summaries.size() and not _row_nodes.is_empty():
		_row_nodes[_row_nodes.size() - 1].divider = false


func _add_group(s: RideSummary) -> void:
	var group := VBoxContainer.new()
	group.theme_type_variation = &"Stack8"
	var header := Label.new()
	header.theme_type_variation = &"OverlineLabel"
	header.uppercase = true
	header.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	header.text = HistoryFormat.month_header(s.started_at_unix)
	header.custom_minimum_size.y = MONTH_HEADER_HEIGHT
	header.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	group.add_child(header)
	_group_rows = VBoxContainer.new()
	_group_rows.theme_type_variation = &"Stack0"
	group.add_child(_group_rows)
	_groups.add_child(group)


## Строка заезда; добавляется в `parent` сразу (слоты строки готовы только после `_ready`).
func _make_row(s: RideSummary, parent: Container) -> ListRow:
	var row: ListRow = ROW_SCENE.instantiate()
	parent.add_child(row)
	row.row_id = s.ride_id
	row.set_texts(HistoryFormat.summary_title(s), "", HistoryFormat.row_overline(s))
	var mode := Label.new()
	mode.theme_type_variation = HistoryFormat.mode_variation(s.is_free_ride())
	mode.uppercase = true
	mode.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	mode.text = HistoryFormat.mode_text(s.is_free_ride())
	mode.custom_minimum_size.x = MODE_LABEL_WIDTH
	mode.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_leading(mode)
	if s.is_emulator():
		row.add_leading(_make_emulator_label())
	row.set_columns(HistoryFormat.columns(s, _compact), HistoryFormat.column_widths(_compact), &"NumLabel")
	var icon_spec := HistoryFormat.strava_icon(s.strava_status)
	var icon := TextureRect.new()
	icon.texture = UiIcons.icon(str(icon_spec["icon"]))
	icon.custom_minimum_size = Vector2(STRAVA_ICON_SIZE, STRAVA_ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.self_modulate = icon_spec["color"]
	icon.tooltip_text = tr(strava_status_key(s.strava_status))
	row.add_trailing(icon)
	if s.total_power_zone_sec() > 0:
		var bar := ZoneBar.new()
		bar.custom_minimum_size.y = ROW_ZONE_BAR_HEIGHT
		bar.mouse_filter = Control.MOUSE_FILTER_PASS
		var tokens: Array[String] = []
		for i in s.time_in_power_zones.size():
			tokens.append(ZonePalette.power_token(i + 1))
		bar.set_zones(s.time_in_power_zones, tokens)
		row.add_bottom(bar)
	row.activated.connect(_on_row_activated)
	return row


## Метка «Эмулятор» рядом с меткой режима (T-160): тот же Overline, цвет `text2`.
static func _make_emulator_label() -> Label:
	var label := Label.new()
	label.name = "EmulatorLabel"
	label.theme_type_variation = HistoryFormat.EMULATOR_VARIATION
	label.uppercase = true
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = HistoryFormat.emulator_text(true)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


## Заголовок колонок: подписи по ширинам колонок строк (единицы здесь, а не в строках).
func _build_column_titles() -> void:
	for child in _column_titles.get_children():
		_column_titles.remove_child(child)
		child.free()
	var titles := HistoryFormat.column_titles(_compact)
	var widths := HistoryFormat.column_widths(_compact)
	for i in titles.size():
		var label := Label.new()
		label.theme_type_variation = &"CaptionLabel"
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.text = titles[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.custom_minimum_size.x = widths[i]
		_column_titles.add_child(label)
	_column_header.visible = not _summaries.is_empty()


func _find_index(ride_id: String) -> int:
	for i in _summaries.size():
		if _summaries[i].ride_id == ride_id:
			return i
	return -1


# ---------------------------------------------------------------------------
# Фильтр, раскладка
# ---------------------------------------------------------------------------

func _build_filter_chips() -> void:
	for value: HistoryFormat.Filter in [HistoryFormat.Filter.ALL, HistoryFormat.Filter.PLAN, HistoryFormat.Filter.FREE]:
		var chip := Button.new()
		chip.theme_type_variation = &"ChipButton"
		chip.toggle_mode = true
		chip.button_group = _filter_group
		chip.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		chip.button_pressed = value == _filter
		chip.toggled.connect(_on_filter_toggled.bind(value))
		_app_bar.add_action(chip)
		TouchTarget.attach(chip, TouchTarget.Kind.UI)
		_filter_chips[value] = chip
	_apply_filter_texts()


func _apply_filter_texts() -> void:
	for value: HistoryFormat.Filter in _filter_chips:
		(_filter_chips[value] as Button).text = tr(FILTER_KEYS[value])


## Кнопка «назад» AppBar доступна экрану как `%BackButton` (как у остальных экранов ред. 2).
func _expose_back_button() -> void:
	var back_button := _app_bar.back_button()
	back_button.name = "BackButton"
	back_button.owner = self
	back_button.unique_name_in_owner = true


## Раскладка по ширине холста: compact — три колонки и плотные поля. Отступы корня —
## безопасная зона (`UiScale.safe_margins`, UIX-05 крит. 2).
func _update_layout() -> void:
	if not is_node_ready() or not is_inside_tree():
		return
	var safe := Vector4.ZERO
	var scale_source := TouchTarget.default_runtime()
	if scale_source != null:
		safe = scale_source.safe_margins()
	_list_panel.offset_left = safe.x
	_list_panel.offset_top = safe.y
	_list_panel.offset_right = -safe.z
	_list_panel.offset_bottom = -safe.w
	var compact := get_viewport_rect().size.x < COMPACT_MAX_WIDTH
	if compact != _compact:
		_compact = compact
		_margin.theme_type_variation = &"ScreenMarginCompact" if compact else &"ScreenMargin"
		_rebuild_list()
	_update_content_width()


## Ширина контента — не больше `CONTENT_MAX_WIDTH`, по центру (от размера экрана, а не содержимого).
func _update_content_width() -> void:
	if not is_node_ready():
		return
	var inner: float = size.x + _list_panel.offset_right - _list_panel.offset_left \
			- float(_margin.get_theme_constant("margin_left") + _margin.get_theme_constant("margin_right"))
	_column.custom_minimum_size.x = clampf(inner, 0.0, CONTENT_MAX_WIDTH)


# ---------------------------------------------------------------------------
# Сигналы
# ---------------------------------------------------------------------------

func _on_scale_changed(_scale: float) -> void:
	_update_layout()


## Догрузка строк при прокрутке к концу списка.
func _on_scroll_changed(_value: float) -> void:
	if _row_nodes.size() >= _summaries.size():
		return
	var bar := _scroll.get_v_scroll_bar()
	if not _page_pending and bar.max_value - (bar.value + bar.page) < LOAD_MORE_THRESHOLD:
		_page_pending = true
		_load_more.call_deferred()


func _load_more() -> void:
	_page_pending = false
	if is_node_ready() and _row_nodes.size() < _summaries.size():
		_render_page()


func _on_filter_toggled(pressed: bool, value: HistoryFormat.Filter) -> void:
	if pressed and value != _filter:
		_filter = value
		_apply_filter()


func _on_empty_action() -> void:
	if _all.is_empty():
		go_home()
	else:
		set_filter(HistoryFormat.Filter.ALL)


func _on_row_activated(ride_id: String) -> void:
	show_ride(ride_id)


func _on_rides_changed(_profile_id: String) -> void:
	if visible and is_node_ready():
		refresh()


func _on_detail_upload_requested(ride_id: String, ride_name: String, description: String) -> void:
	upload_requested.emit(ride_id, ride_name, description)


func _on_ride_deleted(ride_id: String) -> void:
	back_to_list()
	refresh()
	ride_deleted.emit(ride_id)
