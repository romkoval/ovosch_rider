class_name AppBar
extends PanelContainer
## Панель приложения (`docs/game/ui.md` п. 6, 9.2; REQ-UIX-04 крит. 1, REQ-UIX-01 крит. 3).
##
## Слева кнопка «назад» (вариация `IconButton`, иконка Lucide `chevron-left`, цель нажатия
## `touch_ui`, но не меньше 48 lp на компьютере), заголовок экрана (вариация `H1Label`), справа
## слот действий экрана (`actions_slot()` / `add_action()`). Высота 72 lp, на compact
## (ширина холста < 1100 lp) — 64 lp. Все стили — вариация темы `AppBar`, без переопределений.
##
## «Назад» вызывает `AppState.go_back()` (стек «назад», T-061) и испускает `back_pressed`
## с его результатом. Экран с собственной навигацией внутри (карточка заезда → список)
## ставит `navigate_on_back = false` и обрабатывает только сигнал.
##
## Заголовок — ключ перевода (`set_title("ui.settings.title")`) или пользовательские данные
## (`set_title(ride.name, false)` — без перевода, длинное сокращается «…», UIX-05 крит. 3).
## При смене языка текст обновляется сам (`NOTIFICATION_TRANSLATION_CHANGED`).

## Нажата «назад»; `handled` — `AppState.go_back()` сменил экран (false — некуда или навигация выключена).
signal back_pressed(handled: bool)

const HEIGHT: float = 72.0
const HEIGHT_COMPACT: float = 64.0
## Брейкпоинт compact по ширине холста, lp (`ui.md` п. 3).
const COMPACT_MAX_WIDTH: float = 1100.0
## Кнопка «назад» на компьютере не меньше 48 lp (`ui.md` п. 6).
const BACK_MIN_SIZE: Vector2 = Vector2(48, 48)
const BACK_TOOLTIP_KEY: String = "ui.menu.back"
const BACK_ICON: Texture2D = preload("res://assets/icons/lucide/chevron-left.svg")

## Показывать кнопку «назад» (у главного экрана и выбора профиля её нет).
@export var show_back: bool = true:
	set(value):
		show_back = value
		if is_node_ready():
			_back.visible = value
## «Назад» вызывает `AppState.go_back()`; false — только сигнал `back_pressed`.
@export var navigate_on_back: bool = true
## Заголовок: ключ перевода (или текст при `title_translate = false`).
@export var title: String = "":
	set(value):
		title = value
		_apply_title()
@export var title_translate: bool = true:
	set(value):
		title_translate = value
		_apply_title()

var _app_state: AppState = null
var _compact: bool = false

@onready var _back: Button = %Back
@onready var _title: Label = %Title
@onready var _actions: HBoxContainer = %Actions


func _ready() -> void:
	_back.icon = BACK_ICON
	_back.tooltip_text = BACK_TOOLTIP_KEY
	_back.visible = show_back
	_back.pressed.connect(_on_back_pressed)
	TouchTarget.attach(_back, TouchTarget.Kind.UI, BACK_MIN_SIZE)
	_apply_title()
	_update_compact()


func _enter_tree() -> void:
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_update_compact):
		viewport.size_changed.connect(_update_compact)


func _exit_tree() -> void:
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_update_compact):
		viewport.size_changed.disconnect(_update_compact)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_apply_title()


## Состояние навигации, у которого «назад» вызывает `go_back()`.
func setup(app_state: AppState) -> void:
	_app_state = app_state


## Заголовок: ключ перевода (`translate = true`) или готовый текст пользовательских данных.
func set_title(text: String, translate: bool = true) -> void:
	title_translate = translate
	title = text


## Отображаемый (переведённый) заголовок.
func title_text() -> String:
	return _title.text if _title != null else ""


## Кнопка «назад» (для фокуса и тестов).
func back_button() -> Button:
	return _back


## Слот действий справа: экран добавляет кнопки и фишки сюда.
func actions_slot() -> HBoxContainer:
	return _actions


## Добавить действие справа (кнопку, фишку профиля…).
func add_action(control: Control) -> void:
	_actions.add_child(control)


## Нажать «назад» программно (Esc на экране, тесты) — то же, что кнопка.
func press_back() -> bool:
	var handled := false
	if navigate_on_back and _app_state != null:
		handled = _app_state.go_back()
	back_pressed.emit(handled)
	return handled


func is_compact() -> bool:
	return _compact


func _on_back_pressed() -> void:
	press_back()


func _apply_title() -> void:
	if _title == null:
		return
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.text = tr(title) if title_translate else title
	# Сокращение «…» — только для пользовательских данных (UIX-05 крит. 3).
	_title.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING if title_translate else TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.clip_text = not title_translate


func _update_compact() -> void:
	if not is_inside_tree():
		return
	_compact = get_viewport_rect().size.x < COMPACT_MAX_WIDTH
	custom_minimum_size.y = HEIGHT_COMPACT if _compact else HEIGHT
