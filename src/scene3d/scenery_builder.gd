class_name SceneryBuilder
extends RefCounted
## Растительность и мелкие объекты вдоль трассы (REQ-D3D-07, арт-библия «Мир»): лиственные
## деревья, ели, кусты, пучки сухой травы у бордюра — по одному `MultiMeshInstance3D` на тип,
## с разбросом масштаба, поворота и оттенка (цвет экземпляра). Деревья стоят рощами
## (маска шума) и не ближе `TREE_MIN_ROAD_M` к оси трассы. Меши — из `MeshKit`, один
## тун-материал мира. Всё строится один раз в `set_track()`, детерминированно по seed.
## На длинной трассе каждый тип разбит на куски вдоль трассы с дальностью видимости
## (REQ-D3D-08 п.6, T-066): плотность — на километр, в кадре столько же, сколько на петле.
## Наборы окружения трасс (T-083) добавляют лесополосы тополей (ряды вдоль полей и поперёк),
## низкие каменные изгороди вдоль дороги и долю елей/рощи на возвышенностях. Приморье (T-088):
## хвойные — зонтичные сосны (`EnvironmentSet.conifer_kind`), деревья, кусты и валуны не стоят
## на пляже и в воде (не ниже уровня воды + `shore_clear_m`). Мосты (T-090, `BridgeBuilder.ranges`):
## на мосту и подходе к нему объекты «у дороги» (высота — по полосе травы) не ставятся — под
## полотном долина; пучки травы — только не на мосту и устоях. Хвойные (T-107, `ConiferKit`):
## семь форм с долями по трассам, слой MultiMesh на уровень детализации (по удалению от трассы).

const TREE_MIN_ROAD_M: float = 9.0
const TREE_MAX_OFFSET_M: float = 200.0
## Длина трассы, на которую рассчитаны числа объектов `EnvironmentSet` (петля по умолчанию
## ~2.1 км); на трассе длиннее — пропорционально длине (плотность на километр).
const DENSITY_REFERENCE_M: float = 2200.0
## Звено каменной изгороди, м.
const WALL_SEGMENT_M: float = 4.0
## `EnvironmentSet.tree_line_m` не ниже этого — граница леса выключена.
const TREE_LINE_OFF_M: float = 99999.0
## Слои, которые есть не в каждом наборе окружения (лесополосы, изгороди): `RideScene` держит
## их в отдельном контейнере, чтобы состав корня окружения не зависел от трассы.
const EXTRA_LAYERS: Array[String] = ["Poplars", "StoneWalls", "Boulders", "ConifersLod2"]
## Слои хвойных по уровням детализации (T-107): LOD0 и LOD1 — в каждом мире, LOD2 — только
## если есть деревья дальше `ConiferKit.LOD_FAR_M` от трассы.
const CONIFER_LAYERS: Array[String] = ["Conifers", "ConifersLod1", "ConifersLod2"]
## Тень отбрасывают уровни детализации меньше этого.
const CONIFER_SHADOW_LODS: int = 2

static var _meshes: Dictionary = {}


## Сигнальный столбик (белый, чёрная полоса, световозвращатель) размера `size`.
static func delineator_mesh(size: Vector3, material: Material) -> ArrayMesh:
	var kit := MeshKit.new()
	var h: float = size.y
	var white := Color(0.95, 0.95, 0.93, 0.35)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, h * 0.36, 0.0)), Vector3(size.x, h * 0.72, size.z), white)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, h * 0.82, 0.0)), Vector3(size.x, h * 0.2, size.z), Color(0.08, 0.08, 0.09, 0.35))
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, h * 0.96, 0.0)), Vector3(size.x, h * 0.08, size.z), white)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, h * 0.82, 0.0)), Vector3(size.x * 1.08, h * 0.08, size.z * 1.08), Color(0.95, 0.45, 0.1, 0.0))
	return kit.to_mesh(material)


static func tree_mesh(material: Material) -> ArrayMesh:
	return _cached("tree", material, func(kit: MeshKit) -> void:
		var bark := Color(0.42, 0.31, 0.22, 1.0)
		kit.add_tube(Vector3(0, -0.3, 0), Vector3(0, 2.6, 0), Vector2(0.2, 0.2), Vector2(0.12, 0.12), bark, 7)
		kit.add_tube(Vector3(0, 1.8, 0), Vector3(0.7, 3.0, 0.2), Vector2(0.08, 0.08), Vector2(0.05, 0.05), bark, 5)
		var leaf := Color(0.40, 0.62, 0.24, 1.0)
		var leaf_dark := Color(0.33, 0.54, 0.21, 1.0)
		kit.add_ellipsoid(Vector3(0.0, 3.7, 0.0), Vector3(1.8, 1.5, 1.8), leaf_dark, Basis.IDENTITY, 6, 12)
		kit.add_ellipsoid(Vector3(0.8, 4.4, 0.4), Vector3(1.25, 1.15, 1.25), leaf, Basis.IDENTITY, 6, 10)
		kit.add_ellipsoid(Vector3(-0.7, 4.3, -0.5), Vector3(1.2, 1.1, 1.2), leaf, Basis.IDENTITY, 6, 10)
		kit.add_ellipsoid(Vector3(0.1, 5.1, 0.0), Vector3(1.05, 0.95, 1.05), leaf, Basis.IDENTITY, 6, 10)
	)


