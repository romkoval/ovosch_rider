class_name RiderModel
extends RefCounted
## Процедурная модель велосипедиста (REQ-D3D-04, REQ-D3D-07, арт-библия «Велосипедист»):
## шоссейный велосипед (рама, вилка, руль, седло, колёса с высоким ободом, шатуны со
## звездой) и гонщик (шлем, очки, джерси с лампасами, шорты, руки на тормозных ручках,
## ноги из бедра/голени/туфли). All parts share one rider toon material: a face's color is
## its region in UV0 (`MeshKit.region`, table `RiderRegions`), the region color is the material
## palette (T-106a3). Vertex colors (`C_*` constants) are not used by the game: the artist pack
## paints `bike_reference.glb` with them.
##
## Система координат — как у `Rider`: −Z вперёд, Y вверх, начало — на земле под кареткой.
## Гонщик — манекен на скелете контракта `RiderRig` (T-106a2): сетки `Body`, `Hair`, `Helmet`,
## `Eyewear`, `ShoeL/R` со скиннингом (вес 1 на кость), позы костей в кадре ставит `Rider`
## (IK ног и рук, покачивание, пружина хвоста). Меши строятся один раз на процесс
## (статический кэш).

## Велосипед подогнан под контракт скелета (`RiderRig`, T-106a1): верх седла 0.965 м под
## точкой опоры таза S, центр ладони на тормозной ручке (±0.21, 0.885, −0.62), шатун 0.17 м,
## ось педали ±0.115 м, контактные педали. Рама, база 0.99 м и колёса 700c — как были.
const BB := RiderRig.BB
const REAR_AXLE := RiderRig.REAR_AXLE
const FRONT_AXLE := RiderRig.FRONT_AXLE
const CRANK_LENGTH_M: float = RiderRig.CRANK_LENGTH_M
const PEDAL_X_M: float = RiderRig.PEDAL_X_M
## Центр ладони — над верхом тормозной ручки на половину толщины кисти в перчатке.
const HOOD_PALM_CLEARANCE_M: float = 0.015
## Шатун по X (середина плеча шатуна) и толщина плеча: внешняя грань — 0.09 м, корпус педали
## (ширина 0.054 м) — снаружи, его середина на оси педали ±0.115 м.
const CRANK_ARM_X_M: float = 0.08
const PEDAL_BODY_WIDTH_M: float = 0.054
## Кости шатуна (`Skeleton3D` под узлом `Crank`): шатуны со звездой и две педали, которые
## держат угол стопы θ(φ) (`RiderRig.foot_pitch_rad`) при вращении шатуна.
const CRANK_BONES := ["crank", "pedal.R", "pedal.L"]
## Начала костей педалей в системе узла `Crank` (локальный −X — правая сторона, длина по +Y).
const PEDAL_R_REST := Vector3(-RiderRig.PEDAL_X_M, RiderRig.CRANK_LENGTH_M, 0.0)
const PEDAL_L_REST := Vector3(RiderRig.PEDAL_X_M, -RiderRig.CRANK_LENGTH_M, 0.0)
## Манекен (T-106a2): нынешние примитивы на костях контракта `RiderRig` — `Skeleton3D` гонщика
## (25 костей), каждая часть привязана жёстко (вес 1) к своей кости. Две фигуры (`m`, `f`) —
## разный объём плеч, талии, таза и конечностей при общих суставах (арт-библия «Пропорции и
## посадка», таблица фигур); две причёски (`short`, `tail` — хвост на `hair_tail.1/2`).
## Тазобедренный сустав правой ноги (начало `thigh.R`), длины бедра и голени — из контракта.
const HIP := Vector3(0.09, 1.05, 0.19)
const THIGH_M: float = 0.440124
const SHIN_M: float = 0.439346
## Подсказка сгиба колена — вперёд и чуть вверх.
const KNEE_HINT := Vector3(0.0, 0.25, -1.0)
## Объём фигур, м (полуширины и радиусы; таблица фигур спеки): плечи снаружи по дельтам,
## талия, таз по шортам — полуширины; рука у плеча и запястье, бедро у шорт и у колена, икра,
## лодыжка, шея — радиусы.
const FIGURES: Dictionary = {
	"m": {"shoulder_hw": 0.225, "waist_hw": 0.150, "hips_hw": 0.175, "arm_r": 0.045, "wrist_r": 0.0275,
		"thigh_r": 0.0875, "knee_r": 0.0575, "calf_r": 0.060, "ankle_r": 0.031, "neck_r": 0.060},
	"f": {"shoulder_hw": 0.205, "waist_hw": 0.135, "hips_hw": 0.180, "arm_r": 0.040, "wrist_r": 0.025,
		"thigh_r": 0.085, "knee_r": 0.055, "calf_r": 0.055, "ankle_r": 0.029, "neck_r": 0.0525},
}
const HAIR_STYLES: Array[String] = ["short", "tail"]
## Голова манекена: центр и полуоси (спека: (0, 1.45, −0.36), 0.155 × 0.22 × 0.20 м).
const HEAD_CENTER := Vector3(0.0, 1.45, -0.36)
const HEAD_RADII := Vector3(0.0775, 0.11, 0.10)

# Палитра формы (sRGB). Альфа — вес контура.
const C_FRAME := Color(0.88, 0.16, 0.12, 1.0)
const C_ACCENT := Color(0.98, 0.78, 0.14, 1.0)
const C_BLACK := Color(0.09, 0.09, 0.10, 1.0)
const C_SILVER := Color(0.70, 0.71, 0.74, 1.0)
const C_JERSEY := Color(0.95, 0.95, 0.96, 1.0)
const C_JERSEY_RED := Color(0.86, 0.14, 0.16, 1.0)
const C_JERSEY_BLUE := Color(0.18, 0.28, 0.72, 1.0)
const C_SHORTS := Color(0.16, 0.18, 0.44, 1.0)
const C_SKIN := Color(0.87, 0.64, 0.50, 1.0)
const C_HELMET := Color(0.97, 0.97, 0.98, 1.0)
const C_SOCK := Color(0.97, 0.97, 0.97, 1.0)
const C_SHOE := Color(0.95, 0.95, 0.95, 1.0)
const C_TIRE := Color(0.10, 0.10, 0.11, 1.0)
const C_RIM := Color(0.13, 0.13, 0.15, 0.0)
const C_RIM_STRIPE := Color(0.90, 0.70, 0.22, 0.0)

const C_HAIR := Color(0.24, 0.15, 0.09, 1.0)
const C_GLOVE := Color(0.09, 0.09, 0.10, 1.0)

