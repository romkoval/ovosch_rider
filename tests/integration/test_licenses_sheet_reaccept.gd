extends GutTest
## Повторная приёмка T-103 (tester): «О программе» → лицензии (REQ-UIX-04 крит. 3) на всех
## разрешениях вводного абзаца UIX, ru и en, с проверками REQ-UIX-05 крит. 1–3:
## - regular/wide — окно 560 × 360 по центру; compact (телефон) — лист во всю ширину области
##   безопасной зоны, прижат к низу (снимки настоящего окна — accept2/licenses_*.png в отчёте);
## - окно **вместе с заголовком окна** (полоса заголовка встроенного окна рисуется над
##   `position`) лежит в окне приложения и в безопасной зоне;
## - текст прокручивается внутри, кнопка «OK» — цель нажатия по UIX-05 крит. 1, не обрезана;
##   Esc закрывает.

const MAIN_SCENE: String = "res://src/app/main.tscn"
const MATRIX := preload("res://tests/unit/ui/test_ui_matrix.gd")
const SAFE_AREA_LP: Vector4 = Vector4(100.0, 0.0, 100.0, 13.0)
const CONFIGS: Array[Dictionary] = [
	{"id": "1280x720", "px": Vector2i(1280, 720), "device": UiScale.Device.DESKTOP},
	{"id": "1920x1080", "px": Vector2i(1920, 1080), "device": UiScale.Device.DESKTOP},
	{"id": "2732x2048", "px": Vector2i(2732, 2048), "device": UiScale.Device.TABLET},
	{"id": "1024x768", "px": Vector2i(1024, 768), "device": UiScale.Device.TABLET},
	{"id": "2556x1179_safe", "px": Vector2i(2556, 1179), "device": UiScale.Device.PHONE, "safe": true},
	{"id": "2556x1179", "px": Vector2i(2556, 1179), "device": UiScale.Device.PHONE},
	{"id": "1280x590_safe", "px": Vector2i(1280, 590), "device": UiScale.Device.PHONE, "safe": true},
]

var _dir: String = ""
var _prev_locale: String = ""
var _runtime: UiScale = null
var _prev_device: UiScale.Device = UiScale.Device.DESKTOP
var _m: Node = null


func before_each() -> void:
	_dir = "user://test_licenses_sheet_reaccept_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_prev_locale = TranslationServer.get_locale()
	_runtime = TouchTarget.default_runtime()
	if _runtime != null:
		_prev_device = _runtime.device
	_m = MATRIX.new()
	add_child_autofree(_m)


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


func _run(config: Dictionary, locale: String) -> void:
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
	main.app_state.navigate(AppState.Screen.SETTINGS)
	await wait_process_frames(4)
	var s := main.settings_screen()
	s.open_licenses()
	await wait_process_frames(4)
	var where := "%s %s licenses" % [config["id"], locale]
	var dialog := s.get_node("%LicensesDialog") as AcceptDialog
	assert_true(dialog.visible, "%s: окно лицензий открыто" % where)
	var canvas := Vector2(viewport.size)
	var bounds := Rect2(Vector2(safe.x, safe.y), canvas - Vector2(safe.x + safe.z, safe.y + safe.w))
	# Размер окна берётся из раскладки экрана (`licenses_rect`): headless-окно в SubViewport
	# после `popup(rect)` сжимается до минимума содержимого, а в настоящем окне приложения
	# размер — заданный (снимки accept2/licenses_*.png). Положение — фактическое: движок
	# сдвигает встроенное окно так, чтобы полоса заголовка не уходила за верх холста.
	var compact := canvas.x < AppBar.COMPACT_MAX_WIDTH
	var planned := SettingsScreen.licenses_rect(canvas, safe, compact)
	var title_h := float(dialog.get_theme_constant("title_height"))
	var rect := Rect2(Vector2(dialog.position), planned.size)
	var full := Rect2(rect.position - Vector2(0.0, title_h), rect.size + Vector2(0.0, title_h))
	gut.p("%s: холст %s, план %s, фактическое окно %s, с заголовком %s, область %s" % [where, canvas, planned, rect, full, bounds])
	assert_true(bounds.grow(0.5).encloses(full), "%s: окно с заголовком %s в окне и безопасной зоне %s" % [where, full, bounds])
	if compact:
		assert_almost_eq(planned.size.x, bounds.size.x, 1.0, "%s: compact — лист во всю ширину" % where)
		assert_almost_eq(rect.end.y, bounds.end.y, 1.0, "%s: compact — лист прижат к низу безопасной зоны" % where)
	else:
		assert_almost_eq(planned.size.x, 560.0, 1.0, "%s: ширина 560" % where)
		assert_almost_eq(planned.size.y, 360.0, 1.0, "%s: высота 360" % where)
		assert_almost_eq(rect.get_center().x, bounds.get_center().x, 1.0, "%s: по центру" % where)
	assert_not_null(dialog.find_child("LicensesScroll", true, false) as ScrollContainer, "%s: текст в прокрутке" % where)
	var ok := dialog.get_ok_button()
	var threshold := MATRIX.min_target_lp(device, canvas)
	assert_gte(ok.size.x + 0.01, threshold, "%s: ширина «OK» %.1f ≥ %.1f" % [where, ok.size.x, threshold])
	assert_gte(ok.size.y + 0.01, threshold, "%s: высота «OK» %.1f ≥ %.1f" % [where, ok.size.y, threshold])
	var issues: Array[String] = []
	_m._check_button_text(ok, ok.get_parent() as Control, where, issues)
	assert_eq(issues, [] as Array[String], "%s: текст кнопки не обрезан" % where)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	viewport.push_input(esc)
	await wait_process_frames(2)
	assert_false(dialog.visible, "%s: Esc закрыл" % where)
	main.queue_free()
	await wait_process_frames(2)


func test_req_uix_04_c3_licenses_all_resolutions_ru() -> void:
	for config in CONFIGS:
		await _run(config, "ru")


func test_req_uix_04_c3_licenses_all_resolutions_en() -> void:
	for config in CONFIGS:
		await _run(config, "en")
