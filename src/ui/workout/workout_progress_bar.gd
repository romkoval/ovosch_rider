class_name WorkoutProgressBar
extends Control
## Полоса прогресса тренировки (REQ-HUD-07): сегменты плана прямоугольниками,
## высота ∝ целевой мощности, цвет — зона (`ZonePalette`), курсор прошедшего времени;
## пройденные сегменты приглушены, пропущенные заштрихованы.
## Данные приходят из `HudModel.progress_segments()` и `HudModel.cursor()`; отрисовка — в `_draw()`.

const DONE_ALPHA: float = 0.35
const HATCH_STEP_PX: float = 6.0
const MIN_SEGMENT_HEIGHT_FRACTION: float = 0.08

var _segments: Array[Dictionary] = []
var _cursor: float = 0.0
var _total_sec: int = 0
var _max_watts: int = 1


## Обновить модель полосы и перерисовать.
func set_segments(segments: Array[Dictionary], cursor: float) -> void:
	_segments = segments
	_cursor = clampf(cursor, 0.0, 1.0)
	_total_sec = 0
	_max_watts = 1
	for s in _segments:
		_total_sec += int(s["duration_sec"])
		_max_watts = maxi(_max_watts, maxi(int(s["start_watts"]), int(s["end_watts"])))
	queue_redraw()


func segments() -> Array[Dictionary]:
	return _segments


func cursor() -> float:
	return _cursor


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	draw_rect(Rect2(0, 0, w, h), Color(0.12, 0.12, 0.14))
	if _total_sec <= 0:
		return
	for s in _segments:
		var x: float = float(s["start_sec"]) / float(_total_sec) * w
		var sw: float = maxf(float(s["duration_sec"]) / float(_total_sec) * w, 1.0)
		var watts: int = maxi(int(s["start_watts"]), int(s["end_watts"]))
		var frac: float = maxf(float(watts) / float(_max_watts), MIN_SEGMENT_HEIGHT_FRACTION)
		var sh: float = frac * h
		var color: Color = ZonePalette.color(str(s.get("zone_token", "")))
		var status: String = str(s.get("status", ""))
		if status == HudModel.SEGMENT_DONE:
			color.a = DONE_ALPHA
		var rect := Rect2(x, h - sh, sw, sh)
		draw_rect(rect, color)
		if status == HudModel.SEGMENT_SKIPPED:
			_draw_hatch(rect)
		if status == HudModel.SEGMENT_CURRENT:
			draw_rect(rect, Color(1, 1, 1, 0.9), false, 2.0)
	var cx: float = _cursor * w
	draw_line(Vector2(cx, 0), Vector2(cx, h), Color(1, 1, 1), 2.0)


func _draw_hatch(rect: Rect2) -> void:
	var x: float = rect.position.x - rect.size.y
	var stripe := Color(0, 0, 0, 0.6)
	while x < rect.end.x:
		var from := Vector2(maxf(x, rect.position.x), rect.end.y - maxf(0.0, rect.position.x - x) * 0.0)
		var to := Vector2(minf(x + rect.size.y, rect.end.x), rect.position.y)
		draw_line(Vector2(from.x, rect.end.y), to, stripe, 1.0)
		x += HATCH_STEP_PX
