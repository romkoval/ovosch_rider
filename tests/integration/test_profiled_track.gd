extends GutTest
## Трассы каталога в сцене (T-070): `ProfiledTrack` (план-схема + профиль), `RouteWorld`,
## `RideScene.set_route` — REQ-D3D-08 п.2 (геометрия стыка), п.4, п.5, п.7, п.10, п.13,
## REQ-D3D-03 п.1, 2 на новых трассах, бюджет T-066 на каждой трассе, обочина без щели
## (дополнение game-designer: между краем полотна и бордюром нет травы и рельефа).

const SCENE: String = "res://src/scene3d/ride_scene.tscn"
const WORKOUT_SCENE: String = "res://src/ui/workout/workout_screen.tscn"
const FRAME: float = 1.0 / 60.0
const STEP_M: float = 50.0

## Сцены по трассам (строятся один раз: мир трассы — ~1 с).
var _scenes: Dictionary = {}


func before_all() -> void:
	for id in RouteCatalog.ids():
		var s: RideScene = load(SCENE).instantiate()
		s.route_id = id
		add_child(s)
		_scenes[id] = s


func after_all() -> void:
	for id in _scenes:
		var s: RideScene = _scenes[id]
		if is_instance_valid(s):
			s.free()
	_scenes.clear()


func _scene(id: String) -> RideScene:
	var s: RideScene = _scenes[id]
	s.apply_telemetry(0, false, 0, true, 0.0, true)
	return s


func _track(id: String) -> ProfiledTrack:
	return (_scene(id).track as ProfiledTrack)


func _points(track: Track, step: float = STEP_M) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i in int(floor(track.length_m() / step)):
		out.append(float(i) * step)
	return out


## Точки с наибольшим и наименьшим уклоном и перелом подъём → спуск после максимума.
func _special_points(t: ProfiledTrack) -> PackedFloat64Array:
	var grades: PackedFloat64Array = t.profile.sample_grades()
	var step: float = t.profile.sample_step_m()
	var i_max: int = 0
	var i_min: int = 0
	for i in grades.size():
		if grades[i] > grades[i_max]:
			i_max = i
		if grades[i] < grades[i_min]:
			i_min = i
	var crest: int = i_max
	for k in grades.size():
		var j: int = (i_max + k) % grades.size()
		if grades[j] <= 0.0:
			crest = j
			break
	return PackedFloat64Array([i_max * step, i_min * step, crest * step])


## Поставить велосипедиста на s и доехать `frames` кадров на `kmh`.
func _drive_to(s: RideScene, at_m: float, kmh: float, frames: int = 90) -> void:
	s.distance_m = fposmod(at_m - kmh / 3.6 * FRAME * float(frames), s.track.length_m())
	s.apply_telemetry(0, false, 90, true, kmh, true)
	for i in frames:
		s.advance(FRAME)


