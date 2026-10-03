extends GutTest
## Тесты ориентиров каталога трасс (REQ-D3D-08 крит. 12; данные — `docs/game/tracks.md`
## п. 4.5): разрыв между соседними ориентирами по кругу, включая стык, ≤ 1500 м;
## на одной s не больше одного ориентира; s в [0; L); сторона и план из допустимых наборов.

## Предел разрыва между соседними ориентирами по кругу, м (D3D-08 крит. 12).
const MAX_GAP_M: float = 1500.0

## Максимальный разрыв по таблицам п. 4.5, м.
const TABLE_MAX_GAP_M: Dictionary = {
	"flat": 1300.0,
	"hills": 1400.0,
	"mountains": 1500.0,
	"seaside": 1200.0,
}

## Таблицы п. 4.5: [s_m, type, сторона, план]; план: near — у дороги, mid — средний,
## far — дальний.
const TABLE: Dictionary = {
	"flat": [
		[800, "water_tower", "right", "near"],
		[1900, "wind_turbines_far", "left", "far"],
		[3000, "haystacks", "left", "near"],
		[4200, "village", "right", "mid"],
		[5400, "grain_elevator", "left", "mid"],
		[6400, "sunflower_field", "right", "near"],
		[7500, "creek_footbridge", "road", "near"],
		[8600, "wind_turbines_near", "right", "mid"],
		[9500, "farm_silo", "left", "near"],
	],
	"hills": [
		[500, "stone_bridge", "road", "near"],
		[1500, "chapel", "left", "near"],
		[2600, "sheep", "right", "near"],
		[3600, "farmstead", "left", "mid"],
		[4500, "hay_bales", "right", "near"],
		[5400, "lone_tree_bench", "right", "near"],
		[6800, "windmill", "left", "mid"],
		[8000, "lake_view", "right", "far"],
		[8900, "horse_paddock", "left", "near"],
		[9800, "village", "right", "mid"],
		[11000, "castle_ruins", "left", "far"],
		[12200, "tv_tower", "right", "near"],
		[13400, "vineyard", "left", "near"],
		[14400, "hot_air_balloon", "right", "far"],
	],
	"mountains": [
		[500, "valley_village", "right", "mid"],
		[2000, "stone_bridge", "road", "near"],
		[3000, "pass_sign", "right", "near"],
		[4000, "summit_km_sign", "right", "near"],
		[5000, "summit_km_sign", "right", "near"],
		[5200, "waterfall", "left", "mid"],
		[6000, "summit_km_sign", "right", "near"],
		[7000, "summit_km_sign", "right", "near"],
		[7600, "switchbacks_view", "right", "far"],
		[8000, "summit_km_sign", "right", "near"],
		[9000, "summit_km_sign", "right", "near"],
		[9600, "clouds_below", "right", "far"],
		[10400, "pass_summit", "left", "near"],
		[11200, "snow_patch", "left", "near"],
		[12000, "mountain_lake", "right", "far"],
		[13300, "shepherd_hut", "left", "mid"],
		[14500, "avalanche_gallery", "road", "near"],
		[15500, "cable_car", "road", "mid"],
		[16500, "cow_pasture", "right", "near"],
		[17500, "sawmill", "left", "near"],
		[18500, "valley_village", "right", "mid"],
		[19500, "campsite", "left", "near"],
	],
	"seaside": [
		[600, "fishing_pier", "right", "near"],
		[1800, "beach_umbrellas", "right", "near"],
		[3000, "white_houses", "left", "mid"],
		[4200, "sailboat", "right", "far"],
		[5000, "river_mouth", "right", "mid"],
		[5800, "bridge", "road", "near"],
		[7000, "pine_forest", "both", "near"],
		[7800, "olive_terraces", "left", "mid"],
		[8600, "lighthouse", "right", "mid"],
		[9800, "cliffs_spray", "right", "near"],
		[11000, "promenade", "right", "near"],
		[11800, "lifeguard_tower", "right", "near"],
	],
}


## Максимальный разрыв по кругу, включая стык `L − s_last + s_first`.
func _max_gap(r: RouteCatalog.RouteDef) -> float:
	var lms: Array[RouteCatalog.Landmark] = r.landmarks
	var length_m: float = r.profile.length_m()
	var max_gap: float = length_m - lms[lms.size() - 1].s_m + lms[0].s_m
	for i in range(1, lms.size()):
		max_gap = maxf(max_gap, lms[i].s_m - lms[i - 1].s_m)
	return max_gap


