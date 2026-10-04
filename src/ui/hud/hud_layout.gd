class_name HudLayout
extends RefCounted
## Геометрия HUD заезда (`docs/game/hud.md` п. 4, 4.1; REQ-HUD-13 крит. 1, 4–6, 9, 10).
## Чистая математика без узлов: по размеру холста, безопасной зоне и масштабу HUD считает
## прямоугольники слотов. Экран тренировки (и позже экран свободной езды) расставляет по
## ним свои узлы; тесты проверяют доли окна и непересечение без сцены.
##
## Единицы — lp текущего холста HUD. На экране заезда `Window.content_scale_factor = s`
## (`UiScale.Mode.HUD`), поэтому всё, что в `hud.md` задано как «X·s», здесь — просто X;
## то, что `hud.md` оставляет без множителя (отступ телефона 12 lp, нижняя граница высоты
## графика 112 lp), делится на `s`.
##
## Слоты:
## - `panel` — панель цифр 640×166, верх-центр безопасной зоны, `y = T + M`;
## - `list_slot` — список интервалов или панель рельефа: верх-лево, ширина
##   `w_l = min(0.22·W, 300, panel.x − 16 − (L + M))`, высота — наибольшая допустимая
##   (`min(0.60·H, верх графика − 24 − y)`), содержимое занимает её сверху по своей высоте;
## - `chart` — график: низ, от `L` до `W − R` (не шире 1600 lp, по центру), высота
##   `clamp(0.17·H, 112/s, 0.22·H)`; `chart_gradient` — 28 lp над ним;
## - `pause_button` — кнопка паузы в правом верхнем углу: квадрат `touch_hud` или
##   фактический размер кнопки (`pause_size`), если она больше; `status_slot` — фишки
##   статусов: строкой слева от кнопки, если справа от панели свободно ≥ 260 lp и строка
##   фишек (`status_row_width`) помещается, иначе столбиком под кнопкой (`status_vertical`);
## - `hint_slot` — подсказка и фишка «ДАЛЕЕ»: на компьютере и планшете под панелью (+8),
##   высота 40; на телефоне у низа кадра между центральной зоной и графиком (`hud.md` п. 4.1):
##   низ слота = верх графика − 3, верх — не выше низа центральной зоны (75 % H), высота не
##   больше 40 (≈ 34 lp HUD на 19.5:9 — содержимое слота на телефоне компактное, кегль 14);
##   ширина 0.5·W;
## - `toolbar_slot` — колонка панели инструментов у правого края, правее центральной зоны,
##   между статусами и градиентом графика.
##
## Центральная зона (REQ-HUD-13 крит. 5) — `center_zone()`: 30–70 % ширины, 35–75 % высоты.

const PANEL_SIZE: Vector2 = Vector2(640, 166)
## Внешний отступ `M` (lp HUD); на телефоне — 12 lp базового холста (без множителя).
const MARGIN: float = 16.0
const MARGIN_PHONE_BASE: float = 12.0
## Зазор между списком и панелью цифр (REQ-HUD-13 крит. 6: ≥ 16·s).
const LIST_PANEL_GAP: float = 16.0
const LIST_MAX_WIDTH: float = 300.0
const LIST_WIDTH_FRACTION: float = 0.22
const LIST_MAX_HEIGHT_FRACTION: float = 0.60
## Зазор между низом списка и верхом графика.
const LIST_CHART_GAP: float = 24.0
const CHART_HEIGHT_FRACTION: float = 0.17
## Нижняя граница высоты графика — 112 lp базового холста (на телефоне не масштабируется).
const CHART_MIN_HEIGHT_BASE: float = 112.0
const CHART_MAX_HEIGHT_FRACTION: float = 0.22
## 21:9 и шире: график не шире 1600 lp, по центру.
const CHART_MAX_WIDTH: float = 1600.0
const CHART_GRADIENT_HEIGHT: float = 28.0
const HINT_PANEL_GAP: float = 8.0
const HINT_HEIGHT: float = 40.0
## Слот подсказки телефона: низ — на 3 lp выше графика, высота — зазор до центральной зоны.
const HINT_CHART_GAP_PHONE: float = 3.0
const HINT_WIDTH_FRACTION: float = 0.5
const STATUS_CHIP_HEIGHT: float = 24.0
const STATUS_GAP: float = 8.0
## Фишки идут строкой, если справа от панели свободно не меньше этого (иначе — столбиком).
const STATUS_ROW_MIN_FREE: float = 260.0
## Число фишек статуса, под которое резервируется столбик (станок, пульс, ERG/SIM, интенсивность).
const STATUS_CHIP_COUNT: int = 4
const TOOLBAR_MAX_WIDTH: float = 280.0
## Центральная зона в долях окна (REQ-HUD-13 крит. 5).
const CENTER_ZONE_FRACTION: Rect2 = Rect2(0.30, 0.35, 0.40, 0.40)
## Верхняя граница панели цифр в долях высоты (REQ-HUD-13 крит. 1).
const PANEL_MAX_BOTTOM_FRACTION: float = 0.30

