class_name ProfileSelectScreen
extends Control
## Экран выбора и создания профиля (`docs/game/ui.md` п. 8.1; REQ-PRF-01 крит. 1, 2, 4, 5;
## REQ-PRF-05). Все строки — через ключи переводов (REQ-NFR-08 крит. 1); ошибки валидации
## показываются по кодам `Profile.ERR_*` / `ProfileRepository.ERR_*` как
## `tr("error.profile.<code>")`.
##
## Раскладка. Словесный знак `ovosch·rider` (Display; compact — H1) и «Кто едет?» (H2 `text2`),
## без профилей — подсказка «создайте первый». Ниже сетка карточек `ProfileCard` (regular —
## до 4 в ряд, 240×200; compact — 3 в ряд, 240×150) и последней — «Новый профиль» (иконка
## `plus`, пунктирная рамка `line_strong`). Нажатие на карточку — выбор профиля; «⋯» на
## карточке — «Удалить профиль» с подтверждением (опасная кнопка). Создание — диалог с
## подписями над полями. Стрелки ходят по сетке, Enter — выбрать.
##
## Выбор — индекс выделенного профиля в порядке репозитория (индекс ↔ id профиля); на экране
## его показывает выделенная карточка.
##
## Экран не знает, какой экран следующий: по выбору вызывает `AppState.select_profile`
## и испускает `profile_chosen`. Зависимости передаются через `setup()`.

const ERROR_KEY_PREFIX: String = "error.profile."
const COMPACT_MAX_WIDTH: float = AppBar.COMPACT_MAX_WIDTH
const COLUMNS_REGULAR: int = 4
const COLUMNS_COMPACT: int = 3
## Зазор сетки карточек, lp (`Row16`/`Stack16`).
const CARD_GAP: float = 16.0
## Пунктирная рамка карточки «Новый профиль» (`ui.md` п. 8.1): 1.5 lp `line_strong`.
const DASH_WIDTH: float = 1.5
const DASH_LENGTH: float = 6.0
const DASH_RADIUS: float = 16.0
const PLUS_ICON: String = "plus"
## Иконка `plus` карточки «Новый профиль» и зазор до подписи, lp.
const PLUS_SIZE: float = 32.0
const PLUS_GAP: float = 20.0
## Словесный знак (`ui.md` п. 6): имя продукта, не переводится; «·rider» — цветом `accent`.
const LOGO_MAIN: String = HomeScreen.LOGO_MAIN
const LOGO_ACCENT: String = HomeScreen.LOGO_ACCENT
const MENU_DELETE_ID: int = 0
## Диалог создания: место под заголовок окна, кнопки и поля диалога, lp; минимум для полей.
const CREATE_DIALOG_RESERVE: float = 190.0
const CREATE_FIELDS_MIN_HEIGHT: float = 120.0

signal profile_chosen(id: String)
signal profile_created(id: String)
signal profile_deleted(id: String)

var _repo: ProfileRepository
var _app_state: AppState
var _ids: Array[String] = []
## Индекс выделенного профиля в `_ids` (−1 — ничего не выделено).
var _selected: int = -1
var _pending_delete_id: String = ""
var _menu_profile_id: String = ""
var _cards: Array[ProfileCard] = []
var _compact: bool = false
## Число карточек в ряду и раскладка, по которой сетка собрана последней.
var _columns: int = COLUMNS_REGULAR
var _laid_out_compact: bool = false

@onready var _root: VBoxContainer = %Root
@onready var _margin: MarginContainer = %Margin
@onready var _logo_main: Label = %LogoMain
@onready var _logo_accent: Label = %LogoAccent
@onready var _who_label: Label = %WhoLabel
@onready var _grid: VBoxContainer = %Grid
@onready var _create_button: Button = %CreateButton
@onready var _empty_hint: Label = %EmptyHint
@onready var _screen_error_label: Label = %ScreenErrorLabel
@onready var _create_dialog: AcceptDialog = %CreateDialog
@onready var _create_form: VBoxContainer = %CreateForm
@onready var _fields_scroll: ScrollContainer = %FieldsScroll
@onready var _fields: VBoxContainer = %Fields
@onready var _name_edit: LineEdit = %NameEdit
@onready var _ftp_spin: SpinBox = %FtpSpin
@onready var _weight_spin: SpinBox = %WeightSpin
@onready var _max_hr_spin: SpinBox = %MaxHrSpin
@onready var _save_button: Button = %SaveButton
@onready var _cancel_button: Button = %CancelButton
@onready var _error_label: Label = %ErrorLabel
@onready var _delete_dialog: ConfirmationDialog = %DeleteDialog
@onready var _card_menu: PopupMenu = %CardMenu


