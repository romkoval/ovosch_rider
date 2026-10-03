extends GutTest
## Окружения «равнина» и «холмы» (T-083): свои `EnvironmentSet`, лоскуты полей, лесополосы,
## каменные изгороди, ориентиры по `RouteCatalog.landmarks` — REQ-D3D-08 п.6 (`flat`, `hills`:
## свой набор, высота горизонта равнина < холмы, бюджет T-066), п.12 (ориентиры в мире не
## реже 1.5 км, сторона и план), п.8 (ориентиры в кадре у своих s, не больше трёх в кадре).

const SCENE: String = "res://src/scene3d/ride_scene.tscn"
const FRAME: float = 1.0 / 60.0
const STEP_M: float = 50.0
const IDS: Array[String] = [RouteCatalog.FLAT, RouteCatalog.HILLS]
## Половина горизонтального угла обзора камеры (FOV 55° по вертикали, 16:9) с запасом.
const HALF_FOV_RAD: float = 0.72

var _scenes: Dictionary = {}


func before_all() -> void:
	for id in IDS:
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


func _drive_to(s: RideScene, at_m: float, kmh: float, frames: int = 120) -> void:
	s.distance_m = fposmod(at_m - kmh / 3.6 * FRAME * float(frames), s.track.length_m())
	s.apply_telemetry(0, false, 90, true, kmh, true)
	for i in frames:
		s.advance(FRAME)


