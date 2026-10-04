class_name RoutePreview
extends Control
## Превью профиля высот трассы (REQ-FRD-03 крит. 3, 5, 6; REQ-UIX-03 крит. 2, 4 — трасса;
## `docs/game/tracks.md` п. 7, `docs/game/ui.md` п. 6 «ElevationThumb»). Без интерактива:
## нажатия проходят к родителю (карточка `CardButton`).
##
## Все числа — из `RoutePreviewModel`; узел только раскладывает и рисует.
## - Миниатюра (`Mode.THUMB`, `tracks.md` п. 7.1): фон `InsetPanel` темы (радиус 12, поля 12),
##   сверху вниз градиент цвета настроения трассы (альфа 0.10 → 0), заливка кусками по палитре
##   уклона, белый контур 1.5 lp (альфа 0.85); подписей нет. У приморья под мостом — полоса
##   воды 4 lp и значок `waves` 14 lp, у гор — треугольник-вершина 8 lp над максимумом.
## - Крупный профиль (`Mode.LARGE`, `tracks.md` п. 7.2): без фона; линии сетки и подписи
##   максимальной и минимальной высоты (ближе 14 lp — только максимум), шкала км под полем,
##   подписи подъёмов без пересечений, пунктир старта с флажком на s = 0, мост — полоса воды
##   и подпись.

## Контур профиля (`tracks.md` п. 7.1).
const OUTLINE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.85)
const OUTLINE_WIDTH: float = 1.5
## Градиент цвета настроения сверху вниз: альфа вверху (внизу 0).
const MOOD_ALPHA: float = 0.10
## Вода под мостом (`tracks.md` п. 7.1).
const WATER_COLOR: Color = Color(0.30, 0.65, 0.95)
const WATER_BAND_HEIGHT: float = 4.0
const ICON_SIZE: float = 14.0
const ICON_GAP: float = 2.0
## Треугольник-вершина гор: ширина и высота, отступ над максимумом.
const PEAK_SIZE: float = 8.0
const PEAK_GAP: float = 3.0
## Минимальная высота: миниатюра — 56 (`ui.md` п. 6), крупный профиль — 120.
const THUMB_MIN_HEIGHT: float = 56.0
const LARGE_MIN_HEIGHT: float = 120.0
## Крупный профиль: высота полосы шкалы км под полем, размеры подписей.
const AXIS_HEIGHT: float = 22.0
const CAPTION_SIZE: int = 13
const CLIMB_LABEL_SIZE: int = 12
const LABEL_GAP: float = 4.0
const START_DASH: float = 4.0
const START_LINE_ALPHA: float = 0.6
## Шаг дуги скруглённого угла фона градиента, сегментов на угол.
const CORNER_SEGMENTS: int = 6

const FONT_CAPTION_NUM: FontVariation = preload("res://src/ui/theme/fonts/inter_num_600.tres")
const FONT_CLIMB: FontVariation = preload("res://src/ui/theme/fonts/inter_650.tres")
const ICON_WAVES: Texture2D = preload("res://assets/icons/lucide/waves.svg")
const ICON_FLAG: Texture2D = preload("res://assets/icons/lucide/flag.svg")

## Режим превью.
@export var mode: RoutePreviewModel.Mode = RoutePreviewModel.Mode.THUMB:
	set(value):
		mode = value
		update_minimum_size()
		queue_redraw()

var model: RoutePreviewModel:
	set(value):
		model = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


## Показать трассу каталога.
func set_route(route: RouteCatalog.RouteDef) -> void:
	model = RoutePreviewModel.for_route(route) if route != null else null


