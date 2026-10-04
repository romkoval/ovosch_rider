class_name ReliefPanel
extends Control
## Панель рельефа HUD свободной езды в левом слоте (REQ-FRD-06 крит. 3 — отрисовка;
## `docs/game/hud.md` п. 8, 4.1, 11). На месте списка интервалов, в тех же границах:
## ширина `panel_width` (`w_l` из `HudLayout.list_slot`), высота `panel_height`
## (`preferred_height(H)` = 0.40·H, не больше высоты слота).
##
## Сверху вниз на подложке `hud.plate` (радиус 14):
## 1. шапка — название трассы (17 / 650, обрезка с «…») и справа «круг 2» (13);
## 2. круг целиком (44): заливка по палитре уклона, пройденная часть круга с альфой 0.35,
##    контур 1.5 белый с альфой 0.85; позиция — точка `hud.ink` r 6 с белой серединой r 4.5
##    и вертикаль 1 от верха поля;
## 3. строка «6.4 / 20.0 км» слева и «↑ 612 м» справа (13 / 600 tnum);
## 4. «ВПЕРЕДИ 2 КМ» (11 / 650 заглавными) и профиль [s − 200; s + 2000] со своей шкалой
##    (размах ≥ 40 м), та же точка позиции; над самым крутым местом подъёма впереди — «7.1 %»
##    (13 / 700);
## 5. подвал (13 / 550 `hud.text2`): «до вершины 4.2 км · +262 м» / «подъём через 1.3 км» / пусто.
##    Не помещается в ширину (телефон: слот ≈ 220 lp) — переносится по « · » на вторую строку
##    («до вершины 3.7 км» / «+239 м»), окно «впереди» уменьшается на строку; только потом «…».
##
## Данные — `ReliefPanelModel` (на `RoutePreviewModel` той же трассы); здесь только раскладка
## и рисование. Компонент самостоятельный: экран вызывает `setup(session)` при старте и
## `sync(session)` раз в сэмпл (`FreeRideSession.second_elapsed`), перерисовка — только когда
## изменилось показываемое. Размеры в lp HUD: масштаб `s` задаёт окно (`content_scale_factor`).
## Цвета — `UiTokens` (HUD и палитра уклона), шрифты — начертания Inter темы, без `theme_override_*`.
##
## Для тестов: `debug_draw_commands()` прогоняет отрисовку в журнал без холста
## (`HudChart.Painter`): `{tag, op, filled, color, width, points, meta}` в порядке вызовов.

# --- Геометрия (`hud.md` п. 8), lp ------------------------------------------------------------
const PLATE_RADIUS: int = 14
const PAD_X: float = 14.0
const PAD_TOP: float = 10.0
const PAD_BOTTOM: float = 10.0
const TITLE_BASELINE: float = 26.0
const LAP_TOP: float = 38.0
const LAP_HEIGHT: float = 44.0
const ROW_GAP: float = 6.0
const CAPTION_GAP: float = 12.0
const AHEAD_GAP: float = 6.0
const FOOTER_GAP: float = 8.0
## Разделитель частей подвала, по которому он переносится на вторую строку.
const FOOTER_SEPARATOR: String = " · "
## Нижняя граница высоты профиля «впереди», lp (на телефоне слот низкий).
const AHEAD_MIN_HEIGHT: float = 32.0
const TEXT_GAP: float = 8.0
## Доля высоты холста под панель (`hud.md` п. 8: 0.40·H).
const HEIGHT_FRACTION: float = 0.40

# --- Профили и маркер ---------------------------------------------------------------------------
const OUTLINE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.85)
const OUTLINE_WIDTH: float = 1.5
const PASSED_ALPHA: float = 0.35
const MARKER_RADIUS: float = 6.0
const MARKER_CORE_RADIUS: float = 4.5
const MARKER_LINE_WIDTH: float = 1.0
const MARKER_LINE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.85)
const GRADE_LABEL_GAP: float = 4.0

# --- Типографика: [начертание, кегль] ---------------------------------------------------------
const FONT_TITLE: Array = ["inter_650", 17]
const FONT_LAP: Array = ["inter_500", 13]
const FONT_ROW: Array = ["inter_num_600", 13]
const FONT_CAPTION: Array = ["inter_650", 11]
const FONT_GRADE: Array = ["inter_num_700", 13]
## Подвал — 13 / 550 по `hud.md`; в теме нет 550, берётся ближайшее 500.
const FONT_FOOTER: Array = ["inter_500", 13]

