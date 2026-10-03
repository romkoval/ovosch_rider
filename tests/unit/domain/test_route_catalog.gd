extends GutTest
## Тесты каталога трасс RouteCatalog (REQ-D3D-08 крит. 1–3, 11 — данные моста;
## REQ-FRD-02 крит. 3 — трасса по умолчанию; таблица `docs/game/tracks.md` п. 3).

## Таблица `tracks.md` п. 3: длина, км; набор, м; макс. и мин. уклон, %; высоты, м.
const TABLE: Dictionary = {
	"flat": {"km": 10.0, "ascent": 19.0, "max": 1.0, "min": -0.7, "h": Vector2(36, 48),
		"mood": Color(0.93, 0.80, 0.45)},
	"hills": {"km": 15.0, "ascent": 220.0, "max": 7.5, "min": -7.5, "h": Vector2(120, 218),
		"mood": Color(0.45, 0.68, 0.35)},
	"mountains": {"km": 20.0, "ascent": 441.0, "max": 9.4, "min": -7.7, "h": Vector2(300, 738),
		"mood": Color(0.55, 0.62, 0.78)},
	"seaside": {"km": 12.0, "ascent": 56.0, "max": 4.9, "min": -3.4, "h": Vector2(7, 52),
		"mood": Color(0.25, 0.70, 0.78)},
}


func test_exactly_four_unique_routes() -> void:
	var ids := RouteCatalog.ids()
	assert_eq(ids, ["flat", "hills", "mountains", "seaside"] as Array[String])
	var seen: Dictionary = {}
	for r in RouteCatalog.all():
		assert_false(seen.has(r.id), "id %s уникален" % r.id)
		seen[r.id] = true
	assert_eq(seen.size(), 4)
	assert_null(RouteCatalog.get_route("moon"))
	assert_false(RouteCatalog.has_route("moon"))


func test_default_route_is_flat() -> void:
	assert_eq(RouteCatalog.DEFAULT_ID, "flat")
	assert_eq(RouteCatalog.default_route().id, "flat")
	assert_eq(RouteCatalog.resolve_id("hills"), "hills")
	assert_eq(RouteCatalog.resolve_id(""), "flat")
	assert_eq(RouteCatalog.resolve_id("deleted"), "flat")


func test_localization_keys_and_environment_ids() -> void:
	var env_ids: Dictionary = {}
	for r in RouteCatalog.all():
		assert_eq(r.name_key, "track.%s.name" % r.id)
		assert_eq(r.kind_key, "track.%s.kind" % r.id)
		assert_ne(r.environment_set_id, "", "у %s есть набор окружения" % r.id)
		env_ids[r.environment_set_id] = true
	assert_eq(env_ids.size(), 4, "у каждой трассы свой набор окружения")


func test_profiles_are_closed() -> void:
	for r in RouteCatalog.all():
		var p := r.profile
		assert_true(p.is_valid(), "%s: %s" % [r.id, p.error_code()])
		var l: float = p.length_m()
		assert_true(absf(p.height_at(l - 0.001) - p.height_at(0.0)) <= 0.1, "%s: |h(L) − h(0)| ≤ 0.1 м" % r.id)
		assert_true(absf(p.grade_at(l - 0.5) - p.grade_at(0.5)) <= 1.0, "%s: разрыв уклона на стыке ≤ 1 %%" % r.id)
		var gs := p.sample_grades()
		assert_true(absf(gs[gs.size() - 1] - gs[0]) <= 1.0, "%s: уклон последней и первой точек выборки" % r.id)
		assert_eq(r.points[0].x, 0.0)
		assert_eq(r.points[0].y, r.points[r.points.size() - 1].y, "%s: первая и последняя опорные точки совпадают" % r.id)


func test_characteristics_match_tracks_table() -> void:
	for r in RouteCatalog.all():
		var row: Dictionary = TABLE[r.id]
		var p := r.profile
		assert_almost_eq(p.length_m() / 1000.0, float(row["km"]), 0.1, "%s: длина" % r.id)
		assert_almost_eq(p.ascent_m(), float(row["ascent"]), 5.0, "%s: набор" % r.id)
		assert_almost_eq(p.max_grade_pct(), float(row["max"]), 0.3, "%s: макс. уклон" % r.id)
		assert_almost_eq(p.min_grade_pct(), float(row["min"]), 0.3, "%s: мин. уклон" % r.id)
		var h: Vector2 = row["h"]
		assert_almost_eq(p.min_height_m(), h.x, 1.0, "%s: мин. высота" % r.id)
		assert_almost_eq(p.max_height_m(), h.y, 1.0, "%s: макс. высота" % r.id)
		assert_true(p.sample_step_m() <= 10.0, "%s: точки не реже 10 м" % r.id)


func test_characteristics_within_d3d08_ranges() -> void:
	var flat := RouteCatalog.get_route("flat").profile
	assert_true(flat.ascent_m() <= 60.0, "равнина: набор ≤ 60 м")
	assert_true(flat.max_grade_pct() <= 2.0, "равнина: уклон ≤ 2 %")
	var hills := RouteCatalog.get_route("hills").profile
	assert_between(hills.ascent_m(), 150.0, 350.0, "холмы: набор 150–350 м")
	assert_between(hills.max_grade_pct(), 4.0, 8.0, "холмы: макс. уклон 4–8 %")
	assert_eq(hills.climbs().size(), 4, "холмы: ровно четыре подъёма")
	var mountains := RouteCatalog.get_route("mountains").profile
	assert_true(mountains.ascent_m() >= 400.0, "горы: набор ≥ 400 м")
	assert_true(mountains.max_grade_pct() <= 12.0, "горы: уклон ≤ 12 %")
	var seaside := RouteCatalog.get_route("seaside").profile
	assert_between(seaside.length_m(), 8000.0, 15000.0, "приморье: длина 8–15 км")
	assert_true(seaside.ascent_m() <= 150.0, "приморье: набор ≤ 150 м")
	assert_true(seaside.max_grade_pct() <= 6.0, "приморье: уклон ≤ 6 %")


