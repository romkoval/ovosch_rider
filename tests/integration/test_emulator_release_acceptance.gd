extends GutTest
## Приёмка T-150 (tester): эмулятор станка в release-сборке через скрытую строку «Эмулятор
## станка» в «О программе» (5 нажатий на «Версию»). Критерии — карточка T-150 (расширение
## REQ-DEV-09 п.6 и REQ-FRD-01 п.4 на release по Н-52); регрессия REQ-WRK-01 п.5.
## Release имитируется `AppMain.debug_build = false` до входа оболочки в дерево.
## Проверяется то, чего нет в тестах разработчика (`test_emulator_release_toggle.gd`):
## - п.2 карточки: прочие инструменты «Режима разработки» главного в release не открываются;
## - тренировка на эмуляторе в release идёт до конца и заезд сохраняется (WRK-01 п.5);
## - в профиль и в настройки ничего не пишется;
## - выключение переключателя не обрывает идущий заезд;
## - п.3 карточки: пометка «Эмулятор» на HUD заезда на эмуляторе;
## - переводы строки ru/en (п.5 карточки).

const MAIN_SCENE: String = "res://src/app/main.tscn"

var _dir: String
var _previous_locale: String
var _now_usec: int = 0


func before_each() -> void:
	_dir = "user://acc_t150_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_now_usec = 1_000_000


func after_each() -> void:
	DiagLog.uninstall()
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
	var repo := ProfileRepository.new(_dir + "profiles/")
	if repo.list().is_empty():
		repo.create("Solo")
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.debug_build = false
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	add_child_autofree(main)
	main.workout_screen().clock_usec = _clock
	main.workout_screen().keep_awake_setter = _ignore
	main.free_ride_screen().clock_usec = _clock
	main.free_ride_screen().keep_awake_setter = _ignore
	return main


func _clock() -> int:
	return _now_usec


func _ignore(_on: bool) -> void:
	pass


static func _click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e


func _enable_emulator(main: AppMain) -> AboutDiagnostics:
	main.app_state.navigate(AppState.Screen.SETTINGS)
	var settings := main.settings_screen()
	var version_row := (settings.get_node("%VersionLabel") as Control).get_parent() as Control
	for i in AboutDiagnostics.UNLOCK_TAPS:
		version_row.gui_input.emit(_click())
	var diag := settings.diagnostics()
	diag.emulator_check().button_pressed = true
	return diag


## Снимок всех файлов каталога данных, кроме журналов: путь → содержимое.
func _snapshot(root: String) -> Dictionary:
	var out: Dictionary = {}
	_collect(ProjectSettings.globalize_path(root), "", out)
	return out


static func _collect(abs_dir: String, rel: String, out: Dictionary) -> void:
	var d := DirAccess.open(abs_dir)
	if d == null:
		return
	for f in d.get_files():
		out[rel + f] = FileAccess.get_file_as_string(abs_dir.path_join(f))
	for sub in d.get_directories():
		if rel.is_empty() and sub == "logs":
			continue
		_collect(abs_dir.path_join(sub), rel + sub + "/", out)


## Видимые надписи и кнопки узла (тексты).
static func _visible_texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child in node.find_children("*", "Control", true, false):
		var c := child as Control
		if not c.is_visible_in_tree():
			continue
		if c is Label:
			out.append((c as Label).text)
		elif c is Button:
			out.append((c as Button).text)
		elif c is RichTextLabel:
			out.append((c as RichTextLabel).get_parsed_text())
	return out


func _finish_workout(main: AppMain) -> WorkoutSession:
	var ws := main.workout_screen()
	var session := ws.session()
	for i in 400:
		if session == null or session.get_state() == WorkoutSession.State.FINISHED:
			break
		_now_usec += 1_000_000
		ws.ticker().poll()
	return session


# ---------------------------------------------------------------------------
# П.2 карточки: только эмулятор, без прочих инструментов «Режима разработки»
# ---------------------------------------------------------------------------