## Ель взрослая (LOD0, `ConiferKit`) — для ориентиров; растительность трассы — слои хвойных.
static func conifer_mesh(material: Material) -> ArrayMesh:
	return ConiferKit.single_mesh(ConiferKit.M_SPRUCE, 0, material)


static func bush_mesh(material: Material) -> ArrayMesh:
	return _cached("bush", material, func(kit: MeshKit) -> void:
		var c := Color(0.36, 0.57, 0.22, 0.7)
		kit.add_ellipsoid(Vector3(0.0, 0.45, 0.0), Vector3(0.9, 0.7, 0.85), c.darkened(0.08), Basis.IDENTITY, 5, 10)
		kit.add_ellipsoid(Vector3(0.55, 0.6, 0.2), Vector3(0.6, 0.55, 0.6), c, Basis.IDENTITY, 5, 9)
		kit.add_ellipsoid(Vector3(-0.45, 0.55, -0.25), Vector3(0.55, 0.5, 0.55), c, Basis.IDENTITY, 5, 9)
	)


## Пучок травы: тонкие трёхгранные стебли веером, от зелёного основания к сухим кончикам.
static func tuft_mesh(material: Material) -> ArrayMesh:
	return _cached("tuft", material, func(kit: MeshKit) -> void:
		var blades: int = 7
		for i in blades:
			var ang: float = TAU * float(i) / float(blades) + 0.3 * float(i % 2)
			var lean := Vector3(cos(ang), 0.0, sin(ang)) * (0.10 + 0.05 * float(i % 3))
			var height: float = 0.30 + 0.08 * float((i * 5) % 3)
			var tip: Vector3 = Vector3(0.0, height, 0.0) + lean
			var base_c := Color(0.42, 0.55, 0.22, 0.0)
			var tip_c := Color(0.80, 0.74, 0.44, 0.0)
			var r: float = 0.025
			var b0 := Vector3(cos(ang + 1.6), 0.0, sin(ang + 1.6)) * r
			var b1 := Vector3(cos(ang - 1.6), 0.0, sin(ang - 1.6)) * r
			var b2 := Vector3(cos(ang + PI), 0.0, sin(ang + PI)) * r
			for pair in [[b0, b1], [b1, b2], [b2, b0]]:
				var p0: Vector3 = pair[0]
				var p1: Vector3 = pair[1]
				var n: Vector3 = (p1 - p0).cross(tip - p0).normalized()
				if n.dot((p0 + p1) * 0.5) < 0.0:
					n = -n
				n = (n + Vector3.UP * 0.6).normalized()
				var i0: int = kit.vertices.size()
				kit.vertices.append_array(PackedVector3Array([p0, p1, tip]))
				kit.normals.append_array(PackedVector3Array([n, n, n]))
				kit.colors.append_array(PackedColorArray([MeshKit.lin(base_c), MeshKit.lin(base_c), MeshKit.lin(tip_c)]))
				kit.indices.append_array(PackedInt32Array([i0, i0 + 1, i0 + 2]))
	)


## Тополь-«свеча»: короткий ствол и вытянутая крона из двух эллипсоидов (лесополосы равнины).
static func poplar_mesh(material: Material) -> ArrayMesh:
	return _cached("poplar", material, func(kit: MeshKit) -> void:
		var bark := Color(0.45, 0.38, 0.30, 1.0)
		kit.add_tube(Vector3(0, -0.3, 0), Vector3(0, 2.2, 0), Vector2(0.18, 0.18), Vector2(0.12, 0.12), bark, 6)
		var leaf := Color(0.36, 0.56, 0.24, 1.0)
		var leaf_dark := Color(0.29, 0.47, 0.21, 1.0)
		kit.add_ellipsoid(Vector3(0.0, 5.6, 0.0), Vector3(1.15, 4.4, 1.15), leaf_dark, Basis.IDENTITY, 8, 9)
		kit.add_ellipsoid(Vector3(0.25, 7.4, 0.15), Vector3(0.8, 3.0, 0.8), leaf, Basis.IDENTITY, 7, 8)
	)


## Валун (горы, T-087): неровный низкополигональный камень с гранями (плоские нормали), два
## тона камня, контур; низ — немного ниже нуля (камень «врос» в склон). Размер ~2 × 1.3 × 1.7 м.
static func boulder_mesh(material: Material) -> ArrayMesh:
	return _cached("boulder", material, func(kit: MeshKit) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 9173
		var rings: int = 4
		var segs: int = 7
		var radii := Vector3(1.05, 0.75, 0.85)
		var grid: Array[PackedVector3Array] = []
		for r in rings + 1:
			var phi: float = PI * float(r) / float(rings)
			var row := PackedVector3Array()
			for k in segs:
				var th: float = TAU * (float(k) + 0.5 * float(r % 2)) / float(segs)
				var j: float = rng.randf_range(0.78, 1.18) if r > 0 and r < rings else 1.0
				var unit := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
				var v: Vector3 = unit * radii * j
				v.y = maxf(v.y, -0.35) + 0.25
				row.append(v)
			grid.append(row)
		var light := Color(0.60, 0.59, 0.60, 1.0)
		var dark := Color(0.46, 0.46, 0.50, 1.0)
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
					if n.dot((p0 + p1 + p2) / 3.0 - Vector3(0.0, 0.25, 0.0)) < 0.0:
						n = -n
					kit.add_triangle(p0, p1, p2, n, light if n.y > 0.35 else dark)
	)


