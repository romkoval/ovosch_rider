class_name RoutePreviewModel
extends RefCounted
## Модель превью трассы (REQ-FRD-03 крит. 1–3, основа крит. 5, 6; REQ-UIX-03 крит. 2, 4 —
## трасса; `docs/game/tracks.md` п. 7). Только числа, токены и строки — без узлов и
## отрисовки: рисует `RoutePreview` (миниатюра и крупный профиль), на той же модели
## строится панель рельефа HUD свободной езды (T-079), поэтому превью и HUD показывают
## одну и ту же серию.
##
## Источник — `RouteProfile` (выборка с шагом ≤ 10 м, уклоны по окну 100 м, набор, макс.
## уклон, подъёмы D3D-08). Цифры превью не задаются вручную, а форматируются из функций
## профиля (`length_m`, `ascent_m`, `max_grade_pct`).
##
## Серия (s, h) — точки выборки профиля на участке [s_from; s_to] (весь круг: [0; L], обе
## границы входят; s не оборачивается, высота берётся по модулю L). Если точек больше
## 2 × ширины графика в пикселях, серия прореживается min/max-корзинами: границы участка
## остаются, внутренние точки делятся на (ширина − 1) корзин по s, из каждой берутся минимум
## и максимум высоты в порядке s. Так точек ≤ 2 × ширины, а локальные экстремумы масштаба
## пикселя (вершины, седловины, дно) остаются среди точек.
##
## Ось Y (`Plot`):
## - миниатюра — низ поля = минимум трассы, размах max(перепад, 150 м) (`tracks.md` п. 7.1,
##   FRD-03 крит. 3): равнина ≈ 8 % высоты поля, приморье ≈ 30 %, холмы ≈ 65 %, горы — 100 %;
## - крупный профиль — тот же размах max(перепад, 150 м) (`tracks.md` п. 7.2), сверху и снизу
##   поля по `LARGE_MARGIN_FRACTION` высоты поля: место под подписи высот, линия профиля
##   не прилипает к краям;
## - произвольное окно (HUD «впереди 2 км», T-079) — `window_plot()` со своим минимальным
##   размахом.
##
## Заливка — куски по палитре уклона (`UiTokens.grade_color`, `hud.md` п. 11): точка выборки k
## отвечает за ячейку [(k − ½)·шаг; (k + ½)·шаг] (уклон считается по окну с центром в точке),
## соседние ячейки одного цвета сливаются; кусок уже `MIN_PIECE_PX` вливается в более длинного
## соседа (`tracks.md` п. 7.1: кусок ≥ 2 lp).

## Режим превью: миниатюра карточки или крупный профиль детали.
enum Mode { THUMB, LARGE }

## Минимальный размах шкалы высот превью, м (`tracks.md` п. 7.1, 7.2; FRD-03 крит. 3).
const MIN_SPAN_M: float = 150.0
## Поля крупного профиля сверху и снизу — доля высоты поля (не меньше 10 %, T-075).
const LARGE_MARGIN_FRACTION: float = 0.10
## Минимальная ширина куска заливки одного цвета, px (lp) (`tracks.md` п. 7.1).
const MIN_PIECE_PX: float = 2.0
## Подписей подъёмов в полной форме — не больше стольких, самые длинные (FRD-03 крит. 6).
const MAX_CLIMB_LABELS: int = 3
## Если подъёмов больше `MAX_CLIMB_LABELS`, но не больше этого числа, подписываются все
## в краткой форме (холмы — четыре, FRD-03 крит. 6, `tracks.md` п. 7.2).
const MAX_SHORT_CLIMB_LABELS: int = 4
## Ряд шагов шкалы км (FRD-03 крит. 6, как HUD-10.4); дальше — кратные последнему.
const KM_STEPS: Array[int] = [1, 2, 5, 10]
## Не больше стольких подписей шкалы км, включая 0.
const MAX_KM_LABELS: int = 10

