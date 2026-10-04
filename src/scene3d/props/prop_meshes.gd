class_name PropMeshes
extends RefCounted
## Низкополигональные меши ориентиров и построек трасс (T-083, REQ-D3D-08 п.12;
## `docs/game/tracks.md` п. 4.5, 5, 6): постройки, башни, ветряки, животные, стога, изгороди;
## горы (T-087): таблички «км до вершины» и «Перевал» с цифрами из сегментов, водопад, знак
## перевала, флажки, шале, хижина пастуха, пролёт противолавинной галереи, опоры, станции и
## кабинки канатной дороги, коровы, лесопилка, палатки, крест на скале; приморье (T-088): лодки,
## пляжные зонтики и шезлонги, белые домики с синими ставнями, кипарисы, парусник, камыши,
## оливы, маяк (фонарь — отдельный анимированный меш с вращающимся светом без источника света),
## скалы-кекуры и брызги, фонари и балюстрада набережной, вышка спасателя; фонарь моста (T-090).
## Всё собирается `MeshKit` из примитивов с цветом вершин в палитре арт-библии и трассы и
## красится одним тун-материалом мира (бюджет материалов не растёт); альфа цвета — вес
## контура. Вращающиеся части (лопасти ветряков и мельницы) и воздушный шар — отдельные меши
## под анимированный материал (`prop_anim.gdshader`): ось вращения — локальная Z, центр — 0.
## Меши кэшируются по ключу, цвету палитры и материалу; строятся только при построении мира.

const C_INK := Color(0.12, 0.12, 0.15, 0.0)
const C_WINDOW := Color(0.22, 0.30, 0.42, 0.0)
const C_DOOR := Color(0.36, 0.26, 0.20, 0.0)
const C_WOOD := Color(0.55, 0.42, 0.30, 0.5)
const C_WOOD_DARK := Color(0.42, 0.32, 0.24, 0.5)
const C_CONCRETE := Color(0.80, 0.78, 0.72, 1.0)
const C_CONCRETE_DARK := Color(0.66, 0.64, 0.60, 1.0)
const C_STONE := Color(0.62, 0.60, 0.56, 1.0)
const C_STONE_DARK := Color(0.50, 0.49, 0.47, 1.0)
const C_SLATE := Color(0.38, 0.40, 0.45, 1.0)
const C_STRAW := Color(0.86, 0.79, 0.54, 1.0)
const C_STRAW_DARK := Color(0.76, 0.68, 0.46, 1.0)
const C_WHITE := Color(0.93, 0.93, 0.92, 1.0)
const C_LEAF := Color(0.36, 0.55, 0.23, 1.0)

static var _cache: Dictionary = {}


## Меш по ключу (`house`, `barn`, `silo`, `water_tower`, `turbine`, `turbine_rotor`, …);
## `wall`/`roof` — цвета построек палитры трассы. Неизвестный ключ — пустой меш.
static func mesh(key: String, material: Material, wall: Color = Color(0.93, 0.89, 0.80),
		roof: Color = Color(0.78, 0.32, 0.24)) -> ArrayMesh:
	var full_key: String = "%s:%s:%s:%d" % [key, wall.to_html(), roof.to_html(),
		material.get_instance_id() if material != null else 0]
	if _cache.has(full_key):
		return _cache[full_key]
	var kit := MeshKit.new()
	_build(key, kit, Color(wall, 1.0), Color(roof, 1.0))
	var m := kit.to_mesh(material)
	_cache[full_key] = m
	return m


static func _build(key: String, kit: MeshKit, wall: Color, roof: Color) -> void:
	if key.begins_with("km_sign_"):
		_km_sign(kit, int(key.substr(8)))
		return
	if key.begins_with("pass_sign_"):
		_pass_sign(kit, int(key.substr(10)))
		return
	match key:
		"house":
			_house(kit, Vector3(8.0, 4.6, 6.0), wall, roof)
		"house_small":
			_house(kit, Vector3(6.0, 3.6, 5.0), wall, roof)
		"barn":
			_barn(kit)
		"silo":
			_silo(kit, 3.0, 16.0)
		"water_tower":
			_water_tower(kit)
		"turbine":
			_turbine(kit)
		"turbine_rotor":
			_turbine_rotor(kit)
		"grain_elevator":
			_grain_elevator(kit)
		"haystack":
			_haystack(kit)
		"sunflowers":
			_sunflowers(kit)
		"willow":
			_willow(kit)
		"railing":
			_railing(kit)
		"parapet":
			_parapet(kit)
		"chapel":
			_chapel(kit)
		"sheep":
			_sheep(kit)
		"hay_bale":
			_hay_bale(kit)
		"oak":
			_oak(kit)
		"bench":
			_bench(kit)
		"windmill":
			_windmill(kit)
		"windmill_sails":
			_windmill_sails(kit)
		"horse":
			_horse(kit)
		"fence":
			_fence(kit)
		"castle":
			_castle(kit)
		"tv_tower":
			_tv_tower(kit)
		"vines":
			_vines(kit)
		"balloon":
			_balloon(kit)
		"waterfall":
			_waterfall(kit)
		"monument":
			_monument(kit)
		"flags":
			_flags(kit)
		"chalet":
			_chalet(kit, wall, roof)
		"stone_hut":
			_stone_hut(kit)
		"gallery_bay":
			_gallery_bay(kit)
		"cable_tower":
			_cable_tower(kit)
		"cable_station":
			_cable_station(kit, roof)
		"cabin":
			_cabin(kit, roof)
		"cow":
			_cow(kit)
		"sawmill_shed":
			_sawmill_shed(kit, roof)
		"log_pile":
			_log_pile(kit)
		"water_wheel":
			_water_wheel(kit)
		"tent":
			_tent(kit)
		"fire_ring":
			_fire_ring(kit)
		"summit_cross":
			_summit_cross(kit)
		"crag":
			_crag(kit)
		"boat":
			_boat(kit)
		"umbrella_a":
			_umbrella(kit, Color(0.86, 0.50, 0.40, 1.0))
		"umbrella_b":
			_umbrella(kit, Color(0.32, 0.58, 0.62, 1.0))
		"lounger":
			_lounger(kit)
		"white_house":
			_white_house(kit, Vector3(8.0, 6.4, 6.5), roof, true)
		"white_house_small":
			_white_house(kit, Vector3(6.0, 3.8, 5.0), roof, false)
		"cypress":
			_cypress(kit)
		"sailboat":
			_sailboat(kit)
		"reeds":
			_reeds(kit)
		"olive":
			_olive(kit)
		"lighthouse":
			_lighthouse(kit)
		"lighthouse_lamp":
			_lighthouse_lamp(kit)
		"sea_stack":
			_sea_stack(kit)
		"spray":
			_spray(kit)
		"street_lamp":
			_street_lamp(kit)
		"balustrade":
			_balustrade(kit)
		"lifeguard_tower":
			_lifeguard_tower(kit)
		"bridge_lamp":
			_bridge_lamp(kit)


# ---------------------------------------------------------------------------
# Постройки
# ---------------------------------------------------------------------------

## Дом: стены `size` (x — длина по коньку), двускатная крыша, дверь и окна на длинных
## сторонах (+Z — к дороге), труба.
static func _house(kit: MeshKit, size: Vector3, wall: Color, roof: Color) -> void:
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, size.y * 0.5 - 0.3, 0.0)), Vector3(size.x, size.y + 0.6, size.z), wall)
	kit.add_gable_roof(Transform3D(Basis.IDENTITY, Vector3(0.0, size.y, 0.0)), Vector3(size.x, size.z * 0.42, size.z), 0.45,
		roof, wall)
	for zs in [-1.0, 1.0]:
		var z: float = zs * (size.z * 0.5 + 0.04)
		for i in 2:
			var x: float = (float(i) - 0.5) * size.x * 0.5 + size.x * 0.12
			kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, size.y * 0.58, z)), Vector3(1.0, 1.0, 0.1), C_WINDOW)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(-size.x * 0.3, 1.05, size.z * 0.5 + 0.04)), Vector3(1.1, 2.1, 0.1), C_DOOR)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(size.x * 0.28, size.y + size.z * 0.38, -size.z * 0.18)),
		Vector3(0.7, 1.8, 0.7), C_STONE_DARK)


static func _barn(kit: MeshKit) -> void:
	var walls := Color(0.60, 0.32, 0.24, 1.0)
	var roof := Color(0.44, 0.44, 0.47, 1.0)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 3.2, 0.0)), Vector3(14.0, 7.0, 9.0), walls)
	kit.add_gable_roof(Transform3D(Basis.IDENTITY, Vector3(0.0, 6.7, 0.0)), Vector3(14.0, 3.8, 9.0), 0.5, roof, walls)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(7.05, 2.2, 0.0)), Vector3(0.1, 4.4, 4.0), C_DOOR)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(7.08, 2.2, 0.0)), Vector3(0.1, 4.4, 0.25), C_WHITE)


static func _silo(kit: MeshKit, r: float, h: float) -> void:
	kit.add_tube(Vector3(0.0, -0.5, 0.0), Vector3(0.0, h, 0.0), Vector2(r, r), Vector2(r, r), C_CONCRETE, 14)
	for i in 3:
		var y: float = h * (0.25 + 0.25 * float(i))
		kit.add_tube(Vector3(0.0, y, 0.0), Vector3(0.0, y + 0.35, 0.0), Vector2(r + 0.06, r + 0.06), Vector2(r + 0.06, r + 0.06),
			C_CONCRETE_DARK, 14)
	kit.add_ellipsoid(Vector3(0.0, h, 0.0), Vector3(r, r * 0.6, r), Color(0.60, 0.65, 0.70, 1.0), Basis.IDENTITY, 5, 14)


static func _water_tower(kit: MeshKit) -> void:
	kit.add_tube(Vector3(0.0, -0.5, 0.0), Vector3(0.0, 20.0, 0.0), Vector2(1.5, 1.5), Vector2(1.2, 1.2), C_CONCRETE, 12)
	kit.add_tube(Vector3(0.0, 19.6, 0.0), Vector3(0.0, 20.2, 0.0), Vector2(2.8, 2.8), Vector2(2.8, 2.8), C_CONCRETE_DARK, 14)
	var tank := Color(0.60, 0.68, 0.74, 1.0)
	kit.add_tube(Vector3(0.0, 20.2, 0.0), Vector3(0.0, 25.4, 0.0), Vector2(3.8, 3.8), Vector2(4.2, 4.2), tank, 16)
	kit.add_cone(Vector3(0.0, 25.4, 0.0), 2.0, 4.4, Color(0.44, 0.50, 0.56, 1.0), 16)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 1.45)), Vector3(1.0, 2.0, 0.2), C_DOOR)