## Точки мешей велосипедиста на высоте 0.1–1.45 м над дорогой (как в приёмке D3D-07.5).
func _rider_points(s: RideScene) -> PackedVector3Array:
	var out := PackedVector3Array()
	var rider := s.rider()
	var inv: Transform3D = rider.global_transform.affine_inverse()
	for node in rider.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf: Transform3D = mi.global_transform
		for si in mi.mesh.get_surface_count():
			for v in (mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var w: Vector3 = xf * v
				var h: float = (inv * w).y
				if h >= 0.1 and h <= 1.45:
					out.append(w)
	return out


func _outside_frame(s: RideScene, pts: PackedVector3Array) -> int:
	var planes: Array[Plane] = s.camera().get_frustum()
	var outside: int = 0
	for p in pts:
		for pl in planes:
			if pl.is_point_over(p):
				outside += 1
				break
	return outside


# ---------------------------------------------------------------------------
# План и профиль (REQ-D3D-08 п.2, 4; REQ-D3D-03 п.1)
# ---------------------------------------------------------------------------

func test_plan_length_equals_profile_and_lap_closes_horizontally() -> void:
	for id in RouteCatalog.ids():
		var t := _track(id)
		assert_almost_eq(t.length_m(), t.profile.length_m(), 1e-6, "%s: длина плана = длина профиля" % id)
		var a := t.sample(0.0)
		var b := t.sample(t.length_m())
		var c := t.sample(t.length_m() - 0.5)
		var d := t.sample(0.5)
		assert_lt(a.position.distance_to(b.position), 1e-3, "%s: sample(0) == sample(L)" % id)
		assert_lt(c.position.distance_to(d.position), 1.0 + 1e-3, "%s: через стык 1 м — смещение 1 м" % id)
		var fa := Vector2(c.forward.x, c.forward.z).normalized()
		var fb := Vector2(d.forward.x, d.forward.z).normalized()
		assert_lt(absf(fa.angle_to(fb)), deg_to_rad(0.5), "%s: курс на стыке непрерывен" % id)


func test_track_contract_unit_vectors_and_smooth_position_and_heading() -> void:
	for id in RouteCatalog.ids():
		var t := _track(id)
		var bad: Array[String] = []
		var prev := t.sample(0.0)
		var s: float = 0.0
		while s < t.length_m() + 2.0:
			s += 1.0
			var p := t.sample(s)
			if absf(p.forward.length() - 1.0) > 1e-4 or absf(p.up.length() - 1.0) > 1e-4:
				bad.append("s=%.0f: не единичные" % s)
			if absf(p.forward.dot(p.up)) > 1e-4 or absf(p.right().y) > 1e-4:
				bad.append("s=%.0f: up ⟂ forward, правый вектор горизонтален" % s)
			if prev.position.distance_to(p.position) > 1.0 * 1.01:
				bad.append("s=%.0f: |Δpos| %.3f > Δs" % [s, prev.position.distance_to(p.position)])
			if prev.forward.angle_to(p.forward) > deg_to_rad(3.0):
				bad.append("s=%.0f: курс за 1 м %.1f°" % [s, rad_to_deg(prev.forward.angle_to(p.forward))])
			prev = p
			if bad.size() > 5:
				break
		assert_eq(bad, [] as Array[String], "%s: %s" % [id, str(bad)])


func test_parts_of_loop_do_not_approach_each_other() -> void:
	for id in RouteCatalog.ids():
		var t := _track(id)
		assert_gte(t.min_gap_m, ProfiledTrack.MIN_GAP_M, "%s: разные части петли не ближе %.0f м (%.0f м)" % [id, ProfiledTrack.MIN_GAP_M, t.min_gap_m])


func test_road_axis_and_rider_height_follow_profile_every_50m() -> void:
	for id in RouteCatalog.ids():
		var s := _scene(id)
		var t := _track(id)
		var road: MeshInstance3D = s.road()
		var verts := PackedVector3Array()
		for node in [road] + road.get_children():
			verts.append_array((node as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
		var ring_m: float = t.length_m() / float(RoadBuilder.total_segments(t))
		var bad: Array[String] = []
		var checked: int = 0
		for at in _points(t):
			var h: float = t.profile.height_at(at)
			if absf(t.sample(at).position.y - h) > 0.05:
				bad.append("ось s=%.0f" % at)
			# Ось полотна — середина кольца дороги (кольца с шагом ring_m; куски делят кольцо).
			var ring: int = int(round(at / ring_m))
			var chunk: int = ring / RoadBuilder.MAX_SEGMENTS
			var local: int = ring - chunk * RoadBuilder.MAX_SEGMENTS
			if chunk > 0 and local == 0:
				chunk -= 1
				local = RoadBuilder.MAX_SEGMENTS
			var base: int = chunk * (RoadBuilder.MAX_SEGMENTS + 1) * 2 + local * 2
			if absf(ring * ring_m - at) < 1e-3 and base + 1 < verts.size():
				var mid: float = (verts[base].y + verts[base + 1].y) * 0.5
				checked += 1
				if absf(mid - h) > 0.05:
					bad.append("полотно s=%.0f: %+.3f м" % [at, mid - h])
			s.distance_m = at
			s.advance(1e-4)
			if absf(s.rider_position().y - t.profile.height_at(s.distance_m)) > 0.05:
				bad.append("велосипедист s=%.0f" % at)
		assert_gt(checked, int(t.length_m() / STEP_M) - 2, "%s: проверено колец дороги %d" % [id, checked])
		assert_eq(bad, [] as Array[String], "%s: высота ≠ h(s) ± 0.05: %s" % [id, str(bad.slice(0, 5))])


func test_road_segments_about_5m_on_any_length_and_constant_while_riding() -> void:
	for id in RouteCatalog.ids():
		var s := _scene(id)
		var t := _track(id)
		assert_lte(t.length_m() / float(RoadBuilder.total_segments(t)), RoadBuilder.TARGET_SEGMENT_LENGTH_M + 1e-6,
			"%s: шаг колец ≤ 5 м" % id)
		assert_lte(int(s.road().get_meta("segments")), RoadBuilder.MAX_SEGMENTS)
		assert_eq(int(s.road().get_meta("chunks")), RoadBuilder.chunk_count(t))
		var before: int = s.road().get_child_count()
		s.apply_telemetry(0, false, 90, true, 45.0, true)
		for i in 200:
			s.advance(0.25)
		assert_eq(s.road().get_child_count(), before, "%s: куски дороги не пересоздаются" % id)


func test_80km_on_each_route_rider_stays_on_road_and_distance_wraps() -> void:
	for id in RouteCatalog.ids():
		var s := _scene(id)
		s.distance_m = 0.0
		s.apply_telemetry(0, false, 90, true, 40.0, true)
		for i in 28800:
			s.advance(0.25)
		assert_between(s.distance_m, 0.0, s.track.length_m(), "%s: дистанция оборачивается" % id)
		assert_lt(s.rider_position().distance_to(s.track.sample(s.distance_m).position), 1e-3, "%s: на дороге" % id)


# ---------------------------------------------------------------------------
# Рельеф и обочина относительно полотна (REQ-D3D-08 п.4)
# ---------------------------------------------------------------------------

func test_terrain_below_road_across_width_and_shoulder_every_50m() -> void:
	for id in RouteCatalog.ids():
		var s := _scene(id)
		var env: EnvironmentSet = s.environment_set
		var tf: TerrainField = s.terrain()
		var half: float = env.road_width_m * 0.5
		var curb_in: float = half + RoadsideBuilder.SHOULDER_M
		var curb_out: float = RoadsideBuilder.curb_outer_m(env.road_width_m)
		var offsets: Array[float] = [-curb_out, -curb_in, -(half + 0.15), -half, 0.0, half, half + 0.15, curb_in, curb_out]
		var sample := TrackSample.new()
		var above: Array[String] = []
		for at in _points(s.track):
			s.track.sample_into(at, sample)
			var axis: Vector3 = sample.position + sample.right() * env.road_center_offset_m
			for off in offsets:
				var p: Vector3 = axis + sample.right() * off
				var h: float = tf.height_at(p.x, p.z)
				if h > sample.position.y - 0.02:
					above.append("s=%.0f off=%+.2f: %+.2f м" % [at, off, h - sample.position.y])
		assert_eq(above, [] as Array[String], "%s: рельеф не выше полотна и обочины: %s" % [id, str(above.slice(0, 5))])


func test_asphalt_edge_meets_gravel_shoulder_without_gap() -> void:
	for id in RouteCatalog.ids():
		var s := _scene(id)
		var keys: Dictionary = {}
		var side: MeshInstance3D = s.world_nodes().filter(func(n: Node) -> bool: return n.name == "Roadside")[0]
		for node in [side] + side.get_children():
			for v in ((node as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				keys[Vector3i(roundi(v.x * 100.0), roundi(v.y * 100.0), roundi(v.z * 100.0))] = true
		var road: MeshInstance3D = s.road()
		var missing: Array[String] = []
		var checked: int = 0
		for node in [road] + road.get_children():
			var verts: PackedVector3Array = (node as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for i in range(0, verts.size(), 14):
				var v: Vector3 = verts[i]
				checked += 1
				var found: bool = false
				for dx in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						for dy in [-1, 0, 1]:
							if keys.has(Vector3i(roundi(v.x * 100.0) + dx, roundi(v.y * 100.0) + dy, roundi(v.z * 100.0) + dz)):
								found = true
				if not found:
					missing.append(str(v))
		assert_gt(checked, 100)
		assert_eq(missing, [] as Array[String], "%s: край асфальта = кромка обочины (±1 см): %s" % [id, str(missing.slice(0, 3))])


func test_terrain_follows_road_height_not_mean_height() -> void:
	for id in RouteCatalog.ids():
		var s := _scene(id)
		var tf: TerrainField = s.terrain()
		var sample := TrackSample.new()
		var far: Array[String] = []
		# Порог — из набора окружения трассы (T-102: по умолчанию 20 м на 40 м, горы — 30 м).
		var limit: float = s.environment_set.terrain_near_rise_max_m
		assert_between(limit, 20.0, 30.0, "%s: порог перепада у дороги" % id)
		for at in _points(s.track, 250.0):
			s.track.sample_into(at, sample)
			for off in [-40.0, 40.0]:
				var p: Vector3 = sample.position + sample.right() * off
				var dh: float = tf.height_at(p.x, p.z) - sample.position.y
				if absf(dh) > limit:
					far.append("s=%.0f off=%+.0f: %+.1f м" % [at, off, dh])
		assert_eq(far, [] as Array[String], "%s: рельеф в 40 м от дороги — у высоты дороги (порог %.0f м): %s" % [id, limit, str(far.slice(0, 5))])


func test_cross_slope_on_climbs() -> void:
	for id in [RouteCatalog.HILLS, RouteCatalog.MOUNTAINS]:
		var s := _scene(id)
		var tf: TerrainField = s.terrain()
		var sample := TrackSample.new()
		var sum: float = 0.0
		var n: int = 0
		for at in _points(s.track, 100.0):
			s.track.sample_into(at, sample)
			if sample.grade < 0.05:
				continue
			var l: Vector3 = sample.position - sample.right() * 55.0
			var r: Vector3 = sample.position + sample.right() * 55.0
			sum += absf(tf.height_at(r.x, r.z) - tf.height_at(l.x, l.z))
			n += 1
		assert_gt(n, 5, "%s: точек подъёма" % id)
		assert_gt(sum / float(n), 2.0, "%s: склон поперёк дороги на подъёме (в среднем %.1f м на 110 м)" % [id, sum / float(maxi(n, 1))])


# ---------------------------------------------------------------------------
# Велосипедист и камера на уклоне (REQ-D3D-08 п.5)
# ---------------------------------------------------------------------------

func test_rider_pitch_equals_atan_grade_every_50m_and_at_extremes() -> void:
	for id in RouteCatalog.ids():
		var s := _scene(id)
		var t := _track(id)
		var pts := _points(t)
		pts.append_array(_special_points(t))
		var bad: Array[String] = []
		for at in pts:
			s.distance_m = at
			s.advance(1e-4)
			var want: float = atan(t.profile.grade_at(s.distance_m) / 100.0)
			if absf(s.rider_pitch_rad() - want) > deg_to_rad(1.0):
				bad.append("s=%.0f: %.2f° ≠ %.2f°" % [at, rad_to_deg(s.rider_pitch_rad()), rad_to_deg(want)])
		assert_eq(bad, [] as Array[String], "%s: наклон = atan(g) ± 1°: %s" % [id, str(bad.slice(0, 5))])
	var m := _track(RouteCatalog.MOUNTAINS)
	var steep: float = _special_points(m)[0]
	assert_gt(m.profile.grade_at(steep), 9.0, "на горах проверен максимальный уклон")


func test_camera_horizontal_distance_and_rider_in_frame_every_50m_with_max_grade_and_crest() -> void:
	for id in RouteCatalog.ids():
		var s := _scene(id)
		var t := _track(id)
		var pts := _points(t)
		pts.append_array(_special_points(t))
		var bad: Array[String] = []
		var k: int = 0
		for at in pts:
			_drive_to(s, at, 32.0, 30)
			var off: Vector3 = s.camera_offset()
			if absf(Vector2(off.x, off.z).length() - RideScene.CAMERA_BACK_M) > 0.05:
				bad.append("s=%.0f: дистанция %.3f" % [at, Vector2(off.x, off.z).length()])
			# Точки меша — на каждой 4-й точке и на экстремумах (дорого).
			if k % 4 == 0 or k >= pts.size() - 3:
				var out: int = _outside_frame(s, _rider_points(s))
				if out > 0:
					bad.append("s=%.0f: вне кадра %d точек" % [at, out])
			k += 1
		assert_eq(bad, [] as Array[String], "%s: камера D3D-07.5: %s" % [id, str(bad.slice(0, 5))])


# ---------------------------------------------------------------------------
# Цикл не зависит от трассы (REQ-D3D-08 п.7, п.13)
# ---------------------------------------------------------------------------

func test_d3d_02_04_speed_model_and_cadence_on_each_route() -> void:
	for id in RouteCatalog.ids():
		var s := _scene(id)
		s.weight_kg = 75.0
		s.distance_m = 0.0
		s.apply_telemetry(0, false, 0, true, 0.0, true)
		for i in 60:
			s.apply_telemetry(200, true, 90, true, 0.0, false)
			for f in 60:
				s.advance(FRAME)
		assert_almost_eq(s.speed_kmh, 34.0, 3.0, "%s: D3D-02 200 Вт, 75 кг → 34 ± 3 км/ч" % id)
		assert_almost_eq(s.speed_kmh, SpeedModel.steady_speed_kmh(200.0, 75.0), 0.5, "%s: модель ровной дороги" % id)
		assert_almost_eq(s.rider().speed_scale, 1.5, 0.02, "%s: D3D-04 90 rpm → 1.5 об/с" % id)
		s.apply_telemetry(200, true, 0, true, 0.0, false)
		for f in 300:
			s.advance(FRAME)
		assert_false(s.rider().is_pedaling(), "%s: каденс 0 — накат" % id)


func test_d3d_08_13_speed_does_not_depend_on_grade_on_flat_route() -> void:
	var s := _scene(RouteCatalog.FLAT)
	var t := _track(RouteCatalog.FLAT)
	var pts := _special_points(t)
	var speeds := PackedFloat64Array()
	for at in [pts[0], pts[1]]:
		s.distance_m = at
		s.apply_telemetry(0, false, 0, true, 0.0, true)
		s.apply_telemetry(180, true, 90, true, 0.0, false)
		for i in 90:
			s.apply_telemetry(180, true, 90, true, 0.0, false)
		speeds.append(s.speed_kmh)
		s.advance(1e-4)
		var h: float = t.profile.height_at(s.distance_m)
		assert_almost_eq(s.rider_position().y, h, 0.05, "высота велосипедиста по профилю на s=%.0f" % at)
	assert_almost_eq(speeds[0], speeds[1], 0.1, "скорость на макс. (%.1f %%) и мин. уклоне одинакова" % t.profile.grade_at(pts[0]))


func test_d3d_07_c2_feet_on_pedals_and_c3_lean_in_tightest_turn_on_each_route() -> void:
	for id in RouteCatalog.ids():
		var s := _scene(id)
		var t := _track(id)
		# Самый крутой поворот (по кривизне на ±10 м).
		var a := TrackSample.new()
		var b := TrackSample.new()
		var best_s: float = 0.0
		var best_k: float = 0.0
		for at in _points(t, 10.0):
			var k: float = RoadsideBuilder.curvature(t, at, 10.0, a, b)
			if absf(k) > absf(best_k):
				best_k = k
				best_s = at
		var kmh: float = 30.0
		_drive_to(s, best_s, kmh, 240)
		var v: float = kmh / 3.6
		var k_now: float = RoadsideBuilder.curvature(t, s.distance_m, 10.0, a, b)
		var physical: float = atan(v * v * absf(k_now) / RideScene.GRAVITY)
		assert_eq(signf(s.lean_rad()), signf(k_now), "%s: наклон внутрь поворота R %.0f м" % [id, 1.0 / absf(k_now)])
		assert_gte(absf(s.lean_rad()), minf(physical, RideScene.LEAN_MAX_RAD) * 0.9, "%s: наклон не меньше физического" % id)
		assert_lte(absf(s.lean_rad()), RideScene.LEAN_MAX_RAD + 1e-6)
		# Стопа на педали и длины звеньев — на самом крутом подъёме.
		_drive_to(s, _special_points(t)[0], 20.0, 60)
		var rider := s.rider()
		var arm: Node3D = rider.get_node("%CrankArm")
		var lean: Node3D = rider.get_node("%Lean")
		var ankle_off: Vector3 = lean.global_transform.basis * RiderModel.ANKLE_FROM_PEDAL
		var l: float = RiderModel.CRANK_LENGTH_M
		var px: float = RiderModel.PEDAL_X_M
		var foot_r: Vector3 = (rider.get_node("%ShoeR") as Node3D).global_position - ankle_off
		var foot_l: Vector3 = (rider.get_node("%ShoeL") as Node3D).global_position - ankle_off
		assert_lt(foot_r.distance_to(arm.global_transform * Vector3(-px, l, 0.0)), 0.01, "%s: правая стопа на педали" % id)
		assert_lt(foot_l.distance_to(arm.global_transform * Vector3(px, -l, 0.0)), 0.01, "%s: левая стопа на педали" % id)
		var hip: Vector3 = (rider.get_node("%ThighR") as Node3D).global_position
		var knee: Vector3 = (rider.get_node("%ShinR") as Node3D).global_position
		assert_almost_eq(hip.distance_to(knee), RiderModel.THIGH_M, 0.001, "%s: бедро постоянно" % id)


# ---------------------------------------------------------------------------
# Бюджет T-066 на каждой трассе (REQ-D3D-08 п.6, D3D-05 п.4)
# ---------------------------------------------------------------------------

func test_budget_on_each_route_and_visible_multimesh_from_any_point_every_50m() -> void:
	for id in RouteCatalog.ids():
		var s := _scene(id)
		var c := PerfBudget.count(s)
		assert_lte(int(c["mesh_instances"]), PerfBudget.MAX_MESH_INSTANCES, "%s: MeshInstance3D %d" % [id, c["mesh_instances"]])
		assert_lte(int(c["materials"]), PerfBudget.MAX_MATERIALS, "%s: материалов" % id)
		assert_lte(int(c["lights"]), PerfBudget.MAX_LIGHTS)
		assert_lte(int(c["multimesh_instances"]), PerfBudget.MAX_MULTIMESH_INSTANCES, "%s: MultiMesh всего" % id)
		var visible: int = PerfBudget.max_visible_along([s], s.track, STEP_M)
		assert_gt(visible, 500, "%s: мир не пустой" % id)
		assert_lte(visible, PerfBudget.MAX_VISIBLE_MULTIMESH_INSTANCES, "%s: видно с любой точки (шаг 50 м) %d" % [id, visible])
		gut.p("%s: MeshInstance3D %d, материалов %d, MultiMesh всего %d, видно ≤ %d" % [id, c["mesh_instances"], c["materials"], c["multimesh_instances"], visible])


# ---------------------------------------------------------------------------
# Перевал — петля, мост приморья на прямой (REQ-D3D-08 п.10, 3)
# ---------------------------------------------------------------------------

func test_mountain_pass_climb_and_descent_apart_and_no_u_turn_on_summit() -> void:
	var t := _track(RouteCatalog.MOUNTAINS)
	var climb := PackedVector2Array()
	for at in range(3000, 10001, 10):
		var p: Vector3 = t.sample(float(at)).position
		climb.append(Vector2(p.x, p.z))
	var nearest: float = INF
	for at in range(11200, 19001, 10):
		var q: Vector3 = t.sample(float(at)).position
		for c in climb:
			nearest = minf(nearest, c.distance_to(Vector2(q.x, q.z)))
	assert_gte(nearest, 30.0, "подъём и спуск не ближе 30 м (%.0f м)" % nearest)
	var turn: float = 0.0
	var prev := t.sample(10000.0).forward
	for at in range(10010, 11201, 10):
		var f := t.sample(float(at)).forward
		turn += Vector2(prev.x, prev.z).angle_to(Vector2(f.x, f.z))
		prev = f
	assert_lt(absf(rad_to_deg(turn)), 120.0, "поворот на вершине %.0f° — не разворот" % rad_to_deg(turn))


func test_seaside_bridge_range_is_straight() -> void:
	var t := _track(RouteCatalog.SEASIDE)
	var a := TrackSample.new()
	var b := TrackSample.new()
	for br in t.route.bridges:
		for at in range(int(br.x), int(br.y) + 1, 10):
			var k: float = RoadsideBuilder.curvature(t, float(at), 10.0, a, b)
			assert_lt(absf(k), 1.0 / 2000.0, "мост s=%d: прямая (R %.0f м)" % [at, 1.0 / maxf(absf(k), 1e-9)])


# ---------------------------------------------------------------------------
# RouteWorld и set_route (REQ-D3D-08 п.7, п.13)
# ---------------------------------------------------------------------------

func test_default_scene_and_workout_screen_ride_on_flat() -> void:
	var s: RideScene = load(SCENE).instantiate()
	add_child_autofree(s)
	assert_true(s.track is ProfiledTrack, "сцена по умолчанию — трасса каталога")
	assert_eq((s.track as ProfiledTrack).route_id, RouteCatalog.FLAT)
	var ws: WorkoutScreen = load(WORKOUT_SCENE).instantiate()
	add_child_autofree(ws)
	assert_eq((ws.ride_scene().track as ProfiledTrack).route_id, RouteCatalog.FLAT, "тренировка по плану — на равнине")


func test_set_route_switches_track_and_environment_without_accumulating_nodes() -> void:
	var s: RideScene = load(SCENE).instantiate()
	s.route_id = ""
	add_child_autofree(s)
	assert_true(s.track is LoopTrack, "без трассы каталога — петля")
	var root := s.get_node("%EnvironmentRoot")
	var base: int = root.get_child_count()
	for id in RouteCatalog.ids():
		s.set_route(id)
		await wait_process_frames(2)
		assert_eq((s.track as ProfiledTrack).route_id, id)
		assert_eq(s.route_id, id)
		assert_eq(s.environment_set.resource_path, RouteWorld.environment_path(id), "%s: набор окружения трассы" % id)
		assert_eq(root.get_child_count(), base, "%s: узлов мира столько же" % id)
		assert_lt(s.rider_position().distance_to(s.track.sample(0.0).position), 1e-3, "%s: велосипедист на старте" % id)
	s.set_route("no_such_route")
	assert_eq((s.track as ProfiledTrack).route_id, RouteCatalog.DEFAULT_ID, "неизвестный id → трасса по умолчанию")


func test_route_world_caches_tracks_and_maps_environment() -> void:
	for id in RouteCatalog.ids():
		assert_same(RouteWorld.track(id), RouteWorld.track(id), "%s: план строится один раз" % id)
		assert_true(ResourceLoader.exists(RouteWorld.environment_path(id)), "%s: набор окружения есть" % id)
		assert_not_null(RouteWorld.environment(id))
	assert_eq(RouteWorld.resolve_id("x"), RouteCatalog.DEFAULT_ID)