## Ключи переводов (`assets/i18n/strings_tracks.csv`).
const KEY_UNIT_KM: String = "track.unit.km"
const KEY_UNIT_M: String = "track.unit.m"
const KEY_UNIT_PCT: String = "track.unit.pct"
const KEY_STAT_LAP: String = "track.stat.lap"
const KEY_STAT_ASCENT: String = "track.stat.ascent"
const KEY_STAT_MAX_GRADE: String = "track.stat.max_grade"
const KEY_CLIMB: String = "track.climb"
const KEY_BRIDGE: String = "track.bridge"

## Идентификаторы цифр в `stats()`.
const STAT_LENGTH: String = "length"
const STAT_ASCENT: String = "ascent"
const STAT_MAX_GRADE: String = "max_grade"


## Отображение участка трассы на прямоугольник поля: X — s, Y — высота.
class Plot:
	extends RefCounted
	## Поле графика в координатах рисующего узла (lp).
	var rect: Rect2 = Rect2()
	## Участок трассы по s, м (без оборачивания: `s_to` может быть больше L).
	var s_from: float = 0.0
	var s_to: float = 1.0
	## Высоты нижнего и верхнего края поля, м.
	var h_bottom: float = 0.0
	var h_top: float = 1.0

	func _init(field: Rect2 = Rect2(), from_m: float = 0.0, to_m: float = 1.0,
			bottom_m: float = 0.0, top_m: float = 1.0) -> void:
		rect = field
		s_from = from_m
		s_to = to_m if to_m > from_m else from_m + 1.0
		h_bottom = bottom_m
		h_top = top_m if top_m > bottom_m else bottom_m + 1.0

	func x(s_m: float) -> float:
		return rect.position.x + (s_m - s_from) / (s_to - s_from) * rect.size.x

	func y(h_m: float) -> float:
		return rect.end.y - (h_m - h_bottom) / (h_top - h_bottom) * rect.size.y

	func point(s_m: float, h_m: float) -> Vector2:
		return Vector2(x(s_m), y(h_m))

	## Пикселей (lp) на метр дистанции.
	func px_per_m() -> float:
		return rect.size.x / (s_to - s_from)


var profile: RouteProfile
## Id трассы каталога (пусто — модель по голому профилю).
var route_id: String = ""
## Ключи названия и типа трассы (`track.<id>.name` / `.kind`).
var name_key: String = ""
var kind_key: String = ""
## Цвет настроения карточки (`tracks.md` п. 7.1), sRGB.
var mood_color: Color = Color.WHITE
## Диапазоны мостов по s, м (x — начало, y — конец).
var bridges: Array[Vector2] = []
## Отмечать вершину треугольником над максимумом (горы, `tracks.md` п. 7.1).
var marks_peak: bool = false


func _init(route_profile: RouteProfile = null) -> void:
	profile = route_profile


## Модель трассы каталога: профиль, мосты, цвет настроения и ключи названия.
static func for_route(route: RouteCatalog.RouteDef) -> RoutePreviewModel:
	var model := RoutePreviewModel.new(route.profile)
	model.route_id = route.id
	model.name_key = route.name_key
	model.kind_key = route.kind_key
	model.mood_color = route.mood_color
	model.bridges = route.bridges.duplicate()
	model.marks_peak = route.id == RouteCatalog.MOUNTAINS
	return model


## Модель по голому профилю (тесты, профиль не из каталога).
static func for_profile(route_profile: RouteProfile) -> RoutePreviewModel:
	return RoutePreviewModel.new(route_profile)


func is_valid() -> bool:
	return profile != null and profile.is_valid()


func length_m() -> float:
	return profile.length_m() if is_valid() else 0.0


# ---------------------------------------------------------------------------
# Шкалы
# ---------------------------------------------------------------------------

