extends SceneTree
## Снимки 3D-сцены заезда в PNG — «глаза» для агентов и ревью визуала (без станка и сессии).
## Запуск: ./scripts/screenshot.sh [каталог] [скорость_кмч] [каденс] [дистанции_м через запятую] [трасса] [вторая_трасса]
## Трасса — id каталога (`flat`, `hills`, `mountains`, `seaside`; по умолчанию — трасса сцены
## по умолчанию, `flat`) или `loop` — процедурная петля `LoopTrack` (мир до T-070).
## Вторая трасса (T-112) — после снимаемой сцены строится ещё одна `RideScene` этой трассы в
## своём `SubViewport` и живёт до конца (как свободная езда после экрана тренировки в
## `main.tscn`): кадр снимаемой сцены не должен от неё зависеть.
## Сцена ставится на каждую дистанцию, «доезжает» 2 с с заданной скоростью (камера успевает
## догнать поворот), затем кадр сохраняется как `ride_<дистанция>m.png`.
##
## Эталонные ракурсы гонщика (T-106a1, бриф художнику раздел 14, `RiderRig.VIEWS`): ключи
## `--views=all` или `--views=work,side_r,…` и `--crank=0,90,…` (по умолчанию — углы ракурса
## из таблицы). Гонщик стоит на дистанции (по умолчанию 0 м) со скоростью и каденсом 0, шатун —
## на угле φ; файлы `rider_<view>_<φ>.png`. `--bike-only` — без гонщика (подгонка велосипеда),
## файлы `bike_<view>_<φ>.png`. `--figure=m|f` и `--hair=short|tail` (T-106a2) — фигура и
## причёска манекена (по умолчанию `m`, `short`). Пример:
##   ./scripts/screenshot.sh shots 0 0 0 flat --views=all
##
## Серия кадров движения (T-106a2): `--series=<с>` вместе с `--views=…` — гонщик едет со
## скоростью и каденсом из аргументов (k — по каденсу, без мощности), после разгона
## `SERIES_WARMUP_SEC` (педали и пружина хвоста выходят на установившийся режим) каждый ракурс
## снимается `--fps=<кадров/с>` (по умолчанию 30) в течение заданных секунд; сцена шагает по
## 1/60 с, как в игре. Файлы `series_<view>/<view>_<NNN>.png` и `series_<view>/series.csv`
## (время, φ, углы хвоста). Пример — rear_low 2 с при 100 об/мин, 30 кадров/с:
##   ./scripts/screenshot.sh shots 32 100 0 flat --views=rear_low --series=2.0 --fps=30 --figure=f --hair=tail

const RIDE_SCENE: String = "res://src/scene3d/ride_scene.tscn"
const SETTLE_FRAMES: int = 120
const FRAME_DT: float = 1.0 / 60.0
const SERIES_WARMUP_SEC: float = 6.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := PackedStringArray()
	var views_arg: String = ""
	var crank_arg: String = ""
	var bike_only: bool = false
	var figure: String = ""
	var hair: String = ""
	var series_sec: float = 0.0
	var series_fps: float = 30.0
	for a in OS.get_cmdline_user_args():
		if a == "--bike-only":
			bike_only = true
		elif a.begins_with("--figure="):
			figure = a.trim_prefix("--figure=")
		elif a.begins_with("--hair="):
			hair = a.trim_prefix("--hair=")
		elif a.begins_with("--views="):
			views_arg = a.trim_prefix("--views=")
		elif a.begins_with("--crank="):
			crank_arg = a.trim_prefix("--crank=")
		elif a.begins_with("--series="):
			series_sec = float(a.trim_prefix("--series="))
		elif a.begins_with("--fps="):
			series_fps = float(a.trim_prefix("--fps="))
		else:
			args.append(a)
	var out_dir: String = args[0] if args.size() > 0 else "screenshots"
	var speed: float = float(args[1]) if args.size() > 1 else 32.0
	var cadence: int = int(args[2]) if args.size() > 2 else 90
	var stops: PackedStringArray = (args[3] if args.size() > 3 else "0,400,900,1500").split(",")
	var route: String = args[4] if args.size() > 4 else ""
	var other: String = args[5] if args.size() > 5 else ""
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene: RideScene = (load(RIDE_SCENE) as PackedScene).instantiate()
	if route == "loop":
		scene.route_id = ""
	elif not route.is_empty():
		scene.route_id = RouteWorld.resolve_id(route)
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	if not figure.is_empty():
		scene.rider().set_figure(figure)
	if not hair.is_empty():
		scene.rider().set_hair_style(hair)
	if not other.is_empty():
		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.size = Vector2i(320, 180)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var second: RideScene = (load(RIDE_SCENE) as PackedScene).instantiate()
		second.route_id = RouteWorld.resolve_id(other)
		vp.add_child(second)
		second.set_process(false)
		await process_frame
	if not views_arg.is_empty() and series_sec > 0.0:
		await _shoot_series(scene, out_dir, float(stops[0]), views_arg, speed, cadence, series_sec, series_fps)
		quit(0)
		return
	if not views_arg.is_empty():
		await _shoot_views(scene, out_dir, float(stops[0]), views_arg, crank_arg, bike_only)
		quit(0)
		return
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


