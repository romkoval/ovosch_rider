extends GutTest
## Приёмка T-112 (tester; REQ-D3D-07 п.1, 4, 6, REQ-HUD-13 п.10, REQ-D3D-05 п.4): туман и окружающий свет — у узлов своей сцены (параметры экземпляра
## `look_ambient`/`look_fog`), независимые проверки сверх тестов исполнителя:
## - после езды по трассе (кадры, смена кусков, ориентиры, гонщик) у каждого узла с тун-светом
##   параметры заданы и равны окружению своей трассы — узлы, появившиеся после построения, не
##   остаются со значением по умолчанию; на всех четырёх трассах;
## - в оболочке одновременно живут три сцены заезда — тренировка (flat), свободная езда
##   (mountains) и «Замер FPS» (T-116a, seaside) — у каждой свои значения; узлов с параметрами
##   экземпляра на процесс не больше ёмкости буфера Forward+/Mobile (4096), на сцену — бюджета.
## Пиксели Forward+ в облаке не снять (Vulkan недоступен, откат на OpenGL) — кадры
## «flat после mountains» в Forward+ — ручная проверка владельца.

const MAIN_SCENE: String = "res://src/app/main.tscn"
const RIDE_SCENE: String = "res://src/scene3d/ride_scene.tscn"
const PROCESS_LOOK_CAPACITY: int = 4096

var _dir: String


func before_each() -> void:
	_dir = "user://test_t112_accept_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]


func after_each() -> void:
	DiagLog.uninstall()
	RouteWorld.clear_cache()
	_remove_tree(ProjectSettings.globalize_path(_dir))


static func _remove_tree(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var d := DirAccess.open(abs_path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)


## Нарушения: узлы сцены с тун-светом, у которых параметры не заданы или чужие.
static func _look_issues(scene: RideScene, where: String) -> Array[String]:
	var issues: Array[String] = []
	var amb: Vector3 = RenderLook.ambient_of(scene.environment_set)
	var fog: Vector4 = RenderLook.fog_of(scene.environment_set)
	var nodes := RenderLook.instances_under(scene)
	if nodes.is_empty():
		issues.append("%s: нет узлов с тун-светом" % where)
	for gi in nodes:
		if gi.is_queued_for_deletion():
			continue
		var a: Variant = gi.get_instance_shader_parameter(RenderLook.AMBIENT_PARAM)
		var f: Variant = gi.get_instance_shader_parameter(RenderLook.FOG_PARAM)
		if a == null or f == null:
			issues.append("%s: %s без параметров вида" % [where, scene.get_path_to(gi)])
		elif not (a as Vector3).is_equal_approx(amb) or not (f as Vector4).is_equal_approx(fog):
			issues.append("%s: %s — чужие свет/туман %s/%s" % [where, scene.get_path_to(gi), a, f])
	return issues


func test_late_nodes_keep_own_look_while_riding_every_route() -> void:
	assert_true(RenderLook.uses_instance_look(), "предусловие: рендерер проекта читает параметры экземпляра")
	var all: Array[String] = []
	for id in RouteCatalog.ids():
		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.size = Vector2i(320, 180)
		add_child_autofree(vp)
		var s: RideScene = load(RIDE_SCENE).instantiate()
		s.route_id = id
		vp.add_child(s)
		s.speed_kmh = 40.0
		s.cadence_rpm = 90
		# Проехать по трассе крупными шагами: смена кусков, ориентиры, гонщик в движении.
		var length: float = s.track.length_m()
		for k in 12:
			s.advance(length / 12.0 / (40.0 / 3.6))
			await wait_process_frames(1)
		var count := RenderLook.instances_under(s).size()
		if count > PerfBudget.MAX_LOOK_INSTANCES:
			all.append("%s: узлов с параметрами %d > %d" % [id, count, PerfBudget.MAX_LOOK_INSTANCES])
		all.append_array(_look_issues(s, id))
		vp.queue_free()
		await wait_process_frames(1)
	for i in all.slice(0, 20):
		gut.p(i)
	assert_eq(all.size(), 0, "нарушений %d" % all.size())


func test_three_ride_scenes_in_shell_keep_own_look_and_fit_process_buffer() -> void:
	ProfileRepository.new(_dir + "profiles/").create("Solo")
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	add_child_autofree(main)
	assert_true(main.start_free_ride_on_emulator(RouteCatalog.MOUNTAINS, 50), "свободная езда в горах")
	await wait_process_frames(3)
	main.free_ride_screen().request_finish()
	main.free_ride_screen().confirm_finish()
	main.app_state.navigate(AppState.Screen.SETTINGS)
	var bench := main.settings_screen().start_fps_benchmark(RouteCatalog.SEASIDE, 600.0)
	await wait_process_frames(4)
	var scenes := {
		"тренировка": main.workout_screen().ride_scene(),
		"свободная езда": main.free_ride_screen().ride_scene(),
		"замер FPS": bench.ride_scene(),
	}
	var all: Array[String] = []
	var total := 0
	for where: String in scenes:
		var s: RideScene = scenes[where]
		assert_not_null(s, "%s: сцена есть" % where)
		if s == null:
			continue
		gut.p("%s: трасса %s, узлов с параметрами %d" % [where, s.route_id, RenderLook.instances_under(s).size()])
		total += RenderLook.instances_under(s).size()
		all.append_array(_look_issues(s, "%s (%s)" % [where, s.route_id]))
	assert_ne((scenes["тренировка"] as RideScene).route_id, (scenes["замер FPS"] as RideScene).route_id, "предусловие: разные трассы")
	assert_lt(total, PROCESS_LOOK_CAPACITY, "узлов с параметрами экземпляра на процесс %d < %d" % [total, PROCESS_LOOK_CAPACITY])
	for i in all.slice(0, 20):
		gut.p(i)
	assert_eq(all.size(), 0, "нарушений %d" % all.size())
	bench.close()
