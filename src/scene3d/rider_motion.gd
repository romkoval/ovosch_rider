class_name RiderMotion
extends RefCounted
## Движение гонщика при педалировании по видео-референсу владельца (REQ-D3D-09 п.14–18;
## арт-библия «Гонщик» → «Движение по видео-референсу», ред. 3, список «Что закодировать в
## T-106a2»; «Причёски» → «Движение хвоста»). Константы — только здесь; функции — чистая
## арифметика без аллокаций: их зовёт кадр `Rider` (D3D-05 п.4), а тесты — напрямую.
##
## Знаки (спека «Знаки и общая формула»): φ — `Crank.rotation.x` (0 — правая педаль вверху,
## π/2 — впереди); крен ρ > 0 — правая сторона (+X) вниз, поворот на +ρ вокруг
## `Vector3.FORWARD`; рыскание ψ > 0 — правое плечо вперёд, поворот на +ψ вокруг `Vector3.UP`.
## Параметр движения = среднее + A · k · cos(φ − фаза); угол стопы на k не умножается. Левая
## сторона — то же при φ + π.

## 1. Кривая угла стопы θ (линия подошвы «пятка → шип» к горизонту, «+» — носок вверх).
const THETA_MEAN_DEG: float = -14.0
const THETA_AMP_DEG: float = 12.0
const THETA_PHASE_DEG: float = 100.0
## 2. Колено вбок: |колено.x| = среднее + A·k·cos(φ − фаза) — сдвиг полюса IK колена по X.
const KNEE_X_MEAN_M: float = 0.100
const KNEE_X_AMP_M: float = 0.008
const KNEE_X_PHASE_DEG: float = 0.0
## 3. Крен таза — поворот кости `pelvis` вокруг опорной точки S (S не двигается).
const PELVIS_ROLL_AMP_DEG: float = 0.6
const PELVIS_ROLL_PHASE_DEG: float = 180.0
## 4. Крен корпуса (грудь относительно велосипеда, всего): `pelvis` — крен таза, `spine` и
## `chest` — по половине остатка.
const CHEST_ROLL_AMP_DEG: float = 1.5
const CHEST_ROLL_PHASE_DEG: float = 150.0
## 5. Рыскание корпуса: `spine` — 0.4, `chest` — 0.6.
const CHEST_YAW_AMP_DEG: float = 0.8
const CHEST_YAW_PHASE_DEG: float = 90.0
const SPINE_YAW_SHARE: float = 0.4
## 6. Голова: крен и рыскание груди гасятся в кости `head` этой долей.
const HEAD_COMP: float = 0.7
## 7. Коэффициент усилия k = clamp(K_MIN + K_SLOPE · P/FTP, K_MIN, K_MAX), сглаживание первого
## порядка с τ = K_TAU_SEC; без мощности или FTP — k = clamp(каденс / 90, 0, 1); при каденсе 0
## k не обновляется (решение Н-39: P — сэмпл сессии, FTP — профиль).
const K_MIN: float = 0.35
const K_SLOPE: float = 0.65
const K_MAX: float = 1.3
const K_TAU_SEC: float = 0.6
const K_CADENCE_REF_RPM: float = 90.0
const K_CADENCE_MAX: float = 1.0
## 8. Пределы, которые проверяют тесты (спека п.8 списка).
const CHEST_ROLL_LIMIT_DEG: float = 2.0
const HEAD_SHIFT_LIMIT_M: float = 0.02
const HEAD_WORLD_ROLL_LIMIT_DEG: float = 0.6
const PELVIS_ROLL_LIMIT_DEG: float = 1.0
## Arms (spec p.8, rev. 4.3): the elbow holds its rest angle; body sway is taken by the wrist
## turning the hand around `grip` — at most this far from rest (the wrist stays ≤ 5° from the
## forearm line in absolute terms: rest 2.3° + 2.5°) — and the remainder slides the palm on the
## hood (spec ≤ 0.015 m).
const WRIST_BEND_MAX_DEG: float = 2.5
## Elbow limit of the spec (140°) with a 1° margin — checked by the tests.
const ELBOW_MIN_DEG: float = 141.0
## Пружина хвоста (`hair.style` = `tail`): собственная частота 1.5–2 Гц, затухание 0.3–0.5 от
## критического, отклонение кончика вбок до ±8°, вверх-вниз до ±4°, конус 20° от rest.
## Возбуждение — ускорение корня хвоста в системе гонщика (покачивание корпуса и наклон в
## повороте), приведённое к системе головы; плечо `TAIL_LEVER_M`. Вторая кость догибается на
## `TAIL_CURL` от угла первой (кончик отстаёт сильнее корня).
const TAIL_FREQ_HZ: float = 1.75
const TAIL_DAMPING: float = 0.4
const TAIL_SIDE_MAX_DEG: float = 8.0
const TAIL_VERT_MAX_DEG: float = 4.0
const TAIL_CONE_DEG: float = 20.0
const TAIL_LEVER_M: float = 0.12
const TAIL_CURL: float = 0.4
## Ограничение ускорения корня, м/с²: скачок позы (тест ставит шатун без кадров) не
## «выстреливает» хвостом.
const TAIL_ACCEL_MAX: float = 30.0
## Шаг интегрирования пружины, с (полу-неявный Эйлер устойчив при ω·h < 2; здесь ω·h ≈ 0.09).
const TAIL_SUBSTEP_SEC: float = 1.0 / 120.0
const TAIL_MAX_SUBSTEPS: int = 8


