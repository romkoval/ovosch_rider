extends GutTest
## Независимые приёмочные тесты стилизованного мира заезда (тестировщик; T-058 `[visual]`,
## коммит 34adc61): REQ-D3D-07 крит. 1–5 `[авто]`.
##
## Отличия от тестов разработчика (test_ride_world, test_world_builders, test_mesh_kit):
## свои трассы (стадион с поворотами влево/вправо, прямая под углом к осям любой длины,
## короткая прямая 40 м, петля 1 м), проверки в мировых координатах (наклон — к центру
## поворота, колесо — точка контакта не проскальзывает, стопа — по мешу шатуна и в реальном
## цикле кадров движка), собственный подсчёт бюджета против docs/perf_budget.md, все точки
## меша велосипедиста в кадре, транзитивная статическая проверка per-frame кода по всем
## файлам src/scene3d/ и выключение каждой части мира в EnvironmentSet по отдельности.
##
## Известные дефекты: проверка выполняется полностью, при нарушении тест помечается pending
## с фактическими значениями (`_defect`), без нарушений — обычный зачёт. Pending снимется сам,
## когда дефект исправят.

const SCENE: String = "res://src/scene3d/ride_scene.tscn"
const DEFAULT_ENV: String = "res://src/scene3d/default_environment.tres"
const FRAME: float = 1.0 / 60.0
const G: float = 9.81


## Стадион: прямая `straight` вдоль +X, полуокружность радиуса `radius`, прямая обратно,
## полуокружность. mirror = false — оба поворота влево, true — вправо (зеркало по Z).
class StadiumTrack extends Track:
	var straight: float
	var radius: float
	var mirror: bool

	func _init(straight_m: float, radius_m: float, mirror_z: bool) -> void:
		straight = straight_m
		radius = radius_m
		mirror = mirror_z

	func length_m() -> float:
		return 2.0 * straight + TAU * radius

	func is_loop() -> bool:
		return true

	func sample_into(distance_m: float, out: TrackSample) -> void:
		var s: float = wrap_distance(distance_m)
		var arc: float = PI * radius
		var p := Vector3.ZERO
		var f := Vector3.ZERO
		if s < straight:
			p = Vector3(s, 0.0, 0.0)
			f = Vector3(1.0, 0.0, 0.0)
		elif s < straight + arc:
			var th: float = (s - straight) / radius
			p = Vector3(straight + radius * sin(th), 0.0, -radius + radius * cos(th))
			f = Vector3(cos(th), 0.0, -sin(th))
		elif s < 2.0 * straight + arc:
			var t: float = s - straight - arc
			p = Vector3(straight - t, 0.0, -2.0 * radius)
			f = Vector3(-1.0, 0.0, 0.0)
		else:
			var th2: float = (s - 2.0 * straight - arc) / radius
			p = Vector3(-radius * sin(th2), 0.0, -radius - radius * cos(th2))
			f = Vector3(-cos(th2), 0.0, sin(th2))
		if mirror:
			p.z = -p.z
			f.z = -f.z
		out.position = p
		out.forward = f
		out.up = Vector3.UP
		out.grade = 0.0

	## Середина первой дуги (дистанция) и её центр.
	func first_arc_mid() -> float:
		return straight + PI * radius * 0.5

	func first_arc_center() -> Vector3:
		return Vector3(straight, 0.0, radius if mirror else -radius)


## Прямая (не петля) под углом к осям сетки рельефа, любой длины — «маршрут GPX».
class LineTrack extends Track:
	var length: float
	var dir: Vector3

	func _init(length_m_: float, heading_rad: float = 0.6) -> void:
		length = length_m_
		dir = Vector3(sin(heading_rad), 0.0, cos(heading_rad)).normalized()

	func length_m() -> float:
		return length

	func is_loop() -> bool:
		return false

	func sample_into(distance_m: float, out: TrackSample) -> void:
		out.position = dir * wrap_distance(distance_m)
		out.forward = dir
		out.up = Vector3.UP
		out.grade = 0.0


## Петля длиной 1 м (граница).
class TinyLoopTrack extends Track:
	func length_m() -> float:
		return 1.0

	func is_loop() -> bool:
		return true

	func sample_into(distance_m: float, out: TrackSample) -> void:
		out.position = Vector3(wrap_distance(distance_m), 0.0, 0.0)
		out.forward = Vector3.RIGHT
		out.up = Vector3.UP
		out.grade = 0.0


# ---------------------------------------------------------------------------
# Помощники
# ---------------------------------------------------------------------------

func _env() -> EnvironmentSet:
	return (load(DEFAULT_ENV) as EnvironmentSet).duplicate() as EnvironmentSet


func _scene(track: Track = null, env: EnvironmentSet = null) -> RideScene:
	var s: RideScene = load(SCENE).instantiate()
	s.route_id = ""  # петля LoopTrack, как до T-070 (сцена по умолчанию — на трассе flat)
	if env != null:
		s.environment_set = env
	# Трасса до входа в дерево: мир строится один раз в _ready (без старых узлов в очереди
	# на удаление — подсчёт бюджета честный).
	if track != null:
		s.set_track(track)
	add_child_autofree(s)
	return s


func _scene_in_viewport(size: Vector2i, track: Track) -> RideScene:
	var vp := SubViewport.new()
	vp.size = size
	add_child_autofree(vp)
	var s: RideScene = load(SCENE).instantiate()
	s.route_id = ""  # петля LoopTrack, как до T-070 (сцена по умолчанию — на трассе flat)
	s.set_track(track)
	vp.add_child(s)
	return s


func _frames(s: RideScene, n: int) -> void:
	for i in n:
		s.advance(FRAME)


func _drive(s: RideScene, kmh: float, seconds: float) -> void:
	s.apply_telemetry(0, false, 90, true, kmh, true)
	_frames(s, int(seconds * 60.0))


## Нарушения известного дефекта → pending с фактами; без нарушений — зачёт.
func _defect(defect: String, violations: Array, ok_text: String) -> void:
	if violations.is_empty():
		assert_true(true, ok_text)
		return
	var shown: Array = violations.slice(0, 6)
	pending("ДЕФЕКТ %s; нарушений: %d; примеры: %s" % [defect, violations.size(), str(shown)])


func _doc_budget(keyword: String) -> int:
	var re := RegEx.create_from_string("\\|\\s*(\\d+)\\s*\\|")
	for line in FileAccess.get_file_as_string("res://docs/perf_budget.md").split("\n"):
		if line.contains(keyword):
			var m := re.search(line)
			if m != null:
				return int(m.get_string(1))
	return -1


## Собственный подсчёт бюджета: MeshInstance3D, уникальные материалы (материал меша,
## surface override, material_override, материалы мешей MultiMesh; next_pass не считается —
## так в docs/perf_budget.md), Light3D, экземпляры MultiMesh.
func _budget(root: Node) -> Dictionary:
	var mats: Dictionary = {}
	var out := {"meshes": 0, "lights": 0, "mm": 0}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Light3D:
			out["lights"] += 1
		if n is GeometryInstance3D and (n as GeometryInstance3D).material_override != null:
			mats[(n as GeometryInstance3D).material_override.get_instance_id()] = true
		if n is MeshInstance3D:
			out["meshes"] += 1
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				for i in mi.mesh.get_surface_count():
					var m: Material = mi.get_surface_override_material(i)
					if m == null:
						m = mi.mesh.surface_get_material(i)
					if m != null:
						mats[m.get_instance_id()] = true
		elif n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm != null:
				out["mm"] += mm.instance_count
				if mm.mesh != null:
					for i in mm.mesh.get_surface_count():
						var m2: Material = mm.mesh.surface_get_material(i)
						if m2 != null:
							mats[m2.get_instance_id()] = true
	out["materials"] = mats.size()
	return out


