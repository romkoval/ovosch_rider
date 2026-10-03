extends GutTest
## Интеграционные тесты стилизованного мира и велосипедиста в сцене (REQ-D3D-07 крит. 1–5):
## мир построен и укладывается в бюджет, земля не отбрасывает теней, ноги следуют за
## педалями, в повороте велосипедист наклоняется внутрь, на прямой — нет, камера в три
## четверти держит постоянную дистанцию.

const SCENE: String = "res://src/scene3d/ride_scene.tscn"
const FRAME: float = 1.0 / 60.0


class StraightTrack extends Track:
	func length_m() -> float:
		return 3000.0
	func is_loop() -> bool:
		return false
	func sample_into(distance_m: float, out: TrackSample) -> void:
		out.position = Vector3(0.0, 0.0, -wrap_distance(distance_m))
		out.forward = Vector3.FORWARD
		out.up = Vector3.UP
		out.grade = 0.0


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


func _scene() -> RideScene:
	var s: RideScene = load(SCENE).instantiate()
	s.route_id = ""  # петля LoopTrack, как до T-070 (сцена по умолчанию — на трассе flat)
	add_child_autofree(s)
	return s


func test_world_nodes_built_and_within_budget() -> void:
	var s := _scene()
	var names: Array[String] = []
	for n in s.world_nodes():
		names.append(String(n.name))
	for expected in ["Roadside", "Verge", "Terrain", "Trees", "Conifers", "Bushes", "Tufts"]:
		assert_has(names, expected, "в мире есть %s" % expected)
	assert_not_null(s.terrain())
	var counts := PerfBudget.count(s)
	assert_lte(counts["mesh_instances"], PerfBudget.MAX_MESH_INSTANCES)
	assert_lte(counts["materials"], PerfBudget.MAX_MATERIALS)
	assert_lte(counts["multimesh_instances"], PerfBudget.MAX_MULTIMESH_INSTANCES)
	assert_eq(counts["lights"], 1, "один направленный свет")