## Зонтичная сосна — пиния (LOD0, `ConiferKit`) — для ориентиров; растительность трассы —
## слои хвойных.
static func umbrella_pine_mesh(material: Material) -> ArrayMesh:
	return ConiferKit.single_mesh(ConiferKit.M_PINE, 0, material)


## Звено каменной изгороди длиной `WALL_SEGMENT_M` (ось X), низ — на нуле.
static func wall_mesh(material: Material) -> ArrayMesh:
	return _cached("wall", material, func(kit: MeshKit) -> void:
		# Сухая кладка: нижний ряд из трёх камней, верхний — из пяти разной высоты, два тона.
		var tones: Array[Color] = [Color(0.66, 0.64, 0.59, 0.3), Color(0.56, 0.55, 0.52, 0.3), Color(0.72, 0.70, 0.64, 0.3)]
		var base_w: float = WALL_SEGMENT_M / 3.0
		for i in 3:
			var h: float = 0.42 + 0.06 * float(i % 2)
			kit.add_box(Transform3D(Basis.IDENTITY, Vector3(-WALL_SEGMENT_M * 0.5 + base_w * (float(i) + 0.5), h * 0.5 - 0.15, 0.0)),
				Vector3(base_w + 0.02, h + 0.3, 0.6), tones[i % 3])
		var top_w: float = WALL_SEGMENT_M / 5.0
		for i in 5:
			var h: float = 0.22 + 0.07 * float((i * 3) % 4)
			kit.add_box(Transform3D(Basis.IDENTITY, Vector3(-WALL_SEGMENT_M * 0.5 + top_w * (float(i) + 0.5), 0.36 + h * 0.5, 0.0)),
				Vector3(top_w - 0.04, h, 0.5 - 0.04 * float(i % 2)), tones[(i + 1) % 3])
	)


static func _cached(key: String, material: Material, build: Callable) -> ArrayMesh:
	var full_key: String = "%s:%d" % [key, material.get_instance_id() if material != null else 0]
	if _meshes.has(full_key):
		return _meshes[full_key]
	var kit := MeshKit.new()
	build.call(kit)
	var mesh := kit.to_mesh(material)
	_meshes[full_key] = mesh
	return mesh


## Построить узлы растительности: по узлу на тип (лиственные, ели, кусты, трава). На
## длинной трассе (не компактной, `PerfBudget.chunk_length_m`) каждый тип разбит на куски
## вдоль трассы с `visibility_range_end`; кусок 0 — узел типа, остальные — его дети.
## Числа `EnvironmentSet` заданы на петлю длиной до `DENSITY_REFERENCE_M`; на длинной
## трассе — пропорционально длине (плотность на километр), но не больше `total_budget`
## всего. `budget` — сколько экземпляров MultiMesh осталось на видимое из любой точки
## трассы: если видно больше, каждый кусок прореживается одинаково. `field` может быть
## null (рельеф выключен) — тогда высота берётся у дороги.
static func build(track: Track, env: EnvironmentSet, field: TerrainField, material: Material, budget: int,
		total_budget: int = PerfBudget.MAX_MULTIMESH_INSTANCES, keep_out: LandmarkBuilder.KeepOut = null) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	for layer in place(track, env, field, material, budget, total_budget, keep_out):
		var node: MultiMeshInstance3D = chunked_multimesh(layer.name, layer.mesh, layer.xf, layer.col, layer.chunk, layer.chunks,
			layer.range_m if layer.chunks > 1 else 0.0, layer.keep, layer.custom, layer.tris)
		if not layer.shadow:
			for part: GeometryInstance3D in [node] + node.get_children():
				part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		out.append(node)
	return out


