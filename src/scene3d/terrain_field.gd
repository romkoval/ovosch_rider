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
## Высота земли отсчитывается от дороги, а не от средней высоты трассы (REQ-D3D-08 п.4,
## `tracks.md` п. 5): у полотна — высота ближайших точек оси (вес 1/d⁶: у дороги ровно h(s),
## между двумя участками трассы — плавный переход без ступеньки), дальше — «поле высоты
## трассы»: среднее высот точек трассы с ядром 1/(1 + (d/`FAR_KERNEL_M`)⁴) плюс поперечный
## склон: на подъёмах внутренняя сторона поворота (на прямой — петли) выше, внешняя ниже.
## Поверх — увалы и холмы горизонта. На трассе с перепадом 400 м рельеф идёт вместе с
## дорогой, а не стоит на одной высоте.
##
## Расстояние и высоты считаются «штампом»: каждая точка трассы обновляет вершины сетки в
## радиусе — без перебора всех пар (у дороги — по мелкой сетке до `near_radius_m`, поле
## высоты и холмы — по грубой сетке `FAR_CELL_M`). Всё строится один раз в `RideScene.set_track()`.

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

## Поле высоты трассы: ширина ядра, м (на таком расстоянии вес — половина).
const FAR_KERNEL_M: float = 120.0
## Поперечный склон: уклон поперёк дороги = `CROSS_GAIN` · |g(s)| (не больше `CROSS_MAX`);
## выше внутренняя сторона поворота радиусом ≤ `CROSS_FULL_RADIUS_M` (кривизна — по курсу
## через ±`CROSS_WINDOW_M`), на прямой — внутренняя сторона петли; растёт до бокового
## смещения `CROSS_REACH_M`.
const CROSS_GAIN: float = 2.5
const CROSS_MAX: float = 0.2
const CROSS_FULL_RADIUS_M: float = 300.0
const CROSS_WINDOW_M: float = 200.0
const CROSS_REACH_M: float = 150.0
## Высота у дороги: вес точки оси 1/(d⁶ + eps).
const NEAR_EPS: float = 0.02
## Маска полей (T-083): цвет вершины рельефа, альфа = 1 − маска; маска растёт от 0 до 1
## между этими расстояниями от оси трассы (полоса травы у дороги — без лоскутов полей).
## Шейдер травы рисует лоскуты с силой `field_strength` × (1 − альфа).
const FIELD_FROM_M: float = 12.0
const FIELD_FULL_M: float = 18.0
const ANCHOR_FROM_M: float = 70.0
const ANCHOR_FULL_M: float = 380.0

var origin := Vector2.ZERO
var cell_m: float = MIN_CELL_M
## Размер решётки вершин (в коридоре — виртуальной: хранятся только плитки).
var nx: int = 0
var nz: int = 0
## Компактный режим: высоты и расстояние до трассы по всей решётке `nx` × `nz` (в коридоре пусты).
var heights := PackedFloat32Array()
var road_dist := PackedFloat32Array()
## Высота над полем высоты трассы (увалы и холмы, м) по вершинам — UV.x меша: шейдер травы
## красит склоны холмов по высоте над дорогой, а не над нулём (трассы на 40–700 м).
var heights_rel := PackedFloat32Array()
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
var tile_rel: Array[PackedFloat32Array] = []
var chunk_tiles: int = MIN_CHUNK_TILES
## Поперечный склон на подъёмах (`CROSS_GAIN` по умолчанию; набор окружения может усилить).
var cross_gain: float = CROSS_GAIN
var cross_max: float = CROSS_MAX
## «Якорь» дальнего рельефа (T-083): доля, с которой поле высоты трассы вдали от дороги
## (`ANCHOR_FROM_M`…`ANCHOR_FULL_M`) уходит к средней высоте трассы. 0 — рельеф везде идёт за
## дорогой; > 0 — долины и холмы стоят на месте, дорога поднимается и опускается относительно
## них (на подъёме внизу открывается долина, у подножия холмы выше дороги).
var relief_anchor: float = 0.0

var _far_origin := Vector2.ZERO
var _far_nx: int = 0
var _far_nz: int = 0
var _far_dist := PackedFloat32Array()
## Поле высоты трассы по грубой сетке (с поперечным склоном; только на время построения).
var _far_h := PackedFloat32Array()
## Поле высоты трассы в точке последнего `_height` (для `heights_rel`).
var _last_far: float = 0.0
## Точки трассы (шаг `SAMPLE_STEP_M`): правый вектор (x, z) и коэффициент поперечного склона.
var _rights := PackedVector2Array()
var _cross := PackedFloat32Array()
## Высота у дороги по вершинам мелких плиток: Σw·h и Σw (только на время построения).
var _tile_road_y: Array[PackedFloat32Array] = []
var _tile_road_w: Array[PackedFloat32Array] = []


