extends GutTest
## Приёмка T-153 (tester, независимо от `tests/integration/test_power_meter_hud.gd`): минимум UI
## езды по датчику мощности без управляемого станка. Источник истины — `docs/requirements.md`:
## REQ-WRK-09 п.2 (а), (б), (г), (д), REQ-FRD-01 п.4; п.5 (д); п.5 (е) — только фишка «БЕЗ СТАНКА»;
## п.7 — скрытые регуляторы панели свободной езды; п.10 (ru/en, не обрезано).
## Вне объёма T-153 (T-171, не проверяется здесь как passed): п.2 (в) — диалог при запомненном
## станке (до T-171 старт сразу — отступление задачи), фишки «МОЩНОСТЬ» / «СТАНОК», строка режима
## карточки «УКЛОН», шкала допуска, подсказка режима.
##
## Точки входа — как у пользователя: «Начать» в карточке главного экрана (`%StartWorkoutButton`),
## «Начать» на экране выбора тренировки (`workout_chosen`), «Поехать» в карточке главного
## (`%RideButton`) и на экране выбора трассы (`start_button()`). Устройства — `StubBleBridge`
## приложения (CPS, HRS, CSC) и `FakeTrainer` (`KIND_FAKE`) как управляемый станок. Клавиши — через
## `Viewport.push_input` (физическая клавиша, как на клавиатуре).

const MAIN_SCENE: String = "res://src/app/main.tscn"
const WORKOUT_SCENE: String = "res://src/ui/workout/workout_screen.tscn"
const FREE_RIDE_SCENE: String = "res://src/ui/free_ride/free_ride_screen.tscn"
const TEXT_RU: String = "Нужен станок или датчик мощности. Подключите их на экране «Устройства»."
const TEXT_EN: String = "You need a trainer or a power meter. Connect one on the Devices screen."
const SAFE_BASE_LP: Vector4 = Vector4(100, 0, 100, 13)
## Разрешения вводного абзаца HUD (+ 1024×768 и телефон 1280×590 из UIX).
const CASES: Array[Dictionary] = [
	{"name": "1280x720", "px": Vector2i(1280, 720), "phone": false},
	{"name": "1024x768", "px": Vector2i(1024, 768), "phone": false},
	{"name": "1280x590", "px": Vector2i(1280, 590), "phone": true},
	{"name": "1920x1080", "px": Vector2i(1920, 1080), "phone": false},
	{"name": "2732x2048", "px": Vector2i(2732, 2048), "phone": false},
	{"name": "2556x1179", "px": Vector2i(2556, 1179), "phone": true},
]
const PLAN_ENTRIES: Array[String] = ["home_start", "plan_screen_start"]
const RIDE_ENTRIES: Array[String] = ["home_ride", "route_select_ride"]

var _dir: String
var _mains: Array[AppMain] = []
var _devices: Array[TrainerDevice] = []
var _locale_before: String
var _root_size: Vector2i
var _ui: UiScale
var _now_usec: int = 0


func before_each() -> void:
	_locale_before = TranslationServer.get_locale()
	_root_size = get_tree().root.size
	_ui = get_tree().root.get_node_or_null(^"UiScaleRuntime") as UiScale
	_now_usec = 7_000_000
	_dir = "user://acc_t153_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	_mains = []
	_devices = []


func after_each() -> void:
	for m in _mains:
		if is_instance_valid(m):
			if m.get_parent() != null:
				m.get_parent().remove_child(m)
			m.free()
	_mains = []
	for d in _devices:
		if d is UncontrolledTrainer:
			(d as UncontrolledTrainer).dispose()
	_devices = []
	_set_device(false)
	if Engine.has_meta(UiScale.DEBUG_SAFE_AREA_META):
		Engine.remove_meta(UiScale.DEBUG_SAFE_AREA_META)
	if _ui != null:
		_ui.set_mode(UiScale.Mode.MENU)
	get_tree().root.size = _root_size
	TranslationServer.set_locale(_locale_before)
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


# ---------------------------------------------------------------------------
# Приложение и устройства
# ---------------------------------------------------------------------------

func _main(locale: String = "ru", debug: bool = true) -> AppMain:
	var sub := _dir + "app%d/" % _mains.size()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(sub))
	var settings := AppSettings.new(sub + "settings.json")
	settings.locale = locale
	settings.save()
	var repo := ProfileRepository.new(sub + "profiles/")
	var p := repo.create("Тестер")
	p.ftp_w = 200
	repo.save(p)
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = sub
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	main.debug_build = debug
	add_child(main)
	main.set_process(false)
	_mains.append(main)
	return main


func _stub(main: AppMain) -> StubBleBridge:
	return main.bridge as StubBleBridge


