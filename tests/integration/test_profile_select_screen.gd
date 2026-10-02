extends GutTest
## Интеграционные тесты экрана выбора профиля и корневой сцены (REQ-PRF-01 крит. 1, 2, 4, 5; REQ-PRF-05).
## Сцены инстанцируются headless и добавляются в дерево через add_child_autofree.

const SCENE: String = "res://src/ui/profile_select/profile_select.tscn"
const MAIN_SCENE: String = "res://src/app/main.tscn"

var _dir: String
var _repo: ProfileRepository
var _state: AppState


func before_each() -> void:
	_dir = "user://test_ui_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_repo = ProfileRepository.new(_dir + "profiles/")
	_state = AppState.new(_repo)
	TranslationServer.set_locale("en")


func after_each() -> void:
	_remove_tree(ProjectSettings.globalize_path(_dir))
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir)))


static func _remove_tree(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var d := DirAccess.open(abs_path)
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)


func _screen() -> ProfileSelectScreen:
	var s: ProfileSelectScreen = load(SCENE).instantiate()
	s.setup(_repo, _state)
	add_child_autofree(s)
	return s


func test_empty_repository_opens_create_form_and_disables_buttons() -> void:
	var s := _screen()
	assert_eq(s.profile_count(), 0)
	assert_true(s.is_create_form_open(), "REQ-PRF-05 крит. 3")
	assert_true((s.get_node("%SelectButton") as Button).disabled)
	assert_true((s.get_node("%DeleteButton") as Button).disabled)
	assert_true((s.get_node("%EmptyHint") as Label).visible)


func test_create_profile_from_form_adds_it_to_repository_and_list() -> void:
	var s := _screen()
	var created: Array[String] = []
	s.profile_created.connect(func(id: String) -> void: created.append(id))
	s.fill_create_form("  Даша ", 220, 61.5, 185)
	var p := s.submit_create()
	assert_not_null(p)
	assert_eq(_repo.count(), 1)
	assert_eq(_repo.get_by_id(p.id).name, "Даша")
	assert_eq(_repo.get_by_id(p.id).ftp_w, 220)
	assert_almost_eq(_repo.get_by_id(p.id).weight_kg, 61.5, 1e-9)
	assert_eq(_repo.get_by_id(p.id).max_hr, 185)
	assert_eq(s.profile_count(), 1)
	assert_eq(s.selected_profile_id(), p.id, "новый профиль выделен")
	assert_false(s.is_create_form_open())
	assert_eq(s.error_text(), "")
	assert_eq(created, [p.id])


func test_invalid_ftp_shows_translated_error_and_creates_nothing() -> void:
	var s := _screen()
	s.fill_create_form("Даша", 30, 70.0)
	assert_null(s.submit_create())
	assert_eq(_repo.count(), 0)
	assert_eq(s.error_text(), "FTP must be between 50 and 600 W")
	assert_true(s.is_create_form_open(), "форма остаётся открытой для исправления")


func test_errors_follow_locale() -> void:
	var s := _screen()
	TranslationServer.set_locale("ru")
	s.fill_create_form("", 200, 70.0)
	assert_null(s.submit_create())
	assert_eq(s.error_text(), "Введите имя профиля")
	TranslationServer.set_locale("en")


func test_multiple_errors_are_listed() -> void:
	var s := _screen()
	s.fill_create_form("", 700, 10.0, 50)
	assert_null(s.submit_create())
	var lines := s.error_text().split("\n")
	assert_eq(lines.size(), 4)
	assert_has(lines, "Enter a profile name")
	assert_has(lines, "Max heart rate must be 100–220 or 0")


func test_duplicate_name_is_rejected_in_form() -> void:
	_repo.create("Даша")
	var s := _screen()
	s.open_create_form()
	s.fill_create_form("даша", 200, 70.0)
	assert_null(s.submit_create())
	assert_eq(_repo.count(), 1)
	assert_eq(s.error_text(), "A profile with this name already exists")


func test_select_moves_app_state_to_home() -> void:
	var a := _repo.create("Алиса")
	var b := _repo.create("Боб")
	_state.start()
	var s := _screen()
	var chosen: Array[String] = []
	s.profile_chosen.connect(func(id: String) -> void: chosen.append(id))
	assert_false(s.is_create_form_open())
	assert_eq(s.profile_count(), 2)
	assert_eq(_state.current_screen, AppState.Screen.PROFILE_SELECT)
	s.select_index(1)
	assert_eq(s.selected_profile_id(), b.id)
	assert_true(s.select_current())
	assert_eq(_state.current_screen, AppState.Screen.HOME)
	assert_eq(_repo.active_profile_id, b.id)
	assert_eq(chosen, [b.id])
	assert_ne(a.id, b.id)


