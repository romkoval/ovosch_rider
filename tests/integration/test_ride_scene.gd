extends GutTest
## Интеграционные тесты 3D-сцены заезда (REQ-D3D-01 крит. 1, 2; D3D-02 через SpeedModel; D3D-03 крит. 1, 2;
## D3D-04 крит. 1–3; D3D-05 крит. 2, 4 по docs/perf_budget.md; D3D-06 крит. 1–3).

const SCENE: String = "res://src/scene3d/ride_scene.tscn"
const FRAME: float = 1.0 / 60.0

var _trainer: FakeTrainer
var _session: WorkoutSession
var _profile: Profile


## Прямая трасса — вторая реализация Track для D3D-06 крит. 2.
class StraightTrack extends Track:
	var _len: float
	func _init(length: float = 5000.0) -> void:
		_len = length
	func length_m() -> float:
		return _len
	func is_loop() -> bool:
		return false
	func sample_into(distance_m: float, out: TrackSample) -> void:
		var s := wrap_distance(distance_m)
		out.position = Vector3(0.0, 0.0, -s)
		out.forward = Vector3.FORWARD
		out.up = Vector3.UP
		out.grade = 0.0


func before_each() -> void:
	_trainer = FakeTrainer.new(9)
	_trainer.connect_delay_sec = 0.0
	_trainer.power_noise_w = 0.0
	_trainer.power_tau_sec = 0.01
	_trainer.cadence_noise_rpm = 0.0
	_trainer.connect_device("ride")
	_profile = Profile.create("R")
	_profile.ftp_w = 200
	_profile.weight_kg = 75.0


func _scene() -> RideScene:
	var s: RideScene = load(SCENE).instantiate()
	add_child_autofree(s)
	return s


func _plan(power_w: float = 200.0, sec: int = 600) -> Workout:
	var steps: Array[WorkoutStep] = [WorkoutStep.watts(sec, power_w)]
	return Workout.make("ride", steps)


func _bound_scene(power_w: float = 200.0) -> RideScene:
	var s := _scene()
	_session = WorkoutSession.new(_plan(power_w), _trainer, 200, 1.0, _profile.weight_kg)
	s.bind(_session, _profile)
	_session.start()
	return s


## Секунда сессии + 60 кадров сцены.
func _second(s: RideScene) -> void:
	_session.tick(1.0)
	for i in 60:
		s.advance(FRAME)


func _budget_from_doc() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://docs/perf_budget.md")
	assert_false(text.is_empty(), "docs/perf_budget.md существует")
	var out := {}
	for pair in [["mesh_instances", "MeshInstance3D"], ["materials", "Уникальных материалов"], ["lights", "Источников света"], ["multimesh_instances", "Экземпляров в `MultiMesh`"]]:
		var re := RegEx.create_from_string("\\| [^|]*" + pair[1] + "[^|]*\\| *(\\d+) *\\|")
		var m := re.search(text)
		assert_not_null(m, "в документе есть строка бюджета «%s»" % pair[1])
		if m != null:
			out[pair[0]] = int(m.get_string(1))
	return out


# ---------------------------------------------------------------------------
# Структура сцены (D3D-01 крит. 1)
# ---------------------------------------------------------------------------

func test_scene_has_rider_road_camera_light_environment() -> void:
	var s := _scene()
	assert_not_null(s.rider())
	assert_not_null(s.camera())
	assert_not_null(s.road(), "дорога построена при готовности")
	assert_not_null(s.props(), "объекты окружения одним MultiMeshInstance3D")
	assert_true(s.get_node("%Sun") is DirectionalLight3D)
	assert_not_null((s.get_node("%WorldEnvironment") as WorldEnvironment).environment)
	assert_true(s.track is LoopTrack)
	assert_true(s.camera().current)


func test_perf_budget_doc_matches_constants_and_scene_fits() -> void:
	var budget := _budget_from_doc()
	assert_eq(budget["mesh_instances"], PerfBudget.MAX_MESH_INSTANCES)
	assert_eq(budget["materials"], PerfBudget.MAX_MATERIALS)
	assert_eq(budget["lights"], PerfBudget.MAX_LIGHTS)
	assert_eq(budget["multimesh_instances"], PerfBudget.MAX_MULTIMESH_INSTANCES)
	var s := _scene()
	var counts := PerfBudget.count(s)
	assert_true(counts["mesh_instances"] <= budget["mesh_instances"], "MeshInstance3D: %d ≤ %d" % [counts["mesh_instances"], budget["mesh_instances"]])
	assert_true(counts["materials"] <= budget["materials"], "материалов: %d ≤ %d" % [counts["materials"], budget["materials"]])
	assert_true(counts["lights"] <= budget["lights"], "света: %d ≤ %d" % [counts["lights"], budget["lights"]])
	assert_true(counts["multimesh_instances"] <= budget["multimesh_instances"])
	assert_gt(counts["mesh_instances"], 3, "велосипедист и дорога присутствуют")


