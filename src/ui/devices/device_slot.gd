class_name DeviceSlot
extends PanelContainer
## Слот устройства на экране устройств (`docs/game/ui.md` п. 8.7; REQ-UIX-04 крит. 5):
## «Станок», «Пульсометр» или «Каденс».
##
## Шапка: иконка Lucide, заголовок (`TitleLabel`) и фишка статуса (`ChipButton` без нажатия,
## точка цвета состояния — как у фишек главного экрана, `HomeScreen.chip_dot_color`).
## Устройство подключено (или подключается/переподключается) — имя, сигнал и заряд с иконками
## `signal`/`battery` и кнопка «Отключить» (`GhostButton`); нет — «Не подключено», имя
## запомненного устройства (если есть) и кнопка «Найти». После срыва подключения вместо
## «Не подключено» — причина (REQ-DEV-07 крит. 1, Н-55), точка фишки — `danger_text`
## («ошибка подключения», `ui.md` п. 8.7).
##
## Слот только показывает готовые строки (переводит экран) и испускает сигналы; логика — в
## `DevicesScreen` через `ConnectionManager`.

signal disconnect_requested(device_id: String)
signal find_requested()

const DOT_DIAMETER: float = 10.0

var kind: String = ""
var device_id: String = ""
var _state: int = TrainerDevice.ConnectionState.DISCONNECTED
## Последняя попытка подключения сорвалась (точка фишки — `danger_text`).
var _failed: bool = false
var _dot_placeholder: ImageTexture = null

@onready var _icon: TextureRect = %Icon
@onready var _title: Label = %Title
@onready var _chip: Button = %Chip
@onready var _connected: VBoxContainer = %Connected
@onready var _name: Label = %Name
@onready var _signal_label: Label = %SignalLabel
@onready var _battery_label: Label = %BatteryLabel
@onready var _disconnect_button: Button = %DisconnectButton
@onready var _empty: VBoxContainer = %Empty
@onready var _empty_label: Label = %EmptyLabel
@onready var _remembered_label: Label = %RememberedLabel
@onready var _find_button: Button = %FindButton


func _ready() -> void:
	(%SignalIcon as TextureRect).texture = UiIcons.icon("signal")
	(%BatteryIcon as TextureRect).texture = UiIcons.icon("battery")
	for icon: TextureRect in [%SignalIcon, %BatteryIcon]:
		icon.self_modulate = UiTokens.TEXT2
	_dot_placeholder = ImageTexture.create_from_image(Image.create_empty(int(DOT_DIAMETER), int(DOT_DIAMETER), false, Image.FORMAT_RGBA8))
	_chip.icon = _dot_placeholder
	_chip.draw.connect(_draw_dot)
	_disconnect_button.pressed.connect(_on_disconnect_pressed)
	_find_button.pressed.connect(_on_find_pressed)
	TouchTarget.attach(_disconnect_button, TouchTarget.Kind.UI)
	TouchTarget.attach(_find_button, TouchTarget.Kind.BUTTON)


## Вид слота: тип устройства, иконка Lucide и переведённый заголовок.
func setup(slot_kind: String, icon_name: String, title_text: String) -> void:
	kind = slot_kind
	_icon.texture = UiIcons.icon(icon_name)
	_title.text = title_text


## Устройство есть (подключено, подключается или переподключается).
func show_device(id: String, conn_state: int, state_text: String, name_text: String,
		signal_text: String, battery_text: String, disconnect_text: String) -> void:
	device_id = id
	_failed = false
	_set_state(conn_state, state_text)
	_connected.visible = true
	_empty.visible = false
	_name.text = name_text
	_signal_label.text = signal_text
	_battery_label.text = battery_text
	_disconnect_button.text = disconnect_text


## Устройства нет: «Не подключено» (после срыва — причина, `failed`), имя запомненного или
## последнего подключавшегося (пусто — строка скрыта) и «Найти».
func show_empty(state_text: String, empty_text: String, remembered_name: String, find_text: String,
		find_enabled: bool, failed: bool = false) -> void:
	device_id = ""
	_failed = failed
	_set_state(TrainerDevice.ConnectionState.DISCONNECTED, state_text)
	_connected.visible = false
	_empty.visible = true
	_empty_label.text = empty_text
	_remembered_label.text = remembered_name
	_remembered_label.visible = not remembered_name.is_empty()
	_find_button.text = find_text
	_find_button.disabled = not find_enabled


func is_connected_view() -> bool:
	return _connected.visible


func device_state() -> int:
	return _state


func title_text() -> String:
	return _title.text


func chip_text() -> String:
	return _chip.text


func name_text() -> String:
	return _name.text if _connected.visible else _remembered_label.text


## Текст под статусом в пустом виде: «Не подключено» или причина срыва.
func empty_text() -> String:
	return _empty_label.text


func is_failed() -> bool:
	return _failed


## Цвет точки фишки: `danger_text` после срыва, иначе по состоянию (как у фишек главного).
func dot_color() -> Color:
	return UiTokens.DANGER_TEXT if _failed else HomeScreen.chip_dot_color(_state)


func battery_text() -> String:
	return _battery_label.text


func signal_text() -> String:
	return _signal_label.text


func disconnect_button() -> Button:
	return _disconnect_button


func find_button() -> Button:
	return _find_button


func _set_state(conn_state: int, state_text: String) -> void:
	_state = conn_state
	_chip.text = state_text
	_chip.queue_redraw()


func _draw_dot() -> void:
	var box := _chip.get_theme_stylebox("normal")
	var left: float = box.get_margin(SIDE_LEFT) if box != null else 0.0
	var center := Vector2(left + DOT_DIAMETER * 0.5, _chip.size.y * 0.5)
	_chip.draw_circle(center, DOT_DIAMETER * 0.5, dot_color(), true, -1.0, true)


func _on_disconnect_pressed() -> void:
	disconnect_requested.emit(device_id)


func _on_find_pressed() -> void:
	find_requested.emit()