## Ракурсы `RiderRig.VIEWS`: гонщик стоит (скорость и каденс 0, наклона нет), камера — в
## системе гонщика; `work` — камера сцены.
func _shoot_views(scene: RideScene, out_dir: String, distance: float, views_arg: String, crank_arg: String,
		bike_only: bool) -> void:
	scene.distance_m = distance
	scene.apply_telemetry(0, false, 0, true, 0.0, true)
	for i in SETTLE_FRAMES:
		scene.advance(FRAME_DT)
	var cam: Camera3D = scene.camera()
	var work_xf: Transform3D = cam.global_transform
	var work_fov: float = cam.fov
	var rider: Rider = scene.rider()
	var frame: Transform3D = rider.global_transform
	var prefix: String = "rider"
	if bike_only:
		prefix = "bike"
		rider.skeleton().visible = false
	var wanted: PackedStringArray = views_arg.split(",")
	for v in RiderRig.VIEWS:
		var view: String = v[0]
		if views_arg != "all" and not wanted.has(view):
			continue
		if view == "work":
			cam.global_transform = work_xf
			cam.fov = work_fov
		else:
			cam.global_position = frame * (v[1] as Vector3)
			cam.look_at(frame * (v[2] as Vector3), frame.basis.y)
			cam.fov = v[3]
		var angles: Array = v[4]
		if not crank_arg.is_empty():
			angles = Array(crank_arg.split(",")).map(func(x: String) -> int: return int(x))
		for deg in angles:
			rider.set_crank_angle(deg_to_rad(float(deg)))
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var path: String = out_dir.path_join("%s_%s_%d.png" % [prefix, view, int(deg)])
			var err: Error = root.get_texture().get_image().save_png(path)
			print("ride_screenshot: %s (%s)" % [path, error_string(err)])


## Серия кадров ракурсов `views_arg` в движении: скорость `speed` км/ч, каденс `cadence`, без
## мощности (k по каденсу); разгон `SERIES_WARMUP_SEC`, затем `seconds` с по `fps` кадров/с.
func _shoot_series(scene: RideScene, out_dir: String, distance: float, views_arg: String, speed: float,
		cadence: int, seconds: float, fps: float) -> void:
	var cam: Camera3D = scene.camera()
	var work_fov: float = cam.fov
	var rider: Rider = scene.rider()
	var wanted: PackedStringArray = views_arg.split(",")
	var substeps: int = maxi(int(round(1.0 / fps / FRAME_DT)), 1)
	var frames: int = int(round(seconds * fps))
	for v in RiderRig.VIEWS:
		var view: String = v[0]
		if views_arg != "all" and not wanted.has(view):
			continue
		scene.distance_m = distance
		scene.apply_telemetry(0, false, cadence, true, speed, true)
		for i in int(SERIES_WARMUP_SEC / FRAME_DT):
			scene.advance(FRAME_DT)
		var dir: String = out_dir.path_join("series_" + view)
		DirAccess.make_dir_recursive_absolute(dir)
		var csv := FileAccess.open(dir.path_join("series.csv"), FileAccess.WRITE)
		csv.store_line("frame,t_sec,crank_deg,tail_side_deg,tail_vert_deg,effort_k")
		for f in frames + 1:
			if f > 0:
				for i in substeps:
					scene.advance(FRAME_DT)
			if view == "work":
				cam.fov = work_fov
			else:
				var frame: Transform3D = rider.global_transform
				cam.global_position = frame * (v[1] as Vector3)
				cam.look_at(frame * (v[2] as Vector3), frame.basis.y)
				cam.fov = v[3]
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var path: String = dir.path_join("%s_%03d.png" % [view, f])
			var err: Error = root.get_texture().get_image().save_png(path)
			var tail: Vector2 = rider.tail_angles()
			csv.store_line("%d,%.4f,%.1f,%.2f,%.2f,%.3f" % [f, float(f) / fps,
				rad_to_deg(fposmod(rider.crank_rotation_rad(), TAU)), rad_to_deg(tail.x), rad_to_deg(tail.y), rider.effort_k])
			print("ride_screenshot: %s (%s)" % [path, error_string(err)])
		csv.close()
