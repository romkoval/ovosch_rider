class_name Rider
extends Node3D
## Велосипедист (REQ-D3D-04, REQ-D3D-07): модель из `RiderModel` (один тун-материал с
## контуром), педалирование — `AnimationPlayer` с анимацией оборота шатунов (1 с на оборот),
## `speed_scale = каденс / 60` (90 rpm → 1.5 об/с); каденс 0 или «нет данных» → остановка.
## Изменение `speed_scale` сглаживается (τ = `SMOOTHING_TAU_SEC`), чтобы синхронизация шла
## без рывков; цель применяется сразу при `set_cadence` — не позже следующего сэмпла
## (крит. 3). Колёса крутятся по скорости. Ноги каждый кадр ставятся двухзвенной IK
## от тазобедренного сустава к педали по текущему углу шатуна, корпус слегка покачивается
## в такт; в поворотах велосипедист наклоняется (`set_lean`, угол считает `RideScene`);
## на уклоне продольный наклон задаёт трасса (`pitch_rad` = atan(g), REQ-D3D-08 п.5).
## Анимация и меши строятся в `_ready()`; в `_process`/`advance` — только арифметика.

const SMOOTHING_TAU_SEC: float = 0.5
const PEDAL_ANIMATION: String = "pedal"
const WHEEL_RADIUS_M: float = 0.336
## Ниже этого коэффициента анимация считается остановленной.
const STOP_THRESHOLD: float = 0.02
## Покачивание корпуса в такт педалированию, рад (на полной амплитуде).
const SWAY_RAD: float = 0.035
const RIDER_MATERIAL: Material = preload("res://src/scene3d/materials/rider_toon.tres")

var target_speed_scale: float = 0.0
var speed_scale: float = 0.0
var wheel_speed_kmh: float = 0.0
var lean_rad: float = 0.0

@onready var _anim: AnimationPlayer = %PedalPlayer
@onready var _crank: Node3D = %Crank
@onready var _crank_rig: Skeleton3D = %CrankRig
@onready var _front_wheel: Node3D = %FrontWheel
@onready var _rear_wheel: Node3D = %RearWheel
@onready var _lean: Node3D = %Lean
@onready var _upper: Node3D = %Upper
@onready var _thigh_l: Node3D = %ThighL
@onready var _shin_l: Node3D = %ShinL
@onready var _shoe_l: Node3D = %ShoeL
@onready var _thigh_r: Node3D = %ThighR
@onready var _shin_r: Node3D = %ShinR
@onready var _shoe_r: Node3D = %ShoeR


func _ready() -> void:
	_build_model()
	# Шатуны продвигаются вручную в `advance` перед постановкой ног: иначе ноги ставились
	# бы по углу прошлого кадра (AnimationPlayer обрабатывается позже узла сцены).
	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_build_pedal_animation()
	_anim.play(PEDAL_ANIMATION)
	_anim.speed_scale = 0.0
	_anim.pause()
	_pose_body()


## Каденс, об/мин; ≤ 0 (или «нет данных») — остановка педалирования.
func set_cadence(rpm: int) -> void:
	target_speed_scale = maxf(float(rpm), 0.0) / 60.0


## Скорость для вращения колёс, км/ч.
func set_wheel_speed(kmh: float) -> void:
	wheel_speed_kmh = maxf(kmh, 0.0)


## Наклон в повороте, рад (> 0 — влево). Применяется к узлу `Lean` — направление
## движения (`-basis.z` корня) не меняется.
func set_lean(rad: float) -> void:
	lean_rad = rad
	if _lean != null:
		_lean.rotation = Vector3(0.0, 0.0, rad)


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