## Внедрить зависимости (до или после добавления в дерево).
func setup(repo: ProfileRepository, app_state: AppState = null) -> void:
	_repo = repo
	_app_state = app_state
	if is_node_ready():
		refresh()


func _ready() -> void:
	_logo_main.text = LOGO_MAIN
	_logo_accent.text = LOGO_ACCENT
	_create_button.draw.connect(_draw_create_card)
	_create_button.pressed.connect(open_create_form)
	_save_button.pressed.connect(_on_save_pressed)
	_cancel_button.pressed.connect(close_create_form)
	_name_edit.text_submitted.connect(_on_name_submitted)
	_create_dialog.get_ok_button().visible = false
	_create_dialog.canceled.connect(close_create_form)
	_delete_dialog.confirmed.connect(_on_delete_confirmed)
	_delete_dialog.canceled.connect(_on_delete_canceled)
	_delete_dialog.get_ok_button().theme_type_variation = &"DangerButton"
	_card_menu.id_pressed.connect(_on_card_menu_id)
	TouchTarget.attach(_create_button, TouchTarget.Kind.UI)
	for button: Button in [_save_button, _cancel_button]:
		TouchTarget.attach(button, TouchTarget.Kind.BUTTON)
	# Поле `SpinBox` фокусируется внутренним `LineEdit`: высоту цели задаёт сам `SpinBox`.
	for spin: SpinBox in [_ftp_spin, _weight_spin, _max_hr_spin]:
		TouchTarget.attach(spin, TouchTarget.Kind.UI)
	TouchTarget.attach_all(_create_form, TouchTarget.Kind.UI)
	var scale_source := TouchTarget.default_runtime()
	if scale_source != null:
		scale_source.scale_changed.connect(_on_scale_changed)
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()
	if _repo != null:
		refresh()


func _exit_tree() -> void:
	var scale_source := TouchTarget.default_runtime()
	if scale_source != null and scale_source.scale_changed.is_connected(_on_scale_changed):
		scale_source.scale_changed.disconnect(_on_scale_changed)
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_update_layout):
		viewport.size_changed.disconnect(_update_layout)


func _enter_tree() -> void:
	if not is_node_ready():
		return
	var scale_source := TouchTarget.default_runtime()
	if scale_source != null and not scale_source.scale_changed.is_connected(_on_scale_changed):
		scale_source.scale_changed.connect(_on_scale_changed)
	if not get_viewport().size_changed.is_connected(_update_layout):
		get_viewport().size_changed.connect(_update_layout)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready() and is_visible_in_tree():
		_update_layout()
		_focus_selected_card()


## Перечитать список профилей из репозитория.
func refresh() -> void:
	_ids = []
	_selected = -1
	var active_id: String = _repo.active_profile_id
	for p in _repo.list():
		if p.id == active_id:
			_selected = _ids.size()
		_ids.append(p.id)
	var empty: bool = _ids.is_empty()
	_empty_hint.visible = empty
	_who_label.visible = not empty
	_who_label.text = tr("ui.profile_select.who")
	_render_cards()
	_update_dialog_texts()
	if empty:
		open_create_form()
	# Автовыбор единственного профиля при старте не удался (например, сбой записи) — показать причину.
	if _app_state != null and not _app_state.last_select_error().is_empty():
		_show_error([_app_state.last_select_error()])


func profile_count() -> int:
	return _ids.size()


## Выделить профиль по индексу (для тестов и клавиатуры); индекс вне списка выделение не меняет.
func select_index(index: int) -> void:
	if index >= 0 and index < _ids.size():
		_selected = index


## id выделенного профиля или "".
func selected_profile_id() -> String:
	if _selected < 0 or _selected >= _ids.size():
		return ""
	return _ids[_selected]


## Подтвердить выбор выделенного профиля. false — ничего не выделено или выбор не удался
## (например, не записан активный профиль) — причина показана в `error_text()`.
func select_current() -> bool:
	var id := selected_profile_id()
	if id.is_empty():
		return false
	var err := ""
	if _app_state != null:
		if not _app_state.select_profile(id):
			err = _app_state.last_select_error()
			if err.is_empty():
				err = ProfileRepository.ERR_PROFILE_NOT_FOUND
	else:
		err = _repo.set_active(id)
	if not err.is_empty():
		_show_error([err])
		return false
	_show_error([])
	profile_chosen.emit(id)
	return true


