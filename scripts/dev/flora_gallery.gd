extends SceneTree
## Хвойные (T-107): галерея форм и замер кадра. Запуск — `./scripts/flora_gallery.sh` (там же
## аргументы). Отладочный инструмент, в сборку не входит.

const RIDE_SCENE: String = "res://src/scene3d/ride_scene.tscn"
const SETTLE_FRAMES: int = 90
const FRAME_DT: float = 1.0 / 60.0
## Галерея (арт-библия «Эталонные снимки для приёмки», п.2): камера на высоте 1.7 м, ряд — по
## дуге в 25 м, FOV 55°.
const EYE_M: float = 1.7
const ROW_M: float = 25.0
const FOV_DEG: float = 55.0
const GRASS: Color = Color(0.33, 0.52, 0.22, 0.0)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "gallery"
	if mode == "stats":
		await _stats(args[1] if args.size() > 1 else "mountains", float(args[2]) if args.size() > 2 else 100.0)
	elif mode == "gallery":
		var out_dir: String = args[1] if args.size() > 1 else "screenshots/flora"
		DirAccess.make_dir_recursive_absolute(out_dir)
		for route in (args[2] if args.size() > 2 else "mountains,seaside").split(","):
			await _gallery(out_dir, route.strip_edges())
	else:
		push_error("flora_gallery: неизвестный режим %s" % mode)
	quit(0)


## Узлы хвойных мира (слои `Conifers*` и их куски).
func _conifer_nodes(scene: RideScene) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in scene.world_nodes():
		if String(n.name).begins_with("Conifers"):
			out.append(n as Node3D)
	return out


func _frame_info() -> Vector3i:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var vp: RID = root.get_viewport_rid()
	var draws: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims_visible: int = RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
		RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	var draws_shadow: int = RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,
		RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	return Vector3i(draws, prims_visible, draws_shadow)


## Проезд трассы с шагом `step_m`: draw calls кадра (всего и в проходе теней), треугольники
## видимого прохода (цвет + контур), то же без хвойных; максимум по трассе.
func _stats(route: String, step_m: float) -> void:
	var scene: RideScene = (load(RIDE_SCENE) as PackedScene).instantiate()
	scene.route_id = RouteWorld.resolve_id(route)
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	var conifers: Array[Node3D] = _conifer_nodes(scene)
	var length: float = scene.track.length_m()
	var best := {"draws": Vector2(0, 0), "prims": Vector2(0, 0), "flora_prims": Vector2(0, 0), "flora_draws": Vector2(0, 0)}
	var at: float = 0.0
	while at < length:
		scene.distance_m = maxf(at - 32.0 / 3.6 * SETTLE_FRAMES * FRAME_DT, 0.0)
		scene.apply_telemetry(0, false, 90, true, 32.0, true)
		for i in SETTLE_FRAMES:
			scene.advance(FRAME_DT)
		var with: Vector3i = await _frame_info()
		for n in conifers:
			n.visible = false
		var without: Vector3i = await _frame_info()
		for n in conifers:
			n.visible = true
		var flora_prims: int = with.y - without.y
		var flora_draws: int = with.x - without.x
		print("flora_stats: %s s=%d draws=%d shadow_draws=%d prims=%d conifer_prims=%d conifer_draws=%d" %
			[route, int(at), with.x, with.z, with.y, flora_prims, flora_draws])
		for pair in [["draws", with.x], ["prims", with.y], ["flora_prims", flora_prims], ["flora_draws", flora_draws]]:
			if float(pair[1]) > (best[pair[0]] as Vector2).x:
				best[pair[0]] = Vector2(float(pair[1]), at)
		at += step_m
	for key in best:
		var v: Vector2 = best[key]
		print("flora_stats: %s max %s=%d at s=%d" % [route, key, int(v.x), int(v.y)])


