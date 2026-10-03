class_name LandmarkBuilder
extends RefCounted
## Ориентиры трассы в мире (T-083, REQ-D3D-08 п.12; `docs/game/tracks.md` п. 4.5, 5): по списку
## `RouteCatalog.Landmark` (s, тип, сторона, план) строит составные меши `PropMeshes` —
## по `MultiMeshInstance3D` на часть ориентира (повторяющиеся части — экземплярами: ветряки,
## дома, стога, овцы, звенья изгороди). `MeshInstance3D` не создаются — бюджет узлов
## (`PerfBudget.MAX_MESH_INSTANCES`) не растёт; экземпляры входят в бюджет видимых MultiMesh.
##
## Расстановка: сторона `left`/`right` — по ходу движения; `road` — на дороге (мостик,
## парапеты, ручей под полотном); план — удаление от оси дороги: у дороги ~20–60 м, средний
## ~100–250 м, дальний ~400–650 м (в пределах рельефа-коридора). Ориентир ставится немного
## впереди своей точки s по курсу дороги в s (`lead`), чтобы на снимке у его s он был в кадре
## (`tracks.md` п. 8: «ветряки на 1900 м», «деревня на 4200 м»); ближайшее к дороге место —
## рядом с s. Если место занято другой частью трассы (петля возвращается), пробуются другие
## удаления и упреждения. Дальность видимости — по плану (`RANGE_*`): у дороги ориентир
## появляется за ~800 м, средний и дальний — за 1.5–2.6 км; одновременно в кадре 2–3.
##
## Вращение лопастей и дрейф шара — в шейдере (`prop_anim.gdshader`, данные экземпляра), без
## кода в кадре. Всё строится один раз в `RideScene.set_track()`, детерминированно по seed.

const ANIM_MATERIAL: String = "res://src/scene3d/props/materials/prop_anim.tres"
## Дальность видимости частей ориентира по плану, м (до центра AABB части).
const RANGE_NEAR_M: float = 800.0
const RANGE_MID_M: float = 1500.0
const RANGE_FAR_M: float = 2600.0
## Удаление от оси дороги (x) и упреждение по курсу (y) по плану, м.
const PLACE_NEAR := Vector2(28.0, 60.0)
const PLACE_MID := Vector2(125.0, 260.0)
const PLACE_FAR := Vector2(420.0, 800.0)
## Удаление и упреждение для отдельных типов (крупные постройки — дальше от дороги).
const TYPE_PLACE: Dictionary = {
	"water_tower": Vector2(42.0, 95.0),
	"village": Vector2(105.0, 290.0),
	"grain_elevator": Vector2(140.0, 330.0),
	"farm_silo": Vector2(42.0, 85.0),
	"sunflower_field": Vector2(34.0, 75.0),
	"chapel": Vector2(36.0, 75.0),
	"tv_tower": Vector2(42.0, 120.0),
	"lone_tree_bench": Vector2(20.0, 45.0),
}
## Ближе этого к оси трассы части ориентира (кроме ориентиров на дороге) не ставятся, м.
const MIN_CLEARANCE_M: float = 16.0
## Дальше этого от трассы — нет рельефа (коридор `TerrainField.CORRIDOR_RADIUS_M`).
const MAX_FROM_TRACK_M: float = 640.0
## Шаг точек трассы для проверки расстояния, м.
const TRACK_PROBE_M: float = 10.0
## Варианты (масштаб удаления, масштаб упреждения), если место занято.
const TRIES: Array[Vector2] = [
	Vector2(1.0, 1.0), Vector2(1.0, 0.7), Vector2(1.35, 1.0), Vector2(0.75, 0.6), Vector2(1.6, 1.3), Vector2(0.6, 1.4),
]


## Часть ориентира: меш и экземпляры (цвет экземпляра — sRGB, данные анимации — `custom`).
## `world_space` — меш построен в мировых координатах (ручей, озеро; один экземпляр без
## смещения); без меша — только «пятно» для растительности.
class Part:
	var name: String
	var mesh: Mesh
	var animated: bool = false
	var world_space: bool = false
	## Радиус «пятна» экземпляра на земле, м (растительность туда не ставится).
	var footprint_m: float = 0.0
	var xf: Array[Transform3D] = []
	var col: Array[Color] = []
	var custom: Array[Color] = []

	func _init(part_name: String, part_mesh: Mesh, footprint: float, anim: bool) -> void:
		name = part_name
		mesh = part_mesh
		footprint_m = footprint
		animated = anim

	func add(t: Transform3D, c: Color = Color.WHITE, data: Color = Color(0, 0, 0, 0)) -> void:
		xf.append(t)
		col.append(c)
		custom.append(data)


