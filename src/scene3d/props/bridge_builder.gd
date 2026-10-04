class_name BridgeBuilder
extends RefCounted
## Мост трассы (T-090, REQ-D3D-08 п.3, 6, 11; `docs/game/tracks.md` п. 4.4, 6): на участках
## `RouteDef.bridges` дорога идёт по пролётному строению. Полотно — сама дорога (`RoadBuilder`,
## разметка и h(s) не меняются), кромка и бордюр — `RoadsideBuilder` (без травы и отбойника на
## мосту); здесь — всё, что под полотном и по его краям, одним мешем в мировых координатах:
## карниз с тротуарной полосой, перила светлой стали (вместо отбойника), коробчатая балка
## бетона с вутами у опор, три опоры-стенки эллиптического сечения (в воде — с ледорезом у
## уреза), береговые устои на концах с пилонами-порталами (с подъезда мост читается по ним и
## ряду фонарей — дорога к мосту прямая, полотно видно «в торец»); фонари через 40 м по обеим
## сторонам — экземплярами.
## Долину под мостом (заводь реки с пляжем, пойма, откосы у устоев) прорезает `TerrainField`
## по тем же диапазонам; растительность и столбики на мосту не ставятся (`SceneryBuilder`,
## `RoadsideBuilder`).
##
## Узлы — `MultiMeshInstance3D` (бюджет `MeshInstance3D` не растёт): «Bridge_<k>» — меш
## конструкции (один экземпляр, с порталами, опорами и устоями), его дети — перила (без тени) и
## фонари; пятна для растительности (`LandmarkBuilder.keep_out`) — без узлов.
## Строится один раз в `RideScene.set_track()`, не зависит от ориентиров: ориентир `bridge`
## (`LandmarkBuilder`) — камыши по берегам заводи под мостом.

## Подход к мосту по s, м: на нём полоса травы сужается к устою, растительность у дороги не ставится.
const APPROACH_M: float = 25.0
## Устой: полуширина поперёк дороги от её центра, заход за начало моста (под насыпь) и вперёд —
## на нём лежит балка; низ — ниже земли перед устоем.
const ABUT_HALF_W_M: float = 7.0
const ABUT_BACK_M: float = 3.0
const ABUT_IN_M: float = 5.0
## Высота земли перед устоем ниже полотна, м (`TerrainField.carve_bridge_valley`).
const ABUT_DROP_M: float = 6.0
## Карниз: тротуарная полоса за бордюром, её верх — на уровне верха бордюра; низ лицевой грани.
const CORNICE_W_M: float = 0.55
const CORNICE_DROP_M: float = 0.8
## Коробчатая балка: полуширина верха и низа, высота в пролёте и над опорой, длина вута.
const GIRDER_TOP_HALF_M: float = 2.9
const GIRDER_BOTTOM_HALF_M: float = 2.1
const SLAB_M: float = 0.6
const GIRDER_DEPTH_M: float = 2.4
const HAUNCH_DEPTH_M: float = 4.4
const HAUNCH_LEN_M: float = 48.0
## Опоры: число (равные пролёты), полуоси сечения (поперёк, вдоль) внизу и вверху.
const PIERS: int = 3
const PIER_BOTTOM := Vector2(2.0, 1.0)
const PIER_TOP := Vector2(2.7, 1.25)
const CUTWATER := Vector2(2.6, 1.5)
## Перила: отступ от края карниза внутрь, высота, шаг стоек; фонари — шаг и первый от начала.
const RAIL_IN_M: float = 0.3
const RAIL_H_M: float = 1.1
const RAIL_POST_STEP_M: float = 2.5
const LAMP_STEP_M: float = 40.0
const LAMP_FIRST_M: float = 20.0
const LAMP_IN_M: float = 0.1
## Шаг колец конструкции вдоль моста, м (как у дороги).
const STEP_M: float = 5.0
## Дальность видимости моста (до центра габарита), м: виден с подъезда за 1 км и больше
## (`tracks.md`: «виден за 300–400 м до въезда»).
const RANGE_M: float = 1700.0
## Пятна для растительности вдоль моста: шаг и радиус, м; на подходе (`OPEN_APPROACH_M` до
## устоя) — шире: с подъезда видны долина и порталы, а не стена крон.
const KEEP_STEP_M: float = 10.0
const KEEP_RADIUS_M: float = 22.0
const OPEN_APPROACH_M: float = 170.0
const OPEN_RADIUS_M: float = 26.0
## Пилон-портал на устое: отступ от края карниза наружу, вперёд от начала моста, сечение, высота
## над полотном.
const PORTAL_OUT_M: float = 0.9
const PORTAL_AT_M: float = 1.5
const PORTAL_W_M: float = 1.3
const PORTAL_H_M: float = 10.0
## Имя части перил (без тени).
const RAILINGS: String = "bridge_railings"

