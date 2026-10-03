class_name LoopTrack
extends Track
## Процедурная зацикленная трасса (REQ-D3D-03 крит. 1, 2): замкнутый сплайн `Curve3D`
## ~2 км с плавными поворотами и небольшими перепадами высот, детерминированный по seed.
## Контур — `point_count` опорных точек по окружности радиуса `radius_m`, радиус и высота
## каждой точки возмущены ГСЧ с seed; касательные — по Катмуллу–Рому. Выборка —
## линейная между запечёнными точками (шаг `BAKE_INTERVAL_M`), поэтому смещение
## за Δs не превышает Δs. Число активных сегментов постоянно (кривая строится один раз).

const BAKE_INTERVAL_M: float = 1.0
## Шаг «вперёд» для вычисления направления, м.
const FORWARD_PROBE_M: float = 0.5
const MIN_POINTS: int = 6

var seed: int = 1
var radius_m: float = 300.0
## Относительное возмущение радиуса (0.25 → ±25 %).
var waviness: float = 0.25
## Максимальный перепад высоты опорной точки, м.
var elevation_m: float = 3.0
var point_count: int = 12

var _curve := Curve3D.new()
var _length: float = 0.0


func _init(track_seed: int = 1, radius: float = 300.0, wave: float = 0.25, points: int = 12, elevation: float = 3.0) -> void:
	seed = track_seed
	radius_m = maxf(radius, 10.0)
	waviness = clampf(wave, 0.0, 0.6)
	point_count = maxi(points, MIN_POINTS)
	elevation_m = maxf(elevation, 0.0)
	_build()


func length_m() -> float:
	return _length


func is_loop() -> bool:
	return true


func curve() -> Curve3D:
	return _curve


func sample_into(distance_m: float, out: TrackSample) -> void:
	var s: float = wrap_distance(distance_m)
	var pos: Vector3 = _curve.sample_baked(s, false)
	var ahead: Vector3 = _curve.sample_baked(wrap_distance(s + FORWARD_PROBE_M), false)
	var dir: Vector3 = ahead - pos
	if dir.length_squared() < 1e-12:
		dir = Vector3.FORWARD
	out.position = pos
	out.forward = dir.normalized()
	out.up = Vector3.UP
	var horizontal: float = Vector2(dir.x, dir.z).length()
	out.grade = dir.y / horizontal if horizontal > 1e-6 else 0.0


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var points: Array[Vector3] = []
	for i in point_count:
		var angle: float = TAU * float(i) / float(point_count)
		var r: float = radius_m * (1.0 + rng.randf_range(-waviness, waviness))
		var y: float = rng.randf_range(-elevation_m, elevation_m)
		points.append(Vector3(cos(angle) * r, y, sin(angle) * r))
	_curve = Curve3D.new()
	_curve.bake_interval = BAKE_INTERVAL_M
	_curve.closed = true
	for i in point_count:
		var prev: Vector3 = points[(i - 1 + point_count) % point_count]
		var next: Vector3 = points[(i + 1) % point_count]
		var tangent: Vector3 = (next - prev) * 0.25
		_curve.add_point(points[i], -tangent, tangent)
	_length = _curve.get_baked_length()
