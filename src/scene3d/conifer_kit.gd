class_name ConiferKit
extends RefCounted
## Хвойные (T-107, REQ-D3D-10; арт-библия «Растительность: хвойные» — источник чисел): семь
## форм (ель, ель молодая, пихта, ель-ветровал, пиния, пиния молодая, пиния наклонная), меши
## трёх уровней детализации, вариации экземпляра, доли форм по трассам, уровень детализации по
## удалению от трассы при расстановке. Всё строится один раз (`SceneryBuilder.place`), не в кадре.
##
## Меши. Ярус ели — «юбка» лап: от ствола к среднему кольцу скат, дальше — круче (лапы
## опущены), край зубчатый (кончики и выемки), каждый следующий ярус повёрнут на 137.5°, снизу
## — «низ юбки» тенью. Пиния — S-образный ствол с ветвями до плоских комковатых подушек кроны.
## Цвет вершин — три тона (свет, тень, кончики), альфа — вес контура (у сухих веток 0). Нормали
## верха подняты вверх (normalize(нормаль + 0.8 · вверх), у пинии — + 1.3): граница тун-света
## проходит по ярусу, верх светлый при любом солнце.
##
## UV2 вершины: x — номер формы в меше слоя + 1 (0 — меш одной формы), y — 1 у кроны. Один слой
## MultiMesh на уровень детализации несёт все формы трассы: форма экземпляра — `INSTANCE_CUSTOM.r`,
## вершины чужих форм шейдер схлопывает (`conifer_form.gdshaderinc`) — слоёв и вызовов отрисовки
## не больше, чем уровней. Крона (y = 1) не принимает тень (`toon.gdshader`): самозатенение
## граней яруса при наклонённых вверх нормалях давало в Forward+ полосы и пятна («acne»), а
## тон «верх светлый, низ тенью» задают нормали и цвет вершин. Ствол ели тень принимает, ствол
## и ветви пинии — нет (под широкой кроной они чернели).

const SPRUCE: int = 0
const SPRUCE_YOUNG: int = 1
const FIR: int = 2
const SPRUCE_WIND: int = 3
const STONE_PINE: int = 4
const STONE_PINE_YOUNG: int = 5
const STONE_PINE_LEAN: int = 6
## Ключи форм (таблица форм арт-библии; ключи `EnvironmentSet.conifer_forms`).
const FORM_KEYS: PackedStringArray = ["spruce", "spruce_young", "fir", "spruce_wind", "stone_pine",
	"stone_pine_young", "stone_pine_lean"]

## Свои меши (модели); молодые формы берут меш своего семейства, ветровал и наклонная пиния
## дальше LOD0 — меш ели и пинии, пихта на LOD2 — общий меш ели.
const M_SPRUCE: int = 0
const M_FIR: int = 1
const M_WIND: int = 2
const M_PINE: int = 3
const M_PINE_LEAN: int = 4
const MODEL_KEYS: PackedStringArray = ["spruce", "fir", "spruce_wind", "stone_pine", "stone_pine_lean"]
## Высота H и ширина кроны W модели при масштабе 1, м (таблица форм).
const MODEL_SIZE: Array[Vector2] = [Vector2(9.0, 3.8), Vector2(11.0, 2.86), Vector2(8.0, 2.8), Vector2(10.0, 9.0), Vector2(9.0, 8.1)]

## Уровни детализации по удалению от трассы, м (LOD0 ≤ 60 < LOD1 ≤ 220 < LOD2).
const LOD_NEAR_M: float = 60.0
const LOD_FAR_M: float = 220.0
const LOD_COUNT: int = 3
## Бюджет треугольников экземпляра по форме и уровню (таблица LOD арт-библии).
const TRI_BUDGET: Array[PackedInt32Array] = [
	[480, 120, 40], [480, 120, 40], [520, 130, 40], [480, 120, 40], [640, 160, 40], [640, 160, 40], [640, 160, 40],
]

## Вариации экземпляра (таблица «Вариации экземпляра»): масштаб, растяжение по Y, наклон оси, °.
const SCALE_RANGE: Array[Vector2] = [Vector2(0.80, 1.25), Vector2(0.40, 0.55), Vector2(0.85, 1.30), Vector2(0.85, 1.15),
	Vector2(0.85, 1.20), Vector2(0.55, 0.70), Vector2(0.85, 1.20)]
const STRETCH_SPRUCE: Vector2 = Vector2(0.92, 1.12)
const STRETCH_PINE: Vector2 = Vector2(0.95, 1.05)
const TILT_SPRUCE_DEG: float = 3.0
const TILT_SPRUCE_SLOPE_DEG: float = 5.0
const TILT_PINE_DEG: float = 4.0
## Наклон ствола наклонной пинии на уровнях без своего меша (меш пинии), °.
const LEAN_TILT_DEG: float = 12.0
## Направление наклона наклонной пинии — к воде ±35°.
const LEAN_YAW_JITTER_DEG: float = 35.0
## Яркость и множители R / B цвета экземпляра.
const BRIGHT_SPRUCE: Vector2 = Vector2(0.88, 1.10)
const BRIGHT_PINE: Vector2 = Vector2(0.90, 1.10)
const RED_SPRUCE: Vector2 = Vector2(0.94, 1.08)
const BLUE_SPRUCE: Vector2 = Vector2(0.94, 1.06)
const RED_PINE: Vector2 = Vector2(0.95, 1.08)
const BLUE_PINE: Vector2 = Vector2(0.95, 1.04)
## Именованные вариации молодых форм: ширина / высота и тон.
const YOUNG_SPRUCE_WIDTH: float = 1.15
const YOUNG_SPRUCE_TONE: float = 1.06
const YOUNG_PINE_HEIGHT: float = 0.85
const YOUNG_PINE_TONE: float = 1.05

## Тун-тона (sRGB): свет, тень, кончики, ствол (у пинии ещё тень ствола; у ветровала — сухие ветки).
const TONES_SPRUCE: PackedColorArray = [Color(0.22, 0.45, 0.28), Color(0.13, 0.29, 0.22), Color(0.33, 0.55, 0.30), Color(0.40, 0.29, 0.21)]
const TONES_FIR: PackedColorArray = [Color(0.22, 0.43, 0.35), Color(0.12, 0.27, 0.25), Color(0.30, 0.52, 0.40), Color(0.38, 0.30, 0.25)]
const TONES_WIND: PackedColorArray = [Color(0.26, 0.44, 0.27), Color(0.15, 0.29, 0.21), Color(0.36, 0.52, 0.30), Color(0.40, 0.29, 0.21), Color(0.42, 0.38, 0.34)]
const TONES_PINE: PackedColorArray = [Color(0.33, 0.52, 0.27), Color(0.20, 0.36, 0.22), Color(0.40, 0.58, 0.30), Color(0.55, 0.36, 0.25), Color(0.36, 0.24, 0.18)]
## Калибровка тонов кроны (свет, тень, кончики) под яркость в кадре (арт-библия «Не чёрные»:
## освещённый верх HSV V 0.38–0.55, тень — не ниже 0.18): тун-свет мира (солнце 0.8, холодный
## окружающий) отдаёт таблице ~0.6 её V у ели и ~0.75 у пинии; оттенок таблицы сохраняется.
const TONE_GAIN_SPRUCE: float = 1.4
const TONE_GAIN_PINE: float = 1.15

