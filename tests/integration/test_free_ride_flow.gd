extends GutTest
## Сквозной путь свободной езды в оболочке `main.tscn` (T-084): REQ-FRD-01 крит. 1, 4 — запуск с
## главного и с выбора трассы, без станка сессии нет (в отладке — эмулятор); REQ-FRD-02 крит. 2 —
## трасса сессии и сцены совпадает с выбранной; REQ-FRD-04 крит. 6 / REQ-FRD-06 крит. 7 — станок
## без SIM: фиксированное сопротивление и сообщение на HUD ≥ 5 с; REQ-FRD-05 крит. 4, 6 — режим и
## крутизна с панели инструментов и на HUD; REQ-FRD-06 крит. 5 — раскладка HUD; REQ-FRD-07
## крит. 2, 6, 7 — завершение только с подтверждением, заезд в истории и в очереди Strava с
## названием «Свободная езда — <трасса>»; REQ-UIX-04 крит. 1 (Android «назад» на главном не
## перехватывается), крит. 2 (на экране езды «назад» — подтверждение).

const MAIN_SCENE: String = "res://src/app/main.tscn"

var _dir: String
var _previous_locale: String
var _now_usec: int = 0


func before_each() -> void:
	_dir = "user://test_free_ride_flow_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_now_usec = 1_000_000


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
	var screen := main.free_ride_screen()
	screen.clock_usec = _clock
	screen.keep_awake_setter = _ignore
	return main


func _clock() -> int:
	return _now_usec


func _ignore(_on: bool) -> void:
	pass


## Продвинуть время сессии на `seconds` секунд шагами по 0.5 с (как кадры).
func _ride(main: AppMain, seconds: float) -> void:
	var ticker := main.free_ride_screen().ticker()
	var steps := int(round(seconds / 0.5))
	for i in steps:
		_now_usec += 500_000
		ticker.poll()


static func _fake(simulation: bool = true) -> FakeTrainer:
	var trainer := FakeTrainer.new()
	trainer.connect_delay_sec = 0.0
	trainer.set_simulation_supported(simulation)
	trainer.set_rider_power(200)
	trainer.connect_device("fake-neo")
	return trainer


func _connect_app_trainer(main: AppMain) -> void:
	main.connections.trainer.set("connect_delay_sec", 0.0)
	main.connections.connect_trainer("fake-neo")


# ===========================================================================
# REQ-FRD-01 крит. 1, 4; REQ-FRD-02 крит. 2 — запуск и трасса
# ===========================================================================

func test_req_frd_01_c1_route_select_start_with_trainer_runs_chosen_route() -> void:
	var main := _main()
	_connect_app_trainer(main)
	assert_true(main.is_trainer_ready(), "предусловие: станок подключён")
	main.app_state.navigate(AppState.Screen.ROUTE_SELECT)
	main.route_select_screen().start_requested.emit(RouteCatalog.HILLS, 35)
	assert_eq(main.app_state.current_screen, AppState.Screen.FREE_RIDE, "«Поехать» → экран свободной езды")
	var screen := main.free_ride_screen()
	var session := screen.session()
	assert_not_null(session, "сессия создана")
	assert_eq(session.get_state(), WorkoutSession.State.RUNNING)
	assert_eq(session.route.id, RouteCatalog.HILLS, "FRD-02 крит. 2: трасса сессии — выбранная")
	assert_eq(session.steepness_pct(), 35, "крутизна с экрана выбора")
	assert_eq(screen.ride_scene().route_id, RouteCatalog.HILLS, "сцена построена по той же трассе")
	assert_eq(screen.ride_scene().environment_set, RouteWorld.environment(RouteCatalog.HILLS), "окружение трассы")
	assert_eq(session.trainer, main.connections.hub, "станок — хаб менеджера подключений")
	assert_false(main.connections.ticks_devices, "устройства тикает сессия")
	assert_false(main.app_state.can_go_back(), "экран сессии в стек не пишет")


func test_req_frd_01_c1_home_ride_uses_card_route_and_profile_steepness() -> void:
	var main := _main()
	_connect_app_trainer(main)
	var active := main.repo.get_active()
	assert_eq(main.repo.set_sim_steepness_pct(active.id, 70), [])
	main.home_screen().free_ride_requested.emit(RouteCatalog.MOUNTAINS)
	var session := main.free_ride_screen().session()
	assert_not_null(session)
	assert_eq(session.route.id, RouteCatalog.MOUNTAINS)
	assert_eq(session.steepness_pct(), 70, "крутизна из профиля")


