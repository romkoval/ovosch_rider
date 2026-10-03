extends GutTest
## Длинные трассы (T-066): мир на петле ~20 км — коридорный рельеф кусками с LOD, куски
## MultiMesh вдоль трассы с дальностью видимости, бюджет «видимо с любой точки трассы»
## (REQ-D3D-08 п.6, REQ-D3D-05 п.4 в редакции В-7) и регрессия REQ-D3D-07 п.1–5 на 2 и 20 км.
##
## Позиции экземпляров готовых MultiMesh на headless-сервере недоступны (буфер на
## dummy-RenderingServer), поэтому расстановка проверяется по данным строителей
## (`SceneryBuilder.place`, `RoadsideBuilder.place_posts`), а связь данных со сценой — по
## числу экземпляров и `custom_aabb` каждого куска.

const SCENE: String = "res://src/scene3d/ride_scene.tscn"
const DEFAULT_ENV: String = "res://src/scene3d/default_environment.tres"
const FRAME: float = 1.0 / 60.0
## Петля по умолчанию (`LoopTrack(7)`), растянутая до ~20 км: радиус и число опорных точек.
const LONG_RADIUS_M: float = 2175.0
const LONG_POINTS: int = 24

var _long: RideScene = null
var _short: RideScene = null
var _long_layers: Array[SceneryBuilder.Layer] = []
var _short_layers: Array[SceneryBuilder.Layer] = []


func before_all() -> void:
	_long = _make_scene(_long_track())
	_short = _make_scene(null)
	_long_layers = _placement(_long)
	_short_layers = _placement(_short)


func after_all() -> void:
	for s in [_long, _short]:
		if is_instance_valid(s):
			s.free()


func _long_track() -> LoopTrack:
	return LoopTrack.new(7, LONG_RADIUS_M, 0.25, LONG_POINTS, 3.0)


func _make_scene(track: Track) -> RideScene:
	var s: RideScene = load(SCENE).instantiate()
	s.route_id = ""  # петля LoopTrack, как до T-070 (сцена по умолчанию — на трассе flat)
	s.environment_set = (load(DEFAULT_ENV) as EnvironmentSet).duplicate() as EnvironmentSet
	if track != null:
		s.set_track(track)
	add_child(s)
	return s


## Расстановка растительности с теми же бюджетами, что в `RideScene._build_world`.
func _placement(s: RideScene) -> Array[SceneryBuilder.Layer]:
	var posts_visible: int = 0
	var posts_total: int = 0
	if s.props() != null:
		posts_visible = PerfBudget.max_visible_along([s.props()], s.track)
		posts_total = int(PerfBudget.count(s.props())["multimesh_instances"])
	return SceneryBuilder.place(s.track, s.environment_set, s.terrain(), null,
		PerfBudget.MAX_VISIBLE_MULTIMESH_INSTANCES - posts_visible, PerfBudget.MAX_MULTIMESH_INSTANCES - posts_total)


## Позиции экземпляров, попавших в сцену: растительность и столбики.
func _placed_origins(s: RideScene, layers: Array[SceneryBuilder.Layer]) -> PackedVector3Array:
	var out := PackedVector3Array()
	for layer in layers:
		for i in layer.kept():
			out.append(layer.xf[i].origin)
	var posts: Dictionary = RoadsideBuilder.place_posts(s.track, s.environment_set)
	for t in (posts["xf"] as Array[Transform3D]):
		out.append(t.origin)
	return out


func _env_root(s: RideScene) -> Node3D:
	return s.get_node("%EnvironmentRoot") as Node3D


## Все `MultiMeshInstance3D` под узлом (включая куски-дети).
func _multimeshes(root: Node) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	for n in root.find_children("*", "MultiMeshInstance3D", true, false):
		out.append(n as MultiMeshInstance3D)
	return out


func _world_node(s: RideScene, node_name: String) -> Node:
	for n in s.world_nodes():
		if n.name == node_name:
			return n
	return null


func _terrain_chunks(s: RideScene) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var root: Node = _world_node(s, "Terrain")
	if root != null:
		out.append(root as MeshInstance3D)
		for c in root.get_children():
			out.append(c as MeshInstance3D)
	return out


## Экземпляры растительности в радиусе `r` от точки (по горизонтали).
func _vegetation_near(layers: Array[SceneryBuilder.Layer], p: Vector3, r: float) -> int:
	var n: int = 0
	for layer in layers:
		for i in layer.kept():
			var o: Vector3 = layer.xf[i].origin
			if Vector2(o.x - p.x, o.z - p.z).length() <= r:
				n += 1
	return n


