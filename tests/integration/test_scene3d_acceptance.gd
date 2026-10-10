extends GutTest
## Независимые приёмочные тесты 3D-сцены заезда (тестировщик; T-051/T-052, коммит 65715d4).
## Покрытие: REQ-D3D-01 крит. 1, 2; REQ-D3D-02 крит. 1–4 (в сцене); REQ-D3D-03 крит. 1, 2;
## REQ-D3D-04 крит. 1–3; REQ-D3D-05 крит. 2, 4; REQ-D3D-06 крит. 1–3.
## Вторая реализация `Track` — `SquareLoopTrack` (inner class) и `ShortLoopTrack` (1 м) —
## подставляются в `RideScene` без правки сцены. Сцены — headless через `add_child_autofree`.

const SCENE: String = "res://src/scene3d/ride_scene.tscn"
const WORKOUT_SCENE: String = "res://src/ui/workout/workout_screen.tscn"
const FRAME: float = 1.0 / 60.0

var _trainer: FakeTrainer
var _session: WorkoutSession
var _profile: Profile


## Квадратная замкнутая трасса со стороной `side` — вторая реализация Track (REQ-D3D-06).
class SquareLoopTrack extends Track:
	var side: float
	func _init(side_m: float = 500.0) -> void:
		side = maxf(side_m, 1.0)
	func length_m() -> float:
		return 4.0 * side
	func is_loop() -> bool:
		return true
	func sample_into(distance_m: float, out: TrackSample) -> void:
		var s := wrap_distance(distance_m)
		var seg := int(s / side) % 4
		var t := s - float(seg) * side
		var corners: Array[Vector3] = [Vector3(0, 0, 0), Vector3(side, 0, 0), Vector3(side, 0, -side), Vector3(0, 0, -side)]
		var dirs: Array[Vector3] = [Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT, Vector3.BACK]
		out.position = corners[seg] + dirs[seg] * t
		out.forward = dirs[seg]
		out.up = Vector3.UP
		out.grade = 0.0


## Петля длиной 1 м (граница).
class ShortLoopTrack extends Track:
	func length_m() -> float:
		return 1.0
	func is_loop() -> bool:
		return true
	func sample_into(distance_m: float, out: TrackSample) -> void:
		out.position = Vector3(wrap_distance(distance_m), 0.0, 0.0)
		out.forward = Vector3.RIGHT
		out.up = Vector3.UP
		out.grade = 0.0


func before_each() -> void:
	_trainer = FakeTrainer.new(11)
	_trainer.connect_delay_sec = 0.0
	_trainer.power_noise_w = 0.0
	_trainer.power_tau_sec = 0.01
	_trainer.cadence_noise_rpm = 0.0
	_trainer.connect_device("acc3d")
	_profile = Profile.create("Rider")
	_profile.ftp_w = 200
	_profile.weight_kg = 75.0
	_session = null


func _scene(track: Track = null) -> RideScene:
	var s: RideScene = load(SCENE).instantiate()
	s.route_id = ""  # петля LoopTrack, как до T-070 (сцена по умолчанию — на трассе flat)
	add_child_autofree(s)
	if track != null:
		s.set_track(track)
	return s


func _plan(power_w: float = 200.0, sec: int = 900) -> Workout:
	var steps: Array[WorkoutStep] = [WorkoutStep.watts(sec, power_w)]
	return Workout.make("ride-acc", steps)


func _bind(s: RideScene, power_w: float = 200.0, weight: float = 75.0) -> WorkoutSession:
	_profile.weight_kg = weight
	_session = WorkoutSession.new(_plan(power_w), _trainer, 200, 1.0, weight)
	s.bind(_session, _profile)
	_session.start()
	return _session


## Секунда сессии + 60 кадров сцены.
func _second(s: RideScene) -> void:
	_session.tick(1.0)
	for i in 60:
		s.advance(FRAME)


func _frames(s: RideScene, n: int) -> void:
	for i in n:
		s.advance(FRAME)


func _mesh_count(root: Node) -> int:
	return int(PerfBudget.count(root)["mesh_instances"])


# ===========================================================================
# REQ-D3D-01 — вид от третьего лица
# ===========================================================================

func test_req_d3d_01_c1_scene_has_rider_road_camera_and_camera_keeps_offset_while_moving() -> void:
	var s := _scene()
	assert_not_null(s.rider())
	assert_true(s.rider() is Rider)
	assert_not_null(s.road(), "дорога построена")
	assert_true(s.road() is MeshInstance3D)
	assert_not_null(s.camera())
	assert_true(s.camera() is Camera3D)
	assert_not_null(s.get_node("%Sun"))
	assert_not_null(s.get_node("%WorldEnvironment"))
	_bind(s)
	for i in 10:
		_second(s)
	assert_gt(s.distance_m, 50.0, "велосипедист едет")
	for i in 8:
		_second(s)
		var off := s.camera_offset()
		assert_lt(off.dot(s.rider_forward()), 0.0, "камера позади")
		assert_almost_eq(off.y, RideScene.CAMERA_UP_M, 0.1, "высота постоянна ±0.1 м")
		assert_almost_eq(Vector2(off.x, off.z).length(), RideScene.CAMERA_BACK_M, 0.1, "расстояние постоянно ±0.1 м")
		assert_true(s.camera().is_position_in_frustum(s.rider_position() + Vector3.UP), "велосипедист в кадре")


