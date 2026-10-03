class_name RideChart
extends Control
## График одной серии заезда (REQ-LOC-03): ломаная по точкам `RideSeries`,
## разрывы на «нет данных», поверх — серия целевой мощности плана (крит. 3),
## лёгкая сетка. Отрисовка — в `_draw()`; данные приходят через `set_series()`.

const BACKGROUND := Color(0.10, 0.10, 0.12)
const GRID := Color(0.22, 0.22, 0.26)
const TARGET_COLOR := Color(0.95, 0.95, 0.95, 0.55)
const LINE_WIDTH: float = 1.5
const GRID_LINES: int = 4

var _time := PackedFloat32Array()
var _values := PackedFloat32Array()
var _target := PackedFloat32Array()
var _color: Color = Color.WHITE
var _duration_sec: float = 0.0
var _max_value: float = 0.0


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


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	draw_rect(Rect2(0, 0, w, h), BACKGROUND)
	for i in range(1, GRID_LINES):
		var y: float = h * float(i) / float(GRID_LINES)
		draw_line(Vector2(0, y), Vector2(w, y), GRID)
	if _max_value <= 0.0:
		return
	if _target.size() > 0:
		_draw_polyline(_target, TARGET_COLOR, 1.0)
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
		draw_polyline(run, color, width)
	elif run.size() == 1:
		draw_circle(run[0], width, color)


func _to_pixel(t: float, v: float) -> Vector2:
	var x: float = clampf(t / _duration_sec, 0.0, 1.0) * size.x
	var y: float = size.y - clampf(v / _max_value, 0.0, 1.0) * size.y
	return Vector2(x, y)
