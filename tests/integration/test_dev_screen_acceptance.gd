extends GutTest
## Независимые интеграционные приёмочные тесты экрана разработчика (тестировщик, T-013).
## Покрытие: REQ-DEV-09 крит. 6 и REQ-WRK-01 крит. 5 (план проигрывается на эмуляторе
## без железа: 3 команды на границах, FINISHED, текст обновляется; пауза/пропуск/стоп/ERG
## через кнопки), REQ-NFR-02 крит. 1, 2 через экран (тикер от подставленных часов).

const SCENE: String = "res://src/ui/dev/dev_screen.tscn"
const MAIN_SCENE: String = "res://src/app/main.tscn"

var _now_usec: int = 0
var _dir: String
var _repo: ProfileRepository
var _state: AppState
var _previous_locale: String


func before_each() -> void:
	_now_usec = 1_000_000
	_dir = "user://test_acc_devscreen_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_repo = ProfileRepository.new(_dir + "profiles/")
	_state = AppState.new(_repo)
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_each() -> void:
	TranslationServer.set_locale(_previous_locale)
	_remove_tree(ProjectSettings.globalize_path(_dir))
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir)), "временный каталог удалён")


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


## Продвинуть подставленные часы на `real_sec` реального времени и опросить тикер экрана.
func _advance(screen: DevScreen, real_sec: float) -> void:
	_now_usec += int(round(real_sec * 1_000_000.0))
	if screen.ticker() != null:
		screen.ticker().poll()


func _screen(ftp: int = 200) -> DevScreen:
	var s: DevScreen = load(SCENE).instantiate()
	s.clock_usec = _clock
	s.setup(_state, ftp)
	add_child_autofree(s)
	return s


func _press(screen: DevScreen, unique_name: String) -> void:
	(screen.get_node("%" + unique_name) as Button).pressed.emit()


func _commands_of(screen: DevScreen, type: String) -> Array:
	var out: Array = []
	for c in screen.commands():
		if str((c as Dictionary).get("type", "")) == type:
			out.append(c)
	return out


func _targets(screen: DevScreen) -> Array:
	var out: Array = []
	for c in _commands_of(screen, "target_power"):
		out.append([int(c["value"]), float(c["at_sec"])])
	return out


# ===========================================================================
# REQ-DEV-09 крит. 6 / REQ-WRK-01 крит. 5 — план целиком на эмуляторе
# ===========================================================================

