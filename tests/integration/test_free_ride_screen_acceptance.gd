extends GutTest
## Приёмка T-084 (tester, независимо от `tests/integration/test_free_ride_flow.gd`): экран свободной
## езды в `main.tscn` со своим `FakeTrainer` (журнал команд под контролем теста).
## REQ-FRD-01 крит. 1 (без исполнителя и смен шага), 2 (ни одной Set Target Power), 4 (без станка);
## REQ-FRD-06 крит. 1–3 (состав и форматы панели, полный уклон на HUD, маркер на профиле круга),
## крит. 5 (раскладка: рельеф в левых 25 %, график внизу, центр свободен);
## REQ-FRD-07 крит. 2 (пауза: станку ничего, дистанция и время стоят; завершение — с подтверждением),
## крит. 6, 7 (в истории без цели, название для Strava); REQ-UIX-04 крит. 2 («назад» не завершает).

const MAIN_SCENE: String = "res://src/app/main.tscn"
const MINUS: String = "−"

var _dir: String
var _previous_locale: String
var _now_usec: int = 0
var _trainer: FakeTrainer


func before_each() -> void:
	_dir = "user://test_t084_acc_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_previous_locale = TranslationServer.get_locale()
	_now_usec = 2_000_000


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
	ProfileRepository.new(_dir + "profiles/").create("Аня")
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	add_child_autofree(main)
	TranslationServer.set_locale("ru")
	var screen := main.free_ride_screen()
	screen.clock_usec = _clock
	screen.keep_awake_setter = func(_on: bool) -> void: pass
	return main


func _clock() -> int:
	return _now_usec


func _start(main: AppMain, route_id: String, steepness: int = 50) -> FreeRideScreen:
	_trainer = FakeTrainer.new(84)
	_trainer.connect_delay_sec = 0.0
	_trainer.power_noise_w = 0.0
	_trainer.cadence_noise_rpm = 0.0
	_trainer.set_rider_power(220)
	_trainer.connect_device("t084")
	assert_true(main.launch_free_ride(_trainer, route_id, steepness), "предусловие: езда запущена")
	return main.free_ride_screen()


func _ride(main: AppMain, seconds: float) -> void:
	var ticker := main.free_ride_screen().ticker()
	for i in int(round(seconds / 0.5)):
		_now_usec += 500_000
		ticker.poll()


func _types(since: int = 0) -> Array[String]:
	var out: Array[String] = []
	for i in range(since, _trainer.commands.size()):
		out.append(str(_trainer.commands[i]["type"]))
	return out


# ===========================================================================
# REQ-FRD-01 крит. 1, 2 — сессия без плана, ни одной Set Target Power
# ===========================================================================

func test_req_frd_01_c1_c2_no_executor_no_step_events_no_target_power() -> void:
	var main := _main()
	var screen := _start(main, RouteCatalog.HILLS)
	var session := screen.session()
	assert_true(session is FreeRideSession, "сессия свободной езды")
	assert_false("executor" in session, "исполнителя интервалов нет")
	_ride(main, 120.0)
	screen.toolbar().button(&"sim").pressed.emit() # SIM → сопротивление
	_ride(main, 30.0)
	screen.toolbar().button(&"sim").pressed.emit() # обратно в SIM
	_ride(main, 30.0)
	var types := _types()
	gut.p("журнал станка: %d команд, первые %s" % [types.size(), str(types.slice(0, 6))])
	assert_false(types.has(FakeTrainer.CMD_TARGET_POWER), "FRD-01 крит. 2: ни одной Set Target Power")
	assert_true(types.has(FakeTrainer.CMD_SIM), "уклон уходит станку")
	var first_control := ""
	for t in types:
		if t in [FakeTrainer.CMD_SIM, FakeTrainer.CMD_RESISTANCE, FakeTrainer.CMD_TARGET_POWER, FakeTrainer.CMD_ERG]:
			first_control = t
			break
	assert_eq(first_control, FakeTrainer.CMD_SIM, "первая команда управления — SIM")
	for e in session.events:
		assert_ne(str(e["type"]), WorkoutSession.EVENT_SKIP, "событий пропуска шага нет")
		assert_false(str(e["type"]).contains("step"), "событий смены шага нет: %s" % e["type"])


func test_req_frd_01_c4_without_trainer_no_session_and_explanation() -> void:
	var main := _main()
	assert_false(main.is_trainer_ready(), "предусловие: станок не подключён")
	main.home_screen().free_ride_requested.emit(RouteCatalog.FLAT)
	assert_null(main.free_ride_screen().session(), "без станка сессии нет")
	assert_ne(main.app_state.current_screen, AppState.Screen.FREE_RIDE, "экран езды не открыт")
	var dialog := main.free_ride_trainer_dialog()
	assert_true(dialog.visible, "пояснение показано")
	assert_false(dialog.tr(dialog.dialog_text).begins_with("ui."), "текст переведён")
	dialog.get_ok_button().pressed.emit()
	assert_eq(main.app_state.current_screen, AppState.Screen.DEVICES, "ссылка на экран устройств")