## Поставить шатун на угол φ, рад (0 — правая педаль вверху, π/2 — впереди) и позу по нему:
## эталонные ракурсы и тесты. Анимация переводится на ту же фазу — при каденсе > 0 оборот
## продолжится с этого угла. Не для кадра.
func set_crank_angle(rad: float) -> void:
	var phi: float = fposmod(rad, TAU)
	_anim.seek(phi / TAU, true)
	_crank.rotation = Vector3(phi, 0.0, 0.0)
	_pose_body()


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
	# Колесо катится вперёд (−Z): верх обода уходит вперёд — поворот вокруг X отрицательный.
	var angular: float = wheel_speed_kmh / 3.6 / WHEEL_RADIUS_M
	_front_wheel.rotate_object_local(Vector3.RIGHT, -angular * delta)
	_rear_wheel.rotate_object_local(Vector3.RIGHT, -angular * delta)
	_pose_body()


func _process(delta: float) -> void:
	advance(delta)


## Ноги — по углу шатуна, корпус — лёгкое покачивание к ноге, давящей на педаль.
func _pose_body() -> void:
	var phi: float = _crank.rotation.x
	var c: float = cos(phi)
	var s: float = sin(phi)
	var l: float = RiderModel.CRANK_LENGTH_M
	var bb: Vector3 = RiderModel.BB
	var pedal_r := Vector3(RiderModel.PEDAL_X_M, bb.y + l * c, bb.z - l * s)
	var pedal_l := Vector3(-RiderModel.PEDAL_X_M, bb.y - l * c, bb.z + l * s)
	_solve_leg(Vector3(RiderModel.HIP.x, RiderModel.HIP.y, RiderModel.HIP.z), pedal_r, _thigh_r, _shin_r, _shoe_r)
	_solve_leg(Vector3(-RiderModel.HIP.x, RiderModel.HIP.y, RiderModel.HIP.z), pedal_l, _thigh_l, _shin_l, _shoe_l)
	var effort: float = clampf(speed_scale, 0.0, 1.0)
	var sway: float = SWAY_RAD * s * effort
	var basis := Basis(Vector3.BACK, sway)
	_upper.transform = Transform3D(basis, RiderModel.PELVIS - basis * RiderModel.PELVIS)
	# Контактные педали держат угол стопы θ(φ) (кости 1, 2 скелета шатуна).
	_crank_rig.set_bone_pose_rotation(1, Quaternion(Vector3.RIGHT, RiderModel.pedal_bone_angle(phi, false)))
	_crank_rig.set_bone_pose_rotation(2, Quaternion(Vector3.RIGHT, RiderModel.pedal_bone_angle(phi, true)))


func _solve_leg(hip: Vector3, pedal: Vector3, thigh: Node3D, shin: Node3D, shoe: Node3D) -> void:
	var target: Vector3 = pedal + RiderModel.ANKLE_FROM_PEDAL
	var reach: float = RiderModel.THIGH_M + RiderModel.SHIN_M - 1e-3
	var d: Vector3 = target - hip
	if d.length() > reach:
		target = hip + d.normalized() * reach
	var knee: Vector3 = RiderModel.two_bone_joint(hip, target, RiderModel.THIGH_M, RiderModel.SHIN_M, RiderModel.KNEE_HINT)
	thigh.transform = RiderModel.bone_transform(hip, knee)
	shin.transform = RiderModel.bone_transform(knee, target)
	shoe.position = target


func _build_model() -> void:
	var m: Dictionary = RiderModel.meshes(RIDER_MATERIAL)
	(%Bike as MeshInstance3D).mesh = m["bike"]
	(_front_wheel as MeshInstance3D).mesh = m["wheel"]
	(_rear_wheel as MeshInstance3D).mesh = m["rear_wheel"]
	var arm := %CrankArm as MeshInstance3D
	arm.mesh = m["crank"]
	arm.skin = RiderModel.setup_crank_rig(_crank_rig)
	arm.skeleton = arm.get_path_to(_crank_rig)
	(_upper as MeshInstance3D).mesh = m["upper"]
	for leg in [[_thigh_l, _shin_l, _shoe_l], [_thigh_r, _shin_r, _shoe_r]]:
		(leg[0] as MeshInstance3D).mesh = m["thigh"]
		(leg[1] as MeshInstance3D).mesh = m["shin"]
		(leg[2] as MeshInstance3D).mesh = m["shoe"]
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
