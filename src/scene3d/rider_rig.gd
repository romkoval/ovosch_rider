class_name RiderRig
extends RefCounted
## Контракт скелета гонщика (REQ-D3D-09; арт-библия «Гонщик» → «Контракт скелета»; ТЗ
## художнику `docs/game/rider-artist-brief.md` разделы 4–6, 14). Единственный источник чисел
## для кода: из этой таблицы читают подгонка велосипеда (`RiderModel`), эталонный пакет
## (`scripts/dev/rider_reference_pack.gd`), эталонные ракурсы (`scripts/dev/ride_screenshot.gd`),
## манекен на `Skeleton3D` (T-106a2), импорт `rider.glb` (T-106a4) и тесты.
##
## Координаты — Godot, система узла `Lean` гонщика: Y вверх, −Z вперёд, +X — правая сторона
## гонщика (у `.R` x > 0, у `.L` x < 0), начало — на земле под кареткой. Перевод в Blender
## (Z вверх, гонщик смотрит в −Y, левая сторона +X): `to_blender()`. В glTF модель смотрит
## в +Z (экспорт Blender «+Y Up»): `to_gltf()` — поворот на 180° вокруг Y.

## Кости: [имя, родитель ("" — корень), начало кости (сустав) в rest, деформирует сетку].
## Rest — посадка на велосипеде, обе ноги в положении правой при φ = 90° (бриф 5.2).
const BONES: Array = [
	["pelvis", "", Vector3(0.0, 0.965, 0.230), true],
	["spine", "pelvis", Vector3(0.0, 1.147, 0.105), true],
	["chest", "spine", Vector3(0.0, 1.234, -0.018), true],
	["neck", "chest", Vector3(0.0, 1.380, -0.190), true],
	["head", "neck", Vector3(0.0, 1.420, -0.310), true],
	["upperarm.L", "chest", Vector3(-0.180, 1.340, -0.220), true],
	["forearm.L", "upperarm.L", Vector3(-0.240, 1.060, -0.345), true],
	["hand.L", "forearm.L", Vector3(-0.215, 0.925, -0.560), true],
	["grip.L", "hand.L", Vector3(-0.210, 0.885, -0.620), false],
	["upperarm.R", "chest", Vector3(0.180, 1.340, -0.220), true],
	["forearm.R", "upperarm.R", Vector3(0.240, 1.060, -0.345), true],
	["hand.R", "forearm.R", Vector3(0.215, 0.925, -0.560), true],
	["grip.R", "hand.R", Vector3(0.210, 0.885, -0.620), false],
	["thigh.L", "pelvis", Vector3(-0.090, 1.050, 0.190), true],
	["shin.L", "thigh.L", Vector3(-0.100, 0.797, -0.170), true],
	["foot.L", "shin.L", Vector3(-0.110, 0.371, -0.063), true],
	["cleat.L", "foot.L", Vector3(-0.115, 0.270, -0.170), false],
	["heel.L", "foot.L", Vector3(-0.115, 0.296, 0.018), false],
	["thigh.R", "pelvis", Vector3(0.090, 1.050, 0.190), true],
	["shin.R", "thigh.R", Vector3(0.100, 0.797, -0.170), true],
	["foot.R", "shin.R", Vector3(0.110, 0.371, -0.063), true],
	["cleat.R", "foot.R", Vector3(0.115, 0.270, -0.170), false],
	["heel.R", "foot.R", Vector3(0.115, 0.296, 0.018), false],
	["hair_tail.1", "head", Vector3(0.0, 1.390, -0.250), true],
	# Спека задаёт только длину 0.09–0.10 м «вдоль хвоста»: назад и чуть вверх, над воротником.
	["hair_tail.2", "hair_tail.1", Vector3(0.0, 1.430, -0.165), true],
]
const BONE_COUNT: int = 25
## Предел костей скелета гонщика (REQ-D3D-09 п.7).
const MAX_BONES: int = 28
## Допуск начала кости модели художника от таблицы, м (бриф 5.1, Т2).
const ARTIST_TOLERANCE_M: float = 0.005
## Длина `hair_tail.1` → `hair_tail.2`, м (бриф 5.1).
const HAIR_TAIL_MIN_M: float = 0.09
const HAIR_TAIL_MAX_M: float = 0.10
## Окончание `hair_tail.2` (кончик хвоста) в rest, Godot (Blender (0, −0.08, 1.395)): от вершины
## дуги над воротником (начало `hair_tail.2`) хвост ложится назад-вниз ≈ 22° к горизонту, длина
## второй кости 0.092 м, всего 0.186 м (спека «Причёски»: 0.16–0.20 м; вердикт T-106a2, Г15).
const HAIR_TAIL_END := Vector3(0.0, 1.395, -0.080)
## Длина сокета (окончание — вниз от начала), м (бриф 5.1).
const SOCKET_TAIL_M: float = 0.03