## Rim variants (`bike.rims`): inner radius of the rim side, m. The tyre bead is at 0.308 m:
## `deep` ≈ 50 mm, `shallow` ≈ 30 mm.
const RIMS: Dictionary = {"deep": 0.255, "shallow": 0.278}

static var _cache: Dictionary = {}
static var _skin: Skin


## Все меши модели: велосипед (`bike`, `wheel`, `rear_wheel`, `crank`; wheels with the
## `shallow` rim — `wheel_shallow`, `rear_wheel_shallow`) и манекен —
## `body_m`, `body_f`, `hair_short`, `hair_tail`, `helmet`, `eyewear`, `shoe_l`, `shoe_r`
## (скиннинг на скелет `RiderRig`, `rider_skin()`).
static func meshes(material: Material) -> Dictionary:
	var key: int = material.get_instance_id() if material != null else 0
	if _cache.has(key):
		return _cache[key]
	var out := {
		"bike": _bike().to_mesh(material),
		"wheel": _wheel(false).to_mesh(material),
		"rear_wheel": _wheel(true).to_mesh(material),
		"wheel_shallow": _wheel(false, "shallow").to_mesh(material),
		"rear_wheel_shallow": _wheel(true, "shallow").to_mesh(material),
		"crank": crank_mesh(material),
		"helmet": _skinned([[_helmet(), "head"]], material),
		"eyewear": _skinned([[_eyewear(), "head"]], material),
		"shoe_l": _skinned([[_shoe(".L"), "foot.L"]], material),
		"shoe_r": _skinned([[_shoe(".R"), "foot.R"]], material),
	}
	for figure in FIGURES:
		out["body_" + figure] = _skinned(_body_parts(figure), material)
	for style in HAIR_STYLES:
		out["hair_" + style] = _skinned(_hair_parts(style), material)
	_cache[key] = out
	return out


## `Skin` манекена: привязка `i` — кость `i` контракта (`RiderRig.BONES`), поза привязки —
## обратный глобальный rest кости. Один на все сетки гонщика.
static func rider_skin() -> Skin:
	if _skin == null:
		_skin = Skin.new()
		for b in RiderRig.BONES:
			_skin.add_named_bind(b[0], Transform3D(RiderRig.rest_basis(b[0]), b[2]).affine_inverse())
	return _skin


## Сетка со скиннингом из частей `[MeshKit в системе гонщика (rest), имя кости]`, вес 1 на
## кость части (сокеты весов не несут).
static func _skinned(parts: Array, material: Material) -> ArrayMesh:
	var k := MeshKit.new()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for p in parts:
		var part: MeshKit = p[0]
		var bone: int = RiderRig.index_of(p[1])
		assert(bone >= 0 and not RiderRig.is_socket(p[1]), "RiderModel: part on unknown or socket bone %s" % p[1])
		# Regions per face and outline normals per part: smoothing never mixes two bones.
		part.finalize_regions()
		_append(k, part)
		for i in part.vertices.size():
			bones.append_array(PackedInt32Array([bone, 0, 0, 0]))
			weights.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	return _skinned_mesh(k, bones, weights, material)


## Surface of a region kit whose parts are already finalized (`MeshKit.finalize_regions`):
## UV0 regions, outline normals in TANGENT, bones and weights; no vertex colors.
static func _skinned_mesh(k: MeshKit, bones: PackedInt32Array, weights: PackedFloat32Array, material: Material) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = k.vertices
	arrays[Mesh.ARRAY_NORMAL] = k.normals
	arrays[Mesh.ARRAY_TANGENT] = k.outline_tangents()
	arrays[Mesh.ARRAY_TEX_UV] = k.uvs
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = k.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material != null:
		mesh.surface_set_material(0, material)
	return mesh


