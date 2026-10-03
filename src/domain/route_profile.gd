class_name RouteProfile
extends RefCounted
## Профиль высот замкнутой трассы h(s) и его характеристики (REQ-D3D-08 крит. 1–3,
## основа REQ-FRD-03 крит. 1; `docs/game/tracks.md` п. 2).
##
## Вход — опорные точки (s, h) в метрах: первая на s = 0, последняя на s = L с той же
## высотой (круг замкнут). Между опорными точками — периодическая монотонная кубика
## PCHIP (касательные Фрича–Карлсона в форме взвешенного гармонического среднего,
## как в `pchip` Моулера / SciPy `PchipInterpolator`): на экстремумах и ровных участках
## касательная нулевая, выбросов над опорными точками нет. Касательная на стыке круга
## считается по соседям через стык, поэтому профиль и его производная непрерывны на L → 0.
##
## При построении профиль выбирается с шагом не больше 10 м (`SAMPLE_STEP_M`; при L,
## кратной 10 м, — ровно 10 м). Характеристики считаются по выборке так, как в D3D-08:
## - набор — сумма положительных приращений h между соседними точками за круг
##   (включая переход последней точки в s = L ≡ 0);
## - уклон g(s) = (h(s + 50) − h(s − 50)) / 100 м, в % — окно 100 м с центром в s,
##   переходящее через стык круга;
## - макс./мин. уклон — экстремумы g по точкам выборки;
## - подъём — непрерывный участок точек выборки с g > 2 % длиной ≥ 300 м (участок,
##   проходящий через стык, — один подъём).
##
## Объект неизменяем после построения. Некорректный вход даёт профиль с
## `is_valid() == false` и кодом `error_code()`; характеристики у него нулевые.

## Шаг выборки, м (D3D-08: точки профиля не реже чем через 10 м).
const SAMPLE_STEP_M: float = 10.0
## Ширина окна уклона, м (D3D-08).
const GRADE_WINDOW_M: float = 100.0
## Подъём — уклон строго больше этого порога, % (D3D-08).
const CLIMB_MIN_GRADE_PCT: float = 2.0
## Минимальная длина подъёма, м (D3D-08).
const CLIMB_MIN_LENGTH_M: float = 300.0
## Допуск совпадения высоты первой и последней опорной точки, м.
const CLOSURE_EPS_M: float = 1e-6

const ERR_NONE: String = ""
const ERR_TOO_FEW_POINTS: String = "ERR_TOO_FEW_POINTS"
const ERR_START_NOT_ZERO: String = "ERR_START_NOT_ZERO"
const ERR_NOT_INCREASING: String = "ERR_NOT_INCREASING"
const ERR_NOT_CLOSED: String = "ERR_NOT_CLOSED"
const ERR_NOT_FINITE: String = "ERR_NOT_FINITE"


## Подъём на профиле (D3D-08): участок с уклоном > 2 % длиной ≥ 300 м.
class Climb:
	extends RefCounted
	## Начало участка по s, м (в пределах [0; L)).
	var start_m: float = 0.0
	## Длина участка, м.
	var length_m: float = 0.0
	## Разность высот конца и начала участка, м.
	var gain_m: float = 0.0
	## Средний уклон участка = gain_m / length_m, %.
	var avg_grade_pct: float = 0.0

	## Конец участка по s без оборачивания (может быть больше L для подъёма через стык).
	func end_m() -> float:
		return start_m + length_m


var _error: String = ERR_NONE
var _length: float = 0.0
var _knot_s: PackedFloat64Array = PackedFloat64Array()
var _knot_h: PackedFloat64Array = PackedFloat64Array()
## Касательные dh/ds в опорных точках 0..n-1 (точка n совпадает с точкой 0).
var _tangent: PackedFloat64Array = PackedFloat64Array()
var _step: float = SAMPLE_STEP_M
var _heights: PackedFloat64Array = PackedFloat64Array()
var _grades: PackedFloat64Array = PackedFloat64Array()
var _ascent: float = 0.0
var _max_grade: float = 0.0
var _min_grade: float = 0.0
var _min_h: float = 0.0
var _max_h: float = 0.0
var _climbs: Array[Climb] = []


