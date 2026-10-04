extends GutTest
## Приёмка T-085 (история и карточка заезда) и T-086 (настройки, устройства, выбор профиля)
## — tester, независимо от `tests/unit/ui/test_history_screens_r2.gd` и
## `test_settings_devices_r2.gd`. Всё — через `main.tscn` (путь пользователя): навигация,
## данные в каталоге приложения, `FakeTrainer` и `StubBleBridge`.
## REQ-UIX-04 крит. 1 (AppBar с H1 и «назад», Esc), крит. 3 (разделы настроек по порядку,
## открытие в начале; строки истории — вариация строки, колонки фиксированной ширины, метка
## «ПЛАН»/«SIM»), крит. 4 (пустые состояния с иконкой, текстом и действием), крит. 5 (три
## слота устройств, баннер «Bluetooth недоступен» с действием); REQ-FRD-07 крит. 6 (свободная
## езда в истории наравне с тренировками, без цели).

const MAIN_SCENE: String = "res://src/app/main.tscn"
const FREE_SPEED_MS: float = 8.0

var _dir: String
var _prev_locale: String


func before_each() -> void:
	_dir = "user://test_menu_r2_acc_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_prev_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("ru")


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


func _main() -> AppMain:
	var repo := ProfileRepository.new(_dir + "profiles/")
	if repo.count() == 0:
		repo.create("Аня")
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	add_child_autofree(main)
	# Приложение ставит язык из настроек (по умолчанию — системный); проверяем русский интерфейс.
	TranslationServer.set_locale("ru")
	return main


## Открыть экран и перечитать его (тексты — на текущем языке).
func _open(main: AppMain, screen: int) -> Control:
	assert_true(main.app_state.navigate(screen), "%s открыт" % AppState.screen_name(screen))
	var node := main.screen_node(screen)
	if node.has_method("refresh"):
		node.call("refresh")
	return node


## Доступный Bluetooth у заглушки моста (в тестах нативного моста нет).
func _set_ble(main: AppMain, available: bool) -> void:
	var stub := main.bridge as StubBleBridge
	if stub == null:
		pending("мост не заглушка — доступность Bluetooth не подменить")
		return
	stub.set_available(available)


func _esc() -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.physical_keycode = KEY_ESCAPE
		ev.pressed = pressed
		get_tree().root.push_input(ev)


func _profile(main: AppMain) -> Profile:
	return main.repo.get_by_id(main.repo.active_profile_id)


func _plan_ride(main: AppMain, started: int, n: int) -> Ride:
	var p := _profile(main)
	var r := Ride.new()
	r.id = Ride.generate_id(started)
	r.profile_id = p.id
	r.started_at_unix = started
	r.name = "Порог"
	r.workout = WorkoutSerializer.to_dict(Workout.make("Порог", [WorkoutStep.watts(n, 200.0)] as Array[WorkoutStep], "zwo"))
	r.metadata = {"workout_name": "Порог", "workout_source": "zwo", "started_at_unix": started, "ftp_w": p.ftp_w,
		"weight_kg": p.weight_kg, "max_hr": 185, "intensity": 1.0, "stopped_early": false,
		"speed_source": SampleStream.SPEED_SOURCE_TRAINER, "elapsed_sec": n, "paused_total_sec": 0.0,
		"in_progress": false, "recovered": false}
	r.samples.speed_source = SampleStream.SPEED_SOURCE_TRAINER
	for i in n:
		r.samples.append(i, TrainerSample.full(float(i), 200, 88, 32.0), 140, 200, 0, true)
	r.events = [{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0}]
	r.compute_summary()
	assert_ne(main.ride_repository.save(r), "", "предусловие: заезд по плану сохранён")
	return r