func _connect_cps(main: AppMain, id: String = "quarq") -> void:
	_stub(main).set_device_services(id, {BleUuids.CPS_SERVICE: PackedStringArray([BleUuids.CYCLING_POWER_MEASUREMENT])})
	main.connections.connect_sensor(id, RememberedDevices.KIND_POWER)
	_stub(main).pump()


func _cps(main: AppMain, watts: int, id: String = "quarq") -> void:
	_stub(main).emit_notification(id, BleUuids.CYCLING_POWER_MEASUREMENT, CpsCodec.encode_cycling_power_measurement(watts))


func _connect_smart(main: AppMain) -> void:
	main.connections.trainer.set("connect_delay_sec", 0.0)
	main.connections.connect_trainer("fake-neo")


func _remember_trainer(main: AppMain) -> void:
	main.connections.remembered.set_trainer(RememberedDevices.make_device("neo", "Tacx Neo", RememberedDevices.KIND_TRAINER))


static func _workout() -> Workout:
	return Workout.make("T-153", [WorkoutStep.watts(60, 200.0), WorkoutStep.percent(60, 75.0)] as Array[WorkoutStep])


## «Начать» / «Поехать» из точки входа `entry`. Возвращает true, если нажатие было выполнено.
func _press(main: AppMain, entry: String) -> void:
	var home := main.home_screen()
	match entry:
		"home_start":
			home.remember_workout(_workout(), PlanScreen.SOURCE_LIBRARY)
			var b := home.get_node("%StartWorkoutButton") as Button
			assert_true(b.visible, "%s: кнопка «Начать» в карточке плана видна" % entry)
			b.pressed.emit()
		"plan_screen_start":
			main.app_state.navigate(AppState.Screen.PLAN)
			main.plan_screen().workout_chosen.emit(_workout(), PlanScreen.SOURCE_LIBRARY)
		"home_ride":
			(home.get_node("%RideButton") as Button).pressed.emit()
		"route_select_ride":
			main.app_state.navigate(AppState.Screen.ROUTE_SELECT)
			main.route_select_screen().start_button().pressed.emit()


func _plan_dialog(main: AppMain) -> ConfirmationDialog:
	return main.plan_screen().get_node("%TrainerDialog") as ConfirmationDialog


func _any_dialog_visible(main: AppMain) -> bool:
	return _plan_dialog(main).visible or main.free_ride_trainer_dialog().visible


## Клавиша по физическому коду (как с клавиатуры; буквы — по физической клавише).
func _key(code: Key, unicode: int = 0) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.unicode = unicode
		ev.pressed = pressed
		get_tree().root.push_input(ev)


static func _ids(toolbar: HudToolbar) -> Array[StringName]:
	var out: Array[StringName] = []
	for b in toolbar.visible_buttons():
		for id: StringName in [&"erg", &"sim", &"intensity_down", &"intensity_up", &"resistance_down",
				&"resistance_up", &"steepness_down", &"steepness_up", &"skip", &"finish"]:
			if toolbar.button(id) == b:
				out.append(id)
	return out


## Ряды панели: в каждом — id видимых кнопок ряда (по родителю-ряду).
static func _rows(toolbar: HudToolbar) -> Array:
	var rows: Array = []
	var by_parent := {}
	for b in toolbar.visible_buttons():
		var parent := b.get_parent()
		if not by_parent.has(parent):
			by_parent[parent] = rows.size()
			rows.append([])
		for id: StringName in [&"erg", &"sim", &"intensity_down", &"intensity_up", &"resistance_down",
				&"resistance_up", &"steepness_down", &"steepness_up", &"skip", &"finish"]:
			if toolbar.button(id) == b:
				(rows[by_parent[parent]] as Array).append(id)
	return rows


## Подписи видимых фишек статуса экрана.
static func _chip_texts(screen: Control) -> Array[String]:
	var out: Array[String] = []
	var slot := screen.get_node("%StatusSlot")
	for chip in slot.get_children():
		if chip is Control and (chip as Control).is_visible_in_tree():
			for l in (chip as Control).find_children("*", "Label", true, false):
				if (l as Label).is_visible_in_tree():
					out.append((l as Label).text)
	return out


static func _toolbar_labels(toolbar: HudToolbar) -> Array[String]:
	var out: Array[String] = []
	for l in toolbar.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree():
			out.append(str((l as Label).name))
	return out


# ===========================================================================
# REQ-WRK-09 п.2 (б), FRD-01 п.4 — старт power_meter сразу, без диалога
# (с запомненным станком — отступление T-153 от п.2 (в), T-171)
# ===========================================================================

