class_name Rider
extends Node3D
## Велосипедист (REQ-D3D-04, REQ-D3D-07, REQ-D3D-09): велосипед и манекен из `RiderModel`
## (один тун-материал с контуром) на `Skeleton3D` по контракту `RiderRig` (25 костей; T-106a2).
## Узлов с сетками 10: `Body`, `Hair`, `Helmet`, `Eyewear`, `ShoeL`, `ShoeR` (скиннинг, вес 1
## на кость), `Bike`, `FrontWheel`, `RearWheel`, `CrankArm`. Фигура (`m`/`f`) и причёска
## (`short`/`tail`) — подмена `mesh` тех же узлов (`set_figure`, `set_hair_style`).
##
## Педалирование — `AnimationPlayer` с анимацией оборота шатунов (1 с на оборот),
## `speed_scale = каденс / 60` (90 rpm → 1.5 об/с); каденс 0 или «нет данных» → остановка.
## Изменение `speed_scale` сглаживается (τ = `SMOOTHING_TAU_SEC`), цель применяется сразу при
## `set_cadence` (крит. 3). Колёса крутятся по скорости. Каждый кадр `_pose_body` ставит позы
## костей (все — в системе узла `Lean`, скелет в нём без смещения):
## - таз S на седле, крен таза вокруг S, крен и рыскание корпуса по `spine`/`chest`,
##   компенсация в `head` (`RiderMotion`, спека «Движение по видео-референсу»);
## - ноги — двухзвенная IK от тазобедренного сустава к голеностопу: шип (`cleat`) на оси педали,
##   угол стопы θ(φ), колено вбок по спеке; руки — IK от плеча к точке хвата (предплечье с
##   кистью — одно звено, запястье прямое), кисти и сокеты `grip` на тормозных ручках;
## - хвост — пружина на `hair_tail.1/2` от ускорения корня в системе гонщика.
## Размах покачивания — коэффициент усилия k (`RiderMotion`): от P/FTP (`set_power`; решение
## Н-39 — P сэмпла сессии, FTP профиля), без мощности или FTP — от каденса; при каденсе 0 k не
## обновляется. Велосипед от педалирования не качается; наклон в повороте — узел `Lean`
## (`set_lean`), на уклоне продольный наклон задаёт трасса (REQ-D3D-08 п.5).
## Скелет, меши и массивы поз строятся в `_ready()`; в `_process`/`advance` — только
## арифметика (D3D-05 п.4).
##
## Colors (T-106a3): one toon material for all 10 nodes (`RIDER_MATERIAL`, outline —
## `next_pass`); a face's color is its region (UV0) in the material palette. `set_palette` /
## `set_region_color` give the rider its own copy of the material (two riders with different
## looks do not share colors) and write the palette; the meshes stay. Rims (`bike.rims`) —
## `set_rims`, a mesh swap of the wheel nodes.

const SMOOTHING_TAU_SEC: float = 0.5
const PEDAL_ANIMATION: String = "pedal"
const WHEEL_RADIUS_M: float = 0.336
## Ниже этого коэффициента анимация считается остановленной.
const STOP_THRESHOLD: float = 0.02
const RIDER_MATERIAL: Material = preload("res://src/scene3d/materials/rider_toon.tres")
## Фигуры и причёски манекена (слоты `body.figure`, `hair.style`; проводка `RiderLook` — T-109).
const FIGURES: Array[String] = ["m", "f"]
const HAIR_STYLES: Array[String] = ["short", "tail"]
const RIMS: Array[String] = ["deep", "shallow"]

# Индексы костей — порядок `RiderRig.BONES` (сверяется в `_ready`).
const B_PELVIS: int = 0
const B_SPINE: int = 1
const B_CHEST: int = 2
const B_NECK: int = 3
const B_HEAD: int = 4
const B_UPPERARM_L: int = 5
const B_UPPERARM_R: int = 9
const B_THIGH_L: int = 13
const B_THIGH_R: int = 18
const B_TAIL_1: int = 23
const B_TAIL_2: int = 24

var target_speed_scale: float = 0.0
var speed_scale: float = 0.0
var wheel_speed_kmh: float = 0.0
var lean_rad: float = 0.0
## Коэффициент усилия k (сглаженный); до первых данных — 1 (порог, эталонные ракурсы спеки).
var effort_k: float = 1.0
var figure: String = "m"
var hair_style: String = "short"
var rims: String = "deep"