func test_select_without_selection_does_nothing() -> void:
	_repo.create("Алиса")
	_repo.create("Боб")
	_state.start()
	var s := _screen()
	(s.get_node("%ProfileList") as ItemList).deselect_all()
	assert_false(s.select_current())
	assert_eq(_state.current_screen, AppState.Screen.PROFILE_SELECT)


func test_delete_requires_confirmation_and_refuses_last_profile() -> void:
	var a := _repo.create("Алиса")
	var b := _repo.create("Боб")
	var s := _screen()
	s.select_index(1)
	assert_true(s.request_delete(), "показано подтверждение")
	assert_eq(s.pending_delete_id(), b.id)
	assert_eq(_repo.count(), 2, "до подтверждения ничего не удалено")
	assert_eq(s.confirm_delete(), "")
	assert_eq(_repo.count(), 1)
	assert_eq(s.profile_count(), 1)
	s.select_index(0)
	assert_true((s.get_node("%DeleteButton") as Button).disabled, "последний профиль удалить нельзя")
	s.request_delete()
	assert_eq(s.confirm_delete(), ProfileRepository.ERR_LAST_PROFILE, "REQ-PRF-01 крит. 5")
	assert_eq(_repo.count(), 1)
	assert_eq(_repo.get_by_id(a.id).name, "Алиса")


func test_cancel_create_form_hides_it() -> void:
	_repo.create("Алиса")
	var s := _screen()
	s.open_create_form()
	assert_true(s.is_create_form_open())
	s.close_create_form()
	assert_false(s.is_create_form_open())


func test_list_items_are_translated_with_ftp() -> void:
	_repo.create("Алиса")
	var s := _screen()
	var list: ItemList = s.get_node("%ProfileList")
	assert_eq(list.get_item_text(0), "Алиса — FTP 200 W")


func test_home_screen_shows_active_profile_and_switches() -> void:
	var p := _repo.create("Алиса")
	_state.start()
	var home: HomeScreen = load("res://src/ui/home/home.tscn").instantiate()
	home.setup(_repo, _state)
	add_child_autofree(home)
	assert_eq(home.active_profile_text(), "Profile: Алиса")
	assert_eq(_repo.active_profile_id, p.id)
	home.switch_profile()
	assert_eq(_state.current_screen, AppState.Screen.PROFILE_SELECT)


func test_main_scene_boots_with_no_profiles_into_create_mode() -> void:
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	add_child_autofree(main)
	assert_not_null(main.repo)
	assert_not_null(main.secure_store)
	assert_not_null(main.devices)
	assert_eq(main.app_state.current_screen, AppState.Screen.PROFILE_SELECT)
	assert_true(main.app_state.create_mode)
	var visible := main.visible_screen_node()
	assert_true(visible is ProfileSelectScreen)
	assert_true((visible as ProfileSelectScreen).is_create_form_open())


func test_main_scene_with_one_profile_shows_home_and_switches_screens() -> void:
	_repo.create("Алиса")
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	add_child_autofree(main)
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME, "REQ-PRF-05 крит. 1")
	assert_true(main.visible_screen_node() is HomeScreen)
	assert_true(main.app_state.navigate(AppState.Screen.WORKOUT))
	assert_eq(main.visible_screen_node().name, "Placeholder_workout")
	main.app_state.switch_profile()
	assert_true(main.visible_screen_node() is ProfileSelectScreen)


func test_main_scene_cascades_profile_deletion_to_secrets_and_devices() -> void:
	var a := _repo.create("Алиса")
	var b := _repo.create("Боб")
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	add_child_autofree(main)
	main.secure_store.set_secret(SecureStore.key_for(b.id, "strava", "access_token"), "tok")
	main.devices.remember(b.id, RememberedDevices.make_device("hr-1", "HRM", RememberedDevices.KIND_HR))
	main.devices.set_trainer(RememberedDevices.make_device("neo", "Neo", RememberedDevices.KIND_TRAINER))
	assert_eq(main.repo.delete(b.id), "")
	assert_false(main.secure_store.has_secret(SecureStore.key_for(b.id, "strava", "access_token")))
	assert_eq(main.devices.sensors(b.id), [])
	assert_true(main.devices.has_trainer())
	assert_not_null(main.repo.get_by_id(a.id))
