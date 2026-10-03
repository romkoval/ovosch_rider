class_name RideScene
extends Node3D
## 3D-сцена заезда (REQ-D3D-01..06): велосипедист едет по `Track`, камера от третьего
## лица следует с запаздыванием, педалирование — по каденсу, окружение — из `EnvironmentSet`.
##
## Привязка к телеметрии — `bind(session, profile)`: на каждом закрытом слоте потока
## (`second_elapsed`) читается последняя строка `samples`: скорость — станка, если
## `speed_source == "trainer"`, иначе `SpeedModel.step(power, weight, 1 с)`; каденс → `Rider`.
## Дистанция интегрируется в кадре по текущей скорости и переводится в позицию через
## `Track.sample_into` (без аллокаций в `_process`, REQ-D3D-05 крит. 4). Всё «тяжёлое»
## (дорога, объекты окружения, свет, небо) строится в `set_track()`/`_ready()`.
## Трасса и окружение подменяются через интерфейсы `Track`/`EnvironmentSet` — цикл и
## привязка не знают конкретной сцены (REQ-D3D-06).

const DEFAULT_ENVIRONMENT: String = "res://src/scene3d/default_environment.tres"
const RIDER_SCENE: String = "res://src/scene3d/rider.tscn"
## Камера: позади (по горизонтальному направлению движения) и сверху от велосипедиста.
## Сглаживается ВЕКТОР СМЕЩЕНИЯ, а не позиция: расстояние и высота не зависят от скорости
## (D3D-01 крит. 1), повороты трассы камера догоняет с запаздыванием τ.
const CAMERA_BACK_M: float = 7.0
const CAMERA_UP_M: float = 3.0
const CAMERA_LOOK_UP_M: float = 1.0
const CAMERA_TAU_SEC: float = 0.25
const MAX_FRAME_DELTA_SEC: float = 0.25

@export var environment_set: EnvironmentSet = null
## Seed процедурной трассы по умолчанию.
@export var track_seed: int = 7

var track: Track = null
var speed_kmh: float = 0.0
var cadence_rpm: int = 0
var distance_m: float = 0.0
var weight_kg: float = SpeedModel.BIKE_MASS_KG + 67.0

var _session: WorkoutSession = null
var _speed_model := SpeedModel.new()
var _sample := TrackSample.new()
var _camera_offset: Vector3 = Vector3(0.0, CAMERA_UP_M, CAMERA_BACK_M)
var _road: MeshInstance3D = null
var _props: MultiMeshInstance3D = null
var _env_instance: Node = null

@onready var _rider: Rider = %Rider
@onready var _camera: Camera3D = %Camera
@onready var _sun: DirectionalLight3D = %Sun
@onready var _world_env: WorldEnvironment = %WorldEnvironment
@onready var _environment_root: Node3D = %EnvironmentRoot


func _ready() -> void:
	if environment_set == null:
		environment_set = load(DEFAULT_ENVIRONMENT)
	_apply_environment()
	if track == null:
		set_track(LoopTrack.new(track_seed))


# ---------------------------------------------------------------------------
# Трасса и окружение
# ---------------------------------------------------------------------------

## Подменить трассу: перестроить дорогу и объекты, поставить велосипедиста на старт.
func set_track(new_track: Track) -> void:
	track = new_track
	if _road != null:
		_road.queue_free()
		_road = null
	if _props != null:
		_props.queue_free()
		_props = null
	if not is_node_ready():
		return
	_road = RoadBuilder.build(track, environment_set.road_material if environment_set != null else null)
	_environment_root.add_child(_road)
	_props = _build_props()
	if _props != null:
		_environment_root.add_child(_props)
	distance_m = 0.0
	_place_rider(true)


func rider() -> Rider:
	return _rider


func camera() -> Camera3D:
	return _camera


func road() -> MeshInstance3D:
	return _road


func props() -> MultiMeshInstance3D:
	return _props


func rider_position() -> Vector3:
	return _rider.global_position


func rider_forward() -> Vector3:
	return _sample.forward


## Смещение камеры относительно велосипедиста.
func camera_offset() -> Vector3:
	return _camera.global_position - _rider.global_position


# ---------------------------------------------------------------------------
# Привязка к сессии
# ---------------------------------------------------------------------------

func bind(session: WorkoutSession, profile: Profile = null) -> void:
	unbind()
	_session = session
	weight_kg = profile.weight_kg if profile != null else WorkoutSession.DEFAULT_WEIGHT_KG
	_speed_model.reset(0.0)
	speed_kmh = 0.0
	cadence_rpm = 0
	session.executor.second_elapsed.connect(_on_second_elapsed)
	session.state_changed.connect(_on_session_state)


## Отвязать от сессии; педалирование останавливается (накат), сцена больше не двигается от телеметрии.
func unbind() -> void:
	if is_node_ready():
		_rider.set_cadence(0)
	if _session != null:
		if _session.executor.second_elapsed.is_connected(_on_second_elapsed):
			_session.executor.second_elapsed.disconnect(_on_second_elapsed)
		if _session.state_changed.is_connected(_on_session_state):
			_session.state_changed.disconnect(_on_session_state)
	_session = null


