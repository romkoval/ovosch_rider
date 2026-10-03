extends GutTest
## Позиция на трассе (REQ-FRD-04 крит. 2 — s как интеграл скорости по модулю L,
## REQ-FRD-07 крит. 1 — без лимита, монотонная дистанция, стык круга; крит. 4 — набор).

const WEIGHT_KG: float = 75.0


func _triangle() -> RouteProfile:
	# Круг 3 км: подъём 50 м на первом километре, спуск обратно на остальных двух.
	return RouteProfile.from_points(PackedVector2Array([
		Vector2(0, 100), Vector2(1000, 150), Vector2(3000, 100),
	]))


func test_starts_at_zero() -> void:
	var pos := RoutePosition.new(_triangle())
	assert_eq(pos.s_m(), 0.0)
	assert_eq(pos.distance_m(), 0.0)
	assert_eq(pos.laps_completed(), 0)
	assert_eq(pos.lap_number(), 1)
	assert_eq(pos.ascent_m(), 0.0)
	assert_almost_eq(pos.height_m(), 100.0, 1e-6)
	assert_almost_eq(pos.length_m(), 3000.0, 1e-9)


func test_position_is_integral_of_speed() -> void:
	var pos := RoutePosition.new(_triangle())
	# 36 км/ч = 10 м/с.
	assert_almost_eq(pos.advance(36.0, 1.0), 10.0, 1e-9)
	assert_almost_eq(pos.s_m(), 10.0, 1e-9)
	pos.advance(18.0, 2.0)
	assert_almost_eq(pos.s_m(), 20.0, 1e-9)
	assert_almost_eq(pos.distance_m(), 20.0, 1e-9)
	var expected: float = 20.0
	var speeds: Array[float] = [12.5, 30.0, 47.3, 0.0, 22.2]
	for i in 500:
		var v: float = speeds[i % speeds.size()]
		pos.advance(v, 0.5)
		expected += v / 3.6 * 0.5
	assert_almost_eq(pos.distance_m(), expected, 1e-6, "дистанция = ∑ v·dt")
	assert_almost_eq(pos.s_m(), fposmod(expected, 3000.0), 1e-6, "s = дистанция mod L")


func test_height_and_grade_come_from_profile_without_scaling() -> void:
	var profile := _triangle()
	var pos := RoutePosition.new(profile)
	pos.advance(36.0, 50.0)  # 500 м — середина подъёма
	assert_almost_eq(pos.height_m(), profile.height_at(500.0), 1e-9)
	assert_almost_eq(pos.grade_pct(), profile.grade_at(500.0), 1e-9, "полный уклон g(s), FRD-04 крит. 8")
	assert_gt(pos.grade_pct(), 2.0)


func test_wraps_modulo_length_and_counts_laps() -> void:
	var pos := RoutePosition.new(_triangle())
	pos.advance(36.0, 290.0)  # 2900 м
	assert_eq(pos.laps_completed(), 0)
	pos.advance(36.0, 20.0)  # 3100 м
	assert_almost_eq(pos.s_m(), 100.0, 1e-6)
	assert_eq(pos.laps_completed(), 1)
	assert_eq(pos.lap_number(), 2)
	assert_almost_eq(pos.lap_distance_m(), 100.0, 1e-6)
	assert_almost_eq(pos.distance_m(), 3100.0, 1e-6, "дистанция не оборачивается")
	pos.advance(36.0, 600.0)  # +6000 м
	assert_eq(pos.laps_completed(), 3)
	assert_almost_eq(pos.s_m(), 100.0, 1e-6)


func test_start_offset() -> void:
	var pos := RoutePosition.new(_triangle(), 2950.0)
	assert_almost_eq(pos.s_m(), 2950.0, 1e-9)
	assert_almost_eq(pos.start_s_m(), 2950.0, 1e-9)
	pos.advance(36.0, 10.0)
	assert_almost_eq(pos.s_m(), 50.0, 1e-6)
	assert_almost_eq(pos.distance_m(), 100.0, 1e-6)
	assert_eq(pos.laps_completed(), 0, "круги — по дистанции от старта")
	pos.reset(-100.0)
	assert_almost_eq(pos.s_m(), 2900.0, 1e-9, "старт берётся по модулю L")
	assert_almost_eq(pos.start_s_m(), 2900.0, 1e-9)
	assert_eq(pos.distance_m(), 0.0)


func test_non_positive_or_invalid_input_does_not_move() -> void:
	var pos := RoutePosition.new(_triangle())
	pos.advance(36.0, 10.0)
	assert_eq(pos.advance(-20.0, 1.0), 0.0)
	assert_eq(pos.advance(20.0, -1.0), 0.0)
	assert_eq(pos.advance(20.0, 0.0), 0.0)
	assert_eq(pos.advance(NAN, 1.0), 0.0)
	assert_eq(pos.advance(INF, 1.0), 0.0)
	assert_almost_eq(pos.distance_m(), 100.0, 1e-9)