## Нормали верха: + вверх (ель) и (пиния).
const UP_TILT_SPRUCE: float = 0.8
const UP_TILT_PINE: float = 1.3
## Золотой угол между ярусами.
const GOLDEN_RAD: float = 2.399963

static var _geo: Dictionary = {}
static var _meshes: Dictionary = {}


# ---------------------------------------------------------------------------
# Формы, модели, уровни
# ---------------------------------------------------------------------------

static func is_pine(form: int) -> bool:
	return form >= STONE_PINE


## Модель (меш) формы на уровне детализации.
static func model_of(form: int, lod: int) -> int:
	match form:
		SPRUCE, SPRUCE_YOUNG:
			return M_SPRUCE
		FIR:
			return M_FIR if lod < 2 else M_SPRUCE
		SPRUCE_WIND:
			return M_WIND if lod == 0 else M_SPRUCE
		STONE_PINE, STONE_PINE_YOUNG:
			return M_PINE
		_:
			return M_PINE_LEAN if lod == 0 else M_PINE


## Уровень детализации по удалению от трассы, м.
static func lod_of(road_m: float) -> int:
	if road_m <= LOD_NEAR_M:
		return 0
	if road_m <= LOD_FAR_M:
		return 1
	return 2


## Поправка масштаба (ширина, высота), когда форма берёт меш другой модели: пропорции формы.
static func adjust_of(form: int, lod: int) -> Vector2:
	var own: Vector2 = MODEL_SIZE[model_of(form, 0)]
	var used: Vector2 = MODEL_SIZE[model_of(form, lod)]
	return Vector2(own.y / used.y, own.x / used.x)