# --- Теги журнала ----------------------------------------------------------------------------
const TAG_PLATE: String = "plate"
const TAG_TITLE: String = "title"
const TAG_LAP_NUMBER: String = "lap_number"
const TAG_LAP_FILL: String = "lap_fill"
const TAG_LAP_OUTLINE: String = "lap_outline"
const TAG_LAP_DISTANCE: String = "lap_distance"
const TAG_ASCENT: String = "ascent"
const TAG_AHEAD_CAPTION: String = "ahead_caption"
const TAG_AHEAD_FILL: String = "ahead_fill"
const TAG_AHEAD_OUTLINE: String = "ahead_outline"
const TAG_GRADE_LABEL: String = "grade_label"
const TAG_MARKER_LINE: String = "marker_line"
const TAG_MARKER: String = "marker"
const TAG_FOOTER: String = "footer"

## Ширина панели, lp (`w_l`).
@export var panel_width: float = 282.0:
	set(value):
		panel_width = maxf(value, 0.0)
		_update_size()
## Высота панели, lp (0.40·H, не больше высоты левого слота).
@export var panel_height: float = 288.0:
	set(value):
		panel_height = maxf(value, 0.0)
		_update_size()

var model: ReliefPanelModel = null

static var _font_cache: Dictionary = {}

var _painter := HudChart.Painter.new()
var _redraws: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_size()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED or what == NOTIFICATION_RESIZED:
		queue_redraw()


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

## Высота панели для холста высотой `canvas_height` (0.40·H), не больше `slot_height` (> 0).
static func preferred_height(canvas_height: float, slot_height: float = 0.0) -> float:
	var h: float = HEIGHT_FRACTION * canvas_height
	return minf(h, slot_height) if slot_height > 0.0 else h


## Модель трассы сессии с текущей позицией; перерисовка.
func setup(session: FreeRideSession) -> void:
	set_model(ReliefPanelModel.for_session(session))


## Позиция из сессии раз в сэмпл; перерисовка — только если показываемое изменилось.
func sync(session: FreeRideSession) -> bool:
	if model == null:
		setup(session)
		return true
	var changed: bool = model.sync(session)
	if changed:
		refresh()
	return changed


func set_model(value: ReliefPanelModel) -> void:
	model = value
	refresh()


func refresh() -> void:
	_redraws += 1
	queue_redraw()


## Сколько раз запрошена перерисовка (тесты: без изменений позиции — не перерисовывать).
func redraw_requests() -> int:
	return _redraws


# ---------------------------------------------------------------------------
# Геометрия (локальные координаты узла)
# ---------------------------------------------------------------------------

## Поле профиля круга целиком.
func lap_field_rect() -> Rect2:
	return Rect2(PAD_X, LAP_TOP, _inner_width(), LAP_HEIGHT)


## Базовая линия строки «дистанция / длина круга · набор».
func row_baseline() -> float:
	return LAP_TOP + LAP_HEIGHT + ROW_GAP + _font(FONT_ROW).get_ascent(FONT_ROW[1])


## Базовая линия подписи «ВПЕРЕДИ 2 КМ».
func caption_baseline() -> float:
	return row_baseline() + CAPTION_GAP + _font(FONT_CAPTION).get_ascent(FONT_CAPTION[1])


## Базовая линия подвала (последней строки, если он перенесён).
func footer_baseline() -> float:
	return size.y - PAD_BOTTOM - _font(FONT_FOOTER).get_descent(FONT_FOOTER[1])


## Строки подвала под ширину панели: одна, если помещается; иначе перенос по « · » (каждая
## часть — своей строкой, с «…» только если не помещается и она).
func footer_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var text: String = str(model.footer()["text"]) if model != null else ""
	if text.is_empty():
		return out
	var font: Font = _font(FONT_FOOTER)
	var inner: float = _inner_width()
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_FOOTER[1]).x <= inner:
		out.append(text)
		return out
	for part in text.split(FOOTER_SEPARATOR, false):
		out.append(_fit(part.strip_edges(), font, FONT_FOOTER[1], inner))
	return out


## Поле профиля «впереди 2 км»: от подписи до подвала (над всеми его строками).
func ahead_field_rect() -> Rect2:
	var top: float = caption_baseline() + AHEAD_GAP
	var font: Font = _font(FONT_FOOTER)
	var extra_lines: int = maxi(footer_lines().size() - 1, 0)
	var footer_top: float = footer_baseline() - font.get_ascent(FONT_FOOTER[1]) - FOOTER_GAP \
			- extra_lines * font.get_height(FONT_FOOTER[1])
	return Rect2(PAD_X, top, _inner_width(), maxf(footer_top - top, AHEAD_MIN_HEIGHT))


## Маркер гонщика на профиле круга (центр точки).
func lap_marker_position() -> Vector2:
	return model.lap_marker(lap_field_rect()) if model != null else Vector2(NAN, NAN)


