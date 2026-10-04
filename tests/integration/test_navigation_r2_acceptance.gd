extends GutTest
## Независимые приёмочные тесты навигационного каркаса ред. 2 (тестировщик, T-061).
## Покрытие: REQ-UIX-04 крит. 1, 2 (навигация «назад», Esc, системный «назад» Android);
## REQ-UIX-02 крит. 3 (часть «нажатие ведёт на экран устройств» — переход и возврат);
## REQ-FRD-02 крит. 3 и REQ-FRD-05 крит. 1 — хранение в профиле между запусками.
## Esc подаётся настоящим событием ввода в корневое окно (`Viewport.push_input`), Android —
## уведомлением `NOTIFICATION_WM_GO_BACK_REQUEST`, разосланным по дереву, как это делает движок.

const MAIN_SCENE: String = "res://src/app/main.tscn"

var _dir: String
var _prev_locale: String
var _now_usec: int = 0


func before_each() -> void:
	_dir = "user://test_nav_r2_acc_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_prev_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	_now_usec = 0


func after_each() -> void:
	TranslationServer.set_locale(_prev_locale)
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


func _main(profiles: Array = ["Аня"]) -> AppMain:
	var repo := ProfileRepository.new(_dir + "profiles/")
	if repo.count() == 0:
		for name in profiles:
			repo.create(str(name))
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	add_child_autofree(main)
	return main


func _clock() -> int:
	return _now_usec


func _esc() -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.physical_keycode = KEY_ESCAPE
		ev.pressed = pressed
		get_tree().root.push_input(ev)


func _android_back() -> void:
	get_tree().root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)


func _screen(main: AppMain) -> String:
	return AppState.screen_name(main.app_state.current_screen)


func _press(node: Node, unique: String) -> void:
	(node.get_node("%" + unique) as Button).pressed.emit()


# ===========================================================================
# REQ-UIX-04 крит. 1 — «назад» на экран, с которого пришли; Esc и Android так же
# ===========================================================================

func test_req_uix_04_c1_esc_walks_back_the_path_home_plan_devices() -> void:
	var main := _main()
	assert_eq(_screen(main), "home", "предусловие: один профиль → главный")
	_press(main.screen_node(AppState.Screen.HOME), "WorkoutButton")
	assert_eq(_screen(main), "plan")
	assert_true(main.app_state.navigate(AppState.Screen.DEVICES), "с выбора тренировки — на устройства")
	_esc()
	assert_eq(_screen(main), "plan", "Esc: устройства → выбор тренировки (откуда пришли)")
	_esc()
	assert_eq(_screen(main), "home", "Esc: выбор тренировки → главный")
	_esc()
	assert_eq(_screen(main), "home", "на главном «назад» некуда — экран не меняется")
	assert_true(main.visible_screen_node() == main.screen_node(AppState.Screen.HOME), "виден главный экран")


func test_req_uix_04_c1_android_back_walks_the_same_path() -> void:
	var main := _main()
	_press(main.screen_node(AppState.Screen.HOME), "WorkoutButton")
	main.app_state.navigate(AppState.Screen.DEVICES)
	assert_false(get_tree().quit_on_go_back, "не на корне «назад» перехватывает приложение")
	_android_back()
	assert_eq(_screen(main), "plan", "Android «назад»: устройства → выбор тренировки")
	_android_back()
	assert_eq(_screen(main), "home")
	# Новая редакция крит. 1 (У-4): на корне «назад» Android не поглощается приложением — движок
	# сворачивает/закрывает приложение (`quit_on_go_back`); само сворачивание — ручная проверка.
	assert_true(get_tree().quit_on_go_back, "на главном событие «назад» отдаётся движку")
	assert_eq(_screen(main), "home", "экран и стек не менялись")


func test_req_uix_04_c1_history_settings_devices_back_to_home_by_all_three_ways() -> void:
	var main := _main()
	var home := main.screen_node(AppState.Screen.HOME)
	for item in [["HistoryButton", "history"], ["SettingsButton", "settings"], ["DevicesButton", "devices"]]:
		for way in ["esc", "android"]:
			_press(home, item[0])
			assert_eq(_screen(main), item[1], "с главного одним нажатием — %s" % item[1])
			if way == "esc":
				_esc()
			else:
				_android_back()
			assert_eq(_screen(main), "home", "%s: %s → главный" % [way, item[1]])


