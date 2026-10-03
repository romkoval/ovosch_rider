class_name IntervalList
extends Control
## Список интервалов HUD в левом слоте (REQ-HUD-13 крит. 2, 3, 8; `docs/game/hud.md` п. 6, 10.1).
##
## Данные — `IntervalListModel`; здесь только раскладка и отрисовка. Подложка `hud.plate`,
## шапка (название, полоса общего прогресса, «Осталось»), окно строк (≤ 8: до 2 пройденных,
## текущая, до 5 следующих) и подвал «Шаг N из M».
##
## Текущая строка выше остальных (42 против 26–28 lp), залита цветом зоны, текст `hud.ink`,
## пройденная доля шага затемнена, справа снаружи указатель ▶. Пройденные — бледные с ✓,
## пропущенные — со штриховкой и зачёркиванием, предстоящие — с полосой зоны слева,
## «свободно» — `hud.free` со светлой штриховкой. Цвета — `UiTokens` и `ZonePalette`,
## шрифты — начертания Inter темы (`AppThemeBuilder.FONT_DIR`), цифры с `tnum`.
##
## Смена шага: окно прокручивается за `SCROLL_SEC` (ease-out) так, что текущая строка
## остаётся на своём месте; высоты строк меняются за `GROW_SEC` (новая текущая растёт до 42,
## раскрытый блок повторов вырастает из свёрнутой строки).
##
## Ширина — `list_width` (lp; задаёт `HudLayout`, `hud.md` п. 4.1: `w_l`), высота — по
## содержимому, не больше `max_height` (0 — без ограничения). Размеры — в lp HUD: масштаб `s`
## применяется окном (`content_scale_factor`, `hud.md` п. 3), здесь не умножается.
##
## Тексты: единица — `ui.workout.unit_w`. Ключи «свободно», «Осталось», «Шаг {step} из
## {steps}» задаёт владелец экрана (`free_text_key`, `remaining_key`, `step_counter_key`);
## пока ключ пуст, «свободно» не пишется (строку отличает штриховка), подпись «Осталось»
## не выводится, а подвал собирается из `ui.workout.step` («Шаг 3/12»).

# --- Геометрия (`hud.md` п. 6), lp --------------------------------------------------------
const PLATE_RADIUS: int = 14
const PAD: float = 8.0
const HEADER_H: float = 66.0
const FOOTER_H: float = 26.0
const PROGRESS_H: float = 6.0
const ROW_GAP: float = 3.0
const ROW_TEXT_PAD: float = 8.0
const STRIPE_W: float = 5.0
const POINTER_SIZE: Vector2 = Vector2(8, 10)
## Справа от строк остаётся место под указатель ▶ текущей строки.
const ROWS_RIGHT_INSET: float = 6.0
const HATCH_STEP: float = 6.0
const HATCH_WIDTH: float = 1.5
const CHECK_W: float = 12.0

const ROW_HEIGHT: Dictionary = {
	IntervalListModel.STATUS_DONE: 26.0,
	IntervalListModel.STATUS_CURRENT: 42.0,
	IntervalListModel.STATUS_UPCOMING: 28.0,
	IntervalListModel.STATUS_SKIPPED: 26.0,
}
const ROW_RADIUS: Dictionary = {
	IntervalListModel.STATUS_DONE: 7,
	IntervalListModel.STATUS_CURRENT: 9,
	IntervalListModel.STATUS_UPCOMING: 7,
	IntervalListModel.STATUS_SKIPPED: 7,
}
## Альфа заливки строки по состоянию (у текущей — сплошная).
const ROW_FILL_ALPHA: Dictionary = {
	IntervalListModel.STATUS_DONE: 0.22,
	IntervalListModel.STATUS_CURRENT: 1.0,
	IntervalListModel.STATUS_UPCOMING: 0.40,
	IntervalListModel.STATUS_SKIPPED: 0.22,
}
const DONE_TEXT_ALPHA: float = 0.55
const CURRENT_DONE_SHADE: Color = Color(UiTokens.HUD_INK, 0.16)
const SKIPPED_HATCH: Color = Color(UiTokens.HUD_INK, 0.6)
const FREE_HATCH: Color = Color(1.0, 1.0, 1.0, 0.10)
const PROGRESS_TRACK: Color = Color(UiTokens.HUD_TEXT, 0.18)

