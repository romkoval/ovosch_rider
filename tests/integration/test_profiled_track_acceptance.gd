extends GutTest
## Приёмка T-070 (tester): `ProfiledTrack`, `RouteWorld`, `RideScene.set_route`, дорога кусками.
## REQ-D3D-08 крит. 2 (горизонтальная геометрия на стыке), 4 (полотно и велосипедист на h(s),
## рельеф не выше полотна), 5 (продольный наклон atan(g), камера D3D-07.5), 7 (D3D-02, D3D-04,
## D3D-07.2–3 на каждой трассе), 10 («Перевал» — петля, без разворота на вершине),
## 13 (тренировка по плану — на `flat`, скорость не зависит от уклона); REQ-D3D-03 крит. 1, 2.
##
## Отличия от тестов разработчика: высота полотна — по треугольникам меша дороги (вертикальный
## «луч» в точке оси), а не по формуле трассы; рельеф — по треугольникам меша рельефа поперёк
## всей ширины; камера — по фрустуму в SubViewport 1280×720 с точками велосипедиста на 0.1–1.45 м;
## наклон в повороте — в самом крутом повороте каждой трассы, найденном тестом; «Перевал» —
## по своей сетке и по повороту курса в окрестности вершины; сцена по умолчанию (без явной
## трассы) сохраняет состав мира D3D-07.1 — то, что перестали проверять помощники `_scene()`
## чужих тестов после `route_id = ""`.

const SCENE: String = "res://src/scene3d/ride_scene.tscn"
const FRAME: float = 1.0 / 60.0
const G: float = 9.81
const STEP_M: float = 50.0

var _scenes: Dictionary = {}


func before_all() -> void:
	for id in RouteCatalog.IDS:
		var vp := SubViewport.new()
		vp.size = Vector2i(1280, 720)
		add_child(vp)
		var s: RideScene = load(SCENE).instantiate()
		s.set_route(id)
		vp.add_child(s)
		_scenes[id] = s


func after_all() -> void:
	for id in _scenes:
		var s: RideScene = _scenes[id]
		if is_instance_valid(s):
			s.get_parent().free()
	_scenes.clear()


func _profile(id: String) -> RouteProfile:
	return RouteCatalog.get_route(id).profile


## Поставить велосипедиста на s и дать камере догнать курс (скорость 0).
func _place(s: RideScene, at_m: float, frames: int = 45) -> void:
	s.apply_telemetry(0, false, 0, true, 0.0, true)
	s.distance_m = at_m
	for i in frames:
		s.advance(FRAME)


# --- треугольники мешей ----------------------------------------------------------

func _mesh_nodes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root as MeshInstance3D)
	for c in root.find_children("*", "MeshInstance3D", true, false):
		out.append(c as MeshInstance3D)
	return out


func _triangles(nodes: Array[MeshInstance3D], cells: Dictionary, cell_m: float) -> Dictionary:
	var grid: Dictionary = {}
	var tris := PackedVector3Array()
	for mi in nodes:
		if mi.mesh == null:
			continue
		var xf: Transform3D = mi.global_transform
		for surf in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(surf)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count: int = idx.size() if idx.size() > 0 else v.size()
			for t in range(0, count - 2, 3):
				var a: Vector3 = xf * v[idx[t] if idx.size() > 0 else t]
				var b: Vector3 = xf * v[idx[t + 1] if idx.size() > 0 else t + 1]
				var c: Vector3 = xf * v[idx[t + 2] if idx.size() > 0 else t + 2]
				var ti: int = -1
				for cx in range(floori(minf(a.x, minf(b.x, c.x)) / cell_m), floori(maxf(a.x, maxf(b.x, c.x)) / cell_m) + 1):
					for cz in range(floori(minf(a.z, minf(b.z, c.z)) / cell_m), floori(maxf(a.z, maxf(b.z, c.z)) / cell_m) + 1):
						var key := Vector2i(cx, cz)
						if not cells.has(key):
							continue
						if ti < 0:
							ti = tris.size()
							tris.append(a)
							tris.append(b)
							tris.append(c)
						if not grid.has(key):
							grid[key] = PackedInt32Array()
						var list: PackedInt32Array = grid[key]
						list.append(ti)
						grid[key] = list
	return {"grid": grid, "tris": tris}


