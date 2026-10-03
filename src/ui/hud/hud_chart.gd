class_name HudChart
extends Control
## Нижний график HUD: план по зонам, линии мощности и пульса, курсор
## (REQ-HUD-10 крит. 6, 7, REQ-HUD-11 крит. 6, 7, REQ-HUD-12 крит. 3–5; `docs/game/hud.md` п. 7, 11).
## Тот же рисовальщик — превью плана в меню (`PlanPreview`, REQ-UIX-03 крит. 4).
##
## Данные — модели T-065: `PlanChartModel` (куски сегментов, оси, курсор, `revision()`),
## `EffortSeries` (отрезки мощности и пульса, шкала пульса, стиль серий), `TimeAxis`.
## Цвета — `UiTokens` (HUD) и `ZonePalette` (зоны), шрифты — FontVariation темы (Inter).
## Размеры в lp: масштаб HUD `s` задаёт `Window.content_scale_factor` (`hud.md` п. 3).
##
## Слои (дочерние внутренние `Control`, рисуются по порядку):
## 1. Слой плана — подложка → пунктир FTP → сегменты плана (кроме текущего шага) → подписи
##    FTP и времени. Кэш: перерисовывается только при смене `revision()` модели (множитель,
##    FTP, статусы шагов), размера или флагов, а не на каждом сэмпле.
## 2. Слой факта — текущий шаг (разрезан курсором) → линия пульса → линия мощности → курсор →
##    шкала пульса и легенда. Перерисовывается раз в сэмпл (`refresh()`/`sync()`), не каждый кадр.
## Итоговый порядок совпадает с HUD-11.6: подложка → FTP → сегменты → пульс → мощность → курсор.
##
## Режимы: `Mode.PLAN` — тренировка по плану (весь план целиком по X); `Mode.WINDOW` —
## «история усилия» свободной езды (REQ-FRD-06 крит. 4, `hud.md` п. 8; окно
## `EffortSeries.sliding_window`): первые 30 мин шкала 0…30 мин и линия растёт слева направо,
## дальше окно скользит, «сейчас» у правого края с подписью; мощность — площадь, раскрашенная
## по зоне каждой точки (альфа `AREA_ALPHA`), с белой линией сверху; пульс — красная линия без
## заливки; FTP пунктиром; шкала мощности — `EffortSeries.power_y_max()`. Порядок слоя факта
## в окне: площадь мощности → пульс → линия мощности (плана и курсора нет).
##
## Для тестов: `debug_draw_commands()` прогоняет отрисовку обоих слоёв в журнал без холста —
## список `{layer, tag, op, filled, color, width, points, meta}` в порядке вызовов.

enum Mode { PLAN, WINDOW }
enum Background { PLATE, INSET, NONE }

# --- Поле графика (`hud.md` п. 7), lp -------------------------------------------------
const HUD_INSET_LEFT: float = 44.0
const HUD_INSET_RIGHT: float = 44.0
const HUD_INSET_TOP: float = 10.0
const HUD_INSET_BOTTOM: float = 22.0

# --- Сегменты плана ------------------------------------------------------------------
const SEGMENT_GAP: float = 1.0
const SEGMENT_RADIUS: float = 5.0
const FREE_RADIUS: float = 4.0
const UPCOMING_ALPHA: float = 1.0
const DONE_ALPHA: float = 0.30
const FREE_ALPHA: float = 0.55
const DONE_EDGE_WIDTH: float = 2.0
const CURRENT_EDGE_WIDTH: float = 2.0
const CURRENT_EDGE_ALPHA: float = 0.95
const HATCH_STEP: float = 8.0
const HATCH_WIDTH: float = 1.0
const SKIPPED_HATCH_ALPHA: float = 0.6
## Точек на четверть окружности скругления.
const ARC_STEPS: int = 4
## Минимальная видимая высота сегмента над низом поля, px.
const MIN_SEGMENT_HEIGHT: float = 1.0

# --- FTP, курсор, подписи --------------------------------------------------------------
const FTP_DASH: float = 6.0
const FTP_DASH_STEP: float = 10.0
const FTP_LINE_WIDTH: float = 1.0
const FTP_LINE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.35)
const FTP_CAPTION: String = "FTP"
const CURSOR_WIDTH: float = 2.0
const CURSOR_MARK_SIZE: Vector2 = Vector2(12.0, 8.0)
const LABEL_GAP: float = 6.0
const CAPTION_FONT_SIZE: int = 10
const SCALE_FONT_SIZE: int = 11
const LEGEND_STROKE: float = 16.0
const LEGEND_GAP: float = 4.0
const LEGEND_ITEM_GAP: float = 12.0
## Площадь мощности окна: альфа заливки цветом зоны точки (`hud.md` п. 8).
const AREA_ALPHA: float = 0.55
## Фон превью: `inset`, радиус 12 (`ui.md` п. 5, PlanThumb).
const INSET_RADIUS: float = 12.0

# --- Теги журнала отрисовки -------------------------------------------------------------
const TAG_BACKGROUND: String = "background"
const TAG_FTP: String = "ftp"
const TAG_SEGMENT: String = "segment"
const TAG_SEGMENT_EDGE: String = "segment_edge"
const TAG_HATCH: String = "hatch"
const TAG_CURRENT_EDGE: String = "current_edge"
const TAG_HR_OUTLINE: String = "hr_outline"
const TAG_HR_LINE: String = "hr_line"
const TAG_POWER_OUTLINE: String = "power_outline"
const TAG_POWER_LINE: String = "power_line"
const TAG_POWER_AREA: String = "power_area"
const TAG_CURSOR: String = "cursor"
const TAG_FTP_LABEL: String = "ftp_label"
const TAG_TIME_LABEL: String = "time_label"
const TAG_HR_LABEL: String = "hr_label"
const TAG_LEGEND: String = "legend"

