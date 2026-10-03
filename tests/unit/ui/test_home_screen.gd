extends GutTest
## Главный экран (T-081): REQ-UIX-02 крит. 1–6, REQ-FRD-01 крит. 1 (вход с главного).
## Экран живёт в узле-хосте заданного размера (холст в lp): 1280×720 — regular, 867×400 — compact.

const SCENE: String = "res://src/ui/home/home.tscn"
const MAIN_SCENE: String = "res://src/app/main.tscn"
const PLAN_FIXTURE: String = "res://tests/fixtures/workouts_acceptance/acc_full.zwo"
const TODAY: String = "2026-10-03"

var _dir: String
var _repo: ProfileRepository
var _state: AppState
var _profile: Profile
var _bridge: StubBleBridge
var _remembered: RememberedDevices
var _cm: ConnectionManager
var _cache: PlanCache
var _library: WorkoutLibrary
var _rides: FileRideRepository


func before_each() -> void:
	TranslationServer.set_locale("en")
	_dir = "user://test_home_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_repo = ProfileRepository.new(_dir + "profiles/")
	_profile = _repo.create("Rider")
	_profile.ftp_w = 250
	_repo.save(_profile)
	_state = AppState.new(_repo)
	_state.start()
	_bridge = StubBleBridge.new()
	_remembered = RememberedDevices.new(_dir + "devices/")
	_cm = ConnectionManager.new(_bridge, _remembered, TrainerFactory.KIND_FAKE)
	_cache = PlanCache.new(_dir + "plans/")
	_library = WorkoutLibrary.new(_dir + "workouts/")
	_rides = FileRideRepository.new(_dir + "rides/")


func after_each() -> void:
	if _cm != null:
		_cm.dispose()
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


func _home(size: Vector2 = Vector2(1280, 720), dev_tools: bool = false) -> HomeScreen:
	var host := Control.new()
	host.size = size
	add_child_autofree(host)
	var home: HomeScreen = load(SCENE).instantiate()
	home.today = TODAY
	home.dev_tools_enabled = dev_tools
	home.setup(_repo, _state, _cm, _cache, _library, _rides)
	host.add_child(home)
	return home


func _settle() -> void:
	for i in 3:
		await get_tree().process_frame


func _import_fixture() -> Workout:
	var result := _library.import_file(_profile.id, ProjectSettings.globalize_path(PLAN_FIXTURE))
	assert_true(result.ok(), "фикстура импортирована")
	return result.workout


func _press(home: HomeScreen, unique: String) -> void:
	(home.get_node("%" + unique) as Button).pressed.emit()


static func _collect(node: Node, out: Array[Node]) -> void:
	out.append(node)
	for child in node.get_children():
		_collect(child, out)


## Видимые основные кнопки (вариация `PrimaryButton`).
static func _visible_primary(root: Node) -> Array[Button]:
	var all: Array[Node] = []
	_collect(root, all)
	var out: Array[Button] = []
	for n in all:
		if n is Button and (n as Button).is_visible_in_tree() and (n as Button).theme_type_variation == &"PrimaryButton":
			out.append(n)
	return out


## Видимые интерактивные элементы вне карточек сценариев.
static func _interactive_outside_cards(home: HomeScreen) -> Array[Control]:
	var all: Array[Node] = []
	_collect(home, all)
	var cards := home.scenario_cards()
	var out: Array[Control] = []
	for n in all:
		if not (n is Control) or not (n as Control).is_visible_in_tree():
			continue
		var c := n as Control
		if c.focus_mode == Control.FOCUS_NONE or cards.has(c):
			continue
		var inside := false
		for card in cards:
			if card.is_ancestor_of(c):
				inside = true
		if not inside:
			out.append(c)
	return out


# ===========================================================================
# REQ-UIX-02 крит. 1 — две карточки, площади, ровно две основные кнопки
# ===========================================================================

func test_req_uix_02_c1_two_scenario_cards_take_45_percent_and_twice_any_other_element() -> void:
	_import_fixture()
	var home := _home(Vector2(1280, 720), true)
	await _settle()
	var cards := home.scenario_cards()
	assert_eq(cards.size(), 2)
	for card in cards:
		assert_eq((card as Button).theme_type_variation, &"ScenarioCard")
		assert_gte(card.size.y, 720.0 * 0.45, "карточки не ниже 45 %% высоты окна (рядом — вместе по высоте)")
	var biggest_other: float = 0.0
	for c in _interactive_outside_cards(home):
		biggest_other = maxf(biggest_other, c.size.x * c.size.y)
	assert_gt(biggest_other, 0.0, "интерактивные элементы вне карточек найдены")
	for card in cards:
		assert_gte(card.size.x * card.size.y, 2.0 * biggest_other, "%s ≥ 2 × любого другого элемента" % card.name)