func test_req_d3d_01_c2_rider_in_frustum_at_speeds_0_to_60_kmh_on_both_tracks() -> void:
	for track in [null, SquareLoopTrack.new(400.0)]:
		var s := _scene(track)
		for speed in [0.0, 15.0, 30.0, 45.0, 60.0]:
			s.apply_telemetry(300, true, 90, true, speed, true)
			_frames(s, 240)
			var point := s.rider_position() + Vector3.UP * 1.0
			assert_true(s.camera().is_position_in_frustum(point), "в кадре при %.0f км/ч (%s)" % [speed, "LoopTrack" if track == null else "SquareLoopTrack"])
			assert_false(s.camera().is_position_behind(point))
			assert_lt(s.camera().global_position.distance_to(s.rider_position()), RideScene.CAMERA_BACK_M + RideScene.CAMERA_UP_M + 0.5)


func test_req_d3d_01_c1_camera_offset_constant_over_a_full_lap_of_loop_track() -> void:
	var s := _scene()
	s.apply_telemetry(300, true, 90, true, 40.0, true)
	_frames(s, 300) # устояться
	var lap_frames := int(ceil(s.track.length_m() / (40.0 / 3.6) * 60.0))
	var max_h_err := 0.0
	var max_v_err := 0.0
	for i in lap_frames:
		s.advance(FRAME)
		var off := s.camera_offset()
		max_h_err = maxf(max_h_err, absf(Vector2(off.x, off.z).length() - RideScene.CAMERA_BACK_M))
		max_v_err = maxf(max_v_err, absf(off.y - RideScene.CAMERA_UP_M))
	assert_lt(max_h_err, 0.1, "расстояние до камеры постоянно на всём круге (макс. отклонение %.3f м)" % max_h_err)
	assert_lt(max_v_err, 0.1, "высота камеры постоянна (макс. отклонение %.3f м)" % max_v_err)


func test_observation_sharp_90deg_corner_dips_camera_distance_but_rider_stays_in_frame() -> void:
	# Наблюдение: lerp вектора смещения на мгновенном повороте 90° укорачивает дистанцию до камеры;
	# на гладких трассах (LoopTrack, GPX) это не проявляется. Фиксируем величину и то, что кадр не теряется.
	var s := _scene(SquareLoopTrack.new(50.0))
	s.apply_telemetry(200, true, 85, true, 36.0, true)
	var min_dist := 1e9
	for i in 600:
		s.advance(FRAME)
		min_dist = minf(min_dist, Vector2(s.camera_offset().x, s.camera_offset().z).length())
		assert_true(s.camera().is_position_in_frustum(s.rider_position() + Vector3.UP), "в кадре на углу (кадр %d)" % i)
	assert_gt(min_dist, RideScene.CAMERA_BACK_M * 0.6, "просадка дистанции на углу ограничена (мин. %.2f м из %.1f)" % [min_dist, RideScene.CAMERA_BACK_M])


# ===========================================================================
# REQ-D3D-02 — скорость в сцене: только модель (п.6, У-30)
# ===========================================================================

## D3D-02 п.6 (У-30, T-169): поле скорости станка ни на что не влияет — сцена едет со скоростью
## модели из потока сессии.
func test_req_d3d_02_c2_trainer_speed_is_used_when_speed_source_is_trainer() -> void:
	_trainer.power_noise_w = 0.0
	var s := _scene()
	_bind(s, 200.0)
	for i in 40:
		_second(s)
	assert_eq(_session.samples.speed_source, SampleStream.SPEED_SOURCE_MODEL, "источник скорости — модель")
	var row := _session.samples.last_row()
	assert_almost_eq(s.speed_kmh, float(row["speed_kmh"]), 1e-6, "скорость сцены = скорость модели из потока")
	assert_almost_eq(s.speed_kmh, 34.0, 3.0, "200 Вт / 75 кг → 34 ± 3 км/ч по модели")
	var d0 := s.distance_m
	_second(s)
	assert_almost_eq(s.distance_m - d0, s.speed_kmh / 3.6, 0.05, "дистанция интегрируется по скорости")


