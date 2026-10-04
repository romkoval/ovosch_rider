extends GutTest
## Окружения «равнина» и «холмы» (T-083) и «горы» (T-087): свои `EnvironmentSet`, лоскуты полей,
## лесополосы, каменные изгороди; горы — камень и снег в шейдере земли, хребты вдали (широкий
## коридор, третья ступень LOD), поперечный склон «вверх по склону», долина внизу, отбойник со
## стороны долины, только ели до границы леса, валуны; ориентиры по `RouteCatalog.landmarks` —
## REQ-D3D-08 п.6 (свой набор, высота горизонта равнина < холмы < горы, бюджет T-066 с запасом
## на змейке), п.8 (ориентиры в кадре у своих s, не больше трёх в кадре; подъём читается),
## п.12 (ориентиры в мире не реже 1.5 км, сторона и план). Приморье (T-088): море и река — одна
## водная поверхность на уровне воды трассы, рельеф уходит под воду, пляж, зонтичные сосны не на
## песке, маяк на мысу со светом без источника света, ориентиры seaside (мост — T-090,
## `test_seaside_bridge.gd`) — REQ-D3D-08 п.6 (вода, высота горизонта равнина < приморье < холмы), п.8, п.11, п.12.
## Хвойные (T-107): формы, доли, вариации, уровни детализации и бюджет — REQ-D3D-10 п.1–4, бюджет
## кадра и маска тени кроны (acne, п.7).

const SCENE: String = "res://src/scene3d/ride_scene.tscn"
const FRAME: float = 1.0 / 60.0
const STEP_M: float = 50.0
const IDS: Array[String] = [RouteCatalog.FLAT, RouteCatalog.HILLS, RouteCatalog.MOUNTAINS, RouteCatalog.SEASIDE]
## Ориентиры-мосты: дорога и есть мост (ручей под полотном, ограждение по краям).
const BRIDGE_TYPES: Array[String] = ["stone_bridge", "creek_footbridge"]
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
	assert_lt(float(tops[RouteCatalog.HILLS]), float(tops[RouteCatalog.MOUNTAINS]), "холмы < горы")
	assert_gt(float(tops[RouteCatalog.MOUNTAINS]), 600.0, "горы: хребты на 650–900 м выше долины (tracks.md п. 4.3)")


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
			if lm.side == RouteCatalog.Landmark.SIDE_ROAD:
				continue
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
					if best < minf(12.0, LandmarkBuilder.min_clearance(pl.type)):
						bad.append("%s/%s: %.1f м от оси" % [pl.type, part.name, best])
					var g: float = tf.height_at(t.origin.x, t.origin.z)
					if absf(t.origin.y - g) > 2.5:
						bad.append("%s/%s: над землёй %.1f м" % [pl.type, part.name, t.origin.y - g])
		assert_eq(bad, [] as Array[String], "%s: %s" % [id, str(bad.slice(0, 8))])


func test_road_landmarks_have_rails_on_both_edges_and_water_under_road() -> void:
	for id in IDS:
		var s := _scene(id)
		for pl in s.landmarks_placed():
			if pl.side != RouteCatalog.Landmark.SIDE_ROAD or not BRIDGE_TYPES.has(pl.type):
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
			for li in s.landmark_nodes().size():
				var node: MultiMeshInstance3D = s.landmark_nodes()[li]
				if LandmarkBuilder.MINOR_TYPES.has(s.landmarks_placed()[li].type):
					continue
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


# ---------------------------------------------------------------------------
# Горы (T-087, REQ-D3D-08 п.6, 8 — `mountains`; `tracks.md` п. 4.3)
# ---------------------------------------------------------------------------

func test_mountains_environment_set_follows_tracks_md() -> void:
	var env: EnvironmentSet = RouteWorld.environment(RouteCatalog.MOUNTAINS)
	var hills: EnvironmentSet = RouteWorld.environment(RouteCatalog.HILLS)
	assert_eq(RouteWorld.environment_path(RouteCatalog.MOUNTAINS), "res://src/scene3d/tracks/env_mountains.tres")
	assert_gt(env.hills_height_m, hills.hills_height_m, "hills_height_m: горы > холмы (D3D-08 п.6)")
	assert_between(env.hills_height_m, 650.0, 900.0, "дальние пики 650–900 м")
	assert_gt(env.terrain_reach_m, TerrainField.CORRIDOR_RADIUS_M, "хребты вдали — коридор шире")
	assert_true(env.hills_ridged, "хребты гребнями")
	assert_eq(env.cross_slope_side, TerrainField.CROSS_UPHILL, "поперечный склон вверх по склону")
	assert_true(env.guardrail_enabled and env.guardrail_valley_side, "отбойник со стороны долины")
	assert_lte(env.conifer_threshold, -1.0, "только ели")
	assert_gt(env.conifer_scale, 1.0, "ели крупнее")
	assert_lt(env.conifer_shade, 1.0, "ели темнее")
	assert_almost_eq(env.tree_line_m, 650.0, 1.0, "выше 650 м деревьев нет")
	assert_gt(env.boulder_count, 0, "валуны")
	assert_gt(env.visible_reserve, 0, "запас видимого бюджета на змейке")
	for pair in [[env.sky_color, Color(0.24, 0.48, 0.86)], [env.horizon_color, Color(0.70, 0.80, 0.92)],
			[env.ambient_color, Color(0.52, 0.60, 0.84)]]:
		var got: Color = pair[0]
		var want: Color = pair[1]
		assert_true(got.is_equal_approx(want) or Vector3(got.r - want.r, got.g - want.g, got.b - want.b).length() < 0.01,
			"свет и небо по tracks.md п. 4.3: %s ≈ %s" % [got, want])
	assert_lt(env.fog_density, hills.fog_density, "воздух прозрачнее, чем на холмах")
	var mat := env.terrain_material as ShaderMaterial
	assert_not_null(mat)
	assert_lt(float(mat.get_shader_parameter("snow_from_m")), 50000.0, "снег на вершинах — в шейдере земли")
	assert_lt(float(mat.get_shader_parameter("rock_from_m")), 50000.0, "камень выше луга")
	var snow: Color = mat.get_shader_parameter("snow_color")
	assert_true(snow.is_equal_approx(Color(0.95, 0.97, 1.0)), "снег (0.95, 0.97, 1.0)")
	assert_gt(env.view_distance_m, 3000.0, "хребты за 3 км видны")
	var flat_scene := _scene(RouteCatalog.FLAT)
	assert_almost_eq(flat_scene.camera().far, 3000.0, 1e-3, "равнина: дальность камеры прежняя")
	assert_almost_eq(_scene(RouteCatalog.MOUNTAINS).camera().far, env.view_distance_m, 1e-3)


func test_mountains_world_has_boulders_conifers_only_and_no_fields_layers() -> void:
	var s := _scene(RouteCatalog.MOUNTAINS)
	var names: Array[String] = _world_names(s)
	assert_true(names.has("Boulders"), "валуны (%s)" % str(names))
	assert_false(names.has("Poplars"))
	assert_false(names.has("StoneWalls"))
	var layers := SceneryBuilder.place(s.track, s.environment_set, s.terrain(), null, PerfBudget.MAX_VISIBLE_MULTIMESH_INSTANCES,
		PerfBudget.MAX_MULTIMESH_INSTANCES, LandmarkBuilder.keep_out(s.landmarks_placed()))
	var counts: Dictionary = {}
	var above: int = 0
	for layer in layers:
		counts[layer.name] = layer.xf.size()
		if layer.name.begins_with("Conifers"):
			counts["conifers"] = int(counts.get("conifers", 0)) + layer.xf.size()
		if layer.name == "Trees" or layer.name.begins_with("Conifers"):
			for t in layer.xf:
				if t.origin.y > s.environment_set.tree_line_m + 1.0:
					above += 1
	assert_eq(int(counts.get("Trees", 0)), 0, "лиственных нет: %s" % str(counts))
	assert_gt(int(counts.get("conifers", 0)), 500, "ели (все слои хвойных): %s" % str(counts))
	assert_gt(int(counts.get("Boulders", 0)), 300, "валуны по всей трассе: %s" % str(counts))
	assert_eq(above, 0, "выше границы леса деревьев нет")


