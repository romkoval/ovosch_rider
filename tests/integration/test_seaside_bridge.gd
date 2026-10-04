extends GutTest
## Мост приморья (T-090): REQ-D3D-08 п.3 (мост в сцене на участке `bridges` из данных трассы),
## п.6 (мост и вода под ним, бюджет), п.11 (полотно ≥ 10 м над водой, под мостом вода), п.4
## (рельеф не выше полотна, высота велосипедиста по профилю на мосту), D3D-07.5 (камера на мосту).
## Конструкция — `BridgeBuilder`, долина — `TerrainField.carve_bridge_valley`, обочина без травы и
## отбойника — `RoadsideBuilder`, растительность и столбики не на мосту — `SceneryBuilder`.

const SCENE: String = "res://src/scene3d/ride_scene.tscn"
const FRAME: float = 1.0 / 60.0

var _s: RideScene = null
var _b := Vector2.ZERO
var _level: float = 0.0


func before_all() -> void:
	_s = load(SCENE).instantiate()
	_s.route_id = RouteCatalog.SEASIDE
	add_child(_s)
	var def: RouteCatalog.RouteDef = RouteCatalog.get_route(RouteCatalog.SEASIDE)
	_b = def.bridges[0]
	_level = def.water_level_m


func after_all() -> void:
	if is_instance_valid(_s):
		_s.free()


## Кадр в s: центр дороги, горизонтальные «вперёд» и «вправо».
func _center(s: float) -> Vector3:
	var sample := TrackSample.new()
	_s.track.sample_into(s, sample)
	return sample.position + sample.right() * _s.environment_set.road_center_offset_m


func _right(s: float) -> Vector3:
	var r: Vector3 = _s.track.sample(s).right()
	r.y = 0.0
	return r.normalized()


func _fwd(s: float) -> Vector3:
	var f: Vector3 = _s.track.sample(s).forward
	f.y = 0.0
	return f.normalized()


## s точки по прямой моста (мост лежит на прямой, T-070) и боковое смещение от центра дороги.
func _s_lat(p: Vector3) -> Vector2:
	var c0: Vector3 = _center(_b.x)
	var d := Vector3(p.x - c0.x, 0.0, p.z - c0.z)
	return Vector2(_b.x + d.dot(_fwd(_b.x)), d.dot(_right(_b.x)))


func _verts(mesh: Mesh) -> PackedVector3Array:
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _drive_to(at_m: float, kmh: float, frames: int = 120) -> void:
	_s.distance_m = at_m - kmh / 3.6 * FRAME * float(frames)
	_s.apply_telemetry(0, false, 90, true, kmh, true)
	for i in frames:
		_s.advance(FRAME)


func test_bridge_ranges_only_on_seaside() -> void:
	assert_eq(BridgeBuilder.ranges(_s.track).size(), 1, "у приморья один мост")
	for id in [RouteCatalog.FLAT, RouteCatalog.HILLS, RouteCatalog.MOUNTAINS]:
		assert_true(BridgeBuilder.ranges(RouteWorld.track(id)).is_empty(), "%s: мостов нет" % id)
	assert_true(BridgeBuilder.ranges(LoopTrack.new(7)).is_empty(), "процедурная петля: мостов нет")


func test_bridge_node_spans_data_range() -> void:
	assert_eq(_s.bridge_nodes().size(), 1, "узел моста (D3D-08 п.3)")
	assert_eq(_s.bridges_placed().size(), 1)
	var root: MultiMeshInstance3D = _s.bridge_nodes()[0]
	assert_true(_s.world_nodes().has(root), "мост — узел мира трассы")
	assert_gte(root.visibility_range_end, 1000.0, "мост виден с подъезда издали")
	var pl: LandmarkBuilder.Placed = _s.bridges_placed()[0]
	var body: LandmarkBuilder.Part = pl.parts.filter(func(p: LandmarkBuilder.Part) -> bool: return p.name == "bridge")[0]
	var lo: float = INF
	var hi: float = -INF
	for v in _verts(body.mesh):
		var sl: Vector2 = _s_lat(v)
		if absf(sl.y) < 3.0:
			lo = minf(lo, sl.x)
			hi = maxf(hi, sl.x)
	assert_lte(lo, _b.x + 1.0, "конструкция с начала участка моста (%.0f)" % lo)
	assert_gte(hi, _b.y - 1.0, "конструкция до конца участка моста (%.0f)" % hi)
	assert_lte(hi - lo, _b.y - _b.x + 2.0 * (BridgeBuilder.ABUT_BACK_M + 1.0), "не длиннее участка с устоями")