## Высоты нижнего (x) и верхнего (y) края поля для участка с высотами `h_min…h_max`:
## размах max(h_max − h_min, `min_span_m`), низ — `h_min`; затем поля `margin_fraction`
## высоты поля сверху и снизу (0 — без полей).
static func y_range_for(h_min: float, h_max: float, min_span_m: float, margin_fraction: float = 0.0) -> Vector2:
	var span: float = maxf(maxf(h_max - h_min, min_span_m), 1e-6)
	var margin: float = clampf(margin_fraction, 0.0, 0.45)
	var pad: float = span * margin / (1.0 - 2.0 * margin)
	return Vector2(h_min - pad, h_min + span + pad)


## Высоты нижнего и верхнего края поля для режима превью (весь круг).
func y_range(mode: Mode) -> Vector2:
	if not is_valid():
		return Vector2(0.0, MIN_SPAN_M)
	var margin: float = LARGE_MARGIN_FRACTION if mode == Mode.LARGE else 0.0
	return y_range_for(profile.min_height_m(), profile.max_height_m(), MIN_SPAN_M, margin)


## Доля высоты поля, которую занимает профиль круга (перепад / высота шкалы).
func fill_fraction(mode: Mode) -> float:
	if not is_valid():
		return 0.0
	var r := y_range(mode)
	return (profile.max_height_m() - profile.min_height_m()) / (r.y - r.x)


## Отображение всего круга на поле `field` в режиме `mode`.
func plot(mode: Mode, field: Rect2) -> Plot:
	var r := y_range(mode)
	return Plot.new(field, 0.0, maxf(length_m(), 1.0), r.x, r.y)


## Отображение участка [s_from; s_to] (без оборачивания; может выходить за 0 и L) со своей
## шкалой высот: от минимума до максимума участка, размах не меньше `min_span_m`
## (HUD «впереди 2 км»: 40 м, `hud.md` п. 8).
func window_plot(s_from: float, s_to: float, field: Rect2, min_span_m: float, margin_fraction: float = 0.0) -> Plot:
	var lo: float = INF
	var hi: float = -INF
	for p in _raw_series(s_from, s_to):
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	if lo > hi:
		lo = 0.0
		hi = 0.0
	var r := y_range_for(lo, hi, min_span_m, margin_fraction)
	return Plot.new(field, s_from, s_to, r.x, r.y)


# ---------------------------------------------------------------------------
# Серия и заливка
# ---------------------------------------------------------------------------

## Серия (s, h) на участке плота, прореженная до ≤ 2 × ширины поля в пикселях.
func series(p: Plot) -> PackedVector2Array:
	return decimate(_raw_series(p.s_from, p.s_to), max_points_for_width(p.rect.size.x))


## Серия всего круга (s от 0 до L) для графика шириной `width_px`.
func lap_series(width_px: float) -> PackedVector2Array:
	return decimate(_raw_series(0.0, length_m()), max_points_for_width(width_px))


## Предел числа точек серии для графика шириной `width_px` (FRD-03 крит. 3): 2 × ширины.
static func max_points_for_width(width_px: float) -> int:
	return maxi(2 * floori(width_px), 2)


## Прореживание min/max-корзинами: первая и последняя точки остаются, внутренние делятся
## на (max_points / 2 − 1) корзин по порядку, из корзины — минимум и максимум по y в порядке x.
static func decimate(points: PackedVector2Array, max_points: int) -> PackedVector2Array:
	var n: int = points.size()
	var limit: int = maxi(max_points, 2)
	if n <= limit:
		return points.duplicate()
	var out := PackedVector2Array()
	out.append(points[0])
	var inner: int = n - 2
	var buckets: int = maxi(limit / 2 - 1, 1)
	for b in buckets:
		var i0: int = 1 + b * inner / buckets
		var i1: int = 1 + (b + 1) * inner / buckets
		if i1 <= i0:
			continue
		var i_min: int = i0
		var i_max: int = i0
		for i in range(i0, i1):
			if points[i].y < points[i_min].y:
				i_min = i
			if points[i].y > points[i_max].y:
				i_max = i
		out.append(points[mini(i_min, i_max)])
		if i_max != i_min:
			out.append(points[maxi(i_min, i_max)])
	out.append(points[n - 1])
	return out


