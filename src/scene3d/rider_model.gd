class_name RiderModel
extends RefCounted
## Процедурная модель велосипедиста (REQ-D3D-04, REQ-D3D-07, арт-библия «Велосипедист»):
## шоссейный велосипед (рама, вилка, руль, седло, колёса с высоким ободом, шатуны со
## звездой) и гонщик (шлем, очки, джерси с лампасами, шорты, руки на тормозных ручках,
## ноги из бедра/голени/туфли). Все части красятся одним тун-материалом по цвету вершин.
##
## Система координат — как у `Rider`: −Z вперёд, Y вверх, начало — на земле под кареткой.
## Ноги собираются в кадре двухзвенной IK от тазобедренного сустава к педали
## (`Rider._solve_leg`), поэтому бедро, голень и туфля — отдельные меши. Меши строятся
## один раз на процесс (статический кэш).

const BB := Vector3(0.0, 0.27, 0.0)
const REAR_AXLE := Vector3(0.0, 0.335, 0.405)
const FRONT_AXLE := Vector3(0.0, 0.335, -0.585)
const CRANK_LENGTH_M: float = 0.17
const PEDAL_X_M: float = 0.115
## Тазобедренные суставы (x — по модулю), длины бедра и голени.
const HIP := Vector3(0.09, 0.975, 0.215)
const THIGH_M: float = 0.44
const SHIN_M: float = 0.42
## Голеностоп относительно оси педали (подушечка стопы над педалью).
const ANKLE_FROM_PEDAL := Vector3(0.0, 0.075, 0.1)
## Подсказка сгиба колена — вперёд и чуть вверх.
const KNEE_HINT := Vector3(0.0, 0.25, -1.0)
## Центр таза — ось покачивания корпуса.
const PELVIS := Vector3(0.0, 1.0, 0.2)

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

static var _cache: Dictionary = {}


## Все меши модели: bike, wheel, rear_wheel, crank, upper, thigh, shin, shoe.
static func meshes(material: Material) -> Dictionary:
	var key: int = material.get_instance_id() if material != null else 0
	if _cache.has(key):
		return _cache[key]
	var out := {
		"bike": _bike().to_mesh(material),
		"wheel": _wheel(false).to_mesh(material),
		"rear_wheel": _wheel(true).to_mesh(material),
		"crank": _crank().to_mesh(material),
		"upper": _upper().to_mesh(material),
		"thigh": _thigh().to_mesh(material),
		"shin": _shin().to_mesh(material),
		"shoe": _shoe().to_mesh(material),
	}
	_cache[key] = out
	return out


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