## Высоты всех треугольников, накрывающих точку p по вертикали (пусто — нет).
func _heights_at(mesh: Dictionary, p: Vector3, cell_m: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var key := Vector2i(floori(p.x / cell_m), floori(p.z / cell_m))
	var grid: Dictionary = mesh["grid"]
	if not grid.has(key):
		return out
	var tris: PackedVector3Array = mesh["tris"]
	for ti in (grid[key] as PackedInt32Array):
		var a: Vector3 = tris[ti]
		var b: Vector3 = tris[ti + 1]
		var c: Vector3 = tris[ti + 2]
		var d: float = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(d) < 1e-9:
			continue
		var l1: float = ((b.z - c.z) * (p.x - c.x) + (c.x - b.x) * (p.z - c.z)) / d
		var l2: float = ((c.z - a.z) * (p.x - c.x) + (a.x - c.x) * (p.z - c.z)) / d
		var l3: float = 1.0 - l1 - l2
		if l1 < -1e-6 or l2 < -1e-6 or l3 < -1e-6:
			continue
		out.append(l1 * a.y + l2 * b.y + l3 * c.y)
	return out


## Точки поперёк дороги каждые `step` м: [s, смещение, точка на оси/поперёк].
func _cross_points(s: RideScene, step: float, offsets: Array[float]) -> Array:
	var out: Array = []
	var center_offset: float = float(s.environment_set.get("road_center_offset_m"))
	var smp := TrackSample.new()
	var n: int = floori(s.track.length_m() / step)
	for i in n:
		var at: float = float(i) * step
		s.track.sample_into(at, smp)
		var right: Vector3 = smp.right()
		var axis: Vector3 = smp.position + right * center_offset
		for k in offsets:
			out.append([at, k, axis + right * k])
	return out


# ---------------------------------------------------------------------------
# REQ-D3D-08 крит. 2 — стык круга
# ---------------------------------------------------------------------------

func test_req_d3d_08_c2_seam_horizontal_geometry_height_and_grade_continuous_on_each_route() -> void:
	var a := TrackSample.new()
	var b := TrackSample.new()
	for id in RouteCatalog.IDS:
		var t := RouteWorld.track(id)
		var prof := _profile(id)
		var L: float = t.length_m()
		assert_true(t.is_loop(), "%s: замкнутая трасса" % id)
		assert_almost_eq(L, prof.length_m(), 0.5, "%s: длина плана = длине профиля" % id)
		t.sample_into(L - 0.5, a)
		t.sample_into(0.5, b)
		var gap := Vector2(b.position.x - a.position.x, b.position.z - a.position.z).length()
		assert_almost_eq(gap, 1.0, 0.05, "%s: через стык 1 м по плану (%.3f м)" % [id, gap])
		var fa := Vector2(a.forward.x, a.forward.z).normalized()
		var fb := Vector2(b.forward.x, b.forward.z).normalized()
		assert_lt(rad_to_deg(absf(fa.angle_to(fb))), 1.0, "%s: курс через стык без излома" % id)
		assert_lte(absf(prof.height_at(L) - prof.height_at(0.0)), 0.1, "%s: |h(L) − h(0)|" % id)
		assert_lte(absf(prof.grade_at(L - 1.0) - prof.grade_at(1.0)), 1.0, "%s: разрыв уклона на стыке ≤ 1 %%" % id)
		# По всему кругу шаг плана 1 м — без скачков (стык не исключение).
		var worst: float = 0.0
		var prev := TrackSample.new()
		t.sample_into(0.0, prev)
		var cur := TrackSample.new()
		var at: float = 1.0
		while at <= L + 0.5:
			t.sample_into(at, cur)
			var step := Vector2(cur.position.x - prev.position.x, cur.position.z - prev.position.z).length()
			worst = maxf(worst, absf(step - 1.0))
			prev.position = cur.position
			at += 1.0
		assert_lt(worst, 0.05, "%s: шаг плана 1 м ± 5 см по всему кругу (макс. отклонение %.3f)" % [id, worst])


# ---------------------------------------------------------------------------
# REQ-D3D-08 крит. 4 — высота полотна и велосипедиста, рельеф не выше полотна
# ---------------------------------------------------------------------------

func test_req_d3d_08_c4_road_mesh_and_rider_height_equal_profile_every_50m() -> void:
	var cell_m: float = 16.0
	for id in RouteCatalog.IDS:
		var s: RideScene = _scenes[id]
		var prof := _profile(id)
		var pts := _cross_points(s, STEP_M, [0.0] as Array[float])
		var cells: Dictionary = {}
		for q in pts:
			var p: Vector3 = q[2]
			cells[Vector2i(floori(p.x / cell_m), floori(p.z / cell_m))] = true
		var road := _triangles(_mesh_nodes(s.road()), cells, cell_m)
		var bad: Array[String] = []
		var missing: int = 0
		for q in pts:
			var at: float = q[0]
			var hs := _heights_at(road, q[2], cell_m)
			if hs.is_empty():
				missing += 1
				continue
			# Ближайший к h(s) слой полотна (дорога может проходить над собой — мост/развязка).
			var best: float = INF
			for y in hs:
				best = minf(best, absf(y - prof.height_at(at)))
			if best > 0.05 and bad.size() < 6:
				bad.append("s=%.0f: полотно %+.3f м от h(s)" % [at, best])
		assert_eq(missing, 0, "%s: под каждой точкой оси есть полотно" % id)
		assert_eq(bad, [] as Array[String], "%s: ось дороги = h(s) ± 0.05 м" % id)
		var bad_rider: Array[String] = []
		var n: int = floori(prof.length_m() / STEP_M)
		for i in n:
			var at2: float = float(i) * STEP_M
			_place(s, at2, 1)
			var dy: float = s.rider_position().y - prof.height_at(at2)
			if absf(dy) > 0.05 and bad_rider.size() < 6:
				bad_rider.append("s=%.0f: %+.3f м" % [at2, dy])
		assert_eq(bad_rider, [] as Array[String], "%s: велосипедист по вертикали = h(s) ± 0.05 м" % id)


func test_req_d3d_08_c4_terrain_mesh_never_above_road_across_full_width_every_50m() -> void:
	var cell_m: float = 16.0
	for id in RouteCatalog.IDS:
		var s: RideScene = _scenes[id]
		assert_not_null(s.terrain(), "%s: рельеф есть" % id)
		var half: float = s.environment_set.road_width_m * 0.5
		var offsets: Array[float] = []
		var k: float = -half
		while k <= half + 1e-6:
			offsets.append(k)
			k += 0.5
		var pts := _cross_points(s, STEP_M, offsets)
		var cells: Dictionary = {}
		for q in pts:
			var p: Vector3 = q[2]
			cells[Vector2i(floori(p.x / cell_m), floori(p.z / cell_m))] = true
		var terrain_nodes: Array[MeshInstance3D] = []
		for node in s.world_nodes():
			if node.name == "Terrain":
				terrain_nodes.append_array(_mesh_nodes(node))
		assert_gt(terrain_nodes.size(), 0, "%s: меш рельефа найден" % id)
		var terrain := _triangles(terrain_nodes, cells, cell_m)
		var road := _triangles(_mesh_nodes(s.road()), cells, cell_m)
		var above: Array[String] = []
		var covered: int = 0
		for q in pts:
			var p: Vector3 = q[2]
			var ts := _heights_at(terrain, p, cell_m)
			var rs := _heights_at(road, p, cell_m)
			if ts.is_empty() or rs.is_empty():
				continue
			# Полотно в этой точке — слой ближе всего к оси трассы.
			var road_y: float = rs[0]
			for y in rs:
				if absf(y - p.y) < absf(road_y - p.y):
					road_y = y
			covered += 1
			for ty in ts:
				# Рельеф, которого касается полотно (не далёкий склон под мостом/над тоннелем).
				if ty > road_y + 0.001 and ty < road_y + 30.0 and above.size() < 8:
					above.append("s=%.0f off=%+.1f: рельеф на %+.3f м выше полотна" % [q[0], q[1], ty - road_y])
		assert_gt(covered, pts.size() / 2, "%s: под дорогой есть меш рельефа (%d из %d)" % [id, covered, pts.size()])
		assert_eq(above, [] as Array[String], "%s: дорога нигде не «утоплена»" % id)


# ---------------------------------------------------------------------------
# REQ-D3D-08 крит. 5 — продольный наклон и камера
# ---------------------------------------------------------------------------

func _key_points(s: RideScene) -> PackedVector3Array:
	var out := PackedVector3Array()
	var xf: Transform3D = s.rider().global_transform
	for h in [0.1, 0.8, 1.45]:
		for fwd in [-0.6, 0.0, 0.6]:
			out.append(xf * Vector3(0.0, h, -fwd))
		out.append(xf * Vector3(0.3, h, 0.0))
		out.append(xf * Vector3(-0.3, h, 0.0))
	return out


func _outside(s: RideScene, pts: PackedVector3Array) -> int:
	var planes: Array[Plane] = s.camera().get_frustum()
	var n: int = 0
	for p in pts:
		for pl in planes:
			if pl.is_point_over(p):
				n += 1
				break
	return n


func test_req_d3d_08_c5_pitch_atan_grade_and_camera_every_50m_including_max_grade_and_crest() -> void:
	for id in RouteCatalog.IDS:
		var s: RideScene = _scenes[id]
		var prof := _profile(id)
		var L: float = prof.length_m()
		var points: Array[float] = []
		for i in floori(L / STEP_M):
			points.append(float(i) * STEP_M)
		# Максимальный уклон, самый крутой спуск и вершина (переход подъём → спуск).
		var max_g_s: float = 0.0
		var min_g_s: float = 0.0
		var top_s: float = 0.0
		var at: float = 0.0
		while at < L:
			if prof.grade_at(at) > prof.grade_at(max_g_s):
				max_g_s = at
			if prof.grade_at(at) < prof.grade_at(min_g_s):
				min_g_s = at
			if prof.height_at(at) > prof.height_at(top_s):
				top_s = at
			at += 5.0
		points.append_array([max_g_s, min_g_s, top_s])
		var bad_pitch: Array[String] = []
		var bad_cam: Array[String] = []
		for p in points:
			_place(s, p)
			var expected: float = atan(prof.grade_at(p) / 100.0)
			if absf(s.rider_pitch_rad() - expected) > deg_to_rad(1.0) and bad_pitch.size() < 5:
				bad_pitch.append("s=%.0f: %.2f° против %.2f°" % [p, rad_to_deg(s.rider_pitch_rad()), rad_to_deg(expected)])
			# Наклон узла велосипедиста в мире (независимо от `rider_pitch_rad`).
			var fwd: Vector3 = -s.rider().global_transform.basis.z.normalized()
			var world_pitch: float = atan2(fwd.y, Vector2(fwd.x, fwd.z).length())
			if absf(world_pitch - expected) > deg_to_rad(1.0) and bad_pitch.size() < 5:
				bad_pitch.append("s=%.0f: узел в мире %.2f° против %.2f°" % [p, rad_to_deg(world_pitch), rad_to_deg(expected)])
			var off: Vector3 = s.camera_offset()
			var hd: float = Vector2(off.x, off.z).length()
			var out_n: int = _outside(s, _key_points(s))
			if (absf(hd - RideScene.CAMERA_BACK_M) > 0.05 or out_n > 0) and bad_cam.size() < 5:
				bad_cam.append("s=%.0f: расстояние %.3f м, точек вне кадра %d" % [p, hd, out_n])
		assert_eq(bad_pitch, [] as Array[String], "%s: продольный наклон = atan(g(s)/100) ± 1°" % id)
		assert_eq(bad_cam, [] as Array[String], "%s: камера D3D-07.5 на всех точках" % id)
		assert_gt(prof.grade_at(max_g_s), 0.9, "%s: среди точек есть подъём" % id)


# ---------------------------------------------------------------------------
# REQ-D3D-08 крит. 7 — D3D-02, D3D-04, D3D-07.2–3 на каждой трассе
# ---------------------------------------------------------------------------

func _foot_errors(rider: Rider) -> Dictionary:
	var arm: Node3D = rider.get_node("%CrankArm")
	var l: float = RiderModel.CRANK_LENGTH_M
	var px: float = RiderModel.PEDAL_X_M
	var foot_r: Vector3 = rider.bone_global("cleat.R").origin
	var foot_l: Vector3 = rider.bone_global("cleat.L").origin
	var pedal_r: Vector3 = arm.global_transform * Vector3(-px, l, 0.0)
	var pedal_l: Vector3 = arm.global_transform * Vector3(px, -l, 0.0)
	return {"r": foot_r.distance_to(pedal_r), "l": foot_l.distance_to(pedal_l)}


## Самый крутой поворот трассы: s и кривизна плана κ, 1/м (по курсу через 6 м).
func _tightest_turn(t: Track) -> Vector2:
	var a := TrackSample.new()
	var b := TrackSample.new()
	var best := Vector2(0.0, 0.0)
	var at: float = 0.0
	while at < t.length_m():
		t.sample_into(at, a)
		t.sample_into(at + 6.0, b)
		var fa := Vector2(a.forward.x, a.forward.z).normalized()
		var fb := Vector2(b.forward.x, b.forward.z).normalized()
		var k: float = absf(fa.angle_to(fb)) / 6.0
		if k > best.y:
			best = Vector2(at, k)
		at += 2.0
	return best


func test_req_d3d_08_c7_speed_cadence_feet_and_lean_on_each_route() -> void:
	for id in RouteCatalog.IDS:
		var s: RideScene = _scenes[id]
		# D3D-02: модельная скорость сцены — опорные точки и монотонность, на любой трассе.
		s.weight_kg = 75.0
		for i in 90:
			s.apply_telemetry(200, true, 90, true, 0.0, false)
		assert_almost_eq(s.speed_kmh, 34.0, 3.0, "%s: 200 Вт, 75 кг" % id)
		var v200: float = s.speed_kmh
		for i in 90:
			s.apply_telemetry(300, true, 90, true, 0.0, false)
		assert_gt(s.speed_kmh, v200, "%s: скорость растёт с мощностью" % id)
		for i in 31:
			s.apply_telemetry(0, true, 0, true, 0.0, false)
		assert_eq(s.speed_kmh, 0.0, "%s: 0 Вт — остановка не дольше 30 с" % id)
		# D3D-04: 90 rpm → 1.5 об/с на шатуне; 0 — стоит.
		_place(s, _tightest_turn(s.track).x - 200.0, 1)
		s.apply_telemetry(0, false, 90, true, 25.0, true)
		for i in 240:
			s.advance(FRAME)
		var a0: float = s.rider().crank_rotation_rad()
		var unwrapped: float = 0.0
		var prev: float = a0
		var feet_worst: float = 0.0
		for i in 120:
			s.advance(FRAME)
			var a: float = s.rider().crank_rotation_rad()
			unwrapped += wrapf(a - prev, -PI, PI)
			prev = a
			var fe := _foot_errors(s.rider())
			feet_worst = maxf(feet_worst, maxf(float(fe["r"]), float(fe["l"])))
		assert_almost_eq(absf(unwrapped) / TAU / 2.0, 1.5, 0.05, "%s: 90 rpm → 1.5 об/с" % id)
		assert_lte(feet_worst, 0.01, "%s: стопа на педали ±1 см (макс. %.4f м)" % [id, feet_worst])
		# D3D-07.3: наклон в самом крутом повороте ≥ физического, ≤ 0.45 рад.
		var turn := _tightest_turn(s.track)
		var kmh: float = 32.0
		_place(s, turn.x - 60.0, 1)
		s.apply_telemetry(0, false, 90, true, kmh, true)
		var peak: float = 0.0
		var frames: int = 0
		while s.distance_m < turn.x + 6.0 and frames < 1200:
			s.advance(FRAME)
			peak = maxf(peak, absf(s.lean_rad()))
			frames += 1
		var v: float = kmh / 3.6
		var physical: float = atan(v * v * turn.y / G)
		assert_gte(peak, minf(physical, 0.45) * 0.9, "%s: в повороте κ=%.4f наклон %.3f рад против физического %.3f" % [id, turn.y, peak, physical])
		assert_lte(peak, 0.45 + 1e-4, "%s: наклон ≤ 0.45 рад" % id)
		s.apply_telemetry(0, false, 0, true, 0.0, true)
		for i in 240:
			s.advance(FRAME)
		assert_lt(absf(s.lean_rad()), 0.005, "%s: остановился — наклона нет" % id)


# ---------------------------------------------------------------------------
# REQ-D3D-08 крит. 10 — «Перевал»: подъём и спуск — разные дороги, без разворота на вершине
# ---------------------------------------------------------------------------

func test_req_d3d_08_c10_mountain_pass_climb_and_descent_30m_apart_and_no_u_turn_at_summit() -> void:
	var t := RouteWorld.track(RouteCatalog.MOUNTAINS)
	var smp := TrackSample.new()
	var cell: float = 30.0
	var grid: Dictionary = {}
	var at: float = 3000.0
	while at <= 10000.0:
		t.sample_into(at, smp)
		var key := Vector2i(floori(smp.position.x / cell), floori(smp.position.z / cell))
		if not grid.has(key):
			grid[key] = PackedVector2Array()
		var list: PackedVector2Array = grid[key]
		list.append(Vector2(smp.position.x, smp.position.z))
		grid[key] = list
		at += 2.0
	var closest: float = INF
	at = 11200.0
	while at <= 19000.0:
		t.sample_into(at, smp)
		var p := Vector2(smp.position.x, smp.position.z)
		var k := Vector2i(floori(p.x / cell), floori(p.y / cell))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var kk := Vector2i(k.x + dx, k.y + dz)
				if grid.has(kk):
					for q in (grid[kk] as PackedVector2Array):
						closest = minf(closest, p.distance_to(q))
		at += 2.0
	assert_gte(closest, 30.0, "подъём (3–10 км) и спуск (11.2–19 км) не ближе 30 м (мин. %.1f м)" % closest)
	# Нет разворота на 180° у вершины: на любом отрезке 300 м в 9.5–11.7 км курс меняется < 150°.
	var a := TrackSample.new()
	var b := TrackSample.new()
	var worst: float = 0.0
	var worst_at: float = 0.0
	at = 9500.0
	while at + 300.0 <= 11700.0:
		var turn: float = 0.0
		var s0: float = at
		while s0 < at + 300.0:
			t.sample_into(s0, a)
			t.sample_into(s0 + 5.0, b)
			turn += Vector2(a.forward.x, a.forward.z).normalized().angle_to(Vector2(b.forward.x, b.forward.z).normalized())
			s0 += 5.0
		if absf(turn) > worst:
			worst = absf(turn)
			worst_at = at
		at += 25.0
	assert_lt(rad_to_deg(worst), 150.0, "у вершины нет разворота: макс. поворот за 300 м %.0f° (с %.0f м)" % [rad_to_deg(worst), worst_at])


# ---------------------------------------------------------------------------
# REQ-D3D-08 крит. 13 — тренировка по плану на `flat`, скорость не зависит от уклона
# ---------------------------------------------------------------------------

func test_req_d3d_08_c13_default_scene_is_flat_and_bound_workout_speed_ignores_grade() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 360)
	add_child_autofree(vp)
	var s: RideScene = load(SCENE).instantiate()
	vp.add_child(s)
	assert_eq(s.route_id, RouteCatalog.FLAT, "сцена по умолчанию — «равнина»")
	assert_true(s.track is ProfiledTrack, "трасса каталога, а не процедурная петля")
	var prof := _profile(RouteCatalog.FLAT)
	var hi_s: float = 0.0
	var lo_s: float = 0.0
	var at: float = 0.0
	while at < prof.length_m():
		if prof.grade_at(at) > prof.grade_at(hi_s):
			hi_s = at
		if prof.grade_at(at) < prof.grade_at(lo_s):
			lo_s = at
		at += 5.0
	var speeds: Array[float] = []
	for p in [hi_s, lo_s]:
		s.distance_m = p
		for i in 60:
			s.apply_telemetry(220, true, 90, true, 0.0, false)
		# Стоим на месте участка: speed_kmh — установившаяся при 220 Вт.
		speeds.append(s.speed_kmh)
		s.advance(FRAME)
		assert_almost_eq(s.rider_position().y, prof.height_at(s.distance_m), 0.05, "высота следует профилю")
	assert_almost_eq(speeds[0], speeds[1], 0.1,
		"уклон %.1f %% и %.1f %%: %.2f и %.2f км/ч" % [prof.grade_at(hi_s), prof.grade_at(lo_s), speeds[0], speeds[1]])