## Подъём читается (оркестратор, D3D-08 п.8): на подъёме одна сторона дороги выше другой
## (склон поперёк дороги), со стороны долины рельеф заметно ниже полотна — внизу видна долина.
func test_mountains_climb_has_slope_across_road_and_valley_below() -> void:
	var s := _scene(RouteCatalog.MOUNTAINS)
	var tf: TerrainField = s.terrain()
	var sample := TrackSample.new()
	var across: float = 0.0
	var n: int = 0
	var drops := PackedFloat32Array()
	for i in range(14, 41):
		var at: float = float(i) * 250.0
		s.track.sample_into(at, sample)
		var r: Vector3 = sample.right()
		var hl: float = tf.height_at(sample.position.x - r.x * 60.0, sample.position.z - r.z * 60.0)
		var hr: float = tf.height_at(sample.position.x + r.x * 60.0, sample.position.z + r.z * 60.0)
		across += absf(hl - hr)
		n += 1
		var low: float = INF
		for w in [200.0, 300.0, 400.0]:
			for sgn in [-1.0, 1.0]:
				var p: Vector3 = sample.position + r * float(sgn) * float(w)
				low = minf(low, tf.height_at(p.x, p.z))
		if at >= 5000.0:
			drops.append(sample.position.y - low)
	var mean_drop: float = 0.0
	var min_drop: float = INF
	for d in drops:
		mean_drop += d / float(drops.size())
		min_drop = minf(min_drop, d)
	gut.p("горы: средний перепад поперёк дороги на ±60 м — %.1f м; долина ниже дороги в среднем на %.0f м (мин. %.0f)" % [
		across / float(n), mean_drop, min_drop])
	assert_gt(across / float(n), 10.0, "на подъёме склон поперёк дороги")
	assert_gt(mean_drop, 80.0, "с подъёма внизу видна долина")
	# Порог 15 м (T-112, обоснование вместо запаса): 15 м на 200 м — 7.5 %, круче среднего уклона
	# подъёма (6.0 ± 0.3 %, D3D-08 п.4): со стороны долины земля уходит вниз быстрее, чем
	# поднимается дорога, — склон к долине, а не полка вровень с полотном (12 м = 6 % — уже
	# «параллельно дороге»). Минимум — вираж змейки s = 7000 м (15.6 м, слева в 200 м; справа
	# и дальше — верхний и нижний траверсы). Рельеф детерминирован (сид, без случайности в
	# прогоне) — запас 0.6 м не «плавает»; падение — сигнал пересмотреть рельеф гор, принятый
	# по кадрам T-102 (решение game-designer 14). Поднять минимум до 18 м — правка рельефа:
	# `cross_slope_neighbor_damp` 0.6 даёт 16.3 м, `cut_bank_m` и `terrain_near_rise_max_m` его не
	# меняют, остальное меняет кадры 6000/8600, принятые в T-102.
	assert_gt(min_drop, 15.0, "и в виражах змейки рельеф с одной стороны ниже дороги")


func test_mountains_guardrail_on_valley_side_along_climb_and_descent() -> void:
	var s := _scene(RouteCatalog.MOUNTAINS)
	var env: EnvironmentSet = s.environment_set
	var centers := PackedVector3Array()
	var rights := PackedVector3Array()
	var sample := TrackSample.new()
	var climb := Vector2i(-1, -1)
	for i in int(s.track.length_m() / 5.0):
		var at: float = float(i) * 5.0
		s.track.sample_into(at, sample)
		centers.append(sample.position + sample.right() * env.road_center_offset_m)
		rights.append(sample.right())
	var left := RoadsideBuilder.valley_rails(centers, rights, -1.0, s.terrain())
	var right := RoadsideBuilder.valley_rails(centers, rights, 1.0, s.terrain())
	var on: int = 0
	var both: int = 0
	var total: int = 0
	for i in centers.size():
		var at: float = float(i) * 5.0
		var on_slope: bool = (at >= 4000.0 and at <= 9800.0) or (at >= 11800.0 and at <= 17000.0)
		if not on_slope:
			continue
		total += 1
		if left[i] == 1 or right[i] == 1:
			on += 1
		if left[i] == 1 and right[i] == 1:
			both += 1
	gut.p("горы: отбойник со стороны долины на %d %% подъёма и спуска" % int(100.0 * float(on) / float(total)))
	assert_gt(float(on) / float(total), 0.6, "отбойник на большей части подъёма и спуска")
	assert_lt(float(both) / float(total), 0.05, "отбойник с одной стороны — долины")


func test_mountains_km_signs_count_down_to_summit() -> void:
	var s := _scene(RouteCatalog.MOUNTAINS)
	var signs: Dictionary = {}
	for pl in s.landmarks_placed():
		if pl.type == "summit_km_sign" or pl.type == "pass_sign":
			for part in pl.parts:
				signs[int(pl.s_m)] = part.name
	assert_eq(signs.get(3000, ""), "pass_sign_7", "«Перевал 7 км» у подножия")
	for at in [4000, 5000, 6000, 7000, 8000, 9000]:
		assert_eq(signs.get(at, ""), "km_sign_%d" % ((10000 - at) / 1000), "s=%d: табличка" % at)


func test_mountains_gallery_covers_road_and_cable_car_spans_it() -> void:
	var s := _scene(RouteCatalog.MOUNTAINS)
	var env: EnvironmentSet = s.environment_set
	var gallery: LandmarkBuilder.Placed = null
	var cable: LandmarkBuilder.Placed = null
	for pl in s.landmarks_placed():
		if pl.type == "avalanche_gallery":
			gallery = pl
		elif pl.type == "cable_car":
			cable = pl
	assert_not_null(gallery)
	assert_not_null(cable)
	if gallery == null or cable == null:
		return
	var bays: LandmarkBuilder.Part = gallery.parts[0]
	assert_eq(bays.name, "gallery_bay")
	assert_gte(float(bays.xf.size()) * PropMeshes.GALLERY_BAY_M, 140.0, "галерея 150 м")
	var sample := TrackSample.new()
	for i in bays.xf.size():
		var at: float = gallery.s_m + LandmarkBuilder.GALLERY_LEAD_M + (float(i) + 0.5) * PropMeshes.GALLERY_BAY_M
		s.track.sample_into(at, sample)
		var c: Vector3 = sample.position + sample.right() * env.road_center_offset_m
		assert_lt(bays.xf[i].origin.distance_to(c), 0.05, "пролёт %d над полотном" % i)
	var names: Array[String] = []
	var cabins: LandmarkBuilder.Part = null
	for part in cable.parts:
		names.append(part.name)
		if part.name == "cabin":
			cabins = part
	assert_true(names.has("cable_tower") and names.has("cable_station") and names.has("cable"), str(names))
	assert_not_null(cabins, "кабинки")
	if cabins != null:
		assert_true(cabins.animated, "кабинки едут в шейдере")
		for t in cabins.xf:
			assert_gt(t.origin.y - s.terrain().height_at(t.origin.x, t.origin.z), 3.0, "кабинка над землёй")