## Построить профиль по опорным точкам (x — s, м; y — h, м).
static func from_points(points: PackedVector2Array) -> RouteProfile:
	var s := PackedFloat64Array()
	var h := PackedFloat64Array()
	for p in points:
		s.append(p.x)
		h.append(p.y)
	return from_arrays(s, h)


## Построить профиль по массивам s (м) и h (м) одинаковой длины.
static func from_arrays(s_m: PackedFloat64Array, h_m: PackedFloat64Array) -> RouteProfile:
	var profile := RouteProfile.new()
	profile._build(s_m, h_m)
	return profile


func is_valid() -> bool:
	return _error == ERR_NONE


## Код ошибки входа (`ERR_*`) или пустая строка.
func error_code() -> String:
	return _error


## Длина круга L, м.
func length_m() -> float:
	return _length


## Набор высоты за круг, м.
func ascent_m() -> float:
	return _ascent


## Максимальный уклон за круг, %.
func max_grade_pct() -> float:
	return _max_grade


## Минимальный (самый крутой спуск) уклон за круг, %.
func min_grade_pct() -> float:
	return _min_grade


func min_height_m() -> float:
	return _min_h


func max_height_m() -> float:
	return _max_h


## Подъёмы круга в порядке s (копия списка; объекты `Climb` не менять).
func climbs() -> Array[Climb]:
	return _climbs.duplicate()


## Высота h(s), м; s берётся по модулю L (s = L и s = 0 дают одно значение).
func height_at(s_m: float) -> float:
	if not is_valid():
		return 0.0
	var s: float = fposmod(s_m, _length)
	var n: int = _knot_s.size() - 1
	var i: int = clampi(_knot_s.bsearch(s, false) - 1, 0, n - 1)
	var x0: float = _knot_s[i]
	var dx: float = _knot_s[i + 1] - x0
	var t: float = (s - x0) / dx
	var t2: float = t * t
	var t3: float = t2 * t
	var m0: float = _tangent[i]
	var m1: float = _tangent[(i + 1) % n]
	return (2.0 * t3 - 3.0 * t2 + 1.0) * _knot_h[i] \
		+ (t3 - 2.0 * t2 + t) * dx * m0 \
		+ (-2.0 * t3 + 3.0 * t2) * _knot_h[i + 1] \
		+ (t3 - t2) * dx * m1


## Уклон g(s), %: Δh/Δs по окну 100 м с центром в s; окно переходит через стык круга.
func grade_at(s_m: float) -> float:
	if not is_valid():
		return 0.0
	var half: float = GRADE_WINDOW_M * 0.5
	return (height_at(s_m + half) - height_at(s_m - half)) / GRADE_WINDOW_M * 100.0


## Шаг выборки, м (≤ `SAMPLE_STEP_M`; ровно 10 м при L, кратной 10 м).
func sample_step_m() -> float:
	return _step


## Число точек выборки за круг (точка s = L не входит: она совпадает с s = 0).
func sample_count() -> int:
	return _heights.size()


## Высоты выборки, м: i-я точка — s = i · `sample_step_m()` (копия).
func sample_heights() -> PackedFloat64Array:
	return _heights.duplicate()


## Уклоны в точках выборки, % (копия).
func sample_grades() -> PackedFloat64Array:
	return _grades.duplicate()


## Опорные точки (s, h), м (копия).
func knots() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in _knot_s.size():
		out.append(Vector2(_knot_s[i], _knot_h[i]))
	return out


func _build(s_m: PackedFloat64Array, h_m: PackedFloat64Array) -> void:
	_error = _validate(s_m, h_m)
	if _error != ERR_NONE:
		return
	_knot_s = s_m.duplicate()
	_knot_h = h_m.duplicate()
	_knot_h[_knot_h.size() - 1] = _knot_h[0]
	_length = _knot_s[_knot_s.size() - 1]
	_tangent = _periodic_pchip_tangents(_knot_s, _knot_h)
	_sample()
	_find_climbs()