# ===========================================================================
# REQ-FRD-06 крит. 1, 2 — состав и форматы панели, полный уклон трассы
# ===========================================================================

func test_req_frd_06_c1_c2_panel_values_formats_and_full_route_grade() -> void:
	var main := _main()
	var screen := _start(main, RouteCatalog.MOUNTAINS, 50)
	_trainer.set_heart_rate(140)
	_ride(main, 600.0)
	var p := screen.metric_panel()
	var s := screen.session()
	gut.p("время %s, дистанция %s, скорость %s, набор %s, уклон %s, режим «%s», мощность %s" % [p.elapsed_text(),
		p.distance_text(), p.speed_text(), p.ascent_text(), p.grade_text(), p.grade_mode_text(), p.power_text()])
	assert_eq(p.elapsed_text(), "10:00", "время мм:сс")
	assert_true(RegEx.create_from_string("^[0-9]+\\.[0-9]$").search(p.distance_text()) != null, "дистанция — км с одним знаком: %s" % p.distance_text())
	assert_almost_eq(float(p.distance_text()), s.distance_m() / 1000.0, 0.051, "дистанция накопленная за сессию")
	assert_true(RegEx.create_from_string("^[0-9]+\\.[0-9]$").search(p.speed_text()) != null, "скорость с одним знаком")
	assert_true(p.ascent_text().is_valid_int(), "набор — целые метры: %s" % p.ascent_text())
	assert_eq(int(p.ascent_text()), int(round(s.ascent_m())), "набор за заезд")
	var g := s.route_grade_pct()
	var expected := ("+" if g >= 0.0 else MINUS) + "%.1f" % absf(g)
	if absf(g) < 0.05:
		expected = "0.0"
	assert_string_contains(p.grade_text(), expected, "уклон трассы со знаком, один знак: %s" % p.grade_text())
	assert_string_starts_with(p.grade_mode_text(), "SIM 50", "режим и крутизна в карточке")
	assert_eq(p.hr_text(), "140")
	assert_false(p.power_text().is_empty())
	# Цели, отклонения, отсчёта и списка интервалов нет.
	assert_false(p.target_card().is_visible_in_tree(), "карточки цели нет")
	assert_eq(p.deviation_text(), "", "индикации отклонения нет")
	assert_true(screen.relief_panel().is_visible_in_tree(), "в левом слоте — панель рельефа, не список")
	assert_eq(screen.find_children("*", "IntervalList", true, false).size(), 0, "списка интервалов нет")
	# Полный уклон на HUD, на станок — с крутизной.
	var sim_cmds := _trainer.commands.filter(func(c: Dictionary) -> bool: return c["type"] == FakeTrainer.CMD_SIM)
	assert_gt(sim_cmds.size(), 0)
	var sent := float(sim_cmds.back()["value"])
	gut.p("уклон трассы %.2f %%, на станок %.2f %%" % [g, sent])
	if absf(g) >= 1.0:
		assert_almost_eq(sent, g * 0.5, 0.15, "на станок уходит g × 50 %%, на HUD — полный g")


func test_req_frd_06_c1_grade_formats_plus_minus_zero() -> void:
	var main := _main()
	var screen := _start(main, RouteCatalog.FLAT)
	var p := screen.metric_panel()
	var cases := {6.4: "+6.4", -3.0: MINUS + "3.0", 0.0: "0.0"}
	for g: float in cases:
		var state := screen.hud().state() if screen.hud() != null else {}
		state["grade_pct"] = g
		p.set_state(state)
		assert_string_contains(p.grade_text(), cases[g], "g = %s → «%s» (%s)" % [g, cases[g], p.grade_text()])


# ===========================================================================
# REQ-FRD-06 крит. 3 — маркер на профиле круга
# ===========================================================================

func test_req_frd_06_c3_lap_marker_x_follows_position_and_wraps() -> void:
	var main := _main()
	var screen := _start(main, RouteCatalog.FLAT)
	var relief := screen.relief_panel()
	var s := screen.session()
	for chunk in [60.0, 300.0, 900.0]:
		_ride(main, chunk)
		await wait_process_frames(1)
		var f := relief.lap_field_rect()
		var frac := fposmod(s.position.s_m(), s.position.length_m()) / s.position.length_m()
		var x := relief.lap_marker_position().x
		gut.p("s = %.0f м (круг %d), маркер %.1f, ожидание %.1f" % [s.position.s_m(), s.position.lap_number(), x, f.position.x + frac * f.size.x])
		assert_almost_eq(x, f.position.x + frac * f.size.x, 1.0, "маркер на x = (s mod L)/L × ширина ±1 px")
		var a := relief.ahead_field_rect()
		assert_almost_eq(relief.ahead_marker_position().x, a.position.x + 200.0 / 2200.0 * a.size.x, 1.0, "«впереди 2 км»: маркер на 200/2200")


