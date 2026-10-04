extends GutTest
## Контракт скелета гонщика `RiderRig` против ТЗ художнику (T-106a1, REQ-D3D-09 подготовка
## п.1, 2, 5; `docs/game/rider-artist-brief.md` разделы 5.1, 6, 14): имена, родители, начала
## костей — числами брифа в координатах Blender; длины звеньев; ракурсы.

## Таблица 5.1 брифа как есть: кость → [родитель, начало (Blender: x, y, z)], `.L`; `.R` — x с минусом.
const BRIEF: Dictionary = {
	"pelvis": ["", Vector3(0.0, 0.230, 0.965)],
	"spine": ["pelvis", Vector3(0.0, 0.105, 1.147)],
	"chest": ["spine", Vector3(0.0, -0.018, 1.234)],
	"neck": ["chest", Vector3(0.0, -0.190, 1.380)],
	"head": ["neck", Vector3(0.0, -0.310, 1.420)],
	"upperarm.L": ["chest", Vector3(0.180, -0.220, 1.340)],
	"forearm.L": ["upperarm.L", Vector3(0.240, -0.345, 1.060)],
	"hand.L": ["forearm.L", Vector3(0.215, -0.560, 0.925)],
	"grip.L": ["hand.L", Vector3(0.210, -0.620, 0.885)],
	"thigh.L": ["pelvis", Vector3(0.090, 0.190, 1.050)],
	"shin.L": ["thigh.L", Vector3(0.100, -0.170, 0.797)],
	"foot.L": ["shin.L", Vector3(0.110, -0.063, 0.371)],
	"cleat.L": ["foot.L", Vector3(0.115, -0.170, 0.270)],
	"heel.L": ["foot.L", Vector3(0.115, 0.018, 0.296)],
	"hair_tail.1": ["head", Vector3(0.0, -0.250, 1.390)],
}
## Ракурсы брифа раздел 14 (Blender): камера, цель, FOV, углы шатуна.
const BRIEF_VIEWS: Dictionary = {
	"work": [Vector3(0.49, 3.77, 2.10), Vector3(0.0, -6.0, 0.60), 55.0, [0, 90, 180, 270]],
	"side_r": [Vector3(-2.8, -0.1, 0.95), Vector3(0.0, -0.1, 0.85), 40.0, [0, 90, 180, 270]],
	"hips_r": [Vector3(-1.3, 0.15, 0.85), Vector3(0.0, 0.05, 0.75), 35.0, [0, 90, 180, 270]],
	"rear34_l": [Vector3(1.5, 2.0, 1.55), Vector3(0.0, 0.05, 0.95), 40.0, [90]],
	"front34_r": [Vector3(-1.6, -2.2, 1.35), Vector3(0.0, -0.25, 1.05), 40.0, [90]],
	"head_34": [Vector3(-0.7, -1.1, 1.55), Vector3(0.0, -0.38, 1.42), 30.0, [90]],
}


func _mirror(name: String) -> String:
	return name.replace(".L", ".R")


func test_25_bones_unique_names_parents_before_children() -> void:
	var names := RiderRig.bone_names()
	assert_eq(names.size(), RiderRig.BONE_COUNT)
	assert_eq(RiderRig.BONE_COUNT, 25)
	assert_lte(names.size(), RiderRig.MAX_BONES, "REQ-D3D-09 п.7: костей ≤ 28")
	var seen: Dictionary = {}
	for b in RiderRig.BONES:
		assert_false(seen.has(b[0]), "имя кости уникально: %s" % b[0])
		var parent: String = b[1]
		if parent.is_empty():
			assert_eq(b[0], "pelvis", "корень — pelvis")
		else:
			assert_true(seen.has(parent), "родитель %s раньше %s" % [parent, b[0]])
		seen[b[0]] = true


func test_table_matches_brief_names_parents_positions_in_blender_coords() -> void:
	var expected: Dictionary = {}
	for name in BRIEF:
		expected[name] = BRIEF[name]
		if name.ends_with(".L"):
			var p: Vector3 = BRIEF[name][1]
			expected[_mirror(name)] = [_mirror(BRIEF[name][0]), Vector3(-p.x, p.y, p.z)]
	expected["hair_tail.2"] = ["hair_tail.1", null]
	assert_eq(RiderRig.bone_names().size(), expected.size(), "в таблице кода ровно кости брифа")
	for name in expected:
		assert_true(RiderRig.index_of(name) >= 0, "кость %s есть" % name)
		assert_eq(RiderRig.parent_of(name), expected[name][0], "родитель %s" % name)
		if expected[name][1] != null:
			var b: Vector3 = RiderRig.to_blender(RiderRig.head(name))
			assert_lt(b.distance_to(expected[name][1]), 1e-6, "начало %s: %s (бриф %s)" % [name, b, expected[name][1]])