func _assert_power_meter_start(entry: String, remembered: bool) -> void:
	var main := _main()
	_connect_cps(main)
	if remembered:
		_remember_trainer(main)
		assert_true(main.connections.remembered.has_trainer(), "предусловие: станок запомнен")
	assert_ne(main.connections.trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED,
		"предусловие: управляемый станок не подключён")
	_press(main, entry)
	var tag := "%s, запомнен станок: %s" % [entry, remembered]
	assert_false(_any_dialog_visible(main), "%s: без диалога" % tag)
	if entry in PLAN_ENTRIES:
		assert_eq(main.app_state.current_screen, AppState.Screen.WORKOUT, "%s: экран тренировки" % tag)
		var s := main.workout_screen().session()
		assert_not_null(s, "%s: сессия создана" % tag)
		if s != null:
			assert_eq(s.trainer_mode, TrainerDevice.MODE_POWER_METER, tag)
			assert_eq(s.get_state(), WorkoutSession.State.RUNNING, "%s: сессия идёт" % tag)
	else:
		assert_eq(main.app_state.current_screen, AppState.Screen.FREE_RIDE, "%s: экран свободной езды" % tag)
		var fr := main.free_ride_screen().session()
		assert_not_null(fr, "%s: сессия создана" % tag)
		if fr != null:
			assert_eq(fr.trainer_mode, TrainerDevice.MODE_POWER_METER, tag)
	assert_eq(_stub(main).calls_of("write"), [] as Array[Dictionary], "%s: ни одного write" % tag)


func test_req_wrk_09_c2b_home_start_power_meter_immediately() -> void:
	_assert_power_meter_start("home_start", false)


func test_req_wrk_09_c2b_plan_screen_start_power_meter_immediately() -> void:
	_assert_power_meter_start("plan_screen_start", false)


func test_req_wrk_09_c2b_frd_01_c4_home_ride_power_meter_immediately() -> void:
	_assert_power_meter_start("home_ride", false)


func test_req_wrk_09_c2b_frd_01_c4_route_select_ride_power_meter_immediately() -> void:
	_assert_power_meter_start("route_select_ride", false)


func test_t153_remembered_trainer_still_starts_immediately_plan_and_ride() -> void:
	# Отступление задачи T-153 от п.2 (в): до T-171 старт сразу и при запомненном станке.
	for entry in PLAN_ENTRIES + RIDE_ENTRIES:
		_assert_power_meter_start(entry, true)


# ===========================================================================
# REQ-WRK-09 п.2 (а) — с управляемым станком как прежде (smart, ERG на месте)
# ===========================================================================

func test_req_wrk_09_c2a_controllable_trainer_and_cps_smart_as_before() -> void:
	for entry in PLAN_ENTRIES + RIDE_ENTRIES:
		var main := _main()
		_connect_cps(main)
		_connect_smart(main)
		assert_true(main.is_trainer_ready(), "предусловие: станок подключён")
		_press(main, entry)
		assert_false(_any_dialog_visible(main), "%s: без диалога" % entry)
		if entry in PLAN_ENTRIES:
			var s := main.workout_screen().session()
			assert_not_null(s, entry)
			assert_eq(s.trainer_mode, TrainerDevice.MODE_SMART, "%s: smart" % entry)
			assert_true(main.workout_screen().toolbar().visible_buttons().has(main.workout_screen().toolbar().button(&"erg")),
				"%s: кнопка ERG на месте" % entry)
			assert_eq(main.workout_screen().mode_chip_text(), "ERG", "%s: фишка «ERG»" % entry)
			assert_false(_chip_texts(main.workout_screen()).has("БЕЗ СТАНКА"), "%s: в smart фишки «БЕЗ СТАНКА» нет" % entry)
		else:
			var fr := main.free_ride_screen().session()
			assert_not_null(fr, entry)
			assert_eq(fr.trainer_mode, TrainerDevice.MODE_SMART, "%s: smart" % entry)
			assert_true(_ids(main.free_ride_screen().toolbar()).has(&"sim"), "%s: SIM ↔ сопротивление на месте" % entry)
			assert_eq(main.free_ride_screen().mode_chip_text(), "SIM", "%s: фишка «SIM»" % entry)
			assert_false(_chip_texts(main.free_ride_screen()).has("БЕЗ СТАНКА"), entry)


func test_req_wrk_09_c2a_c5d_smart_after_power_meter_session_gets_erg_back() -> void:
	# Экран тренировки переиспользуется: после заезда power_meter следующий smart — с ERG.
	var main := _main()
	_connect_cps(main)
	_press(main, "home_start")
	var s := main.workout_screen().session()
	assert_eq(s.trainer_mode, TrainerDevice.MODE_POWER_METER, "предусловие: power_meter")
	while s.get_state() != WorkoutSession.State.FINISHED:
		_cps(main, 180)
		s.tick(1.0)
	_connect_smart(main)
	main.app_state.navigate(AppState.Screen.HOME)
	_press(main, "home_start")
	var s2 := main.workout_screen().session()
	assert_ne(s2, s, "новая сессия")
	assert_eq(s2.trainer_mode, TrainerDevice.MODE_SMART)
	var tb := main.workout_screen().toolbar()
	assert_true(tb.controls_trainer())
	assert_true(_ids(tb).has(&"erg"), "ERG вернулась")
	assert_eq(main.workout_screen().mode_chip_text(), "ERG")
	# Контроль доставки клавиш: в smart та же клавиша E переключает ERG (в power_meter — нет).
	var erg_before := s2.erg_enabled
	_key(KEY_E)
	assert_ne(s2.erg_enabled, erg_before, "smart: E переключает ERG, как прежде")
	_key(KEY_EQUAL, 0x2B)
	assert_almost_eq(s2.intensity(), 1.05, 0.001, "smart: `+` — интенсивность, как прежде")