## Расставленный ориентир: данные каталога, точка привязки (на земле) и части.
class Placed:
	var type: String = ""
	var s_m: float = 0.0
	var side: String = ""
	var plane: String = ""
	var anchor := Vector3.ZERO
	var range_m: float = RANGE_NEAR_M
	var parts: Array[Part] = []
	## Котловины под воду для рельефа (`TerrainField.carve_basin`): центр, ось, полуоси, уровень.
	var basins: Array[Basin] = []

	## Позиции экземпляров видимых частей (без мешей в мировых координатах и пятен).
	func origins() -> PackedVector3Array:
		var out := PackedVector3Array()
		for p in parts:
			if p.mesh == null or p.world_space:
				continue
			for t in p.xf:
				out.append(t.origin)
		return out

	## Экземпляров MultiMesh (части с мешем).
	func instance_count() -> int:
		var n: int = 0
		for p in parts:
			if p.mesh != null:
				n += p.xf.size()
		return n


## Котловина под воду (озеро ориентира): рельеф опускается до построения меша.
class Basin:
	var center := Vector3.ZERO
	var axis := Vector3.FORWARD
	var radii := Vector2.ONE
	var level: float = 0.0


## Опустить рельеф под водой ориентиров (до `TerrainField.build_mesh`).
static func carve(placed: Array[Placed], field: TerrainField) -> void:
	if field == null:
		return
	for pl in placed:
		for b in pl.basins:
			field.carve_basin(b.center, b.axis, b.radii, b.level)


## Пятна, куда растительность не ставится: (x, z, радиус) по сетке 64 м.
class KeepOut:
	const CELL_M: float = 64.0
	var _cells: Dictionary = {}

	func add(x: float, z: float, r: float) -> void:
		if r <= 0.0:
			return
		var c0 := Vector2i(floori((x - r) / CELL_M), floori((z - r) / CELL_M))
		var c1 := Vector2i(floori((x + r) / CELL_M), floori((z + r) / CELL_M))
		for cz in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				var key := Vector2i(cx, cz)
				var list: PackedVector3Array = _cells.get(key, PackedVector3Array())
				list.append(Vector3(x, z, r))
				_cells[key] = list

	func blocks(x: float, z: float, pad: float = 0.0) -> bool:
		var key := Vector2i(floori(x / CELL_M), floori(z / CELL_M))
		if not _cells.has(key):
			return false
		for c: Vector3 in _cells[key]:
			var dx: float = x - c.x
			var dz: float = z - c.y
			var rr: float = c.z + pad
			if dx * dx + dz * dz < rr * rr:
				return true
		return false

	func is_empty() -> bool:
		return _cells.is_empty()


## Контекст расстановки одного ориентира: кадр (вперёд по курсу, наружу), высота земли.
class Ctx:
	var track: Track
	var env: EnvironmentSet
	var field: TerrainField
	var material: Material
	var anim_material: Material
	var rng := RandomNumberGenerator.new()
	var placed: Placed
	## Точка ориентира на трассе (s_m): позиция оси и горизонтальные курс и «вправо».
	var at := Vector3.ZERO
	var fwd := Vector3.FORWARD
	var right := Vector3.RIGHT
	## Наружу от дороги (знак стороны × right) и точка привязки.
	var out := Vector3.RIGHT
	var anchor := Vector3.ZERO
	var road_y: float = 0.0
	## Точки трассы через `TRACK_PROBE_M` (расстояние до дороги).
	var probe := PackedVector3Array()
	var _parts: Dictionary = {}

	func ground(p: Vector3) -> float:
		if field == null:
			return road_y - TerrainField.ROAD_SINK_M
		return field.height_at(p.x, p.z)

	## Точка от привязки: `u` — вперёд по курсу, `v` — наружу от дороги.
	func local(u: float, v: float) -> Vector3:
		var p: Vector3 = anchor + fwd * u + out * v
		p.y = ground(p)
		return p

	## Базис «лицом» (+Z) по направлению `face` (горизонталь), с поворотом `yaw` и масштабом.
	func facing(face: Vector3, yaw: float = 0.0, scale: Vector3 = Vector3.ONE) -> Basis:
		var z := Vector3(face.x, 0.0, face.z)
		if z.length_squared() < 1e-6:
			z = -out
		z = z.normalized()
		var x: Vector3 = Vector3.UP.cross(z).normalized()
		return Basis(x, Vector3.UP, z).rotated(Vector3.UP, yaw) * Basis.from_scale(scale)

	func part(key: String, footprint: float, anim: bool = false) -> Part:
		if not _parts.has(key):
			var m: Mesh = PropMeshes.mesh(key, anim_material if anim else material, env.building_wall_color, env.building_roof_color)
			var p := Part.new(key, m, footprint, anim)
			_parts[key] = p
			placed.parts.append(p)
		return _parts[key]

	func part_mesh(key: String, m: Mesh, footprint: float, in_world: bool = false) -> Part:
		if not _parts.has(key):
			var p := Part.new(key, m, footprint, false)
			p.world_space = in_world
			_parts[key] = p
			placed.parts.append(p)
		return _parts[key]

	## Экземпляр части `key` в точке (u, v) от привязки, «лицом» к дороге с поворотом `yaw`.
	func put(key: String, footprint: float, u: float, v: float, yaw: float = 0.0, scale: float = 1.0,
			color: Color = Color.WHITE, dy: float = 0.0) -> Transform3D:
		var p: Vector3 = local(u, v)
		var t := Transform3D(facing(-out, yaw, Vector3.ONE * scale), p + Vector3.UP * dy)
		part(key, footprint).add(t, color)
		return t