func test_left_side_is_negative_x_in_godot_and_positive_in_blender() -> void:
	assert_lt(RiderRig.head("thigh.L").x, 0.0, "Godot: .L — x < 0 (правая сторона гонщика +X)")
	assert_gt(RiderRig.head("thigh.R").x, 0.0)
	assert_gt(RiderRig.to_blender(RiderRig.head("thigh.L")).x, 0.0, "Blender: .L — +X")
	for name in RiderRig.bone_names():
		if name.ends_with(".L"):
			var l: Vector3 = RiderRig.head(name)
			var r: Vector3 = RiderRig.head(_mirror(name))
			assert_lt(Vector3(-l.x, l.y, l.z).distance_to(r), 1e-6, "%s зеркально %s" % [_mirror(name), name])


func test_sockets_and_deform_bones() -> void:
	var sockets: Array[String] = []
	for name in RiderRig.bone_names():
		if RiderRig.is_socket(name):
			sockets.append(name)
	sockets.sort()
	assert_eq(sockets, ["cleat.L", "cleat.R", "grip.L", "grip.R", "heel.L", "heel.R"], "6 сокетов без весов")
	assert_true(RiderRig.deforms("hair_tail.1") and RiderRig.deforms("hair_tail.2"), "2 кости хвоста")


func test_link_lengths_from_brief() -> void:
	for s in [".L", ".R"]:
		assert_almost_eq(RiderRig.span("thigh" + s, "shin" + s), 0.44, 0.001, "бедро 0.44")
		assert_almost_eq(RiderRig.span("shin" + s, "foot" + s), 0.44, 0.001, "голень 0.44")
		assert_almost_eq(RiderRig.span("upperarm" + s, "forearm" + s), 0.31, 0.005, "плечо 0.31")
		assert_almost_eq(RiderRig.span("forearm" + s, "grip" + s), 0.33, 0.005, "локоть — центр ладони 0.33")
		assert_almost_eq(RiderRig.span("cleat" + s, "heel" + s), 0.19, 0.002, "пятка 0.19 позади шипа")
	assert_almost_eq(RiderRig.span("thigh.L", "thigh.R"), 0.18, 1e-6, "между тазобедренными 0.18")
	assert_almost_eq(RiderRig.span("upperarm.L", "upperarm.R"), 0.36, 1e-6, "между плечевыми 0.36")
	var hips: Vector3 = (RiderRig.head("thigh.L") + RiderRig.head("thigh.R")) * 0.5
	var shoulders: Vector3 = (RiderRig.head("upperarm.L") + RiderRig.head("upperarm.R")) * 0.5
	assert_almost_eq(hips.distance_to(shoulders), 0.50, 0.02, "таз — плечи 0.50")
	var torso_deg: float = rad_to_deg(atan2(shoulders.y - hips.y, hips.z - shoulders.z))
	assert_almost_eq(torso_deg, 35.0, 1.0, "наклон корпуса 35°")
	var tail: float = RiderRig.span("hair_tail.1", "hair_tail.2")
	assert_between(tail, RiderRig.HAIR_TAIL_MIN_M, RiderRig.HAIR_TAIL_MAX_M, "хвост 0.09–0.10")


func test_rest_is_symmetric_right_leg_at_crank_90() -> void:
	# Шип rest — на оси правой педали при φ = 90° (педаль впереди): BB + (±0.115, 0, −0.17).
	var pedal := RiderRig.BB + Vector3(RiderRig.PEDAL_X_M, 0.0, -RiderRig.CRANK_LENGTH_M)
	assert_lt(RiderRig.head("cleat.R").distance_to(pedal), 1e-6)
	assert_almost_eq(rad_to_deg(RiderRig.rest_sole_pitch_rad()), -8.0, 0.5, "линия подошвы rest −8° (бриф 5.2)")
	# Ред. 3: в игре при φ = 90° стопа на 6° площе rest.
	assert_almost_eq(rad_to_deg(RiderRig.foot_pitch_rad(RiderRig.REST_CRANK_RAD)), -2.0, 0.5, "θ(90°) ≈ −2°")


## Контрольные позы брифа 5.4 (ред. 3): длины бедра и голени, угол колена, угол стопы по кривой.
func test_control_poses_keep_links_and_follow_foot_curve() -> void:
	assert_eq(RiderRig.CONTROL_POSES.size(), 4)
	var hip: Vector3 = RiderRig.head("thigh.R")
	var l: float = RiderRig.CRANK_LENGTH_M
	for pose in RiderRig.CONTROL_POSES:
		var phi: float = deg_to_rad(float(pose[0]))
		var cleat: Vector3 = pose[1]
		var foot: Vector3 = pose[2]
		var knee: Vector3 = pose[3]
		var pedal := RiderRig.BB + Vector3(RiderRig.PEDAL_X_M, l * cos(phi), -l * sin(phi))
		assert_lt(cleat.distance_to(pedal), 0.002, "φ=%d: шип на оси педали" % pose[0])
		assert_almost_eq(hip.distance_to(knee), 0.44, 0.002, "φ=%d: бедро" % pose[0])
		assert_almost_eq(knee.distance_to(foot), 0.44, 0.002, "φ=%d: голень" % pose[0])
		var a: Vector3 = Vector3(0.0, hip.y - knee.y, hip.z - knee.z)
		var b: Vector3 = Vector3(0.0, foot.y - knee.y, foot.z - knee.z)
		assert_almost_eq(rad_to_deg(a.angle_to(b)), float(pose[4]), 1.5, "φ=%d: угол колена" % pose[0])
		assert_almost_eq(rad_to_deg(RiderRig.foot_pitch_rad(phi)), float(pose[5]), 0.5, "φ=%d: θ по кривой" % pose[0])
		var bl: Vector3 = RiderRig.to_blender(cleat)
		assert_true(bl.x < 0.0, "Blender: правая нога — −X")