# ===========================================================================
# REQ-WRK-09 п.2 (д) — «подключение» / «переподключение» — не «подключено»
# ===========================================================================

func test_req_wrk_09_c2d_cps_connecting_no_start_plan_and_ride() -> void:
	for entry in PLAN_ENTRIES + RIDE_ENTRIES:
		var main := _main()
		_stub(main).auto_connect = false
		_connect_cps(main)
		var pm := main.connections.sensor(RememberedDevices.KIND_POWER)
		assert_eq(pm.get_connection_state(), TrainerDevice.ConnectionState.CONNECTING, "предусловие: подключение")
		_press(main, entry)
		assert_null(main.workout_screen().session(), "%s: сессии плана нет" % entry)
		assert_null(main.free_ride_screen().session(), "%s: сессии езды нет" % entry)
		assert_true(_any_dialog_visible(main), "%s: диалог «Станок не подключён»" % entry)
		_plan_dialog(main).hide()
		main.free_ride_trainer_dialog().hide()


func test_req_wrk_09_c2d_cps_reconnecting_no_start_plan_and_ride() -> void:
	for entry in PLAN_ENTRIES + RIDE_ENTRIES:
		var main := _main()
		_connect_cps(main)
		_stub(main).auto_connect = false
		_stub(main).emit_disconnected("quarq", BleBridge.DisconnectReason.LINK_LOSS)
		_stub(main).pump()
		var pm := main.connections.sensor(RememberedDevices.KIND_POWER)
		assert_eq(pm.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING, "предусловие: переподключение")
		_press(main, entry)
		assert_null(main.workout_screen().session(), "%s: сессии плана нет" % entry)
		assert_null(main.free_ride_screen().session(), "%s: сессии езды нет" % entry)
		assert_true(_any_dialog_visible(main), "%s: диалог «Станок не подключён»" % entry)
		_plan_dialog(main).hide()
		main.free_ride_trainer_dialog().hide()


# ===========================================================================
# REQ-WRK-09 п.2 (г), п.10 — ни станка, ни источника мощности: диалог с новым текстом
# ===========================================================================

## Устройства сценария (г): "hrs_csc" — только пульсометр и датчик каденса, "none" — ничего.
func _assert_no_source_dialog(entry: String, devices: String, locale: String, debug: bool) -> void:
	var main := _main(locale, debug)
	if devices == "hrs_csc":
		main.connections.connect_sensor("hrs", RememberedDevices.KIND_HR)
		main.connections.connect_sensor("csc", RememberedDevices.KIND_CADENCE)
		_stub(main).pump()
	var tag := "%s, %s, %s, %s" % [entry, devices, locale, "debug" if debug else "release"]
	assert_false(main.can_start_session(), "%s: предусловие — старта нет" % tag)
	_press(main, entry)
	assert_null(main.workout_screen().session(), "%s: сессия плана не создана" % tag)
	assert_null(main.free_ride_screen().session(), "%s: сессия езды не создана" % tag)
	var expected := TEXT_RU if locale == "ru" else TEXT_EN
	var title := "Станок не подключён" if locale == "ru" else ""
	if entry in PLAN_ENTRIES:
		var d := _plan_dialog(main)
		assert_eq(main.app_state.current_screen, AppState.Screen.PLAN, "%s: экран выбора тренировки" % tag)
		assert_true(d.visible, "%s: диалог открыт" % tag)
		assert_eq(tr(d.dialog_text), expected, "%s: текст диалога" % tag)
		if title != "":
			assert_eq(tr(d.title), title, tag)
		var emu_visible := _dialog_has_visible_button(d, tr("ui.plan.trainer_choice.emulator"))
		assert_eq(emu_visible, debug, "%s: кнопка «Эмулятор» — только в отладочной сборке" % tag)
		assert_true(d.get_ok_button().visible, "%s: кнопка экрана устройств" % tag)
		d.hide()
	else:
		var d := main.free_ride_trainer_dialog()
		assert_true(d.visible, "%s: диалог открыт" % tag)
		assert_eq(tr(d.dialog_text), expected, "%s: текст диалога" % tag)
		if title != "":
			assert_eq(tr(d.title), title, tag)
		assert_eq(main.free_ride_emulator_button().visible, debug, "%s: «Эмулятор» — только в отладочной сборке" % tag)
		assert_eq(tr(d.get_ok_button().text), tr("ui.free_ride.no_trainer.devices"), "%s: «Устройства»" % tag)
		d.hide()


