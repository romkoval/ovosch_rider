class_name RideChart
extends Control
## График каденса в карточке заезда (REQ-LOC-03; `docs/game/ui.md` п. 8.5 п. 2, решение ред. 2):
## отдельный от общего графика мощности и пульса, чтобы там не было третьей шкалы.
##
## Вид: фон — вариация темы `InsetPanel` (радиус 12), линия 2 lp `text2` без заливки и обводки,
## разрывы на «нет данных» (`NAN`). Шкала Y — от `SCALE_MIN` до max(`SCALE_MAX_FLOOR`,
## ⌈максимум / 10⌉·10) об/мин; подписи `GRID_VALUES` (60 и 90) слева — Caption `tnum` `text2`,
## тонкие линии сетки `line` только на этих значениях. Поле графика по горизонтали — те же
## поля, что у графика мощности (`field_left` / `field_right` задаёт карточка из
## `RideEffortChart`), поэтому минуты на двух графиках совпадают по вертикали.
## Данные приходят через `set_series()`; отрисовка — в `_draw()`.

const LINE_WIDTH: float = 2.0
const GRID := UiTokens.LINE
## Шкала, об/мин (`ui.md` п. 8.5).
const SCALE_MIN: float = 40.0
const SCALE_MAX_FLOOR: float = 120.0
const GRID_VALUES: Array[float] = [60.0, 90.0]
## Поля поля графика сверху и снизу, lp (как у фона `InsetPanel`).
const FIELD_TOP: float = 12.0
const FIELD_BOTTOM: float = 12.0
const CAPTION_SIZE: int = 13
const LABEL_GAP: float = 6.0
const FONT_CAPTION_NUM: FontVariation = preload("res://src/ui/theme/fonts/inter_num_600.tres")

## Поля поля графика слева и справа, lp (по умолчанию — как у графика мощности HUD).
@export var field_left: float = HudChart.HUD_INSET_LEFT:
	set(value):
		field_left = maxf(value, 0.0)
		queue_redraw()
@export var field_right: float = HudChart.HUD_INSET_RIGHT:
	set(value):
		field_right = maxf(value, 0.0)
		queue_redraw()

var _time := PackedFloat32Array()
var _values := PackedFloat32Array()
var _color: Color = UiTokens.TEXT2
var _duration_sec: float = 0.0
var _max_value: float = 0.0
var _scale_max: float = SCALE_MAX_FLOOR
var _plot := Rect2()


## Задать серию: время корзин, значения (`NAN` — разрыв), цвет линии, длительность заезда.
func set_series(time_sec: PackedFloat32Array, values: PackedFloat32Array, color: Color,
		duration_sec: float) -> void:
	_time = time_sec
	_values = values
	_color = color
	_duration_sec = maxf(duration_sec, 1.0)
	_max_value = 0.0
	for v in values:
		if not is_nan(v):
			_max_value = maxf(_max_value, v)
	_scale_max = scale_max_for(_max_value)
	queue_redraw()


func clear() -> void:
	set_series(PackedFloat32Array(), PackedFloat32Array(), UiTokens.TEXT2, 0.0)


## Верх шкалы: max(`SCALE_MAX_FLOOR`, ⌈максимум / 10⌉·10).
static func scale_max_for(max_value: float) -> float:
	return maxf(SCALE_MAX_FLOOR, ceilf(max_value / 10.0) * 10.0)


## Число точек с данными в серии.
func point_count() -> int:
	var n: int = 0
	for v in _values:
		if not is_nan(v):
			n += 1
	return n


func max_value() -> float:
	return _max_value


## Шкала Y: (низ, верх), об/мин.
func scale_range() -> Vector2:
	return Vector2(SCALE_MIN, _scale_max)


## Значения, на которых есть подписи и линии сетки.
func grid_values() -> Array[float]:
	return GRID_VALUES.duplicate()


## Поле графика в координатах узла.
func plot_rect() -> Rect2:
	return Rect2(field_left, FIELD_TOP, maxf(size.x - field_left - field_right, 0.0),
		maxf(size.y - FIELD_TOP - FIELD_BOTTOM, 0.0))


## Y значения `v` в координатах узла (за шкалой — у края поля).
func y_of(v: float) -> float:
	var f := plot_rect()
	return f.end.y - clampf((v - SCALE_MIN) / (_scale_max - SCALE_MIN), 0.0, 1.0) * f.size.y


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var box := get_theme_stylebox("panel", "InsetPanel")
	if box != null:
		draw_style_box(box, Rect2(Vector2.ZERO, size))
	var f := plot_rect()
	_plot = f
	if f.size.x < 1.0 or f.size.y < 1.0:
		return
	var shift: float = (FONT_CAPTION_NUM.get_ascent(CAPTION_SIZE) - FONT_CAPTION_NUM.get_descent(CAPTION_SIZE)) * 0.5
	for value in GRID_VALUES:
		var y: float = roundf(y_of(value)) + 0.5
		draw_line(Vector2(f.position.x, y), Vector2(f.end.x, y), GRID)
		var text := str(roundi(value))
		var w: float = FONT_CAPTION_NUM.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE).x
		draw_string(FONT_CAPTION_NUM, Vector2(f.position.x - LABEL_GAP - w, y + shift), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE, UiTokens.TEXT2)
	if _max_value <= 0.0:
		return
	_draw_polyline(_values, _color, LINE_WIDTH)


## Ломаная с разрывами на `NAN`.
func _draw_polyline(values: PackedFloat32Array, color: Color, width: float) -> void:
	var run := PackedVector2Array()
	var n: int = mini(values.size(), _time.size())
	for i in n:
		var v: float = values[i]
		if is_nan(v):
			_flush_run(run, color, width)
			run = PackedVector2Array()
			continue
		run.append(_to_pixel(_time[i], v))
	_flush_run(run, color, width)


func _flush_run(run: PackedVector2Array, color: Color, width: float) -> void:
	if run.size() >= 2:
		draw_polyline(run, color, width, true)
	elif run.size() == 1:
		draw_circle(run[0], width, color)


## Точка серии в координатах узла (поле — `_plot`, вычисленное в начале `_draw`).
func _to_pixel(t: float, v: float) -> Vector2:
	var x: float = _plot.position.x + clampf(t / _duration_sec, 0.0, 1.0) * _plot.size.x
	return Vector2(x, y_of(v))
