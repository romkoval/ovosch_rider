class_name HudScreenFrame
extends RefCounted
## Общая «рамка» HUD экранов заезда — тренировки (`WorkoutScreen`) и свободной езды
## (`FreeRideScreen`): фишки статусов, расстановка слотов по `HudLayout`, панель инструментов
## в своём слоте, плашка и фишка слота подсказки, цель нажатия `touch_hud` и Esc на карточке
## паузы (`docs/game/hud.md` п. 4.1, 10.2, 10.3; REQ-HUD-13 крит. 5, 6, 9; REQ-UIX-04 крит. 2).
##
## Узлы — экрана: у обеих сцен одинаковые уникальные имена `%MetricPanel`, `%PauseButton`,
## `%ListSlot`, `%ChartSlot`, `%Chart`, `%HintSlot`, `%StatusSlot`, `%ToolbarSlot`, `%Toolbar`,
## `%PauseOverlay`; помощник их только расставляет. Содержимое левого слота (список интервалов
## или панель рельефа) и подсказки экран кладёт сам по `layout()`. Настройка 3D-вьюпорта
## (`SubViewport`, физическое разрешение) — забота экрана, здесь её нет.
##
## Фишки статусов (`hud.md` п. 10.3): высота 24, радиус 12, точка 8, текст 12 / 650; строкой
## влево от кнопки паузы или столбиком под ней (`HudLayout.status_vertical`).
## Панель инструментов: на телефоне — сетка (`HudToolbar.set_compact(true)`) у верха слота под
## фишками; на компьютере и планшете — колонка по центру высоты слота, а если колонка выше
## слота — та же сетка: панель не заходит ни на фишки, ни на график (REQ-HUD-13 крит. 5, 6).

const CHIP_HEIGHT: float = HudLayout.STATUS_CHIP_HEIGHT
const CHIP_RADIUS: int = 12
const CHIP_DOT_RADIUS: float = 4.0
const CHIP_PAD_LEFT: float = 22.0
const CHIP_PAD_RIGHT: float = 10.0
const CHIP_GAP: float = 6.0
## Подсказка в слоте подсказки: обычная вариация и телефонная (кегль 14, одна строка).
const HINT_VARIATION: StringName = &"BodyStrongLabel"
const HINT_VARIATION_COMPACT: StringName = &"HudHintCompact"
const HINT_MAX_LINES: int = 2

var _screen: Control
var _panel: HudMetricPanel
var _pause_button: Control
var _list_slot: Control
var _chart_slot: Control
var _chart: HudChart
var _hint_slot: Control
var _status_slot: Control
var _toolbar_slot: Control
var _toolbar: HudToolbar
var _overlay: PauseOverlay
var _chips: Array[Control] = []
var _dots: Dictionary = {}
var _chip_box: StyleBoxFlat
var _layout: HudLayout
var _touch_applied: float = -1.0
## Условия, при которых выбрана раскладка панели инструментов (колонка или сетка).
var _toolbar_fit_key: String = ""
var _placing_toolbar: bool = false


## `screen` — корень экрана заезда, `chips` — его фишки статусов в порядке строки.
func _init(screen: Control, chips: Array[Control]) -> void:
	_screen = screen
	_panel = screen.get_node(^"%MetricPanel")
	_pause_button = screen.get_node(^"%PauseButton")
	_list_slot = screen.get_node(^"%ListSlot")
	_chart_slot = screen.get_node(^"%ChartSlot")
	_chart = screen.get_node(^"%Chart")
	_hint_slot = screen.get_node(^"%HintSlot")
	_status_slot = screen.get_node(^"%StatusSlot")
	_toolbar_slot = screen.get_node(^"%ToolbarSlot")
	_toolbar = screen.get_node(^"%Toolbar")
	_overlay = screen.get_node(^"%PauseOverlay")
	_chips = chips
	_chip_box = StyleBoxFlat.new()
	_chip_box.bg_color = UiTokens.HUD_PLATE
	_chip_box.set_corner_radius_all(CHIP_RADIUS)
	for chip in _chips:
		chip.draw.connect(_draw_chip.bind(chip))
	_chart.fade_height = HudLayout.CHART_GRADIENT_HEIGHT
	_toolbar.minimum_size_changed.connect(place_toolbar)


## Текущая геометрия (null — ещё не считалась).
func current_layout() -> HudLayout:
	return _layout


