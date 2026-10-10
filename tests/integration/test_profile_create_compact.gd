extends GutTest
## T-174: форма «Новый профиль» — каждое поле с подписью целиком в видимой области прокрутки
## (REQ-UIX-05 п.2 — дополнение Н-76 (в), REQ-PRF-01) на разрешениях вводного абзаца UIX, в том
## числе телефон 1280×590 с безопасной зоной; ru и en; первое и повторное открытие. Окно с полосой
## заголовка — в безопасной зоне; создание профиля сохраняет значения (регрессия PRF-01).

const MAIN_SCENE: String = "res://src/app/main.tscn"
const MATRIX := preload("res://tests/unit/ui/test_ui_matrix.gd")
const SAFE_AREA_LP: Vector4 = Vector4(100.0, 0.0, 100.0, 13.0)
const CONFIGS: Array[Dictionary] = [
	{"id": "1280x720", "px": Vector2i(1280, 720), "device": UiScale.Device.DESKTOP},
	{"id": "1024x768", "px": Vector2i(1024, 768), "device": UiScale.Device.DESKTOP},
	{"id": "1280x590_safe_phone", "px": Vector2i(1280, 590), "device": UiScale.Device.PHONE, "safe": true},
]
const FIELDS: Array[String] = ["NameField", "FtpField", "WeightField", "MaxHrField"]
const EPS: float = 0.5

var _dir: String = ""
var _prev_locale: String = ""
var _runtime: UiScale = null
var _prev_device: UiScale.Device = UiScale.Device.DESKTOP


func before_each() -> void:
	_dir = "user://test_profile_create_compact_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
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


func _start(config: Dictionary, locale: String) -> Array:
	var dir := _dir + "%s_%s/" % [config["id"], locale]
	var settings := AppSettings.load_from(dir + "settings.json")
	settings.locale = locale
	settings.save()
	var repo := ProfileRepository.new(dir + "profiles/")
	repo.create("Даша")
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
	TranslationServer.set_locale(locale)
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	viewport.add_child(main)
	if _runtime != null:
		_runtime.set_mode(UiScale.Mode.MENU)
	main.app_state.switch_profile()
	await wait_process_frames(2)
	return [viewport, main]


static func _bounds(viewport: Viewport, config: Dictionary) -> Rect2:
	var safe: Vector4 = SAFE_AREA_LP if bool(config.get("safe", false)) else Vector4.ZERO
	var canvas := Vector2(viewport.size)
	return Rect2(Vector2(safe.x, safe.y), canvas - Vector2(safe.x + safe.z, safe.y + safe.w))


static func _inside(inner: Rect2, outer: Rect2) -> bool:
	return inner.position.x >= outer.position.x - EPS and inner.position.y >= outer.position.y - EPS \
		and inner.end.x <= outer.end.x + EPS and inner.end.y <= outer.end.y + EPS


func _issues(screen: ProfileSelectScreen, viewport: Viewport, config: Dictionary, where: String) -> Array[String]:
	var out: Array[String] = []
	var dialog := screen.get_node("%CreateDialog") as AcceptDialog
	var scroll := screen.get_node("%FieldsScroll") as ScrollContainer
	var visible_rect := scroll.get_global_rect()
	for field_name in FIELDS:
		var field := scroll.find_child(field_name, true, false) as Control
		if field == null:
			out.append("%s: нет поля %s" % [where, field_name])
			continue
		var r := field.get_global_rect()
		if not _inside(r, visible_rect):
			out.append("%s: %s %s не целиком в видимой области прокрутки %s" % [where, field_name, r, visible_rect])
		for c in field.find_children("*", "Label", true, false):
			var label := c as Label
			if label.get_line_count() > label.get_visible_line_count() or label.get_minimum_size().x > label.size.x + EPS:
				out.append("%s: подпись %s обрезана" % [where, label.text])
	var title_h := float(dialog.get_theme_constant(&"title_height"))
	var full := Rect2(Vector2(dialog.position) - Vector2(0.0, title_h), Vector2(dialog.size) + Vector2(0.0, title_h))
	if not _inside(full, _bounds(viewport, config)):
		out.append("%s: окно %s вне безопасной зоны %s" % [where, full, _bounds(viewport, config)])
	return out


func _run(locale: String) -> void:
	var issues: Array[String] = []
	for config in CONFIGS:
		var started: Array = await _start(config, locale)
		var viewport: SubViewport = started[0]
		var main: AppMain = started[1]
		var screen := main.screen_node(AppState.Screen.PROFILE_SELECT) as ProfileSelectScreen
		for attempt in ["первое", "повторное"]:
			screen.open_create_form()
			await wait_process_frames(3)
			issues.append_array(_issues(screen, viewport, config, "%s %s %s" % [config["id"], locale, attempt]))
			screen.close_create_form()
			await wait_process_frames(2)
		viewport.queue_free()
		await wait_process_frames(1)
	assert_eq(issues, [] as Array[String])


func test_req_uix_05_c2_profile_create_fields_fully_visible_ru() -> void:
	await _run("ru")


func test_req_uix_05_c2_profile_create_fields_fully_visible_en() -> void:
	await _run("en")


func test_req_prf_01_create_keeps_values_on_phone() -> void:
	var started: Array = await _start(CONFIGS[2], "ru")
	var main: AppMain = started[1]
	var screen := main.screen_node(AppState.Screen.PROFILE_SELECT) as ProfileSelectScreen
	screen.open_create_form()
	await wait_process_frames(3)
	screen.fill_create_form("Рома", 260, 72.5, 185)
	var p := screen.submit_create()
	assert_not_null(p)
	if p != null:
		assert_eq([p.name, p.ftp_w, p.max_hr], ["Рома", 260, 185])
		assert_almost_eq(p.weight_kg, 72.5, 0.01)