## Палитра (`tracks.md` п. 6): бетон (0.74, 0.74, 0.72), перила (0.78, 0.82, 0.86); альфа — вес контура.
const C_CONCRETE := Color(0.74, 0.74, 0.72, 0.6)
const C_CONCRETE_LIGHT := Color(0.80, 0.80, 0.78, 0.0)
const C_CONCRETE_SHADE := Color(0.62, 0.63, 0.63, 0.6)
const C_WET := Color(0.50, 0.53, 0.53, 0.6)
const C_STEEL := Color(0.78, 0.82, 0.86, 0.0)
const C_STEEL_DARK := Color(0.68, 0.72, 0.77, 0.0)
const C_PORTAL := Color(0.84, 0.84, 0.81, 0.8)
const C_PORTAL_CAP := Color(0.42, 0.44, 0.48, 1.0)
const C_LANTERN := Color(0.99, 0.95, 0.80, 0.5)


## Диапазоны мостов трассы по s (x — начало, y — конец, м): у трассы каталога — `RouteDef.bridges`,
## у прочих (петля, GPX) мостов нет.
static func ranges(track: Track) -> PackedVector2Array:
	var out := PackedVector2Array()
	if track is ProfiledTrack:
		var def: RouteCatalog.RouteDef = (track as ProfiledTrack).route
		if def != null:
			for b in def.bridges:
				if b.y > b.x:
					out.append(b)
	return out


## Попадает ли s (уже в пределах круга) в мост, расширенный на `margin` м с обеих сторон.
static func in_ranges(bridges: PackedVector2Array, s: float, margin: float = 0.0) -> bool:
	for b in bridges:
		if s >= b.x - margin and s <= b.y + margin:
			return true
	return false


## Положение опор по s на мосту `b`: равные пролёты.
static func pier_distances(b: Vector2) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for k in PIERS:
		out.append(lerpf(b.x, b.y, float(k + 1) / float(PIERS + 1)))
	return out


## Высота балки, м, в точке s моста `b`: вуты к опорам.
static func girder_depth(b: Vector2, s: float) -> float:
	var near: float = INF
	for p in pier_distances(b):
		near = minf(near, absf(s - p))
	var t: float = 1.0 - clampf(near / HAUNCH_LEN_M, 0.0, 1.0)
	return GIRDER_DEPTH_M + (HAUNCH_DEPTH_M - GIRDER_DEPTH_M) * t * t


## Низ балки под осью дороги в точке s моста `b` (абсолютная высота, м).
static func girder_bottom_y(track: Track, b: Vector2, s: float) -> float:
	return track.sample(s).position.y - SLAB_M - girder_depth(b, s)


## Полуширина пролётного строения от центра дороги (край карниза), м.
static func deck_half_m(road_width_m: float) -> float:
	return RoadsideBuilder.curb_outer_m(road_width_m) + CORNICE_W_M


## Расставить мосты трассы (данные без узлов): по `Placed` на мост, тип `bridge_span`, точка —
## центр дороги в середине моста. `field` — рельеф после всех правок (опоры стоят на дне).
static func place(track: Track, env: EnvironmentSet, field: TerrainField, material: Material) -> Array[LandmarkBuilder.Placed]:
	var out: Array[LandmarkBuilder.Placed] = []
	if track == null or env == null:
		return out
	for b in ranges(track):
		out.append(_place_one(track, b, env, field, material))
	return out