# --- Типографика (`hud.md` п. 6): [начертание, кегль] ------------------------------------
const FONT_TITLE: Array = ["inter_650", 17]
const FONT_CAPTION: Array = ["inter_500", 13]
const FONT_REMAINING: Array = ["inter_num_650", 13]
## Пройденный и пропущенный — 14 / 550 по `hud.md`; в теме нет 550, берётся ближайшее 600.
const FONT_ROW: Dictionary = {
	IntervalListModel.STATUS_DONE: ["inter_num_600", 14],
	IntervalListModel.STATUS_CURRENT: ["inter_num_750", 20],
	IntervalListModel.STATUS_UPCOMING: ["inter_num_600", 15],
	IntervalListModel.STATUS_SKIPPED: ["inter_num_600", 14],
}
const FONT_PREFIX: Array = ["inter_num_750", 15]

# --- Анимация (`hud.md` п. 10.1) ------------------------------------------------------------
const SCROLL_SEC: float = 0.3
const GROW_SEC: float = 0.2

## Ширина списка, lp (`w_l` из `HudLayout`).
@export var list_width: float = 282.0:
	set(value):
		list_width = maxf(value, 0.0)
		_update_size()
## Наибольшая высота списка, lp (0 — без ограничения).
@export var max_height: float = 0.0:
	set(value):
		max_height = maxf(value, 0.0)
		_update_size()

## Ключ перевода «свободно» (пусто — у свободного шага пишется только длительность).
var free_text_key: String = ""
## Ключ подписи «Осталось» в шапке (пусто — подписи нет, время остаётся).
var remaining_key: String = ""
## Ключ подвала с плейсхолдерами `{step}` и `{steps}` (пусто — `ui.workout.step` с «N/M»).
var step_counter_key: String = ""

var model: IntervalListModel = null

static var _font_cache: Dictionary = {}

var _rows_view: Control
var _rows: Array[Dictionary] = []
var _revision: int = -1
## Показываемые высоты строк по `key`, начало и цель анимации.
var _heights: Dictionary = {}
var _from_heights: Dictionary = {}
var _to_heights: Dictionary = {}
var _scroll: float = 0.0
var _from_scroll: float = 0.0
var _to_scroll: float = 0.0
var _area_h: float = 0.0
var _from_area_h: float = 0.0
var _to_area_h: float = 0.0
var _anim_t: float = 0.0
var _animating: bool = false
var _plate: StyleBoxFlat
var _box: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate = StyleBoxFlat.new()
	_plate.bg_color = UiTokens.HUD_PLATE
	_plate.set_corner_radius_all(PLATE_RADIUS)
	_box = StyleBoxFlat.new()
	_rows_view = Control.new()
	_rows_view.name = "Rows"
	_rows_view.clip_contents = true
	_rows_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows_view.draw.connect(_draw_rows)
	add_child(_rows_view, false, Node.INTERNAL_MODE_FRONT)
	set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()
		_rows_view.queue_redraw()


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

## Модель списка; раскладка строится сразу, без анимации.
func set_model(value: IntervalListModel) -> void:
	model = value
	_revision = -1
	_rows.clear()
	_heights.clear()
	refresh(false)


## Модель по сессии (план, FTP, множитель, зоны профиля) и первая синхронизация.
func setup(session: WorkoutSession, power_zones: PowerZones = null) -> void:
	set_model(IntervalListModel.for_session(session, power_zones))


## Синхронизация с сессией раз в сэмпл и после пропуска/смены множителя: выделение
## переходит на новую строку в этом же вызове, прокрутка и рост строк — анимацией.
func sync(session: WorkoutSession) -> bool:
	if model == null:
		return false
	var changed: bool = model.sync(session)
	if changed:
		refresh()
	return changed


## Перечитать модель: при новой версии строк — перестроить раскладку (с анимацией, если
## `animate` и список уже был показан), иначе только перерисовать (доля текущего шага, шапка).
func refresh(animate: bool = true) -> void:
	if model == null:
		_rows.clear()
		_update_size()
		queue_redraw()
		_rows_view.queue_redraw()
		return
	if model.revision() != _revision:
		_relayout(animate and _revision >= 0 and is_inside_tree())
	queue_redraw()
	_rows_view.queue_redraw()


## Завершить текущую анимацию прокрутки и роста (для снимков и тестов).
func skip_animation() -> void:
	if _animating:
		_advance(INF)


func is_animating() -> bool:
	return _animating


## Прямоугольник области строк в координатах списка.
func rows_area_rect() -> Rect2:
	return Rect2(_rows_view.position, _rows_view.size)


## Показываемый прямоугольник строки `row` (индекс в `model.rows()`) в координатах списка;
## пустой, если строка вне области строк.
func row_rect(row: int) -> Rect2:
	if row < 0 or row >= _rows.size():
		return Rect2()
	var r: Rect2 = _row_rect_content(row)
	r.position += _rows_view.position - Vector2(0.0, _scroll)
	return r.intersection(rows_area_rect())


