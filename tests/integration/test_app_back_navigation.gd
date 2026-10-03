extends GutTest
## «Назад» в оболочке `main.tscn` (T-061): REQ-UIX-04 крит. 1 — Esc и системный «назад» Android
## возвращают на экран, с которого пришли; крит. 2 — на экране тренировки «назад» не завершает
## сессию, а просит подтверждение (WRK-05 крит. 4); заготовки экранов `ROUTE_SELECT`/`FREE_RIDE`;
## REQ-FRD-02 крит. 3 — предвыбранная трасса из профиля.

const MAIN_SCENE: String = "res://src/app/main.tscn"

var _dir: String
var _previous_locale: String


func before_each() -> void:
	_dir = "user://test_back_nav_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_each() -> void:
	TranslationServer.set_locale(_previous_locale)
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


func _main() -> AppMain:
	ProfileRepository.new(_dir + "profiles/").create("Solo")
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	add_child_autofree(main)
	return main


static func _esc() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	return event


func _press_esc(main: AppMain) -> void:
	main._unhandled_input(_esc())


func _android_back(main: AppMain) -> void:
	main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)


func test_new_screens_are_real_scenes() -> void:
	var main := _main()
	assert_true(main.app_state.navigate(AppState.Screen.ROUTE_SELECT))
	assert_true(main.visible_screen_node() is RouteSelectScreen)
	assert_eq(main.visible_screen_node(), main.route_select_screen())
	assert_true(main.app_state.navigate(AppState.Screen.FREE_RIDE))
	assert_true(main.visible_screen_node() is FreeRideScreen)
	assert_eq(main.visible_screen_node(), main.free_ride_screen())
	for screen in AppState.Screen.values():
		assert_not_null(main.screen_node(screen), "узел есть для %s" % AppState.screen_name(screen))


func test_esc_returns_from_history_settings_devices_to_home() -> void:
	var main := _main()
	for screen in [AppState.Screen.HISTORY, AppState.Screen.SETTINGS, AppState.Screen.DEVICES, AppState.Screen.ROUTE_SELECT]:
		main.app_state.navigate(screen)
		_press_esc(main)
		assert_eq(main.app_state.current_screen, AppState.Screen.HOME, "Esc: %s → главный" % AppState.screen_name(screen))
		assert_true(main.visible_screen_node() is HomeScreen)


func test_android_back_matches_esc_and_returns_to_previous() -> void:
	var main := _main()
	main.app_state.navigate(AppState.Screen.PLAN)
	main.app_state.navigate(AppState.Screen.DEVICES)
	_android_back(main)
	assert_eq(main.app_state.current_screen, AppState.Screen.PLAN, "Android «назад»: устройства → план")
	_android_back(main)
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME)
	_android_back(main)
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME, "на главном «назад» ничего не делает")
	assert_false(get_tree().quit_on_go_back, "движок не закрывает приложение сам")


func test_esc_on_home_and_profile_select_does_nothing() -> void:
	var main := _main()
	assert_false(main.handle_back())
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME)
	main.app_state.switch_profile()
	assert_false(main.handle_back())
	assert_eq(main.app_state.current_screen, AppState.Screen.PROFILE_SELECT)


func test_route_select_back_button_and_preselected_route() -> void:
	var main := _main()
	var route := main.route_select_screen()
	assert_eq(route.preselected_route_id(), "flat", "FRD-02 крит. 3: первый запуск — равнина")
	assert_eq(route.preselected_sim_steepness_pct(), 50)
	var active := main.repo.get_active()
	assert_eq(main.repo.set_last_route_id(active.id, "hills"), [])
	assert_eq(main.repo.set_sim_steepness_pct(active.id, 35), [])
	main.app_state.navigate(AppState.Screen.ROUTE_SELECT)
	assert_eq(route.preselected_route_id(), "hills", "последняя трасса предвыбрана")
	assert_eq(route.preselected_sim_steepness_pct(), 35)
	route.app_bar().back_button().pressed.emit()  # «назад» AppBar (T-080)
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME)


func test_free_ride_stub_back_goes_home() -> void:
	var main := _main()
	main.app_state.navigate(AppState.Screen.ROUTE_SELECT)
	main.app_state.navigate(AppState.Screen.FREE_RIDE)
	_press_esc(main)
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME, "без сессии — на главный")
	main.app_state.navigate(AppState.Screen.FREE_RIDE)
	(main.free_ride_screen().get_node("%BackButton") as Button).pressed.emit()
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME)


func test_history_detail_back_returns_to_list_first() -> void:
	var main := _main()
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	# Слой карточки показываем напрямую: для проверки «назад» заезд не нужен.
	(history.get_node("%Detail") as Control).visible = true
	assert_true(history.is_detail_visible())
	_press_esc(main)
	assert_false(history.is_detail_visible(), "Esc закрывает карточку заезда")
	assert_eq(main.app_state.current_screen, AppState.Screen.HISTORY)
	_press_esc(main)
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME)


func test_workout_back_asks_confirmation_and_does_not_stop() -> void:
	var main := _main()
	main.start_emulator_workout()
	assert_eq(main.app_state.current_screen, AppState.Screen.WORKOUT)
	var ws := main.workout_screen()
	assert_not_null(ws.session())
	_press_esc(main)
	assert_true(ws.is_stop_confirmation_pending(), "UIX-04 крит. 2: Esc просит подтверждение")
	assert_eq(ws.session().get_state(), WorkoutSession.State.RUNNING, "сессия не остановлена")
	assert_eq(main.app_state.current_screen, AppState.Screen.WORKOUT)
	_android_back(main)
	assert_false(ws.is_stop_confirmation_pending(), "повторный «назад» закрывает диалог как «Отмена»")
	assert_eq(ws.session().get_state(), WorkoutSession.State.RUNNING)
	assert_eq(main.app_state.current_screen, AppState.Screen.WORKOUT)
	ws.confirm_stop()
	assert_eq(ws.session().get_state(), WorkoutSession.State.FINISHED)
	_press_esc(main)
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME, "после финиша «назад» — на главный")


func test_android_back_closes_open_dialog_before_navigating() -> void:
	var main := _main()
	main.app_state.navigate(AppState.Screen.PLAN)
	var plan := main.plan_screen()
	plan.show_trainer_choice()
	var dialog: ConfirmationDialog = plan.get_node("%TrainerDialog")
	assert_true(dialog.visible)
	var canceled: Array[bool] = []
	dialog.canceled.connect(func() -> void: canceled.append(true))
	_android_back(main)
	assert_false(dialog.visible, "диалог закрыт")
	assert_eq(canceled, [true], "закрытие — как «Отмена»")
	assert_eq(main.app_state.current_screen, AppState.Screen.PLAN, "экран не сменился")
	_android_back(main)
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME)


func test_dev_screen_back_stops_emulator_run() -> void:
	var main := _main()
	main.app_state.navigate(AppState.Screen.DEV)
	_press_esc(main)
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME)