## Узлы мостов: «Bridge_<k>» — конструкция, дети — перила и фонари. Тени отбрасывают все, кроме перил.
static func nodes(placed: Array[LandmarkBuilder.Placed]) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	for k in placed.size():
		var root: MultiMeshInstance3D = null
		for part in placed[k].parts:
			if part.mesh == null or part.xf.is_empty():
				continue
			var node := LandmarkBuilder.multimesh_node(part, placed[k].range_m)
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if part.name == RAILINGS \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if root == null:
				node.name = "Bridge_%d" % k
				root = node
				out.append(root)
			else:
				node.name = part.name
				root.add_child(node)
	return out


static func _place_one(track: Track, b: Vector2, env: EnvironmentSet, field: TerrainField,
		material: Material) -> LandmarkBuilder.Placed:
	var pl := LandmarkBuilder.Placed.new()
	pl.type = "bridge_span"
	pl.s_m = b.x
	pl.side = RouteCatalog.Landmark.SIDE_ROAD
	pl.plane = RouteCatalog.Landmark.PLANE_NEAR
	pl.range_m = RANGE_M
	var kit := MeshKit.new()
	var level: float = field.water_level if field != null and field.has_water() else -INF
	_deck(kit, track, b, env)
	var rails := MeshKit.new()
	_railings(rails, track, b, env)
	for s in pier_distances(b):
		_pier(kit, track, b, s, env, field, level)
	_abutment(kit, track, b, b.x, 1.0, env, field)
	_abutment(kit, track, b, b.y, -1.0, env, field)
	_portals(kit, track, b.x + PORTAL_AT_M, env)
	_portals(kit, track, b.y - PORTAL_AT_M, env)
	var body := LandmarkBuilder.Part.new("bridge", kit.to_mesh(material), 1.0, false)
	body.world_space = true
	body.add(Transform3D.IDENTITY)
	pl.parts.append(body)
	# Перила — отдельной частью без тени: тонкие планки в карте теней дают «лесенку» на полотне.
	var rail_part := LandmarkBuilder.Part.new(RAILINGS, rails.to_mesh(material), 0.0, false)
	rail_part.world_space = true
	rail_part.add(Transform3D.IDENTITY)
	pl.parts.append(rail_part)
	var lamps := LandmarkBuilder.Part.new("bridge_lamps", PropMeshes.mesh("bridge_lamp", material), 0.5, false)
	var half: float = deck_half_m(env.road_width_m)
	var at: float = b.x + LAMP_FIRST_M
	while at <= b.y - LAMP_FIRST_M * 0.5:
		var f := _frame(track, at, env)
		for sgn in [-1.0, 1.0]:
			var p: Vector3 = f.center + f.right * float(sgn) * (half - LAMP_IN_M) + Vector3.UP * RoadsideBuilder.CURB_H_M
			lamps.add(Transform3D(_facing(-f.right * float(sgn)), p))
		at += LAMP_STEP_M
	pl.parts.append(lamps)
	# Пятна для растительности вдоль моста и устоев (без меша — не в узлах).
	var spots := LandmarkBuilder.Part.new("bridge_keep_out", null, KEEP_RADIUS_M, false)
	var s_k: float = b.x - OPEN_APPROACH_M
	while s_k <= b.y + OPEN_APPROACH_M:
		var fk := _frame(track, track.wrap_distance(s_k), env)
		var open: bool = s_k < b.x - ABUT_BACK_M or s_k > b.y + ABUT_BACK_M
		var r: float = OPEN_RADIUS_M if open else KEEP_RADIUS_M
		spots.add(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * r / KEEP_RADIUS_M), fk.center))
		s_k += KEEP_STEP_M
	pl.parts.append(spots)
	var mid := _frame(track, (b.x + b.y) * 0.5, env)
	pl.anchor = mid.center
	return pl


## Кадр моста в s: центр дороги (на высоте полотна), горизонтальные «вправо» и «вперёд».
class Frame:
	var center := Vector3.ZERO
	var right := Vector3.RIGHT
	var fwd := Vector3.FORWARD


static func _frame(track: Track, s: float, env: EnvironmentSet) -> Frame:
	var sample := TrackSample.new()
	track.sample_into(s, sample)
	var f := Frame.new()
	var r: Vector3 = sample.right()
	r.y = 0.0
	f.right = r.normalized()
	f.fwd = Vector3(sample.forward.x, 0.0, sample.forward.z).normalized()
	f.center = sample.position + f.right * env.road_center_offset_m
	return f