static func _bike() -> MeshKit:
	var k := MeshKit.new()
	var seat_dir := Vector3(0.0, 0.959, 0.284)
	var st_top: Vector3 = BB + seat_dir * 0.53
	var ht_top := Vector3(0.0, 0.83, -0.40)
	var ht_bot := Vector3(0.0, 0.69, -0.445)
	var saddle: Vector3 = BB + seat_dir * 0.70
	# Рама: верхняя (акцент), нижняя, подседельная, перья.
	k.add_tube(st_top + Vector3(0, -0.01, -0.01), ht_top + Vector3(0, -0.02, 0.0), Vector2(0.02, 0.02), Vector2(0.021, 0.021), C_ACCENT, 10)
	k.add_tube(BB, ht_bot, Vector2(0.03, 0.026), Vector2(0.026, 0.024), C_FRAME, 10)
	k.add_tube(BB, st_top, Vector2(0.022, 0.022), Vector2(0.019, 0.019), C_FRAME, 10)
	k.add_tube(ht_bot + Vector3(0, -0.02, -0.006), ht_top + Vector3(0, 0.02, 0.006), Vector2(0.025, 0.025), Vector2(0.024, 0.024), C_FRAME, 10)
	for sx in [-1.0, 1.0]:
		var axle: Vector3 = REAR_AXLE + Vector3(0.062 * sx, 0.0, 0.0)
		k.add_tube(BB + Vector3(0.035 * sx, 0.0, 0.02), axle, Vector2(0.013, 0.015), Vector2(0.009, 0.009), C_FRAME, 7)
		k.add_tube(st_top + Vector3(0.022 * sx, -0.02, 0.0), axle, Vector2(0.011, 0.011), Vector2(0.008, 0.008), C_ACCENT, 7)
		# Вилка.
		k.add_tube(ht_bot + Vector3(0.03 * sx, 0.0, 0.0), FRONT_AXLE + Vector3(0.05 * sx, 0.0, 0.0), Vector2(0.016, 0.02), Vector2(0.009, 0.01), C_FRAME, 7)
	# Подседельный штырь и седло.
	k.add_tube(st_top, saddle, Vector2(0.014, 0.014), Vector2(0.014, 0.014), C_BLACK, 8)
	k.add_ellipsoid(saddle + Vector3(0.0, 0.025, -0.02), Vector3(0.065, 0.028, 0.14), C_BLACK, Basis.IDENTITY, 5, 10)
	# Вынос и руль: верхний хват, «бараны» и тормозные ручки.
	var stem_end := Vector3(0.0, 0.86, -0.51)
	k.add_tube(ht_top, stem_end, Vector2(0.018, 0.018), Vector2(0.016, 0.016), C_BLACK, 8)
	k.add_tube(Vector3(-0.21, 0.86, -0.51), Vector3(0.21, 0.86, -0.51), Vector2(0.014, 0.014), Vector2(0.014, 0.014), C_BLACK, 8)
	for sx in [-1.0, 1.0]:
		var x: float = 0.21 * sx
		var drop := PackedVector3Array([Vector3(x, 0.86, -0.51), Vector3(x, 0.86, -0.59), Vector3(x, 0.80, -0.63),
			Vector3(x, 0.72, -0.60), Vector3(x, 0.70, -0.52)])
		k.add_limb(drop, PackedFloat32Array([0.014, 0.014, 0.014, 0.014, 0.014]), C_BLACK, 7)
		k.add_ellipsoid(Vector3(x, 0.885, -0.6), Vector3(0.018, 0.03, 0.045), C_BLACK, Basis.IDENTITY, 4, 8)
	# Цепь и задний переключатель (правая сторона, +X).
	var cog := REAR_AXLE + Vector3(0.045, 0.0, 0.0)
	var ring := BB + Vector3(0.065, 0.0, 0.0)
	k.add_tube(ring + Vector3(0, 0.105, 0), cog + Vector3(0, 0.05, 0), Vector2(0.005, 0.005), Vector2(0.005, 0.005), Color(0.3, 0.3, 0.32, 0.0), 5, false)
	k.add_tube(ring + Vector3(0, -0.105, 0), cog + Vector3(0, -0.09, 0.01), Vector2(0.005, 0.005), Vector2(0.005, 0.005), Color(0.3, 0.3, 0.32, 0.0), 5, false)
	k.add_box(Transform3D(Basis.IDENTITY, cog + Vector3(0.01, -0.07, 0.01)), Vector3(0.02, 0.07, 0.03), C_BLACK)
	# Флягодержатель с флягой на нижней трубе.
	var bottle_a: Vector3 = BB.lerp(ht_bot, 0.25) + Vector3(0, 0.05, 0.0)
	var bottle_b: Vector3 = BB.lerp(ht_bot, 0.62) + Vector3(0, 0.05, 0.0)
	k.add_tube(bottle_a, bottle_b, Vector2(0.034, 0.034), Vector2(0.034, 0.034), C_JERSEY_BLUE, 9)
	return k


static func _wheel(rear: bool) -> MeshKit:
	var k := MeshKit.new()
	k.add_torus_x(0.322, 0.014, C_TIRE, 40, 8)
	# Высокий обод: боковины (карбон + золотая полоса), внутренняя лента.
	for sx in [-1.0, 1.0]:
		k.add_annulus_x(0.012 * sx, 0.255, 0.292, C_RIM, sx, 40)
		k.add_annulus_x(0.0125 * sx, 0.292, 0.31, C_RIM_STRIPE, sx, 40)
	k.add_band_x(-0.012, 0.012, 0.255, C_RIM, false, 40)
	k.add_band_x(-0.012, 0.012, 0.31, C_RIM, true, 40)
	# Втулка и спицы.
	k.add_tube(Vector3(-0.045, 0, 0), Vector3(0.045, 0, 0), Vector2(0.02, 0.02), Vector2(0.02, 0.02), C_SILVER, 10)
	var spokes: int = 18
	for i in spokes:
		var ang: float = TAU * float(i) / float(spokes)
		var sx: float = -1.0 if i % 2 == 0 else 1.0
		var hub := Vector3(0.03 * sx, cos(ang + 0.15) * 0.018, sin(ang + 0.15) * 0.018)
		var rim := Vector3(0.004 * sx, cos(ang) * 0.255, sin(ang) * 0.255)
		k.add_tube(hub, rim, Vector2(0.0025, 0.0025), Vector2(0.0025, 0.0025), Color(0.2, 0.2, 0.22, 0.0), 4, false)
	if rear:
		for i in 4:
			var x: float = 0.028 + 0.006 * float(i)
			var r: float = 0.06 - 0.008 * float(i)
			k.add_annulus_x(x, 0.02, r, C_SILVER, 1.0, 16)
			k.add_annulus_x(x - 0.002, 0.02, r, C_SILVER, -1.0, 16)
	return k