func test_req_d3d_02_c2_model_speed_when_trainer_has_no_speed_reference_points_and_weight() -> void:
	_trainer.emit_speed = false
	var s := _scene()
	_bind(s, 200.0, 75.0)
	for i in 40:
		_second(s)
	assert_eq(_session.samples.speed_source, SampleStream.SPEED_SOURCE_MODEL)
	assert_almost_eq(s.speed_kmh, 34.0, 3.0, "200 Вт / 75 кг → 34 ± 3 км/ч")
	var v200_75 := s.speed_kmh
	# модель напрямую (apply_telemetry) — опорные точки и зависимость от массы
	var m := _scene()
	m.weight_kg = 75.0
	for i in 60:
		m.apply_telemetry(100, true, 85, true, 0.0, false)
	assert_almost_eq(m.speed_kmh, 26.0, 3.0, "100 Вт → 26 ± 3")
	for i in 60:
		m.apply_telemetry(300, true, 85, true, 0.0, false)
	assert_almost_eq(m.speed_kmh, 40.0, 3.0, "300 Вт → 40 ± 3")
	var heavy := _scene()
	heavy.weight_kg = 95.0
	for i in 60:
		heavy.apply_telemetry(200, true, 85, true, 0.0, false)
	assert_lt(heavy.speed_kmh, v200_75, "95 кг медленнее 75 кг при 200 Вт")


func test_req_d3d_02_c1_scene_speed_monotonic_in_power_and_mass() -> void:
	var prev := 0.0
	for p in [50, 100, 200, 300, 400]:
		var s := _scene()
		s.weight_kg = 75.0
		for i in 60:
			s.apply_telemetry(p, true, 85, true, 0.0, false)
		assert_gt(s.speed_kmh, prev, "%d Вт → %.1f км/ч" % [p, s.speed_kmh])
		prev = s.speed_kmh
	prev = 1e9
	for w in [55.0, 75.0, 95.0, 120.0]:
		var s := _scene()
		s.weight_kg = w
		for i in 60:
			s.apply_telemetry(200, true, 85, true, 0.0, false)
		assert_lt(s.speed_kmh, prev, "%.0f кг → %.1f км/ч" % [w, s.speed_kmh])
		prev = s.speed_kmh


func test_req_d3d_02_c3_zero_power_from_30_kmh_decays_to_zero_within_30_samples_and_standing_start_stays() -> void:
	var s := _scene()
	s.weight_kg = 75.0
	for i in 60:
		s.apply_telemetry(150, true, 85, true, 0.0, false)
	assert_gt(s.speed_kmh, 28.0, "разогнался")
	var prev := s.speed_kmh
	var stopped_at := -1
	for i in 30:
		s.apply_telemetry(0, true, 0, true, 0.0, false)
		assert_lte(s.speed_kmh, prev + 1e-9, "монотонно убывает (сэмпл %d)" % i)
		prev = s.speed_kmh
		if s.speed_kmh == 0.0 and stopped_at < 0:
			stopped_at = i + 1
	assert_true(stopped_at > 0 and stopped_at <= 30, "остановка не позже 30 с (факт %d)" % stopped_at)
	var still := _scene()
	for i in 10:
		still.apply_telemetry(0, true, 0, true, 0.0, false)
		_frames(still, 60)
	assert_eq(still.speed_kmh, 0.0, "0 Вт стоя — скорость 0")
	assert_eq(still.distance_m, 0.0, "и дистанция не растёт")


func test_req_d3d_02_c4_power_jump_0_to_400_changes_scene_speed_at_most_5_kmh_per_sample() -> void:
	var s := _scene()
	s.weight_kg = 75.0
	var prev := 0.0
	for i in 60:
		s.apply_telemetry(400, true, 95, true, 0.0, false)
		assert_lte(s.speed_kmh - prev, 5.0 + 1e-9, "сэмпл %d: прирост %.2f" % [i, s.speed_kmh - prev])
		prev = s.speed_kmh
	assert_almost_eq(s.speed_kmh, SpeedModel.steady_speed_kmh(400.0, 75.0), 0.5)


# ===========================================================================
# REQ-D3D-03 — зацикленная трасса, постоянное число сегментов
# ===========================================================================

