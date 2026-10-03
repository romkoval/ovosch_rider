class_name ReliefPanelModel
extends RefCounted
## Модель панели рельефа HUD свободной езды (REQ-FRD-06 крит. 3 — отображение; `docs/game/hud.md`
## п. 8, «Левый слот — панель рельефа»). Только числа, строки и отображения участков трассы на
## прямоугольники — без узлов; рисует `ReliefPanel`.
##
## Источник рельефа — `RoutePreviewModel` той же трассы (та же серия, что превью FRD-03 крит. 3:
## точки выборки профиля, прореживание min/max под ширину, куски заливки по палитре уклона).
## Позиция — из `FreeRideSession` (`sync`) или задаётся напрямую (`set_position`, тесты).
##
## - Круг целиком: участок [0; L], шкала Y от минимума до максимума трассы с размахом не
##   меньше `LAP_MIN_SPAN_M`. Маркер — x = (s mod L) / L × ширина, y — высота профиля в s.
##   Пройденная часть круга — `lap_distance_m` за маркером (через стык — два отрезка).
## - «Впереди 2 км»: участок [s − 200; s + 2000] м (без оборачивания: через стык профиль
##   продолжается следующим кругом), своя шкала Y с размахом не меньше `AHEAD_MIN_SPAN_M`
##   и полями сверху/снизу `AHEAD_MARGIN_FRACTION` (место под подпись уклона). Маркер —
##   x = 200 / 2200 × ширина.
## - Подпись самого крутого места подъёма впереди: максимум уклона точек выборки на (s; s + 2000],
##   если он больше порога подъёма D3D-08 (2 %).
## - Подвал: на подъёме (участок уклона > 2 % длиной ≥ 300 м, D3D-08), если до вершины
##   ≥ 300 м, — «до вершины 4.2 км · +262 м»; не на подъёме — «подъём через 1.3 км», если
##   начало ближайшего подъёма ближе 3 км; иначе пусто.

## Окно «впереди»: назад и вперёд от позиции, м (FRD-06 крит. 3 б).
const AHEAD_BEHIND_M: float = 200.0
const AHEAD_FORWARD_M: float = 2000.0
## Минимальный размах шкалы высот окна «впереди», м (FRD-06 крит. 3 б, `hud.md` п. 8).
const AHEAD_MIN_SPAN_M: float = 40.0
## Поля окна «впереди» сверху и снизу — доля высоты поля (подпись уклона над профилем).
const AHEAD_MARGIN_FRACTION: float = 0.12
## Минимальный размах шкалы высот круга целиком, м: равнина (перепад 12 м) не выглядит горами.
const LAP_MIN_SPAN_M: float = 40.0
## Подвал «до вершины» — только если до вершины не меньше, м (`hud.md` п. 8).
const SUMMIT_MIN_REMAINING_M: float = 300.0
## Подвал «подъём через» — только если подъём ближе, м (`hud.md` п. 8).
const CLIMB_SOON_M: float = 3000.0

const FOOTER_NONE: String = ""
const FOOTER_SUMMIT: String = "summit"
const FOOTER_CLIMB_IN: String = "climb_in"

## Ключи переводов (`assets/i18n/strings_free_ride.csv`).
const KEY_LAP: String = "ui.free_ride.relief.lap"
const KEY_AHEAD: String = "ui.free_ride.relief.ahead"
const KEY_LAP_DISTANCE: String = "ui.free_ride.relief.lap_distance"
const KEY_ASCENT: String = "ui.free_ride.relief.ascent"
const KEY_TO_SUMMIT: String = "ui.free_ride.relief.to_summit"
const KEY_CLIMB_IN: String = "ui.free_ride.relief.climb_in"
const KEY_GRADE_LABEL: String = "ui.free_ride.relief.grade"

var preview: RoutePreviewModel = null
## Ключ названия трассы (`track.<id>.name`).
var name_key: String = ""

var _s: float = 0.0
var _lap_number: int = 1
var _lap_distance: float = 0.0
var _ascent: float = 0.0


func _init(route_preview: RoutePreviewModel = null) -> void:
	preview = route_preview
	if preview != null:
		name_key = preview.name_key


