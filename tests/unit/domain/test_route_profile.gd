extends GutTest
## Тесты профиля трассы RouteProfile (REQ-D3D-08 крит. 2, 3 — расчёт; REQ-FRD-03 крит. 1).


## Кусочно-линейный профиль, заданный точками через 10 м (D3D-08: не реже 10 м).
func _linear_profile(corners: PackedVector2Array) -> RouteProfile:
	var pts := PackedVector2Array()
	for c in range(corners.size() - 1):
		var a: Vector2 = corners[c]
		var b: Vector2 = corners[c + 1]
		var steps: int = roundi((b.x - a.x) / 10.0)
		for i in steps:
			pts.append(a.lerp(b, float(i) / float(steps)))
	pts.append(corners[corners.size() - 1])
	return RouteProfile.from_points(pts)


## Профиль FRD-03 крит. 1: 1000 м ровно, 1000 м подъём на 50 м, 1000 м спуск на 50 м.
func _frd03_profile() -> RouteProfile:
	return _linear_profile(PackedVector2Array([
		Vector2(0, 0), Vector2(1000, 0), Vector2(2000, 50), Vector2(3000, 0),
	]))


func test_frd03_reference_profile_characteristics() -> void:
	var p := _frd03_profile()
	assert_true(p.is_valid(), p.error_code())
	assert_almost_eq(p.length_m() / 1000.0, 3.0, 0.05, "длина 3.0 км")
	assert_almost_eq(p.ascent_m(), 50.0, 0.5, "набор 50 м")
	assert_almost_eq(p.max_grade_pct(), 5.0, 0.1, "макс. уклон 5.0 %")
	assert_almost_eq(p.min_grade_pct(), -5.0, 0.1, "мин. уклон −5.0 %")
	assert_almost_eq(p.min_height_m(), 0.0, 1e-6)
	assert_almost_eq(p.max_height_m(), 50.0, 1e-6)


func test_frd03_profile_has_one_climb() -> void:
	var climbs := _frd03_profile().climbs()
	assert_eq(climbs.size(), 1, "один подъём > 2 % и ≥ 300 м")
	if climbs.size() != 1:
		return
	var c: RouteProfile.Climb = climbs[0]
	assert_almost_eq(c.start_m, 1000.0, 60.0, "начало подъёма около 1000 м")
	assert_almost_eq(c.length_m, 1000.0, 100.0, "длина подъёма около 1000 м")
	assert_almost_eq(c.avg_grade_pct, 5.0, 0.5, "средний уклон около 5 %")
	assert_almost_eq(c.gain_m, c.avg_grade_pct * c.length_m / 100.0, 1e-6, "набор = уклон × длина")


func test_sampling_step_is_10_m() -> void:
	var p := _frd03_profile()
	assert_almost_eq(p.sample_step_m(), 10.0, 1e-9)
	assert_eq(p.sample_count(), 300, "точка s = L не дублирует s = 0")
	var odd := RouteProfile.from_points(PackedVector2Array([
		Vector2(0, 0), Vector2(400, 10), Vector2(1005, 0),
	]))
	assert_true(odd.sample_step_m() <= 10.0, "шаг не больше 10 м при L, не кратной 10")
	assert_almost_eq(odd.sample_step_m() * odd.sample_count(), 1005.0, 1e-6)


func test_samples_match_height_at() -> void:
	var p := _seam_slope_profile()
	var hs := p.sample_heights()
	var gs := p.sample_grades()
	for i in range(0, p.sample_count(), 7):
		var s: float = float(i) * p.sample_step_m()
		assert_almost_eq(hs[i], p.height_at(s), 1e-9)
		assert_almost_eq(gs[i], p.grade_at(s), 1e-9)


func test_interpolation_passes_through_knots() -> void:
	var pts := PackedVector2Array([
		Vector2(0, 100), Vector2(700, 140), Vector2(1300, 120), Vector2(2500, 180),
		Vector2(3100, 90), Vector2(4000, 100),
	])
	var p := RouteProfile.from_points(pts)
	for k in pts:
		assert_almost_eq(p.height_at(k.x), k.y if k.x < 4000.0 else pts[0].y, 1e-9, "h(%.0f)" % k.x)
	assert_eq(p.knots(), pts, "опорные точки отдаются как заданы")


func test_pchip_no_overshoot_between_knots() -> void:
	var pts := PackedVector2Array([
		Vector2(0, 100), Vector2(300, 101), Vector2(1300, 160), Vector2(1500, 160),
		Vector2(2500, 95), Vector2(2600, 140), Vector2(4000, 100),
	])
	var p := RouteProfile.from_points(pts)
	for k in range(pts.size() - 1):
		var lo: float = minf(pts[k].y, pts[k + 1].y)
		var hi: float = maxf(pts[k].y, pts[k + 1].y)
		var s: float = pts[k].x
		while s <= pts[k + 1].x:
			var h: float = p.height_at(s)
			assert_true(h >= lo - 1e-9 and h <= hi + 1e-9,
				"h(%.0f) = %.3f в пределах [%.1f; %.1f]" % [s, h, lo, hi])
			s += 5.0