func test_req_frd_01_c4_without_trainer_no_session_and_dialog_with_devices_link() -> void:
	var main := _main()
	assert_false(main.is_trainer_ready(), "предусловие: станка нет")
	assert_false(main.start_free_ride(RouteCatalog.FLAT, 50), "без станка «Поехать» сессию не создаёт")
	assert_null(main.free_ride_screen().session())
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME, "экран не сменился")
	var dialog := main.free_ride_trainer_dialog()
	assert_true(dialog.visible, "пояснение показано")
	assert_eq(dialog.ok_button_text, "ui.free_ride.no_trainer.devices")
	assert_eq(main.pending_free_ride(), {"route_id": RouteCatalog.FLAT, "steepness_pct": 50})
	dialog.get_ok_button().pressed.emit()
	assert_eq(main.app_state.current_screen, AppState.Screen.DEVICES, "ссылка ведёт на «Устройства» (DEV-07)")
	assert_true(main.pending_free_ride().is_empty())


func test_req_frd_01_c4_debug_build_offers_emulator_and_session_starts() -> void:
	var main := _main()
	assert_true(AppMain.is_debug_build(), "тесты идут в отладочной сборке")
	main.start_free_ride(RouteCatalog.FLAT, 50)
	assert_true(main.choose_free_ride_emulator(), "в отладке — эмулятор (DEV-09)")
	assert_false(main.free_ride_trainer_dialog().visible)
	var session := main.free_ride_screen().session()
	assert_not_null(session)
	assert_true(session.trainer is FakeTrainer, "станок сессии — эмулятор")
	assert_eq(main.app_state.current_screen, AppState.Screen.FREE_RIDE)


# ===========================================================================
# REQ-FRD-04 крит. 6, REQ-FRD-06 крит. 7 — станок без SIM
# ===========================================================================

func test_req_frd_06_c7_no_sim_fixed_resistance_and_message_at_least_5s() -> void:
	var main := _main()
	assert_true(main.launch_free_ride(_fake(false), RouteCatalog.HILLS, 50))
	var screen := main.free_ride_screen()
	var session := screen.session()
	assert_eq(session.mode(), SimController.Mode.FIXED, "FRD-04 крит. 6: переход на фиксированное сопротивление")
	assert_eq(session.get_state(), WorkoutSession.State.RUNNING, "сессия не прервана")
	assert_true(screen.is_notice_visible(), "сообщение на HUD")
	assert_eq(screen.notice_text(), "Trainer does not support SIM — fixed resistance")
	assert_string_starts_with(screen.metric_panel().grade_mode_text(), "RES.", "в карточке уклона — «СОПР.»")
	assert_eq(screen.mode_chip_text(), "RES.", "фишка режима")
	_ride(main, 5.0)
	assert_true(screen.is_notice_visible(), "сообщение видно не меньше 5 с")
	_ride(main, FreeRideScreen.NOTICE_SEC)
	assert_false(screen.is_notice_visible(), "потом сообщение убирается")
	assert_string_starts_with(screen.metric_panel().grade_mode_text(), "RES.", "режим «СОПР.» остаётся")


# ===========================================================================
# REQ-FRD-05 крит. 4, 6 — SIM ↔ сопротивление и крутизна с панели инструментов
# ===========================================================================

func test_req_frd_05_c4_c6_toolbar_toggles_mode_and_steepness_shown_on_hud() -> void:
	var main := _main()
	main.launch_free_ride(_fake(), RouteCatalog.FLAT, 50)
	var screen := main.free_ride_screen()
	var session := screen.session()
	assert_eq(screen.metric_panel().grade_mode_text(), "SIM 50 %")
	screen.toolbar().steepness_step_requested.emit(10)
	assert_eq(session.steepness_pct(), 60, "крутизна +10 %")
	assert_eq(screen.metric_panel().grade_mode_text(), "SIM 60 %", "крутизна видна на HUD")
	assert_eq(main.repo.get_active().sim_steepness_pct, 60, "крутизна сохранена в профиле")
	screen.toolbar().sim_toggle_requested.emit()
	assert_eq(session.mode(), SimController.Mode.FIXED, "одно действие — фиксированное сопротивление")
	assert_eq(screen.mode_chip_text(), "RES.")
	screen.toolbar().resistance_step_requested.emit(5)
	assert_eq(screen.metric_panel().grade_mode_text(), "RES. %d %%" % session.resistance_level())
	var types: Array[String] = []
	for e in session.events:
		types.append(str(e["type"]))
	assert_has(types, SimController.EVENT_MODE, "переключение — событие заезда")
	assert_has(types, SimController.EVENT_STEEPNESS)