## Расстановка без узлов (данные `build`): слои — лиственные, ели, кусты, трава; у слоя
## трансформы и цвета экземпляров, кусок каждого и доля `keep`, которая останется в каждом
## куске. Позиции экземпляров готовых MultiMesh на headless-сервере недоступны — тесты
## проверяют расстановку здесь. `keep_out` — пятна ориентиров (`LandmarkBuilder.keep_out`):
## деревья, кусты, лесополосы и изгороди туда не ставятся.
static func place(track: Track, env: EnvironmentSet, field: TerrainField, material: Material, budget: int,
		total_budget: int = PerfBudget.MAX_MULTIMESH_INSTANCES, keep_out: LandmarkBuilder.KeepOut = null) -> Array[Layer]:
	var ko: LandmarkBuilder.KeepOut = keep_out if keep_out != null and not keep_out.is_empty() else null
	var chunk_m: float = PerfBudget.chunk_length_m(track)
	var chunks: int = PerfBudget.chunk_count(track, chunk_m)
	var length: float = track.length_m()
	var per_length: float = maxf(1.0, length / DENSITY_REFERENCE_M)
	var wanted: int = int((maxi(env.tree_count, 0) + maxi(env.bush_count, 0) + maxi(env.tuft_count, 0)
		+ maxi(env.boulder_count, 0)) * per_length)
	var cap: int = maxi(total_budget, 0)
	# Компактный мир виден целиком — урезается заранее; на длинной трассе видимое
	# считается после расстановки по кускам.
	if chunks == 1:
		cap = mini(cap, maxi(budget, 0))
	# Лесополосы и изгороди (своя последовательность случайных чисел — расстановка рощ
	# от них не зависит); их экземпляры вычитаются из потолка растительности.
	var poplars := Layer.new("Poplars", poplar_mesh(material), PerfBudget.RANGE_TREES_M, chunks)
	var extra_rng := RandomNumberGenerator.new()
	extra_rng.seed = env.scenery_seed + 17
	_place_windbreaks(poplars, track, env, field, extra_rng, chunk_m, chunks, cap / 4, ko)
	var walls := Layer.new("StoneWalls", wall_mesh(material), PerfBudget.RANGE_BUSHES_M, chunks)
	_place_walls(walls, track, env, field, chunk_m, chunks, cap / 8, ko)
	cap = maxi(cap - poplars.xf.size() - walls.xf.size(), 0)
	var scale: float = per_length if wanted <= cap else per_length * float(cap) / float(maxi(wanted, 1))
	var n_trees: int = int(env.tree_count * scale)
	var n_bushes: int = int(env.bush_count * scale)
	var n_tufts: int = int(env.tuft_count * scale)
	var n_boulders: int = int(maxi(env.boulder_count, 0) * scale)
	var rng := RandomNumberGenerator.new()
	rng.seed = env.scenery_seed
	var forest := FastNoiseLite.new()
	forest.seed = env.scenery_seed + 7
	forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	forest.frequency = 1.0 / 140.0
	var curb_out: float = RoadsideBuilder.curb_outer_m(env.road_width_m)
	var verge_w: float = RoadsideBuilder.verge_width_m(env.road_width_m)
	var bridges: PackedVector2Array = BridgeBuilder.ranges(track)
	var sample := TrackSample.new()
	var trees := Layer.new("Trees", tree_mesh(material), PerfBudget.RANGE_TREES_M, chunks)
	# Хвойные: точки рощ здесь, формы, уровни и вариации — `ConiferKit.plant` после расстановки.
	var plants: Array[ConiferKit.Plant] = []
	# Берег (приморье): не на пляже и не в воде.
	var dry_y: float = shore_line_y(env, field)
	var bushes := Layer.new("Bushes", bush_mesh(material), PerfBudget.RANGE_BUSHES_M, chunks)
	var tufts := Layer.new("Tufts", tuft_mesh(material), PerfBudget.RANGE_TUFTS_M, chunks)
	# Деревья: лиственные и ели — рощами по маске шума.
	var attempts: int = n_trees * 8
	while attempts > 0 and trees.xf.size() + plants.size() < n_trees:
		attempts -= 1
		var s: float = rng.randf() * length
		var sgn: float = -1.0 if rng.randf() < 0.5 else 1.0
		var near_row: bool = rng.randf() < 0.4
		var w: float = (curb_out + 4.5 + rng.randf() * 14.0) if near_row else (TREE_MIN_ROAD_M + 4.0 + pow(rng.randf(), 1.8) * TREE_MAX_OFFSET_M)
		if _on_bridge_verge(bridges, s, w, verge_w):
			continue
		track.sample_into(s, sample)
		var right: Vector3 = sample.right()
		var c: Vector3 = sample.position + right * env.road_center_offset_m
		var p: Vector3 = c + right * sgn * w + sample.forward * rng.randf_range(-3.0, 3.0)
		var mask: float = forest.get_noise_2d(p.x, p.z) * 0.5 + 0.5
		if not near_row and rng.randf() > mask * mask * 1.6:
			continue
		if not near_row and env.tree_hilltop_bias > 0.0 and field != null:
			var rise: float = field.height_at(p.x, p.z) - sample.position.y
			if rng.randf() > lerpf(1.0, smoothstep(-4.0, 22.0, rise), env.tree_hilltop_bias):
				continue
		if field != null and field.road_distance_at(p.x, p.z) < TREE_MIN_ROAD_M + absf(env.road_center_offset_m):
			continue
		if ko != null and ko.blocks(p.x, p.z, 2.0):
			continue
		var y: float = _ground_y(p, w, sample.position.y, env.road_width_m, verge_w, field)
		if y < dry_y:
			continue
		# Граница леса (горы): выше неё деревьев нет, кромка неровная.
		if env.tree_line_m < TREE_LINE_OFF_M and y > env.tree_line_m - 45.0 * rng.randf():
			continue
		var sc: float = rng.randf_range(0.75, 1.35)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.15), sc))
		var xf := Transform3D(basis, Vector3(p.x, y - 0.1, p.z))
		var conifer: bool = forest.get_noise_2d(p.x + 913.0, p.z - 377.0) > env.conifer_threshold
		var shade: float = rng.randf_range(0.85, 1.12)
		var chunk: int = PerfBudget.chunk_of(s, chunk_m, chunks)
		if conifer:
			# Тот же расход случайных чисел, что у лиственного: расстановка рощ не зависит от форм.
			rng.randf_range(0.95, 1.05)
			var cp := ConiferKit.Plant.new()
			cp.origin = xf.origin
			cp.s = s
			cp.chunk = chunk
			# Удаление от ближайшей точки трассы: не больше, чем от своей точки выборки; ближе к
			# соседнему витку серпантина — по полю расстояний рельефа (точно ближе `near_radius_m`).
			cp.road_m = absf(sgn * w + env.road_center_offset_m)
			if field != null:
				cp.road_m = minf(cp.road_m, field.road_distance_at(p.x, p.z))
			plants.append(cp)
		else:
			trees.add(xf, Color(shade * rng.randf_range(0.95, 1.12), shade, shade * 0.9, 1.0), chunk)
	# Кусты: у кювета и в поле.
	attempts = n_bushes * 6
	while attempts > 0 and bushes.xf.size() < n_bushes:
		attempts -= 1
		var s: float = rng.randf() * length
		var sgn: float = -1.0 if rng.randf() < 0.5 else 1.0
		var w: float = curb_out + 3.2 + pow(rng.randf(), 2.0) * 40.0
		if _on_bridge_verge(bridges, s, w, verge_w):
			continue
		track.sample_into(s, sample)
		var right: Vector3 = sample.right()
		var p: Vector3 = sample.position + right * (env.road_center_offset_m + sgn * w)
		if field != null and field.road_distance_at(p.x, p.z) < curb_out + 2.5:
			continue
		if ko != null and ko.blocks(p.x, p.z, 1.0):
			continue
		var y: float = _ground_y(p, w, sample.position.y, env.road_width_m, verge_w, field)
		if y < dry_y:
			continue
		var sc: float = rng.randf_range(0.6, 1.3)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.8, 1.1), sc))
		var shade: float = rng.randf_range(0.85, 1.15)
		bushes.add(Transform3D(basis, Vector3(p.x, y - 0.08, p.z)), Color(shade, shade, shade * 0.95, 1.0),
			PerfBudget.chunk_of(s, chunk_m, chunks))
	# Пучки травы: 85 % — вдоль бордюра (мелькают у края кадра), остальное — по обочине.
	for i in n_tufts:
		var s: float = rng.randf() * length
		var sgn: float = -1.0 if rng.randf() < 0.5 else 1.0
		var w: float = (curb_out + rng.randf_range(0.05, 0.9)) if rng.randf() < 0.85 else (curb_out + rng.randf_range(1.0, 9.0))
		if BridgeBuilder.in_ranges(bridges, s, BridgeBuilder.ABUT_BACK_M):
			continue
		track.sample_into(s, sample)
		var right: Vector3 = sample.right()
		var p: Vector3 = sample.position + right * (env.road_center_offset_m + sgn * w)
		var y: float = sample.position.y + RoadsideBuilder.verge_height(w, env.road_width_m)
		var sc: float = rng.randf_range(0.7, 1.6)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.8, 1.3), sc))
		var dry: float = rng.randf()
		tufts.add(Transform3D(basis, Vector3(p.x, y - 0.02, p.z)), Color(1.0 + dry * 0.15, 1.0, 1.0 - dry * 0.2, 1.0),
			PerfBudget.chunk_of(s, chunk_m, chunks))
	var boulders := Layer.new("Boulders", boulder_mesh(material), PerfBudget.RANGE_BUSHES_M, chunks)
	_place_boulders(boulders, track, env, field, n_boulders, chunk_m, chunks, ko)
	var conifers: Array[Layer] = conifer_layers(plants, env, field, material, chunks)
	var layers: Array[Layer] = [trees, conifers[0], conifers[1], bushes, tufts]
	for extra in [conifers[2], poplars, walls, boulders]:
		if not (extra as Layer).xf.is_empty():
			layers.append(extra)
	if chunks > 1:
		var seen: int = _max_visible(layers, chunks, track)
		if seen > budget:
			for layer in layers:
				layer.keep = float(maxi(budget, 0)) / float(seen)
	return layers


