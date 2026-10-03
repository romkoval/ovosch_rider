class_name RideAltitudeChart
extends Control
## Профиль высоты проеханного в карточке свободной езды (REQ-FRD-07 крит. 6; `docs/game/ui.md`
## п. 8.5, `docs/game/tracks.md` п. 7.2, 7.3).
##
## Данные — `RideSeries.altitude_by_distance()`: точки (дистанция от старта, высота), круги
## подряд. Ось X — вся проеханная дистанция, подписи по км (шаг — как у крупного профиля
## трассы, ≤ 10 подписей); ось Y — размах max(перепад, 150 м) с запасом 10 % (как крупный
## профиль), слева подписи максимума и минимума высоты с линиями сетки `line`. Заливка под
## профилем кусками по цвету уклона (палитра `hud.md` п. 11, кусок ≥ 100 м — окно уклона
## D3D-08 — и ≥ 2 lp), белый контур 1.5 lp с альфой 0.85; граница круга — вертикаль пунктиром.
## Фон — вариация темы `InsetPanel` (поля 12). Без данных — только фон.

## Поля и размеры, lp (`tracks.md` п. 7.2).
const MIN_HEIGHT: float = 120.0
const AXIS_HEIGHT: float = 22.0
const LABEL_GAP: float = 4.0
const CAPTION_SIZE: int = 13
const OUTLINE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.85)
const OUTLINE_WIDTH: float = 1.5
const LAP_LINE_ALPHA: float = 0.6
const LAP_DASH: float = 4.0
## Наименьший кусок заливки по дистанции, м (окно уклона D3D-08) и по ширине, lp.
const MIN_PIECE_M: float = 100.0
const MIN_PIECE_PX: float = 2.0
## Минимальный размах шкалы высоты, м, и запас сверху и снизу (как крупный профиль трассы).
const MIN_SPAN_M: float = 150.0
const MARGIN_FRACTION: float = 0.10
const FONT_CAPTION_NUM: FontVariation = preload("res://src/ui/theme/fonts/inter_num_600.tres")