## Модели слоя уровня `lod` для набора форм трассы — по возрастанию (номер слота = индекс).
static func models_for(forms: PackedInt32Array, lod: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for f in forms:
		var m: int = model_of(f, lod)
		if not out.has(m):
			out.append(m)
	out.sort()
	return out


## Треугольников в меше модели на уровне (без контура).
static func triangles(model: int, lod: int) -> int:
	return geometry(model, lod).tri_count()


## Доли форм трассы: `EnvironmentSet.conifer_forms` (ключ формы → доля), пусто — по
## `conifer_kind` (ель 50 / 35 / пихта 15; пиния 55 / 30 / наклонная 15).
static func form_mix(env: EnvironmentSet) -> Dictionary:
	var out: Dictionary = {}
	for key in env.conifer_forms:
		var f: int = FORM_KEYS.find(String(key))
		var share: float = float(env.conifer_forms[key])
		if f >= 0 and share > 0.0:
			out[f] = share
	if out.is_empty():
		if env.conifer_kind == 1:
			out = {STONE_PINE: 0.55, STONE_PINE_YOUNG: 0.30, STONE_PINE_LEAN: 0.15}
		else:
			out = {SPRUCE: 0.50, SPRUCE_YOUNG: 0.35, FIR: 0.15}
	return out


static func mix_forms(mix: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	for f in mix:
		out.append(int(f))
	out.sort()
	return out


# ---------------------------------------------------------------------------
# Экземпляр и расстановка
# ---------------------------------------------------------------------------

## Хвойное дерево на трассе: точка, кусок, удаление от трассы — от `SceneryBuilder`; форма,
## уровень и вариации — `plant()`.
class Plant:
	var origin := Vector3.ZERO
	var s: float = 0.0
	var chunk: int = 0
	## Удаление от ближайшей точки оси трассы, м.
	var road_m: float = 0.0
	var form: int = SPRUCE
	var lod: int = 0
	## Равномерный масштаб, растяжение по Y, поворот вокруг вертикали и наклон оси, рад.
	var scale: float = 1.0
	var stretch: float = 1.0
	var yaw: float = 0.0
	var tilt: float = 0.0
	var tilt_dir := Vector3.FORWARD
	## Именованные вариации молодых форм: ширина / высота, тон.
	var width_mul: float = 1.0
	var height_mul: float = 1.0
	var tone: float = 1.0
	## Яркость, множители R и B цвета экземпляра (до `conifer_shade`).
	var tint := Vector3.ONE
	## Наклонная пиния: горизонтальное направление к воде (ноль — не у берега).
	var lean_dir := Vector3.ZERO

	## Трансформ экземпляра: масштаб формы (и поправка модели уровня), поворот, наклон.
	func transform(conifer_scale: float) -> Transform3D:
		var adj: Vector2 = ConiferKit.adjust_of(form, lod)
		var sw: float = scale * width_mul * adj.x * conifer_scale
		var sh: float = scale * stretch * height_mul * adj.y * conifer_scale
		var b := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(sw, sh, sw))
		if tilt > 1e-5:
			var axis: Vector3 = Vector3.UP.cross(tilt_dir)
			if axis.length_squared() > 1e-8:
				b = Basis(axis.normalized(), tilt) * b
		return Transform3D(b, origin)

	## Цвет экземпляра (sRGB): яркость × тон × `conifer_shade`, множители R и B.
	func color(shade: float) -> Color:
		var v: float = tint.x * tone * shade
		return Color(v * tint.y, v, v * tint.z, 1.0)


## Формы, уровни и вариации хвойных трассы. Доли форм — `form_mix` (точно по числу деревьев,
## наибольшие остатки). Горы: в полосе `conifer_tree_line_band_m` ниже границы леса пихта и
## ветровал вместе — не меньше `conifer_tree_line_share`. Приморье: наклонная пиния — только в
## `conifer_lean_shore_m` от воды, наклон к воде; не хватило мест у берега — остаток долей
## другим пиниям. Своя последовательность случайных чисел (расстановка рощ от неё не зависит).
static func plant(plants: Array[Plant], env: EnvironmentSet, field: TerrainField) -> void:
	var n: int = plants.size()
	if n == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = env.scenery_seed + 53
	var mix: Dictionary = form_mix(env)
	var forms: PackedInt32Array = mix_forms(mix)
	var quota: Dictionary = _quotas(mix, forms, n)
	var assigned := PackedInt32Array()
	assigned.resize(n)
	assigned.fill(-1)
	if quota.has(STONE_PINE_LEAN):
		var band := PackedInt32Array()
		if field != null and field.has_water():
			for i in n:
				var d: Vector3 = _water_dir(field, plants[i].origin, env.conifer_lean_shore_m)
				if d != Vector3.ZERO:
					plants[i].lean_dir = d
					band.append(i)
		_shuffle(band, rng)
		var k: int = mini(int(quota[STONE_PINE_LEAN]), band.size())
		for j in k:
			assigned[band[j]] = STONE_PINE_LEAN
		var spare: int = int(quota[STONE_PINE_LEAN]) - k
		quota[STONE_PINE_LEAN] = 0
		_give_spare(quota, spare, [STONE_PINE, STONE_PINE_YOUNG], mix)
	var high: Array[int] = []
	for f in [FIR, SPRUCE_WIND]:
		if quota.has(f):
			high.append(f)
	if not high.is_empty() and env.tree_line_m < SceneryBuilder.TREE_LINE_OFF_M:
		var band := PackedInt32Array()
		for i in n:
			if plants[i].origin.y > env.tree_line_m - env.conifer_tree_line_band_m:
				band.append(i)
		_shuffle(band, rng)
		var left: int = 0
		for f in high:
			left += int(quota[f])
		var need: int = mini(int(ceil(env.conifer_tree_line_share * float(band.size()))), left)
		for j in need:
			var pick: int = high[0]
			if high.size() > 1:
				var a: int = int(quota[high[0]])
				var b: int = int(quota[high[1]])
				pick = high[0] if rng.randf() * float(a + b) < float(a) else high[1]
			quota[pick] = int(quota[pick]) - 1
			assigned[band[j]] = pick
	var pool := PackedInt32Array()
	for f in forms:
		for q in int(quota.get(f, 0)):
			pool.append(f)
	_shuffle(pool, rng)
	var next: int = 0
	for i in n:
		if assigned[i] < 0:
			assigned[i] = pool[next] if next < pool.size() else forms[0]
			next += 1
	for i in n:
		_vary(plants[i], assigned[i], field, rng)


## Вариации экземпляра формы `form` по таблице спеки.
static func _vary(p: Plant, form: int, field: TerrainField, rng: RandomNumberGenerator) -> void:
	p.form = form
	p.lod = lod_of(p.road_m)
	var pine: bool = is_pine(form)
	p.scale = rng.randf_range(SCALE_RANGE[form].x, SCALE_RANGE[form].y)
	var st: Vector2 = STRETCH_PINE if pine else STRETCH_SPRUCE
	p.stretch = rng.randf_range(st.x, st.y)
	p.yaw = rng.randf() * TAU
	var br: Vector2 = BRIGHT_PINE if pine else BRIGHT_SPRUCE
	var rr: Vector2 = RED_PINE if pine else RED_SPRUCE
	var bb: Vector2 = BLUE_PINE if pine else BLUE_SPRUCE
	p.tint = Vector3(rng.randf_range(br.x, br.y), rng.randf_range(rr.x, rr.y), rng.randf_range(bb.x, bb.y))
	if form == SPRUCE_YOUNG:
		p.width_mul = YOUNG_SPRUCE_WIDTH
		p.tone = YOUNG_SPRUCE_TONE
	elif form == STONE_PINE_YOUNG:
		p.height_mul = YOUNG_PINE_HEIGHT
		p.tone = YOUNG_PINE_TONE
	# Наклон оси: случайный; ель на склоне — по уклону (вниз), до 5°.
	var max_deg: float = TILT_PINE_DEG if pine else TILT_SPRUCE_DEG
	var dir_ang: float = rng.randf() * TAU
	p.tilt_dir = Vector3(cos(dir_ang), 0.0, sin(dir_ang))
	if field != null and not pine:
		var e: float = 2.0
		var o: Vector3 = p.origin
		var g := Vector2(field.height_at(o.x + e, o.z) - field.height_at(o.x - e, o.z),
			field.height_at(o.x, o.z + e) - field.height_at(o.x, o.z - e)) / (2.0 * e)
		var slope: float = g.length()
		if slope > 0.08:
			max_deg = lerpf(TILT_SPRUCE_DEG, TILT_SPRUCE_SLOPE_DEG, clampf((slope - 0.08) / 0.4, 0.0, 1.0))
			var down := Vector3(-g.x, 0.0, -g.y).normalized()
			p.tilt_dir = down.rotated(Vector3.UP, rng.randf_range(-0.5, 0.5))
	p.tilt = deg_to_rad(rng.randf_range(0.0, max_deg))
	if form == STONE_PINE_LEAN and p.lean_dir != Vector3.ZERO:
		var d: Vector3 = p.lean_dir.rotated(Vector3.UP, deg_to_rad(rng.randf_range(-LEAN_YAW_JITTER_DEG, LEAN_YAW_JITTER_DEG)))
		if p.lod == 0:
			# Свой меш наклонён к +X: локальный +X — к воде.
			p.yaw = atan2(-d.z, d.x)
		else:
			p.tilt_dir = d
			p.tilt = deg_to_rad(LEAN_TILT_DEG) + p.tilt


## Число деревьев каждой формы: доли × n, наибольшие остатки (сумма — ровно n).
static func _quotas(mix: Dictionary, forms: PackedInt32Array, n: int) -> Dictionary:
	var total: float = 0.0
	for f in forms:
		total += float(mix[f])
	var out: Dictionary = {}
	var rest: Array = []
	var used: int = 0
	for f in forms:
		var exact: float = float(mix[f]) / maxf(total, 1e-6) * float(n)
		out[f] = int(floor(exact))
		used += int(out[f])
		rest.append([exact - floor(exact), f])
	rest.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var i: int = 0
	while used < n and not rest.is_empty():
		var f: int = rest[i % rest.size()][1]
		out[f] = int(out[f]) + 1
		used += 1
		i += 1
	return out


## Раздать `spare` деревьев формам `to` пропорционально долям.
static func _give_spare(quota: Dictionary, spare: int, to: Array, mix: Dictionary) -> void:
	var targets: Array[int] = []
	for f in to:
		if quota.has(f):
			targets.append(f)
	if spare <= 0 or targets.is_empty():
		return
	var sum: float = 0.0
	for f in targets:
		sum += float(mix[f])
	var given: int = 0
	for k in targets.size():
		var f: int = targets[k]
		var add: int = spare - given if k == targets.size() - 1 else int(round(float(spare) * float(mix[f]) / maxf(sum, 1e-6)))
		quota[f] = int(quota[f]) + add
		given += add


static func _shuffle(a: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t: int = a[i]
		a[i] = a[j]
		a[j] = t


## Направление к ближайшей воде в пределах `reach_m` (8 направлений, 4 дальности), ноль — нет.
static func _water_dir(field: TerrainField, p: Vector3, reach_m: float) -> Vector3:
	for step in 4:
		var d: float = reach_m * float(step + 1) / 4.0
		for k in 8:
			var a: float = TAU * float(k) / 8.0
			var dir := Vector3(cos(a), 0.0, sin(a))
			var q: Vector3 = p + dir * d
			if field.water_depth_at(q.x, q.z) > 0.3:
				return dir
	return Vector3.ZERO


# ---------------------------------------------------------------------------
# Меши
# ---------------------------------------------------------------------------

## Меш одной модели (ориентиры, галерея): без выбора формы в шейдере.
static func single_mesh(model: int, lod: int, material: Material) -> ArrayMesh:
	var models := PackedInt32Array([model])
	return layer_mesh(models, lod, material)


## Меш слоя уровня `lod`: модели `models` подряд; больше одной — у вершин номер слота в UV2.x.
static func layer_mesh(models: PackedInt32Array, lod: int, material: Material) -> ArrayMesh:
	var key: String = "%s:%d:%d" % [str(models), lod, material.get_instance_id() if material != null else 0]
	if _meshes.has(key):
		return _meshes[key]
	var g := Geo.new()
	for slot in models.size():
		g.append(geometry(models[slot], lod), float(slot + 1) if models.size() > 1 else 0.0)
	var mesh := g.to_mesh(material)
	_meshes[key] = mesh
	return mesh


## Геометрия модели на уровне (кэш на процесс, детерминированно).
static func geometry(model: int, lod: int) -> Geo:
	var key: int = model * LOD_COUNT + lod
	if _geo.has(key):
		return _geo[key]
	var g := Geo.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7001 + key * 31
	match model:
		M_SPRUCE:
			_spruce(g, rng, lod)
		M_FIR:
			_fir(g, rng, lod)
		M_WIND:
			_wind(g, rng)
		M_PINE:
			_pine(g, rng, lod, 0.0, MODEL_SIZE[M_PINE].x)
		M_PINE_LEAN:
			_pine(g, rng, lod, 15.0, MODEL_SIZE[M_PINE_LEAN].x)
	_geo[key] = g
	return g


## Высоты краёв ярусов снизу вверх: высота яруса от `h0` до `h1` (доли H) линейно, верхний
## ярус с вершиной `apex_k` × высоты; сумма — от `b0` до `top` (м). Возвращает [края, высоты].
static func _tier_heights(count: int, b0: float, top: float, h0: float, h1: float, apex_k: float, gap_after: int = -1,
		gap_m: float = 0.0) -> Array[PackedFloat32Array]:
	var raw := PackedFloat32Array()
	var sum: float = 0.0
	for i in count:
		var t: float = float(i) / float(maxi(count - 1, 1))
		raw.append(lerpf(h0, h1, t))
		sum += raw[i] * (apex_k if i == count - 1 else 1.0)
	var k: float = (top - b0 - gap_m) / sum
	var edges := PackedFloat32Array()
	var heights := PackedFloat32Array()
	var b: float = b0
	for i in count:
		edges.append(b)
		heights.append(raw[i] * k)
		b += raw[i] * k
		if i == gap_after:
			b += gap_m
	return [edges, heights]


## Ель взрослая: 6 ярусов (LOD0), 4 (LOD1), 3 конуса (LOD2).
static func _spruce(g: Geo, rng: RandomNumberGenerator, lod: int) -> void:
	var size: Vector2 = MODEL_SIZE[M_SPRUCE]
	var H: float = size.x
	var p := TierParams.new()
	p.tones = _crown_tones(TONES_SPRUCE, TONE_GAIN_SPRUCE)
	p.notch = Vector2(0.15, 0.25)
	p.droop_deg = 12.0
	p.apex_k = 1.3
	if lod == 0:
		_spruce_like(g, rng, H, size.y, 6, [9, 9, 8, 8, 7, 7], 0.12, 0.94, 0.17, 0.09, 0.9, p, true)
	elif lod == 1:
		_spruce_like(g, rng, H, size.y, 4, [6, 6, 6, 6], 0.12, 0.94, 0.26, 0.16, 0.9, p, false)
	else:
		_far_cones(g, H, size.y, 0.12, 0.94, p.tones)


## Пихта узкая: колонна, 8 ярусов (LOD0), 5 (LOD1); выемки мельче, лапы опущены меньше.
static func _fir(g: Geo, rng: RandomNumberGenerator, lod: int) -> void:
	var size: Vector2 = MODEL_SIZE[M_FIR]
	var p := TierParams.new()
	p.tones = _crown_tones(TONES_FIR, TONE_GAIN_SPRUCE)
	p.notch = Vector2(0.08, 0.12)
	p.droop_deg = 6.5
	p.apex_k = 1.45
	if lod == 0:
		_spruce_like(g, rng, size.x, size.y, 8, [7, 7, 7, 6, 6, 6, 6, 6], 0.09, 0.95, 0.13, 0.075, 0.55, p, true)
	else:
		_spruce_like(g, rng, size.x, size.y, 5, [6, 6, 6, 6, 6], 0.09, 0.95, 0.2, 0.12, 0.55, p, false)


## Ель-ветровал: 5 ярусов, с подветренной стороны (−X) лапы короче, между 2-м и 3-м ярусом —
## разрыв с голым стволом и сухими ветками (вес контура 0); нижний ярус — 5 лап.
static func _wind(g: Geo, rng: RandomNumberGenerator) -> void:
	var size: Vector2 = MODEL_SIZE[M_WIND]
	var H: float = size.x
	var p := TierParams.new()
	p.tones = _crown_tones(TONES_WIND, TONE_GAIN_SPRUCE)
	p.notch = Vector2(0.15, 0.25)
	p.droop_deg = 12.0
	p.apex_k = 1.3
	p.lee = Vector3.LEFT
	p.lee_k = 0.35
	p.gap_after = 1
	p.gap_m = 0.10 * H
	_spruce_like(g, rng, H, size.y, 5, [5, 7, 7, 6, 6], 0.15, 0.93, 0.17, 0.10, 0.9, p, true)
	var hs: Array[PackedFloat32Array] = _tier_heights(5, 0.15 * H, 0.93 * H, 0.17, 0.10, p.apex_k, p.gap_after, p.gap_m)
	var gap_lo: float = hs[0][1] + hs[1][1] * 1.0
	g.crown = 0.0
	for i in 3:
		var y: float = gap_lo + p.gap_m * (0.25 + 0.3 * float(i))
		var a: float = 0.6 + 2.3 * float(i) + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), rng.randf_range(-0.25, 0.1), sin(a)).normalized()
		var length: float = rng.randf_range(0.5, 0.9)
		var root := Vector3(0.0, y, 0.0)
		g.tube(root, root + dir * length, 0.035, 0.012, 4, TONES_WIND[4], TONES_WIND[4], 0.0)
	g.crown = 1.0