## Ветряк: башня 62 м и гондола; ротор — отдельный меш `turbine_rotor` (крепление — `TURBINE_HUB`).
const TURBINE_HUB := Vector3(0.0, 63.0, 2.9)


static func _turbine(kit: MeshKit) -> void:
	kit.add_tube(Vector3(0.0, -0.5, 0.0), Vector3(0.0, 62.5, 0.0), Vector2(1.8, 1.8), Vector2(0.9, 0.9), C_WHITE, 12)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 63.0, 0.2)), Vector3(2.4, 2.4, 5.6), C_WHITE)


static func _turbine_rotor(kit: MeshKit) -> void:
	var blade := Color(0.95, 0.95, 0.95, 1.0)
	kit.add_ellipsoid(Vector3.ZERO, Vector3(0.9, 0.9, 1.4), C_WHITE, Basis.IDENTITY, 5, 10)
	for i in 3:
		var a: float = TAU * float(i) / 3.0
		var dir := Vector3(sin(a), cos(a), 0.0)
		kit.add_tube(dir * 0.6, dir * 30.0, Vector2(0.9, 0.22), Vector2(0.25, 0.08), blade, 6, true, Vector3(cos(a), -sin(a), 0.0))


static func _grain_elevator(kit: MeshKit) -> void:
	for ix in 2:
		for iz in 2:
			var c := Vector3(float(ix) * 7.0 - 3.5, 0.0, float(iz) * 7.0 - 3.5)
			kit.add_tube(c + Vector3(0.0, -0.5, 0.0), c + Vector3(0.0, 28.0, 0.0), Vector2(3.4, 3.4), Vector2(3.4, 3.4), C_CONCRETE, 14)
			kit.add_cone(c + Vector3(0.0, 28.0, 0.0), 1.6, 3.4, C_CONCRETE_DARK, 14)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(9.0, 19.0, 0.0)), Vector3(7.0, 39.0, 8.0), C_CONCRETE)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(9.0, 39.2, 0.0)), Vector3(7.6, 1.0, 8.6), C_CONCRETE_DARK)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(4.8, 30.0, 0.0)), Vector3(4.0, 1.6, 1.6), C_CONCRETE_DARK)
	for i in 4:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(9.0, 8.0 + 8.0 * float(i), 4.06)), Vector3(1.2, 1.2, 0.1), C_WINDOW)


## Стог: высокий округлый конус соломы, тёмная «шапка» и жердь.
static func _haystack(kit: MeshKit) -> void:
	kit.add_tube(Vector3(0.0, -0.3, 0.0), Vector3(0.0, 2.2, 0.0), Vector2(2.3, 2.3), Vector2(2.1, 2.1), C_STRAW, 12, false)
	kit.add_ellipsoid(Vector3(0.0, 2.2, 0.0), Vector3(2.1, 2.0, 2.1), C_STRAW, Basis.IDENTITY, 6, 12)
	kit.add_ellipsoid(Vector3(0.0, 3.9, 0.0), Vector3(0.8, 0.7, 0.8), C_STRAW_DARK, Basis.IDENTITY, 5, 10)
	kit.add_tube(Vector3(0.0, 3.8, 0.0), Vector3(0.0, 5.0, 0.0), Vector2(0.06, 0.06), Vector2(0.05, 0.05), C_WOOD_DARK, 4)


## Куртина подсолнухов 3 × 4 м: тёмная зелёная масса листвы и 12 корзинок на стеблях,
## повёрнутых к +Z (к дороге).
static func _sunflowers(kit: MeshKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var leaves := Color(0.40, 0.55, 0.25, 0.0)
	kit.add_ellipsoid(Vector3(-0.7, 0.75, -0.9), Vector3(1.0, 0.9, 1.2), leaves, Basis.IDENTITY, 5, 8)
	kit.add_ellipsoid(Vector3(0.7, 0.8, 0.9), Vector3(1.0, 0.95, 1.2), leaves.darkened(0.06), Basis.IDENTITY, 5, 8)
	kit.add_ellipsoid(Vector3(0.6, 0.7, -1.0), Vector3(0.9, 0.8, 1.0), leaves.lightened(0.05), Basis.IDENTITY, 5, 8)
	kit.add_ellipsoid(Vector3(-0.6, 0.72, 1.0), Vector3(0.9, 0.85, 1.0), leaves, Basis.IDENTITY, 5, 8)
	var head := Color(0.92, 0.74, 0.22, 0.4)
	var core := Color(0.36, 0.25, 0.14, 0.0)
	for ix in 3:
		for iz in 4:
			var b := Vector3(float(ix) - 1.0 + rng.randf_range(-0.2, 0.2), 0.0, float(iz) * 1.0 - 1.5 + rng.randf_range(-0.2, 0.2))
			var h: float = rng.randf_range(1.6, 2.1)
			var top := b + Vector3(0.0, h, 0.0)
			kit.add_tube(b + Vector3(0.0, 1.2, 0.0), top, Vector2(0.04, 0.04), Vector2(0.03, 0.03), Color(0.34, 0.48, 0.20, 0.0), 4, false)
			var face := Vector3(rng.randf_range(-0.2, 0.2), 0.45, 1.0).normalized()
			kit.add_tube(top - face * 0.06, top + face * 0.06, Vector2(0.32, 0.32), Vector2(0.30, 0.30), head, 9)
			kit.add_tube(top + face * 0.06, top + face * 0.09, Vector2(0.14, 0.14), Vector2(0.12, 0.12), core, 7)


static func _willow(kit: MeshKit) -> void:
	kit.add_tube(Vector3(0.0, -0.3, 0.0), Vector3(0.2, 3.2, 0.0), Vector2(0.35, 0.35), Vector2(0.22, 0.22), Color(0.40, 0.34, 0.27, 1.0), 7)
	kit.add_ellipsoid(Vector3(0.2, 4.6, 0.0), Vector3(3.3, 2.4, 3.3), Color(0.50, 0.62, 0.34, 1.0), Basis.IDENTITY, 6, 12)
	kit.add_ellipsoid(Vector3(0.2, 3.2, 0.0), Vector3(3.8, 1.8, 3.8), Color(0.56, 0.67, 0.38, 1.0), Basis.IDENTITY, 6, 12)


## Деревянные перила мостика: 14 м вдоль X, стойки через 2 м.
static func _railing(kit: MeshKit) -> void:
	for i in 8:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(-7.0 + 2.0 * float(i), 0.5, 0.0)), Vector3(0.14, 1.1, 0.14), C_WOOD_DARK)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), Vector3(14.2, 0.12, 0.12), C_WOOD)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.55, 0.0)), Vector3(14.2, 0.09, 0.08), C_WOOD)


## Каменный парапет моста: 16 м вдоль X, столбы на концах.
static func _parapet(kit: MeshKit) -> void:
	var stone := Color(0.76, 0.73, 0.66, 0.5)
	var cap := Color(0.84, 0.82, 0.76, 0.5)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0)), Vector3(16.0, 0.9, 0.5), stone)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.81, 0.0)), Vector3(16.3, 0.14, 0.62), cap)
	for x in [-8.3, 8.3]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 0.5, 0.0)), Vector3(0.8, 1.4, 0.8), stone)
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 1.24, 0.0)), Vector3(0.9, 0.12, 0.9), cap)


static func _chapel(kit: MeshKit) -> void:
	var walls := Color(0.95, 0.93, 0.88, 1.0)
	var roof := Color(0.52, 0.30, 0.26, 1.0)
	var rot := Basis(Vector3.UP, PI * 0.5)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.8, 0.0)), Vector3(7.0, 6.2, 11.0), walls)
	kit.add_gable_roof(Transform3D(rot, Vector3(0.0, 5.9, 0.0)), Vector3(11.0, 3.6, 7.0), 0.4, roof, walls)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 6.0, 6.6)), Vector3(3.4, 12.6, 3.4), walls)
	kit.add_pyramid(Vector3(0.0, 12.3, 6.6), Vector2(2.0, 2.0), 5.0, C_SLATE)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 18.3, 6.6)), Vector3(0.14, 1.6, 0.14), C_INK)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 18.6, 6.6)), Vector3(0.8, 0.14, 0.14), C_INK)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 9.6, 8.32)), Vector3(1.0, 1.4, 0.1), C_INK)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.3, 8.32)), Vector3(1.4, 2.6, 0.1), C_DOOR)
	for z in [-3.0, 0.0, 3.0]:
		for xs in [-1.0, 1.0]:
			kit.add_box(Transform3D(Basis.IDENTITY, Vector3(xs * 3.54, 3.4, z)), Vector3(0.1, 1.8, 0.8), C_WINDOW)


# ---------------------------------------------------------------------------
# Животные, сено, сад
# ---------------------------------------------------------------------------

## Овца: шерсть «облачком», тёмные голова и ноги; смотрит вдоль +X.
static func _sheep(kit: MeshKit) -> void:
	var wool := Color(0.95, 0.94, 0.90, 1.0)
	var dark := Color(0.20, 0.19, 0.20, 0.6)
	kit.add_ellipsoid(Vector3(0.0, 0.78, 0.0), Vector3(0.75, 0.52, 0.48), wool, Basis.IDENTITY, 6, 10)
	kit.add_ellipsoid(Vector3(0.25, 1.05, 0.0), Vector3(0.45, 0.35, 0.40), wool, Basis.IDENTITY, 5, 9)
	kit.add_ellipsoid(Vector3(0.82, 0.95, 0.0), Vector3(0.26, 0.2, 0.18), dark, Basis.IDENTITY, 5, 8)
	for x in [-0.4, 0.4]:
		for z in [-0.22, 0.22]:
			kit.add_tube(Vector3(x, 0.45, z), Vector3(x, 0.0, z), Vector2(0.06, 0.06), Vector2(0.05, 0.05), dark, 5)


static func _hay_bale(kit: MeshKit) -> void:
	kit.add_tube(Vector3(-0.65, 0.82, 0.0), Vector3(0.65, 0.82, 0.0), Vector2(0.85, 0.85), Vector2(0.85, 0.85), Color(0.82, 0.70, 0.40, 1.0),
		14, true, Vector3.UP)