func _assert_budget(s: RideScene, label: String) -> void:
	var b := _budget(s)
	assert_lte(int(b["meshes"]), _doc_budget("MeshInstance3D"), "%s: MeshInstance3D %d" % [label, int(b["meshes"])])
	assert_lte(int(b["materials"]), _doc_budget("материалов"), "%s: материалов %d" % [label, int(b["materials"])])
	assert_lte(int(b["lights"]), _doc_budget("Light3D"), "%s: Light3D %d" % [label, int(b["lights"])])
	assert_lte(int(b["mm"]), _doc_budget("MultiMesh"), "%s: экземпляров MultiMesh %d" % [label, int(b["mm"])])


func _env_root(s: RideScene) -> Node3D:
	return s.get_node("%EnvironmentRoot") as Node3D


func _shader_path(m: Material) -> String:
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		return (m as ShaderMaterial).shader.resource_path
	return ""


func _surface_material(g: GeometryInstance3D) -> Material:
	if g.material_override != null:
		return g.material_override
	if g is MeshInstance3D:
		var mi := g as MeshInstance3D
		return mi.get_active_material(0) if mi.mesh != null and mi.mesh.get_surface_count() > 0 else null
	if g is MultiMeshInstance3D:
		var mm := (g as MultiMeshInstance3D).multimesh
		return mm.mesh.surface_get_material(0) if mm != null and mm.mesh != null else null
	return null


## Растительность: MultiMesh с экземплярами в мире, кроме столбиков; ключ — меш (тип).
func _vegetation_types(s: RideScene) -> Dictionary:
	var types: Dictionary = {}
	for c in _env_root(s).get_children():
		if c is MultiMeshInstance3D and c != s.props():
			var mm := (c as MultiMeshInstance3D).multimesh
			if mm != null and mm.mesh != null and mm.instance_count > 0:
				types[mm.mesh.get_instance_id()] = mm.instance_count
	return types


func _meshes_with_shader(s: RideScene, needle: String) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in _env_root(s).get_children():
		if c is MeshInstance3D and _shader_path(_surface_material(c as MeshInstance3D)).contains(needle):
			out.append(c as MeshInstance3D)
	return out


## Сетка точек оси дороги (ось трассы + смещение) для поиска ближайшей точки.
func _road_axis_grid(track: Track, env: EnvironmentSet, step: float) -> Dictionary:
	var grid: Dictionary = {}
	var sample := TrackSample.new()
	var n: int = int(ceil(track.length_m() / step))
	for i in n + 1:
		track.sample_into(minf(float(i) * step, track.length_m()), sample)
		var p: Vector3 = sample.position + sample.right() * env.road_center_offset_m
		var key := Vector2i(int(floor(p.x / 10.0)), int(floor(p.z / 10.0)))
		if not grid.has(key):
			grid[key] = PackedVector3Array()
		var arr: PackedVector3Array = grid[key]
		arr.append(p)
		grid[key] = arr
	return grid


