extends GutTest
## Приёмка T-066 (tester): длинные трассы — видимый бюджет MultiMesh и рельеф-коридор.
## REQ-D3D-08 крит. 6 (бюджетная часть): экземпляров MultiMesh, видимых из любой точки трассы
## с шагом 50 м (с учётом дальности видимости), не больше бюджета `docs/perf_budget.md`;
## REQ-D3D-05 крит. 4: MeshInstance3D и материалы в бюджете на 20 км; регрессия REQ-D3D-07
## крит. 1 (бюджет — теперь «видимо», 2000) и крит. 5 (камера) на 2 и 20 км; рельеф не выше
## полотна в пределах ширины дороги — по треугольникам реального меша рельефа.
##
## Видимый бюджет проверяется двумя способами: `PerfBudget.max_visible_along(…, 50 м)` и
## собственным подсчётом теста из точки камеры (3.8 м назад, 2.1 м вверх): кусок без
## `visibility_range_end` виден всегда, иначе — если расстояние от камеры до центра его AABB
## (`custom_aabb` в мировых координатах) ≤ end + margin. Старые приёмочные тесты D3D-07 сверяют
## общее число экземпляров с первой строкой «MultiMesh» документа, которая теперь — потолок
## «всего на трассе» (40000); здесь бюджет кадра — строка «Видимых экземпляров».

const SCENE: String = "res://src/scene3d/ride_scene.tscn"
const DEFAULT_ENV: String = "res://src/scene3d/default_environment.tres"
const BUDGET_DOC: String = "res://docs/perf_budget.md"
const FRAME: float = 1.0 / 60.0
const STEP_M: float = 50.0
const CAM_BACK_M: float = 3.8
const CAM_UP_M: float = 2.1


## Ломаная (замкнутая или нет) по точкам XZ: направление — направление отрезка.
class PolylineTrack extends Track:
	var pts: PackedVector3Array
	var cum := PackedFloat64Array()
	var loop: bool

	func _init(points: PackedVector3Array, closed: bool) -> void:
		pts = points.duplicate()
		loop = closed
		if closed:
			pts.append(points[0])
		cum.append(0.0)
		for i in range(1, pts.size()):
			cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))

	func length_m() -> float:
		return cum[cum.size() - 1]

	func is_loop() -> bool:
		return loop

	func sample_into(distance_m: float, out: TrackSample) -> void:
		var s: float = wrap_distance(distance_m)
		var i: int = clampi(cum.bsearch(s, true) - 1, 0, pts.size() - 2)
		while i < pts.size() - 2 and s > cum[i + 1]:
			i += 1
		var seg: float = cum[i + 1] - cum[i]
		var t: float = clampf((s - cum[i]) / seg, 0.0, 1.0) if seg > 0.0 else 0.0
		out.position = pts[i].lerp(pts[i + 1], t)
		out.forward = (pts[i + 1] - pts[i]).normalized()
		out.up = Vector3.UP
		out.grade = 0.0


var _short: RideScene = null
var _long: RideScene = null
var _shuttle: RideScene = null
var _zigzag: RideScene = null


func before_all() -> void:
	_short = _make(null)
	_long = _make(LoopTrack.new(7, 2175.0, 0.25, 24, 3.0))
	# «Туда-обратно» 20 км: две параллельные дороги в 80 м друг от друга.
	_shuttle = _make(_stadium(9800.0, 40.0))
	_zigzag = _make(_zigzag_track())


func after_all() -> void:
	for s in [_short, _long, _shuttle, _zigzag]:
		if is_instance_valid(s):
			s.free()


func _make(track: Track) -> RideScene:
	var s: RideScene = load(SCENE).instantiate()
	s.environment_set = (load(DEFAULT_ENV) as EnvironmentSet).duplicate() as EnvironmentSet
	if track != null:
		s.set_track(track)
	add_child(s)
	return s