func test_req_uix_04_c1_route_select_back_to_where_came_from() -> void:
	var main := _main()
	assert_true(main.app_state.navigate(AppState.Screen.ROUTE_SELECT))
	assert_true(main.visible_screen_node() is RouteSelectScreen, "экран выбора трассы — сцена")
	_esc()
	assert_eq(_screen(main), "home", "Esc с выбора трассы → главный")
	main.app_state.navigate(AppState.Screen.ROUTE_SELECT)
	main.route_select_screen().app_bar().back_button().pressed.emit()  # «назад» AppBar (T-080)
	assert_eq(_screen(main), "home", "кнопка «назад» выбора трассы → главный")
	# Пришли с настроек — туда и возвращаемся.
	main.app_state.navigate(AppState.Screen.SETTINGS)
	main.app_state.navigate(AppState.Screen.ROUTE_SELECT)
	_android_back()
	assert_eq(_screen(main), "settings", "выбор трассы → экран, с которого пришли")


func test_req_uix_04_c1_profile_select_is_root_back_does_not_bypass_choice() -> void:
	var main := _main(["Аня", "Боря"])
	assert_eq(_screen(main), "profile_select", "два профиля — выбор профиля")
	_esc()
	_android_back()
	assert_eq(_screen(main), "profile_select", "«назад» не открывает главный без выбора профиля")
	assert_false(main.app_state.can_open_main())
	main.app_state.select_profile(main.repo.list()[0].id)
	main.app_state.navigate(AppState.Screen.HISTORY)
	main.app_state.switch_profile()
	_esc()
	assert_eq(_screen(main), "profile_select", "после смены профиля «назад» не уводит в старую историю")


func test_req_uix_04_c1_esc_with_open_dialog_closes_dialog_first() -> void:
	var main := _main()
	main.app_state.navigate(AppState.Screen.HISTORY)
	var dialog := AcceptDialog.new()
	main.screen_node(AppState.Screen.HISTORY).add_child(dialog)
	dialog.popup_centered()
	assert_true(dialog.visible, "предусловие: диалог открыт")
	_android_back()
	assert_false(dialog.visible, "Android «назад» закрывает диалог")
	assert_eq(_screen(main), "history", "и не уводит с экрана")
	_android_back()
	assert_eq(_screen(main), "home")


# ===========================================================================
# REQ-UIX-04 крит. 2 — на экране тренировки «назад» не завершает сессию без подтверждения
# ===========================================================================

func _start_workout(main: AppMain) -> WorkoutScreen:
	var screen := main.workout_screen()
	screen.clock_usec = _clock
	screen.keep_awake_setter = func(_on: bool) -> void: pass
	var plan := Workout.make("nav", [WorkoutStep.percent(120, 60.0), WorkoutStep.percent(60, 80.0)] as Array[WorkoutStep])
	assert_true(main.start_workout_on_emulator(plan), "предусловие: тренировка на эмуляторе")
	return screen


func _advance(screen: WorkoutScreen, sec: float) -> void:
	_now_usec += int(round(sec * 1_000_000.0))
	if screen.ticker() != null:
		screen.ticker().poll()


func test_req_uix_04_c2_esc_on_workout_asks_confirmation_and_keeps_session() -> void:
	var main := _main()
	var screen := _start_workout(main)
	_advance(screen, 10.0)
	_esc()
	assert_eq(_screen(main), "workout", "Esc не уводит с экрана тренировки")
	assert_eq(screen.session().get_state(), WorkoutSession.State.RUNNING, "сессия идёт")
	assert_true(screen.is_stop_confirmation_pending(), "запрошено подтверждение досрочного завершения")
	_advance(screen, 5.0)
	assert_eq(screen.session().executor.elapsed_sec(), 15, "таймер идёт, пока висит подтверждение")
	_esc()
	assert_false(screen.is_stop_confirmation_pending(), "повторный Esc — «Отмена»")
	assert_eq(screen.session().get_state(), WorkoutSession.State.RUNNING, "сессия не завершена")
	assert_eq(_screen(main), "workout")


func test_req_uix_04_c2_android_back_on_workout_then_confirm_stops() -> void:
	var main := _main()
	var screen := _start_workout(main)
	_advance(screen, 3.0)
	_android_back()
	assert_eq(screen.session().get_state(), WorkoutSession.State.RUNNING, "«назад» сам по себе не завершает")
	assert_true(screen.is_stop_confirmation_pending())
	_android_back()
	assert_false(screen.is_stop_confirmation_pending(), "второй «назад» закрывает подтверждение как «Отмена»")
	assert_eq(screen.session().get_state(), WorkoutSession.State.RUNNING)
	_android_back()
	screen.confirm_stop()
	assert_eq(screen.session().get_state(), WorkoutSession.State.FINISHED, "завершение — только после подтверждения")
	assert_true(screen.session().executor.stopped_early)


func test_req_uix_04_c2_back_on_paused_workout_does_not_end_it() -> void:
	var main := _main()
	var screen := _start_workout(main)
	_advance(screen, 4.0)
	screen.toggle_pause()
	_esc()
	assert_eq(screen.session().get_state(), WorkoutSession.State.PAUSED, "на паузе «назад» не завершает")
	assert_true(screen.is_stop_confirmation_pending())