static func build(track: Track, rolling_m: float, hills_m: float, seed: int,
		cross_slope_gain: float = CROSS_GAIN, anchor: float = 0.0, cross_slope_max: float = CROSS_MAX) -> TerrainField:
	var f := TerrainField.new()
	f.cross_gain = maxf(cross_slope_gain, 0.0)
	f.cross_max = clampf(cross_slope_max, 0.0, 0.6)
	f.relief_anchor = clampf(anchor, 0.0, 1.0)
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
	var heading := PackedFloat32Array()
	var grade := PackedFloat32Array()
	heading.resize(count + 1)
	grade.resize(count + 1)
	_rights.resize(count + 1)
	for i in count + 1:
		track.sample_into(minf(float(i) * SAMPLE_STEP_M, length), sample)
		pts[i] = sample.position
		lo = Vector2(minf(lo.x, sample.position.x), minf(lo.y, sample.position.z))
		hi = Vector2(maxf(hi.x, sample.position.x), maxf(hi.y, sample.position.z))
		sum_y += sample.position.y
		var r: Vector3 = sample.right()
		_rights[i] = Vector2(r.x, r.z)
		heading[i] = atan2(sample.forward.z, sample.forward.x)
		grade[i] = sample.grade
	mean_y = sum_y / float(count + 1)
	bounds_min = lo
	bounds_max = hi
	# Поперечный склон, сила — |g|. Сторона: в повороте (кривизна по курсу через
	# ±`CROSS_WINDOW_M`) выше внутренняя (курс растёт — поворот вправо, выше правая), на
	# прямой — внутренняя сторона петли; между ними — плавно.
	var w: int = maxi(int(CROSS_WINDOW_M / SAMPLE_STEP_M), 1)
	var loop: bool = track.is_loop()
	var total_turn: float = 0.0
	for i in count:
		total_turn += wrapf(heading[i + 1] - heading[i], -PI, PI)
	var inner: float = 1.0 if total_turn >= 0.0 else -1.0
	_cross.resize(count + 1)
	for i in count + 1:
		var a: int = posmod(i - w, count) if loop else maxi(i - w, 0)
		var b: int = posmod(i + w, count) if loop else mini(i + w, count)
		var kappa: float = wrapf(heading[b] - heading[a], -PI, PI) / (float(w * 2) * SAMPLE_STEP_M)
		var turn: float = clampf(kappa * CROSS_FULL_RADIUS_M, -1.0, 1.0)
		var side: float = clampf(turn + inner * (1.0 - absf(turn)), -1.0, 1.0)
		_cross[i] = clampf(cross_gain * absf(grade[i]), 0.0, cross_max) * side
	return pts