func _stadium(straight: float, radius: float) -> PolylineTrack:
	var p := PackedVector3Array()
	p.append(Vector3(0, 0, 0))
	p.append(Vector3(straight, 0, 0))
	for k in range(1, 12):
		var a: float = PI * float(k) / 12.0
		p.append(Vector3(straight + radius * sin(a), 0, radius - radius * cos(a)))
	p.append(Vector3(straight, 0, 2.0 * radius))
	p.append(Vector3(0, 0, 2.0 * radius))
	for k in range(1, 12):
		var a: float = PI * float(k) / 12.0
		p.append(Vector3(-radius * sin(a), 0, radius + radius * cos(a)))
	return PolylineTrack.new(p, true)


## Змейка ~22.5 км в квадрате ~1.5 × 1.3 км: 14 галсов по 1400 м через 100 м (серпантин).
func _zigzag_track() -> PolylineTrack:
	var p := PackedVector3Array()
	for i in 14:
		var z: float = 100.0 * float(i)
		if i % 2 == 0:
			p.append(Vector3(0, 0, z))
			p.append(Vector3(1400, 0, z))
		else:
			p.append(Vector3(1400, 0, z))
			p.append(Vector3(0, 0, z))
	p.append(Vector3(-150, 0, 1300))
	p.append(Vector3(-150, 0, 0))
	return PolylineTrack.new(p, true)


func _doc_row(keyword: String) -> int:
	var re := RegEx.create_from_string("\\|\\s*(\\d+)\\s*\\|")
	for line in FileAccess.get_file_as_string(BUDGET_DOC).split("\n"):
		if line.contains(keyword):
			var m := re.search(line)
			if m != null:
				return int(m.get_string(1))
	return -1


func _visible_budget() -> int:
	return _doc_row("Видимых экземпляров")


func _multimeshes(root: Node) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	for n in root.find_children("*", "MultiMeshInstance3D", true, false):
		out.append(n as MultiMeshInstance3D)
	return out


## Собственный подсчёт видимых экземпляров из точки `eye`; `problems` — куски, которые
## нельзя честно посчитать (дальность есть, а `custom_aabb` нет).
func _visible_from(root: Node, eye: Vector3, problems: Array[String]) -> int:
	var total: int = 0
	for mmi in _multimeshes(root):
		var mm := mmi.multimesh
		if mm == null or mm.instance_count == 0 or not mmi.visible:
			continue
		if mmi.visibility_range_end <= 0.0:
			total += mm.instance_count
			continue
		if mm.custom_aabb.size == Vector3.ZERO:
			if problems.size() < 5:
				problems.append("%s: дальность %.0f м без custom_aabb" % [mmi.name, mmi.visibility_range_end])
			total += mm.instance_count
			continue
		var center: Vector3 = mmi.global_transform * mm.custom_aabb.get_center()
		if eye.distance_to(center) <= mmi.visibility_range_end + mmi.visibility_range_end_margin:
			total += mm.instance_count
	return total


## Максимум собственного подсчёта из камеры по точкам трассы через `step` м.
func _worst_from_camera(s: RideScene, step: float) -> Dictionary:
	var track: Track = s.track
	var n: int = int(ceil(track.length_m() / step))
	var sample := TrackSample.new()
	var worst: int = 0
	var at: float = 0.0
	var problems: Array[String] = []
	for i in n:
		track.sample_into(float(i) * step, sample)
		var eye: Vector3 = sample.position - sample.forward * CAM_BACK_M + Vector3.UP * CAM_UP_M
		var seen: int = _visible_from(s, eye, problems)
		if seen > worst:
			worst = seen
			at = float(i) * step
	return {"worst": worst, "at": at, "problems": problems}


func _total_instances(root: Node) -> int:
	var n: int = 0
	for mmi in _multimeshes(root):
		if mmi.multimesh != null:
			n += mmi.multimesh.instance_count
	return n


func _vegetation_types(root: Node) -> int:
	var names: Dictionary = {}
	for mmi in _multimeshes(root):
		if mmi.multimesh != null and mmi.multimesh.instance_count > 0:
			var base: String = String(mmi.name).get_slice("_", 0)
			names[base] = true
	names.erase("Props")
	return names.size()


# ---------------------------------------------------------------------------
# Бюджет в документе
# ---------------------------------------------------------------------------

