class_name RoadsideBuilder
extends RefCounted
## Обочина вдоль `Track` (REQ-D3D-07, арт-библия «Дорога»): гравийная кромка, бетонный
## бордюр, отбойник участками на внешней стороне поворотов (материал мира, цвет вершин)
## и полоса травы с кюветом до ~14 м от кромки (материал травы). Сечение одинаково на
## всей трассе и строится от полотна (высота и нормаль — из `Track`, на подъёме обочина
## идёт вместе с дорогой, REQ-D3D-08 п.4); на внутренней стороне крутых поворотов ширина
## полосы ограничивается радиусом поворота, чтобы меш не выворачивался. Кольца — те же,
## что у дороги (`RoadBuilder.ring_distances`, шаг ~5 м на любой длине): край асфальта и
## кромка совпадают, щели «асфальт — бордюр» нет. Куски — как у дороги
## (`RoadBuilder.chunk_rings`): кусок 0 — узел, остальные — его дети с дальностью видимости.
## Строится один раз в `set_track()`.

const SHOULDER_M: float = 0.35
const CURB_W_M: float = 0.2
const CURB_H_M: float = 0.13
## Высота травы у бордюра (ниже верха бордюра).
const GRASS_AT_CURB_M: float = 0.07
## Профиль полосы травы: (отступ от внешней грани бордюра, высота над дорогой).
const VERGE_PROFILE: Array[Vector2] = [
	Vector2(0.0, GRASS_AT_CURB_M), Vector2(0.7, 0.05), Vector2(2.3, 0.0), Vector2(3.7, -0.35),
	Vector2(5.0, -0.15), Vector2(8.5, -0.25), Vector2(13.5, -0.8),
]
## Отбойник: отступ от внешней грани бордюра, высоты планки и стоек.
const GUARDRAIL_W_M: float = 1.8
const RAIL_BOTTOM_M: float = 0.42
const RAIL_TOP_M: float = 0.74
const POST_H_M: float = 0.68

const C_GRAVEL := Color(0.60, 0.57, 0.50, 0.0)
const C_CURB_TOP := Color(0.78, 0.78, 0.76, 0.0)
const C_CURB_FACE := Color(0.66, 0.66, 0.65, 0.0)
const C_RAIL := Color(0.70, 0.73, 0.77, 0.0)
const C_RAIL_GROOVE := Color(0.52, 0.55, 0.60, 0.0)
const C_POST := Color(0.40, 0.42, 0.45, 0.0)
const C_DRY := Color(0.98, 0.86, 0.62)
## Лоскуты полей на полосе травы начинаются за кюветом (отступ от внешней грани бордюра, м).
const VERGE_FIELD_FROM_M: float = 5.0


## Внешняя грань бордюра от центра дороги.
static func curb_outer_m(road_width_m: float) -> float:
	return road_width_m * 0.5 + SHOULDER_M + CURB_W_M


## Высота травы над дорогой на расстоянии `w` от центра дороги (для расстановки объектов).
static func verge_height(w: float, road_width_m: float) -> float:
	return _profile_y(w - curb_outer_m(road_width_m))


static func verge_width_m(road_width_m: float) -> float:
	return curb_outer_m(road_width_m) + VERGE_PROFILE[VERGE_PROFILE.size() - 1].x


## Кривизна трассы в точке, 1/м (знак: > 0 — поворот влево).
static func curvature(track: Track, s: float, probe_m: float, a: TrackSample, b: TrackSample) -> float:
	track.sample_into(s - probe_m, a)
	track.sample_into(s + probe_m, b)
	var fa := Vector2(a.forward.x, a.forward.z)
	var fb := Vector2(b.forward.x, b.forward.z)
	if fa.length_squared() < 1e-8 or fb.length_squared() < 1e-8:
		return 0.0
	var cross_y: float = a.forward.z * b.forward.x - a.forward.x * b.forward.z
	return cross_y / (2.0 * probe_m)


