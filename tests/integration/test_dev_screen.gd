extends GutTest
## Интеграционные тесты экрана разработчика (REQ-DEV-09 крит. 6, REQ-WRK-01 крит. 5, REQ-NFR-02 крит. 1):
## прогон тестового плана на эмуляторе через `TrainerFactory.create("fake")` и `SessionTicker`
## с подставленными часами.

const SCENE: String = "res://src/ui/dev/dev_screen.tscn"
const MAIN_SCENE: String = "res://src/app/main.tscn"

var _now_usec: int = 0
var _dir: String
var _repo: ProfileRepository
var _state: AppState


func before_each() -> void:
	_now_usec = 5_000_000
	_dir = "user://test_dev_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_repo = ProfileRepository.new(_dir + "profiles/")
	_state = AppState.new(_repo)
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


## Продвинуть подставленные часы на `real_sec` реального времени и опросить тикер.
func _advance(screen: DevScreen, real_sec: float) -> void:
	_now_usec += int(round(real_sec * 1_000_000.0))
	screen.ticker().poll()


func _screen() -> DevScreen:
	var s: DevScreen = load(SCENE).instantiate()
	s.clock_usec = _clock
	s.setup(_state, 200)
	add_child_autofree(s)
	return s


func _count(screen: DevScreen, type: String) -> int:
	var n := 0
	for c in screen.commands():
		if str((c as Dictionary).get("type", "")) == type:
			n += 1
	return n


func test_initial_state_has_no_session_and_disabled_controls() -> void:
	var s := _screen()
	assert_null(s.session())
	assert_eq(s.status_text(), "No session — press “Play on emulator”")
	assert_true((s.get_node("%PauseButton") as Button).disabled)
	assert_false((s.get_node("%PlayButton") as Button).disabled)


