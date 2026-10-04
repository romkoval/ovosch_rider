class_name RideScene
extends Node3D
## 3D-сцена заезда (REQ-D3D-01..07): велосипедист едет по `Track`, камера от третьего
## лица следует с запаздыванием, педалирование — по каденсу, окружение — из `EnvironmentSet`:
## стилизованный «нарисованный» мир (тун-свет, контуры) — дорога с разметкой, обочина с
## бордюром и отбойником, рельеф с холмами, деревья и трава, небо с облаками.
##
## Привязка к телеметрии — `bind(session, profile)`: на каждом закрытом слоте потока
## (`second_elapsed`) читается последняя строка `samples`: скорость — станка, если
## `speed_source == "trainer"`, иначе `SpeedModel.step(power, weight, 1 с)`; каденс → `Rider`.
## Дистанция интегрируется в кадре по текущей скорости и переводится в позицию через
## `Track.sample_into` (без аллокаций в `_process`, REQ-D3D-05 крит. 4). Всё «тяжёлое»
## (дорога, обочина, рельеф, растительность, свет, небо) строится в `set_track()`/`_ready()`.
## В поворотах велосипедист наклоняется на угол atan(v²·κ/g), κ — кривизна трассы.
## Трасса и окружение подменяются через интерфейсы `Track`/`EnvironmentSet` — цикл и
## привязка не знают конкретной сцены (REQ-D3D-06). Трасса каталога — `set_route(id)`
## (`RouteWorld`: план-схема + профиль + набор окружения); по умолчанию — `flat`, поэтому
## тренировка по плану идёт на равнине (REQ-D3D-08 п.13). Скорость от уклона не зависит
## (модель — ровная дорога, D3D-02), высота и продольный наклон велосипедиста — по профилю.

const DEFAULT_ENVIRONMENT: String = "res://src/scene3d/default_environment.tres"
const RIDER_SCENE: String = "res://src/scene3d/rider.tscn"
const DEFAULT_ROAD_MATERIAL: String = "res://src/scene3d/materials/road.tres"
const DEFAULT_WORLD_MATERIAL: String = "res://src/scene3d/materials/world_toon.tres"
const DEFAULT_TERRAIN_MATERIAL: String = "res://src/scene3d/materials/grass.tres"
const DEFAULT_SKY_MATERIAL: String = "res://src/scene3d/materials/sky.tres"
const DEFAULT_WATER_MATERIAL: String = "res://src/scene3d/materials/water.tres"
## Камера: позади (по горизонтальному направлению движения) и сверху от велосипедиста.
## Сглаживается УГОЛ направления (yaw), а не вектор смещения: расстояние и высота
## постоянны при любой скорости и на любых поворотах (D3D-01 крит. 1), повороты
## трассы камера догоняет с запаздыванием τ. Камера смотрит не в велосипедиста, а на
## точку дороги впереди него (`CAMERA_LOOK_AHEAD_M`): гонщик — в нижней трети кадра,
## дорога уходит к горизонту над ним. Камера чуть смещена влево от линии движения
## (`CAMERA_SIDE_RAD`, к середине дороги): вид в три четверти — читаются руки, руль, рама;
## горизонтальное расстояние до велосипедиста при этом остаётся ровно `CAMERA_BACK_M`.
const CAMERA_BACK_M: float = 3.8
const CAMERA_UP_M: float = 2.1
const CAMERA_SIDE_RAD: float = -0.13
const CAMERA_LOOK_UP_M: float = 0.6
const CAMERA_LOOK_AHEAD_M: float = 6.0
const CAMERA_TAU_SEC: float = 0.25
const MAX_FRAME_DELTA_SEC: float = 0.25
## Наклон в повороте: шаг оценки кривизны, усиление (немного больше физического — чтобы
## читался на пологих поворотах), предел и сглаживание.
const LEAN_PROBE_M: float = 6.0
const LEAN_GAIN: float = 1.6
const LEAN_MAX_RAD: float = 0.45
const LEAN_TAU_SEC: float = 0.35
const GRAVITY: float = 9.81

@export var environment_set: EnvironmentSet = null
## Трасса каталога по умолчанию (`RouteCatalog`); пустая строка — процедурная петля
## `LoopTrack(track_seed)` на окружении по умолчанию.
@export var route_id: String = RouteCatalog.DEFAULT_ID
## Seed процедурной петли (при пустом `route_id`).
@export var track_seed: int = 7