## Базис «лицом» (+Z) по горизонтальному направлению `face`.
static func _facing(face: Vector3) -> Basis:
	var z := Vector3(face.x, 0.0, face.z).normalized()
	return Basis(Vector3.UP.cross(z).normalized(), Vector3.UP, z)


## Кольца моста: s от начала до конца с шагом `STEP_M` (концы — точно на границах).
static func _rings(b: Vector2) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var n: int = maxi(int(ceil((b.y - b.x) / STEP_M)), 1)
	for i in n + 1:
		out.append(lerpf(b.x, b.y, float(i) / float(n)))
	return out


## Карниз (тротуарная полоса, лицевая грань, низ консоли) и коробчатая балка с вутами.
static func _deck(kit: MeshKit, track: Track, b: Vector2, env: EnvironmentSet) -> void:
	var co: float = RoadsideBuilder.curb_outer_m(env.road_width_m)
	var edge: float = co + CORNICE_W_M
	var top: float = RoadsideBuilder.CURB_H_M
	var rings: PackedFloat64Array = _rings(b)
	var frames: Array[Frame] = []
	for s in rings:
		frames.append(_frame(track, s, env))
	for i in rings.size() - 1:
		var f0: Frame = frames[i]
		var f1: Frame = frames[i + 1]
		var d0: float = girder_depth(b, rings[i])
		var d1: float = girder_depth(b, rings[i + 1])
		# Балка — от устоя до устоя (концы спрятаны в устоях).
		var inside: bool = rings[i] >= b.x + ABUT_IN_M - STEP_M and rings[i + 1] <= b.y - ABUT_IN_M + STEP_M
		for sgn in [-1.0, 1.0]:
			var o0: Vector3 = f0.right * float(sgn)
			var o1: Vector3 = f1.right * float(sgn)
			var up := Vector3.UP
			# Тротуарная полоса карниза.
			kit.add_quad(f0.center + o0 * co + up * top, f1.center + o1 * co + up * top,
				f1.center + o1 * edge + up * top, f0.center + o0 * edge + up * top, up, C_CONCRETE_LIGHT)
			# Лицевая грань карниза.
			kit.add_quad(f0.center + o0 * edge + up * top, f1.center + o1 * edge + up * top,
				f1.center + o1 * edge - up * CORNICE_DROP_M, f0.center + o0 * edge - up * CORNICE_DROP_M, o0, C_CONCRETE)
			# Низ консоли: от карниза к верху стенки балки.
			var cn: Vector3 = (-up + o0 * 0.25).normalized()
			kit.add_quad(f0.center + o0 * edge - up * CORNICE_DROP_M, f1.center + o1 * edge - up * CORNICE_DROP_M,
				f1.center + o1 * GIRDER_TOP_HALF_M - up * SLAB_M, f0.center + o0 * GIRDER_TOP_HALF_M - up * SLAB_M, cn, C_CONCRETE_SHADE)
			if inside:
				# Стенка балки (наклонная).
				var wn: Vector3 = (o0 * 2.4 - up * (GIRDER_TOP_HALF_M - GIRDER_BOTTOM_HALF_M)).normalized()
				kit.add_quad(f0.center + o0 * GIRDER_TOP_HALF_M - up * SLAB_M, f1.center + o1 * GIRDER_TOP_HALF_M - up * SLAB_M,
					f1.center + o1 * GIRDER_BOTTOM_HALF_M - up * (SLAB_M + d1), f0.center + o0 * GIRDER_BOTTOM_HALF_M - up * (SLAB_M + d0),
					wn, C_CONCRETE)
		if inside:
			kit.add_quad(f0.center - f0.right * GIRDER_BOTTOM_HALF_M - Vector3.UP * (SLAB_M + d0),
				f1.center - f1.right * GIRDER_BOTTOM_HALF_M - Vector3.UP * (SLAB_M + d1),
				f1.center + f1.right * GIRDER_BOTTOM_HALF_M - Vector3.UP * (SLAB_M + d1),
				f0.center + f0.right * GIRDER_BOTTOM_HALF_M - Vector3.UP * (SLAB_M + d0), Vector3.DOWN, C_CONCRETE_SHADE)
	# Торцы карниза на концах моста (лицом к насыпи — закрывают щель у устоя).
	for k in [0, rings.size() - 1]:
		var f: Frame = frames[k]
		var n: Vector3 = -f.fwd if k == 0 else f.fwd
		for sgn in [-1.0, 1.0]:
			var o: Vector3 = f.right * float(sgn)
			kit.add_quad(f.center + o * co + Vector3.UP * top, f.center + o * edge + Vector3.UP * top,
				f.center + o * edge - Vector3.UP * CORNICE_DROP_M, f.center + o * co - Vector3.UP * CORNICE_DROP_M, n, C_CONCRETE)


