extends GutTest
## T-153 (минимум): езда по датчику мощности без управляемого станка — HUD без органов управления
## станком и текст диалога «Станок не подключён» (REQ-WRK-09 п.2 (г), п.5 (д), (е), п.7, п.10).
## - Панель инструментов в `power_meter`: нет ERG, сопротивления, SIM ↔ сопротивление и крутизны;
##   E без действия; `+`/`−` в плане — интенсивность (цель меняется), в свободной езде — ничего;
##   журнал моста симулятора CPS пуст.
## - Фишка режима — «БЕЗ СТАНКА» вместо «ERG» / «SIM»; в `smart` всё как прежде.
## - Нет ни станка, ни датчика мощности — диалог с текстом «Нужен станок или датчик мощности».

const WORKOUT_SCENE: String = "res://src/ui/workout/workout_screen.tscn"
const FREE_RIDE_SCENE: String = "res://src/ui/free_ride/free_ride_screen.tscn"
const TOOLBAR_SCENE: String = "res://src/ui/hud/hud_toolbar.tscn"
const MAIN_SCENE: String = "res://src/app/main.tscn"

var _now_usec: int = 0
var _profile: Profile
var _state: AppState
var _dir: String
var _locale_before: String
var _devices: Array[TrainerDevice] = []
var _mains: Array[AppMain] = []


func before_each() -> void:
	_locale_before = TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	_now_usec = 5_000_000
	_dir = "user://test_power_meter_hud_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	_state = AppState.new(ProfileRepository.new(_dir + "profiles/"))
	_profile = Profile.create("Rider")
	_profile.ftp_w = 200
	_devices = []
	_mains = []


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


func _clock() -> int:
	return _now_usec


func _no_keep(_on: bool) -> void:
	pass


func _power_meter() -> TrainerDevice:
	var device := TrainerFactory.create_power_meter_emulator()
	_devices.append(device)
	return device


func _smart_trainer() -> FakeTrainer:
	var t := FakeTrainer.new(7)
	t.connect_delay_sec = 0.0
	t.connect_device("smart")
	return t


func _workout_screen(device: TrainerDevice) -> WorkoutScreen:
	var s: WorkoutScreen = load(WORKOUT_SCENE).instantiate()
	s.clock_usec = _clock
	s.keep_awake_setter = _no_keep
	add_child_autofree(s)
	s.setup(DevScreen.test_workout(), _profile, device, _state)
	assert_true(s.start(), "тренировка запущена")
	return s


func _free_ride_screen(device: TrainerDevice) -> FreeRideScreen:
	var s: FreeRideScreen = load(FREE_RIDE_SCENE).instantiate()
	s.clock_usec = _clock
	s.keep_awake_setter = _no_keep
	add_child_autofree(s)
	s.setup(_state, _profile, device, RouteCatalog.MOUNTAINS, 50)
	assert_true(s.start(), "свободная езда запущена")
	return s


func _toolbar(mode: HudToolbar.Mode) -> HudToolbar:
	var t: HudToolbar = load(TOOLBAR_SCENE).instantiate()
	add_child_autofree(t)
	t.set_mode(mode)
	return t


## Видимые кнопки панели по именам — в порядке раскладки (сверху вниз, слева направо).
func _ids(toolbar: HudToolbar) -> Array[StringName]:
	var out: Array[StringName] = []
	for b in toolbar.visible_buttons():
		for id: StringName in [&"erg", &"sim", &"intensity_down", &"intensity_up", &"resistance_down",
				&"resistance_up", &"steepness_down", &"steepness_up", &"skip", &"finish"]:
			if toolbar.button(id) == b:
				out.append(id)
	return out


static func _write_calls(device: TrainerDevice) -> Array[Dictionary]:
	return TrainerFactory.power_meter_emulator_sensor(device).stub.calls_of("write")


# ---------------------------------------------------------------------------
# Панель инструментов
# ---------------------------------------------------------------------------