## Колено двухзвенной цепи «бедро → голень» (или «плечо → предплечье»): решение в плоскости
## через `root`, `target` и подсказку сгиба. Цель дальше суммы длин — подтягивается.
static func two_bone_joint(root: Vector3, target: Vector3, l1: float, l2: float, hint: Vector3) -> Vector3:
	var d: Vector3 = target - root
	var dist: float = clampf(d.length(), absf(l1 - l2) + 1e-3, l1 + l2 - 1e-4)
	var dn: Vector3 = d.normalized() if d.length_squared() > 1e-10 else Vector3.DOWN
	var a: float = (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h: float = sqrt(maxf(l1 * l1 - a * a, 0.0))
	var bend: Vector3 = hint - dn * dn.dot(hint)
	if bend.length_squared() < 1e-10:
		bend = Vector3.FORWARD
	return root + dn * a + bend.normalized() * h


## Система звена «локоть → точка хвата» руки: X — от локтя к точке хвата, Z — нормаль плоскости
## «плечо — локоть — точка хвата», Y = Z × X (в плоскости руки). Без аллокаций (кадр).
static func arm_frame(shoulder: Vector3, elbow: Vector3, grip: Vector3) -> Basis:
	var u: Vector3 = (grip - elbow).normalized()
	var n: Vector3 = (elbow - shoulder).cross(u)
	n = n.normalized() if n.length_squared() > 1e-12 else Vector3.RIGHT
	return Basis(u, n.cross(u), n)


## Трансформ кости, меш которой идёт от начала координат вдоль −Y: от `from` к `to`.
static func bone_transform(from: Vector3, to: Vector3) -> Transform3D:
	var y: Vector3 = from - to
	if y.length_squared() < 1e-10:
		y = Vector3.UP
	y = y.normalized()
	var x: Vector3 = Vector3.RIGHT - y * y.x
	x = x.normalized() if x.length_squared() > 1e-10 else Vector3.FORWARD
	var z: Vector3 = x.cross(y)
	return Transform3D(Basis(x, y, z), from)


## Колено двухзвенной цепи с заданной координатой X (сдвиг полюса IK вбок, «колено вбок»
## спеки): из окружности решений (длины `l1`, `l2` точно) берётся точка с `x` (если её нет —
## ближайшая по X), ближайшая к направлению подсказки `hint`. Без аллокаций (кадр).
static func two_bone_joint_x(root: Vector3, target: Vector3, l1: float, l2: float, hint: Vector3, x: float) -> Vector3:
	var d: Vector3 = target - root
	var dist: float = clampf(d.length(), absf(l1 - l2) + 1e-3, l1 + l2 - 1e-4)
	var dn: Vector3 = d.normalized() if d.length_squared() > 1e-10 else Vector3.DOWN
	var a: float = (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h: float = sqrt(maxf(l1 * l1 - a * a, 0.0))
	var u: Vector3 = hint - dn * dn.dot(hint)
	if u.length_squared() < 1e-10:
		u = Vector3.FORWARD
	u = u.normalized()
	var v: Vector3 = dn.cross(u)
	var c: Vector3 = root + dn * a
	var ax: float = h * u.x
	var bx: float = h * v.x
	var r: float = sqrt(ax * ax + bx * bx)
	if r < 1e-9:
		return c + u * h
	var gamma: float = atan2(bx, ax)
	var delta: float = acos(clampf((x - c.x) / r, -1.0, 1.0))
	var b1: float = wrapf(gamma - delta, -PI, PI)
	var b2: float = wrapf(gamma + delta, -PI, PI)
	var beta: float = b1 if absf(b1) <= absf(b2) else b2
	return c + (u * cos(beta) + v * sin(beta)) * h


## Оси кости по направлению `dir` (начало → окончание), как у контракта (`RiderRig.rest_basis`,
## бриф 5.3): Y — вдоль кости, X — к мировой X Blender (Godot −X), Z = X × Y. Без аллокаций.
static func bone_basis(dir: Vector3) -> Basis:
	var y: Vector3 = dir.normalized() if dir.length_squared() > 1e-12 else Vector3.UP
	var x: Vector3 = Vector3.LEFT - y * Vector3.LEFT.dot(y)
	x = x.normalized() if x.length_squared() > 1e-10 else Vector3.FORWARD
	return Basis(x, y, x.cross(y))


static func _bike() -> MeshKit:
	var k := MeshKit.new()
	var seat_dir := Vector3(0.0, 0.959, 0.284)
	var st_top: Vector3 = BB + seat_dir * 0.53
	var ht_top := Vector3(0.0, 0.83, -0.40)
	var ht_bot := Vector3(0.0, 0.69, -0.445)
	# Frame: top, down, seat and head tubes and chainstays — main color; seat stays — accent
	# (small parts, from behind two thin lines: checklist F11).
	k.region = RiderRegions.FRAME_MAIN
	k.add_tube(st_top + Vector3(0, -0.01, -0.01), ht_top + Vector3(0, -0.02, 0.0), Vector2(0.02, 0.02), Vector2(0.021, 0.021), C_ACCENT, 10)
	k.add_tube(BB, ht_bot, Vector2(0.03, 0.026), Vector2(0.026, 0.024), C_FRAME, 10)
	k.add_tube(BB, st_top, Vector2(0.022, 0.022), Vector2(0.019, 0.019), C_FRAME, 10)
	k.add_tube(ht_bot + Vector3(0, -0.02, -0.006), ht_top + Vector3(0, 0.02, 0.006), Vector2(0.025, 0.025), Vector2(0.024, 0.024), C_FRAME, 10)
	for sx in [-1.0, 1.0]:
		var axle: Vector3 = REAR_AXLE + Vector3(0.062 * sx, 0.0, 0.0)
		k.add_tube(BB + Vector3(0.035 * sx, 0.0, 0.02), axle, Vector2(0.013, 0.015), Vector2(0.009, 0.009), C_FRAME, 7)
		k.region = RiderRegions.FRAME_ACCENT
		k.add_tube(st_top + Vector3(0.022 * sx, -0.02, 0.0), axle, Vector2(0.011, 0.011), Vector2(0.008, 0.008), C_ACCENT, 7)
		k.region = RiderRegions.FRAME_MAIN
		# Вилка.
		k.add_tube(ht_bot + Vector3(0.03 * sx, 0.0, 0.0), FRONT_AXLE + Vector3(0.05 * sx, 0.0, 0.0), Vector2(0.016, 0.02), Vector2(0.009, 0.01), C_FRAME, 7)
	_add_saddle(k, seat_dir, st_top)
	_add_cockpit(k, ht_bot, ht_top)
	# Цепь и задний переключатель (правая сторона, +X).
	var cog := REAR_AXLE + Vector3(0.045, 0.0, 0.0)
	var ring := BB + Vector3(0.065, 0.0, 0.0)
	k.region = RiderRegions.METAL
	k.add_tube(ring + Vector3(0, 0.105, 0), cog + Vector3(0, 0.05, 0), Vector2(0.005, 0.005), Vector2(0.005, 0.005), Color(0.3, 0.3, 0.32, 0.0), 5, false)
	k.add_tube(ring + Vector3(0, -0.105, 0), cog + Vector3(0, -0.09, 0.01), Vector2(0.005, 0.005), Vector2(0.005, 0.005), Color(0.3, 0.3, 0.32, 0.0), 5, false)
	k.region = RiderRegions.COMPONENT
	k.add_box(Transform3D(Basis.IDENTITY, cog + Vector3(0.01, -0.07, 0.01)), Vector3(0.02, 0.07, 0.03), C_BLACK)
	# Флягодержатель с флягой на нижней трубе.
	var bottle_a: Vector3 = BB.lerp(ht_bot, 0.25) + Vector3(0, 0.05, 0.0)
	var bottle_b: Vector3 = BB.lerp(ht_bot, 0.62) + Vector3(0, 0.05, 0.0)
	k.region = RiderRegions.BOTTLE
	k.add_tube(bottle_a, bottle_b, Vector2(0.034, 0.034), Vector2(0.034, 0.034), C_JERSEY_BLUE, 9)
	return k


## Седло под точку опоры таза S (`pelvis`): верх под S — ровно 0.965 м, длина 0.27 м, ширина
## сзади 0.13 м, задний край в 0.065 м позади S. Лофт по сечениям-суперэллипсам (верх почти
## плоский поперёк), нос чуть ниже, задний край с подъёмом; штырь и рамки под седлом.
static func _add_saddle(k: MeshKit, seat_dir: Vector3, st_top: Vector3) -> void:
	var s: Vector3 = RiderRig.head("pelvis")
	var rear_z: float = s.z + RiderRig.SADDLE_REAR_BEHIND_S_M
	var nose_z: float = rear_z - RiderRig.SADDLE_LENGTH_M
	var stations: int = 10
	var sides: int = 12
	var expo: float = 3.0
	var col := MeshKit.lin(C_BLACK)
	k.region = RiderRegions.COMPONENT
	var start: int = k.vertices.size()
	var centers: Array[Vector3] = []
	for i in stations + 1:
		var t: float = float(i) / float(stations)
		var z: float = lerpf(nose_z, rear_z, t)
		var w: float = lerpf(0.018, RiderRig.SADDLE_REAR_WIDTH_M * 0.5, smoothstep(0.25, 0.92, t))
		var top: float = s.y - 0.008 * (1.0 - smoothstep(0.0, 0.6, t)) + 0.006 * smoothstep(0.86, 1.0, t)
		var hh: float = lerpf(0.022, 0.032, t) * 0.5
		var yc: float = top - hh
		centers.append(Vector3(0.0, yc, z))
		for j in sides + 1:
			var a: float = TAU * float(j) / float(sides)
			var c: float = cos(a)
			var sn: float = sin(a)
			var px: float = w * signf(c) * pow(absf(c), 2.0 / expo)
			var py: float = hh * signf(sn) * pow(absf(sn), 2.0 / expo)
			var nx: float = signf(c) * pow(absf(c), 2.0 * (expo - 1.0) / expo) / w
			var ny: float = signf(sn) * pow(absf(sn), 2.0 * (expo - 1.0) / expo) / hh
			k.add_vertex(Vector3(px, yc + py, z), Vector3(nx, ny, 0.0).normalized(), col)
	for i in stations:
		for j in sides:
			var i0: int = start + i * (sides + 1) + j
			var i1: int = i0 + sides + 1
			k.indices.append_array(PackedInt32Array([i0, i1, i0 + 1, i0 + 1, i1, i1 + 1]))
	# Торцы — веер из центра сечения.
	for end in [0, stations]:
		var ring0: int = start + end * (sides + 1)
		var c0: int = k.add_vertex(centers[end], Vector3(0.0, 0.0, -1.0 if end == 0 else 1.0), col)
		for j in sides:
			k.indices.append_array(PackedInt32Array([c0, ring0 + j, ring0 + j + 1]))
	# Подседельный штырь до замка рамок (на 4 см ниже верха седла) и рамки.
	var clamp_y: float = s.y - 0.04
	var clamp: Vector3 = BB + seat_dir * ((clamp_y - BB.y) / seat_dir.y)
	k.add_tube(st_top, clamp, Vector2(0.014, 0.014), Vector2(0.014, 0.014), C_BLACK, 8)
	k.add_box(Transform3D(Basis.IDENTITY, clamp), Vector3(0.036, 0.016, 0.04), C_BLACK)
	k.region = RiderRegions.METAL
	for sx in [-1.0, 1.0]:
		k.add_tube(Vector3(0.022 * sx, clamp_y + 0.002, nose_z + 0.06), Vector3(0.03 * sx, clamp_y + 0.006, rear_z - 0.04),
			Vector2(0.0035, 0.0035), Vector2(0.0035, 0.0035), C_SILVER, 5, false)


## Вынос и руль: верхний хват, «бараны», тормозные ручки (корпус, рог, рычаг). Центр ладони
## на ручке — `grip.L/R` контракта: верх корпуса ручки ниже него на `HOOD_PALM_CLEARANCE_M`.
static func _add_cockpit(k: MeshKit, ht_bot: Vector3, ht_top: Vector3) -> void:
	var grip: Vector3 = RiderRig.head("grip.R")
	var bar_y: float = grip.y - 0.03
	var clamp_z: float = grip.z + 0.09
	var steer: Vector3 = (ht_top - ht_bot).normalized()
	var stem_start: Vector3 = ht_top + steer * 0.02
	var stem_end := Vector3(0.0, bar_y, clamp_z)
	k.region = RiderRegions.COMPONENT
	k.add_tube(ht_top, stem_start + steer * 0.012, Vector2(0.017, 0.017), Vector2(0.017, 0.017), C_BLACK, 8)
	k.add_tube(stem_start, stem_end, Vector2(0.018, 0.018), Vector2(0.016, 0.016), C_BLACK, 8)
	k.region = RiderRegions.BAR_TAPE
	k.add_tube(Vector3(-grip.x, bar_y, clamp_z), Vector3(grip.x, bar_y, clamp_z), Vector2(0.013, 0.013), Vector2(0.013, 0.013), C_BLACK, 8)
	for sx in [-1.0, 1.0]:
		var x: float = grip.x * sx
		k.region = RiderRegions.BAR_TAPE
		var drop := PackedVector3Array([Vector3(x, bar_y, clamp_z), Vector3(x, bar_y, grip.z + 0.025),
			Vector3(x, bar_y - 0.045, grip.z - 0.02), Vector3(x, bar_y - 0.13, grip.z - 0.005),
			Vector3(x, bar_y - 0.155, grip.z + 0.06)])
		k.add_limb(drop, PackedFloat32Array([0.013, 0.013, 0.013, 0.013, 0.013]), C_BLACK, 8)
		# Корпус ручки: верх в точке хвата — grip.y − HOOD_PALM_CLEARANCE_M.
		k.region = RiderRegions.COMPONENT
		var hood_r := Vector3(0.016, 0.017, 0.040)
		var hood_c := Vector3(x, grip.y - HOOD_PALM_CLEARANCE_M - hood_r.y, grip.z)
		k.add_ellipsoid(hood_c, hood_r, C_BLACK, Basis.IDENTITY, 5, 10)
		# Рог ручки и рычаг тормоза.
		k.add_ellipsoid(Vector3(x, grip.y - 0.017, grip.z - 0.04), Vector3(0.013, 0.012, 0.014), C_BLACK, Basis.IDENTITY, 4, 8)
		k.region = RiderRegions.METAL
		k.add_limb(PackedVector3Array([Vector3(x, grip.y - 0.033, grip.z - 0.035), Vector3(x, grip.y - 0.085, grip.z - 0.052),
			Vector3(x, grip.y - 0.135, grip.z - 0.04)]), PackedFloat32Array([0.007, 0.007, 0.006]), C_SILVER, 6)


## Wheel with rim `rims` (`RIMS`): tyre, rim (sides with the decal strip, inner and outer
## bands), hub, spokes; the rear one also has the cassette.
static func _wheel(rear: bool, rims: String = "deep") -> MeshKit:
	var k := MeshKit.new()
	var r_in: float = RIMS[rims]
	k.region = RiderRegions.TIRE
	k.add_torus_x(0.322, 0.014, C_TIRE, 40, 8)
	# Высокий обод: боковины (карбон + золотая полоса), внутренняя лента.
	for sx in [-1.0, 1.0]:
		k.region = RiderRegions.RIM_CARBON
		k.add_annulus_x(0.012 * sx, r_in, 0.292, C_RIM, sx, 40)
		k.region = RiderRegions.RIM_DECAL
		k.add_annulus_x(0.0125 * sx, 0.292, 0.31, C_RIM_STRIPE, sx, 40)
	k.region = RiderRegions.RIM_CARBON
	k.add_band_x(-0.012, 0.012, r_in, C_RIM, false, 40)
	k.add_band_x(-0.012, 0.012, 0.31, C_RIM, true, 40)
	# Втулка и спицы.
	k.region = RiderRegions.METAL
	k.add_tube(Vector3(-0.045, 0, 0), Vector3(0.045, 0, 0), Vector2(0.02, 0.02), Vector2(0.02, 0.02), C_SILVER, 10)
	var spokes: int = 18
	for i in spokes:
		var ang: float = TAU * float(i) / float(spokes)
		var sx: float = -1.0 if i % 2 == 0 else 1.0
		var hub := Vector3(0.03 * sx, cos(ang + 0.15) * 0.018, sin(ang + 0.15) * 0.018)
		var rim := Vector3(0.004 * sx, cos(ang) * r_in, sin(ang) * r_in)
		k.add_tube(hub, rim, Vector2(0.0025, 0.0025), Vector2(0.0025, 0.0025), Color(0.2, 0.2, 0.22, 0.0), 4, false)
	if rear:
		for i in 4:
			var x: float = 0.028 + 0.006 * float(i)
			var r: float = 0.06 - 0.008 * float(i)
			k.add_annulus_x(x, 0.02, r, C_SILVER, 1.0, 16)
			k.add_annulus_x(x - 0.002, 0.02, r, C_SILVER, -1.0, 16)
	return k


## Шатуны в системе узла `Crank` (он развёрнут на 180° вокруг Y: локальный +X — левая сторона
## велосипеда, локальный +Z — вперёд, положительный поворот вокруг X — педалирование вперёд):
## ось каретки, плечи шатунов, звезда, оси педалей. Кость `crank`.
static func _crank_arms() -> MeshKit:
	var k := MeshKit.new()
	var l: float = CRANK_LENGTH_M
	var ax: float = CRANK_ARM_X_M
	k.region = RiderRegions.METAL
	k.add_tube(Vector3(-ax, 0, 0), Vector3(ax, 0, 0), Vector2(0.013, 0.013), Vector2(0.013, 0.013), C_SILVER, 8)
	k.region = RiderRegions.COMPONENT
	k.add_tube(Vector3(-ax, 0, 0), Vector3(-ax, l, 0), Vector2(0.01, 0.02), Vector2(0.008, 0.013), C_BLACK, 8)
	k.add_tube(Vector3(ax, 0, 0), Vector3(ax, -l, 0), Vector2(0.01, 0.02), Vector2(0.008, 0.013), C_BLACK, 8)
	k.region = RiderRegions.METAL
	# Оси педалей — от плеча шатуна до корпуса педали (соосны оси педали: им всё равно, как
	# повёрнута педаль).
	var inner: float = PEDAL_X_M - PEDAL_BODY_WIDTH_M * 0.5
	k.add_tube(Vector3(-ax, l, 0), Vector3(-inner, l, 0), Vector2(0.006, 0.006), Vector2(0.006, 0.006), C_SILVER, 6)
	k.add_tube(Vector3(ax, -l, 0), Vector3(inner, -l, 0), Vector2(0.006, 0.006), Vector2(0.006, 0.006), C_SILVER, 6)
	# Chainring — metal (outline 0: flat discs with an outline would show dark side ghosts).
	var ring_col := Color(0.15, 0.15, 0.17, 0.0)
	k.add_annulus_x(-0.068, 0.06, 0.105, ring_col, -1.0, 36)
	k.add_annulus_x(-0.062, 0.06, 0.105, ring_col, 1.0, 36)
	k.add_band_x(-0.068, -0.062, 0.105, C_SILVER, true, 36)
	return k


## Контактная педаль в своей системе: начало — ось педали (центр шипа), корпус горизонтален,
## нос — вперёд (+Z системы `Crank`), верх корпуса на 2 мм ниже оси — под шипом туфли.
static func _pedal() -> MeshKit:
	var k := MeshKit.new()
	var w: float = PEDAL_BODY_WIDTH_M
	k.region = RiderRegions.COMPONENT
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, -0.010, -0.004)), Vector3(w, 0.016, 0.066), C_BLACK)
	k.add_box(Transform3D(Basis(Vector3.RIGHT, 0.32), Vector3(0.0, -0.011, 0.036)), Vector3(w * 0.7, 0.012, 0.026), C_BLACK)
	k.region = RiderRegions.METAL
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, -0.004, -0.032)), Vector3(w * 0.9, 0.006, 0.012), C_SILVER)
	return k