var _power_w: int = 0
var _has_power: bool = false
var _ftp_w: int = 0
# Глобальный rest и поза кадра каждой кости (система `Lean`), родители, длины звеньев.
var _rest: Array[Transform3D] = []
var _rest_inv: Array[Transform3D] = []
var _pose: Array[Transform3D] = []
var _parent := PackedInt32Array()
var _thigh_len: float = 0.0
var _shin_len: float = 0.0
var _upper_len: float = 0.0
# Arm (T-106a2 acceptance fix, REQ-D3D-09 p.15): the elbow holds its rest angle, so the distance
# shoulder -> wrist is fixed (`_shoulder_wrist_len`); forearm and hand lengths; the rest angle
# shoulder - wrist - grip (`_wrist_rest_rad`) — the wrist bends around it by at most
# `RiderMotion.WRIST_BEND_MAX_DEG`, the rest of the shoulder motion slides the palm on the hood.
var _forearm_len: float = 0.0
var _hand_len: float = 0.0
var _shoulder_wrist_len: float = 0.0
var _wrist_rest_rad: float = 0.0
var _sole_rest_rad: float = 0.0
# Оси «вбок» костей хвоста в rest: перпендикуляр к своей кости в продольной плоскости.
var _tail_side_axis_1 := Vector3.UP
var _tail_side_axis_2 := Vector3.UP
# Пружина хвоста: углы кончика от rest (x > 0 — вправо, y > 0 — вниз), рад, их скорости;
# корень хвоста в системе гонщика на прошлых кадрах (`_tail_primed` — сколько кадров есть).
var _tail_ang := Vector2.ZERO
var _tail_vel := Vector2.ZERO
var _tail_prev_p := Vector3.ZERO
var _tail_prev_v := Vector3.ZERO
var _tail_primed: int = 0
var _meshes: Dictionary = {}
# The rider material: `RIDER_MATERIAL` until the first palette write, then an own copy.
var _material: ShaderMaterial = RIDER_MATERIAL

@onready var _anim: AnimationPlayer = %PedalPlayer
@onready var _crank: Node3D = %Crank
@onready var _crank_rig: Skeleton3D = %CrankRig
@onready var _front_wheel: Node3D = %FrontWheel
@onready var _rear_wheel: Node3D = %RearWheel
@onready var _lean: Node3D = %Lean
@onready var _skel: Skeleton3D = %Skeleton
@onready var _body: MeshInstance3D = %Body
@onready var _hair: MeshInstance3D = %Hair


func _ready() -> void:
	_build_skeleton()
	_build_model()
	# Шатуны продвигаются вручную в `advance` перед постановкой ног: иначе ноги ставились
	# бы по углу прошлого кадра (AnimationPlayer обрабатывается позже узла сцены).
	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_build_pedal_animation()
	_anim.play(PEDAL_ANIMATION)
	_anim.speed_scale = 0.0
	_anim.pause()
	_pose_body(0.0)


## Каденс, об/мин; ≤ 0 (или «нет данных») — остановка педалирования.
func set_cadence(rpm: int) -> void:
	target_speed_scale = maxf(float(rpm), 0.0) / 60.0


## Мощность сэмпла сессии и FTP профиля для коэффициента усилия k (Н-39). Без мощности
## (`has_power` = false) или при FTP ≤ 0 — запасная ветка «k по каденсу».
func set_power(power_w: int, has_power: bool, ftp_w: int) -> void:
	_power_w = power_w
	_has_power = has_power
	_ftp_w = ftp_w


## Цель k по текущим данным (до сглаживания).
func effort_target() -> float:
	return RiderMotion.effort_target(_power_w, _has_power, _ftp_w, target_speed_scale * 60.0)


## Задать k сразу, без сглаживания (эталонные ракурсы, тесты). Не для кадра.
func set_effort_k(k: float) -> void:
	effort_k = k
	_pose_body(0.0)


## Скорость для вращения колёс, км/ч.
func set_wheel_speed(kmh: float) -> void:
	wheel_speed_kmh = maxf(kmh, 0.0)


## Наклон в повороте, рад (> 0 — влево). Применяется к узлу `Lean` — направление
## движения (`-basis.z` корня) не меняется.
func set_lean(rad: float) -> void:
	lean_rad = rad
	if _lean != null:
		_lean.rotation = Vector3(0.0, 0.0, rad)