func test_project_settings_do_not_cap_fps_below_60() -> void:
	var max_fps: int = int(ProjectSettings.get_setting("application/run/max_fps", 0))
	assert_true(max_fps == 0 or max_fps >= 60, "REQ-D3D-05 крит. 2: max_fps=%d" % max_fps)
	assert_true(int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60)) >= PerfBudget.MIN_PHYSICS_TICKS_PER_SECOND)


func test_no_allocations_in_per_frame_methods_of_scene3d() -> void:
	var re := RegEx.create_from_string("\\.new\\(|instantiate\\(|\\[\\]|\\{\\}|\\bstr\\(|\\bArray\\(|\\bDictionary\\(|Packed[A-Za-z0-9]*Array\\(|\\bload\\(|\\bpreload\\(")
	var offenders: Array[String] = []
	var dir := DirAccess.open("res://src/scene3d")
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var path := "res://src/scene3d/" + f
		var in_frame := false
		var n := 0
		for raw in FileAccess.get_file_as_string(path).split("\n"):
			n += 1
			var line: String = raw.substr(0, raw.find("#")) if raw.find("#") != -1 else raw
			if line.begins_with("func "):
				in_frame = line.begins_with("func _process(") or line.begins_with("func _physics_process(") or line.begins_with("func advance(")
				continue
			if in_frame and re.search(line) != null:
				offenders.append("%s:%d %s" % [path, n, line.strip_edges()])
	assert_eq(offenders, [], "REQ-D3D-05 крит. 4: аллокации в per-frame коде: %s" % str(offenders))


# ---------------------------------------------------------------------------
# Движение и скорость (D3D-02, D3D-03)
# ---------------------------------------------------------------------------

func test_60s_at_200w_trainer_speed_gives_distance_v_t_within_10pct() -> void:
	var s := _bound_scene(200.0)
	var start := s.rider_position()
	for i in 60:
		_second(s)
	assert_eq(_session.samples.speed_source, SampleStream.SPEED_SOURCE_TRAINER)
	assert_almost_eq(s.speed_kmh, 34.0, 1.0, "скорость станка 34 км/ч при 200 Вт")
	var expected := 34.0 / 3.6 * 60.0
	assert_almost_eq(s.distance_m, expected, expected * 0.10, "дистанция ≈ v·t ± 10 %%: %.1f" % s.distance_m)
	assert_gt(s.rider_position().distance_to(start), 100.0, "позиция на трассе изменилась")


func test_model_speed_when_trainer_has_no_speed_field() -> void:
	_trainer.emit_speed = false
	var s := _bound_scene(200.0)
	for i in 60:
		_second(s)
	assert_eq(_session.samples.speed_source, SampleStream.SPEED_SOURCE_MODEL)
	assert_almost_eq(s.speed_kmh, SpeedModel.steady_speed_kmh(200.0, 75.0), 1.0, "REQ-D3D-02: модель по мощности и весу")
	assert_almost_eq(s.speed_kmh, 34.0, 3.0)
	assert_gt(s.distance_m, 400.0)


func test_rider_follows_track_position_and_orientation() -> void:
	var s := _bound_scene()
	for i in 20:
		_second(s)
	var expected := s.track.sample(s.distance_m)
	assert_lt(s.rider_position().distance_to(expected.position), 0.05)
	var rider_forward: Vector3 = -s.rider().global_transform.basis.z
	assert_gt(rider_forward.dot(expected.forward), 0.99, "велосипедист смотрит вдоль дороги")