func _free_ride(main: AppMain, started: int, n: int) -> Ride:
	var p := _profile(main)
	var r := Ride.new()
	r.id = Ride.generate_id(started)
	r.profile_id = p.id
	r.started_at_unix = started
	r.metadata = Ride.free_ride_metadata("hills", 50.0)
	r.metadata["ftp_w"] = p.ftp_w
	r.metadata["max_hr"] = 185
	r.metadata["weight_kg"] = 70.0
	r.metadata["in_progress"] = false
	r.metadata["recovered"] = false
	r.samples.speed_source = SampleStream.SPEED_SOURCE_MODEL
	var profile := RouteCatalog.get_route("hills").profile
	for i in n:
		var d: float = float(i + 1) * FREE_SPEED_MS
		var s: float = fposmod(d, profile.length_m())
		r.samples.append(i, TrainerSample.full(float(i), 220, 88, 0.0), 130, 0, -1, false, FREE_SPEED_MS * 3.6, {},
			{"distance_m": d, "altitude_m": profile.height_at(s), "grade_pct": profile.grade_at(s)})
	r.events = [{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0}]
	r.compute_summary()
	assert_ne(main.ride_repository.save(r), "", "предусловие: свободная езда сохранена")
	return r


## Метки режима строки (вариация Overline, показываются заглавными).
static func _mode_labels(row: Node) -> Array[String]:
	var out: Array[String] = []
	for n in row.find_children("*", "Label", true, false):
		var l := n as Label
		if l.is_visible_in_tree() and l.theme_type_variation == &"OverlineLabel":
			out.append(l.text.to_upper() if l.uppercase else l.text)
	return out


static func _labels(root: Node) -> Array[String]:
	var out: Array[String] = []
	for n in root.find_children("*", "Label", true, false):
		var l := n as Label
		if l.is_visible_in_tree():
			out.append(l.text)
	return out


# ===========================================================================
# REQ-UIX-04 крит. 1 — AppBar с заголовком H1 и «назад» → откуда пришли (главный); Esc так же
# ===========================================================================

func test_req_uix_04_c1_history_settings_devices_app_bar_h1_and_back_to_home() -> void:
	var main := _main()
	var titles := {AppState.Screen.HISTORY: "История", AppState.Screen.SETTINGS: "Настройки", AppState.Screen.DEVICES: "Устройства"}
	for screen: int in titles:
		var name := AppState.screen_name(screen)
		var node := _open(main, screen)
		var bar := node.call("app_bar") as AppBar
		assert_not_null(bar, "%s: есть AppBar" % name)
		assert_true(bar.is_visible_in_tree(), "%s: AppBar на экране" % name)
		assert_eq((bar.get_node("%Title") as Label).theme_type_variation, &"H1Label", "%s: заголовок — вариация H1" % name)
		assert_eq(bar.title_text(), titles[screen], "%s: заголовок экрана" % name)
		assert_true(bar.back_button().is_visible_in_tree(), "%s: кнопка «назад»" % name)
		bar.back_button().pressed.emit()
		assert_eq(main.app_state.current_screen, AppState.Screen.HOME, "%s: «назад» → главный" % name)
		_open(main, screen)
		_esc()
		assert_eq(main.app_state.current_screen, AppState.Screen.HOME, "%s: Esc → главный" % name)


func test_req_uix_04_c1_ride_detail_back_returns_to_history_list() -> void:
	var main := _main()
	var r := _plan_ride(main, 1_790_000_000, 120)
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	history.refresh()
	assert_true(history.show_ride(r.id), "карточка заезда открыта")
	assert_true(history.detail().app_bar().is_visible_in_tree(), "у карточки свой AppBar")
	history.detail().app_bar().back_button().pressed.emit()
	assert_false(history.is_detail_visible(), "«назад» карточки → список")
	assert_eq(main.app_state.current_screen, AppState.Screen.HISTORY, "экран не сменился")
	_esc()
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME, "Esc со списка → главный")


# ===========================================================================
# REQ-UIX-04 крит. 3 — разделы настроек по порядку, экран открывается в начале
# ===========================================================================