## Шатуны в системе узла `Crank` (он развёрнут на 180° вокруг Y: локальный +X — левая сторона
## велосипеда, положительный поворот вокруг X — педалирование вперёд).
static func _crank() -> MeshKit:
	var k := MeshKit.new()
	var l: float = CRANK_LENGTH_M
	k.add_tube(Vector3(-0.1, 0, 0), Vector3(0.1, 0, 0), Vector2(0.014, 0.014), Vector2(0.014, 0.014), C_SILVER, 8)
	k.add_tube(Vector3(-0.09, 0, 0), Vector3(-0.09, l, 0), Vector2(0.016, 0.022), Vector2(0.012, 0.014), C_BLACK, 8)
	k.add_tube(Vector3(0.09, 0, 0), Vector3(0.09, -l, 0), Vector2(0.016, 0.022), Vector2(0.012, 0.014), C_BLACK, 8)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(-PEDAL_X_M - 0.01, l, 0)), Vector3(0.07, 0.018, 0.08), C_BLACK)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(PEDAL_X_M + 0.01, -l, 0)), Vector3(0.07, 0.018, 0.08), C_BLACK)
	var ring_col := Color(0.15, 0.15, 0.17, 0.0)
	k.add_annulus_x(-0.068, 0.06, 0.105, ring_col, -1.0, 36)
	k.add_annulus_x(-0.062, 0.06, 0.105, ring_col, 1.0, 36)
	k.add_band_x(-0.068, -0.062, 0.105, C_SILVER, true, 36)
	return k


static func _upper() -> MeshKit:
	var k := MeshKit.new()
	# Таз в шортах и корпус в джерси с красными боковыми вставками: спина почти
	# горизонтальна — гоночная посадка «в нижнем хвате».
	k.add_ellipsoid(PELVIS, Vector3(0.135, 0.11, 0.14), C_SHORTS, Basis.IDENTITY, 6, 12)
	k.add_tube(Vector3(0, 1.0, 0.19), Vector3(0, 1.07, 0.08), Vector2(0.135, 0.11), Vector2(0.15, 0.112), C_SHORTS, 12, false)
	k.add_tube(Vector3(0, 1.05, 0.11), Vector3(0, 1.2, -0.25), Vector2(0.148, 0.11), Vector2(0.18, 0.115), C_JERSEY, 14,
		false, Vector3.RIGHT, C_JERSEY_RED, 0.82)
	var shoulder_basis := Basis(Vector3.RIGHT, -0.35)
	k.add_ellipsoid(Vector3(0, 1.2, -0.26), Vector3(0.2, 0.095, 0.12), C_JERSEY, shoulder_basis, 7, 14, 0, -1.0, -0.84, C_JERSEY_BLUE)
	k.add_ellipsoid(Vector3(0, 1.2, -0.26), Vector3(0.2001, 0.0951, 0.1201), C_JERSEY, shoulder_basis, 7, 14, 0, 0.84, 1.0, C_JERSEY_BLUE)
	# Красная полоса поперёк спины.
	k.add_tube(Vector3(0, 1.145, -0.1), Vector3(0, 1.162, -0.145), Vector2(0.168, 0.117), Vector2(0.171, 0.118), C_JERSEY_RED, 14, false)
	# Шея, голова, шлем, очки.
	k.add_tube(Vector3(0, 1.23, -0.31), Vector3(0, 1.31, -0.4), Vector2(0.05, 0.05), Vector2(0.048, 0.048), C_SKIN, 8, false)
	k.add_ellipsoid(Vector3(0, 1.335, -0.44), Vector3(0.082, 0.098, 0.1), C_SKIN, Basis.IDENTITY, 6, 12)
	var helmet_basis := Basis(Vector3.RIGHT, 0.12)
	k.add_ellipsoid(Vector3(0, 1.385, -0.425), Vector3(0.11, 0.08, 0.155), C_HELMET, helmet_basis, 7, 14, 0, -0.18, 0.18, C_BLACK)
	k.add_ellipsoid(Vector3(0, 1.345, -0.512), Vector3(0.088, 0.024, 0.035), C_BLACK, Basis.IDENTITY, 4, 10)
	# Руки: от плеча к тормозной ручке, локти слегка наружу и вниз.
	for sx in [-1.0, 1.0]:
		var shoulder := Vector3(0.18 * sx, 1.21, -0.28)
		var hand := Vector3(0.205 * sx, 0.895, -0.6)
		var elbow: Vector3 = two_bone_joint(shoulder, hand, 0.25, 0.24, Vector3(0.35 * sx, 0.6, 0.7))
		var cuff: Vector3 = shoulder.lerp(elbow, 0.5)
		var cuff_end: Vector3 = shoulder.lerp(elbow, 0.64)
		k.add_ellipsoid(shoulder, Vector3(0.06, 0.06, 0.06), C_JERSEY, Basis.IDENTITY, 5, 10)
		k.add_tube(shoulder, cuff, Vector2(0.06, 0.06), Vector2(0.054, 0.054), C_JERSEY, 10, false)
		k.add_tube(cuff, cuff_end, Vector2(0.054, 0.054), Vector2(0.052, 0.052), C_JERSEY_BLUE, 10, false)
		k.add_tube(cuff_end, elbow, Vector2(0.046, 0.046), Vector2(0.042, 0.042), C_SKIN, 10, false)
		k.add_ellipsoid(elbow, Vector3(0.042, 0.042, 0.042), C_SKIN, Basis.IDENTITY, 5, 10)
		var wrist: Vector3 = elbow.lerp(hand, 0.82)
		k.add_tube(elbow, wrist, Vector2(0.042, 0.042), Vector2(0.032, 0.032), C_SKIN, 10, false)
		k.add_ellipsoid(hand + Vector3(0, 0.0, 0.01), Vector3(0.042, 0.04, 0.062), C_BLACK, Basis.IDENTITY, 5, 10)
	return k


