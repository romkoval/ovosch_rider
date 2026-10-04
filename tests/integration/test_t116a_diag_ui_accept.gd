extends GutTest
## Приёмка T-116a (tester): строки диагностики в «О программе», «Замер FPS» и «Ограничить FPS
## до 15» глазами пользователя — независимые проверки по карточке T-116a (п.4–6) и регрессия
## REQ-UIX-04 п.3, REQ-UIX-05 п.1–3 на новых строках:
## - строки разработчика скрыты в обычном меню и открываются пятью нажатиями на «Версию»
##   настоящим вводом (мышь и касание через `Input`, с эмуляцией мыши от касания, как на
##   телефоне); четырёх нажатий мало;
## - после перезапуска оболочки строки снова скрыты;
## - открытые строки и экран замера (идёт и итог) — на всех разрешениях матрицы UIX, ru и en:
##   цели нажатия, окно и безопасная зона, текст не обрезан (проверки `test_ui_matrix.gd`);
## - переводы новых ключей — непустые ru и en.

const MAIN_SCENE: String = "res://src/app/main.tscn"
const MATRIX := preload("res://tests/unit/ui/test_ui_matrix.gd")
const SAFE_AREA_LP: Vector4 = Vector4(100.0, 0.0, 100.0, 13.0)
const NEW_KEY_PREFIXES: Array[String] = ["ui.settings.diag_", "ui.settings.fps_", "ui.fps_bench."]

var _dir: String = ""
var _prev_locale: String = ""
var _runtime: UiScale = null
var _prev_device: UiScale.Device = UiScale.Device.DESKTOP
var _m: Node = null


func before_each() -> void:
	_dir = "user://test_t116a_ui_accept_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_prev_locale = TranslationServer.get_locale()
	_runtime = TouchTarget.default_runtime()
	if _runtime != null:
		_prev_device = _runtime.device
	_m = MATRIX.new()
	add_child_autofree(_m)


func after_each() -> void:
	FrameRateLimit.set_limited(false)
	DiagLog.uninstall()
	if Engine.has_meta(UiScale.DEBUG_SAFE_AREA_META):
		Engine.remove_meta(UiScale.DEBUG_SAFE_AREA_META)
	if _runtime != null:
		_runtime.device = _prev_device
		_runtime.set_mode(UiScale.Mode.MENU)
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


func _main_in_root(dir: String) -> AppMain:
	var repo := ProfileRepository.new(dir + "profiles/")
	if repo.list().is_empty():
		repo.create("Solo")
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	add_child(main)
	return main


func _version_row(settings: SettingsScreen) -> Control:
	return (settings.get_node("%VersionLabel") as Control).get_parent() as Control


## Прокрутить настройки так, чтобы `c` был виден; вернуть центр `c` в координатах окна.
func _scroll_into_view(settings: SettingsScreen, c: Control) -> Vector2:
	settings.scroll_container().ensure_control_visible(c)
	await wait_process_frames(3)
	return c.get_global_rect().get_center()


## Касание на телефоне: движок отдаёт `InputEventScreenTouch` и, при
## `input_devices/pointing/emulate_mouse_from_touch` (по умолчанию включено), эмулированный щелчок
## мыши с `device = InputEvent.DEVICE_ID_EMULATION` (`Input::_parse_input_event_impl`). В headless
## `Input.parse_input_event` до окна не доходит, поэтому события подаются во вьюпорт так же,
## как их подаёт движок.
func _tap_touch(vp: Viewport, at: Vector2) -> void:
	var emulate: bool = ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true)
	for pressed in [true, false]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = at
		t.pressed = pressed
		vp.push_input(t)
		if emulate:
			var m := InputEventMouseButton.new()
			m.device = InputEvent.DEVICE_ID_EMULATION
			m.button_index = MOUSE_BUTTON_LEFT
			m.pressed = pressed
			m.position = at
			m.global_position = at
			vp.push_input(m)
	await wait_process_frames(1)