## Построить `{roadside: MeshInstance3D, verge: MeshInstance3D}` (корни кусков).
## `valley_field` (горы, T-087): отбойник не участками по поворотам, а со стороны долины —
## там, где рельеф за полосой травы заметно ниже полотна.
static func build(track: Track, road_width_m: float, center_offset_m: float, world_material: Material,
		grass_material: Material, guardrail: bool, seed: int, valley_field: TerrainField = null) -> Dictionary:
	var dist: PackedFloat64Array = RoadBuilder.ring_distances(track)
	var rings: int = dist.size()
	var last: int = rings - 1
	var half: float = road_width_m * 0.5
	var curb_in: float = half + SHOULDER_M
	var curb_out: float = curb_in + CURB_W_M
	var sample := TrackSample.new()
	var pa := TrackSample.new()
	var pb := TrackSample.new()
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / 320.0
	# Кольца: центр дороги, правый вектор, нормаль полотна, кривизна.
	var centers := PackedVector3Array()
	var rights := PackedVector3Array()
	var ups := PackedVector3Array()
	var kappa := PackedFloat32Array()
	for i in rings:
		var s: float = 0.0 if (track.is_loop() and i == last) else dist[i]
		track.sample_into(s, sample)
		var r: Vector3 = sample.right()
		centers.append(sample.position + r * center_offset_m)
		rights.append(r)
		ups.append(sample.up)
		kappa.append(curvature(track, s, 10.0, pa, pb))
	var limits: Array[PackedFloat32Array] = []
	var rails: Array[PackedByteArray] = []
	for side_i in 2:
		var sgn: float = -1.0 if side_i == 0 else 1.0
		# Ограничение ширины на внутренней стороне поворота.
		var limit_side := PackedFloat32Array()
		for i in rings:
			var limit: float = 1.0e6
			var k: float = kappa[i]
			var inner_sgn: float = -1.0 if k > 0.0 else 1.0
			if absf(k) > 1e-5 and inner_sgn == sgn:
				limit = 0.8 / absf(k) - center_offset_m * sgn
			limit_side.append(maxf(limit, curb_out + 0.5))
		limits.append(limit_side)
		if not guardrail:
			rails.append(PackedByteArray())
		elif valley_field != null:
			rails.append(valley_rails(centers, rights, sgn, valley_field))
		else:
			rails.append(_guardrail_active(dist, kappa, sgn, noise))
	var chunks: int = RoadBuilder.chunk_count(track)
	var roadside: MeshInstance3D = null
	var verge_root: MeshInstance3D = null
	for c in chunks:
		var span: Vector2i = RoadBuilder.chunk_rings(track, c)
		var kit := MeshKit.new()
		var verge := MeshKit.new()
		for side_i in 2:
			var sgn: float = -1.0 if side_i == 0 else 1.0
			for i in range(span.x, span.y):
				var c0: Vector3 = centers[i]
				var c1: Vector3 = centers[i + 1]
				var o0: Vector3 = rights[i] * sgn
				var o1: Vector3 = rights[i + 1] * sgn
				var u0: Vector3 = ups[i]
				var u1: Vector3 = ups[i + 1]
				# Гравийная кромка.
				kit.add_quad(c0 + o0 * half, c1 + o1 * half, c1 + o1 * curb_in, c0 + o0 * curb_in, u0, C_GRAVEL)
				# Бордюр: внутренняя грань, верх, внешняя грань.
				kit.add_quad(c0 + o0 * curb_in, c1 + o1 * curb_in, c1 + o1 * curb_in + u1 * CURB_H_M,
					c0 + o0 * curb_in + u0 * CURB_H_M, -o0, C_CURB_FACE)
				kit.add_quad(c0 + o0 * curb_in + u0 * CURB_H_M, c1 + o1 * curb_in + u1 * CURB_H_M,
					c1 + o1 * curb_out + u1 * CURB_H_M, c0 + o0 * curb_out + u0 * CURB_H_M, u0, C_CURB_TOP)
				kit.add_quad(c0 + o0 * curb_out + u0 * CURB_H_M, c1 + o1 * curb_out + u1 * CURB_H_M,
					c1 + o1 * curb_out + u1 * (GRASS_AT_CURB_M - 0.02), c0 + o0 * curb_out + u0 * (GRASS_AT_CURB_M - 0.02),
					o0, C_CURB_FACE)
			_add_verge_side(verge, centers, rights, ups, limits[side_i], sgn, curb_out, span)
			if guardrail:
				var post_end: int = span.y if (span.y == last and not track.is_loop()) else span.y - 1
				_add_guardrail_side(kit, centers, rights, ups, rails[side_i], sgn, curb_out, Vector2i(span.x, post_end))
		var side_node := MeshInstance3D.new()
		side_node.mesh = kit.to_mesh(world_material)
		var verge_node := MeshInstance3D.new()
		verge_node.mesh = verge.to_mesh(grass_material)
		if chunks > 1:
			for node: MeshInstance3D in [side_node, verge_node]:
				node.visibility_range_end = RoadBuilder.RANGE_M + node.get_aabb().size.length() * 0.5
		if roadside == null:
			side_node.name = "Roadside"
			verge_node.name = "Verge"
			roadside = side_node
			verge_root = verge_node
		else:
			side_node.name = "Roadside_%02d" % c
			verge_node.name = "Verge_%02d" % c
			roadside.add_child(side_node)
			verge_root.add_child(verge_node)
	return {"roadside": roadside, "verge": verge_root}