func test_card_p2_release_emulator_does_not_open_dev_mode_screen_on_home() -> void:
	var main := _main()
	_enable_emulator(main)
	assert_true(main.emulator_enabled(), "эмулятор включён")
	main.app_state.navigate(AppState.Screen.HOME)
	var home := main.home_screen()
	var dev_button := home.get_node("%DevButton") as Control
	var dev_menu_button := home.get_node("%DevMenuButton") as Control
	var dev_menu := home.get_node("%DevMenu") as PopupMenu
	var via_menu: bool = dev_menu_button.is_visible_in_tree() and dev_menu.get_item_index(HomeScreen.MENU_DEV_SCREEN) >= 0
	assert_false(dev_button.is_visible_in_tree() or via_menu,
		"карточка T-150 п.2: «Прочие инструменты „Режима разработки“ главного экрана в release не открываются» — "
		+ "после включения эмулятора кнопка «Режим разработки» (AppState.Screen.DEV) видна")
	if dev_button.is_visible_in_tree():
		(dev_button as Button).pressed.emit()
		assert_ne(main.app_state.current_screen, AppState.Screen.DEV,
			"в release экран «Режим разработки» (сценарии FakeTrainer, инструменты) открывается с главного")


# ---------------------------------------------------------------------------
# Тренировка на эмуляторе до конца (WRK-01 п.5) и сохранение заезда
# ---------------------------------------------------------------------------

func test_release_emulator_workout_runs_to_finish_and_ride_saved() -> void:
	var main := _main()
	_enable_emulator(main)
	var profile_id: String = main.repo.get_active().id
	var before := main.ride_repository.list(profile_id).size()
	assert_false(main.start_workout(DevScreen.test_workout()), "станка нет — диалог выбора")
	(main.plan_screen().get_node("%TrainerDialog") as ConfirmationDialog).custom_action.emit(PlanScreen.TRAINER_ACTION_EMULATOR)
	var session := main.workout_screen().session()
	assert_not_null(session, "тренировка запущена")
	if session == null:
		return
	assert_true(session.trainer is FakeTrainer, "станок — эмулятор")
	_finish_workout(main)
	assert_eq(session.get_state(), WorkoutSession.State.FINISHED, "WRK-01 п.5: план 180 с проигран до конца")
	await wait_process_frames(2)
	assert_eq(main.ride_repository.list(profile_id).size(), before + 1, "заезд на эмуляторе сохранён (п.4 карточки)")


func test_release_toggle_off_during_emulator_ride_does_not_stop_it() -> void:
	var main := _main()
	var diag := _enable_emulator(main)
	main.start_emulator_workout()
	var session := main.workout_screen().session()
	assert_not_null(session)
	if session == null:
		return
	_now_usec += 3_000_000
	main.workout_screen().ticker().poll()
	diag.emulator_check().button_pressed = false
	assert_false(main.emulator_enabled())
	for i in 5:
		_now_usec += 1_000_000
		main.workout_screen().ticker().poll()
	assert_eq(session.get_state(), WorkoutSession.State.RUNNING, "идущий заезд не прерывается")


# ---------------------------------------------------------------------------
# В профиль и в настройки ничего не пишется
# ---------------------------------------------------------------------------

func test_release_toggle_writes_nothing_to_profile_or_settings() -> void:
	var main := _main()
	await wait_process_frames(2)
	var before := _snapshot(_dir)
	var diag := _enable_emulator(main)
	diag.emulator_check().button_pressed = false
	diag.emulator_check().button_pressed = true
	main.app_state.navigate(AppState.Screen.HOME)
	await wait_process_frames(2)
	var after := _snapshot(_dir)
	assert_eq(after.keys().size(), before.keys().size(), "новых файлов нет (кроме журнала): %s" % str(after.keys()))
	for path: String in before:
		assert_true(after.has(path), path + " на месте")
		if after.has(path):
			assert_eq(after[path], before[path], path + ": не изменён переключателем")


# ---------------------------------------------------------------------------
# П.3 карточки: пометка «Эмулятор» на HUD
# ---------------------------------------------------------------------------

func test_card_p3_hud_shows_emulator_mark_during_release_emulator_ride() -> void:
	var main := _main()
	_enable_emulator(main)
	main.start_emulator_workout()
	assert_eq(main.app_state.current_screen, AppState.Screen.WORKOUT)
	await wait_process_frames(2)
	var mark := TranslationServer.translate("ui.plan.trainer_choice.emulator")  # «Эмулятор» / "Emulator"
	var found := false
	var texts := _visible_texts(main.workout_screen())
	assert_gt(texts.size(), 0, "на HUD есть видимые надписи (проверка самого теста)")
	for t in texts:
		if t.containsn(mark):
			found = true
	assert_true(found, "карточка T-150 п.3: «пока эмулятор включён, на экране плана и на HUD видна пометка „Эмулятор“» — "
		+ "на HUD тренировки нет видимого текста «%s»" % mark)