const LAYER_PLAN: String = "plan"
const LAYER_FACT: String = "fact"

const _FONT_DIR: String = "res://src/ui/theme/fonts/"

## Фон: `PLATE` — подложка HUD во всю ширину, `INSET` — скруглённая панель превью.
@export var background: Background = Background.PLATE:
	set(value):
		background = value
		_invalidate()
## Высота градиента над подложкой (прозрачный → `hud.plate`), lp; поле графика ниже него.
@export var fade_height: float = 0.0:
	set(value):
		fade_height = maxf(value, 0.0)
		_invalidate()
@export var inset_left: float = HUD_INSET_LEFT:
	set(value):
		inset_left = value
		_invalidate()
@export var inset_right: float = HUD_INSET_RIGHT:
	set(value):
		inset_right = value
		_invalidate()
@export var inset_top: float = HUD_INSET_TOP:
	set(value):
		inset_top = value
		_invalidate()
@export var inset_bottom: float = HUD_INSET_BOTTOM:
	set(value):
		inset_bottom = value
		_invalidate()
@export var show_ftp_line: bool = true:
	set(value):
		show_ftp_line = value
		_invalidate()
@export var show_ftp_label: bool = true:
	set(value):
		show_ftp_label = value
		_invalidate()
@export var show_time_axis: bool = true:
	set(value):
		show_time_axis = value
		_invalidate()
## Линии факта мощности и пульса.
@export var show_fact: bool = true:
	set(value):
		show_fact = value
		_invalidate()
@export var show_cursor: bool = true:
	set(value):
		show_cursor = value
		_invalidate()
## Подписи шкалы пульса справа (100, 150) — только при данных пульса.
@export var show_hr_scale: bool = true:
	set(value):
		show_hr_scale = value
		_invalidate()
## Ключи перевода легенды «мощность»/«пульс» над правым верхним углом поля;
## пустой ключ — без своей половины легенды (ключи заводит экран, T-078/T-079).
@export var legend_power_key: String = "":
	set(value):
		legend_power_key = value
		_invalidate()
@export var legend_hr_key: String = "":
	set(value):
		legend_hr_key = value
		_invalidate()
## Ключ перевода подписи «сейчас» у правого края скользящего окна (пусто — без подписи).
@export var now_label_key: String = "ui.free_ride.chart.now":
	set(value):
		now_label_key = value
		_invalidate()

var mode: Mode = Mode.PLAN

var _model: PlanChartModel = null
var _series: EffortSeries = null
var _window_ftp_w: int = 0
## Зоны мощности для заливки площади окна (по умолчанию — Коган от FTP окна).
var _window_zones: PowerZones = null
## Куски плана текущего сэмпла (`PlanChartModel.pieces()`), один вызов на `refresh()`.
var _pieces: Array[Dictionary] = []
## Ключ кэша слоя плана: версия модели, размер, потолок шкалы окна.
var _plan_revision: int = -1
var _plan_size: Vector2 = Vector2(-1.0, -1.0)
var _plan_y_max: float = -1.0
var _plan_redraws: int = 0
var _fact_redraws: int = 0

var _plan_layer: _Layer
var _fact_layer: _Layer
var _plan_painter := Painter.new()
var _fact_painter := Painter.new()

static var _fonts: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plan_layer = _make_layer(_paint_plan_layer)
	_fact_layer = _make_layer(_paint_fact_layer)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED, NOTIFICATION_TRANSLATION_CHANGED:
			_invalidate()


# ---------------------------------------------------------------------------
# Данные
# ---------------------------------------------------------------------------

## Режим плана: модель плана и (необязательно) серии факта. Перерисовывает оба слоя.
func set_plan(model: PlanChartModel, series: EffortSeries = null) -> void:
	mode = Mode.PLAN
	_model = model
	_series = series
	_invalidate()


## Серии факта (мощность, пульс) для текущей модели.
func set_series(series: EffortSeries) -> void:
	_series = series
	refresh()


## Режим «история усилия» свободной езды (REQ-FRD-06 крит. 4). `series` —
## `EffortSeries.sliding_window(ftp, max_hr)`, `ftp_w` — для пунктира FTP, `zones` — зоны
## профиля для заливки площади (null — зоны Когана от `ftp_w`).
func set_window(series: EffortSeries, ftp_w: int, zones: PowerZones = null) -> void:
	mode = Mode.WINDOW
	_model = null
	_series = series
	_window_ftp_w = ftp_w
	_window_zones = zones if zones != null else PowerZones.coggan(ftp_w)
	_invalidate()


## Зоны мощности заливки окна.
func window_zones() -> PowerZones:
	return _window_zones


func plan_model() -> PlanChartModel:
	return _model


func effort_series() -> EffortSeries:
	return _series


## Подтянуть сессию раз в сэмпл: множитель, курсор и пропуски — в модель, новые сэмплы — в серии
## (со сдвигом позиции в плане после пропуска, REQ-HUD-10.5), затем `refresh()`.
func sync(session: WorkoutSession) -> void:
	if _model != null:
		_model.sync(session)
	if _series != null:
		if _model != null:
			_series.sync_from_plan(session.samples, _model)
		else:
			_series.sync_from_stream(session.samples)
	refresh()


