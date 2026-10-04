extends GutTest
## T-145: диалоги меню по `docs/game/ui.md` п. 6 «Диалог» / «Диалог-выбор» и п. 9.1
## (REQ-UIX-01 п.8, 9; REQ-UIX-04; REQ-UIX-05 п.2; REQ-LOC-07 п.3). Обход всех диалогов оболочки
## и экранов меню (все `AcceptDialog`, кроме системного `FileDialog`), открытых как в приложении,
## на 1280×720 и телефоне 1280×590 с безопасной зоной, ru и en:
## - заголовок окна после показа — `title_font_size` 20 и шрифт `inter_700` (а не 16 / 400);
## - заливка: в обычном диалоге ровно одна кнопка с заливкой — основная `PrimaryButton` или
##   опасная `DangerButton`, крайняя справа; в «диалоге-выборе» (восстановление заезда) —
##   опасная слева и основная крайняя справа, «Отмены» нет;
## - первое открытие в сессии: окно вместе с полосой заголовка внутри холста и безопасной зоны,
##   размер первого и второго открытия совпадает (±2 lp).

const MAIN_SCENE: String = "res://src/app/main.tscn"
const MATRIX := preload("res://tests/unit/ui/test_ui_matrix.gd")
const TITLE_FONT: String = "res://src/ui/theme/fonts/inter_700.tres"
const SAFE_AREA_LP: Vector4 = Vector4(100.0, 0.0, 100.0, 13.0)
const CONFIGS: Array[Dictionary] = [
	{"id": "1280x720", "px": Vector2i(1280, 720), "device": UiScale.Device.DESKTOP},
	{"id": "1280x590_safe_phone", "px": Vector2i(1280, 590), "device": UiScale.Device.PHONE, "safe": true},
]
const FILLED: Array[StringName] = [&"PrimaryButton", &"DangerButton"]
const SIZE_TOLERANCE_LP: float = 2.0

var _dir: String = ""
var _prev_locale: String = ""
var _runtime: UiScale = null
var _prev_device: UiScale.Device = UiScale.Device.DESKTOP


func before_each() -> void:
	_dir = "user://test_menu_dialogs_ui6_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
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
	repo.create("Роман")
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
	main.app_state.select_profile(main.repo.list()[0].id)
	# Экраны создаются при первом переходе — обойти все экраны меню.
	for screen in [AppState.Screen.HOME, AppState.Screen.PLAN, AppState.Screen.ROUTE_SELECT,
			AppState.Screen.HISTORY, AppState.Screen.SETTINGS, AppState.Screen.DEVICES]:
		main.app_state.navigate(screen)
		await wait_process_frames(2)
	main.app_state.switch_profile()
	await wait_process_frames(2)
	return [viewport, main]


static func _dialogs(main: AppMain) -> Array[AcceptDialog]:
	var out: Array[AcceptDialog] = []
	for node in main.find_children("*", "AcceptDialog", true, false):
		if node is FileDialog:
			continue
		out.append(node as AcceptDialog)
	return out


static func _recovery_ride() -> Ride:
	var ride := Ride.new()
	ride.started_at_unix = int(Time.get_unix_time_from_system()) - 7200
	ride.id = Ride.generate_id(ride.started_at_unix)
	ride.name = "Sweet Spot 3×10 с длинным названием тренировки"
	ride.compute_summary()
	return ride


## Открыть диалог так же, как его открывает приложение.
func _open(main: AppMain, dialog: AcceptDialog) -> void:
	var owner_screen := dialog.get_parent()
	if dialog.name == &"LicensesDialog":
		var st := main.settings_screen()
		main.app_state.navigate(AppState.Screen.SETTINGS)
		await wait_process_frames(2)
		gut.p("DBG licenses: in_tree=%s vp=%s rect=%s" % [st.is_inside_tree(), st.get_viewport_rect(), SettingsScreen.licenses_rect(st.get_viewport_rect().size, Vector4.ZERO, false)])
		main.settings_screen().open_licenses()
		gut.p("DBG after popup: size=%s pos=%s" % [dialog.size, dialog.position])
	elif dialog is IntervalsKeyDialog:
		(dialog as IntervalsKeyDialog).open("")
	elif dialog is RecoveryDialog:
		var rides: Array[Ride] = [_recovery_ride()]
		(dialog as RecoveryDialog).show_for(rides)
	elif owner_screen is ProfileSelectScreen and dialog.name == &"CreateDialog":
		(owner_screen as ProfileSelectScreen).open_create_form()
	else:
		dialog.popup_centered()
	await wait_process_frames(3)