## Тоны с калибровкой кроны: первые три (свет, тень, кончики) × `gain`, ствол и ветки — как в таблице.
static func _crown_tones(tones: PackedColorArray, gain: float) -> PackedColorArray:
	var out := tones.duplicate()
	for i in 3:
		out[i] = Color(minf(tones[i].r * gain, 1.0), minf(tones[i].g * gain, 1.0), minf(tones[i].b * gain, 1.0))
	return out


class TierParams:
	var tones: PackedColorArray
	var notch := Vector2(0.15, 0.25)
	var droop_deg: float = 12.0
	var apex_k: float = 1.3
	var lee := Vector3.ZERO
	var lee_k: float = 0.0
	var gap_after: int = -1
	var gap_m: float = 0.0


## Ель-подобная крона: ствол (с расширением у корня), ярусы-«юбки» с поворотом на золотой угол,
## лидер над верхним ярусом (только LOD0). Радиус края яруса — 0.5 W · (1 − t)^`power`.
static func _spruce_like(g: Geo, rng: RandomNumberGenerator, H: float, W: float, count: int, lappets: Array,
		b0_k: float, top_k: float, h0: float, h1: float, power: float, p: TierParams, detail: bool) -> void:
	var b0: float = b0_k * H
	var top: float = top_k * H
	var hs: Array[PackedFloat32Array] = _tier_heights(count, b0, top, h0, h1, p.apex_k, p.gap_after, p.gap_m)
	var edges: PackedFloat32Array = hs[0]
	var heights: PackedFloat32Array = hs[1]
	# Ствол: виден у основания; внутри кроны до нижней части верхних ярусов.
	g.crown = 0.0
	var r0: float = 0.022 * H
	var bark: Color = p.tones[3]
	var trunk_top: float = edges[mini(count - 1, maxi(p.gap_after + 2, 1))] + heights[0] * 0.3
	if detail:
		g.tube(Vector3(0.0, -0.3, 0.0), Vector3(0.0, 0.35, 0.0), r0 * 1.5, r0, 6, bark, bark, 1.0)
		g.tube(Vector3(0.0, 0.35, 0.0), Vector3(0.0, trunk_top, 0.0), r0, r0 * 0.55, 6, bark, bark.darkened(0.2), 1.0)
	else:
		g.tube(Vector3(0.0, -0.3, 0.0), Vector3(0.0, trunk_top, 0.0), r0 * 1.2, r0 * 0.6, 4, bark, bark.darkened(0.2), 1.0)
	g.crown = 1.0
	var phase: float = rng.randf() * TAU
	var span: float = top - b0 - p.gap_m
	for i in count:
		var below: float = 0.0
		if p.gap_after >= 0 and i > p.gap_after:
			below = p.gap_m
		var t: float = clampf((edges[i] - b0 - below) / span, 0.0, 0.97)
		var R: float = maxf(0.5 * W * pow(1.0 - t, power), 0.08 * W)
		var apex_k: float = 1.0 if i == p.gap_after else p.apex_k
		_tier(g, rng, edges[i], heights[i], R, int(lappets[i]), phase, p, apex_k, detail)
		phase += GOLDEN_RAD + rng.randf_range(-0.15, 0.15)
	if detail:
		# Лидер («свечка») над верхним ярусом.
		var y_top: float = edges[count - 1] + heights[count - 1] * p.apex_k
		g.leader(Vector3(0.0, y_top - 0.3, 0.0), Vector3(0.0, y_top + 0.06 * H, 0.0), 0.012 * H, p.tones[0])