func _dialog_has_visible_button(d: AcceptDialog, text: String) -> bool:
	for n in d.find_children("*", "Button", true, false):
		var b := n as Button
		if b.visible and tr(b.text) == text:
			return true
	return false


func test_req_wrk_09_c2g_frd_01_c4_hrs_csc_only_dialog_ru_en_plan_and_ride() -> void:
	for entry in PLAN_ENTRIES + RIDE_ENTRIES:
		for locale: String in ["ru", "en"]:
			_assert_no_source_dialog(entry, "hrs_csc", locale, false)


func test_req_wrk_09_c2g_frd_01_c4_nothing_connected_dialog_ru_en_plan_and_ride() -> void:
	for entry in PLAN_ENTRIES + RIDE_ENTRIES:
		for locale: String in ["ru", "en"]:
			_assert_no_source_dialog(entry, "none", locale, false)


# ===========================================================================
# REQ-WRK-09 п.5 (д), (е) — HUD тренировки по плану в power_meter (приложение, реальный мост)
# ===========================================================================

func test_req_wrk_09_c5d_plan_toolbar_hidden_controls_keys_and_no_bridge_writes() -> void:
	var main := _main()
	_connect_cps(main)
	_press(main, "home_start")
	var screen := main.workout_screen()
	var s := screen.session()
	assert_eq(s.trainer_mode, TrainerDevice.MODE_POWER_METER, "предусловие: power_meter")
	for i in 5:
		_cps(main, 190)
		s.tick(1.0)
	var tb := screen.toolbar()
	# Скрыты, а не недоступны: кнопок нет на панели.
	for id: StringName in [&"erg", &"resistance_down", &"resistance_up", &"sim", &"steepness_down", &"steepness_up"]:
		assert_false(tb.button(id).is_visible_in_tree(), "кнопки %s на панели нет" % id)
	assert_eq(_ids(tb), [&"intensity_down", &"intensity_up", &"skip", &"finish"] as Array[StringName],
		"остаются интенсивность −5 / +5 %, «Пропустить шаг», «Завершить»")
	for name in _toolbar_labels(tb):
		assert_false(name.begins_with("Resistance") or name.begins_with("Steepness"), "подписи %s на панели нет" % name)
	assert_false(screen.is_resistance_row_visible(), "строки сопротивления нет")
	_stub(main).clear_calls()
	var events_before := s.events.size()
	var erg_before := s.erg_enabled
	# E — посреди интервала, несколько раз.
	for i in 3:
		_key(KEY_E)
		_cps(main, 190)
		s.tick(1.0)
	assert_eq(s.erg_enabled, erg_before, "E не меняет ERG")
	assert_false(s.erg_enabled, "ERG «выкл»")
	assert_eq(s.events.size(), events_before, "E не пишет событий в сессию")
	assert_eq(_stub(main).calls, [] as Array[Dictionary], "E и тики: журнал моста без записей (только приём данных)")
	assert_false(_ids(tb).has(&"erg"), "после E ERG не появилась")
	# `+` / `−` — интенсивность и цель в карточке не позже следующего сэмпла.
	var target_before := s.current_target_watts()
	assert_eq(target_before, 200, "предусловие: шаг 200 Вт")
	_key(KEY_EQUAL, 0x2B)
	_cps(main, 190)
	s.tick(1.0)
	assert_almost_eq(s.intensity(), 1.05, 0.001, "`+` → 105 %")
	assert_eq(s.current_target_watts(), 210, "цель 210 Вт")
	assert_eq(screen.target_text(), tr("ui.workout.target_value").format({"value": "210"}), "цель в карточке — 210")
	assert_eq(s.samples.target_w[s.samples.size() - 1], 210, "цель следующего сэмпла — 210")
	_key(KEY_MINUS, 0x2D)
	_cps(main, 190)
	s.tick(1.0)
	assert_almost_eq(s.intensity(), 1.0, 0.001, "`−` → 100 %")
	assert_eq(screen.target_text(), tr("ui.workout.target_value").format({"value": "200"}))
	# Кнопка +5 % на панели — то же.
	tb.button(&"intensity_up").pressed.emit()
	assert_almost_eq(s.intensity(), 1.05, 0.001, "кнопка +5 %")
	_cps(main, 190)
	s.tick(1.0)
	assert_eq(screen.target_text(), tr("ui.workout.target_value").format({"value": "210"}))
	assert_eq(_stub(main).calls_of("write"), [] as Array[Dictionary], "ни одного write")
	assert_eq(_stub(main).calls_of("subscribe"), [] as Array[Dictionary], "новых подписок нет")


