class_name RouteWorld
extends RefCounted
## Трасса каталога → мир сцены (REQ-D3D-08 п.7, REQ-D3D-06): id трассы (`RouteCatalog`) →
## `ProfiledTrack` (план-схема + профиль) и `EnvironmentSet` (`.tres`). Игровой цикл
## (`RideScene`) знает только интерфейсы `Track`/`EnvironmentSet`; смена трассы — смена
## данных, а не ветвление кода (`RideScene.set_route(id)`).
##
## Окружения по трассам — `src/scene3d/tracks/env_<id>.tres`: равнина и холмы — T-083,
## горы — T-087, приморье — T-088 (море, река, пляж, маяк) и T-090 (мост, `BridgeBuilder`). Ориентиры —
## из `RouteDef.landmarks` (`ProfiledTrack.route`, расстановка — `LandmarkBuilder`). Планы
## трасс неизменяемы и строятся один раз на процесс (кэш по id). Кэш статический — его
## очищает `clear_cache()`; при первом заполнении он подписывается на выход корня дерева
## сцен (выход из приложения, конец прогона тестов) и очищается сам — к проверке ресурсов
## при выходе планы уже освобождены (T-100).

const DEFAULT_ENVIRONMENT: String = "res://src/scene3d/default_environment.tres"
## Набор окружения по `RouteDef.environment_set_id`; нет записи — `DEFAULT_ENVIRONMENT`.
const ENVIRONMENTS: Dictionary = {
	RouteCatalog.FLAT: "res://src/scene3d/tracks/env_flat.tres",
	RouteCatalog.HILLS: "res://src/scene3d/tracks/env_hills.tres",
	RouteCatalog.MOUNTAINS: "res://src/scene3d/tracks/env_mountains.tres",
	RouteCatalog.SEASIDE: "res://src/scene3d/tracks/env_seaside.tres",
}

static var _tracks: Dictionary = {}
static var _exit_hooked: bool = false


## Id, который реально будет построен (неизвестный → трасса по умолчанию каталога).
static func resolve_id(route_id: String) -> String:
	return RouteCatalog.resolve_id(route_id)


## Трасса по id (кэш; неизвестный id → трасса по умолчанию).
static func track(route_id: String) -> ProfiledTrack:
	var id: String = resolve_id(route_id)
	if not _tracks.has(id):
		_hook_exit()
		_tracks[id] = ProfiledTrack.from_id(id)
	return _tracks[id]


## Сбросить кэш планов трасс: следующий `track()` построит план заново. Сцены, которые уже
## держат трассу, её не теряют (ссылка — у них).
static func clear_cache() -> void:
	_tracks.clear()


## Сколько планов трасс в кэше.
static func cached_count() -> int:
	return _tracks.size()


## Очистка кэша при выходе корня дерева сцен (одна подписка на процесс).
static func _hook_exit() -> void:
	if _exit_hooked:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	_exit_hooked = true
	tree.root.tree_exiting.connect(_on_root_exiting, CONNECT_ONE_SHOT)


## Подписан ли кэш на выход корня дерева сцен (для тестов).
static func is_exit_hooked() -> bool:
	return _exit_hooked


static func _on_root_exiting() -> void:
	_exit_hooked = false
	clear_cache()


## Путь к набору окружения трассы.
static func environment_path(route_id: String) -> String:
	var def: RouteCatalog.RouteDef = RouteCatalog.get_route(resolve_id(route_id))
	var key: String = def.environment_set_id if def != null else ""
	return String(ENVIRONMENTS.get(key, DEFAULT_ENVIRONMENT))


## Набор окружения трассы (общий ресурс; правка — через `duplicate()`).
static func environment(route_id: String) -> EnvironmentSet:
	return load(environment_path(route_id)) as EnvironmentSet