func _tap_mouse(vp: Viewport, at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	vp.push_input(motion)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		vp.push_input(e)
	await wait_process_frames(1)


# ---------------------------------------------------------------------------
# Скрытые строки: открытие и сброс
# ---------------------------------------------------------------------------

func test_dev_rows_hidden_until_five_mouse_clicks_on_version_row() -> void:
	var started := _start(MATRIX.CONFIGS[0], "ru")
	var vp: SubViewport = started[0]
	var main: AppMain = started[1]
	main.app_state.navigate(AppState.Screen.SETTINGS)
	await wait_process_frames(3)
	var settings := main.settings_screen()
	var diag := settings.diagnostics()
	assert_false(diag.benchmark_button().is_visible_in_tree(), "«Замер FPS» скрыт в обычном меню")
	assert_false(diag.fps_limit_check().is_visible_in_tree(), "«Ограничить FPS до 15» скрыто в обычном меню")
	var at: Vector2 = await _scroll_into_view(settings, _version_row(settings))
	for i in AboutDiagnostics.UNLOCK_TAPS - 1:
		await _tap_mouse(vp, at)
	assert_false(diag.are_dev_tools_visible(), "четыре щелчка не открывают строки")
	await _tap_mouse(vp, at)
	assert_true(diag.are_dev_tools_visible(), "пятый щелчок открывает строки")
	main.queue_free()
	await wait_process_frames(2)


func test_dev_rows_need_five_touch_taps_not_fewer() -> void:
	# На телефоне касание по умолчанию порождает и `InputEventScreenTouch`, и эмулированный щелчок
	# мыши (`input_devices/pointing/emulate_mouse_from_touch`) — одно касание = одно нажатие.
	var started := _start(MATRIX.CONFIGS[4], "ru")
	var vp: SubViewport = started[0]
	var main: AppMain = started[1]
	main.app_state.navigate(AppState.Screen.SETTINGS)
	await wait_process_frames(3)
	var settings := main.settings_screen()
	var diag := settings.diagnostics()
	var at: Vector2 = await _scroll_into_view(settings, _version_row(settings))
	var taps := 0
	while taps < AboutDiagnostics.UNLOCK_TAPS and not diag.are_dev_tools_visible():
		await _tap_touch(vp, at)
		taps += 1
	gut.p("emulate_mouse_from_touch = %s; строки открыты: %s после %d касаний" % [
		ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true),
		diag.are_dev_tools_visible(), taps])
	assert_true(diag.are_dev_tools_visible(), "касания по «Версии» открывают строки")
	assert_eq(taps, AboutDiagnostics.UNLOCK_TAPS, "строки открываются ровно пятым касанием, а не %d-м" % taps)
	main.queue_free()
	await wait_process_frames(2)


func test_dev_rows_hidden_again_after_shell_restart() -> void:
	var main := _main_in_root(_dir)
	main.app_state.navigate(AppState.Screen.SETTINGS)
	main.settings_screen().diagnostics().unlock_dev_tools()
	assert_true(main.settings_screen().diagnostics().benchmark_button().is_visible_in_tree())
	main.free()
	var again := _main_in_root(_dir)
	again.app_state.navigate(AppState.Screen.SETTINGS)
	await wait_process_frames(2)
	var diag := again.settings_screen().diagnostics()
	assert_false(diag.are_dev_tools_visible(), "после перезапуска строки разработчика снова скрыты")
	assert_false(diag.benchmark_button().is_visible_in_tree())
	again.free()


func test_save_log_row_is_in_about_section_after_version_and_licenses() -> void:
	var main := _main_in_root(_dir)
	main.app_state.navigate(AppState.Screen.SETTINGS)
	await wait_process_frames(2)
	var settings := main.settings_screen()
	var about := settings.section_node(SettingsSections.ABOUT)
	var diag := settings.diagnostics()
	assert_true(about.is_ancestor_of(diag), "строки диагностики — в «О программе» (UIX-04 п.3)")
	var version_row := _version_row(settings)
	assert_true(version_row.get_index() < diag.get_index(), "«Версия» выше журнала")
	main.free()


# ---------------------------------------------------------------------------
# Переводы
# ---------------------------------------------------------------------------

func test_new_keys_have_ru_and_en_translations() -> void:
	var f := FileAccess.open("res://assets/i18n/strings_menu.csv", FileAccess.READ)
	assert_not_null(f)
	var header := f.get_csv_line()
	var ru := header.find("ru")
	var en := header.find("en")
	var keys: Array[String] = []
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 2:
			continue
		for prefix in NEW_KEY_PREFIXES:
			if row[0].begins_with(prefix):
				keys.append(row[0])
				assert_false(row[ru].strip_edges().is_empty(), "%s: ru" % row[0])
				assert_false(row[en].strip_edges().is_empty(), "%s: en" % row[0])
				assert_ne(row[ru], row[en], "%s: ru и en различаются" % row[0])
	assert_gt(keys.size(), 15, "ключи диагностики найдены: %d" % keys.size())
	for locale in ["ru", "en"]:
		TranslationServer.set_locale(locale)
		for key in keys:
			assert_ne(TranslationServer.translate(key), StringName(key), "%s %s: перевод подгружен" % [locale, key])


