class_name SpeedModel
extends RefCounted
## Модель скорости по мощности, массе и уклону (REQ-D3D-02, REQ-FRD-04 крит. 7, 8;
## REQ-WRK-08 крит. 5 — источник скорости «модель», решение В-8; константы —
## «Открытые решения» п. 15).
##
## Без ветра: P = v · (m·g·(Crr·cos θ + sin θ) + ½·ρ·CdA·v²), θ = atan(уклон / 100),
## m = масса всадника + велосипед 8 кг (вводный абзац FRD). На уклоне 0 формула
## совпадает с моделью ровной дороги D3D-02: P = ½·ρ·CdA·v³ + Crr·m·g·v.
## Установившаяся скорость находится бисекцией: при v выше корня потребная мощность
## растёт монотонно (на спуске ниже корня она отрицательна), поэтому корень единственный.
## Опорные точки при 75 кг: 200 Вт → 34 ± 3 км/ч; 100 Вт → 26 ± 3; 300 Вт → 40 ± 3;
## 200 Вт на 5 % → 15.2 ± 1.5; на 10 % → 8.4 ± 1.0; 0 Вт на −5 % → 49.8 ± 3.
##
## Уклон — полный уклон трассы g(s), а не уклон, сниженный крутизной SIM (FRD-04 крит. 8):
## крутизна влияет только на нагрузку станка, сюда её не передают.
##
## Стационарная часть — `steady_speed_kmh()` (она же `from_power()`); для потока
## 1 Гц и сцены — экземпляр с `step(power_w, weight_kg, dt_sec, grade_pct)`: скорость
## плавно стремится к установившейся (постоянная времени `TAU_SEC`), изменение за один
## сэмпл ограничено `MAX_DELTA_KMH_PER_SEC`; при 0 Вт с 30 км/ч на ровном или в подъём
## останавливается не более чем за 30 с (D3D-02 крит. 3, 4; FRD-04 крит. 7).

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
## Ниже этой скорости при нулевой мощности и нулевой установившейся скорости
## считаем, что всадник остановился.
const STOP_THRESHOLD_KMH: float = 0.1

## Текущая сглаженная скорость экземпляра, км/ч.
var speed_kmh: float = 0.0


## Установившаяся скорость, км/ч, для мощности `power_w`, массы всадника `weight_kg`
## и уклона `grade_pct` (%, «+» — подъём). Отрицательная мощность считается нулевой.
## При 0 Вт скорость ненулевая только на спуске круче, чем сопротивление качению
## (иначе 0, как в D3D-02). Монотонно растёт по мощности, убывает по уклону; на ровном
## и в подъём убывает по массе (D3D-02 крит. 1, FRD-04 крит. 7).
static func steady_speed_kmh(power_w: float, weight_kg: float, grade_pct: float = 0.0) -> float:
	var power: float = maxf(power_w, 0.0)
	var mass: float = maxf(weight_kg, 0.0) + BIKE_MASS_KG
	if power <= 0.0 and _slope_force_n(mass, grade_pct) >= 0.0:
		return 0.0
	var lo: float = 0.0
	var hi: float = MAX_SPEED_KMH / 3.6
	for i in 60:
		var mid: float = (lo + hi) * 0.5
		if power_required_w(mid, mass, grade_pct) < power:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5 * 3.6


## Синоним `steady_speed_kmh` (имя из постановки T-023).
static func from_power(power_w: float, weight_kg: float, grade_pct: float = 0.0) -> float:
	return steady_speed_kmh(power_w, weight_kg, grade_pct)


## Мощность, нужная для удержания скорости `v_ms` (м/с) при полной массе `total_mass_kg`
## на уклоне `grade_pct` (%). На спуске при малой скорости отрицательна.
static func power_required_w(v_ms: float, total_mass_kg: float, grade_pct: float = 0.0) -> float:
	return 0.5 * AIR_DENSITY * CDA_M2 * v_ms * v_ms * v_ms + _slope_force_n(total_mass_kg, grade_pct) * v_ms


## Сила сопротивления качению и скатывающая сила вдоль дороги, Н: m·g·(Crr·cos θ + sin θ).
## На уклоне 0 — ровно Crr·m·g (как в D3D-02).
static func _slope_force_n(total_mass_kg: float, grade_pct: float) -> float:
	if grade_pct == 0.0:
		return CRR * total_mass_kg * GRAVITY
	var theta: float = atan(grade_pct / 100.0)
	return (CRR * cos(theta) + sin(theta)) * total_mass_kg * GRAVITY


## Сбросить сглаженную скорость.
func reset(initial_kmh: float = 0.0) -> void:
	speed_kmh = maxf(initial_kmh, 0.0)


## Продвинуть модель на `dt_sec` при мощности `power_w`, массе `weight_kg` и полном
## уклоне трассы `grade_pct` (%); возвращает новую скорость, км/ч.
func step(power_w: float, weight_kg: float, dt_sec: float = 1.0, grade_pct: float = 0.0) -> float:
	if dt_sec <= 0.0:
		return speed_kmh
	var target: float = steady_speed_kmh(power_w, weight_kg, grade_pct)
	var alpha: float = 1.0 - exp(-dt_sec / TAU_SEC)
	var delta: float = (target - speed_kmh) * alpha
	var limit: float = MAX_DELTA_KMH_PER_SEC * dt_sec
	delta = clampf(delta, -limit, limit)
	speed_kmh = maxf(speed_kmh + delta, 0.0)
	if power_w <= 0.0 and target == 0.0 and speed_kmh < STOP_THRESHOLD_KMH:
		speed_kmh = 0.0
	return speed_kmh