static func _validate(s_m: PackedFloat64Array, h_m: PackedFloat64Array) -> String:
	if s_m.size() != h_m.size() or s_m.size() < 3:
		return ERR_TOO_FEW_POINTS
	for i in s_m.size():
		if not is_finite(s_m[i]) or not is_finite(h_m[i]):
			return ERR_NOT_FINITE
	if absf(s_m[0]) > 1e-9:
		return ERR_START_NOT_ZERO
	for i in range(1, s_m.size()):
		if s_m[i] <= s_m[i - 1]:
			return ERR_NOT_INCREASING
	if absf(h_m[h_m.size() - 1] - h_m[0]) > CLOSURE_EPS_M:
		return ERR_NOT_CLOSED
	return ERR_NONE


## Касательные периодической PCHIP: в точке k — взвешенное гармоническое среднее
## наклонов соседних отрезков (веса по длинам отрезков), 0 при смене знака или
## ровном отрезке. Для k = 0 предыдущий отрезок — последний (через стык).
static func _periodic_pchip_tangents(xs: PackedFloat64Array, ys: PackedFloat64Array) -> PackedFloat64Array:
	var n: int = xs.size() - 1
	var widths := PackedFloat64Array()
	var slopes := PackedFloat64Array()
	widths.resize(n)
	slopes.resize(n)
	for i in n:
		widths[i] = xs[i + 1] - xs[i]
		slopes[i] = (ys[i + 1] - ys[i]) / widths[i]
	var out := PackedFloat64Array()
	out.resize(n)
	for k in n:
		var prev: int = (k - 1 + n) % n
		var d_prev: float = slopes[prev]
		var d_next: float = slopes[k]
		if d_prev * d_next <= 0.0:
			out[k] = 0.0
			continue
		var w1: float = 2.0 * widths[k] + widths[prev]
		var w2: float = widths[k] + 2.0 * widths[prev]
		out[k] = (w1 + w2) / (w1 / d_prev + w2 / d_next)
	return out


func _sample() -> void:
	var count: int = maxi(ceili(_length / SAMPLE_STEP_M - 1e-9), 1)
	_step = _length / float(count)
	_heights.resize(count)
	_grades.resize(count)
	for i in count:
		var s: float = float(i) * _step
		_heights[i] = height_at(s)
		_grades[i] = grade_at(s)
	_ascent = 0.0
	_min_h = _heights[0]
	_max_h = _heights[0]
	_max_grade = _grades[0]
	_min_grade = _grades[0]
	for i in count:
		var h: float = _heights[i]
		var dh: float = _heights[(i + 1) % count] - h
		if dh > 0.0:
			_ascent += dh
		_min_h = minf(_min_h, h)
		_max_h = maxf(_max_h, h)
		_max_grade = maxf(_max_grade, _grades[i])
		_min_grade = minf(_min_grade, _grades[i])


func _find_climbs() -> void:
	_climbs.clear()
	var count: int = _grades.size()
	# Начинаем обход с точки вне подъёма, чтобы подъём через стык не разрезался на два.
	var first_flat: int = -1
	for i in count:
		if _grades[i] <= CLIMB_MIN_GRADE_PCT:
			first_flat = i
			break
	if first_flat < 0:
		return
	var run_start: int = -1
	var run_len: int = 0
	for j in range(1, count + 1):
		var idx: int = (first_flat + j) % count
		var climbing: bool = _grades[idx] > CLIMB_MIN_GRADE_PCT
		if climbing:
			if run_len == 0:
				run_start = idx
			run_len += 1
		elif run_len > 0:
			_add_climb(run_start, run_len)
			run_len = 0
	_climbs.sort_custom(_climb_before)


func _add_climb(start_idx: int, sample_len: int) -> void:
	var length: float = float(sample_len) * _step
	if length < CLIMB_MIN_LENGTH_M - 1e-6:
		return
	var count: int = _heights.size()
	var climb := Climb.new()
	climb.start_m = float(start_idx) * _step
	climb.length_m = length
	climb.gain_m = _heights[(start_idx + sample_len) % count] - _heights[start_idx]
	climb.avg_grade_pct = climb.gain_m / length * 100.0
	_climbs.append(climb)


static func _climb_before(a: Climb, b: Climb) -> bool:
	return a.start_m < b.start_m
