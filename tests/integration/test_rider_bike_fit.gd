extends GutTest
## Подгонка велосипеда под контракт скелета (T-106a1; подготовка REQ-D3D-09 п.1, 2, 5; бриф
## художнику раздел 6): верх седла под S, размеры седла, центр хвата тормозных ручек, шатун и
## ось педали, контактные педали под углом стопы; рама и колёса не меняются (регрессия
## D3D-04 п.1–3).

const RIDER_SCENE: String = "res://src/scene3d/rider.tscn"
const FRAME: float = 1.0 / 60.0


## Наивысшая точка меша на вертикали (x, z) — по треугольникам `ARRAY_VERTEX`/`ARRAY_INDEX`.
static func top_at(mesh: Mesh, x: float, z: float, xf: Transform3D = Transform3D.IDENTITY) -> float:
	var best: float = -INF
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(x, 5.0, z), Vector3.DOWN,
				xf * v[idx[t]], xf * v[idx[t + 1]], xf * v[idx[t + 2]])
			if hit == null:
				hit = Geometry3D.ray_intersects_triangle(Vector3(x, 5.0, z), Vector3.DOWN,
					xf * v[idx[t]], xf * v[idx[t + 2]], xf * v[idx[t + 1]])
			if hit != null:
				best = maxf(best, (hit as Vector3).y)
	return best


func _bike_mesh() -> Mesh:
	return RiderModel.meshes(load("res://src/scene3d/materials/rider_toon.tres"))["bike"]


func test_saddle_top_under_pelvis_support_point() -> void:
	var s: Vector3 = RiderRig.head("pelvis")
	var top: float = top_at(_bike_mesh(), s.x, s.z)
	assert_almost_eq(top, 0.965, 0.002, "верх седла под S — 0.965 ± 0.002 (%.4f)" % top)
	assert_between(s.y - top, -1e-4, 0.015, "REQ-D3D-09 п.1: S над седлом на 0…15 мм")
	var hip: Vector3 = RiderRig.head("thigh.R")
	assert_between(hip.y - top, 0.075, 0.095, "п.2: HIP над седлом на 75–95 мм")


func test_saddle_length_rear_width_and_rear_edge_behind_s() -> void:
	# Вершины седла — всё, что выше 0.93 м у средней плоскости между осями (руль — z < −0.4).
	var arr: Array = _bike_mesh().surface_get_arrays(0)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p in arr[Mesh.ARRAY_VERTEX] as PackedVector3Array:
		if p.y > 0.935 and p.z > -0.2:
			lo = lo.min(p)
			hi = hi.max(p)
	var s: Vector3 = RiderRig.head("pelvis")
	assert_almost_eq(hi.z - lo.z, RiderRig.SADDLE_LENGTH_M, 0.005, "длина седла 0.27")
	assert_almost_eq(hi.x - lo.x, RiderRig.SADDLE_REAR_WIDTH_M, 0.005, "ширина сзади 0.13")
	assert_between(hi.z - s.z, 0.03, 0.10, "п.1: задний край на 3–10 см позади S")
	assert_lt(hi.y, 0.975, "седло не выше S + 1 см нигде")


func test_brake_hood_grip_points() -> void:
	for side in ["grip.L", "grip.R"]:
		var g: Vector3 = RiderRig.head(side)
		var top: float = top_at(_bike_mesh(), g.x, g.z)
		assert_almost_eq(top + RiderModel.HOOD_PALM_CLEARANCE_M, g.y, 0.005,
			"%s: центр ладони над ручкой (верх ручки %.4f)" % [side, top])
		# Сбоку от ручки на 4 см — ниже (ручка — локальный верх под ладонью).
		assert_lt(top_at(_bike_mesh(), g.x + 0.04 * signf(g.x), g.z), top - 0.01, "%s: ручка под ладонью" % side)


func test_frame_and_wheels_unchanged() -> void:
	assert_almost_eq(RiderModel.REAR_AXLE.z - RiderModel.FRONT_AXLE.z, 0.99, 1e-6, "база 0.99")
	assert_eq(RiderModel.BB, Vector3(0.0, 0.27, 0.0))
	assert_almost_eq(RiderModel.CRANK_LENGTH_M, 0.17, 1e-6, "шатун 0.17")
	assert_almost_eq(RiderModel.PEDAL_X_M, 0.115, 1e-6, "ось педали ±0.115")