func test_req_d3d_08_c6_budget_doc_has_visible_row_equal_to_constant() -> void:
	assert_eq(_visible_budget(), 2000, "строка «Видимых экземпляров MultiMesh» = 2000")
	assert_eq(_visible_budget(), PerfBudget.MAX_VISIBLE_MULTIMESH_INSTANCES, "документ = константа")
	assert_eq(_doc_row("MeshInstance3D"), PerfBudget.MAX_MESH_INSTANCES)
	assert_eq(_doc_row("материалов"), PerfBudget.MAX_MATERIALS)


# ---------------------------------------------------------------------------
# D3D-08 крит. 6 — видимо из любой точки трассы, шаг 50 м
# ---------------------------------------------------------------------------

func test_req_d3d_08_c6_visible_every_50m_on_20km_loop_perfbudget_and_own_count() -> void:
	var budget: int = _visible_budget()
	var by_lib: int = PerfBudget.max_visible_along([_long], _long.track, STEP_M)
	assert_lte(by_lib, budget, "20 км: max_visible_along(50 м) = %d" % by_lib)
	var own := _worst_from_camera(_long, STEP_M)
	assert_lte(int(own["worst"]), budget, "20 км: из камеры видно %d (s = %.0f м)" % [own["worst"], own["at"]])
	assert_eq(own["problems"], [] as Array[String], "куски с дальностью без custom_aabb: %s" % str(own["problems"]))
	assert_gt(int(own["worst"]), 500, "мир не пустой")
	assert_gt(_total_instances(_long), budget, "на 20 км всего больше, чем видно (куски работают)")


func test_req_d3d_08_c6_visible_every_50m_on_out_and_back_20km() -> void:
	var budget: int = _visible_budget()
	assert_between(_shuttle.track.length_m(), 19000.0, 21000.0)
	var by_lib: int = PerfBudget.max_visible_along([_shuttle], _shuttle.track, STEP_M)
	var own := _worst_from_camera(_shuttle, STEP_M)
	assert_lte(by_lib, budget, "туда-обратно: max_visible_along(50 м) = %d" % by_lib)
	assert_lte(int(own["worst"]), budget, "туда-обратно: из камеры видно %d (s = %.0f м)" % [own["worst"], own["at"]])
	assert_gte(_vegetation_types(_shuttle), 3, "растительность осталась")


## Стресс вне трасс T-066 (сложенная трасса, как серпантин гор T-070/T-087). Критерий — из
## точки трассы (и из камеры), без запаса `PerfBudget.EYE_SLACK_M`: запас 10 м — внутренняя
## методика строителя, не часть D3D-08 крит. 6 (с ним здесь 2058 > 2000 — риск, см. отчёт).
func test_req_d3d_08_c6_visible_every_50m_on_folded_serpentine_22km() -> void:
	var budget: int = _visible_budget()
	assert_false(PerfBudget.is_compact(_zigzag.track), "змейка — длинная трасса")
	var by_lib: int = 0
	var sample := TrackSample.new()
	for i in int(ceil(_zigzag.track.length_m() / STEP_M)):
		_zigzag.track.sample_into(float(i) * STEP_M, sample)
		by_lib = maxi(by_lib, PerfBudget.visible_multimesh_instances(_zigzag, sample.position, 0.0))
	var own := _worst_from_camera(_zigzag, STEP_M)
	assert_lte(by_lib, budget, "змейка: из точек трассы через 50 м видно %d" % by_lib)
	assert_lte(int(own["worst"]), budget, "змейка: из камеры видно %d (s = %.0f м)" % [own["worst"], own["at"]])
	assert_gte(_vegetation_types(_zigzag), 3, "растительность осталась")


func test_req_d3d_08_c6_visible_while_riding_20km_from_real_camera() -> void:
	var budget: int = _visible_budget()
	_long.apply_telemetry(200, true, 90, true, 40.0, true)
	var worst: int = 0
	var problems: Array[String] = []
	for k in 40:
		_long.distance_m = float(k) * 500.0 + 37.0
		for i in 20:
			_long.advance(FRAME)
		worst = maxi(worst, _visible_from(_long, _long.camera().global_position, problems))
	assert_lte(worst, budget, "из Camera3D на 40 точках видно %d" % worst)