## Ярус: край (кончики лап) на высоте `b`, радиус `R`, `n` лап. LOD0 (`detail`): вершина у ствола
## (тень) → среднее кольцо 0.55 R (свет) → край (кончики — третьим тоном), снаружи от среднего
## кольца скат круче на `droop_deg` (лапы висят); выемки между кончиками глубиной `notch` × R,
## радиус кончиков ±12 %. LOD1: вершина → край. Снизу — «низ юбки» тенью.
static func _tier(g: Geo, rng: RandomNumberGenerator, b: float, h: float, R: float, n: int, phase: float,
		p: TierParams, apex_k: float, detail: bool) -> void:
	var light: Color = p.tones[0]
	var shade: Color = p.tones[1]
	var tip_c: Color = p.tones[2] if detail else light
	var rise: float = apex_k * h
	var delta: float = deg_to_rad(p.droop_deg)
	# Наклон внутреннего ската α: 0.55 R tg α + 0.45 R tg(α + δ) = подъём вершины над краем.
	var lo: float = deg_to_rad(5.0)
	var hi: float = deg_to_rad(84.0) - delta
	for it in 30:
		var mid_a: float = (lo + hi) * 0.5
		if 0.55 * R * tan(mid_a) + 0.45 * R * tan(mid_a + delta) < rise:
			lo = mid_a
		else:
			hi = mid_a
	var alpha: float = (lo + hi) * 0.5
	var outer_tan: float = tan(alpha + delta) if detail else rise / R
	var m: int = n * 2
	var lee_ang: float = atan2(p.lee.z, p.lee.x)
	var apex := Vector3(0.0, b + rise, 0.0)
	var v_top: int = g.v.size()
	var t_top: int = g.idx.size()
	var i_apex: int = g.vert(apex, shade if detail else shade.lerp(light, 0.25))
	var edge_pos := PackedVector3Array()
	var ring := PackedInt32Array()
	var mid := PackedInt32Array()
	for j in m:
		var th: float = phase + PI * float(j) / float(n)
		var dir := Vector3(cos(th), 0.0, sin(th))
		var lf: float = 1.0
		if p.lee_k > 0.0:
			lf = 1.0 - p.lee_k * maxf(0.0, cos(th - lee_ang))
		var tip: bool = j % 2 == 0
		var r: float = R * lf * (rng.randf_range(0.88, 1.12) if tip else 1.0 - rng.randf_range(p.notch.x, p.notch.y))
		var y: float = b + (R * lf - r) * outer_tan
		var e: Vector3 = dir * r + Vector3(0.0, y, 0.0)
		edge_pos.append(e)
		if detail:
			var ridge: float = (0.04 if tip else -0.04) * h
			mid.append(g.vert(dir * (0.55 * R * lf) + Vector3(0.0, b + 0.45 * R * tan(alpha + delta) + ridge, 0.0), light))
		ring.append(g.vert(e, tip_c if tip else light))
	for j in m:
		var j1: int = (j + 1) % m
		var out: Vector3 = (edge_pos[j] + edge_pos[j1]) * 0.5
		var hint := Vector3(out.x, 0.0, out.z).normalized() + Vector3.UP
		if detail:
			g.tri(i_apex, mid[j], mid[j1], hint)
			g.tri(mid[j], ring[j], ring[j1], hint)
			g.tri(mid[j], ring[j1], mid[j1], hint)
		else:
			g.tri(i_apex, ring[j], ring[j1], hint)
	g.smooth(v_top, t_top, UP_TILT_SPRUCE, 0.0)
	# Низ юбки: от края к стволу, тенью.
	var v_under: int = g.v.size()
	var t_under: int = g.idx.size()
	var c_under: int = g.vert(Vector3(0.0, b + 0.35 * h, 0.0), shade.darkened(0.1))
	var under := PackedInt32Array()
	for j in m:
		under.append(g.vert(edge_pos[j], shade))
	for j in m:
		g.tri(c_under, under[j], under[(j + 1) % m], Vector3.DOWN)
	g.smooth(v_under, t_under, 0.0, 0.0)