## Расставить ориентиры (данные без узлов — для тестов и `build`).
static func place(track: Track, landmarks: Array, env: EnvironmentSet, field: TerrainField,
		material: Material) -> Array[Placed]:
	var out: Array[Placed] = []
	if track == null or landmarks.is_empty():
		return out
	var probe := _track_points(track)
	var anim: Material = load(ANIM_MATERIAL) as Material
	var sample := TrackSample.new()
	for i in landmarks.size():
		var lm: RouteCatalog.Landmark = landmarks[i]
		var best: Placed = null
		var best_clear: float = -INF
		for k in TRIES.size():
			var ctx := Ctx.new()
			ctx.track = track
			ctx.env = env
			ctx.field = field
			ctx.material = material
			ctx.anim_material = anim
			ctx.probe = probe
			ctx.rng.seed = env.scenery_seed * 131 + i * 977 + 5
			ctx.placed = Placed.new()
			ctx.placed.type = lm.type
			ctx.placed.s_m = lm.s_m
			ctx.placed.side = lm.side
			ctx.placed.plane = lm.plane
			ctx.placed.range_m = _range_for(lm.plane)
			track.sample_into(track.wrap_distance(lm.s_m), sample)
			_frame(ctx, sample, lm, TRIES[k])
			_build_type(ctx, lm.type)
			ctx.placed.anchor = ctx.anchor
			if ctx.placed.instance_count() == 0:
				break
			if lm.side == RouteCatalog.Landmark.SIDE_ROAD:
				best = ctx.placed
				break
			var clear: float = _clearance(ctx.placed, probe)
			if clear >= 0.0:
				best = ctx.placed
				break
			if clear > best_clear:
				best_clear = clear
				best = ctx.placed
		if best != null and best.instance_count() > 0:
			out.append(best)
	return out


## Узлы ориентиров: по `MultiMeshInstance3D` на часть; первая часть ориентира — узел
## `Landmark_<i>_<type>`, остальные — его дети. Пусто — ориентиров нет.
static func build(track: Track, landmarks: Array, env: EnvironmentSet, field: TerrainField,
		material: Material) -> Array[MultiMeshInstance3D]:
	return nodes(place(track, landmarks, env, field, material))


static func nodes(placed: Array[Placed]) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	for i in placed.size():
		var pl: Placed = placed[i]
		var root: MultiMeshInstance3D = null
		for part in pl.parts:
			if part.xf.is_empty() or part.mesh == null:
				continue
			var node := _multimesh(part, pl.range_m)
			if root == null:
				node.name = "Landmark_%02d_%s" % [i, pl.type]
				root = node
				out.append(root)
			else:
				node.name = part.name
				root.add_child(node)
	return out


## Пятна ориентиров для растительности (`SceneryBuilder`): по экземпляру с ненулевым пятном.
static func keep_out(placed: Array[Placed]) -> KeepOut:
	var ko := KeepOut.new()
	for pl in placed:
		for part in pl.parts:
			if part.footprint_m <= 0.0 or part.world_space:
				continue
			for t in part.xf:
				var sc: float = t.basis.get_scale().x
				ko.add(t.origin.x, t.origin.z, part.footprint_m * maxf(sc, 0.2))
	return ko


static func _range_for(plane: String) -> float:
	match plane:
		RouteCatalog.Landmark.PLANE_MID:
			return RANGE_MID_M
		RouteCatalog.Landmark.PLANE_FAR:
			return RANGE_FAR_M
	return RANGE_NEAR_M


