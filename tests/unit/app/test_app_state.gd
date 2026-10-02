extends GutTest
## Тесты модели навигации AppState (REQ-PRF-05 крит. 1–3, REQ-NFR-08 крит. 3).

var _dir: String
var _repo: ProfileRepository
var _screens: Array[int] = []
var _selected: Array[String] = []


func before_each() -> void:
	_dir = "user://test_app_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_repo = ProfileRepository.new(_dir)
	_screens = []
	_selected = []


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


func _state() -> AppState:
	var s := AppState.new(_repo)
	s.screen_changed.connect(func(screen: int) -> void: _screens.append(screen))
	s.profile_selected.connect(func(id: String) -> void: _selected.append(id))
	return s


func test_initial_screen_rule_0_1_2_profiles() -> void:
	assert_eq(AppState.initial_screen(_repo), AppState.Screen.PROFILE_SELECT, "0 профилей → выбор/создание")
	_repo.create("Один")
	assert_eq(AppState.initial_screen(_repo), AppState.Screen.HOME, "REQ-PRF-05 крит. 1")
	_repo.create("Два")
	assert_eq(AppState.initial_screen(_repo), AppState.Screen.PROFILE_SELECT, "REQ-PRF-05 крит. 2")
	assert_eq(_repo.count(), 2, "initial_screen без побочных эффектов")


func test_start_with_no_profiles_opens_create_mode() -> void:
	var s := _state()
	s.start()
	assert_eq(s.current_screen, AppState.Screen.PROFILE_SELECT)
	assert_true(s.create_mode, "REQ-PRF-05 крит. 3")
	assert_false(s.can_open_main())
	assert_eq(_selected, [])


func test_start_with_single_profile_autoselects_and_goes_home() -> void:
	var p := _repo.create("Один")
	var s := _state()
	s.start()
	assert_eq(s.current_screen, AppState.Screen.HOME)
	assert_true(s.can_open_main())
	assert_eq(_repo.active_profile_id, p.id)
	assert_eq(_selected, [p.id])
	assert_eq(_screens, [AppState.Screen.HOME])


func test_start_with_two_profiles_requires_explicit_choice_even_if_active_saved() -> void:
	var a := _repo.create("Алиса")
	_repo.create("Боб")
	_repo.active_profile_id = a.id
	var s := _state()
	s.start()
	assert_eq(s.current_screen, AppState.Screen.PROFILE_SELECT)
	assert_false(s.create_mode)
	assert_false(s.can_open_main(), "REQ-PRF-05 крит. 2: главный недоступен до выбора")
	assert_false(s.navigate(AppState.Screen.HOME))
	assert_eq(s.current_screen, AppState.Screen.PROFILE_SELECT)


func test_select_profile_sets_active_and_opens_home() -> void:
	_repo.create("Алиса")
	var b := _repo.create("Боб")
	var s := _state()
	s.start()
	assert_true(s.select_profile(b.id))
	assert_eq(_repo.active_profile_id, b.id)
	assert_eq(s.current_screen, AppState.Screen.HOME)
	assert_true(s.can_open_main())
	assert_eq(_selected, [b.id])


func test_select_unknown_profile_fails() -> void:
	_repo.create("Алиса")
	_repo.create("Боб")
	var s := _state()
	s.start()
	assert_false(s.select_profile("ghost"))
	assert_eq(s.current_screen, AppState.Screen.PROFILE_SELECT)
	assert_false(s.can_open_main())


func test_navigate_between_main_screens_after_selection() -> void:
	_repo.create("Один")
	var s := _state()
	s.start()
	_screens = []
	assert_true(s.navigate(AppState.Screen.WORKOUT))
	assert_true(s.navigate(AppState.Screen.HISTORY))
	assert_true(s.navigate(AppState.Screen.SETTINGS))
	assert_true(s.navigate(AppState.Screen.DEV))
	assert_true(s.navigate(AppState.Screen.HOME))
	assert_eq(_screens, [AppState.Screen.WORKOUT, AppState.Screen.HISTORY, AppState.Screen.SETTINGS, AppState.Screen.DEV, AppState.Screen.HOME])


func test_navigate_to_same_screen_does_not_emit() -> void:
	_repo.create("Один")
	var s := _state()
	s.start()
	_screens = []
	assert_true(s.navigate(AppState.Screen.HOME))
	assert_eq(_screens, [])


func test_switch_profile_returns_to_select_and_locks_main() -> void:
	_repo.create("Один")
	var s := _state()
	s.start()
	s.switch_profile()
	assert_eq(s.current_screen, AppState.Screen.PROFILE_SELECT)
	assert_false(s.can_open_main())
	assert_false(s.navigate(AppState.Screen.HOME))
	assert_true(s.navigate(AppState.Screen.PROFILE_SELECT), "экран выбора доступен всегда")


func test_pick_locale_ru_en_fallback() -> void:
	assert_eq(AppLocale.pick("ru"), "ru")
	assert_eq(AppLocale.pick("de_DE"), "en")
	assert_true(AppLocale.SUPPORTED_LOCALES.has(AppLocale.detect()), "detect() всегда даёт поддерживаемый язык")
	assert_eq(AppState.pick_locale("ru"), "ru")
	assert_eq(AppState.pick_locale("ru_RU"), "ru")
	assert_eq(AppState.pick_locale("en"), "en")
	assert_eq(AppState.pick_locale("en_US"), "en")
	assert_eq(AppState.pick_locale("de"), "en", "REQ-NFR-08 крит. 3: откат на en")
	assert_eq(AppState.pick_locale(""), "en")


func test_screen_name() -> void:
	assert_eq(AppState.screen_name(AppState.Screen.PROFILE_SELECT), "profile_select")
	assert_eq(AppState.screen_name(AppState.Screen.DEV), "dev")
	assert_eq(AppState.screen_name(99), "unknown")
