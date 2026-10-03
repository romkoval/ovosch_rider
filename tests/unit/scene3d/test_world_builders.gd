extends GutTest
## Тесты строителей мира (REQ-D3D-07 крит. 1, 3, 4): рельеф вокруг трассы, обочина с
## бордюром и полосой травы, растительность в бюджете MultiMesh.

var _track: LoopTrack


## Точная окружность радиуса R, обход от +X к +Z (по ходу — поворот вправо).
class CircleTrack extends Track:
	var radius: float
	func _init(r: float = 100.0) -> void:
		radius = r
	func length_m() -> float:
		return TAU * radius
	func is_loop() -> bool:
		return true
	func sample_into(distance_m: float, out: TrackSample) -> void:
		var a := wrap_distance(distance_m) / radius
		out.position = Vector3(cos(a), 0.0, sin(a)) * radius
		out.forward = Vector3(-sin(a), 0.0, cos(a))
		out.up = Vector3.UP
		out.grade = 0.0


func before_each() -> void:
	_track = LoopTrack.new(7)


func test_terrain_is_below_road_near_track_and_rises_into_hills_at_edge() -> void:
	var f := TerrainField.build(_track, 5.0, 120.0, 11)
	assert_gt(f.nx, 10)
	assert_lte(maxi(f.nx, f.nz), TerrainField.MAX_CELLS + 2, "размер сетки ограничен")
	var max_gap := -INF
	for s in range(0, int(_track.length_m()), 50):
		var p := _track.sample(float(s)).position
		var h := f.height_at(p.x, p.z)
		max_gap = maxf(max_gap, h - p.y)
		assert_lt(f.road_distance_at(p.x, p.z), f.cell_m, "расстояние до трассы на трассе мало (s=%d)" % s)
	assert_lt(max_gap, 0.0, "земля у дороги ниже полотна (макс. %.2f м)" % max_gap)
	var edge_max := -INF
	for i in f.nx:
		edge_max = maxf(edge_max, f.heights[i])
	assert_gt(edge_max, f.mean_y + 30.0, "на краю мира — холмы горизонта")


func test_terrain_mesh_single_surface_vertices_match_grid() -> void:
	var f := TerrainField.build(_track, 5.0, 120.0, 11)
	var node := f.build_mesh(null)
	autofree(node)
	assert_eq(node.mesh.get_surface_count(), 1)
	var verts: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), f.nx * f.nz)


func test_roadside_builds_curb_and_verge_meshes() -> void:
	var out := RoadsideBuilder.build(_track, 6.5, -1.4, null, null, true, 11)
	var roadside: MeshInstance3D = out["roadside"]
	var verge: MeshInstance3D = out["verge"]
	autofree(roadside)
	autofree(verge)
	assert_eq(roadside.mesh.get_surface_count(), 1)
	assert_eq(verge.mesh.get_surface_count(), 1)
	for v in verge.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		assert_true((v as Vector3).is_finite())
	assert_almost_eq(RoadsideBuilder.verge_height(RoadsideBuilder.curb_outer_m(6.5), 6.5), RoadsideBuilder.GRASS_AT_CURB_M, 1e-6)
	assert_lt(RoadsideBuilder.verge_height(RoadsideBuilder.verge_width_m(6.5), 6.5), 0.0, "внешний край полосы ниже дороги")


func test_curvature_magnitude_and_sign() -> void:
	var a := TrackSample.new()
	var b := TrackSample.new()
	# Круглая петля R = 100 м обходится от +X к +Z: вправо по ходу (правый вектор — −X), κ < 0.
	var circle := CircleTrack.new(100.0)
	var k := RoadsideBuilder.curvature(circle, 10.0, 5.0, a, b)
	assert_almost_eq(absf(k), 1.0 / 100.0, 1e-4, "|κ| ≈ 1/R")
	assert_lt(k, 0.0, "поворот вправо — отрицательная кривизна")
	var right_vec := circle.sample(10.0).right()
	assert_lt(right_vec.x, 0.0)


func test_scenery_fits_budget_and_scales_down() -> void:
	var env := EnvironmentSet.new()
	var f := TerrainField.build(_track, 5.0, 120.0, 11)
	var nodes := SceneryBuilder.build(_track, env, f, null, 2000)
	var total := 0
	for n in nodes:
		total += n.multimesh.instance_count
		assert_true(n.multimesh.use_colors, "оттенок экземпляра")
		autofree(n)
	assert_gt(total, 500, "мир не пустой")
	assert_lte(total, 2000)
	var small := SceneryBuilder.build(_track, env, f, null, 300)
	var small_total := 0
	for n in small:
		small_total += n.multimesh.instance_count
		autofree(n)
	assert_lte(small_total, 300, "при нехватке бюджета число объектов урезается")