## Слои хвойных (T-107, арт-библия «Уровни детализации»): по слою на уровень детализации —
## `CONIFER_LAYERS[lod]`; уровень экземпляра назначен при расстановке по удалению от трассы, в
## кадре ничего не переключается. Меш слоя несёт все формы трассы этого уровня
## (`ConiferKit.layer_mesh`), форма экземпляра — данные экземпляра (слот модели). Тень
## отбрасывают уровни меньше `CONIFER_SHADOW_LODS`: тень солнца — до 90 м от камеры, а камера
## всегда у дороги.
static func conifer_layers(plants: Array[ConiferKit.Plant], env: EnvironmentSet, field: TerrainField,
		material: Material, chunks: int) -> Array[Layer]:
	ConiferKit.plant(plants, env, field)
	var forms: PackedInt32Array = ConiferKit.mix_forms(ConiferKit.form_mix(env))
	var out: Array[Layer] = []
	var models: Array[PackedInt32Array] = []
	for lod in ConiferKit.LOD_COUNT:
		var mods: PackedInt32Array = ConiferKit.models_for(forms, lod)
		models.append(mods)
		var layer := Layer.new(CONIFER_LAYERS[lod], ConiferKit.layer_mesh(mods, lod, material), PerfBudget.RANGE_TREES_M, chunks)
		layer.shadow = lod < CONIFER_SHADOW_LODS
		out.append(layer)
	for cp in plants:
		var layer: Layer = out[cp.lod]
		var mods: PackedInt32Array = models[cp.lod]
		var model: int = ConiferKit.model_of(cp.form, cp.lod)
		layer.add(cp.transform(env.conifer_scale), cp.color(env.conifer_shade), cp.chunk)
		if mods.size() > 1:
			layer.custom.append(Color(float(mods.find(model)), 0.0, 0.0, 0.0))
		layer.tris.append(ConiferKit.triangles(model, cp.lod))
		layer.plants.append(cp)
	return out


