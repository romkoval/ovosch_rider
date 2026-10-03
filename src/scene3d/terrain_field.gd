class_name TerrainField
extends RefCounted
## Рельеф вокруг трассы (REQ-D3D-07, арт-библия «Земля»; длинные трассы — REQ-D3D-08 п.6,
## `docs/game/tracks.md` п. 5, T-066). У дороги земля чуть ниже полотна (полоса обочины
## `RoadsideBuilder` ложится сверху), дальше — пологие увалы, к краю мира — холмы, которые
## закрывают горизонт. Работает с любой реализацией `Track` (петля, прямая, GPX).
##
## Два режима, выбор — по габариту трассы (`PerfBudget.is_compact`):
## - компактная трасса (петля ~2 км): одна сетка высот на габарит трассы с запасом
##   `MARGIN_M`, холмы растут от габарита; один меш;
## - длинная трасса: коридор вдоль трассы шириной `CORRIDOR_RADIUS_M` в каждую сторону из
##   квадратных плиток по `TILE_CELLS` ячеек. Ячейка у дороги та же, что на петле
##   (`CORRIDOR_CELL_M`), дальше `FINE_RADIUS_M` — вдвое крупнее (LOD); холмы растут от
##   расстояния до трассы. Плитки собраны в куски-меши (не больше `MAX_TERRAIN_CHUNKS`) с
##   дальностью видимости `RANGE_M`; на стыке мелкой и крупной плитки рёбра мелкой
##   выровнены по крупной (без щелей).
##
## Расстояние до трассы считается «штампом»: каждая точка трассы обновляет вершины сетки в
## радиусе — без перебора всех пар (у дороги — по мелкой сетке до `near_radius_m`, для
## холмов коридора — по грубой сетке `FAR_CELL_M`). Всё строится один раз в `RideScene.set_track()`.

const SAMPLE_STEP_M: float = 5.0
## Дальше этого расстояния от трассы рельеф не зависит от высоты дороги (минимум; на
## длинном маршруте с крупной ячейкой — не меньше трёх ячеек, см. `near_radius_m`).
const NEAR_RADIUS_M: float = 60.0
## До этого расстояния земля ровная, на `ROAD_SINK_M` ниже дороги (минимум; не меньше
## полутора ячеек — тогда все углы ячейки под дорогой ровные и интерполяция не поднимает
## землю над полотном).
const FLAT_RADIUS_M: float = 16.0
const ROAD_SINK_M: float = 0.45
## Запас сетки за габаритом трассы, м: на нём поднимаются холмы горизонта.
const MARGIN_M: float = 700.0
## Холмы начинают расти на этом расстоянии от габарита трассы (в коридоре — от трассы).
const HILLS_START_M: float = 140.0
## Холмы в полную высоту на этом расстоянии.
const HILLS_FULL_M: float = MARGIN_M - 80.0
## Максимум вершин сетки по большей стороне (компактный режим).
const MAX_CELLS: int = 150
const MIN_CELL_M: float = 12.0
const FAR: float = 1.0e9

## Коридор: полуширина (холмы горизонта успевают вырасти в полную высоту), ячейка у дороги,
## плитка, расстояние до трассы, ближе которого плитка мелкая.
const CORRIDOR_RADIUS_M: float = MARGIN_M
const CORRIDOR_CELL_M: float = MIN_CELL_M
const TILE_CELLS: int = 16
const COARSE_STEP: int = 2
const FINE_RADIUS_M: float = 150.0
## Грубая сетка расстояния до трассы (для холмов и выбора плиток), м; делит плитку нацело.
const FAR_CELL_M: float = CORRIDOR_CELL_M * float(TILE_CELLS) / 3.0
const FAR_SAMPLE_STEP_M: float = 40.0
## Кусков-мешей рельефа не больше этого (бюджет `MeshInstance3D`); кусок — квадрат
## из `chunk_tiles` × `chunk_tiles` плиток, не меньше `MIN_CHUNK_TILES`.
const MAX_TERRAIN_CHUNKS: int = 32
const MIN_CHUNK_TILES: int = 4
## Дальность видимости куска рельефа (до центра AABB) сверх его полудиагонали, м — дальняя
## плоскость камеры: земля видна до горизонта, куски позади и дальше отсекаются.
const RANGE_M: float = 3000.0