# ---------------------------------------------------------------------------
# REQ-D3D-03 крит. 1, 2 — 80 км без конца трассы, число кусков постоянно
# ---------------------------------------------------------------------------

func _node_count(n: Node) -> int:
	var c: int = 1
	for ch in n.get_children():
		c += _node_count(ch)
	return c


func test_req_d3d_03_c1_c2_80_km_at_40_kmh_on_each_route_rider_on_road_nodes_constant() -> void:
	var smp := TrackSample.new()
	for id in RouteCatalog.IDS:
		var s: RideScene = _scenes[id]
		_place(s, 0.0, 1)
		var nodes0: int = _node_count(s)
		var road_chunks0: int = _mesh_nodes(s.road()).size()
		s.apply_telemetry(0, false, 90, true, 40.0, true)
		var travelled: float = 0.0
		var off_road: int = 0
		var wraps: int = 0
		var prev_d: float = s.distance_m
		var dt: float = 0.25
		for i in roundi(7200.0 / dt):
			s.advance(dt)
			travelled += 40.0 / 3.6 * dt
			if s.distance_m < prev_d:
				wraps += 1
			prev_d = s.distance_m
			if i % 40 == 0:
				s.track.sample_into(s.distance_m, smp)
				if s.distance_m < 0.0 or s.distance_m >= s.track.length_m() \
						or s.rider_position().distance_to(smp.position) > 0.01:
					off_road += 1
		assert_almost_eq(travelled, 80000.0, 1.0)
		assert_eq(off_road, 0, "%s: велосипедист всегда на оси дороги" % id)
		assert_eq(wraps, floori((travelled - 0.5) / s.track.length_m()), "%s: позиция оборачивается на каждом круге" % id)
		assert_eq(_node_count(s), nodes0, "%s: узлов столько же после 80 км" % id)
		assert_eq(_mesh_nodes(s.road()).size(), road_chunks0, "%s: кусков дороги столько же" % id)
		assert_lte(road_chunks0, RoadBuilder.MAX_CHUNKS, "%s: кусков дороги ≤ константы" % id)