## Видимые кнопки диалога слева направо: ряд окна и кнопки формы внутри содержимого.
static func _visible_buttons(dialog: AcceptDialog) -> Array[Button]:
	var out: Array[Button] = []
	for node in dialog.find_children("*", "Button", true, false):
		var b := node as Button
		if b.is_visible_in_tree() and not b is OptionButton and not b is CheckButton:
			out.append(b)
	for b in DialogLayout.row_buttons(dialog):
		if b.is_visible_in_tree() and not out.has(b):
			out.append(b)
	return out


static func _title_issues(dialog: AcceptDialog, where: String) -> Array[String]:
	var issues: Array[String] = []
	var size := dialog.get_theme_font_size(&"title_font_size")
	if size != 20:
		issues.append("%s: кегль заголовка %d ≠ 20" % [where, size])
	var font := dialog.get_theme_font(&"title_font")
	if font == null or font.resource_path != TITLE_FONT:
		issues.append("%s: шрифт заголовка %s ≠ inter_700" % [where, font.resource_path if font != null else "null"])
	return issues


static func _fill_issues(dialog: AcceptDialog, where: String) -> Array[String]:
	var issues: Array[String] = []
	var shown := _visible_buttons(dialog)
	var filled: Array[Button] = []
	var rightmost: Button = null
	for b in shown:
		if FILLED.has(b.theme_type_variation):
			filled.append(b)
		# Кнопки решения — в одном ряду внизу: крайняя справа — с наибольшим правым краем.
		if rightmost == null or b.get_global_rect().end.x > rightmost.get_global_rect().end.x + 0.5:
			rightmost = b
	var names := ", ".join(shown.map(func(b: Button) -> String: return "%s[%s]" % [b.text, b.theme_type_variation]))
	if dialog is RecoveryDialog:
		# «Диалог-выбор»: опасная слева, основная крайняя справа, «Отмены» нет.
		var rec := dialog as RecoveryDialog
		if filled.size() != 2 or rec.delete_button().theme_type_variation != &"DangerButton" \
				or rec.get_ok_button().theme_type_variation != &"PrimaryButton":
			issues.append("%s: диалог-выбор — ожидались Danger + Primary, кнопки: %s" % [where, names])
		if rightmost != rec.get_ok_button():
			issues.append("%s: основная не крайняя справа (%s)" % [where, names])
		if rec.get_cancel_button().is_visible_in_tree():
			issues.append("%s: у диалога-выбора видна «Отмена»" % where)
		return issues
	if filled.size() != 1:
		issues.append("%s: кнопок с заливкой %d ≠ 1 (%s)" % [where, filled.size(), names])
	elif filled[0] != rightmost:
		issues.append("%s: кнопка с заливкой не крайняя справа (%s)" % [where, names])
	return issues


## Содержимое помещается в окно: текст диалога не обрезан, кнопки внутри окна.
static func _content_issues(dialog: AcceptDialog, where: String) -> Array[String]:
	var issues: Array[String] = []
	var label := dialog.get_label()
	if label.is_visible_in_tree() and label.get_visible_line_count() < label.get_line_count():
		issues.append("%s: текст обрезан (%d из %d строк)" % [where, label.get_visible_line_count(), label.get_line_count()])
	var window := Rect2(Vector2.ZERO, Vector2(dialog.size))
	for b in _visible_buttons(dialog):
		if not window.grow(0.5).encloses(b.get_global_rect()):
			issues.append("%s: кнопка «%s» %s вне окна %s" % [where, b.text, b.get_global_rect(), window])
	return issues


static func _bounds(viewport: Viewport, config: Dictionary) -> Rect2:
	var safe: Vector4 = SAFE_AREA_LP if bool(config.get("safe", false)) else Vector4.ZERO
	var canvas := Vector2(viewport.size)
	return Rect2(Vector2(safe.x, safe.y), canvas - Vector2(safe.x + safe.z, safe.y + safe.w))