static func _place_for(plane: String) -> Vector2:
	match plane:
		RouteCatalog.Landmark.PLANE_MID:
			return PLACE_MID
		RouteCatalog.Landmark.PLANE_FAR:
			return PLACE_FAR
	return PLACE_NEAR


## Кадр ориентира: курс и «вправо» в точке s (горизонтальные), сторона, точка привязки
## (удаление и упреждение плана × масштабы попытки `tryk`).
static func _frame(ctx: Ctx, sample: TrackSample, lm: RouteCatalog.Landmark, tryk: Vector2) -> void:
	ctx.at = sample.position
	ctx.road_y = sample.position.y
	var f := Vector3(sample.forward.x, 0.0, sample.forward.z)
	ctx.fwd = f.normalized() if f.length_squared() > 1e-8 else Vector3.FORWARD
	var r: Vector3 = sample.right()
	r.y = 0.0
	ctx.right = r.normalized() if r.length_squared() > 1e-8 else Vector3.RIGHT
	var sgn: float = -1.0 if lm.side == RouteCatalog.Landmark.SIDE_LEFT else 1.0
	ctx.out = ctx.right * sgn
	var center: Vector3 = sample.position + ctx.right * ctx.env.road_center_offset_m
	if lm.side == RouteCatalog.Landmark.SIDE_ROAD:
		ctx.anchor = center
		return
	var pl: Vector2 = TYPE_PLACE.get(lm.type, _place_for(lm.plane))
	ctx.anchor = center + ctx.fwd * pl.y * tryk.y + ctx.out * pl.x * tryk.x
	ctx.anchor.y = ctx.ground(ctx.anchor)


static func _track_points(track: Track) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var n: int = maxi(int(ceil(track.length_m() / TRACK_PROBE_M)), 2)
	var sample := TrackSample.new()
	for i in n + 1:
		track.sample_into(minf(float(i) * TRACK_PROBE_M, track.length_m()), sample)
		pts.append(sample.position)
	return pts


static func _dist_to_track(p: Vector3, pts: PackedVector3Array) -> float:
	var best: float = INF
	for q in pts:
		var dx: float = p.x - q.x
		var dz: float = p.z - q.z
		best = minf(best, dx * dx + dz * dz)
	return sqrt(best)


## Запас расстановки: min по частям (расстояние до трассы − пятно − `MIN_CLEARANCE_M`) и
## (`MAX_FROM_TRACK_M` − расстояние до трассы); ≥ 0 — место годится.
static func _clearance(pl: Placed, pts: PackedVector3Array) -> float:
	var worst: float = INF
	for part in pl.parts:
		if part.mesh == null or part.world_space:
			continue
		for t in part.xf:
			var d: float = _dist_to_track(t.origin, pts)
			var sc: float = t.basis.get_scale().x
			worst = minf(worst, d - part.footprint_m * sc - MIN_CLEARANCE_M)
			worst = minf(worst, MAX_FROM_TRACK_M - d)
	return worst