# ---------------------------------------------------------------------------
# Регрессия D3D-07 крит. 1 / D3D-05 крит. 4 — бюджет на 2 и 20 км
# ---------------------------------------------------------------------------

func test_req_d3d_07_c1_compact_loop_total_within_visible_budget() -> void:
	# Компактный мир виден целиком: «видимо» = «всего», значит всего ≤ 2000.
	var budget: int = _visible_budget()
	assert_true(PerfBudget.is_compact(_short.track))
	var total: int = _total_instances(_short)
	assert_lte(total, budget, "петля 2 км: экземпляров MultiMesh всего %d" % total)
	assert_lte(PerfBudget.max_visible_along([_short], _short.track, STEP_M), budget)
	assert_gte(_vegetation_types(_short), 3, "не меньше трёх типов растительности")
	assert_not_null(_short.props(), "сигнальные столбики")


func test_req_d3d_07_c1_other_track_shapes_keep_visible_budget() -> void:
	var budget: int = _visible_budget()
	var shapes: Dictionary = {
		"петля 1.2 км (ломаная)": _stadium(400.0, 60.0),
		"прямая 8 км": PolylineTrack.new(PackedVector3Array([Vector3.ZERO, Vector3(4800, 0, 6400)]), false),
		"прямая 60 км": PolylineTrack.new(PackedVector3Array([Vector3.ZERO, Vector3(36000, 0, 48000)]), false),
	}
	for label in shapes:
		var s := _make(shapes[label])
		var own := _worst_from_camera(s, 100.0 if s.track.length_m() > 30000.0 else STEP_M)
		assert_lte(int(own["worst"]), budget, "%s: видно %d" % [label, own["worst"]])
		assert_gte(_vegetation_types(s), 3, "%s: ≥ 3 типов растительности" % label)
		assert_not_null(s.props(), "%s: столбики" % label)
		s.free()


func test_req_d3d_05_c4_meshes_materials_lights_on_20km() -> void:
	for s in [_short, _long, _shuttle, _zigzag]:
		var meshes: int = 0
		var lights: int = 0
		var mats: Dictionary = {}
		for n in s.find_children("*", "", true, false):
			if n is Light3D:
				lights += 1
			if n is GeometryInstance3D and (n as GeometryInstance3D).material_override != null:
				mats[(n as GeometryInstance3D).material_override.get_instance_id()] = true
			if n is MeshInstance3D:
				meshes += 1
				var mi := n as MeshInstance3D
				if mi.mesh != null:
					for i in mi.mesh.get_surface_count():
						var m: Material = mi.get_active_material(i)
						if m != null:
							mats[m.get_instance_id()] = true
			elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh.mesh != null:
				var mesh: Mesh = (n as MultiMeshInstance3D).multimesh.mesh
				for i in mesh.get_surface_count():
					if mesh.surface_get_material(i) != null:
						mats[mesh.surface_get_material(i).get_instance_id()] = true
		var label: String = "%.1f км" % (s.track.length_m() / 1000.0)
		assert_lte(meshes, _doc_row("MeshInstance3D"), "%s: MeshInstance3D %d" % [label, meshes])
		assert_lte(mats.size(), _doc_row("материалов"), "%s: материалов %d" % [label, mats.size()])
		assert_lte(lights, _doc_row("Light3D"), "%s: Light3D %d" % [label, lights])


# ---------------------------------------------------------------------------
# Рельеф не выше полотна (по треугольникам меша)
# ---------------------------------------------------------------------------

## Треугольники всех кусков рельефа в мировых координатах, отобранные по клеткам запросов.
func _terrain_triangles(s: RideScene, cells: Dictionary, cell_m: float) -> Dictionary:
	var grid: Dictionary = {}
	var tris := PackedVector3Array()
	var roots: Array[MeshInstance3D] = []
	for n in s.world_nodes():
		if n.name == "Terrain":
			roots.append(n as MeshInstance3D)
			for c in n.get_children():
				if c is MeshInstance3D:
					roots.append(c as MeshInstance3D)
	for mi in roots:
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
				var x0: int = floori(minf(a.x, minf(b.x, c.x)) / cell_m)
				var x1: int = floori(maxf(a.x, maxf(b.x, c.x)) / cell_m)
				var z0: int = floori(minf(a.z, minf(b.z, c.z)) / cell_m)
				var z1: int = floori(maxf(a.z, maxf(b.z, c.z)) / cell_m)
				var ti: int = -1
				for cx in range(x0, x1 + 1):
					for cz in range(z0, z1 + 1):
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