## Фигура манекена (`m`/`f`): подмена `mesh` узла `Body`. Не для кадра.
func set_figure(value: String) -> void:
	assert(FIGURES.has(value), "Rider: unknown figure %s" % value)
	figure = value
	if _body != null and _meshes.has("body_" + value):
		_body.mesh = _meshes["body_" + value]


## Причёска (`short`/`tail`): подмена `mesh` узла `Hair`, хвост — в rest. Не для кадра.
func set_hair_style(value: String) -> void:
	assert(HAIR_STYLES.has(value), "Rider: unknown hair style %s" % value)
	hair_style = value
	if _hair != null and _meshes.has("hair_" + value):
		_hair.mesh = _meshes["hair_" + value]
		_tail_reset()
		_pose_body(0.0)


## Rims (`deep`/`shallow`): mesh swap of `FrontWheel` and `RearWheel`. Not per frame.
func set_rims(value: String) -> void:
	assert(RIMS.has(value), "Rider: unknown rims %s" % value)
	rims = value
	var suffix: String = "" if value == "deep" else "_" + value
	if _front_wheel != null and _meshes.has("wheel" + suffix):
		(_front_wheel as MeshInstance3D).mesh = _meshes["wheel" + suffix]
		(_rear_wheel as MeshInstance3D).mesh = _meshes["rear_wheel" + suffix]


## Active material of all rider nodes (palette `RiderPalette.PALETTE_PARAM`).
func material() -> ShaderMaterial:
	return _material


## Write the appearance palette: 32 region colors (sRGB) and the lens highlight. Not per frame.
func set_palette(palette: PackedColorArray, lens_highlight: Color) -> void:
	RiderPalette.write(_own_material(), palette, lens_highlight)


## Write the color of region `code` only (sRGB). Not per frame.
func set_region_color(code: int, color: Color) -> void:
	RiderPalette.write_region(_own_material(), code, color)


func _own_material() -> ShaderMaterial:
	if _material == RIDER_MATERIAL:
		_material = RIDER_MATERIAL.duplicate() as ShaderMaterial
		for node in find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).material_override = _material
	return _material


## Продольный наклон велосипедиста, рад (> 0 — нос вверх): угол направления движения
## (`-basis.z`) к горизонту. На уклоне корень ставится по касательной трассы, поэтому
## наклон = atan(g) (REQ-D3D-08 п.5); наклон в повороте (`Lean`) на него не влияет.
func pitch_rad() -> float:
	var fwd: Vector3 = -global_transform.basis.z.normalized()
	return atan2(fwd.y, Vector2(fwd.x, fwd.z).length())


func is_pedaling() -> bool:
	return speed_scale > STOP_THRESHOLD


func crank_rotation_rad() -> float:
	return _crank.rotation.x


func skeleton() -> Skeleton3D:
	return _skel


## Поза кости в системе узла `Lean` (точки посадки — по контракту скелета). Для тестов.
func bone_pose(bone: String) -> Transform3D:
	return _skel.get_bone_global_pose(_skel.find_bone(bone))


## Поза кости в мировых координатах. Для тестов.
func bone_global(bone: String) -> Transform3D:
	return _skel.global_transform * bone_pose(bone)


## Углы кончика хвоста от rest в системе головы, рад: x > 0 — вправо, y > 0 — вниз.
func tail_angles() -> Vector2:
	return _tail_ang


## Поставить шатун на угол φ, рад (0 — правая педаль вверху, π/2 — впереди) и позу по нему:
## эталонные ракурсы и тесты. Анимация переводится на ту же фазу — при каденсе > 0 оборот
## продолжится с этого угла; хвост — в rest. Не для кадра.
func set_crank_angle(rad: float) -> void:
	var phi: float = fposmod(rad, TAU)
	_anim.seek(phi / TAU, true)
	_crank.rotation = Vector3(phi, 0.0, 0.0)
	_tail_reset()
	_pose_body(0.0)