## Пересчитать `HudLayout` по размеру экрана, безопасной зоне, масштабу HUD и типу устройства и
## расставить общие слоты: панель цифр, кнопку паузы, левый слот, график, слот подсказки, фишки
## статусов и панель инструментов. null — экран ещё без размера.
func layout() -> HudLayout:
	var size := _screen.size
	if size.x <= 0.0 or size.y <= 0.0:
		return _layout
	var ui := ui_scale()
	var s := ui.current_scale() if ui != null and ui.mode == UiScale.Mode.HUD else 1.0
	var touch := ui.touch_hud() if ui != null else UiScale.TOUCH_HUD_DESKTOP
	var phone := ui != null and ui.device == UiScale.Device.PHONE
	var safe := ui.safe_margins() if ui != null else Vector4.ZERO
	_apply_touch_target(touch)
	var chips := visible_chips()
	var row_w := CHIP_GAP * maxf(chips.size() - 1, 0)
	for chip in chips:
		_size_chip(chip)
		row_w += chip.size.x
	_layout = HudLayout.compute(size, safe, s, touch, phone, _pause_button.get_combined_minimum_size(), row_w)
	set_rect(_panel, _layout.panel)
	set_rect(_pause_button, _layout.pause_button)
	set_rect(_list_slot, _layout.list_slot)
	# График: градиент над подложкой и поле — во всю ширину слота.
	var chart_rect := _layout.chart_gradient.merge(_layout.chart)
	set_rect(_chart_slot, chart_rect)
	_chart.fade_height = _layout.chart_gradient.size.y
	set_rect(_chart, Rect2(Vector2.ZERO, chart_rect.size))
	set_rect(_hint_slot, _layout.hint_slot)
	set_rect(_status_slot, _layout.status_slot)
	_layout_chips(chips)
	set_rect(_toolbar_slot, _layout.toolbar_slot)
	place_toolbar()
	return _layout


# ---------------------------------------------------------------------------
# Фишки статусов
# ---------------------------------------------------------------------------

## Цвет точки фишки (перерисовка — `redraw_chips()`).
func set_dot(chip: Control, color: Color) -> void:
	_dots[chip] = color


func dot(chip: Control) -> Color:
	return _dots.get(chip, UiTokens.HUD_TEXT2)


func redraw_chips() -> void:
	for chip in _chips:
		chip.queue_redraw()


func visible_chips() -> Array[Control]:
	var out: Array[Control] = []
	for chip in _chips:
		if chip.visible:
			out.append(chip)
	return out


## Точка фишки «СТАНОК» по состоянию подключения.
static func connection_dot(state: int) -> Color:
	match state:
		TrainerDevice.ConnectionState.CONNECTED:
			return UiTokens.HUD_OK
		TrainerDevice.ConnectionState.SCANNING, TrainerDevice.ConnectionState.CONNECTING, TrainerDevice.ConnectionState.RECONNECTING:
			return UiTokens.HUD_WARN
		_:
			return UiTokens.HUD_ERR


func _size_chip(chip: Control) -> void:
	var label := chip.get_child(0) as Label
	var label_size := label.get_combined_minimum_size()
	label.position = Vector2(CHIP_PAD_LEFT, (CHIP_HEIGHT - label_size.y) * 0.5)
	label.size = label_size
	chip.size = Vector2(CHIP_PAD_LEFT + label_size.x + CHIP_PAD_RIGHT, CHIP_HEIGHT)


## Строкой — вправо к кнопке паузы; столбиком — под кнопкой, по правому краю.
func _layout_chips(chips: Array[Control]) -> void:
	var slot := _layout.status_slot.size
	if _layout.status_vertical:
		var y := 0.0
		for chip in chips:
			chip.position = Vector2(slot.x - chip.size.x, y)
			y += CHIP_HEIGHT + HudLayout.STATUS_GAP
	else:
		var x := slot.x
		for i in range(chips.size() - 1, -1, -1):
			x -= chips[i].size.x
			chips[i].position = Vector2(x, 0)
			x -= CHIP_GAP


## Фишка статуса: подложка `hud.plate` (r 12) и точка состояния.
func _draw_chip(chip: Control) -> void:
	chip.draw_style_box(_chip_box, Rect2(Vector2.ZERO, chip.size))
	chip.draw_circle(Vector2(CHIP_PAD_LEFT * 0.5 + 1.0, CHIP_HEIGHT * 0.5), CHIP_DOT_RADIUS, dot(chip))


# ---------------------------------------------------------------------------
# Панель инструментов, слот подсказки
# ---------------------------------------------------------------------------