## Дальний уровень ели (LOD2): 3 конуса по 5 граней с низом юбки, ствол-трубка 4 граней.
static func _far_cones(g: Geo, H: float, W: float, b0_k: float, top_k: float, tones: PackedColorArray) -> void:
	var b0: float = b0_k * H
	var top: float = top_k * H
	g.crown = 0.0
	g.tube(Vector3(0.0, -0.3, 0.0), Vector3(0.0, b0 + 0.6, 0.0), 0.022 * H * 1.2, 0.022 * H * 0.8, 4, tones[3], tones[3], 1.0)
	g.crown = 1.0
	var hs: Array[PackedFloat32Array] = _tier_heights(3, b0, top, 0.36, 0.24, 1.25)
	for i in 3:
		var b: float = hs[0][i]
		var h: float = hs[1][i]
		var t: float = (b - b0) / (top - b0)
		var R: float = 0.5 * W * pow(1.0 - t, 0.9)
		var rise: float = h * (1.25 if i == 2 else 1.3)
		var v0: int = g.v.size()
		var t0: int = g.idx.size()
		var apex: int = g.vert(Vector3(0.0, b + rise, 0.0), tones[1].lerp(tones[0], 0.3))
		var ring := PackedInt32Array()
		var pos := PackedVector3Array()
		for k in 5:
			var a: float = TAU * float(k) / 5.0 + GOLDEN_RAD * float(i)
			var e := Vector3(cos(a) * R, b, sin(a) * R)
			pos.append(e)
			ring.append(g.vert(e, tones[0]))
		for k in 5:
			var out: Vector3 = (pos[k] + pos[(k + 1) % 5]) * 0.5
			g.tri(apex, ring[k], ring[(k + 1) % 5], Vector3(out.x, 0.0, out.z).normalized() + Vector3.UP)
		g.smooth(v0, t0, UP_TILT_SPRUCE, 0.0)
		var v1: int = g.v.size()
		var t1: int = g.idx.size()
		var c: int = g.vert(Vector3(0.0, b + 0.35 * h, 0.0), tones[1])
		var under := PackedInt32Array()
		for k in 5:
			under.append(g.vert(pos[k], tones[1]))
		for k in 5:
			g.tri(c, under[k], under[(k + 1) % 5], Vector3.DOWN)
		g.smooth(v1, t1, 0.0, 0.0)


## Пиния: S-образный ствол до развилки на 0.58 H, ветви до подушек нижнего уровня; крона —
## подушки на двух уровнях (+ верхняя), плоский верх и почти плоский низ, между подушками
## просветы. `lean_deg` > 0 — наклонная: ствол наклонён к +X, крона смещена и асимметрична.
## LOD1 — 4 подушки без колец, ствол 2 звена; LOD2 — 2 плоских диска на трубке 4 граней.
static func _pine(g: Geo, rng: RandomNumberGenerator, lod: int, lean_deg: float, H: float) -> void:
	var tn: PackedColorArray = _crown_tones(TONES_PINE, TONE_GAIN_PINE)
	var lean: float = tan(deg_to_rad(lean_deg))
	var asym: float = 0.06 * H if lean_deg > 0.0 else 0.0
	var trunk_pts: Array[Vector3] = [Vector3(0.0, -0.3, 0.0), Vector3(0.035 * H, 0.2 * H, 0.01 * H),
		Vector3(-0.03 * H, 0.4 * H, -0.01 * H), Vector3(0.02 * H, 0.58 * H, 0.0)]
	for i in trunk_pts.size():
		trunk_pts[i].x += lean * maxf(trunk_pts[i].y, 0.0)
	var radii: Array[float] = [0.026 * H, 0.022 * H, 0.018 * H, 0.015 * H]
	var fork: Vector3 = trunk_pts[3]
	# Подушки: угол (°), удаление от оси (H), высота края (H), радиус (H), толщина (H), зубцов.
	var pads: Array = [[10.0, 0.265, 0.68, 0.215, 0.17, 9], [132.0, 0.27, 0.66, 0.215, 0.16, 9], [248.0, 0.26, 0.70, 0.21, 0.18, 9],
		[70.0, 0.11, 0.79, 0.19, 0.16, 9], [192.0, 0.10, 0.80, 0.18, 0.15, 9], [308.0, 0.12, 0.78, 0.18, 0.16, 9],
		[0.0, 0.0, 0.88, 0.14, 0.13, 8]]
	var centers: Array[Vector3] = []
	var sizes: Array[Vector3] = []
	for pd in pads:
		var a: float = deg_to_rad(float(pd[0]))
		var y0: float = float(pd[2]) * H
		var c := Vector3(cos(a) * float(pd[1]) * H, y0, sin(a) * float(pd[1]) * H)
		var r: float = float(pd[3]) * H
		if lean_deg > 0.0:
			c.x += lean * y0 + asym
			r *= 1.1 if cos(a) > 0.2 else 0.92
		centers.append(c)
		sizes.append(Vector3(r, float(pd[4]) * H, float(pd[5])))
	# Ствол и ветви пинии тоже не принимают тень и их нормали подняты вверх (+ 0.7): под широкой
	# кроной ствол целиком в её тени и с теневой стороны был чёрным (V ≈ 0.13); теперь он бурый,
	# стороны различает тон вершин (низ — свет коры, у кроны — тень коры).
	var v_trunk: int = g.v.size()
	if lod == 2:
		g.tube(trunk_pts[0], fork, radii[0], radii[3], 4, tn[3], tn[4], 1.0)
		g.lift_normals(v_trunk, 0.7)
		var hub := Vector3(fork.x + 0.03 * H, 0.0, fork.z)
		_disk(g, hub + Vector3(asym, 0.69 * H, 0.0), 0.40 * H, 0.10 * H, tn)
		_disk(g, hub + Vector3(asym * 1.4 + lean * 0.12 * H, 0.81 * H, 0.0), 0.27 * H, 0.08 * H, tn)
		return
	if lod == 0:
		for i in 3:
			g.tube(trunk_pts[i], trunk_pts[i + 1], radii[i], radii[i + 1], 6, tn[3].lerp(tn[4], float(i) / 3.0),
				tn[3].lerp(tn[4], float(i + 1) / 3.0), 1.0)
		for k in 3:
			var target: Vector3 = centers[k] - Vector3(0.0, 0.2 * sizes[k].y, 0.0)
			var bend: Vector3 = fork.lerp(target, 0.5) + Vector3(0.0, 0.04 * H, 0.0)
			g.tube(fork, bend, 0.014 * H, 0.011 * H, 5, tn[4], tn[4], 1.0)
			g.tube(bend, target, 0.011 * H, 0.008 * H, 5, tn[4], tn[4], 1.0)
	else:
		g.tube(trunk_pts[0], trunk_pts[2], radii[0], radii[2], 5, tn[3], tn[3].lerp(tn[4], 0.6), 1.0)
		g.tube(trunk_pts[2], fork, radii[2], radii[3], 5, tn[3].lerp(tn[4], 0.6), tn[4], 1.0)
		for k in 2:
			var target: Vector3 = centers[k] - Vector3(0.0, 0.2 * sizes[k].y, 0.0)
			g.tube(fork, target, 0.013 * H, 0.008 * H, 4, tn[4], tn[4], 1.0)
	g.lift_normals(v_trunk, 0.7)
	var phase: float = rng.randf() * TAU
	for k in centers.size():
		if lod == 1 and k >= 3 and k < 6:
			continue
		var sz: Vector3 = sizes[k]
		if lod == 1 and k == 6:
			sz = Vector3(sz.x * 1.3, sz.y * 1.2, sz.z)
		_pad(g, rng, centers[k], sz.x, sz.y, int(sz.z) if lod == 0 else 7, phase, tn, lod == 0)
		phase += GOLDEN_RAD