static func _multimesh(part: Part, range_m: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = part.animated
	mm.mesh = part.mesh
	mm.instance_count = part.xf.size()
	var box := AABB()
	var mesh_box: AABB = part.mesh.get_aabb() if part.mesh != null else AABB(Vector3.ZERO, Vector3.ONE)
	for i in part.xf.size():
		mm.set_instance_transform(i, part.xf[i])
		mm.set_instance_color(i, MeshKit.lin(part.col[i]))
		if part.animated:
			mm.set_instance_custom_data(i, part.custom[i])
		var b: AABB = part.xf[i] * mesh_box
		if part.animated:
			b = b.grow(part.custom[i].b + part.custom[i].a + mesh_box.size.length() * 0.5)
		box = b if i == 0 else box.merge(b)
	mm.custom_aabb = box
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.visibility_range_end = range_m
	node.visibility_range_end_margin = PerfBudget.RANGE_MARGIN_M
	if part.footprint_m <= 0.0 and not part.animated:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


# ---------------------------------------------------------------------------
# Типы ориентиров (`tracks.md` п. 4.5)
# ---------------------------------------------------------------------------

static func _build_type(ctx: Ctx, type: String) -> void:
	match type:
		"water_tower":
			ctx.put("water_tower", 5.0, 0.0, 0.0, ctx.rng.randf() * TAU)
			ctx.put("house_small", 4.0, -9.0, 6.0, 0.3, 0.8)
		"wind_turbines_far":
			_turbines(ctx, 7, Vector2(150.0, 55.0))
		"wind_turbines_near":
			_turbines(ctx, 4, Vector2(120.0, 40.0))
		"haystacks":
			for i in 5:
				ctx.put("haystack", 3.0, ctx.rng.randf_range(-16.0, 16.0), ctx.rng.randf_range(-6.0, 10.0),
					ctx.rng.randf() * TAU, ctx.rng.randf_range(0.8, 1.2))
		"village":
			_village(ctx, 7)
		"grain_elevator":
			ctx.put("grain_elevator", 12.0, 0.0, 0.0, ctx.rng.randf_range(-0.3, 0.3))
			ctx.put("barn", 9.0, -26.0, 4.0, PI * 0.5, 0.9, Color(0.85, 0.85, 0.85))
		"sunflower_field":
			_sunflowers(ctx)
		"creek_footbridge":
			_bridge(ctx, "railing", true)
		"farm_silo":
			ctx.put("barn", 9.0, 0.0, 0.0, ctx.rng.randf_range(-0.2, 0.2))
			ctx.put("silo", 4.0, 12.0, 4.0)
			ctx.put("house_small", 4.0, -15.0, -2.0, 0.4)
		"stone_bridge":
			_bridge(ctx, "parapet", false)
		"chapel":
			ctx.put("chapel", 8.0, 0.0, 0.0, ctx.rng.randf_range(-0.25, 0.25))
			var cy: Mesh = SceneryBuilder.conifer_mesh(ctx.material)
			for u in [-9.0, 9.0]:
				var p: Vector3 = ctx.local(u, 3.0)
				ctx.part_mesh("chapel_trees", cy, 2.0).add(Transform3D(ctx.facing(-ctx.out, 0.0, Vector3(0.8, 1.5, 0.8)), p))
		"sheep":
			for i in 14:
				ctx.put("sheep", 0.8, ctx.rng.randf_range(-18.0, 18.0), ctx.rng.randf_range(-8.0, 14.0),
					ctx.rng.randf() * TAU, ctx.rng.randf_range(0.9, 1.15))
		"farmstead":
			ctx.put("house", 6.0, 0.0, 0.0, ctx.rng.randf_range(-0.3, 0.3))
			ctx.put("barn", 9.0, 22.0, 10.0, PI * 0.5 + ctx.rng.randf_range(-0.2, 0.2))
			ctx.put("silo", 4.0, 34.0, 2.0, 0.0, 0.7)
			_trees(ctx, 4, Vector2(-25.0, 10.0), 18.0)
		"hay_bales":
			for i in 10:
				ctx.put("hay_bale", 1.2, ctx.rng.randf_range(-26.0, 26.0), ctx.rng.randf_range(-10.0, 18.0),
					ctx.rng.randf() * TAU, ctx.rng.randf_range(0.9, 1.1), Color.WHITE, -0.1)
		"lone_tree_bench":
			ctx.put("oak", 4.5, 0.0, 0.0, ctx.rng.randf() * TAU, 1.15)
			ctx.put("bench", 1.0, -2.5, -5.5, PI)
		"windmill":
			var t: Transform3D = ctx.put("windmill", 5.0, 0.0, 0.0, ctx.rng.randf_range(-0.4, 0.2))
			ctx.part("windmill_sails", 0.0, true).add(t * Transform3D(Basis.IDENTITY, PropMeshes.WINDMILL_HUB), Color.WHITE,
				Color(0.45, ctx.rng.randf() * TAU, 0.0, 0.0))
		"lake_view":
			_lake(ctx)
		"horse_paddock":
			_paddock(ctx)
		"castle_ruins":
			ctx.put("castle", 26.0, 0.0, 0.0, ctx.rng.randf_range(-0.5, 0.5), 1.3, Color.WHITE, -1.0)
		"tv_tower":
			ctx.put("tv_tower", 6.0, 0.0, 0.0, ctx.rng.randf() * TAU)
		"vineyard":
			_vineyard(ctx)
		"hot_air_balloon":
			var p: Vector3 = ctx.local(0.0, 0.0)
			var tb := Transform3D(ctx.facing(-ctx.out), p + Vector3.UP * 72.0)
			ctx.part("balloon", 0.0, true).add(tb, Color.WHITE, Color(0.0, ctx.rng.randf() * TAU, 12.0, 2.5))


## Ряд ветряков, уходящий от зрителя: шаг (вперёд, наружу); ротор смотрит на точку s.
static func _turbines(ctx: Ctx, count: int, step: Vector2) -> void:
	for i in count:
		var k: float = float(i) - float(count - 1) * 0.5
		var p: Vector3 = ctx.local(k * step.x + ctx.rng.randf_range(-15.0, 15.0), k * step.y + ctx.rng.randf_range(-12.0, 12.0))
		var face: Vector3 = ctx.at - p
		var t := Transform3D(ctx.facing(face, ctx.rng.randf_range(-0.25, 0.25)), p)
		ctx.part("turbine", 3.0).add(t)
		ctx.part("turbine_rotor", 0.0, true).add(t * Transform3D(Basis.IDENTITY, PropMeshes.TURBINE_HUB), Color.WHITE,
			Color(ctx.rng.randf_range(0.55, 0.8), ctx.rng.randf() * TAU, 0.0, 0.0))


## Деревня: дома на неровной сетке, крыши к дороге с разбросом, несколько деревьев.
static func _village(ctx: Ctx, count: int) -> void:
	var cols: int = 4
	for i in count:
		var gx: float = float(i % cols) - float(cols - 1) * 0.5
		var gz: float = float(i / cols) - 0.5
		var u: float = gx * 19.0 + ctx.rng.randf_range(-4.0, 4.0)
		var v: float = gz * 22.0 + ctx.rng.randf_range(-4.0, 4.0)
		var key: String = "house" if ctx.rng.randf() < 0.6 else "house_small"
		var tint: float = ctx.rng.randf_range(0.92, 1.05)
		ctx.put(key, 6.0, u, v, ctx.rng.randf_range(-0.35, 0.35) + (PI * 0.5 if ctx.rng.randf() < 0.3 else 0.0),
			ctx.rng.randf_range(0.9, 1.15), Color(tint, tint, tint))
	_trees(ctx, 5, Vector2(0.0, 20.0), 45.0)


static func _trees(ctx: Ctx, count: int, center: Vector2, spread: float) -> void:
	var m: Mesh = SceneryBuilder.tree_mesh(ctx.material)
	for i in count:
		var p: Vector3 = ctx.local(center.x + ctx.rng.randf_range(-spread, spread), center.y + ctx.rng.randf_range(-spread * 0.5, spread * 0.5))
		var sc: float = ctx.rng.randf_range(0.9, 1.3)
		ctx.part_mesh("trees", m, 2.5).add(Transform3D(ctx.facing(-ctx.out, ctx.rng.randf() * TAU, Vector3.ONE * sc), p - Vector3.UP * 0.1))


## Подсолнуховое поле: куртины 3 × 4 м сеткой ~60 × 24 м, корзинки к дороге.
static func _sunflowers(ctx: Ctx) -> void:
	for iu in 21:
		for iv in 7:
			var u: float = (float(iu) - 10.0) * 3.0
			var v: float = (float(iv) - 3.0) * 4.0
			ctx.put("sunflowers", 0.0, u, v, ctx.rng.randf_range(-0.12, 0.12), ctx.rng.randf_range(0.92, 1.08),
				Color.WHITE, -0.05)
	# Пятно поля целиком — растительность туда не ставится.
	ctx.part_mesh("sunflower_footprint", null, 34.0).add(Transform3D(Basis.IDENTITY, ctx.local(0.0, 0.0)))


## Мост через ручей: дорога и есть мост — по краям полотна перила/парапеты, под полотном
## поперёк дороги лента воды по рельефу, у ручья ивы (у мостика).
static func _bridge(ctx: Ctx, rail_key: String, willows: bool) -> void:
	var s_c: float = ctx.track.wrap_distance(ctx.placed.s_m + 28.0)
	var sample := TrackSample.new()
	ctx.track.sample_into(s_c, sample)
	var r: Vector3 = sample.right()
	var center: Vector3 = sample.position + r * ctx.env.road_center_offset_m
	var edge: float = RoadsideBuilder.curb_outer_m(ctx.env.road_width_m) + 0.2
	var basis := Basis(sample.forward, sample.up, r)
	for sgn in [-1.0, 1.0]:
		var p: Vector3 = center + r * sgn * edge + sample.up * RoadsideBuilder.CURB_H_M
		ctx.part(rail_key, 0.0).add(Transform3D(basis, p))
	var creek: ArrayMesh = _creek_mesh(ctx, sample, center)
	ctx.part_mesh("creek", creek, 0.0, true).add(Transform3D.IDENTITY)
	if willows:
		var m: Mesh = PropMeshes.mesh("willow", ctx.material)
		for i in 4:
			var sgn: float = -1.0 if i % 2 == 0 else 1.0
			var w: float = ctx.rng.randf_range(20.0, 38.0) + float(i / 2) * 12.0
			var p: Vector3 = center + r * sgn * w + sample.forward * ctx.rng.randf_range(5.0, 9.0) * (1.0 if i < 2 else -1.0)
			p.y = ctx.ground(p) - 0.1
			ctx.part_mesh("willow", m, 3.5).add(Transform3D(Basis(Vector3.UP, ctx.rng.randf() * TAU).scaled(Vector3.ONE * ctx.rng.randf_range(0.9, 1.2)), p))
	ctx.anchor = center


## Лента ручья поперёк дороги (±`CREEK_HALF_M` от оси), с меандром и берегами, по рельефу и
## полосе травы; под полотном и бордюром не строится.
const CREEK_HALF_M: float = 90.0


static func _creek_mesh(ctx: Ctx, sample: TrackSample, center: Vector3) -> ArrayMesh:
	var kit := MeshKit.new()
	var r: Vector3 = sample.right()
	r.y = 0.0
	r = r.normalized()
	var f := Vector3(sample.forward.x, 0.0, sample.forward.z).normalized()
	var curb_out: float = RoadsideBuilder.curb_outer_m(ctx.env.road_width_m)
	var verge_w: float = RoadsideBuilder.verge_width_m(ctx.env.road_width_m)
	var water: Color = Color(ctx.env.water_color, 0.0)
	var bank := Color(0.36, 0.42, 0.26, 0.0)
	var offsets: Array[float] = [-3.0, -1.7, 1.7, 3.0]
	var cols: Array[Color] = [bank, water, water, bank]
	for sgn in [-1.0, 1.0]:
		var rows: Array[PackedVector3Array] = []
		var t: float = curb_out + 0.05
		while t <= CREEK_HALF_M:
			var row := PackedVector3Array()
			var meander: float = sin(t / 17.0 + sgn) * 3.5 * smoothstep(curb_out + 4.0, curb_out + 20.0, t)
			for o in offsets:
				var p: Vector3 = center + r * sgn * t + f * (o + meander)
				var y_field: float = ctx.ground(p)
				var y: float = y_field
				if t < verge_w:
					var y_verge: float = sample.position.y + RoadsideBuilder.verge_height(t, ctx.env.road_width_m)
					y = maxf(y_verge, y_field) if t > verge_w - 3.0 else y_verge
				p.y = y + 0.06
				row.append(p)
			rows.append(row)
			t += 3.0
		for i in rows.size() - 1:
			for j in offsets.size() - 1:
				kit.add_quad(rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j], Vector3.UP, cols[j] if j != 1 else water)
	return kit.to_mesh(ctx.material)