## Показываемый прямоугольник текущей строки (пустой — нет текущей или она не видна).
func current_row_rect() -> Rect2:
	return row_rect(model.current_row()) if model != null else Rect2()


## Индексы строк, которые видны в области строк (хотя бы частично).
func visible_rows() -> Array[int]:
	var out: Array[int] = []
	for i in _rows.size():
		if row_rect(i).has_area():
			out.append(i)
	return out


# ---------------------------------------------------------------------------
# Раскладка и анимация
# ---------------------------------------------------------------------------

func _relayout(animate: bool) -> void:
	var old_keys: Dictionary = {}
	for r in _rows:
		old_keys[r["key"]] = true
	_rows = model.rows()
	_revision = model.revision()
	_from_heights.clear()
	_to_heights.clear()
	for r in _rows:
		var key: String = r["key"]
		var target: float = _target_height(r)
		_to_heights[key] = target
		if not animate:
			_from_heights[key] = target
		elif _heights.has(key):
			_from_heights[key] = _heights[key]
		else:
			# Первый шаг раскрытого блока повторов вырастает из свёрнутой строки, остальные — из нуля.
			var collapsed: String = "r%d" % int(r["first_step"])
			_from_heights[key] = float(_heights.get(collapsed, 0.0)) if old_keys.has(collapsed) else 0.0
	var window: Vector2i = model.visible_window()
	_to_scroll = _content_y(window.x, _to_heights)
	_to_area_h = _window_height(window, _to_heights)
	if animate:
		_from_scroll = _scroll
		_from_area_h = _area_h
		_anim_t = 0.0
		_animating = true
		set_process(true)
		_advance(0.0)
	else:
		_animating = false
		set_process(false)
		_advance(INF)


func _process(delta: float) -> void:
	_advance(delta)


func _advance(delta: float) -> void:
	_anim_t += delta
	var k_grow: float = _ease_out(_anim_t / GROW_SEC)
	var k_scroll: float = _ease_out(_anim_t / SCROLL_SEC)
	_heights.clear()
	for key: String in _to_heights:
		_heights[key] = lerpf(float(_from_heights.get(key, 0.0)), float(_to_heights[key]), k_grow)
	_scroll = lerpf(_from_scroll, _to_scroll, k_scroll)
	_area_h = lerpf(_from_area_h, _to_area_h, k_scroll)
	if k_grow >= 1.0 and k_scroll >= 1.0:
		_scroll = _to_scroll
		_area_h = _to_area_h
		_animating = false
		set_process(false)
	_update_size()
	queue_redraw()
	_rows_view.queue_redraw()


static func _ease_out(x: float) -> float:
	var t: float = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


func _target_height(row: Dictionary) -> float:
	return float(ROW_HEIGHT.get(row["status"], ROW_HEIGHT[IntervalListModel.STATUS_UPCOMING]))


## Y начала строки `index` в координатах содержимого (строки подряд с зазором).
func _content_y(index: int, heights: Dictionary) -> float:
	var y: float = 0.0
	for i in mini(index, _rows.size()):
		y += float(heights.get(_rows[i]["key"], 0.0)) + ROW_GAP
	return y


func _window_height(window: Vector2i, heights: Dictionary) -> float:
	if window.y <= 0:
		return 0.0
	var h: float = 0.0
	for i in range(window.x, mini(window.x + window.y, _rows.size())):
		h += float(heights.get(_rows[i]["key"], 0.0))
	return h + ROW_GAP * float(window.y - 1)


func _row_rect_content(index: int) -> Rect2:
	var x0: float = PAD
	var x1: float = list_width - PAD - ROWS_RIGHT_INSET
	return Rect2(x0, _content_y(index, _heights), maxf(x1 - x0, 0.0), float(_heights.get(_rows[index]["key"], 0.0)))


func _rows_area_height() -> float:
	var h: float = _area_h
	if max_height > 0.0:
		h = minf(h, maxf(max_height - HEADER_H - FOOTER_H, 0.0))
	return maxf(h, 0.0)


func _get_minimum_size() -> Vector2:
	return Vector2(list_width, HEADER_H + _rows_area_height() + FOOTER_H)


func _update_size() -> void:
	if _rows_view == null:
		return
	_rows_view.position = Vector2(0.0, HEADER_H)
	_rows_view.size = Vector2(list_width, _rows_area_height())
	update_minimum_size()
	if not (get_parent() is Container):
		size = get_combined_minimum_size()