## Подушка кроны пинии: край (зубцы и выемки 10–15 %) на высоте `c.y`, верх — купол с буграми
## (±6 % толщины), низ почти плоский. LOD0: центр → кольцо 0.45 R → кольцо 0.8 R → край; LOD1:
## центр → край. Нормали подняты вверх (низ кроны не чёрный), у низа — ещё и наружу (контур).
static func _pad(g: Geo, rng: RandomNumberGenerator, c: Vector3, R: float, thick: float, teeth: int, phase: float,
		tn: PackedColorArray, detail: bool) -> void:
	var light: Color = tn[0]
	var shade: Color = tn[1]
	var tip_c: Color = tn[2] if detail else light
	var v0: int = g.v.size()
	var t0: int = g.idx.size()
	var top: int = g.vert(c + Vector3(0.0, 0.62 * thick * rng.randf_range(0.94, 1.06), 0.0), light)
	var m: int = teeth * 2
	var edge := PackedInt32Array()
	var edge_pos := PackedVector3Array()
	var ra := PackedInt32Array()
	var rb := PackedInt32Array()
	for j in m:
		var th: float = phase + PI * float(j) / float(teeth)
		var dir := Vector3(cos(th), 0.0, sin(th))
		var tip: bool = j % 2 == 0
		var r: float = R * (rng.randf_range(0.95, 1.05) if tip else 1.0 - rng.randf_range(0.10, 0.15))
		var e: Vector3 = c + dir * r + Vector3(0.0, (-0.04 if tip else 0.03) * thick, 0.0)
		edge_pos.append(e)
		edge.append(g.vert(e, tip_c if tip else light))
		if detail and tip:
			var bump_a: float = rng.randf_range(-0.06, 0.06) * thick
			var bump_b: float = rng.randf_range(-0.06, 0.06) * thick
			ra.append(g.vert(c + dir * (0.45 * R) + Vector3(0.0, 0.50 * thick + bump_a, 0.0), light))
			rb.append(g.vert(c + dir * (0.80 * R) + Vector3(0.0, 0.30 * thick + bump_b, 0.0), light))
	for j in m:
		var j1: int = (j + 1) % m
		var out: Vector3 = (edge_pos[j] + edge_pos[j1]) * 0.5 - c
		var hint: Vector3 = Vector3(out.x, 0.0, out.z).normalized() + Vector3.UP
		if not detail:
			g.tri(top, edge[j], edge[j1], hint)
	if detail:
		for k in teeth:
			var k1: int = (k + 1) % teeth
			var dir_k: Vector3 = (g.v[rb[k]] - c) * Vector3(1.0, 0.0, 1.0)
			var hint: Vector3 = dir_k.normalized() + Vector3.UP
			g.tri(top, ra[k], ra[k1], Vector3.UP)
			g.tri(ra[k], rb[k], rb[k1], hint)
			g.tri(ra[k], rb[k1], ra[k1], hint)
			# Край: кончик k, выемка k, кончик k+1 (индексы края 2k, 2k+1, 2k+2).
			var e0: int = edge[2 * k]
			var e1: int = edge[2 * k + 1]
			var e2: int = edge[(2 * k + 2) % m]
			g.tri(rb[k], e0, e1, hint)
			g.tri(rb[k], e1, rb[k1], hint)
			g.tri(rb[k1], e1, e2, hint)
	g.smooth(v0, t0, UP_TILT_PINE, 0.0, c)
	var v1: int = g.v.size()
	var t1: int = g.idx.size()
	var bottom: int = g.vert(c - Vector3(0.0, 0.38 * thick, 0.0), shade)
	var under := PackedInt32Array()
	for j in m:
		under.append(g.vert(edge_pos[j], shade))
	for j in m:
		g.tri(bottom, under[j], under[(j + 1) % m], Vector3.DOWN)
	g.smooth(v1, t1, UP_TILT_PINE, 0.6, c)