## Галерея форм трассы `route`: свет, небо и туман окружения трассы, мир скрыт; на траве по дуге
## стоят все формы трассы (молодые — с именованной вариацией, середина диапазона масштаба) на
## одном уровне детализации; три кадра (LOD0, LOD1, LOD2) и они же друг под другом.
func _gallery(out_dir: String, route: String) -> void:
	var scene: RideScene = (load(RIDE_SCENE) as PackedScene).instantiate()
	scene.route_id = RouteWorld.resolve_id(route)
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	var env: EnvironmentSet = scene.environment_set
	for child in (scene.get_node("%EnvironmentRoot") as Node3D).get_children():
		if child is Node3D:
			(child as Node3D).visible = false
	scene.rider().visible = false
	var mat: Material = env.world_material if env.world_material != null else load(RideScene.DEFAULT_WORLD_MATERIAL)
	var stage := Node3D.new()
	stage.name = "FloraGallery"
	scene.add_child(stage)
	var kit := MeshKit.new()
	kit.add_quad(Vector3(-400, 0, -400), Vector3(400, 0, -400), Vector3(400, 0, 400), Vector3(-400, 0, 400), Vector3.UP, GRASS)
	var ground := MeshInstance3D.new()
	ground.mesh = kit.to_mesh(mat)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(ground)
	var forms: PackedInt32Array = ConiferKit.mix_forms(ConiferKit.form_mix(env))
	# Ряд — вдоль направления солнца, повёрнутого на 50°: свет сбоку-спереди, видны и свет, и тень.
	var sun: DirectionalLight3D = scene.get_node("%Sun")
	var light_dir: Vector3 = -sun.global_transform.basis.z
	var flat := Vector3(light_dir.x, 0.0, light_dir.z).normalized().rotated(Vector3.UP, deg_to_rad(50.0))
	stage.transform = Transform3D(Basis(Vector3.UP, atan2(-flat.x, -flat.z)), Vector3.ZERO)
	var cam := scene.camera()
	cam.fov = FOV_DEG
	cam.global_transform = stage.transform * Transform3D(Basis.IDENTITY, Vector3(0.0, EYE_M, 0.0))
	cam.look_at(stage.transform * Vector3(0.0, EYE_M + 3.2, -ROW_M), Vector3.UP)
	var canvas := CanvasLayer.new()
	stage.add_child(canvas)
	var label := Label.new()
	label.position = Vector2(16, 12)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08))
	canvas.add_child(label)
	var frames: Array[Image] = []
	for lod in ConiferKit.LOD_COUNT:
		var row := Node3D.new()
		stage.add_child(row)
		var names: PackedStringArray = []
		for i in forms.size():
			var form: int = forms[i]
			var p := ConiferKit.Plant.new()
			p.form = form
			p.lod = lod
			p.scale = (ConiferKit.SCALE_RANGE[form].x + ConiferKit.SCALE_RANGE[form].y) * 0.5
			if form == ConiferKit.SPRUCE_YOUNG:
				p.width_mul = ConiferKit.YOUNG_SPRUCE_WIDTH
				p.tone = ConiferKit.YOUNG_SPRUCE_TONE
			elif form == ConiferKit.STONE_PINE_YOUNG:
				p.height_mul = ConiferKit.YOUNG_PINE_HEIGHT
				p.tone = ConiferKit.YOUNG_PINE_TONE
			var ang: float = deg_to_rad(lerpf(-32.0, 32.0, (float(i) + 0.5) / float(forms.size())))
			p.origin = Vector3(sin(ang) * ROW_M, 0.0, -cos(ang) * ROW_M)
			p.yaw = 0.7 + float(i) * 1.3
			if form == ConiferKit.STONE_PINE_LEAN:
				p.lean_dir = Vector3.RIGHT
				if lod == 0:
					p.yaw = 0.0
				else:
					p.tilt_dir = Vector3.RIGHT
					p.tilt = deg_to_rad(ConiferKit.LEAN_TILT_DEG)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = ConiferKit.single_mesh(ConiferKit.model_of(form, lod), lod, mat)
			mm.instance_count = 1
			mm.set_instance_transform(0, p.transform(1.0))
			mm.set_instance_color(0, MeshKit.lin(p.color(env.conifer_shade)))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			if lod >= SceneryBuilder.CONIFER_SHADOW_LODS:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			row.add_child(mmi)
			names.append("%s %d△" % [ConiferKit.FORM_KEYS[form], ConiferKit.triangles(ConiferKit.model_of(form, lod), lod)])
		label.text = "%s · LOD%d · %s" % [route, lod, " · ".join(names)]
		RenderLook.apply(stage, env)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		var path: String = out_dir.path_join("vegetation_%s_lod%d.png" % [route, lod])
		print("flora_gallery: %s (%s)" % [path, error_string(img.save_png(path))])
		frames.append(img)
		row.queue_free()
		await process_frame
	var w: int = frames[0].get_width()
	var h: int = frames[0].get_height()
	var sheet := Image.create(w, h * frames.size(), false, frames[0].get_format())
	for k in frames.size():
		sheet.blit_rect(frames[k], Rect2i(0, 0, w, h), Vector2i(0, h * k))
	var sheet_path: String = out_dir.path_join("vegetation_%s.png" % route)
	print("flora_gallery: %s (%s)" % [sheet_path, error_string(sheet.save_png(sheet_path))])
	scene.queue_free()
	await process_frame