func test_mountains_single_long_climb() -> void:
	var climbs := RouteCatalog.get_route("mountains").profile.climbs()
	assert_eq(climbs.size(), 1, "горы: один непрерывный подъём")
	if climbs.is_empty():
		return
	var c: RouteProfile.Climb = climbs[0]
	assert_almost_eq(c.length_m / 1000.0, 7.0, 0.2, "длина подъёма 7.0 ± 0.2 км")
	assert_almost_eq(c.avg_grade_pct, 6.0, 0.3, "средний уклон 6.0 ± 0.3 %")
	assert_almost_eq(c.start_m / 1000.0, 3.03, 0.05, "начало ≈ 3.03 км (tracks.md п. 4.3)")
	assert_almost_eq(c.gain_m, 420.0, 5.0, "набор подъёма ≈ +420 м")


func test_hills_climbs_match_tracks_table() -> void:
	# tracks.md п. 4.2: начало, км; длина, км; набор, м; средний уклон, %.
	var expected: Array = [
		[0.67, 0.75, 36.0, 4.8], [3.70, 1.17, 66.0, 5.7],
		[7.27, 0.67, 35.0, 5.2], [10.41, 1.59, 68.0, 4.3],
	]
	var climbs := RouteCatalog.get_route("hills").profile.climbs()
	assert_eq(climbs.size(), expected.size())
	for i in mini(climbs.size(), expected.size()):
		var c: RouteProfile.Climb = climbs[i]
		var e: Array = expected[i]
		assert_almost_eq(c.start_m / 1000.0, float(e[0]), 0.02, "подъём %d: начало" % (i + 1))
		assert_almost_eq(c.length_m / 1000.0, float(e[1]), 0.02, "подъём %d: длина" % (i + 1))
		assert_almost_eq(c.gain_m, float(e[2]), 1.5, "подъём %d: набор" % (i + 1))
		assert_almost_eq(c.avg_grade_pct, float(e[3]), 0.1, "подъём %d: средний уклон" % (i + 1))


func test_seaside_climb_to_cape() -> void:
	var climbs := RouteCatalog.get_route("seaside").profile.climbs()
	assert_eq(climbs.size(), 1, "приморье: один подъём на мыс")
	if climbs.is_empty():
		return
	var c: RouteProfile.Climb = climbs[0]
	assert_almost_eq(c.start_m / 1000.0, 7.16, 0.02)
	assert_almost_eq(c.length_m / 1000.0, 1.02, 0.02)
	assert_almost_eq(c.avg_grade_pct, 3.7, 0.1)


func test_seaside_bridge_above_water() -> void:
	var r := RouteCatalog.get_route("seaside")
	assert_true(r.has_water(), "у приморья есть вода")
	assert_eq(r.bridges.size(), 1, "один мост")
	if r.bridges.is_empty():
		return
	var b: Vector2 = r.bridges[0]
	assert_almost_eq(b.x, 5820.0, 10.0, "начало моста 5820 ± 10 м")
	assert_almost_eq(b.y, 6330.0, 10.0, "конец моста 6330 ± 10 м")
	var s: float = b.x
	while s <= b.y:
		assert_true(r.profile.height_at(s) - r.water_level_m >= 10.0,
			"полотно на мосту (s = %.0f) выше воды не меньше чем на 10 м" % s)
		s += 10.0
	assert_true(r.is_on_bridge(6000.0))
	assert_true(r.is_on_bridge(6000.0 + r.profile.length_m()), "по модулю круга")
	assert_false(r.is_on_bridge(5000.0))


func test_only_seaside_has_bridge_and_water() -> void:
	for r in RouteCatalog.all():
		if r.id == "seaside":
			continue
		assert_eq(r.bridges.size(), 0, "%s без моста" % r.id)
		assert_false(r.has_water(), "%s без воды" % r.id)


func test_landmarks_layout_mood() -> void:
	var seeds: Dictionary = {}
	for r in RouteCatalog.all():
		var row: Dictionary = TABLE[r.id]
		assert_eq(r.mood_color, row["mood"], "%s: цвет настроения из таблицы" % r.id)
		assert_false(r.landmarks.is_empty(), "%s: ориентиры в данных" % r.id)
		var prev: float = -1.0
		for lm in r.landmarks:
			assert_true(lm.s_m >= prev, "%s: ориентиры по возрастанию s" % r.id)
			assert_true(lm.s_m >= 0.0 and lm.s_m < r.profile.length_m(), "%s: ориентир в пределах круга" % r.id)
			assert_ne(lm.type, "")
			prev = lm.s_m
		assert_true(r.layout.has("shape"), "%s: layout.shape" % r.id)
		assert_true(r.layout.has("control_points"), "%s: layout.control_points" % r.id)
		assert_true(r.layout.has("min_radius_m"), "%s: layout.min_radius_m" % r.id)
		seeds[r.seed] = true
	assert_eq(seeds.size(), 4, "seed план-схем различны")


func test_returned_defs_do_not_share_mutable_state() -> void:
	var a := RouteCatalog.get_route("seaside")
	a.bridges.clear()
	a.landmarks.clear()
	a.layout.clear()
	var b := RouteCatalog.get_route("seaside")
	assert_eq(b.bridges.size(), 1)
	assert_false(b.landmarks.is_empty())
	assert_false(b.layout.is_empty())
	assert_same(a.profile, b.profile, "профиль кэшируется")