## Большой одинокий дуб: широкий ствол, крона из пяти шаров.
static func _oak(kit: MeshKit) -> void:
	var bark := Color(0.40, 0.30, 0.22, 1.0)
	kit.add_tube(Vector3(0, -0.3, 0), Vector3(0, 4.0, 0), Vector2(0.55, 0.55), Vector2(0.35, 0.35), bark, 8)
	kit.add_tube(Vector3(0, 3.2, 0), Vector3(2.0, 5.4, 0.4), Vector2(0.22, 0.22), Vector2(0.14, 0.14), bark, 6)
	kit.add_tube(Vector3(0, 3.4, 0), Vector3(-1.8, 5.6, -0.6), Vector2(0.22, 0.22), Vector2(0.14, 0.14), bark, 6)
	var leaf := Color(0.38, 0.58, 0.23, 1.0)
	var dark := Color(0.31, 0.50, 0.21, 1.0)
	kit.add_ellipsoid(Vector3(0.0, 6.2, 0.0), Vector3(4.2, 2.8, 4.2), dark, Basis.IDENTITY, 7, 14)
	kit.add_ellipsoid(Vector3(2.2, 7.0, 0.8), Vector3(2.6, 2.1, 2.6), leaf, Basis.IDENTITY, 6, 12)
	kit.add_ellipsoid(Vector3(-2.0, 7.2, -0.9), Vector3(2.5, 2.0, 2.5), leaf, Basis.IDENTITY, 6, 12)
	kit.add_ellipsoid(Vector3(0.3, 8.4, 0.2), Vector3(2.6, 1.9, 2.6), leaf, Basis.IDENTITY, 6, 12)
	kit.add_ellipsoid(Vector3(-0.4, 7.0, 2.2), Vector3(2.2, 1.8, 2.2), leaf, Basis.IDENTITY, 6, 12)


static func _bench(kit: MeshKit) -> void:
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.48, 0.0)), Vector3(1.9, 0.08, 0.5), C_WOOD)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.85, -0.24)), Vector3(1.9, 0.35, 0.06), C_WOOD)
	for x in [-0.8, 0.8]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 0.22, 0.0)), Vector3(0.08, 0.5, 0.45), C_WOOD_DARK)


## Ветряная мельница: белёная башня, деревянная шапка; крылья — `windmill_sails` (крепление — `WINDMILL_HUB`).
const WINDMILL_HUB := Vector3(0.0, 13.0, 3.4)


static func _windmill(kit: MeshKit) -> void:
	kit.add_tube(Vector3(0.0, -0.5, 0.0), Vector3(0.0, 12.5, 0.0), Vector2(3.6, 3.6), Vector2(2.5, 2.5), Color(0.92, 0.90, 0.84, 1.0), 12)
	kit.add_ellipsoid(Vector3(0.0, 12.9, 0.3), Vector3(2.8, 2.2, 3.2), Color(0.42, 0.33, 0.26, 1.0), Basis.IDENTITY, 6, 12)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.2, 3.45)), Vector3(1.3, 2.4, 0.2), C_DOOR)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 6.5, 3.0)), Vector3(0.9, 1.1, 0.2), C_WINDOW)
	kit.add_tube(Vector3(0.0, 13.0, 1.8), Vector3(0.0, 13.0, 3.4), Vector2(0.3, 0.3), Vector2(0.3, 0.3), C_WOOD_DARK, 6)


static func _windmill_sails(kit: MeshKit) -> void:
	var cloth := Color(0.90, 0.86, 0.76, 0.6)
	kit.add_ellipsoid(Vector3.ZERO, Vector3(0.5, 0.5, 0.5), C_WOOD_DARK, Basis.IDENTITY, 4, 8)
	for i in 4:
		var a: float = TAU * float(i) / 4.0 + 0.3
		var dir := Vector3(sin(a), cos(a), 0.0)
		var side := Vector3(cos(a), -sin(a), 0.0)
		kit.add_tube(dir * 0.3, dir * 11.5, Vector2(0.14, 0.14), Vector2(0.1, 0.1), C_WOOD_DARK, 4)
		var basis := Basis(side, dir, Vector3.BACK)
		kit.add_box(Transform3D(basis, dir * 6.6 + side * 0.85), Vector3(1.6, 9.0, 0.08), cloth)


## Лошадь, смотрит вдоль +X; масть — цвет экземпляра.
static func _horse(kit: MeshKit) -> void:
	var coat := Color(0.80, 0.80, 0.80, 1.0)
	var mane := Color(0.25, 0.22, 0.20, 0.8)
	kit.add_ellipsoid(Vector3(0.0, 1.35, 0.0), Vector3(1.05, 0.5, 0.42), coat, Basis.IDENTITY, 6, 10)
	kit.add_tube(Vector3(0.75, 1.55, 0.0), Vector3(1.15, 2.2, 0.0), Vector2(0.24, 0.3), Vector2(0.18, 0.2), coat, 7)
	kit.add_ellipsoid(Vector3(1.35, 2.1, 0.0), Vector3(0.42, 0.18, 0.17), coat, Basis(Vector3.BACK, -0.6), 5, 8)
	kit.add_tube(Vector3(0.7, 1.75, 0.0), Vector3(1.1, 2.35, 0.0), Vector2(0.06, 0.06), Vector2(0.05, 0.05), mane, 4)
	kit.add_tube(Vector3(-1.0, 1.5, 0.0), Vector3(-1.25, 0.8, 0.0), Vector2(0.09, 0.09), Vector2(0.05, 0.05), mane, 4)
	for x in [-0.7, 0.7]:
		for z in [-0.22, 0.22]:
			kit.add_tube(Vector3(x, 1.1, z), Vector3(x, 0.0, z), Vector2(0.1, 0.1), Vector2(0.07, 0.07), coat, 5)


## Звено жердевой изгороди: 6 м вдоль X, столб у начала, две жерди.
static func _fence(kit: MeshKit) -> void:
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(-3.0, 0.6, 0.0)), Vector3(0.16, 1.5, 0.16), C_WOOD_DARK)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.15, 0.0)), Vector3(6.0, 0.12, 0.09), C_WOOD)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.65, 0.0)), Vector3(6.0, 0.12, 0.09), C_WOOD)


## Руины замка (~50 × 30 м): круглая башня с зубцами, обломок второй, стены с рваным верхом.
static func _castle(kit: MeshKit) -> void:
	kit.add_tube(Vector3(-16.0, -2.0, 0.0), Vector3(-16.0, 24.0, 0.0), Vector2(5.5, 5.5), Vector2(5.0, 5.0), C_STONE, 14)
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		kit.add_box(Transform3D(Basis(Vector3.UP, -a), Vector3(-16.0 + cos(a) * 4.6, 25.0, sin(a) * 4.6)), Vector3(1.6, 2.0, 1.2), C_STONE)
	kit.add_tube(Vector3(18.0, -2.0, -6.0), Vector3(18.0, 13.0, -6.0), Vector2(4.5, 4.5), Vector2(4.3, 4.3), C_STONE_DARK, 12)
	var tops: Array[float] = [9.0, 12.0, 7.0, 10.5, 5.0, 8.0]
	for i in tops.size():
		var x: float = -11.0 + 5.0 * float(i)
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, tops[i] * 0.5 - 2.0, 0.0)), Vector3(5.2, tops[i] + 4.0, 2.6), C_STONE)
	var side_tops: Array[float] = [10.0, 6.0, 8.0]
	for i in side_tops.size():
		var z: float = -4.0 - 5.0 * float(i)
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(-11.0, 3.0, z)), Vector3(2.4, side_tops[i], 5.2), C_STONE_DARK)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(-16.0, 14.0, 5.4)), Vector3(1.0, 2.2, 0.3), C_INK)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(-4.0, 4.5, 1.35)), Vector3(1.0, 2.2, 0.2), C_INK)


## Телевышка: ствол 80 м красно-белыми полосами, площадка, антенна, будка у подножия.
static func _tv_tower(kit: MeshKit) -> void:
	var red := Color(0.80, 0.24, 0.20, 1.0)
	var h: float = 80.0
	for i in 8:
		var y0: float = h * float(i) / 8.0
		var y1: float = h * float(i + 1) / 8.0
		var r0: float = lerpf(2.2, 0.7, y0 / h)
		var r1: float = lerpf(2.2, 0.7, y1 / h)
		kit.add_tube(Vector3(0.0, y0 - (0.5 if i == 0 else 0.0), 0.0), Vector3(0.0, y1, 0.0), Vector2(r0, r0), Vector2(r1, r1),
			red if i % 2 == 1 else C_WHITE, 10, false)
	kit.add_tube(Vector3(0.0, 54.0, 0.0), Vector3(0.0, 56.0, 0.0), Vector2(3.6, 3.6), Vector2(3.6, 3.6), C_CONCRETE_DARK, 12)
	kit.add_tube(Vector3(0.0, h, 0.0), Vector3(0.0, h + 16.0, 0.0), Vector2(0.25, 0.25), Vector2(0.1, 0.1), C_SLATE, 6)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(6.0, 1.3, 0.0)), Vector3(5.0, 3.2, 4.0), C_CONCRETE)


## Ряд виноградника: звено 8 м вдоль X — шпалера (зелёная лента), лоза, столбики.
static func _vines(kit: MeshKit) -> void:
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), Vector3(8.0, 1.1, 0.7), Color(0.44, 0.61, 0.28, 0.3))
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0)), Vector3(8.0, 0.5, 0.14), Color(0.40, 0.31, 0.24, 0.0))
	for x in [-4.0, 4.0]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 0.8, 0.0)), Vector3(0.12, 1.8, 0.12), C_WOOD_DARK)