func test_deck_at_least_10m_above_water_on_whole_bridge() -> void:
	var worst: float = INF
	var at: float = _b.x
	while at <= _b.y:
		worst = minf(worst, _s.track.sample(at).position.y - _level)
		at += 5.0
	assert_gte(worst, 10.0, "полотно над водой не ниже 10 м на всём мосту (D3D-08 п.11): %.1f" % worst)


func test_water_under_bridge_and_piers_stand_in_it() -> void:
	var tf: TerrainField = _s.terrain()
	var wet: float = 0.0
	var at: float = _b.x
	while at <= _b.y:
		var c: Vector3 = _center(at)
		if tf.water_depth_at(c.x, c.z) > 0.5:
			wet += 5.0
		at += 5.0
	assert_gt(wet, 150.0, "под мостом вода на %.0f м пролёта (D3D-08 п.11)" % wet)
	var water: MeshInstance3D = _s.water()
	var mid: Vector3 = _center((_b.x + _b.y) * 0.5)
	assert_true(water.get_aabb().has_point(Vector3(mid.x, _level, mid.z)), "водная поверхность под серединой моста")
	var piers: PackedFloat64Array = BridgeBuilder.pier_distances(_b)
	assert_eq(piers.size(), 3, "три опоры (tracks.md п. 4.4)")
	for p in piers:
		var c: Vector3 = _center(p)
		assert_gt(tf.water_depth_at(c.x, c.z), 1.0, "опора в s=%.0f — в воде" % p)
	var lake_ok: bool = tf.river_crossing_s > _b.x and tf.river_crossing_s < _b.y
	assert_true(lake_ok, "река проходит под мостом")


func test_terrain_below_girder_under_deck_and_never_above_road() -> void:
	var tf: TerrainField = _s.terrain()
	var half: float = BridgeBuilder.deck_half_m(_s.environment_set.road_width_m)
	var bad: Array[String] = []
	var at: float = _b.x
	while at <= _b.y:
		var c: Vector3 = _center(at)
		var r: Vector3 = _right(at)
		var road_y: float = _s.track.sample(at).position.y
		var bottom: float = BridgeBuilder.girder_bottom_y(_s.track, _b, at)
		var inner: bool = at >= _b.x + BridgeBuilder.ABUT_IN_M + 1.0 and at <= _b.y - BridgeBuilder.ABUT_IN_M - 1.0
		for k in 9:
			var p: Vector3 = c + r * lerpf(-half, half, float(k) / 8.0)
			var g: float = tf.height_at(p.x, p.z)
			if g > road_y - 0.4:
				bad.append("s=%.0f: рельеф %.1f выше полотна %.1f" % [at, g, road_y])
			elif inner and g > bottom - 0.3:
				bad.append("s=%.0f: рельеф %.1f у низа балки %.1f" % [at, g, bottom])
		at += 5.0
	assert_eq(bad, [] as Array[String], str(bad.slice(0, 6)))


func test_piers_reach_from_ground_to_girder() -> void:
	var tf: TerrainField = _s.terrain()
	var body: Mesh = _s.bridges_placed()[0].parts[0].mesh
	for p in BridgeBuilder.pier_distances(_b):
		var c: Vector3 = _center(p)
		var low: float = INF
		var high: float = -INF
		for v in _verts(body):
			if Vector2(v.x - c.x, v.z - c.z).length() < BridgeBuilder.PIER_TOP.x + 0.1:
				low = minf(low, v.y)
				high = maxf(high, v.y)
		assert_lte(low, tf.height_at(c.x, c.z), "опора s=%.0f стоит на дне" % p)
		assert_gte(high, BridgeBuilder.girder_bottom_y(_s.track, _b, p), "опора s=%.0f доходит до балки" % p)