func test_req_uix_04_c3_settings_sections_in_order_and_open_scrolled_to_top() -> void:
	var main := _main()
	_open(main, AppState.Screen.SETTINGS)
	var s := main.settings_screen()
	var titles: Array[String] = []
	for id in s.section_ids():
		titles.append(s.section_title(id).text)
	assert_eq(titles, ["Профиль", "Тренировка", "Зоны", "Интеграции", "Интерфейс", "О программе"] as Array[String],
		"разделы ровно в этом порядке")
	var training := " | ".join(_labels(s.section_node(s.section_ids()[1])))
	gut.p("раздел «Тренировка»: %s" % training)
	for word in ["Сопротивление", "Интенсивность", "Крутизна"]:
		assert_string_contains(training, word, "в «Тренировке» есть «%s»" % word)
	var about := " | ".join(_labels(s.section_node(s.section_ids()[5])))
	assert_string_contains(s.licenses_text() + about, "Inter", "лицензия Inter в «О программе»")
	s.scroll_to_section(s.section_ids()[5])
	main.app_state.go_back()
	main.app_state.navigate(AppState.Screen.SETTINGS)
	await wait_process_frames(2)
	assert_eq(s.scroll_container().scroll_vertical, 0, "при повторном открытии — в начале")


# ===========================================================================
# REQ-UIX-04 крит. 3 / REQ-FRD-07 крит. 6 — строки истории: колонки, метка режима, свободная езда
# ===========================================================================

func test_req_uix_04_c3_history_rows_list_row_columns_mode_label_and_free_ride() -> void:
	var main := _main()
	var plan := _plan_ride(main, 1_790_000_000, 1800)
	var free := _free_ride(main, 1_790_100_000, 1200)
	_open(main, AppState.Screen.HISTORY)
	var h := main.history_screen()
	await wait_process_frames(3)
	assert_eq(h.row_count(), 2, "обе поездки в одном списке")
	var plan_row := h.row_for(plan.id)
	var free_row := h.row_for(free.id)
	assert_not_null(plan_row)
	assert_not_null(free_row)
	for row: ListRow in [plan_row, free_row]:
		assert_eq(row.theme_type_variation, &"ListRowButton", "строка — вариация строки списка темы")
	gut.p("план: %s / %s" % [_labels(plan_row), plan_row.column_texts()])
	gut.p("свободная: %s / %s" % [_labels(free_row), free_row.column_texts()])
	assert_has(_mode_labels(plan_row), "ПЛАН", "метка режима «ПЛАН»")
	assert_has(_mode_labels(free_row), "SIM", "метка режима «SIM»")
	var pc := plan_row.column_texts()
	var fc := free_row.column_texts()
	assert_gte(pc.size(), 5, "колонки: время, км, ср. Вт, NP, набор")
	assert_eq(fc.size(), pc.size(), "колонки строк совпадают по составу")
	assert_eq(pc[0], "30:00", "время")
	assert_eq(fc[pc.size() - 1].is_valid_int(), true, "у свободной езды — набор числом: %s" % [fc])
	assert_eq(pc[pc.size() - 1], "—", "у тренировки по плану набора нет — «—»")
	# Фиксированная ширина колонок: общие колонки стоят на одних и тех же x в разных строках.
	var a := plan_row.get_node("%Columns").get_children()
	var b := free_row.get_node("%Columns").get_children()
	for i in mini(a.size(), plan_row.column_texts().size()):
		assert_eq((a[i] as Control).size.x, (b[i] as Control).size.x, "колонка %d — одной ширины" % i)
	assert_true(h.show_ride(free.id))
	assert_false(h.detail().effort_chart().has_plan(), "карточка свободной езды — без цели")
	assert_true(h.detail().is_altitude_visible(), "профиль высоты по дистанции")


