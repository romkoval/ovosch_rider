class_name TerrainField
extends RefCounted
## Рельеф вокруг трассы (REQ-D3D-07, арт-библия «Земля»): сетка высот, покрывающая
## габарит трассы с запасом `MARGIN_M`. У дороги земля чуть ниже полотна (полоса обочины
## `RoadsideBuilder` ложится сверху), дальше — пологие увалы, к краю мира — холмы, которые
## закрывают горизонт. Работает с любой реализацией `Track` (петля, прямая, GPX).
##
## Расстояние до трассы считается «штампом»: каждая точка трассы (шаг `SAMPLE_STEP_M`)
## обновляет вершины сетки в радиусе `NEAR_RADIUS_M` — без перебора всех пар. Всё
## строится один раз в `RideScene.set_track()`.

const SAMPLE_STEP_M: float = 5.0
## Дальше этого расстояния от трассы рельеф не зависит от высоты дороги.
const NEAR_RADIUS_M: float = 60.0
## До этого расстояния земля ровная, на `ROAD_SINK_M` ниже дороги.
const FLAT_RADIUS_M: float = 16.0
const ROAD_SINK_M: float = 0.45
## Запас сетки за габаритом трассы, м: на нём поднимаются холмы горизонта.
const MARGIN_M: float = 700.0
## Холмы начинают расти на этом расстоянии от габарита трассы.
const HILLS_START_M: float = 140.0
## Максимум вершин сетки по большей стороне.
const MAX_CELLS: int = 150
const MIN_CELL_M: float = 12.0
const FAR: float = 1.0e9

var origin := Vector2.ZERO
var cell_m: float = MIN_CELL_M
var nx: int = 0
var nz: int = 0
var heights := PackedFloat32Array()
var road_dist := PackedFloat32Array()
var mean_y: float = 0.0
var bounds_min := Vector2.ZERO
var bounds_max := Vector2.ZERO


static func build(track: Track, rolling_m: float, hills_m: float, seed: int) -> TerrainField:
	var f := TerrainField.new()
	f._build(track, rolling_m, hills_m, seed)
	return f


