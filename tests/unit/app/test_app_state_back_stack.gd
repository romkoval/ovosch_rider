extends GutTest
## Стек «назад» и новые экраны ред. 2 в AppState (T-061): REQ-UIX-04 крит. 1 (навигация «назад»
## на экран, с которого пришли), крит. 2 (на экранах сессии `go_back` не уводит), REQ-UIX-02
## крит. 3, 4 (главный → устройства/история/настройки и обратно), FRD-01 крит. 1 (экраны
## `ROUTE_SELECT`, `FREE_RIDE` в навигации).

var _dir: String
var _repo: ProfileRepository
var _screens: Array[int] = []


func before_each() -> void:
	_dir = "user://test_app_back_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_repo = ProfileRepository.new(_dir)
	_screens = []


func after_each() -> void:
	_remove_tree(ProjectSettings.globalize_path(_dir))


static func _remove_tree(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var d := DirAccess.open(abs_path)
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)


func _on_screen(screen: int) -> void:
	_screens.append(screen)


## Один профиль → сразу HOME, стек пуст.
func _started_state() -> AppState:
	_repo.create("Один")
	var s := AppState.new(_repo)
	s.screen_changed.connect(_on_screen)
	s.start()
	_screens = []
	return s


func test_new_screens_exist_and_are_navigable() -> void:
	var s := _started_state()
	assert_eq(AppState.screen_name(AppState.Screen.ROUTE_SELECT), "route_select")
	assert_eq(AppState.screen_name(AppState.Screen.FREE_RIDE), "free_ride")
	assert_eq(AppState.Screen.PLAN, 7, "старые значения перечисления не сдвинуты")
	assert_true(s.navigate(AppState.Screen.ROUTE_SELECT))
	assert_true(s.navigate(AppState.Screen.FREE_RIDE))
	assert_eq(_screens, [AppState.Screen.ROUTE_SELECT, AppState.Screen.FREE_RIDE])


func test_unknown_screen_is_rejected() -> void:
	var s := _started_state()
	assert_false(s.navigate(99))
	assert_false(s.navigate(-1))
	assert_eq(s.current_screen, AppState.Screen.HOME)
	assert_eq(_screens, [])


func test_root_has_no_back() -> void:
	var s := _started_state()
	assert_false(s.can_go_back())
	assert_eq(s.back_target(), -1)
	assert_false(s.go_back(), "с главного «назад» некуда")
	assert_eq(s.current_screen, AppState.Screen.HOME)
	assert_eq(_screens, [])


func test_history_settings_devices_return_home() -> void:
	var s := _started_state()
	for screen in [AppState.Screen.HISTORY, AppState.Screen.SETTINGS, AppState.Screen.DEVICES]:
		assert_true(s.navigate(screen))
		assert_eq(s.back_target(), AppState.Screen.HOME, AppState.screen_name(screen))
		assert_true(s.go_back(), AppState.screen_name(screen))
		assert_eq(s.current_screen, AppState.Screen.HOME, "UIX-04 крит. 1: %s → главный" % AppState.screen_name(screen))
		assert_false(s.can_go_back())


func test_back_returns_to_screen_we_came_from() -> void:
	var s := _started_state()
	s.navigate(AppState.Screen.PLAN)
	s.navigate(AppState.Screen.DEVICES)
	assert_eq(s.back_stack(), [AppState.Screen.HOME, AppState.Screen.PLAN])
	assert_true(s.go_back())
	assert_eq(s.current_screen, AppState.Screen.PLAN, "устройства, открытые из плана, возвращают в план")
	assert_true(s.go_back())
	assert_eq(s.current_screen, AppState.Screen.HOME)
	assert_false(s.go_back())
	assert_eq(_screens, [AppState.Screen.PLAN, AppState.Screen.DEVICES, AppState.Screen.PLAN, AppState.Screen.HOME])


func test_navigating_to_screen_in_stack_truncates_it() -> void:
	var s := _started_state()
	s.navigate(AppState.Screen.ROUTE_SELECT)
	s.navigate(AppState.Screen.DEVICES)
	s.navigate(AppState.Screen.ROUTE_SELECT)
	assert_eq(s.back_stack(), [AppState.Screen.HOME], "цикла выбор трассы → устройства → выбор трассы нет")
	assert_true(s.go_back())
	assert_eq(s.current_screen, AppState.Screen.HOME)


func test_navigate_home_clears_stack() -> void:
	var s := _started_state()
	s.navigate(AppState.Screen.PLAN)
	s.navigate(AppState.Screen.DEVICES)
	assert_true(s.navigate(AppState.Screen.HOME), "старые кнопки «На главный» продолжают работать")
	assert_eq(s.back_stack(), [])
	assert_false(s.can_go_back())


func test_navigate_same_screen_keeps_stack_and_does_not_emit() -> void:
	var s := _started_state()
	s.navigate(AppState.Screen.SETTINGS)
	_screens = []
	assert_true(s.navigate(AppState.Screen.SETTINGS))
	assert_eq(s.back_stack(), [AppState.Screen.HOME])
	assert_eq(_screens, [])


func test_session_screens_block_go_back() -> void:
	var s := _started_state()
	s.navigate(AppState.Screen.ROUTE_SELECT)
	s.navigate(AppState.Screen.FREE_RIDE)
	assert_true(AppState.is_session_screen(AppState.Screen.FREE_RIDE))
	assert_true(AppState.is_session_screen(AppState.Screen.WORKOUT))
	assert_false(s.can_go_back(), "UIX-04 крит. 2: «назад» на экране сессии решает экран")
	assert_eq(s.back_target(), -1)
	assert_false(s.go_back())
	assert_eq(s.current_screen, AppState.Screen.FREE_RIDE)
	s.navigate(AppState.Screen.PLAN)
	s.navigate(AppState.Screen.WORKOUT)
	assert_false(s.go_back())
	assert_eq(s.current_screen, AppState.Screen.WORKOUT)


func test_after_session_back_leads_home_not_into_selection() -> void:
	var s := _started_state()
	s.navigate(AppState.Screen.PLAN)
	s.navigate(AppState.Screen.WORKOUT)
	s.navigate(AppState.Screen.HISTORY)
	assert_eq(s.back_stack(), [AppState.Screen.HOME], "экран сессии и путь выбора в стек не попадают")
	assert_true(s.go_back())
	assert_eq(s.current_screen, AppState.Screen.HOME)


func test_profile_switch_and_restart_clear_stack() -> void:
	var s := _started_state()
	s.navigate(AppState.Screen.SETTINGS)
	s.switch_profile()
	assert_eq(s.current_screen, AppState.Screen.PROFILE_SELECT)
	assert_false(s.can_go_back(), "с выбора профиля «назад» некуда")
	assert_false(s.go_back())
	s.start()
	assert_eq(s.current_screen, AppState.Screen.HOME)
	assert_eq(s.back_stack(), [])


func test_root_and_session_screen_sets() -> void:
	assert_true(AppState.is_root_screen(AppState.Screen.HOME))
	assert_true(AppState.is_root_screen(AppState.Screen.PROFILE_SELECT))
	for screen in [AppState.Screen.HISTORY, AppState.Screen.SETTINGS, AppState.Screen.DEVICES, AppState.Screen.PLAN,
			AppState.Screen.DEV, AppState.Screen.ROUTE_SELECT]:
		assert_false(AppState.is_root_screen(screen))
		assert_false(AppState.is_session_screen(screen))