func test_mountains_visible_budget_keeps_reserve_on_switchbacks() -> void:
	var s := _scene(RouteCatalog.MOUNTAINS)
	var c := PerfBudget.count(s)
	assert_lte(int(c["mesh_instances"]), PerfBudget.MAX_MESH_INSTANCES, "MeshInstance3D %d" % c["mesh_instances"])
	var visible: int = PerfBudget.max_visible_along([s], s.track, 25.0)
	gut.p("горы: видно ≤ %d экземпляров MultiMesh (шаг 25 м), всего %d" % [visible, c["multimesh_instances"]])
	assert_lte(visible, PerfBudget.MAX_VISIBLE_MULTIMESH_INSTANCES - s.environment_set.visible_reserve / 2,
		"запас бюджета видимых на змейке")


func test_mountains_far_tiles_lod_has_no_cracks() -> void:
	var tf: TerrainField = _scene(RouteCatalog.MOUNTAINS).terrain()
	var far: int = 0
	for st in tf.tile_step:
		far += 1 if st == TerrainField.FAR_STEP else 0
	assert_gt(far, 100, "дальние плитки (третья ступень LOD)")
	var checked: int = 0
	var cracks: int = 0
	for ti in tf.tile_keys.size():
		var step: int = tf.tile_step[ti]
		var key: Vector2i = tf.tile_keys[ti]
		var right := key + Vector2i(1, 0)
		if not tf.tile_index.has(right):
			continue
		var tj: int = tf.tile_index[right]
		var other: int = tf.tile_step[tj]
		if other <= step:
			continue
		var n: int = TerrainField.TILE_CELLS / step + 1
		var on: int = TerrainField.TILE_CELLS / other + 1
		var h: PackedFloat32Array = tf.tile_heights[ti]
		var oh: PackedFloat32Array = tf.tile_heights[tj]
		var ratio: int = other / step
		for m in n:
			var m0: int = m / ratio
			var r: int = m % ratio
			var expect: float = oh[m0 * on] if r == 0 else lerpf(oh[m0 * on], oh[(m0 + 1) * on], float(r) / float(ratio))
			checked += 1
			if absf(h[m * n + n - 1] - expect) > 1e-3:
				cracks += 1
	assert_gt(checked, 0)
	assert_eq(cracks, 0, "стыки плиток разного шага без щелей")


# ---------------------------------------------------------------------------
# Приморье (T-088, REQ-D3D-08 п.6, 8, 11, 12 — `seaside`; `tracks.md` п. 4.4)
# ---------------------------------------------------------------------------

func _seaside() -> RideScene:
	return _scene(RouteCatalog.SEASIDE)


func test_seaside_environment_set_follows_tracks_md() -> void:
	var env: EnvironmentSet = RouteWorld.environment(RouteCatalog.SEASIDE)
	assert_true(env.water_enabled, "приморье: вода")
	assert_false(env.sea_s_ranges.is_empty(), "участки с морем")
	assert_eq(env.conifer_kind, 1, "зонтичные сосны")
	assert_almost_eq(env.hills_height_m, 60.0, 0.5, "холмы 60 м со стороны суши")
	assert_almost_eq(env.fog_density, 0.0006, 1e-5)
	assert_true(env.sun_color.is_equal_approx(Color(1.0, 0.95, 0.86)), "солнце (1.0, 0.95, 0.86)")
	assert_almost_eq(env.sun_energy, 0.9, 1e-3)
	assert_true(env.sky_color.is_equal_approx(Color(0.30, 0.62, 0.92)), "зенит")
	assert_true(env.horizon_color.is_equal_approx(Color(0.80, 0.90, 0.96)), "горизонт")
	var mat := (env.water_material if env.water_material != null else load(RideScene.DEFAULT_WATER_MATERIAL)) as ShaderMaterial
	assert_not_null(mat, "материал воды — шейдер")
	assert_true((mat.get_shader_parameter("deep_color") as Color).is_equal_approx(Color(0.10, 0.42, 0.62)), "глубокая вода")
	assert_true((mat.get_shader_parameter("shallow_color") as Color).is_equal_approx(Color(0.22, 0.68, 0.75)), "мелкая вода")
	assert_true((mat.get_shader_parameter("foam_color") as Color).is_equal_approx(Color(0.95, 0.97, 0.98)), "пена")
	var tm := env.terrain_material as ShaderMaterial
	assert_almost_eq(float(tm.get_shader_parameter("water_level")), 0.0, 1e-3, "песок по высоте над водой")
	# Альбедо песка темнее палитры (0.90, 0.82, 0.62): под солнцем и небом он читается её цветом, а не белым.
	var sand: Color = tm.get_shader_parameter("sand_color")
	assert_true(sand.r > sand.g and sand.g > sand.b and sand.r > 0.7, "песок — тёплый светлый (%s)" % str(sand))