## Серия в координатах поля — контур профиля.
func outline(p: Plot) -> PackedVector2Array:
	var out := PackedVector2Array()
	for pt in series(p):
		out.append(p.point(pt.x, pt.y))
	return out


## Куски цвета уклона на участке плота: `{s0, s1, color}` по возрастанию s, без зазоров,
## от `p.s_from` до `p.s_to`; каждый кусок шире `MIN_PIECE_PX` (если поле не уже).
func grade_pieces(p: Plot) -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
	if not is_valid():
		return pieces
	var grades := profile.sample_grades()
	var n: int = grades.size()
	var step: float = profile.sample_step_m()
	var k0: int = roundi(p.s_from / step)
	var k1: int = roundi(p.s_to / step)
	for k in range(k0, k1 + 1):
		var c0: float = maxf(p.s_from, (float(k) - 0.5) * step)
		var c1: float = minf(p.s_to, (float(k) + 0.5) * step)
		if c1 <= c0:
			continue
		var color: Color = UiTokens.grade_color(grades[posmod(k, n)])
		if not pieces.is_empty() and pieces[-1]["color"] == color:
			pieces[-1]["s1"] = c1
		else:
			pieces.append({"s0": c0, "s1": c1, "color": color})
	_merge_narrow(pieces, MIN_PIECE_PX / maxf(p.px_per_m(), 1e-9))
	return pieces


## Заливка под профилем кусками: `{color, top}`, где `top` — точки контура куска в координатах
## поля слева направо (с концами на границах куска); низ заливки — `p.rect.end.y`.
func fill(p: Plot) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pts := series(p)
	if pts.size() < 2:
		return out
	var xs := PackedFloat64Array()
	for pt in pts:
		xs.append(pt.x)
	for piece in grade_pieces(p):
		var s0: float = piece["s0"]
		var s1: float = piece["s1"]
		var top := PackedVector2Array()
		top.append(p.point(s0, _interp(pts, xs, s0)))
		var i: int = xs.bsearch(s0, false)
		while i < pts.size() and pts[i].x < s1:
			if pts[i].x > s0:
				top.append(p.point(pts[i].x, pts[i].y))
			i += 1
		top.append(p.point(s1, _interp(pts, xs, s1)))
		out.append({"color": piece["color"], "top": top})
	return out


# ---------------------------------------------------------------------------
# Подписи
# ---------------------------------------------------------------------------

## Подъёмы для подписей (FRD-03 крит. 6, `tracks.md` п. 7.2) в порядке s:
## `{start_m, length_m, mid_m, avg_grade_pct, short, text}`. До `MAX_CLIMB_LABELS` — все,
## полная форма «подъём 7.0 км · 6.0 %»; до `MAX_SHORT_CLIMB_LABELS` — все, краткая форма
## «1.2 км · 5.7 %»; больше — `MAX_CLIMB_LABELS` самых длинных в полной форме.
func climb_labels() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_valid():
		return out
	var climbs := profile.climbs()
	var short: bool = climbs.size() > MAX_CLIMB_LABELS and climbs.size() <= MAX_SHORT_CLIMB_LABELS
	if climbs.size() > MAX_SHORT_CLIMB_LABELS:
		climbs.sort_custom(func(a: RouteProfile.Climb, b: RouteProfile.Climb) -> bool: return a.length_m > b.length_m)
		climbs = climbs.slice(0, MAX_CLIMB_LABELS)
		climbs.sort_custom(func(a: RouteProfile.Climb, b: RouteProfile.Climb) -> bool: return a.start_m < b.start_m)
	for c in climbs:
		var body: String = "%s · %s" % [format_length_km(c.length_m), format_grade_pct(c.avg_grade_pct)]
		out.append({
			"start_m": c.start_m,
			"length_m": c.length_m,
			"mid_m": c.start_m + c.length_m * 0.5,
			"avg_grade_pct": c.avg_grade_pct,
			"short": short,
			"text": body if short else _tr(KEY_CLIMB).format({"value": body}),
		})
	return out