func _build(track: Track, rolling_m: float, hills_m: float, seed: int) -> void:
	var length: float = track.length_m()
	var count: int = maxi(int(ceil(length / SAMPLE_STEP_M)), 2)
	var pts := PackedVector3Array()
	pts.resize(count + 1)
	var sample := TrackSample.new()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var sum_y: float = 0.0
	for i in count + 1:
		track.sample_into(minf(float(i) * SAMPLE_STEP_M, length), sample)
		pts[i] = sample.position
		lo = Vector2(minf(lo.x, sample.position.x), minf(lo.y, sample.position.z))
		hi = Vector2(maxf(hi.x, sample.position.x), maxf(hi.y, sample.position.z))
		sum_y += sample.position.y
	mean_y = sum_y / float(count + 1)
	bounds_min = lo
	bounds_max = hi
	var extent: Vector2 = (hi - lo) + Vector2.ONE * MARGIN_M * 2.0
	cell_m = maxf(MIN_CELL_M, maxf(extent.x, extent.y) / float(MAX_CELLS))
	nx = int(ceil(extent.x / cell_m)) + 1
	nz = int(ceil(extent.y / cell_m)) + 1
	origin = lo - Vector2.ONE * MARGIN_M
	var total: int = nx * nz
	road_dist.resize(total)
	road_dist.fill(FAR)
	var road_y := PackedFloat32Array()
	road_y.resize(total)
	road_y.fill(mean_y)
	var reach: int = int(ceil(NEAR_RADIUS_M / cell_m))
	for p in pts:
		var cx: int = int(round((p.x - origin.x) / cell_m))
		var cz: int = int(round((p.z - origin.y) / cell_m))
		for iz in range(maxi(cz - reach, 0), mini(cz + reach, nz - 1) + 1):
			var vz: float = origin.y + float(iz) * cell_m - p.z
			for ix in range(maxi(cx - reach, 0), mini(cx + reach, nx - 1) + 1):
				var vx: float = origin.x + float(ix) * cell_m - p.x
				var d: float = sqrt(vx * vx + vz * vz)
				var k: int = iz * nx + ix
				if d < road_dist[k]:
					road_dist[k] = d
					road_y[k] = p.y
	var rolling := FastNoiseLite.new()
	rolling.seed = seed
	rolling.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	rolling.frequency = 1.0 / 260.0
	var hills := FastNoiseLite.new()
	hills.seed = seed + 101
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills.frequency = 1.0 / 420.0
	hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	hills.fractal_octaves = 3
	heights.resize(total)
	for iz in nz:
		for ix in nx:
			var k: int = iz * nx + ix
			var x: float = origin.x + float(ix) * cell_m
			var z: float = origin.y + float(iz) * cell_m
			var base: float = mean_y + rolling.get_noise_2d(x, z) * rolling_m
			var dbox: float = _box_distance(x, z)
			if dbox > HILLS_START_M:
				var t: float = smoothstep(HILLS_START_M, MARGIN_M - 80.0, dbox)
				var h01: float = 0.3 + 0.7 * clampf(hills.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
				base += t * t * h01 * hills_m
			var d: float = road_dist[k]
			if d < NEAR_RADIUS_M:
				var w: float = smoothstep(FLAT_RADIUS_M, NEAR_RADIUS_M, d)
				heights[k] = lerpf(road_y[k] - ROAD_SINK_M, base, w)
			else:
				heights[k] = base


func _box_distance(x: float, z: float) -> float:
	var dx: float = maxf(maxf(bounds_min.x - x, x - bounds_max.x), 0.0)
	var dz: float = maxf(maxf(bounds_min.y - z, z - bounds_max.y), 0.0)
	return sqrt(dx * dx + dz * dz)


## Высота рельефа в точке (билинейно).
func height_at(x: float, z: float) -> float:
	return _bilinear(heights, x, z)


## Расстояние до оси трассы в точке (билинейно; дальше `NEAR_RADIUS_M` — большое число).
func road_distance_at(x: float, z: float) -> float:
	return _bilinear(road_dist, x, z)


func _bilinear(values: PackedFloat32Array, x: float, z: float) -> float:
	if nx < 2 or nz < 2:
		return mean_y
	var fx: float = clampf((x - origin.x) / cell_m, 0.0, float(nx - 1) - 1e-4)
	var fz: float = clampf((z - origin.y) / cell_m, 0.0, float(nz - 1) - 1e-4)
	var ix: int = int(fx)
	var iz: int = int(fz)
	var tx: float = fx - float(ix)
	var tz: float = fz - float(iz)
	var k: int = iz * nx + ix
	var a: float = lerpf(values[k], values[k + 1], tx)
	var b: float = lerpf(values[k + nx], values[k + nx + 1], tx)
	return lerpf(a, b, tz)


## Меш рельефа: одна поверхность, нормали по разностям высот.
func build_mesh(material: Material) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(nx * nz)
	norms.resize(nx * nz)
	cols.resize(nx * nz)
	cols.fill(Color.WHITE)
	for iz in nz:
		for ix in nx:
			var k: int = iz * nx + ix
			verts[k] = Vector3(origin.x + float(ix) * cell_m, heights[k], origin.y + float(iz) * cell_m)
			var hl: float = heights[iz * nx + maxi(ix - 1, 0)]
			var hr: float = heights[iz * nx + mini(ix + 1, nx - 1)]
			var hd: float = heights[maxi(iz - 1, 0) * nx + ix]
			var hu: float = heights[mini(iz + 1, nz - 1) * nx + ix]
			norms[k] = Vector3(hl - hr, 2.0 * cell_m, hd - hu).normalized()
	idx.resize((nx - 1) * (nz - 1) * 6)
	var t: int = 0
	for iz in nz - 1:
		for ix in nx - 1:
			var a: int = iz * nx + ix
			var b: int = a + 1
			var c: int = a + nx
			var d: int = c + 1
			idx[t] = a
			idx[t + 1] = b
			idx[t + 2] = c
			idx[t + 3] = b
			idx[t + 4] = d
			idx[t + 5] = c
			t += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material != null:
		mesh.surface_set_material(0, material)
	var node := MeshInstance3D.new()
	node.name = "Terrain"
	node.mesh = mesh
	return node