func test_req_d3d_03_c1_loop_track_closes_and_80km_ride_never_leaves_road() -> void:
	var s := _scene()
	var track := s.track
	assert_true(track.is_loop())
	var a := track.sample(0.0)
	var b := track.sample(track.length_m())
	assert_lt(a.position.distance_to(b.position), 1e-3, "sample(0) == sample(length)")
	assert_lt(a.forward.distance_to(b.forward), 1e-3)
	s.apply_telemetry(300, true, 90, true, 40.0, true)
	var segments_before: int = s.road().get_meta("segments")
	var nodes_before := s.get_node("%EnvironmentRoot").get_child_count()
	var probe := TrackSample.new()
	var max_off := 0.0
	for sec in 7200: # 2 часа на 40 км/ч = 80 км
		for q in 4:
			s.advance(0.25)
		assert_true(s.distance_m >= 0.0 and s.distance_m < track.length_m(), "дистанция обёрнута (с %d: %.1f)" % [sec, s.distance_m])
		if sec % 60 == 0:
			track.sample_into(s.distance_m, probe)
			max_off = maxf(max_off, probe.position.distance_to(s.rider_position()))
	assert_lt(max_off, 1e-3, "велосипедист всегда на оси дороги (макс. отклонение %.4f м)" % max_off)
	assert_eq(int(s.road().get_meta("segments")), segments_before, "сегменты дороги не пересоздавались")
	assert_eq(s.get_node("%EnvironmentRoot").get_child_count(), nodes_before, "окружение не разрастается")


func test_req_d3d_03_c2_segment_count_bounded_by_constant_and_props_repeat_along_track() -> void:
	var s := _scene()
	var n: int = s.road().get_meta("segments")
	assert_lte(n, RoadBuilder.MAX_SEGMENTS)
	assert_gte(n, 8)
	assert_eq(RoadBuilder.segment_count(s.track), n)
	assert_eq(s.road().mesh.get_surface_count(), 1, "одна поверхность")
	var long_track := SquareLoopTrack.new(5000.0) # 20 км
	assert_eq(RoadBuilder.segment_count(long_track), RoadBuilder.MAX_SEGMENTS, "длинная трасса — потолок сегментов")
	var props := s.props()
	assert_not_null(props, "повторяющиеся объекты окружения построены")
	var count := props.multimesh.instance_count
	assert_gt(count, 0)
	assert_lte(count, PerfBudget.MAX_MULTIMESH_INSTANCES)
	var expected := mini(int(s.track.length_m() / s.environment_set.prop_spacing_m) * 2, PerfBudget.MAX_MULTIMESH_INSTANCES)
	assert_eq(count, expected, "объекты с шагом prop_spacing по обеим сторонам")
	# Позиции экземпляров MultiMesh в headless недоступны (буфер на dummy-RenderingServer) — проверяется визуально.
	assert_eq(props.multimesh.transform_format, MultiMesh.TRANSFORM_3D)


# ===========================================================================
# REQ-D3D-04 — педалирование по каденсу
# ===========================================================================

func test_req_d3d_04_c1_speed_scale_1_5_at_90_and_1_0_at_60_rpm_and_animation_runs() -> void:
	var s := _scene()
	var rider := s.rider()
	var anim := rider.get_node("%PedalPlayer") as AnimationPlayer
	rider.set_cadence(90)
	assert_almost_eq(rider.target_speed_scale, 1.5, 1e-9, "90 rpm → 1.5 об/с")
	_frames(s, 300)
	assert_almost_eq(rider.speed_scale, 1.5, 0.01)
	assert_almost_eq(anim.speed_scale, 1.5, 0.01, "AnimationPlayer крутит шатуны 1.5 об/с")
	assert_true(anim.is_playing())
	assert_true(rider.is_pedaling())
	# AnimationPlayer в headless продвигается только реальными кадрами; проверяем отображение
	# «1 с анимации = 1 оборот шатуна», тогда speed_scale 1.5 = 1.5 об/с.
	var pedal := anim.get_animation(Rider.PEDAL_ANIMATION)
	assert_not_null(pedal)
	assert_almost_eq(pedal.length, 1.0, 1e-9, "анимация оборота длится 1 с")
	assert_eq(pedal.loop_mode, Animation.LOOP_LINEAR)
	anim.seek(0.25, true)
	assert_almost_eq(rider.crank_rotation_rad(), PI / 2.0, 0.05, "четверть анимации — четверть оборота")
	anim.seek(0.5, true)
	assert_almost_eq(rider.crank_rotation_rad(), PI, 0.05, "половина — полоборота")
	rider.set_cadence(60)
	assert_almost_eq(rider.target_speed_scale, 1.0, 1e-9, "60 rpm → 1.0 об/с")
	_frames(s, 300)
	assert_almost_eq(rider.speed_scale, 1.0, 0.01)
	assert_almost_eq(anim.speed_scale, 1.0, 0.01)


