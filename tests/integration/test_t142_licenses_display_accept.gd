extends GutTest
## Приёмка T-142 (tester): лист лицензий — **фактическое** окно, а не план раскладки
## (REQ-UIX-05 п.2, REQ-UIX-04 п.3 «О программе»). `test_licenses_sheet_reaccept` проверяет
## план `SettingsScreen.licenses_rect` и фактическое положение: headless-движок сжимает
## `popup(rect)` встроенного окна до минимума содержимого (128 × 128). Здесь — фактический размер
## и положение окна вместе с полосой заголовка; запуск — с дисплеем (`xvfb-run`, рендер
## gl_compatibility), в headless-прогоне тест помечается pending:
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s addons/gut/gut_cmdln.gd \
##     -gconfig=res://.gutconfig.json -gselect=test_t142_licenses_display_accept
## На всех разрешениях вводного абзаца UIX, ru и en: окно лицензий равно плану (±1 lp), с
## полосой заголовка — в холсте и безопасной зоне; compact — лист во всю ширину безопасной зоны и
## прижат к её низу; regular — 560 × 360 по центру; под окном вуаль на весь холст; Esc закрывает.

const MAIN_SCENE: String = "res://src/app/main.tscn"
const MATRIX := preload("res://tests/unit/ui/test_ui_matrix.gd")
const SAFE_AREA_LP: Vector4 = Vector4(100.0, 0.0, 100.0, 13.0)
const CONFIGS: Array[Dictionary] = [
	{"id": "1280x720", "px": Vector2i(1280, 720), "device": UiScale.Device.DESKTOP},
	{"id": "1920x1080", "px": Vector2i(1920, 1080), "device": UiScale.Device.DESKTOP},
	{"id": "2732x2048", "px": Vector2i(2732, 2048), "device": UiScale.Device.TABLET},
	{"id": "1024x768", "px": Vector2i(1024, 768), "device": UiScale.Device.TABLET},
	{"id": "2556x1179_safe", "px": Vector2i(2556, 1179), "device": UiScale.Device.PHONE, "safe": true},
	{"id": "1280x590_safe", "px": Vector2i(1280, 590), "device": UiScale.Device.PHONE, "safe": true},
]

var _dir: String = ""
var _prev_locale: String = ""
var _runtime: UiScale = null
var _prev_device: UiScale.Device = UiScale.Device.DESKTOP


func before_each() -> void:
	_dir = "user://test_t142_licenses_display_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_prev_locale = TranslationServer.get_locale()
	_runtime = TouchTarget.default_runtime()
	if _runtime != null:
		_prev_device = _runtime.device


func after_each() -> void:
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