var track: Track = null
var speed_kmh: float = 0.0
var cadence_rpm: int = 0
var distance_m: float = 0.0
var weight_kg: float = SpeedModel.BIKE_MASS_KG + 67.0

var _session: WorkoutSession = null
var _speed_model := SpeedModel.new()
var _sample := TrackSample.new()
var _ahead := TrackSample.new()
var _camera_yaw: float = 0.0
var _lean: float = 0.0
var _road: MeshInstance3D = null
var _props: MultiMeshInstance3D = null
## Прочие узлы мира, построенные по трассе (обочина, рельеф, растительность).
var _world_nodes: Array[Node] = []
var _terrain: TerrainField = null
## Вода (море, река; T-088): один меш на уровне воды трассы, null — воды нет.
var _water: MeshInstance3D = null
var _env_instance: Node = null
## Ориентиры трассы каталога (T-083): расстановка и узлы (входят в `_world_nodes`).
var _landmarks_placed: Array[LandmarkBuilder.Placed] = []
var _landmark_nodes: Array[MultiMeshInstance3D] = []
## Мосты трассы (T-090, `BridgeBuilder` по `RouteDef.bridges`): расстановка и узлы (входят в `_world_nodes`).
var _bridges_placed: Array[LandmarkBuilder.Placed] = []
var _bridge_nodes: Array[MultiMeshInstance3D] = []
## Контейнер того, что есть не на каждой трассе (ориентиры, лесополосы, изгороди): живёт всё
## время сцены, поэтому число детей корня окружения от трассы не зависит.
var _features: Node3D = null

@onready var _rider: Rider = %Rider
@onready var _camera: Camera3D = %Camera
@onready var _sun: DirectionalLight3D = %Sun
@onready var _world_env: WorldEnvironment = %WorldEnvironment
@onready var _environment_root: Node3D = %EnvironmentRoot


func _ready() -> void:
	# Велосипедиста двигает только сцена (`advance` → `Rider.advance`), иначе его анимация
	# и колёса продвигались бы дважды за кадр.
	_rider.set_process(false)
	_features = Node3D.new()
	_features.name = "RouteFeatures"
	_environment_root.add_child(_features)
	if environment_set == null:
		environment_set = RouteWorld.environment(route_id) if not route_id.is_empty() else load(DEFAULT_ENVIRONMENT)
	_apply_environment()
	# Трасса, заданная до входа в дерево (например, GPX), строится здесь же.
	if track != null:
		set_track(track)
	elif not route_id.is_empty():
		set_track(RouteWorld.track(route_id))
	else:
		set_track(LoopTrack.new(track_seed))


## Трасса каталога (`flat`, `hills`, `mountains`, `seaside`; неизвестный id — трасса по
## умолчанию): план и профиль (`ProfiledTrack`) и набор окружения из `RouteWorld`. Игровой
## цикл и движение велосипедиста не меняются (REQ-D3D-08 п.7).
func set_route(id: String) -> void:
	route_id = RouteWorld.resolve_id(id)
	environment_set = RouteWorld.environment(route_id)
	if is_node_ready():
		_apply_environment()
	set_track(RouteWorld.track(route_id))


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
	for node in _world_nodes:
		node.queue_free()
	_world_nodes.clear()
	_terrain = null
	_water = null
	_landmarks_placed.clear()
	_landmark_nodes.clear()
	_bridges_placed.clear()
	_bridge_nodes.clear()
	if not is_node_ready():
		return
	var env: EnvironmentSet = environment_set
	_road = RoadBuilder.build(track, _material_or(env.road_material, DEFAULT_ROAD_MATERIAL), env.road_width_m,
		-1, env.road_center_offset_m)
	_road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_environment_root.add_child(_road)
	_build_world()
	if _props != null:
		_environment_root.add_child(_props)
	# Окружающий свет и туман — в материалы мира и велосипедиста: по ним шейдеры выравнивают
	# освещённую сторону в Forward+/Mobile под эталон Compatibility (T-102, `RenderLook`).
	RenderLook.apply(self, environment_set)
	distance_m = 0.0
	_lean = 0.0
	_place_rider(true)


func rider() -> Rider:
	return _rider


func camera() -> Camera3D:
	return _camera


func road() -> MeshInstance3D:
	return _road