func test_req_uix_02_c1_exactly_two_primary_buttons_with_plan_and_without() -> void:
	var empty := _home()
	await _settle()
	assert_true(empty.is_plan_empty())
	assert_eq(_visible_primary(empty).size(), 2, "пустой план: «Из библиотеки» и «Поехать»")
	_import_fixture()
	empty.refresh()
	await _settle()
	var primary := _visible_primary(empty)
	assert_eq(primary.size(), 2)
	assert_has(primary, empty.get_node("%StartWorkoutButton"))
	assert_has(primary, empty.get_node("%RideButton"))


func test_req_uix_02_c1_start_emits_card_workout_and_secondary_opens_plan() -> void:
	var workout := _import_fixture()
	var home := _home()
	await _settle()
	watch_signals(home)
	_press(home, "StartWorkoutButton")
	assert_signal_emitted(home, "workout_start_requested")
	var params: Array = get_signal_parameters(home, "workout_start_requested")
	assert_eq((params[0] as Workout).name, workout.name, "«Начать» — тренировка карточки")
	_press(home, "WorkoutButton")
	assert_eq(_state.current_screen, AppState.Screen.PLAN, "«Другая тренировка» → выбор тренировки")


func test_req_uix_02_c1_frd_01_c1_ride_emits_card_route_and_change_route_opens_route_select() -> void:
	_profile.last_route_id = RouteCatalog.MOUNTAINS
	_repo.save(_profile)
	var home := _home()
	await _settle()
	watch_signals(home)
	_press(home, "RideButton")
	assert_signal_emitted_with_parameters(home, "free_ride_requested", [RouteCatalog.MOUNTAINS])
	_press(home, "RouteButton")
	assert_eq(_state.current_screen, AppState.Screen.ROUTE_SELECT, "«Сменить трассу» → выбор трассы")


# ===========================================================================
# REQ-UIX-02 крит. 2 — содержимое карточек
# ===========================================================================

func test_req_uix_02_c2_plan_card_from_library_shows_name_source_and_three_numbers() -> void:
	var workout := _import_fixture()
	var home := _home()
	await _settle()
	assert_eq(home.plan_title_text(), workout.name)
	assert_eq(home.plan_source_text(), "Library")
	var ftp := _profile.ftp_w
	var values := home.plan_stat_values()
	assert_eq(values[0], IntervalsPlanService.format_duration(workout.total_duration_sec()))
	assert_eq(values[1], str(HomeScreen.max_target_watts(workout, ftp)))
	assert_eq(values[2], str(workout.steps.size()))
	var preview := home.get_node("%PlanPreview") as PlanPreview
	assert_not_null(preview.plan_model(), "превью плана по модели HUD")


func test_req_uix_02_c2_today_from_intervals_cache_wins_over_library() -> void:
	_import_fixture()
	var today := Workout.make("Today Sweet Spot", [WorkoutStep.percent(600, 90.0)] as Array[WorkoutStep])
	assert_true(_cache.save(_profile.id, TODAY, [{"event_id": 1, "name": today.name, "duration_sec": 600, "workout": today}]))
	var home := _home()
	await _settle()
	assert_eq(home.plan_title_text(), "Today Sweet Spot")
	assert_eq(home.card_workout_source(), HomeScreen.SOURCE_INTERVALS)
	assert_eq(home.plan_source_text(), "Intervals.icu · today")


func test_req_uix_02_c2_last_chosen_workout_shown_when_no_plan_today() -> void:
	_import_fixture()
	var chosen := Workout.make("Chosen", [WorkoutStep.percent(300, 60.0)] as Array[WorkoutStep])
	var home := _home()
	await _settle()
	home.remember_workout(chosen, HomeScreen.SOURCE_LIBRARY)
	assert_eq(home.plan_title_text(), "Chosen", "последняя выбранная")


func test_req_uix_02_c2_no_plan_empty_state_without_start() -> void:
	var home := _home()
	await _settle()
	assert_true(home.is_plan_empty())
	assert_true((home.get_node("%PlanEmpty") as Control).visible)
	assert_false((home.get_node("%StartWorkoutButton") as Control).visible, "основной «Начать» нет")
	var from_library := home.get_node("%WorkoutButton") as Button
	assert_true(from_library.is_visible_in_tree())
	assert_eq(from_library.tr(from_library.text), "From library")
	var import_button := home.get_node("%ImportButton") as Button
	assert_true(import_button.is_visible_in_tree())
	assert_eq(import_button.tr(import_button.text), "Import file")
	watch_signals(home)
	import_button.pressed.emit()
	assert_signal_emitted(home, "import_requested")
	from_library.pressed.emit()
	assert_eq(_state.current_screen, AppState.Screen.PLAN)