## Воздушный шар: оболочка дольками в два цвета, корзина и стропы. Начало — в корзине.
static func _balloon(kit: MeshKit) -> void:
	var a := Color(0.86, 0.36, 0.24, 1.0)
	var b := Color(0.96, 0.88, 0.62, 1.0)
	var rings: int = 10
	var segs: int = 16
	var center := Vector3(0.0, 13.0, 0.0)
	var radii := Vector3(7.0, 8.5, 7.0)
	for sgi in segs:
		var col: Color = MeshKit.lin(a if sgi % 2 == 0 else b)
		var start: int = kit.vertices.size()
		for r in rings + 1:
			var phi: float = PI * float(r) / float(rings)
			# Низ оболочки сужается к горловине.
			var pinch: float = 1.0 - 0.55 * smoothstep(0.55, 1.0, float(r) / float(rings))
			for k in 2:
				var theta: float = TAU * float(sgi + k) / float(segs)
				var unit := Vector3(sin(phi) * cos(theta) * pinch, cos(phi), sin(phi) * sin(theta) * pinch)
				kit.vertices.append(center + unit * radii)
				kit.normals.append(Vector3(unit.x / radii.x, unit.y / radii.y, unit.z / radii.z).normalized())
				kit.colors.append(col)
		for r in rings:
			var i0: int = start + r * 2
			kit.indices.append_array(PackedInt32Array([i0, i0 + 1, i0 + 2, i0 + 1, i0 + 3, i0 + 2]))
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.6, 0.0)), Vector3(1.6, 1.2, 1.6), Color(0.50, 0.38, 0.26, 1.0))
	for x in [-0.7, 0.7]:
		for z in [-0.7, 0.7]:
			kit.add_tube(Vector3(x, 1.2, z), Vector3(x * 2.4, 5.4, z * 2.4), Vector2(0.04, 0.04), Vector2(0.04, 0.04), C_INK, 3, false)


# ---------------------------------------------------------------------------
# Горы (T-087, `tracks.md` п. 4.3, 4.5)
# ---------------------------------------------------------------------------

const C_SIGN_WHITE := Color(0.96, 0.96, 0.94, 0.6)
const C_SIGN_INK := Color(0.10, 0.10, 0.12, 0.0)
const C_SIGN_BROWN := Color(0.42, 0.27, 0.18, 0.6)
const C_POST_GREY := Color(0.55, 0.57, 0.60, 0.6)
const C_ROCK := Color(0.47, 0.46, 0.50, 1.0)
const C_ROCK_DARK := Color(0.36, 0.36, 0.41, 1.0)
const C_FOAM := Color(0.93, 0.96, 0.98, 0.0)
const C_FALL := Color(0.78, 0.89, 0.95, 0.0)
const C_CABLE := Color(0.18, 0.18, 0.20, 0.0)

## Сегменты цифры (a, b, c, d, e, f, g) для 0–9.
const SEGMENTS: Array[String] = ["abcdef", "bc", "abged", "abgcd", "fgbc", "afgcd", "afgedc", "abc", "abcdefg", "abcdfg"]


## Цифра `d` из сегментов-брусков на плоскости XY (лицом к +Z) с нижним левым углом
## `origin`, высота `h`, толщина сегмента `t`.
static func _digit(kit: MeshKit, d: int, origin: Vector3, h: float, t: float, col: Color) -> void:
	var w: float = h * 0.55
	var hh: float = h * 0.5
	var segs: String = SEGMENTS[clampi(d, 0, 9)]
	var depth: float = 0.03
	var bars: Dictionary = {
		"a": [Vector3(w * 0.5, h - t * 0.5, 0.0), Vector3(w, t, depth)],
		"g": [Vector3(w * 0.5, hh, 0.0), Vector3(w, t, depth)],
		"d": [Vector3(w * 0.5, t * 0.5, 0.0), Vector3(w, t, depth)],
		"b": [Vector3(w - t * 0.5, hh + hh * 0.5, 0.0), Vector3(t, hh, depth)],
		"c": [Vector3(w - t * 0.5, hh * 0.5, 0.0), Vector3(t, hh, depth)],
		"f": [Vector3(t * 0.5, hh + hh * 0.5, 0.0), Vector3(t, hh, depth)],
		"e": [Vector3(t * 0.5, hh * 0.5, 0.0), Vector3(t, hh, depth)],
	}
	for k in segs:
		var bar: Array = bars[k]
		kit.add_box(Transform3D(Basis.IDENTITY, origin + (bar[0] as Vector3)), bar[1] as Vector3, col)


## Буквы «км» из брусков (высота `h`, нижний левый угол `origin`, лицом к +Z).
static func _km(kit: MeshKit, origin: Vector3, h: float, t: float, col: Color) -> void:
	var depth: float = 0.03
	# «к»: стойка и две диагонали.
	kit.add_box(Transform3D(Basis.IDENTITY, origin + Vector3(t * 0.5, h * 0.5, 0.0)), Vector3(t, h, depth), col)
	for sgn in [1.0, -1.0]:
		var c: Vector3 = origin + Vector3(t + h * 0.2, h * 0.5 + sgn * h * 0.24, 0.0)
		kit.add_box(Transform3D(Basis(Vector3.BACK, -sgn * 0.75), c), Vector3(t, h * 0.6, depth), col)
	# «м»: две стойки и «галочка».
	var x0: float = h * 0.78
	for x in [x0 + t * 0.5, x0 + h * 0.8 - t * 0.5]:
		kit.add_box(Transform3D(Basis.IDENTITY, origin + Vector3(x, h * 0.5, 0.0)), Vector3(t, h, depth), col)
	for sgn in [1.0, -1.0]:
		var c: Vector3 = origin + Vector3(x0 + h * 0.4 - sgn * h * 0.17, h * 0.66, 0.0)
		kit.add_box(Transform3D(Basis(Vector3.BACK, sgn * 0.55), c), Vector3(t, h * 0.6, depth), col)


## Табличка «N км до вершины»: белый щит в чёрной рамке на двух стойках, лицом к +Z
## (навстречу гонщику), крупная цифра и «км».
static func _km_sign(kit: MeshKit, n: int) -> void:
	for x in [-0.55, 0.55]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 0.9, -0.06)), Vector3(0.09, 2.6, 0.09), C_POST_GREY)
	var c := Vector3(0.0, 2.0, 0.0)
	kit.add_box(Transform3D(Basis.IDENTITY, c), Vector3(1.5, 1.05, 0.07), C_SIGN_INK)
	kit.add_box(Transform3D(Basis.IDENTITY, c + Vector3(0.0, 0.0, 0.02)), Vector3(1.38, 0.93, 0.06), C_SIGN_WHITE)
	_digit(kit, n, c + Vector3(-0.6, -0.36, 0.06), 0.72, 0.12, C_SIGN_INK)
	_km(kit, c + Vector3(-0.08, -0.36, 0.06), 0.42, 0.08, C_SIGN_INK)


## Табличка «Перевал N км»: коричневый щит, белая рамка, белая гора со снежной шапкой
## (пиктограмма), цифра и «км» — у подножия подъёма.
static func _pass_sign(kit: MeshKit, n: int) -> void:
	for x in [-1.0, 1.0]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 1.1, -0.07)), Vector3(0.12, 3.2, 0.12), C_POST_GREY)
	var c := Vector3(0.0, 2.45, 0.0)
	kit.add_box(Transform3D(Basis.IDENTITY, c), Vector3(2.6, 1.5, 0.08), C_SIGN_WHITE)
	kit.add_box(Transform3D(Basis.IDENTITY, c + Vector3(0.0, 0.0, 0.02)), Vector3(2.44, 1.34, 0.07), C_SIGN_BROWN)
	var white := Color(0.96, 0.96, 0.94, 0.0)
	var m0 := c + Vector3(-1.08, -0.5, 0.07)
	kit.add_triangle(m0, m0 + Vector3(1.0, 0.0, 0.0), m0 + Vector3(0.5, 0.95, 0.0), Vector3.BACK, Color(0.66, 0.70, 0.74, 0.0))
	kit.add_triangle(m0 + Vector3(0.31, 0.6, 0.01), m0 + Vector3(0.69, 0.6, 0.01), m0 + Vector3(0.5, 0.95, 0.01), Vector3.BACK, white)
	_digit(kit, n, c + Vector3(0.05, -0.45, 0.07), 0.9, 0.14, white)
	_km(kit, c + Vector3(0.66, -0.45, 0.07), 0.5, 0.09, white)


## Водопад на скальном уступе (~34 × 40 м, лицом к +Z): уступы скалы двух тонов, лента воды
## полосами, пенная чаша и камни у подножия. Низ скалы уходит в склон.
static func _waterfall(kit: MeshKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5517
	for i in 7:
		var w: float = rng.randf_range(9.0, 16.0)
		var h: float = rng.randf_range(22.0, 44.0)
		var x: float = -15.0 + float(i) * 5.0 + rng.randf_range(-1.5, 1.5)
		var z: float = -rng.randf_range(2.0, 7.0) - (0.0 if absf(x) > 5.0 else 3.0)
		var col: Color = C_ROCK if i % 2 == 0 else C_ROCK_DARK
		kit.add_box(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), Vector3(x, h * 0.5 - 6.0, z)), Vector3(w, h, 12.0), col)
	# Лента воды: падает с 36 м, расширяется книзу, полосы двух тонов.
	var top: float = 36.0
	for k in 5:
		var x0: float = -2.6 + float(k) * 1.04
		var col: Color = C_FOAM if k % 2 == 0 else C_FALL
		var a := Vector3(x0, top, 0.6)
		var b := Vector3(x0 + 1.04, top, 0.6)
		var c := Vector3((x0 + 1.04) * 1.6, 1.0, 2.2)
		var d := Vector3(x0 * 1.6, 1.0, 2.2)
		kit.add_quad(a, b, c, d, Vector3(0.0, 0.05, 1.0).normalized(), col)
	# Чаша с пеной и камни.
	kit.add_ellipsoid(Vector3(0.0, 0.2, 5.0), Vector3(8.0, 0.6, 5.0), Color(0.24, 0.62, 0.70, 0.0), Basis.IDENTITY, 4, 16)
	kit.add_ellipsoid(Vector3(0.0, 0.6, 2.8), Vector3(4.5, 1.2, 2.2), C_FOAM, Basis.IDENTITY, 4, 12)
	for i in 6:
		var a: float = TAU * float(i) / 6.0 + 0.4
		kit.add_ellipsoid(Vector3(cos(a) * 8.5, 0.6, 5.0 + sin(a) * 5.5), Vector3(1.6, 1.1, 1.3), C_ROCK, Basis.IDENTITY, 4, 7)