# ---------------------------------------------------------------------------
# Матрица UIX-05 на открытых строках и экране замера
# ---------------------------------------------------------------------------

func _start(config: Dictionary, locale: String) -> Array:
	var dir := _dir + "%s_%s/" % [config["id"], locale]
	var settings := AppSettings.load_from(dir + "settings.json")
	settings.locale = locale
	settings.save()
	ProfileRepository.new(dir + "profiles/").create("Даша")
	var device: UiScale.Device = config["device"]
	if _runtime != null:
		_runtime.device = device
	if bool(config.get("safe", false)):
		Engine.set_meta(UiScale.DEBUG_SAFE_AREA_META, SAFE_AREA_LP)
	elif Engine.has_meta(UiScale.DEBUG_SAFE_AREA_META):
		Engine.remove_meta(UiScale.DEBUG_SAFE_AREA_META)
	var viewport := SubViewport.new()
	viewport.gui_embed_subwindows = true
	viewport.size = Vector2i(MATRIX.canvas_lp(config["px"], UiScale.scale_for(device, UiScale.Mode.MENU)))
	add_child_autofree(viewport)
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	viewport.add_child(main)
	if _runtime != null:
		_runtime.set_mode(UiScale.Mode.MENU)
	main.app_state.select_profile(main.repo.list()[0].id)
	TranslationServer.set_locale(locale)
	return [viewport, main]


func _matrix_run(config: Dictionary, locale: String, with_benchmark: bool) -> Array[String]:
	var issues: Array[String] = []
	var started := _start(config, locale)
	var viewport: SubViewport = started[0]
	var main: AppMain = started[1]
	var device: UiScale.Device = config["device"]
	var safe: Vector4 = SAFE_AREA_LP if bool(config.get("safe", false)) else Vector4.ZERO
	var tag := "%s %s" % [config["id"], locale]
	main.app_state.navigate(AppState.Screen.SETTINGS)
	await wait_process_frames(4)
	var settings := main.settings_screen()
	var diag := settings.diagnostics()
	diag.unlock_dev_tools()
	await wait_process_frames(3)
	var canvas := Vector2(viewport.size)
	var threshold: float = MATRIX.min_target_lp(device, canvas)
	if not with_benchmark:
		settings.scroll_container().ensure_control_visible(diag)
		await wait_process_frames(3)
		issues.append_array(_m._inspect(settings, canvas, safe, threshold, tag + " settings_dev_rows"))
	else:
		var bench := settings.start_fps_benchmark(RouteCatalog.MOUNTAINS, 600.0)
		bench.warmup_sec = 0.0
		await wait_process_frames(4)
		issues.append_array(_m._inspect(bench, canvas, safe, threshold, tag + " fps_benchmark_running"))
		bench.close()
		await wait_process_frames(2)
		bench = settings.start_fps_benchmark(RouteCatalog.MOUNTAINS, 0.2)
		bench.warmup_sec = 0.0
		var waited := 0
		while bench.is_running() and waited < 600:
			await wait_process_frames(1)
			waited += 1
		await wait_process_frames(3)
		if not bench.is_result_visible():
			issues.append("%s: итог замера не показан" % tag)
		else:
			issues.append_array(_m._inspect(bench, canvas, safe, threshold, tag + " fps_benchmark_result"))
			var card := bench.find_child("ResultCard", true, false) as Control
			var bounds := Rect2(Vector2(safe.x, safe.y), canvas - Vector2(safe.x + safe.z, safe.y + safe.w))
			if card != null and not bounds.grow(0.5).encloses(card.get_global_rect()):
				issues.append("%s: карточка итога %s вне окна/безопасной зоны %s" % [tag, card.get_global_rect(), bounds])
		bench.close()
		await wait_process_frames(2)
	main.queue_free()
	await wait_process_frames(2)
	return issues


func _run_all(locale: String, with_benchmark: bool) -> void:
	var all: Array[String] = []
	for config: Dictionary in MATRIX.CONFIGS:
		all.append_array(await _matrix_run(config, locale, with_benchmark))
	for issue in all:
		gut.p(issue)
	assert_eq(all.size(), 0, "%s: нарушений %d (первые: %s)" % [locale, all.size(), ", ".join(all.slice(0, 6))])


func test_unlocked_dev_rows_matrix_ru() -> void:
	await _run_all("ru", false)


func test_unlocked_dev_rows_matrix_en() -> void:
	await _run_all("en", false)


func test_fps_benchmark_screen_matrix_ru() -> void:
	await _run_all("ru", true)


func test_fps_benchmark_screen_matrix_en() -> void:
	await _run_all("en", true)