## Горизонтальное расстояние до ближайшей точки оси дороги (не меньше истинного).
func _dist_to_axis(grid: Dictionary, p: Vector3) -> float:
	var best: float = INF
	var kx: int = int(floor(p.x / 10.0))
	var kz: int = int(floor(p.z / 10.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := Vector2i(kx + dx, kz + dz)
			if grid.has(key):
				for q in (grid[key] as PackedVector3Array):
					best = minf(best, Vector2(p.x - q.x, p.z - q.z).length())
	return best


## Точки мешей велосипедиста на высоте 0.1–1.45 м над дорогой (в мировых координатах).
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
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var w: Vector3 = xf * v
				var h: float = (inv * w).y
				if h >= 0.1 and h <= 1.45:
					out.append(w)
	return out


## Точки велосипедиста вне кадра (по плоскостям фрустума камеры).
func _points_outside_frame(s: RideScene, pts: PackedVector3Array) -> int:
	var planes: Array[Plane] = s.camera().get_frustum()
	var outside: int = 0
	for p in pts:
		for pl in planes:
			if pl.is_point_over(p):
				outside += 1
				break
	return outside


func _horizontal_cam_distance(s: RideScene) -> float:
	var off: Vector3 = s.camera_offset()
	return Vector2(off.x, off.z).length()


## Наклон корпуса (узел Lean) к центру поворота, рад (> 0 — внутрь).
func _tilt_toward(s: RideScene, center: Vector3) -> float:
	var lean: Node3D = s.rider().get_node("%Lean")
	var up: Vector3 = lean.global_transform.basis.y.normalized()
	var to_c: Vector3 = center - s.rider_position()
	to_c.y = 0.0
	to_c = to_c.normalized()
	return atan2(up.dot(to_c), up.y)


## Абсолютный наклон корпуса от вертикали дороги, рад.
func _tilt_abs(s: RideScene) -> float:
	var lean: Node3D = s.rider().get_node("%Lean")
	var up: Vector3 = lean.global_transform.basis.y.normalized()
	return acos(clampf(up.dot(Vector3.UP), -1.0, 1.0))


## Ошибка «стопа на педали», м: голеностоп минус смещение стопы против оси педали по мешу
## шатуна (правая педаль — локальный −X шатуна, +Y; левая — +X, −Y). Плюс признак, что
## точка стопы лежит на площадке педали (бокс меша шатуна).
func _foot_errors(rider: Rider) -> Dictionary:
	var arm: Node3D = rider.get_node("%CrankArm")
	var l: float = RiderModel.CRANK_LENGTH_M
	var px: float = RiderModel.PEDAL_X_M
	# Точка стопы — шип (сокет `cleat` скелета гонщика, T-106a2).
	var foot_r: Vector3 = rider.bone_global("cleat.R").origin
	var foot_l: Vector3 = rider.bone_global("cleat.L").origin
	var pedal_r: Vector3 = arm.global_transform * Vector3(-px, l, 0.0)
	var pedal_l: Vector3 = arm.global_transform * Vector3(px, -l, 0.0)
	var arm_inv: Transform3D = arm.global_transform.affine_inverse()
	var lr: Vector3 = arm_inv * foot_r
	var ll: Vector3 = arm_inv * foot_l
	# Площадка педали в мешe шатуна: центр (∓(PEDAL_X + 0.01), ±l, 0), размер 0.07 × 0.018 × 0.08.
	var on_r: bool = absf(lr.x - (-px - 0.01)) <= 0.035 + 1e-3 and absf(lr.z) <= 0.04 + 1e-3 and absf(lr.y - l) <= 0.02
	var on_l: bool = absf(ll.x - (px + 0.01)) <= 0.035 + 1e-3 and absf(ll.z) <= 0.04 + 1e-3 and absf(ll.y + l) <= 0.02
	return {"r": foot_r.distance_to(pedal_r), "l": foot_l.distance_to(pedal_l), "on_r": on_r, "on_l": on_l}


func _strip_comment(raw: String) -> String:
	var in_str: bool = false
	var quote: String = ""
	for i in raw.length():
		var ch: String = raw[i]
		if in_str:
			if ch == "\\":
				continue
			if ch == quote:
				in_str = false
		elif ch == "\"" or ch == "'":
			in_str = true
			quote = ch
		elif ch == "#":
			return raw.substr(0, i)
	return raw


# ===========================================================================
# Крит. 1 — мир по трассе, бюджет, выключение частей мира
# ===========================================================================

func test_req_d3d_07_c1_default_loop_world_has_marked_road_curb_verge_terrain_vegetation_and_posts() -> void:
	var s := _scene()
	# Дорога: шейдер с разметкой по UV, не сплошной цвет.
	var road_mat: Material = s.road().get_active_material(0)
	assert_true(road_mat is ShaderMaterial, "асфальт — ShaderMaterial")
	var road_shader: Shader = (road_mat as ShaderMaterial).shader
	assert_eq(road_shader.get_mode(), Shader.MODE_SPATIAL)
	assert_true(road_shader.code.contains("UV"), "цвет асфальта зависит от UV (разметка)")
	var color_uniforms: int = 0
	for u in road_shader.get_shader_uniform_list():
		if int(u["type"]) == TYPE_COLOR:
			color_uniforms += 1
	assert_gte(color_uniforms, 2, "асфальт и разметка — разные цвета (uniform-цвета: %d)" % color_uniforms)
	var uvs: PackedVector2Array = s.road().mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var umin: float = INF
	var umax: float = -INF
	for uv in uvs:
		umin = minf(umin, uv.x)
		umax = maxf(umax, uv.x)
	assert_almost_eq(umin, 0.0, 1e-4, "UV поперёк дороги от 0")
	assert_almost_eq(umax, 1.0, 1e-4, "UV поперёк дороги до 1")
	# Обочина (материал мира), полоса травы и рельеф (шейдер травы).
	assert_eq(_meshes_with_shader(s, "grass").size(), 2, "полоса травы и рельеф — шейдер травы")
	assert_not_null(s.terrain(), "рельеф построен")
	# Растительность ≥ 3 типов (разные меши) и сигнальные столбики.
	var types := _vegetation_types(s)
	assert_gte(types.size(), 3, "типов растительности: %d" % types.size())
	assert_not_null(s.props(), "столбики есть")
	assert_gt(s.props().multimesh.instance_count, 0)
	assert_false(types.has(s.props().multimesh.mesh.get_instance_id()), "столбик — отдельный тип объекта")
	_assert_budget(s, "петля по умолчанию")


func test_req_d3d_07_c1_curb_and_grass_strip_cross_section_on_straight_both_sides() -> void:
	var env := _env()
	var track := StadiumTrack.new(300.0, 60.0, false)
	var s := _scene(track, env)
	var sample := track.sample(150.0)
	var axis: Vector3 = sample.position + sample.right() * env.road_center_offset_m
	var half: float = env.road_width_m * 0.5
	var roadside: MeshInstance3D = null
	for c in _env_root(s).get_children():
		if c is MeshInstance3D and c != s.road() and _shader_path(_surface_material(c as MeshInstance3D)).contains("toon"):
			roadside = c as MeshInstance3D
	assert_not_null(roadside, "обочина (материал мира) построена")
	# Полоса травы — меньший из двух мешей с шейдером травы (второй — рельеф до горизонта).
	var verge: MeshInstance3D = null
	for m in _meshes_with_shader(s, "grass"):
		if verge == null or m.get_aabb().size.length() < verge.get_aabb().size.length():
			verge = m
	if roadside == null:
		return
	for sgn in [-1.0, 1.0]:
		var kerb_top: float = -INF
		for v in (roadside.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var d: Vector3 = roadside.global_transform * v - axis
			if absf(d.dot(sample.forward)) > 3.0:
				continue
			var lateral: float = d.dot(sample.right()) * sgn
			if lateral >= half + 0.3 and lateral <= half + 0.6:
				kerb_top = maxf(kerb_top, d.y)
		assert_between(kerb_top, 0.1, 0.2, "бордюр выше полотна на 0.1–0.2 м (сторона %+d): %.3f" % [int(sgn), kerb_top])
	assert_not_null(verge, "полоса травы построена")
	if verge != null:
		var widest: float = 0.0
		for v in (verge.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var d2: Vector3 = verge.global_transform * v - axis
			if absf(d2.dot(sample.forward)) <= 3.0:
				widest = maxf(widest, absf(d2.dot(sample.right())))
		assert_gte(widest, half + 8.0, "полоса травы уходит от кромки ≥ 8 м: %.1f м" % widest)


func test_req_d3d_07_c1_terrain_reaches_horizon_with_hills_at_edge_and_lies_below_road() -> void:
	var env := _env()
	var s := _scene(null, env)
	var track: Track = s.track
	var terrain: MeshInstance3D = null
	for m in _meshes_with_shader(s, "grass"):
		if terrain == null or m.get_aabb().size.length() > terrain.get_aabb().size.length():
			terrain = m
	assert_not_null(terrain)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var road_y: float = 0.0
	var n: int = 0
	var sample := TrackSample.new()
	var steps: int = int(track.length_m() / 5.0)
	for i in steps:
		track.sample_into(float(i) * 5.0, sample)
		lo = Vector2(minf(lo.x, sample.position.x), minf(lo.y, sample.position.z))
		hi = Vector2(maxf(hi.x, sample.position.x), maxf(hi.y, sample.position.z))
		road_y += sample.position.y
		n += 1
	road_y /= float(n)
	var box: AABB = terrain.global_transform * terrain.get_aabb()
	var margin: float = minf(minf(lo.x - box.position.x, box.end.x - hi.x), minf(lo.y - box.position.z, box.end.z - hi.y))
	assert_gte(margin, 500.0, "рельеф выходит за габарит трассы на ≥ 500 м: %.0f м" % margin)
	# Холмы на краю: минимум высоты во внешнем кольце 100 м — выше дороги на ≥ 25 % hills_height_m.
	var ring_min: float = INF
	for v in (terrain.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		var w: Vector3 = terrain.global_transform * v
		var edge: float = minf(minf(w.x - box.position.x, box.end.x - w.x), minf(w.z - box.position.z, box.end.z - w.z))
		if edge <= 100.0:
			ring_min = minf(ring_min, w.y)
	assert_gte(ring_min - road_y, env.hills_height_m * 0.25, "холмы на краю: минимум %.1f м над дорогой" % (ring_min - road_y))
	# У дороги рельеф ниже полотна (не закрывает асфальт и обочину).
	var above: Array[String] = _terrain_above_road(s, env, 5.0)
	assert_eq(above, [] as Array[String], "рельеф не выше полотна у дороги: %s" % str(above.slice(0, 5)))


## Точки дороги (ось, кромки, бордюр), где рельеф выше полотна.
func _terrain_above_road(s: RideScene, env: EnvironmentSet, step: float) -> Array[String]:
	var out: Array[String] = []
	var field: TerrainField = s.terrain()
	if field == null:
		return out
	var sample := TrackSample.new()
	var curb_out: float = RoadsideBuilder.curb_outer_m(env.road_width_m)
	var n: int = int(s.track.length_m() / step)
	for i in n:
		s.track.sample_into(float(i) * step, sample)
		var axis: Vector3 = sample.position + sample.right() * env.road_center_offset_m
		for off in [-curb_out, -env.road_width_m * 0.5, 0.0, env.road_width_m * 0.5, curb_out]:
			var p: Vector3 = axis + sample.right() * float(off)
			var h: float = field.height_at(p.x, p.z)
			if h > sample.position.y - 0.02:
				out.append("s=%.0f off=%+.1f: рельеф %+.2f м" % [float(i) * step, float(off), h - sample.position.y])
	return out


func test_req_d3d_07_c1_budget_counted_independently_on_several_tracks() -> void:
	assert_gt(_doc_budget("MeshInstance3D"), 0, "бюджет читается из docs/perf_budget.md")
	assert_gt(_doc_budget("материалов"), 0)
	assert_gt(_doc_budget("Light3D"), 0)
	assert_gt(_doc_budget("MultiMesh"), 0)
	var s := _scene()
	_assert_budget(s, "петля")
	var b := _budget(s)
	assert_eq(int(b["lights"]), 1, "источник света один (солнце)")
	s.set_track(StadiumTrack.new(400.0, 50.0, true))
	await wait_process_frames(2)
	_assert_budget(s, "стадион после пересборки")
	s.set_track(LineTrack.new(8000.0))
	await wait_process_frames(2)
	_assert_budget(s, "прямая 8 км")


func test_req_d3d_07_c1_rebuilding_world_does_not_accumulate_nodes() -> void:
	var s := _scene()
	var base: int = _env_root(s).get_child_count()
	for i in 3:
		s.set_track(StadiumTrack.new(200.0 + 50.0 * i, 40.0, i % 2 == 0))
	s.set_track(LoopTrack.new(7))
	await wait_process_frames(3)
	assert_eq(_env_root(s).get_child_count(), base, "после 4 пересборок узлов мира столько же, сколько было")
	for n in s.world_nodes():
		assert_true(is_instance_valid(n) and n.is_inside_tree(), "узел мира жив и в дереве")


func test_req_d3d_07_c1_short_40m_track_builds_world_with_three_vegetation_types_and_posts() -> void:
	var s := _scene(LineTrack.new(40.0))
	assert_not_null(s.road())
	assert_not_null(s.terrain())
	assert_gte(_vegetation_types(s).size(), 3, "типов растительности: %d" % _vegetation_types(s).size())
	assert_not_null(s.props(), "столбики на трассе 40 м")
	if s.props() != null:
		assert_gt(s.props().multimesh.instance_count, 0)
	_assert_budget(s, "прямая 40 м")
	_drive(s, 30.0, 6.0)
	assert_true(s.rider_position().is_finite(), "велосипедист стоит в конце короткой трассы без ошибок")


func test_req_d3d_07_c1_one_metre_loop_builds_world_without_errors() -> void:
	var s := _scene(TinyLoopTrack.new())
	assert_not_null(s.road())
	_assert_budget(s, "петля 1 м")
	_drive(s, 40.0, 2.0)
	assert_between(s.distance_m, 0.0, 1.0, "дистанция оборачивается на петле 1 м")
	assert_almost_eq(_horizontal_cam_distance(s), RideScene.CAMERA_BACK_M, 0.05)


func test_req_d3d_07_c1_long_60km_route_keeps_budget_vegetation_and_posts() -> void:
	var s := _scene(LineTrack.new(60000.0))
	_assert_budget(s, "маршрут 60 км")
	var violations: Array = []
	var types := _vegetation_types(s)
	if types.size() < 3:
		violations.append("типов растительности %d (< 3), экземпляров столбиков %d из бюджета %d" % [
			types.size(), s.props().multimesh.instance_count if s.props() != null else 0, PerfBudget.MAX_MULTIMESH_INSTANCES])
	if s.props() == null or s.props().multimesh.instance_count == 0:
		violations.append("нет столбиков")
	_defect("D3D-07-A: на длинной трассе (≥ 25 км) столбики (длина/25·2) съедают весь бюджет MultiMesh 2000 — растительности не остаётся (RideScene._props_count/_build_world)",
		violations, "на маршруте 60 км ≥ 3 типов растительности и столбики")


func test_req_d3d_07_c1_long_route_terrain_does_not_cover_road() -> void:
	var above: Array[String] = []
	for length in [12000.0, 60000.0]:
		var env := _env()
		var s := _scene(LineTrack.new(length), env)
		for v in _terrain_above_road(s, env, 50.0):
			above.append("%.0f км, ячейка %.0f м: %s" % [length / 1000.0, s.terrain().cell_m, v])
	_defect("D3D-07-B: на трассе ≳ 10 км ячейка рельефа (габарит/150: 75 м при 12 км, 409 м при 60 км) больше FLAT_RADIUS/NEAR_RADIUS — увалы поднимаются выше полотна и закрывают дорогу (TerrainField)",
		above, "рельеф ниже полотна на маршрутах 12 и 60 км")


func test_req_d3d_07_c1_disabling_each_world_part_in_environment_set_keeps_scene_working() -> void:
	var base_env := _env()
	var reference := _scene(StadiumTrack.new(250.0, 60.0, false), _env())
	var ref_meshes: int = 0
	for c in _env_root(reference).get_children():
		if c is MeshInstance3D:
			ref_meshes += 1
	var ref_roadside_verts: int = 0
	for c in _env_root(reference).get_children():
		if c is MeshInstance3D and c.name == "Roadside":
			ref_roadside_verts = (c as MeshInstance3D).mesh.surface_get_array_len(0)
	var variants: Dictionary = {
		"terrain_off": {"terrain_enabled": false},
		"roadside_off": {"roadside_enabled": false},
		"guardrail_off": {"guardrail_enabled": false},
		"vegetation_zero": {"tree_count": 0, "bush_count": 0, "tuft_count": 0},
		"vegetation_negative": {"tree_count": -5, "bush_count": -1, "tuft_count": -100},
		"posts_off": {"prop_spacing_m": 0.0},
		"flat_world": {"hills_height_m": 0.0, "rolling_height_m": 0.0},
		"all_off": {"terrain_enabled": false, "roadside_enabled": false, "guardrail_enabled": false,
			"tree_count": 0, "bush_count": 0, "tuft_count": 0, "prop_spacing_m": 0.0},
	}
	for key in variants:
		var env := base_env.duplicate() as EnvironmentSet
		var props: Dictionary = variants[key]
		for p in props:
			env.set(p, props[p])
		var track := StadiumTrack.new(250.0, 60.0, false)
		var s := _scene(track, env)
		assert_not_null(s.road(), "%s: дорога есть" % key)
		_drive(s, 30.0, 2.0)
		assert_lt(s.rider_position().distance_to(track.sample(s.distance_m).position), 1e-3, "%s: велосипедист на трассе" % key)
		assert_almost_eq(_horizontal_cam_distance(s), RideScene.CAMERA_BACK_M, 0.05, "%s: камера следует" % key)
		_assert_budget(s, key)
		var meshes: int = 0
		for c in _env_root(s).get_children():
			if c is MeshInstance3D:
				meshes += 1
		match key:
			"terrain_off":
				assert_null(s.terrain(), "%s: рельефа нет" % key)
				assert_eq(meshes, ref_meshes - 1, "%s: на один меш меньше" % key)
			"roadside_off":
				assert_eq(meshes, ref_meshes - 2, "%s: нет обочины и полосы травы" % key)
			"guardrail_off":
				for c in _env_root(s).get_children():
					if c is MeshInstance3D and c.name == "Roadside":
						assert_lt((c as MeshInstance3D).mesh.surface_get_array_len(0), ref_roadside_verts, "%s: без отбойника меньше вершин" % key)
			"vegetation_zero", "vegetation_negative":
				assert_eq(_vegetation_types(s).size(), 0, "%s: растительности нет" % key)
			"posts_off":
				assert_null(s.props(), "%s: столбиков нет" % key)
			"all_off":
				assert_null(s.terrain())
				assert_null(s.props())
				assert_eq(_vegetation_types(s).size(), 0)
				assert_eq(meshes, 1, "%s: осталась только дорога" % key)
		# Пересборка на другой трассе с тем же набором — без ошибок.
		s.set_track(LineTrack.new(500.0))
		_drive(s, 30.0, 1.0)
		assert_not_null(s.road(), "%s: пересборка на прямой" % key)


func test_req_d3d_07_c1_vegetation_and_posts_not_on_asphalt_with_and_without_terrain() -> void:
	for terrain_on in [true, false]:
		var env := _env()
		env.terrain_enabled = terrain_on
		var s := _scene(null, env)
		var grid := _road_axis_grid(s.track, env, 1.0)
		var half: float = env.road_width_m * 0.5
		var on_road: Array[String] = []
		var nodes: Array = []
		for c in _env_root(s).get_children():
			if c is MultiMeshInstance3D:
				nodes.append(c)
		for node in nodes:
			var mm := (node as MultiMeshInstance3D).multimesh
			for i in mm.instance_count:
				var p: Vector3 = mm.get_instance_transform(i).origin
				var d: float = _dist_to_axis(grid, p)
				if d < half:
					on_road.append("%s#%d d=%.2f" % [(node as Node).name, i, d])
		assert_eq(on_road, [] as Array[String], "рельеф %s: объекты на асфальте: %s" % [str(terrain_on), str(on_road.slice(0, 5))])


func test_req_d3d_07_c1_per_frame_code_has_no_allocations_transitively_across_scene3d() -> void:
	var func_re := RegEx.create_from_string("^(static\\s+)?func\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\(")
	var call_re := RegEx.create_from_string("\\b([A-Za-z_][A-Za-z0-9_]*)\\s*\\(")
	var alloc_res: Array[RegEx] = []
	for pattern in [
		"\\.new\\(", "\\binstantiate\\(", "\\bduplicate\\(", "\\b(load|preload)\\(",
		"\\b(str|Array|Dictionary|String|StringName|NodePath|Callable)\\(", "\\bPacked[A-Za-z0-9]*Array\\(",
		"(?<![A-Za-z0-9_\\]\\)])\\[", "\\{", "\"[^\"]*\"\\s*%", "\"\\s*\\+|\\+\\s*\"", "\\bfunc\\s*\\(",
		"\\.(append|append_array|push_back|push_front|resize|insert)\\(",
		"\\b(get_children|find_children|get_nodes_in_group)\\(",
	]:
		alloc_res.append(RegEx.create_from_string(pattern))
	# имя функции → [{file, lines: [{n, text}]}] по всем файлам src/scene3d/
	var defs: Dictionary = {}
	var dir := DirAccess.open("res://src/scene3d")
	var files: int = 0
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		files += 1
		var path: String = "res://src/scene3d/" + f
		var cur: Dictionary = {}
		var ln: int = 0
		for raw in FileAccess.get_file_as_string(path).split("\n"):
			ln += 1
			var line: String = _strip_comment(raw)
			var m := func_re.search(line)
			if m != null:
				cur = {"file": path, "lines": []}
				var fname: String = m.get_string(2)
				if not defs.has(fname):
					defs[fname] = []
				(defs[fname] as Array).append(cur)
				continue
			if line.strip_edges().is_empty():
				continue
			if not line.begins_with("\t") and not line.begins_with(" "):
				cur = {}
				continue
			if not cur.is_empty():
				(cur["lines"] as Array).append({"n": ln, "text": line})
	assert_gt(files, 10, "разобраны файлы src/scene3d/")
	assert_true(defs.has("_process"), "per-frame методы найдены")
	var queue: Array[String] = ["_process", "_physics_process"]
	var visited: Dictionary = {}
	while not queue.is_empty():
		var fn: String = queue.pop_back()
		if visited.has(fn) or not defs.has(fn):
			continue
		visited[fn] = true
		for d in defs[fn]:
			for entry in (d["lines"] as Array):
				for cm in call_re.search_all(str(entry["text"])):
					var callee: String = cm.get_string(1)
					if defs.has(callee) and not visited.has(callee):
						queue.append(callee)
	for must in ["advance", "_pose_body", "_solve_leg", "_solve_arm", "two_bone_joint", "two_bone_joint_x", "bone_basis",
			"_step_tail", "_pose_tail", "smooth_effort", "_lean_target", "set_lean", "sample_into"]:
		assert_true(visited.has(must), "граф вызовов кадра включает %s" % must)
	var offenders: Array[String] = []
	for fn in visited:
		for d in defs[fn]:
			for entry in (d["lines"] as Array):
				var text: String = str(entry["text"])
				for re in alloc_res:
					if re.search(text) != null:
						offenders.append("%s:%d (%s) %s" % [str(d["file"]).get_file(), int(entry["n"]), fn, text.strip_edges()])
						break
	assert_eq(offenders, [] as Array[String], "аллокации в коде кадра (%d функций: %s): %s" % [visited.size(), str(visited.keys()), str(offenders)])


func test_req_d3d_07_c1_objects_and_nodes_do_not_grow_while_leaning_and_pedaling() -> void:
	var track := StadiumTrack.new(150.0, 30.0, false)
	var s := _scene(track)
	s.apply_telemetry(0, false, 95, true, 40.0, true)
	_frames(s, 120)
	var nodes_before: int = s.get_child_count() + _env_root(s).get_child_count() + s.rider().get_child_count()
	var objects_before: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	var max_lean: float = 0.0
	for i in 1200:
		s.advance(FRAME)
		max_lean = maxf(max_lean, absf(s.lean_rad()))
	assert_gt(max_lean, 0.1, "наклон и IK работали в кадре (наклон до %.2f рад)" % max_lean)
	var nodes_after: int = s.get_child_count() + _env_root(s).get_child_count() + s.rider().get_child_count()
	assert_eq(nodes_after, nodes_before, "узлы не создаются в кадре")
	var objects_after: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	assert_lte(objects_after - objects_before, 0.0, "Object-ы не создаются за 1200 кадров (Δ = %.0f)" % (objects_after - objects_before))


# ===========================================================================
# Крит. 2 — велосипедист: стопа на педали, длины звеньев, педаль вперёд, колёса вперёд
# ===========================================================================

func test_req_d3d_07_c2_foot_on_pedal_and_constant_bone_lengths_for_any_crank_angle_and_lean() -> void:
	var track := StadiumTrack.new(200.0, 40.0, false)
	var s := _scene(track)
	var rider := s.rider()
	var crank: Node3D = rider.get_node("%Crank")
	var sides: Array[String] = [".R", ".L"]
	var worst_foot: float = 0.0
	var worst_len: float = 0.0
	var off_platform: Array[String] = []
	var checked: int = 0
	for lean in [0.0, 0.3, -0.45]:
		rider.set_lean(lean)
		var phi: float = -TAU
		while phi <= 2.0 * TAU:
			crank.rotation = Vector3(phi, 0.0, 0.0)
			rider.advance(1e-4)
			var e := _foot_errors(rider)
			worst_foot = maxf(worst_foot, maxf(float(e["r"]), float(e["l"])))
			if not bool(e["on_r"]) or not bool(e["on_l"]):
				off_platform.append("φ=%.2f lean=%.2f" % [phi, lean])
			for k in 2:
				# Кости скелета гонщика (T-106a2): бедро — `thigh`, голень — `shin`, голеностоп — `foot`.
				var thigh: Transform3D = rider.bone_global("thigh" + sides[k])
				var shin: Transform3D = rider.bone_global("shin" + sides[k])
				var hip: Vector3 = thigh.origin
				var knee: Vector3 = shin.origin
				var ankle: Vector3 = rider.bone_global("foot" + sides[k]).origin
				worst_len = maxf(worst_len, absf(hip.distance_to(knee) - RiderModel.THIGH_M))
				worst_len = maxf(worst_len, absf(knee.distance_to(ankle) - RiderModel.SHIN_M))
				# Кость бедра (вдоль локальной +Y) заканчивается в колене, голени — в голеностопе; без растяжения.
				worst_len = maxf(worst_len, (thigh.origin + thigh.basis.y.normalized() * RiderModel.THIGH_M).distance_to(knee))
				worst_len = maxf(worst_len, (shin.origin + shin.basis.y.normalized() * RiderModel.SHIN_M).distance_to(ankle))
				worst_len = maxf(worst_len, absf(thigh.basis.get_scale().length() - sqrt(3.0)))
			checked += 1
			phi += 0.05
	assert_gt(checked, 1000, "проверено углов шатуна × наклонов: %d" % checked)
	assert_lte(worst_foot, 0.01, "стопа на педали (±1 см): худшее %.4f м" % worst_foot)
	assert_lte(worst_len, 0.001, "бедро и голень постоянны (±1 мм): худшее %.5f м" % worst_len)
	assert_eq(off_platform, [] as Array[String], "точка стопы на площадке педали: %s" % str(off_platform.slice(0, 5)))


func test_req_d3d_07_c2_feet_stay_on_pedals_in_real_engine_frame_loop_at_90_rpm() -> void:
	var s := _scene(LineTrack.new(5000.0))
	var old_fps: int = Engine.max_fps
	Engine.max_fps = 60
	# Контроль: без педалирования стопа на педали и в реальном цикле кадров.
	s.apply_telemetry(0, false, 0, true, 0.0, true)
	var control: float = 0.0
	for i in 10:
		await get_tree().process_frame
		var e0 := _foot_errors(s.rider())
		control = maxf(control, maxf(float(e0["r"]), float(e0["l"])))
	s.apply_telemetry(0, false, 90, true, 30.0, true)
	var worst: float = 0.0
	var dt_sum: float = 0.0
	var n: int = 0
	for i in 150:
		await get_tree().process_frame
		if i < 90:
			continue
		var e := _foot_errors(s.rider())
		worst = maxf(worst, maxf(float(e["r"]), float(e["l"])))
		dt_sum += get_process_delta_time()
		n += 1
	Engine.max_fps = old_fps
	assert_lte(control, 0.001, "контроль без педалирования: %.4f м" % control)
	assert_true(s.rider().is_pedaling(), "педалирование идёт")
	var violations: Array = []
	if worst > 0.01:
		violations.append("худшее расстояние стопа–педаль %.3f м при кадре %.1f мс, %.2f об/с" % [
			worst, dt_sum / maxf(float(n), 1.0) * 1000.0, s.rider().speed_scale])
	_defect("D3D-07-C: в реальном цикле кадров ноги ставятся по углу шатуна прошлого кадра — RideScene._process (Rider.advance/_pose_body) идёт раньше AnimationPlayer (потомок), стопа отстаёт от педали на ω·Δt",
		violations, "стопа на педали в реальном цикле кадров")


func test_req_d3d_07_c2_top_pedal_moves_forward_for_positive_crank_angle_and_cadence_turns_crank_positive() -> void:
	var track := LineTrack.new(1000.0, -1.1)
	var s := _scene(track)
	_drive(s, 20.0, 0.5)
	var rider := s.rider()
	var crank: Node3D = rider.get_node("%Crank")
	var arm: Node3D = rider.get_node("%CrankArm")
	var fwd: Vector3 = track.sample(s.distance_m).forward
	var l: float = RiderModel.CRANK_LENGTH_M
	var px: float = RiderModel.PEDAL_X_M
	for phi0 in [0.0, PI, TAU]:
		crank.rotation = Vector3(phi0, 0.0, 0.0)
		var a: Vector3 = arm.global_transform * Vector3(-px, l, 0.0)
		var b: Vector3 = arm.global_transform * Vector3(px, -l, 0.0)
		var top_local: Vector3 = Vector3(-px, l, 0.0) if a.y > b.y else Vector3(px, -l, 0.0)
		var top0: Vector3 = arm.global_transform * top_local
		crank.rotation = Vector3(phi0 + 0.2, 0.0, 0.0)
		var top1: Vector3 = arm.global_transform * top_local
		assert_gt((top1 - top0).dot(fwd), 0.02, "φ0=%.2f: верхняя педаль уходит вперёд по ходу на %.3f м" % [phi0, (top1 - top0).dot(fwd)])
	# Педалирование крутит шатун в положительную сторону.
	crank.rotation = Vector3.ZERO
	s.apply_telemetry(0, false, 90, true, 30.0, true)
	_frames(s, 120)
	var player: AnimationPlayer = rider.get_node("%PedalPlayer")
	var before: float = rider.crank_rotation_rad()
	player.advance(0.05)
	var after: float = rider.crank_rotation_rad()
	var d: float = wrapf(after - before, -PI, PI)
	assert_gt(d, 0.0, "при каденсе угол шатуна растёт (Δ = %.3f рад за 0.05 с)" % d)


func test_req_d3d_07_c2_wheels_roll_forward_without_slip_on_any_speed() -> void:
	var track := LineTrack.new(5000.0, 2.3)
	var s := _scene(track)
	var wheels: Array[MeshInstance3D] = [s.rider().get_node("%FrontWheel") as MeshInstance3D, s.rider().get_node("%RearWheel") as MeshInstance3D]
	for kmh in [8.0, 36.0, 60.0]:
		_drive(s, kmh, 0.5)
		# Короткий шаг: поворот обода за шаг мал, хорда ≈ дуге (иначе при 0.5 рад/кадр
		# конечный поворот сам даёт смещение точки контакта второго порядка).
		var h: float = 0.001
		var v_dt: float = kmh / 3.6 * h
		var fwd: Vector3 = track.sample(s.distance_m).forward
		for w in wheels:
			var r: float = w.get_aabb().size.y * 0.5
			# Материальные точки обода: в локальных координатах колеса они неподвижны.
			var inv0: Transform3D = w.global_transform.affine_inverse()
			var bottom_mat: Vector3 = inv0 * (w.global_transform.origin + Vector3.DOWN * r)
			var top_mat: Vector3 = inv0 * (w.global_transform.origin + Vector3.UP * r)
			var b0: Vector3 = w.global_transform * bottom_mat
			var t0: Vector3 = w.global_transform * top_mat
			s.advance(h)
			var b1: Vector3 = w.global_transform * bottom_mat
			var t1: Vector3 = w.global_transform * top_mat
			assert_lt((b1 - b0).length(), 0.15 * v_dt, "%s %.0f км/ч: точка контакта не скользит (%.4f м при v·dt %.4f)" % [w.name, kmh, (b1 - b0).length(), v_dt])
			assert_almost_eq((t1 - t0).dot(fwd), 2.0 * v_dt, 0.15 * v_dt, "%s %.0f км/ч: верх обода идёт вперёд вдвое быстрее" % [w.name, kmh])


# ===========================================================================
# Крит. 3 — наклон в повороте
# ===========================================================================

func test_req_d3d_07_c3_leans_into_left_and_right_turns_at_least_physical_angle_and_capped() -> void:
	var cases: Array = [[20.0, 80.0], [32.0, 40.0], [45.0, 150.0], [32.0, 30.0], [32.0, 25.0], [60.0, 15.0]]
	for mirror in [false, true]:
		for c in cases:
			var kmh: float = c[0]
			var radius: float = c[1]
			var track := StadiumTrack.new(300.0, radius, mirror)
			var s := _scene(track)
			s.distance_m = track.straight + 2.0
			s.apply_telemetry(0, false, 90, true, kmh, true)
			var max_tilt: float = 0.0
			var arc_end: float = track.straight + PI * radius - 8.0
			var frames: int = 0
			while s.distance_m < arc_end and frames < 600:
				s.advance(FRAME)
				max_tilt = maxf(max_tilt, _tilt_abs(s))
				frames += 1
				if frames >= 180:
					break
			var tilt: float = _tilt_toward(s, track.first_arc_center())
			var v: float = kmh / 3.6
			var physical: float = atan(v * v / (radius * G))
			var label: String = "%s R=%.0f м, %.0f км/ч" % ["вправо" if mirror else "влево", radius, kmh]
			assert_gt(tilt, 0.0, "%s: наклон внутрь поворота (%.3f рад)" % [label, tilt])
			assert_gte(tilt, minf(physical, RideScene.LEAN_MAX_RAD) - 0.002, "%s: наклон %.3f ≥ физического %.3f" % [label, tilt, physical])
			assert_lte(max_tilt, 0.45 + 1e-4, "%s: наклон ограничен 0.45 рад (макс. %.4f)" % [label, max_tilt])
			if physical > 0.45:
				assert_almost_eq(tilt, 0.45, 0.005, "%s: на пределе ровно 0.45 рад" % label)


func test_req_d3d_07_c3_no_lean_on_straight_and_when_stopped() -> void:
	var track := StadiumTrack.new(300.0, 30.0, false)
	var s := _scene(track)
	# Прямая на 60 км/ч: наклона нет совсем.
	s.distance_m = 40.0
	s.apply_telemetry(0, false, 90, true, 60.0, true)
	var worst: float = 0.0
	for i in 180:
		s.advance(FRAME)
		worst = maxf(worst, _tilt_abs(s))
	assert_lt(worst, 1e-6, "на прямой наклона нет (%.8f рад)" % worst)
	# Стоя посреди поворота с самого начала — наклона нет.
	var s2 := _scene(track)
	s2.distance_m = track.first_arc_mid()
	s2.apply_telemetry(0, false, 0, true, 0.0, true)
	worst = 0.0
	for i in 120:
		s2.advance(FRAME)
		worst = maxf(worst, _tilt_abs(s2))
	assert_lt(worst, 1e-6, "стоя в повороте — без наклона (%.8f рад)" % worst)
	# Ехал в повороте и остановился — наклон уходит.
	s2.distance_m = track.straight + 1.0
	s2.apply_telemetry(0, false, 90, true, 40.0, true)
	_frames(s2, 150)
	assert_gt(_tilt_abs(s2), 0.2, "в повороте наклон был")
	s2.apply_telemetry(0, false, 0, true, 0.0, true)
	_frames(s2, 180)
	assert_lt(_tilt_abs(s2), 0.005, "после остановки наклона нет (%.4f рад)" % _tilt_abs(s2))
	# Выезд из поворота на прямую — наклон уходит.
	var s3 := _scene(track)
	s3.distance_m = track.straight + PI * track.radius - 30.0
	s3.apply_telemetry(0, false, 90, true, 36.0, true)
	_frames(s3, 300)
	assert_lt(s3.distance_m, 2.0 * track.straight + PI * track.radius, "всё ещё на второй прямой")
	assert_lt(_tilt_abs(s3), 0.005, "на прямой после поворота наклон ушёл (%.4f рад)" % _tilt_abs(s3))


func test_req_d3d_07_c3_lean_does_not_change_heading_or_path() -> void:
	for mirror in [false, true]:
		var track := StadiumTrack.new(200.0, 30.0, mirror)
		var s := _scene(track)
		s.distance_m = track.straight + 1.0
		s.apply_telemetry(0, false, 90, true, 40.0, true)
		var worst_heading: float = 0.0
		var worst_pos: float = 0.0
		var max_tilt: float = 0.0
		s.advance(FRAME)
		for i in 150:
			var prev: Vector3 = s.rider_position()
			s.advance(FRAME)
			var smp := track.sample(s.distance_m)
			var root_fwd: Vector3 = -s.rider().global_transform.basis.z.normalized()
			var lean_fwd: Vector3 = -(s.rider().get_node("%Lean") as Node3D).global_transform.basis.z.normalized()
			worst_heading = maxf(worst_heading, maxf(root_fwd.angle_to(smp.forward), lean_fwd.angle_to(smp.forward)))
			worst_pos = maxf(worst_pos, s.rider_position().distance_to(smp.position))
			var step: Vector3 = s.rider_position() - prev
			if step.length() > 1e-4:
				worst_heading = maxf(worst_heading, step.normalized().angle_to(smp.forward) - 0.02)
			max_tilt = maxf(max_tilt, _tilt_abs(s))
		assert_gt(max_tilt, 0.2, "наклон был (%.2f рад)" % max_tilt)
		assert_lt(worst_heading, 1e-3, "%s: курс не меняется от наклона (%.6f рад)" % ["вправо" if mirror else "влево", worst_heading])
		assert_lt(worst_pos, 1e-4, "велосипедист на линии трассы (%.6f м)" % worst_pos)


# ===========================================================================
# Крит. 4 — тун-материалы, небо-шейдер, контур велосипедиста, земля без теней
# ===========================================================================

func test_req_d3d_07_c4_sky_is_direction_dependent_shader_for_default_custom_colors_and_custom_material() -> void:
	var s := _scene()
	var env: Environment = (s.get_node("%WorldEnvironment") as WorldEnvironment).environment
	assert_eq(env.background_mode, Environment.BG_SKY, "фон — небо")
	assert_not_null(env.sky)
	var mat: Material = env.sky.sky_material
	assert_true(mat is ShaderMaterial, "небо — ShaderMaterial, не ProceduralSky/цвет")
	var sh: Shader = (mat as ShaderMaterial).shader
	assert_eq(sh.get_mode(), Shader.MODE_SKY)
	assert_true(sh.code.contains("EYEDIR"), "цвет неба зависит от направления взгляда")
	var top: Color = (mat as ShaderMaterial).get_shader_parameter("top_color")
	var hor: Color = (mat as ShaderMaterial).get_shader_parameter("horizon_color")
	assert_false(top.is_equal_approx(hor), "зенит и горизонт разных цветов — градиент")
	# Свои цвета в EnvironmentSet — попадают в шейдер неба.
	var env_set := _env()
	env_set.sky_color = Color(0.1, 0.2, 0.9)
	env_set.horizon_color = Color(0.9, 0.8, 0.7)
	var s2 := _scene(null, env_set)
	var m2 := (s2.get_node("%WorldEnvironment") as WorldEnvironment).environment.sky.sky_material as ShaderMaterial
	assert_true((m2.get_shader_parameter("top_color") as Color).is_equal_approx(Color(0.1, 0.2, 0.9)))
	assert_true((m2.get_shader_parameter("horizon_color") as Color).is_equal_approx(Color(0.9, 0.8, 0.7)))
	assert_ne(m2, mat, "материал неба не общий между сценами (цвета не протекают)")
	assert_true((mat as ShaderMaterial).get_shader_parameter("horizon_color").is_equal_approx(hor), "первая сцена не изменилась")
	# Свой материал неба — используется как есть.
	var own := ShaderMaterial.new()
	own.shader = sh
	var env_set3 := _env()
	env_set3.sky_material = own
	var s3 := _scene(null, env_set3)
	assert_eq((s3.get_node("%WorldEnvironment") as WorldEnvironment).environment.sky.sky_material, own)


func test_req_d3d_07_c4_every_rider_mesh_has_outline_pass_with_nonzero_weight() -> void:
	var s := _scene()
	var meshes: Array[Node] = s.rider().find_children("*", "MeshInstance3D", true, false)
	# Состав гонщика с велосипедом — 10 узлов (REQ-D3D-09 п.7, спека «Состав и бюджет»).
	assert_eq(meshes.size(), 10, "частей велосипедиста: %d" % meshes.size())
	for node in meshes:
		var mi := node as MeshInstance3D
		var m: Material = mi.get_active_material(0)
		assert_true(m is ShaderMaterial, "%s: тун-материал" % mi.name)
		if not (m is ShaderMaterial):
			continue
		assert_true((m as ShaderMaterial).shader.code.contains("toon_light"), "%s: тун-свет" % mi.name)
		var outline: Material = m.next_pass
		assert_true(outline is ShaderMaterial, "%s: есть проход контура" % mi.name)
		if outline is ShaderMaterial:
			var code: String = (outline as ShaderMaterial).shader.code
			assert_true(code.contains("cull_front"), "%s: контур — инвертированная оболочка" % mi.name)
			assert_gt(float((outline as ShaderMaterial).get_shader_parameter("outline_width")), 0.0, "%s: толщина контура > 0" % mi.name)
	# Вес контура — альфа цвета вершины: у тела, ног и рамы контур не схлопнут.
	for part in ["Body", "Helmet", "ShoeR", "Bike"]:
		var pm := s.rider().get_node("%" + part) as MeshInstance3D
		var cols: PackedColorArray = pm.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var weighted: int = 0
		for c in cols:
			if c.a >= 0.5:
				weighted += 1
		assert_gte(float(weighted) / maxf(float(cols.size()), 1.0), 0.5, "%s: у %d из %d вершин вес контура ≥ 0.5" % [part, weighted, cols.size()])


func test_req_d3d_07_c4_ground_casts_no_shadows_and_world_uses_toon_materials_on_any_track() -> void:
	for track in [null, StadiumTrack.new(250.0, 40.0, true), LineTrack.new(3000.0)]:
		var s := _scene(track)
		var ground: Array[GeometryInstance3D] = [s.road()]
		for m in _meshes_with_shader(s, "grass"):
			ground.append(m)
		assert_eq(ground.size(), 3, "земля: дорога, полоса травы, рельеф")
		for g in ground:
			assert_eq(g.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s не отбрасывает тень" % g.name)
		var non_toon: Array[String] = []
		for c in _env_root(s).get_children():
			if c is GeometryInstance3D:
				var mat: Material = _surface_material(c as GeometryInstance3D)
				if not (mat is ShaderMaterial) or not (mat as ShaderMaterial).shader.code.contains("toon_light"):
					non_toon.append(String(c.name))
		assert_eq(non_toon, [] as Array[String], "все объекты мира — с тун-светом: %s" % str(non_toon))
		var sun: DirectionalLight3D = s.get_node("%Sun")
		assert_true(sun.shadow_enabled, "солнце даёт тени (велосипедист, объекты)")


# ===========================================================================
# Крит. 5 — камера в три четверти
# ===========================================================================

func test_req_d3d_07_c5_three_quarter_camera_left_of_travel_constant_horizontal_distance() -> void:
	for mirror in [false, true]:
		for kmh in [0.0, 18.0, 45.0, 60.0]:
			var track := StadiumTrack.new(250.0, 35.0, mirror)
			var s := _scene(track)
			s.distance_m = 60.0
			s.apply_telemetry(0, false, 90, true, kmh, true)
			var d0: float = _horizontal_cam_distance(s)
			var worst: float = 0.0
			var frames: int = int(minf(track.length_m() / maxf(kmh / 3.6, 1.0), 40.0) * 60.0)
			for i in frames:
				s.advance(FRAME)
				worst = maxf(worst, absf(_horizontal_cam_distance(s) - d0))
			var label: String = "%s %.0f км/ч" % ["вправо" if mirror else "влево", kmh]
			assert_lt(worst, 0.05, "%s: горизонтальное расстояние постоянно (откл. %.4f м)" % [label, worst])
	# На прямой после установления: камера позади и чуть левее линии движения.
	var t2 := StadiumTrack.new(400.0, 40.0, false)
	var s2 := _scene(t2)
	s2.distance_m = 20.0
	s2.apply_telemetry(0, false, 90, true, 30.0, true)
	_frames(s2, 180)
	var smp := t2.sample(s2.distance_m)
	var off: Vector3 = s2.camera_offset()
	var back: float = -off.dot(smp.forward)
	var left: float = -off.dot(smp.right())
	assert_gt(back, 3.0, "камера позади (%.2f м)" % back)
	var angle: float = atan2(left, back)
	assert_between(angle, deg_to_rad(3.0), deg_to_rad(20.0), "камера левее линии движения на %.1f°" % rad_to_deg(angle))
	# Петля по умолчанию с перепадами высоты — горизонтальное расстояние то же.
	var s3 := _scene()
	s3.apply_telemetry(0, false, 90, true, 40.0, true)
	var worst3: float = 0.0
	for i in 60 * 60:
		s3.advance(FRAME)
		worst3 = maxf(worst3, absf(_horizontal_cam_distance(s3) - RideScene.CAMERA_BACK_M))
	assert_lt(worst3, 0.05, "петля 60 с на 40 км/ч: откл. %.4f м" % worst3)


func test_req_d3d_07_c5_all_rider_points_between_0_1_and_1_45_m_in_frame_on_turns_speeds_and_aspects() -> void:
	# Санитарная проба фрустума: точка позади камеры — вне кадра.
	var probe := _scene()
	var cam := probe.camera()
	var behind := PackedVector3Array([cam.global_position + cam.global_transform.basis.z * 5.0])
	assert_eq(_points_outside_frame(probe, behind), 1, "точка позади камеры — вне кадра (фрустум рабочий)")
	var pts0 := _rider_points(probe)
	assert_gt(pts0.size(), 500, "точек велосипедиста на высоте 0.1–1.45 м: %d" % pts0.size())
	var failures: Array[String] = []
	for mirror in [false, true]:
		for kmh in [0.0, 20.0, 45.0, 60.0]:
			var track := StadiumTrack.new(200.0, 25.0, mirror)
			var s := _scene(track)
			s.distance_m = track.straight - 10.0
			s.apply_telemetry(0, false, 90, true, kmh, true)
			for i in 240:
				s.advance(FRAME)
				if i % 30 == 29:
					var out: int = _points_outside_frame(s, _rider_points(s))
					if out > 0:
						failures.append("%s %.0f км/ч кадр %d: вне кадра %d точек (наклон %.2f)" % ["R" if mirror else "L", kmh, i, out, s.lean_rad()])
	# Петля по умолчанию, полный круг на 32 км/ч.
	var s2 := _scene()
	s2.apply_telemetry(0, false, 90, true, 32.0, true)
	var lap_frames: int = int(s2.track.length_m() / (32.0 / 3.6) * 60.0)
	for i in range(0, lap_frames, 1):
		s2.advance(FRAME)
		if i % 600 == 0:
			var out2: int = _points_outside_frame(s2, _rider_points(s2))
			if out2 > 0:
				failures.append("петля s=%.0f: вне кадра %d точек" % [s2.distance_m, out2])
	# Другие соотношения сторон экрана: iPad 4:3, iPhone 19.5:9.
	for size in [Vector2i(1024, 768), Vector2i(2532, 1170)]:
		var track2 := StadiumTrack.new(200.0, 25.0, false)
		var s3 := _scene_in_viewport(size, track2)
		s3.distance_m = track2.straight - 5.0
		s3.apply_telemetry(0, false, 90, true, 45.0, true)
		for i in 180:
			s3.advance(FRAME)
		var out3: int = _points_outside_frame(s3, _rider_points(s3))
		if out3 > 0:
			failures.append("экран %s: вне кадра %d точек" % [str(size), out3])
	assert_eq(failures, [] as Array[String], "велосипедист в кадре: %s" % str(failures))