## Высота меша рельефа в точке (максимум по накрывающим треугольникам) или NAN.
func _terrain_y(mesh: Dictionary, p: Vector3, cell_m: float) -> float:
	var key := Vector2i(floori(p.x / cell_m), floori(p.z / cell_m))
	var grid: Dictionary = mesh["grid"]
	if not grid.has(key):
		return NAN
	var tris: PackedVector3Array = mesh["tris"]
	var best: float = NAN
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
		var y: float = l1 * a.y + l2 * b.y + l3 * c.y
		best = y if is_nan(best) else maxf(best, y)
	return best


func _terrain_above_road(s: RideScene, step: float) -> Dictionary:
	var env: EnvironmentSet = s.environment_set
	var cell_m: float = 16.0
	var queries: Array = []
	var cells: Dictionary = {}
	var sample := TrackSample.new()
	var n: int = int(s.track.length_m() / step)
	for i in n:
		s.track.sample_into(float(i) * step, sample)
		var right: Vector3 = sample.right()
		var axis: Vector3 = sample.position + right * env.road_center_offset_m
		var k: float = -env.road_width_m * 0.5
		while k <= env.road_width_m * 0.5 + 1e-6:
			var p: Vector3 = axis + right * k
			queries.append([float(i) * step, k, p])
			cells[Vector2i(floori(p.x / cell_m), floori(p.z / cell_m))] = true
			k += 0.5
	var mesh := _terrain_triangles(s, cells, cell_m)
	var above: Array[String] = []
	var covered: int = 0
	for q in queries:
		var p: Vector3 = q[2]
		var y: float = _terrain_y(mesh, p, cell_m)
		if is_nan(y):
			continue
		covered += 1
		if y > p.y + 0.001 and above.size() < 8:
			above.append("s=%.0f off=%+.1f: рельеф на %+.3f м выше полотна" % [q[0], q[1], y - p.y])
	return {"above": above, "covered": covered, "total": queries.size()}


func test_req_d3d_07_c1_terrain_mesh_not_above_road_within_width_20km_every_10m() -> void:
	var r := _terrain_above_road(_long, 10.0)
	assert_gt(int(r["covered"]), int(r["total"]) / 2, "под дорогой есть меш рельефа (%d из %d точек)" % [r["covered"], r["total"]])
	assert_eq(r["above"], [] as Array[String], "20 км: %s" % str(r["above"]))


func test_req_d3d_07_c1_terrain_mesh_not_above_road_on_2km_and_folded_tracks() -> void:
	for s in [_short, _shuttle, _zigzag]:
		var r := _terrain_above_road(s, 10.0)
		assert_eq(r["above"], [] as Array[String], "%.1f км: %s" % [s.track.length_m() / 1000.0, str(r["above"])])


# ---------------------------------------------------------------------------
# Регрессия D3D-07 крит. 5 — камера на 20 км
# ---------------------------------------------------------------------------

func test_req_d3d_07_c5_camera_distance_constant_on_20km() -> void:
	_long.apply_telemetry(200, true, 90, true, 36.0, true)
	var bad: Array[String] = []
	for k in 10:
		_long.distance_m = float(k) * 2003.0
		for i in 90:
			_long.advance(FRAME)
		var off: Vector3 = _long.camera().global_position - _long.rider_position()
		var horiz: float = Vector2(off.x, off.z).length()
		if absf(horiz - RideScene.CAMERA_BACK_M) > 0.05:
			bad.append("s=%.0f: %.3f м" % [_long.distance_m, horiz])
	assert_eq(bad, [] as Array[String], "горизонтальное расстояние камеры 3.8 ± 0.05 м: %s" % str(bad))