## Велосипед (бриф раздел 6; база 0.99 м и колёса 700c не меняются).
const BB := Vector3(0.0, 0.27, 0.0)
const CRANK_LENGTH_M: float = 0.17
## Ось педали (центр шипа) от средней плоскости велосипеда, м.
const PEDAL_X_M: float = 0.115
const REAR_AXLE := Vector3(0.0, 0.335, 0.405)
const FRONT_AXLE := Vector3(0.0, 0.335, -0.585)
const WHEEL_RADIUS_M: float = 0.335
## Седло: верх под точкой опоры таза S (начало `pelvis`) — 0.965 м; длина 0.27 м, ширина
## сзади 0.13 м; задний край — в 0.03–0.10 м позади S (берём середину, 0.065 м).
const SADDLE_LENGTH_M: float = 0.27
const SADDLE_REAR_WIDTH_M: float = 0.13
const SADDLE_REAR_BEHIND_S_M: float = 0.065
## Угол шатуна rest, рад: φ = 90° — правая педаль впереди (бриф 5.2, `bike_reference.glb`).
const REST_CRANK_RAD: float = PI / 2.0

## Эталонные ракурсы (бриф раздел 14, арт-библия «Эталонные ракурсы»): камера и цель в
## системе гонщика (Godot), вертикальный FOV, углы шатуна φ в градусах. `work` — рабочая
## камера сцены (`RideScene`); её числа здесь — для сверки с брифом.
const VIEWS: Array = [
	["work", Vector3(-0.49, 2.10, 3.77), Vector3(0.0, 0.60, -6.0), 55.0, [0, 90, 180, 270]],
	["side_r", Vector3(2.8, 0.95, -0.1), Vector3(0.0, 0.85, -0.1), 40.0, [0, 90, 180, 270]],
	# Ред. 4.1: камера и цель на 0.12 м выше — таз и седло в центре кадра.
	["hips_r", Vector3(1.3, 0.97, 0.15), Vector3(0.0, 0.87, 0.05), 35.0, [0, 90, 180, 270]],
	["rear34_l", Vector3(-1.5, 1.55, 2.0), Vector3(0.0, 0.95, 0.05), 40.0, [90]],
	["front34_r", Vector3(1.6, 1.35, -2.2), Vector3(0.0, 1.05, -0.25), 40.0, [90]],
	["head_34", Vector3(0.7, 1.55, -1.1), Vector3(0.0, 1.42, -0.38), 30.0, [90]],
	# Ред. 3: как камера видео-референса (сзади, на высоте руля) — движение; художнику не нужен.
	["rear_low", Vector3(0.0, 1.15, 3.0), Vector3(0.0, 0.80, 0.0), 45.0, [0, 45, 90, 135, 180, 225, 270, 315]],
]
## Ракурсы, которые бриф передаёт художнику (раздел 14); остальные — только наши.
const ARTIST_VIEWS: Array[String] = ["work", "side_r", "hips_r", "rear34_l", "front34_r", "head_34"]

## Контрольные позы правой ноги (бриф 5.4, арт-библия ред. 3; Godot): [φ°, шип, голеностоп,
## колено, угол в колене°, угол стопы θ°]. Rest (5.2) — отдельно: при φ = 90° в игре стопа на
## 6° площе rest. Для IK манекена (T-106a2) и проверок Т8.
const CONTROL_POSES: Array = [
	[0, Vector3(0.115, 0.440, 0.000), Vector3(0.110, 0.555, 0.092), Vector3(0.100, 0.873, -0.213), 70.0, -16.0],
	[90, Vector3(0.115, 0.270, -0.170), Vector3(0.110, 0.360, -0.053), Vector3(0.100, 0.786, -0.162), 113.0, -2.0],
	[180, Vector3(0.115, 0.100, 0.000), Vector3(0.110, 0.208, 0.100), Vector3(0.100, 0.642, 0.026), 148.0, -12.0],
	[270, Vector3(0.115, 0.270, 0.170), Vector3(0.110, 0.399, 0.241), Vector3(0.100, 0.701, -0.078), 96.0, -26.0],
]


static func bone_names() -> PackedStringArray:
	var out := PackedStringArray()
	for b in BONES:
		out.append(b[0])
	return out


static func index_of(bone: String) -> int:
	for i in BONES.size():
		if BONES[i][0] == bone:
			return i
	return -1


static func parent_of(bone: String) -> String:
	var i: int = index_of(bone)
	return BONES[i][1] if i >= 0 else ""


## Начало кости (сустав) в rest, Godot.
static func head(bone: String) -> Vector3:
	var i: int = index_of(bone)
	assert(i >= 0, "RiderRig: unknown bone %s" % bone)
	return BONES[i][2] if i >= 0 else Vector3.ZERO


static func deforms(bone: String) -> bool:
	var i: int = index_of(bone)
	return i >= 0 and BONES[i][3]


## Сокет — кость без весов (`grip`, `cleat`, `heel`): по ним IK ставит кисти и стопы.
static func is_socket(bone: String) -> bool:
	return index_of(bone) >= 0 and not deforms(bone)