## Высота земли: увалы, холмы (доля `hills_t` от полной высоты) и у дороги — ровная
## площадка на `ROAD_SINK_M` ниже полотна.
func _height(x: float, z: float, hills_t: float, near_d: float, near_y: float, rolling: FastNoiseLite,
		hills: FastNoiseLite, rolling_m: float, hills_m: float, far_d: float = 0.0) -> float:
	_last_far = _far_height_at(x, z)
	if relief_anchor > 0.0:
		_last_far = lerpf(_last_far, mean_y, relief_anchor * smoothstep(ANCHOR_FROM_M, ANCHOR_FULL_M, far_d))
	var base: float = _last_far + rolling.get_noise_2d(x, z) * rolling_m
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
	var road_w := PackedFloat32Array()
	road_w.resize(total)
	_stamp_far(pts, origin, extent.x + cell_m, extent.y + cell_m, maxf(extent.x, extent.y) + FAR_CELL_M)
	var reach: int = int(ceil(near_radius_m / cell_m))
	for p in pts:
		var cx: int = int(round((p.x - origin.x) / cell_m))
		var cz: int = int(round((p.z - origin.y) / cell_m))
		for iz in range(maxi(cz - reach, 0), mini(cz + reach, nz - 1) + 1):
			var vz: float = origin.y + float(iz) * cell_m - p.z
			for ix in range(maxi(cx - reach, 0), mini(cx + reach, nx - 1) + 1):
				var vx: float = origin.x + float(ix) * cell_m - p.x
				var d2: float = vx * vx + vz * vz
				var k: int = iz * nx + ix
				road_dist[k] = minf(road_dist[k], sqrt(d2))
				var wt: float = 1.0 / (d2 * d2 * d2 + NEAR_EPS)
				road_w[k] += wt
				road_y[k] += wt * p.y
	var noises := _noises(seed)
	heights.resize(total)
	heights_rel.resize(total)
	for iz in nz:
		for ix in nx:
			var k: int = iz * nx + ix
			var x: float = origin.x + float(ix) * cell_m
			var z: float = origin.y + float(iz) * cell_m
			var dbox: float = _box_distance(x, z)
			var t: float = smoothstep(HILLS_START_M, HILLS_FULL_M, dbox) if dbox > HILLS_START_M else 0.0
			var ny: float = road_y[k] / road_w[k] if road_w[k] > 0.0 else mean_y
			heights[k] = _height(x, z, t, road_dist[k], ny, noises[0], noises[1], rolling_m, hills_m, minf(road_dist[k], dbox + NEAR_RADIUS_M))
			heights_rel[k] = heights[k] - _last_far
	_release_build_data()


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
	_stamp_far(pts, origin, float(tiles_x) * tile_m, float(tiles_z) * tile_m, CORRIDOR_RADIUS_M + tile_m * 1.5)
	_select_tiles(tiles_x, tiles_z)
	_stamp_near(pts)
	var noises := _noises(seed)
	for ti in tile_keys.size():
		var key: Vector2i = tile_keys[ti]
		var step: int = tile_step[ti]
		var n: int = TILE_CELLS / step + 1
		var h: PackedFloat32Array = tile_heights[ti]
		var rel := PackedFloat32Array()
		rel.resize(n * n)
		var fine: bool = step == 1
		var rd: PackedFloat32Array = tile_road_dist[ti]
		var ry: PackedFloat32Array = _tile_road_y[ti]
		var rw: PackedFloat32Array = _tile_road_w[ti]
		for j in n:
			var z: float = origin.y + float(key.y * TILE_CELLS + j * step) * cell_m
			for i in n:
				var x: float = origin.x + float(key.x * TILE_CELLS + i * step) * cell_m
				var d_far: float = _far_distance_at(x, z)
				var t: float = smoothstep(HILLS_START_M, HILLS_FULL_M, d_far) if d_far > HILLS_START_M else 0.0
				var k: int = j * n + i
				var near_d: float = rd[k] if fine else FAR
				var near_y: float = ry[k] / rw[k] if fine and rw[k] > 0.0 else mean_y
				h[k] = _height(x, z, t, near_d, near_y, noises[0], noises[1], rolling_m, hills_m, d_far)
				rel[k] = h[k] - _last_far
		tile_heights[ti] = h
		tile_rel.append(rel)
	_snap_fine_edges()
	_release_build_data()


## Грубая сетка от `grid_origin` размером `size_x` × `size_z` м: расстояние до трассы и поле
## высоты трассы — штамп из точек трассы через `FAR_SAMPLE_STEP_M` в радиусе `reach_m`.
func _stamp_far(pts: PackedVector3Array, grid_origin: Vector2, size_x: float, size_z: float, reach_m: float) -> void:
	_far_origin = grid_origin
	_far_nx = int(ceil(size_x / FAR_CELL_M)) + 1
	_far_nz = int(ceil(size_z / FAR_CELL_M)) + 1
	var total: int = _far_nx * _far_nz
	_far_dist.resize(total)
	_far_dist.fill(FAR)
	var wsum := PackedFloat64Array()
	var hsum := PackedFloat64Array()
	wsum.resize(total)
	hsum.resize(total)
	var reach: int = int(ceil(reach_m / FAR_CELL_M))
	var every: int = maxi(int(FAR_SAMPLE_STEP_M / SAMPLE_STEP_M), 1)
	var picks := PackedInt32Array(range(0, pts.size(), every))
	if picks[picks.size() - 1] != pts.size() - 1:
		picks.append(pts.size() - 1)
	var inv_k2: float = 1.0 / (FAR_KERNEL_M * FAR_KERNEL_M)
	for pi in picks:
		var p: Vector3 = pts[pi]
		var r: Vector2 = _rights[pi]
		var c: float = _cross[pi]
		var cx: int = int(round((p.x - _far_origin.x) / FAR_CELL_M))
		var cz: int = int(round((p.z - _far_origin.y) / FAR_CELL_M))
		for iz in range(maxi(cz - reach, 0), mini(cz + reach, _far_nz - 1) + 1):
			var vz: float = _far_origin.y + float(iz) * FAR_CELL_M - p.z
			for ix in range(maxi(cx - reach, 0), mini(cx + reach, _far_nx - 1) + 1):
				var vx: float = _far_origin.x + float(ix) * FAR_CELL_M - p.x
				var d2: float = vx * vx + vz * vz
				var k: int = iz * _far_nx + ix
				_far_dist[k] = minf(_far_dist[k], sqrt(d2))
				var q: float = d2 * inv_k2
				var wt: float = 1.0 / (1.0 + q * q)
				var lat: float = clampf(vx * r.x + vz * r.y, -CROSS_REACH_M, CROSS_REACH_M)
				wsum[k] += wt
				hsum[k] += wt * (p.y + c * lat)
	_far_h.resize(total)
	for k in total:
		_far_h[k] = hsum[k] / wsum[k] if wsum[k] > 0.0 else mean_y