## Перила по обоим краям: стойки через `RAIL_POST_STEP_M`, поручень и две продольные планки.
static func _railings(kit: MeshKit, track: Track, b: Vector2, env: EnvironmentSet) -> void:
	var w: float = deck_half_m(env.road_width_m) - RAIL_IN_M
	var base: float = RoadsideBuilder.CURB_H_M
	var rings: PackedFloat64Array = _rings(b)
	var frames: Array[Frame] = []
	for s in rings:
		frames.append(_frame(track, s, env))
	for sgn in [-1.0, 1.0]:
		for i in rings.size() - 1:
			var f0: Frame = frames[i]
			var f1: Frame = frames[i + 1]
			var p0: Vector3 = f0.center + f0.right * float(sgn) * w
			var p1: Vector3 = f1.center + f1.right * float(sgn) * w
			var along: Vector3 = p1 - p0
			var len_m: float = along.length()
			if len_m < 1e-3:
				continue
			var x: Vector3 = along / len_m
			var basis := Basis(x, Vector3.UP, x.cross(Vector3.UP).normalized())
			var mid: Vector3 = (p0 + p1) * 0.5
			kit.add_box(Transform3D(basis, mid + Vector3.UP * (base + RAIL_H_M)), Vector3(len_m + 0.04, 0.09, 0.11), C_STEEL)
			for hy in [0.42, 0.74]:
				kit.add_box(Transform3D(basis, mid + Vector3.UP * (base + hy)), Vector3(len_m + 0.02, 0.05, 0.04), C_STEEL_DARK)
			var posts: int = maxi(int(round(len_m / RAIL_POST_STEP_M)), 1)
			for k in posts:
				var p: Vector3 = p0 + along * (float(k) / float(posts))
				kit.add_box(Transform3D(basis, p + Vector3.UP * (base + RAIL_H_M * 0.5)), Vector3(0.07, RAIL_H_M, 0.07), C_STEEL_DARK)
		var f_end: Frame = frames[frames.size() - 1]
		var pe: Vector3 = f_end.center + f_end.right * float(sgn) * w
		kit.add_box(Transform3D(_facing(f_end.right), pe + Vector3.UP * (base + RAIL_H_M * 0.5)), Vector3(0.09, RAIL_H_M, 0.09), C_STEEL_DARK)


## Опора-стенка в s: эллипс вытянут поперёк дороги, от дна до низа балки; в воде — ледорез у уреза.
static func _pier(kit: MeshKit, track: Track, b: Vector2, s: float, env: EnvironmentSet, field: TerrainField, level: float) -> void:
	var f := _frame(track, s, env)
	var top_y: float = f.center.y - SLAB_M - girder_depth(b, s) + 0.3
	var ground: float = f.center.y - 20.0
	if field != null:
		ground = f.center.y
		for k in 5:
			var p: Vector3 = f.center + f.right * lerpf(-PIER_TOP.x, PIER_TOP.x, float(k) / 4.0)
			ground = minf(ground, field.height_at(p.x, p.z))
	var foot: Vector3 = Vector3(f.center.x, ground - 1.5, f.center.z)
	var head: Vector3 = Vector3(f.center.x, top_y, f.center.z)
	kit.add_tube(foot, head, PIER_BOTTOM, PIER_TOP, C_CONCRETE, 14, true, f.right)
	if level > ground + 0.2:
		kit.add_tube(foot, Vector3(f.center.x, level + 0.7, f.center.z), CUTWATER, CUTWATER * 0.92, C_WET, 14, true, f.right)