## Шаг шкалы км: наименьший из `KM_STEPS`, при котором подписей (включая 0) не больше
## `MAX_KM_LABELS`; если не хватает и последнего — кратный ему.
static func km_step(length_m: float) -> int:
	var km: float = maxf(length_m, 0.0) / 1000.0
	for step in KM_STEPS:
		if floori(km / float(step) + 1e-9) + 1 <= MAX_KM_LABELS:
			return step
	var base: int = KM_STEPS[-1]
	var k: int = 2
	while floori(km / float(base * k) + 1e-9) + 1 > MAX_KM_LABELS:
		k += 1
	return base * k


## Подписи шкалы км: `{s_m, fraction, text}` — 0, шаг, 2·шаг, … ≤ L (число без единицы).
func km_labels() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var length: float = length_m()
	if length <= 0.0:
		return out
	var step: int = km_step(length)
	var km: int = 0
	while float(km) * 1000.0 <= length + 1e-6:
		out.append({"s_m": float(km) * 1000.0, "fraction": float(km) * 1000.0 / length, "text": "%d" % km})
		km += step
	return out


## Подписи высот крупного профиля: максимум и минимум трассы `{h_m, text}` («738 м»).
func height_labels() -> Array[Dictionary]:
	if not is_valid():
		return [] as Array[Dictionary]
	return [
		{"h_m": profile.max_height_m(), "text": format_height_m(profile.max_height_m())},
		{"h_m": profile.min_height_m(), "text": format_height_m(profile.min_height_m())},
	] as Array[Dictionary]


## s самой высокой точки выборки, м (вершина для треугольника гор).
func peak_s_m() -> float:
	if not is_valid():
		return 0.0
	var heights := profile.sample_heights()
	var best: int = 0
	for i in heights.size():
		if heights[i] > heights[best]:
			best = i
	return float(best) * profile.sample_step_m()


func has_bridge() -> bool:
	return not bridges.is_empty()


## Подпись моста («мост» / «bridge»).
static func bridge_text() -> String:
	return _tr(KEY_BRIDGE)


# ---------------------------------------------------------------------------
# Цифры и форматы (FRD-03 крит. 1, 2)
# ---------------------------------------------------------------------------

## Три цифры превью по функциям профиля: `{id, value, unit, text, caption}`
## («20.0», «км», «20.0 км», «круг»), порядок — длина, набор, макс. уклон.
func stats() -> Array[Dictionary]:
	var length: float = length_m()
	var ascent: float = profile.ascent_m() if is_valid() else 0.0
	var grade: float = profile.max_grade_pct() if is_valid() else 0.0
	return [
		_stat(STAT_LENGTH, length_value(length), KEY_UNIT_KM, KEY_STAT_LAP),
		_stat(STAT_ASCENT, ascent_value(ascent), KEY_UNIT_M, KEY_STAT_ASCENT),
		_stat(STAT_MAX_GRADE, grade_value(grade), KEY_UNIT_PCT, KEY_STAT_MAX_GRADE),
	] as Array[Dictionary]


func length_text() -> String:
	return format_length_km(length_m())


func ascent_text() -> String:
	return format_ascent_m(profile.ascent_m() if is_valid() else 0.0)


func max_grade_text() -> String:
	return format_grade_pct(profile.max_grade_pct() if is_valid() else 0.0)


## Длина в км с одним знаком: «3.0 км» / «3.0 km».
static func format_length_km(length_m: float) -> String:
	return "%s %s" % [length_value(length_m), _tr(KEY_UNIT_KM)]


## Набор — целые метры: «50 м» / «50 m».
static func format_ascent_m(ascent_m: float) -> String:
	return "%s %s" % [ascent_value(ascent_m), _tr(KEY_UNIT_M)]


