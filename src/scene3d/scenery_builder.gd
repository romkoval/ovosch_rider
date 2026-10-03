class_name SceneryBuilder
extends RefCounted
## Растительность и мелкие объекты вдоль трассы (REQ-D3D-07, арт-библия «Мир»): лиственные
## деревья, ели, кусты, пучки сухой травы у бордюра — по одному `MultiMeshInstance3D` на тип,
## с разбросом масштаба, поворота и оттенка (цвет экземпляра). Деревья стоят рощами
## (маска шума) и не ближе `TREE_MIN_ROAD_M` к оси трассы. Меши — из `MeshKit`, один
## тун-материал мира. Всё строится один раз в `set_track()`, детерминированно по seed.

const TREE_MIN_ROAD_M: float = 9.0
const TREE_MAX_OFFSET_M: float = 200.0

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


## Построить узлы растительности. `budget` — сколько экземпляров MultiMesh осталось на всё.
## `field` может быть null (рельеф выключен) — тогда высота берётся у дороги.
static func build(track: Track, env: EnvironmentSet, field: TerrainField, material: Material, budget: int) -> Array[MultiMeshInstance3D]:
	var wanted: int = maxi(env.tree_count, 0) + maxi(env.bush_count, 0) + maxi(env.tuft_count, 0)
	var scale: float = 1.0 if wanted <= budget else float(maxi(budget, 0)) / float(maxi(wanted, 1))
	var n_trees: int = int(env.tree_count * scale)
	var n_bushes: int = int(env.bush_count * scale)
	var n_tufts: int = int(env.tuft_count * scale)
	var rng := RandomNumberGenerator.new()
	rng.seed = env.scenery_seed
	var forest := FastNoiseLite.new()
	forest.seed = env.scenery_seed + 7
	forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	forest.frequency = 1.0 / 140.0
	var length: float = track.length_m()
	var half: float = env.road_width_m * 0.5
	var curb_out: float = RoadsideBuilder.curb_outer_m(env.road_width_m)
	var verge_w: float = RoadsideBuilder.verge_width_m(env.road_width_m)
	var sample := TrackSample.new()
	var out: Array[MultiMeshInstance3D] = []
	# Деревья: лиственные и ели — рощами по маске шума.
	var round_xf: Array[Transform3D] = []
	var round_col: Array[Color] = []
	var pine_xf: Array[Transform3D] = []
	var pine_col: Array[Color] = []
	var attempts: int = n_trees * 8
	while attempts > 0 and round_xf.size() + pine_xf.size() < n_trees:
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
		if conifer:
			pine_xf.append(xf)
			pine_col.append(Color(shade, shade, shade * rng.randf_range(0.95, 1.05), 1.0))
		else:
			round_xf.append(xf)
			round_col.append(Color(shade * rng.randf_range(0.95, 1.12), shade, shade * 0.9, 1.0))
	out.append(_multimesh("Trees", tree_mesh(material), round_xf, round_col))
	out.append(_multimesh("Conifers", conifer_mesh(material), pine_xf, pine_col))
	# Кусты: у кювета и в поле.
	var bush_xf: Array[Transform3D] = []
	var bush_col: Array[Color] = []
	attempts = n_bushes * 6
	while attempts > 0 and bush_xf.size() < n_bushes:
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
		bush_xf.append(Transform3D(basis, Vector3(p.x, y - 0.08, p.z)))
		var shade: float = rng.randf_range(0.85, 1.15)
		bush_col.append(Color(shade, shade, shade * 0.95, 1.0))
	out.append(_multimesh("Bushes", bush_mesh(material), bush_xf, bush_col))
	# Пучки травы: 85 % — вдоль бордюра (мелькают у края кадра), остальное — по обочине.
	var tuft_xf: Array[Transform3D] = []
	var tuft_col: Array[Color] = []
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
		tuft_xf.append(Transform3D(basis, Vector3(p.x, y - 0.02, p.z)))
		var dry: float = rng.randf()
		tuft_col.append(Color(1.0 + dry * 0.15, 1.0, 1.0 - dry * 0.2, 1.0))
	out.append(_multimesh("Tufts", tuft_mesh(material), tuft_xf, tuft_col))
	return out


static func _ground_y(p: Vector3, w: float, road_y: float, road_width: float, verge_w: float, field: TerrainField) -> float:
	if w < verge_w - 1.5 or field == null:
		return road_y + RoadsideBuilder.verge_height(w, road_width)
	return field.height_at(p.x, p.z)


static func _multimesh(node_name: String, mesh: Mesh, xforms: Array[Transform3D], cols: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, MeshKit.lin(cols[i]))
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	return node