func test_req_d3d_04_c2_zero_negative_or_missing_cadence_stops_pedaling() -> void:
	var s := _scene()
	var rider := s.rider()
	var anim := rider.get_node("%PedalPlayer") as AnimationPlayer
	rider.set_cadence(90)
	_frames(s, 300)
	assert_true(rider.is_pedaling())
	rider.set_cadence(0)
	_frames(s, 300)
	assert_false(rider.is_pedaling(), "каденс 0 → остановка")
	assert_false(anim.is_playing())
	assert_eq(anim.speed_scale, 0.0)
	rider.set_cadence(90)
	_frames(s, 300)
	rider.set_cadence(-1)
	assert_eq(rider.target_speed_scale, 0.0, "отрицательный каденс = остановка")
	_frames(s, 300)
	assert_false(rider.is_pedaling())
	# «нет данных» из потока: эмулятор молчит → has_cadence=false → стоп
	var bound := _scene()
	_bind(bound)
	_trainer.set_cadence_sequence([90])
	for i in 5:
		_second(bound)
	assert_true(bound.rider().is_pedaling())
	_trainer.inject_silence(100.0)
	for i in 6:
		_second(bound)
	assert_false(bound.rider().is_pedaling(), "без данных каденса — накат")
	assert_eq(bound.cadence_rpm, 0)


func test_req_d3d_04_c3_cadence_change_applies_by_next_sample_and_is_smoothed_without_jumps() -> void:
	var s := _scene()
	_bind(s)
	_trainer.set_cadence_sequence([60, 60, 60, 90])
	for i in 3:
		_second(s)
	assert_almost_eq(s.rider().target_speed_scale, 1.0, 1e-9)
	assert_almost_eq(s.rider().speed_scale, 1.0, 0.05)
	_session.tick(1.0) # закрылся слот с каденсом 90
	assert_almost_eq(s.rider().target_speed_scale, 1.5, 1e-9, "цель применена не позже следующего сэмпла")
	var prev := s.rider().speed_scale
	var max_jump := 0.0
	for i in 60:
		s.advance(FRAME)
		var now := s.rider().speed_scale
		assert_gte(now, prev - 1e-9, "без провалов")
		max_jump = maxf(max_jump, now - prev)
		prev = now
	assert_lt(max_jump, 0.1, "сглаживание: за кадр не более 0.1 об/с (факт %.3f)" % max_jump)
	assert_gt(s.rider().speed_scale, 1.3, "через 1 с почти догнал 1.5")
	_frames(s, 240)
	assert_almost_eq(s.rider().speed_scale, 1.5, 0.01)
	assert_lte(s.rider().speed_scale, 1.5 + 1e-6, "без перерегулирования")


# ===========================================================================
# REQ-D3D-05 крит. 2, 4 — бюджет и per-frame код
# ===========================================================================

func _doc_budget(keyword: String) -> int:
	var re := RegEx.create_from_string("\\|\\s*(\\d+)\\s*\\|")
	for line in FileAccess.get_file_as_string("res://docs/perf_budget.md").split("\n"):
		if line.contains(keyword):
			var m := re.search(line)
			if m != null:
				return int(m.get_string(1))
	return -1


func test_req_d3d_05_c2_project_does_not_cap_fps_below_60_and_physics_60() -> void:
	var max_fps := int(ProjectSettings.get_setting("application/run/max_fps", 0))
	assert_true(max_fps == 0 or max_fps >= 60, "max_fps = %d" % max_fps)
	var ticks := int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
	assert_gte(ticks, 60)
	assert_gte(ticks, PerfBudget.MIN_PHYSICS_TICKS_PER_SECOND)


func test_req_d3d_05_c4_scene_fits_budget_from_doc_and_doc_matches_constants() -> void:
	assert_eq(_doc_budget("MeshInstance3D"), PerfBudget.MAX_MESH_INSTANCES, "документ и константа: меши")
	assert_eq(_doc_budget("материалов"), PerfBudget.MAX_MATERIALS, "материалы")
	assert_eq(_doc_budget("Light3D"), PerfBudget.MAX_LIGHTS, "свет")
	assert_eq(_doc_budget("MultiMesh"), PerfBudget.MAX_MULTIMESH_INSTANCES, "мультимеш")
	var s := _scene()
	var c := PerfBudget.count(s)
	assert_lte(int(c["mesh_instances"]), _doc_budget("MeshInstance3D"), "мешей %d" % int(c["mesh_instances"]))
	assert_lte(int(c["materials"]), _doc_budget("материалов"), "материалов %d" % int(c["materials"]))
	assert_lte(int(c["lights"]), _doc_budget("Light3D"))
	assert_lte(int(c["multimesh_instances"]), _doc_budget("MultiMesh"))
	assert_gt(int(c["mesh_instances"]), 0)
	assert_gt(int(c["lights"]), 0)


func test_req_d3d_05_c4_negative_probe_61st_mesh_instance_exceeds_budget() -> void:
	var s := _scene()
	var base := _mesh_count(s)
	assert_lte(base, PerfBudget.MAX_MESH_INSTANCES)
	var to_add := PerfBudget.MAX_MESH_INSTANCES - base + 1
	var added: Array[MeshInstance3D] = []
	for i in to_add:
		var mi := MeshInstance3D.new()
		mi.name = "ProbeMesh%d" % i
		s.add_child(mi)
		added.append(mi)
	assert_eq(_mesh_count(s), PerfBudget.MAX_MESH_INSTANCES + 1, "61-й меш учтён")
	assert_gt(_mesh_count(s), PerfBudget.MAX_MESH_INSTANCES, "PerfBudget сообщает превышение")
	for mi in added:
		s.remove_child(mi)
		mi.free()
	assert_eq(_mesh_count(s), base, "проба удалена — бюджет снова соблюдён")