func test_req_wrk_09_c5_d_plan_toolbar_without_trainer_controls() -> void:
	var t := _toolbar(HudToolbar.Mode.PLAN)
	assert_true(t.controls_trainer(), "по умолчанию — со станком")
	assert_true(_ids(t).has(&"erg"), "smart: ERG на панели")
	t.set_controls_trainer(false)
	t.set_erg_enabled(false)
	assert_eq(_ids(t), [&"intensity_down", &"intensity_up", &"skip", &"finish"] as Array[StringName],
		"только интенсивность, «Пропустить шаг», «Завершить» — ERG и сопротивления нет даже при ERG выкл")
	watch_signals(t)
	assert_false(t.trigger(HudToolbar.ACTION_TOGGLE), "E ничего не делает")
	assert_signal_not_emitted(t, "erg_toggle_requested")
	assert_true(t.trigger(HudToolbar.ACTION_PLUS), "`+` — интенсивность")
	assert_signal_emitted_with_parameters(t, "intensity_step_requested", [HudToolbar.INTENSITY_STEP_PCT])
	assert_signal_not_emitted(t, "resistance_step_requested")
	t.set_compact(true)
	assert_eq(t.button_row_count(), 2, "телефон: два ряда")
	assert_eq(_ids(t), [&"skip", &"finish", &"intensity_down", &"intensity_up"] as Array[StringName],
		"телефон: ряд «Пропустить шаг» · «Завершить», под ним интенсивность")
	t.set_controls_trainer(true)
	assert_true(_ids(t).has(&"erg"), "со станком ERG возвращается")


func test_req_wrk_09_c7_free_ride_toolbar_only_finish() -> void:
	var t := _toolbar(HudToolbar.Mode.FREE_RIDE)
	t.set_controls_trainer(false)
	assert_eq(_ids(t), [&"finish"] as Array[StringName], "только «Завершить»")
	t.set_compact(true)
	assert_eq(_ids(t), [&"finish"] as Array[StringName], "и на телефоне")
	watch_signals(t)
	for action: StringName in [HudToolbar.ACTION_TOGGLE, HudToolbar.ACTION_PLUS, HudToolbar.ACTION_MINUS]:
		assert_false(t.trigger(action), "E и `+`/`−` ничего не делают: %s" % action)
	for sig: String in ["sim_toggle_requested", "steepness_step_requested", "resistance_step_requested"]:
		assert_signal_not_emitted(t, sig)
	assert_true(t.trigger(HudToolbar.ACTION_PAUSE), "Esc — как прежде")


# ---------------------------------------------------------------------------
# Экран тренировки
# ---------------------------------------------------------------------------

func test_req_wrk_09_c5_d_e_workout_screen_power_meter() -> void:
	var device := _power_meter()
	var s := _workout_screen(device)
	assert_eq(s.session().trainer_mode, TrainerDevice.MODE_POWER_METER)
	var toolbar := s.toolbar()
	assert_false(toolbar.controls_trainer())
	assert_false(toolbar.visible_buttons().has(toolbar.button(&"erg")), "кнопки ERG нет")
	assert_false(toolbar.visible_buttons().has(toolbar.button(&"resistance_up")), "сопротивления нет")
	assert_false(s.is_resistance_row_visible())
	assert_eq(s.mode_chip_text(), "БЕЗ СТАНКА", "фишка режима вместо «ERG»")
	assert_eq(s.mode_chip_text(), tr("ui.hud.status.no_trainer"))
	var events_before := s.session().events.size()
	toolbar.trigger(HudToolbar.ACTION_TOGGLE)
	assert_false(s.session().erg_enabled, "E не включает ERG")
	assert_eq(s.session().events.size(), events_before, "E не пишет событий")
	var target_before := s.session().current_target_watts()
	toolbar.trigger(HudToolbar.ACTION_PLUS)
	assert_almost_eq(s.session().intensity(), 1.05, 0.001, "`+` — интенсивность 105 %")
	assert_gt(target_before, 0, "предусловие: у шага есть цель")
	assert_almost_eq(s.session().current_target_watts(), roundi(target_before * 1.05), 1, "цель с множителем")
	assert_eq(s.target_text(), tr("ui.workout.target_value").format({"value": str(s.session().current_target_watts())}),
		"цель в карточке обновлена")
	for i in 10:
		_now_usec += 1_000_000
		s.ticker().poll()
	assert_eq(_write_calls(device), [] as Array[Dictionary], "журнал моста: ни одной записи")


func test_req_wrk_09_c5_e_workout_screen_smart_unchanged() -> void:
	var s := _workout_screen(_smart_trainer())
	assert_true(s.toolbar().controls_trainer())
	assert_true(s.toolbar().visible_buttons().has(s.toolbar().button(&"erg")), "ERG на месте")
	assert_eq(s.mode_chip_text(), tr("ui.hud.status.erg"), "фишка «ERG» как прежде")