# ---------------------------------------------------------------------------
# П.5 карточки: переводы ru/en
# ---------------------------------------------------------------------------

func test_card_p5_switch_texts_ru_en() -> void:
	var main := _main()
	var diag := _enable_emulator(main)
	for pair: Array in [["ru", "Эмулятор станка"], ["en", "Trainer emulator"]]:
		TranslationServer.set_locale(str(pair[0]))
		diag.render_texts()
		var texts := _visible_texts(diag)
		assert_true(texts.has(str(pair[1])), "%s: подпись строки «%s» видна: %s" % [pair[0], pair[1], str(texts)])
		var hint := TranslationServer.translate("ui.settings.emulator_hint")
		assert_ne(hint, "ui.settings.emulator_hint", "%s: пояснение переведено" % pair[0])
		assert_true(texts.has(hint), "%s: пояснение видно" % pair[0])


# ---------------------------------------------------------------------------
# Повтор приёмки после 33f7d34: п.3 — свободная езда, ru/en, настоящий станок без пометки
# ---------------------------------------------------------------------------

func test_card_p3_free_ride_hud_shows_emulator_chip_ru_en() -> void:
	var main := _main()
	_enable_emulator(main)
	assert_true(main.start_free_ride_on_emulator(RouteCatalog.FLAT, 50), "свободная езда на эмуляторе стартует")
	assert_eq(main.app_state.current_screen, AppState.Screen.FREE_RIDE)
	for pair: Array in [["ru", "ЭМУЛЯТОР"], ["en", "EMULATOR"]]:
		TranslationServer.set_locale(str(pair[0]))
		main.free_ride_screen().refresh()
		await wait_process_frames(2)
		var texts := _visible_texts(main.free_ride_screen())
		assert_true(texts.has(str(pair[1])), "%s: на HUD свободной езды видна фишка «%s»: %s" % [pair[0], pair[1], str(texts)])
		assert_false(texts.has("СТАНОК") or texts.has("TRAINER"), "%s: вместо фишки «СТАНОК», а не рядом" % pair[0])


func test_card_p3_workout_hud_emulator_chip_ru_en_and_real_trainer_has_none() -> void:
	var main := _main()
	_enable_emulator(main)
	main.start_emulator_workout()
	for pair: Array in [["ru", "ЭМУЛЯТОР"], ["en", "EMULATOR"]]:
		TranslationServer.set_locale(str(pair[0]))
		main.workout_screen().refresh()
		await wait_process_frames(2)
		var texts := _visible_texts(main.workout_screen())
		assert_true(texts.has(str(pair[1])), "%s: фишка «%s» на HUD тренировки: %s" % [pair[0], pair[1], str(texts)])
	# Настоящий станок (через менеджер подключений, не эмулятор) — пометки нет.
	var main2: AppMain = load(MAIN_SCENE).instantiate()
	main2.data_dir = _dir
	main2.debug_build = false
	main2.trainer_kind = TrainerFactory.KIND_BLE
	main2.transport = MockHttpTransport.new()
	main2.env_reader = Callable()
	add_child_autofree(main2)
	main2.free_ride_screen().clock_usec = _clock
	main2.free_ride_screen().keep_awake_setter = _ignore
	var stub := main2.bridge as StubBleBridge
	stub.set_device_services("real", {BleUuids.FTMS_SERVICE: PackedStringArray([BleUuids.INDOOR_BIKE_DATA,
		BleUuids.FTMS_STATUS, BleUuids.FTMS_CONTROL_POINT])})
	main2.connections.connect_trainer("real")
	stub.pump()
	assert_true(main2.is_trainer_ready(), "предусловие: станок подключён")
	assert_false(main2.connections.session_device().is_emulator(), "предусловие: это не эмулятор")
	assert_true(main2.start_free_ride(RouteCatalog.FLAT, 50))
	TranslationServer.set_locale("en")
	main2.free_ride_screen().refresh()
	await wait_process_frames(2)
	var texts2 := _visible_texts(main2.free_ride_screen())
	assert_false(texts2.has("EMULATOR"), "у настоящего станка фишки «EMULATOR» нет: %s" % str(texts2))
	assert_true(texts2.has("TRAINER"), "фишка «TRAINER» на месте")