static func _thigh() -> MeshKit:
	var k := MeshKit.new()
	var l: float = THIGH_M
	k.add_ellipsoid(Vector3.ZERO, Vector3(0.088, 0.088, 0.088), C_SHORTS, Basis.IDENTITY, 6, 12)
	k.add_tube(Vector3.ZERO, Vector3(0, -l * 0.62, 0), Vector2(0.088, 0.09), Vector2(0.074, 0.076), C_SHORTS, 12, false)
	k.add_tube(Vector3(0, -l * 0.62, 0), Vector3(0, -l * 0.66, 0), Vector2(0.075, 0.077), Vector2(0.073, 0.075), C_BLACK, 12, false)
	k.add_tube(Vector3(0, -l * 0.66, 0), Vector3(0, -l, 0), Vector2(0.071, 0.072), Vector2(0.056, 0.056), C_SKIN, 12, false)
	k.add_ellipsoid(Vector3(0, -l, 0), Vector3(0.056, 0.056, 0.056), C_SKIN, Basis.IDENTITY, 5, 12)
	return k


static func _shin() -> MeshKit:
	var k := MeshKit.new()
	var l: float = SHIN_M
	# Икра — объём сзади (локальный +Z при сгибе колена вперёд).
	k.add_tube(Vector3.ZERO, Vector3(0, -l * 0.3, 0.012), Vector2(0.054, 0.054), Vector2(0.06, 0.066), C_SKIN, 12, false)
	k.add_tube(Vector3(0, -l * 0.3, 0.012), Vector3(0, -l * 0.68, 0), Vector2(0.06, 0.066), Vector2(0.042, 0.044), C_SKIN, 12, false)
	k.add_tube(Vector3(0, -l * 0.68, 0), Vector3(0, -l, 0), Vector2(0.043, 0.045), Vector2(0.038, 0.04), C_SOCK, 12, true)
	return k


## Туфля: начало координат — голеностоп, носок вперёд (−Z) к педали.
static func _shoe() -> MeshKit:
	var k := MeshKit.new()
	var basis := Basis(Vector3.RIGHT, -0.32)
	k.add_ellipsoid(Vector3(0, -0.045, -0.06), Vector3(0.046, 0.042, 0.13), C_SHOE, basis, 6, 12, 1, -1.0, -0.55, C_BLACK)
	return k