## Точки оси трассы с шагом `step` (для расстояния до трассы).
func _axis_points(track: Track, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n: int = int(ceil(track.length_m() / step))
	for i in n + 1:
		out.append(track.sample(minf(float(i) * step, track.length_m())).position)
	return out


func _distance_to(points: PackedVector3Array, p: Vector3) -> float:
	var best: float = INF
	for q in points:
		best = minf(best, Vector2(p.x - q.x, p.z - q.z).length())
	return best


# ---------------------------------------------------------------------------
# Бюджет «видимо с любой точки трассы»
# ---------------------------------------------------------------------------

func test_long_loop_is_about_20_km() -> void:
	assert_between(_long.track.length_m(), 19500.0, 20500.0, "петля %.0f м" % _long.track.length_m())
	assert_false(PerfBudget.is_compact(_long.track), "20 км — не компактная трасса")
	assert_true(PerfBudget.is_compact(_short.track), "петля по умолчанию компактна")


func test_visible_multimesh_from_any_point_every_50m_within_budget_on_2_and_20_km() -> void:
	for s in [_short, _long]:
		var worst: int = PerfBudget.max_visible_along([s], s.track, 50.0)
		assert_gt(worst, 500, "мир не пустой: видно %d" % worst)
		assert_lte(worst, PerfBudget.MAX_VISIBLE_MULTIMESH_INSTANCES,
			"%.0f км: видимых экземпляров MultiMesh %d" % [s.track.length_m() / 1000.0, worst])


func test_visible_count_from_camera_within_budget_while_riding_20_km() -> void:
	_long.apply_telemetry(0, false, 90, true, 40.0, true)
	var worst: int = 0
	for stop in 20:
		_long.distance_m = float(stop) * 1000.0
		for i in 30:
			_long.advance(FRAME)
		worst = maxi(worst, PerfBudget.visible_multimesh_instances(_long, _long.camera().global_position))
	assert_lte(worst, PerfBudget.MAX_VISIBLE_MULTIMESH_INSTANCES, "из камеры видно %d" % worst)


func test_long_route_objects_split_into_chunks_with_visibility_range() -> void:
	var chunk_m: float = PerfBudget.chunk_length_m(_long.track)
	assert_almost_eq(chunk_m, PerfBudget.CHUNK_LENGTH_M, 1e-3, "кусок ~500 м")
	var chunks: int = 0
	var bad: Array[String] = []
	for mmi in _multimeshes(_env_root(_long)):
		var mm := mmi.multimesh
		if mm.instance_count == 0:
			continue
		chunks += 1
		if mmi.visibility_range_end <= 0.0:
			bad.append("%s: нет visibility_range_end" % mmi.name)
		var box: AABB = PerfBudget.multimesh_aabb(mm)
		# Кусок ~500 м трассы плюс отступ объектов от дороги — не весь мир.
		if maxf(box.size.x, box.size.z) > chunk_m + 2.0 * (SceneryBuilder.TREE_MAX_OFFSET_M + 50.0):
			bad.append("%s: кусок %s слишком велик" % [mmi.name, str(box.size)])
	assert_gt(chunks, 4 * 30, "кусков с объектами: %d" % chunks)
	assert_eq(bad, [] as Array[String], str(bad.slice(0, 5)))
	var trees: MultiMeshInstance3D = _world_node(_long, "Trees")
	var tufts: MultiMeshInstance3D = _world_node(_long, "Tufts")
	assert_almost_eq(trees.visibility_range_end, PerfBudget.RANGE_TREES_M, 1e-3, "деревья видны ±1.5 км")
	assert_lt(tufts.visibility_range_end, PerfBudget.RANGE_TREES_M, "мелочь — ближе")


func test_scene_chunks_match_placement_and_custom_aabb_holds_instances() -> void:
	var bad: Array[String] = []
	for layer in _long_layers:
		var root: MultiMeshInstance3D = _world_node(_long, layer.name)
		assert_not_null(root, layer.name)
		if root == null:
			continue
		var per_chunk: Dictionary = {}
		for i in layer.kept():
			var k: int = layer.chunk[i]
			if not per_chunk.has(k):
				per_chunk[k] = PackedVector3Array()
			var arr: PackedVector3Array = per_chunk[k]
			arr.append(layer.xf[i].origin)
			per_chunk[k] = arr
		for k in per_chunk:
			var node: MultiMeshInstance3D = root if k == 0 else root.get_node_or_null("%s_%02d" % [layer.name, k])
			if node == null:
				bad.append("%s: нет куска %d" % [layer.name, k])
				continue
			var pts: PackedVector3Array = per_chunk[k]
			if node.multimesh.instance_count != pts.size():
				bad.append("%s#%d: %d экземпляров, расстановка %d" % [layer.name, k, node.multimesh.instance_count, pts.size()])
			var box: AABB = node.multimesh.custom_aabb.grow(0.01)
			for p in pts:
				if not box.has_point(p):
					bad.append("%s#%d: экземпляр вне custom_aabb" % [layer.name, k])
					break
	assert_eq(bad, [] as Array[String], str(bad.slice(0, 5)))


func test_compact_loop_has_no_chunks_and_no_visibility_ranges() -> void:
	for mmi in _multimeshes(_env_root(_short)):
		assert_eq(mmi.visibility_range_end, 0.0, "%s: компактный мир без дальности" % mmi.name)
		assert_eq(mmi.get_child_count(), 0, "%s: без кусков" % mmi.name)
	assert_eq(_terrain_chunks(_short).size(), 1, "рельеф петли — один меш")
	assert_false(_short.terrain().corridor)
	assert_eq(_short.props().multimesh.instance_count,
		int(_short.track.length_m() / _short.environment_set.prop_spacing_m) * 2, "столбики как раньше")


func test_density_per_km_on_20_km_matches_default_loop() -> void:
	var short_total: int = int(PerfBudget.count(_short)["multimesh_instances"])
	var long_total: int = int(PerfBudget.count(_long)["multimesh_instances"])
	var short_per_km: float = float(short_total) / (_short.track.length_m() / 1000.0)
	var long_per_km: float = float(long_total) / (_long.track.length_m() / 1000.0)
	assert_gt(long_per_km, short_per_km * 0.7, "плотность на 20 км %.0f/км против %.0f/км на петле" % [long_per_km, short_per_km])
	assert_lte(long_total, PerfBudget.MAX_MULTIMESH_INSTANCES, "всего на трассе %d" % long_total)
	# Около гонщика объектов примерно столько же, сколько на петле (сумма по 8 точкам).
	var near_short: int = 0
	var near_long: int = 0
	for i in 8:
		near_short += _vegetation_near(_short_layers, _short.track.sample(float(i) * 250.0).position, 150.0)
		near_long += _vegetation_near(_long_layers, _long.track.sample(float(i) * 2500.0).position, 150.0)
	assert_gt(near_short, 100)
	assert_gt(near_long, int(near_short * 0.6), "у дороги на 20 км %d, на петле %d" % [near_long, near_short])


func test_posts_on_20_km_keep_spacing_and_are_chunked() -> void:
	var props := _long.props()
	assert_not_null(props)
	var total: int = int(PerfBudget.count(props)["multimesh_instances"])
	var expected: int = int(_long.track.length_m() / _long.environment_set.prop_spacing_m) * 2
	assert_eq(total, expected, "столбики с шагом prop_spacing по всей трассе")
	assert_gt(props.get_child_count(), 10, "столбики кусками")
	assert_eq((RoadsideBuilder.place_posts(_long.track, _long.environment_set)["xf"] as Array).size(), expected)


# ---------------------------------------------------------------------------
# Рельеф-коридор
# ---------------------------------------------------------------------------

func test_corridor_terrain_chunks_lod_and_mesh_budget() -> void:
	var tf: TerrainField = _long.terrain()
	assert_not_null(tf)
	assert_true(tf.corridor, "рельеф 20 км — коридор")
	assert_lte(tf.cell_m, _short.terrain().cell_m, "ячейка у дороги не крупнее, чем на петле")
	var fine: int = 0
	for st in tf.tile_step:
		fine += 1 if st == 1 else 0
	assert_gt(fine, 0)
	assert_lt(fine, tf.tile_keys.size(), "вдали — крупная ячейка (LOD)")
	var chunks := _terrain_chunks(_long)
	assert_between(chunks.size(), 2, TerrainField.MAX_TERRAIN_CHUNKS)
	for c in chunks:
		assert_gt(c.visibility_range_end, TerrainField.RANGE_M - 1.0, "%s: дальность видимости" % c.name)
		assert_eq(c.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: без тени" % c.name)
	var counts := PerfBudget.count(_long)
	assert_lte(counts["mesh_instances"], PerfBudget.MAX_MESH_INSTANCES, "MeshInstance3D %d" % counts["mesh_instances"])
	assert_lte(counts["materials"], PerfBudget.MAX_MATERIALS)
	assert_eq(counts["lights"], 1)


func test_corridor_terrain_below_road_within_width_every_50m() -> void:
	var env: EnvironmentSet = _long.environment_set
	var tf: TerrainField = _long.terrain()
	var curb_out: float = RoadsideBuilder.curb_outer_m(env.road_width_m)
	var sample := TrackSample.new()
	var above: Array[String] = []
	var n: int = int(_long.track.length_m() / 50.0)
	for i in n:
		_long.track.sample_into(float(i) * 50.0, sample)
		var axis: Vector3 = sample.position + sample.right() * env.road_center_offset_m
		for off in [-curb_out, -env.road_width_m * 0.5, 0.0, env.road_width_m * 0.5, curb_out]:
			var p: Vector3 = axis + sample.right() * float(off)
			var h: float = tf.height_at(p.x, p.z)
			if h > sample.position.y - 0.02:
				above.append("s=%d off=%+.1f: %+.2f м" % [i * 50, float(off), h - sample.position.y])
	assert_eq(above, [] as Array[String], "рельеф не выше полотна: %s" % str(above.slice(0, 5)))


func test_corridor_terrain_has_ground_beside_road_and_hills_far_from_it() -> void:
	var tf: TerrainField = _long.terrain()
	var env: EnvironmentSet = _long.environment_set
	var axis := _axis_points(_long.track, 20.0)
	var sample := TrackSample.new()
	var low: Array[String] = []
	var far_points: int = 0
	for i in 40:
		_long.track.sample_into(float(i) * 500.0, sample)
		for sgn in [-1.0, 1.0]:
			for w in [30.0, 300.0, 600.0]:
				var p: Vector3 = sample.position + sample.right() * float(sgn) * float(w)
				assert_true(tf.tile_index.has(_tile_key(tf, p)), "s=%d: рельеф на %d м от дороги" % [i * 500, int(w)])
			# Холмы горизонта: точка, которая дальше `HILLS_FULL_M` от любой части трассы.
			var e: Vector3 = sample.position + sample.right() * float(sgn) * (TerrainField.CORRIDOR_RADIUS_M - 20.0)
			if _distance_to(axis, e) < TerrainField.HILLS_FULL_M + 20.0:
				continue
			far_points += 1
			var h: float = tf.height_at(e.x, e.z)
			if h < tf.mean_y + env.hills_height_m * 0.25:
				low.append("s=%d: %+.1f м" % [i * 500, h - tf.mean_y])
	assert_gt(far_points, 10)
	assert_eq(low, [] as Array[String], "холмы на краю коридора не ниже 25 %% высоты: %s" % str(low.slice(0, 5)))


func _tile_key(tf: TerrainField, p: Vector3) -> Vector2i:
	var gx: int = int((p.x - tf.origin.x) / tf.cell_m)
	var gz: int = int((p.z - tf.origin.y) / tf.cell_m)
	return Vector2i(gx / TerrainField.TILE_CELLS, gz / TerrainField.TILE_CELLS)


func test_corridor_terrain_has_no_cracks_between_fine_and_coarse_tiles() -> void:
	var tf: TerrainField = _long.terrain()
	var n: int = TerrainField.TILE_CELLS + 1
	var cn: int = TerrainField.TILE_CELLS / TerrainField.COARSE_STEP + 1
	var checked: int = 0
	var cracks: Array[String] = []
	for ti in tf.tile_keys.size():
		if tf.tile_step[ti] != 1:
			continue
		var key: Vector2i = tf.tile_keys[ti]
		var right := key + Vector2i(1, 0)
		if not tf.tile_index.has(right) or tf.tile_step[int(tf.tile_index[right])] == 1:
			continue
		var h: PackedFloat32Array = tf.tile_heights[ti]
		var ch: PackedFloat32Array = tf.tile_heights[int(tf.tile_index[right])]
		for m in n:
			# Крупная плитка справа: её левый столбец; между её вершинами — прямая.
			var expect: float = ch[(m / 2) * cn] if m % 2 == 0 else (ch[(m / 2) * cn] + ch[(m / 2 + 1) * cn]) * 0.5
			var got: float = h[m * n + TerrainField.TILE_CELLS]
			checked += 1
			if absf(got - expect) > 1e-3:
				cracks.append("%s m=%d: %.3f ≠ %.3f" % [str(key), m, got, expect])
	assert_gt(checked, 0, "есть стыки мелкой и крупной плиток")
	assert_eq(cracks, [] as Array[String], str(cracks.slice(0, 5)))


func test_corridor_terrain_shared_edges_between_neighbour_tiles_match() -> void:
	var tf: TerrainField = _long.terrain()
	var bad: int = 0
	var checked: int = 0
	for ti in tf.tile_keys.size():
		var key: Vector2i = tf.tile_keys[ti]
		var up := key + Vector2i(0, 1)
		if not tf.tile_index.has(up) or tf.tile_step[ti] != tf.tile_step[int(tf.tile_index[up])]:
			continue
		var cn: int = TerrainField.TILE_CELLS / tf.tile_step[ti] + 1
		var a: PackedFloat32Array = tf.tile_heights[ti]
		var b: PackedFloat32Array = tf.tile_heights[int(tf.tile_index[up])]
		for i in cn:
			checked += 1
			if absf(a[(cn - 1) * cn + i] - b[i]) > 1e-4:
				bad += 1
	assert_gt(checked, 100)
	assert_eq(bad, 0, "общие вершины соседних плиток совпадают")


# ---------------------------------------------------------------------------
# Регрессия REQ-D3D-07 на 20 км
# ---------------------------------------------------------------------------

func test_vegetation_and_posts_not_on_asphalt_on_20_km() -> void:
	var env: EnvironmentSet = _long.environment_set
	var grid: Dictionary = {}
	var sample := TrackSample.new()
	for i in int(_long.track.length_m()) + 1:
		_long.track.sample_into(float(i), sample)
		var p: Vector3 = sample.position + sample.right() * env.road_center_offset_m
		var key := Vector2i(int(floor(p.x / 10.0)), int(floor(p.z / 10.0)))
		if not grid.has(key):
			grid[key] = PackedVector3Array()
		var arr: PackedVector3Array = grid[key]
		arr.append(p)
		grid[key] = arr
	var half: float = env.road_width_m * 0.5
	var origins := _placed_origins(_long, _long_layers)
	assert_gt(origins.size(), 5000)
	var on_road: Array[String] = []
	for o in origins:
		var best: float = INF
		var kx: int = int(floor(o.x / 10.0))
		var kz: int = int(floor(o.z / 10.0))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var k := Vector2i(kx + dx, kz + dz)
				if grid.has(k):
					for q in (grid[k] as PackedVector3Array):
						best = minf(best, Vector2(o.x - q.x, o.z - q.z).length())
		if best < half:
			on_road.append("%s d=%.2f" % [str(o), best])
	assert_eq(on_road, [] as Array[String], "объекты на асфальте: %s" % str(on_road.slice(0, 5)))


func test_rider_and_camera_follow_20_km_loop() -> void:
	_long.apply_telemetry(0, false, 90, true, 40.0, true)
	for stop in [0.0, 400.0, 900.0, 1500.0, 10000.0, 19900.0]:
		_long.distance_m = stop
		for i in 120:
			_long.advance(FRAME)
		var on_track: Vector3 = _long.track.sample(_long.distance_m).position
		assert_lt(_long.rider_position().distance_to(on_track), 1e-3, "s=%.0f: велосипедист на трассе" % stop)
		var off: Vector3 = _long.camera_offset()
		assert_almost_eq(Vector2(off.x, off.z).length(), RideScene.CAMERA_BACK_M, 0.05, "s=%.0f: дистанция камеры" % stop)
		assert_lte(absf(_long.lean_rad()), RideScene.LEAN_MAX_RAD + 1e-6)
	assert_between(_long.distance_m, 0.0, _long.track.length_m(), "дистанция оборачивается на петле 20 км")


func test_rebuilding_long_world_does_not_accumulate_nodes() -> void:
	var s := _make_scene(null)
	var base: int = _env_root(s).get_child_count()
	s.set_track(_long_track())
	await wait_process_frames(2)
	s.set_track(LoopTrack.new(7))
	await wait_process_frames(2)
	assert_eq(_env_root(s).get_child_count(), base, "после пересборки 20 км → 2 км узлов столько же")
	assert_false(s.terrain().corridor)
	s.free()


func test_budget_doc_lists_visible_and_total_multimesh_rows() -> void:
	var text := FileAccess.get_file_as_string("res://docs/perf_budget.md")
	var visible := RegEx.create_from_string("\\|[^|]*Видимых экземпляров `MultiMesh`[^|]*\\| *(\\d+) *\\|").search(text)
	assert_not_null(visible, "строка бюджета видимых экземпляров")
	if visible != null:
		assert_eq(int(visible.get_string(1)), PerfBudget.MAX_VISIBLE_MULTIMESH_INSTANCES)
	var total := RegEx.create_from_string("\\|[^|]*`MultiMesh` всего на трассе[^|]*\\| *(\\d+) *\\|").search(text)
	assert_not_null(total, "строка потолка «всего на трассе»")
	if total != null:
		assert_eq(int(total.get_string(1)), PerfBudget.MAX_MULTIMESH_INSTANCES)