## Валуны (горы): вдоль трассы на склонах — у дороги (осыпь под скальной стенкой) и в поле,
## дальше от дороги — крупнее; не на дороге и не в пятнах ориентиров. Своя последовательность
## случайных чисел (расстановка остальных слоёв от валунов не зависит).
static func _place_boulders(layer: Layer, track: Track, env: EnvironmentSet, field: TerrainField, count: int,
		chunk_m: float, chunks: int, ko: LandmarkBuilder.KeepOut = null) -> void:
	if count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = env.scenery_seed + 41
	var length: float = track.length_m()
	var sample := TrackSample.new()
	var curb_out: float = RoadsideBuilder.curb_outer_m(env.road_width_m)
	var verge_w: float = RoadsideBuilder.verge_width_m(env.road_width_m)
	var attempts: int = count * 4
	while attempts > 0 and layer.xf.size() < count:
		attempts -= 1
		var s: float = rng.randf() * length
		var sgn: float = -1.0 if rng.randf() < 0.5 else 1.0
		var far: float = pow(rng.randf(), 1.6)
		var w: float = curb_out + 4.0 + far * 160.0
		track.sample_into(s, sample)
		var p: Vector3 = sample.position + sample.right() * (env.road_center_offset_m + sgn * w) + sample.forward * rng.randf_range(-3.0, 3.0)
		if field != null and field.road_distance_at(p.x, p.z) < curb_out + 3.5:
			continue
		if ko != null and ko.blocks(p.x, p.z, 1.5):
			continue
		var y: float = _ground_y(p, w, sample.position.y, env.road_width_m, verge_w, field)
		if y < shore_line_y(env, field):
			continue
		var sc: float = rng.randf_range(0.45, 1.0) * lerpf(1.0, 2.6, far)
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
		basis = basis.scaled(Vector3(sc, sc * rng.randf_range(0.7, 1.15), sc * rng.randf_range(0.8, 1.2)))
		var shade: float = rng.randf_range(0.86, 1.1)
		layer.add(Transform3D(basis, Vector3(p.x, y - 0.15 * sc, p.z)), Color(shade, shade, shade * rng.randf_range(0.97, 1.04), 1.0),
			PerfBudget.chunk_of(s, chunk_m, chunks))


## Лесополосы: ряды тополей вдоль дороги (по её изгибу, на постоянном удалении) и поперёк
## (от дороги в поле). Не ближе `TREE_MIN_ROAD_M` к любой части трассы; не больше `limit`.
static func _place_windbreaks(layer: Layer, track: Track, env: EnvironmentSet, field: TerrainField,
		rng: RandomNumberGenerator, chunk_m: float, chunks: int, limit: int, ko: LandmarkBuilder.KeepOut = null) -> void:
	var rows: int = int(round(maxf(env.windbreak_rows_per_km, 0.0) * track.length_m() / 1000.0))
	if rows <= 0 or env.windbreak_spacing_m <= 0.5:
		return
	var length: float = track.length_m()
	var sample := TrackSample.new()
	var curb_out: float = RoadsideBuilder.curb_outer_m(env.road_width_m)
	var verge_w: float = RoadsideBuilder.verge_width_m(env.road_width_m)
	var min_road: float = maxf(TREE_MIN_ROAD_M + absf(env.road_center_offset_m), curb_out + 6.0)
	for r in rows:
		var s0: float = rng.randf() * length
		var sgn: float = -1.0 if rng.randf() < 0.5 else 1.0
		var w0: float = rng.randf_range(env.windbreak_offset_m.x, env.windbreak_offset_m.y)
		var row_len: float = rng.randf_range(env.windbreak_length_m.x, env.windbreak_length_m.y)
		var along: bool = rng.randf() < 0.65
		var n: int = int(row_len / env.windbreak_spacing_m)
		track.sample_into(s0, sample)
		var base: Vector3 = sample.position + sample.right() * env.road_center_offset_m
		var out_dir: Vector3 = sample.right() * sgn
		for i in n:
			if layer.xf.size() >= limit:
				return
			var t: float = float(i) * env.windbreak_spacing_m + rng.randf_range(-0.8, 0.8)
			var s: float = s0
			var p: Vector3
			var w: float = w0
			if along:
				s = fposmod(s0 + t, length) if track.is_loop() else clampf(s0 + t, 0.0, length)
				track.sample_into(s, sample)
				p = sample.position + sample.right() * (env.road_center_offset_m + sgn * w0)
			else:
				w = w0 + t
				p = base + out_dir * w
			p += Vector3(rng.randf_range(-0.6, 0.6), 0.0, rng.randf_range(-0.6, 0.6))
			if field != null and field.road_distance_at(p.x, p.z) < min_road:
				continue
			if ko != null and ko.blocks(p.x, p.z, 1.5):
				continue
			var y: float = _ground_y(p, w, sample.position.y, env.road_width_m, verge_w, field)
			var sc: float = rng.randf_range(0.8, 1.2)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.2), sc))
			var shade: float = rng.randf_range(0.88, 1.1)
			layer.add(Transform3D(basis, Vector3(p.x, y - 0.1, p.z)), Color(shade, shade, shade * 0.92, 1.0),
				PerfBudget.chunk_of(s, chunk_m, chunks))