# ===========================================================================
# REQ-FRD-07 крит. 2, 6, 7; REQ-UIX-04 крит. 2 — завершение, история, Strava
# ===========================================================================

func test_req_frd_07_c2_back_asks_confirmation_and_session_keeps_running() -> void:
	var main := _main()
	main.launch_free_ride(_fake(), RouteCatalog.FLAT, 50)
	var screen := main.free_ride_screen()
	_ride(main, 3.0)
	assert_true(main.handle_back(), "«назад» перехвачен экраном")
	assert_true(screen.is_finish_confirmation_pending(), "подтверждение показано")
	assert_eq(screen.session().get_state(), WorkoutSession.State.RUNNING, "без подтверждения сессия идёт")
	assert_eq(main.app_state.current_screen, AppState.Screen.FREE_RIDE)
	assert_true(main.handle_back(), "второй «назад» — отмена подтверждения")
	assert_false(screen.is_finish_confirmation_pending())
	assert_eq(screen.session().get_state(), WorkoutSession.State.RUNNING)


func test_req_frd_07_c2_c6_c7_finish_saves_ride_history_and_strava_queue() -> void:
	var main := _main()
	var profile := main.repo.get_active()
	main.secure_store.set_secret(SecureStore.key_for(profile.id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_REFRESH_TOKEN), "refresh")
	assert_true(main.strava.is_authorized(), "предусловие: Strava привязана")
	main.launch_free_ride(_fake(), RouteCatalog.MOUNTAINS, 50)
	var screen := main.free_ride_screen()
	_ride(main, 30.0)
	screen.toolbar().finish_requested.emit()
	assert_true(screen.is_finish_confirmation_pending())
	screen.pause_overlay().confirm_button().pressed.emit()
	var session := screen.session()
	assert_eq(session.get_state(), WorkoutSession.State.FINISHED, "после подтверждения — завершена")
	assert_true(screen.is_summary_visible(), "итог заезда")
	var ride_id := screen.saved_ride_id()
	assert_false(ride_id.is_empty(), "заезд сохранён (RideRepository.save)")
	var ride := main.ride_repository.get_ride(ride_id)
	assert_not_null(ride)
	assert_true(ride.is_free_ride(), "тип — свободная езда")
	assert_eq(ride.route_id(), RouteCatalog.MOUNTAINS)
	assert_false(ride.is_in_progress())
	assert_eq(screen.summary_value_text("time"), "00:30")
	assert_true(main.strava.queue.has(ride_id), "FRD-07 крит. 7: заезд в очереди Strava")
	assert_eq(str(main.strava.queue.get_item(ride_id)["name"]), "Free ride — " + tr("track.mountains.name"))
	(screen.get_node("%HistoryButton") as Button).pressed.emit()
	assert_eq(main.app_state.current_screen, AppState.Screen.HISTORY, "«Открыть в истории»")
	var history := main.history_screen()
	assert_true(history.summaries().any(func(s: RideSummary) -> bool: return s.ride_id == ride_id), "FRD-07 крит. 6: заезд в истории")
	assert_true(history.is_detail_visible(), "открыта карточка заезда")


# ===========================================================================
# REQ-FRD-06 крит. 5 — раскладка HUD свободной езды
# ===========================================================================