## Окно вместе с полосой заголовка (она рисуется над `position`).
static func _full_rect(dialog: AcceptDialog) -> Rect2:
	var title_h := float(dialog.get_theme_constant(&"title_height"))
	return Rect2(Vector2(dialog.position) - Vector2(0.0, title_h), Vector2(dialog.size) + Vector2(0.0, title_h))


func _check_all(config: Dictionary, locale: String) -> Array[String]:
	var issues: Array[String] = []
	var started: Array = await _start(config, locale)
	var viewport: SubViewport = started[0]
	var main: AppMain = started[1]
	var dialogs := _dialogs(main)
	gut.p("%s %s: диалогов %d" % [config["id"], locale, dialogs.size()])
	if dialogs.size() < 10:
		issues.append("%s %s: найдено диалогов %d < 10" % [config["id"], locale, dialogs.size()])
	var bounds := _bounds(viewport, config)
	for dialog in dialogs:
		var where := "%s %s %s" % [config["id"], locale, dialog.name]
		var sizes: Array[Vector2] = []
		for attempt in 2:
			await _open(main, dialog)
			if not dialog.visible:
				issues.append("%s: не открылся (открытие %d)" % [where, attempt + 1])
				continue
			var full := _full_rect(dialog)
			sizes.append(Vector2(dialog.size))
			if attempt == 0:
				gut.p("%s: окно %s, кнопки: %s" % [where, full, ", ".join(_visible_buttons(dialog).map(func(b: Button) -> String: return "%s[%s]" % [b.text, b.theme_type_variation]))])
				issues.append_array(_title_issues(dialog, where))
				issues.append_array(_fill_issues(dialog, where))
			issues.append_array(_content_issues(dialog, "%s (открытие %d)" % [where, attempt + 1]))
			if not bounds.grow(0.5).encloses(full):
				issues.append("%s: открытие %d — окно с заголовком %s вне холста/безопасной зоны %s" % [where, attempt + 1, full, bounds])
			dialog.hide()
			await wait_process_frames(2)
		if sizes.size() == 2 and (absf(sizes[0].x - sizes[1].x) > SIZE_TOLERANCE_LP or absf(sizes[0].y - sizes[1].y) > SIZE_TOLERANCE_LP):
			issues.append("%s: размер первого открытия %s ≠ второго %s" % [where, sizes[0], sizes[1]])
	main.queue_free()
	await wait_process_frames(2)
	return issues


func _run(locale: String) -> void:
	var all: Array[String] = []
	for config in CONFIGS:
		all.append_array(await _check_all(config, locale))
	for e in get_errors():
		if e.contains_text("spawned at invalid position"):
			all.append("движок: %s" % str(e.code))
			e.handled = true
	for issue in all:
		gut.p(issue)
	assert_eq(all.size(), 0, "нарушений %d (первые: %s)" % [all.size(), ", ".join(all.slice(0, 6))])


## Причина дефекта Н-38 (16 / 400): у темы есть `default_font` / `default_font_size`, и шрифт
## заголовка, заданный только для `Window`, до классов-наследников не доходил. Тема проекта —
## у каждого типа окна с заголовком и у вариации `FormDialog`.
func test_req_uix_01_window_title_font_reaches_every_dialog_type() -> void:
	var dialogs: Array[Window] = [AcceptDialog.new(), ConfirmationDialog.new(), FileDialog.new()]
	var form := AcceptDialog.new()
	form.theme_type_variation = &"FormDialog"
	dialogs.append(form)
	var form_confirm := ConfirmationDialog.new()
	form_confirm.theme_type_variation = &"FormDialog"
	dialogs.append(form_confirm)
	for d in dialogs:
		add_child_autofree(d)
		var where := "%s/%s" % [d.get_class(), d.theme_type_variation]
		assert_eq(d.get_theme_font_size(&"title_font_size"), 20, "%s: кегль заголовка 20" % where)
		var font := d.get_theme_font(&"title_font")
		assert_eq(font.resource_path if font != null else "", TITLE_FONT, "%s: шрифт заголовка inter_700" % where)


func test_req_uix_01_menu_dialogs_title_fill_first_open_ru() -> void:
	await _run("ru")


func test_req_uix_01_menu_dialogs_title_fill_first_open_en() -> void:
	await _run("en")