func props() -> MultiMeshInstance3D:
	return _props


## Узлы мира, построенные по трассе: обочина, полоса травы, рельеф, растительность.
func world_nodes() -> Array[Node]:
	return _world_nodes


## Поле высот рельефа (null — рельеф выключен в `EnvironmentSet`).
func terrain() -> TerrainField:
	return _terrain


## Меш воды (море и река, `TerrainField.build_water_mesh`); null — у трассы нет воды.
func water() -> MeshInstance3D:
	return _water


## Узлы ориентиров (корни; части — их дети). Пусто — у трассы нет ориентиров или они
## выключены в `EnvironmentSet`.
func landmark_nodes() -> Array[MultiMeshInstance3D]:
	return _landmark_nodes


## Расстановка ориентиров (данные для тестов: тип, s, точка привязки, экземпляры частей).
func landmarks_placed() -> Array[LandmarkBuilder.Placed]:
	return _landmarks_placed


## Узлы мостов трассы (`BridgeBuilder`; корни, фонари — их дети). Пусто — мостов нет.
func bridge_nodes() -> Array[MultiMeshInstance3D]:
	return _bridge_nodes


## Расстановка мостов (данные для тестов: части, точка привязки).
func bridges_placed() -> Array[LandmarkBuilder.Placed]:
	return _bridges_placed


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


## Отвязать от сессии: скорость обнуляется (сцена замирает), педалирование останавливается;
## последний каденс в поле сохраняется — телеметрия отвязанной сессии его больше не меняет.
func unbind() -> void:
	speed_kmh = 0.0
	if is_node_ready():
		_rider.set_cadence(0)
		_rider.set_wheel_speed(0.0)
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
	_camera_yaw = lerp_angle(_camera_yaw, _desired_yaw(), alpha)
	_camera.global_position = _rider.global_position + _camera_offset_for(_camera_yaw)
	_camera.look_at(_camera_target(_camera_yaw), Vector3.UP)
	_lean += (_lean_target() - _lean) * (1.0 - exp(-dt / LEAN_TAU_SEC))
	_rider.set_lean(_lean)
	_rider.advance(dt)


## Продольный наклон велосипедиста, рад (> 0 — нос вверх): atan(g) уклона трассы.
func rider_pitch_rad() -> float:
	return _rider.pitch_rad()


## Курс движения в горизонтальной плоскости (yaw), рад.
func _desired_yaw() -> float:
	var flat := Vector2(_sample.forward.x, _sample.forward.z)
	if flat.length_squared() < 1e-8:
		return _camera_yaw
	return atan2(flat.x, flat.y)


## Смещение камеры для курса `yaw`: ровно CAMERA_BACK_M назад (с поворотом на
## `CAMERA_SIDE_RAD`) и CAMERA_UP_M вверх.
func _camera_offset_for(yaw: float) -> Vector3:
	var a: float = yaw + CAMERA_SIDE_RAD
	return Vector3(-sin(a) * CAMERA_BACK_M, CAMERA_UP_M, -cos(a) * CAMERA_BACK_M)


## Точка взгляда камеры: на дороге впереди велосипедиста по курсу камеры. Наклон камеры от
## уклона не зависит (горизонтальная дистанция и высота постоянны, D3D-07.5): на подъёме
## дорога и склон в кадре уходят вверх, на спуске — вниз (REQ-D3D-08 п.5, 8).
func _camera_target(yaw: float) -> Vector3:
	return _rider.global_position + Vector3(sin(yaw) * CAMERA_LOOK_AHEAD_M, CAMERA_LOOK_UP_M, cos(yaw) * CAMERA_LOOK_AHEAD_M)


## Угол наклона в повороте: atan(v²·κ/g) с усилением и пределом (> 0 — влево).
func _lean_target() -> float:
	if speed_kmh <= 0.0 or track == null:
		return 0.0
	track.sample_into(distance_m + LEAN_PROBE_M, _ahead)
	var cross_y: float = _sample.forward.z * _ahead.forward.x - _sample.forward.x * _ahead.forward.z
	var kappa: float = cross_y / LEAN_PROBE_M
	var v: float = speed_kmh / 3.6
	return clampf(atan(v * v * kappa / GRAVITY) * LEAN_GAIN, -LEAN_MAX_RAD, LEAN_MAX_RAD)