## Озеро внизу (дальний план): среди точек сектора впереди-сбоку (20–40° от курса, 600–1000 м)
## выбирается самая низкая из видимых с дороги в s (луч от глаз до точки не уходит под
## рельеф); водная гладь — эллипс на уровне чуть выше земли в ней (вода видна там, где рельеф
## ниже уровня, — берег по рельефу).
const LAKE_RADII := Vector2(140.0, 85.0)
const LAKE_DROP_M: float = 30.0


static func _lake(ctx: Ctx) -> void:
	var eye: Vector3 = ctx.at + Vector3.UP * 2.5
	var best := Vector3.ZERO
	var best_score: float = INF
	var best_level: float = 0.0
	var reach: float = maxf(LAKE_RADII.x, LAKE_RADII.y)
	for ia in 13:
		var th: float = deg_to_rad(8.0 + 4.0 * float(ia))
		for idist in 8:
			var d: float = 260.0 + 60.0 * float(idist)
			var p: Vector3 = ctx.at + ctx.fwd * cos(th) * d + ctx.out * sin(th) * d
			# Котловина с долиной не подходит к дороге (рельеф у полотна не поднимается) и лежит
			# в рельефе-коридоре.
			var to_track: float = _dist_to_track(p, ctx.probe)
			var clear: float = minf(to_track - reach * TerrainField.BASIN_REACH - 40.0, TerrainField.CORRIDOR_RADIUS_M - 60.0 - to_track - reach)
			if clear < 0.0:
				continue
			p.y = ctx.ground(p)
			# Самый низкий уровень (до `LAKE_DROP_M` под дорогой), при котором ближний берег
			# виден с дороги: луч от глаз к ближней кромке воды не уходит под рельеф.
			var near_edge: Vector3 = p + (eye - p).normalized() * reach * 0.8
			var level: float = INF
			for drop in [LAKE_DROP_M, 22.0, 15.0, 9.0, 4.0, 0.0]:
				var lv: float = minf(p.y + 1.0, ctx.road_y - float(drop))
				var target := Vector3(near_edge.x, lv, near_edge.z)
				var blocked: bool = false
				for k in range(1, 24):
					var q: Vector3 = eye.lerp(target, float(k) / 24.0)
					if q.distance_to(target) < reach * 0.25:
						break
					if ctx.ground(q) > q.y - 0.5:
						blocked = true
						break
				if not blocked:
					level = lv
					break
			if level == INF:
				continue
			# Ниже — лучше; ближе к курсу — лучше (озеро в кадре).
			var score: float = level + rad_to_deg(th) * 0.4
			if score < best_score:
				best_score = score
				best = p
				best_level = level
	if best_score == INF:
		return
	var best_y: float = best_level
	best.y = best_y
	ctx.anchor = best
	var kit := MeshKit.new()
	var level: float = best_y
	var basin := Basin.new()
	basin.center = best
	basin.axis = ctx.fwd
	basin.radii = LAKE_RADII
	basin.level = level
	var deep := Color(0.10, 0.42, 0.62, 0.0)
	var shallow := Color(ctx.env.water_color, 0.0)
	var a: float = LAKE_RADII.x
	var b: float = LAKE_RADII.y
	var n: int = 28
	var f: Vector3 = ctx.fwd
	var o: Vector3 = ctx.out
	for i in n:
		var t0: float = TAU * float(i) / float(n)
		var t1: float = TAU * float(i + 1) / float(n)
		var e0: Vector3 = f * cos(t0) * a + o * sin(t0) * b
		var e1: Vector3 = f * cos(t1) * a + o * sin(t1) * b
		var c := Vector3(best.x, level, best.z)
		kit.add_triangle(c, c + e0 * 0.8, c + e1 * 0.8, Vector3.UP, deep)
		kit.add_quad(c + e0 * 0.8, c + e1 * 0.8, c + e1, c + e0, Vector3.UP, shallow)
	ctx.part_mesh("lake", kit.to_mesh(ctx.material), 0.0, true).add(Transform3D.IDENTITY)
	ctx.placed.basins.append(basin)
	# Пятно озера для растительности — по центру.
	ctx.part_mesh("lake_footprint", null, 210.0).add(Transform3D(Basis.IDENTITY, best))