func _rider() -> Rider:
	var r: Rider = load(RIDER_SCENE).instantiate()
	add_child_autofree(r)
	r.set_process(false)
	return r


## Начало и «нос» кости педали в системе узла `Lean`.
func _pedal_in_lean(r: Rider, bone: int) -> Transform3D:
	var rig: Skeleton3D = r.get_node("%CrankRig")
	var lean: Node3D = r.get_node("%Lean")
	return lean.global_transform.affine_inverse() * rig.global_transform * rig.get_bone_global_pose(bone)


func test_contact_pedals_on_pedal_axis_and_follow_foot_pitch() -> void:
	var r := _rider()
	var arm: MeshInstance3D = r.get_node("%CrankArm")
	assert_not_null(arm.skin, "шатуны со скиннингом на кости педалей")
	assert_eq((r.get_node("%CrankRig") as Skeleton3D).get_bone_count(), 3)
	for i in 24:
		var phi: float = deg_to_rad(15.0 * i)
		r.set_crank_angle(phi)
		for side in [1, 2]:
			var xf: Transform3D = _pedal_in_lean(r, side)
			var side_phi: float = phi if side == 1 else phi + PI
			var axis := RiderModel.BB + Vector3(RiderModel.PEDAL_X_M * (1.0 if side == 1 else -1.0),
				RiderModel.CRANK_LENGTH_M * cos(side_phi), -RiderModel.CRANK_LENGTH_M * sin(side_phi))
			assert_lt(xf.origin.distance_to(axis), 1e-4, "φ=%d° кость %d на оси педали" % [15 * i, side])
			# Нос педали — +Z системы шатуна (вперёд по ходу).
			var nose: Vector3 = xf.basis * Vector3.BACK
			var pitch: float = atan2(nose.y, -nose.z)
			assert_almost_eq(pitch, RiderRig.foot_pitch_rad(side_phi), 1e-3,
				"φ=%d° педаль %d под углом стопы" % [15 * i, side])


func test_pedal_body_centered_on_pedal_axis() -> void:
	var mesh: ArrayMesh = RiderModel.crank_mesh(null)
	var arr: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var stride: int = bones.size() / verts.size()
	for bone in [1, 2]:
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for i in verts.size():
			if bones[i * stride] == bone:
				lo = lo.min(verts[i])
				hi = hi.max(verts[i])
		var rest: Vector3 = RiderModel.PEDAL_R_REST if bone == 1 else RiderModel.PEDAL_L_REST
		assert_almost_eq((lo.x + hi.x) * 0.5, rest.x, 0.002, "корпус педали по X — на оси педали")
		assert_lt(hi.y, rest.y + 0.001, "верх корпуса не выше оси (шип туфли — на оси)")
		assert_gt(hi.z - lo.z, 0.07, "контактная педаль — платформа ≥ 7 см")


func test_rider_still_has_eleven_mesh_nodes_and_one_material() -> void:
	var r := _rider()
	var meshes := r.find_children("*", "MeshInstance3D", true, false)
	assert_eq(meshes.size(), 11, "узлов с сетками столько же, сколько до T-106a1")
	for m in meshes:
		assert_eq((m as MeshInstance3D).mesh.surface_get_material(0), Rider.RIDER_MATERIAL, String(m.name))


func test_set_crank_angle_holds_with_zero_cadence() -> void:
	var r := _rider()
	r.set_cadence(0)
	r.set_crank_angle(deg_to_rad(270.0))
	for i in 30:
		r.advance(FRAME)
	assert_almost_eq(r.crank_rotation_rad(), deg_to_rad(270.0), 1e-4, "каденс 0 — шатун стоит на угле")
	r.set_cadence(90)
	for i in 60:
		r.advance(FRAME)
	assert_ne(snappedf(r.crank_rotation_rad(), 1e-3), snappedf(deg_to_rad(270.0), 1e-3), "с каденсом — оборот продолжается")
