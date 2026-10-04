extends GutTest
## Пакет художнику `assets/rider/reference/` (T-106a1; бриф разделы 4–6, 10, 18): файлы
## собраны сценарием `scripts/rider_artist_kit.sh` из кода (`RiderRig`, `RiderModel`,
## `RiderRegions`) и не устарели; оба `.glb` импортируются в Godot (`GLTFDocument`, тот же
## импорт, что у редактора), точки после круга «экспорт → импорт» — в ±1 мм; оси — как у
## экспорта Blender «+Y Up» из координат брифа (проверка формулой импорта Blender).

const DIR: String = "res://assets/rider/reference"
const MM: float = 0.001


func _path(file: String) -> String:
	return ProjectSettings.globalize_path(DIR.path_join(file))


func _import(file: String) -> Node:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err: Error = doc.append_from_file(_path(file), state)
	assert_eq(err, OK, "%s импортируется" % file)
	if err != OK:
		return null
	var scene: Node = doc.generate_scene(state)
	add_child_autofree(scene)
	return scene


## Импорт Blender glTF (+Y Up): (x, y, z) → (x, −z, y) — `convert_swizzle_location`.
static func blender_from_gltf(g: Vector3) -> Vector3:
	return Vector3(g.x, -g.z, g.y)


func test_package_files_present_and_excluded_from_project_import() -> void:
	for f in ["bike_reference.glb", "rider_rig_reference.glb", "rider_atlas_preview.png", "rider_atlas_id.png", "README.md"]:
		assert_true(FileAccess.file_exists(_path(f)), f)
	assert_true(FileAccess.file_exists(_path(".gdignore")), "каталог не импортируется и не попадает в сборку")
	var total: int = 0
	for f in ["bike_reference.glb", "rider_rig_reference.glb", "rider_atlas_preview.png", "rider_atlas_id.png"]:
		total += FileAccess.get_file_as_bytes(_path(f)).size()
	assert_lt(total, 1024 * 1024, "пакет меньше 1 МБ (%d байт)" % total)


func test_bike_reference_points_axes_and_geometry() -> void:
	var scene := _import("bike_reference.glb")
	if scene == null:
		return
	for part in ["bike_frame", "wheel_front", "wheel_rear", "crankset"]:
		var mi := scene.find_child(part, true, false) as MeshInstance3D
		assert_not_null(mi, part)
		if mi == null:
			continue
		assert_eq(mi.transform, Transform3D.IDENTITY, "%s: поворот и масштаб применены" % part)
		for s in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			assert_true(arr[Mesh.ARRAY_COLOR] == null or (arr[Mesh.ARRAY_COLOR] as PackedColorArray).is_empty(),
				"%s: без цвета вершин" % part)
	var points := {
		"pt_bb": RiderRig.BB, "pt_saddle_S": RiderRig.head("pelvis"),
		"pt_grip_L": RiderRig.head("grip.L"), "pt_grip_R": RiderRig.head("grip.R"),
		"pt_cleat_R_pedal_axis": RiderRig.head("cleat.R"),
		"pt_axle_rear": RiderRig.REAR_AXLE, "pt_axle_front": RiderRig.FRONT_AXLE,
	}
	for n in points:
		var node := scene.find_child(n, true, false) as Node3D
		assert_not_null(node, n)
		if node != null:
			assert_lt(RiderRig.from_gltf(node.global_position).distance_to(points[n]), MM, "%s ± 1 мм" % n)
	# Оси глазами Blender: числа брифа раздел 6.
	var b_s: Vector3 = blender_from_gltf((scene.find_child("pt_saddle_S", true, false) as Node3D).global_position)
	assert_lt(b_s.distance_to(Vector3(0.0, 0.230, 0.965)), MM, "Blender: S (0, 0.23, 0.965)")
	var b_gl: Vector3 = blender_from_gltf((scene.find_child("pt_grip_L", true, false) as Node3D).global_position)
	assert_lt(b_gl.distance_to(Vector3(0.21, -0.62, 0.885)), MM, "Blender: grip.L (+0.21, −0.62, 0.885) — левая +X, перед −Y")
	var b_c: Vector3 = blender_from_gltf((scene.find_child("pt_cleat_R_pedal_axis", true, false) as Node3D).global_position)
	assert_lt(b_c.distance_to(Vector3(-0.115, -0.170, 0.270)), MM, "Blender: cleat.R (−0.115, −0.17, 0.27)")
	# Геометрия после круга экспорт → импорт: седло и ручки.
	var frame := scene.find_child("bike_frame", true, false) as MeshInstance3D
	var to_godot: Transform3D = RiderRig.gltf_flip()
	var s: Vector3 = RiderRig.head("pelvis")
	var top: float = preload("res://tests/integration/test_rider_bike_fit.gd").top_at(frame.mesh, s.x, s.z, to_godot)
	assert_almost_eq(top, 0.965, 0.002, "верх седла под S в файле")
	for side in ["grip.L", "grip.R"]:
		var g: Vector3 = RiderRig.head(side)
		var hood: float = preload("res://tests/integration/test_rider_bike_fit.gd").top_at(frame.mesh, g.x, g.z, to_godot)
		assert_almost_eq(hood + RiderModel.HOOD_PALM_CLEARANCE_M, g.y, 0.005, "%s в файле" % side)