## Текущий наклон велосипедиста, рад.
func lean_rad() -> float:
	return _lean


func _process(delta: float) -> void:
	advance(delta)


func _place_rider(snap_camera: bool) -> void:
	track.sample_into(distance_m, _sample)
	_rider.global_position = _sample.position
	_rider.look_at(_sample.position + _sample.forward, _sample.up)
	if snap_camera:
		_camera_yaw = _desired_yaw()
		_camera.global_position = _sample.position + _camera_offset_for(_camera_yaw)
		_camera.look_at(_camera_target(_camera_yaw), Vector3.UP)


func _on_second_elapsed(_elapsed: int, _offset: int, _remaining: int) -> void:
	if _session == null or _session.samples.size() == 0:
		return
	if _session.get_state() == WorkoutSession.State.PAUSED:
		return
	var row: Dictionary = _session.samples.last_row()
	var use_trainer: bool = _session.samples.speed_source == SampleStream.SPEED_SOURCE_TRAINER and bool(row["has_speed"])
	apply_telemetry(int(row["power_w"]), bool(row["has_power"]), int(row["cadence_rpm"]), bool(row["has_cadence"]),
		float(row["speed_kmh"]), use_trainer)


## Пауза: велосипедист останавливается (скорость и каденс — 0, дистанция не растёт);
## после возобновления движение продолжается по следующему сэмплу телеметрии.
func _on_session_state(state: int) -> void:
	if state == WorkoutSession.State.PAUSED:
		speed_kmh = 0.0
		cadence_rpm = 0
		_speed_model.reset(0.0)
		if is_node_ready():
			_rider.set_cadence(0)
			_rider.set_wheel_speed(0.0)
	elif state == WorkoutSession.State.FINISHED:
		if is_node_ready():
			_rider.set_cadence(0)


# ---------------------------------------------------------------------------
# Построение окружения (не в кадре)
# ---------------------------------------------------------------------------

func _apply_environment() -> void:
	var e: EnvironmentSet = environment_set
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.background_color = e.sky_color
	var sky_mat: Material = e.sky_material
	if sky_mat == null:
		var sm := (load(DEFAULT_SKY_MATERIAL) as ShaderMaterial).duplicate() as ShaderMaterial
		sm.set_shader_parameter("top_color", e.sky_color)
		sm.set_shader_parameter("horizon_color", e.horizon_color)
		sm.set_shader_parameter("ground_color", e.sky_ground_color)
		sm.set_shader_parameter("cloud_cover", e.cloud_cover)
		sky_mat = sm
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = e.ambient_color
	env.ambient_light_energy = e.ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = e.fog_color
	env.fog_density = e.fog_density
	env.fog_sky_affect = 0.0
	_world_env.environment = env
	_sun.light_color = e.sun_color
	_sun.light_energy = e.sun_energy
	_sun.rotation_degrees = e.sun_rotation_deg
	_camera.far = maxf(e.view_distance_m, TerrainField.RANGE_M)
	if _env_instance != null:
		_env_instance.queue_free()
		_env_instance = null
	if e.environment_scene != null:
		_env_instance = e.environment_scene.instantiate()
		_environment_root.add_child(_env_instance)


func _material_or(material: Material, fallback_path: String) -> Material:
	return material if material != null else load(fallback_path) as Material