## Высота — целые метры: «738 м».
static func format_height_m(height_m: float) -> String:
	return "%d %s" % [roundi(height_m), _tr(KEY_UNIT_M)]


## Уклон в % с одним знаком: «5.0 %».
static func format_grade_pct(grade_pct: float) -> String:
	return "%s %s" % [grade_value(grade_pct), _tr(KEY_UNIT_PCT)]


static func length_value(length_m: float) -> String:
	return _fixed1(maxf(length_m, 0.0) / 1000.0)


static func ascent_value(ascent_m: float) -> String:
	return "%d" % roundi(maxf(ascent_m, 0.0))


static func grade_value(grade_pct: float) -> String:
	return _fixed1(grade_pct)


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

## Точки выборки профиля на [s_from; s_to] плюс обе границы участка (высота границ — h(s)).
func _raw_series(s_from: float, s_to: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not is_valid() or s_to <= s_from:
		return out
	var heights := profile.sample_heights()
	var n: int = heights.size()
	var step: float = profile.sample_step_m()
	var eps: float = step * 1e-6
	out.append(Vector2(s_from, profile.height_at(s_from)))
	var k: int = ceili(s_from / step)
	while float(k) * step < s_to - eps:
		var s: float = float(k) * step
		if s > s_from + eps:
			out.append(Vector2(s, heights[posmod(k, n)]))
		k += 1
	out.append(Vector2(s_to, profile.height_at(s_to)))
	return out


## Слить куски уже `min_len_m` с более длинным соседом (сначала самые узкие).
static func _merge_narrow(pieces: Array[Dictionary], min_len_m: float) -> void:
	while pieces.size() > 1:
		var idx: int = -1
		var narrow: float = min_len_m
		for i in pieces.size():
			var len_i: float = pieces[i]["s1"] - pieces[i]["s0"]
			if len_i < narrow:
				narrow = len_i
				idx = i
		if idx < 0:
			return
		var left: int = idx - 1
		var right: int = idx + 1
		var into: int = left
		if left < 0:
			into = right
		elif right < pieces.size():
			var len_l: float = pieces[left]["s1"] - pieces[left]["s0"]
			var len_r: float = pieces[right]["s1"] - pieces[right]["s0"]
			into = right if len_r > len_l else left
		if into < idx:
			pieces[into]["s1"] = pieces[idx]["s1"]
		else:
			pieces[into]["s0"] = pieces[idx]["s0"]
		pieces.remove_at(idx)
		_coalesce(pieces)


## Соседние куски одного цвета — один кусок.
static func _coalesce(pieces: Array[Dictionary]) -> void:
	var i: int = 1
	while i < pieces.size():
		if pieces[i - 1]["color"] == pieces[i]["color"]:
			pieces[i - 1]["s1"] = pieces[i]["s1"]
			pieces.remove_at(i)
		else:
			i += 1


## Высота серии в s линейной интерполяцией между точками серии (заливка совпадает с контуром).
static func _interp(pts: PackedVector2Array, xs: PackedFloat64Array, s: float) -> float:
	var i: int = xs.bsearch(s, true)
	if i <= 0:
		return pts[0].y
	if i >= pts.size():
		return pts[-1].y
	var a: Vector2 = pts[i - 1]
	var b: Vector2 = pts[i]
	if b.x - a.x <= 0.0:
		return b.y
	return lerpf(a.y, b.y, (s - a.x) / (b.x - a.x))


static func _stat(id: String, value: String, unit_key: String, caption_key: String) -> Dictionary:
	var unit: String = _tr(unit_key)
	return {"id": id, "value": value, "unit": unit, "text": "%s %s" % [value, unit], "caption": _tr(caption_key)}


## Число с одним знаком после точки (точка на обоих языках, как в макетах); без «−0.0».
static func _fixed1(v: float) -> String:
	var r: float = roundf(v * 10.0) / 10.0
	if r == 0.0:
		r = 0.0
	return "%.1f" % r


static func _tr(key: String) -> String:
	return String(TranslationServer.translate(key))