## Плоский диск кроны (LOD2 пинии): шестиугольник, верх и низ.
static func _disk(g: Geo, c: Vector3, R: float, thick: float, tn: PackedColorArray) -> void:
	var v0: int = g.v.size()
	var t0: int = g.idx.size()
	var top: int = g.vert(c + Vector3(0.0, thick * 0.6, 0.0), tn[0])
	var pos := PackedVector3Array()
	var ring := PackedInt32Array()
	for k in 6:
		var a: float = TAU * float(k) / 6.0
		var e: Vector3 = c + Vector3(cos(a) * R, 0.0, sin(a) * R)
		pos.append(e)
		ring.append(g.vert(e, tn[0]))
	for k in 6:
		g.tri(top, ring[k], ring[(k + 1) % 6], Vector3.UP)
	g.smooth(v0, t0, UP_TILT_PINE, 0.0, c)
	var v1: int = g.v.size()
	var t1: int = g.idx.size()
	var bottom: int = g.vert(c - Vector3(0.0, thick * 0.4, 0.0), tn[1])
	var under := PackedInt32Array()
	for k in 6:
		under.append(g.vert(pos[k], tn[1]))
	for k in 6:
		g.tri(bottom, under[k], under[(k + 1) % 6], Vector3.DOWN)
	g.smooth(v1, t1, UP_TILT_PINE, 0.6, c)


## Геометрия с цветом вершин (sRGB → линейный, альфа — вес контура) и UV2 (слот формы, крона).
class Geo:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var f := PackedVector2Array()
	var idx := PackedInt32Array()
	## UV2.y новых вершин: 1 — крона (не принимает тень), 0 — ствол и ветки.
	var crown: float = 1.0

	func tri_count() -> int:
		return idx.size() / 3

	func vert(p: Vector3, col: Color, outline: float = 1.0, nrm: Vector3 = Vector3.UP) -> int:
		v.append(p)
		n.append(nrm)
		var lc: Color = MeshKit.lin(Color(col.r, col.g, col.b, outline))
		c.append(lc)
		f.append(Vector2(0.0, crown))
		return v.size() - 1

	## Треугольник, лицевой стороной к `hint` (в Godot лицевая — обход по часовой в экране).
	func tri(a: int, b: int, d: int, hint: Vector3) -> void:
		var fn: Vector3 = (v[d] - v[a]).cross(v[b] - v[a])
		if fn.dot(hint) < 0.0:
			idx.append_array(PackedInt32Array([a, d, b]))
		else:
			idx.append_array(PackedInt32Array([a, b, d]))

	## Нормали вершин с индексом ≥ `v_from` — сглаженные по треугольникам с `t_from` (индекс в
	## `idx`), плюс `up` × вверх и `radial` × наружу от оси через `center`.
	func smooth(v_from: int, t_from: int, up: float, radial: float, center: Vector3 = Vector3.ZERO) -> void:
		var acc := PackedVector3Array()
		acc.resize(v.size() - v_from)
		for t in range(t_from, idx.size(), 3):
			var i0: int = idx[t]
			var i1: int = idx[t + 1]
			var i2: int = idx[t + 2]
			var fn: Vector3 = (v[i2] - v[i0]).cross(v[i1] - v[i0])
			if fn.length_squared() < 1e-12:
				continue
			fn = fn.normalized()
			for i in [i0, i1, i2]:
				if i >= v_from:
					acc[i - v_from] += fn
		for k in acc.size():
			var nn: Vector3 = acc[k].normalized() if acc[k].length_squared() > 1e-12 else Vector3.UP
			var out := Vector3(v[v_from + k].x - center.x, 0.0, v[v_from + k].z - center.z)
			if radial > 0.0 and out.length_squared() > 1e-8:
				nn += out.normalized() * radial
			n[v_from + k] = (nn + Vector3.UP * up).normalized()

	## Трубка без торцов от `a` до `b` (радиусы `ra` → `rb`), цвет от `ca` к `cb`.
	func tube(a: Vector3, b: Vector3, ra: float, rb: float, sides: int, ca: Color, cb: Color, outline: float) -> void:
		var axis: Vector3 = b - a
		if axis.length_squared() < 1e-8:
			return
		var dir: Vector3 = axis.normalized()
		var u: Vector3 = Vector3.RIGHT - dir * dir.x
		if u.length_squared() < 1e-6:
			u = Vector3.FORWARD - dir * dir.dot(Vector3.FORWARD)
		u = u.normalized()
		var w: Vector3 = dir.cross(u).normalized()
		var slope: float = (ra - rb) / axis.length()
		var start: int = v.size()
		for i in sides:
			var ang: float = TAU * float(i) / float(sides)
			var radial: Vector3 = u * cos(ang) + w * sin(ang)
			var nrm: Vector3 = (radial + dir * slope).normalized()
			vert(a + radial * ra, ca, outline, nrm)
			vert(b + radial * rb, cb, outline, nrm)
		for i in sides:
			var i0: int = start + i * 2
			var i1: int = start + ((i + 1) % sides) * 2
			var ang: float = TAU * (float(i) + 0.5) / float(sides)
			var out: Vector3 = u * cos(ang) + w * sin(ang)
			tri(i0, i1, i0 + 1, out)
			tri(i0 + 1, i1, i1 + 1, out)

	## Нормали вершин с индексом ≥ `v_from` (до текущего конца) подняты на `up` × вверх.
	func lift_normals(v_from: int, up: float) -> void:
		for i in range(v_from, v.size()):
			n[i] = (n[i] + Vector3.UP * up).normalized()

	## Лидер ели: тонкая четырёхгранная пирамида без донца.
	func leader(base: Vector3, tip: Vector3, r: float, col: Color) -> void:
		var start: int = v.size()
		var t0: int = idx.size()
		var top: int = vert(tip, col, 0.5)
		for k in 4:
			var a: float = TAU * float(k) / 4.0 + 0.4
			vert(base + Vector3(cos(a) * r, 0.0, sin(a) * r), col, 0.5)
		for k in 4:
			var a: float = TAU * (float(k) + 0.5) / 4.0 + 0.4
			tri(top, start + 1 + k, start + 1 + (k + 1) % 4, Vector3(cos(a), 0.3, sin(a)))
		smooth(start, t0, 0.3, 0.0, base)

	## Дописать геометрию `other` с номером слота `slot` в UV2.x.
	func append(other: Geo, slot: float) -> void:
		var base: int = v.size()
		v.append_array(other.v)
		n.append_array(other.n)
		c.append_array(other.c)
		for uv in other.f:
			f.append(Vector2(slot, uv.y))
		for i in other.idx:
			idx.append(base + i)

	func to_mesh(material: Material) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		if v.is_empty():
			return mesh
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_TEX_UV2] = f
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if material != null:
			mesh.surface_set_material(0, material)
		return mesh
