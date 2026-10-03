extends SceneTree
## Снимки 3D-сцены заезда в PNG — «глаза» для агентов и ревью визуала (без станка и сессии).
## Запуск: ./scripts/screenshot.sh [каталог] [скорость_кмч] [каденс] [дистанции_м через запятую] [трасса]
## Трасса — id каталога (`flat`, `hills`, `mountains`, `seaside`; по умолчанию — трасса сцены
## по умолчанию, `flat`) или `loop` — процедурная петля `LoopTrack` (мир до T-070).
## Сцена ставится на каждую дистанцию, «доезжает» 2 с с заданной скоростью (камера успевает
## догнать поворот), затем кадр сохраняется как `ride_<дистанция>m.png`.

const RIDE_SCENE: String = "res://src/scene3d/ride_scene.tscn"
const SETTLE_FRAMES: int = 120
const FRAME_DT: float = 1.0 / 60.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "screenshots"
	var speed: float = float(args[1]) if args.size() > 1 else 32.0
	var cadence: int = int(args[2]) if args.size() > 2 else 90
	var stops: PackedStringArray = (args[3] if args.size() > 3 else "0,400,900,1500").split(",")
	var route: String = args[4] if args.size() > 4 else ""
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene: RideScene = (load(RIDE_SCENE) as PackedScene).instantiate()
	if route == "loop":
		scene.route_id = ""
	elif not route.is_empty():
		scene.route_id = RouteWorld.resolve_id(route)
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	for stop in stops:
		scene.distance_m = maxf(float(stop) - speed / 3.6 * SETTLE_FRAMES * FRAME_DT, 0.0)
		scene.apply_telemetry(0, false, cadence, true, speed, true)
		for i in SETTLE_FRAMES:
			scene.advance(FRAME_DT)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path: String = out_dir.path_join("ride_%sm.png" % stop.strip_edges())
		var err: Error = root.get_texture().get_image().save_png(path)
		print("ride_screenshot: %s (%s)" % [path, error_string(err)])
	quit(0)