func _get_minimum_size() -> Vector2:
	return Vector2(0.0, LARGE_MIN_HEIGHT if mode == RoutePreviewModel.Mode.LARGE else THUMB_MIN_HEIGHT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED or what == NOTIFICATION_RESIZED:
		queue_redraw()


## Поле графика в координатах узла: миниатюра — внутри полей фона; крупный — над шкалой км,
## справа от колонки подписей высот.
func field_rect() -> Rect2:
	var full := Rect2(Vector2.ZERO, size)
	if mode == RoutePreviewModel.Mode.LARGE:
		var gutter: float = minf(height_gutter_width(), size.x)
		return Rect2(gutter, 0.0, size.x - gutter, maxf(size.y - AXIS_HEIGHT, 0.0))
	var box := _background()
	if box == null:
		return full
	var left := box.get_margin(SIDE_LEFT)
	var top := box.get_margin(SIDE_TOP)
	return Rect2(left, top,
		maxf(size.x - left - box.get_margin(SIDE_RIGHT), 0.0),
		maxf(size.y - top - box.get_margin(SIDE_BOTTOM), 0.0))


## Ширина колонки подписей высот слева от поля крупного профиля (0 у миниатюры и без модели).
func height_gutter_width() -> float:
	if mode != RoutePreviewModel.Mode.LARGE or model == null or not model.is_valid():
		return 0.0
	var widest: float = 0.0
	for label in model.height_labels():
		widest = maxf(widest, FONT_CAPTION_NUM.get_string_size(label["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE).x)
	return ceilf(widest + LABEL_GAP * 2.0)


## Отображение круга на поле в текущем режиме (null без модели).
func current_plot() -> RoutePreviewModel.Plot:
	if model == null or not model.is_valid():
		return null
	return model.plot(mode, field_rect())


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	if mode == RoutePreviewModel.Mode.THUMB:
		_draw_thumb_background()
	var p := current_plot()
	if p == null or p.rect.size.x < 1.0 or p.rect.size.y < 1.0:
		return
	if mode == RoutePreviewModel.Mode.LARGE:
		_draw_height_grid(p)
	_draw_profile(p)
	_draw_bridges(p)
	if mode == RoutePreviewModel.Mode.THUMB:
		if model.marks_peak:
			_draw_peak(p)
	else:
		_draw_start_line(p)
		_draw_height_labels(p)
		_draw_km_axis(p)
		_draw_climb_labels(p)


func _background() -> StyleBox:
	return get_theme_stylebox("panel", "InsetPanel")


func _draw_thumb_background() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var box := _background()
	if box != null:
		draw_style_box(box, rect)
	if model == null:
		return
	var radius: float = 0.0
	if box is StyleBoxFlat:
		radius = float((box as StyleBoxFlat).corner_radius_top_left)
	var points := _rounded_rect(rect, radius)
	var colors := PackedColorArray()
	for pt in points:
		var t: float = pt.y / maxf(rect.size.y, 1.0)
		colors.append(Color(model.mood_color, lerpf(MOOD_ALPHA, 0.0, t)))
	draw_polygon(points, colors)


func _draw_profile(p: RoutePreviewModel.Plot) -> void:
	var bottom: float = p.rect.end.y
	for piece in model.fill(p):
		var top: PackedVector2Array = piece["top"]
		var color: Color = piece["color"]
		var colors := PackedColorArray([color, color, color, color])
		for i in range(1, top.size()):
			var a: Vector2 = top[i - 1]
			var b: Vector2 = top[i]
			if b.x <= a.x:
				continue
			draw_primitive(PackedVector2Array([a, b, Vector2(b.x, bottom), Vector2(a.x, bottom)]), colors, PackedVector2Array())
	draw_polyline(model.outline(p), OUTLINE_COLOR, OUTLINE_WIDTH, true)


func _draw_bridges(p: RoutePreviewModel.Plot) -> void:
	for bridge in model.bridges:
		var x0: float = p.x(bridge.x)
		var x1: float = p.x(bridge.y)
		var band := Rect2(x0, p.rect.end.y - WATER_BAND_HEIGHT, x1 - x0, WATER_BAND_HEIGHT)
		draw_rect(band, WATER_COLOR)
		var mid: float = (x0 + x1) * 0.5
		if mode == RoutePreviewModel.Mode.THUMB:
			var icon_top: float = band.position.y - ICON_GAP - ICON_SIZE
			draw_texture_rect(ICON_WAVES, Rect2(mid - ICON_SIZE * 0.5, icon_top, ICON_SIZE, ICON_SIZE), false, WATER_COLOR)
			continue
		# Крупный профиль: значок и подпись «мост» над контуром в середине моста.
		var text: String = RoutePreviewModel.bridge_text()
		var w: float = ICON_SIZE + ICON_GAP + FONT_CAPTION_NUM.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE).x
		var top_y: float = p.y(model.profile.height_at((bridge.x + bridge.y) * 0.5)) - LABEL_GAP * 2.0 - ICON_SIZE
		top_y = maxf(top_y, p.rect.position.y)
		var left: float = _clamp_x(mid - w * 0.5, w)
		draw_texture_rect(ICON_WAVES, Rect2(left, top_y, ICON_SIZE, ICON_SIZE), false, WATER_COLOR)
		var baseline: float = top_y + (ICON_SIZE + FONT_CAPTION_NUM.get_ascent(CAPTION_SIZE) - FONT_CAPTION_NUM.get_descent(CAPTION_SIZE)) * 0.5
		draw_string(FONT_CAPTION_NUM, Vector2(left + ICON_SIZE + ICON_GAP, baseline), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE, UiTokens.TEXT)


func _draw_peak(p: RoutePreviewModel.Plot) -> void:
	var s: float = model.peak_s_m()
	var tip := p.point(s, model.profile.max_height_m())
	var base_y: float = tip.y - PEAK_GAP
	var half: float = PEAK_SIZE * 0.5
	var tri := PackedVector2Array([
		Vector2(tip.x - half, base_y), Vector2(tip.x, base_y - PEAK_SIZE), Vector2(tip.x + half, base_y)])
	draw_colored_polygon(tri, UiTokens.TEXT)


func _draw_height_grid(p: RoutePreviewModel.Plot) -> void:
	for label in model.visible_height_labels(p):
		var y: float = roundf(p.y(label["h_m"])) + 0.5
		draw_line(Vector2(p.rect.position.x, y), Vector2(p.rect.end.x, y), UiTokens.LINE, 1.0)


func _draw_height_labels(p: RoutePreviewModel.Plot) -> void:
	# Подписи справа налево в колонке слева от поля, по центру своих линий. Линии ближе 14 lp —
	# только максимум (`tracks.md` п. 7.2); ближе высоты строки — подписи раздвигаются поровну.
	var labels := model.visible_height_labels(p)
	if labels.is_empty():
		return
	var line_h: float = FONT_CAPTION_NUM.get_height(CAPTION_SIZE)
	var centers: Array[float] = []
	for label in labels:
		centers.append(p.y(label["h_m"]))
	if centers.size() == 2:
		var lack: float = line_h + 2.0 - (centers[1] - centers[0])
		if lack > 0.0:
			centers[0] -= lack * 0.5
			centers[1] += lack * 0.5
	var half_text: float = (FONT_CAPTION_NUM.get_ascent(CAPTION_SIZE) - FONT_CAPTION_NUM.get_descent(CAPTION_SIZE)) * 0.5
	var right: float = p.rect.position.x - LABEL_GAP
	for i in labels.size():
		var text: String = labels[i]["text"]
		var w: float = FONT_CAPTION_NUM.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE).x
		draw_string(FONT_CAPTION_NUM, Vector2(right - w, centers[i] + half_text), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE, UiTokens.TEXT2)


func _draw_km_axis(p: RoutePreviewModel.Plot) -> void:
	var baseline: float = p.rect.end.y + LABEL_GAP + FONT_CAPTION_NUM.get_ascent(CAPTION_SIZE)
	for label in model.km_labels():
		var text: String = label["text"]
		var w: float = FONT_CAPTION_NUM.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE).x
		var x: float = _clamp_x(p.x(label["s_m"]) - w * 0.5, w)
		draw_string(FONT_CAPTION_NUM, Vector2(x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE, UiTokens.TEXT2)


func _draw_start_line(p: RoutePreviewModel.Plot) -> void:
	var x: float = p.rect.position.x + 0.5
	draw_dashed_line(Vector2(x, p.rect.position.y), Vector2(x, p.rect.end.y),
		Color(UiTokens.TEXT, START_LINE_ALPHA), 1.0, START_DASH)
	draw_texture_rect(ICON_FLAG, Rect2(p.rect.position.x, p.rect.position.y, ICON_SIZE, ICON_SIZE), false, UiTokens.TEXT)


func _draw_climb_labels(p: RoutePreviewModel.Plot) -> void:
	for label in climb_label_layout(p):
		var rect: Rect2 = label["rect"]
		draw_string(FONT_CLIMB, Vector2(rect.position.x, rect.position.y + FONT_CLIMB.get_ascent(CLIMB_LABEL_SIZE)),
			str(label["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, CLIMB_LABEL_SIZE, UiTokens.TEXT)


## Подписи подъёмов на крупном профиле `p` с местом `rect` (координаты узла), без пересечений:
## из двух пересекающихся остаётся подпись более длинного подъёма (`tracks.md` п. 7.2).
func climb_label_layout(p: RoutePreviewModel.Plot) -> Array[Dictionary]:
	var placed: Array[Dictionary] = []
	if model == null or p == null:
		return placed
	var ascent: float = FONT_CLIMB.get_ascent(CLIMB_LABEL_SIZE)
	var height: float = FONT_CLIMB.get_height(CLIMB_LABEL_SIZE)
	for label in model.climb_labels():
		var text: String = label["text"]
		var start: float = label["start_m"]
		var top_h: float = maxf(model.profile.height_at(start), model.profile.height_at(start + float(label["length_m"])))
		var w: float = FONT_CLIMB.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CLIMB_LABEL_SIZE).x
		var x: float = _clamp_x(p.x(label["mid_m"]) - w * 0.5, w)
		var baseline: float = maxf(p.y(top_h) - LABEL_GAP * 2.0, p.rect.position.y + ascent)
		var item := label.duplicate()
		item["rect"] = Rect2(x, baseline - ascent, w, height)
		placed.append(item)
	return RoutePreviewModel.without_overlaps(placed)


## Левый край подписи шириной `w`, чтобы она не выходила за узел.
func _clamp_x(x: float, w: float) -> float:
	return clampf(x, 0.0, maxf(size.x - w, 0.0))


## Контур скруглённого прямоугольника по часовой стрелке (для градиента с вершинными цветами).
static func _rounded_rect(rect: Rect2, radius: float) -> PackedVector2Array:
	var r: float = clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	var out := PackedVector2Array()
	if r <= 0.0:
		return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var centers := [
		Vector2(rect.position.x + r, rect.position.y + r),
		Vector2(rect.end.x - r, rect.position.y + r),
		Vector2(rect.end.x - r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.end.y - r),
	]
	for c in 4:
		var start_angle: float = PI + float(c) * PI * 0.5
		for k in CORNER_SEGMENTS + 1:
			var a: float = start_angle + float(k) / float(CORNER_SEGMENTS) * PI * 0.5
			out.append(centers[c] + Vector2(cos(a), sin(a)) * r)
	return out