## Продвинуть анимацию на `delta` с (доступно тестам). Отдельно стоящий велосипедист
## продвигается из своего `_process`; внутри `RideScene` его `_process` выключен и
## `advance` вызывает только сцена — ровно один раз за кадр.
func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	var alpha: float = 1.0 - exp(-delta / SMOOTHING_TAU_SEC)
	speed_scale += (target_speed_scale - speed_scale) * alpha
	if absf(speed_scale - target_speed_scale) < 0.001:
		speed_scale = target_speed_scale
	if speed_scale > STOP_THRESHOLD:
		_anim.speed_scale = speed_scale
		if not _anim.is_playing():
			_anim.play(PEDAL_ANIMATION)
	else:
		if _anim.is_playing():
			_anim.pause()
		_anim.speed_scale = 0.0
	if _anim.is_playing():
		_anim.advance(delta)
	# k: при каденсе 0 не обновляется — поза стоит (D3D-04 п.2).
	if target_speed_scale > 0.0:
		effort_k = RiderMotion.smooth_effort(effort_k, effort_target(), delta)
	# Колесо катится вперёд (−Z): верх обода уходит вперёд — поворот вокруг X отрицательный.
	var angular: float = wheel_speed_kmh / 3.6 / WHEEL_RADIUS_M
	_front_wheel.rotate_object_local(Vector3.RIGHT, -angular * delta)
	_rear_wheel.rotate_object_local(Vector3.RIGHT, -angular * delta)
	_pose_body(delta)


func _process(delta: float) -> void:
	advance(delta)


## Позы всех костей по углу шатуна φ и k; `dt` > 0 — шаг пружины хвоста.
func _pose_body(dt: float) -> void:
	var phi: float = _crank.rotation.x
	var k: float = effort_k
	var rho_p: float = RiderMotion.pelvis_roll_rad(phi, k)
	var rho_c: float = RiderMotion.chest_roll_rad(phi, k)
	var psi_c: float = RiderMotion.chest_yaw_rad(phi, k)
	var half: float = (rho_c - rho_p) * 0.5
	var share: float = RiderMotion.SPINE_YAW_SHARE
	var m_pelvis: Transform3D = _turn(B_PELVIS, rho_p, 0.0, Transform3D.IDENTITY)
	var m_spine: Transform3D = _turn(B_SPINE, half, psi_c * share, m_pelvis)
	var m_chest: Transform3D = _turn(B_CHEST, half, psi_c * (1.0 - share), m_spine)
	var m_head: Transform3D = _turn(B_HEAD, -RiderMotion.HEAD_COMP * rho_c, -RiderMotion.HEAD_COMP * psi_c, m_chest)
	_pose[B_PELVIS] = m_pelvis * _rest[B_PELVIS]
	_pose[B_SPINE] = m_spine * _rest[B_SPINE]
	_pose[B_CHEST] = m_chest * _rest[B_CHEST]
	_pose[B_NECK] = m_chest * _rest[B_NECK]
	_pose[B_HEAD] = m_head * _rest[B_HEAD]
	_solve_arm(B_UPPERARM_R, m_chest)
	_solve_arm(B_UPPERARM_L, m_chest)
	_solve_leg(B_THIGH_R, phi, m_pelvis, 1.0)
	_solve_leg(B_THIGH_L, phi + PI, m_pelvis, -1.0)
	_step_tail(m_head, dt)
	_pose_tail(m_head)
	for i in _pose.size():
		var p: int = _parent[i]
		var local: Transform3D = _pose[i] if p < 0 else _pose[p].affine_inverse() * _pose[i]
		_skel.set_bone_pose_position(i, local.origin)
		_skel.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())
	# Контактные педали держат угол стопы θ(φ) (кости 1, 2 скелета шатуна).
	_crank_rig.set_bone_pose_rotation(1, Quaternion(Vector3.RIGHT, RiderModel.pedal_bone_angle(phi, false)))
	_crank_rig.set_bone_pose_rotation(2, Quaternion(Vector3.RIGHT, RiderModel.pedal_bone_angle(phi, true)))


## Смещение кости `bone` в системе `Lean` (M = поза · rest⁻¹): поворот на крен `roll` и
## рыскание `yaw` вокруг её сустава в rest поверх смещения родителя `parent_m`.
func _turn(bone: int, roll: float, yaw: float, parent_m: Transform3D) -> Transform3D:
	var b: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, roll)
	var o: Vector3 = _rest[bone].origin
	return parent_m * Transform3D(b, o - b * o)