func test_req_d3d_05_c4_no_allocations_in_per_frame_methods_including_helpers() -> void:
	var alloc := RegEx.create_from_string("\\.new\\(|\\binstantiate\\(|(^|[^A-Za-z0-9_\\]\\)])\\[\\]|\\{\\}|\\bstr\\(|\\bArray\\(|\\bDictionary\\(|Packed[A-Za-z0-9]*Array\\(|\\bload\\(|\\bpreload\\(|\\bduplicate\\(|\" % ")
	var call_re := RegEx.create_from_string("\\b(_[a-z_0-9]+)\\(")
	var offenders: Array[String] = []
	var dir := DirAccess.open("res://src/scene3d")
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var path := "res://src/scene3d/" + f
		var bodies: Dictionary = {} # имя функции → строки [{n, text}]
		var current := ""
		var n := 0
		for raw in FileAccess.get_file_as_string(path).split("\n"):
			n += 1
			var line: String = raw.substr(0, raw.find("#")) if raw.find("#") != -1 else raw
			if line.begins_with("func ") or line.begins_with("static func "):
				var name := line.substr(line.find("func ") + 5)
				current = name.substr(0, name.find("("))
				bodies[current] = []
				continue
			if not current.is_empty() and not line.strip_edges().is_empty():
				(bodies[current] as Array).append({"n": n, "text": line})
		var roots: Array[String] = []
		for name in ["_process", "_physics_process", "advance"]:
			if bodies.has(name):
				roots.append(name)
		# один уровень вложенности: приватные помощники, вызываемые из per-frame методов
		var to_check: Array[String] = roots.duplicate()
		for root in roots:
			for entry in bodies[root]:
				for m in call_re.search_all(str(entry["text"])):
					var callee := m.get_string(1)
					if bodies.has(callee) and not to_check.has(callee):
						to_check.append(callee)
		for name in to_check:
			for entry in bodies[name]:
				if alloc.search(str(entry["text"])) != null:
					offenders.append("%s:%d (%s) %s" % [path, entry["n"], name, str(entry["text"]).strip_edges()])
	assert_eq(offenders, [], "аллокации в per-frame коде src/scene3d/: %s" % str(offenders))


func test_req_d3d_05_c4_advance_does_not_create_track_samples_or_nodes() -> void:
	var s := _scene()
	s.apply_telemetry(250, true, 90, true, 35.0, true)
	_frames(s, 60)
	var nodes_before := s.get_child_count() + s.get_node("%EnvironmentRoot").get_child_count()
	var objects_before := Performance.get_monitor(Performance.OBJECT_COUNT)
	_frames(s, 600)
	var nodes_after := s.get_child_count() + s.get_node("%EnvironmentRoot").get_child_count()
	assert_eq(nodes_after, nodes_before, "за 600 кадров узлы не создаются")
	var objects_after := Performance.get_monitor(Performance.OBJECT_COUNT)
	assert_lte(objects_after - objects_before, 2.0, "число Object-ов не растёт в кадре (Δ = %.0f)" % (objects_after - objects_before))


# ===========================================================================
# REQ-D3D-06 — подмена трассы и окружения без правки цикла
# ===========================================================================

func test_req_d3d_06_c1_c2_square_track_swap_keeps_speed_and_pedaling_behaviour() -> void:
	_trainer.emit_speed = false
	var s := _scene(SquareLoopTrack.new(300.0))
	assert_true(s.track is SquareLoopTrack)
	assert_not_null(s.road(), "дорога перестроена под новую трассу")
	assert_eq(RoadBuilder.segment_count(s.track), int(s.road().get_meta("segments")))
	_bind(s, 200.0, 75.0)
	_trainer.set_cadence_sequence([90])
	for i in 40:
		_second(s)
	assert_almost_eq(s.speed_kmh, 34.0, 3.0, "D3D-02 на другой трассе: 34 ± 3 км/ч")
	assert_almost_eq(s.rider().speed_scale, 1.5, 0.02, "D3D-04 на другой трассе: 1.5 об/с")
	var probe := TrackSample.new()
	s.track.sample_into(s.distance_m, probe)
	assert_lt(probe.position.distance_to(s.rider_position()), 1e-3, "велосипедист на квадратной трассе")
	assert_true(s.rider_position().x >= -1e-3 and s.rider_position().x <= 300.0 + 1e-3)
	var off := s.camera_offset()
	assert_almost_eq(off.y, RideScene.CAMERA_UP_M, 0.1)
	assert_almost_eq(Vector2(off.x, off.z).length(), RideScene.CAMERA_BACK_M, 0.1)


