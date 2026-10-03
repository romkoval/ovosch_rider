class_name RouteCatalog
extends RefCounted
## Каталог трасс свободной езды (REQ-D3D-08 крит. 1–3, REQ-FRD-02 крит. 3,
## основа REQ-FRD-03; данные — `docs/game/tracks.md` п. 3–4).
##
## Ровно четыре трассы: `flat`, `hills`, `mountains` (петля через перевал — решение
## владельца, D3D-08 крит. 10), `seaside`. У каждой — ключи названия и типа
## (`track.<id>.name` / `track.<id>.kind`, строки заводит T-060), опорные точки
## профиля (м), мосты, уровень воды, ориентиры, параметры план-схемы `layout` и `seed`
## для генератора дороги (T-070), цвет настроения карточки и идентификатор набора
## окружения (строка; маппинг на `.tres` — `src/scene3d/route_world.gd`, T-070).
##
## Профили строятся один раз на процесс и кэшируются (`RouteProfile` неизменяем);
## описания `RouteDef` создаются заново при каждом запросе, поэтому их правка
## вызывающим кодом не портит каталог.

const FLAT: String = "flat"
const HILLS: String = "hills"
const MOUNTAINS: String = "mountains"
const SEASIDE: String = "seaside"

## Порядок трасс в каталоге.
const IDS: Array[String] = [FLAT, HILLS, MOUNTAINS, SEASIDE]
## Трасса по умолчанию (REQ-FRD-02 крит. 3, вопрос Н-14): равнина.
const DEFAULT_ID: String = FLAT

## Кэш профилей: id → RouteProfile.
static var _profiles: Dictionary = {}


## Ориентир у дороги или на горизонте (`tracks.md` п. 4.5, REQ-D3D-08 крит. 12).
## Сторона и план нужны миру для расстановки (T-083, T-087, T-088).
class Landmark:
	extends RefCounted
	## Сторона по ходу движения: слева.
	const SIDE_LEFT: String = "left"
	## Справа.
	const SIDE_RIGHT: String = "right"
	## Над дорогой или дорога через него (мост, галерея, канатка).
	const SIDE_ROAD: String = "road"
	## По обе стороны дороги (лес).
	const SIDE_BOTH: String = "both"
	## Допустимые значения `side`.
	const SIDES: Array[String] = [SIDE_LEFT, SIDE_RIGHT, SIDE_ROAD, SIDE_BOTH]
	## План «у дороги»: до 60 м от полотна.
	const PLANE_NEAR: String = "near"
	## Средний план: 60–400 м.
	const PLANE_MID: String = "mid"
	## Дальний план: горизонт, небо.
	const PLANE_FAR: String = "far"
	## Допустимые значения `plane`.
	const PLANES: Array[String] = [PLANE_NEAR, PLANE_MID, PLANE_FAR]

	## Положение по s, м: точка, где ориентир ближе всего к дороге (у моста и галереи — въезд).
	var s_m: float = 0.0
	## Тип ориентира (snake_case, английский): по нему мир выбирает сцену или меш.
	var type: String = ""
	## Сторона по ходу движения — одно из `SIDES`.
	var side: String = SIDE_RIGHT
	## План (удаление от дороги) — одно из `PLANES`.
	var plane: String = PLANE_NEAR

	func _init(
		at_m: float = 0.0,
		landmark_type: String = "",
		landmark_side: String = SIDE_RIGHT,
		landmark_plane: String = PLANE_NEAR,
	) -> void:
		s_m = at_m
		type = landmark_type
		side = landmark_side
		plane = landmark_plane


## Описание одной трассы.
class RouteDef:
	extends RefCounted
	var id: String = ""
	## Ключ локализации названия: `track.<id>.name`.
	var name_key: String = ""
	## Ключ локализации подписи типа: `track.<id>.kind`.
	var kind_key: String = ""
	## Опорные точки профиля (x — s, м; y — h, м); первая на 0, последняя на L с той же высотой.
	var points: PackedVector2Array = PackedVector2Array()
	## Профиль по `points` (общий для всех описаний трассы, неизменяемый).
	var profile: RouteProfile = null
	## Диапазоны мостов по s, м: x — начало, y — конец.
	var bridges: Array[Vector2] = []
	## Уровень воды, м (NAN — воды у трассы нет).
	var water_level_m: float = NAN
	var landmarks: Array[Landmark] = []
	## Параметры план-схемы для генератора дороги (T-070), см. `tracks.md` п. 4.
	## Общие ключи: `shape` (String), `control_points` (int), `waviness` (float),
	## `min_radius_m` (float); остальные — по форме трассы (описаны в `_layout_*`).
	var layout: Dictionary = {}
	## Seed план-схемы и расстановки окружения.
	var seed: int = 0
	## Цвет полосы настроения на карточке (`ui.md` п. 8.4), sRGB.
	var mood_color: Color = Color.WHITE
	## Идентификатор набора окружения (`EnvironmentSet`); маппинг на `.tres` — T-070.
	var environment_set_id: String = ""

	func has_water() -> bool:
		return not is_nan(water_level_m)

	## Лежит ли s (по модулю длины круга) на мосту.
	func is_on_bridge(s_m: float) -> bool:
		if profile == null or not profile.is_valid():
			return false
		var s: float = fposmod(s_m, profile.length_m())
		for b in bridges:
			if s >= b.x and s <= b.y:
				return true
		return false