func test_req_wrk_09_c5d_plan_cps_lost_and_restored_still_no_trainer_controls() -> void:
	# Потеря и восстановление BLE-соединения датчика посреди интервала: панель не меняется,
	# E без действия, записей в мост нет.
	var main := _main()
	_connect_cps(main)
	_press(main, "plan_screen_start")
	var screen := main.workout_screen()
	var s := screen.session()
	_stub(main).clear_calls()
	var stub := _stub(main)
	stub.auto_connect = false
	for t in 60:
		if t == 10:
			stub.emit_disconnected("quarq", BleBridge.DisconnectReason.LINK_LOSS)
			stub.pump()
		if t == 20:
			_key(KEY_E)
		if t == 30:
			stub.emit_connected("quarq")
			stub.pump()
		if t < 10 or t > 30:
			_cps(main, 205)
		s.tick(1.0)
		stub.pump()
	assert_eq(_ids(screen.toolbar()), [&"intensity_down", &"intensity_up", &"skip", &"finish"] as Array[StringName],
		"панель без органов управления станком и после обрыва")
	assert_eq(screen.mode_chip_text(), "БЕЗ СТАНКА")
	assert_false(s.erg_enabled)
	assert_eq(stub.calls_of("write"), [] as Array[Dictionary], "ни одного write за обрыв и восстановление")
	var subs: Array[String] = []
	for c in stub.calls_of("subscribe"):
		subs.append(str(c["char"]))
	assert_true(subs.has(BleUuids.CYCLING_POWER_MEASUREMENT), "после восстановления — подписка на 2A63: %s" % str(subs))
	assert_false(subs.has(BleUuids.FTMS_CONTROL_POINT) or subs.has("2A66"), "подписок на 2AD9 / 2A66 нет: %s" % str(subs))


func test_req_wrk_09_c5e_plan_chip_no_trainer_instead_of_erg_dot_text2() -> void:
	var main := _main()
	_connect_cps(main)
	_press(main, "home_start")
	var screen := main.workout_screen()
	_cps(main, 150)
	screen.session().tick(1.0)
	assert_eq(screen.mode_chip_text(), "БЕЗ СТАНКА", "на месте «ERG» — «БЕЗ СТАНКА»")
	var texts := _chip_texts(screen)
	assert_true(texts.has("БЕЗ СТАНКА"), "фишка видна: %s" % str(texts))
	assert_false(texts.has("ERG"), "фишки «ERG» нет: %s" % str(texts))
	assert_false(texts.has("SIM"), "фишки «SIM» нет")
	var frame: HudScreenFrame = screen.get("_frame")
	assert_eq(frame.dot(screen.get_node("%ModeChip") as Control), UiTokens.HUD_TEXT2, "точка `hud.text2`")
	# Интенсивность — как в smart: фишка «105 %».
	screen.toolbar().trigger(HudToolbar.ACTION_PLUS)
	screen.refresh()
	assert_true(_chip_texts(screen).has("105 %"), "фишка интенсивности как в smart: %s" % str(_chip_texts(screen)))


func test_req_wrk_09_c5e_c10_plan_chip_en_no_trainer() -> void:
	var main := _main("en")
	_connect_cps(main)
	_press(main, "home_start")
	assert_eq(main.workout_screen().mode_chip_text(), "NO TRAINER")
	assert_false(_chip_texts(main.workout_screen()).has("ERG"))


# ===========================================================================
# REQ-WRK-09 п.7 — панель свободной езды без регуляторов; п.5 (е) фишка
# ===========================================================================