func test_play_creates_connected_trainer_session_and_ticker_x10() -> void:
	var s := _screen()
	assert_true(s.play())
	assert_not_null(s.trainer())
	assert_true(s.trainer() is TrainerDevice)
	assert_eq(s.trainer().get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(s.session().get_state(), WorkoutSession.State.RUNNING)
	assert_true(s.ticker().is_running())
	assert_eq(s.ticker().time_scale, 10.0)
	assert_true(s.ticker().is_inside_tree())
	assert_eq(_count(s, "target_power"), 1, "первая цель ушла на старте")
	assert_true(s.status_text().begins_with("State: running (connected) · step 1/3 · target 100 W"), s.status_text())


func test_200_seconds_of_session_time_finish_plan_with_3_target_commands() -> void:
	var s := _screen()
	s.play()
	_advance(s, 20.0)  # ×10 → 200 с сессионного времени, план 180 с
	assert_eq(s.session().get_state(), WorkoutSession.State.FINISHED, "REQ-WRK-01 крит. 5 / REQ-DEV-09 крит. 6")
	assert_eq(_count(s, "target_power"), 3, "по одной цели на шаг: 100, 200, 120 Вт")
	var values: Array[int] = []
	for c in s.commands():
		if str((c as Dictionary).get("type", "")) == "target_power":
			values.append(int((c as Dictionary)["value"]))
	assert_eq(values, [100, 200, 120])
	assert_eq(s.session().samples.size(), 180)
	assert_true(s.status_text().begins_with("State: finished"), s.status_text())
	assert_string_contains(s.status_text(), "samples 180")
	assert_string_contains(s.commands_text(), "target_power")


func test_status_text_updates_as_time_passes() -> void:
	var s := _screen()
	s.play()
	_advance(s, 0.5)  # 5 с
	assert_string_contains(s.status_text(), "time 00:05")
	assert_string_contains(s.status_text(), "samples 5")
	_advance(s, 6.0)  # ещё 60 с → 65 с, второй шаг
	assert_string_contains(s.status_text(), "step 2/3")
	assert_string_contains(s.status_text(), "target 200 W")
	assert_string_contains(s.status_text(), "time 01:05")
	assert_false(s.status_text().contains("power — W"), "мощность эмулятора отображается")


func test_pause_and_resume_toggle() -> void:
	var s := _screen()
	s.play()
	_advance(s, 1.0)
	s.toggle_pause()
	assert_eq(s.session().get_state(), WorkoutSession.State.PAUSED)
	assert_eq((s.get_node("%PauseButton") as Button).text, "Resume")
	var before := s.session().executor.elapsed_sec()
	_advance(s, 5.0)
	assert_eq(s.session().executor.elapsed_sec(), before, "на паузе исполнитель стоит")
	assert_string_contains(s.status_text(), "State: paused")
	s.toggle_pause()
	assert_eq(s.session().get_state(), WorkoutSession.State.RUNNING)
	assert_eq((s.get_node("%PauseButton") as Button).text, "Pause")


func test_skip_advances_step() -> void:
	var s := _screen()
	s.play()
	_advance(s, 0.1)
	s.skip()
	assert_eq(s.session().executor.current_step_index(), 1)
	assert_eq(_count(s, "target_power"), 2)
	assert_string_contains(s.status_text(), "step 2/3")


func test_stop_finishes_early_and_stops_ticker() -> void:
	var s := _screen()
	s.play()
	_advance(s, 1.0)
	s.stop()
	assert_eq(s.session().get_state(), WorkoutSession.State.FINISHED)
	assert_false(s.ticker().is_running())
	var elapsed := s.session().executor.elapsed_sec()
	_advance(s, 5.0)
	assert_eq(s.session().executor.elapsed_sec(), elapsed)


func test_toggle_erg_sends_commands_and_updates_button() -> void:
	var s := _screen()
	s.play()
	_advance(s, 0.1)
	s.toggle_erg()
	assert_false(s.session().erg_enabled)
	assert_eq(_count(s, "erg"), 1)
	assert_eq(_count(s, "resistance"), 1)
	assert_eq((s.get_node("%ErgButton") as Button).text, "ERG on")
	assert_string_contains(s.status_text(), "ERG off")
	s.toggle_erg()
	assert_true(s.session().erg_enabled)
	assert_eq(_count(s, "erg"), 2)


func test_commands_text_shows_last_five() -> void:
	var s := _screen()
	s.play()
	for i in 4:
		s.toggle_erg()
	assert_gt(s.commands().size(), 5)
	var lines := s.commands_text().split("\n")
	assert_eq(lines.size(), 1 + DevScreen.COMMANDS_SHOWN, "заголовок + 5 последних")
	assert_eq(lines[0], "Last trainer commands (time; type; value):")


func test_play_again_restarts_run() -> void:
	var s := _screen()
	s.play()
	_advance(s, 3.0)
	var first_trainer := s.trainer()
	assert_true(s.play())
	assert_ne(s.trainer(), first_trainer)
	assert_eq(s.session().executor.elapsed_sec(), 0)
	assert_eq(_count(s, "target_power"), 1)
	assert_eq(first_trainer.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED, "старый эмулятор отключён")


func test_back_navigates_home_when_profile_chosen() -> void:
	_repo.create("Dev")
	_state.start()
	_state.navigate(AppState.Screen.DEV)
	var s := _screen()
	s.back()
	assert_eq(_state.current_screen, AppState.Screen.HOME)


func test_main_scene_wires_dev_screen_with_profile_ftp() -> void:
	var p := _repo.create("Dev")
	p.ftp_w = 250
	_repo.save(p)
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	add_child_autofree(main)
	assert_true(main.app_state.navigate(AppState.Screen.DEV))
	var dev := main.visible_screen_node()
	assert_true(dev is DevScreen)
	assert_eq((dev as DevScreen).ftp_w, 250, "FTP активного профиля")
	(dev as DevScreen).clock_usec = _clock
	assert_true((dev as DevScreen).play())
	_advance(dev as DevScreen, 0.1)
	assert_string_contains((dev as DevScreen).status_text(), "target 125 W")
	(dev as DevScreen).stop()