## Знак перевала: каменный постамент-обелиск с табличкой высоты (светлая плашка с тёмными
## штрихами), сложенный из блоков двух тонов.
static func _monument(kit: MeshKit) -> void:
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0)), Vector3(3.2, 1.0, 2.2), C_STONE_DARK)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.4, 0.0)), Vector3(2.6, 1.4, 1.8), C_STONE)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.8, 0.0)), Vector3(2.0, 1.6, 1.4), C_STONE_DARK)
	kit.add_tube(Vector3(0.0, 3.6, 0.0), Vector3(0.0, 6.2, 0.0), Vector2(0.75, 0.6), Vector2(0.25, 0.2), C_STONE, 4, true, Vector3(1.0, 0.0, 1.0))
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.9, 0.72)), Vector3(1.5, 0.9, 0.06), Color(0.86, 0.80, 0.62, 0.3))
	for i in 4:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(-0.45 + 0.3 * float(i), 2.9, 0.76)), Vector3(0.12, 0.45, 0.02), C_SIGN_INK)


## Гирлянда флажков 16 м вдоль X между двумя шестами: верёвка провисает, треугольные флажки
## пяти приглушённых цветов (не цвета зон HUD).
static func _flags(kit: MeshKit) -> void:
	var cols: Array[Color] = [Color(0.92, 0.90, 0.84, 0.0), Color(0.74, 0.34, 0.26, 0.0), Color(0.36, 0.48, 0.64, 0.0),
		Color(0.86, 0.74, 0.40, 0.0), Color(0.40, 0.56, 0.42, 0.0)]
	for x in [-8.0, 8.0]:
		kit.add_tube(Vector3(x, -0.3, 0.0), Vector3(x, 5.2, 0.0), Vector2(0.07, 0.07), Vector2(0.05, 0.05), C_WOOD_DARK, 5)
	var n: int = 16
	var prev := Vector3(-8.0, 5.0, 0.0)
	for i in n:
		var t: float = float(i + 1) / float(n)
		var x: float = -8.0 + 16.0 * t
		var y: float = 5.0 - 1.4 * (1.0 - pow(2.0 * t - 1.0, 2.0))
		var p := Vector3(x, y, 0.0)
		kit.add_tube(prev, p, Vector2(0.02, 0.02), Vector2(0.02, 0.02), C_CABLE, 3, false)
		var m: Vector3 = (prev + p) * 0.5
		var col: Color = cols[i % cols.size()]
		kit.add_triangle(m + Vector3(-0.35, 0.0, 0.0), m + Vector3(0.35, 0.0, 0.0), m + Vector3(0.0, -0.75, 0.0), Vector3.BACK, col)
		kit.add_triangle(m + Vector3(-0.35, 0.0, -0.01), m + Vector3(0.35, 0.0, -0.01), m + Vector3(0.0, -0.75, -0.01), Vector3.FORWARD, col)
		prev = p


## Шале: каменный цоколь, деревянный верх с балконом, широкая пологая крыша с большим
## свесом (вдоль X 12 м, глубина 9 м), окна и дверь на +Z.
static func _chalet(kit: MeshKit, wall: Color, roof: Color) -> void:
	var wood := Color(0.52, 0.36, 0.24, 1.0)
	var wood_light := Color(0.66, 0.50, 0.34, 1.0)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.2, 0.0)), Vector3(12.0, 3.4, 9.0), wall.lerp(C_STONE, 0.5))
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 4.4, 0.0)), Vector3(12.0, 3.0, 9.0), wood)
	kit.add_gable_roof(Transform3D(Basis.IDENTITY, Vector3(0.0, 5.9, 0.0)), Vector3(12.0, 2.6, 9.0), 1.6, roof, wood_light)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 3.3, 5.0)), Vector3(10.0, 0.2, 1.4), wood_light)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 3.95, 5.65)), Vector3(10.0, 1.0, 0.1), wood_light)
	for x in [-3.6, -1.2, 1.2, 3.6]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 4.6, 4.53)), Vector3(1.0, 1.1, 0.1), C_WINDOW)
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 1.5, 4.53)), Vector3(1.0, 1.0, 0.1), C_WINDOW)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(5.0, 1.1, 4.53)), Vector3(1.2, 2.2, 0.1), C_DOOR)


## Каменная хижина пастуха: низкие стены из камня, сланцевая крыша, труба, дверь на +Z.
static func _stone_hut(kit: MeshKit) -> void:
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.1, 0.0)), Vector3(7.0, 3.0, 5.0), C_STONE)
	for i in 5:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(-2.8 + 1.4 * float(i), 0.25 + 0.4 * float(i % 3), 2.53)),
			Vector3(1.1, 0.35, 0.08), C_STONE_DARK)
	kit.add_gable_roof(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.6, 0.0)), Vector3(7.0, 2.0, 5.0), 0.4, C_SLATE, C_STONE)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(2.2, 4.0, -0.8)), Vector3(0.8, 1.6, 0.8), C_STONE_DARK)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(-1.2, 0.95, 2.53)), Vector3(1.0, 1.9, 0.1), C_DOOR)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(1.4, 1.5, 2.53)), Vector3(0.8, 0.7, 0.1), C_WINDOW)


## Пролёт противолавинной галереи (`GALLERY_BAY_M` вдоль X, дорога — вдоль X, центр полотна —
## 0, +Z — сторона склона): глухая стена со стороны склона, плита перекрытия, со стороны
## долины — опора и ригель (галерея открыта к долине).
const GALLERY_BAY_M: float = 10.0
const GALLERY_HALF_W: float = 5.6
const GALLERY_H: float = 6.2


static func _gallery_bay(kit: MeshKit) -> void:
	var concrete := Color(0.74, 0.74, 0.72, 1.0)
	var under := Color(0.58, 0.58, 0.58, 1.0)
	var l: float = GALLERY_BAY_M + 0.1
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, GALLERY_H * 0.5 - 0.4, GALLERY_HALF_W + 0.4)), Vector3(l, GALLERY_H + 0.8, 0.8), concrete)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, GALLERY_H + 0.4, 0.6)), Vector3(l, 0.8, GALLERY_HALF_W * 2.0 + 2.4), concrete)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, GALLERY_H - 0.05, 0.6)), Vector3(l - 0.2, 0.1, GALLERY_HALF_W * 2.0 + 1.2), under)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, GALLERY_H - 0.35, -GALLERY_HALF_W - 0.2)), Vector3(l, 0.7, 0.8), concrete)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, (GALLERY_H - 0.7) * 0.5 - 0.3, -GALLERY_HALF_W - 0.2)), Vector3(0.8, GALLERY_H - 0.1, 0.8), concrete)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.35, -GALLERY_HALF_W - 0.2)), Vector3(l, 0.7, 0.5), under)


## Опора канатной дороги: решётчатая пирамидальная мачта (стойки и раскосы) с траверсой и
## роликами; верх — точка подвеса троса (`CABLE_TOWER_TOP`), трос вдоль X.
const CABLE_TOWER_TOP: float = 22.0


static func _cable_tower(kit: MeshKit) -> void:
	var steel := Color(0.50, 0.53, 0.57, 0.6)
	var h: float = CABLE_TOWER_TOP - 0.8
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			kit.add_tube(Vector3(sx * 1.8, -0.5, sz * 1.8), Vector3(sx * 0.6, h, sz * 0.6), Vector2(0.14, 0.14), Vector2(0.1, 0.1), steel, 4)
	for i in 4:
		var y0: float = h * float(i) / 4.0
		var y1: float = h * float(i + 1) / 4.0
		var r0: float = lerpf(1.8, 0.6, y0 / h)
		var r1: float = lerpf(1.8, 0.6, y1 / h)
		kit.add_tube(Vector3(-r0, y0, r0), Vector3(r1, y1, r1), Vector2(0.06, 0.06), Vector2(0.06, 0.06), steel, 3, false)
		kit.add_tube(Vector3(r0, y0, -r0), Vector3(-r1, y1, -r1), Vector2(0.06, 0.06), Vector2(0.06, 0.06), steel, 3, false)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, h + 0.3, 0.0)), Vector3(1.0, 0.6, 4.4), steel)
	for z in [-1.6, 1.6]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, h + 0.75, z)), Vector3(2.4, 0.3, 0.3), C_CABLE)


## Станция канатной дороги: бетонный корпус, плоская кровля, колесо троса сверху.
static func _cable_station(kit: MeshKit, roof: Color) -> void:
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.6, 0.0)), Vector3(10.0, 6.2, 8.0), C_CONCRETE)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 5.9, 0.0)), Vector3(12.0, 0.6, 9.4), roof)
	kit.add_tube(Vector3(0.0, 6.2, 0.0), Vector3(0.0, 7.4, 0.0), Vector2(2.4, 2.4), Vector2(2.4, 2.4), C_SLATE, 14)
	for x in [-3.0, 0.0, 3.0]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 3.4, 4.03)), Vector3(1.8, 1.4, 0.1), C_WINDOW)


## Кабинка канатной дороги: начало — точка на тросе; подвес и кабина ниже на 1.9–4.2 м;
## трос — вдоль X.
static func _cabin(kit: MeshKit, roof: Color) -> void:
	kit.add_tube(Vector3(0.0, 0.0, 0.0), Vector3(0.0, -1.9, 0.0), Vector2(0.06, 0.06), Vector2(0.06, 0.06), C_CABLE, 4)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.0)), Vector3(0.7, 0.3, 0.3), C_CABLE)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, -3.1, 0.0)), Vector3(2.1, 2.2, 1.7), Color(roof, 1.0))
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, -1.9, 0.0)), Vector3(2.3, 0.25, 1.9), C_WHITE)
	for z in [-0.86, 0.86]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, -2.75, z)), Vector3(1.7, 0.8, 0.06), C_WINDOW)