## Маркер гонщика в окне «впереди 2 км».
func ahead_marker_position() -> Vector2:
	return model.ahead_marker(ahead_field_rect()) if model != null else Vector2(NAN, NAN)


# ---------------------------------------------------------------------------
# Тексты (для тестов и экрана)
# ---------------------------------------------------------------------------

func title_text() -> String:
	return model.title_text() if model != null else ""


func lap_text() -> String:
	return model.lap_text() if model != null else ""


func lap_distance_text() -> String:
	return model.lap_distance_text() if model != null else ""


func ascent_text() -> String:
	return model.ascent_text() if model != null else ""


func footer_text() -> String:
	return str(model.footer()["text"]) if model != null else ""


# ---------------------------------------------------------------------------
# Журнал (тесты)
# ---------------------------------------------------------------------------

## Прогнать отрисовку в журнал без холста (порядок вызовов, цвета, геометрия).
func debug_draw_commands() -> Array[Dictionary]:
	_painter.begin(null, true)
	_paint(_painter)
	var out: Array[Dictionary] = _painter.entries.duplicate()
	_painter.begin(null, false)
	return out


# ---------------------------------------------------------------------------
# Рисование
# ---------------------------------------------------------------------------

func _draw() -> void:
	_painter.begin(self, false)
	_paint(_painter)
	_painter.begin(null, false)


func _paint(p: HudChart.Painter) -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	p.rounded_rect(TAG_PLATE, Rect2(Vector2.ZERO, size), UiTokens.HUD_PLATE, PLATE_RADIUS)
	if model == null:
		return
	var inner: float = _inner_width()
	# 1. Шапка: название слева, номер круга справа.
	var lap_font: Font = _font(FONT_LAP)
	var lap_str: String = model.lap_text()
	var lap_w: float = lap_font.get_string_size(lap_str, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_LAP[1]).x
	var title_font: Font = _font(FONT_TITLE)
	var title: String = _fit(model.title_text(), title_font, FONT_TITLE[1], inner - lap_w - TEXT_GAP)
	p.text(TAG_TITLE, title_font, Vector2(PAD_X, TITLE_BASELINE), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			FONT_TITLE[1], UiTokens.HUD_TEXT)
	p.text(TAG_LAP_NUMBER, lap_font, Vector2(PAD_X + inner - lap_w, TITLE_BASELINE), lap_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_LAP[1], UiTokens.HUD_TEXT2)
	if not model.is_valid():
		return
	# 2. Круг целиком.
	var lap_field: Rect2 = lap_field_rect()
	var lap_plot := model.lap_plot(lap_field)
	_paint_fill(p, lap_plot, model.passed_ranges(), TAG_LAP_FILL)
	p.polyline(TAG_LAP_OUTLINE, model.preview.outline(lap_plot), OUTLINE_COLOR, OUTLINE_WIDTH)
	_paint_marker(p, lap_field, model.lap_marker(lap_field))
	# 3. Строка «дистанция / длина круга» и набор.
	var row_font: Font = _font(FONT_ROW)
	var row_y: float = row_baseline()
	p.text(TAG_LAP_DISTANCE, row_font, Vector2(PAD_X, row_y), model.lap_distance_text(), HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, FONT_ROW[1], UiTokens.HUD_TEXT)
	var ascent: String = model.ascent_text()
	var ascent_w: float = row_font.get_string_size(ascent, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_ROW[1]).x
	p.text(TAG_ASCENT, row_font, Vector2(PAD_X + inner - ascent_w, row_y), ascent, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			FONT_ROW[1], UiTokens.HUD_TEXT2)
	# 4. «Впереди 2 км».
	var cap_font: Font = _font(FONT_CAPTION)
	p.text(TAG_AHEAD_CAPTION, cap_font, Vector2(PAD_X, caption_baseline()),
			ReliefPanelModel.ahead_caption().to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_CAPTION[1],
			UiTokens.HUD_TEXT2)
	var ahead_field: Rect2 = ahead_field_rect()
	var ahead_plot := model.ahead_plot(ahead_field)
	_paint_fill(p, ahead_plot, [] as Array[Vector2], TAG_AHEAD_FILL)
	p.polyline(TAG_AHEAD_OUTLINE, model.preview.outline(ahead_plot), OUTLINE_COLOR, OUTLINE_WIDTH)
	_paint_grade_label(p, ahead_plot)
	_paint_marker(p, ahead_field, model.ahead_marker(ahead_field))
	# 5. Подвал (одна или две строки, последняя — на `footer_baseline()`).
	var lines := footer_lines()
	var foot_font: Font = _font(FONT_FOOTER)
	var line_h: float = foot_font.get_height(FONT_FOOTER[1])
	for i in lines.size():
		var baseline: float = footer_baseline() - (lines.size() - 1 - i) * line_h
		p.text(TAG_FOOTER, foot_font, Vector2(PAD_X, baseline), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				FONT_FOOTER[1], UiTokens.HUD_TEXT2)