func test_80km_wrap_keeps_rider_on_track_and_segments_constant() -> void:
	var s := _scene()
	s.apply_telemetry(250, true, 90, true, 40.0, true)
	var segments_before: int = int(s.road().get_meta("segments"))
	var max_radius: float = (s.track as LoopTrack).radius_m * 1.3 + 5.0
	for i in 7200:
		s.advance(1.0)  # кадр длиннее MAX_FRAME_DELTA клампится — двигаем по 0.25 с
	for i in 28800:
		s.advance(0.25)
	assert_true(s.distance_m < s.track.length_m(), "дистанция оборачивается")
	assert_true(s.rider_position().is_finite())
	assert_lt(Vector2(s.rider_position().x, s.rider_position().z).length(), max_radius, "REQ-D3D-03 крит. 1: всегда на дороге")
	assert_eq(int(s.road().get_meta("segments")), segments_before, "REQ-D3D-03 крит. 2: число сегментов не растёт")
	assert_eq(PerfBudget.count(s)["mesh_instances"], PerfBudget.count(s)["mesh_instances"])


# ---------------------------------------------------------------------------
# Педалирование (D3D-04)
# ---------------------------------------------------------------------------

func test_pedal_speed_scale_1_5_at_90rpm_and_1_0_at_60rpm() -> void:
	var s := _scene()
	s.apply_telemetry(200, true, 90, true, 30.0, true)
	for i in 180:
		s.advance(FRAME)
	assert_almost_eq(s.rider().speed_scale, 1.5, 0.02, "REQ-D3D-04 крит. 1: 90 rpm → 1.5 об/с")
	assert_true(s.rider().is_pedaling())
	s.apply_telemetry(200, true, 60, true, 30.0, true)
	for i in 180:
		s.advance(FRAME)
	assert_almost_eq(s.rider().speed_scale, 1.0, 0.02, "60 rpm → 1.0 об/с")


func test_zero_or_no_cadence_stops_pedaling() -> void:
	var s := _scene()
	s.apply_telemetry(200, true, 90, true, 30.0, true)
	for i in 120:
		s.advance(FRAME)
	s.apply_telemetry(0, true, 0, true, 10.0, true)
	for i in 180:
		s.advance(FRAME)
	assert_lt(s.rider().speed_scale, Rider.STOP_THRESHOLD, "REQ-D3D-04 крит. 2: каденс 0 → стоп")
	assert_false(s.rider().is_pedaling())
	s.apply_telemetry(200, true, 90, true, 30.0, true)
	for i in 60:
		s.advance(FRAME)
	s.apply_telemetry(200, true, 0, false, 30.0, true)
	for i in 180:
		s.advance(FRAME)
	assert_false(s.rider().is_pedaling(), "«нет данных» каденса → стоп")


func test_cadence_change_from_session_applies_by_next_sample_and_is_smoothed() -> void:
	var s := _bound_scene()
	_trainer.set_cadence_sequence([90])
	_second(s)
	assert_almost_eq(s.rider().target_speed_scale, 1.5, 1e-6, "REQ-D3D-04 крит. 3: цель обновлена на следующем сэмпле")
	_trainer.set_cadence_sequence([0])
	_session.tick(1.0)
	assert_almost_eq(s.rider().target_speed_scale, 0.0, 1e-6)
	var before := s.rider().speed_scale
	s.advance(FRAME)
	assert_true(s.rider().speed_scale < before and s.rider().speed_scale > 0.5, "без рывка: сглаживание τ = 0.5 с")
	for i in 180:
		s.advance(FRAME)
	assert_false(s.rider().is_pedaling())


func test_wheels_rotate_with_speed() -> void:
	var s := _scene()
	var wheel: Node3D = s.rider().get_node("%FrontWheel")
	var before := wheel.transform.basis
	s.apply_telemetry(200, true, 90, true, 36.0, true)
	for i in 30:
		s.advance(FRAME)
	assert_false(before.is_equal_approx(wheel.transform.basis), "колесо повернулось")


# ---------------------------------------------------------------------------
# Камера (D3D-01)
# ---------------------------------------------------------------------------

func test_camera_is_behind_and_above_rider_with_constant_offset() -> void:
	var s := _bound_scene()
	for i in 10:
		_second(s)
	var offsets: Array[Vector3] = []
	for i in 5:
		_second(s)
		offsets.append(s.camera_offset())
	for off in offsets:
		assert_lt(off.dot(s.rider_forward()), 0.0, "камера позади велосипедиста")
		assert_almost_eq(off.y, RideScene.CAMERA_UP_M, 0.1, "REQ-D3D-01 крит. 1: высота постоянна ±0.1 м")
		assert_almost_eq(Vector2(off.x, off.z).length(), RideScene.CAMERA_BACK_M, 0.1, "расстояние постоянно ±0.1 м")
	assert_almost_eq(offsets[0].length(), offsets[4].length(), 0.1)