## Шатуны с педалями — один меш со скиннингом на 3 кости (`CRANK_BONES`, вес 1): педали
## держат угол стопы, а узел остаётся один (бюджет гонщика — 10 `MeshInstance3D`).
static func crank_mesh(material: Material) -> ArrayMesh:
	var parts: Array[MeshKit] = [_crank_arms(), _moved(_pedal(), Transform3D(Basis.IDENTITY, PEDAL_R_REST)),
		_moved(_pedal(), Transform3D(Basis.IDENTITY, PEDAL_L_REST))]
	var k := MeshKit.new()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for bone in parts.size():
		parts[bone].finalize_regions()
		_append(k, parts[bone])
		for i in parts[bone].vertices.size():
			bones.append_array(PackedInt32Array([bone, 0, 0, 0]))
			weights.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	return _skinned_mesh(k, bones, weights, material)


## Кости шатуна в `skeleton` (rest — без поворота) и `Skin` к мешу `crank_mesh`.
static func setup_crank_rig(skeleton: Skeleton3D) -> Skin:
	skeleton.clear_bones()
	var rests: Array[Vector3] = [Vector3.ZERO, PEDAL_R_REST, PEDAL_L_REST]
	var skin := Skin.new()
	for i in CRANK_BONES.size():
		skeleton.add_bone(CRANK_BONES[i])
		skeleton.set_bone_rest(i, Transform3D(Basis.IDENTITY, rests[i]))
		skin.add_named_bind(CRANK_BONES[i], Transform3D(Basis.IDENTITY, -rests[i]))
	skeleton.reset_bone_poses()
	return skin