## Идентификаторы трасс в порядке каталога.
static func ids() -> Array[String]:
	return IDS.duplicate()


static func has_route(route_id: String) -> bool:
	return IDS.has(route_id)


## Описание трассы по id или null для неизвестного id.
static func get_route(route_id: String) -> RouteDef:
	match route_id:
		FLAT:
			return _flat()
		HILLS:
			return _hills()
		MOUNTAINS:
			return _mountains()
		SEASIDE:
			return _seaside()
	return null


## Все трассы в порядке каталога.
static func all() -> Array[RouteDef]:
	var out: Array[RouteDef] = []
	for route_id in IDS:
		out.append(get_route(route_id))
	return out


## Описание трассы по умолчанию (`DEFAULT_ID`).
static func default_route() -> RouteDef:
	return get_route(DEFAULT_ID)


## Id, пригодный для запуска: известный id как есть, иначе `DEFAULT_ID`
## (например, `last_route_id` из профиля после удаления трассы).
static func resolve_id(route_id: String) -> String:
	return route_id if has_route(route_id) else DEFAULT_ID


static func _make(route_id: String, points: PackedVector2Array) -> RouteDef:
	var r := RouteDef.new()
	r.id = route_id
	r.name_key = "track.%s.name" % route_id
	r.kind_key = "track.%s.kind" % route_id
	r.points = points
	r.environment_set_id = route_id
	if not _profiles.has(route_id):
		_profiles[route_id] = RouteProfile.from_points(points)
	r.profile = _profiles[route_id]
	return r


## Ориентиры из строк `[s_m, type, side, plane]` таблиц `tracks.md` п. 4.5.
static func _landmarks(items: Array) -> Array[Landmark]:
	var out: Array[Landmark] = []
	for item: Array in items:
		out.append(Landmark.new(float(item[0]), String(item[1]), String(item[2]), String(item[3])))
	return out


# --- Равнина: «Пшеничные поля» (tracks.md п. 4.1) ---
static func _flat() -> RouteDef:
	var r := _make(FLAT, PackedVector2Array([
		Vector2(0, 40), Vector2(1200, 42), Vector2(2400, 47), Vector2(3300, 45),
		Vector2(4500, 38), Vector2(5600, 36), Vector2(6600, 41), Vector2(7500, 48),
		Vector2(8400, 46), Vector2(9200, 42), Vector2(10000, 40),
	]))
	r.mood_color = Color(0.93, 0.80, 0.45)
	r.seed = 101
	# Неправильный четырёхугольник: длинные прямые 1.2–2 км (≈ 50 % длины), дуги R 250–600 м.
	r.layout = {
		"shape": "quad",
		"control_points": 11,
		"waviness": 0.15,
		"min_radius_m": 200.0,
		"arc_radius_m": Vector2(250.0, 600.0),
		"straight_length_m": Vector2(1200.0, 2000.0),
		"straight_share": 0.5,
	}
	r.landmarks = _landmarks([
		[800, "water_tower", Landmark.SIDE_RIGHT, Landmark.PLANE_NEAR],
		[1900, "wind_turbines_far", Landmark.SIDE_LEFT, Landmark.PLANE_FAR],
		[3000, "haystacks", Landmark.SIDE_LEFT, Landmark.PLANE_NEAR],
		[4200, "village", Landmark.SIDE_RIGHT, Landmark.PLANE_MID],
		[5400, "grain_elevator", Landmark.SIDE_LEFT, Landmark.PLANE_MID],
		[6400, "sunflower_field", Landmark.SIDE_RIGHT, Landmark.PLANE_NEAR],
		[7500, "creek_footbridge", Landmark.SIDE_ROAD, Landmark.PLANE_NEAR],
		[8600, "wind_turbines_near", Landmark.SIDE_RIGHT, Landmark.PLANE_MID],
		[9500, "farm_silo", Landmark.SIDE_LEFT, Landmark.PLANE_NEAR],
	])
	return r


