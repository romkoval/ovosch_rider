class_name WorkoutChart
extends Control
## График целевой мощности по времени для предпросмотра (REQ-INT-05 крит. 1–4):
## сегменты `Workout.segments()` окрашены по зоне (`ZonePalette`), рампы — трапеции,
## точки `Workout.power_points()`, ось времени в минутах, линия и подпись FTP.
## Данные задаются `set_workout()`, отрисовка — в `_draw()`.

const PADDING_LEFT: float = 36.0
const PADDING_BOTTOM: float = 18.0
const PADDING_TOP: float = 8.0
const AXIS_TICK_MIN: int = 5
## Нижний запас по мощности: максимум ≥ FTP·1.2, чтобы FTP-линия была видна.
const MIN_Y_FACTOR: float = 1.2

var _points := PackedVector2Array()
var _segments: Array[Dictionary] = []
var _total_sec: int = 0
var _ftp_w: int = 0
var _max_w: float = 1.0


## Задать план; `ftp_w`/`intensity` — как у сессии.
func set_workout(workout: Workout, ftp_w: int, intensity: float = 1.0) -> void:
	_ftp_w = ftp_w
	if workout == null:
		_points = PackedVector2Array()
		_segments = []
		_total_sec = 0
		_max_w = 1.0
	else:
		_points = workout.power_points(ftp_w, intensity)
		_segments = workout.segments(ftp_w, intensity)
		_total_sec = workout.total_duration_sec()
		_max_w = maxf(float(ftp_w) * MIN_Y_FACTOR, 1.0)
		for p in _points:
			_max_w = maxf(_max_w, p.y * 1.1)
	queue_redraw()


func points() -> PackedVector2Array:
	return _points


func segments() -> Array[Dictionary]:
	return _segments


func total_sec() -> int:
	return _total_sec


## Подписи оси времени в минутах (0, 5, 10, …) до конца плана.
func axis_minutes() -> Array[int]:
	var out: Array[int] = []
	var minutes: int = int(ceil(float(_total_sec) / 60.0))
	var m: int = 0
	while m <= minutes:
		out.append(m)
		m += AXIS_TICK_MIN
	return out


## Цвет сегмента по зоне.
static func segment_color(segment: Dictionary) -> Color:
	return ZonePalette.color(ZonePalette.power_token(int(segment.get("zone", 0))))


func _draw() -> void:
	var w: float = size.x - PADDING_LEFT
	var h: float = size.y - PADDING_BOTTOM - PADDING_TOP
	if w <= 0.0 or h <= 0.0:
		return
	draw_rect(Rect2(0, 0, size.x, size.y), Color(0.1, 0.1, 0.12))
	if _total_sec <= 0:
		return
	var font := ThemeDB.fallback_font
	var font_size: int = 12
	for seg in _segments:
		var x0: float = PADDING_LEFT + float(seg["start_sec"]) / float(_total_sec) * w
		var x1: float = PADDING_LEFT + float(int(seg["start_sec"]) + int(seg["duration_sec"])) / float(_total_sec) * w
		var y0: float = PADDING_TOP + h - float(seg["start_watts"]) / _max_w * h
		var y1: float = PADDING_TOP + h - float(seg["end_watts"]) / _max_w * h
		var base: float = PADDING_TOP + h
		var poly := PackedVector2Array([Vector2(x0, base), Vector2(x0, y0), Vector2(x1, y1), Vector2(x1, base)])
		draw_colored_polygon(poly, segment_color(seg))
	var ftp_y: float = PADDING_TOP + h - float(_ftp_w) / _max_w * h
	draw_line(Vector2(PADDING_LEFT, ftp_y), Vector2(size.x, ftp_y), Color(1, 1, 1, 0.7), 1.0)
	draw_string(font, Vector2(2, ftp_y + 4), "FTP %d" % _ftp_w, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.9))
	for m in axis_minutes():
		var x: float = PADDING_LEFT + float(m * 60) / float(_total_sec) * w
		draw_line(Vector2(x, PADDING_TOP + h), Vector2(x, PADDING_TOP + h + 4), Color(1, 1, 1, 0.6), 1.0)
		draw_string(font, Vector2(x - 6, size.y - 2), str(m), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.8))