## Поворот кости педали вокруг оси педали (локальный X узла `Crank`) при угле шатуна φ, чтобы
## корпус педали стоял под углом стопы θ к горизонту (`RiderRig.foot_pitch_rad`, левая —
## при φ + 180°). Узел `Crank` развёрнут на 180° вокруг Y, поэтому его поворот на φ вокруг
## своего X — это −φ вокруг X велосипеда; педаль: −(φ + β) = θ, β = −θ − φ.
static func pedal_bone_angle(crank_rad: float, left: bool) -> float:
	var side_phi: float = crank_rad + PI if left else crank_rad
	return -RiderRig.foot_pitch_rad(side_phi) - crank_rad


## Части велосипеда для пакета художнику (`bike_reference.glb`) в системе гонщика (Godot):
## рама с седлом и рулём, колёса на своих осях, шатуны с педалями при угле `crank_rad`. Левая
## педаль — под углом стопы, как в игре; правая — под подошвой правой стопы rest (≈ −8°,
## `RiderRig.rest_sole_pitch_rad`): художник ставит на неё туфлю позы привязки. Наборы без
## скиннинга; цвета вершин — линейные.
static func reference_kits(crank_rad: float) -> Dictionary:
	var mount := Transform3D(Basis(Vector3.UP, PI), BB) * Transform3D(Basis(Vector3.RIGHT, crank_rad), Vector3.ZERO)
	var crank := _moved(_crank_arms(), mount)
	var rests: Array[Vector3] = [PEDAL_R_REST, PEDAL_L_REST]
	var angles: Array[float] = [-RiderRig.rest_sole_pitch_rad() - crank_rad, pedal_bone_angle(crank_rad, true)]
	for side in 2:
		var pose := Transform3D(Basis(Vector3.RIGHT, angles[side]), rests[side])
		_append(crank, _moved(_pedal(), mount * pose))
	return {
		"bike_frame": _bike(),
		"wheel_front": _moved(_wheel(false), Transform3D(Basis.IDENTITY, FRONT_AXLE)),
		"wheel_rear": _moved(_wheel(true), Transform3D(Basis.IDENTITY, REAR_AXLE)),
		"crankset": crank,
	}