## Выбрать профиль по id (нажатие на карточку): выделение и подтверждение выбора.
func choose(id: String) -> bool:
	select_index(_ids.find(id))
	var ok := select_current()
	_sync_card_selection()
	return ok


func open_create_form() -> void:
	_name_edit.text = ""
	_ftp_spin.value = 200
	_weight_spin.value = 75.0
	_max_hr_spin.value = 0
	_show_error([])
	_update_dialog_texts()
	_fit_create_form()
	if not _create_dialog.visible and _create_dialog.is_inside_tree():
		_create_dialog.popup_centered()
	_name_edit.grab_focus()


func close_create_form() -> void:
	if _create_dialog.visible:
		_create_dialog.hide()
	_show_error([])


func is_create_form_open() -> bool:
	return _create_dialog.visible


## Заполнить форму (для тестов).
func fill_create_form(profile_name: String, ftp_w: int, weight_kg: float, max_hr: int = 0) -> void:
	_name_edit.text = profile_name
	_ftp_spin.value = ftp_w
	_weight_spin.value = weight_kg
	_max_hr_spin.value = max_hr


## Создать профиль из формы. Возвращает профиль или null (ошибки показаны в `error_text()`).
func submit_create() -> Profile:
	var p := Profile.create(_name_edit.text)
	p.ftp_w = int(_ftp_spin.value)
	p.weight_kg = _weight_spin.value
	p.max_hr = int(_max_hr_spin.value)
	var errors := _repo.save(p)
	if not errors.is_empty():
		_show_error(errors, true)
		return null
	close_create_form()
	refresh()
	select_index(_ids.find(p.id))
	_sync_card_selection()
	profile_created.emit(p.id)
	return p


## Запросить удаление выделенного профиля (показывает подтверждение, REQ-PRF-01 крит. 4).
func request_delete() -> bool:
	var id := selected_profile_id()
	if id.is_empty():
		return false
	_pending_delete_id = id
	var p := _repo.get_by_id(id)
	_delete_dialog.title = tr("ui.profile_select.delete")
	_delete_dialog.ok_button_text = tr("ui.common.delete")
	_delete_dialog.cancel_button_text = tr("ui.common.cancel")
	_delete_dialog.dialog_text = tr("ui.profile_select.delete_confirm").format({"name": p.name if p != null else id})
	_delete_dialog.popup_centered()
	return true


## Подтверждённое удаление. Возвращает "" или код ошибки (например, `last_profile`).
func confirm_delete() -> String:
	var id := _pending_delete_id
	_pending_delete_id = ""
	if id.is_empty():
		return ProfileRepository.ERR_PROFILE_NOT_FOUND
	var err := _repo.delete(id)
	if err.is_empty():
		profile_deleted.emit(id)
	refresh()
	if not err.is_empty():
		_show_error([err])
	return err


func pending_delete_id() -> String:
	return _pending_delete_id


## Текущий текст ошибки ("" если нет): ошибка формы создания или ошибка экрана (выбор, удаление).
func error_text() -> String:
	if _error_label.visible:
		return _error_label.text
	return _screen_error_label.text if _screen_error_label.visible else ""


## Перевод кода ошибки.
static func error_message(code: String) -> String:
	return TranslationServer.translate(ERROR_KEY_PREFIX + code)


## Карточки профилей по порядку (без «Новый профиль»).
func cards() -> Array[ProfileCard]:
	return _cards.duplicate()


func card_for(id: String) -> ProfileCard:
	for card in _cards:
		if card.profile_id == id:
			return card
	return null


func create_card() -> Button:
	return _create_button


## Число карточек в ряду сетки: до 4 на regular, до 3 на compact — сколько помещается.
func columns() -> int:
	return _columns


func is_compact() -> bool:
	return _compact


## Открыть меню «⋯» карточки профиля `id` (для тестов и клавиатуры).
func open_card_menu(id: String) -> void:
	var card := card_for(id)
	if card == null:
		return
	_menu_profile_id = id
	_card_menu.clear()
	_card_menu.add_item(tr("ui.profile_select.delete_profile"), MENU_DELETE_ID)
	var anchor := card.menu_button()
	var at := Vector2i(anchor.get_screen_position() + Vector2(0.0, anchor.size.y))
	_card_menu.popup(Rect2i(at, Vector2i.ZERO))


func card_menu() -> PopupMenu:
	return _card_menu


## Пункт меню «⋯» (`MENU_DELETE_ID` — «Удалить профиль»): удаление с подтверждением.
func activate_card_menu_item(id: int) -> void:
	_on_card_menu_id(id)