func test_req_wrk_09_c7_free_ride_only_finish_keys_do_nothing_no_writes() -> void:
	for entry in RIDE_ENTRIES:
		var main := _main()
		_connect_cps(main)
		_press(main, entry)
		var screen := main.free_ride_screen()
		var fr := screen.session()
		assert_eq(fr.trainer_mode, TrainerDevice.MODE_POWER_METER, "предусловие: power_meter")
		for i in 5:
			_cps(main, 200)
			fr.tick(1.0)
		var tb := screen.toolbar()
		assert_eq(_ids(tb), [&"finish"] as Array[StringName], "%s: на панели только «Завершить»" % entry)
		for name in _toolbar_labels(tb):
			assert_false(name.begins_with("Steepness") or name.begins_with("Resistance"), "%s: подписи %s нет" % [entry, name])
		_stub(main).clear_calls()
		var mode_before := fr.mode()
		var steep_before := fr.steepness_pct()
		var res_before := fr.resistance_level()
		var events_before := fr.events.size()
		for k: Array in [[KEY_E, 0], [KEY_EQUAL, 0x2B], [KEY_MINUS, 0x2D], [KEY_KP_ADD, 0], [KEY_KP_SUBTRACT, 0]]:
			_key(k[0], k[1])
			_cps(main, 200)
			fr.tick(1.0)
		assert_eq(fr.mode(), mode_before, "%s: E не переключает SIM ↔ сопротивление" % entry)
		assert_eq(fr.steepness_pct(), steep_before, "%s: `+`/`−` не меняют крутизну" % entry)
		assert_eq(fr.resistance_level(), res_before, "%s: `+`/`−` не меняют сопротивление" % entry)
		assert_eq(fr.events.size(), events_before, "%s: событий нет" % entry)
		assert_false(screen.is_notice_visible(), "%s: сообщения «станок не поддерживает SIM» нет" % entry)
		assert_eq(_stub(main).calls_of("write"), [] as Array[Dictionary], "%s: ни одного write" % entry)
		assert_eq(screen.mode_chip_text(), "БЕЗ СТАНКА", "%s: фишка «БЕЗ СТАНКА» вместо «SIM»" % entry)
		var texts := _chip_texts(screen)
		assert_false(texts.has("SIM") or texts.has("СОПР."), "%s: фишек «SIM» / «СОПР.» нет: %s" % [entry, str(texts)])
		var frame: HudScreenFrame = screen.get("_frame")
		assert_eq(frame.dot(screen.get_node("%ModeChip") as Control), UiTokens.HUD_TEXT2, "%s: точка `hud.text2`" % entry)


# ===========================================================================
# REQ-WRK-09 п.5 (д), п.7, п.10 — раскладка на разрешениях HUD, ru/en: панель и фишка
# ===========================================================================

func _clock() -> int:
	return _now_usec


func _no_keep(_on: bool) -> void:
	pass


func _set_device(phone: bool) -> void:
	if phone:
		Engine.set_meta(UiScale.DEBUG_DEVICE_META, "phone")
	elif Engine.has_meta(UiScale.DEBUG_DEVICE_META):
		Engine.remove_meta(UiScale.DEBUG_DEVICE_META)
	if _ui != null:
		_ui.device = UiScale.detect_device()


func _emulator() -> TrainerDevice:
	var d := TrainerFactory.create_power_meter_emulator()
	_devices.append(d)
	return d


func _apply_case(screen: Control, c: Dictionary) -> void:
	var phone: bool = c["phone"]
	_set_device(phone)
	if phone:
		Engine.set_meta(UiScale.DEBUG_SAFE_AREA_META, SAFE_BASE_LP / UiScale.HUD_SCALE_PHONE)
	elif Engine.has_meta(UiScale.DEBUG_SAFE_AREA_META):
		Engine.remove_meta(UiScale.DEBUG_SAFE_AREA_META)
	get_tree().root.size = c["px"]
	if _ui != null:
		_ui.set_mode(UiScale.Mode.HUD)
	screen.call("on_screen_entered")
	await wait_process_frames(3)
	screen.call("refresh")


func _assert_chip_not_clipped(screen: Control, expected: String, tag: String) -> void:
	var chip := screen.get_node("%ModeChip") as Control
	var label := screen.get_node("%ModeStatusLabel") as Label
	assert_eq(label.text, expected, "%s: подпись фишки" % tag)
	assert_true(chip.is_visible_in_tree(), "%s: фишка видна" % tag)
	var font := label.get_theme_font("font")
	var text_w := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
	assert_true(text_w <= label.size.x + 0.5, "%s: «%s» %.1f помещается в подпись %.1f" % [tag, label.text, text_w, label.size.x])
	var chip_rect := chip.get_global_rect()
	var label_rect := label.get_global_rect()
	assert_true(chip_rect.grow(0.5).encloses(label_rect), "%s: подпись внутри фишки %s ⊂ %s" % [tag, label_rect, chip_rect])
	var view := screen.get_viewport_rect()
	assert_true(view.grow(0.5).encloses(chip_rect), "%s: фишка внутри окна %s ⊂ %s" % [tag, chip_rect, view])
	var pause := screen.get_node("%PauseButton") as Control
	assert_false(chip_rect.intersects(pause.get_global_rect()), "%s: фишка не заходит на кнопку паузы" % tag)
	for other in screen.get_node("%StatusSlot").get_children():
		if other == chip or not (other is Control) or not (other as Control).is_visible_in_tree():
			continue
		var r := (other as Control).get_global_rect()
		assert_false(chip_rect.grow(-0.5).intersects(r), "%s: фишка не перекрывает %s" % [tag, other.name])