var origin := Vector2.ZERO
var cell_m: float = MIN_CELL_M
## Размер решётки вершин (в коридоре — виртуальной: хранятся только плитки).
var nx: int = 0
var nz: int = 0
## Компактный режим: высоты и расстояние до трассы по всей решётке `nx` × `nz` (в коридоре пусты).
var heights := PackedFloat32Array()
var road_dist := PackedFloat32Array()
var mean_y: float = 0.0
var bounds_min := Vector2.ZERO
var bounds_max := Vector2.ZERO
var flat_radius_m: float = FLAT_RADIUS_M
var near_radius_m: float = NEAR_RADIUS_M
## Режим коридора (длинная трасса).
var corridor: bool = false
## Коридор: плитки по ключу (tx, tz) → индекс; шаг вершин плитки (1 — мелкая, `COARSE_STEP` —
## крупная); высоты и расстояние до трассы (у крупной — пусто) по вершинам плитки.
var tile_index: Dictionary = {}
var tile_keys: Array[Vector2i] = []
var tile_step := PackedInt32Array()
var tile_heights: Array[PackedFloat32Array] = []
var tile_road_dist: Array[PackedFloat32Array] = []
var chunk_tiles: int = MIN_CHUNK_TILES

var _far_origin := Vector2.ZERO
var _far_nx: int = 0
var _far_nz: int = 0
var _far_dist := PackedFloat32Array()
## Высота ближайшей точки трассы по вершинам мелких плиток (только на время построения).
var _tile_road_y: Array[PackedFloat32Array] = []


static func build(track: Track, rolling_m: float, hills_m: float, seed: int) -> TerrainField:
	var f := TerrainField.new()
	if PerfBudget.is_compact(track):
		f._build(track, rolling_m, hills_m, seed)
	else:
		f._build_corridor(track, rolling_m, hills_m, seed)
	return f


static func _noises(seed: int) -> Array[FastNoiseLite]:
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
	return [rolling, hills]


## Точки трассы с шагом `SAMPLE_STEP_M`; заодно габарит и средняя высота.
func _sample_track(track: Track) -> PackedVector3Array:
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
	return pts