func test_height_continuous_across_seam() -> void:
	var pos := RoutePosition.new(_triangle(), 2999.95)
	var before := pos.height_m()
	pos.advance(3.6, 0.1)  # 0.1 м через стык
	assert_lt(pos.s_m(), 1.0)
	assert_eq(pos.laps_completed(), 0)
	assert_almost_eq(pos.height_m(), before, 0.1, "стык круга без скачка высоты")


func test_ascent_sums_positive_increments_per_advance() -> void:
	var profile := _triangle()
	var pos := RoutePosition.new(profile)
	var expected: float = 0.0
	var prev_h := pos.height_m()
	for i in 450:  # 4500 м шагами по 10 м
		pos.advance(36.0, 1.0)
		var h := profile.height_at(pos.s_m())
		if h > prev_h:
			expected += h - prev_h
		prev_h = h
	assert_almost_eq(pos.ascent_m(), expected, 1e-6)
	pos.advance(0.0, 1.0)
	assert_almost_eq(pos.ascent_m(), expected, 1e-9, "стоянка набор не меняет")
	pos.reset()
	assert_eq(pos.ascent_m(), 0.0)


func test_ascent_over_full_laps_matches_route_ascent() -> void:
	# FRD-07 крит. 4: N полных кругов → N × набор трассы ± 5 % (шаг ~ сэмпл 1 Гц на 30 км/ч).
	for route_id in RouteCatalog.ids():
		var profile: RouteProfile = RouteCatalog.get_route(route_id).profile
		var pos := RoutePosition.new(profile)
		var laps: int = 3
		var total: float = profile.length_m() * laps
		var step_m: float = 30.0 / 3.6
		while pos.distance_m() + step_m <= total:
			pos.advance(30.0, 1.0)
		pos.advance((total - pos.distance_m()) * 3.6, 1.0)
		assert_almost_eq(pos.distance_m(), total, 1e-6)
		var expected: float = profile.ascent_m() * laps
		assert_almost_eq(pos.ascent_m(), expected, expected * 0.05, "набор за %d круга на %s" % [laps, route_id])


func test_four_hours_at_250w_on_flat() -> void:
	# FRD-07 крит. 1: 4 ч при 250 Вт на «равнине» — дистанция монотонна и > 10 L,
	# s оборачивается по модулю L, на стыке высота не прыгает больше 0.1 м сверх уклона шага.
	var profile: RouteProfile = RouteCatalog.get_route(RouteCatalog.FLAT).profile
	var length: float = profile.length_m()
	var max_abs_grade: float = maxf(absf(profile.max_grade_pct()), absf(profile.min_grade_pct()))
	var pos := RoutePosition.new(profile)
	var model := SpeedModel.new()
	var prev_distance: float = 0.0
	var prev_laps: int = 0
	var wraps: int = 0
	var monotonic: bool = true
	var in_range: bool = true
	var worst_seam_excess: float = 0.0
	for t in 4 * 3600:
		var v := model.step(250.0, WEIGHT_KG, 1.0, pos.grade_pct())
		var h_before := pos.height_m()
		var moved := pos.advance(v, 1.0)
		if pos.distance_m() < prev_distance:
			monotonic = false
		if pos.s_m() < 0.0 or pos.s_m() >= length:
			in_range = false
		if pos.laps_completed() != prev_laps:
			wraps += 1
			var allowed: float = max_abs_grade / 100.0 * moved
			worst_seam_excess = maxf(worst_seam_excess, absf(pos.height_m() - h_before) - allowed)
			prev_laps = pos.laps_completed()
		prev_distance = pos.distance_m()
	assert_true(monotonic, "дистанция растёт монотонно")
	assert_true(in_range, "s ∈ [0; L)")
	assert_gt(pos.distance_m(), 10.0 * length, "дистанция > 10 L, факт %.0f м" % pos.distance_m())
	assert_eq(wraps, pos.laps_completed(), "каждый круг пройден через стык")
	assert_true(worst_seam_excess <= 0.1, "скачок высоты на стыке ≤ 0.1 м (превышение %.3f)" % worst_seam_excess)
	assert_almost_eq(profile.height_at(length - 1e-3), profile.height_at(1e-3), 0.1, "h непрерывна в L → 0")
	assert_almost_eq(pos.s_m(), fposmod(pos.distance_m(), length), 1e-6)


func test_without_profile_accumulates_distance_only() -> void:
	var pos := RoutePosition.new(null)
	pos.advance(36.0, 10.0)
	assert_almost_eq(pos.distance_m(), 100.0, 1e-9)
	assert_eq(pos.s_m(), 0.0)
	assert_eq(pos.height_m(), 0.0)
	assert_eq(pos.grade_pct(), 0.0)
	assert_eq(pos.laps_completed(), 0)