# ---------------------------------------------------------------------------
# Отрисовка
# ---------------------------------------------------------------------------

func _draw() -> void:
	var w: float = size.x
	draw_style_box(_plate, Rect2(Vector2.ZERO, size))
	if model == null:
		return
	# Шапка: название (обрезка с «…»), полоса общего прогресса, «Осталось» и время.
	var inner: float = w - 2.0 * PAD - 4.0
	var title_font: Font = _font(FONT_TITLE)
	var title_size: int = FONT_TITLE[1]
	var title: String = _fit(model.title(), title_font, title_size, inner)
	draw_string(title_font, Vector2(PAD + 2.0, PAD + 2.0 + title_font.get_ascent(title_size)), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, UiTokens.HUD_TEXT)
	var bar := Rect2(PAD + 2.0, 34.0, inner, PROGRESS_H)
	draw_rect(bar, PROGRESS_TRACK)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * model.progress(), bar.size.y)), UiTokens.HUD_TEXT)
	var cap_font: Font = _font(FONT_CAPTION)
	var cap_size: int = FONT_CAPTION[1]
	var line_y: float = 46.0 + cap_font.get_ascent(cap_size)
	if not remaining_key.is_empty():
		draw_string(cap_font, Vector2(PAD + 2.0, line_y), tr(remaining_key), HORIZONTAL_ALIGNMENT_LEFT, -1,
				cap_size, UiTokens.HUD_TEXT2)
	var time_font: Font = _font(FONT_REMAINING)
	var time_text: String = HudModel.format_elapsed(model.remaining_sec())
	var time_w: float = time_font.get_string_size(time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_REMAINING[1]).x
	draw_string(time_font, Vector2(PAD + 2.0 + inner - time_w, line_y), time_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			FONT_REMAINING[1], UiTokens.HUD_TEXT)
	# Подвал: «Шаг N из M».
	var footer: String = _footer_text()
	if not footer.is_empty():
		var fy: float = HEADER_H + _rows_area_height() + 6.0 + cap_font.get_ascent(cap_size)
		draw_string(cap_font, Vector2(PAD + 2.0, fy), _fit(footer, cap_font, cap_size, inner),
				HORIZONTAL_ALIGNMENT_LEFT, -1, cap_size, UiTokens.HUD_TEXT2)


func _footer_text() -> String:
	var counter: Vector2i = model.step_counter()
	if counter.y <= 0:
		return ""
	var n: int = maxi(counter.x, 1)
	if not step_counter_key.is_empty():
		return tr(step_counter_key).format({"step": n, "steps": counter.y})
	return tr("ui.workout.step").format({"step": "%d/%d" % [n, counter.y]})


func _draw_rows() -> void:
	if model == null:
		return
	var area_h: float = _rows_view.size.y
	var unit: String = tr("ui.workout.unit_w")
	var free_text: String = tr(free_text_key) if not free_text_key.is_empty() else ""
	var progress: float = model.current_progress()
	for i in _rows.size():
		var rect: Rect2 = _row_rect_content(i)
		rect.position.y -= _scroll
		if rect.size.y <= 0.5 or rect.end.y <= 0.0 or rect.position.y >= area_h:
			continue
		_draw_row(_rows[i], rect, unit, free_text, progress)