func is_bound() -> bool:
	return _session != null


## Прямое задание телеметрии (тесты, экран разработчика): скорость станка или модель.
func apply_telemetry(power_w: int, has_power: bool, cadence: int, has_cadence: bool,
		trainer_speed_kmh: float, use_trainer_speed: bool) -> void:
	if use_trainer_speed:
		speed_kmh = maxf(trainer_speed_kmh, 0.0)
	else:
		speed_kmh = _speed_model.step(float(power_w) if has_power else 0.0, weight_kg, 1.0)
	cadence_rpm = cadence if has_cadence else 0
	_rider.set_cadence(cadence_rpm)
	_rider.set_wheel_speed(speed_kmh)


# ---------------------------------------------------------------------------
# Игровой цикл
# ---------------------------------------------------------------------------

## Кадр: интегрировать дистанцию, поставить велосипедиста, подтянуть камеру. Без аллокаций.
func advance(delta: float) -> void:
	if delta <= 0.0 or track == null:
		return
	var dt: float = minf(delta, MAX_FRAME_DELTA_SEC)
	distance_m += speed_kmh / 3.6 * dt
	if track.is_loop() and distance_m >= track.length_m():
		distance_m = fmod(distance_m, track.length_m())
	_place_rider(false)
	var alpha: float = 1.0 - exp(-dt / CAMERA_TAU_SEC)
	_camera_offset = _camera_offset.lerp(_desired_camera_offset(), alpha)
	_camera.global_position = _rider.global_position + _camera_offset
	_camera.look_at(_rider.global_position + Vector3.UP * CAMERA_LOOK_UP_M, Vector3.UP)
	_rider.advance(dt)


## Смещение камеры: назад по горизонтальной проекции направления и вверх.
func _desired_camera_offset() -> Vector3:
	var flat := Vector3(_sample.forward.x, 0.0, _sample.forward.z)
	if flat.length_squared() < 1e-8:
		flat = Vector3.FORWARD
	return -flat.normalized() * CAMERA_BACK_M + Vector3.UP * CAMERA_UP_M


func _process(delta: float) -> void:
	advance(delta)


func _place_rider(snap_camera: bool) -> void:
	track.sample_into(distance_m, _sample)
	_rider.global_position = _sample.position
	_rider.look_at(_sample.position + _sample.forward, _sample.up)
	if snap_camera:
		_camera_offset = _desired_camera_offset()
		_camera.global_position = _sample.position + _camera_offset
		_camera.look_at(_sample.position + Vector3.UP * CAMERA_LOOK_UP_M, Vector3.UP)


func _on_second_elapsed(_elapsed: int, _offset: int, _remaining: int) -> void:
	if _session == null or _session.samples.size() == 0:
		return
	var row: Dictionary = _session.samples.last_row()
	var use_trainer: bool = _session.samples.speed_source == SampleStream.SPEED_SOURCE_TRAINER and bool(row["has_speed"])
	apply_telemetry(int(row["power_w"]), bool(row["has_power"]), int(row["cadence_rpm"]), bool(row["has_cadence"]),
		float(row["speed_kmh"]), use_trainer)


func _on_session_state(state: int) -> void:
	if state == WorkoutSession.State.FINISHED:
		_rider.set_cadence(0)


# ---------------------------------------------------------------------------
# Построение окружения (не в кадре)
# ---------------------------------------------------------------------------

func _apply_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = environment_set.sky_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = environment_set.ambient_color
	env.fog_enabled = true
	env.fog_light_color = environment_set.fog_color
	env.fog_density = environment_set.fog_density
	_world_env.environment = env
	_sun.light_energy = environment_set.sun_energy
	_sun.rotation_degrees = environment_set.sun_rotation_deg
	if _env_instance != null:
		_env_instance.queue_free()
		_env_instance = null
	if environment_set.environment_scene != null:
		_env_instance = environment_set.environment_scene.instantiate()
		_environment_root.add_child(_env_instance)


func _build_props() -> MultiMeshInstance3D:
	if environment_set == null or environment_set.prop_spacing_m <= 0.0:
		return null
	var per_side: int = int(track.length_m() / environment_set.prop_spacing_m)
	var count: int = mini(per_side * 2, PerfBudget.MAX_MULTIMESH_INSTANCES)
	if count <= 0:
		return null
	var mesh := BoxMesh.new()
	mesh.size = environment_set.prop_size
	if environment_set.prop_material != null:
		mesh.material = environment_set.prop_material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var sample := TrackSample.new()
	var half_height: float = environment_set.prop_size.y * 0.5
	for i in count:
		var s: float = float(i / 2) * environment_set.prop_spacing_m
		track.sample_into(s, sample)
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var pos: Vector3 = sample.position + sample.right() * side * environment_set.prop_offset_m + Vector3.UP * half_height
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
	var node := MultiMeshInstance3D.new()
	node.name = "Props"
	node.multimesh = mm
	return node