## Столбиков на сторону: с шагом `spacing_m` по всей трассе (плотность на километр,
## T-066); потолок — восьмая часть общего потолка MultiMesh на сторону.
static func posts_per_side(track: Track, spacing_m: float) -> int:
	if spacing_m <= 0.0:
		return 0
	return mini(int(track.length_m() / spacing_m), PerfBudget.MAX_MULTIMESH_INSTANCES / 8)


## Сигнальные столбики по обеим сторонам дороги с шагом `prop_spacing_m` (REQ-D3D-03,
## D3D-07): один `MultiMeshInstance3D` «Props»; на длинной трассе — куски вдоль трассы с
## дальностью видимости `PerfBudget.RANGE_POSTS_M` (кусок 0 — сам узел, остальные — его
## дети). null — столбики выключены.
static func build_posts(track: Track, env: EnvironmentSet, mesh: Mesh) -> MultiMeshInstance3D:
	var placed: Dictionary = place_posts(track, env)
	var xforms: Array[Transform3D] = placed["xf"]
	if xforms.is_empty():
		return null
	var chunks: int = placed["chunks"]
	var no_colors: Array[Color] = []
	return SceneryBuilder.chunked_multimesh("Props", mesh, xforms, no_colors, placed["chunk"], chunks,
		PerfBudget.RANGE_POSTS_M if chunks > 1 else 0.0)


## Расстановка столбиков без узлов: `{xf: Array[Transform3D], chunk: PackedInt32Array, chunks: int}`
## (позиции экземпляров готовых MultiMesh на headless-сервере недоступны — тесты смотрят сюда).
static func place_posts(track: Track, env: EnvironmentSet) -> Dictionary:
	var xforms: Array[Transform3D] = []
	var chunk := PackedInt32Array()
	var per_side: int = posts_per_side(track, env.prop_spacing_m)
	if per_side <= 0:
		return {"xf": xforms, "chunk": chunk, "chunks": 1}
	var count: int = per_side * 2
	var chunk_m: float = PerfBudget.chunk_length_m(track)
	var chunks: int = PerfBudget.chunk_count(track, chunk_m)
	var sample := TrackSample.new()
	var ground: float = verge_height(env.prop_offset_m, env.road_width_m) - 0.05
	var spacing: float = maxf(env.prop_spacing_m, track.length_m() / float(per_side))
	for i in count:
		var s: float = float(i / 2) * spacing
		track.sample_into(s, sample)
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var right: Vector3 = sample.right()
		var pos: Vector3 = sample.position + right * (env.road_center_offset_m + side * env.prop_offset_m) + sample.up * ground
		xforms.append(Transform3D(Basis.looking_at(sample.forward, sample.up), pos))
		chunk.append(PerfBudget.chunk_of(s, chunk_m, chunks))
	return {"xf": xforms, "chunk": chunk, "chunks": chunks}