## Панель инструментов — у правого края слота: на телефоне сетка у верха слота, иначе колонка
## по центру высоты (или сетка, если колонка выше слота). Не выходит из слота по высоте.
func place_toolbar() -> void:
	if _layout == null or _placing_toolbar:
		return
	_placing_toolbar = true
	var slot := _layout.toolbar_slot.size
	var key := "%s|%d|%d|%d|%s|%s" % [_layout.phone, roundi(slot.y), roundi(_touch_applied), _toolbar.get_mode(),
			_toolbar.is_erg_enabled(), _toolbar.is_sim_enabled()]
	if key != _toolbar_fit_key:
		_toolbar_fit_key = key
		if _layout.phone:
			_toolbar.set_compact(true)
		else:
			_toolbar.set_compact(false)
			_toolbar.set_compact(_toolbar.get_combined_minimum_size().y > slot.y)
	var tools := _toolbar.get_combined_minimum_size()
	_toolbar.size = tools
	var y := 0.0 if _layout.phone else maxf((slot.y - tools.y) * 0.5, 0.0)
	_toolbar.position = Vector2(slot.x - tools.x, y)
	_placing_toolbar = false


## Плашка в слоте подсказки (подсказка плана, сообщение «нет SIM»): по ширине текста, не шире
## слота; вверху слота на компьютере и планшете, внизу — на телефоне. На телефоне текст —
## `HudHintCompact` в одну строку с «…» (слот ≈ 34 lp), иначе Body Strong до двух строк.
func place_hint_plate(plate: PanelContainer, label: Label) -> void:
	if _layout == null or not plate.visible:
		return
	var phone := _layout.phone
	label.theme_type_variation = HINT_VARIATION_COMPACT if phone else HINT_VARIATION
	label.max_lines_visible = 1 if phone else HINT_MAX_LINES
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if phone else TextServer.OVERRUN_NO_TRIMMING
	var slot := _layout.hint_slot.size
	var box := plate.get_theme_stylebox(&"panel")
	var pad := box.get_minimum_size() if box != null else Vector2.ZERO
	var font := label.get_theme_font(&"font")
	var text_w := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size(&"font_size")).x
	var width := minf(ceilf(text_w) + pad.x + 1.0, slot.x)
	label.custom_minimum_size = Vector2(width - pad.x, 0)
	plate.size = Vector2(width, 0)
	plate.size = plate.get_combined_minimum_size()
	var y := slot.y - plate.size.y if phone else 0.0
	plate.position = Vector2((slot.x - plate.size.x) * 0.5, y)


## Фишка «ДАЛЕЕ» — во всю ширину слота (плашка по центру); на компьютере и планшете — у верха
## слота под панелью, на телефоне — компактная, низом к низу слота (над графиком).
func place_next_chip(chip: NextChip) -> void:
	if _layout == null:
		return
	chip.set_compact(_layout.phone)
	var slot := _layout.hint_slot.size
	var h := chip.get_combined_minimum_size().y
	var y := slot.y - h if _layout.phone else 0.0
	set_rect(chip, Rect2(0.0, y, slot.x, h))


## Цель нажатия `touch_hud` — панели инструментов и карточке паузы (при смене).
func _apply_touch_target(touch: float) -> void:
	if is_equal_approx(touch, _touch_applied):
		return
	_touch_applied = touch
	_toolbar.set_touch_target(touch)
	_overlay.set_touch_target(touch)


# ---------------------------------------------------------------------------
# Esc на карточке паузы
# ---------------------------------------------------------------------------

## Перехват Esc раньше `PauseOverlay._input` (карточка паузы клавишу поглощает): последний
## ребёнок экрана получает `_input` раньше вуали. `handler() -> bool`: true — Esc обработан.
func install_escape_guard(handler: Callable) -> void:
	var guard := EscapeGuard.new()
	guard.name = "EscapeGuard"
	guard.handler = handler
	_screen.add_child(guard)


# ---------------------------------------------------------------------------
# Служебное
# ---------------------------------------------------------------------------

func ui_scale() -> UiScale:
	return _screen.get_node_or_null(^"/root/UiScaleRuntime") as UiScale


static func set_rect(node: Control, rect: Rect2) -> void:
	node.position = rect.position
	node.size = rect.size


## Узел-перехватчик Esc (см. `install_escape_guard`).
class EscapeGuard extends Node:
	var handler: Callable = Callable()

	func _input(event: InputEvent) -> void:
		var key := event as InputEventKey
		if key == null or not key.pressed or key.echo or not handler.is_valid():
			return
		if key.keycode != KEY_ESCAPE and key.physical_keycode != KEY_ESCAPE:
			return
		if handler.call():
			get_viewport().set_input_as_handled()