func test_rider_in_camera_frustum_at_0_and_60_kmh() -> void:
	var s := _scene()
	for speed in [0.0, 60.0]:
		s.apply_telemetry(300, true, 90, true, speed, true)
		for i in 240:
			s.advance(FRAME)
		var point := s.rider_position() + Vector3.UP * 1.0
		assert_true(s.camera().is_position_in_frustum(point), "REQ-D3D-01 крит. 2: велосипедист в кадре при %.0f км/ч" % speed)
		assert_true(s.camera().is_position_behind(point) == false)


# ---------------------------------------------------------------------------
# Подмена трассы и окружения (D3D-06)
# ---------------------------------------------------------------------------

func test_straight_track_swap_keeps_movement_and_pedaling_tests_passing() -> void:
	var s := _scene()
	s.set_track(StraightTrack.new(5000.0))
	_session = WorkoutSession.new(_plan(200.0), _trainer, 200, 1.0, _profile.weight_kg)
	s.bind(_session, _profile)
	_session.start()
	_trainer.set_cadence_sequence([90])
	for i in 60:
		_second(s)
	var expected := 34.0 / 3.6 * 60.0
	assert_almost_eq(s.distance_m, expected, expected * 0.10, "REQ-D3D-06 крит. 2: та же дистанция на другой трассе")
	assert_almost_eq(s.rider_position().z, -s.distance_m, 0.5, "позиция по прямой трассе")
	assert_almost_eq(s.rider().speed_scale, 1.5, 0.05, "педалирование не зависит от трассы")
	assert_lt(s.camera_offset().dot(Vector3.FORWARD), 0.0)
	assert_eq(int(s.road().get_meta("segments")), RoadBuilder.MAX_SEGMENTS, "дорога перестроена под новую трассу")


func test_straight_track_clamps_at_end_instead_of_wrapping() -> void:
	var s := _scene()
	s.set_track(StraightTrack.new(100.0))
	s.apply_telemetry(200, true, 90, true, 36.0, true)
	for i in 100:
		s.advance(0.25)  # 250 м при 10 м/с
	assert_almost_eq(s.rider_position().z, -100.0, 0.01, "не петля — кламп на конце")


func test_environment_set_swap_changes_sky_and_road_material() -> void:
	var env := EnvironmentSet.new()
	env.sky_color = Color.RED
	env.road_material = StandardMaterial3D.new()
	env.prop_spacing_m = 50.0
	var s: RideScene = load(SCENE).instantiate()
	s.environment_set = env
	add_child_autofree(s)
	assert_eq((s.get_node("%WorldEnvironment") as WorldEnvironment).environment.background_color, Color.RED)
	assert_eq(s.road().get_active_material(0), env.road_material, "REQ-D3D-06 крит. 1: окружение через ресурс")
	assert_true(s.props().multimesh.instance_count <= PerfBudget.MAX_MULTIMESH_INSTANCES)


func test_set_track_before_ready_builds_road_after_entering_tree() -> void:
	var s: RideScene = load(SCENE).instantiate()
	s.set_track(StraightTrack.new(500.0))
	assert_null(s.road(), "до входа в дерево дорога не строится")
	add_child_autofree(s)
	assert_not_null(s.road(), "заранее заданная трасса (сценарий GPX) построена в _ready")
	assert_not_null(s.props())
	assert_true(s.track is StraightTrack, "трасса не подменена на LoopTrack")
	assert_almost_eq(s.rider_position().z, 0.0, 1e-6)


func test_unbind_zeroes_speed_and_scene_freezes() -> void:
	var s := _bound_scene()
	for i in 10:
		_second(s)
	assert_gt(s.speed_kmh, 20.0)
	s.unbind()
	assert_eq(s.speed_kmh, 0.0, "после unbind скорость обнулена")
	var dist := s.distance_m
	for i in 60:
		s.advance(FRAME)
	assert_eq(s.distance_m, dist, "сцена замерла")


func test_camera_distance_constant_through_sharp_turns() -> void:
	var s := _scene()
	s.set_track(LoopTrack.new(3, 40.0, 0.4, 6, 0.0))  # маленькая петля — крутые повороты
	s.apply_telemetry(300, true, 90, true, 40.0, true)
	for i in 600:
		s.advance(FRAME)
		var off := s.camera_offset()
		assert_almost_eq(Vector2(off.x, off.z).length(), RideScene.CAMERA_BACK_M, 0.05, "дистанция камеры не укорачивается на поворотах (кадр %d)" % i)
		assert_almost_eq(off.y, RideScene.CAMERA_UP_M, 1e-3)