func test_req_uix_04_c2_free_ride_stub_without_session_back_goes_home() -> void:
	var main := _main()
	assert_true(main.app_state.navigate(AppState.Screen.FREE_RIDE))
	assert_true(main.visible_screen_node() is FreeRideScreen)
	assert_false(main.app_state.can_go_back(), "экран сессии в стек не пишет и стеком не уходит")
	_esc()
	assert_eq(_screen(main), "home", "сессии нет — на главный")


# ===========================================================================
# REQ-UIX-02 крит. 3 — фишка статуса ведёт на экран устройств (переход и возврат)
# ===========================================================================

func test_req_uix_02_c3_devices_reachable_from_home_and_back_returns_home() -> void:
	var main := _main()
	_press(main.screen_node(AppState.Screen.HOME), "DevicesButton")
	assert_eq(_screen(main), "devices")
	assert_true(main.visible_screen_node() == main.screen_node(AppState.Screen.DEVICES))
	assert_eq(main.app_state.back_target(), AppState.Screen.HOME, "«назад» с устройств — на главный")
	_esc()
	assert_eq(_screen(main), "home")


# ===========================================================================
# REQ-FRD-02 крит. 3 — последняя трасса в профиле, первый запуск — flat
# ===========================================================================

func test_req_frd_02_c3_first_launch_preselects_flat() -> void:
	var main := _main()
	main.app_state.navigate(AppState.Screen.ROUTE_SELECT)
	assert_eq(main.route_select_screen().preselected_route_id(), "flat", "в профиле нет трассы → равнина")
	assert_true(RouteCatalog.ids().has("flat"), "flat есть в каталоге")


func test_req_frd_02_c3_last_route_persists_across_restart() -> void:
	var main := _main()
	var id: String = main.repo.get_active().id
	assert_eq(main.repo.set_last_route_id(id, "mountains"), [] as Array[String], "сохранено на диск")
	main.free()
	# Новый запуск: свежий репозиторий и оболочка читают профиль с диска.
	var reread := ProfileRepository.new(_dir + "profiles/")
	assert_eq(reread.get_by_id(id).effective_route_id(), "mountains", "трасса в профиле на диске")
	var again := _main()
	again.app_state.navigate(AppState.Screen.ROUTE_SELECT)
	assert_eq(again.route_select_screen().preselected_route_id(), "mountains", "предвыбрана при следующем открытии")
	# Смена трассы не трогает другие поля профиля.
	var p := reread.get_by_id(id)
	assert_eq(p.name, "Аня")


func test_req_frd_02_c3_route_is_per_profile() -> void:
	var main := _main(["Аня", "Боря"])
	var a: Profile = main.repo.list()[0]
	var b: Profile = main.repo.list()[1]
	main.repo.set_last_route_id(a.id, "seaside")
	main.app_state.select_profile(b.id)
	main.app_state.navigate(AppState.Screen.ROUTE_SELECT)
	assert_eq(main.route_select_screen().preselected_route_id(), "flat", "у второго профиля — своя (по умолчанию)")
	main.app_state.select_profile(a.id)
	main.app_state.navigate(AppState.Screen.ROUTE_SELECT)
	assert_eq(main.route_select_screen().preselected_route_id(), "seaside")


# ===========================================================================
# REQ-FRD-05 крит. 1 — крутизна SIM 0–100 % шагом 5, по умолчанию 50, между сессиями
# ===========================================================================

func test_req_frd_05_c1_default_50_and_persisted_between_sessions() -> void:
	var main := _main()
	var id: String = main.repo.get_active().id
	assert_eq(main.repo.get_active().sim_steepness_pct, 50, "по умолчанию 50 %")
	main.app_state.navigate(AppState.Screen.ROUTE_SELECT)
	assert_eq(main.route_select_screen().preselected_sim_steepness_pct(), 50)
	assert_eq(main.repo.set_sim_steepness_pct(id, 35), [] as Array[String])
	main.free()
	var again := _main()
	again.app_state.navigate(AppState.Screen.ROUTE_SELECT)
	assert_eq(again.route_select_screen().preselected_sim_steepness_pct(), 35, "сохранено между запусками")


func test_req_frd_05_c1_range_0_100_step_5() -> void:
	var repo := ProfileRepository.new(_dir + "profiles/")
	var p := repo.create("Шаг")
	var cases := {0: 0, 100: 100, 5: 5, 95: 95, 37: 35, 38: 40, -10: 0, 140: 100}
	for input: int in cases:
		repo.set_sim_steepness_pct(p.id, input)
		var stored: int = ProfileRepository.new(_dir + "profiles/").get_by_id(p.id).sim_steepness_pct
		assert_eq(stored, cases[input], "ввод %d → хранится %d" % [input, cases[input]])
		assert_true(stored % 5 == 0 and stored >= 0 and stored <= 100)