func test_railings_on_both_edges_and_lamps_every_40m() -> void:
	var pl: LandmarkBuilder.Placed = _s.bridges_placed()[0]
	var rails: Array = pl.parts.filter(func(p: LandmarkBuilder.Part) -> bool: return p.name == BridgeBuilder.RAILINGS)
	assert_eq(rails.size(), 1, "перила")
	var sides := {-1: Vector2(INF, -INF), 1: Vector2(INF, -INF)}
	for v in _verts((rails[0] as LandmarkBuilder.Part).mesh):
		var sl: Vector2 = _s_lat(v)
		var k: int = 1 if sl.y > 0.0 else -1
		var cur: Vector2 = sides[k]
		sides[k] = Vector2(minf(cur.x, sl.x), maxf(cur.y, sl.x))
		var top: float = v.y - _s.track.sample(clampf(sl.x, _b.x, _b.y)).position.y
		assert_lte(top, RoadsideBuilder.CURB_H_M + BridgeBuilder.RAIL_H_M + 0.1, "перила не выше 1.3 м")
	for k in sides:
		var span: Vector2 = sides[k]
		assert_lte(span.x, _b.x + 1.0, "перила %s с начала моста" % ("справа" if k > 0 else "слева"))
		assert_gte(span.y, _b.y - 1.0, "перила %s до конца моста" % ("справа" if k > 0 else "слева"))
	var lamps: Array = pl.parts.filter(func(p: LandmarkBuilder.Part) -> bool: return p.name == "bridge_lamps")
	assert_eq(lamps.size(), 1)
	var per_side: int = int((_b.y - _b.x - BridgeBuilder.LAMP_FIRST_M * 1.5) / BridgeBuilder.LAMP_STEP_M) + 1
	assert_eq((lamps[0] as LandmarkBuilder.Part).xf.size(), per_side * 2, "фонари через 40 м по обеим сторонам")
	var names: Array[String] = []
	for n in _s.bridge_nodes()[0].get_children():
		names.append(String(n.name))
	assert_true(names.has(BridgeBuilder.RAILINGS) and names.has("bridge_lamps"), str(names))