func test_req_uix_02_c2_route_card_first_launch_flat_and_numbers_from_route_profile() -> void:
	var home := _home()
	await _settle()
	assert_eq(home.card_route_id(), RouteCatalog.FLAT, "первый запуск — равнина")
	assert_eq(home.route_title_text(), "Wheat Fields")
	assert_eq(home.route_kind_text(), "flatlands")
	var route := RouteCatalog.get_route(RouteCatalog.FLAT)
	assert_eq(home.route_stat_values(), [
		RoutePreviewModel.length_value(route.profile.length_m()),
		RoutePreviewModel.ascent_value(route.profile.ascent_m()),
		RoutePreviewModel.grade_value(route.profile.max_grade_pct()),
	] as Array[String])
	assert_not_null((home.get_node("%RoutePreview") as RoutePreview).model)


func test_req_uix_02_c2_route_card_follows_profile_last_route() -> void:
	_profile.last_route_id = RouteCatalog.SEASIDE
	_repo.save(_profile)
	var home := _home()
	await _settle()
	assert_eq(home.card_route_id(), RouteCatalog.SEASIDE)
	assert_eq(home.route_title_text(), "Seaside")


# ===========================================================================
# REQ-UIX-02 крит. 3 — фишки устройств
# ===========================================================================

func test_req_uix_02_c3_trainer_chip_reflects_fake_trainer_state_within_1s() -> void:
	var home := _home()
	await _settle()
	assert_eq(home.device_chip_texts(), ["Trainer · not connected"] as Array[String], "станок есть всегда")
	assert_eq(home.device_chip_color(0), UiTokens.TEXT_DISABLED)
	_cm.trainer.set("connect_delay_sec", 0.5)
	_cm.connect_trainer("fake-neo")
	assert_eq(home.device_chip_texts()[0], "Trainer · connecting", "смена состояния — сразу по сигналу")
	assert_eq(home.device_chip_color(0), UiTokens.WARN)
	_cm.tick(1.0)
	assert_eq(_cm.state_of("fake-neo"), TrainerDevice.ConnectionState.CONNECTED, "предусловие: эмулятор подключился")
	assert_string_starts_with(home.device_chip_texts()[0], "Trainer · ", "подключён — имя станка")
	assert_ne(home.device_chip_texts()[0], "Trainer · connecting")
	assert_eq(home.device_chip_color(0), UiTokens.ACCENT)
	assert_eq(home.tile_caption(home.get_node("%DevicesButton")), "trainer connected")


func test_req_uix_02_c3_remembered_sensor_chip_with_battery_and_not_found() -> void:
	_remembered.remember(_profile.id, RememberedDevices.make_device("hr-1", "HRM Pro", RememberedDevices.KIND_HR))
	var home := _home()
	await _settle()
	assert_eq(home.device_chips().size(), 2, "станок + запомненный датчик")
	assert_eq(home.device_chip_texts()[1], "Heart rate · not connected")
	_cm.auto_connect_timed_out.emit(["hr-1"] as Array[String])
	assert_eq(home.device_chip_texts()[1], "Heart rate · not found")
	_cm.connect_sensor("hr-1", RememberedDevices.KIND_HR)
	_cm.sensor(RememberedDevices.KIND_HR).battery_level.emit(80)
	assert_string_ends_with(home.device_chip_texts()[1], " · 80 %", "заряд DEV-07.2")


func test_req_uix_02_c3_chip_press_opens_devices() -> void:
	var home := _home()
	await _settle()
	home.device_chips()[0].pressed.emit()
	assert_eq(_state.current_screen, AppState.Screen.DEVICES)


# ===========================================================================
# REQ-UIX-02 крит. 4 — история, устройства, настройки одним нажатием
# ===========================================================================

func test_req_uix_02_c4_tiles_navigate_in_one_press() -> void:
	var home := _home()
	await _settle()
	for item in [["HistoryButton", AppState.Screen.HISTORY], ["DevicesButton", AppState.Screen.DEVICES],
			["SettingsButton", AppState.Screen.SETTINGS]]:
		_state.navigate(AppState.Screen.HOME)
		var tile := home.get_node("%" + item[0]) as Button
		assert_true(tile.is_visible_in_tree(), "%s видна" % item[0])
		tile.pressed.emit()
		assert_eq(_state.current_screen, item[1], item[0])
	assert_eq(home.tile_caption(home.get_node("%SettingsButton")), "FTP 250 · 75 kg")
	assert_eq(home.tile_caption(home.get_node("%HistoryButton")), "No rides yet")