var canvas_size: Vector2 = Vector2.ZERO
## Отступы безопасной зоны `Vector4(слева, сверху, справа, снизу)` (порядок `Side`).
var safe_margins: Vector4 = Vector4.ZERO
var hud_scale: float = 1.0
var phone: bool = false
var margin: float = MARGIN

var panel: Rect2
var list_slot: Rect2
var chart: Rect2
var chart_gradient: Rect2
var pause_button: Rect2
var status_slot: Rect2
var status_vertical: bool = false
var hint_slot: Rect2
var toolbar_slot: Rect2


## Раскладка для холста `size` (lp HUD), безопасной зоны `safe` (lp HUD), масштаба HUD `s`,
## цели нажатия `touch_hud` (lp HUD) и признака телефона (подсказка у низа, отступ 12 lp).
## `pause_size` — фактический размер кнопки паузы (не меньше `touch_hud`), `status_row_width` —
## ширина строки фишек статусов (0 — не проверять, помещается ли строка).
static func compute(size: Vector2, safe: Vector4 = Vector4.ZERO, s: float = 1.0,
		touch_hud: float = UiScale.TOUCH_HUD_DESKTOP, is_phone: bool = false,
		pause_size: Vector2 = Vector2.ZERO, status_row_width: float = 0.0) -> HudLayout:
	var l := HudLayout.new()
	l.canvas_size = size
	l.safe_margins = safe
	l.hud_scale = maxf(s, 1.0)
	l.phone = is_phone
	l._build(Vector2(maxf(pause_size.x, touch_hud), maxf(pause_size.y, touch_hud)), status_row_width)
	return l


## Центральная зона окна размера `size` (REQ-HUD-13 крит. 5).
static func center_zone(size: Vector2) -> Rect2:
	return Rect2(CENTER_ZONE_FRACTION.position * size, CENTER_ZONE_FRACTION.size * size)


## Высота графика: `clamp(0.17·H, 112/s, 0.22·H)`.
static func chart_height(height: float, s: float = 1.0) -> float:
	return clampf(CHART_HEIGHT_FRACTION * height, CHART_MIN_HEIGHT_BASE / maxf(s, 1.0), CHART_MAX_HEIGHT_FRACTION * height)


## Безопасная (рабочая) область холста без отступов безопасной зоны.
func safe_rect() -> Rect2:
	var left := safe_margins.x
	var top := safe_margins.y
	return Rect2(left, top, canvas_size.x - left - safe_margins.z, canvas_size.y - top - safe_margins.w)


## Непрозрачные слоты по именам — для проверок пересечения и центральной зоны.
## Градиент графика сюда не входит: его непрозрачность < 0.5 (`hud.md` п. 4.1).
func opaque_slots() -> Dictionary:
	return {
		"panel": panel,
		"list": list_slot,
		"chart": chart,
		"pause": pause_button,
		"status": status_slot,
		"hint": hint_slot,
		"toolbar": toolbar_slot,
	}