func test_max_gap_within_limit_on_every_route() -> void:
	for r in RouteCatalog.all():
		assert_true(r.landmarks.size() >= 2, "%s: хотя бы два ориентира" % r.id)
		if r.landmarks.size() < 2:
			continue
		var gap: float = _max_gap(r)
		assert_true(gap <= MAX_GAP_M, "%s: макс. разрыв %.0f м ≤ %.0f м" % [r.id, gap, MAX_GAP_M])
		assert_almost_eq(gap, float(TABLE_MAX_GAP_M[r.id]), 0.001,
			"%s: макс. разрыв как в tracks.md п. 4.5" % r.id)


func test_seam_gap_counted() -> void:
	# Разрыв через стык у каждой трассы — по таблице п. 4.5.
	var expected: Dictionary = {"flat": 1300.0, "hills": 1100.0, "mountains": 1000.0, "seaside": 800.0}
	for r in RouteCatalog.all():
		var lms: Array[RouteCatalog.Landmark] = r.landmarks
		var seam: float = r.profile.length_m() - lms[lms.size() - 1].s_m + lms[0].s_m
		assert_almost_eq(seam, float(expected[r.id]), 0.001, "%s: разрыв через стык" % r.id)


func test_one_landmark_per_s_and_strictly_sorted() -> void:
	for r in RouteCatalog.all():
		var seen: Dictionary = {}
		var prev: float = -INF
		for lm in r.landmarks:
			assert_false(seen.has(lm.s_m), "%s: на s = %.0f один ориентир" % [r.id, lm.s_m])
			seen[lm.s_m] = true
			assert_true(lm.s_m > prev, "%s: s строго возрастает (%.0f)" % [r.id, lm.s_m])
			prev = lm.s_m


func test_s_within_lap() -> void:
	for r in RouteCatalog.all():
		var length_m: float = r.profile.length_m()
		for lm in r.landmarks:
			assert_true(lm.s_m >= 0.0 and lm.s_m < length_m,
				"%s: s = %.0f в [0; %.0f)" % [r.id, lm.s_m, length_m])


func test_side_and_plane_in_allowed_sets() -> void:
	assert_eq(RouteCatalog.Landmark.SIDES, ["left", "right", "road", "both"] as Array[String])
	assert_eq(RouteCatalog.Landmark.PLANES, ["near", "mid", "far"] as Array[String])
	for r in RouteCatalog.all():
		for lm in r.landmarks:
			assert_has(RouteCatalog.Landmark.SIDES, lm.side, "%s/%s: сторона" % [r.id, lm.type])
			assert_has(RouteCatalog.Landmark.PLANES, lm.plane, "%s/%s: план" % [r.id, lm.type])


func test_landmarks_match_tracks_table() -> void:
	for r in RouteCatalog.all():
		var rows: Array = TABLE[r.id]
		assert_eq(r.landmarks.size(), rows.size(), "%s: число ориентиров" % r.id)
		for i in mini(rows.size(), r.landmarks.size()):
			var row: Array = rows[i]
			var lm: RouteCatalog.Landmark = r.landmarks[i]
			var where: String = "%s[%d]" % [r.id, i]
			assert_almost_eq(lm.s_m, float(row[0]), 0.001, "%s: s_m" % where)
			assert_eq(lm.type, String(row[1]), "%s: type" % where)
			assert_eq(lm.side, String(row[2]), "%s: сторона" % where)
			assert_eq(lm.plane, String(row[3]), "%s: план" % where)


func test_type_is_snake_case() -> void:
	var re := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	for r in RouteCatalog.all():
		for lm in r.landmarks:
			assert_not_null(re.search(lm.type), "%s: type «%s» в snake_case" % [r.id, lm.type])


func test_landmark_defaults_are_valid() -> void:
	var lm := RouteCatalog.Landmark.new(100.0, "x")
	assert_has(RouteCatalog.Landmark.SIDES, lm.side)
	assert_has(RouteCatalog.Landmark.PLANES, lm.plane)
