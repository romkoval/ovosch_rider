class_name RoadsideBuilder
extends RefCounted
## Обочина вдоль `Track` (REQ-D3D-07, арт-библия «Дорога»): гравийная кромка, бетонный
## бордюр, отбойник участками на внешней стороне поворотов (материал мира, цвет вершин)
## и полоса травы с кюветом до ~14 м от кромки (материал травы). Сечение одинаково на
## всей трассе; на внутренней стороне крутых поворотов ширина полосы ограничивается
## радиусом поворота, чтобы меш не выворачивался. Строится один раз в `set_track()`.

const STEP_M: float = 4.0
const MAX_RINGS: int = 700
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


## Построить `{roadside: MeshInstance3D, verge: MeshInstance3D}`.
static func build(track: Track, road_width_m: float, center_offset_m: float, world_material: Material,
		grass_material: Material, guardrail: bool, seed: int) -> Dictionary:
	var length: float = track.length_m()
	var n: int = clampi(int(ceil(length / STEP_M)), 8, MAX_RINGS)
	var step: float = length / float(n)
	var half: float = road_width_m * 0.5
	var curb_in: float = half + SHOULDER_M
	var curb_out: float = curb_in + CURB_W_M
	var kit := MeshKit.new()
	var verge := MeshKit.new()
	var sample := TrackSample.new()
	var pa := TrackSample.new()
	var pb := TrackSample.new()
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / 320.0
	# Кольца: центр дороги, правый вектор, кривизна.
	var centers := PackedVector3Array()
	var rights := PackedVector3Array()
	var ups := PackedVector3Array()
	var kappa := PackedFloat32Array()
	for i in n + 1:
		var s: float = float(i) * step if not (track.is_loop() and i == n) else 0.0
		track.sample_into(minf(s, length), sample)
		var r: Vector3 = sample.right()
		centers.append(sample.position + r * center_offset_m)
		rights.append(r)
		ups.append(sample.up)
		kappa.append(curvature(track, s, 10.0, pa, pb))
	for side_i in 2:
		var sgn: float = -1.0 if side_i == 0 else 1.0
		# Ограничение ширины на внутренней стороне поворота.
		var limits := PackedFloat32Array()
		for i in n + 1:
			var limit: float = 1.0e6
			var k: float = kappa[i]
			var inner_sgn: float = -1.0 if k > 0.0 else 1.0
			if absf(k) > 1e-5 and inner_sgn == sgn:
				limit = 0.8 / absf(k) - center_offset_m * sgn
			limits.append(maxf(limit, curb_out + 0.5))
		for i in n:
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
		_add_verge_side(verge, centers, rights, ups, limits, sgn, curb_out)
		if guardrail:
			_add_guardrail_side(kit, centers, rights, ups, kappa, step, sgn, curb_out, noise)
	var roadside := MeshInstance3D.new()
	roadside.name = "Roadside"
	roadside.mesh = kit.to_mesh(world_material)
	var verge_node := MeshInstance3D.new()
	verge_node.name = "Verge"
	verge_node.mesh = verge.to_mesh(grass_material)
	return {"roadside": roadside, "verge": verge_node}


static func _add_verge_side(kit: MeshKit, centers: PackedVector3Array, rights: PackedVector3Array,
		ups: PackedVector3Array, limits: PackedFloat32Array, sgn: float, curb_out: float) -> void:
	var cols: int = VERGE_PROFILE.size()
	var start: int = kit.vertices.size()
	for i in centers.size():
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
			kit.vertices.append(centers[i] + o * w + up * pr.y)
			kit.normals.append(nrm)
			kit.colors.append(col)
	for i in centers.size() - 1:
		for j in cols - 1:
			var a: int = start + i * cols + j
			var b: int = a + 1
			var c: int = a + cols
			var d: int = c + 1
			kit.indices.append_array(PackedInt32Array([a, b, c, b, d, c]))


static func _add_guardrail_side(kit: MeshKit, centers: PackedVector3Array, rights: PackedVector3Array,
		ups: PackedVector3Array, kappa: PackedFloat32Array, step: float, sgn: float, curb_out: float,
		noise: FastNoiseLite) -> void:
	var w: float = curb_out + GUARDRAIL_W_M
	var ground: float = _profile_y(GUARDRAIL_W_M)
	var count: int = centers.size()
	var active := PackedByteArray()
	active.resize(count)
	for i in count:
		var s: float = float(i) * step
		var k: float = kappa[i]
		var outer_sgn: float = 1.0 if k > 0.0 else -1.0
		# Участки: шум вдоль трассы + только внешняя сторона поворота (на прямой — справа).
		var want_side: float = outer_sgn if absf(k) > 1.0 / 900.0 else 1.0
		var on: bool = noise.get_noise_1d(s) > -0.05 and want_side == sgn
		active[i] = 1 if on else 0
	var post_size := Vector3(0.09, POST_H_M - ground + 0.15, 0.12)
	for i in count:
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
