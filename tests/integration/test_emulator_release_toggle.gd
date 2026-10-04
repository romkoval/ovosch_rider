extends GutTest
## T-EMU: эмулятор станка в release-сборке через скрытую строку разработчика «О программе»
## (REQ-DEV-09 крит. 6 — симулятор в приложении для проигрывания без железа; REQ-FRD-01 крит. 4 —
## эмулятор в диалоге свободной езды). Release-сборка имитируется `AppMain.debug_build = false`
## до входа оболочки в дерево:
## - по умолчанию в release эмулятора нет нигде (главный, выбор тренировки, диалог свободной езды);
## - строка «Эмулятор станка» скрыта до пятого нажатия на «Версию»;
## - включение открывает «Режим разработки»/«На эмуляторе» главного, «На эмуляторе» и «Эмулятор»
##   выбора тренировки, «Эмулятор» диалога свободной езды — и в уже открытом диалоге; тренировка и
##   свободная езда идут на `FakeTrainer`; переключение — в журнале;
## - выключение убирает всё обратно; после перезапуска оболочки эмулятор снова выключен;
## - в отладочной сборке эмулятор включён всегда, переключатель недоступен.

const MAIN_SCENE: String = "res://src/app/main.tscn"
const EVENT: String = "emulator"

var _dir: String
var _previous_locale: String
var _now_usec: int = 0


func before_each() -> void:
	_dir = "user://test_emulator_release_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
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


func _main(debug_build: bool = false) -> AppMain:
	var repo := ProfileRepository.new(_dir + "profiles/")
	if repo.list().is_empty():
		repo.create("Solo")
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.debug_build = debug_build
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


## Пять нажатий на строку «Версия» — открыть строки разработчика.
func _unlock(main: AppMain) -> AboutDiagnostics:
	main.app_state.navigate(AppState.Screen.SETTINGS)
	var settings := main.settings_screen()
	var version_row := (settings.get_node("%VersionLabel") as Control).get_parent() as Control
	for i in AboutDiagnostics.UNLOCK_TAPS:
		version_row.gui_input.emit(_click())
	return settings.diagnostics()


## Кнопки разработки главного экрана (ряд на широком окне или «⋯» на compact).
static func _home_dev_shown(main: AppMain) -> bool:
	var home := main.home_screen()
	return (home.get_node("%DevRow") as Control).visible or (home.get_node("%DevMenuButton") as Control).visible


static func _plan_dialog(main: AppMain) -> ConfirmationDialog:
	return main.plan_screen().get_node("%TrainerDialog") as ConfirmationDialog


static func _plan_dialog_emulator(main: AppMain) -> Button:
	var dialog := _plan_dialog(main)
	for child in dialog.find_children("*", "Button", true, false):
		if (child as Button).text == TranslationServer.translate("ui.plan.trainer_choice.emulator"):
			return child
	return null


