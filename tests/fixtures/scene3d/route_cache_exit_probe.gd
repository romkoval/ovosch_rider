extends SceneTree
## Проба REQ-INF-01 крит. 2, 5 для T-100 (запускается отдельным процессом из
## `test_route_world_cache_reaccept.gd`): строит планы трасс через статический кэш
## `RouteWorld` и выходит, не очищая кэш явно. Аргумент `--keep` — держать ссылку на план в
## статическом поле пробы (контроль: проверка ресурсов при выходе должна это увидеть).

static var _held: ProfiledTrack = null


func _initialize() -> void:
	var ids: Array[String] = ["flat", "seaside"]
	for id in ids:
		var t := RouteWorld.track(id)
		if "--keep" in OS.get_cmdline_user_args():
			_held = t
	print("PROBE cached=%d hooked=%s" % [RouteWorld.cached_count(), RouteWorld.is_exit_hooked()])
	quit(0)