## Рука: плечо — с грудью; ладонь (сокет `grip`) — в точке хвата тормозной ручки; предплечье с
## кистью — одно жёсткое звено «локоть → точка хвата» (запястье держит изгиб rest, ≈ 2.3°, —
## прямое, спека: ≤ 5° от линии предплечья); локоть — IK «плечо → точка хвата» с направлением
## сгиба rest, угол локтя «дышит» с плечами.
## Arm to the hood (spec "What to code in T-106a2" p.8, rev. 4.3): the elbow keeps its rest
## angle; the change of the distance shoulder -> grip (body sway) is taken by the wrist turning
## the hand around `grip` in the arm plane (≤ `RiderMotion.WRIST_BEND_MAX_DEG` from rest), the
## remainder slides the palm along the line shoulder -> grip (a few mm, spec ≤ 0.015 m). No
## allocations (per frame).
func _solve_arm(b_upper: int, m_chest: Transform3D) -> void:
	var b_fore: int = b_upper + 1
	var b_hand: int = b_upper + 2
	var b_grip: int = b_upper + 3
	var shoulder: Vector3 = m_chest * _rest[b_upper].origin
	var grip: Vector3 = _rest[b_grip].origin
	var sw: float = _shoulder_wrist_len
	var l3: float = _hand_len
	var reach: float = grip.distance_to(shoulder)
	# Wrist angle shoulder - wrist - grip that gives this reach, within the bend limit.
	var cos_a: float = clampf((sw * sw + l3 * l3 - reach * reach) / (2.0 * sw * l3), -1.0, 1.0)
	var bend: float = deg_to_rad(RiderMotion.WRIST_BEND_MAX_DEG)
	var alpha: float = clampf(acos(cos_a), _wrist_rest_rad - bend, _wrist_rest_rad + bend)
	var reach_ok: float = sqrt(sw * sw + l3 * l3 - 2.0 * sw * l3 * cos(alpha))
	grip = shoulder + (grip - shoulder) * (reach_ok / reach)
	var wrist: Vector3 = RiderModel.two_bone_joint(shoulder, grip, sw, l3, _rest[b_hand].origin - _rest[b_upper].origin)
	# Elbow on its circle around shoulder -> wrist, nearest to the rest forearm carried with the
	# hand (the hand turned from rest): the wrist bends as little as possible out of plane.
	var hand_rest: Vector3 = _rest[b_grip].origin - _rest[b_hand].origin
	var turn := Quaternion(hand_rest.normalized(), (grip - wrist).normalized())
	var elbow_guess: Vector3 = wrist + turn * (_rest[b_fore].origin - _rest[b_hand].origin)
	var elbow: Vector3 = RiderModel.two_bone_joint(shoulder, wrist, _upper_len, _forearm_len, elbow_guess - shoulder)
	_pose[b_upper] = Transform3D(RiderModel.bone_basis(elbow - shoulder), shoulder)
	_pose[b_fore] = Transform3D(RiderModel.bone_basis(wrist - elbow), elbow)
	_pose[b_hand] = Transform3D(RiderModel.bone_basis(grip - wrist), wrist)
	_pose[b_grip] = _pose[b_hand] * _rest_inv[b_hand] * _rest[b_grip]


## Нога стороны `sx` (+1 — правая) при угле шатуна этой стороны: шип на оси педали, подошва
## под углом θ(φ), колено — IK с заданным |x| (колено вбок), бедро от тазобедренного сустава
## (движется с тазом).
func _solve_leg(b_thigh: int, side_phi: float, m_pelvis: Transform3D, sx: float) -> void:
	var b_shin: int = b_thigh + 1
	var b_foot: int = b_thigh + 2
	var l: float = RiderModel.CRANK_LENGTH_M
	var cleat := Vector3(sx * RiderModel.PEDAL_X_M, RiderModel.BB.y + l * cos(side_phi), RiderModel.BB.z - l * sin(side_phi))
	var rot := Basis(Vector3.RIGHT, RiderMotion.foot_pitch_rad(side_phi) - _sole_rest_rad)
	var ankle: Vector3 = cleat - rot * (_rest[b_thigh + 3].origin - _rest[b_foot].origin)
	var hip: Vector3 = m_pelvis * _rest[b_thigh].origin
	var knee_x: float = sx * RiderMotion.knee_x(side_phi, effort_k)
	var knee: Vector3 = RiderModel.two_bone_joint_x(hip, ankle, _thigh_len, _shin_len, RiderModel.KNEE_HINT, knee_x)
	_pose[b_thigh] = Transform3D(RiderModel.bone_basis(knee - hip), hip)
	_pose[b_shin] = Transform3D(RiderModel.bone_basis(ankle - knee), knee)
	_pose[b_foot] = Transform3D(rot * _rest[b_foot].basis, ankle)
	var m_foot: Transform3D = _pose[b_foot] * _rest_inv[b_foot]
	_pose[b_thigh + 3] = m_foot * _rest[b_thigh + 3]
	_pose[b_thigh + 4] = m_foot * _rest[b_thigh + 4]