## Высота земли: увалы, холмы (доля `hills_t` от полной высоты) и у дороги — ровная
## площадка на `ROAD_SINK_M` ниже полотна.
func _height(x: float, z: float, hills_t: float, near_d: float, near_y: float, rolling: FastNoiseLite,
		hills: FastNoiseLite, rolling_m: float, hills_m: float) -> float:
	var base: float = mean_y + rolling.get_noise_2d(x, z) * rolling_m
	if hills_t > 0.0:
		var h01: float = 0.3 + 0.7 * clampf(hills.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
		base += hills_t * hills_t * h01 * hills_m
	if near_d < near_radius_m:
		var w: float = smoothstep(flat_radius_m, near_radius_m, near_d)
		return lerpf(near_y - ROAD_SINK_M, base, w)
	return base


# ---------------------------------------------------------------------------
# Компактный режим: одна сетка на габарит
# ---------------------------------------------------------------------------

func _build(track: Track, rolling_m: float, hills_m: float, seed: int) -> void:
	var pts := _sample_track(track)
	var lo: Vector2 = bounds_min
	var hi: Vector2 = bounds_max
	var extent: Vector2 = (hi - lo) + Vector2.ONE * MARGIN_M * 2.0
	cell_m = maxf(MIN_CELL_M, maxf(extent.x, extent.y) / float(MAX_CELLS))
	nx = int(ceil(extent.x / cell_m)) + 1
	nz = int(ceil(extent.y / cell_m)) + 1
	origin = lo - Vector2.ONE * MARGIN_M
	flat_radius_m = maxf(FLAT_RADIUS_M, cell_m * 1.5)
	near_radius_m = maxf(NEAR_RADIUS_M, flat_radius_m + cell_m * 1.5)
	var total: int = nx * nz
	road_dist.resize(total)
	road_dist.fill(FAR)
	var road_y := PackedFloat32Array()
	road_y.resize(total)
	road_y.fill(mean_y)
	var reach: int = int(ceil(near_radius_m / cell_m))
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
	var noises := _noises(seed)
	heights.resize(total)
	for iz in nz:
		for ix in nx:
			var k: int = iz * nx + ix
			var x: float = origin.x + float(ix) * cell_m
			var z: float = origin.y + float(iz) * cell_m
			var dbox: float = _box_distance(x, z)
			var t: float = smoothstep(HILLS_START_M, HILLS_FULL_M, dbox) if dbox > HILLS_START_M else 0.0
			heights[k] = _height(x, z, t, road_dist[k], road_y[k], noises[0], noises[1], rolling_m, hills_m)


func _box_distance(x: float, z: float) -> float:
	var dx: float = maxf(maxf(bounds_min.x - x, x - bounds_max.x), 0.0)
	var dz: float = maxf(maxf(bounds_min.y - z, z - bounds_max.y), 0.0)
	return sqrt(dx * dx + dz * dz)


# ---------------------------------------------------------------------------
# Коридор: плитки вдоль трассы
# ---------------------------------------------------------------------------

func _build_corridor(track: Track, rolling_m: float, hills_m: float, seed: int) -> void:
	corridor = true
	var pts := _sample_track(track)
	cell_m = CORRIDOR_CELL_M
	flat_radius_m = maxf(FLAT_RADIUS_M, cell_m * 1.5)
	near_radius_m = maxf(NEAR_RADIUS_M, flat_radius_m + cell_m * 1.5)
	var tile_m: float = cell_m * float(TILE_CELLS)
	var pad: float = CORRIDOR_RADIUS_M + tile_m
	origin = bounds_min - Vector2.ONE * pad
	var tiles_x: int = int(ceil((bounds_max.x - bounds_min.x + pad * 2.0) / tile_m))
	var tiles_z: int = int(ceil((bounds_max.y - bounds_min.y + pad * 2.0) / tile_m))
	nx = tiles_x * TILE_CELLS + 1
	nz = tiles_z * TILE_CELLS + 1
	_stamp_far(pts, tiles_x, tiles_z)
	_select_tiles(tiles_x, tiles_z)
	_stamp_near(pts)
	var noises := _noises(seed)
	for ti in tile_keys.size():
		var key: Vector2i = tile_keys[ti]
		var step: int = tile_step[ti]
		var n: int = TILE_CELLS / step + 1
		var h: PackedFloat32Array = tile_heights[ti]
		var fine: bool = step == 1
		var rd: PackedFloat32Array = tile_road_dist[ti]
		var ry: PackedFloat32Array = _tile_road_y[ti]
		for j in n:
			var z: float = origin.y + float(key.y * TILE_CELLS + j * step) * cell_m
			for i in n:
				var x: float = origin.x + float(key.x * TILE_CELLS + i * step) * cell_m
				var d_far: float = _far_distance_at(x, z)
				var t: float = smoothstep(HILLS_START_M, HILLS_FULL_M, d_far) if d_far > HILLS_START_M else 0.0
				var k: int = j * n + i
				var near_d: float = rd[k] if fine else FAR
				var near_y: float = ry[k] if fine else mean_y
				h[k] = _height(x, z, t, near_d, near_y, noises[0], noises[1], rolling_m, hills_m)
		tile_heights[ti] = h
	_tile_road_y.clear()
	_snap_fine_edges()
	_far_dist = PackedFloat32Array()


## Грубая сетка расстояния до трассы: штамп из точек трассы через `FAR_SAMPLE_STEP_M`.
func _stamp_far(pts: PackedVector3Array, tiles_x: int, tiles_z: int) -> void:
	var per_tile: int = int(round(cell_m * float(TILE_CELLS) / FAR_CELL_M))
	_far_origin = origin
	_far_nx = tiles_x * per_tile + 1
	_far_nz = tiles_z * per_tile + 1
	_far_dist.resize(_far_nx * _far_nz)
	_far_dist.fill(FAR)
	var reach: int = int(ceil((CORRIDOR_RADIUS_M + 2.0 * FAR_CELL_M) / FAR_CELL_M))
	var every: int = maxi(int(FAR_SAMPLE_STEP_M / SAMPLE_STEP_M), 1)
	var picks := PackedInt32Array(range(0, pts.size(), every))
	if picks[picks.size() - 1] != pts.size() - 1:
		picks.append(pts.size() - 1)
	for pi in picks:
		var p: Vector3 = pts[pi]
		var cx: int = int(round((p.x - _far_origin.x) / FAR_CELL_M))
		var cz: int = int(round((p.z - _far_origin.y) / FAR_CELL_M))
		for iz in range(maxi(cz - reach, 0), mini(cz + reach, _far_nz - 1) + 1):
			var vz: float = _far_origin.y + float(iz) * FAR_CELL_M - p.z
			for ix in range(maxi(cx - reach, 0), mini(cx + reach, _far_nx - 1) + 1):
				var vx: float = _far_origin.x + float(ix) * FAR_CELL_M - p.x
				var d: float = sqrt(vx * vx + vz * vz)
				var k: int = iz * _far_nx + ix
				if d < _far_dist[k]:
					_far_dist[k] = d


func _far_distance_at(x: float, z: float) -> float:
	var fx: float = clampf((x - _far_origin.x) / FAR_CELL_M, 0.0, float(_far_nx - 1) - 1e-4)
	var fz: float = clampf((z - _far_origin.y) / FAR_CELL_M, 0.0, float(_far_nz - 1) - 1e-4)
	var ix: int = int(fx)
	var iz: int = int(fz)
	var k: int = iz * _far_nx + ix
	var a: float = lerpf(_far_dist[k], _far_dist[k + 1], fx - float(ix))
	var b: float = lerpf(_far_dist[k + _far_nx], _far_dist[k + _far_nx + 1], fx - float(ix))
	return lerpf(a, b, fz - float(iz))


## Плитки коридора: ближайшая к трассе точка плитки не дальше `CORRIDOR_RADIUS_M`;
## мелкая — ближе `FINE_RADIUS_M`.
func _select_tiles(tiles_x: int, tiles_z: int) -> void:
	var per_tile: int = int(round(cell_m * float(TILE_CELLS) / FAR_CELL_M))
	var half_diag: float = FAR_CELL_M * 0.7072
	for tz in tiles_z:
		for tx in tiles_x:
			var nearest: float = FAR
			for jz in per_tile + 1:
				var row: int = (tz * per_tile + jz) * _far_nx + tx * per_tile
				for jx in per_tile + 1:
					nearest = minf(nearest, _far_dist[row + jx])
			nearest -= half_diag
			if nearest > CORRIDOR_RADIUS_M:
				continue
			var step: int = 1 if nearest < FINE_RADIUS_M else COARSE_STEP
			var n: int = TILE_CELLS / step + 1
			tile_index[Vector2i(tx, tz)] = tile_keys.size()
			tile_keys.append(Vector2i(tx, tz))
			tile_step.append(step)
			var h := PackedFloat32Array()
			h.resize(n * n)
			tile_heights.append(h)
			var rd := PackedFloat32Array()
			var ry := PackedFloat32Array()
			if step == 1:
				rd.resize(n * n)
				rd.fill(FAR)
				ry.resize(n * n)
				ry.fill(mean_y)
			tile_road_dist.append(rd)
			_tile_road_y.append(ry)


## Мелкая сетка расстояния до трассы и высоты дороги — в мелких плитках, до `near_radius_m`.
## Вершина на ребре принадлежит обеим плиткам — пишется в каждую.
func _stamp_near(pts: PackedVector3Array) -> void:
	var reach: int = int(ceil(near_radius_m / cell_m))
	for p in pts:
		var cx: int = int(round((p.x - origin.x) / cell_m))
		var cz: int = int(round((p.z - origin.y) / cell_m))
		var gx0: int = maxi(cx - reach, 0)
		var gx1: int = mini(cx + reach, nx - 1)
		var gz0: int = maxi(cz - reach, 0)
		var gz1: int = mini(cz + reach, nz - 1)
		for tz in range(ceili(float(gz0 - TILE_CELLS) / float(TILE_CELLS)), floori(float(gz1) / float(TILE_CELLS)) + 1):
			for tx in range(ceili(float(gx0 - TILE_CELLS) / float(TILE_CELLS)), floori(float(gx1) / float(TILE_CELLS)) + 1):
				var key := Vector2i(tx, tz)
				if not tile_index.has(key):
					continue
				var ti: int = tile_index[key]
				if tile_step[ti] != 1:
					continue
				var rd: PackedFloat32Array = tile_road_dist[ti]
				var ry: PackedFloat32Array = _tile_road_y[ti]
				var n: int = TILE_CELLS + 1
				var bx: int = tx * TILE_CELLS
				var bz: int = tz * TILE_CELLS
				for gz in range(maxi(gz0, bz), mini(gz1, bz + TILE_CELLS) + 1):
					var vz: float = origin.y + float(gz) * cell_m - p.z
					for gx in range(maxi(gx0, bx), mini(gx1, bx + TILE_CELLS) + 1):
						var vx: float = origin.x + float(gx) * cell_m - p.x
						var d: float = sqrt(vx * vx + vz * vz)
						var k: int = (gz - bz) * n + (gx - bx)
						if d < rd[k]:
							rd[k] = d
							ry[k] = p.y
				tile_road_dist[ti] = rd
				_tile_road_y[ti] = ry


## Рёбра мелкой плитки, соседней с крупной: промежуточные вершины — на прямой между
## общими вершинами (иначе Т-стык даёт щель).
func _snap_fine_edges() -> void:
	var n: int = TILE_CELLS + 1
	var sides: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
	for ti in tile_keys.size():
		if tile_step[ti] != 1:
			continue
		var h: PackedFloat32Array = tile_heights[ti]
		for side in sides:
			var other: Vector2i = tile_keys[ti] + side
			if not tile_index.has(other) or tile_step[int(tile_index[other])] == 1:
				continue
			for m in range(1, TILE_CELLS, 2):
				var a: int = 0
				var b: int = 0
				var c: int = 0
				if side.x != 0:
					var col: int = 0 if side.x < 0 else TILE_CELLS
					a = (m - 1) * n + col
					b = m * n + col
					c = (m + 1) * n + col
				else:
					var row: int = 0 if side.y < 0 else TILE_CELLS
					a = row * n + m - 1
					b = row * n + m
					c = row * n + m + 1
				h[b] = (h[a] + h[c]) * 0.5
		tile_heights[ti] = h


# ---------------------------------------------------------------------------
# Запросы
# ---------------------------------------------------------------------------

## Высота рельефа в точке (билинейно; вне коридора — средняя высота трассы).
func height_at(x: float, z: float) -> float:
	if corridor:
		return _tile_lookup(x, z, true)
	return _bilinear(heights, x, z)


## Расстояние до оси трассы в точке (билинейно; дальше `near_radius_m` — большое число).
func road_distance_at(x: float, z: float) -> float:
	if corridor:
		return _tile_lookup(x, z, false)
	return _bilinear(road_dist, x, z)


func _tile_lookup(x: float, z: float, want_height: bool) -> float:
	var gx: float = clampf((x - origin.x) / cell_m, 0.0, float(nx - 1) - 1e-4)
	var gz: float = clampf((z - origin.y) / cell_m, 0.0, float(nz - 1) - 1e-4)
	var tx: int = int(gx) / TILE_CELLS
	var tz: int = int(gz) / TILE_CELLS
	var key := Vector2i(tx, tz)
	if not tile_index.has(key):
		return mean_y if want_height else FAR
	var ti: int = tile_index[key]
	var step: int = tile_step[ti]
	var values: PackedFloat32Array = tile_heights[ti] if want_height else tile_road_dist[ti]
	if values.is_empty():
		return FAR
	var n: int = TILE_CELLS / step + 1
	var fx: float = minf((gx - float(tx * TILE_CELLS)) / float(step), float(n - 1) - 1e-4)
	var fz: float = minf((gz - float(tz * TILE_CELLS)) / float(step), float(n - 1) - 1e-4)
	var ix: int = int(fx)
	var iz: int = int(fz)
	var k: int = iz * n + ix
	var a: float = lerpf(values[k], values[k + 1], fx - float(ix))
	var b: float = lerpf(values[k + n], values[k + n + 1], fx - float(ix))
	return lerpf(a, b, fz - float(iz))


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


# ---------------------------------------------------------------------------
# Меш
# ---------------------------------------------------------------------------

## Меш рельефа «Terrain», тени не отбрасывает. Компактный режим — одна поверхность по
## решётке; коридор — куски из плиток: первый кусок — сам узел, остальные — его дети
## (`Terrain_<k>`), у каждого дальность видимости.
func build_mesh(material: Material) -> MeshInstance3D:
	if corridor:
		return _build_corridor_mesh(material)
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
	var node := _mesh_node(verts, norms, cols, idx, material)
	node.name = "Terrain"
	return node


func _mesh_node(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray,
		idx: PackedInt32Array, material: Material) -> MeshInstance3D:
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
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Число кусков рельефа при стороне куска `k` плиток.
func _chunk_count(k: int) -> int:
	var seen: Dictionary = {}
	for key in tile_keys:
		seen[Vector2i(floori(float(key.x) / float(k)), floori(float(key.y) / float(k)))] = true
	return seen.size()


func _build_corridor_mesh(material: Material) -> MeshInstance3D:
	chunk_tiles = MIN_CHUNK_TILES
	while _chunk_count(chunk_tiles) > MAX_TERRAIN_CHUNKS:
		chunk_tiles += 1
	var groups: Dictionary = {}
	var order: Array[Vector2i] = []
	for ti in tile_keys.size():
		var key: Vector2i = tile_keys[ti]
		var ck := Vector2i(floori(float(key.x) / float(chunk_tiles)), floori(float(key.y) / float(chunk_tiles)))
		if not groups.has(ck):
			groups[ck] = PackedInt32Array()
			order.append(ck)
		var list: PackedInt32Array = groups[ck]
		list.append(ti)
		groups[ck] = list
	var root: MeshInstance3D = null
	for ci in order.size():
		var node := _chunk_mesh(groups[order[ci]], material)
		var half_diag: float = node.get_aabb().size.length() * 0.5
		node.visibility_range_end = RANGE_M + half_diag
		if root == null:
			node.name = "Terrain"
			root = node
		else:
			node.name = "Terrain_%02d" % ci
			root.add_child(node)
	return root


func _chunk_mesh(tiles: PackedInt32Array, material: Material) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for ti in tiles:
		var key: Vector2i = tile_keys[ti]
		var step: int = tile_step[ti]
		var n: int = TILE_CELLS / step + 1
		var h: PackedFloat32Array = tile_heights[ti]
		var span: float = cell_m * float(step)
		var start: int = verts.size()
		for j in n:
			var z: float = origin.y + float(key.y * TILE_CELLS + j * step) * cell_m
			for i in n:
				var x: float = origin.x + float(key.x * TILE_CELLS + i * step) * cell_m
				var k: int = j * n + i
				verts.append(Vector3(x, h[k], z))
				var hl: float = h[k - 1] if i > 0 else height_at(x - span, z)
				var hr: float = h[k + 1] if i < n - 1 else height_at(x + span, z)
				var hd: float = h[k - n] if j > 0 else height_at(x, z - span)
				var hu: float = h[k + n] if j < n - 1 else height_at(x, z + span)
				norms.append(Vector3(hl - hr, 2.0 * span, hd - hu).normalized())
				cols.append(Color.WHITE)
		for j in n - 1:
			for i in n - 1:
				var a: int = start + j * n + i
				var b: int = a + 1
				var c: int = a + n
				var d: int = c + 1
				idx.append_array(PackedInt32Array([a, b, c, b, d, c]))
	return _mesh_node(verts, norms, cols, idx, material)