static func _add_verge_side(kit: MeshKit, centers: PackedVector3Array, rights: PackedVector3Array,
		ups: PackedVector3Array, limits: PackedFloat32Array, sgn: float, curb_out: float, span: Vector2i) -> void:
	var cols: int = VERGE_PROFILE.size()
	var start: int = kit.vertices.size()
	for i in range(span.x, span.y + 1):
		var o: Vector3 = rights[i] * sgn
		var up: Vector3 = ups[i]
		var prev_w: float = curb_out - 0.01
		for j in cols:
			var pr: Vector2 = VERGE_PROFILE[j]
			var w: float = minf(curb_out + pr.x, limits[i])
			w = maxf(w, prev_w + 0.01)
			prev_w = w
			# Нормаль сечения: по среднему наклону соседних отрезков профиля.
			var ja: int = maxi(j - 1, 0)
			var jb: int = mini(j + 1, cols - 1)
			var slope: float = (VERGE_PROFILE[jb].y - VERGE_PROFILE[ja].y) / maxf(VERGE_PROFILE[jb].x - VERGE_PROFILE[ja].x, 1e-3)
			var nrm: Vector3 = (up - o * slope).normalized()
			var dry: float = 1.0 - clampf(pr.x / 1.6, 0.0, 1.0)
			var col: Color = MeshKit.lin(Color.WHITE.lerp(C_DRY, dry))
			# Альфа — «не поле» для шейдера травы (T-083): у кромки 1, за кюветом лоскуты полей
			# набора окружения начинаются уже на полосе травы (как на рельефе, `TerrainField.field_color`).
			col.a = 1.0 - smoothstep(VERGE_FIELD_FROM_M, VERGE_PROFILE[VERGE_PROFILE.size() - 1].x, pr.x)
			kit.vertices.append(centers[i] + o * w + up * pr.y)
			kit.normals.append(nrm)
			kit.colors.append(col)
	for i in span.y - span.x:
		for j in cols - 1:
			var a: int = start + i * cols + j
			var b: int = a + 1
			var c: int = a + cols
			var d: int = c + 1
			kit.indices.append_array(PackedInt32Array([a, b, c, b, d, c]))


## Участки отбойника по кольцам: шум вдоль трассы + только внешняя сторона поворота (на
## прямой — справа).
static func _guardrail_active(dist: PackedFloat64Array, kappa: PackedFloat32Array, sgn: float,
		noise: FastNoiseLite) -> PackedByteArray:
	var active := PackedByteArray()
	active.resize(dist.size())
	for i in dist.size():
		var k: float = kappa[i]
		var outer_sgn: float = 1.0 if k > 0.0 else -1.0
		var want_side: float = outer_sgn if absf(k) > 1.0 / 900.0 else 1.0
		var on: bool = noise.get_noise_1d(dist[i]) > -0.05 and want_side == sgn
		active[i] = 1 if on else 0
	return active


## Отбойник со стороны долины: перепад «полотно − рельеф» на 22 и 40 м от кромки на стороне
## `sgn` больше `VALLEY_DROP_M` и больше, чем на другой стороне (по окну ±`VALLEY_WINDOW`
## колец); разрывы короче `VALLEY_GAP` колец заполняются.
const VALLEY_DROP_M: float = 2.5
const VALLEY_WINDOW: int = 8
const VALLEY_GAP: int = 10


static func valley_rails(centers: PackedVector3Array, rights: PackedVector3Array, sgn: float,
		field: TerrainField) -> PackedByteArray:
	var n: int = centers.size()
	var diff := PackedFloat32Array()
	var drop := PackedFloat32Array()
	diff.resize(n)
	drop.resize(n)
	for i in n:
		var c: Vector3 = centers[i]
		var d_side: float = 0.0
		var d_other: float = 0.0
		for w in [22.0, 40.0]:
			var a: Vector3 = c + rights[i] * sgn * float(w)
			var b: Vector3 = c - rights[i] * sgn * float(w)
			d_side += (c.y - field.height_at(a.x, a.z)) * 0.5
			d_other += (c.y - field.height_at(b.x, b.z)) * 0.5
		drop[i] = d_side
		diff[i] = d_side - d_other
	var active := PackedByteArray()
	active.resize(n)
	for i in n:
		var sd: float = 0.0
		var sf: float = 0.0
		for k in range(-VALLEY_WINDOW, VALLEY_WINDOW + 1):
			var j: int = clampi(i + k, 0, n - 1)
			sd += drop[j]
			sf += diff[j]
		active[i] = 1 if sd > VALLEY_DROP_M * float(VALLEY_WINDOW * 2 + 1) and sf > 0.0 else 0
	var last_on: int = -1
	for i in n:
		if active[i] == 0:
			continue
		if last_on >= 0 and i - last_on > 1 and i - last_on <= VALLEY_GAP:
			for j in range(last_on + 1, i):
				active[j] = 1
		last_on = i
	return active


