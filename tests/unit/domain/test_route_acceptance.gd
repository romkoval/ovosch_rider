extends GutTest
## Приёмка T-062 (tester): профиль трассы и каталог четырёх трасс.
## REQ-D3D-08 крит. 1 (каталог: id, названия и тип на ru/en, профиль, набор окружения),
## крит. 2 (замкнутость профиля и уклона), крит. 3 (характеристики по таблице),
## крит. 11 (данные моста приморья: полотно ≥ 10 м над водой); REQ-FRD-03 крит. 1 (доменная
## часть: тестовый профиль 3.0 км / 50 м / 5.0 %).
##
## Характеристики считаются в тесте независимо от `RouteProfile.ascent_m()/max_grade_pct()/
## climbs()` — по определениям из вводного абзаца D3D-08 поверх h(s) = `height_at`:
## набор — сумма положительных приращений по точкам через ≤ 10 м; уклон — Δh/Δs по окну 100 м
## (скользящее, шаг 5 м); подъём — непрерывный участок с g > 2 % длиной ≥ 300 м.

const IDS: Array[String] = ["flat", "hills", "mountains", "seaside"]
## Названия и типы (D3D-08 крит. 1).
const NAMES: Dictionary = {
	"flat": {"ru": ["Пшеничные поля", "равнина"], "en": ["Wheat Fields", "flatlands"]},
	"hills": {"ru": ["Зелёные холмы", "холмы"], "en": ["Green Hills", "hills"]},
	"mountains": {"ru": ["Перевал", "горы"], "en": ["Mountain Pass", "mountains"]},
	"seaside": {"ru": ["Приморье", "море и мост"], "en": ["Seaside", "sea & bridge"]},
}
## Таблица D3D-08 крит. 3: длина, км; набор, м; макс. уклон, %.
const TABLE: Dictionary = {
	"flat": [10.0, 19.0, 1.0],
	"hills": [15.0, 220.0, 7.5],
	"mountains": [20.0, 441.0, 9.4],
	"seaside": [12.0, 56.0, 4.9],
}
const WINDOW_M: float = 100.0
const GRADE_SCAN_STEP_M: float = 5.0

var _previous_locale: String = ""


func before_each() -> void:
	_previous_locale = TranslationServer.get_locale()


func after_each() -> void:
	TranslationServer.set_locale(_previous_locale)


# ---------------------------------------------------------------------------
# Независимые расчёты по определениям D3D-08
# ---------------------------------------------------------------------------

## Набор по точкам через `step` (≤ 10 м) за круг, включая переход L → 0.
func _ascent(p: RouteProfile, step: float = 10.0) -> float:
	var l: float = p.length_m()
	var n: int = int(ceil(l / step))
	var total: float = 0.0
	var prev: float = p.height_at(0.0)
	for i in range(1, n + 1):
		var h: float = p.height_at(minf(float(i) * l / float(n), l))
		if h > prev:
			total += h - prev
		prev = h
	return total


## g(s), %: окно 100 м с центром в s, через стык круга (h по модулю L — свойство профиля).
func _grade(p: RouteProfile, s: float) -> float:
	return (p.height_at(s + WINDOW_M * 0.5) - p.height_at(s - WINDOW_M * 0.5)) / WINDOW_M * 100.0


func _grade_extremes(p: RouteProfile) -> Vector2:
	var lo: float = INF
	var hi: float = -INF
	var s: float = 0.0
	while s < p.length_m():
		var g: float = _grade(p, s)
		lo = minf(lo, g)
		hi = maxf(hi, g)
		s += GRADE_SCAN_STEP_M
	return Vector2(lo, hi)


## Подъёмы: [начало, длина, средний уклон] — участки g > 2 % ≥ 300 м (шаг 10 м, через стык).
func _climbs(p: RouteProfile) -> Array:
	var step: float = 10.0
	var n: int = int(round(p.length_m() / step))
	var up: Array[bool] = []
	for i in n:
		up.append(_grade(p, float(i) * step) > 2.0)
	var start_i: int = up.find(false)
	if start_i < 0:
		return []
	var out: Array = []
	var run_from: int = -1
	var run_len: int = 0
	for k in range(1, n + 1):
		var i: int = (start_i + k) % n
		if up[i]:
			if run_len == 0:
				run_from = i
			run_len += 1
		elif run_len > 0:
			var length: float = float(run_len) * step
			if length >= 300.0:
				var s0: float = float(run_from) * step
				var gain: float = p.height_at(s0 + length) - p.height_at(s0)
				out.append([s0, length, gain / length * 100.0])
			run_len = 0
	return out