func test_req_wrk_09_c10_no_trainer_chip_en() -> void:
	TranslationServer.set_locale("en")
	var s := _workout_screen(_power_meter())
	assert_eq(s.mode_chip_text(), "NO TRAINER")


# ---------------------------------------------------------------------------
# Свободная езда
# ---------------------------------------------------------------------------

func test_req_wrk_09_c7_free_ride_screen_power_meter() -> void:
	var device := _power_meter()
	var s := _free_ride_screen(device)
	assert_eq(s.session().trainer_mode, TrainerDevice.MODE_POWER_METER)
	assert_eq(_ids(s.toolbar()), [&"finish"] as Array[StringName], "только «Завершить»")
	assert_eq(s.mode_chip_text(), "БЕЗ СТАНКА", "фишка режима вместо «SIM»")
	var steepness := s.session().steepness_pct()
	s.toolbar().trigger(HudToolbar.ACTION_TOGGLE)
	s.toolbar().trigger(HudToolbar.ACTION_PLUS)
	assert_eq(s.session().steepness_pct(), steepness, "`+` не меняет крутизну")
	for i in 10:
		_now_usec += 1_000_000
		s.ticker().poll()
	assert_false(s.is_notice_visible(), "сообщения «станок не поддерживает SIM» нет")
	assert_eq(_write_calls(device), [] as Array[Dictionary], "ни одной SIM-команды")


func test_req_wrk_09_c7_free_ride_screen_smart_unchanged() -> void:
	var s := _free_ride_screen(_smart_trainer())
	assert_true(_ids(s.toolbar()).has(&"sim"), "SIM ↔ сопротивление на месте")
	assert_eq(s.mode_chip_text(), tr("ui.free_ride.status.sim"))


# ---------------------------------------------------------------------------
# Диалог «Станок не подключён» без источника мощности
# ---------------------------------------------------------------------------

func _main(debug: bool) -> AppMain:
	var settings := AppSettings.new(_dir + "settings.json")
	settings.locale = "ru"
	settings.save()
	var repo := ProfileRepository.new(_dir + "profiles/")
	repo.create("Даша")
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	main.debug_build = debug
	add_child(main)
	main.set_process(false)
	_mains.append(main)
	main.app_state.select_profile(main.repo.list()[0].id)
	return main


func test_req_wrk_09_c2_g_no_power_source_dialog_text() -> void:
	var main := _main(false)
	assert_false(main.can_start_session(), "предусловие: нет ни станка, ни датчика")
	assert_false(main.start_free_ride(RouteCatalog.FLAT, 50), "свободная езда не стартует")
	var free_dialog := main.free_ride_trainer_dialog()
	assert_true(free_dialog.visible, "диалог «Станок не подключён»")
	assert_eq(tr(free_dialog.title), "Станок не подключён")
	assert_eq(tr(free_dialog.dialog_text), "Нужен станок или датчик мощности. Подключите их на экране «Устройства».")
	free_dialog.hide()
	assert_false(main.start_workout(DevScreen.test_workout()), "план не стартует")
	var plan_dialog := main.plan_screen().get_node("%TrainerDialog") as ConfirmationDialog
	assert_true(plan_dialog.visible)
	assert_eq(plan_dialog.dialog_text, "Нужен станок или датчик мощности. Подключите их на экране «Устройства».",
		"release: текст зовёт к устройствам")
	plan_dialog.hide()


func test_req_wrk_09_c2_g_no_power_source_dialog_text_en_debug() -> void:
	var main := _main(true)
	TranslationServer.set_locale("en")
	assert_false(main.start_free_ride(RouteCatalog.FLAT, 50))
	assert_eq(tr(main.free_ride_trainer_dialog().dialog_text),
		"You need a trainer or a power meter. Connect one on the Devices screen.")
	main.free_ride_trainer_dialog().hide()
	assert_false(main.start_workout(DevScreen.test_workout()))
	var plan_dialog := main.plan_screen().get_node("%TrainerDialog") as ConfirmationDialog
	assert_eq(plan_dialog.dialog_text,
		"You need a trainer or a power meter. Connect one on the Devices screen or ride on the emulator.",
		"отладочная сборка: прежняя кнопка «Эмулятор» и упоминание эмулятора")
	plan_dialog.hide()