func test_no_verge_guardrail_or_posts_on_bridge() -> void:
	var curb_out: float = RoadsideBuilder.curb_outer_m(_s.environment_set.road_width_m)
	for name in ["Verge", "Roadside"]:
		var hits: int = 0
		for root in _s.world_nodes().filter(func(n: Node) -> bool: return n.name == name):
			for mi: MeshInstance3D in [root] + Array(root.get_children()):
				var arrays: Array = mi.mesh.surface_get_arrays(0)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				for t in range(0, idx.size(), 3):
					var c: Vector3 = (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
					var sl: Vector2 = _s_lat(c)
					if sl.x > _b.x + 1.0 and sl.x < _b.y - 1.0 and absf(sl.y) < 60.0:
						if name == "Verge" or absf(sl.y) > curb_out + 0.05:
							hits += 1
		assert_eq(hits, 0, "%s: на мосту только кромка и бордюр (без травы и отбойника)" % name)
	var posts: Array[Transform3D] = RoadsideBuilder.place_posts(_s.track, _s.environment_set)["xf"]
	var on: int = 0
	for t in posts:
		var sl: Vector2 = _s_lat(t.origin)
		if sl.x > _b.x and sl.x < _b.y and absf(sl.y) < 10.0:
			on += 1
	assert_eq(on, 0, "сигнальных столбиков на мосту нет")


func test_vegetation_not_on_or_under_deck() -> void:
	var layers := SceneryBuilder.place(_s.track, _s.environment_set, _s.terrain(), null, PerfBudget.MAX_VISIBLE_MULTIMESH_INSTANCES,
		PerfBudget.MAX_MULTIMESH_INSTANCES, LandmarkBuilder.keep_out(_s.bridges_placed()))
	var half: float = BridgeBuilder.deck_half_m(_s.environment_set.road_width_m)
	var bad: Array[String] = []
	for layer in layers:
		for t in layer.xf:
			var sl: Vector2 = _s_lat(t.origin)
			if sl.x < _b.x - 2.0 or sl.x > _b.y + 2.0:
				continue
			var reach: float = 1.5 if layer.name == "Tufts" else 6.0
			if absf(sl.y) < half + reach:
				bad.append("%s s=%.0f lat=%.1f" % [layer.name, sl.x, sl.y])
	assert_eq(bad, [] as Array[String], str(bad.slice(0, 6)))


func test_rider_and_camera_follow_profile_on_bridge() -> void:
	for at in [_b.x + 10.0, (_b.x + _b.y) * 0.5, _b.y - 10.0]:
		_drive_to(at, 32.0)
		var want: Vector3 = _s.track.sample(_s.distance_m).position
		assert_almost_eq(_s.rider_position().y, want.y, 0.05, "высота велосипедиста = h(s) на мосту (s=%.0f)" % at)
		var off: Vector3 = _s.camera_offset()
		assert_almost_eq(Vector2(off.x, off.z).length(), RideScene.CAMERA_BACK_M, 0.05, "камера позади на 3.8 м (D3D-07.5)")
		assert_almost_eq(off.y, RideScene.CAMERA_UP_M, 0.05)


func test_bridge_visible_from_approach() -> void:
	# `tracks.md` п. 4.4: мост виден за 300–400 м до въезда — порталы на устое в кадре и в дальности.
	_drive_to(_b.x - 350.0, 32.0)
	var cam: Camera3D = _s.camera()
	var root: MultiMeshInstance3D = _s.bridge_nodes()[0]
	var center: Vector3 = root.global_transform * PerfBudget.multimesh_aabb(root.multimesh).get_center()
	assert_lte(cam.global_position.distance_to(center), root.visibility_range_end, "мост в дальности видимости")
	var c: Vector3 = _center(_b.x + BridgeBuilder.PORTAL_AT_M)
	var w: float = BridgeBuilder.deck_half_m(_s.environment_set.road_width_m) + BridgeBuilder.PORTAL_OUT_M
	for sgn in [-1.0, 1.0]:
		var top: Vector3 = c + _right(_b.x) * sgn * w + Vector3.UP * BridgeBuilder.PORTAL_H_M
		var local: Vector3 = cam.global_transform.affine_inverse() * top
		assert_lt(local.z, 0.0, "портал впереди")
		var ty: float = tan(deg_to_rad(cam.fov) * 0.5)
		assert_lte(absf(local.x / -local.z), ty * 16.0 / 9.0, "портал в кадре по горизонтали")
		assert_lte(absf(local.y / -local.z), ty, "портал в кадре по вертикали")


func test_budget_with_bridge() -> void:
	var c := PerfBudget.count(_s)
	assert_lte(int(c["mesh_instances"]), PerfBudget.MAX_MESH_INSTANCES)
	assert_lte(int(c["materials"]), PerfBudget.MAX_MATERIALS)
	assert_lte(int(c["lights"]), PerfBudget.MAX_LIGHTS)
	var visible: int = PerfBudget.max_visible_along([_s], _s.track)
	assert_lte(visible, PerfBudget.MAX_VISIBLE_MULTIMESH_INSTANCES)
	var bridge: int = int(PerfBudget.count(_s.bridge_nodes()[0])["multimesh_instances"])
	gut.p("seaside с мостом: MeshInstance3D %d, материалов %d, свет %d, видно ≤ %d, экземпляров моста %d" % [
		c["mesh_instances"], c["materials"], c["lights"], visible, bridge])
	assert_lt(bridge, 40, "мост — несколько экземпляров (конструкция, перила, фонари)")