## Модель трассы каталога.
static func for_route(route: RouteCatalog.RouteDef) -> ReliefPanelModel:
	return ReliefPanelModel.new(RoutePreviewModel.for_route(route) if route != null else null)


## Модель трассы сессии с текущей позицией.
static func for_session(session: FreeRideSession) -> ReliefPanelModel:
	var m := ReliefPanelModel.for_route(session.route)
	m.sync(session)
	return m


func is_valid() -> bool:
	return preview != null and preview.is_valid()


func profile() -> RouteProfile:
	return preview.profile if preview != null else null


func length_m() -> float:
	return preview.length_m() if preview != null else 0.0


# ---------------------------------------------------------------------------
# Позиция
# ---------------------------------------------------------------------------

## Позиция на круге `s_m` (берётся по модулю L), номер круга с 1, пройдено на круге и набор за заезд.
func set_position(s_m: float, lap_number: int = 1, lap_distance_m: float = -1.0, ascent_m: float = 0.0) -> void:
	var length: float = length_m()
	_s = fposmod(s_m, length) if length > 0.0 else 0.0
	_lap_number = maxi(lap_number, 1)
	_lap_distance = clampf(lap_distance_m if lap_distance_m >= 0.0 else _s, 0.0, length)
	_ascent = maxf(ascent_m, 0.0)


## Подтянуть позицию из сессии. Возвращает true, если что-то из показываемого изменилось.
func sync(session: FreeRideSession) -> bool:
	var pos: RoutePosition = session.position
	var before: Array = [_s, _lap_number, _lap_distance, _ascent]
	set_position(pos.s_m(), pos.lap_number(), pos.lap_distance_m(), session.ascent_m())
	return before != [_s, _lap_number, _lap_distance, _ascent]


func s_m() -> float:
	return _s


func lap_number() -> int:
	return _lap_number


func lap_distance_m() -> float:
	return _lap_distance


func ascent_m() -> float:
	return _ascent


func height_at(s_m: float) -> float:
	return profile().height_at(s_m) if is_valid() else 0.0


# ---------------------------------------------------------------------------
# Круг целиком
# ---------------------------------------------------------------------------

## Отображение круга [0; L] на поле `field`: шкала Y от минимума до максимума трассы
## (размах не меньше `LAP_MIN_SPAN_M`).
func lap_plot(field: Rect2) -> RoutePreviewModel.Plot:
	if not is_valid():
		return RoutePreviewModel.Plot.new(field, 0.0, 1.0, 0.0, LAP_MIN_SPAN_M)
	var p: RouteProfile = profile()
	var r := RoutePreviewModel.y_range_for(p.min_height_m(), p.max_height_m(), LAP_MIN_SPAN_M)
	return RoutePreviewModel.Plot.new(field, 0.0, length_m(), r.x, r.y)


## Маркер гонщика на профиле круга: x = (s mod L) / L × ширина, y — профиль в s.
func lap_marker(field: Rect2) -> Vector2:
	var p := lap_plot(field)
	return p.point(_s, height_at(_s))


## Пройденная часть круга — отрезки по s (x — начало, y — конец) в пределах [0; L]:
## `lap_distance_m` за маркером; если старт круга за стыком — два отрезка.
func passed_ranges() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var length: float = length_m()
	if length <= 0.0 or _lap_distance <= 0.0:
		return out
	var from: float = _s - _lap_distance
	if from >= 0.0:
		out.append(Vector2(from, _s))
	else:
		out.append(Vector2(length + from, length))
		if _s > 0.0:
			out.append(Vector2(0.0, _s))
	return out


# ---------------------------------------------------------------------------
# Впереди 2 км
# ---------------------------------------------------------------------------

## Участок окна «впереди» по s без оборачивания (x — начало, y — конец).
func ahead_range() -> Vector2:
	return Vector2(_s - AHEAD_BEHIND_M, _s + AHEAD_FORWARD_M)


## Отображение окна [s − 200; s + 2000] на поле: своя шкала, размах ≥ 40 м, поля под подпись.
func ahead_plot(field: Rect2) -> RoutePreviewModel.Plot:
	var r := ahead_range()
	if not is_valid():
		return RoutePreviewModel.Plot.new(field, r.x, r.y, 0.0, AHEAD_MIN_SPAN_M)
	return preview.window_plot(r.x, r.y, field, AHEAD_MIN_SPAN_M, AHEAD_MARGIN_FRACTION)