func _route(id: String) -> RouteCatalog.RouteDef:
	return RouteCatalog.get_route(id)


func _linear_points(corners: PackedVector2Array, step: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for c in range(corners.size() - 1):
		var a: Vector2 = corners[c]
		var b: Vector2 = corners[c + 1]
		var steps: int = int(round((b.x - a.x) / step))
		for i in steps:
			pts.append(a.lerp(b, float(i) / float(steps)))
	pts.append(corners[corners.size() - 1])
	return pts


# ---------------------------------------------------------------------------
# D3D-08 крит. 1 — каталог
# ---------------------------------------------------------------------------

func test_req_d3d_08_c1_catalog_has_exactly_four_unique_ids() -> void:
	var ids: Array[String] = RouteCatalog.ids()
	assert_eq(ids, IDS, "ровно четыре трассы в каталоге: %s" % str(ids))
	var all := RouteCatalog.all()
	assert_eq(all.size(), 4)
	var seen: Dictionary = {}
	for r in all:
		assert_false(seen.has(r.id), "id %s уникален" % r.id)
		seen[r.id] = true
		assert_true(RouteCatalog.has_route(r.id))
	assert_null(RouteCatalog.get_route("no_such_route"), "неизвестный id — null")
	assert_null(RouteCatalog.get_route(""), "пустой id — null")


func test_req_d3d_08_c1_names_and_kinds_on_ru_and_en() -> void:
	for id in IDS:
		var r := _route(id)
		for locale in ["ru", "en"]:
			TranslationServer.set_locale(locale)
			var expected: Array = NAMES[id][locale]
			assert_eq(String(TranslationServer.translate(r.name_key)), expected[0], "%s: название (%s)" % [id, locale])
			assert_eq(String(TranslationServer.translate(r.kind_key)), expected[1], "%s: тип (%s)" % [id, locale])


func test_req_d3d_08_c1_each_route_has_valid_profile_and_environment_set() -> void:
	var env_ids: Dictionary = {}
	for id in IDS:
		var r := _route(id)
		assert_not_null(r.profile, "%s: профиль" % id)
		if r.profile == null:
			continue
		assert_true(r.profile.is_valid(), "%s: профиль корректен (%s)" % [id, r.profile.error_code()])
		assert_false(r.environment_set_id.strip_edges().is_empty(), "%s: ссылка на набор окружения" % id)
		env_ids[r.environment_set_id] = true
	assert_eq(env_ids.size(), 4, "у каждой трассы свой набор окружения: %s" % str(env_ids.keys()))


func test_req_d3d_08_c1_returned_route_is_not_shared_mutable_state() -> void:
	var a := _route("hills")
	a.points.set(1, Vector2(600, 9999))
	a.bridges.append(Vector2(1, 2))
	a.landmarks.clear()
	var b := _route("hills")
	assert_eq(b.points[1], Vector2(600, 122), "правка описания вызывающим не портит каталог")
	assert_eq(b.bridges.size(), 0)
	assert_gt(b.landmarks.size(), 0)
	assert_almost_eq(b.profile.height_at(600.0), 122.0, 1e-6, "профиль каталога не изменился")


# ---------------------------------------------------------------------------
# D3D-08 крит. 2 — замкнутость
# ---------------------------------------------------------------------------

func test_req_d3d_08_c2_every_route_closed_height_and_grade_across_seam() -> void:
	for id in IDS:
		var p := _route(id).profile
		var l: float = p.length_m()
		assert_lte(absf(p.height_at(l) - p.height_at(0.0)), 0.1, "%s: |h(L) − h(0)| ≤ 0.1 м" % id)
		assert_lte(absf(p.height_at(l - 0.001) - p.height_at(0.0)), 0.1, "%s: h(L−) → h(0)" % id)
		# Уклон по окну, переходящему через стык: слева и справа от s = 0.
		var g_left: float = _grade(p, l - 0.5)
		var g_right: float = _grade(p, 0.5)
		assert_lte(absf(g_left - g_right), 1.0, "%s: разрыв уклона на стыке %.3f %%" % [id, absf(g_left - g_right)])
		assert_almost_eq(p.grade_at(0.0), _grade(p, 0.0), 1e-6, "%s: grade_at(0) — окно через стык" % id)
		assert_almost_eq(p.grade_at(l), p.grade_at(0.0), 1e-6, "%s: g(L) = g(0)" % id)


func test_req_d3d_08_c2_height_is_continuous_along_loop_and_wraps() -> void:
	for id in IDS:
		var p := _route(id).profile
		var l: float = p.length_m()
		var worst: float = 0.0
		var s: float = 0.0
		while s < l:
			worst = maxf(worst, absf(p.height_at(s + 1.0) - p.height_at(s)))
			s += 1.0
		assert_lte(worst, 0.2, "%s: скачок h за 1 м %.3f м (нет разрывов)" % [id, worst])
		assert_almost_eq(p.height_at(l + 1234.0), p.height_at(1234.0), 1e-6, "%s: s по модулю L" % id)
		assert_almost_eq(p.height_at(-300.0), p.height_at(l - 300.0), 1e-6, "%s: отрицательное s" % id)


# ---------------------------------------------------------------------------
# D3D-08 крит. 3 — характеристики
# ---------------------------------------------------------------------------

func test_req_d3d_08_c3_length_ascent_max_grade_match_table_computed_independently() -> void:
	for id in IDS:
		var p := _route(id).profile
		var row: Array = TABLE[id]
		var ascent: float = _ascent(p)
		var ext := _grade_extremes(p)
		assert_almost_eq(p.length_m() / 1000.0, row[0], 0.1, "%s: длина %.3f км" % [id, p.length_m() / 1000.0])
		assert_almost_eq(ascent, row[1], 5.0, "%s: набор %.1f м (тест)" % [id, ascent])
		assert_almost_eq(ext.y, row[2], 0.3, "%s: макс. уклон %.2f %% (тест)" % [id, ext.y])
		# Функции профиля дают то же, что расчёт по определению.
		assert_almost_eq(p.ascent_m(), ascent, 0.5, "%s: ascent_m() = набор по определению" % id)
		assert_almost_eq(p.max_grade_pct(), ext.y, 0.05, "%s: max_grade_pct() = максимум g(s)" % id)
		assert_almost_eq(p.min_grade_pct(), ext.x, 0.05, "%s: min_grade_pct() = минимум g(s)" % id)


func test_req_d3d_08_c3_hills_has_exactly_four_climbs() -> void:
	var p := _route("hills").profile
	var mine := _climbs(p)
	assert_eq(mine.size(), 4, "холмы: подъёмов по определению %d: %s" % [mine.size(), str(mine)])
	assert_eq(p.climbs().size(), 4, "climbs() холмов")


func test_req_d3d_08_c3_mountains_one_continuous_climb_7km_6pct() -> void:
	var p := _route("mountains").profile
	var mine := _climbs(p)
	assert_eq(mine.size(), 1, "горы: один подъём, найдено %s" % str(mine))
	if mine.size() == 1:
		assert_almost_eq(float(mine[0][1]) / 1000.0, 7.0, 0.2, "длина подъёма %.2f км" % (float(mine[0][1]) / 1000.0))
		assert_almost_eq(float(mine[0][2]), 6.0, 0.3, "средний уклон %.2f %%" % float(mine[0][2]))
	var cs := p.climbs()
	assert_eq(cs.size(), 1, "climbs() гор")
	if cs.size() == 1:
		var c: RouteProfile.Climb = cs[0]
		assert_almost_eq(c.length_m / 1000.0, 7.0, 0.2, "climbs(): длина %.2f км" % (c.length_m / 1000.0))
		assert_almost_eq(c.avg_grade_pct, 6.0, 0.3, "climbs(): средний уклон %.2f %%" % c.avg_grade_pct)


func test_req_d3d_08_c3_seaside_bridge_range_in_data() -> void:
	var r := _route("seaside")
	assert_eq(r.bridges.size(), 1, "у приморья один мост")
	if r.bridges.size() == 1:
		assert_almost_eq(r.bridges[0].x, 5820.0, 10.0, "начало моста")
		assert_almost_eq(r.bridges[0].y, 6330.0, 10.0, "конец моста")
	assert_true(r.is_on_bridge(6000.0))
	assert_true(r.is_on_bridge(6000.0 + r.profile.length_m()), "мост по модулю круга")
	assert_false(r.is_on_bridge(5700.0))
	assert_false(r.is_on_bridge(6400.0))
	for id in ["flat", "hills", "mountains"]:
		assert_eq(_route(id).bridges.size(), 0, "%s: мостов нет" % id)


# ---------------------------------------------------------------------------
# D3D-08 крит. 11 — мост над водой (данные)
# ---------------------------------------------------------------------------

func test_req_d3d_08_c11_seaside_deck_at_least_10m_above_water_over_bridge() -> void:
	var r := _route("seaside")
	assert_true(r.has_water(), "у приморья есть уровень воды")
	assert_eq(r.bridges.size(), 1)
	if r.bridges.size() != 1 or not r.has_water():
		return
	var lowest: float = INF
	var s: float = r.bridges[0].x
	while s <= r.bridges[0].y:
		lowest = minf(lowest, r.profile.height_at(s) - r.water_level_m)
		s += 5.0
	assert_gte(lowest, 10.0, "полотно над водой не меньше 10 м на всём мосту (min %.2f м)" % lowest)


# ---------------------------------------------------------------------------
# FRD-03 крит. 1 — тестовый профиль (доменная часть)
# ---------------------------------------------------------------------------

func test_req_frd_03_c1_reference_profile_3km_50m_5pct_points_every_10m() -> void:
	var corners := PackedVector2Array([Vector2(0, 0), Vector2(1000, 0), Vector2(2000, 50), Vector2(3000, 0)])
	for step in [10.0, 5.0]:
		var p := RouteProfile.from_points(_linear_points(corners, step))
		assert_true(p.is_valid(), p.error_code())
		assert_almost_eq(p.length_m() / 1000.0, 3.0, 0.05, "шаг %.0f м: длина 3.0 км" % step)
		assert_almost_eq(p.ascent_m(), 50.0, 0.5, "шаг %.0f м: набор 50 м" % step)
		assert_almost_eq(p.max_grade_pct(), 5.0, 0.1, "шаг %.0f м: макс. уклон %.2f %%" % [step, p.max_grade_pct()])
		assert_almost_eq(_ascent(p), 50.0, 0.5, "независимый набор")
		assert_almost_eq(_grade_extremes(p).y, 5.0, 0.1, "независимый макс. уклон")


func test_req_frd_03_c1_climb_is_reported_once_on_reference_profile() -> void:
	var corners := PackedVector2Array([Vector2(0, 0), Vector2(1000, 0), Vector2(2000, 50), Vector2(3000, 0)])
	var p := RouteProfile.from_points(_linear_points(corners, 10.0))
	var cs := p.climbs()
	assert_eq(cs.size(), 1, "подъём 1000 м × 5 %% — один")
	if cs.size() == 1:
		assert_almost_eq(cs[0].avg_grade_pct, 5.0, 0.3)
		assert_almost_eq(cs[0].length_m, 1000.0, 100.0)


# ---------------------------------------------------------------------------
# Границы входа
# ---------------------------------------------------------------------------

func test_req_d3d_08_c2_invalid_profiles_rejected_with_code() -> void:
	var cases: Dictionary = {
		"не замкнут": PackedVector2Array([Vector2(0, 0), Vector2(500, 10), Vector2(1000, 3)]),
		"s не с нуля": PackedVector2Array([Vector2(10, 0), Vector2(500, 10), Vector2(1000, 0)]),
		"s убывает": PackedVector2Array([Vector2(0, 0), Vector2(500, 10), Vector2(400, 5), Vector2(1000, 0)]),
		"две точки": PackedVector2Array([Vector2(0, 0), Vector2(1000, 0)]),
		"NaN": PackedVector2Array([Vector2(0, 0), Vector2(500, NAN), Vector2(1000, 0)]),
	}
	for label in cases:
		var p := RouteProfile.from_points(cases[label])
		assert_false(p.is_valid(), "%s: профиль некорректен" % label)
		assert_ne(p.error_code(), "", "%s: код ошибки" % label)
		assert_eq(p.height_at(100.0), 0.0, "%s: h = 0 без ошибок" % label)
		assert_eq(p.climbs().size(), 0)