func test_flat_tangent_at_extremum() -> void:
	var p := RouteProfile.from_points(PackedVector2Array([
		Vector2(0, 0), Vector2(1000, 50), Vector2(2000, 0),
	]))
	var d_left: float = (p.height_at(1000.0) - p.height_at(999.0))
	var d_right: float = (p.height_at(1001.0) - p.height_at(1000.0))
	assert_almost_eq(d_left, 0.0, 1e-3, "на вершине касательная ровная")
	assert_almost_eq(d_right, 0.0, 1e-3)


## Профиль, у которого на стыке круга ненулевой наклон (подъём через s = 0).
func _seam_slope_profile() -> RouteProfile:
	return RouteProfile.from_points(PackedVector2Array([
		Vector2(0, 25), Vector2(500, 50), Vector2(1500, 0), Vector2(2500, 0), Vector2(3000, 25),
	]))


func test_closed_loop_height_and_tangent_continuous() -> void:
	var p := _seam_slope_profile()
	var l: float = p.length_m()
	assert_almost_eq(p.height_at(l), p.height_at(0.0), 1e-9, "h(L) = h(0)")
	assert_true(absf(p.height_at(l - 0.001) - p.height_at(0.0)) <= 0.1, "|h(L−) − h(0)| ≤ 0.1 м")
	var slope_left: float = (p.height_at(l - 0.01) - p.height_at(l - 0.02)) / 0.01
	var slope_right: float = (p.height_at(0.02) - p.height_at(0.01)) / 0.01
	assert_gt(slope_right, 0.0, "на стыке подъём")
	assert_almost_eq(slope_left, slope_right, 1e-4, "касательная на стыке непрерывна")
	assert_true(absf(p.grade_at(l - 1.0) - p.grade_at(1.0)) <= 1.0, "разрыв уклона на стыке ≤ 1 %")


func test_height_wraps_by_modulo() -> void:
	var p := _seam_slope_profile()
	assert_almost_eq(p.height_at(3000.0 + 700.0), p.height_at(700.0), 1e-9)
	assert_almost_eq(p.height_at(-200.0), p.height_at(2800.0), 1e-9)


func test_grade_window_crosses_seam() -> void:
	var p := _seam_slope_profile()
	var expected: float = (p.height_at(50.0) - p.height_at(p.length_m() - 50.0)) / 100.0 * 100.0
	assert_almost_eq(p.grade_at(0.0), expected, 1e-9, "окно 100 м вокруг s = 0 берёт хвост круга")
	assert_gt(p.grade_at(0.0), 2.0)


func test_climb_across_seam_is_single() -> void:
	var climbs := _seam_slope_profile().climbs()
	assert_eq(climbs.size(), 1, "подъём через стык не режется на два")
	if climbs.size() != 1:
		return
	var c: RouteProfile.Climb = climbs[0]
	assert_gt(c.end_m(), 3000.0, "подъём заканчивается после стыка")
	assert_almost_eq(c.length_m, 1000.0, 150.0)
	assert_gt(c.avg_grade_pct, 2.0)


func test_short_climb_is_ignored() -> void:
	var p := _linear_profile(PackedVector2Array([
		Vector2(0, 0), Vector2(1000, 0), Vector2(1200, 10), Vector2(1400, 0), Vector2(3000, 0),
	]))
	assert_gt(p.max_grade_pct(), 2.0, "участок круче 2 %")
	assert_eq(p.climbs().size(), 0, "но короче 300 м — не подъём")


func test_ascent_sums_positive_increments_over_loop() -> void:
	var p := _linear_profile(PackedVector2Array([
		Vector2(0, 0), Vector2(500, 20), Vector2(1000, 10), Vector2(1500, 30), Vector2(2000, 0),
	]))
	assert_almost_eq(p.ascent_m(), 40.0, 0.01, "20 + 20 м")


func test_invalid_inputs() -> void:
	var few := RouteProfile.from_points(PackedVector2Array([Vector2(0, 0), Vector2(100, 0)]))
	assert_false(few.is_valid())
	assert_eq(few.error_code(), RouteProfile.ERR_TOO_FEW_POINTS)
	var unordered := RouteProfile.from_points(PackedVector2Array([
		Vector2(0, 0), Vector2(500, 5), Vector2(400, 3), Vector2(1000, 0),
	]))
	assert_eq(unordered.error_code(), RouteProfile.ERR_NOT_INCREASING)
	var open := RouteProfile.from_points(PackedVector2Array([
		Vector2(0, 0), Vector2(500, 5), Vector2(1000, 1),
	]))
	assert_eq(open.error_code(), RouteProfile.ERR_NOT_CLOSED)
	var shifted := RouteProfile.from_points(PackedVector2Array([
		Vector2(10, 0), Vector2(500, 5), Vector2(1000, 0),
	]))
	assert_eq(shifted.error_code(), RouteProfile.ERR_START_NOT_ZERO)
	var mismatch := RouteProfile.from_arrays(PackedFloat64Array([0, 500, 1000]), PackedFloat64Array([0, 5]))
	assert_eq(mismatch.error_code(), RouteProfile.ERR_TOO_FEW_POINTS)
	assert_eq(open.length_m(), 0.0)
	assert_eq(open.height_at(100.0), 0.0)
	assert_eq(open.grade_at(100.0), 0.0)
	assert_eq(open.climbs().size(), 0)


func test_climbs_returns_copy() -> void:
	var p := _frd03_profile()
	var list := p.climbs()
	list.clear()
	assert_eq(p.climbs().size(), 1, "правка списка снаружи не меняет профиль")