## Копия набора с трансформом вершин и нормалей (обход граней сначала приводится к нормалям).
static func _moved(src: MeshKit, xf: Transform3D) -> MeshKit:
	src.fix_winding()
	var k := MeshKit.new()
	for i in src.vertices.size():
		k.vertices.append(xf * src.vertices[i])
		k.normals.append((xf.basis * src.normals[i]).normalized())
	k.colors = src.colors.duplicate()
	k.uvs = src.uvs.duplicate()
	k.accents = src.accents.duplicate()
	k.indices = src.indices.duplicate()
	return k


## Дописать `src` в `dst` (индексы со сдвигом).
static func _append(dst: MeshKit, src: MeshKit) -> void:
	src.fix_winding()
	var base: int = dst.vertices.size()
	dst.vertices.append_array(src.vertices)
	dst.normals.append_array(src.normals)
	dst.colors.append_array(src.colors)
	dst.uvs.append_array(src.uvs)
	dst.accents.append_array(src.accents)
	dst.outline_normals.append_array(src.outline_normals)
	for i in src.indices:
		dst.indices.append(base + i)


## Части тела манекена `[MeshKit, кость]` в системе гонщика (rest): таз в шортах (ядро и две
## доли по бокам седла), корпус (поясница в шортах, джерси с боковыми вставками), шея, голова,
## руки до хвата, ноги (бедро в шортах с резинкой, голень с икрой и высоким носком).
static func _body_parts(figure: String) -> Array:
	var d: Dictionary = FIGURES[figure]
	var parts: Array = []
	# Таз: ядро и доли «сердца» по бокам седла (низ долей ниже верха седла).
	var hw: float = d["hips_hw"]
	var pelvis := _kit(RiderRegions.SHORTS_MAIN)
	pelvis.add_ellipsoid(Vector3(0.0, 1.05, 0.195), Vector3(hw - 0.04, 0.085, 0.125), C_SHORTS, Basis.IDENTITY, 8, 16)
	for sx in [-1.0, 1.0]:
		pelvis.add_ellipsoid(Vector3(sx * (hw - 0.09), 1.0, 0.23), Vector3(0.09, 0.072, 0.105), C_SHORTS, Basis.IDENTITY, 7, 14)
	parts.append([pelvis, "pelvis"])
	# Корпус: поясница в шортах до низа джерси (≈ 0.24 м над седлом по спине), джерси до груди.
	var waist: float = d["waist_hw"]
	var chest_j: Vector3 = RiderRig.head("chest")
	var p0 := Vector3(0.0, 1.06, 0.17)
	var p1 := Vector3(0.0, 1.13, 0.105)
	var spine := _kit(RiderRegions.SHORTS_MAIN)
	spine.add_tube(p0, p1, Vector2(waist + 0.012, 0.10), Vector2(waist + 0.004, 0.10), C_SHORTS, 16, false)
	_use_region(spine, RiderRegions.JERSEY_MAIN, RiderRegions.JERSEY_SIDE)
	spine.add_tube(p1, chest_j, Vector2(waist + 0.004, 0.10), Vector2(waist + 0.012, 0.105), C_JERSEY, 16, false,
		Vector3.RIGHT, C_JERSEY_RED, 0.82)
	parts.append([spine, "spine"])
	var sh_hw: float = d["shoulder_hw"]
	var p3 := Vector3(0.0, 1.30, -0.175)
	var chest := _kit(RiderRegions.JERSEY_MAIN, RiderRegions.JERSEY_SIDE)
	chest.add_tube(chest_j, p3, Vector2(waist + 0.012, 0.105), Vector2(sh_hw - 0.06, 0.085), C_JERSEY, 16, false,
		Vector3.RIGHT, C_JERSEY_RED, 0.82)
	# Shoulders and upper back — the yoke (region 5).
	_use_region(chest, RiderRegions.JERSEY_YOKE)
	chest.add_ellipsoid(Vector3(0.0, 1.30, -0.215), Vector3(sh_hw - 0.045, 0.07, 0.10), C_JERSEY, Basis(Vector3.RIGHT, 0.5), 7, 16)
	# Band across the back (region 4, color by the jersey pattern).
	_use_region(chest, RiderRegions.JERSEY_BAND)
	chest.add_tube(Vector3(0.0, 1.245, -0.035), Vector3(0.0, 1.262, -0.058), Vector2(waist + 0.016, 0.109),
		Vector2(waist + 0.018, 0.108), C_JERSEY_RED, 16, false)
	parts.append([chest, "chest"])
	var neck := _kit(RiderRegions.SKIN)
	var nr: float = d["neck_r"]
	neck.add_tube(Vector3(0.0, 1.34, -0.19), Vector3(0.0, 1.425, -0.325), Vector2(nr, nr), Vector2(nr * 0.95, nr * 0.95), C_SKIN, 12, false)
	parts.append([neck, "neck"])
	var head := _kit(RiderRegions.SKIN)
	head.add_ellipsoid(HEAD_CENTER, HEAD_RADII, C_SKIN, Basis(Vector3.RIGHT, -0.2), 8, 16)
	# Нос — пологий выступ.
	head.add_ellipsoid(HEAD_CENTER + Vector3(0.0, -0.025, -0.095), Vector3(0.016, 0.026, 0.02), C_SKIN, Basis.IDENTITY, 4, 8)
	parts.append([head, "head"])
	for side in [".L", ".R"]:
		var sx: float = -1.0 if side == ".L" else 1.0
		var r: float = d["arm_r"]
		var sh: Vector3 = RiderRig.head("upperarm" + side)
		var el: Vector3 = RiderRig.head("forearm" + side)
		var wr: Vector3 = RiderRig.head("hand" + side)
		var gr: Vector3 = RiderRig.head("grip" + side)
		var upper := _kit(RiderRegions.JERSEY_YOKE)
		var delt: Vector3 = sh + Vector3(sx * (sh_hw - r - absf(sh.x)), 0.0, 0.0)
		var cuff: Vector3 = sh.lerp(el, 0.48)
		var cuff_end: Vector3 = sh.lerp(el, 0.56)
		upper.add_ellipsoid(delt, Vector3.ONE * r * 1.05, C_JERSEY, Basis.IDENTITY, 6, 14)
		_use_region(upper, RiderRegions.JERSEY_MAIN)
		upper.add_tube(delt, cuff, Vector2(r, r) * 1.02, Vector2(r, r) * 0.95, C_JERSEY, 14, false)
		_use_region(upper, RiderRegions.JERSEY_CUFF)
		upper.add_tube(cuff, cuff_end, Vector2(r, r) * 0.96, Vector2(r, r) * 0.94, C_JERSEY_BLUE, 14, false)
		_use_region(upper, RiderRegions.SKIN)
		upper.add_tube(cuff_end, el, Vector2(r, r) * 0.88, Vector2(r, r) * 0.8, C_SKIN, 14, false)
		upper.add_ellipsoid(el, Vector3.ONE * r * 0.8, C_SKIN, Basis.IDENTITY, 6, 14)
		parts.append([upper, "upperarm" + side])
		var fore := _kit(RiderRegions.SKIN)
		var wr_r: float = d["wrist_r"]
		fore.add_tube(el, wr, Vector2(r, r) * 0.8, Vector2(wr_r, wr_r), C_SKIN, 14, false)
		fore.add_ellipsoid(wr, Vector3.ONE * wr_r, C_SKIN, Basis.IDENTITY, 5, 12)
		parts.append([fore, "forearm" + side])
		# Кисть в перчатке обхватывает корпус ручки: ладонь сверху (центр — `grip`), большой
		# палец с внутренней стороны.
		var hand := _kit(RiderRegions.GLOVE)
		var hb: Basis = bone_basis(gr - wr)
		hand.add_ellipsoid(wr.lerp(gr, 0.75) + Vector3(0.0, -0.004, 0.0), Vector3(0.036, 0.055, 0.03), C_GLOVE, hb, 6, 12)
		hand.add_ellipsoid(gr + Vector3(-sx * 0.022, -0.022, -0.004), Vector3(0.012, 0.028, 0.012), C_GLOVE, hb, 4, 8)
		hand.add_ellipsoid(gr + Vector3(sx * 0.006, -0.03, -0.02), Vector3(0.022, 0.03, 0.014), C_GLOVE, hb, 4, 8)
		parts.append([hand, "hand" + side])
		var hip: Vector3 = RiderRig.head("thigh" + side)
		var knee: Vector3 = RiderRig.head("shin" + side)
		var ankle: Vector3 = RiderRig.head("foot" + side)
		parts.append([_moved(_thigh_kit(d, hip.distance_to(knee)), bone_transform(hip, knee)), "thigh" + side])
		parts.append([_moved(_shin_kit(d, knee.distance_to(ankle)), bone_transform(knee, ankle)), "shin" + side])
	return parts