## Заливка профиля по палитре уклона; участки `passed` (по s) — с альфой `PASSED_ALPHA`.
## Каждый участок рисуется своим отображением с той же шкалой, поэтому куски стыкуются.
func _paint_fill(p: HudChart.Painter, plot: RoutePreviewModel.Plot, passed: Array[Vector2], tag: String) -> void:
	var spans: Array[Dictionary] = []
	var cursor: float = plot.s_from
	var sorted: Array[Vector2] = passed.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	for r in sorted:
		var a: float = clampf(r.x, plot.s_from, plot.s_to)
		var b: float = clampf(r.y, plot.s_from, plot.s_to)
		if a > cursor:
			spans.append({"from": cursor, "to": a, "passed": false})
		if b > a:
			spans.append({"from": a, "to": b, "passed": true})
		cursor = maxf(cursor, b)
	if cursor < plot.s_to:
		spans.append({"from": cursor, "to": plot.s_to, "passed": false})
	var bottom: float = plot.rect.end.y
	for span in spans:
		var from: float = span["from"]
		var to: float = span["to"]
		var x0: float = plot.x(from)
		var x1: float = plot.x(to)
		if x1 - x0 < 0.25:
			continue
		var sub := RoutePreviewModel.Plot.new(Rect2(x0, plot.rect.position.y, x1 - x0, plot.rect.size.y),
				from, to, plot.h_bottom, plot.h_top)
		var alpha: float = PASSED_ALPHA if bool(span["passed"]) else 1.0
		for piece in model.preview.fill(sub):
			var color: Color = piece["color"]
			p.area(tag, piece["top"], bottom, Color(color, alpha), {"passed": bool(span["passed"])})


## Позиция: вертикаль 1 lp от верха поля до точки, точка `hud.ink` r 6 с белой серединой r 4.5.
func _paint_marker(p: HudChart.Painter, field: Rect2, at: Vector2) -> void:
	p.line(TAG_MARKER_LINE, Vector2(at.x, field.position.y), at, MARKER_LINE_COLOR, MARKER_LINE_WIDTH)
	p.circle(TAG_MARKER, at, MARKER_RADIUS, UiTokens.HUD_INK)
	p.circle(TAG_MARKER, at, MARKER_CORE_RADIUS, UiTokens.HUD_TEXT)


## Подпись уклона над самым крутым местом подъёма впереди (не выходит за поле по X и за подпись
## «ВПЕРЕДИ 2 КМ» по Y).
func _paint_grade_label(p: HudChart.Painter, plot: RoutePreviewModel.Plot) -> void:
	var steep: Dictionary = model.steepest_ahead()
	if steep.is_empty():
		return
	var font: Font = _font(FONT_GRADE)
	var text: String = steep["text"]
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_GRADE[1]).x
	var s: float = steep["s_m"]
	var at: Vector2 = plot.point(s, model.height_at(s))
	var x: float = clampf(at.x - w * 0.5, plot.rect.position.x, plot.rect.end.x - w)
	var baseline: float = maxf(at.y - GRADE_LABEL_GAP, plot.rect.position.y + font.get_ascent(FONT_GRADE[1]))
	p.text(TAG_GRADE_LABEL, font, Vector2(x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_GRADE[1],
			UiTokens.HUD_TEXT)


func _inner_width() -> float:
	return maxf(size.x - PAD_X * 2.0, 0.0)


func _get_minimum_size() -> Vector2:
	return Vector2(panel_width, panel_height)


func _update_size() -> void:
	update_minimum_size()
	size = Vector2(panel_width, panel_height)
	queue_redraw()


## Текст, обрезанный с «…» до ширины `max_w`.
static func _fit(text: String, font: Font, font_size: int, max_w: float) -> String:
	if max_w <= 0.0 or font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
		return text
	var cut: String = text
	while cut.length() > 0:
		cut = cut.substr(0, cut.length() - 1)
		var candidate: String = cut.strip_edges(false, true) + "…"
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
			return candidate
	return ""


## Начертание Inter темы по спецификации `[имя, кегль]`.
static func _font(spec: Array) -> Font:
	var name: String = spec[0]
	if not _font_cache.has(name):
		_font_cache[name] = load(AppThemeBuilder.FONT_DIR + name + ".tres")
	return _font_cache[name]