# --- Холмы: «Зелёные холмы» (tracks.md п. 4.2) ---
static func _hills() -> RouteDef:
	var r := _make(HILLS, PackedVector2Array([
		Vector2(0, 120), Vector2(600, 122), Vector2(1500, 160), Vector2(2100, 158),
		Vector2(2800, 132), Vector2(3600, 128), Vector2(4900, 196), Vector2(5400, 200),
		Vector2(6400, 165), Vector2(7200, 158), Vector2(8000, 194), Vector2(8500, 191),
		Vector2(9500, 150), Vector2(10200, 146), Vector2(12200, 218), Vector2(12700, 214),
		Vector2(14000, 140), Vector2(15000, 120),
	]))
	r.mood_color = Color(0.45, 0.68, 0.35)
	r.seed = 7
	# Извилистая петля: повороты R 80–250 м, S-связки на спусках, прямые ≤ 600 м.
	r.layout = {
		"shape": "winding",
		"control_points": 17,
		"waviness": 0.3,
		"min_radius_m": 80.0,
		"arc_radius_m": Vector2(80.0, 250.0),
		"max_straight_m": 600.0,
	}
	r.landmarks = _landmarks([
		[500, "stone_bridge", Landmark.SIDE_ROAD, Landmark.PLANE_NEAR],
		[1500, "chapel", Landmark.SIDE_LEFT, Landmark.PLANE_NEAR],
		[2600, "sheep", Landmark.SIDE_RIGHT, Landmark.PLANE_NEAR],
		[3600, "farmstead", Landmark.SIDE_LEFT, Landmark.PLANE_MID],
		[4500, "hay_bales", Landmark.SIDE_RIGHT, Landmark.PLANE_NEAR],
		[5400, "lone_tree_bench", Landmark.SIDE_RIGHT, Landmark.PLANE_NEAR],
		[6800, "windmill", Landmark.SIDE_LEFT, Landmark.PLANE_MID],
		[8000, "lake_view", Landmark.SIDE_RIGHT, Landmark.PLANE_FAR],
		[8900, "horse_paddock", Landmark.SIDE_LEFT, Landmark.PLANE_NEAR],
		[9800, "village", Landmark.SIDE_RIGHT, Landmark.PLANE_MID],
		[11000, "castle_ruins", Landmark.SIDE_LEFT, Landmark.PLANE_FAR],
		[12200, "tv_tower", Landmark.SIDE_RIGHT, Landmark.PLANE_NEAR],
		[13400, "vineyard", Landmark.SIDE_LEFT, Landmark.PLANE_NEAR],
		[14400, "hot_air_balloon", Landmark.SIDE_RIGHT, Landmark.PLANE_FAR],
	])
	return r


# --- Горы: «Перевал», петля (tracks.md п. 4.3, D3D-08 крит. 10) ---
static func _mountains() -> RouteDef:
	var r := _make(MOUNTAINS, PackedVector2Array([
		Vector2(0, 300), Vector2(1000, 305), Vector2(2000, 302), Vector2(3000, 312),
		Vector2(4000, 360), Vector2(5000, 416), Vector2(6000, 476), Vector2(7000, 530),
		Vector2(7600, 560), Vector2(8400, 625), Vector2(9200, 672), Vector2(10000, 732),
		Vector2(10600, 738), Vector2(11200, 732), Vector2(12500, 652), Vector2(14000, 548),
		Vector2(15500, 452), Vector2(17000, 362), Vector2(18200, 318), Vector2(19200, 304),
		Vector2(20000, 300),
	]))
	r.mood_color = Color(0.55, 0.62, 0.78)
	r.seed = 303
	# Петля: долина R ≥ 300 м; подъём — змейка 6–8 виражей R 40–60 м с траверсами
	# 300–600 м; спуск по другому склону R 80–150 м; подъём и спуск не ближе 30 м.
	r.layout = {
		"shape": "pass_loop",
		"control_points": 20,
		"waviness": 0.2,
		"min_radius_m": 40.0,
		"valley_ranges_m": [Vector2(0.0, 3000.0), Vector2(17000.0, 20000.0)],
		"valley_min_radius_m": 300.0,
		"climb_range_m": Vector2(3000.0, 10000.0),
		"switchback_range_m": Vector2(7600.0, 9200.0),
		"switchback_count": 7,
		"switchback_radius_m": Vector2(40.0, 60.0),
		"traverse_length_m": Vector2(300.0, 600.0),
		"descent_range_m": Vector2(11200.0, 19000.0),
		"descent_radius_m": Vector2(80.0, 150.0),
		"min_climb_descent_gap_m": 30.0,
	}
	r.landmarks = _landmarks([
		[500, "valley_village", Landmark.SIDE_RIGHT, Landmark.PLANE_MID],
		[2000, "stone_bridge", Landmark.SIDE_ROAD, Landmark.PLANE_NEAR],
		[3000, "pass_sign", Landmark.SIDE_RIGHT, Landmark.PLANE_NEAR],
		[4000, "summit_km_sign", Landmark.SIDE_RIGHT, Landmark.PLANE_NEAR],
		[5000, "summit_km_sign", Landmark.SIDE_RIGHT, Landmark.PLANE_NEAR],
		[5200, "waterfall", Landmark.SIDE_LEFT, Landmark.PLANE_MID],
		[6000, "summit_km_sign", Landmark.SIDE_RIGHT, Landmark.PLANE_NEAR],
		[7000, "summit_km_sign", Landmark.SIDE_RIGHT, Landmark.PLANE_NEAR],
		[7600, "switchbacks_view", Landmark.SIDE_RIGHT, Landmark.PLANE_FAR],
		[8000, "summit_km_sign", Landmark.SIDE_RIGHT, Landmark.PLANE_NEAR],
		[9000, "summit_km_sign", Landmark.SIDE_RIGHT, Landmark.PLANE_NEAR],
		[9600, "clouds_below", Landmark.SIDE_RIGHT, Landmark.PLANE_FAR],
		[10400, "pass_summit", Landmark.SIDE_LEFT, Landmark.PLANE_NEAR],
		[11200, "snow_patch", Landmark.SIDE_LEFT, Landmark.PLANE_NEAR],
		[12000, "mountain_lake", Landmark.SIDE_RIGHT, Landmark.PLANE_FAR],
		[13300, "shepherd_hut", Landmark.SIDE_LEFT, Landmark.PLANE_MID],
		[14500, "avalanche_gallery", Landmark.SIDE_ROAD, Landmark.PLANE_NEAR],
		[15500, "cable_car", Landmark.SIDE_ROAD, Landmark.PLANE_MID],
		[16500, "cow_pasture", Landmark.SIDE_RIGHT, Landmark.PLANE_NEAR],
		[17500, "sawmill", Landmark.SIDE_LEFT, Landmark.PLANE_NEAR],
		[18500, "valley_village", Landmark.SIDE_RIGHT, Landmark.PLANE_MID],
		[19500, "campsite", Landmark.SIDE_LEFT, Landmark.PLANE_NEAR],
	])
	return r