## Бедро вдоль −Y от тазобедренного сустава длиной `l` (локальный +Z — задняя поверхность):
## шорты до 66 % длины, резинка 3 см, кожа до колена, надколенник.
static func _thigh_kit(d: Dictionary, l: float) -> MeshKit:
	var k := _kit(RiderRegions.SHORTS_MAIN)
	var r: float = d["thigh_r"]
	var kr: float = d["knee_r"]
	k.add_ellipsoid(Vector3.ZERO, Vector3.ONE * r * 0.95, C_SHORTS, Basis.IDENTITY, 7, 14)
	k.add_tube(Vector3.ZERO, Vector3(0.0, -l * 0.33, 0.0), Vector2(r * 0.95, r * 1.04), Vector2(r * 0.93, r * 1.0), C_SHORTS, 14, false)
	k.add_tube(Vector3(0.0, -l * 0.33, 0.0), Vector3(0.0, -l * 0.66, 0.0), Vector2(r * 0.93, r * 1.0), Vector2(r * 0.8, r * 0.84), C_SHORTS, 14, false)
	_use_region(k, RiderRegions.SHORTS_GRIPPER)
	k.add_tube(Vector3(0.0, -l * 0.66, 0.0), Vector3(0.0, -l * 0.70, 0.0), Vector2(r * 0.81, r * 0.85), Vector2(r * 0.79, r * 0.83), C_BLACK, 14, false)
	_use_region(k, RiderRegions.SKIN)
	k.add_tube(Vector3(0.0, -l * 0.70, 0.0), Vector3(0.0, -l, 0.0), Vector2(r * 0.76, r * 0.79), Vector2(kr, kr), C_SKIN, 14, false)
	k.add_ellipsoid(Vector3(0.0, -l, 0.0), Vector3.ONE * kr, C_SKIN, Basis.IDENTITY, 7, 14)
	k.add_ellipsoid(Vector3(0.0, -l * 0.96, -kr * 0.55), Vector3(kr * 0.6, kr * 0.7, kr * 0.5), C_SKIN, Basis.IDENTITY, 4, 10)
	return k