var _points := PackedVector2Array()
var _lap_m: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _get_minimum_size() -> Vector2:
	return Vector2(0.0, MIN_HEIGHT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()


## Точки `(distance_m, altitude_m)` по возрастанию дистанции и длина круга трассы, м
## (0 — границы кругов не рисуются).
func set_profile(points: PackedVector2Array, lap_length_m: float) -> void:
	_points = points
	_lap_m = maxf(lap_length_m, 0.0)
	queue_redraw()


func clear() -> void:
	set_profile(PackedVector2Array(), 0.0)


func point_count() -> int:
	return _points.size()


## Проеханная дистанция по профилю, м.
func total_distance_m() -> float:
	return _points[_points.size() - 1].x if _points.size() > 0 else 0.0


## Дистанции границ кругов внутри профиля, м.
func lap_marks() -> PackedFloat32Array:
	return lap_boundaries(total_distance_m(), _lap_m)


## Границы кругов: L, 2L, … строго внутри (0; `total_m`).
static func lap_boundaries(total_m: float, lap_m: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if lap_m <= 0.0:
		return out
	var k: int = 1
	while float(k) * lap_m < total_m - 1e-3:
		out.append(float(k) * lap_m)
		k += 1
	return out


## Куски заливки: подряд идущие точки, пока кусок не наберёт `min_len_m` по дистанции.
## `{from, to, grade}` — индексы первой и последней точки куска и средний уклон, %.
static func grade_pieces(points: PackedVector2Array, min_len_m: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n: int = points.size()
	if n < 2:
		return out
	var a: int = 0
	for i in range(1, n):
		var length: float = points[i].x - points[a].x
		if length >= min_len_m or i == n - 1:
			var grade: float = (points[i].y - points[a].y) / length * 100.0 if length > 0.0 else 0.0
			out.append({"from": a, "to": i, "grade": grade})
			a = i
	return out


## Шкала высот `(низ, верх)`, м.
static func height_range(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2(0.0, MIN_SPAN_M)
	var lo: float = INF
	var hi: float = -INF
	for p in points:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	return RoutePreviewModel.y_range_for(lo, hi, MIN_SPAN_M, MARGIN_FRACTION)


## Подписи км: `{distance_m, text}` — 0, шаг, 2·шаг, … ≤ дистанции.
static func km_labels(total_m: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if total_m <= 0.0:
		return out
	var step: int = RoutePreviewModel.km_step(total_m)
	var km: int = 0
	while float(km) * 1000.0 <= total_m + 1e-6:
		out.append({"distance_m": float(km) * 1000.0, "text": "%d" % km})
		km += step
	return out


## Поле графика: внутри полей фона, справа от колонки подписей высот, над шкалой км.
func field_rect() -> Rect2:
	var box := _background()
	var left: float = box.get_margin(SIDE_LEFT) if box != null else 0.0
	var top: float = box.get_margin(SIDE_TOP) if box != null else 0.0
	var right: float = box.get_margin(SIDE_RIGHT) if box != null else 0.0
	var bottom: float = box.get_margin(SIDE_BOTTOM) if box != null else 0.0
	var gutter: float = _gutter_width()
	return Rect2(left + gutter, top,
		maxf(size.x - left - right - gutter, 0.0),
		maxf(size.y - top - bottom - AXIS_HEIGHT, 0.0))


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var box := _background()
	if box != null:
		draw_style_box(box, Rect2(Vector2.ZERO, size))
	var f := field_rect()
	var total: float = total_distance_m()
	if _points.size() < 2 or total <= 0.0 or f.size.x < 1.0 or f.size.y < 1.0:
		return
	var range_m := height_range(_points)
	_draw_height_grid(f, range_m)
	_draw_fill(f, range_m, total)
	_draw_outline(f, range_m, total)
	_draw_laps(f, total)
	_draw_height_labels(f, range_m)
	_draw_km_axis(f, total)


func _x(f: Rect2, distance_m: float, total: float) -> float:
	return f.position.x + clampf(distance_m / total, 0.0, 1.0) * f.size.x


func _y(f: Rect2, height_m: float, range_m: Vector2) -> float:
	var span: float = maxf(range_m.y - range_m.x, 1e-3)
	return f.position.y + f.size.y * (1.0 - clampf((height_m - range_m.x) / span, 0.0, 1.0))


func _draw_fill(f: Rect2, range_m: Vector2, total: float) -> void:
	var bottom: float = f.end.y
	# Кусок не уже `MIN_PIECE_PX`: на длинном заезде 100 м уже пикселя.
	var min_len: float = maxf(MIN_PIECE_M, MIN_PIECE_PX / maxf(f.size.x, 1.0) * total)
	for piece in grade_pieces(_points, min_len):
		var color: Color = UiTokens.grade_color(float(piece["grade"]))
		var colors := PackedColorArray([color, color, color, color])
		for i in range(int(piece["from"]) + 1, int(piece["to"]) + 1):
			var a := Vector2(_x(f, _points[i - 1].x, total), _y(f, _points[i - 1].y, range_m))
			var b := Vector2(_x(f, _points[i].x, total), _y(f, _points[i].y, range_m))
			if b.x <= a.x:
				continue
			draw_primitive(PackedVector2Array([a, b, Vector2(b.x, bottom), Vector2(a.x, bottom)]), colors, PackedVector2Array())


func _draw_outline(f: Rect2, range_m: Vector2, total: float) -> void:
	var line := PackedVector2Array()
	line.resize(_points.size())
	for i in _points.size():
		line[i] = Vector2(_x(f, _points[i].x, total), _y(f, _points[i].y, range_m))
	draw_polyline(line, OUTLINE_COLOR, OUTLINE_WIDTH, true)


func _draw_laps(f: Rect2, total: float) -> void:
	var color := Color(UiTokens.TEXT, LAP_LINE_ALPHA)
	for d in lap_marks():
		var x: float = roundf(_x(f, d, total)) + 0.5
		draw_dashed_line(Vector2(x, f.position.y), Vector2(x, f.end.y), color, 1.0, LAP_DASH)


func _draw_height_grid(f: Rect2, range_m: Vector2) -> void:
	for h in _extremes():
		var y: float = roundf(_y(f, h, range_m)) + 0.5
		draw_line(Vector2(f.position.x, y), Vector2(f.end.x, y), UiTokens.LINE, 1.0)


## Подписи максимума и минимума слева от поля; близкие линии — раздвигаются поровну.
func _draw_height_labels(f: Rect2, range_m: Vector2) -> void:
	var ext := _extremes()
	var line_h: float = FONT_CAPTION_NUM.get_height(CAPTION_SIZE)
	var y_top: float = _y(f, ext[0], range_m)
	var y_bottom: float = _y(f, ext[1], range_m)
	var lack: float = line_h + 2.0 - (y_bottom - y_top)
	if lack > 0.0:
		y_top -= lack * 0.5
		y_bottom += lack * 0.5
	var half_text: float = (FONT_CAPTION_NUM.get_ascent(CAPTION_SIZE) - FONT_CAPTION_NUM.get_descent(CAPTION_SIZE)) * 0.5
	var right: float = f.position.x - LABEL_GAP
	var centers: Array[float] = [y_top, y_bottom]
	for i in 2:
		var text: String = RoutePreviewModel.format_height_m(ext[i])
		var w: float = FONT_CAPTION_NUM.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE).x
		draw_string(FONT_CAPTION_NUM, Vector2(right - w, centers[i] + half_text), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE, UiTokens.TEXT2)


func _draw_km_axis(f: Rect2, total: float) -> void:
	var baseline: float = f.end.y + LABEL_GAP + FONT_CAPTION_NUM.get_ascent(CAPTION_SIZE)
	var labels := km_labels(total)
	for k in labels.size():
		var text: String = str(labels[k]["text"])
		if k == labels.size() - 1:
			text += " " + String(TranslationServer.translate(RoutePreviewModel.KEY_UNIT_KM))
		var w: float = FONT_CAPTION_NUM.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE).x
		var x: float = clampf(_x(f, float(labels[k]["distance_m"]), total) - w * 0.5, f.position.x, maxf(f.end.x - w, f.position.x))
		draw_string(FONT_CAPTION_NUM, Vector2(x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE, UiTokens.TEXT2)


## Максимум и минимум высоты профиля, м.
func _extremes() -> Array[float]:
	var lo: float = INF
	var hi: float = -INF
	for p in _points:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	return [hi, lo]


func _gutter_width() -> float:
	if _points.is_empty():
		return 0.0
	var widest: float = 0.0
	for h in _extremes():
		var text: String = RoutePreviewModel.format_height_m(h)
		widest = maxf(widest, FONT_CAPTION_NUM.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE).x)
	return ceilf(widest + LABEL_GAP * 2.0)


func _background() -> StyleBox:
	return get_theme_stylebox("panel", "InsetPanel")
