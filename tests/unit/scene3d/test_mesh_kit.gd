extends GutTest
## Тесты MeshKit и геометрии модели велосипедиста (REQ-D3D-07 крит. 2, 4): обход граней
## совпадает с нормалями, цвета вершин — в линейном пространстве, двухзвенная IK сохраняет
## длины звеньев, кость смотрит от начала к концу.


func _front_facing_ratio(kit: MeshKit) -> float:
	var ok := 0
	var total := 0
	for t in range(0, kit.indices.size(), 3):
		var a: Vector3 = kit.vertices[kit.indices[t]]
		var b: Vector3 = kit.vertices[kit.indices[t + 1]]
		var c: Vector3 = kit.vertices[kit.indices[t + 2]]
		var fn: Vector3 = (c - a).cross(b - a)
		if fn.length_squared() < 1e-14:
			continue
		total += 1
		var n: Vector3 = kit.normals[kit.indices[t]] + kit.normals[kit.indices[t + 1]] + kit.normals[kit.indices[t + 2]]
		if fn.dot(n) >= 0.0:
			ok += 1
	return float(ok) / float(maxi(total, 1))


func test_primitives_have_consistent_winding_after_fix() -> void:
	var kit := MeshKit.new()
	kit.add_tube(Vector3.ZERO, Vector3(0, 1, 0.3), Vector2(0.1, 0.05), Vector2(0.08, 0.04), Color.RED)
	kit.add_ellipsoid(Vector3(1, 0, 0), Vector3(0.3, 0.2, 0.4), Color.WHITE)
	kit.add_box(Transform3D(Basis(Vector3.UP, 0.4), Vector3(0, 0, 2)), Vector3(1, 2, 3), Color.BLUE)
	kit.add_cone(Vector3(3, 0, 0), 2.0, 0.5, Color.GREEN)
	kit.add_torus_x(0.3, 0.02, Color.BLACK)
	kit.add_annulus_x(0.01, 0.2, 0.3, Color.GRAY, -1.0)
	kit.add_band_x(-0.01, 0.01, 0.2, Color.GRAY, false)
	kit.fix_winding()
	assert_almost_eq(_front_facing_ratio(kit), 1.0, 1e-9, "все грани лицом по нормали (обход Godot — по часовой)")


func test_colors_are_linear_and_alpha_is_outline_weight() -> void:
	var kit := MeshKit.new()
	kit.add_box(Transform3D.IDENTITY, Vector3.ONE, Color(0.5, 0.5, 0.5, 0.25))
	var c: Color = kit.colors[0]
	assert_almost_eq(c.r, Color(0.5, 0.5, 0.5).srgb_to_linear().r, 1e-5, "sRGB → линейный")
	assert_almost_eq(c.a, 0.25, 1e-6, "альфа (вес контура) не преобразуется")


func test_to_mesh_single_surface_with_material() -> void:
	var kit := MeshKit.new()
	kit.add_ellipsoid(Vector3.ZERO, Vector3.ONE, Color.WHITE)
	var mat := ShaderMaterial.new()
	var mesh := kit.to_mesh(mat)
	assert_eq(mesh.get_surface_count(), 1)
	assert_eq(mesh.surface_get_material(0), mat)
	assert_eq(MeshKit.new().to_mesh().get_surface_count(), 0, "пустой набор — пустой меш без ошибок")


func test_two_bone_joint_keeps_segment_lengths_and_bends_to_hint() -> void:
	var hip := RiderModel.HIP
	for phi in [0.0, PI * 0.5, PI, PI * 1.5]:
		var pedal := Vector3(RiderModel.PEDAL_X_M, RiderModel.BB.y + RiderModel.CRANK_LENGTH_M * cos(phi), -RiderModel.CRANK_LENGTH_M * sin(phi))
		var ankle: Vector3 = pedal + RiderModel.ANKLE_FROM_PEDAL
		assert_lt(hip.distance_to(ankle), RiderModel.THIGH_M + RiderModel.SHIN_M, "педаль достижима при угле %.2f" % phi)
		var knee := RiderModel.two_bone_joint(hip, ankle, RiderModel.THIGH_M, RiderModel.SHIN_M, RiderModel.KNEE_HINT)
		assert_almost_eq(knee.distance_to(hip), RiderModel.THIGH_M, 1e-4, "длина бедра")
		assert_almost_eq(knee.distance_to(ankle), RiderModel.SHIN_M, 1e-4, "длина голени")
		assert_lt(knee.z, minf(hip.z, ankle.z) + 0.05, "колено согнуто вперёд (−Z)")


func test_two_bone_joint_clamps_unreachable_target() -> void:
	var knee := RiderModel.two_bone_joint(Vector3.ZERO, Vector3(0, -5, 0), 0.4, 0.4, Vector3.FORWARD)
	assert_true(knee.is_finite())
	assert_almost_eq(knee.length(), 0.4, 1e-3)


func test_bone_transform_points_minus_y_from_start_to_end() -> void:
	var xf := RiderModel.bone_transform(Vector3(0, 1, 0), Vector3(0, 0.5, -0.3))
	var end: Vector3 = xf * Vector3(0, -Vector3(0, 0.5, 0.3).length(), 0)
	assert_lt(end.distance_to(Vector3(0, 0.5, -0.3)), 1e-4)
	assert_almost_eq(xf.basis.determinant(), 1.0, 1e-4, "ортонормированный базис без зеркала")


func test_rider_meshes_are_cached_and_share_one_material() -> void:
	var mat := ShaderMaterial.new()
	var a := RiderModel.meshes(mat)
	var b := RiderModel.meshes(mat)
	assert_eq(a["bike"], b["bike"], "статический кэш")
	for key in ["bike", "wheel", "rear_wheel", "crank", "upper", "thigh", "shin", "shoe"]:
		var m: ArrayMesh = a[key]
		assert_eq(m.get_surface_count(), 1, key)
		assert_eq(m.surface_get_material(0), mat, key)
