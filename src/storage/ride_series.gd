class_name RideSeries
extends RefCounted
## Серии для графиков заезда (REQ-LOC-03 крит. 1–3, решение 17).
##
## Из `SampleStream` строятся серии мощности, пульса, каденса, скорости и
## целевой мощности плана по корзинам времени. Без прореживания корзина = 1 с,
## значение — сэмпл; «нет данных» — `NAN` (разрыв линии), не 0 (крит. 1).
## Для потоков длиннее `max_points` сэмплов корзина = ceil(n / max_points) с:
## значение — среднее по сэмплам корзины с данными, параллельно хранятся
## минимум и максимум корзины (крит. 2: экстремумы не теряются); корзина без
## данных → `NAN`. Цель плана (`target`) всегда с данными (0 — свободная езда).
##
## `points(name)` — точки `(t, значение)` без разрывов: длина серии мощности
## без прореживания равна числу сэмплов с данными мощности.

const MAX_POINTS_DEFAULT: int = 3600
const POWER: String = "power"
const HEART_RATE: String = "heart_rate"
const CADENCE: String = "cadence"
const SPEED: String = "speed"
const TARGET: String = "target"
const NAMES: Array[String] = [POWER, HEART_RATE, CADENCE, SPEED, TARGET]

## Начало корзины, с активного времени.
var time_sec := PackedFloat32Array()
## Ширина корзины, с (1 — без прореживания).
var bucket_sec: int = 1
## Длительность потока, с.
var duration_sec: int = 0
var _avg: Dictionary = {}
var _min: Dictionary = {}
var _max: Dictionary = {}


static func from_samples(samples: SampleStream, max_points: int = MAX_POINTS_DEFAULT) -> RideSeries:
	var s := RideSeries.new()
	var n: int = samples.size()
	s.duration_sec = n
	var limit: int = maxi(max_points, 1)
	s.bucket_sec = maxi(ceili(float(n) / float(limit)), 1) if n > 0 else 1
	var buckets: int = ceili(float(n) / float(s.bucket_sec)) if n > 0 else 0
	for name in NAMES:
		var avg := PackedFloat32Array()
		var mn := PackedFloat32Array()
		var mx := PackedFloat32Array()
		avg.resize(buckets)
		mn.resize(buckets)
		mx.resize(buckets)
		s._avg[name] = avg
		s._min[name] = mn
		s._max[name] = mx
	s.time_sec.resize(buckets)
	for b in buckets:
		var first: int = b * s.bucket_sec
		var last: int = mini(first + s.bucket_sec, n)
		s.time_sec[b] = float(samples.time_sec[first])
		for name in NAMES:
			var sum: float = 0.0
			var count: int = 0
			var lo: float = INF
			var hi: float = -INF
			for i in range(first, last):
				if not _has(samples, name, i):
					continue
				var v: float = _value(samples, name, i)
				sum += v
				count += 1
				lo = minf(lo, v)
				hi = maxf(hi, v)
			if count == 0:
				s._avg[name][b] = NAN
				s._min[name][b] = NAN
				s._max[name][b] = NAN
			else:
				s._avg[name][b] = sum / float(count)
				s._min[name][b] = lo
				s._max[name][b] = hi
	return s


static func _has(samples: SampleStream, name: String, i: int) -> bool:
	match name:
		POWER:
			return samples.has_power[i]
		HEART_RATE:
			return samples.has_heart_rate[i]
		CADENCE:
			return samples.has_cadence[i]
		SPEED:
			return samples.has_speed[i]
		TARGET:
			return true
	return false


static func _value(samples: SampleStream, name: String, i: int) -> float:
	match name:
		POWER:
			return float(samples.power_w[i])
		HEART_RATE:
			return float(samples.heart_rate_bpm[i])
		CADENCE:
			return float(samples.cadence_rpm[i])
		SPEED:
			return samples.speed_kmh[i]
		TARGET:
			return float(samples.target_w[i])
	return NAN


## Число корзин (точек серии, включая разрывы).
func size() -> int:
	return time_sec.size()


## Средние по корзинам (`NAN` — разрыв).
func values(name: String) -> PackedFloat32Array:
	return _avg.get(name, PackedFloat32Array())


func min_values(name: String) -> PackedFloat32Array:
	return _min.get(name, PackedFloat32Array())


func max_values(name: String) -> PackedFloat32Array:
	return _max.get(name, PackedFloat32Array())


## Точки `(t, значение)` без разрывов.
func points(name: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	var vals: PackedFloat32Array = values(name)
	for i in vals.size():
		if not is_nan(vals[i]):
			out.append(Vector2(time_sec[i], vals[i]))
	return out


## Число точек с данными.
func count(name: String) -> int:
	var n: int = 0
	for v in values(name):
		if not is_nan(v):
			n += 1
	return n


func has_data(name: String) -> bool:
	return count(name) > 0


## Максимум серии по данным (по максимумам корзин); `NAN`, если данных нет.
func peak(name: String) -> float:
	var hi: float = -INF
	for v in max_values(name):
		if not is_nan(v):
			hi = maxf(hi, v)
	return hi if hi > -INF else NAN


## Минимум серии по данным; `NAN`, если данных нет.
func low(name: String) -> float:
	var lo: float = INF
	for v in min_values(name):
		if not is_nan(v):
			lo = minf(lo, v)
	return lo if lo < INF else NAN