func test_req_frd_06_c5_hud_layout_relief_left_chart_bottom_center_free() -> void:
	var main := _main()
	main.launch_free_ride(_fake(), RouteCatalog.MOUNTAINS, 50)
	var screen := main.free_ride_screen()
	_ride(main, 10.0)
	await wait_process_frames(2)
	var layout := screen.hud_layout()
	var size := screen.size
	var relief := screen.relief_panel()
	assert_true(screen.is_hud_visible())
	assert_eq(relief.get_global_rect().position, screen.list_slot().get_global_rect().position, "рельеф в левом слоте")
	assert_almost_eq(relief.panel_width, layout.list_slot.size.x, 0.01, "ширина рельефа — w_l")
	assert_almost_eq(relief.panel_height, ReliefPanel.preferred_height(size.y, layout.list_slot.size.y), 0.01, "высота 0.40·H")
	assert_lte(relief.get_global_rect().end.x, 0.25 * size.x + 0.5, "рельеф в левых 25 %")
	assert_eq(screen.chart().get_global_rect(), layout.chart_gradient.merge(layout.chart), "график внизу во всю ширину")
	assert_eq(screen.metric_panel().get_global_rect(), layout.panel)
	var center := HudLayout.center_zone(size)
	for node: Control in [screen.metric_panel(), relief, screen.chart()]:
		var r := node.get_global_rect()
		if node == screen.chart():
			r = layout.chart
		assert_false(r.intersects(center), "%s не заходит в центральную зону" % node.name)
	assert_eq(screen.metric_panel().mode(), HudMetricPanel.Mode.FREE_RIDE)
	assert_ne(screen.metric_panel().grade_text(), "—", "уклон показан")


# ===========================================================================
# Плавное движение гонщика между сэмплами
# ===========================================================================

func test_rider_moves_smoothly_between_samples_and_follows_session() -> void:
	var main := _main()
	main.launch_free_ride(_fake(), RouteCatalog.FLAT, 50)
	var screen := main.free_ride_screen()
	_ride(main, 20.0)
	var scene := screen.ride_scene()
	var positions: Array[float] = []
	for i in 8:
		_now_usec += 125_000
		screen.ticker().poll()
		screen._process(0.125)
		positions.append(scene.distance_m)
	for i in range(1, positions.size()):
		assert_gt(positions[i], positions[i - 1], "гонщик едет вперёд каждый кадр, а не раз в секунду")
		assert_lt(positions[i] - positions[i - 1], 2.0, "без рывков (≤ 2 м за 1/8 с)")
	var session := screen.session()
	assert_almost_eq(scene.distance_m, fposmod(session.position.s_m(), scene.track.length_m()), 3.0,
			"сцена — в позиции сессии")


# ===========================================================================
# REQ-UIX-04 крит. 1 — Android «назад» на главном приложение не перехватывает
# ===========================================================================

func test_req_uix_04_c1_android_back_on_home_left_to_engine_elsewhere_handled() -> void:
	var main := _main()
	await wait_process_frames(1)
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME)
	assert_true(get_tree().quit_on_go_back, "на главном «назад» — штатное закрытие движком")
	assert_false(main.handle_back(), "Esc на главном ничего не делает")
	main.app_state.navigate(AppState.Screen.PLAN)
	assert_false(get_tree().quit_on_go_back, "на остальных экранах «назад» обрабатывает оболочка")
	main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME, "Android «назад»: план → главный")
	assert_true(get_tree().quit_on_go_back)
	main.start_free_ride(RouteCatalog.FLAT, 50)
	await wait_process_frames(1)
	assert_false(get_tree().quit_on_go_back, "открытый диалог на главном закрывается «назад», а не приложение")
	main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_false(main.free_ride_trainer_dialog().visible, "«назад» закрыл диалог")


func test_req_uix_04_c1_hidden_free_ride_screen_does_not_swallow_esc() -> void:
	var main := _main()
	main.launch_free_ride(_fake(), RouteCatalog.FLAT, 50)
	var screen := main.free_ride_screen()
	screen.toolbar().finish_requested.emit()
	screen.confirm_finish()
	screen.go_home()
	main.app_state.navigate(AppState.Screen.SETTINGS)
	assert_false(screen.toolbar().hotkeys_enabled, "без сессии горячие клавиши выключены")
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	get_tree().root.push_input(ev)
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME, "Esc в настройках — назад на главный")


func test_req_uix_04_c2_esc_on_running_ride_pauses_not_finishes() -> void:
	var main := _main()
	main.launch_free_ride(_fake(), RouteCatalog.FLAT, 50)
	var screen := main.free_ride_screen()
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	get_tree().root.push_input(ev)
	assert_eq(screen.session().get_state(), WorkoutSession.State.PAUSED, "Esc — пауза (hud.md п. 10.2)")
	assert_eq(screen.pause_overlay().view(), PauseOverlay.View.PAUSE, "карточка паузы")
	assert_false(screen.pause_overlay().skip_button().visible, "без «Пропустить шаг»")
	assert_eq(main.app_state.current_screen, AppState.Screen.FREE_RIDE)
