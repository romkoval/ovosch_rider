extends GutTest
## Журнал диагностики и журнал кадров в приложении (T-116a; инструмент для REQ-D3D-05 п.1, 3,
## D3D-07 п.7, D3D-08 п.9, NFR-02 п.3; регрессия REQ-NFR-05 п.1, 2, NFR-06 п.3):
## - оболочка открывает файл запуска в `<data_dir>/logs/` и делает его общим;
## - заезд (тренировка и свободная езда) пишет при завершении статистику кадров с полями п.3;
##   значения сходятся с поданной серией длительностей кадров;
## - «Замер FPS» headless на короткой длительности завершается, пишет статистику в журнал и
##   показывает итог; «назад» прерывает замер без итога;
## - «О программе»: «Сохранить журнал» копирует журнал в выбранный путь, строки разработчика
##   скрыты до пяти нажатий на «Версию», «Ограничить FPS до 15» меняет `Engine.max_fps`;
## - при ограничении FPS 15 поток 1 Гц идёт без пропусков (как NFR-02 п.1, 2);
## - значения тестовых секретов в журнале не находятся.

const MAIN_SCENE: String = "res://src/app/main.tscn"
const SECRET_KEY: String = "fixture-diag-intervals-key-41"
## Поля статистики кадров (T-116a п.3).
const STAT_FIELDS: Array[String] = ["avg_fps", "low_1pct_fps", "p95_ms", "p99_ms", "share_over_16_7_ms",
	"share_over_33_ms", "frames", "renderer", "window_px", "viewport_3d_px", "route", "mode", "build"]

var _dir: String
var _previous_locale: String
var _now_usec: int = 0


func before_each() -> void:
	_dir = "user://test_diagnostics_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_now_usec = 1_000_000


func after_each() -> void:
	FrameRateLimit.set_limited(false)
	TranslationServer.set_locale(_previous_locale)
	DiagLog.uninstall()
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
	ProfileRepository.new(_dir + "profiles/").create("Solo")
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	add_child_autofree(main)
	main.free_ride_screen().clock_usec = _clock
	main.free_ride_screen().keep_awake_setter = _ignore
	return main


func _clock() -> int:
	return _now_usec


func _ignore(_on: bool) -> void:
	pass


## Записи журнала (все файлы каталога логов), опционально — только события `event`.
func _records(event: String = "") -> Array[Dictionary]:
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
			if parsed is Dictionary and (event.is_empty() or (parsed as Dictionary).get("ev", "") == event):
				out.append(parsed)
	return out


func _logs_text() -> String:
	var text := ""
	var logs := _dir + "logs/"
	var d := DirAccess.open(logs)
	if d == null:
		return text
	for f in d.get_files():
		text += FileAccess.get_file_as_string(logs + f)
	return text


func _assert_stat_fields(data: Dictionary, what: String) -> void:
	for field in STAT_FIELDS:
		assert_true(data.has(field), "%s: поле %s" % [what, field])


# ---------------------------------------------------------------------------
# Журнал запуска
# ---------------------------------------------------------------------------

func test_app_opens_launch_log_in_data_dir_and_installs_it() -> void:
	var main := _main()
	assert_not_null(main.journal)
	assert_true(main.journal.is_open())
	assert_true(main.journal.file_path().begins_with(_dir + "logs/"), main.journal.file_path())
	assert_eq(DiagLog.shared(), main.journal, "журнал оболочки — общий")
	var started := _records("app_started")
	assert_eq(started.size(), 1)
	for field in ["app_version", "engine", "renderer", "build", "window_px", "locale"]:
		assert_true((started[0]["data"] as Dictionary).has(field), "app_started: поле %s" % field)
	main.free()
	assert_null(DiagLog.shared(), "после выхода общий журнал снят")
	assert_eq(_records("app_stopped").size(), 1)


# ---------------------------------------------------------------------------
# Статистика кадров заезда (п.3)
# ---------------------------------------------------------------------------