## Корова: белое тело с тёмными пятнами, голова, рога, ноги; смотрит вдоль +X; масть — цвет экземпляра.
static func _cow(kit: MeshKit) -> void:
	var hide := Color(0.94, 0.92, 0.88, 1.0)
	var patch := Color(0.30, 0.24, 0.20, 0.0)
	kit.add_ellipsoid(Vector3(0.0, 1.25, 0.0), Vector3(1.15, 0.55, 0.5), hide, Basis.IDENTITY, 6, 12)
	kit.add_ellipsoid(Vector3(-0.3, 1.45, 0.38), Vector3(0.45, 0.3, 0.16), patch, Basis.IDENTITY, 4, 8)
	kit.add_ellipsoid(Vector3(0.4, 1.2, -0.4), Vector3(0.38, 0.28, 0.14), patch, Basis.IDENTITY, 4, 8)
	kit.add_ellipsoid(Vector3(-0.7, 1.5, -0.3), Vector3(0.3, 0.25, 0.25), patch, Basis.IDENTITY, 4, 8)
	kit.add_ellipsoid(Vector3(1.35, 1.35, 0.0), Vector3(0.42, 0.3, 0.28), hide, Basis(Vector3.BACK, -0.35), 5, 9)
	kit.add_ellipsoid(Vector3(1.66, 1.2, 0.0), Vector3(0.18, 0.16, 0.2), Color(0.86, 0.66, 0.60, 0.5), Basis.IDENTITY, 4, 7)
	for zs in [-1.0, 1.0]:
		kit.add_tube(Vector3(1.25, 1.6, zs * 0.18), Vector3(1.3, 1.85, zs * 0.38), Vector2(0.05, 0.05), Vector2(0.03, 0.03), Color(0.90, 0.86, 0.74, 0.4), 4)
	for x in [-0.75, 0.75]:
		for z in [-0.28, 0.28]:
			kit.add_tube(Vector3(x, 0.95, z), Vector3(x, 0.0, z), Vector2(0.11, 0.11), Vector2(0.08, 0.08), hide, 5)
	kit.add_tube(Vector3(-1.1, 1.4, 0.0), Vector3(-1.25, 0.7, 0.0), Vector2(0.04, 0.04), Vector2(0.04, 0.04), patch, 4)


## Лесопилка: длинный навес на столбах (вдоль X 18 м), дощатые стены сзади и с торцов,
## станок и пила; открыт к +Z.
static func _sawmill_shed(kit: MeshKit, roof: Color) -> void:
	var wood := Color(0.55, 0.40, 0.28, 1.0)
	var plank := Color(0.66, 0.50, 0.34, 1.0)
	for x in [-8.5, -2.8, 2.8, 8.5]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 1.9, 3.2)), Vector3(0.35, 4.3, 0.35), wood)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.1, -3.4)), Vector3(18.0, 4.6, 0.3), plank)
	for sx in [-1.0, 1.0]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(sx * 9.0, 2.1, -0.1)), Vector3(0.3, 4.6, 6.6), plank)
	kit.add_gable_roof(Transform3D(Basis.IDENTITY, Vector3(0.0, 4.3, 0.0)), Vector3(18.0, 1.6, 7.0), 0.7, roof, plank)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(-2.0, 0.6, 0.0)), Vector3(8.0, 1.0, 1.2), C_SLATE)
	kit.add_tube(Vector3(1.0, 1.1, 0.0), Vector3(1.0, 2.8, 0.0), Vector2(0.5, 0.5), Vector2(0.5, 0.5), C_CONCRETE_DARK, 10)


## Штабель брёвен: 3 + 2 + 1 бревна 6 м вдоль X, светлые торцы.
static func _log_pile(kit: MeshKit) -> void:
	var bark := Color(0.46, 0.34, 0.24, 1.0)
	var cut := Color(0.86, 0.74, 0.52, 1.0)
	var r: float = 0.36
	var rows: Array[int] = [3, 2, 1]
	for row in rows.size():
		var n: int = rows[row]
		for i in n:
			var z: float = (float(i) - float(n - 1) * 0.5) * r * 2.05
			var y: float = r + float(row) * r * 1.75
			kit.add_tube(Vector3(-3.0, y, z), Vector3(3.0, y, z), Vector2(r, r), Vector2(r, r), bark, 8, false, Vector3.UP)
			for x in [-3.0, 3.0]:
				kit.add_tube(Vector3(x, y, z), Vector3(x + signf(x) * 0.03, y, z), Vector2(r * 0.97, r * 0.97), Vector2(r * 0.97, r * 0.97),
					cut, 8, true, Vector3.UP)


## Водяное колесо (ось — X): два обода, спицы, лопасти, вал.
static func _water_wheel(kit: MeshKit) -> void:
	var wood := Color(0.48, 0.35, 0.24, 1.0)
	var r: float = 2.6
	for x in [-0.6, 0.6]:
		kit.add_tube(Vector3(x - 0.08, 0.0, 0.0), Vector3(x + 0.08, 0.0, 0.0), Vector2(r + 0.15, r + 0.15), Vector2(r + 0.15, r + 0.15),
			wood, 18, false, Vector3.UP)
	for i in 10:
		var a: float = TAU * float(i) / 10.0
		var d := Vector3(0.0, cos(a), sin(a))
		kit.add_tube(Vector3.ZERO, d * r, Vector2(0.07, 0.07), Vector2(0.07, 0.07), wood, 4, false)
		kit.add_box(Transform3D(Basis(Vector3.RIGHT, -a), d * (r + 0.1)), Vector3(1.4, 0.08, 0.7), wood)
	kit.add_tube(Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector2(0.18, 0.18), Vector2(0.18, 0.18), C_SLATE, 6)


## Палатка-«домик» 2.4 м вдоль X: два ската, торцы и тёмный вход; цвет ткани — цвет экземпляра.
static func _tent(kit: MeshKit) -> void:
	var cloth := Color(1.0, 1.0, 1.0, 0.6)
	var hw: float = 1.1
	var h: float = 1.35
	var l: float = 1.2
	for sgn in [-1.0, 1.0]:
		var n := Vector3(0.0, hw, sgn * h).normalized()
		kit.add_quad(Vector3(-l, -0.05, sgn * hw), Vector3(l, -0.05, sgn * hw), Vector3(l, h, 0.0), Vector3(-l, h, 0.0), n, cloth)
	for sgn in [-1.0, 1.0]:
		kit.add_triangle(Vector3(sgn * l, -0.05, -hw), Vector3(sgn * l, -0.05, hw), Vector3(sgn * l, h, 0.0), Vector3(sgn, 0.0, 0.0),
			cloth.darkened(0.12) if sgn > 0.0 else cloth)
	kit.add_triangle(Vector3(l + 0.02, 0.0, -0.35), Vector3(l + 0.02, 0.0, 0.35), Vector3(l + 0.02, 0.8, 0.0), Vector3.RIGHT, Color(0.2, 0.18, 0.18, 0.0))


## Кострище: кольцо камней и сложенные шалашом поленья.
static func _fire_ring(kit: MeshKit) -> void:
	for i in 9:
		var a: float = TAU * float(i) / 9.0
		kit.add_ellipsoid(Vector3(cos(a) * 0.9, 0.12, sin(a) * 0.9), Vector3(0.25, 0.18, 0.22), C_STONE, Basis.IDENTITY, 3, 6)
	for i in 4:
		var a: float = TAU * float(i) / 4.0
		kit.add_tube(Vector3(cos(a) * 0.55, 0.05, sin(a) * 0.55), Vector3(0.0, 0.7, 0.0), Vector2(0.06, 0.06), Vector2(0.05, 0.05), C_WOOD_DARK, 4)


## Крест на вершине скалы (деревянный, 6 м).
static func _summit_cross(kit: MeshKit, base: Vector3 = Vector3.ZERO) -> void:
	var wood := Color(0.36, 0.26, 0.20, 1.0)
	kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(0.0, 2.8, 0.0)), Vector3(0.35, 6.4, 0.35), wood)
	kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(0.0, 4.4, 0.0)), Vector3(2.8, 0.32, 0.32), wood)


## Скальный останец с крестом (вид на змейку): груда граней-глыб двух тонов ~26 м в
## поперечнике и ~20 м высотой, наверху — крест. Начало — у подножия.
static func _crag(kit: MeshKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	var blocks: Array[Vector4] = [
		Vector4(0.0, 4.0, 0.0, 11.0), Vector4(-8.0, 2.0, 4.0, 7.0), Vector4(7.5, 2.5, -3.0, 7.5),
		Vector4(1.5, 11.0, -1.0, 7.0), Vector4(-2.0, 16.5, 0.5, 4.2), Vector4(5.0, 7.0, 6.0, 5.0),
	]
	for b in blocks:
		_rock(kit, Vector3(b.x, b.y, b.z), Vector3(b.w, b.w * 0.85, b.w * 0.95), rng)
	_summit_cross(kit, Vector3(-2.0, 19.5, 0.5))


## Глыба: неровная низкополигональная «сфера» с гранями (плоские нормали), светлый верх и
## тёмные бока.
static func _rock(kit: MeshKit, center: Vector3, radii: Vector3, rng: RandomNumberGenerator) -> void:
	var rings: int = 4
	var segs: int = 7
	var grid: Array[PackedVector3Array] = []
	for r in rings + 1:
		var phi: float = PI * float(r) / float(rings)
		var row := PackedVector3Array()
		for k in segs:
			var th: float = TAU * (float(k) + 0.5 * float(r % 2)) / float(segs)
			var j: float = rng.randf_range(0.78, 1.18) if r > 0 and r < rings else 1.0
			row.append(center + Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th)) * radii * j)
		grid.append(row)
	for r in rings:
		for k in segs:
			var a: Vector3 = grid[r][k]
			var b: Vector3 = grid[r][(k + 1) % segs]
			var c: Vector3 = grid[r + 1][(k + 1) % segs]
			var d: Vector3 = grid[r + 1][k]
			for tri in [[a, c, b], [a, d, c]]:
				var p0: Vector3 = tri[0]
				var p1: Vector3 = tri[1]
				var p2: Vector3 = tri[2]
				var n: Vector3 = (p1 - p0).cross(p2 - p0)
				if n.length_squared() < 1e-10:
					continue
				n = n.normalized()
				if n.dot((p0 + p1 + p2) / 3.0 - center) < 0.0:
					n = -n
				kit.add_triangle(p0, p1, p2, n, C_ROCK if n.y > 0.35 else C_ROCK_DARK)


# ---------------------------------------------------------------------------
# Приморье (T-088, `tracks.md` п. 4.4, 4.5, 6)
# ---------------------------------------------------------------------------

const C_SHUTTER := Color(0.30, 0.45, 0.62, 0.6)
const C_LIGHTHOUSE_RED := Color(0.80, 0.20, 0.18, 1.0)
const C_LIGHTHOUSE_WHITE := Color(0.95, 0.95, 0.93, 1.0)
const C_LAMP := Color(1.0, 0.90, 0.62, 0.0)
const C_SAND_WOOD := Color(0.70, 0.58, 0.42, 0.6)
## Фонарь маяка: высота центра фонаря над основанием башни (крепление `lighthouse_lamp`).
const LIGHTHOUSE_LAMP_Y: float = 24.9