func test_ground_does_not_cast_shadows() -> void:
	var s := _scene()
	assert_eq(s.road().cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	for n in s.world_nodes():
		if n.name in ["Verge", "Terrain"]:
			assert_eq((n as GeometryInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, String(n.name))


func test_sky_and_toon_materials_applied() -> void:
	var s := _scene()
	var env := (s.get_node("%WorldEnvironment") as WorldEnvironment).environment
	assert_eq(env.background_mode, Environment.BG_SKY, "небо — шейдер, не сплошная заливка")
	assert_not_null(env.sky)
	assert_true(s.road().get_active_material(0) is ShaderMaterial, "асфальт с разметкой — шейдер")
	var bike: MeshInstance3D = s.rider().get_node("%Bike")
	var mat := bike.mesh.surface_get_material(0)
	assert_true(mat is ShaderMaterial)
	assert_not_null(mat.next_pass, "у велосипедиста есть контур (вторая проходка)")


func test_world_disabled_by_environment_set() -> void:
	var env := EnvironmentSet.new()
	env.terrain_enabled = false
	env.roadside_enabled = false
	env.tree_count = 0
	env.bush_count = 0
	env.tuft_count = 0
	var s: RideScene = load(SCENE).instantiate()
	s.route_id = ""  # петля LoopTrack, как до T-070 (сцена по умолчанию — на трассе flat)
	s.environment_set = env
	add_child_autofree(s)
	assert_null(s.terrain())
	for n in s.world_nodes():
		assert_eq((n as MultiMeshInstance3D).multimesh.instance_count, 0, "пустые типы растительности")
	assert_not_null(s.road())


func test_feet_follow_pedals_through_crank_revolution() -> void:
	var s := _scene()
	var rider := s.rider()
	var crank: Node3D = rider.get_node("%Crank")
	var shoe_r: Node3D = rider.get_node("%ShoeR")
	var shoe_l: Node3D = rider.get_node("%ShoeL")
	var thigh_r: Node3D = rider.get_node("%ThighR")
	var shin_r: Node3D = rider.get_node("%ShinR")
	var arm_r: Node3D = rider.get_node("%Lean/CrankMount/Crank/CrankArm")
	for phi in [0.0, 1.0, 2.5, 4.0, 5.5]:
		crank.rotation = Vector3(phi, 0.0, 0.0)
		rider.advance(FRAME)
		var lean_inv: Transform3D = (rider.get_node("%Lean") as Node3D).global_transform.affine_inverse()
		# Ось правой педали в системе узла Lean (шатун: локальный −X — правая сторона, длина по +Y).
		var pedal_r: Vector3 = lean_inv * (arm_r.global_transform * Vector3(-RiderModel.PEDAL_X_M, RiderModel.CRANK_LENGTH_M, 0.0))
		var pedal_l: Vector3 = lean_inv * (arm_r.global_transform * Vector3(RiderModel.PEDAL_X_M, -RiderModel.CRANK_LENGTH_M, 0.0))
		assert_lt(shoe_r.position.distance_to(pedal_r + RiderModel.ANKLE_FROM_PEDAL), 0.01, "правая стопа на педали (φ=%.1f)" % phi)
		assert_lt(shoe_l.position.distance_to(pedal_l + RiderModel.ANKLE_FROM_PEDAL), 0.01, "левая стопа на педали (φ=%.1f)" % phi)
		assert_almost_eq(thigh_r.position.distance_to(shin_r.position), RiderModel.THIGH_M, 1e-3, "бедро не растягивается")
		assert_almost_eq(shin_r.position.distance_to(shoe_r.position), RiderModel.SHIN_M, 1e-3, "голень не растягивается")


func test_right_pedal_moves_forward_at_top_of_stroke() -> void:
	var s := _scene()
	var rider := s.rider()
	var crank: Node3D = rider.get_node("%Crank")
	var shoe_r: Node3D = rider.get_node("%ShoeR")
	crank.rotation = Vector3(0.0, 0.0, 0.0)
	rider.advance(FRAME)
	var top := shoe_r.position
	crank.rotation = Vector3(0.2, 0.0, 0.0)
	rider.advance(FRAME)
	assert_lt(shoe_r.position.z, top.z, "положительный угол шатуна — педаль вверху уходит вперёд (−Z)")


func test_rider_leans_into_turn_and_not_on_straight() -> void:
	var s := _scene()
	s.set_track(CircleTrack.new(60.0))  # поворот вправо, R = 60 м
	s.apply_telemetry(300, true, 90, true, 40.0, true)
	for i in 180:
		s.advance(FRAME)
	var v := 40.0 / 3.6
	var physical := atan(v * v / (9.81 * 60.0))
	assert_lt(s.lean_rad(), -physical * 0.8, "наклон вправо (внутрь поворота) не меньше физического: %.3f" % s.lean_rad())
	assert_gte(s.lean_rad(), -RideScene.LEAN_MAX_RAD - 1e-6, "наклон ограничен")
	var lean_node: Node3D = s.rider().get_node("%Lean")
	assert_almost_eq(lean_node.rotation.z, s.lean_rad(), 1e-6, "наклон применён к узлу Lean")
	var fwd: Vector3 = -s.rider().global_transform.basis.z
	assert_gt(fwd.dot(s.track.sample(s.distance_m).forward), 0.99, "направление движения не меняется от наклона")
	s.set_track(StraightTrack.new())
	s.apply_telemetry(300, true, 90, true, 40.0, true)
	for i in 120:
		s.advance(FRAME)
	assert_almost_eq(s.lean_rad(), 0.0, 1e-3, "на прямой — без наклона")


func test_lean_returns_to_zero_when_stopped() -> void:
	var s := _scene()
	s.set_track(CircleTrack.new(60.0))
	s.apply_telemetry(300, true, 90, true, 40.0, true)
	for i in 120:
		s.advance(FRAME)
	s.apply_telemetry(0, true, 0, true, 0.0, true)
	for i in 240:
		s.advance(FRAME)
	assert_almost_eq(s.lean_rad(), 0.0, 0.01, "стоя — без наклона")


func test_three_quarter_camera_keeps_constant_horizontal_distance_and_rider_in_frame() -> void:
	var s := _scene()
	s.apply_telemetry(250, true, 90, true, 35.0, true)
	for i in 300:
		s.advance(FRAME)
	var off := s.camera_offset()
	var right := s.track.sample(s.distance_m).right()
	assert_almost_eq(Vector2(off.x, off.z).length(), RideScene.CAMERA_BACK_M, 0.05)
	assert_lt(off.dot(s.rider_forward()), 0.0, "камера позади")
	var cam: Camera3D = s.camera()
	for h in [0.1, 0.9, 1.45]:
		assert_true(cam.is_position_in_frustum(s.rider_position() + Vector3.UP * h), "в кадре точка велосипедиста на высоте %.2f м" % h)
	assert_not_null(right)