func test_probe_with_synthetic_frames_writes_stats_matching_the_series() -> void:
	var journal := DiagLog.new(_dir + "logs/")
	assert_eq(journal.open(), OK)
	DiagLog.install(journal)
	var probe := FrameStatsProbe.attach(self)
	autofree(probe)
	probe.begin({"mode": "workout", "route": RouteCatalog.FLAT})
	probe.set_process(false)
	# 200 кадров: 196 × 16 мс, 2 × 40 мс, 2 × 100 мс. Сумма 3136 + 80 + 200 = 3416 мс.
	var series := PackedFloat32Array()
	for i in 196:
		series.append(16.0)
	series.append_array(PackedFloat32Array([40.0, 100.0, 40.0, 100.0]))
	for ms in series:
		probe.add_frame_ms(ms)
	var expected := FrameStats.from_frame_times_ms(series).summary()
	probe.finish()
	var rows := _records(FrameStatsProbe.EVENT_RIDE)
	assert_eq(rows.size(), 1)
	var data: Dictionary = rows[0]["data"]
	_assert_stat_fields(data, "синтетический заезд")
	assert_eq(int(data["frames"]), 200)
	assert_almost_eq(float(data["avg_fps"]), 200.0 * 1000.0 / 3416.0, 0.01)
	assert_almost_eq(float(data["avg_fps"]), float(expected["avg_fps"]), 1e-6)
	# 1 % от 200 — два худших кадра (100 и 100 мс) → 10 FPS.
	assert_almost_eq(float(data["low_1pct_fps"]), 10.0, 0.01)
	assert_almost_eq(float(data["p95_ms"]), 16.0, 1e-3)
	# 99-й по рангу из 200 — 198-й кадр: 40 мс.
	assert_almost_eq(float(data["p99_ms"]), 40.0, 1e-3)
	assert_almost_eq(float(data["max_ms"]), 100.0, 1e-3)
	assert_almost_eq(float(data["share_over_16_7_ms"]), 0.02, 1e-6)
	assert_almost_eq(float(data["share_over_33_ms"]), 0.02, 1e-6)
	assert_eq(data["mode"], "workout")
	assert_eq(data["route"], RouteCatalog.FLAT)
	assert_eq(probe.finish(), {}, "повторный finish ничего не пишет")
	assert_eq(_records(FrameStatsProbe.EVENT_RIDE).size(), 1)


func test_probe_measures_frames_by_clock_between_process_calls() -> void:
	var probe := FrameStatsProbe.attach(self)
	autofree(probe)
	probe.clock_usec = _clock
	probe.begin()
	for ms in [10, 20, 30]:
		_now_usec += ms * 1000
		probe._process(0.0)
	# Первый вызов — отметка, дальше два кадра: 20 и 30 мс.
	assert_eq(probe.stats().frame_count(), 2)
	assert_almost_eq(probe.stats().total_ms(), 50.0, 1e-6)
	var summary := probe.finish()
	assert_almost_eq(float(summary["max_ms"]), 30.0, 1e-6)


func test_free_ride_finish_writes_frame_stats_with_route_and_render_fields() -> void:
	var main := _main()
	assert_true(main.start_free_ride_on_emulator(RouteCatalog.HILLS, 50))
	var screen := main.free_ride_screen()
	await wait_process_frames(5)
	screen.request_finish()
	screen.confirm_finish()
	var rows := _records(FrameStatsProbe.EVENT_RIDE)
	assert_eq(rows.size(), 1, "статистика кадров записана при завершении")
	var data: Dictionary = rows[0]["data"]
	_assert_stat_fields(data, "свободная езда")
	assert_eq(data["mode"], "free_ride")
	assert_eq(data["route"], RouteCatalog.HILLS)
	assert_gt(int(data["frames"]), 0, "кадры заезда учтены")
	assert_eq(data["viewport_3d_px"], "%dx%d" % [screen.ride_viewport_size().x, screen.ride_viewport_size().y])


func test_workout_finish_writes_frame_stats() -> void:
	var main := _main()
	main.start_emulator_workout()
	var ws := main.workout_screen()
	assert_not_null(ws.session())
	await wait_process_frames(5)
	ws.confirm_stop()
	var rows := _records(FrameStatsProbe.EVENT_RIDE)
	assert_eq(rows.size(), 1)
	var data: Dictionary = rows[0]["data"]
	_assert_stat_fields(data, "тренировка")
	assert_eq(data["mode"], "workout")
	assert_eq(data["route"], ws.ride_scene().route_id)


# ---------------------------------------------------------------------------
# «Замер FPS» (п.4)
# ---------------------------------------------------------------------------