func _show_error(codes: Array[String], in_form: bool = false) -> void:
	var lines: Array[String] = []
	for code in codes:
		lines.append(tr(ERROR_KEY_PREFIX + code))
	var text := "\n".join(lines)
	var form := in_form or is_create_form_open()
	_error_label.text = text if form else ""
	_error_label.visible = form and not lines.is_empty()
	_fit_create_form()
	if _error_label.visible and is_inside_tree():
		# Низкий экран (телефон): поля прокручиваются — показать ошибки.
		_fields_scroll.ensure_control_visible.call_deferred(_error_label)
	_screen_error_label.text = "" if form else text
	_screen_error_label.visible = not form and not lines.is_empty()


## Высота прокрутки полей формы: всё содержимое, но не выше холста за вычетом заголовка окна,
## кнопок и полей диалога (телефон — холст ≈ 400 lp: поля прокручиваются, кнопки видны).
func _fit_create_form() -> void:
	if not is_inside_tree():
		return
	var content := _fields.get_combined_minimum_size().y
	var limit := get_viewport_rect().size.y - CREATE_DIALOG_RESERVE
	_fields_scroll.custom_minimum_size.y = maxf(minf(content, limit), CREATE_FIELDS_MIN_HEIGHT)
	_create_dialog.reset_size()


func _update_dialog_texts() -> void:
	_create_dialog.title = tr("ui.profile_create.title")


# ---------------------------------------------------------------------------
# Карточки
# ---------------------------------------------------------------------------

func _render_cards() -> void:
	var profiles: Array[Profile] = _repo.list()
	while _cards.size() < profiles.size():
		var card := ProfileCard.new()
		card.chosen.connect(_on_card_chosen)
		card.menu_requested.connect(_on_card_menu_requested)
		_cards.append(card)
	while _cards.size() > profiles.size():
		var extra: ProfileCard = _cards.pop_back()
		if extra.get_parent() != null:
			extra.get_parent().remove_child(extra)
		# Сразу, без «сирот» до конца кадра: удаление идёт не из сигнала самой карточки.
		extra.free()
	for i in profiles.size():
		var p := profiles[i]
		_cards[i].name = "Card_" + p.id.validate_node_name()
		_cards[i].set_profile(p.id, p.name, tr("ui.profile_select.card_stats").format({
			"ftp": p.ftp_w, "weight": _format_weight(p.weight_kg)}))
		_cards[i].set_menu_visible(profiles.size() > 1)
	_layout_grid()
	_sync_card_selection()


## Разложить карточки и «Новый профиль» по рядам сетки (`columns()` в ряд, по центру).
func _layout_grid() -> void:
	var items: Array[Control] = []
	for card in _cards:
		items.append(card)
	items.append(_create_button)
	var per_row := columns()
	var rows_needed := ceili(float(items.size()) / float(per_row))
	var rows: Array[HBoxContainer] = []
	for child in _grid.get_children():
		if child is HBoxContainer:
			rows.append(child)
	while rows.size() < rows_needed:
		var row := HBoxContainer.new()
		row.name = "Row%d" % rows.size()
		row.theme_type_variation = &"Row16"
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		_grid.add_child(row)
		rows.append(row)
	for i in items.size():
		var item := items[i]
		var row := rows[floori(float(i) / float(per_row))]
		if item.get_parent() == null:
			row.add_child(item)
		elif item.get_parent() != row:
			item.reparent(row, false)
		row.move_child(item, i % per_row)
	for i in range(rows_needed, rows.size()):
		_grid.remove_child(rows[i])
		rows[i].free()
	_laid_out_compact = _compact
	for card in _cards:
		card.set_compact(_compact)
	var touch := TouchTarget.of(_create_button)
	var card_size := ProfileCard.SIZE_COMPACT if _compact else ProfileCard.SIZE_REGULAR
	if touch != null:
		touch.set_floor(card_size)
	else:
		_create_button.custom_minimum_size = card_size


func _sync_card_selection() -> void:
	var selected := selected_profile_id()
	for card in _cards:
		card.set_selected(card.profile_id == selected)


func _focus_selected_card() -> void:
	if _is_touch_device() or is_create_form_open():
		return
	var card := card_for(selected_profile_id())
	if card != null and card.is_visible_in_tree():
		card.grab_focus()


static func _is_touch_device() -> bool:
	var scale_source := TouchTarget.default_runtime()
	return scale_source != null and scale_source.device != UiScale.Device.DESKTOP


static func _format_weight(kg: float) -> String:
	return str(roundi(kg)) if is_equal_approx(kg, roundf(kg)) else "%.1f" % kg