# ===========================================================================
# REQ-FRD-06 крит. 5 — раскладка
# ===========================================================================

func test_req_frd_06_c5_relief_in_left_25_percent_chart_bottom_center_free() -> void:
	var main := _main()
	var screen := _start(main, RouteCatalog.HILLS)
	_ride(main, 30.0)
	await wait_process_frames(3)
	var canvas := screen.get_viewport_rect().size
	var relief := screen.relief_panel().get_global_rect()
	assert_true(relief.end.x <= 0.25 * canvas.x + 0.5, "рельеф в левых 25 %%: %s" % relief)
	var chart := screen.chart().get_global_rect()
	assert_almost_eq(chart.end.y, canvas.y, 1.0, "график прижат к низу")
	assert_almost_eq(chart.size.x, canvas.x, 1.0, "во всю ширину")
	var center := Rect2(canvas * Vector2(0.30, 0.35), canvas * Vector2(0.40, 0.40))
	screen.toolbar().poke()
	await wait_seconds(0.3)
	assert_false(screen.toolbar().get_global_rect().intersects(center), "панель инструментов не в центре")
	assert_false(screen.metric_panel().get_global_rect().intersects(center), "панель цифр не в центре")


# ===========================================================================
# REQ-FRD-07 крит. 2 — пауза; завершение только с подтверждением; UIX-04 крит. 2
# ===========================================================================

func test_req_frd_07_c2_pause_sends_nothing_and_freezes_distance_and_time() -> void:
	var main := _main()
	var screen := _start(main, RouteCatalog.HILLS)
	_ride(main, 60.0)
	screen.toggle_pause()
	assert_eq(screen.session().get_state(), WorkoutSession.State.PAUSED)
	assert_eq(screen.pause_overlay().view(), PauseOverlay.View.PAUSE, "карточка паузы")
	assert_false(screen.pause_overlay().skip_button().visible, "в свободной езде нет «Пропустить шаг»")
	var before := _trainer.commands.size()
	var dist := screen.session().distance_m()
	var t := screen.metric_panel().elapsed_text()
	_ride(main, 30.0)
	assert_eq(_trainer.commands.size(), before, "на паузе станку ничего")
	assert_eq(screen.session().distance_m(), dist, "дистанция стоит")
	assert_eq(screen.metric_panel().elapsed_text(), t, "время стоит")
	screen.pause_overlay().resume_button().pressed.emit()
	assert_eq(screen.session().get_state(), WorkoutSession.State.RUNNING)
	assert_true(_types(before).has(FakeTrainer.CMD_SIM), "при возобновлении — уклон станку (FRD-04 крит. 5)")


func test_req_frd_07_c2_c6_c7_uix_04_c2_back_confirms_finish_saves_history_and_strava_name() -> void:
	var main := _main()
	var screen := _start(main, RouteCatalog.MOUNTAINS)
	_ride(main, 120.0)
	assert_true(screen.handle_back(), "«назад» перехвачен экраном")
	assert_eq(screen.session().get_state(), WorkoutSession.State.RUNNING, "«назад» не завершает")
	assert_true(screen.is_finish_confirmation_pending(), "UIX-04 крит. 2: подтверждение")
	screen.pause_overlay().cancel_button().pressed.emit()
	assert_false(screen.is_finish_confirmation_pending())
	screen.toolbar().button(&"finish").pressed.emit()
	assert_eq(screen.pause_overlay().view(), PauseOverlay.View.CONFIRM, "«Завершить» — подтверждение")
	screen.pause_overlay().confirm_button().pressed.emit()
	assert_eq(screen.session().get_state(), WorkoutSession.State.FINISHED)
	assert_true(screen.is_summary_visible(), "итог заезда")
	var ride_id := screen.saved_ride_id()
	assert_ne(ride_id, "", "заезд сохранён")
	main.app_state.navigate(AppState.Screen.HISTORY)
	var h := main.history_screen()
	h.refresh()
	assert_not_null(h.row_for(ride_id), "FRD-07 крит. 6: заезд в истории")
	assert_true(h.show_ride(ride_id))
	assert_false(h.detail().effort_chart().has_plan(), "график без цели")
	assert_eq(h.detail().upload_name(), "Свободная езда — Перевал", "FRD-07 крит. 7: название для Strava")