## Загон: жердевая изгородь прямоугольником 36 × 24 м, внутри три лошади.
static func _paddock(ctx: Ctx) -> void:
	var hw: float = 18.0
	var hd: float = 12.0
	var edges: Array[Vector4] = [
		Vector4(-hw, -hd, hw, -hd), Vector4(hw, -hd, hw, hd), Vector4(hw, hd, -hw, hd), Vector4(-hw, hd, -hw, -hd),
	]
	for e in edges:
		var a := Vector2(e.x, e.y)
		var b := Vector2(e.z, e.w)
		var segs: int = int(round(a.distance_to(b) / 6.0))
		for k in segs:
			var m: Vector2 = a.lerp(b, (float(k) + 0.5) / float(segs))
			var p: Vector3 = ctx.local(m.x, m.y)
			var dir: Vector3 = ctx.fwd * (b.x - a.x) + ctx.out * (b.y - a.y)
			var x: Vector3 = Vector3(dir.x, 0.0, dir.z).normalized()
			ctx.part("fence", 0.0).add(Transform3D(Basis(x, Vector3.UP, x.cross(Vector3.UP)), p))
	var coats: Array[Color] = [Color(0.62, 0.42, 0.28), Color(0.34, 0.25, 0.20), Color(0.90, 0.88, 0.82)]
	for i in 3:
		ctx.put("horse", 1.5, ctx.rng.randf_range(-12.0, 12.0), ctx.rng.randf_range(-7.0, 7.0), ctx.rng.randf() * TAU,
			ctx.rng.randf_range(0.95, 1.05), coats[i])
	ctx.part_mesh("paddock_footprint", null, 22.0).add(Transform3D(Basis.IDENTITY, ctx.local(0.0, 0.0)))


## Виноградник: 7 рядов шпалер вдоль дороги по 5 звеньев, звенья наклонены по склону.
static func _vineyard(ctx: Ctx) -> void:
	for row in 7:
		var v: float = -9.0 + 3.0 * float(row)
		for k in 5:
			var u0: float = -20.0 + 8.0 * float(k)
			var p0: Vector3 = ctx.local(u0, v)
			var p1: Vector3 = ctx.local(u0 + 8.0, v)
			var x: Vector3 = p1 - p0
			var xs: float = x.length() / 8.0
			x = x.normalized()
			var z: Vector3 = x.cross(Vector3.UP).normalized()
			ctx.part("vines", 0.0).add(Transform3D(Basis(x * xs, z.cross(x).normalized(), z), (p0 + p1) * 0.5 - Vector3.UP * 0.05))
	ctx.part_mesh("vineyard_footprint", null, 26.0).add(Transform3D(Basis.IDENTITY, ctx.local(0.0, 0.0)))