func test_seaside_water_surface_is_one_opaque_mesh_at_water_level() -> void:
	var s := _seaside()
	var water: MeshInstance3D = s.water()
	assert_not_null(water, "водная поверхность в мире приморья (D3D-08 п.6)")
	if water == null:
		return
	assert_true(s.world_nodes().has(water), "вода — узел мира трассы")
	var level: float = RouteCatalog.get_route(RouteCatalog.SEASIDE).water_level_m
	var arrays: Array = water.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var off: int = 0
	var deep: int = 0
	for i in verts.size():
		if absf(verts[i].y - level) > 1e-3:
			off += 1
		if uvs[i].x > 2.0:
			deep += 1
	assert_eq(off, 0, "вода плоская, на уровне воды трассы")
	assert_gt(deep, 0, "в UV.x — глубина под водой")
	var aabb: AABB = water.get_aabb()
	assert_gt(maxf(aabb.size.x, aabb.size.z), 8000.0, "море до горизонта")
	assert_eq(water.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var mat := water.mesh.surface_get_material(0) as ShaderMaterial
	assert_not_null(mat)
	var code: String = mat.shader.code
	assert_true(code.contains("TIME"), "волны и пена анимируются в шейдере")
	for banned in ["ALPHA", "hint_depth_texture", "hint_screen_texture", "SCREEN_TEXTURE", "DEPTH_TEXTURE"]:
		assert_false(code.contains(banned), "без прозрачности, глубины и экрана: %s" % banned)
	var c := PerfBudget.count(s)
	assert_lte(int(c["lights"]), PerfBudget.MAX_LIGHTS, "свет маяка — без источника света")


func test_seaside_terrain_goes_under_water_on_sea_side_with_beach() -> void:
	var s := _seaside()
	var tf: TerrainField = s.terrain()
	var level: float = tf.water_level
	var sample := TrackSample.new()
	var bad: Array[String] = []
	var beaches: int = 0
	var points: int = 0
	for at in range(400, 4600, 300):
		s.track.sample_into(float(at), sample)
		points += 1
		var r: Vector3 = sample.right()
		var sea: Vector3 = sample.position + r * 320.0
		var land: Vector3 = sample.position - r * 320.0
		if tf.height_at(sea.x, sea.z) > level - 1.0:
			bad.append("s=%d: справа на 320 м не море (%.1f м)" % [at, tf.height_at(sea.x, sea.z)])
		if tf.height_at(land.x, land.z) < level + 2.0:
			bad.append("s=%d: слева на 320 м не суша" % at)
		for v in range(40, 300, 4):
			var p: Vector3 = sample.position + r * float(v)
			var h: float = tf.height_at(p.x, p.z)
			if h > level + 0.2 and h < level + 2.0:
				beaches += 1
				break
	assert_eq(bad, [] as Array[String], str(bad.slice(0, 5)))
	assert_eq(beaches, points, "между дорогой и водой — пляж")
	var hills_sea: float = -INF
	for at in range(400, 4600, 300):
		s.track.sample_into(float(at), sample)
		var p: Vector3 = sample.position + sample.right() * 650.0
		hills_sea = maxf(hills_sea, tf.height_at(p.x, p.z))
	assert_lt(hills_sea, level, "со стороны моря холмов нет — горизонт открыт")


func test_seaside_river_under_bridge_range_and_deck_10m_above_water() -> void:
	var s := _seaside()
	var tf: TerrainField = s.terrain()
	var def: RouteCatalog.RouteDef = RouteCatalog.get_route(RouteCatalog.SEASIDE)
	var bridge: Vector2 = def.bridges[0]
	assert_gt(tf.river_points.size(), 10, "река — ломаная")
	assert_false(is_nan(tf.river_crossing_s), "река пересекает дорогу")
	assert_between(tf.river_crossing_s, bridge.x + 20.0, bridge.y - 20.0, "переход реки — на диапазоне моста (D3D-08 п.11)")
	var sample := TrackSample.new()
	s.track.sample_into(tf.river_crossing_s, sample)
	assert_gte(sample.position.y - def.water_level_m, 10.0, "полотно над водой ≥ 10 м")
	# У перехода — вода реки по обе стороны дороги (под мостом, T-090).
	var cross: Vector3 = tf.river_crossing
	var near: Array[Vector3] = []
	for p in tf.river_points:
		var d: float = Vector2(p.x - cross.x, p.z - cross.z).length()
		if d > 40.0 and d < 140.0:
			near.append(p)
	var sides: Dictionary = {}
	for p in near:
		if tf.water_depth_at(p.x, p.z) > 0.5:
			sides[signf((p - cross).dot(sample.right()))] = true
	assert_eq(sides.size(), 2, "вода реки по обе стороны дороги у перехода")
	# Русло доходит до моря, исток — озеро внутри петли.
	var mouth: Vector3 = tf.river_points[tf.river_points.size() - 1]
	assert_gt(tf.water_depth_at(mouth.x, mouth.z), 1.0, "устье в море")
	var head: Vector3 = tf.river_points[0]
	assert_gt(tf.water_depth_at(head.x, head.z), 1.0, "озеро у истока")
	assert_lt(tf.sea_mask_at(head.x, head.z), 0.01, "озеро — внутри петли, не море")
	var water: MeshInstance3D = s.water()
	assert_true(water.get_aabb().has_point(Vector3(near[0].x, tf.water_level, near[0].z)), "река — часть водной поверхности")


func test_seaside_vegetation_not_on_beach_or_in_water() -> void:
	var s := _seaside()
	var env: EnvironmentSet = s.environment_set
	var tf: TerrainField = s.terrain()
	var layers := SceneryBuilder.place(s.track, env, tf, null, PerfBudget.MAX_VISIBLE_MULTIMESH_INSTANCES,
		PerfBudget.MAX_MULTIMESH_INSTANCES, LandmarkBuilder.keep_out(s.landmarks_placed()))
	var wet: int = 0
	var pines: int = 0
	for layer in layers:
		if layer.name == "Tufts":
			continue
		if layer.name.begins_with("Conifers"):
			pines += layer.xf.size()
		for t in layer.xf:
			if t.origin.y < tf.water_level + env.shore_clear_m - 0.5:
				wet += 1
	assert_eq(wet, 0, "деревья и кусты не на пляже и не в воде")
	assert_gt(pines, 50, "зонтичные сосны")
	var conifers: Array[Node] = s.world_nodes().filter(func(n: Node) -> bool: return n.name == "Conifers")
	assert_eq(conifers.size(), 1)
	var mm: MultiMesh = (conifers[0] as MultiMeshInstance3D).multimesh
	var forms: Dictionary = conifers[0].get_meta(&"conifer_forms", {})
	assert_true(forms.has("stone_pine"), "хвойные приморья — зонтичная сосна (пиния): %s" % str(forms))
	for key in forms:
		assert_true(ConiferKit.is_pine(ConiferKit.FORM_KEYS.find(String(key))), "на приморье только пинии: %s" % key)
	assert_eq(mm.mesh, ConiferKit.layer_mesh(ConiferKit.models_for(ConiferKit.mix_forms(ConiferKit.form_mix(s.environment_set)), 0), 0,
		mm.mesh.surface_get_material(0)), "меш слоя — пинии (T-107)")


func test_seaside_lighthouse_on_headland_with_glowing_rotating_lamp() -> void:
	var s := _seaside()
	var tf: TerrainField = s.terrain()
	var found: Array = s.landmarks_placed().filter(func(p: LandmarkBuilder.Placed) -> bool: return p.type == "lighthouse")
	assert_eq(found.size(), 1, "маяк")
	var pl: LandmarkBuilder.Placed = found[0]
	assert_eq(pl.headlands.size(), 1, "маяк — на мысу")
	assert_almost_eq(tf.height_at(pl.anchor.x, pl.anchor.z), pl.anchor.y, 0.6, "башня стоит на площадке мыса")
	var hl: LandmarkBuilder.Headland = pl.headlands[0]
	var tip: Vector3 = hl.to + (hl.to - hl.from).normalized() * (hl.half_width + 60.0)
	assert_gt(tf.water_depth_at(tip.x, tip.z), 1.0, "за мысом — море")
	var lamps: Array = pl.parts.filter(func(p: LandmarkBuilder.Part) -> bool: return p.name == "lighthouse_lamp")
	assert_eq(lamps.size(), 1, "свет маяка")
	var lamp: LandmarkBuilder.Part = lamps[0]
	assert_true(lamp.animated, "свет вращается в шейдере")
	assert_ne(lamp.custom[0].r, 0.0, "скорость вращения")
	assert_lt(lamp.custom[0].a, 0.0, "свечение без источника света (w < 0)")
	var lights: Array[Node] = s.find_children("*", "Light3D", true, false)
	assert_eq(lights.size(), 1, "свет сцены — только солнце")


func test_seaside_boats_float_at_water_level() -> void:
	var s := _seaside()
	var tf: TerrainField = s.terrain()
	var floating: int = 0
	for pl in s.landmarks_placed():
		for part in pl.parts:
			if not ["moored_boats", "river_boats", "sailboat"].has(part.name):
				continue
			for t in part.xf:
				floating += 1
				assert_almost_eq(t.origin.y, tf.water_level, 1e-3, "%s на воде" % part.name)
				assert_gt(tf.water_depth_at(t.origin.x, t.origin.z), 0.4, "%s: под ним вода" % part.name)
	assert_gte(floating, 5, "лодки у причала и в устье, парусники")


func test_horizon_height_flat_lower_than_seaside_lower_than_hills() -> void:
	var tops: Dictionary = {}
	for id in [RouteCatalog.FLAT, RouteCatalog.SEASIDE, RouteCatalog.HILLS]:
		var s := _scene(id)
		var tf: TerrainField = s.terrain()
		var start_y: float = s.track.sample(0.0).position.y
		var top: float = -INF
		for h in tf.tile_heights:
			for v in h:
				top = maxf(top, v)
		tops[id] = top - start_y
	gut.p("горизонт над стартом: %s" % str(tops))
	assert_lt(float(tops[RouteCatalog.FLAT]), float(tops[RouteCatalog.SEASIDE]), "равнина < приморье")
	assert_lt(float(tops[RouteCatalog.SEASIDE]), float(tops[RouteCatalog.HILLS]), "приморье < холмы")


func test_seaside_landmarks_on_shore_and_pier_reaches_water() -> void:
	var s := _seaside()
	var tf: TerrainField = s.terrain()
	var level: float = tf.water_level
	var seen: Array[String] = []
	for pl in s.landmarks_placed():
		match pl.type:
			"beach_umbrellas", "lifeguard_tower":
				var on_sand: int = 0
				var total: int = 0
				for part in pl.parts:
					if not part.name.begins_with("umbrella"):
						continue
					for t in part.xf:
						total += 1
						if t.origin.y > level and t.origin.y < level + 3.0:
							on_sand += 1
				assert_gt(total, 0, "%s: зонтики" % pl.type)
				assert_eq(on_sand, total, "%s: зонтики на песке у воды" % pl.type)
				seen.append(pl.type)
			"fishing_pier":
				var pier: Array = pl.parts.filter(func(p: LandmarkBuilder.Part) -> bool: return p.name == "pier")
				assert_eq(pier.size(), 1, "причал")
				var verts: PackedVector3Array = (pier[0] as LandmarkBuilder.Part).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				var over_water: int = 0
				for v in verts:
					if tf.water_depth_at(v.x, v.z) > 1.0:
						over_water += 1
				assert_gt(over_water, 20, "причал уходит в море")
				seen.append(pl.type)
	assert_eq(seen.size(), 3, "причал, пляж и вышка спасателя: %s" % str(seen))


# ---------------------------------------------------------------------------
# Хвойные (T-107, REQ-D3D-10; числа — арт-библия «Растительность: хвойные», `ConiferKit`)
# ---------------------------------------------------------------------------

## Уникальных материалов сцены до T-107 (a03d1f8): хвойные не добавляют материалов (п.4).
const MATERIALS_BEFORE_T107: Dictionary = {"flat": 5, "hills": 5, "mountains": 5, "seaside": 6}

var _conifer_place: Dictionary = {}


## Расстановка хвойных трассы (все экземпляры до прореживания) — слои `Conifers*`.
func _conifer_layers(id: String) -> Array[SceneryBuilder.Layer]:
	if not _conifer_place.has(id):
		var s := _scene(id)
		var out: Array[SceneryBuilder.Layer] = []
		for layer in SceneryBuilder.place(s.track, s.environment_set, s.terrain(), null, PerfBudget.MAX_VISIBLE_MULTIMESH_INSTANCES,
				PerfBudget.MAX_MULTIMESH_INSTANCES, LandmarkBuilder.keep_out(s.landmarks_placed())):
			if layer.name.begins_with("Conifers"):
				out.append(layer)
		_conifer_place[id] = out
	return _conifer_place[id]


func _conifer_plants(id: String) -> Array[ConiferKit.Plant]:
	var out: Array[ConiferKit.Plant] = []
	for layer in _conifer_layers(id):
		out.append_array(layer.plants)
	return out


## Узлы слоёв хвойных в мире сцены.
func _conifer_nodes(s: RideScene) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	for n in s.world_nodes():
		if String(n.name).begins_with("Conifers"):
			out.append(n as MultiMeshInstance3D)
	return out


## REQ-D3D-10 п.1: в сцене каждой трассы — не меньше трёх форм хвойных, набор — из распределения
## спеки (приморье — пинии); доли форм — по спеке ±10 п.п.; горы: у границы леса пихта и
## ветровал ≥ 60 %; приморье: наклонные пинии — у воды (≤ 150 м).
func test_req_d3d_10_c1_conifer_forms_per_track_follow_spec() -> void:
	for id in IDS:
		var s := _scene(id)
		var mix: Dictionary = ConiferKit.form_mix(s.environment_set)
		var in_scene: Dictionary = {}
		for n in _conifer_nodes(s):
			var forms: Dictionary = n.get_meta(&"conifer_forms", {})
			for key in forms:
				in_scene[key] = int(in_scene.get(key, 0)) + int(forms[key])
		assert_gte(in_scene.size(), 3, "%s: в сцене не меньше трёх форм хвойных: %s" % [id, str(in_scene)])
		for key in in_scene:
			assert_true(mix.has(ConiferKit.FORM_KEYS.find(String(key))), "%s: форма %s — из распределения спеки" % [id, key])
		var plants := _conifer_plants(id)
		var counts: Dictionary = {}
		for p in plants:
			counts[p.form] = int(counts.get(p.form, 0)) + 1
		for f in mix:
			var share: float = float(counts.get(f, 0)) / float(maxi(plants.size(), 1))
			assert_almost_eq(share, float(mix[f]), 0.10, "%s: доля %s" % [id, ConiferKit.FORM_KEYS[f]])
	assert_true(ConiferKit.form_mix(_scene(RouteCatalog.SEASIDE).environment_set).has(ConiferKit.STONE_PINE), "приморье — пиния")
	# Горы: полоса 60 м ниже границы леса.
	var env: EnvironmentSet = _scene(RouteCatalog.MOUNTAINS).environment_set
	var band: int = 0
	var high: int = 0
	for p in _conifer_plants(RouteCatalog.MOUNTAINS):
		if p.origin.y > env.tree_line_m - env.conifer_tree_line_band_m:
			band += 1
			if p.form == ConiferKit.FIR or p.form == ConiferKit.SPRUCE_WIND:
				high += 1
	assert_gt(band, 20, "у границы леса есть хвойные")
	assert_gte(float(high) / float(maxi(band, 1)), 0.6, "у границы леса пихта и ветровал ≥ 60 %% (%d из %d)" % [high, band])
	# Приморье: наклонные — у воды, наклон к ней.
	var tf: TerrainField = _scene(RouteCatalog.SEASIDE).terrain()
	var lean: int = 0
	var far: int = 0
	for p in _conifer_plants(RouteCatalog.SEASIDE):
		if p.form != ConiferKit.STONE_PINE_LEAN:
			continue
		lean += 1
		if p.lean_dir == Vector3.ZERO or not _water_within(tf, p.origin, 150.0):
			far += 1
	assert_gt(lean, 20, "наклонные пинии есть")
	assert_eq(far, 0, "наклонные пинии — в 150 м от воды, наклон к воде")


func _water_within(tf: TerrainField, p: Vector3, reach: float) -> bool:
	for k in 16:
		var a: float = TAU * float(k) / 16.0
		var d: float = 10.0
		while d <= reach:
			if tf.water_depth_at(p.x + cos(a) * d, p.z + sin(a) * d) > 0.0:
				return true
			d += 10.0
	return false


## REQ-D3D-10 п.2: масштаб, растяжение, наклон, поворот и оттенок — в диапазонах спеки; ни один
## из масштаба, поворота и оттенка не одинаков у всех экземпляров одной формы.
func test_req_d3d_10_c2_conifer_variations_within_spec_ranges() -> void:
	for id in IDS:
		var by_form: Dictionary = {}
		for p in _conifer_plants(id):
			var f: int = p.form
			var pine: bool = ConiferKit.is_pine(f)
			var tag: String = "%s %s" % [id, ConiferKit.FORM_KEYS[f]]
			assert_between(p.scale, ConiferKit.SCALE_RANGE[f].x, ConiferKit.SCALE_RANGE[f].y, "%s: масштаб" % tag)
			var st: Vector2 = ConiferKit.STRETCH_PINE if pine else ConiferKit.STRETCH_SPRUCE
			assert_between(p.stretch, st.x, st.y, "%s: растяжение по Y" % tag)
			var tilt_max: float = ConiferKit.TILT_PINE_DEG if pine else ConiferKit.TILT_SPRUCE_SLOPE_DEG
			if f == ConiferKit.STONE_PINE_LEAN and p.lod > 0:
				tilt_max += ConiferKit.LEAN_TILT_DEG
			assert_lte(rad_to_deg(p.tilt), tilt_max + 1e-3, "%s: наклон оси" % tag)
			var br: Vector2 = ConiferKit.BRIGHT_PINE if pine else ConiferKit.BRIGHT_SPRUCE
			var rr: Vector2 = ConiferKit.RED_PINE if pine else ConiferKit.RED_SPRUCE
			var bb: Vector2 = ConiferKit.BLUE_PINE if pine else ConiferKit.BLUE_SPRUCE
			assert_between(p.tint.x, br.x, br.y, "%s: яркость" % tag)
			assert_between(p.tint.y, rr.x, rr.y, "%s: множитель R" % tag)
			assert_between(p.tint.z, bb.x, bb.y, "%s: множитель B" % tag)
			if not by_form.has(f):
				by_form[f] = []
			(by_form[f] as Array).append(Vector3(p.scale, p.yaw, p.tint.x))
		for f in by_form:
			var rows: Array = by_form[f]
			if rows.size() < 2:
				continue
			for axis in 3:
				var lo: float = INF
				var hi: float = -INF
				for r in rows:
					lo = minf(lo, (r as Vector3)[axis])
					hi = maxf(hi, (r as Vector3)[axis])
				assert_gt(hi - lo, 1e-3, "%s %s: параметр %d различается у экземпляров" % [id, ConiferKit.FORM_KEYS[f], axis])


## REQ-D3D-10 п.3: треугольников экземпляра каждой формы на каждом уровне — не больше спеки
## (по слоту формы в меше слоя); уровень назначен по удалению от трассы (≤ 60 / ≤ 220 / дальше),
## экземпляр — в слое своего уровня; дальность видимости кусков — как у деревьев, переключения
## в кадре нет (без `visibility_range_begin`).
func test_req_d3d_10_c3_conifer_lod_triangles_and_switch_distances() -> void:
	for f in ConiferKit.FORM_KEYS.size():
		for lod in ConiferKit.LOD_COUNT:
			var tris: int = ConiferKit.triangles(ConiferKit.model_of(f, lod), lod)
			assert_gt(ConiferKit.tri_budget(f, lod), 0, "%s LOD%d: бюджет из спеки" % [ConiferKit.FORM_KEYS[f], lod])
			assert_lte(tris, ConiferKit.tri_budget(f, lod), "%s LOD%d: %d треугольников" % [ConiferKit.FORM_KEYS[f], lod, tris])
	for id in IDS:
		var s := _scene(id)
		var forms: PackedInt32Array = ConiferKit.mix_forms(ConiferKit.form_mix(s.environment_set))
		for lod in ConiferKit.LOD_COUNT:
			var models: PackedInt32Array = ConiferKit.models_for(forms, lod)
			var mesh: ArrayMesh = ConiferKit.layer_mesh(models, lod, null)
			var arrays: Array = mesh.surface_get_arrays(0)
			var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var per_slot := PackedInt32Array()
			per_slot.resize(models.size())
			var mixed: int = 0
			for t in range(0, idx.size(), 3):
				var slot: int = maxi(int(round(uv2[idx[t]].x)) - 1, 0)
				for k in 3:
					if maxi(int(round(uv2[idx[t + k]].x)) - 1, 0) != slot:
						mixed += 1
				per_slot[slot] += 1
			assert_eq(mixed, 0, "%s LOD%d: каждый треугольник — в одном слоте формы" % [id, lod])
			for f in forms:
				var slot: int = models.find(ConiferKit.model_of(f, lod))
				assert_lte(per_slot[slot], ConiferKit.tri_budget(f, lod), "%s %s LOD%d: треугольников в меше слоя" % [id, ConiferKit.FORM_KEYS[f], lod])
		var bad: Array[String] = []
		var axis: PackedVector2Array = _track_points(s.track, 4.0)
		var k: int = 0
		for layer in _conifer_layers(id):
			for p in layer.plants:
				if layer.name != SceneryBuilder.CONIFER_LAYERS[p.lod] or p.lod != ConiferKit.lod_of(p.road_m):
					bad.append("s=%.0f: слой %s, LOD%d, %.1f м" % [p.s, layer.name, p.lod, p.road_m])
					continue
				# Удаление — не больше расстояния до оси около своей точки выборки.
				var near_m: float = _track_distance(s.track, p.origin, p.s)
				if p.road_m > near_m + 1.0:
					bad.append("s=%.0f: до трассы у своей точки %.1f м < %.1f м" % [p.s, near_m, p.road_m])
				# Каждое пятое — перебором всей оси (серпантин: соседний виток ближе своей точки).
				k += 1
				if k % 5 != 0:
					continue
				var true_m: float = _nearest_point(axis, p.origin)
				if true_m <= ConiferKit.LOD_FAR_M + 10.0 and absf(true_m - p.road_m) > 1.0:
					bad.append("s=%.0f: до трассы %.1f м, удаление %.1f м" % [p.s, true_m, p.road_m])
				if p.lod != ConiferKit.lod_of(true_m) and absf(true_m - ConiferKit.LOD_NEAR_M) > 1.0 and absf(true_m - ConiferKit.LOD_FAR_M) > 1.0:
					bad.append("s=%.0f: LOD%d, а до трассы %.1f м" % [p.s, p.lod, true_m])
		assert_eq(bad, [] as Array[String], "%s: уровни по удалению от трассы: %s" % [id, str(bad.slice(0, 5))])
		for n in _conifer_nodes(s):
			for part: MultiMeshInstance3D in [n] + n.get_children():
				assert_eq(part.visibility_range_begin, 0.0, "%s: уровни не переключаются в кадре" % id)
				if part.visibility_range_end > 0.0:
					assert_almost_eq(part.visibility_range_end, PerfBudget.RANGE_TREES_M, 1e-3, "%s: дальность — как у деревьев" % id)


## Точки оси трассы с шагом `step_m` (в плане).
func _track_points(track: Track, step_m: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var sample := TrackSample.new()
	var at: float = 0.0
	while at <= track.length_m():
		track.sample_into(at, sample)
		out.append(Vector2(sample.position.x, sample.position.z))
		at += step_m
	return out


## Расстояние в плане до ближайшей точки `pts` (перебор; шаг точек 4 м — ошибка ≤ 0.05 м на 40 м).
func _nearest_point(pts: PackedVector2Array, p: Vector3) -> float:
	var q := Vector2(p.x, p.z)
	var best: float = INF
	for a in pts:
		best = minf(best, q.distance_squared_to(a))
	return sqrt(best)


## Расстояние от точки до оси трассы по выборке с шагом 5 м в окне ±400 м вокруг `s` (верхняя
## оценка расстояния до ближайшей точки трассы).
func _track_distance(track: Track, p: Vector3, s: float) -> float:
	var sample := TrackSample.new()
	var best: float = INF
	var d: float = -400.0
	while d <= 400.0:
		track.sample_into(fposmod(s + d, track.length_m()) if track.is_loop() else clampf(s + d, 0.0, track.length_m()), sample)
		best = minf(best, Vector2(sample.position.x - p.x, sample.position.z - p.z).length())
		d += 5.0
	return best


## REQ-D3D-10 п.4: слоёв MultiMesh хвойных ≤ 6; материалов не больше, чем до T-107, и ≤ 12;
## экземпляров всего ≤ 40000; строка бюджета хвойных в `docs/perf_budget.md`.
func test_req_d3d_10_c4_conifer_layers_materials_and_budget_row() -> void:
	for id in IDS:
		var s := _scene(id)
		var layers: Array[MultiMeshInstance3D] = _conifer_nodes(s)
		assert_between(layers.size(), 1, PerfBudget.MAX_CONIFER_LAYERS, "%s: слоёв хвойных" % id)
		var c := PerfBudget.count(s)
		assert_lte(int(c["materials"]), int(MATERIALS_BEFORE_T107[id]), "%s: материалов не больше, чем до T-107" % id)
		assert_lte(int(c["materials"]), PerfBudget.MAX_MATERIALS)
		assert_lte(int(c["multimesh_instances"]), PerfBudget.MAX_MULTIMESH_INSTANCES)
		for n in layers:
			var tris: int = 0
			var count: int = 0
			for part: MultiMeshInstance3D in [n] + n.get_children():
				tris += int(part.get_meta(&"triangles", 0))
				count += part.multimesh.instance_count
			if count > 0:
				assert_gt(tris, 0, "%s %s: треугольники кусков посчитаны" % [id, n.name])
	var text := FileAccess.get_file_as_string("res://docs/perf_budget.md")
	var row := RegEx.create_from_string("\\|[^|]*Хвойные: треугольников в кадре[^|]*\\| *(\\d+) *\\|").search(text)
	assert_not_null(row, "строка бюджета хвойных в docs/perf_budget.md")
	if row != null:
		assert_eq(int(row.get_string(1)), PerfBudget.MAX_CONIFER_FRAME_TRIANGLES)
	var layers_row := RegEx.create_from_string("\\|[^|]*Слоёв `MultiMesh` хвойных[^|]*\\| *(\\d+) *\\|").search(text)
	assert_not_null(layers_row, "строка бюджета слоёв хвойных")
	if layers_row != null:
		assert_eq(int(layers_row.get_string(1)), PerfBudget.MAX_CONIFER_LAYERS)
	assert_string_contains(text, "MacBook на базовом M1", "эталон бюджета указан явно")


## Бюджет кадра (арт-библия «Бюджет»): треугольников хвойных в кадре рабочей камеры (без контура,
## куски в дальности видимости и в пирамиде камеры) — не больше 260 тыс. на всех трассах, шаг 100 м.
func test_conifer_triangles_in_frame_within_budget() -> void:
	for id in IDS:
		var s := _scene(id)
		var nodes: Array[MultiMeshInstance3D] = _conifer_nodes(s)
		var best: int = 0
		var at: float = 0.0
		while at < s.track.length_m():
			_drive_to(s, at, 32.0, 30)
			var cam: Camera3D = s.camera()
			var fr: Array[Plane] = []
			fr.assign(cam.get_frustum())
			var t: int = 0
			for n in nodes:
				t += PerfBudget.frame_triangles(n, cam.global_position, fr)
			best = maxi(best, t)
			at += 100.0
		gut.p("%s: треугольников хвойных в кадре — до %d" % [id, best])
		assert_lte(best, PerfBudget.MAX_CONIFER_FRAME_TRIANGLES, "%s: треугольников хвойных в кадре" % id)
		if id != RouteCatalog.FLAT:
			assert_gt(best, 0, "%s: хвойные в кадре есть (подсчёт работает)" % id)


## Средняя (по площади) яркость HSV V цвета вершин верха кроны модели (грани кроны, смотрящие
## вверх), sRGB — без света; прокси замера галереи «Тон LOD1» без рендера.
func _crown_top_v(model: int, lod: int) -> float:
	var g: ConiferKit.Geo = ConiferKit.geometry(model, lod)
	var sum: float = 0.0
	var area: float = 0.0
	for t in range(0, g.idx.size(), 3):
		var i: PackedInt32Array = [g.idx[t], g.idx[t + 1], g.idx[t + 2]]
		if g.f[i[0]].y < 0.99 or g.f[i[1]].y < 0.99 or g.f[i[2]].y < 0.99:
			continue
		var fn: Vector3 = (g.v[i[2]] - g.v[i[0]]).cross(g.v[i[1]] - g.v[i[0]])
		if fn.y <= 0.0:
			continue
		var a: float = fn.length() * 0.5
		for k in i:
			sum += g.c[k].linear_to_srgb().v * a / 3.0
		area += a
	return sum / area


## Арт-библия ред. 3 (вердикт game-designer по T-107): калибровка яркости ели — в диапазоне
## вердикта (1.15–1.25), пиния — 1.15 без изменений; край яруса LOD1 — средний тон
## (свет + кончики) / 2, тона кончиков на LOD1 нет; средняя яркость верха кроны LOD1 — в пределах
## 0.04 от LOD0 той же модели; кора ели, пихты и ветровала тёплая (R − B ≥ 0.03, R > G > B) и
## светлее таблицы (под юбкой в холодном окружающем свете кора по таблице — цвета контура);
## горы — `conifer_shade` не ниже 0.92. Замеры по кадрам (маска «Как мерить») — в отчёте T-107.
func test_conifer_tone_calibration_lod1_edge_and_bark_rev3() -> void:
	assert_between(ConiferKit.TONE_GAIN_SPRUCE, 1.15, 1.25, "калибровка ели — в диапазоне вердикта")
	assert_almost_eq(ConiferKit.TONE_GAIN_PINE, 1.15, 1e-6, "калибровка пинии не меняется")
	var env: EnvironmentSet = _scene(RouteCatalog.MOUNTAINS).environment_set
	assert_between(env.conifer_shade, 0.92, 0.99, "горы: conifer_shade не ниже 0.92 и темнее равнин")
	for model in [ConiferKit.M_SPRUCE, ConiferKit.M_FIR, ConiferKit.M_PINE]:
		var tones: PackedColorArray = ConiferKit.tones_of(model)
		var tag: String = ConiferKit.MODEL_KEYS[model]
		var edge: Color = ConiferKit.lod1_edge(tones)
		assert_true(edge.is_equal_approx((tones[0] + tones[2]) * 0.5), "%s: край LOD1 — (свет + кончики) / 2" % tag)
		var g: ConiferKit.Geo = ConiferKit.geometry(model, 1)
		var edges: int = 0
		var tips: int = 0
		for c in g.c:
			if c.is_equal_approx(MeshKit.lin(Color(edge.r, edge.g, edge.b, c.a))):
				edges += 1
			elif c.is_equal_approx(MeshKit.lin(Color(tones[2].r, tones[2].g, tones[2].b, c.a))):
				tips += 1
		assert_gt(edges, 0, "%s LOD1: край средним тоном" % tag)
		assert_eq(tips, 0, "%s LOD1: отдельного тона кончиков нет" % tag)
	for model in [ConiferKit.M_SPRUCE, ConiferKit.M_FIR]:
		var v0: float = _crown_top_v(model, 0)
		var v1: float = _crown_top_v(model, 1)
		gut.p("%s: V верха кроны LOD0 %.3f, LOD1 %.3f" % [ConiferKit.MODEL_KEYS[model], v0, v1])
		assert_almost_eq(v1, v0, 0.04, "%s: тон LOD1 без ступени к LOD0" % ConiferKit.MODEL_KEYS[model])
	var tables: Array[PackedColorArray] = [ConiferKit.TONES_SPRUCE, ConiferKit.TONES_FIR, ConiferKit.TONES_WIND]
	for model in [ConiferKit.M_SPRUCE, ConiferKit.M_FIR, ConiferKit.M_WIND]:
		var bark: Color = ConiferKit.tones_of(model)[3]
		var tag: String = ConiferKit.MODEL_KEYS[model]
		assert_gte(bark.r - bark.b, 0.03, "%s: кора тёплая, R − B" % tag)
		assert_true(bark.r > bark.g and bark.g > bark.b, "%s: кора бурая (R > G > B), не лиловая" % tag)
		assert_gt(bark.v, tables[model][3].v + 0.05, "%s: кора светлее таблицы (не цвета контура)" % tag)


## Арт-библия ред. 4, «Нормали» и «Низ юбки» (повторный вердикт по T-107): низ юбки ели, пихты и
## ветровала на всех уровнях — нормали подняты (наружу + вверх), тень — вершинным цветом не темнее
## тона тени таблицы: с нормалью грани вниз тун-свет давал под ярусом чёрную полосу (горы 14500 м —
## 19 px, V 0.075). Срезы кроны по кадрам (полосы V < 0.18 толще 4 px) — в отчёте T-107.
func test_conifer_skirt_underside_lit_normals_rev4() -> void:
	for model in [ConiferKit.M_SPRUCE, ConiferKit.M_FIR, ConiferKit.M_WIND]:
		var shade_v: float = ConiferKit.tones_of(model)[1].v
		for lod in ConiferKit.LOD_COUNT:
			var tag: String = "%s LOD%d" % [ConiferKit.MODEL_KEYS[model], lod]
			var g: ConiferKit.Geo = ConiferKit.geometry(model, lod)
			var under: int = 0
			var low_n: int = 0
			var dark: int = 0
			for t in range(0, g.idx.size(), 3):
				var i: PackedInt32Array = [g.idx[t], g.idx[t + 1], g.idx[t + 2]]
				if g.f[i[0]].y < 0.99 or g.f[i[1]].y < 0.99 or g.f[i[2]].y < 0.99:
					continue
				var fn: Vector3 = (g.v[i[2]] - g.v[i[0]]).cross(g.v[i[1]] - g.v[i[0]])
				if fn.length_squared() < 1e-12 or fn.normalized().y > -0.3:
					continue
				under += 1
				for k in i:
					if g.n[k].y < ConiferKit.UNDER_MIN_NORMAL_Y:
						low_n += 1
					if g.c[k].linear_to_srgb().v < shade_v - 1e-3:
						dark += 1
			assert_gt(under, 0, "%s: грани низа юбки есть" % tag)
			assert_eq(low_n, 0, "%s: нормали низа юбки подняты (Y ≥ %.2f)" % [tag, ConiferKit.UNDER_MIN_NORMAL_Y])
			assert_eq(dark, 0, "%s: тон низа юбки не темнее тона тени таблицы" % tag)


## Арт-библия ред. 4, «Тон LOD2»: форма на меше другой модели (пихта и ветровал на LOD2 — меш ели)
## сохраняет свой тон цветом экземпляра (`ConiferKit.model_tint`): средний тон кроны × цвет
## экземпляра на LOD2 — оттенок в пределах 8° и V в пределах 0.04 от LOD1 (у пихты холодный тон
## не уходит к оттенку ели: галерея до правки — 157° → 132°). Замер галереи — в отчёте T-107.
func test_conifer_lod2_keeps_form_tone_rev4() -> void:
	for f in ConiferKit.FORM_KEYS.size():
		var tags: Array[Color] = []
		for lod in [1, 2]:
			var p := ConiferKit.Plant.new()
			p.form = f
			p.lod = lod
			var inst: Color = p.color(1.0)
			var tones: PackedColorArray = ConiferKit.tones_of(ConiferKit.model_of(f, lod))
			var mean := Color(0.0, 0.0, 0.0)
			for k in 3:
				mean += tones[k] / 3.0
			tags.append(Color(mean.r * inst.r, mean.g * inst.g, mean.b * inst.b))
		var dh: float = absf(tags[1].h - tags[0].h) * 360.0
		dh = minf(dh, 360.0 - dh)
		var key: String = ConiferKit.FORM_KEYS[f]
		assert_lte(dh, 8.0, "%s: оттенок LOD2 − LOD1 %.1f°" % [key, dh])
		assert_almost_eq(tags[1].v, tags[0].v, 0.04, "%s: V LOD2 − LOD1" % key)
	var fir := ConiferKit.Plant.new()
	fir.form = ConiferKit.FIR
	fir.lod = 2
	assert_gt(fir.color(1.0).b, fir.color(1.0).r * 1.2, "пихта на LOD2: холодный (голубой) сдвиг цвета экземпляра")
	assert_true(ConiferKit.model_tint(ConiferKit.SPRUCE, 2).is_equal_approx(Color.WHITE), "своя модель — без поправки")


## Acne (п.7, Forward+): крона не принимает тень (UV2.y = 1 → `toon.gdshader`), ствол ели —
## наполовину (`ConiferKit.TRUNK_SHADOW`: не чёрный под юбкой); форма экземпляра выбирается в шейдере (цвет и контур); у сухих веток ветровала нет
## контура; тень отбрасывает только LOD0.
func test_conifer_crowns_skip_shadow_receive_and_forms_select_in_shaders() -> void:
	var toon: String = FileAccess.get_file_as_string("res://src/scene3d/shaders/toon.gdshader")
	var outline: String = FileAccess.get_file_as_string("res://src/scene3d/shaders/outline.gdshader")
	var light: String = FileAccess.get_file_as_string("res://src/scene3d/shaders/toon_light.gdshaderinc")
	assert_string_contains(toon, "#define TOON_CROWN_MASK")
	assert_string_contains(toon, "v_receive = 1.0 - UV2.y")
	assert_string_contains(toon, "conifer_hidden(UV2, INSTANCE_CUSTOM)")
	assert_string_contains(outline, "conifer_hidden(UV2, INSTANCE_CUSTOM)")
	assert_string_contains(light, "receive *= v_receive")
	var g: ConiferKit.Geo = ConiferKit.geometry(ConiferKit.M_SPRUCE, 0)
	var crown: int = 0
	var trunk: int = 0
	for i in g.v.size():
		if g.f[i].y > 0.99:
			crown += 1
		elif g.v[i].y < 1.0 and is_equal_approx(g.f[i].y, ConiferKit.TRUNK_SHADOW):
			trunk += 1
	assert_gt(crown, 200, "вершины кроны помечены")
	assert_gt(trunk, 4, "ствол у земли принимает тень наполовину")
	assert_between(ConiferKit.TRUNK_SHADOW, 0.01, 0.99, "ствол ели принимает тень частично")
	var wind: ConiferKit.Geo = ConiferKit.geometry(ConiferKit.M_WIND, 0)
	var dry: int = 0
	for i in wind.v.size():
		if wind.c[i].a < 0.01:
			dry += 1
	assert_gt(dry, 0, "сухие ветки ветровала без контура")
	for id in IDS:
		for n in _conifer_nodes(_scene(id)):
			var want: int = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if String(n.name) == "Conifers" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			assert_eq(n.cast_shadow, want, "%s %s: тень" % [id, n.name])