func _run(config: Dictionary, locale: String) -> Array[String]:
	var issues: Array[String] = []
	var dir := _dir + "%s_%s/" % [config["id"], locale]
	var settings := AppSettings.load_from(dir + "settings.json")
	settings.locale = locale
	settings.save()
	ProfileRepository.new(dir + "profiles/").create("Даша")
	var device: UiScale.Device = config["device"]
	if _runtime != null:
		_runtime.device = device
	var safe: Vector4 = SAFE_AREA_LP if bool(config.get("safe", false)) else Vector4.ZERO
	if bool(config.get("safe", false)):
		Engine.set_meta(UiScale.DEBUG_SAFE_AREA_META, SAFE_AREA_LP)
	elif Engine.has_meta(UiScale.DEBUG_SAFE_AREA_META):
		Engine.remove_meta(UiScale.DEBUG_SAFE_AREA_META)
	var viewport := SubViewport.new()
	viewport.gui_embed_subwindows = true
	viewport.size = Vector2i(MATRIX.canvas_lp(config["px"], UiScale.scale_for(device, UiScale.Mode.MENU)))
	add_child_autofree(viewport)
	TranslationServer.set_locale(locale)
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	viewport.add_child(main)
	if _runtime != null:
		_runtime.set_mode(UiScale.Mode.MENU)
	main.app_state.select_profile(main.repo.list()[0].id)
	main.app_state.navigate(AppState.Screen.SETTINGS)
	await wait_process_frames(4)
	var where := "%s %s licenses" % [config["id"], locale]
	var s := main.settings_screen()
	var dialog := s.get_node("%LicensesDialog") as AcceptDialog
	for attempt in 2:
		var w := "%s (открытие %d)" % [where, attempt + 1]
		s.open_licenses()
		await wait_process_frames(4)
		if not dialog.visible:
			issues.append("%s: не открылось" % w)
			continue
		var canvas := Vector2(viewport.size)
		var bounds := Rect2(Vector2(safe.x, safe.y), canvas - Vector2(safe.x + safe.z, safe.y + safe.w))
		var compact := canvas.x < AppBar.COMPACT_MAX_WIDTH
		var planned := SettingsScreen.licenses_rect(canvas, safe, compact)
		var rect := Rect2(Vector2(dialog.position), Vector2(dialog.size))
		var title_h := float(dialog.get_theme_constant(&"title_height"))
		var full := Rect2(rect.position - Vector2(0.0, title_h), rect.size + Vector2(0.0, title_h))
		gut.p("%s: холст %s, план %s, окно %s, область %s" % [w, canvas, planned, rect, bounds])
		if absf(rect.size.x - planned.size.x) > 1.0 or absf(rect.size.y - planned.size.y) > 1.0:
			issues.append("%s: размер окна %s ≠ плану %s" % [w, rect.size, planned.size])
		if not bounds.grow(0.5).encloses(full):
			issues.append("%s: окно с заголовком %s вне безопасной зоны %s" % [w, full, bounds])
		if compact:
			if absf(rect.size.x - bounds.size.x) > 1.0:
				issues.append("%s: compact — ширина %.0f ≠ %.0f" % [w, rect.size.x, bounds.size.x])
			if absf(rect.end.y - bounds.end.y) > 1.0:
				issues.append("%s: compact — низ %.0f ≠ %.0f" % [w, rect.end.y, bounds.end.y])
		else:
			if absf(rect.size.x - 560.0) > 1.0 or absf(rect.size.y - minf(360.0, planned.size.y)) > 1.0:
				issues.append("%s: regular — окно %s ≠ 560 × 360" % [w, rect.size])
			if absf(full.get_center().x - bounds.get_center().x) > 1.0:
				issues.append("%s: не по центру" % w)
		var ok := dialog.get_ok_button()
		if not Rect2(Vector2.ZERO, rect.size).grow(0.5).encloses(ok.get_global_rect()):
			issues.append("%s: «OK» %s вне окна %s" % [w, ok.get_global_rect(), rect.size])
		var scroll := dialog.find_child("LicensesScroll", true, false) as ScrollContainer
		if scroll == null or not Rect2(Vector2.ZERO, rect.size).grow(0.5).encloses(scroll.get_global_rect()):
			issues.append("%s: прокрутка %s вне окна" % [w, scroll.get_global_rect() if scroll != null else Rect2()])
		var layout := DialogLayout.of(dialog)
		if layout == null or not layout.is_scrim_visible():
			issues.append("%s: нет вуали" % w)
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.physical_keycode = KEY_ESCAPE
		esc.pressed = true
		viewport.push_input(esc)
		await wait_process_frames(2)
		if dialog.visible:
			issues.append("%s: Esc не закрыл" % w)
			dialog.hide()
	main.queue_free()
	await wait_process_frames(2)
	return issues


func test_req_uix_05_c2_licenses_actual_window_with_display_ru_en() -> void:
	if DisplayServer.get_name() == "headless":
		pending("нужен дисплей: headless сжимает popup(rect) до 128 × 128 — запуск под xvfb-run")
		return
	var all: Array[String] = []
	for config in CONFIGS:
		for locale in ["ru", "en"]:
			all.append_array(await _run(config, locale))
	# С дисплеем журнал диагностики при выходе пишет сводку кадров с NaN (предупреждение движка
	# JSON.stringify) — к листу лицензий не относится, вынесено в отчёт приёмки отдельно.
	for e in get_errors():
		if e.contains_text("found in argument passed to JSON.stringify"):
			gut.p("НАБЛЮДЕНИЕ (вне T-142): %s" % e.contains_text("NaN"))
			e.handled = true
	for i in all:
		gut.p(i)
	assert_eq(all.size(), 0, "нарушений %d (первые: %s)" % [all.size(), ", ".join(all.slice(0, 6))])