func test_req_uix_02_c4_compact_icon_buttons_in_bar_and_no_overflow() -> void:
	var home := _home(Vector2(867, 400))
	await _settle()
	assert_true(home.is_compact())
	assert_false((home.get_node("%Tiles") as Control).is_visible_in_tree(), "плитки — в панели")
	for item in [["HistoryIconButton", AppState.Screen.HISTORY], ["DevicesIconButton", AppState.Screen.DEVICES],
			["SettingsIconButton", AppState.Screen.SETTINGS]]:
		_state.navigate(AppState.Screen.HOME)
		var button := home.get_node("%" + item[0]) as Button
		assert_true(button.is_visible_in_tree())
		button.pressed.emit()
		assert_eq(_state.current_screen, item[1], item[0])
	var column := home.get_node("%Column") as Control
	assert_lte(column.get_global_rect().end.y, 400.0 + 0.5, "без прокрутки: колонка в окне")
	assert_gte(column.get_global_rect().position.y, -0.5)
	var cards := home.scenario_cards()
	assert_almost_eq(cards[0].get_global_rect().position.y, cards[1].get_global_rect().position.y, 0.5, "карточки в ряд")
	assert_eq(_visible_primary(home).size(), 2)


# ===========================================================================
# REQ-UIX-02 крит. 5 — фишка профиля и смена профиля
# ===========================================================================

func test_req_uix_02_c5_profile_chip_shows_name_and_switch_only_with_two_profiles() -> void:
	var home := _home()
	await _settle()
	var chip := home.get_node("%SwitchProfileButton") as Button
	assert_string_starts_with(chip.text, "Rider")
	assert_eq(home.active_profile_text(), "Profile: Rider")
	assert_eq(chip.focus_mode, Control.FOCUS_NONE, "один профиль — сменить не на кого")
	_repo.create("Second")
	home.refresh()
	assert_ne(chip.focus_mode, Control.FOCUS_NONE)
	chip.pressed.emit()
	assert_true(home.profile_menu().visible, "меню «Сменить профиль»")
	home.profile_menu().id_pressed.emit(HomeScreen.MENU_SWITCH_PROFILE)
	assert_eq(_state.current_screen, AppState.Screen.PROFILE_SELECT)
	home.profile_menu().hide()


# ===========================================================================
# REQ-UIX-02 крит. 6 — кнопки разработки только в отладке
# ===========================================================================

func test_req_uix_02_c6_dev_buttons_hidden_outside_debug_and_shown_in_debug() -> void:
	var release := _home(Vector2(1280, 720), false)
	await _settle()
	for name in ["EmulatorWorkoutButton", "DevButton", "DevMenuButton"]:
		assert_false((release.get_node("%" + name) as Control).is_visible_in_tree(), "%s скрыта вне отладки" % name)
	release.dev_tools_enabled = true
	await _settle()
	assert_true((release.get_node("%EmulatorWorkoutButton") as Control).is_visible_in_tree())
	assert_true((release.get_node("%DevButton") as Control).is_visible_in_tree())
	var compact := _home(Vector2(867, 400), true)
	await _settle()
	assert_true((compact.get_node("%DevMenuButton") as Control).is_visible_in_tree(), "compact — за «⋯»")
	watch_signals(compact)
	compact.dev_menu().id_pressed.emit(HomeScreen.MENU_DEV_EMULATOR)
	assert_signal_emitted(compact, "emulator_workout_requested")


func test_req_uix_02_c6_main_enables_dev_tools_only_in_debug_build() -> void:
	assert_true(AppMain.is_debug_build(), "тесты идут в отладочной сборке")
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir + "app/"
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.env_reader = Callable()
	add_child_autofree(main)
	var home := main.home_screen()
	assert_eq(home.dev_tools_enabled, AppMain.is_debug_build())


# ===========================================================================
# Проводка оболочки: «Начать» без станка — выбор «эмулятор / устройства» на экране плана
# ===========================================================================

func test_main_home_start_without_trainer_asks_on_plan_screen_and_import_opens_plan() -> void:
	var app_repo := ProfileRepository.new(_dir + "app/profiles/")
	app_repo.create("Solo")
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir + "app/"
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.env_reader = Callable()
	add_child_autofree(main)
	var workout := Workout.make("Short", [WorkoutStep.percent(60, 50.0)] as Array[WorkoutStep])
	main.home_screen().workout_start_requested.emit(workout)
	assert_eq(main.app_state.current_screen, AppState.Screen.PLAN)
	assert_true(main.plan_screen().is_trainer_choice_pending())
	assert_eq(main.pending_workout(), workout)
	(main.plan_screen().get_node("%TrainerDialog") as Window).hide()
	main.app_state.navigate(AppState.Screen.HOME)
	main.home_screen().import_requested.emit()
	assert_eq(main.app_state.current_screen, AppState.Screen.PLAN)
	(main.plan_screen().get_node("%ImportDialog") as Window).hide()
