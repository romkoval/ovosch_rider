class_name SpeedModel
extends RefCounted
## Модель скорости по мощности и массе (REQ-D3D-02, REQ-WRK-08 крит. 5 — источник
## скорости «модель», решение В-8; константы — «Открытые решения» п. 15).
##
## Ровная дорога, без ветра: P = ½·ρ·CdA·v³ + Crr·m·g·v, где m = масса всадника +
## велосипед 8 кг. Установившаяся скорость находится бисекцией по монотонной функции.
## Опорные точки: 200 Вт / 75 кг → 34 ± 3 км/ч; 100 Вт → 26 ± 3; 300 Вт → 40 ± 3.
##
## Стационарная часть — `steady_speed_kmh()` (она же `from_power()`); для потока
## 1 Гц и сцены — экземпляр с `step(power_w, weight_kg, dt_sec)`: скорость плавно
## стремится к установившейся (постоянная времени `TAU_SEC`), изменение за один
## сэмпл ограничено `MAX_DELTA_KMH_PER_SEC`; при 0 Вт с 30 км/ч останавливается
## не более чем за 30 с (D3D-02 крит. 3, 4).

const AIR_DENSITY: float = 1.225      # кг/м³
const CDA_M2: float = 0.32            # м²
const CRR: float = 0.004
const BIKE_MASS_KG: float = 8.0
const GRAVITY: float = 9.81
const MAX_SPEED_KMH: float = 150.0
## Постоянная времени приближения к установившейся скорости, с.
const TAU_SEC: float = 3.0
## Ограничение изменения скорости за секунду, км/ч.
const MAX_DELTA_KMH_PER_SEC: float = 5.0
## Ниже этой скорости при нулевой мощности считаем, что всадник остановился.
const STOP_THRESHOLD_KMH: float = 0.1

## Текущая сглаженная скорость экземпляра, км/ч.
var speed_kmh: float = 0.0


## Установившаяся скорость, км/ч, для мощности `power_w` и массы всадника `weight_kg`.
## Мощность ≤ 0 → 0. Монотонно растёт по мощности и убывает по массе (D3D-02 крит. 1).
static func steady_speed_kmh(power_w: float, weight_kg: float) -> float:
	if power_w <= 0.0:
		return 0.0
	var mass: float = maxf(weight_kg, 0.0) + BIKE_MASS_KG
	var lo: float = 0.0
	var hi: float = MAX_SPEED_KMH / 3.6
	for i in 60:
		var mid: float = (lo + hi) * 0.5
		if power_required_w(mid, mass) < power_w:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5 * 3.6


## Синоним `steady_speed_kmh` (имя из постановки T-023).
static func from_power(power_w: float, weight_kg: float) -> float:
	return steady_speed_kmh(power_w, weight_kg)


## Мощность, нужная для удержания скорости `v_ms` (м/с) при полной массе `total_mass_kg`.
static func power_required_w(v_ms: float, total_mass_kg: float) -> float:
	return 0.5 * AIR_DENSITY * CDA_M2 * v_ms * v_ms * v_ms + CRR * total_mass_kg * GRAVITY * v_ms


## Сбросить сглаженную скорость.
func reset(initial_kmh: float = 0.0) -> void:
	speed_kmh = maxf(initial_kmh, 0.0)


## Продвинуть модель на `dt_sec` при мощности `power_w` и массе `weight_kg`; возвращает новую скорость, км/ч.
func step(power_w: float, weight_kg: float, dt_sec: float = 1.0) -> float:
	if dt_sec <= 0.0:
		return speed_kmh
	var target: float = steady_speed_kmh(power_w, weight_kg)
	var alpha: float = 1.0 - exp(-dt_sec / TAU_SEC)
	var delta: float = (target - speed_kmh) * alpha
	var limit: float = MAX_DELTA_KMH_PER_SEC * dt_sec
	delta = clampf(delta, -limit, limit)
	speed_kmh = maxf(speed_kmh + delta, 0.0)
	if power_w <= 0.0 and speed_kmh < STOP_THRESHOLD_KMH:
		speed_kmh = 0.0
	return speed_kmh
