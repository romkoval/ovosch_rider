extends GutTest
## Интеграционные тесты экрана тренировки (REQ-HUD-01..09, REQ-WRK-03 крит. 1, REQ-WRK-04 крит. 1,
## REQ-WRK-05 крит. 4, REQ-WRK-06, REQ-WRK-07, REQ-NFR-04 крит. 1, 2, REQ-NFR-08 крит. 1).
## Сцена инстанцируется headless, время — через подставленные часы тикера.

const SCENE: String = "res://src/ui/workout/workout_screen.tscn"
const MAIN_SCENE: String = "res://src/app/main.tscn"

var _now_usec: int = 0
var _keep_calls: Array[bool] = []
var _trainer: FakeTrainer
var _profile: Profile
var _state: AppState
var _repo: ProfileRepository
var _dir: String


func before_each() -> void:
	_now_usec = 7_000_000
	_keep_calls = []
	_dir = "user://test_wscreen_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_repo = ProfileRepository.new(_dir + "profiles/")
	_state = AppState.new(_repo)
	_trainer = FakeTrainer.new(21)
	_trainer.connect_delay_sec = 0.0
	_trainer.power_noise_w = 0.0
	_trainer.power_tau_sec = 0.01
	_trainer.cadence_noise_rpm = 0.0
	_trainer.connect_device("ws")
	_profile = Profile.create("Rider")
	_profile.ftp_w = 200
	_profile.max_hr = 180
	_profile.resistance_level_default = 50
	TranslationServer.set_locale("en")


func after_each() -> void:
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


func _clock() -> int:
	return _now_usec


func _keep(on: bool) -> void:
	_keep_calls.append(on)


func _screen(start: bool = true) -> WorkoutScreen:
	var s: WorkoutScreen = load(SCENE).instantiate()
	s.clock_usec = _clock
	s.keep_awake_setter = _keep
	add_child_autofree(s)
	s.setup(DevScreen.test_workout(), _profile, _trainer, _state)
	if start:
		assert_true(s.start())
	return s


func _advance(s: WorkoutScreen, sec: float) -> void:
	_now_usec += int(round(sec * 1_000_000.0))
	s.ticker().poll()