## Каменные изгороди: звенья по `WALL_SEGMENT_M` на удалении `stone_wall_offset_m` от оси
## дороги, участками (маска шума вдоль трассы, доля `stone_wall_share`), сторона участка — по
## знаку второй маски; звено наклонено по рельефу.
static func _place_walls(layer: Layer, track: Track, env: EnvironmentSet, field: TerrainField,
		chunk_m: float, chunks: int, limit: int, ko: LandmarkBuilder.KeepOut = null) -> void:
	if env.stone_wall_share <= 0.0:
		return
	var length: float = track.length_m()
	var noise := FastNoiseLite.new()
	noise.seed = env.scenery_seed + 31
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / 260.0
	var verge_w: float = RoadsideBuilder.verge_width_m(env.road_width_m)
	var a := TrackSample.new()
	var b := TrackSample.new()
	var n: int = int(length / WALL_SEGMENT_M)
	# Порог маски — квантиль значений шума по звеньям: изгородь занимает долю `stone_wall_share`.
	var values := PackedFloat32Array()
	values.resize(n)
	for i in n:
		values[i] = noise.get_noise_1d(float(i) * WALL_SEGMENT_M)
	var sorted_values := values.duplicate()
	sorted_values.sort()
	var threshold: float = sorted_values[clampi(int(float(n) * (1.0 - clampf(env.stone_wall_share, 0.0, 1.0))), 0, maxi(n - 1, 0))] if n > 0 else 1.0
	var w: float = env.stone_wall_offset_m
	for i in n:
		if layer.xf.size() >= limit:
			return
		var s0: float = float(i) * WALL_SEGMENT_M
		if values[i] < threshold:
			continue
		var sgn: float = 1.0 if noise.get_noise_1d(s0 + 5000.0) >= 0.0 else -1.0
		track.sample_into(s0, a)
		track.sample_into(minf(s0 + WALL_SEGMENT_M, length), b)
		var p0: Vector3 = a.position + a.right() * (env.road_center_offset_m + sgn * w)
		var p1: Vector3 = b.position + b.right() * (env.road_center_offset_m + sgn * w)
		if field != null and minf(field.road_distance_at(p0.x, p0.z), field.road_distance_at(p1.x, p1.z)) < w - absf(env.road_center_offset_m) - 1.0:
			continue
		if ko != null and (ko.blocks(p0.x, p0.z) or ko.blocks(p1.x, p1.z)):
			continue
		p0.y = _ground_y(p0, w, a.position.y, env.road_width_m, verge_w, field) - 0.12
		p1.y = _ground_y(p1, w, b.position.y, env.road_width_m, verge_w, field) - 0.12
		var x: Vector3 = p1 - p0
		if x.length_squared() < 1e-4:
			continue
		var xs: float = x.length() / WALL_SEGMENT_M
		x = x.normalized()
		var z: Vector3 = x.cross(Vector3.UP).normalized()
		var y: Vector3 = z.cross(x).normalized()
		var shade: float = 0.9 + 0.16 * absf(values[(i * 7) % n])
		layer.add(Transform3D(Basis(x * xs, y, z), (p0 + p1) * 0.5), Color(shade, shade, shade), PerfBudget.chunk_of(s0, chunk_m, chunks))


## Ниже этой высоты деревья, кусты и валуны не ставятся: уровень воды + `shore_clear_m` (пляж и
## вода); без воды — без ограничения.
static func shore_line_y(env: EnvironmentSet, field: TerrainField) -> float:
	if field == null or not field.has_water():
		return -INF
	return field.water_level + maxf(env.shore_clear_m, 0.0)


## Объект у дороги с высотой по полосе травы (`_ground_y`) на мосту или подходе: под ним нет земли.
static func _on_bridge_verge(bridges: PackedVector2Array, s: float, w: float, verge_w: float) -> bool:
	return not bridges.is_empty() and w < verge_w - 1.5 and BridgeBuilder.in_ranges(bridges, s, BridgeBuilder.APPROACH_M)


static func _ground_y(p: Vector3, w: float, road_y: float, road_width: float, verge_w: float, field: TerrainField) -> float:
	if w < verge_w - 1.5 or field == null:
		return road_y + RoadsideBuilder.verge_height(w, road_width)
	return field.height_at(p.x, p.z)


## Экземпляры одного типа объектов до разбиения на куски: `chunk[i]` — кусок экземпляра i
## из `chunks`; в каждом куске останется доля `keep` (первые по порядку расстановки).
class Layer:
	var name: String
	var mesh: Mesh
	var range_m: float
	var chunks: int
	var keep: float = 1.0
	var xf: Array[Transform3D] = []
	var col: Array[Color] = []
	var chunk := PackedInt32Array()
	## Данные экземпляра (`INSTANCE_CUSTOM`): пусто — без них (хвойные — слот формы в меше слоя).
	var custom: Array[Color] = []
	## Треугольников экземпляра (хвойные; пусто — не считаются).
	var tris := PackedInt32Array()
	## Хвойные: форма, уровень и вариации каждого экземпляра (для тестов и замеров).
	var plants: Array[ConiferKit.Plant] = []
	## Слой отбрасывает тень.
	var shadow: bool = true

	func _init(node_name: String, layer_mesh: Mesh, visible_m: float, chunk_total: int) -> void:
		name = node_name
		mesh = layer_mesh
		range_m = visible_m
		chunks = chunk_total

	func add(t: Transform3D, c: Color, chunk_index: int) -> void:
		xf.append(t)
		col.append(c)
		chunk.append(chunk_index)

	## Индексы экземпляров, которые попадут в узлы (с учётом `keep`).
	func kept() -> PackedInt32Array:
		var out := PackedInt32Array()
		var per_chunk := PackedInt32Array()
		per_chunk.resize(maxi(chunks, 1))
		for i in xf.size():
			per_chunk[chunk[i] if chunks > 1 else 0] += 1
		var limit := PackedInt32Array()
		limit.resize(per_chunk.size())
		for k in per_chunk.size():
			limit[k] = per_chunk[k] if keep >= 1.0 else int(float(per_chunk[k]) * maxf(keep, 0.0))
		var used := PackedInt32Array()
		used.resize(per_chunk.size())
		for i in xf.size():
			var k: int = chunk[i] if chunks > 1 else 0
			if used[k] < limit[k]:
				used[k] += 1
				out.append(i)
		return out