## Окончание (tail) кости в rest, Godot (бриф 5.1, колонка «Окончание»): начало «своего»
## ребёнка цепочки; у `head` — к макушке, у `foot` — к носку, у сокетов — 3 см вниз, у
## `hair_tail.2` — кончик хвоста `HAIR_TAIL_END` (хвост изгибается на вершине дуги и лежит над
## спиной). Окончания задают направление кости (ось Y, бриф 5.3) в эталонной арматуре, в
## конвейере доводки и в rest скелета игры (сетка хвоста и оси пружины — по ним).
static func tail(bone: String) -> Vector3:
	var side: String = bone.right(2) if bone.ends_with(".L") or bone.ends_with(".R") else ""
	var sx: float = -1.0 if side == ".L" else 1.0
	match bone.trim_suffix(side):
		"pelvis":
			return head("spine")
		"spine":
			return head("chest")
		"chest":
			return head("neck")
		"neck":
			return head("head")
		"head":
			return Vector3(0.0, 1.56, -0.40)
		"upperarm":
			return head("forearm" + side)
		"forearm":
			return head("hand" + side)
		"hand":
			return head("grip" + side)
		"thigh":
			return head("shin" + side)
		"shin":
			return head("foot" + side)
		"foot":
			return Vector3(0.115 * sx, 0.258, -0.259)
		"hair_tail.1":
			return head("hair_tail.2")
		"hair_tail.2":
			return HAIR_TAIL_END
	return head(bone) + Vector3(0.0, -SOCKET_TAIL_M, 0.0)


## Оси кости в rest, Godot (бриф 5.3): Y — от начала к окончанию, X — параллельно мировой X
## Blender (Godot −X; Recalculate Roll → Global +X), Z = X × Y.
static func rest_basis(bone: String) -> Basis:
	var y: Vector3 = (tail(bone) - head(bone)).normalized()
	var x: Vector3 = Vector3.LEFT - y * Vector3.LEFT.dot(y)
	x = x.normalized()
	return Basis(x, y, x.cross(y))


## Расстояние между началами двух костей, м.
static func span(a: String, b: String) -> float:
	return head(a).distance_to(head(b))


## Godot (система гонщика) → Blender: (x, y, z) → (−x, z, y).
static func to_blender(p: Vector3) -> Vector3:
	return Vector3(-p.x, p.z, p.y)


static func from_blender(b: Vector3) -> Vector3:
	return Vector3(-b.x, b.z, b.y)


## Godot (система гонщика) → glTF, как его пишет экспорт Blender «+Y Up» из координат брифа:
## модель смотрит в +Z — поворот на 180° вокруг Y. Обратный перевод — тот же поворот.
static func to_gltf(p: Vector3) -> Vector3:
	return Vector3(-p.x, p.y, -p.z)


static func from_gltf(g: Vector3) -> Vector3:
	return Vector3(-g.x, g.y, -g.z)


## Поворот glTF ↔ Godot (180° вокруг Y) как трансформ.
static func gltf_flip() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)


## Скелет rest по таблице, в системе гонщика (Godot): начала костей — суставы таблицы, оси —
## `rest_basis` (Y вдоль кости, X — мировая X Blender), как у `rider.glb` после экспорта по
## брифу. Используется при построении сцены (эталонная арматура, манекен T-106a2), не в кадре.
static func build_skeleton(skeleton: Skeleton3D) -> void:
	skeleton.clear_bones()
	for b in BONES:
		skeleton.add_bone(b[0])
	for b in BONES:
		var i: int = skeleton.find_bone(b[0])
		var parent: String = b[1]
		var rest := Transform3D(rest_basis(b[0]), b[2])
		if not parent.is_empty():
			skeleton.set_bone_parent(i, skeleton.find_bone(parent))
			rest = Transform3D(rest_basis(parent), head(parent)).affine_inverse() * rest
		skeleton.set_bone_rest(i, rest)
	skeleton.reset_bone_poses()


## Угол шатуна в градусах → сторона: φ правой ноги; левая работает с φ + 180°.
static func left_phase_deg(right_deg: float) -> float:
	return fposmod(right_deg + 180.0, 360.0)


## Рекомендуемая кривая угла стопы θ(φ) (допуски п.4, ред. 3 по видео владельца):
## θ = −14° + 12°·cos(φ − 100°), рад; «+» — носок вверх. По ней же стоит контактная педаль
## под шипом. Константы — `RiderMotion` (одно место для движения, T-106a2).
static func foot_pitch_rad(crank_rad: float) -> float:
	return RiderMotion.foot_pitch_rad(crank_rad)


## Угол линии подошвы «пятка → шип» в rest (бриф 5.2: ≈ −8°), рад; правая сторона.
static func rest_sole_pitch_rad() -> float:
	var heel: Vector3 = head("heel.R")
	var cleat: Vector3 = head("cleat.R")
	return atan2(cleat.y - heel.y, heel.z - cleat.z)