func test_req_d3d_06_c1_environment_set_swap_changes_sky_road_material_and_props_not_motion() -> void:
	var custom := EnvironmentSet.new()
	custom.sky_color = Color(0.9, 0.2, 0.1)
	custom.fog_color = Color(0.5, 0.1, 0.1)
	custom.prop_spacing_m = 50.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.RED
	custom.road_material = mat
	var s: RideScene = load(SCENE).instantiate()
	s.route_id = ""  # петля LoopTrack, как до T-070 (сцена по умолчанию — на трассе flat)
	s.environment_set = custom
	add_child_autofree(s)
	var env := (s.get_node("%WorldEnvironment") as WorldEnvironment).environment
	assert_eq(env.background_color, custom.sky_color, "небо из набора окружения")
	assert_eq(env.fog_light_color, custom.fog_color)
	assert_eq(s.road().get_active_material(0), mat, "материал дороги из набора")
	var default_scene := _scene()
	assert_eq(default_scene.props().multimesh.instance_count, s.props().multimesh.instance_count * 2, "шаг объектов 50 м → вдвое меньше объектов")
	s.apply_telemetry(200, true, 85, true, 36.0, true)
	default_scene.apply_telemetry(200, true, 85, true, 36.0, true)
	_frames(s, 600)
	_frames(default_scene, 600)
	assert_almost_eq(s.distance_m, default_scene.distance_m, 1e-6, "движение не зависит от окружения")


func test_req_d3d_06_c1_game_loop_does_not_reference_concrete_environment_scene() -> void:
	var code := FileAccess.get_file_as_string("res://src/scene3d/ride_scene.gd")
	var in_frame := false
	var offenders: Array[String] = []
	var n := 0
	for raw in code.split("\n"):
		n += 1
		var line: String = raw.substr(0, raw.find("#")) if raw.find("#") != -1 else raw
		if line.begins_with("func "):
			in_frame = line.begins_with("func advance(") or line.begins_with("func _on_second_elapsed(") or line.begins_with("func apply_telemetry(") or line.begins_with("func bind(") or line.begins_with("func _place_rider(")
			continue
		if in_frame and (line.contains("LoopTrack") or line.contains(".tres") or line.contains(".tscn") or line.contains("environment_set")):
			offenders.append("%d: %s" % [n, line.strip_edges()])
	assert_eq(offenders, [], "цикл/привязка ссылаются на конкретную трассу или сцену окружения: %s" % str(offenders))
	assert_true(code.contains("track.sample_into("), "движение — через интерфейс Track")


func test_req_d3d_06_c3_docs_describe_architecture_interfaces_and_gpx_route() -> void:
	var doc := FileAccess.get_file_as_string("res://docs/scene3d.md")
	assert_false(doc.is_empty(), "docs/scene3d.md существует")
	for term in ["Track", "sample_into", "TrackSample", "EnvironmentSet", "RideScene", "GPX", "length_m", "is_loop"]:
		assert_true(doc.contains(term), "в документе есть «%s»" % term)
	assert_true(doc.contains("```"), "есть схема интерфейсов")
	assert_true(doc.to_lower().contains("gpx") and doc.contains("set_track("), "описано добавление GPX-маршрута через set_track")
	assert_true(FileAccess.file_exists("res://docs/perf_budget.md"))


# ===========================================================================
# Границы
# ===========================================================================

func test_edge_set_track_before_ready_builds_road_after_entering_tree() -> void:
	var s: RideScene = load(SCENE).instantiate()
	s.route_id = ""  # петля LoopTrack, как до T-070 (сцена по умолчанию — на трассе flat)
	s.set_track(SquareLoopTrack.new(200.0))
	add_child_autofree(s)
	assert_true(s.track is SquareLoopTrack, "трасса, заданная до входа в дерево, сохранена")
	assert_not_null(s.road(), "дорога должна быть построена после _ready для заранее заданной трассы")
	assert_not_null(s.props())
	s.apply_telemetry(200, true, 85, true, 36.0, true)
	_frames(s, 60)
	assert_gt(s.distance_m, 9.0)


func test_edge_bind_before_set_track_and_before_ready_is_safe() -> void:
	var s: RideScene = load(SCENE).instantiate()
	s.route_id = ""  # петля LoopTrack, как до T-070 (сцена по умолчанию — на трассе flat)
	_session = WorkoutSession.new(_plan(), _trainer, 200, 1.0, 75.0)
	s.bind(_session, _profile)
	assert_true(s.is_bound())
	add_child_autofree(s)
	_session.start()
	for i in 5:
		_second(s)
	assert_gt(s.distance_m, 0.0, "после входа в дерево движение идёт по трассе по умолчанию")
	s.set_track(SquareLoopTrack.new(100.0))
	assert_eq(s.distance_m, 0.0, "смена трассы ставит на старт")
	assert_true(s.is_bound(), "привязка к сессии сохранена")
	_second(s)
	assert_gt(s.distance_m, 0.0)