## Поле высоты трассы в точке (билинейно по грубой сетке).
func _far_height_at(x: float, z: float) -> float:
	if _far_h.is_empty():
		return mean_y
	var fx: float = clampf((x - _far_origin.x) / FAR_CELL_M, 0.0, float(_far_nx - 1) - 1e-4)
	var fz: float = clampf((z - _far_origin.y) / FAR_CELL_M, 0.0, float(_far_nz - 1) - 1e-4)
	var ix: int = int(fx)
	var iz: int = int(fz)
	var k: int = iz * _far_nx + ix
	var a: float = lerpf(_far_h[k], _far_h[k + 1], fx - float(ix))
	var b: float = lerpf(_far_h[k + _far_nx], _far_h[k + _far_nx + 1], fx - float(ix))
	return lerpf(a, b, fz - float(iz))


## Данные построения больше не нужны (запросы `height_at` их не используют).
func _release_build_data() -> void:
	_tile_road_y.clear()
	_tile_road_w.clear()
	_far_dist = PackedFloat32Array()
	_far_h = PackedFloat32Array()
	_rights = PackedVector2Array()
	_cross = PackedFloat32Array()


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
			var rw := PackedFloat32Array()
			if step == 1:
				rd.resize(n * n)
				rd.fill(FAR)
				ry.resize(n * n)
				rw.resize(n * n)
			tile_road_dist.append(rd)
			_tile_road_y.append(ry)
			_tile_road_w.append(rw)


## Мелкая сетка расстояния до трассы и высоты дороги (вес 1/d⁶) — в мелких плитках,
## до `near_radius_m`.
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
				var rw: PackedFloat32Array = _tile_road_w[ti]
				var n: int = TILE_CELLS + 1
				var bx: int = tx * TILE_CELLS
				var bz: int = tz * TILE_CELLS
				for gz in range(maxi(gz0, bz), mini(gz1, bz + TILE_CELLS) + 1):
					var vz: float = origin.y + float(gz) * cell_m - p.z
					for gx in range(maxi(gx0, bx), mini(gx1, bx + TILE_CELLS) + 1):
						var vx: float = origin.x + float(gx) * cell_m - p.x
						var d2: float = vx * vx + vz * vz
						var k: int = (gz - bz) * n + (gx - bx)
						rd[k] = minf(rd[k], sqrt(d2))
						var wt: float = 1.0 / (d2 * d2 * d2 + NEAR_EPS)
						rw[k] += wt
						ry[k] += wt * p.y
				tile_road_dist[ti] = rd
				_tile_road_y[ti] = ry
				_tile_road_w[ti] = rw


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
# Котловины (T-083: озёра ориентиров)
# ---------------------------------------------------------------------------

## Котловина под воду: эллипс с центром `center` (x, z), полуосями `radii` (x — вдоль `axis`)
## и уровнем воды `level`. Внутри 0.8 радиуса земля не выше `level − BASIN_DEPTH_M`, к краю
## эллипса — подъём до `level + BASIN_BANK_M` (берег внутри эллипса воды), дальше — склоны
## долины плавно к исходному рельефу до `BASIN_REACH` радиусов. Вызывается до `build_mesh`
## (меш строится по высотам).
const BASIN_DEPTH_M: float = 3.0
const BASIN_BANK_M: float = 0.8
const BASIN_REACH: float = 1.4