## Пилоны-порталы в s по обеим сторонам за краем карниза (на устое): бетонный ствол с поясом,
## фонарь-«капитель» тёплого цвета под тёмной пирамидкой.
static func _portals(kit: MeshKit, track: Track, s: float, env: EnvironmentSet) -> void:
	var f := _frame(track, s, env)
	var basis := Basis(f.right, Vector3.UP, -f.fwd)
	var w: float = deck_half_m(env.road_width_m) + PORTAL_OUT_M
	var base_y: float = f.center.y - 1.2
	for sgn in [-1.0, 1.0]:
		var p: Vector3 = f.center + f.right * float(sgn) * w
		p.y = base_y
		var shaft: float = PORTAL_H_M + 1.2 - 1.4
		kit.add_box(Transform3D(basis, p + Vector3.UP * shaft * 0.5), Vector3(PORTAL_W_M, shaft, PORTAL_W_M), C_PORTAL)
		kit.add_box(Transform3D(basis, p + Vector3.UP * (1.2 + 1.0)), Vector3(PORTAL_W_M + 0.24, 0.3, PORTAL_W_M + 0.24), C_CONCRETE_SHADE)
		kit.add_box(Transform3D(basis, p + Vector3.UP * (shaft + 0.12)), Vector3(PORTAL_W_M + 0.3, 0.24, PORTAL_W_M + 0.3), C_CONCRETE_SHADE)
		kit.add_box(Transform3D(basis, p + Vector3.UP * (shaft + 0.24 + 0.5)), Vector3(PORTAL_W_M * 0.75, 1.0, PORTAL_W_M * 0.75), C_LANTERN)
		_pyramid(kit, p + Vector3.UP * (shaft + 1.24), f.right, f.fwd, PORTAL_W_M * 0.55, 0.9, C_PORTAL_CAP)


## Четырёхгранная пирамидка в осях моста (`MeshKit.add_pyramid` — только по осям мира).
static func _pyramid(kit: MeshKit, base: Vector3, x: Vector3, z: Vector3, half: float, height: float, color: Color) -> void:
	var apex: Vector3 = base + Vector3.UP * height
	var c: Array[Vector3] = [base - x * half - z * half, base + x * half - z * half, base + x * half + z * half,
		base - x * half + z * half]
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		var out: Vector3 = ((a + b) * 0.5 - base).normalized()
		kit.add_triangle(a, b, apex, (out * height + Vector3.UP * half).normalized(), color)


## Береговой устой: блок на конце моста `end_s` (`dir` +1 — начало, −1 — конец), поперёк —
## ±`ABUT_HALF_W_M`, вдоль — от `ABUT_BACK_M` под насыпью до `ABUT_IN_M` под мостом; низ — ниже
## земли перед ним. Верх — чуть ниже полосы травы насыпи; карниз и перила — сверху.
static func _abutment(kit: MeshKit, track: Track, b: Vector2, end_s: float, dir: float, env: EnvironmentSet,
		field: TerrainField) -> void:
	var f := _frame(track, end_s + dir * (ABUT_IN_M - ABUT_BACK_M) * 0.5, env)
	var front := _frame(track, end_s + dir * ABUT_IN_M, env)
	var road_y: float = track.sample(end_s).position.y
	var low: float = road_y - ABUT_DROP_M - 2.0
	if field != null:
		for k in 5:
			var p: Vector3 = front.center + front.right * lerpf(-ABUT_HALF_W_M, ABUT_HALF_W_M, float(k) / 4.0) + front.fwd * dir * 6.0
			low = minf(low, field.height_at(p.x, p.z) - 1.5)
	var top: float = road_y - 0.45
	var center := Vector3(f.center.x, (top + low) * 0.5, f.center.z)
	var basis := Basis(f.right, Vector3.UP, -f.fwd)
	kit.add_box(Transform3D(basis, center), Vector3(ABUT_HALF_W_M * 2.0, top - low, ABUT_IN_M + ABUT_BACK_M), C_CONCRETE)
	# Опорная площадка (подферменник) под концом балки — тёмная полоса на лицевой грани.
	var seat := Vector3(front.center.x, road_y - SLAB_M - GIRDER_DEPTH_M - 0.25, front.center.z) + front.fwd * dir * 0.05
	kit.add_box(Transform3D(basis, seat), Vector3(GIRDER_BOTTOM_HALF_M * 2.0 + 1.6, 0.5, 0.3), C_CONCRETE_SHADE)