# --- Приморье (tracks.md п. 4.4) ---
static func _seaside() -> RouteDef:
	var r := _make(SEASIDE, PackedVector2Array([
		Vector2(0, 12), Vector2(1000, 14), Vector2(2000, 13), Vector2(3000, 16),
		Vector2(4000, 12), Vector2(4800, 8), Vector2(5500, 7), Vector2(5700, 12),
		Vector2(5900, 14), Vector2(6250, 14), Vector2(6450, 9), Vector2(7000, 8),
		Vector2(7600, 24), Vector2(8200, 48), Vector2(8600, 52), Vector2(9100, 46),
		Vector2(10000, 26), Vector2(11000, 14), Vector2(12000, 12),
	]))
	r.mood_color = Color(0.25, 0.70, 0.78)
	r.seed = 404
	r.bridges = [Vector2(5820.0, 6330.0)]
	r.water_level_m = 0.0
	# «D»: прямая береговая сторона 0–4.8 км, море справа (снаружи петли); дуга через
	# мыс и лес; река из озера внутри петли пересекается один раз — мостом.
	r.layout = {
		"shape": "d_loop",
		"control_points": 14,
		"waviness": 0.2,
		"min_radius_m": 60.0,
		"coast_range_m": Vector2(0.0, 4800.0),
		"coast_radius_m": Vector2(300.0, 800.0),
		"cape_radius_m": Vector2(60.0, 120.0),
		"sea_side": "outside",
		"river_crossings": 1,
	}
	r.landmarks = _landmarks([
		[600, "fishing_pier", Landmark.SIDE_RIGHT, Landmark.PLANE_NEAR],
		[1800, "beach_umbrellas", Landmark.SIDE_RIGHT, Landmark.PLANE_NEAR],
		[3000, "white_houses", Landmark.SIDE_LEFT, Landmark.PLANE_MID],
		[4200, "sailboat", Landmark.SIDE_RIGHT, Landmark.PLANE_FAR],
		[5000, "river_mouth", Landmark.SIDE_RIGHT, Landmark.PLANE_MID],
		[5800, "bridge", Landmark.SIDE_ROAD, Landmark.PLANE_NEAR],
		[7000, "pine_forest", Landmark.SIDE_BOTH, Landmark.PLANE_NEAR],
		[7800, "olive_terraces", Landmark.SIDE_LEFT, Landmark.PLANE_MID],
		[8600, "lighthouse", Landmark.SIDE_RIGHT, Landmark.PLANE_MID],
		[9800, "cliffs_spray", Landmark.SIDE_RIGHT, Landmark.PLANE_NEAR],
		[11000, "promenade", Landmark.SIDE_RIGHT, Landmark.PLANE_NEAR],
		[11800, "lifeguard_tower", Landmark.SIDE_RIGHT, Landmark.PLANE_NEAR],
	])
	return r