func carve_basin(center: Vector3, axis: Vector3, radii: Vector2, level: float) -> void:
	var ax := Vector2(axis.x, axis.z).normalized()
	var side := Vector2(-ax.y, ax.x)
	var reach: float = maxf(radii.x, radii.y) * (BASIN_REACH + 0.05)
	var lo := Vector2(center.x - reach, center.z - reach)
	var hi := Vector2(center.x + reach, center.z + reach)
	if corridor:
		for ti in tile_keys.size():
			var key: Vector2i = tile_keys[ti]
			var step: int = tile_step[ti]
			var n: int = TILE_CELLS / step + 1
			var x0: float = origin.x + float(key.x * TILE_CELLS) * cell_m
			var z0: float = origin.y + float(key.y * TILE_CELLS) * cell_m
			var span: float = cell_m * float(TILE_CELLS)
			if x0 > hi.x or x0 + span < lo.x or z0 > hi.y or z0 + span < lo.y:
				continue
			var h: PackedFloat32Array = tile_heights[ti]
			var rel: PackedFloat32Array = tile_rel[ti]
			for j in n:
				for i in n:
					var k: int = j * n + i
					var x: float = x0 + float(i * step) * cell_m
					var z: float = z0 + float(j * step) * cell_m
					var nh: float = _basin_height(h[k], Vector2(x - center.x, z - center.z), ax, side, radii, level)
					rel[k] += nh - h[k]
					h[k] = nh
			tile_heights[ti] = h
			tile_rel[ti] = rel
	else:
		for iz in nz:
			for ix in nx:
				var k: int = iz * nx + ix
				var d := Vector2(origin.x + float(ix) * cell_m - center.x, origin.y + float(iz) * cell_m - center.z)
				var nh: float = _basin_height(heights[k], d, ax, side, radii, level)
				heights_rel[k] += nh - heights[k]
				heights[k] = nh


static func _basin_height(h: float, d: Vector2, ax: Vector2, side: Vector2, radii: Vector2, level: float) -> float:
	var a: float = d.dot(ax) / maxf(radii.x, 1.0)
	var b: float = d.dot(side) / maxf(radii.y, 1.0)
	var e: float = sqrt(a * a + b * b)
	if e >= BASIN_REACH:
		return h
	if e < 0.8:
		return minf(h, level - BASIN_DEPTH_M)
	if e < 1.0:
		return lerpf(level - BASIN_DEPTH_M, level + BASIN_BANK_M, (e - 0.8) / 0.2)
	return minf(h, lerpf(level + BASIN_BANK_M, h, smoothstep(1.0, BASIN_REACH, e))) if h > level else lerpf(level + BASIN_BANK_M, h, smoothstep(1.0, BASIN_REACH, e))


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
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.resize(nx * nz)
	uvs.resize(nx * nz)
	norms.resize(nx * nz)
	cols.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var k: int = iz * nx + ix
			cols[k] = field_color(road_dist[k])
			uvs[k] = Vector2(heights_rel[k], 0.0)
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
	var node := _mesh_node(verts, norms, cols, uvs, idx, material)
	node.name = "Terrain"
	return node


## Цвет вершины рельефа: белый, альфа = 1 − маска полей по расстоянию до оси трассы.
static func field_color(road_d: float) -> Color:
	return Color(1.0, 1.0, 1.0, 1.0 - smoothstep(FIELD_FROM_M, FIELD_FULL_M, road_d))


func _mesh_node(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray,
		uvs: PackedVector2Array, idx: PackedInt32Array, material: Material) -> MeshInstance3D:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
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
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for ti in tiles:
		var key: Vector2i = tile_keys[ti]
		var step: int = tile_step[ti]
		var n: int = TILE_CELLS / step + 1
		var h: PackedFloat32Array = tile_heights[ti]
		var rd: PackedFloat32Array = tile_road_dist[ti]
		var rel: PackedFloat32Array = tile_rel[ti]
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
				cols.append(field_color(rd[k] if step == 1 else FAR))
				uvs.append(Vector2(rel[k], 0.0))
		for j in n - 1:
			for i in n - 1:
				var a: int = start + j * n + i
				var b: int = a + 1
				var c: int = a + n
				var d: int = c + 1
				idx.append_array(PackedInt32Array([a, b, c, b, d, c]))
	return _mesh_node(verts, norms, cols, uvs, idx, material)