## Центры AABB видимых частей ориентира (узел и дети) в мировых координатах.
func _part_centers(node: MultiMeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for n: MultiMeshInstance3D in [node] + Array(node.get_children()):
		out.append(n.global_transform * PerfBudget.multimesh_aabb(n.multimesh).get_center())
	return out


## Виден ли ориентир из камеры: хотя бы один экземпляр части (центр его габарита или точка
## на 2 м над основанием; у мешей в мировых координатах — центр габарита) в дальности видимости и в пирамиде камеры.
## Позиции экземпляров готового MultiMesh на headless-сервере недоступны — берутся из расстановки.
func _in_frame(s: RideScene, pl: LandmarkBuilder.Placed) -> bool:
	var cam: Camera3D = s.camera()
	for part in pl.parts:
		if part.mesh == null:
			continue
		for t in part.xf:
			var center: Vector3 = (t * part.mesh.get_aabb()).get_center()
			for p in [center, t.origin + Vector3.UP * 2.0]:
				if part.world_space and p != center:
					continue
				if cam.global_position.distance_to(p) > pl.range_m:
					continue
				if _in_view(cam, p):
					return true
	return false


## Точка в кадре 16:9 (снимки 1280×720) камеры с вертикальным FOV `cam.fov`.
func _in_view(cam: Camera3D, p: Vector3) -> bool:
	var local: Vector3 = cam.global_transform.affine_inverse() * p
	if local.z >= -0.1:
		return false
	var ty: float = tan(deg_to_rad(cam.fov) * 0.5)
	var tx: float = ty * 16.0 / 9.0
	return absf(local.x / -local.z) <= tx and absf(local.y / -local.z) <= ty


# ---------------------------------------------------------------------------
# Свои наборы окружения (REQ-D3D-08 п.6)
# ---------------------------------------------------------------------------

func test_flat_and_hills_have_own_environment_sets() -> void:
	var paths: Array[String] = []
	for id in IDS:
		var path: String = RouteWorld.environment_path(id)
		assert_ne(path, RouteWorld.DEFAULT_ENVIRONMENT, "%s: свой набор окружения" % id)
		assert_true(ResourceLoader.exists(path), "%s: %s есть" % [id, path])
		assert_false(paths.has(path), "%s: набор не общий с другой трассой" % id)
		paths.append(path)
		assert_eq(_scene(id).environment_set.resource_path, path, "%s: сцена построена на своём наборе" % id)
	var flat: EnvironmentSet = RouteWorld.environment(RouteCatalog.FLAT)
	var hills: EnvironmentSet = RouteWorld.environment(RouteCatalog.HILLS)
	assert_lt(flat.hills_height_m, hills.hills_height_m, "hills_height_m: равнина < холмы")
	assert_lt(flat.rolling_height_m, hills.rolling_height_m)
	assert_gt(flat.windbreak_rows_per_km, 0.0, "равнина: лесополосы тополей")
	assert_gt(hills.stone_wall_share, 0.0, "холмы: каменные изгороди")
	assert_false(flat.guardrail_enabled, "равнина: отбойника нет (tracks.md п. 4.1)")
	var fm := flat.terrain_material as ShaderMaterial
	assert_not_null(fm, "равнина: свой материал рельефа")
	assert_gt(float(fm.get_shader_parameter("field_strength")), 0.5, "равнина: лоскуты полей")
	assert_ne(flat.fog_color, hills.fog_color, "свет и дымка у трасс разные")
	assert_ne(flat.sun_color, hills.sun_color)


func test_scene_world_differs_by_route_composition() -> void:
	var flat := _scene(RouteCatalog.FLAT)
	var hills := _scene(RouteCatalog.HILLS)
	var names_flat: Array[String] = _world_names(flat)
	var names_hills: Array[String] = _world_names(hills)
	assert_true(names_flat.has("Poplars"), "равнина: тополя (%s)" % str(names_flat))
	assert_false(names_flat.has("StoneWalls"))
	assert_true(names_hills.has("StoneWalls"), "холмы: изгороди (%s)" % str(names_hills))
	assert_false(names_hills.has("Poplars"))


func _world_names(s: RideScene) -> Array[String]:
	var out: Array[String] = []
	for n in s.world_nodes():
		out.append(String(n.name))
	return out


## Максимальная высота рельефа над стартом трассы (REQ-D3D-08 п.6: равнина < холмы).
func test_horizon_height_flat_lower_than_hills() -> void:
	var tops: Dictionary = {}
	for id in IDS:
		var s := _scene(id)
		var tf: TerrainField = s.terrain()
		var start_y: float = s.track.sample(0.0).position.y
		var top: float = -INF
		for h in tf.tile_heights:
			for v in h:
				top = maxf(top, v)
		tops[id] = top - start_y
		gut.p("%s: рельеф горизонта выше старта на %.0f м" % [id, top - start_y])
	assert_lt(float(tops[RouteCatalog.FLAT]), 60.0, "равнина: горизонт низкий")
	assert_lt(float(tops[RouteCatalog.FLAT]), float(tops[RouteCatalog.HILLS]), "равнина < холмы")


func test_terrain_marks_fields_away_from_road_in_vertex_alpha() -> void:
	assert_almost_eq(TerrainField.field_color(5.0).a, 1.0, 1e-6, "у дороги полей нет")
	assert_almost_eq(TerrainField.field_color(TerrainField.FIELD_FULL_M + 1.0).a, 0.0, 1e-6, "в поле — лоскуты")
	var s := _scene(RouteCatalog.FLAT)
	var terrain: MeshInstance3D = s.world_nodes().filter(func(n: Node) -> bool: return n.name == "Terrain")[0]
	var cols: PackedColorArray = terrain.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var field: int = 0
	for c in cols:
		if c.a < 0.5:
			field += 1
	assert_gt(field, cols.size() / 2, "большая часть рельефа — поля")


# ---------------------------------------------------------------------------
# Ориентиры (REQ-D3D-08 п.12, п.8)
# ---------------------------------------------------------------------------

func test_every_catalog_landmark_is_built_with_side_and_plane() -> void:
	for id in IDS:
		var s := _scene(id)
		var def: RouteCatalog.RouteDef = RouteCatalog.get_route(id)
		var placed: Array[LandmarkBuilder.Placed] = s.landmarks_placed()
		assert_eq(placed.size(), def.landmarks.size(), "%s: построены все ориентиры" % id)
		assert_eq(s.landmark_nodes().size(), def.landmarks.size(), "%s: по узлу на ориентир" % id)
		var sample := TrackSample.new()
		var bad: Array[String] = []
		for i in placed.size():
			var pl: LandmarkBuilder.Placed = placed[i]
			var lm: RouteCatalog.Landmark = def.landmarks[i]
			assert_eq(pl.type, lm.type)
			if pl.instance_count() == 0:
				bad.append("%s: пусто" % pl.type)
				continue
			s.track.sample_into(lm.s_m, sample)
			var center: Vector3 = sample.position + sample.right() * s.environment_set.road_center_offset_m
			var lateral: float = (pl.anchor - center).dot(sample.right())
			match lm.side:
				RouteCatalog.Landmark.SIDE_LEFT:
					if lateral > -5.0:
						bad.append("%s@%.0f: не слева (%.0f м)" % [pl.type, lm.s_m, lateral])
				RouteCatalog.Landmark.SIDE_RIGHT, RouteCatalog.Landmark.SIDE_BOTH:
					if lateral < 5.0:
						bad.append("%s@%.0f: не справа (%.0f м)" % [pl.type, lm.s_m, lateral])
				RouteCatalog.Landmark.SIDE_ROAD:
					if absf(lateral) > 2.0:
						bad.append("%s@%.0f: не на дороге (%.1f м)" % [pl.type, lm.s_m, lateral])
			var d: float = absf(lateral)
			match lm.plane:
				RouteCatalog.Landmark.PLANE_NEAR:
					if d > 70.0:
						bad.append("%s: у дороги, а стоит в %.0f м" % [pl.type, d])
				RouteCatalog.Landmark.PLANE_MID:
					if d < 50.0 or d > 400.0:
						bad.append("%s: средний план, а стоит в %.0f м" % [pl.type, d])
				RouteCatalog.Landmark.PLANE_FAR:
					if d < 200.0:
						bad.append("%s: дальний план, а стоит в %.0f м" % [pl.type, d])
		assert_eq(bad, [] as Array[String], "%s: %s" % [id, str(bad)])


func test_landmarks_not_rarer_than_1500m_including_lap_seam() -> void:
	for id in IDS:
		var s := _scene(id)
		var placed: Array[LandmarkBuilder.Placed] = s.landmarks_placed()
		var length: float = s.track.length_m()
		var worst: float = 0.0
		for i in placed.size():
			var a: float = placed[i].s_m
			var b: float = placed[(i + 1) % placed.size()].s_m
			var gap: float = b - a if i + 1 < placed.size() else length - a + b
			worst = maxf(worst, gap)
		assert_lte(worst, 1500.0, "%s: максимальный разрыв между ориентирами в мире %.0f м" % [id, worst])


func test_landmark_parts_off_the_road_and_on_the_ground() -> void:
	for id in IDS:
		var s := _scene(id)
		var tf: TerrainField = s.terrain()
		var probe := PackedVector3Array()
		var sample := TrackSample.new()
		for i in int(s.track.length_m() / 5.0):
			s.track.sample_into(float(i) * 5.0, sample)
			probe.append(sample.position)
		var bad: Array[String] = []
		for pl in s.landmarks_placed():
			if pl.side == RouteCatalog.Landmark.SIDE_ROAD:
				continue
			for part in pl.parts:
				if part.mesh == null or part.world_space or part.animated:
					continue
				for t in part.xf:
					var best: float = INF
					for q in probe:
						best = minf(best, Vector2(t.origin.x - q.x, t.origin.z - q.z).length())
					if best < 12.0:
						bad.append("%s/%s: %.1f м от оси" % [pl.type, part.name, best])
					var g: float = tf.height_at(t.origin.x, t.origin.z)
					if absf(t.origin.y - g) > 2.5:
						bad.append("%s/%s: над землёй %.1f м" % [pl.type, part.name, t.origin.y - g])
		assert_eq(bad, [] as Array[String], "%s: %s" % [id, str(bad.slice(0, 8))])


func test_road_landmarks_have_rails_on_both_edges_and_water_under_road() -> void:
	for id in IDS:
		var s := _scene(id)
		for pl in s.landmarks_placed():
			if pl.side != RouteCatalog.Landmark.SIDE_ROAD:
				continue
			var names: Array[String] = []
			for part in pl.parts:
				names.append(part.name)
			assert_true(names.has("creek"), "%s: ручей (%s)" % [pl.type, str(names)])
			var rails: LandmarkBuilder.Part = pl.parts.filter(func(p: LandmarkBuilder.Part) -> bool:
				return p.name == "railing" or p.name == "parapet")[0]
			assert_eq(rails.xf.size(), 2, "%s: ограждение с обеих сторон" % pl.type)


func test_landmark_nodes_have_visibility_range_and_animated_parts_use_shader() -> void:
	for id in IDS:
		var s := _scene(id)
		var animated: int = 0
		for node in s.landmark_nodes():
			for n: MultiMeshInstance3D in [node] + Array(node.get_children()):
				assert_gt(n.visibility_range_end, 0.0, "%s/%s: дальность видимости" % [node.name, n.name])
				var mat: Material = n.multimesh.mesh.surface_get_material(0)
				if n.multimesh.use_custom_data:
					animated += 1
					assert_eq(mat.resource_path, LandmarkBuilder.ANIM_MATERIAL, "%s: анимация в шейдере" % n.name)
		assert_gt(animated, 0, "%s: есть анимированные части (ветряки/мельница/шар)" % id)


func test_landmark_animation_drift_is_slow() -> void:
	var mat := load(LandmarkBuilder.ANIM_MATERIAL) as ShaderMaterial
	var rate: float = float(mat.get_shader_parameter("drift_rate"))
	for id in IDS:
		for pl in _scene(id).landmarks_placed():
			for part in pl.parts:
				if not part.animated:
					continue
				for c in part.custom:
					assert_lte(c.b * rate, 0.5, "%s: дрейф ≤ 0.5 м/с" % part.name)
					assert_lte(c.a * rate * 1.7, 0.5, "%s: покачивание ≤ 0.5 м/с" % part.name)


func test_no_more_than_three_landmarks_in_view_from_any_point() -> void:
	for id in IDS:
		var s := _scene(id)
		var sample := TrackSample.new()
		var worst: int = 0
		var where: float = 0.0
		for i in int(s.track.length_m() / STEP_M):
			var at: float = float(i) * STEP_M
			s.track.sample_into(at, sample)
			var eye: Vector3 = sample.position + Vector3.UP * 2.1 - Vector3(sample.forward.x, 0.0, sample.forward.z).normalized() * 3.8
			var fwd := Vector3(sample.forward.x, 0.0, sample.forward.z).normalized()
			var seen: int = 0
			for node in s.landmark_nodes():
				var visible: bool = false
				for n: MultiMeshInstance3D in [node] + Array(node.get_children()):
					var c: Vector3 = n.global_transform * PerfBudget.multimesh_aabb(n.multimesh).get_center()
					var to := Vector3(c.x - eye.x, 0.0, c.z - eye.z)
					if to.length() > n.visibility_range_end:
						continue
					if to.normalized().dot(fwd) > cos(HALF_FOV_RAD):
						visible = true
						break
				if visible:
					seen += 1
			if seen > worst:
				worst = seen
				where = at
		gut.p("%s: ориентиров в кадре не больше %d (s = %.0f)" % [id, worst, where])
		assert_lte(worst, 3, "%s: в кадре одновременно не больше трёх ориентиров" % id)


## Снимки `tracks.md` п. 8: у своих s ориентиры в кадре (≥ 3 на трассе).
func test_landmarks_in_frame_at_their_s() -> void:
	for id in IDS:
		var s := _scene(id)
		var seen: Array[String] = []
		var missed: Array[String] = []
		for pl in s.landmarks_placed():
			_drive_to(s, pl.s_m, 32.0)
			if _in_frame(s, pl):
				seen.append(pl.type)
			else:
				missed.append(pl.type)
		gut.p("%s: в кадре у своих s: %s; нет: %s" % [id, str(seen), str(missed)])
		assert_gte(seen.size(), 3, "%s: не меньше трёх ориентиров в кадре у своих s" % id)
		assert_gte(seen.size(), s.landmark_nodes().size() - 2, "%s: почти все ориентиры видны у своих s (%s)" % [id, str(missed)])


# ---------------------------------------------------------------------------
# Бюджет T-066 (REQ-D3D-08 п.6, D3D-05 п.4)
# ---------------------------------------------------------------------------

func test_budget_on_flat_and_hills_with_landmarks() -> void:
	for id in IDS:
		var s := _scene(id)
		var c := PerfBudget.count(s)
		assert_lte(int(c["mesh_instances"]), PerfBudget.MAX_MESH_INSTANCES, "%s: MeshInstance3D" % id)
		assert_lte(int(c["materials"]), PerfBudget.MAX_MATERIALS, "%s: материалов" % id)
		assert_lte(int(c["lights"]), PerfBudget.MAX_LIGHTS)
		assert_lte(int(c["multimesh_instances"]), PerfBudget.MAX_MULTIMESH_INSTANCES, "%s: MultiMesh всего" % id)
		var visible: int = PerfBudget.max_visible_along([s], s.track, STEP_M)
		var marks: int = 0
		for n in s.landmark_nodes():
			marks += int(PerfBudget.count(n)["multimesh_instances"])
		assert_lte(visible, PerfBudget.MAX_VISIBLE_MULTIMESH_INSTANCES, "%s: видно с любой точки %d" % [id, visible])
		assert_gt(marks, 0)
		gut.p("%s: MeshInstance3D %d, материалов %d, MultiMesh всего %d (ориентиры %d), видно ≤ %d" % [id,
			c["mesh_instances"], c["materials"], c["multimesh_instances"], marks, visible])


func test_landmarks_off_and_route_less_track_build_without_landmarks() -> void:
	var s: RideScene = load(SCENE).instantiate()
	var env: EnvironmentSet = RouteWorld.environment(RouteCatalog.FLAT).duplicate() as EnvironmentSet
	env.landmarks_enabled = false
	s.environment_set = env
	s.route_id = RouteCatalog.FLAT
	add_child_autofree(s)
	assert_eq(s.landmark_nodes().size(), 0, "ориентиры выключены в наборе")
	s.set_track(LoopTrack.new(7))
	assert_eq(s.landmark_nodes().size(), 0, "у процедурной петли ориентиров нет")
	assert_not_null(s.terrain())


func test_landmark_placement_is_deterministic() -> void:
	# Вторая сцена той же трассы (рельеф строится заново: озёра уже опустили землю в первой).
	var again_scene: RideScene = load(SCENE).instantiate()
	again_scene.route_id = RouteCatalog.HILLS
	add_child_autofree(again_scene)
	var again: Array[LandmarkBuilder.Placed] = again_scene.landmarks_placed()
	var first: Array[LandmarkBuilder.Placed] = _scene(RouteCatalog.HILLS).landmarks_placed()
	assert_eq(again.size(), first.size())
	for i in first.size():
		assert_true(again[i].anchor.is_equal_approx(first[i].anchor), "%s: та же точка" % first[i].type)
		assert_eq(again[i].instance_count(), first[i].instance_count())


func test_vegetation_keeps_out_of_landmark_footprints() -> void:
	for id in IDS:
		var s := _scene(id)
		var ko := LandmarkBuilder.keep_out(s.landmarks_placed())
		var layers := SceneryBuilder.place(s.track, s.environment_set, s.terrain(), null, PerfBudget.MAX_VISIBLE_MULTIMESH_INSTANCES,
			PerfBudget.MAX_MULTIMESH_INSTANCES, ko)
		var inside: int = 0
		for layer in layers:
			if layer.name == "Tufts":
				continue
			for t in layer.xf:
				if ko.blocks(t.origin.x, t.origin.z):
					inside += 1
		assert_eq(inside, 0, "%s: деревья и кусты не стоят в постройках ориентиров" % id)