func test_req_wrk_09_c5d_c5e_c10_plan_hud_all_resolutions_ru_en() -> void:
	var screen: WorkoutScreen = load(WORKOUT_SCENE).instantiate()
	screen.clock_usec = _clock
	screen.keep_awake_setter = _no_keep
	add_child_autofree(screen)
	var profile := Profile.create("Rider")
	profile.ftp_w = 200
	screen.setup(_workout(), profile, _emulator(), AppState.new(ProfileRepository.new(_dir + "profiles/")))
	assert_true(screen.start())
	screen.on_screen_entered()
	for locale: String in ["ru", "en"]:
		TranslationServer.set_locale(locale)
		for c in CASES:
			await _apply_case(screen, c)
			var tag := "%s %s" % [locale, c["name"]]
			_assert_chip_not_clipped(screen, "БЕЗ СТАНКА" if locale == "ru" else "NO TRAINER", tag)
			var tb := screen.toolbar()
			if c["phone"]:
				assert_eq(_rows(tb), [[&"skip", &"finish"], [&"intensity_down", &"intensity_up"]],
					"%s: телефон — ряд «Пропустить шаг» · «Завершить», ряд интенсивности" % tag)
			else:
				assert_eq(_ids(tb), [&"intensity_down", &"intensity_up", &"skip", &"finish"] as Array[StringName], tag)
			for id: StringName in [&"erg", &"resistance_down", &"resistance_up"]:
				assert_false(tb.button(id).is_visible_in_tree(), "%s: %s нет" % [tag, id])


func test_req_wrk_09_c7_c5e_c10_free_ride_hud_all_resolutions_ru_en() -> void:
	var screen: FreeRideScreen = load(FREE_RIDE_SCENE).instantiate()
	screen.clock_usec = _clock
	screen.keep_awake_setter = _no_keep
	add_child_autofree(screen)
	var profile := Profile.create("Rider")
	profile.ftp_w = 200
	screen.setup(AppState.new(ProfileRepository.new(_dir + "profiles/")), profile, _emulator(), RouteCatalog.MOUNTAINS, 50)
	assert_true(screen.start())
	screen.on_screen_entered()
	for locale: String in ["ru", "en"]:
		TranslationServer.set_locale(locale)
		for c in CASES:
			await _apply_case(screen, c)
			var tag := "%s %s" % [locale, c["name"]]
			_assert_chip_not_clipped(screen, "БЕЗ СТАНКА" if locale == "ru" else "NO TRAINER", tag)
			assert_eq(_ids(screen.toolbar()), [&"finish"] as Array[StringName], "%s: только «Завершить»" % tag)


# ===========================================================================
# REQ-WRK-09 п.10, NFR-08 — ключи ru/en; текст диалога не обрезан
# ===========================================================================

func test_req_wrk_09_c10_new_keys_ru_en() -> void:
	var expect := {
		"ui.hud.status.no_trainer": ["БЕЗ СТАНКА", "NO TRAINER"],
		"ui.free_ride.no_trainer.text": [TEXT_RU, TEXT_EN],
		"ui.plan.trainer_choice.text_release": [TEXT_RU, TEXT_EN],
	}
	for key: String in expect:
		for i in 2:
			var locale: String = ["ru", "en"][i]
			TranslationServer.set_locale(locale)
			assert_eq(tr(key), expect[key][i], "%s [%s]" % [key, locale])
	# Ключ отладочного текста плана — тоже на обоих языках (содержание — тест п.2 (г) выше).
	for locale: String in ["ru", "en"]:
		TranslationServer.set_locale(locale)
		assert_ne(tr("ui.plan.trainer_choice.text"), "ui.plan.trainer_choice.text", locale)
		assert_ne(tr("ui.hud.status.no_trainer_hint"), "ui.hud.status.no_trainer_hint", locale)


func test_req_wrk_09_c10_no_source_dialog_text_not_clipped_ru_en() -> void:
	for locale: String in ["ru", "en"]:
		for entry: String in ["plan_screen_start", "route_select_ride"]:
			var main := _main(locale, false)
			_press(main, entry)
			var d: AcceptDialog = _plan_dialog(main) if entry == "plan_screen_start" else main.free_ride_trainer_dialog()
			assert_true(d.visible, "%s %s: диалог открыт" % [locale, entry])
			await wait_process_frames(2)
			var label := d.get_label()
			# Подпись диалога свободной езды хранит ключ и переводится при показе (auto_translate).
			var shown := tr(label.text)
			var tag := "%s %s «%s»" % [locale, entry, shown]
			assert_eq(shown, TEXT_RU if locale == "ru" else TEXT_EN, tag)
			assert_eq(label.get_visible_line_count(), label.get_line_count(), "%s: все строки видны" % tag)
			var lh := label.get_line_height()
			assert_true(label.get_line_count() * lh <= label.size.y + 1.0,
				"%s: %d строк × %d ≤ высоты %.1f" % [tag, label.get_line_count(), lh, label.size.y])
			var vp := get_tree().root.get_visible_rect()
			assert_true(vp.grow(0.5).encloses(Rect2(Vector2(d.position), Vector2(d.size))), "%s: диалог в окне" % tag)
			d.hide()