func test_scene3d_doc_describes_track_interface() -> void:
	var text := FileAccess.get_file_as_string("res://docs/scene3d.md")
	assert_false(text.is_empty(), "REQ-D3D-06 крит. 3: docs/scene3d.md существует")
	for word in ["Track", "sample_into", "EnvironmentSet", "RideScene", "GPX"]:
		assert_string_contains(text, word)


func test_bind_unbind_and_finished_stops_pedaling() -> void:
	var s := _bound_scene()
	assert_true(s.is_bound())
	_trainer.set_cadence_sequence([90])
	for i in 3:
		_second(s)
	assert_true(s.rider().target_speed_scale > 1.0)
	_session.stop()
	assert_almost_eq(s.rider().target_speed_scale, 0.0, 1e-6, "финиш → педалирование остановлено")
	s.unbind()
	assert_false(s.is_bound())
	var dist := s.distance_m
	_session.tick(1.0)
	assert_eq(s.distance_m, dist, "после unbind сессия сцену не двигает")


func test_workout_screen_binds_ride_scene_under_hud() -> void:
	var screen: WorkoutScreen = load("res://src/ui/workout/workout_screen.tscn").instantiate()
	screen.keep_awake_setter = func(_on: bool) -> void: pass
	add_child_autofree(screen)
	assert_not_null(screen.ride_scene())
	assert_true(screen.get_child(0) is SubViewportContainer, "3D-фон — первый ребёнок, HUD поверх")
	screen.setup(_plan(200.0, 30), _profile, _trainer, AppState.new(ProfileRepository.new("user://test_ride_tmp/")))
	assert_true(screen.start())
	assert_true(screen.ride_scene().is_bound())
	for i in 5:
		screen.session().tick(1.0)
		screen.ride_scene().advance(1.0)
	assert_gt(screen.ride_scene().distance_m, 0.0, "сцена двигается от телеметрии сессии")
	screen.confirm_stop()
	assert_false(screen.ride_scene().is_bound(), "после завершения сцена отвязана")


func test_pause_stops_rider_and_resume_continues_by_telemetry() -> void:
	# Ревью MEDIUM-2: на паузе велосипедист стоит, после возобновления едет по данным.
	var s := _bound_scene()
	_trainer.set_cadence_sequence([90])
	for i in 10:
		_second(s)
	assert_gt(s.speed_kmh, 20.0)
	_session.pause()
	assert_eq(s.speed_kmh, 0.0, "на паузе скорость сцены — 0")
	assert_eq(s.cadence_rpm, 0, "на паузе каденс сцены — 0")
	assert_almost_eq(s.rider().target_speed_scale, 0.0, 1e-6, "педалирование остановлено")
	assert_eq(s.rider().wheel_speed_kmh, 0.0, "колёса остановлены")
	var dist := s.distance_m
	for i in 5:
		_second(s)
	assert_eq(s.distance_m, dist, "на паузе дистанция не растёт")
	assert_false(s.rider().is_pedaling())
	_session.resume()
	for i in 3:
		_second(s)
	assert_gt(s.speed_kmh, 20.0, "после возобновления скорость — по телеметрии")
	assert_gt(s.distance_m, dist, "движение продолжилось")
	assert_almost_eq(s.rider().target_speed_scale, 1.5, 1e-6, "каденс снова по телеметрии")


func test_rider_is_advanced_only_by_scene_once_per_frame() -> void:
	# Ревью LOW-5: `Rider.advance` вызывает только `RideScene.advance` (не ещё и `Rider._process`).
	var s := _scene()
	assert_false(s.rider().is_processing(), "собственный _process велосипедиста выключен")
	s.apply_telemetry(200, true, 90, true, 36.0, true)
	s.set_process(false)
	var wheel: Node3D = s.rider().get_node("%FrontWheel")
	var before := wheel.transform.basis
	var scale_before := s.rider().speed_scale
	for i in 3:
		await get_tree().process_frame
	assert_true(before.is_equal_approx(wheel.transform.basis), "без кадра сцены колёса не крутятся")
	assert_eq(s.rider().speed_scale, scale_before, "без кадра сцены сглаживание не идёт")
	s.advance(FRAME)
	var angle := 36.0 / 3.6 / Rider.WHEEL_RADIUS_M * FRAME
	assert_true((before * Basis(Vector3.RIGHT, angle)).is_equal_approx(wheel.transform.basis), "один кадр сцены — один поворот колеса")