func _build(pause_size: Vector2, status_row_width: float) -> void:
	var w := canvas_size.x
	var h := canvas_size.y
	var left := safe_margins.x
	var top := safe_margins.y
	var right := safe_margins.z
	var bottom := safe_margins.w
	margin = MARGIN_PHONE_BASE / hud_scale if phone else MARGIN
	var safe := safe_rect()

	# Панель цифр: верх-центр безопасной зоны.
	panel = Rect2(Vector2(safe.position.x + (safe.size.x - PANEL_SIZE.x) * 0.5, top + margin), PANEL_SIZE)

	# График: низ, во всю ширину безопасной зоны (не шире 1600 по центру).
	var chart_h := chart_height(h, hud_scale)
	var chart_w := minf(w - left - right, CHART_MAX_WIDTH)
	var chart_x := left + (w - left - right - chart_w) * 0.5
	chart = Rect2(chart_x, h - bottom - chart_h, chart_w, chart_h)
	chart_gradient = Rect2(chart_x, chart.position.y - CHART_GRADIENT_HEIGHT, chart_w, CHART_GRADIENT_HEIGHT)

	# Левый слот: ширина не налезает на панель (зазор 16), высота до графика − 24.
	var list_pos := Vector2(left + margin, top + margin)
	var list_w := minf(minf(LIST_WIDTH_FRACTION * w, LIST_MAX_WIDTH), panel.position.x - LIST_PANEL_GAP - list_pos.x)
	var list_h := minf(LIST_MAX_HEIGHT_FRACTION * h, chart.position.y - LIST_CHART_GAP - list_pos.y)
	list_slot = Rect2(list_pos, Vector2(maxf(list_w, 0.0), maxf(list_h, 0.0)))

	# Кнопка паузы и фишки статусов.
	var edge := w - right - margin
	pause_button = Rect2(Vector2(edge - pause_size.x, top + margin), pause_size)
	var free_right := edge - panel.end.x
	var row_x := panel.end.x + LIST_PANEL_GAP
	var row_w := maxf(pause_button.position.x - STATUS_GAP - row_x, 0.0)
	status_vertical = free_right < STATUS_ROW_MIN_FREE or status_row_width > row_w
	if status_vertical:
		var column_h := STATUS_CHIP_COUNT * STATUS_CHIP_HEIGHT + (STATUS_CHIP_COUNT - 1) * STATUS_GAP
		status_slot = Rect2(Vector2(pause_button.position.x, pause_button.end.y + STATUS_GAP), Vector2(pause_size.x, column_h))
	else:
		var row_y := pause_button.position.y + (pause_size.y - STATUS_CHIP_HEIGHT) * 0.5
		status_slot = Rect2(Vector2(row_x, row_y), Vector2(row_w, STATUS_CHIP_HEIGHT))

	# Слот подсказки.
	var hint_w := HINT_WIDTH_FRACTION * w
	if phone:
		# Между центральной зоной и верхом графика: слот не заходит в центр (REQ-HUD-13 крит. 9),
		# поэтому его высота — весь зазор, но не больше 40.
		var hint_bottom := chart.position.y - HINT_CHART_GAP_PHONE
		var center_bottom := center_zone(canvas_size).end.y
		var hint_h := clampf(hint_bottom - center_bottom, 0.0, HINT_HEIGHT)
		hint_slot = Rect2(Vector2(chart.get_center().x - hint_w * 0.5, hint_bottom - hint_h), Vector2(hint_w, hint_h))
	else:
		hint_slot = Rect2(Vector2(panel.get_center().x - hint_w * 0.5, panel.end.y + HINT_PANEL_GAP), Vector2(hint_w, HINT_HEIGHT))

	# Панель инструментов: правее центральной зоны, ниже статусов и панели, выше градиента.
	var center := center_zone(canvas_size)
	var tool_x := maxf(edge - TOOLBAR_MAX_WIDTH, center.end.x + margin)
	var tool_top := maxf(maxf(status_slot.end.y, pause_button.end.y), panel.end.y) + margin
	var tool_bottom := chart_gradient.position.y - margin
	toolbar_slot = Rect2(Vector2(tool_x, tool_top), Vector2(maxf(edge - tool_x, 0.0), maxf(tool_bottom - tool_top, 0.0)))
