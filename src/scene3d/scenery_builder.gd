class_name SceneryBuilder
extends RefCounted
## Растительность и мелкие объекты вдоль трассы (REQ-D3D-07, арт-библия «Мир»): лиственные
## деревья, ели, кусты, пучки сухой травы у бордюра — по одному `MultiMeshInstance3D` на тип,
## с разбросом масштаба, поворота и оттенка (цвет экземпляра). Деревья стоят рощами
## (маска шума) и не ближе `TREE_MIN_ROAD_M` к оси трассы. Меши — из `MeshKit`, один
## тун-материал мира. Всё строится один раз в `set_track()`, детерминированно по seed.
## На длинной трассе каждый тип разбит на куски вдоль трассы с дальностью видимости
## (REQ-D3D-08 п.6, T-066): плотность — на километр, в кадре столько же, сколько на петле.

const TREE_MIN_ROAD_M: float = 9.0
const TREE_MAX_OFFSET_M: float = 200.0
## Длина трассы, на которую рассчитаны числа объектов `EnvironmentSet` (петля по умолчанию
## ~2.1 км); на трассе длиннее — пропорционально длине (плотность на километр).
const DENSITY_REFERENCE_M: float = 2200.0

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


static func conifer_mesh(material: Material) -> ArrayMesh:
	return _cached("conifer", material, func(kit: MeshKit) -> void:
		kit.add_tube(Vector3(0, -0.3, 0), Vector3(0, 1.4, 0), Vector2(0.16, 0.16), Vector2(0.12, 0.12), Color(0.38, 0.28, 0.2, 1.0), 6)
		var c := Color(0.20, 0.42, 0.25, 1.0)
		kit.add_cone(Vector3(0, 1.0, 0), 3.2, 1.7, c, 9)
		kit.add_cone(Vector3(0, 2.7, 0), 2.8, 1.3, c.lightened(0.05), 9)
		kit.add_cone(Vector3(0, 4.2, 0), 2.6, 0.95, c.lightened(0.1), 9)
	)


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
		total_budget: int = PerfBudget.MAX_MULTIMESH_INSTANCES) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	for layer in place(track, env, field, material, budget, total_budget):
		out.append(chunked_multimesh(layer.name, layer.mesh, layer.xf, layer.col, layer.chunk, layer.chunks,
			layer.range_m if layer.chunks > 1 else 0.0, layer.keep))
	return out