## Свободная езда: новые сэмплы потока сессии — в серии окна (`sync_from_stream`), затем
## `refresh()`. Вызывать раз в сэмпл (`FreeRideSession.second_elapsed`); на паузе сэмплов
## нет — линия стоит.
func sync_free_ride(session: FreeRideSession) -> void:
	if _series != null:
		_series.sync_from_stream(session.samples)
	refresh()


## Перерисовка после изменения моделей (раз в сэмпл). Слой плана — только если сменились
## `revision()` модели, размер или потолок шкалы окна; слой факта — всегда.
func refresh() -> void:
	_pieces = _model.pieces() if _model != null else ([] as Array[Dictionary])
	var y_max: float = _series.power_y_max() if mode == Mode.WINDOW and _series != null else 0.0
	var revision: int = _model.revision() if _model != null else 0
	if revision != _plan_revision or size != _plan_size or not is_equal_approx(y_max, _plan_y_max):
		_plan_revision = revision
		_plan_size = size
		_plan_y_max = y_max
		_plan_redraws += 1
		_plan_layer.queue_redraw()
	_fact_redraws += 1
	_fact_layer.queue_redraw()


## Сколько раз запрошена перерисовка слоя плана (кэш) и слоя факта — для тестов и профилирования.
func plan_redraw_requests() -> int:
	return _plan_redraws


func fact_redraw_requests() -> int:
	return _fact_redraws


# ---------------------------------------------------------------------------
# Геометрия (локальные координаты узла)
# ---------------------------------------------------------------------------

## Верх подложки (под градиентом).
func plate_top() -> float:
	return fade_height


## Поле графика: подложка минус поля шкал.
func field_rect() -> Rect2:
	var top: float = plate_top() + inset_top
	var w: float = maxf(size.x - inset_left - inset_right, 0.0)
	var h: float = maxf(size.y - top - inset_bottom, 0.0)
	return Rect2(inset_left, top, w, h)


## X момента `t_sec` (позиция в плане или время окна).
func x_at(t_sec: float) -> float:
	var f: Rect2 = field_rect()
	if mode == Mode.WINDOW:
		return f.position.x + (_series.window_x_of(t_sec, f.size.x) if _series != null else 0.0)
	return f.position.x + (_model.x_of(t_sec, f.size.x) if _model != null else 0.0)


## Y мощности по шкале 0…`power_y_max()`.
func y_power(watts: float) -> float:
	var f: Rect2 = field_rect()
	var top: float = power_y_max()
	var frac: float = clampf(watts / top, 0.0, 1.0) if top > 0.0 else 0.0
	return f.position.y + f.size.y * (1.0 - frac)


## Y пульса по своей шкале пульса (`EffortSeries.hr_fraction`).
func y_hr(bpm: float) -> float:
	var f: Rect2 = field_rect()
	var frac: float = _series.hr_fraction(bpm) if _series != null else 0.0
	return f.position.y + f.size.y * (1.0 - frac)


## Потолок шкалы мощности: модель плана или окно серии.
func power_y_max() -> float:
	if mode == Mode.WINDOW:
		return _series.power_y_max() if _series != null else 1.0
	return _model.y_max() if _model != null else 1.0


## FTP для пунктира.
func ftp_w() -> int:
	if mode == Mode.WINDOW:
		return _window_ftp_w
	return _model.ftp_w if _model != null else 0


## Курсор «сейчас», X; NAN — курсора нет (режим окна или нет модели).
func cursor_x() -> float:
	if mode != Mode.PLAN or _model == null:
		return NAN
	var f: Rect2 = field_rect()
	return f.position.x + _model.cursor_fraction() * f.size.x


# ---------------------------------------------------------------------------
# Журнал (тесты)
# ---------------------------------------------------------------------------

## Прогнать отрисовку обоих слоёв в журнал без холста (порядок вызовов, цвета, геометрия).
## Перед вызовом модели должны быть актуальны (`refresh()`/`sync()` либо `set_plan`).
func debug_draw_commands() -> Array[Dictionary]:
	if _model != null:
		_pieces = _model.pieces()
	var out: Array[Dictionary] = []
	for pair: Array in [[_plan_painter, LAYER_PLAN, _paint_plan], [_fact_painter, LAYER_FACT, _paint_fact]]:
		var painter: Painter = pair[0]
		var canvas: CanvasItem = painter.canvas
		painter.begin(null, true)
		(pair[2] as Callable).call(painter)
		for e in painter.entries:
			e["layer"] = pair[1]
			out.append(e)
		painter.begin(canvas, false)
	return out


# ---------------------------------------------------------------------------
# Слои
# ---------------------------------------------------------------------------

func _invalidate() -> void:
	if _plan_layer == null:
		return
	_plan_revision = -1
	refresh()


func _make_layer(paint: Callable) -> _Layer:
	var layer := _Layer.new()
	layer.paint = paint
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(layer, false, Node.INTERNAL_MODE_FRONT)
	return layer


func _paint_plan_layer(canvas: CanvasItem) -> void:
	_plan_painter.begin(canvas, false)
	_paint_plan(_plan_painter)


func _paint_fact_layer(canvas: CanvasItem) -> void:
	_fact_painter.begin(canvas, false)
	_paint_fact(_fact_painter)


## Слой плана: подложка → пунктир FTP → сегменты (кроме текущего шага) → подписи FTP и времени.
func _paint_plan(p: Painter) -> void:
	var f: Rect2 = field_rect()
	_paint_background(p)
	if f.size.x <= 0.0 or f.size.y <= 0.0:
		return
	if show_ftp_line:
		_paint_ftp_line(p, f)
	if mode == Mode.PLAN:
		_paint_pieces(p, f, false)
	if show_ftp_label:
		_paint_ftp_label(p, f)
	if show_time_axis:
		_paint_time_axis(p, f)


