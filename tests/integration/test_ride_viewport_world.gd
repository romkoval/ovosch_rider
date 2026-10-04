extends GutTest
## T-096: у 3D экранов заезда свой мир (REQ-D3D-07 п.6, REQ-HUD-13 п.10).
## Оба экрана живут в `main.tscn` всё время. Пока `SubViewport` без `own_world_3d` делили
## `World3D` корневого окна, вторая `RideScene` (свободная езда) добавляла в тот же мир второе
## солнце и второй `WorldEnvironment`: кадр пересвечен (трава жёлтая, холмы белые), небо и
## туман — от трассы, зарегистрированной первой. Цвета headless не проверить — проверяется то,
## что их определяет: у каждого экрана свой мир, в мире одно солнце и окружение своей трассы.

const MAIN_SCENE: String = "res://src/app/main.tscn"
const SCREEN_SCENES: Array[String] = [
	"res://src/ui/workout/workout_screen.tscn",
	"res://src/ui/free_ride/free_ride_screen.tscn",
]

var _dir: String


func before_each() -> void:
	_dir = "user://test_ride_viewport_world_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]


func after_each() -> void:
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


func _ignore(_on: bool) -> void:
	pass


func _main() -> AppMain:
	ProfileRepository.new(_dir + "profiles/").create("Solo")
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	add_child_autofree(main)
	main.workout_screen().keep_awake_setter = _ignore
	main.free_ride_screen().keep_awake_setter = _ignore
	return main


## Солнца (`DirectionalLight3D`) под узлом, сгруппированные по миру, в котором они светят.
static func _suns_by_world(root: Node) -> Dictionary:
	var by_world: Dictionary = {}
	for n in root.find_children("*", "DirectionalLight3D", true, false):
		var w: World3D = (n as Node3D).get_world_3d()
		by_world[w] = int(by_world.get(w, 0)) + 1
	return by_world


func test_screen_subviewports_own_world_3d() -> void:
	for path in SCREEN_SCENES:
		var screen: Control = load(path).instantiate()
		var vp := screen.find_child("Viewport", true, false) as SubViewport
		assert_not_null(vp, "%s: SubViewport 3D-фона" % path)
		if vp != null:
			assert_true(vp.own_world_3d, "%s: свой World3D — мир экрана не смешивается с другими" % path)
		screen.free()


func test_free_ride_and_workout_scenes_do_not_share_world() -> void:
	var main := _main()
	assert_true(main.start_free_ride_on_emulator(RouteCatalog.MOUNTAINS, 50), "предусловие: свободная езда запущена")
	var free_scene := main.free_ride_screen().ride_scene()
	var workout_scene := main.workout_screen().ride_scene()
	assert_not_null(free_scene, "предусловие: сцена свободной езды создана")
	assert_not_null(workout_scene, "предусловие: сцена тренировки в дереве")
	if free_scene == null or workout_scene == null:
		return
	var free_world := free_scene.get_world_3d()
	var workout_world := workout_scene.get_world_3d()
	assert_ne(free_world, workout_world, "у экранов разные World3D")
	assert_ne(free_world, main.get_viewport().world_3d, "3D свободной езды не в мире корневого окна")
	assert_ne(workout_world, main.get_viewport().world_3d, "3D тренировки не в мире корневого окна")
	var suns := _suns_by_world(main)
	for w: World3D in suns:
		assert_eq(int(suns[w]), 1, "в мире ровно одно солнце (два — пересвет кадра)")


func test_each_world_uses_own_route_environment() -> void:
	var main := _main()
	assert_true(main.start_free_ride_on_emulator(RouteCatalog.MOUNTAINS, 50), "предусловие: свободная езда запущена")
	for scene: RideScene in [main.workout_screen().ride_scene(), main.free_ride_screen().ride_scene()]:
		var env_node := scene.find_child("WorldEnvironment", true, false) as WorldEnvironment
		assert_not_null(env_node)
		if env_node == null:
			continue
		assert_not_null(env_node.environment, "%s: окружение применено" % scene.route_id)
		assert_eq(scene.get_world_3d().environment, env_node.environment,
			"%s: небо, свет и туман мира — от своей трассы" % scene.route_id)