## Маркер гонщика в окне «впереди»: x = 200 / 2200 × ширина, y — профиль в s.
func ahead_marker(field: Rect2) -> Vector2:
	return ahead_plot(field).point(_s, height_at(_s))


## Самое крутое место подъёма впереди (на (s; s + 2000]): `{s_m, grade_pct, text}`, где s — без
## оборачивания (в координатах окна); пусто, если уклон впереди не больше порога подъёма.
func steepest_ahead() -> Dictionary:
	if not is_valid():
		return {}
	var p: RouteProfile = profile()
	var grades := p.sample_grades()
	var n: int = grades.size()
	var step: float = p.sample_step_m()
	var best_k: int = -1
	var best: float = RouteProfile.CLIMB_MIN_GRADE_PCT
	var k0: int = floori(_s / step) + 1
	var k1: int = floori((_s + AHEAD_FORWARD_M) / step)
	for k in range(k0, k1 + 1):
		var g: float = grades[posmod(k, n)]
		if g > best + 1e-9:
			best = g
			best_k = k
	if best_k < 0:
		return {}
	return {
		"s_m": float(best_k) * step,
		"grade_pct": best,
		"text": format_grade_label(best),
	}


# ---------------------------------------------------------------------------
# Подвал
# ---------------------------------------------------------------------------

## Подвал: `{kind, distance_m, gain_m, text}` — `FOOTER_SUMMIT` (на подъёме, до вершины ≥ 300 м),
## `FOOTER_CLIMB_IN` (не на подъёме, подъём ближе 3 км) или `FOOTER_NONE` (пустой текст).
func footer() -> Dictionary:
	var none := {"kind": FOOTER_NONE, "distance_m": 0.0, "gain_m": 0.0, "text": ""}
	if not is_valid():
		return none
	var length: float = length_m()
	var nearest: float = INF
	for c in profile().climbs():
		var into: float = fposmod(_s - c.start_m, length)
		if into < c.length_m:
			var remaining: float = c.length_m - into
			if remaining < SUMMIT_MIN_REMAINING_M:
				return none
			var gain: float = height_at(c.end_m()) - height_at(_s)
			return {
				"kind": FOOTER_SUMMIT, "distance_m": remaining, "gain_m": gain,
				"text": _tr(KEY_TO_SUMMIT).format({"km": km_value(remaining), "m": "%d" % roundi(maxf(gain, 0.0))}),
			}
		nearest = minf(nearest, fposmod(c.start_m - _s, length))
	if nearest < CLIMB_SOON_M:
		return {
			"kind": FOOTER_CLIMB_IN, "distance_m": nearest, "gain_m": 0.0,
			"text": _tr(KEY_CLIMB_IN).format({"km": km_value(nearest)}),
		}
	return none


# ---------------------------------------------------------------------------
# Тексты
# ---------------------------------------------------------------------------

## Название трассы на языке интерфейса.
func title_text() -> String:
	return _tr(name_key) if not name_key.is_empty() else ""


## «круг 2» / «lap 2».
func lap_text() -> String:
	return _tr(KEY_LAP).format({"n": _lap_number})


## «6.4 / 20.0 км»: пройдено на круге / длина круга, км с одним знаком.
func lap_distance_text() -> String:
	return _tr(KEY_LAP_DISTANCE).format({"lap": km_value(_lap_distance), "length": km_value(length_m())})


## «↑ 612 м»: набор за заезд, целые метры.
func ascent_text() -> String:
	return _tr(KEY_ASCENT).format({"m": "%d" % roundi(_ascent)})


## «ВПЕРЕДИ 2 КМ» (заглавные — при отрисовке).
static func ahead_caption() -> String:
	return _tr(KEY_AHEAD)


## Подпись уклона места впереди: «7.1 %».
static func format_grade_label(grade_pct: float) -> String:
	return _tr(KEY_GRADE_LABEL).format({"value": RoutePreviewModel.grade_value(grade_pct)})


## Километры с одним знаком, точка на обоих языках: 4180 → «4.2».
static func km_value(distance_m: float) -> String:
	return RoutePreviewModel.length_value(distance_m)


static func _tr(key: String) -> String:
	return String(TranslationServer.translate(key))