## A · k · cos(φ − фаза), рад или м — общая формула параметра движения.
static func wave(amp: float, phase_deg: float, crank_rad: float, k: float) -> float:
	return amp * k * cos(crank_rad - deg_to_rad(phase_deg))


## θ(φ) = −14° + 12°·cos(φ − 100°), рад (от −2° при 100° до −26° при 280°); от k не зависит.
static func foot_pitch_rad(crank_rad: float) -> float:
	return deg_to_rad(THETA_MEAN_DEG) + wave(deg_to_rad(THETA_AMP_DEG), THETA_PHASE_DEG, crank_rad, 1.0)


## |колено.x| своей стороны при угле φ этой стороны, м.
static func knee_x(crank_rad: float, k: float) -> float:
	return KNEE_X_MEAN_M + wave(KNEE_X_AMP_M, KNEE_X_PHASE_DEG, crank_rad, k)


## Крен таза ρ_p, рад.
static func pelvis_roll_rad(crank_rad: float, k: float) -> float:
	return wave(deg_to_rad(PELVIS_ROLL_AMP_DEG), PELVIS_ROLL_PHASE_DEG, crank_rad, k)


## Крен корпуса ρ_c (грудь относительно велосипеда), рад.
static func chest_roll_rad(crank_rad: float, k: float) -> float:
	return wave(deg_to_rad(CHEST_ROLL_AMP_DEG), CHEST_ROLL_PHASE_DEG, crank_rad, k)


## Рыскание корпуса ψ_c (грудь), рад.
static func chest_yaw_rad(crank_rad: float, k: float) -> float:
	return wave(deg_to_rad(CHEST_YAW_AMP_DEG), CHEST_YAW_PHASE_DEG, crank_rad, k)


## Есть ли у сцены мощность и FTP для основной ветки k (иначе — запасная «k по каденсу»).
static func has_effort_source(has_power: bool, ftp_w: int) -> bool:
	return has_power and ftp_w > 0


## Целевое k (до сглаживания): основная ветка — от P/FTP, запасная — от каденса.
static func effort_target(power_w: int, has_power: bool, ftp_w: int, cadence_rpm: float) -> float:
	if has_effort_source(has_power, ftp_w):
		return clampf(K_MIN + K_SLOPE * maxf(float(power_w), 0.0) / float(ftp_w), K_MIN, K_MAX)
	return clampf(cadence_rpm / K_CADENCE_REF_RPM, 0.0, K_CADENCE_MAX)


## Шаг сглаживания k первого порядка за `delta` с.
static func smooth_effort(k: float, target: float, delta: float) -> float:
	return k + (target - k) * (1.0 - exp(-maxf(delta, 0.0) / K_TAU_SEC))