## Расстановка без узлов (данные `build`): слои — лиственные, ели, кусты, трава; у слоя
## трансформы и цвета экземпляров, кусок каждого и доля `keep`, которая останется в каждом
## куске. Позиции экземпляров готовых MultiMesh на headless-сервере недоступны — тесты
## проверяют расстановку здесь.
static func place(track: Track, env: EnvironmentSet, field: TerrainField, material: Material, budget: int,
		total_budget: int = PerfBudget.MAX_MULTIMESH_INSTANCES) -> Array[Layer]:
	var chunk_m: float = PerfBudget.chunk_length_m(track)
	var chunks: int = PerfBudget.chunk_count(track, chunk_m)
	var length: float = track.length_m()
	var per_length: float = maxf(1.0, length / DENSITY_REFERENCE_M)
	var wanted: int = int((maxi(env.tree_count, 0) + maxi(env.bush_count, 0) + maxi(env.tuft_count, 0)) * per_length)
	var cap: int = maxi(total_budget, 0)
	# Компактный мир виден целиком — урезается заранее; на длинной трассе видимое
	# считается после расстановки по кускам.
	if chunks == 1:
		cap = mini(cap, maxi(budget, 0))
	var scale: float = per_length if wanted <= cap else per_length * float(cap) / float(maxi(wanted, 1))
	var n_trees: int = int(env.tree_count * scale)
	var n_bushes: int = int(env.bush_count * scale)
	var n_tufts: int = int(env.tuft_count * scale)
	var rng := RandomNumberGenerator.new()
	rng.seed = env.scenery_seed
	var forest := FastNoiseLite.new()
	forest.seed = env.scenery_seed + 7
	forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	forest.frequency = 1.0 / 140.0
	var curb_out: float = RoadsideBuilder.curb_outer_m(env.road_width_m)
	var verge_w: float = RoadsideBuilder.verge_width_m(env.road_width_m)
	var sample := TrackSample.new()
	var trees := Layer.new("Trees", tree_mesh(material), PerfBudget.RANGE_TREES_M, chunks)
	var pines := Layer.new("Conifers", conifer_mesh(material), PerfBudget.RANGE_TREES_M, chunks)
	var bushes := Layer.new("Bushes", bush_mesh(material), PerfBudget.RANGE_BUSHES_M, chunks)
	var tufts := Layer.new("Tufts", tuft_mesh(material), PerfBudget.RANGE_TUFTS_M, chunks)
	# Деревья: лиственные и ели — рощами по маске шума.
	var attempts: int = n_trees * 8
	while attempts > 0 and trees.xf.size() + pines.xf.size() < n_trees:
		attempts -= 1
		var s: float = rng.randf() * length
		var sgn: float = -1.0 if rng.randf() < 0.5 else 1.0
		var near_row: bool = rng.randf() < 0.4
		var w: float = (curb_out + 4.5 + rng.randf() * 14.0) if near_row else (TREE_MIN_ROAD_M + 4.0 + pow(rng.randf(), 1.8) * TREE_MAX_OFFSET_M)
		track.sample_into(s, sample)
		var right: Vector3 = sample.right()
		var c: Vector3 = sample.position + right * env.road_center_offset_m
		var p: Vector3 = c + right * sgn * w + sample.forward * rng.randf_range(-3.0, 3.0)
		var mask: float = forest.get_noise_2d(p.x, p.z) * 0.5 + 0.5
		if not near_row and rng.randf() > mask * mask * 1.6:
			continue
		if field != null and field.road_distance_at(p.x, p.z) < TREE_MIN_ROAD_M + absf(env.road_center_offset_m):
			continue
		var y: float = _ground_y(p, w, sample.position.y, env.road_width_m, verge_w, field)
		var sc: float = rng.randf_range(0.75, 1.35)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.15), sc))
		var xf := Transform3D(basis, Vector3(p.x, y - 0.1, p.z))
		var conifer: bool = forest.get_noise_2d(p.x + 913.0, p.z - 377.0) > 0.15
		var shade: float = rng.randf_range(0.85, 1.12)
		var chunk: int = PerfBudget.chunk_of(s, chunk_m, chunks)
		if conifer:
			pines.add(xf, Color(shade, shade, shade * rng.randf_range(0.95, 1.05), 1.0), chunk)
		else:
			trees.add(xf, Color(shade * rng.randf_range(0.95, 1.12), shade, shade * 0.9, 1.0), chunk)
	# Кусты: у кювета и в поле.
	attempts = n_bushes * 6
	while attempts > 0 and bushes.xf.size() < n_bushes:
		attempts -= 1
		var s: float = rng.randf() * length
		var sgn: float = -1.0 if rng.randf() < 0.5 else 1.0
		var w: float = curb_out + 3.2 + pow(rng.randf(), 2.0) * 40.0
		track.sample_into(s, sample)
		var right: Vector3 = sample.right()
		var p: Vector3 = sample.position + right * (env.road_center_offset_m + sgn * w)
		if field != null and field.road_distance_at(p.x, p.z) < curb_out + 2.5:
			continue
		var y: float = _ground_y(p, w, sample.position.y, env.road_width_m, verge_w, field)
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
		track.sample_into(s, sample)
		var right: Vector3 = sample.right()
		var p: Vector3 = sample.position + right * (env.road_center_offset_m + sgn * w)
		var y: float = sample.position.y + RoadsideBuilder.verge_height(w, env.road_width_m)
		var sc: float = rng.randf_range(0.7, 1.6)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.8, 1.3), sc))
		var dry: float = rng.randf()
		tufts.add(Transform3D(basis, Vector3(p.x, y - 0.02, p.z)), Color(1.0 + dry * 0.15, 1.0, 1.0 - dry * 0.2, 1.0),
			PerfBudget.chunk_of(s, chunk_m, chunks))
	var layers: Array[Layer] = [trees, pines, bushes, tufts]
	if chunks > 1:
		var seen: int = _max_visible(layers, chunks, track)
		if seen > budget:
			for layer in layers:
				layer.keep = float(maxi(budget, 0)) / float(seen)
	return layers


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
## `cols` пустой — без цвета экземпляра.
static func chunked_multimesh(node_name: String, mesh: Mesh, xforms: Array[Transform3D], cols: Array[Color],
		chunk: PackedInt32Array, chunks: int, range_m: float, keep: float = 1.0) -> MultiMeshInstance3D:
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
		mm.mesh = mesh
		mm.instance_count = n
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for j in n:
			var t: Transform3D = xforms[idx[j]]
			mm.set_instance_transform(j, t)
			if mm.use_colors:
				mm.set_instance_color(j, MeshKit.lin(cols[idx[j]]))
			lo = lo.min(t.origin)
			hi = hi.max(t.origin)
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
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