func test_req_dev_09_c6_play_button_creates_connected_fake_trainer_session_and_ticker() -> void:
	var s := _screen()
	assert_null(s.session())
	assert_eq(s.status_text(), "No session — press “Play on emulator”")
	_press(s, "PlayButton")
	assert_not_null(s.trainer())
	assert_true(s.trainer() is TrainerDevice)
	assert_eq(s.trainer().get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_not_null(s.session())
	assert_eq(s.session().get_state(), WorkoutSession.State.RUNNING)
	assert_not_null(s.ticker())
	assert_true(s.ticker().is_running())
	assert_eq(s.ticker().time_scale, DevScreen.DEFAULT_TIME_SCALE)
	assert_true(s.ticker().get_parent() == s, "тикер — в дереве под экраном, чтобы работал _process")
	assert_eq(_targets(s), [[100, 0.0]], "первая цель 50 % от 200 Вт ушла на старте")
	assert_true(s.status_text().contains("running"), s.status_text())
	assert_true(s.status_text().contains("connected"))
	assert_true(s.status_text().contains("step 1/3"))
	assert_true(s.status_text().contains("target 100 W"))


func test_req_wrk_01_c5_plan_finishes_with_three_target_commands_on_boundaries() -> void:
	var s := _screen()
	_press(s, "PlayButton")
	var polls := 0
	while s.session().get_state() != WorkoutSession.State.FINISHED and polls < 400:
		_advance(s, 0.25) # 0.25 с реального = 2.5 с сессии при scale 10
		polls += 1
	assert_eq(s.session().get_state(), WorkoutSession.State.FINISHED, "план 180 с завершён")
	assert_eq(polls, 72, "180 с сессии = 18 с реального = 72 опроса по 0.25 с")
	assert_eq(_targets(s), [[100, 0.0], [200, 60.0], [120, 90.0]], "ровно 3 Set Target Power с метками на границах интервалов")
	assert_eq(s.commands().size(), 3, "других команд в ERG-прогоне нет")
	assert_eq(s.session().samples.size(), 180, "180 сэмплов")
	assert_true(s.session().samples.is_monotonic())
	assert_eq(s.session().executor.elapsed_sec(), 180)
	assert_true(s.status_text().contains("finished"), s.status_text())
	assert_true(s.status_text().contains("time 03:00"))
	assert_true(s.status_text().contains("samples 180"))
	# После финиша executor.current_step_index() == -1, экран показывает «step 0/3» (наблюдение в отчёте).
	assert_not_null(RegEx.create_from_string("step [0-3]/3").search(s.status_text()), s.status_text())
	# после завершения время не идёт дальше
	_advance(s, 5.0)
	assert_eq(s.session().samples.size(), 180)


func test_req_wrk_01_c5_status_text_updates_as_time_passes_and_power_converges() -> void:
	var s := _screen()
	_press(s, "PlayButton")
	var t0 := s.status_text()
	_advance(s, 0.5) # 5 с сессии
	var t1 := s.status_text()
	assert_ne(t0, t1, "текст состояния обновился")
	assert_true(t1.contains("time 00:05"), t1)
	assert_true(t1.contains("samples 5"))
	assert_false(t1.contains("power — W"), "мощность эмулятора отображается числом: %s" % t1)
	assert_true(RegEx.create_from_string("power (9[5-9]|10[0-5]) W").search(t1) != null, "через 5 с мощность около цели 100 Вт: %s" % t1)
	assert_true(RegEx.create_from_string("cadence [0-9]+ rpm").search(t1) != null)
	_advance(s, 6.0) # 65 с сессии — второй шаг
	var t2 := s.status_text()
	assert_true(t2.contains("step 2/3"), t2)
	assert_true(t2.contains("target 200 W"))
	assert_true(t2.contains("time 01:05"))


func test_req_wrk_01_c5_commands_text_shows_header_and_last_five_commands() -> void:
	var s := _screen()
	_press(s, "PlayButton")
	for i in 4:
		_press(s, "ErgButton") # каждое нажатие даёт 2 команды
	assert_gt(s.commands().size(), DevScreen.COMMANDS_SHOWN)
	var lines := s.commands_text().split("\n")
	assert_eq(lines[0], "Last trainer commands (time; type; value):")
	assert_eq(lines.size(), 1 + DevScreen.COMMANDS_SHOWN, "заголовок + 5 последних")
	var last: Dictionary = s.commands()[s.commands().size() - 1]
	assert_true(lines[-1].contains(str(last["type"])), "последняя строка — последняя команда")


func test_req_wrk_01_c5_screen_uses_fake_kind_through_factory_and_ftp_from_setup() -> void:
	var s := _screen(300)
	assert_eq(DevScreen.TRAINER_KIND, TrainerFactory.KIND_FAKE)
	_press(s, "PlayButton")
	assert_eq(_targets(s), [[150, 0.0]], "50 % от FTP 300")
	assert_eq(s.session().current_target_watts(), 150)


# ===========================================================================
# Кнопки: пауза/возобновление, пропуск, стоп, ERG
# ===========================================================================

func test_req_wrk_01_c5_pause_button_freezes_session_time_and_resume_resends_target() -> void:
	var s := _screen()
	_press(s, "PlayButton")
	_advance(s, 0.5) # 5 с
	_press(s, "PauseButton")
	assert_eq(s.session().get_state(), WorkoutSession.State.PAUSED)
	assert_eq((s.get_node("%PauseButton") as Button).text, "Resume")
	assert_true(s.status_text().contains("paused"))
	var before := s.session().samples.size()
	_advance(s, 1.0)
	_advance(s, 1.0)
	assert_eq(s.session().samples.size(), before, "на паузе сэмплы не пишутся")
	assert_eq(s.session().executor.elapsed_sec(), 5, "таймер шага стоит")
	assert_true(s.ticker().is_running(), "тикер продолжает опрашивать часы — пауза живёт в сессии")
	var cmds_before := s.commands().size()
	_press(s, "PauseButton")
	assert_eq(s.session().get_state(), WorkoutSession.State.RUNNING)
	assert_eq((s.get_node("%PauseButton") as Button).text, "Pause")
	assert_eq(s.commands().size(), cmds_before + 1, "при возобновлении повторно уходит ровно одна команда — текущая цель (REQ-WRK-05 крит. 3)")
	var last: Dictionary = s.commands()[s.commands().size() - 1]
	assert_eq(last["type"], "target_power")
	assert_eq(int(last["value"]), 100)
	# На паузе станок продолжает тикать (как реальное устройство): 5 с до паузы + 2 с реального × 10 = 25 с по часам эмулятора.
	assert_almost_eq(float(last["at_sec"]), 25.0, 1e-9, "метка — часы эмулятора в момент возобновления")
	assert_eq(s.trainer().get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "связь на паузе не рвётся")
	_advance(s, 0.5)
	assert_eq(s.session().executor.elapsed_sec(), 10, "после возобновления время идёт с того же места")


func test_req_wrk_01_c5_skip_button_advances_step_and_sends_new_target_immediately() -> void:
	var s := _screen()
	_press(s, "PlayButton")
	_advance(s, 1.0) # 10 с
	_press(s, "SkipButton")
	assert_eq(s.session().executor.current_step_index(), 1)
	assert_eq(_targets(s)[-1], [200, 10.0], "новая цель с меткой момента пропуска")
	assert_true(s.status_text().contains("step 2/3"))
	_press(s, "SkipButton")
	_press(s, "SkipButton")
	assert_eq(s.session().get_state(), WorkoutSession.State.FINISHED, "пропуск последнего шага завершает тренировку")
	assert_true(s.status_text().contains("finished"))


func test_req_wrk_01_c5_stop_button_finishes_early_stops_ticker_and_freezes_text() -> void:
	var s := _screen()
	_press(s, "PlayButton")
	_advance(s, 0.5)
	_press(s, "StopButton")
	assert_eq(s.session().get_state(), WorkoutSession.State.FINISHED)
	assert_false(s.ticker().is_running())
	var text := s.status_text()
	var samples := s.session().samples.size()
	_advance(s, 3.0)
	assert_eq(s.ticker().poll(), 0.0)
	assert_eq(s.session().samples.size(), samples)
	assert_eq(s.status_text(), text, "после стопа текст не меняется")
	assert_eq(s.commands().size(), 1, "стоп не шлёт команд станку")


func test_req_wrk_01_c5_erg_button_toggles_mode_and_sends_commands_with_timestamps() -> void:
	var s := _screen()
	_press(s, "PlayButton")
	_advance(s, 0.3) # 3 с
	assert_true(s.session().erg_enabled)
	assert_eq((s.get_node("%ErgButton") as Button).text, "ERG off", "кнопка предлагает выключить")
	_press(s, "ErgButton")
	assert_false(s.session().erg_enabled)
	assert_eq((s.get_node("%ErgButton") as Button).text, "ERG on")
	assert_true(s.status_text().contains("ERG off"))
	var journal := s.commands()
	assert_eq(journal.size(), 3)
	assert_eq(journal[1]["type"], "erg")
	assert_eq(journal[1]["value"], false)
	assert_eq(journal[2]["type"], "resistance")
	assert_almost_eq(float(journal[2]["at_sec"]), 3.0, 1e-9, "метка — момент нажатия по часам эмулятора")
	_press(s, "ErgButton")
	journal = s.commands()
	assert_eq(journal.size(), 5)
	assert_eq(journal[3]["type"], "erg")
	assert_eq(journal[3]["value"], true)
	assert_eq(journal[4]["type"], "target_power")
	assert_eq(journal[4]["value"], 100)
	assert_true(s.status_text().contains("ERG on"))


func test_req_wrk_01_c5_buttons_disabled_without_session_and_enabled_after_play() -> void:
	var s := _screen()
	for b in ["PauseButton", "SkipButton", "StopButton", "ErgButton"]:
		assert_true((s.get_node("%" + b) as Button).disabled, "%s недоступна без сессии" % b)
	assert_false((s.get_node("%PlayButton") as Button).disabled)
	_press(s, "SkipButton")
	_press(s, "StopButton")
	_press(s, "ErgButton")
	_press(s, "PauseButton")
	assert_null(s.session(), "нажатия без сессии безопасны")
	_press(s, "PlayButton")
	for b in ["PauseButton", "SkipButton", "StopButton", "ErgButton"]:
		assert_false((s.get_node("%" + b) as Button).disabled)


func test_req_wrk_01_c5_play_again_restarts_run_with_fresh_trainer_and_single_ticker() -> void:
	var s := _screen()
	_press(s, "PlayButton")
	_advance(s, 2.0)
	var first_trainer := s.trainer()
	var first_ticker := s.ticker()
	assert_eq(s.session().executor.elapsed_sec(), 20)
	_press(s, "PlayButton")
	assert_ne(s.trainer(), first_trainer, "новый эмулятор")
	assert_ne(s.ticker(), first_ticker, "новый тикер")
	assert_false(first_ticker.is_running(), "старый тикер остановлен")
	assert_eq(first_trainer.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED, "старый эмулятор отключён")
	assert_eq(s.session().executor.elapsed_sec(), 0)
	assert_eq(s.commands().size(), 1, "журнал нового эмулятора начат заново")
	await get_tree().process_frame
	var tickers := 0
	for child in s.get_children():
		if child is SessionTicker:
			tickers += 1
	assert_eq(tickers, 1, "старый тикер освобождён — время не удваивается")


# ===========================================================================
# REQ-NFR-02 крит. 1, 2 через экран
# ===========================================================================

func test_req_nfr_02_c1_screen_ticker_follows_injected_clock_not_frames() -> void:
	var s := _screen()
	_press(s, "PlayButton")
	s.ticker().set_time_scale(1.0)
	var pattern: Array[float] = [0.016, 0.984, 2.0, 1.0] # сумма 4.0 за 4 опроса
	for i in 60:
		_advance(s, pattern[i % 4])
	assert_almost_eq(s.ticker().real_elapsed_sec, 60.0, 1e-6)
	assert_eq(s.session().samples.size(), 60, "60 с реального → 60 сэмплов при 60 неровных опросах")
	assert_true(s.status_text().contains("time 01:00"))


func test_req_nfr_02_c2_screen_survives_two_second_freeze_with_backfilled_samples() -> void:
	var s := _screen()
	_press(s, "PlayButton")
	s.ticker().set_time_scale(1.0)
	_advance(s, 1.0)
	_advance(s, 2.0) # заморозка кадра
	assert_eq(Array(s.session().samples.time_sec), [0, 1, 2])
	assert_true(s.status_text().contains("samples 3"))
	assert_true(s.status_text().contains("time 00:03"))


func test_req_nfr_02_c1_screen_in_tree_advances_via_process_frames() -> void:
	var s := _screen()
	_press(s, "PlayButton")
	_now_usec += 1_000_000 # 1 с реального = 10 с сессии
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(s.session().executor.elapsed_sec(), 10, "_process тикера опросил подставленные часы")
	assert_true(s.status_text().contains("time 00:10"))


# ===========================================================================
# Навигация и подключение через main.tscn
# ===========================================================================

func test_req_dev_09_c6_back_button_returns_home_only_when_profile_chosen() -> void:
	_repo.create("Alice")
	_repo.create("Bob")
	_state.start()
	var s := _screen()
	_press(s, "BackButton")
	assert_eq(_state.current_screen, AppState.Screen.PROFILE_SELECT, "без выбранного профиля главный экран закрыт")
	_state.select_profile(_repo.list()[0].id)
	_state.navigate(AppState.Screen.DEV)
	assert_eq(_state.current_screen, AppState.Screen.DEV)
	_press(s, "BackButton")
	assert_eq(_state.current_screen, AppState.Screen.HOME)


func test_req_dev_09_c6_main_scene_opens_dev_screen_with_profile_ftp_and_plays() -> void:
	var p := _repo.create("Solo")
	var ep := p.duplicate_profile()
	ep.ftp_w = 250
	assert_eq(_repo.save(ep), [])
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	add_child_autofree(main)
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME)
	assert_true(main.app_state.navigate(AppState.Screen.DEV))
	var dev := main.visible_screen_node() as DevScreen
	assert_not_null(dev, "экран DEV доступен из приложения")
	assert_eq(dev.ftp_w, 250, "FTP активного профиля")
	dev.clock_usec = _clock
	assert_true(dev.play())
	assert_eq(dev.session().current_target_watts(), 125, "50 % от 250")
	_now_usec += 20_000_000 # 20 с реального = 200 с сессии
	dev.ticker().poll()
	assert_eq(dev.session().get_state(), WorkoutSession.State.FINISHED, "тренировка проиграна до конца без железа")
	assert_eq(dev.session().samples.size(), 180)
	dev.back()
	assert_true(main.visible_screen_node() is HomeScreen)
