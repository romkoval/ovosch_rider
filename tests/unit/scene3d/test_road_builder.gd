extends GutTest
## Тесты RoadBuilder (REQ-D3D-03 крит. 2, REQ-D3D-05 крит. 4 — бюджет узлов/материалов).

var _track: LoopTrack


func before_each() -> void:
	_track = LoopTrack.new(5)


func test_builds_single_mesh_instance_with_one_surface() -> void:
	var road := RoadBuilder.build(_track)
	autofree(road)
	assert_true(road is MeshInstance3D)
	assert_eq(road.name, "Road")
	assert_not_null(road.mesh)
	assert_eq(road.mesh.get_surface_count(), 1, "одна поверхность — один материал")
	assert_gt(road.mesh.get_faces().size(), 0, "меш не пустой")


func test_segment_count_within_budget_and_constant() -> void:
	var n := RoadBuilder.segment_count(_track)
	assert_true(n <= RoadBuilder.MAX_SEGMENTS, "≤ MAX_SEGMENTS")
	assert_true(n >= 8)
	var road := RoadBuilder.build(_track)
	autofree(road)
	assert_eq(int(road.get_meta("segments")), n)
	var arrays := road.mesh.surface_get_arrays(0)
	assert_eq((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), (n + 1) * 2)
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), n * 6)
	var long_track := LoopTrack.new(3, 3000.0)
	assert_eq(RoadBuilder.segment_count(long_track), RoadBuilder.MAX_SEGMENTS, "длинная трасса упирается в бюджет")


func test_width_is_six_metres() -> void:
	var road := RoadBuilder.build(_track)
	autofree(road)
	var verts: PackedVector3Array = road.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i in range(0, verts.size(), 2):
		assert_almost_eq(verts[i].distance_to(verts[i + 1]), RoadBuilder.DEFAULT_WIDTH_M, 1e-3, "кольцо %d" % (i / 2))


func test_material_applied_when_given() -> void:
	var mat := StandardMaterial3D.new()
	var road := RoadBuilder.build(_track, mat)
	autofree(road)
	assert_eq(road.get_active_material(0), mat)
	var plain := RoadBuilder.build(_track)
	autofree(plain)
	assert_null(plain.get_active_material(0))


func test_loop_road_closes_on_itself() -> void:
	var road := RoadBuilder.build(_track)
	autofree(road)
	var verts: PackedVector3Array = road.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var n: int = int(road.get_meta("segments"))
	assert_lt(verts[0].distance_to(verts[n * 2]), 1e-3, "последнее кольцо совпадает с первым")
	assert_lt(verts[1].distance_to(verts[n * 2 + 1]), 1e-3)


func test_uv_runs_along_distance() -> void:
	var road := RoadBuilder.build(_track)
	autofree(road)
	var uvs: PackedVector2Array = road.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	assert_eq(uvs[0], Vector2(0.0, 0.0))
	assert_eq(uvs[1], Vector2(1.0, 0.0))
	assert_gt(uvs[uvs.size() - 1].y, 100.0, "v = дистанция / ширина — повтор разметки вдоль")