# ===========================================================================
# REQ-UIX-04 крит. 4 — пустые состояния: иконка, текст, действие
# ===========================================================================

func test_req_uix_04_c4_empty_history_icon_text_and_action_goes_home() -> void:
	var main := _main()
	_open(main, AppState.Screen.HISTORY)
	var e := main.history_screen().empty_state()
	assert_true(e.is_visible_in_tree(), "пустая история — пустое состояние")
	assert_not_null(e.icon_rect().texture, "иконка")
	assert_eq(e.title_label().text, "Заездов пока нет")
	assert_false(e.text_label().text.is_empty(), "поясняющий текст")
	assert_eq(e.action_button().text, "На главный")
	e.action_button().pressed.emit()
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME, "действие ведёт на главный")


func test_req_uix_04_c4_c5_devices_slots_empty_found_and_ble_unavailable_banner() -> void:
	var main := _main()
	var d := _open(main, AppState.Screen.DEVICES) as DevicesScreen
	_set_ble(main, true)
	d.refresh()
	var slot_titles: Array[String] = []
	for kind in [RememberedDevices.KIND_TRAINER, RememberedDevices.KIND_HR, RememberedDevices.KIND_CADENCE]:
		var slot := d.slot(kind)
		assert_not_null(slot, "слот %s" % kind)
		if slot != null:
			slot_titles.append(slot.title_text())
			assert_false(slot.chip_text().is_empty(), "у слота %s есть статус" % kind)
	assert_eq(slot_titles, ["Станок", "Пульсометр", "Каденс"] as Array[String], "три слота по порядку")
	var e := d.found_empty_state()
	assert_true(e.is_visible_in_tree(), "ничего не найдено — пустое состояние")
	assert_not_null(e.icon_rect().texture)
	assert_false(e.text_label().text.is_empty())
	assert_eq(e.action_button().text, "Искать")
	assert_false(d.is_ble_banner_visible(), "Bluetooth доступен — баннера нет")
	_set_ble(main, false)
	d.refresh()
	assert_true(d.is_ble_banner_visible(), "Bluetooth недоступен — баннер")
	assert_eq(d.ble_banner().kind, Banner.Kind.WARN, "баннер-предупреждение")
	assert_false(d.ble_banner().text_label().text.is_empty())
	assert_true(d.ble_banner().action_button().is_visible_in_tree(), "у баннера есть действие")
	assert_false(d.ble_banner().action_button().text.is_empty())


# ===========================================================================
# T-086 — выбор профиля карточками; удаление через «⋯» с подтверждением
# ===========================================================================

func test_t086_profile_select_cards_choose_and_delete_via_menu() -> void:
	var repo := ProfileRepository.new(_dir + "profiles/")
	repo.create("Аня")
	repo.create("Боря")
	var main := _main()
	assert_eq(main.app_state.current_screen, AppState.Screen.PROFILE_SELECT, "два профиля — выбор профиля")
	var s := main.screen_node(AppState.Screen.PROFILE_SELECT) as ProfileSelectScreen
	assert_eq(s.cards().size(), 2, "по карточке на профиль")
	assert_true(s.create_card().is_visible_in_tree(), "карточка «Новый профиль»")
	var bob := s.cards()[1]
	assert_eq(bob.name_text(), "Боря")
	assert_string_contains(bob.stats_text(), "FTP")
	s.open_card_menu(bob.profile_id)
	s.activate_card_menu_item(ProfileSelectScreen.MENU_DELETE_ID)
	s.card_menu().hide()
	assert_eq(s.pending_delete_id(), bob.profile_id, "удаление — только через подтверждение")
	assert_eq(repo.count(), 2, "до подтверждения не удалено")
	assert_eq(s.confirm_delete(), "")
	assert_eq(ProfileRepository.new(_dir + "profiles/").count(), 1)
	var anya := s.cards()[0]
	anya.pressed.emit()
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME, "нажатие на карточку — выбор профиля")
