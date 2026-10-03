class_name Rider
extends Node3D
## Велосипедист из примитивов (REQ-D3D-04): педалирование — `AnimationPlayer` с анимацией
## оборота шатунов (1 с на оборот), `speed_scale = каденс / 60` (90 rpm → 1.5 об/с);
## каденс 0 или «нет данных» → остановка. Изменение `speed_scale` сглаживается
## (τ = `SMOOTHING_TAU_SEC`), чтобы синхронизация шла без рывков; цель применяется сразу
## при `set_cadence` — не позже следующего сэмпла (крит. 3). Колёса крутятся по скорости.
## Анимация строится в `_ready()`; в `_process` — только арифметика.

const SMOOTHING_TAU_SEC: float = 0.5
const PEDAL_ANIMATION: String = "pedal"
const WHEEL_RADIUS_M: float = 0.35
## Ниже этого коэффициента анимация считается остановленной.
const STOP_THRESHOLD: float = 0.02

var target_speed_scale: float = 0.0
var speed_scale: float = 0.0
var wheel_speed_kmh: float = 0.0

@onready var _anim: AnimationPlayer = %PedalPlayer
@onready var _crank: Node3D = %Crank
@onready var _front_wheel: Node3D = %FrontWheel
@onready var _rear_wheel: Node3D = %RearWheel


func _ready() -> void:
	_build_pedal_animation()
	_anim.play(PEDAL_ANIMATION)
	_anim.speed_scale = 0.0
	_anim.pause()


## Каденс, об/мин; ≤ 0 (или «нет данных») — остановка педалирования.
func set_cadence(rpm: int) -> void:
	target_speed_scale = maxf(float(rpm), 0.0) / 60.0


## Скорость для вращения колёс, км/ч.
func set_wheel_speed(kmh: float) -> void:
	wheel_speed_kmh = maxf(kmh, 0.0)


func is_pedaling() -> bool:
	return speed_scale > STOP_THRESHOLD


func crank_rotation_rad() -> float:
	return _crank.rotation.x


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
	var angular: float = wheel_speed_kmh / 3.6 / WHEEL_RADIUS_M
	_front_wheel.rotate_object_local(Vector3.RIGHT, angular * delta)
	_rear_wheel.rotate_object_local(Vector3.RIGHT, angular * delta)


func _process(delta: float) -> void:
	advance(delta)


func _build_pedal_animation() -> void:
	var anim := Animation.new()
	anim.length = 1.0
	anim.loop_mode = Animation.LOOP_LINEAR
	var track_idx: int = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track_idx, NodePath("Crank:rotation"))
	anim.track_set_interpolation_type(track_idx, Animation.INTERPOLATION_LINEAR)
	anim.track_insert_key(track_idx, 0.0, Vector3(0.0, 0.0, 0.0))
	anim.track_insert_key(track_idx, 0.5, Vector3(PI, 0.0, 0.0))
	anim.track_insert_key(track_idx, 1.0, Vector3(TAU, 0.0, 0.0))
	var library := AnimationLibrary.new()
	library.add_animation(PEDAL_ANIMATION, anim)
	_anim.add_animation_library("", library)
