class_name RideSeries
extends RefCounted
## Серии для графиков заезда (REQ-LOC-03 крит. 1–3, решения 17 и В-18).
##
## Из `SampleStream` строятся серии мощности, пульса, каденса, скорости и
## целевой мощности плана по общей сетке слотов времени. Без прореживания
## (сэмплов ≤ `max_points`) корзина = 1 с, один слот на корзину, значение —
## сэмпл; «нет данных» — `NAN` (разрыв линии), не 0 (крит. 1).
##
## Для потоков длиннее `max_points` сэмплов корзина = ceil(n / (max_points / 2)) с,
## на корзину — два слота (крит. 2, В-18): в них для каждой серии кладутся
## минимум и максимум корзины в хронологическом порядке их сэмплов, так что
## экстремумы остаются среди самих точек графика. Если min и max — один и тот же
## сэмпл (в корзине одно значение с данными), заполняется только первый слот.
## Корзина без данных — `NAN` в обоих слотах (разрыв). Итого ≤ `max_points` слотов.
## Цель плана (`target`) всегда с данными (0 — свободная езда).
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

## Время слота, с активного времени (первый слот корзины — её начало).
var time_sec := PackedFloat32Array()
## Ширина корзины, с (1 — без прореживания).
var bucket_sec: int = 1
## Длительность потока, с.
var duration_sec: int = 0
var _values: Dictionary = {}


static func from_samples(samples: SampleStream, max_points: int = MAX_POINTS_DEFAULT) -> RideSeries:
	var s := RideSeries.new()
	var n: int = samples.size()
	s.duration_sec = n
	var limit: int = maxi(max_points, 2)
	var decimate: bool = n > limit
	# При прореживании — по два слота на корзину, корзин ≤ limit / 2.
	s.bucket_sec = maxi(ceili(float(n) / float(limit / 2)), 1) if decimate else 1
	var buckets: int = ceili(float(n) / float(s.bucket_sec)) if n > 0 else 0
	# Слоты: без прореживания — один на корзину; с прореживанием — два,
	# кроме корзины из единственного сэмпла.
	var slot_of_bucket := PackedInt32Array()
	slot_of_bucket.resize(buckets)
	var slots: int = 0
	for b in buckets:
		slot_of_bucket[b] = slots
		var first: int = b * s.bucket_sec
		var last: int = mini(first + s.bucket_sec, n)
		slots += 2 if decimate and last - first >= 2 else 1
	s.time_sec.resize(slots)
	for name in NAMES:
		var vals := PackedFloat32Array()
		vals.resize(slots)
		vals.fill(NAN)
		s._values[name] = vals
	for b in buckets:
		var first: int = b * s.bucket_sec
		var last: int = mini(first + s.bucket_sec, n)
		var slot: int = slot_of_bucket[b]
		var two_slots: bool = decimate and last - first >= 2
		s.time_sec[slot] = float(samples.time_sec[first])
		if two_slots:
			# Второй слот — середина корзины (не позже последнего сэмпла корзины).
			s.time_sec[slot + 1] = float(samples.time_sec[mini(first + maxi(s.bucket_sec / 2, 1), last - 1)])
		for name in NAMES:
			var lo_i: int = -1
			var hi_i: int = -1
			for i in range(first, last):
				if not _has(samples, name, i):
					continue
				var v: float = _value(samples, name, i)
				# Минимум — первое вхождение, максимум — последнее: при равных
				# значениях остаются два разных сэмпла (начало и конец корзины).
				if lo_i < 0 or v < _value(samples, name, lo_i):
					lo_i = i
				if hi_i < 0 or v >= _value(samples, name, hi_i):
					hi_i = i
			if lo_i < 0:
				continue
			if not two_slots or lo_i == hi_i:
				s._values[name][slot] = _value(samples, name, lo_i)
			else:
				var a: int = mini(lo_i, hi_i)
				var z: int = maxi(lo_i, hi_i)
				s._values[name][slot] = _value(samples, name, a)
				s._values[name][slot + 1] = _value(samples, name, z)
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


## Число слотов (точек серии, включая разрывы).
func size() -> int:
	return time_sec.size()


## Значения по слотам (`NAN` — разрыв); длина равна `size()`.
func values(name: String) -> PackedFloat32Array:
	return _values.get(name, PackedFloat32Array())


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


## Максимум серии по данным (экстремумы корзин — среди точек); `NAN`, если данных нет.
func peak(name: String) -> float:
	var hi: float = -INF
	for v in values(name):
		if not is_nan(v):
			hi = maxf(hi, v)
	return hi if hi > -INF else NAN


## Минимум серии по данным; `NAN`, если данных нет.
func low(name: String) -> float:
	var lo: float = INF
	for v in values(name):
		if not is_nan(v):
			lo = minf(lo, v)
	return lo if lo < INF else NAN