## «Новый профиль»: иконка `plus` над подписью (подпись кнопки — по центру) и пунктирная
## рамка — стороны пунктиром, углы дугами радиуса карточки.
func _draw_create_card() -> void:
	var plus := UiIcons.icon(PLUS_ICON)
	if plus != null:
		var center := _create_button.size * 0.5
		var icon_rect := Rect2(center + Vector2(-PLUS_SIZE * 0.5, -PLUS_SIZE - PLUS_GAP), Vector2(PLUS_SIZE, PLUS_SIZE))
		_create_button.draw_texture_rect(plus, icon_rect, false, UiTokens.TEXT2)
	var rect := Rect2(Vector2.ONE * DASH_WIDTH * 0.5, _create_button.size - Vector2.ONE * DASH_WIDTH)
	var r := minf(DASH_RADIUS, minf(rect.size.x, rect.size.y) * 0.5)
	var color := UiTokens.LINE_STRONG
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.end.x
	var y1 := rect.end.y
	_create_button.draw_dashed_line(Vector2(x0 + r, y0), Vector2(x1 - r, y0), color, DASH_WIDTH, DASH_LENGTH)
	_create_button.draw_dashed_line(Vector2(x0 + r, y1), Vector2(x1 - r, y1), color, DASH_WIDTH, DASH_LENGTH)
	_create_button.draw_dashed_line(Vector2(x0, y0 + r), Vector2(x0, y1 - r), color, DASH_WIDTH, DASH_LENGTH)
	_create_button.draw_dashed_line(Vector2(x1, y0 + r), Vector2(x1, y1 - r), color, DASH_WIDTH, DASH_LENGTH)
	_create_button.draw_arc(Vector2(x0 + r, y0 + r), r, PI, PI * 1.5, 8, color, DASH_WIDTH, true)
	_create_button.draw_arc(Vector2(x1 - r, y0 + r), r, PI * 1.5, TAU, 8, color, DASH_WIDTH, true)
	_create_button.draw_arc(Vector2(x1 - r, y1 - r), r, 0.0, PI * 0.5, 8, color, DASH_WIDTH, true)
	_create_button.draw_arc(Vector2(x0 + r, y1 - r), r, PI * 0.5, PI, 8, color, DASH_WIDTH, true)


# ---------------------------------------------------------------------------
# Обработчики (связанные методы, без лямбд)
# ---------------------------------------------------------------------------

func _on_save_pressed() -> void:
	submit_create()


func _on_name_submitted(_text: String) -> void:
	submit_create()


func _on_delete_confirmed() -> void:
	confirm_delete()


func _on_delete_canceled() -> void:
	_pending_delete_id = ""


func _on_card_chosen(id: String) -> void:
	choose(id)


func _on_card_menu_requested(id: String, _anchor: Control) -> void:
	open_card_menu(id)


func _on_card_menu_id(id: int) -> void:
	if id != MENU_DELETE_ID or _menu_profile_id.is_empty():
		return
	select_index(_ids.find(_menu_profile_id))
	_sync_card_selection()
	_menu_profile_id = ""
	request_delete()


func _on_scale_changed(_scale: float) -> void:
	_update_layout()


## Раскладка: безопасная зона, поля, compact (логотип H1, карточки 240×150, 3 в ряд). Карточек
## в ряду не больше, чем помещается в ширину без безопасной зоны и полей (вырез телефона).
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
	var canvas_width := get_viewport_rect().size.x
	var compact := canvas_width < COMPACT_MAX_WIDTH
	_compact = compact
	_margin.theme_type_variation = &"ScreenMarginCompact" if compact else &"ScreenMargin"
	var available := canvas_width - safe.x - safe.z \
		- float(_margin.get_theme_constant("margin_left")) - float(_margin.get_theme_constant("margin_right"))
	var max_columns := COLUMNS_COMPACT if compact else COLUMNS_REGULAR
	var fit := floori((available + CARD_GAP) / (ProfileCard.SIZE_REGULAR.x + CARD_GAP))
	var columns_now := clampi(fit, 1, max_columns)
	var changed := columns_now != _columns or compact != _laid_out_compact
	_columns = columns_now
	var logo_variation := &"H1Label" if compact else &"DisplayLabel"
	_logo_main.theme_type_variation = logo_variation
	_logo_accent.theme_type_variation = logo_variation
	_logo_accent.self_modulate = HomeScreen.tint_for(_logo_accent.get_theme_color("font_color"), UiTokens.ACCENT)
	_who_label.self_modulate = HomeScreen.tint_for(_who_label.get_theme_color("font_color"), UiTokens.TEXT2)
	if changed and _repo != null:
		_layout_grid()