## Записи журнала события `ev`.
func _records(ev: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var logs := _dir + "logs/"
	var d := DirAccess.open(logs)
	if d == null:
		return out
	var names := Array(d.get_files())
	names.sort()
	for f: String in names:
		for line in FileAccess.get_file_as_string(logs + f).split("\n", false):
			var parsed: Variant = JSON.parse_string(line)
			if parsed is Dictionary and (parsed as Dictionary).get("ev", "") == ev:
				out.append(parsed)
	return out


func _assert_emulator_everywhere(main: AppMain, shown: bool, what: String) -> void:
	assert_eq(main.emulator_enabled(), shown, "%s: признак оболочки" % what)
	assert_eq(main.home_screen().dev_tools_enabled, shown, "%s: главный — «На эмуляторе»/«Режим разработки»" % what)
	assert_eq(_home_dev_shown(main), shown, "%s: кнопки разработки главного" % what)
	var plan := main.plan_screen()
	assert_eq(plan.dev_tools_enabled, shown, "%s: экран выбора тренировки" % what)
	assert_eq(plan.emulator_start_button().visible, shown, "%s: «На эмуляторе» на плане" % what)
	assert_not_null(_plan_dialog_emulator(main), "кнопка «Эмулятор» в диалоге выбора станка есть")
	assert_eq(_plan_dialog_emulator(main).visible, shown, "%s: «Эмулятор» в диалоге выбора станка" % what)
	assert_not_null(main.free_ride_emulator_button(), "кнопка «Эмулятор» в диалоге свободной езды есть всегда")
	assert_eq(main.free_ride_emulator_button().visible, shown, "%s: «Эмулятор» в диалоге свободной езды" % what)


# ---------------------------------------------------------------------------

func test_release_default_has_no_emulator_anywhere() -> void:
	var main := _main()
	assert_false(main.debug_build, "имитация release-сборки")
	_assert_emulator_everywhere(main, false, "release по умолчанию")
	main.plan_screen().show_trainer_choice()
	assert_eq(_plan_dialog(main).dialog_text, tr("ui.plan.trainer_choice.text_release"), "текст зовёт только к устройствам")
	_plan_dialog(main).hide()
	assert_false(main.start_free_ride(RouteCatalog.FLAT, 50))
	assert_true(main.free_ride_trainer_dialog().visible, "пояснение «станок не подключён»")
	assert_false(main.choose_free_ride_emulator(), "в release без включения эмулятора нет")
	assert_null(main.free_ride_screen().session(), "сессия не создана")
	main.free_ride_trainer_dialog().hide()


func test_emulator_row_hidden_until_fifth_tap() -> void:
	var main := _main()
	assert_true(main.app_state.navigate(AppState.Screen.SETTINGS))
	var settings := main.settings_screen()
	var diag := settings.diagnostics()
	assert_false(diag.emulator_check().is_visible_in_tree(), "строка скрыта в обычном меню")
	var version_row := (settings.get_node("%VersionLabel") as Control).get_parent() as Control
	for i in AboutDiagnostics.UNLOCK_TAPS - 1:
		version_row.gui_input.emit(_click())
	assert_false(diag.emulator_check().is_visible_in_tree(), "четырёх нажатий мало")
	version_row.gui_input.emit(_click())
	assert_true(diag.emulator_check().is_visible_in_tree(), "пятое нажатие открывает строку")
	assert_false(diag.emulator_check().button_pressed, "в release по умолчанию выключено")
	assert_false(diag.emulator_check().disabled, "в release переключатель доступен")
	assert_eq(main.emulator_enabled(), false, "открытие строк само эмулятор не включает")


func test_toggle_on_in_release_shows_emulator_and_logs() -> void:
	var main := _main()
	var diag := _unlock(main)
	diag.emulator_check().button_pressed = true
	_assert_emulator_everywhere(main, true, "после включения")
	main.plan_screen().show_trainer_choice()
	assert_eq(_plan_dialog(main).dialog_text, tr("ui.plan.trainer_choice.text"), "текст предлагает эмулятор")
	_plan_dialog(main).hide()
	var records := _records(EVENT)
	assert_eq(records.size(), 1, "включение — одна запись журнала")
	if records.size() == 1:
		assert_eq(records[0].get("cat", ""), DiagLog.CAT_APP, "категория приложения")
		assert_eq((records[0].get("data", {}) as Dictionary).get("enabled", null), true)


func test_enabled_in_release_workout_from_plan_dialog_runs_on_fake_trainer() -> void:
	var main := _main()
	_unlock(main).emulator_check().button_pressed = true
	assert_false(main.start_workout(DevScreen.test_workout()), "станка нет — выбор станка")
	assert_true(_plan_dialog(main).visible, "диалог выбора станка открыт")
	_plan_dialog(main).custom_action.emit(PlanScreen.TRAINER_ACTION_EMULATOR)
	var session := main.workout_screen().session()
	assert_not_null(session, "тренировка запущена")
	assert_true(session.trainer is FakeTrainer, "станок сессии — эмулятор")
	assert_eq(main.app_state.current_screen, AppState.Screen.WORKOUT)
	_now_usec += 3_000_000
	main.workout_screen().ticker().poll()
	assert_eq(session.get_state(), WorkoutSession.State.RUNNING, "тренировка идёт")


func test_enabled_in_release_home_emulator_button_runs_workout() -> void:
	var main := _main()
	_unlock(main).emulator_check().button_pressed = true
	main.app_state.navigate(AppState.Screen.HOME)
	(main.home_screen().get_node("%EmulatorWorkoutButton") as Button).pressed.emit()
	var session := main.workout_screen().session()
	assert_not_null(session, "«Тренировка на эмуляторе» с главного")
	assert_true(session.trainer is FakeTrainer)


func test_toggle_while_free_ride_dialog_open_updates_and_starts_on_emulator() -> void:
	var main := _main()
	var diag := _unlock(main)
	main.app_state.navigate(AppState.Screen.HOME)
	assert_false(main.start_free_ride(RouteCatalog.HILLS, 50))
	var dialog := main.free_ride_trainer_dialog()
	assert_true(dialog.visible)
	assert_false(main.free_ride_emulator_button().visible, "до включения «Эмулятора» нет")
	diag.emulator_check().button_pressed = true
	assert_true(main.free_ride_emulator_button().visible, "в открытом диалоге кнопка появилась")
	dialog.custom_action.emit(&"emulator")
	assert_false(dialog.visible, "диалог закрыт")
	var session := main.free_ride_screen().session()
	assert_not_null(session, "свободная езда запущена")
	assert_true(session.trainer is FakeTrainer, "станок — эмулятор")
	assert_eq(main.app_state.current_screen, AppState.Screen.FREE_RIDE)


func test_toggle_off_hides_emulator_again_and_logs() -> void:
	var main := _main()
	var diag := _unlock(main)
	diag.emulator_check().button_pressed = true
	main.plan_screen().show_trainer_choice()
	diag.emulator_check().button_pressed = false
	_assert_emulator_everywhere(main, false, "после выключения")
	assert_eq(_plan_dialog(main).dialog_text, tr("ui.plan.trainer_choice.text_release"), "открытый диалог обновлён")
	_plan_dialog(main).custom_action.emit(PlanScreen.TRAINER_ACTION_EMULATOR)
	assert_null(main.workout_screen().session(), "действие эмулятора не выполняется")
	_plan_dialog(main).hide()
	main.start_free_ride(RouteCatalog.FLAT, 50)
	assert_false(main.choose_free_ride_emulator(), "свободная езда на эмуляторе недоступна")
	main.free_ride_trainer_dialog().hide()
	var records := _records(EVENT)
	assert_eq(records.size(), 2, "включение и выключение — две записи")
	if records.size() == 2:
		assert_eq((records[1].get("data", {}) as Dictionary).get("enabled", null), false)


func test_not_persisted_after_shell_restart() -> void:
	var main := _main()
	_unlock(main).emulator_check().button_pressed = true
	assert_true(main.emulator_enabled())
	main.queue_free()
	await wait_process_frames(2)
	var again := _main()
	_assert_emulator_everywhere(again, false, "после перезапуска")
	assert_false(_unlock(again).emulator_check().button_pressed, "переключатель снова выключен")


func test_debug_build_emulator_always_on_and_switch_locked() -> void:
	var main := _main(true)
	_assert_emulator_everywhere(main, true, "отладочная сборка")
	var check := _unlock(main).emulator_check()
	assert_true(check.button_pressed, "в отладке включён")
	assert_true(check.disabled, "в отладке выключить нельзя")