func test_fps_benchmark_short_run_finishes_logs_and_shows_result() -> void:
	var journal := DiagLog.new(_dir + "logs/")
	assert_eq(journal.open(), OK)
	DiagLog.install(journal)
	var bench := FpsBenchmark.new()
	bench.duration_sec = 0.3
	bench.warmup_sec = 0.1
	add_child_autofree(bench)
	assert_eq(bench.route_id, RouteCatalog.MOUNTAINS, "по умолчанию — «Перевал»")
	watch_signals(bench)
	assert_true(bench.start())
	assert_eq(bench.ride_scene().route_id, RouteCatalog.MOUNTAINS)
	assert_eq(bench.ride_scene().speed_kmh, FpsBenchmark.DEFAULT_SPEED_KMH, "постоянная скорость")
	await wait_for_signal(bench.finished, 20.0)
	assert_signal_emitted(bench, "finished")
	assert_false(bench.is_running())
	assert_true(bench.is_result_visible(), "итог на экране")
	var rows := _records(FpsBenchmark.EVENT)
	assert_eq(rows.size(), 1, "итог в журнале")
	var data: Dictionary = rows[0]["data"]
	_assert_stat_fields(data, "замер FPS")
	assert_eq(data["mode"], "fps_benchmark")
	assert_eq(data["route"], RouteCatalog.MOUNTAINS)
	assert_gt(int(data["frames"]), 0)
	assert_gt(float(data["distance_m"]), 0.0, "гонщик ехал")
	assert_true(bench.result_text().contains("Average FPS"), bench.result_text())
	assert_true(bench.result_text().contains("p95"), bench.result_text())


func test_fps_benchmark_cancel_logs_cancel_without_result() -> void:
	var journal := DiagLog.new(_dir + "logs/")
	assert_eq(journal.open(), OK)
	DiagLog.install(journal)
	var bench := FpsBenchmark.new()
	bench.duration_sec = 30.0
	bench.warmup_sec = 0.0
	add_child_autofree(bench)
	watch_signals(bench)
	bench.start()
	await wait_process_frames(3)
	assert_true(bench.handle_back())
	assert_false(bench.is_running())
	assert_signal_emitted(bench, "closed")
	assert_eq(_records(FpsBenchmark.EVENT).size(), 0, "итога нет")
	assert_eq(_records(FpsBenchmark.EVENT_CANCELLED).size(), 1)


func test_settings_unlock_starts_benchmark_and_back_cancels_it() -> void:
	var main := _main()
	assert_true(main.app_state.navigate(AppState.Screen.SETTINGS))
	var settings := main.settings_screen()
	var diag := settings.diagnostics()
	assert_not_null(diag)
	assert_true(settings.section_node(SettingsSections.ABOUT).is_ancestor_of(diag.save_log_button()), "строка журнала — в «О программе»")
	assert_true(diag.save_log_button().is_visible_in_tree(), "«Сохранить журнал» видна всегда")
	assert_false(diag.benchmark_button().is_visible_in_tree(), "«Замер FPS» скрыт")
	assert_false(diag.fps_limit_check().is_visible_in_tree(), "ограничение FPS скрыто")
	var version_row := (settings.get_node("%VersionLabel") as Control).get_parent() as Control
	for i in AboutDiagnostics.UNLOCK_TAPS - 1:
		version_row.gui_input.emit(_click())
	assert_false(diag.are_dev_tools_visible(), "четырёх нажатий мало")
	version_row.gui_input.emit(_click())
	assert_true(diag.are_dev_tools_visible())
	assert_true(diag.benchmark_button().is_visible_in_tree())
	assert_eq(diag.selected_route(), RouteCatalog.MOUNTAINS, "трасса по умолчанию — «Перевал»")
	assert_eq(diag.selected_duration_sec(), 180.0, "длительность по умолчанию — 3 мин")
	diag.benchmark_button().pressed.emit()
	var bench := settings.fps_benchmark()
	assert_not_null(bench, "замер открыт поверх настроек")
	assert_true(bench.is_running())
	assert_eq(bench.duration_sec, 180.0)
	await wait_process_frames(2)
	assert_true(main.handle_back(), "«назад» обрабатывает экран настроек")
	assert_null(settings.fps_benchmark(), "замер закрыт")
	assert_eq(main.app_state.current_screen, AppState.Screen.SETTINGS, "экран остался")
	assert_eq(_records(FpsBenchmark.EVENT_CANCELLED).size(), 1)


static func _click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e


# ---------------------------------------------------------------------------
# Ограничение FPS 15 (п.5, NFR-02 п.3)
# ---------------------------------------------------------------------------