## Слой факта: текущий шаг (план) или площадь мощности (окно) → пульс → мощность → курсор →
## шкала пульса и легенда.
func _paint_fact(p: Painter) -> void:
	var f: Rect2 = field_rect()
	if f.size.x <= 0.0 or f.size.y <= 0.0:
		return
	if mode == Mode.PLAN:
		_paint_pieces(p, f, true)
	if show_fact and _series != null and mode == Mode.WINDOW:
		_paint_power_area(p, f)
	if show_fact and _series != null:
		_paint_series(p, f, EffortSeries.SERIES_HR, TAG_HR_OUTLINE, TAG_HR_LINE)
		_paint_series(p, f, EffortSeries.SERIES_POWER, TAG_POWER_OUTLINE, TAG_POWER_LINE)
	if show_cursor and mode == Mode.PLAN and _model != null:
		_paint_cursor(p, f)
	if show_fact and show_hr_scale and _series != null:
		_paint_hr_scale(p, f)
	_paint_legend(p, f)


# ---------------------------------------------------------------------------
# Фон и FTP
# ---------------------------------------------------------------------------

func _paint_background(p: Painter) -> void:
	match background:
		Background.PLATE:
			var top: float = plate_top()
			if fade_height > 0.0:
				var clear := Color(UiTokens.HUD_PLATE, 0.0)
				p.gradient_rect(TAG_BACKGROUND, Rect2(0.0, 0.0, size.x, top), clear, UiTokens.HUD_PLATE)
			p.rect(TAG_BACKGROUND, Rect2(0.0, top, size.x, maxf(size.y - top, 0.0)), UiTokens.HUD_PLATE)
		Background.INSET:
			p.rounded_rect(TAG_BACKGROUND, Rect2(Vector2.ZERO, size), UiTokens.INSET, INSET_RADIUS)
		_:
			pass


func _ftp_y(f: Rect2) -> float:
	var top: float = power_y_max()
	if ftp_w() <= 0 or top <= 0.0 or float(ftp_w()) > top:
		return NAN
	return f.position.y + f.size.y * (1.0 - float(ftp_w()) / top)


## Пунктир FTP: штрих 6, шаг 10, белый с альфой 0.35 (`hud.md` п. 7).
func _paint_ftp_line(p: Painter, f: Rect2) -> void:
	var y: float = _ftp_y(f)
	if is_nan(y):
		return
	var pts := PackedVector2Array()
	var x: float = f.position.x
	var x_end: float = f.end.x
	while x < x_end:
		pts.append(Vector2(x, y))
		pts.append(Vector2(minf(x + FTP_DASH, x_end), y))
		x += FTP_DASH_STEP
	p.multiline(TAG_FTP, pts, FTP_LINE_COLOR, FTP_LINE_WIDTH)


## Слева от поля: «FTP» (10 / 650 `hud.text2`) над значением (11 / 600 tnum `hud.text2`).
func _paint_ftp_label(p: Painter, f: Rect2) -> void:
	var y: float = _ftp_y(f)
	if is_nan(y) or f.position.x < 20.0:
		return
	var cap_font: Font = _font("inter_650", 0)
	var num_font: Font = _font("inter_num_600", 0)
	var cap_h: float = cap_font.get_ascent(CAPTION_FONT_SIZE)
	var num_h: float = num_font.get_ascent(SCALE_FONT_SIZE)
	# Подпись над пунктиром, значение под ним; блок не выходит за подложку.
	var cap_base: float = clampf(y - 2.0, plate_top() + cap_h, size.y - num_h - 3.0)
	var num_base: float = cap_base + 3.0 + num_h
	var w: float = f.position.x - LABEL_GAP
	p.text(TAG_FTP_LABEL, cap_font, Vector2(0.0, cap_base), FTP_CAPTION, HORIZONTAL_ALIGNMENT_RIGHT, w,
			CAPTION_FONT_SIZE, UiTokens.HUD_TEXT2)
	p.text(TAG_FTP_LABEL, num_font, Vector2(0.0, num_base), str(ftp_w()), HORIZONTAL_ALIGNMENT_RIGHT, w,
			SCALE_FONT_SIZE, UiTokens.HUD_TEXT2)