func _cmds(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in _trainer.commands:
		if c["type"] == type:
			out.append(c)
	return out


func test_without_setup_shows_no_session_placeholder() -> void:
	var s: WorkoutScreen = load(SCENE).instantiate()
	add_child_autofree(s)
	assert_false(s.start(), "без плана старт невозможен")
	assert_true((s.get_node("%NoSessionLabel") as Label).visible)
	assert_false(s.is_summary_visible())


func test_start_builds_session_hud_ticker_and_keep_awake() -> void:
	var s := _screen()
	assert_not_null(s.session())
	assert_eq(s.session().get_state(), WorkoutSession.State.RUNNING)
	assert_not_null(s.hud())
	assert_true(s.ticker().is_running())
	assert_true(s.ticker().get_parent() == s, "один тикер в дереве под экраном")
	assert_eq(_keep_calls, [true], "REQ-NFR-04 крит. 1: запрет гашения при старте")
	assert_eq(s.session().resistance_level, 50, "уровень из профиля")
	assert_almost_eq(s.session().intensity(), 1.0, 1e-9)


func test_hud_texts_after_65_seconds() -> void:
	var s := _screen()
	_trainer.set_heart_rate(144)
	_advance(s, 65.0)
	assert_eq(s.target_text(), "200 W", "REQ-HUD-01 крит. 1: второй шаг 100 % FTP")
	assert_eq(s.power_text(), "200 W", "REQ-HUD-02 крит. 1: сглаженная мощность эмулятора")
	assert_eq(s.deviation_text(), "●", "в цели")
	assert_eq(s.power_zone_text(), "Z4", "REQ-HUD-03: 200 Вт при FTP 200")
	assert_eq((s.get_node("%PowerZoneLabel") as Label).modulate, ZonePalette.color("z4"))
	assert_eq(s.hr_text(), "144")
	assert_eq((s.get_node("%HrZoneLabel") as Label).text, "Z4", "REQ-HUD-04 крит. 1")
	assert_eq(s.cadence_text(), "85")
	assert_true(s.speed_text().is_valid_float(), "скорость с одним знаком: %s" % s.speed_text())
	assert_eq(s.elapsed_text(), "01:05", "REQ-HUD-05 крит. 1")
	assert_eq(s.countdown_text(), "00:25", "REQ-HUD-06 крит. 1: 30 − 5")
	assert_eq(s.step_text(), "Step 2/3")
	assert_eq(s.connection_text(), "Trainer connected")
	TranslationServer.set_locale("ru")
	s.refresh()
	assert_eq(s.connection_text(), "Станок подключён", "REQ-NFR-08 крит. 1: перевод делает view при каждой отрисовке")
	TranslationServer.set_locale("en")


func test_countdown_accent_in_last_5_seconds() -> void:
	var s := _screen()
	_advance(s, 54.0)
	assert_false(s.is_countdown_accented())
	_advance(s, 1.0)
	assert_eq(s.countdown_text(), "00:05")
	assert_true(s.is_countdown_accented(), "REQ-HUD-06 крит. 2")
	_advance(s, 5.0)
	assert_eq(s.countdown_text(), "00:30", "на тике перехода — длительность нового шага")
	assert_false(s.is_countdown_accented())


## REQ-HUD-01 крит. 3 (ред. 2026-10-03): факт мощности ≥ 2× пульса и каденса; цель мельче факта,
## но не мельче пульса и каденса; скорость, время и отсчёт мельче факта.
func test_hero_power_font_largest_and_target_between_metrics() -> void:
	var s := _screen()
	var size_of := func(unique: String) -> int: return (s.get_node(unique) as Label).get_theme_font_size("font_size")
	var hero: int = size_of.call("%PowerLabel")
	var target: int = size_of.call("%TargetLabel")
	for name in ["%HrLabel", "%CadenceLabel"]:
		var metric: int = size_of.call(name)
		assert_true(hero >= 2 * metric, "REQ-HUD-01 крит. 3: факт %d ≥ 2×%d (%s)" % [hero, metric, name])
		assert_true(target >= metric, "цель %d не мельче %s %d" % [target, name, metric])
	assert_true(target < hero, "цель %d мельче факта %d" % [target, hero])
	for name in ["%SpeedLabel", "%ElapsedLabel", "%CountdownLabel"]:
		assert_true(size_of.call(name) < hero, "%s мельче факта" % name)


func test_200_seconds_finish_plan_shows_summary_and_emits_hook() -> void:
	var s := _screen()
	var finished: Array[WorkoutSession] = []
	s.session_finished.connect(func(ses: WorkoutSession) -> void: finished.append(ses))
	_advance(s, 200.0)
	assert_eq(s.session().get_state(), WorkoutSession.State.FINISHED)
	assert_true(s.is_summary_visible(), "сводка после FINISHED")
	assert_false((s.get_node("%HudRoot") as Control).visible)
	assert_string_contains(s.summary_text(), "dev-3-steps · 03:00")
	assert_string_contains(s.summary_text(), "samples 180")
	assert_string_contains(s.summary_text(), "Paused: 00:00", "общее время пауз в сводке")
	assert_false(s.summary_text().contains("ended early"))
	assert_eq(finished.size(), 1, "хук сохранения заезда")
	assert_eq(_cmds(FakeTrainer.CMD_TARGET_POWER).size(), 3)
	assert_false(s.ticker().is_running())
	assert_eq(_keep_calls, [true, false], "REQ-NFR-04 крит. 1: снятие при завершении")


func test_pause_resume_button_and_keep_awake_holds() -> void:
	var s := _screen()
	_advance(s, 3.0)
	s.toggle_pause()
	assert_eq(s.session().get_state(), WorkoutSession.State.PAUSED)
	assert_eq((s.get_node("%PauseButton") as Button).text, "Resume")
	_advance(s, 10.0)
	assert_eq(s.elapsed_text(), "00:03", "на паузе время стоит")
	assert_eq(_keep_calls, [true], "REQ-NFR-04 крит. 2: на паузе запрет сохраняется")
	var before := _trainer.commands.size()
	s.toggle_pause()
	assert_eq(s.session().get_state(), WorkoutSession.State.RUNNING)
	assert_eq(_trainer.commands.size(), before + 1, "при возобновлении — повтор цели")
	assert_eq(_cmds(FakeTrainer.CMD_TARGET_POWER).back()["value"], 100)


func test_skip_button_moves_to_next_step_and_logs_event() -> void:
	var s := _screen()
	_advance(s, 2.0)
	s.skip_step()
	assert_eq(s.session().executor.current_step_index(), 1)
	assert_eq(s.target_text(), "200 W")
	assert_eq(_cmds(FakeTrainer.CMD_TARGET_POWER).back()["value"], 200, "REQ-WRK-06 крит. 2")
	var skips := 0
	for e in s.session().events:
		if e["type"] == WorkoutSession.EVENT_SKIP:
			skips += 1
	assert_eq(skips, 1, "REQ-WRK-06 крит. 4")


func test_stop_requires_confirmation() -> void:
	var s := _screen()
	_advance(s, 4.0)
	assert_true(s.request_stop())
	assert_true(s.is_stop_confirmation_pending(), "REQ-WRK-05 крит. 4: диалог показан")
	assert_eq(s.session().get_state(), WorkoutSession.State.RUNNING, "до подтверждения не остановлено")
	s.cancel_stop()
	assert_false(s.is_stop_confirmation_pending())
	assert_eq(s.session().get_state(), WorkoutSession.State.RUNNING)
	s.request_stop()
	s.confirm_stop()
	assert_eq(s.session().get_state(), WorkoutSession.State.FINISHED)
	assert_true(s.session().metadata()["stopped_early"])
	assert_true(s.is_summary_visible())
	assert_string_contains(s.summary_text(), "ended early")
	assert_false(s.request_stop(), "после финиша стоп недоступен")


func test_erg_button_toggles_mode_shows_resistance_row_and_sends_commands() -> void:
	var s := _screen()
	_advance(s, 2.0)
	assert_false(s.is_resistance_row_visible(), "REQ-WRK-04: ползунок скрыт при ERG")
	assert_eq((s.get_node("%ErgButton") as Button).text, "ERG on")
	s.toggle_erg()
	assert_false(s.session().erg_enabled, "REQ-WRK-03 крит. 1: одно нажатие")
	assert_true(s.is_resistance_row_visible())
	assert_eq((s.get_node("%ErgButton") as Button).text, "ERG off")
	assert_eq(_cmds(FakeTrainer.CMD_ERG).back()["value"], false)
	assert_eq(_cmds(FakeTrainer.CMD_RESISTANCE).back()["value"], 50, "REQ-WRK-03 крит. 2")
	s.toggle_erg()
	assert_true(s.session().erg_enabled)
	assert_false(s.is_resistance_row_visible())
	assert_eq(_cmds(FakeTrainer.CMD_TARGET_POWER).back()["value"], 100, "REQ-WRK-03 крит. 3")


func test_resistance_plus_minus_in_steps_of_5_and_profile_update() -> void:
	var s := _screen()
	var updated: Array[Profile] = []
	s.profile_updated.connect(func(p: Profile) -> void: updated.append(p))
	_advance(s, 1.0)
	s.toggle_erg()
	s.adjust_resistance(5)
	assert_eq(s.session().resistance_level, 55)
	assert_eq(_cmds(FakeTrainer.CMD_RESISTANCE).back()["value"], 55, "REQ-WRK-04 крит. 2")
	assert_eq((s.get_node("%ResistanceLabel") as Label).text, "Resistance 55 %")
	s.adjust_resistance(-5)
	s.adjust_resistance(-5)
	assert_eq(s.session().resistance_level, 45)
	assert_eq(_profile.resistance_level_default, 45, "REQ-WRK-04 крит. 1: уровень в профиле")
	assert_eq(updated.size(), 3, "владелец получает профиль для сохранения")


func test_intensity_plus_minus_changes_target() -> void:
	var s := _screen()
	_advance(s, 1.0)
	s.adjust_intensity(0.05)
	assert_almost_eq(s.session().intensity(), 1.05, 1e-9)
	assert_eq(s.target_text(), "105 W", "REQ-WRK-07 крит. 2, 4")
	assert_eq(_cmds(FakeTrainer.CMD_TARGET_POWER).back()["value"], 105, "крит. 3: новая цель ушла")
	assert_eq((s.get_node("%IntensityLabel") as Label).text, "Intensity 105 %")
	s.adjust_intensity(-0.05)
	s.adjust_intensity(-0.05)
	assert_eq(s.target_text(), "95 W")


func test_progress_bar_has_segments_and_cursor() -> void:
	var s := _screen()
	_advance(s, 90.0)
	var bar := s.progress_bar()
	assert_eq(bar.segments().size(), 3, "REQ-HUD-07 крит. 1")
	assert_almost_eq(bar.cursor(), 0.5, 1e-9)
	assert_eq(bar.segments()[0]["status"], HudModel.SEGMENT_DONE)
	assert_eq(bar.segments()[2]["status"], HudModel.SEGMENT_CURRENT)
	assert_eq(s.hud().progress_segments().size(), 3)


func test_cue_label_shows_and_hides() -> void:
	var w := DevScreen.test_workout()
	w.steps[0].text_cues = [TextCue.make(0, "Spin easy")]
	var s: WorkoutScreen = load(SCENE).instantiate()
	s.clock_usec = _clock
	s.keep_awake_setter = _keep
	add_child_autofree(s)
	s.setup(w, _profile, _trainer, _state)
	s.start()
	assert_eq(s.cue_text(), "Spin easy", "REQ-HUD-08 крит. 1")
	assert_true((s.get_node("%CueLabel") as Label).visible)
	_advance(s, 10.0)
	assert_eq(s.cue_text(), "", "REQ-HUD-08 крит. 2")
	assert_false((s.get_node("%CueLabel") as Label).visible)


func test_screen_exit_and_enter_toggle_keep_awake_and_home_navigates() -> void:
	_repo.create("Rider")
	_state.start()
	_state.navigate(AppState.Screen.WORKOUT)
	var s := _screen()
	s.on_screen_exited()
	assert_eq(_keep_calls, [true, false], "уход с экрана снимает запрет")
	s.on_screen_entered()
	assert_eq(_keep_calls, [true, false, true])
	_advance(s, 200.0)
	s.go_home()
	assert_eq(_state.current_screen, AppState.Screen.HOME)


func test_connections_ticks_devices_toggled_around_session() -> void:
	var devices := RememberedDevices.new(_dir + "devices/")
	var manager := ConnectionManager.new(StubBleBridge.new(), devices, TrainerFactory.KIND_FAKE)
	assert_true(manager.ticks_devices)
	var s: WorkoutScreen = load(SCENE).instantiate()
	s.clock_usec = _clock
	s.keep_awake_setter = _keep
	add_child_autofree(s)
	s.setup(DevScreen.test_workout(), _profile, _trainer, _state, manager)
	s.start()
	assert_false(manager.ticks_devices, "сессия забрала тики устройств")
	_advance(s, 200.0)
	assert_true(manager.ticks_devices, "после финиша менеджер тикает сам")
	manager.dispose()


func test_main_scene_emulator_workout_button_starts_workout_screen() -> void:
	var p := _repo.create("Rider")
	p.ftp_w = 250
	_repo.save(p)
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	add_child_autofree(main)
	var home: HomeScreen = main.screen_node(AppState.Screen.HOME)
	home.emulator_workout_requested.emit()
	assert_eq(main.app_state.current_screen, AppState.Screen.WORKOUT)
	var ws := main.workout_screen()
	assert_true(main.visible_screen_node() == ws)
	assert_not_null(ws.session())
	assert_eq(ws.session().executor.ftp_w, 250, "FTP активного профиля")
	assert_eq(ws.target_text(), "125 W")
	ws.confirm_stop()
	assert_not_null(main.last_finished_session, "хук session_finished дошёл до main")
	ws.go_home()
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME)