func test_fps_limit_toggle_sets_engine_max_fps_and_restores_project_value() -> void:
	var main := _main()
	main.app_state.navigate(AppState.Screen.SETTINGS)
	var diag := main.settings_screen().diagnostics()
	diag.unlock_dev_tools()
	diag.fps_limit_check().button_pressed = true
	assert_eq(Engine.max_fps, FrameRateLimit.DEBUG_FPS)
	assert_true(FrameRateLimit.is_limited())
	assert_eq(int(ProjectSettings.get_setting("application/run/max_fps", 0)), FrameRateLimit.project_max_fps(),
			"настройка проекта не меняется (D3D-05 п.2)")
	diag.fps_limit_check().button_pressed = false
	assert_eq(Engine.max_fps, FrameRateLimit.project_max_fps())
	var rows := _records(FrameRateLimit.EVENT)
	assert_eq(rows.size(), 2, "оба переключения в журнале")
	assert_eq(int(rows[0]["data"]["max_fps"]), 15)


func test_fps_limit_15_keeps_1hz_stream_without_gaps() -> void:
	FrameRateLimit.set_limited(true)
	assert_eq(Engine.max_fps, 15)
	var trainer := FakeTrainer.new(3)
	trainer.connect_delay_sec = 0.0
	trainer.connect_device("fps15")
	var steps: Array[WorkoutStep] = [WorkoutStep.percent(120, 60.0, WorkoutStep.StepKind.STEADY)]
	var session := WorkoutSession.new(Workout.make("fps15", steps), trainer, 200)
	var ticker := SessionTicker.new(_clock)
	ticker.attach(session)
	add_child_autofree(ticker)
	session.start()
	ticker.start()
	# 60 с «кадрами» по 1/15 с (66 667 мкс).
	var frame_usec: int = 1_000_000 / Engine.max_fps
	var frames := ceili(60.0 * 1_000_000.0 / float(frame_usec))
	for i in frames:
		_now_usec += frame_usec
		ticker.poll()
	assert_eq(session.samples.size(), 60, "60 с при 15 FPS → 60 сэмплов")
	assert_true(session.samples.is_monotonic())
	for i in session.samples.size():
		assert_eq(session.samples.time_sec[i], i, "секунда %d без пропуска" % i)
	session.stop()


# ---------------------------------------------------------------------------
# Экспорт (п.6) и секреты (п.2)
# ---------------------------------------------------------------------------

func test_save_log_copies_journal_to_chosen_path_and_reports_it() -> void:
	var main := _main()
	main.app_state.navigate(AppState.Screen.SETTINGS)
	var diag := main.settings_screen().diagnostics()
	DiagLog.event(DiagLog.CAT_APP, "marker_before_export")
	var target := ProjectSettings.globalize_path(_dir + "exported.log")
	assert_eq(diag.export_log_to(target), OK)
	var text := FileAccess.get_file_as_string(target)
	assert_true(text.contains("app_started") and text.contains("marker_before_export"), "журнал скопирован")
	assert_true(diag.log_hint_text().contains(target), "путь показан в строке: %s" % diag.log_hint_text())
	assert_ne(diag.export_log_to(_dir + "missing/deeper/x.log"), OK)
	assert_eq(diag.log_hint_text(), tr("ui.settings.diag_log_failed").format({"path": _dir + "missing/deeper/x.log"}))


func test_save_log_button_opens_native_save_dialog() -> void:
	var main := _main()
	main.app_state.navigate(AppState.Screen.SETTINGS)
	var diag := main.settings_screen().diagnostics()
	diag.save_log_button().pressed.emit()
	var dialog := diag.export_dialog()
	assert_not_null(dialog)
	assert_eq(dialog.file_mode, FileDialog.FILE_MODE_SAVE_FILE)
	assert_true(dialog.use_native_dialog, "системный диалог")
	assert_true(dialog.current_file.ends_with(".log"))
	dialog.hide()


func test_secrets_never_reach_app_journal() -> void:
	var main := _main()
	var profile := main.repo.get_active()
	main.secure_store.set_secret(SecureStore.key_for(profile.id, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY), SECRET_KEY)
	DiagLog.event(DiagLog.CAT_APP, "leak_attempt", {"key": SECRET_KEY, "auth": "Authorization: Bearer " + SECRET_KEY,
			"url": "http://127.0.0.1/callback?code=fixture-diag-oauth-code&state=x"})
	main.start_free_ride_on_emulator(RouteCatalog.FLAT, 50)
	main.free_ride_screen().confirm_finish()
	var text := _logs_text()
	assert_true(text.contains("leak_attempt"), "событие записано")
	assert_false(text.contains(SECRET_KEY), "ключ API не в журнале")
	assert_false(text.contains("fixture-diag-oauth-code"), "код OAuth не в журнале")