## Лодка (~5 м вдоль X): корпус — сплюснутый эллипсоид, низ ниже нуля (на воде низ скрыт водой,
## на берегу — в песке), тёмная внутренность, полоса по борту, банки; начало — ватерлиния.
static func _boat(kit: MeshKit) -> void:
	var hull := Color(0.93, 0.92, 0.88, 1.0)
	var stripe := Color(0.30, 0.45, 0.62, 1.0)
	kit.add_ellipsoid(Vector3(0.0, 0.05, 0.0), Vector3(2.6, 0.62, 0.95), hull, Basis.IDENTITY, 6, 14, 1, 0.3, 0.62, stripe)
	kit.add_ellipsoid(Vector3(0.0, 0.62, 0.0), Vector3(2.2, 0.08, 0.72), Color(0.44, 0.33, 0.24, 0.0), Basis.IDENTITY, 3, 12)
	for x in [-0.8, 0.5]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 0.66, 0.0)), Vector3(0.28, 0.06, 1.5), C_SAND_WOOD)


## Пляжный зонтик: шест 2.5 м и купол из восьми долей — цвет `accent` через одну с белой.
static func _umbrella(kit: MeshKit, accent: Color) -> void:
	kit.add_tube(Vector3(0.0, -0.3, 0.0), Vector3(0.0, 2.5, 0.0), Vector2(0.04, 0.04), Vector2(0.035, 0.035), Color(0.85, 0.85, 0.82, 0.0), 4)
	var white := Color(0.96, 0.95, 0.90, 1.0)
	var apex := Vector3(0.0, 2.75, 0.0)
	var n: int = 8
	for i in n:
		var a0: float = TAU * float(i) / float(n)
		var a1: float = TAU * float(i + 1) / float(n)
		var p0 := Vector3(cos(a0) * 1.25, 2.2, sin(a0) * 1.25)
		var p1 := Vector3(cos(a1) * 1.25, 2.2, sin(a1) * 1.25)
		var col: Color = accent if i % 2 == 0 else white
		var nrm: Vector3 = (p1 - apex).cross(p0 - apex).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		kit.add_triangle(apex, p0, p1, nrm, col)
		kit.add_triangle(apex, p1, p0, -nrm, Color(col.darkened(0.25), 0.0))


## Шезлонг: рама и полотно, спинка поднята (вдоль X, изголовье — +X).
static func _lounger(kit: MeshKit) -> void:
	var cloth := Color(0.92, 0.88, 0.78, 0.4)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(-0.25, 0.3, 0.0)), Vector3(1.4, 0.06, 0.6), cloth)
	kit.add_box(Transform3D(Basis(Vector3.BACK, 0.7), Vector3(0.65, 0.55, 0.0)), Vector3(0.65, 0.06, 0.6), cloth)
	for x in [-0.85, 0.35]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 0.14, 0.0)), Vector3(0.06, 0.3, 0.6), C_SAND_WOOD)


## Белый средиземноморский дом: стены, плоская крыша (у большого — надстройка с террасой), у
## малого — черепичная пирамида; окна и дверь с синими ставнями на +Z.
static func _white_house(kit: MeshKit, size: Vector3, roof: Color, terrace: bool) -> void:
	var wall := Color(0.95, 0.95, 0.93, 1.0)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, size.y * 0.5 - 0.4, 0.0)), Vector3(size.x, size.y + 0.8, size.z), wall)
	if terrace:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(size.x * 0.22, size.y + 0.25, 0.0)), Vector3(size.x * 0.56 + 0.2, 0.5, size.z + 0.2), wall)
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(-size.x * 0.28, size.y + 1.4, -size.z * 0.12)),
			Vector3(size.x * 0.44, 2.8, size.z * 0.7), wall)
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(-size.x * 0.28, size.y + 2.9, -size.z * 0.12)),
			Vector3(size.x * 0.44 + 0.3, 0.2, size.z * 0.7 + 0.3), Color(0.86, 0.86, 0.84, 1.0))
	else:
		kit.add_pyramid(Vector3(0.0, size.y, 0.0), Vector2(size.x * 0.5 + 0.3, size.z * 0.5 + 0.3), 1.6, Color(roof, 1.0))
	var floors: int = 2 if size.y > 5.0 else 1
	for f in floors:
		var y: float = 1.3 + 2.9 * float(f) + (0.4 if floors == 1 else 0.0)
		for i in 2:
			var x: float = (float(i) - 0.5) * size.x * 0.5 + size.x * 0.1
			if f == 0 and i == 0:
				kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 1.05, size.z * 0.5 + 0.04)), Vector3(1.0, 2.1, 0.1), C_SHUTTER)
				continue
			kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, y, size.z * 0.5 + 0.04)), Vector3(0.8, 1.0, 0.1), C_WINDOW)
			for sx in [-1.0, 1.0]:
				kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x + sx * 0.62, y, size.z * 0.5 + 0.05)), Vector3(0.42, 1.05, 0.08), C_SHUTTER)


## Кипарис: узкое высокое веретено тёмной зелени на коротком стволе (~9 м).
static func _cypress(kit: MeshKit) -> void:
	kit.add_tube(Vector3(0, -0.3, 0), Vector3(0, 1.2, 0), Vector2(0.16, 0.16), Vector2(0.12, 0.12), Color(0.40, 0.31, 0.24, 1.0), 6)
	var c := Color(0.22, 0.36, 0.22, 1.0)
	kit.add_ellipsoid(Vector3(0.0, 4.6, 0.0), Vector3(0.95, 4.2, 0.95), c, Basis.IDENTITY, 8, 9)
	kit.add_ellipsoid(Vector3(0.1, 7.2, 0.05), Vector3(0.6, 2.0, 0.6), c.lightened(0.06), Basis.IDENTITY, 6, 8)


## Парусник (~8 м вдоль X): белый корпус, рубка, мачта 10 м, грот и стаксель (двусторонние);
## начало — ватерлиния.
static func _sailboat(kit: MeshKit) -> void:
	kit.add_ellipsoid(Vector3(0.0, 0.1, 0.0), Vector3(4.2, 0.9, 1.3), Color(0.94, 0.94, 0.92, 1.0), Basis.IDENTITY, 6, 14, 1, 0.45, 0.75,
		Color(0.30, 0.42, 0.58, 1.0))
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(-0.6, 1.05, 0.0)), Vector3(2.2, 0.6, 1.4), Color(0.88, 0.86, 0.80, 1.0))
	kit.add_tube(Vector3(0.6, 0.8, 0.0), Vector3(0.6, 11.0, 0.0), Vector2(0.08, 0.08), Vector2(0.06, 0.06), Color(0.70, 0.70, 0.72, 0.6), 5)
	var sail := Color(0.97, 0.96, 0.92, 0.0)
	var main: Array[Vector3] = [Vector3(0.45, 1.6, 0.0), Vector3(0.45, 10.6, 0.0), Vector3(-3.4, 1.7, 0.0)]
	var jib: Array[Vector3] = [Vector3(0.75, 9.8, 0.0), Vector3(0.75, 1.7, 0.0), Vector3(3.9, 1.3, 0.0)]
	for tri: Array[Vector3] in [main, jib]:
		kit.add_triangle(tri[0], tri[1], tri[2], Vector3.BACK, sail)
		var back := Vector3(0.0, 0.0, -0.02)
		kit.add_triangle(tri[0] + back, tri[2] + back, tri[1] + back, Vector3.FORWARD, Color(0.86, 0.86, 0.84, 0.0))


## Куртина камыша: веер высоких стеблей (до 2.4 м) с бурыми початками, без контура.
static func _reeds(kit: MeshKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3391
	for i in 13:
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(0.0, 0.9)
		var base := Vector3(cos(a) * r, -0.2, sin(a) * r)
		var lean := Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.35, 0.35))
		var top: Vector3 = base + Vector3(0.0, rng.randf_range(1.6, 2.4), 0.0) + lean
		kit.add_tube(base, top, Vector2(0.035, 0.035), Vector2(0.015, 0.015), Color(0.46, 0.56, 0.30, 0.0), 3, false)
		if i % 2 == 0:
			var dir: Vector3 = (top - base).normalized()
			kit.add_tube(top - dir * 0.45, top - dir * 0.05, Vector2(0.07, 0.07), Vector2(0.06, 0.06), Color(0.44, 0.31, 0.20, 0.0), 5)
	kit.add_ellipsoid(Vector3(0.0, 0.35, 0.0), Vector3(1.1, 0.55, 1.1), Color(0.42, 0.52, 0.28, 0.0), Basis.IDENTITY, 4, 8)


## Олива: короткий узловатый ствол с развилкой, серебристо-зелёная округлая крона (~4.5 м).
static func _olive(kit: MeshKit) -> void:
	var bark := Color(0.44, 0.38, 0.30, 1.0)
	kit.add_tube(Vector3(0, -0.3, 0), Vector3(0.3, 1.5, 0.1), Vector2(0.28, 0.28), Vector2(0.2, 0.2), bark, 6)
	kit.add_tube(Vector3(0.3, 1.3, 0.1), Vector3(-0.6, 2.6, 0.3), Vector2(0.14, 0.14), Vector2(0.1, 0.1), bark, 5)
	kit.add_tube(Vector3(0.3, 1.3, 0.1), Vector3(1.1, 2.5, -0.3), Vector2(0.14, 0.14), Vector2(0.1, 0.1), bark, 5)
	var leaf := Color(0.54, 0.60, 0.42, 1.0)
	kit.add_ellipsoid(Vector3(0.2, 3.1, 0.0), Vector3(2.1, 1.3, 1.9), leaf.darkened(0.08), Basis.IDENTITY, 6, 10)
	kit.add_ellipsoid(Vector3(-0.8, 3.4, 0.4), Vector3(1.2, 0.9, 1.1), leaf, Basis.IDENTITY, 5, 9)
	kit.add_ellipsoid(Vector3(1.1, 3.5, -0.3), Vector3(1.1, 0.85, 1.1), leaf, Basis.IDENTITY, 5, 9)