func _draw_row(row: Dictionary, rect: Rect2, unit: String, free_text: String, progress: float) -> void:
	var ci: Control = _rows_view
	var status: String = row["status"]
	var free: bool = row["free"]
	var radius: int = ROW_RADIUS.get(status, 7)
	var base: Color = UiTokens.HUD_FREE if free else ZonePalette.color(str(row["zone_token"]))
	var current: bool = status == IntervalListModel.STATUS_CURRENT
	_fill(ci, rect, Color(base, float(ROW_FILL_ALPHA.get(status, 0.4))), radius)
	if current and progress > 0.0:
		var shade := Rect2(rect.position, Vector2(rect.size.x * progress, rect.size.y))
		_fill(ci, shade, CURRENT_DONE_SHADE, radius, progress >= 1.0)
	if status == IntervalListModel.STATUS_UPCOMING:
		_fill(ci, Rect2(rect.position, Vector2(STRIPE_W, rect.size.y)), base, radius, false)
	if free:
		_hatch(ci, rect, FREE_HATCH, radius)
	if status == IntervalListModel.STATUS_SKIPPED:
		_hatch(ci, rect, SKIPPED_HATCH, radius)
	if current:
		var px: float = rect.end.x + 1.0
		var cy: float = rect.get_center().y
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(px, cy - POINTER_SIZE.y * 0.5),
			Vector2(px + POINTER_SIZE.x, cy),
			Vector2(px, cy + POINTER_SIZE.y * 0.5),
		]), UiTokens.HUD_TEXT)
	# Текст: длительность слева, цель справа (у блока повторов — «N ×» и одна строка).
	var spec: Array = FONT_ROW.get(status, FONT_ROW[IntervalListModel.STATUS_UPCOMING])
	var font: Font = _font(spec)
	var fsize: int = spec[1]
	var color: Color = UiTokens.HUD_INK if current else UiTokens.HUD_TEXT
	if status == IntervalListModel.STATUS_DONE or status == IntervalListModel.STATUS_SKIPPED:
		color = Color(UiTokens.HUD_TEXT, DONE_TEXT_ALPHA)
	var left_x: float = rect.position.x + ROW_TEXT_PAD + (STRIPE_W if status == IntervalListModel.STATUS_UPCOMING else 0.0)
	var right_x: float = rect.end.x - ROW_TEXT_PAD
	if status == IntervalListModel.STATUS_DONE:
		_check(ci, Vector2(right_x - CHECK_W * 0.5, rect.get_center().y), color)
		right_x -= CHECK_W + 4.0
	var baseline: float = rect.position.y + (rect.size.y - font.get_height(fsize)) * 0.5 + font.get_ascent(fsize)
	var text_end: float = left_x
	if row["kind"] == IntervalListModel.KIND_REPEAT:
		var pfont: Font = _font(FONT_PREFIX)
		var prefix: String = IntervalListModel.repeat_prefix(row)
		ci.draw_string(pfont, Vector2(left_x, baseline), prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PREFIX[1], color)
		var bx: float = left_x + pfont.get_string_size(prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PREFIX[1]).x + 6.0
		var body: String = _fit(IntervalListModel.target_label(row, unit, free_text), font, fsize, right_x - bx)
		ci.draw_string(font, Vector2(bx, baseline), body, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)
		text_end = bx + font.get_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	else:
		var left: String = str(row["duration_text"])
		var left_w: float = font.get_string_size(left, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		ci.draw_string(font, Vector2(left_x, baseline), left, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)
		text_end = left_x + left_w
		var right: String = IntervalListModel.target_label(row, unit, free_text)
		if not right.is_empty():
			right = _fit(right, font, fsize, right_x - text_end - 8.0)
			var right_w: float = font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
			ci.draw_string(font, Vector2(right_x - right_w, baseline), right, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)
			text_end = right_x
	if status == IntervalListModel.STATUS_SKIPPED:
		var sy: float = baseline - font.get_ascent(fsize) * 0.35
		ci.draw_line(Vector2(left_x, sy), Vector2(text_end, sy), color, 1.0)


## Скруглённый прямоугольник; `round_right = false` — правые углы прямые (полоса зоны,
## затемнение пройденной доли).
func _fill(ci: CanvasItem, rect: Rect2, color: Color, radius: int, round_right: bool = true) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var r: int = mini(radius, int(minf(rect.size.x, rect.size.y) * 0.5))
	var right: int = r if round_right else 0
	_box.bg_color = color
	_box.corner_radius_top_left = r
	_box.corner_radius_bottom_left = r
	_box.corner_radius_top_right = right
	_box.corner_radius_bottom_right = right
	ci.draw_style_box(_box, rect)


## Штриховка 45° (снизу-слева вверх-вправо) внутри прямоугольника; от углов скругления
## отступ 0.3 радиуса, чтобы линии не выходили за скруглённую заливку.
static func _hatch(ci: CanvasItem, rect: Rect2, color: Color, radius: int) -> void:
	var r: Rect2 = rect.grow(-float(radius) * 0.3)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	# Линии x + y = c; c от (лево + верх) до (право + низ).
	var c: float = r.position.x + r.position.y + HATCH_STEP
	while c < r.end.x + r.end.y:
		var x0: float = maxf(r.position.x, c - r.end.y)
		var x1: float = minf(r.end.x, c - r.position.y)
		if x1 > x0:
			ci.draw_line(Vector2(x0, c - x0), Vector2(x1, c - x1), color, HATCH_WIDTH, true)
		c += HATCH_STEP


## Галочка «пройден» с центром `center`.
static func _check(ci: CanvasItem, center: Vector2, color: Color) -> void:
	var s: float = CHECK_W * 0.5
	ci.draw_polyline(PackedVector2Array([
		center + Vector2(-s, 0.0),
		center + Vector2(-s * 0.3, s * 0.65),
		center + Vector2(s, -s * 0.7),
	]), color, 1.6, true)


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
