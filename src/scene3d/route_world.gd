class_name RouteWorld
extends RefCounted
## Трасса каталога → мир сцены (REQ-D3D-08 п.7, REQ-D3D-06): id трассы (`RouteCatalog`) →
## `ProfiledTrack` (план-схема + профиль) и `EnvironmentSet` (`.tres`). Игровой цикл
## (`RideScene`) знает только интерфейсы `Track`/`EnvironmentSet`; смена трассы — смена
## данных, а не ветвление кода (`RideScene.set_route(id)`).
##
## Окружения по трассам появятся в T-083/T-087/T-088 (`src/scene3d/tracks/env_<id>.tres`);
## пока у всех четырёх — общее `default_environment.tres`. Планы трасс неизменяемы и
## строятся один раз на процесс (кэш по id).

const DEFAULT_ENVIRONMENT: String = "res://src/scene3d/default_environment.tres"
## Набор окружения по `RouteDef.environment_set_id`; нет записи — `DEFAULT_ENVIRONMENT`.
const ENVIRONMENTS: Dictionary = {}

static var _tracks: Dictionary = {}


## Id, который реально будет построен (неизвестный → трасса по умолчанию каталога).
static func resolve_id(route_id: String) -> String:
	return RouteCatalog.resolve_id(route_id)


## Трасса по id (кэш; неизвестный id → трасса по умолчанию).
static func track(route_id: String) -> ProfiledTrack:
	var id: String = resolve_id(route_id)
	if not _tracks.has(id):
		_tracks[id] = ProfiledTrack.from_id(id)
	return _tracks[id]


## Путь к набору окружения трассы.
static func environment_path(route_id: String) -> String:
	var def: RouteCatalog.RouteDef = RouteCatalog.get_route(resolve_id(route_id))
	var key: String = def.environment_set_id if def != null else ""
	return String(ENVIRONMENTS.get(key, DEFAULT_ENVIRONMENT))


## Набор окружения трассы (общий ресурс; правка — через `duplicate()`).
static func environment(route_id: String) -> EnvironmentSet:
	return load(environment_path(route_id)) as EnvironmentSet