# ---------------------------------------------------------------------------
# Сцена по умолчанию (трасса каталога) сохраняет состав мира D3D-07.1
# ---------------------------------------------------------------------------

func test_req_d3d_07_c1_world_on_each_catalog_route_has_marked_road_vegetation_posts_terrain() -> void:
	for id in RouteCatalog.IDS:
		var s: RideScene = _scenes[id]
		var mat: Material = s.road().get_active_material(0)
		assert_true(mat is ShaderMaterial, "%s: асфальт — шейдер (разметка)" % id)
		if mat is ShaderMaterial:
			assert_true((mat as ShaderMaterial).shader.code.contains("UV"), "%s: цвет асфальта зависит от UV" % id)
		var types: Dictionary = {}
		var env_root: Node = s.get_node("%EnvironmentRoot")
		for c in env_root.get_children():
			if c is MultiMeshInstance3D and c != s.props():
				var mm := (c as MultiMeshInstance3D).multimesh
				if mm != null and mm.mesh != null and mm.instance_count > 0:
					types[mm.mesh.get_instance_id()] = true
		assert_gte(types.size(), 3, "%s: типов растительности %d" % [id, types.size()])
		assert_not_null(s.props(), "%s: сигнальные столбики" % id)
		if s.props() != null:
			assert_gt(s.props().multimesh.instance_count, 0)
		assert_not_null(s.terrain(), "%s: рельеф" % id)