## Маяк: башня 23 м, сужается кверху, белая с красными полосами (`tracks.md` п. 6), галерея с
## ограждением, остеклённый фонарь (тёмные стойки) и красный купол; дверь и окна на +Z.
## Свет — отдельный анимированный меш `lighthouse_lamp` на высоте `LIGHTHOUSE_LAMP_Y`.
static func _lighthouse(kit: MeshKit) -> void:
	var h: float = 23.0
	var bands: int = 6
	var dark := Color(0.25, 0.25, 0.28, 0.6)
	for i in bands:
		var y0: float = h * float(i) / float(bands)
		var y1: float = h * float(i + 1) / float(bands)
		var r0: float = lerpf(3.0, 2.0, y0 / h)
		var r1: float = lerpf(3.0, 2.0, y1 / h)
		kit.add_tube(Vector3(0.0, y0 - (0.8 if i == 0 else 0.0), 0.0), Vector3(0.0, y1, 0.0), Vector2(r0, r0), Vector2(r1, r1),
			C_LIGHTHOUSE_RED if i % 2 == 1 else C_LIGHTHOUSE_WHITE, 14, false)
	kit.add_tube(Vector3(0.0, h, 0.0), Vector3(0.0, h + 0.4, 0.0), Vector2(2.9, 2.9), Vector2(2.9, 2.9), dark, 16)
	for i in 12:
		var a: float = TAU * float(i) / 12.0
		kit.add_box(Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * 2.75, h + 0.9, sin(a) * 2.75)), Vector3(0.08, 1.0, 0.08), dark)
	kit.add_tube(Vector3(0.0, h + 1.35, 0.0), Vector3(0.0, h + 1.45, 0.0), Vector2(2.8, 2.8), Vector2(2.8, 2.8), dark, 16, false)
	kit.add_tube(Vector3(0.0, h + 0.4, 0.0), Vector3(0.0, h + 1.0, 0.0), Vector2(1.7, 1.7), Vector2(1.7, 1.7), C_LIGHTHOUSE_WHITE, 12)
	kit.add_tube(Vector3(0.0, h + 3.1, 0.0), Vector3(0.0, h + 3.3, 0.0), Vector2(1.75, 1.75), Vector2(1.75, 1.75), C_LIGHTHOUSE_WHITE, 12)
	for i in 6:
		var a: float = TAU * float(i) / 6.0
		kit.add_box(Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * 1.55, h + 2.05, sin(a) * 1.55)), Vector3(0.12, 2.1, 0.12),
			Color(0.22, 0.22, 0.25, 0.6))
	kit.add_cone(Vector3(0.0, h + 3.3, 0.0), 1.6, 1.9, C_LIGHTHOUSE_RED, 12)
	kit.add_tube(Vector3(0.0, h + 4.9, 0.0), Vector3(0.0, h + 5.8, 0.0), Vector2(0.06, 0.06), Vector2(0.04, 0.04), Color(0.2, 0.2, 0.22, 0.0), 4)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.1, 3.0)), Vector3(1.1, 2.2, 0.2), C_DOOR)
	for y in [8.0, 15.0]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, y, lerpf(3.0, 2.0, y / h) + 0.05)), Vector3(0.6, 0.9, 0.1), C_WINDOW)


## Свет маяка (анимированный; ось вращения — локальная Z, у экземпляра — вертикаль): линза и
## два луча-клина по ±X, тёплый цвет без контура. Светится сам (эмиссия `prop_anim` по данным
## экземпляра), источника света нет — бюджет света не растёт.
static func _lighthouse_lamp(kit: MeshKit) -> void:
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3.ZERO), Vector3(1.1, 1.0, 1.4), C_LAMP)
	for sgn in [-1.0, 1.0]:
		var a := Vector3(sgn * 0.6, 0.0, 0.0)
		var b := Vector3(sgn * 15.0, 0.0, -0.3)
		kit.add_tube(a, b, Vector2(0.3, 0.3), Vector2(1.5, 1.0), Color(1.0, 0.95, 0.80, 0.0), 6, false, Vector3.BACK)


## Скала-кекур в море: столб из граней-глыб двух тонов ~10 × 24 м; начало — на дне, низ под водой.
static func _sea_stack(kit: MeshKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6603
	var blocks: Array[Vector4] = [
		Vector4(0.0, 0.0, 0.0, 6.5), Vector4(1.0, 7.0, 0.5, 5.5), Vector4(-0.5, 13.0, -0.3, 4.6), Vector4(0.6, 18.5, 0.2, 3.6),
		Vector4(-3.5, 3.0, 2.5, 3.5), Vector4(3.0, 1.5, -2.0, 3.8),
	]
	for b in blocks:
		_rock(kit, Vector3(b.x, b.y, b.z), Vector3(b.w, b.w * 1.15, b.w * 0.95), rng)


## Брызги у подножия скалы: плоское пятно пены на воде и белые клубы вокруг (без контура);
## анимация — медленное покачивание (`prop_anim`). Начало — уровень воды.
static func _spray(kit: MeshKit) -> void:
	var foam := Color(0.95, 0.97, 0.98, 0.0)
	var shade := Color(0.80, 0.88, 0.93, 0.0)
	for i in 7:
		var a: float = TAU * float(i) / 7.0 + 0.3
		var r: float = 6.0 + 1.5 * float(i % 3)
		kit.add_ellipsoid(Vector3(cos(a) * r, 0.4 + 0.5 * float(i % 2), sin(a) * r), Vector3(2.2, 1.1 + 0.6 * float(i % 3), 1.8),
			foam if i % 2 == 0 else shade, Basis(Vector3.UP, a), 4, 8)
	kit.add_ellipsoid(Vector3(0.0, 0.05, 0.0), Vector3(9.0, 0.15, 8.0), foam, Basis.IDENTITY, 2, 16)


## Фонарь набережной: тёмный столб 4.6 м с кронштейном и светлым плафоном (без источника света).
static func _street_lamp(kit: MeshKit) -> void:
	var iron := Color(0.20, 0.26, 0.26, 0.6)
	kit.add_tube(Vector3(0.0, -0.3, 0.0), Vector3(0.0, 4.4, 0.0), Vector2(0.09, 0.09), Vector2(0.06, 0.06), iron, 6)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.25, 0.0)), Vector3(0.3, 0.5, 0.3), iron)
	kit.add_tube(Vector3(0.0, 4.3, 0.0), Vector3(0.0, 4.4, 0.7), Vector2(0.04, 0.04), Vector2(0.04, 0.04), iron, 4, false)
	kit.add_ellipsoid(Vector3(0.0, 4.15, 0.7), Vector3(0.26, 0.34, 0.26), Color(0.98, 0.94, 0.80, 0.4), Basis.IDENTITY, 5, 8)
	kit.add_cone(Vector3(0.0, 4.4, 0.7), 0.25, 0.32, iron, 8)


## Фонарь моста (T-090, `tracks.md` п. 4.4): мачта светлой стали 7.5 м на тумбе, консоль к
## дороге (+Z) с плоским светильником. Выше перил и гонщика — с подъезда ряд фонарей читает мост.
static func _bridge_lamp(kit: MeshKit) -> void:
	var steel := Color(0.78, 0.82, 0.86, 0.5)
	var steel_dark := Color(0.58, 0.62, 0.67, 0.5)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0)), Vector3(0.34, 0.6, 0.34), steel_dark)
	kit.add_tube(Vector3(0.0, 0.5, 0.0), Vector3(0.0, 7.5, 0.0), Vector2(0.1, 0.1), Vector2(0.065, 0.065), steel, 6)
	kit.add_tube(Vector3(0.0, 7.2, 0.0), Vector3(0.0, 7.55, 1.5), Vector2(0.05, 0.05), Vector2(0.045, 0.045), steel, 5, false)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 7.5, 1.55)), Vector3(0.36, 0.14, 0.8), steel_dark)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 7.41, 1.55)), Vector3(0.28, 0.05, 0.66), Color(0.99, 0.95, 0.80, 0.0))


## Балюстрада набережной: звено 10 м вдоль X — светлые перила на столбиках, тумбы на концах.
static func _balustrade(kit: MeshKit) -> void:
	var stone := Color(0.90, 0.88, 0.82, 0.4)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.1, 0.0)), Vector3(10.0, 0.4, 0.4), stone)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.95, 0.0)), Vector3(10.1, 0.14, 0.34), stone)
	for i in 12:
		kit.add_tube(Vector3(-4.6 + float(i) * 0.84, 0.3, 0.0), Vector3(-4.6 + float(i) * 0.84, 0.88, 0.0), Vector2(0.08, 0.08),
			Vector2(0.06, 0.06), stone, 5, false)
	for x in [-5.0, 5.0]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 0.55, 0.0)), Vector3(0.45, 1.2, 0.45), stone)


## Вышка спасателя: будка на четырёх ногах (площадка 3 м), навес, лестница к +Z, флаг.
static func _lifeguard_tower(kit: MeshKit) -> void:
	var wood := Color(0.86, 0.84, 0.78, 0.6)
	var red := Color(0.78, 0.28, 0.24, 1.0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			kit.add_tube(Vector3(sx * 1.3, -0.3, sz * 1.3), Vector3(sx * 1.0, 3.0, sz * 1.0), Vector2(0.09, 0.09), Vector2(0.08, 0.08), wood, 5)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 3.05, 0.0)), Vector3(2.6, 0.15, 2.6), wood)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 3.7, -0.4)), Vector3(2.2, 1.2, 1.4), red)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 3.75, 0.31)), Vector3(1.6, 0.5, 0.06), C_WINDOW)
	kit.add_gable_roof(Transform3D(Basis.IDENTITY, Vector3(0.0, 4.35, -0.1)), Vector3(2.4, 0.6, 2.4), 0.3, C_LIGHTHOUSE_WHITE, red)
	for x in [-0.35, 0.35]:
		kit.add_tube(Vector3(x, -0.2, 2.6), Vector3(x, 3.1, 1.3), Vector2(0.05, 0.05), Vector2(0.05, 0.05), wood, 4)
	for k in 5:
		var t: float = (float(k) + 0.5) / 5.0
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, lerpf(-0.2, 3.1, t), lerpf(2.6, 1.3, t))), Vector3(0.75, 0.06, 0.12), wood)
	kit.add_tube(Vector3(1.2, 3.1, -1.2), Vector3(1.2, 7.2, -1.2), Vector2(0.04, 0.04), Vector2(0.03, 0.03), Color(0.3, 0.3, 0.32, 0.0), 4)
	var flag := Color(red, 0.0)
	kit.add_quad(Vector3(1.2, 7.1, -1.2), Vector3(2.5, 7.1, -1.2), Vector3(2.5, 6.3, -1.2), Vector3(1.2, 6.3, -1.2), Vector3.BACK, flag)
	kit.add_quad(Vector3(1.2, 7.1, -1.21), Vector3(1.2, 6.3, -1.21), Vector3(2.5, 6.3, -1.21), Vector3(2.5, 7.1, -1.21), Vector3.FORWARD, flag)