## Шаг пружины хвоста за `dt`: ускорение корня в системе гонщика (с наклоном `Lean`) → в систему
## головы → угловое «отставание» кончика; полу-неявный Эйлер с подшагами, упор в пределы.
func _step_tail(m_head: Transform3D, dt: float) -> void:
	if dt <= 0.0:
		return
	var p: Vector3 = _lean.transform * (m_head * _rest[B_TAIL_1].origin)
	if _tail_primed == 0:
		_tail_prev_p = p
		_tail_primed = 1
		return
	var v: Vector3 = (p - _tail_prev_p) / dt
	_tail_prev_p = p
	if _tail_primed == 1:
		_tail_prev_v = v
		_tail_primed = 2
		return
	var a: Vector3 = (v - _tail_prev_v) / dt
	_tail_prev_v = v
	if a.length() > RiderMotion.TAIL_ACCEL_MAX:
		a = a.normalized() * RiderMotion.TAIL_ACCEL_MAX
	var local: Vector3 = (_lean.transform.basis * m_head.basis).transposed() * a
	# Корень уходит вправо — кончик отстаёт влево; корень вверх — кончик вниз.
	var force := Vector2(-local.x, local.y) / RiderMotion.TAIL_LEVER_M
	var w: float = TAU * RiderMotion.TAIL_FREQ_HZ
	var damp: float = 2.0 * RiderMotion.TAIL_DAMPING * w
	var steps: int = clampi(ceili(dt / RiderMotion.TAIL_SUBSTEP_SEC), 1, RiderMotion.TAIL_MAX_SUBSTEPS)
	var h: float = dt / float(steps)
	var side_max: float = deg_to_rad(RiderMotion.TAIL_SIDE_MAX_DEG)
	var vert_max: float = deg_to_rad(RiderMotion.TAIL_VERT_MAX_DEG)
	for i in steps:
		_tail_vel += (force - _tail_ang * (w * w) - _tail_vel * damp) * h
		_tail_ang += _tail_vel * h
		if absf(_tail_ang.x) > side_max:
			_tail_ang.x = signf(_tail_ang.x) * side_max
			_tail_vel.x = 0.0
		if absf(_tail_ang.y) > vert_max:
			_tail_ang.y = signf(_tail_ang.y) * vert_max
			_tail_vel.y = 0.0
	var cone: float = deg_to_rad(RiderMotion.TAIL_CONE_DEG)
	if _tail_ang.length() > cone:
		_tail_ang = _tail_ang.normalized() * cone


## Позы `hair_tail.1/2` от головы: угол кончика делится между костями (вторая догибается на
## `TAIL_CURL` от первой, кончик в сумме — на угол пружины).
func _pose_tail(m_head: Transform3D) -> void:
	var w1: float = 1.0 / (1.0 + 0.5 * RiderMotion.TAIL_CURL)
	var m1: Transform3D = m_head * _tail_turn(B_TAIL_1, _tail_ang * w1, _tail_side_axis_1)
	_pose[B_TAIL_1] = m1 * _rest[B_TAIL_1]
	var m2: Transform3D = m1 * _tail_turn(B_TAIL_2, _tail_ang * (w1 * RiderMotion.TAIL_CURL), _tail_side_axis_2)
	_pose[B_TAIL_2] = m2 * _rest[B_TAIL_2]


## Поворот вокруг начала кости хвоста: вбок — вокруг `side_axis`, перпендикуляра к этой кости в
## продольной плоскости (+ — кончик вправо), вверх-вниз — вокруг X (+ — кончик вниз).
func _tail_turn(bone: int, ang: Vector2, side_axis: Vector3) -> Transform3D:
	var b: Basis = Basis(Vector3.RIGHT, ang.y) * Basis(side_axis, ang.x)
	var o: Vector3 = _rest[bone].origin
	return Transform3D(b, o - b * o)