func test_foot_pitch_curve_within_tolerances() -> void:
	var ranges := {0: [-25.0, 0.0], 90: [-12.0, 8.0], 180: [-35.0, -10.0], 270: [-28.0, -5.0]}
	for deg in ranges:
		var th: float = rad_to_deg(RiderRig.foot_pitch_rad(deg_to_rad(float(deg))))
		assert_between(th, ranges[deg][0], ranges[deg][1], "θ(%d°) = %.1f°" % [deg, th])
	for i in 24:
		var th: float = rad_to_deg(RiderRig.foot_pitch_rad(deg_to_rad(15.0 * i)))
		assert_between(th, -35.0, 10.0, "θ за оборот")


func test_axis_conversions() -> void:
	var p := Vector3(0.21, 0.885, -0.62)
	assert_eq(RiderRig.to_blender(p), Vector3(-0.21, -0.62, 0.885))
	assert_lt(RiderRig.from_blender(RiderRig.to_blender(p)).distance_to(p), 1e-7)
	assert_lt(RiderRig.from_gltf(RiderRig.to_gltf(p)).distance_to(p), 1e-7)
	assert_lt((RiderRig.gltf_flip() * p).distance_to(RiderRig.to_gltf(p)), 1e-6)
	# Экспорт Blender «+Y Up»: glTF = (x_b, z_b, −y_b) — то же, что to_gltf из Godot.
	var b: Vector3 = RiderRig.to_blender(p)
	assert_lt(Vector3(b.x, b.z, -b.y).distance_to(RiderRig.to_gltf(p)), 1e-7)


func test_build_skeleton_global_rest_equals_table() -> void:
	var skel := Skeleton3D.new()
	RiderRig.build_skeleton(skel)
	assert_eq(skel.get_bone_count(), RiderRig.BONE_COUNT)
	for b in RiderRig.BONES:
		var i: int = skel.find_bone(b[0])
		assert_lt(skel.get_bone_global_rest(i).origin.distance_to(b[2]), 1e-5, b[0])
		var parent: int = skel.get_bone_parent(i)
		assert_eq(skel.get_bone_name(parent) if parent >= 0 else "", b[1], "родитель %s" % b[0])
	skel.free()


func test_reference_views_match_brief_and_work_camera() -> void:
	assert_eq(RiderRig.ARTIST_VIEWS.size(), BRIEF_VIEWS.size())
	for v in RiderRig.VIEWS:
		if not RiderRig.ARTIST_VIEWS.has(v[0]):
			continue
		var want: Array = BRIEF_VIEWS[v[0]]
		assert_lt(RiderRig.to_blender(v[1]).distance_to(want[0]), 1e-6, "%s: камера" % v[0])
		assert_lt(RiderRig.to_blender(v[2]).distance_to(want[1]), 1e-6, "%s: цель" % v[0])
		assert_eq(v[3], want[2], "%s: FOV" % v[0])
		assert_eq(v[4], want[3], "%s: углы шатуна" % v[0])
	# `work` — рабочая камера сцены: 3.8 м назад с поворотом CAMERA_SIDE_RAD, 2.1 м вверх.
	var side: float = RideScene.CAMERA_SIDE_RAD
	var cam := Vector3(sin(side) * RideScene.CAMERA_BACK_M, RideScene.CAMERA_UP_M, cos(side) * RideScene.CAMERA_BACK_M)
	assert_lt(cam.distance_to(RiderRig.VIEWS[0][1]), 0.01, "work = камера RideScene")
	var target := Vector3(0.0, RideScene.CAMERA_LOOK_UP_M, -RideScene.CAMERA_LOOK_AHEAD_M)
	assert_lt(target.distance_to(RiderRig.VIEWS[0][2]), 1e-6)
	# Ред. 3: `rear_low` (арт-библия, Godot) — 7-й ракурс, углы через 45°.
	var low: Array = RiderRig.VIEWS[RiderRig.VIEWS.size() - 1]
	assert_eq(low[0], "rear_low")
	assert_eq(low[1], Vector3(0.0, 1.15, 3.0))
	assert_eq(low[2], Vector3(0.0, 0.80, 0.0))
	assert_eq(low[3], 45.0)
	assert_eq(low[4], [0, 45, 90, 135, 180, 225, 270, 315])