## Подписи времени (HUD-10.4) по центру под делением: 11 / 550 tnum `hud.text2`, без рисок.
## У правого края скользящего окна — «сейчас» (`now_label_key`), выровнена так, чтобы не
## выходить за подложку.
func _paint_time_axis(p: Painter, f: Rect2) -> void:
	var labels: Array[Dictionary] = []
	if mode == Mode.WINDOW:
		if _series != null:
			labels = _series.window_time_labels()
	elif _model != null:
		labels = _model.time_labels()
	if labels.is_empty():
		return
	var font: Font = _font("inter_num_600", 550)
	var base: float = f.end.y + 3.0 + font.get_ascent(SCALE_FONT_SIZE)
	var box: float = 64.0
	for label in labels:
		var text: String = str(label["text"])
		var x: float = f.position.x + float(label["fraction"]) * f.size.x
		if bool(label.get("is_now", false)) and not now_label_key.is_empty():
			text = tr(now_label_key)
			var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, SCALE_FONT_SIZE).x
			var left: float = minf(x - w * 0.5, size.x - w - 2.0)
			p.text(TAG_TIME_LABEL, font, Vector2(left, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
					SCALE_FONT_SIZE, UiTokens.HUD_TEXT2)
			continue
		if text.is_empty():
			continue
		p.text(TAG_TIME_LABEL, font, Vector2(x - box * 0.5, base), text, HORIZONTAL_ALIGNMENT_CENTER, box,
				SCALE_FONT_SIZE, UiTokens.HUD_TEXT2)


# ---------------------------------------------------------------------------
# Сегменты плана
# ---------------------------------------------------------------------------

## Куски плана: `current_only = false` — всё, кроме текущего шага (кэш), `true` — только
## текущий шаг (слева от курсора — как пройдено, справа — как предстоит) и белая линия по верху.
func _paint_pieces(p: Painter, f: Rect2, current_only: bool) -> void:
	if _model == null or _pieces.is_empty():
		return
	var current_edge := PackedVector2Array()
	var n: int = _pieces.size()
	for i in n:
		var piece: Dictionary = _pieces[i]
		if bool(piece["current"]) != current_only:
			continue
		var step: int = int(piece["step_index"])
		var starts: bool = i == 0 or int(_pieces[i - 1]["step_index"]) != step
		var ends: bool = i == n - 1 or int(_pieces[i + 1]["step_index"]) != step
		var top_line: PackedVector2Array = _paint_piece(p, f, piece, starts, ends)
		if current_only:
			current_edge.append_array(top_line)
	if current_edge.size() >= 2:
		p.polyline(TAG_CURRENT_EDGE, current_edge, Color(UiTokens.HUD_TEXT, CURRENT_EDGE_ALPHA),
				CURRENT_EDGE_WIDTH)


## Один кусок: заливка, линия по верху для пройденного, штриховка «свободно»/«пропущено».
## Возвращает верхний контур (для белой линии текущего шага).
func _paint_piece(p: Painter, f: Rect2, piece: Dictionary, starts: bool, ends: bool) -> PackedVector2Array:
	var total: float = float(_model.total_sec())
	var start: float = float(piece["start_sec"])
	var end: float = float(piece["end_sec"])
	var xa: float = f.position.x + _model.x_of(start, f.size.x)
	var xb: float = f.position.x + _model.x_of(end, f.size.x)
	# Зазор 1 lp — между шагами (не между кусками одной рампы и не по краям плана).
	if xb - xa > 3.0 * SEGMENT_GAP:
		if starts and start > 0.0:
			xa += SEGMENT_GAP * 0.5
		if ends and end < total:
			xb -= SEGMENT_GAP * 0.5
	if xb - xa < 0.25:
		return PackedVector2Array()
	var base: float = f.end.y
	var ya: float = minf(f.position.y + f.size.y * (1.0 - float(piece["top_start"])), base - MIN_SEGMENT_HEIGHT)
	var yb: float = minf(f.position.y + f.size.y * (1.0 - float(piece["top_end"])), base - MIN_SEGMENT_HEIGHT)
	var free: bool = bool(piece["free"])
	var ramp: bool = bool(piece["ramp"])
	var radius: float = 0.0
	if not ramp:
		var r: float = FREE_RADIUS if free else SEGMENT_RADIUS
		var corners: int = int(starts) + int(ends)
		var limit: float = (xb - xa) / float(maxi(corners, 1))
		radius = minf(minf(r, limit), base - ya - 0.5)
	var top: PackedVector2Array = _top_contour(xa, ya, xb, yb, radius if starts else 0.0, radius if ends else 0.0)
	var poly := PackedVector2Array([Vector2(xa, base)])
	poly.append_array(top)
	poly.append(Vector2(xb, base))
	var status: String = str(piece["status"])
	var token: String = str(piece["color_token"])
	var color: Color = UiTokens.HUD_FREE if free else ZonePalette.color(token)
	var alpha: float = UPCOMING_ALPHA
	if status != PlanChartModel.STATUS_UPCOMING:
		alpha = DONE_ALPHA
	elif free:
		alpha = FREE_ALPHA
	var meta: Dictionary = {
		"step_index": int(piece["step_index"]), "status": status, "token": token, "free": free,
		"ramp": ramp, "current": bool(piece["current"]), "x0": xa, "x1": xb, "y0": ya, "y1": yb,
		"base": base, "radius": radius,
	}
	p.polygon(TAG_SEGMENT, poly, Color(color, alpha), meta)
	if free:
		_paint_hatch(p, f, poly, UiTokens.HUD_FREE_HATCH, meta)
	if status == PlanChartModel.STATUS_SKIPPED:
		_paint_hatch(p, f, poly, Color(UiTokens.HUD_INK, SKIPPED_HATCH_ALPHA), meta)
	# «Призрак» пройденного: линия 2 lp цвета зоны по верхнему краю (у текущего — белая, общая).
	if not bool(piece["current"]) and status != PlanChartModel.STATUS_UPCOMING:
		p.polyline(TAG_SEGMENT_EDGE, _shifted(top, DONE_EDGE_WIDTH * 0.5), Color(color, 1.0), DONE_EDGE_WIDTH, meta)
	return _shifted(top, CURRENT_EDGE_WIDTH * 0.5)


## Верхний контур слева направо: скругление радиусом `r_left`/`r_right` (0 — острый угол).
static func _top_contour(xa: float, ya: float, xb: float, yb: float, r_left: float, r_right: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if r_left >= 0.5:
		_append_arc(out, Vector2(xa + r_left, ya + r_left), r_left, PI, PI * 1.5)
	else:
		out.append(Vector2(xa, ya))
	if r_right >= 0.5:
		_append_arc(out, Vector2(xb - r_right, yb + r_right), r_right, PI * 1.5, TAU)
	else:
		out.append(Vector2(xb, yb))
	return out


static func _append_arc(out: PackedVector2Array, center: Vector2, r: float, from: float, to: float) -> void:
	for k in ARC_STEPS + 1:
		var a: float = lerpf(from, to, float(k) / float(ARC_STEPS))
		var pt: Vector2 = center + Vector2(cos(a), sin(a)) * r
		if out.is_empty() or out[out.size() - 1].distance_squared_to(pt) > 1e-6:
			out.append(pt)


static func _shifted(points: PackedVector2Array, dy: float) -> PackedVector2Array:
	var out := PackedVector2Array(points)
	for i in out.size():
		out[i].y += dy
	return out


## Штриховка 45° через 8 lp внутри контура куска; сетка общая для всего поля, чтобы
## штрихи соседних кусков продолжали друг друга.
func _paint_hatch(p: Painter, f: Rect2, poly: PackedVector2Array, color: Color, meta: Dictionary) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for pt in poly:
		lo = lo.min(pt)
		hi = hi.max(pt)
	var origin: float = f.position.x + f.position.y
	var c: float = origin + ceilf((lo.x + lo.y - origin) / HATCH_STEP) * HATCH_STEP
	var lines := PackedVector2Array()
	while c <= hi.x + hi.y:
		# Прямая x + y = c («/»), продлённая за габарит куска.
		var seg := PackedVector2Array([Vector2(c - hi.y - 1.0, hi.y + 1.0), Vector2(c - lo.y + 1.0, lo.y - 1.0)])
		for part: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(seg, poly):
			for k in part.size() - 1:
				lines.append(part[k])
				lines.append(part[k + 1])
		c += HATCH_STEP
	if lines.size() >= 2:
		p.multiline(TAG_HATCH, lines, color, HATCH_WIDTH, meta)


# ---------------------------------------------------------------------------
# Линии факта, курсор, шкала пульса, легенда
# ---------------------------------------------------------------------------

## Линия серии: обводка `hud.ink` 0.9 толщиной 5 lp, затем линия 2 lp (HUD-11.7, HUD-12.4).
## Только полилинии, без заливки (у пульса стиль «линия», HUD-12.3). Мощность в режиме плана
## и пульс — левее курсора; площадь под мощностью окна (`STYLE_AREA_LINE`) — `_paint_power_area`.
func _paint_series(p: Painter, f: Rect2, series: String, outline_tag: String, line_tag: String) -> void:
	var style: Dictionary = _series.style(series)
	var t_from: float = 0.0
	var t_to: float = 0.0
	if mode == Mode.WINDOW:
		var r: Vector2 = _series.visible_range()
		t_from = r.x
		t_to = r.y
	elif _model != null:
		t_to = _model.cursor_sec()
	if t_to <= t_from:
		return
	var width_px: int = maxi(int(f.size.x), 1)
	var runs: Array[Dictionary]
	if series == EffortSeries.SERIES_HR:
		runs = _series.hr_runs(t_from, t_to, width_px)
	else:
		runs = _series.power_runs(t_from, t_to, width_px, power_y_max())
	if runs.is_empty():
		return
	var color: Color = _token_color(str(style["color_token"]))
	var outline := Color(_token_color(str(style["outline_token"])), float(style["outline_alpha"]))
	var line_w: float = float(style["width_lp"])
	var outline_w: float = float(style["outline_width_lp"])
	var is_hr: bool = series == EffortSeries.SERIES_HR
	var top: float = power_y_max()
	var lines: Array[PackedVector2Array] = []
	for run in runs:
		var src: PackedVector2Array = run["points"]
		var pts := PackedVector2Array()
		pts.resize(src.size())
		for i in src.size():
			var t: float = src[i].x
			var x: float = _series.window_x_of(t, f.size.x) if mode == Mode.WINDOW else _model.x_of(t, f.size.x)
			var frac: float = _series.hr_fraction(src[i].y) if is_hr else clampf(src[i].y / top, 0.0, 1.0)
			pts[i] = Vector2(f.position.x + x, f.position.y + f.size.y * (1.0 - frac))
		if pts.size() == 1:
			# Одиночная точка между разрывами — короткий штрих, чтобы её было видно.
			pts.append(pts[0] + Vector2(1.0, 0.0))
			pts[0] -= Vector2(1.0, 0.0)
		lines.append(pts)
	var meta: Dictionary = {"series": series, "style": str(style["style"]), "fill": bool(style["fill"])}
	for pts in lines:
		p.polyline(outline_tag, pts, outline, outline_w, meta)
	for pts in lines:
		p.polyline(line_tag, pts, color, line_w, meta)


## Площадь под линией мощности окна (стиль `STYLE_AREA_LINE`, `hud.md` п. 8): те же отрезки,
## что у линии (разрывы, прореживание HUD-11), до низа поля; каждая точка красит свою ячейку
## (от середины до предыдущей точки до середины до следующей) цветом своей зоны мощности
## с альфой `AREA_ALPHA`; соседние ячейки одной зоны — одна площадь.
func _paint_power_area(p: Painter, f: Rect2) -> void:
	if not bool(_series.style(EffortSeries.SERIES_POWER)["fill"]):
		return
	var r: Vector2 = _series.visible_range()
	if r.y <= r.x:
		return
	var top: float = power_y_max()
	var runs: Array[Dictionary] = _series.power_runs(r.x, r.y, maxi(int(f.size.x), 1), top)
	var zones: PowerZones = _window_zones if _window_zones != null else PowerZones.coggan(_window_ftp_w)
	var base: float = f.end.y
	for run in runs:
		var src: PackedVector2Array = run["points"]
		var pts := PackedVector2Array()
		var tokens: Array[String] = []
		for pt in src:
			var frac: float = clampf(pt.y / top, 0.0, 1.0) if top > 0.0 else 0.0
			pts.append(Vector2(f.position.x + _series.window_x_of(pt.x, f.size.x), f.position.y + f.size.y * (1.0 - frac)))
			tokens.append(ZonePalette.power_token(zones.zone_of(roundi(pt.y))))
		if pts.size() == 1:
			# Одиночная точка между разрывами — полоска шириной 2 lp, как штрих линии.
			pts.append(pts[0] + Vector2(1.0, 0.0))
			pts[0] -= Vector2(1.0, 0.0)
			tokens.append(tokens[0])
		var group := PackedVector2Array([pts[0]])
		var token: String = tokens[0]
		for i in range(1, pts.size()):
			if tokens[i] != token:
				var mid: Vector2 = (pts[i - 1] + pts[i]) * 0.5
				group.append(mid)
				p.area(TAG_POWER_AREA, group, base, Color(ZonePalette.color(token), AREA_ALPHA), {"token": token})
				group = PackedVector2Array([mid])
				token = tokens[i]
			group.append(pts[i])
		p.area(TAG_POWER_AREA, group, base, Color(ZonePalette.color(token), AREA_ALPHA), {"token": token})


## Курсор: вертикаль 2 lp `hud.text` на всю высоту поля и треугольник 12 × 8 вершиной вниз над полем.
func _paint_cursor(p: Painter, f: Rect2) -> void:
	var x: float = cursor_x()
	p.line(TAG_CURSOR, Vector2(x, f.position.y), Vector2(x, f.end.y), UiTokens.HUD_TEXT, CURSOR_WIDTH)
	var half: float = CURSOR_MARK_SIZE.x * 0.5
	var y: float = f.position.y
	p.polygon(TAG_CURSOR, PackedVector2Array([
		Vector2(x - half, y - CURSOR_MARK_SIZE.y), Vector2(x + half, y - CURSOR_MARK_SIZE.y), Vector2(x, y),
	]), UiTokens.HUD_TEXT)


## Подписи шкалы пульса справа от поля (HUD-12.5): 100 и 150 цветом `hud.hr_label`, 11 / 600 tnum.
func _paint_hr_scale(p: Painter, f: Rect2) -> void:
	if not _series.hr_scale_visible() or inset_right < 20.0:
		return
	var font: Font = _font("inter_num_600", 0)
	var shift: float = (font.get_ascent(SCALE_FONT_SIZE) - font.get_descent(SCALE_FONT_SIZE)) * 0.5
	var color: Color = _token_color(str(_series.style(EffortSeries.SERIES_HR)["label_token"]))
	for bpm in _series.hr_scale_labels():
		var y: float = y_hr(float(bpm)) + shift
		p.text(TAG_HR_LABEL, font, Vector2(f.end.x + LABEL_GAP, y), str(bpm), HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				SCALE_FONT_SIZE, color)


## Легенда над правым верхним углом поля: штрих 16 lp + подпись (11 / 550 `hud.text2`);
## половина «пульс» — только при данных пульса.
func _paint_legend(p: Painter, f: Rect2) -> void:
	if not show_fact or _series == null:
		return
	var items: Array[Array] = []
	if not legend_power_key.is_empty():
		items.append([tr(legend_power_key), UiTokens.HUD_POWER_LINE])
	if not legend_hr_key.is_empty() and _series.hr_scale_visible():
		items.append([tr(legend_hr_key), UiTokens.HUD_HR_LINE])
	if items.is_empty():
		return
	var font: Font = _font("inter_500", 550)
	var base: float = plate_top() - 4.0
	var mid: float = base - font.get_ascent(SCALE_FONT_SIZE) * 0.35
	var x: float = f.end.x
	for k in range(items.size() - 1, -1, -1):
		var text: String = items[k][0]
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, SCALE_FONT_SIZE).x
		x -= w
		p.text(TAG_LEGEND, font, Vector2(x, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, SCALE_FONT_SIZE,
				UiTokens.HUD_TEXT2)
		x -= LEGEND_GAP + LEGEND_STROKE
		p.line(TAG_LEGEND, Vector2(x, mid), Vector2(x + LEGEND_STROKE, mid), items[k][1], 2.0)
		x -= LEGEND_ITEM_GAP


# ---------------------------------------------------------------------------
# Токены и шрифты
# ---------------------------------------------------------------------------

## Цвет токена серии (`hud.md` п. 11) из `UiTokens`.
static func _token_color(token: String) -> Color:
	match token:
		EffortSeries.TOKEN_POWER_LINE:
			return UiTokens.HUD_POWER_LINE
		EffortSeries.TOKEN_HR_LINE:
			return UiTokens.HUD_HR_LINE
		EffortSeries.TOKEN_HR_LABEL:
			return UiTokens.HUD_HR_LABEL
		EffortSeries.TOKEN_OUTLINE:
			return UiTokens.HUD_INK
		PlanChartModel.FREE_TOKEN:
			return UiTokens.HUD_FREE
	return ZonePalette.color(token)


## FontVariation темы (`src/ui/theme/fonts/<name>.tres`); `weight > 0` — та же гарнитура с другой
## осью `wght` (550 для подписей, `hud.md` п. 7). Кэш на класс.
static func _font(name: String, weight: int) -> Font:
	var key: String = "%s@%d" % [name, weight]
	if _fonts.has(key):
		return _fonts[key]
	var font: Font = ThemeDB.fallback_font
	var res: Resource = load(_FONT_DIR + name + ".tres")
	if res is FontVariation:
		var v: FontVariation = res
		if weight > 0:
			v = v.duplicate() as FontVariation
			var axes: Dictionary = v.variation_opentype.duplicate()
			axes[TextServerManager.get_primary_interface().name_to_tag("wght")] = weight
			v.variation_opentype = axes
		font = v
	_fonts[key] = font
	return font


# ---------------------------------------------------------------------------
# Вспомогательные классы
# ---------------------------------------------------------------------------

## Слой отрисовки: внутренний `Control` на весь узел, `_draw` вызывает рисовальщик графика.
class _Layer extends Control:
	var paint: Callable

	func _draw() -> void:
		if paint.is_valid():
			paint.call(self)


## Обёртка над `CanvasItem.draw_*`: рисует на холсте и/или пишет журнал вызовов (тесты).
class Painter extends RefCounted:
	var canvas: CanvasItem = null
	var recording: bool = false
	var entries: Array[Dictionary] = []
	var _box: StyleBoxFlat = null

	func begin(target: CanvasItem, record: bool) -> void:
		canvas = target
		recording = record
		entries.clear()

	func rect(tag: String, r: Rect2, color: Color, meta: Dictionary = {}) -> void:
		if canvas != null:
			canvas.draw_rect(r, color)
		_log(tag, "rect", true, color, 0.0, PackedVector2Array([r.position, r.end]), meta)

	func gradient_rect(tag: String, r: Rect2, top: Color, bottom: Color, meta: Dictionary = {}) -> void:
		if r.size.y <= 0.0 or r.size.x <= 0.0:
			return
		var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		if canvas != null:
			canvas.draw_polygon(pts, PackedColorArray([top, top, bottom, bottom]))
		_log(tag, "gradient", true, bottom, 0.0, pts, meta)

	func rounded_rect(tag: String, r: Rect2, color: Color, radius: float, meta: Dictionary = {}) -> void:
		if canvas != null:
			if _box == null:
				_box = StyleBoxFlat.new()
				_box.anti_aliasing = true
			_box.bg_color = color
			_box.set_corner_radius_all(int(radius))
			canvas.draw_style_box(_box, r)
		_log(tag, "rounded_rect", true, color, 0.0, PackedVector2Array([r.position, r.end]), meta)

	func polygon(tag: String, points: PackedVector2Array, color: Color, meta: Dictionary = {}) -> void:
		if points.size() < 3:
			return
		if canvas != null:
			canvas.draw_colored_polygon(points, color)
		_log(tag, "polygon", true, color, 0.0, points, meta)

	## Площадь под верхним контуром `top` (x по возрастанию) до горизонтали `base_y` — четырёхугольниками
	## между соседними точками (без триангуляции: вырожденные контуры не теряются). В журнале одна
	## запись `area`: `points` — контур, `meta.base` — низ.
	func area(tag: String, top: PackedVector2Array, base_y: float, color: Color, meta: Dictionary = {}) -> void:
		if top.size() < 2:
			return
		if canvas != null:
			var colors := PackedColorArray([color, color, color, color])
			for i in range(1, top.size()):
				var a: Vector2 = top[i - 1]
				var b: Vector2 = top[i]
				if b.x - a.x <= 0.0:
					continue
				canvas.draw_primitive(PackedVector2Array([a, b, Vector2(b.x, base_y), Vector2(a.x, base_y)]), colors,
						PackedVector2Array())
		var m: Dictionary = meta.duplicate()
		m["base"] = base_y
		_log(tag, "area", true, color, 0.0, top, m)

	func circle(tag: String, center: Vector2, radius: float, color: Color, meta: Dictionary = {}) -> void:
		if canvas != null:
			canvas.draw_circle(center, radius, color, true, -1.0, true)
		var m: Dictionary = meta.duplicate()
		m["radius"] = radius
		_log(tag, "circle", true, color, 0.0, PackedVector2Array([center]), m)

	func polyline(tag: String, points: PackedVector2Array, color: Color, width: float, meta: Dictionary = {}) -> void:
		if points.size() < 2:
			return
		if canvas != null:
			canvas.draw_polyline(points, color, width, true)
		_log(tag, "polyline", false, color, width, points, meta)

	func multiline(tag: String, points: PackedVector2Array, color: Color, width: float, meta: Dictionary = {}) -> void:
		if points.size() < 2:
			return
		if canvas != null:
			canvas.draw_multiline(points, color, width, true)
		_log(tag, "multiline", false, color, width, points, meta)

	func line(tag: String, a: Vector2, b: Vector2, color: Color, width: float, meta: Dictionary = {}) -> void:
		if canvas != null:
			canvas.draw_line(a, b, color, width, true)
		_log(tag, "line", false, color, width, PackedVector2Array([a, b]), meta)

	func text(tag: String, font: Font, pos: Vector2, value: String, align: HorizontalAlignment, width: float,
			font_size: int, color: Color) -> void:
		if canvas != null:
			canvas.draw_string(font, pos, value, align, width, font_size, color)
		_log(tag, "text", false, color, 0.0, PackedVector2Array([pos]), {"text": value, "size": font_size})

	func _log(tag: String, op: String, filled: bool, color: Color, width: float, points: PackedVector2Array,
			meta: Dictionary) -> void:
		if not recording:
			return
		entries.append({
			"tag": tag, "op": op, "filled": filled, "color": color, "width": width,
			"points": points, "meta": meta,
		})