func _tail_reset() -> void:
	_tail_ang = Vector2.ZERO
	_tail_vel = Vector2.ZERO
	_tail_primed = 0


## Скелет по контракту и массивы поз (один раз).
func _build_skeleton() -> void:
	RiderRig.build_skeleton(_skel)
	assert(_skel.get_bone_count() == RiderRig.BONE_COUNT)
	_rest.resize(RiderRig.BONE_COUNT)
	_rest_inv.resize(RiderRig.BONE_COUNT)
	_pose.resize(RiderRig.BONE_COUNT)
	_parent.resize(RiderRig.BONE_COUNT)
	for i in RiderRig.BONE_COUNT:
		var bone_name: String = RiderRig.BONES[i][0]
		assert(_skel.get_bone_name(i) == bone_name, "Rider: bone order differs from RiderRig.BONES")
		_rest[i] = Transform3D(RiderRig.rest_basis(bone_name), RiderRig.BONES[i][2])
		_rest_inv[i] = _rest[i].affine_inverse()
		_pose[i] = _rest[i]
		_parent[i] = _skel.get_bone_parent(i)
	_thigh_len = RiderRig.span("thigh.R", "shin.R")
	_shin_len = RiderRig.span("shin.R", "foot.R")
	_upper_len = RiderRig.span("upperarm.R", "forearm.R")
	_forearm_len = RiderRig.span("forearm.R", "hand.R")
	_hand_len = RiderRig.span("hand.R", "grip.R")
	_shoulder_wrist_len = RiderRig.span("upperarm.R", "hand.R")
	var wr: Vector3 = RiderRig.head("hand.R")
	_wrist_rest_rad = (RiderRig.head("upperarm.R") - wr).angle_to(RiderRig.head("grip.R") - wr)
	_sole_rest_rad = RiderRig.rest_sole_pitch_rad()
	# Поворот вокруг оси «направление кости × X» на + уводит кончик кости к +X.
	_tail_side_axis_1 = _rest[B_TAIL_1].basis.y.normalized().cross(Vector3.RIGHT).normalized()
	_tail_side_axis_2 = _rest[B_TAIL_2].basis.y.normalized().cross(Vector3.RIGHT).normalized()


func _build_model() -> void:
	_meshes = RiderModel.meshes(RIDER_MATERIAL)
	(%Bike as MeshInstance3D).mesh = _meshes["bike"]
	(_front_wheel as MeshInstance3D).mesh = _meshes["wheel"]
	(_rear_wheel as MeshInstance3D).mesh = _meshes["rear_wheel"]
	var arm := %CrankArm as MeshInstance3D
	arm.mesh = _meshes["crank"]
	arm.skin = RiderModel.setup_crank_rig(_crank_rig)
	arm.skeleton = arm.get_path_to(_crank_rig)
	var skin: Skin = RiderModel.rider_skin()
	var parts: Dictionary = {"Body": "body_" + figure, "Hair": "hair_" + hair_style, "Helmet": "helmet",
		"Eyewear": "eyewear", "ShoeL": "shoe_l", "ShoeR": "shoe_r"}
	for part in parts:
		var mi := _skel.get_node(NodePath(part)) as MeshInstance3D
		mi.mesh = _meshes[parts[part]]
		mi.skin = skin
		mi.skeleton = mi.get_path_to(_skel)
	# Тень от обеих сторон граней: тонкие трубки и незакрытые торцы не дают «дыр» в тени.
	for node in find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED


func _build_pedal_animation() -> void:
	var anim := Animation.new()
	anim.length = 1.0
	anim.loop_mode = Animation.LOOP_LINEAR
	var track_idx: int = anim.add_track(Animation.TYPE_VALUE)
	var root: Node = _anim.get_node(_anim.root_node)
	anim.track_set_path(track_idx, NodePath(str(root.get_path_to(_crank)) + ":rotation"))
	anim.track_set_interpolation_type(track_idx, Animation.INTERPOLATION_LINEAR)
	anim.track_insert_key(track_idx, 0.0, Vector3(0.0, 0.0, 0.0))
	anim.track_insert_key(track_idx, 0.5, Vector3(PI, 0.0, 0.0))
	anim.track_insert_key(track_idx, 1.0, Vector3(TAU, 0.0, 0.0))
	var library := AnimationLibrary.new()
	library.add_animation(PEDAL_ANIMATION, anim)
	_anim.add_animation_library("", library)