## Обочина, полоса травы, рельеф, столбики и растительность — по трассе, один раз.
## Столбики строятся первыми: растительности остаётся бюджет видимых экземпляров
## MultiMesh за вычетом видимых столбиков (REQ-D3D-08 п.6, `PerfBudget`).
func _build_world() -> void:
	var e: EnvironmentSet = environment_set
	var world_mat: Material = _material_or(e.world_material, DEFAULT_WORLD_MATERIAL)
	var grass_mat: Material = _material_or(e.terrain_material, DEFAULT_TERRAIN_MATERIAL)
	# Поле высот — до обочины: отбойник со стороны долины смотрит на рельеф (горы).
	if e.terrain_enabled:
		_terrain = TerrainField.build_for(track, e)
	if e.roadside_enabled:
		var side: Dictionary = RoadsideBuilder.build(track, e.road_width_m, e.road_center_offset_m, world_mat, grass_mat,
			e.guardrail_enabled, e.scenery_seed, _terrain if e.guardrail_valley_side else null)
		_add_world_node(side["roadside"])
		_add_world_node(_no_shadow(side["verge"]))
	# Ориентиры расставляются по рельефу до его меша: озёра опускают землю под водой.
	_place_landmarks(world_mat)
	if _terrain != null:
		LandmarkBuilder.carve(_landmarks_placed, _terrain)
		_add_world_node(_no_shadow(_terrain.build_mesh(grass_mat)))
	# Мосты — по данным трассы, после правок рельефа (опоры стоят на дне долины).
	_bridges_placed = BridgeBuilder.place(track, e, _terrain, world_mat)
	_bridge_nodes = BridgeBuilder.nodes(_bridges_placed)
	for node in _bridge_nodes:
		_add_world_node(node, true)
	if _terrain != null:
		# Вода — после всех правок рельефа (котловины, русло, мыс): глубина под водой — по ним.
		if e.water_enabled:
			_water = _terrain.build_water_mesh(_material_or(e.water_material, DEFAULT_WATER_MATERIAL))
			if _water != null:
				_add_world_node(_water, true)
	_props = _build_props()
	_landmark_nodes = LandmarkBuilder.nodes(_landmarks_placed)
	for node in _landmark_nodes:
		_add_world_node(node, true)
	var fixed: Array = []
	fixed.append(_props)
	fixed.append_array(_landmark_nodes)
	fixed.append_array(_bridge_nodes)
	var fixed_visible: int = PerfBudget.max_visible_along(fixed, track)
	var fixed_total: int = 0
	for node in fixed:
		if node != null:
			fixed_total += int(PerfBudget.count(node)["multimesh_instances"])
	var spots: Array[LandmarkBuilder.Placed] = []
	spots.append_array(_landmarks_placed)
	spots.append_array(_bridges_placed)
	var keep: LandmarkBuilder.KeepOut = LandmarkBuilder.keep_out(spots)
	# Длинная трасса: видимое считается по точкам через 50 м — между ними (и на сложенной
	# змейке) может быть чуть больше; запас — `EnvironmentSet.visible_reserve`. Компактный мир
	# виден целиком — без запаса.
	var reserve: int = 0 if PerfBudget.is_compact(track) else maxi(e.visible_reserve, 0)
	for node in SceneryBuilder.build(track, e, _terrain, world_mat, PerfBudget.MAX_VISIBLE_MULTIMESH_INSTANCES - fixed_visible - reserve,
			PerfBudget.MAX_MULTIMESH_INSTANCES - fixed_total, keep):
		_add_world_node(node, SceneryBuilder.EXTRA_LAYERS.has(String(node.name)))


## Ориентиры трассы каталога (`ProfiledTrack.route.landmarks`, `LandmarkBuilder`); у прочих
## трасс (петля, GPX) их нет. Строятся до растительности: она обходит их пятна и получает
## остаток бюджета видимых экземпляров.
func _place_landmarks(world_mat: Material) -> void:
	var e: EnvironmentSet = environment_set
	if not e.landmarks_enabled or not (track is ProfiledTrack):
		return
	var def: RouteCatalog.RouteDef = (track as ProfiledTrack).route
	if def == null or def.landmarks.is_empty():
		return
	_landmarks_placed = LandmarkBuilder.place(track, def.landmarks, e, _terrain, world_mat)


## Земля тени не отбрасывает: её габарит — весь мир, он растянул бы глубину карты теней
## и съел точность (дыры и «грязь» в тени велосипедиста).
func _no_shadow(node: GeometryInstance3D) -> GeometryInstance3D:
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _add_world_node(node: Node, feature: bool = false) -> void:
	_world_nodes.append(node)
	if feature:
		if _features == null:
			_features = Node3D.new()
			_features.name = "RouteFeatures"
			_environment_root.add_child(_features)
		_features.add_child(node)
	else:
		_environment_root.add_child(node)


## Сигнальные столбики (`RoadsideBuilder.build_posts`): шаг `prop_spacing_m` по всей
## трассе, на длинной — куски с дальностью видимости.
func _build_props() -> MultiMeshInstance3D:
	if environment_set == null or environment_set.prop_spacing_m <= 0.0:
		return null
	var e: EnvironmentSet = environment_set
	var mesh := SceneryBuilder.delineator_mesh(e.prop_size, _material_or(e.prop_material, DEFAULT_WORLD_MATERIAL))
	return RoadsideBuilder.build_posts(track, e, mesh)