## Стойки на кольцах `posts.x..posts.y`, планки — между соседними активными кольцами.
static func _add_guardrail_side(kit: MeshKit, centers: PackedVector3Array, rights: PackedVector3Array,
		ups: PackedVector3Array, active: PackedByteArray, sgn: float, curb_out: float, posts: Vector2i) -> void:
	var w: float = curb_out + GUARDRAIL_W_M
	var ground: float = _profile_y(GUARDRAIL_W_M)
	var count: int = centers.size()
	var post_size := Vector3(0.09, POST_H_M - ground + 0.15, 0.12)
	for i in range(posts.x, posts.y + 1):
		if active[i] == 0:
			continue
		var o: Vector3 = rights[i] * sgn
		var up: Vector3 = ups[i]
		var fwd: Vector3 = up.cross(rights[i]).normalized()
		var base: Vector3 = centers[i] + o * (w + 0.08)
		var post_center: Vector3 = base + up * (ground - 0.15 + post_size.y * 0.5)
		kit.add_box(Transform3D(Basis(rights[i], up, -fwd), post_center), post_size, C_POST)
		if i + 1 >= count or active[i + 1] == 0:
			continue
		var o1: Vector3 = rights[i + 1] * sgn
		var up1: Vector3 = ups[i + 1]
		var p0: Vector3 = centers[i] + o * w
		var p1: Vector3 = centers[i + 1] + o1 * w
		# W-профиль планки: три полосы с наклонёнными нормалями — тун-свет даёт рёбра.
		var rows := [
			[RAIL_BOTTOM_M, RAIL_BOTTOM_M + 0.1, -0.5, C_RAIL],
			[RAIL_BOTTOM_M + 0.1, RAIL_TOP_M - 0.1, 0.0, C_RAIL_GROOVE],
			[RAIL_TOP_M - 0.1, RAIL_TOP_M, 0.5, C_RAIL],
		]
		for row in rows:
			var y0: float = ground + float(row[0])
			var y1: float = ground + float(row[1])
			var tilt: float = float(row[2])
			var col: Color = row[3]
			var n_front: Vector3 = (-o + up * tilt).normalized()
			kit.add_quad(p0 + up * y0, p1 + up1 * y0, p1 + up1 * y1, p0 + up * y1, n_front, col)
			var back_off: Vector3 = o * 0.03
			kit.add_quad(p0 + back_off + up * y0, p1 + o1 * 0.03 + up1 * y0, p1 + o1 * 0.03 + up1 * y1,
				p0 + back_off + up * y1, o, C_RAIL_GROOVE)
		kit.add_quad(p0 + up * (ground + RAIL_TOP_M), p1 + up1 * (ground + RAIL_TOP_M),
			p1 + o1 * 0.03 + up1 * (ground + RAIL_TOP_M), p0 + o * 0.03 + up * (ground + RAIL_TOP_M), up, C_RAIL)


static func _profile_y(x_from_curb: float) -> float:
	if x_from_curb <= VERGE_PROFILE[0].x:
		return VERGE_PROFILE[0].y
	for i in range(1, VERGE_PROFILE.size()):
		if x_from_curb <= VERGE_PROFILE[i].x:
			var a: Vector2 = VERGE_PROFILE[i - 1]
			var b: Vector2 = VERGE_PROFILE[i]
			return lerpf(a.y, b.y, (x_from_curb - a.x) / (b.x - a.x))
	return VERGE_PROFILE[VERGE_PROFILE.size() - 1].y