## Максимум видимых экземпляров по точкам трассы (шаг `PerfBudget.CHECK_STEP_M`) — по
## центрам кусков, как `PerfBudget.visible_multimesh_instances` по готовым узлам.
static func _max_visible(layers: Array[Layer], chunks: int, track: Track) -> int:
	var centers := PackedVector3Array()
	var counts := PackedInt32Array()
	var ranges := PackedFloat32Array()
	for layer in layers:
		var lo := PackedVector3Array()
		var hi := PackedVector3Array()
		var n := PackedInt32Array()
		lo.resize(chunks)
		hi.resize(chunks)
		n.resize(chunks)
		lo.fill(Vector3(INF, INF, INF))
		hi.fill(Vector3(-INF, -INF, -INF))
		for i in layer.xf.size():
			var k: int = layer.chunk[i]
			var p: Vector3 = layer.xf[i].origin
			lo[k] = lo[k].min(p)
			hi[k] = hi[k].max(p)
			n[k] += 1
		for k in chunks:
			if n[k] > 0:
				centers.append((lo[k] + hi[k]) * 0.5)
				counts.append(n[k])
				ranges.append(layer.range_m + PerfBudget.RANGE_MARGIN_M + PerfBudget.EYE_SLACK_M)
	var length: float = track.length_m()
	var steps: int = maxi(int(ceil(length / PerfBudget.CHECK_STEP_M)), 1)
	var sample := TrackSample.new()
	var best: int = 0
	for i in steps:
		track.sample_into(minf(float(i) * PerfBudget.CHECK_STEP_M, length), sample)
		var seen: int = 0
		for j in centers.size():
			if sample.position.distance_to(centers[j]) <= ranges[j]:
				seen += counts[j]
		best = maxi(best, seen)
	return best


## Узел типа объектов, разбитый на `chunks` кусков: кусок 0 — сам узел (имя `node_name`),
## остальные — его дети (`<имя>_<k>`; пустые не создаются). У каждого куска `custom_aabb`
## по позициям экземпляров (центр AABB — точка отсчёта дальности видимости); `range_m` > 0 —
## дальность видимости куска. `keep` < 1 — в каждом куске остаётся эта доля экземпляров
## (первые по порядку расстановки; порядок случайный — прореживание равномерное).
## `cols` пустой — без цвета экземпляра; `customs` — данные экземпляра (пусто — без них);
## `tris` — треугольников экземпляра: сумма по куску — в метаданных узла `triangles`.
static func chunked_multimesh(node_name: String, mesh: Mesh, xforms: Array[Transform3D], cols: Array[Color],
		chunk: PackedInt32Array, chunks: int, range_m: float, keep: float = 1.0, customs: Array[Color] = [],
		tris: PackedInt32Array = PackedInt32Array()) -> MultiMeshInstance3D:
	var buckets: Array[PackedInt32Array] = []
	buckets.resize(maxi(chunks, 1))
	for i in xforms.size():
		var k: int = chunk[i] if chunks > 1 else 0
		buckets[k].append(i)
	var pad: float = mesh.get_aabb().size.length() if mesh != null else 1.0
	var root: MultiMeshInstance3D = null
	for k in buckets.size():
		var idx: PackedInt32Array = buckets[k]
		var n: int = idx.size() if keep >= 1.0 else int(float(idx.size()) * maxf(keep, 0.0))
		if k > 0 and n == 0:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = not cols.is_empty()
		mm.use_custom_data = not customs.is_empty()
		mm.mesh = mesh
		mm.instance_count = n
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var tri_sum: int = 0
		for j in n:
			var t: Transform3D = xforms[idx[j]]
			mm.set_instance_transform(j, t)
			if mm.use_colors:
				mm.set_instance_color(j, MeshKit.lin(cols[idx[j]]))
			if mm.use_custom_data:
				mm.set_instance_custom_data(j, customs[idx[j]])
			if not tris.is_empty():
				tri_sum += tris[idx[j]]
			lo = lo.min(t.origin)
			hi = hi.max(t.origin)
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		if not tris.is_empty():
			# Треугольников куска без контура (хвойные: только формы своих экземпляров).
			node.set_meta(&"triangles", tri_sum)
		if n > 0:
			var half := Vector3.ONE * pad
			mm.custom_aabb = AABB(lo - half, (hi - lo) + half * 2.0)
			if range_m > 0.0:
				node.visibility_range_end = range_m
				node.visibility_range_end_margin = PerfBudget.RANGE_MARGIN_M
		if k == 0:
			node.name = node_name
			root = node
		else:
			node.name = "%s_%02d" % [node_name, k]
			root.add_child(node)
	return root