func test_bike_reference_crank_at_rest_right_pedal_forward() -> void:
	var scene := _import("bike_reference.glb")
	if scene == null:
		return
	var crank := scene.find_child("crankset", true, false) as MeshInstance3D
	var cleat_r: Vector3 = RiderRig.head("cleat.R")
	var cleat_l := Vector3(-cleat_r.x, RiderRig.BB.y, -cleat_r.z)
	for target in [cleat_r, cleat_l]:
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for si in crank.mesh.get_surface_count():
			for g in crank.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
				var p: Vector3 = RiderRig.from_gltf(g)
				if absf(p.z - target.z) < 0.06 and absf(p.y - target.y) < 0.03 and absf(p.x - target.x) < 0.03:
					lo = lo.min(p)
					hi = hi.max(p)
		assert_almost_eq((lo.x + hi.x) * 0.5, target.x, 0.003, "корпус педали на оси %s" % target)
		assert_between(target.y, lo.y, hi.y + 0.001, "педаль у оси %s" % target)
		assert_gt(hi.z - lo.z, 0.06, "контактная педаль — платформа %s" % target)
	assert_lt(cleat_r.z, 0.0, "правая педаль впереди (Godot −Z)")


func test_rig_reference_bones_names_parents_positions() -> void:
	var scene := _import("rider_rig_reference.glb")
	if scene == null:
		return
	var skels := scene.find_children("*", "Skeleton3D", true, false)
	assert_eq(skels.size(), 1, "одна арматура")
	if skels.is_empty():
		return
	var skel := skels[0] as Skeleton3D
	assert_eq(skel.get_bone_count(), RiderRig.BONE_COUNT, "25 костей")
	var to_scene: Transform3D = skel.global_transform
	for b in RiderRig.BONES:
		var i: int = skel.find_bone(b[0])
		assert_true(i >= 0, "кость %s (имя с .L/.R как в брифе)" % b[0])
		if i < 0:
			continue
		var parent: int = skel.get_bone_parent(i)
		assert_eq(skel.get_bone_name(parent) if parent >= 0 else "", b[1], "родитель %s" % b[0])
		var g: Vector3 = to_scene * skel.get_bone_global_rest(i).origin
		assert_lt(RiderRig.from_gltf(g).distance_to(b[2]), MM, "%s ± 1 мм" % b[0])
		assert_lt(blender_from_gltf(g).distance_to(RiderRig.to_blender(b[2])), MM, "%s в Blender" % b[0])
	var markers := scene.find_children("*", "MeshInstance3D", true, false)
	assert_eq(markers.size(), 1, "сетка меток суставов")


func test_atlases_size_columns_and_reproducible() -> void:
	var preview := Image.load_from_file(_path("rider_atlas_preview.png"))
	var ids := Image.load_from_file(_path("rider_atlas_id.png"))
	for img in [preview, ids]:
		assert_eq(img.get_size(), RiderRegions.ATLAS_SIZE, "1024 × 256")
	assert_eq(RiderRegions.ATLAS_SIZE.x / RiderRegions.COLUMN_PX, 32, "32 колонки")
	# Колонка k при V = 0.5 — цвет региона пресета classic (тон 1.0).
	for k in RiderRegions.COUNT:
		var c: Color = preview.get_pixel(k * RiderRegions.COLUMN_PX + 16, 128)
		var want: Color = RiderRegions.CLASSIC[k]
		assert_lt(Vector3(c.r - want.r, c.g - want.g, c.b - want.b).length(), 3.0 / 255.0,
			"колонка %d (%s) = classic" % [k, RiderRegions.region_name(k)])
	# Тон: верх светлее низа (кроме чистого чёрного), у линзы вверху — блик.
	var lens_top: Color = preview.get_pixel(RiderRegions.LENS * 32 + 16, 10)
	assert_gt(lens_top.v, (RiderRegions.CLASSIC[RiderRegions.LENS] as Color).v * 1.6, "блик линзы V ≥ 0.75")
	assert_gt(preview.get_pixel(16, 0).v, preview.get_pixel(16, 255).v, "кожа: верх (тон 1.4) светлее низа (0.6)")
	# Различимость колонок атласа-проверки.
	var cols: Array[Color] = []
	for k in RiderRegions.COUNT:
		cols.append(ids.get_pixel(k * RiderRegions.COLUMN_PX + 3, 50))
		var want: Color = RiderRegions.id_color(k)
		assert_lt(Vector3(cols[k].r - want.r, cols[k].g - want.g, cols[k].b - want.b).length(), 2.0 / 255.0,
			"колонка %d — свой оттенок" % k)
	var min_d: float = INF
	for a in cols.size():
		for b in range(a + 1, cols.size()):
			min_d = minf(min_d, Vector3(cols[a].r - cols[b].r, cols[a].g - cols[b].g, cols[a].b - cols[b].b).length())
	assert_gt(min_d, 0.08, "32 различимых оттенка (мин. расстояние RGB %.3f)" % min_d)
	# Файлы = то, что даёт код сейчас (пакет не устарел).
	assert_eq(preview.get_data(), RiderRegions.preview_atlas().get_data(), "превью совпадает с генератором")
	assert_eq(ids.get_data(), RiderRegions.id_atlas().get_data(), "атлас-проверка совпадает с генератором")


## Пакет не устарел: велосипед в файле — тот же, что строит код (число вершин частей и точки).
func test_bike_reference_matches_current_code() -> void:
	var scene := _import("bike_reference.glb")
	if scene == null:
		return
	var kits: Dictionary = RiderModel.reference_kits(RiderRig.REST_CRANK_RAD)
	for part in kits:
		var mi := scene.find_child(part, true, false) as MeshInstance3D
		var tris: int = 0
		for s in mi.mesh.get_surface_count():
			tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		assert_eq(tris, (kits[part] as MeshKit).indices.size() / 3, "%s: треугольников как в коде — пересоберите пакет" % part)