## Голень вдоль −Y от колена длиной `l` (локальный +Z — сзади): икра в верхней трети,
## высокий носок с середины голени до голеностопа.
static func _shin_kit(d: Dictionary, l: float) -> MeshKit:
	var k := _kit(RiderRegions.SKIN)
	var kr: float = d["knee_r"] * 0.95
	var c: float = d["calf_r"]
	var a: float = d["ankle_r"]
	var calf := Vector3(0.0, -l * 0.32, c * 0.25)
	var sock := Vector3(0.0, -l * 0.5, c * 0.1)
	k.add_tube(Vector3.ZERO, calf, Vector2(kr, kr), Vector2(c * 0.92, c), C_SKIN, 14, false)
	k.add_tube(calf, sock, Vector2(c * 0.92, c), Vector2(c * 0.78, c * 0.8), C_SKIN, 14, false)
	_use_region(k, RiderRegions.SOCKS_MAIN)
	k.add_tube(sock, Vector3(0.0, -l, 0.0), Vector2(c * 0.79, c * 0.81), Vector2(a, a * 1.1), C_SOCK, 14, false)
	k.add_ellipsoid(Vector3(0.0, -l, 0.0), Vector3(a, a, a * 1.1) * 1.05, C_SOCK, Basis.IDENTITY, 5, 12)
	return k


## Причёска `[MeshKit, кость]`: волосы на затылке из-под шлема (кость `head`); у `tail` —
## резинка и хвост строго по костям: `hair_tail.1` — от корня до вершины дуги над воротником,
## `hair_tail.2` — от вершины до кончика (окончание кости, `RiderRig.tail`), без своего изгиба.
static func _hair_parts(style: String) -> Array:
	var parts: Array = []
	var cap := _kit(RiderRegions.HAIR)
	cap.add_ellipsoid(Vector3(0.0, 1.425, -0.29), Vector3(0.074, 0.05, 0.05), C_HAIR, Basis(Vector3.RIGHT, 0.3), 6, 14)
	parts.append([cap, "head"])
	if style == "tail":
		var t1: Vector3 = RiderRig.head("hair_tail.1")
		var t2: Vector3 = RiderRig.head("hair_tail.2")
		var dir: Vector3 = (t2 - t1).normalized()
		# Hair tie — region 18 (dark, no outline), hair — 1.
		var root := _kit(RiderRegions.HELMET_INNER)
		root.add_tube(t1 - dir * 0.004, t1 + dir * 0.012, Vector2(0.019, 0.015), Vector2(0.019, 0.015), C_BLACK, 10, true)
		_use_region(root, RiderRegions.HAIR)
		root.add_tube(t1, t2, Vector2(0.017, 0.012), Vector2(0.015, 0.011), C_HAIR, 10, false)
		root.add_ellipsoid(t2, Vector3(0.015, 0.011, 0.015), C_HAIR, Basis.IDENTITY, 4, 10)
		parts.append([root, "hair_tail.1"])
		var tip: Vector3 = RiderRig.tail("hair_tail.2")
		var end := _kit(RiderRegions.HAIR)
		end.add_tube(t2, tip, Vector2(0.015, 0.011), Vector2(0.008, 0.006), C_HAIR, 10, false)
		end.add_ellipsoid(tip, Vector3(0.008, 0.006, 0.008), C_HAIR, Basis.IDENTITY, 4, 8)
		parts.append([end, "hair_tail.2"])
	return parts


## Road helmet (mannequin): teardrop shell (region 16) with a dark lengthwise stripe (accent,
## 17) on the top only — the lower rim of the shell is solid main color (helmet rule of spec
## rev. 4.6); rear edge lower than the front, straps to the chin (18). Bone `head`.
const HELMET_BAND_MIN_Y: float = 0.45

static func _helmet() -> MeshKit:
	var k := _kit(RiderRegions.HELMET_MAIN, RiderRegions.HELMET_ACCENT)
	k.add_ellipsoid(Vector3(0.0, 1.505, -0.35), Vector3(0.105, 0.078, 0.14), C_HELMET, Basis(Vector3.RIGHT, 0.12),
		10, 20, 0, -0.18, 0.18, C_BLACK, HELMET_BAND_MIN_Y)
	_use_region(k, RiderRegions.HELMET_INNER)
	for sx in [-1.0, 1.0]:
		k.add_tube(Vector3(0.074 * sx, 1.455, -0.335), Vector3(0.03 * sx, 1.355, -0.42), Vector2(0.006, 0.003),
			Vector2(0.006, 0.003), C_BLACK, 6, false)
	return k


## Eyewear — wraparound shield lens 1–1.5 cm in front of the face (region 19): the top row of
## faces is the highlight strip (V 0.9), the rest — the base tone (V 0.5). Bone `head`.
static func _eyewear() -> MeshKit:
	var k := _kit(RiderRegions.LENS)
	k.highlight_from_y = 0.75
	k.add_ellipsoid(Vector3(0.0, 1.455, -0.447), Vector3(0.088, 0.022, 0.036), C_BLACK, Basis.IDENTITY, 4, 14)
	return k


## Туфля стороны `side` (".L"/".R") в rest: подошва по линии «пятка → носок» через шип,
## тёмная подошва, манжета у голеностопа, шип. Кость `foot`.
static func _shoe(side: String) -> MeshKit:
	var k := _kit(RiderRegions.SHOE_MAIN, RiderRegions.SHOE_SOLE)
	var heel: Vector3 = RiderRig.head("heel" + side)
	var toe: Vector3 = RiderRig.tail("foot" + side)
	var ankle: Vector3 = RiderRig.head("foot" + side)
	var cleat: Vector3 = RiderRig.head("cleat" + side)
	var back: Vector3 = (heel - toe).normalized()
	var up: Vector3 = back.cross(Vector3.RIGHT).normalized()
	var basis := Basis(up.cross(back), up, back)
	k.add_ellipsoid((heel + toe) * 0.5 + up * 0.04, Vector3(0.05, 0.042, 0.145), C_SHOE, basis, 7, 14, 1, -1.0, -0.6, C_BLACK)
	k.add_ellipsoid(ankle + Vector3(0.0, -0.025, 0.012), Vector3(0.042, 0.04, 0.05), C_SHOE, Basis.IDENTITY, 5, 12)
	_use_region(k, RiderRegions.CLEAT)
	k.add_box(Transform3D(basis, cleat + up * 0.004), Vector3(0.034, 0.008, 0.036), C_BLACK)
	return k


## New region kit: region `code`, accent part — `accent` (-1 — none).
static func _kit(code: int, accent: int = -1) -> MeshKit:
	var k := MeshKit.new()
	_use_region(k, code, accent)
	return k


static func _use_region(k: MeshKit, code: int, accent: int = -1) -> void:
	k.region = code
	k.accent_region = accent