func test_edge_advance_zero_or_negative_dt_changes_nothing() -> void:
	var s := _scene()
	s.apply_telemetry(200, true, 85, true, 36.0, true)
	_frames(s, 10)
	var d := s.distance_m
	var cam := s.camera().global_position
	var crank := s.rider().crank_rotation_rad()
	s.advance(0.0)
	s.advance(-1.0)
	s.rider().advance(0.0)
	assert_eq(s.distance_m, d)
	assert_eq(s.camera().global_position, cam)
	assert_eq(s.rider().crank_rotation_rad(), crank)
	s.advance(10.0) # огромный кадр — ограничен MAX_FRAME_DELTA_SEC
	assert_almost_eq(s.distance_m - d, 10.0 * RideScene.MAX_FRAME_DELTA_SEC, 1e-6, "дельта кадра ограничена 0.25 с")


func test_edge_unbind_twice_and_finished_session_stop_pedaling() -> void:
	var s := _scene()
	_bind(s, 200.0)
	_trainer.set_cadence_sequence([90])
	for i in 5:
		_second(s)
	assert_true(s.rider().is_pedaling())
	s.unbind()
	assert_false(s.is_bound())
	s.unbind()
	assert_false(s.is_bound(), "повторный unbind безопасен")
	_frames(s, 300)
	assert_false(s.rider().is_pedaling(), "после unbind — накат")
	_trainer.set_cadence_sequence([30])
	_session.tick(5.0)
	assert_eq(s.cadence_rpm, 90, "телеметрия отвязанной сессии не доходит (поле осталось прежним, не стало 30)")
	var s2 := _scene()
	_bind(s2, 200.0)
	_trainer.set_cadence_sequence([90])
	for i in 5:
		_second(s2)
	_session.stop()
	_frames(s2, 300)
	assert_false(s2.rider().is_pedaling(), "FINISHED → педалирование остановлено")


func test_edge_one_metre_loop_track_is_handled() -> void:
	var s := _scene(ShortLoopTrack.new())
	assert_eq(s.track.length_m(), 1.0)
	assert_not_null(s.road(), "дорога построена и для 1 м")
	assert_eq(int(s.road().get_meta("segments")), 8, "минимум 8 сегментов")
	assert_null(s.props(), "объектов с шагом 25 м на 1 м нет")
	s.apply_telemetry(200, true, 85, true, 36.0, true)
	for i in 120:
		s.advance(FRAME)
		assert_true(s.distance_m >= 0.0 and s.distance_m < 1.0, "кадр %d: дистанция %.3f обёрнута" % [i, s.distance_m])
		assert_true(s.rider_position().x >= -1e-6 and s.rider_position().x < 1.0 + 1e-6, "кадр %d: x=%.4f при дистанции %.4f" % [i, s.rider_position().x, s.distance_m])
	assert_true(s.camera().is_position_in_frustum(s.rider_position() + Vector3.UP))


func test_edge_process_without_session_does_not_crash_and_stays_still() -> void:
	var s := _scene()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(s.distance_m, 0.0)
	assert_eq(s.speed_kmh, 0.0)
	assert_false(s.is_bound())
	assert_false(s.rider().is_pedaling())


func test_edge_workout_screen_binds_ride_scene_on_start_and_unbinds_on_finish() -> void:
	var ws: WorkoutScreen = load(WORKOUT_SCENE).instantiate()
	add_child_autofree(ws)
	var steps: Array[WorkoutStep] = [WorkoutStep.watts(3, 200.0)]
	ws.setup(Workout.make("short", steps), _profile, _trainer, AppState.new(ProfileRepository.new("user://test_acc_scene3d_unused/")))
	assert_not_null(ws.ride_scene())
	assert_false(ws.ride_scene().is_bound())
	assert_true(ws.start())
	assert_true(ws.ride_scene().is_bound(), "старт тренировки привязывает сцену")
	_trainer.set_cadence_sequence([90])
	ws.session().tick(1.0)
	ws.ride_scene().advance(FRAME)
	assert_almost_eq(ws.ride_scene().rider().target_speed_scale, 1.5, 1e-9, "каденс из сессии дошёл до сцены")
	ws.session().tick(2.0)
	assert_eq(ws.session().get_state(), WorkoutSession.State.FINISHED)
	assert_false(ws.ride_scene().is_bound(), "финиш отвязывает сцену")
	for i in 300:
		ws.ride_scene().advance(FRAME)
	assert_false(ws.ride_scene().rider().is_pedaling())
