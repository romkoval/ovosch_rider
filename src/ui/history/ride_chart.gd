class_name RideChart
extends Control
## График одной серии заезда (REQ-LOC-03): ломаная по точкам `RideSeries`,
## разрывы на «нет данных», под ней — серия целевой мощности плана (крит. 3),
## лёгкая сетка. Отрисовка — в `_draw()`; данные приходят через `set_series()`.
##
## В карточке заезда ред. 2 (T-085) так рисуется каденс; мощность и пульс — общий график
## `RideEffortChart` (рисовальщик HUD). Фон — вариация темы `InsetPanel` (поля 12, радиус 12),
## сетка — `line`, подпись максимума серии — Caption `tnum` `text2` слева на его высоте.

const TARGET_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const GRID := UiTokens.LINE
const LINE_WIDTH: float = 2.0
const GRID_LINES: int = 4
## Запас шкалы над максимумом: линия не прилипает к верхнему краю.
const HEADROOM: float = 1.15
const CAPTION_SIZE: int = 13
const LABEL_GAP: float = 4.0
const FONT_CAPTION_NUM: FontVariation = preload("res://src/ui/theme/fonts/inter_num_600.tres")

var _time := PackedFloat32Array()
var _values := PackedFloat32Array()
var _target := PackedFloat32Array()
var _color: Color = Color.WHITE
var _duration_sec: float = 0.0
var _max_value: float = 0.0
var _plot := Rect2()


## Задать серию: время корзин, значения (`NAN` — разрыв), цвет; `target` — цель плана
## той же длины (пусто — не рисуется).
func set_series(time_sec: PackedFloat32Array, values: PackedFloat32Array, color: Color,
		duration_sec: float, target: PackedFloat32Array = PackedFloat32Array()) -> void:
	_time = time_sec
	_values = values
	_target = target
	_color = color
	_duration_sec = maxf(duration_sec, 1.0)
	_max_value = 0.0
	for v in values:
		if not is_nan(v):
			_max_value = maxf(_max_value, v)
	for v in target:
		if not is_nan(v):
			_max_value = maxf(_max_value, v)
	queue_redraw()


func clear() -> void:
	set_series(PackedFloat32Array(), PackedFloat32Array(), Color.WHITE, 0.0)


## Число точек с данными в основной серии.
func point_count() -> int:
	var n: int = 0
	for v in _values:
		if not is_nan(v):
			n += 1
	return n


func has_target() -> bool:
	return _target.size() > 0


func max_value() -> float:
	return _max_value


## Поле графика: внутри полей фона `InsetPanel`, слева — колонка подписи шкалы.
func plot_rect() -> Rect2:
	var box := get_theme_stylebox("panel", "InsetPanel")
	var left: float = box.get_margin(SIDE_LEFT) if box != null else 0.0
	var top: float = box.get_margin(SIDE_TOP) if box != null else 0.0
	var right: float = box.get_margin(SIDE_RIGHT) if box != null else 0.0
	var bottom: float = box.get_margin(SIDE_BOTTOM) if box != null else 0.0
	var gutter: float = _gutter_width()
	return Rect2(left + gutter, top, maxf(size.x - left - right - gutter, 0.0), maxf(size.y - top - bottom, 0.0))


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
	for i in range(1, GRID_LINES):
		var y: float = roundf(f.position.y + f.size.y * float(i) / float(GRID_LINES)) + 0.5
		draw_line(Vector2(f.position.x, y), Vector2(f.end.x, y), GRID)
	if _max_value <= 0.0:
		return
	if _target.size() > 0:
		_draw_polyline(_target, TARGET_COLOR, 1.0)
	_draw_polyline(_values, _color, LINE_WIDTH)
	var text := str(roundi(_max_value))
	var w: float = FONT_CAPTION_NUM.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE).x
	var y_max: float = _to_pixel(0.0, _max_value).y
	draw_string(FONT_CAPTION_NUM, Vector2(f.position.x - LABEL_GAP - w, y_max + FONT_CAPTION_NUM.get_ascent(CAPTION_SIZE) * 0.4),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE, UiTokens.TEXT2)


func _gutter_width() -> float:
	if _max_value <= 0.0:
		return 0.0
	var text := str(roundi(_max_value))
	return ceilf(FONT_CAPTION_NUM.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE).x + LABEL_GAP * 2.0)


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
		draw_polyline(run, color, width)
	elif run.size() == 1:
		draw_circle(run[0], width, color)


## Точка серии в координатах узла (поле — `_plot`, вычисленное в начале `_draw`).
func _to_pixel(t: float, v: float) -> Vector2:
	var x: float = _plot.position.x + clampf(t / _duration_sec, 0.0, 1.0) * _plot.size.x
	var y: float = _plot.end.y - clampf(v / (_max_value * HEADROOM), 0.0, 1.0) * _plot.size.y
	return Vector2(x, y)
