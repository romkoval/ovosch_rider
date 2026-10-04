extends GutTest
## Приёмка T-142 (tester): вуаль `scrim` под диалогами меню (REQ-UIX-01 п.9, `ui.md` п. 6:
## «scrim под ним», токен `scrim` — #000000, альфа 0.55) — независимые проверки.
## - каждый диалог оболочки и экранов меню (обход всех экранов, все `AcceptDialog`, кроме
##   системного `FileDialog`), открытый как в приложении, — под ним вуаль на весь холст, в том
##   числе в отступах безопасной зоны телефона; закрыт — вуали нет; повторное открытие — снова есть;
## - диалог удаления заезда (настоящий путь: история → карточка → «Удалить») на 1280×720,
##   1024×768 и телефоне 1280×590 с безопасной зоной, ru и en: вуаль на весь холст, кнопки
##   показывают перевод («Отмена»/«Удалить», "Cancel"/"Delete"), а не ключи `ui.common.*`.

const MAIN_SCENE: String = "res://src/app/main.tscn"
const MATRIX := preload("res://tests/unit/ui/test_ui_matrix.gd")
const SAFE_AREA_LP: Vector4 = Vector4(100.0, 0.0, 100.0, 13.0)
const CONFIGS: Array[Dictionary] = [
	{"id": "1280x720", "px": Vector2i(1280, 720), "device": UiScale.Device.DESKTOP},
	{"id": "1024x768", "px": Vector2i(1024, 768), "device": UiScale.Device.TABLET},
	{"id": "1280x590_safe_phone", "px": Vector2i(1280, 590), "device": UiScale.Device.PHONE, "safe": true},
]
const BUTTON_TEXTS: Dictionary = {"ru": ["Отмена", "Удалить"], "en": ["Cancel", "Delete"]}

var _dir: String = ""
var _prev_locale: String = ""
var _runtime: UiScale = null
var _prev_device: UiScale.Device = UiScale.Device.DESKTOP


func before_each() -> void:
	_dir = "user://test_t142_scrim_accept_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
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


## Нарушения вуали под видимым диалогом `dialog` в холсте `viewport`.
static func _scrim_issues(dialog: AcceptDialog, viewport: Viewport, where: String) -> Array[String]:
	var issues: Array[String] = []
	var layout := DialogLayout.of(dialog)
	if layout == null:
		issues.append("%s: нет DialogLayout" % where)
		return issues
	if not dialog.visible:
		issues.append("%s: диалог не открыт" % where)
	if not layout.is_scrim_visible():
		issues.append("%s: вуали нет" % where)
		return issues
	var scrim := layout.scrim()
	if not scrim.is_visible_in_tree():
		issues.append("%s: вуаль не видна в дереве" % where)
	if not scrim.color.is_equal_approx(Color(0, 0, 0, 0.55)):
		issues.append("%s: цвет вуали %s ≠ scrim #000000/0.55" % [where, scrim.color])
	var canvas := Rect2(Vector2.ZERO, Vector2(viewport.size))
	var covered := Rect2(scrim.get_global_rect().position, scrim.get_global_rect().size)
	if not covered.grow(0.5).encloses(canvas):
		issues.append("%s: вуаль %s не закрывает холст %s" % [where, covered, canvas])
	var layer := scrim.get_parent() as CanvasLayer
	if layer == null or layer.get_viewport() == null:
		issues.append("%s: вуаль не в CanvasLayer" % where)
	elif layer.custom_viewport != null and layer.custom_viewport != viewport:
		issues.append("%s: вуаль в чужом вьюпорте" % where)
	return issues


func _all_dialogs(main: AppMain) -> Array[AcceptDialog]:
	var out: Array[AcceptDialog] = []
	for node in main.find_children("*", "AcceptDialog", true, false):
		if node is FileDialog:
			continue
		out.append(node as AcceptDialog)
	return out


# ---------------------------------------------------------------------------
# Все диалоги меню
# ---------------------------------------------------------------------------

func _every_dialog(config: Dictionary, locale: String) -> Array[String]:
	var issues: Array[String] = []
	var started := _start(config, locale)
	var viewport: SubViewport = started[0]
	var main: AppMain = started[1]
	# Экраны создаются при первом переходе — обойти все экраны меню.
	for screen in [AppState.Screen.HOME, AppState.Screen.PLAN, AppState.Screen.ROUTE_SELECT,
			AppState.Screen.HISTORY, AppState.Screen.SETTINGS, AppState.Screen.DEVICES]:
		main.app_state.navigate(screen)
		await wait_process_frames(2)
	main.app_state.switch_profile()
	await wait_process_frames(2)
	var dialogs := _all_dialogs(main)
	gut.p("%s %s: диалогов %d: %s" % [config["id"], locale, dialogs.size(), ", ".join(dialogs.map(func(d: AcceptDialog) -> String: return str(d.name)))])
	if dialogs.size() < 10:
		issues.append("%s %s: найдено диалогов %d < 10" % [config["id"], locale, dialogs.size()])
	for dialog in dialogs:
		var where := "%s %s %s" % [config["id"], locale, dialog.name]
		var host_vp := dialog.get_parent().get_viewport()
		for attempt in 2:
			if dialog.name == &"LicensesDialog":
				# Лист лицензий открывается своей раскладкой (`open_licenses`), как в приложении.
				main.settings_screen().open_licenses()
			elif dialog is IntervalsKeyDialog:
				# Форма ключа открывается своим методом (размер и фокус), как в приложении.
				(dialog as IntervalsKeyDialog).open("")
			else:
				dialog.popup_centered()
			await wait_process_frames(2)
			issues.append_array(_scrim_issues(dialog, host_vp, "%s (открытие %d)" % [where, attempt + 1]))
			dialog.hide()
			await wait_process_frames(1)
			var layout := DialogLayout.of(dialog)
			if layout != null and layout.is_scrim_visible():
				issues.append("%s: после закрытия вуаль осталась" % where)
	main.queue_free()
	await wait_process_frames(2)
	return issues


func test_every_menu_dialog_has_full_canvas_scrim_ru_en() -> void:
	var all: Array[String] = []
	for config in [CONFIGS[0], CONFIGS[2]]:
		for locale in ["ru", "en"]:
			all.append_array(await _every_dialog(config, locale))
	# Первое открытие формы ключа Intervals.icu движок ругает «spawned at invalid position» —
	# это отдельный дефект раскладки (`test_intervals_key_dialog_first_open_fits_canvas`), к
	# вуали отношения не имеет: здесь ошибки помечены обработанными.
	for e in get_errors():
		if e.contains_text("spawned at invalid position"):
			e.handled = true
	for issue in all:
		gut.p(issue)
	assert_eq(all.size(), 0, "нарушений %d (первые: %s)" % [all.size(), ", ".join(all.slice(0, 6))])


# ---------------------------------------------------------------------------
# Форма ключа Intervals.icu при первом открытии (регрессия UIX-05 п.2, найдено при обходе)
# ---------------------------------------------------------------------------

func test_intervals_key_dialog_first_open_fits_canvas() -> void:
	var all: Array[String] = []
	for config in CONFIGS:
		var started := _start(config, "ru")
		var viewport: SubViewport = started[0]
		var main: AppMain = started[1]
		var safe: Vector4 = SAFE_AREA_LP if bool(config.get("safe", false)) else Vector4.ZERO
		main.app_state.navigate(AppState.Screen.SETTINGS)
		await wait_process_frames(3)
		var settings := main.settings_screen()
		settings.open_key_dialog()
		await wait_process_frames(4)
		var dialog := settings.find_child("IntervalsKeyDialog", true, false) as Window
		var canvas := Vector2(viewport.size)
		var bounds := Rect2(Vector2(safe.x, safe.y), canvas - Vector2(safe.x + safe.z, safe.y + safe.w))
		var rect := Rect2(Vector2(dialog.position), Vector2(dialog.size))
		gut.p("%s: первое открытие — окно %s, холст %s" % [config["id"], rect, canvas])
		if not bounds.grow(0.5).encloses(rect):
			all.append("%s: форма ключа при первом открытии %s вне окна/безопасной зоны %s" % [config["id"], rect, bounds])
		dialog.hide()
		main.queue_free()
		await wait_process_frames(2)
	for e in get_errors():
		if e.contains_text("spawned at invalid position"):
			all.append("движок: %s" % str(e.code))
			e.handled = true
	for issue in all:
		gut.p(issue)
	assert_eq(all.size(), 0, "нарушений %d (первые: %s)" % [all.size(), ", ".join(all.slice(0, 6))])


# ---------------------------------------------------------------------------
# Диалог удаления заезда
# ---------------------------------------------------------------------------

func _delete_ride(config: Dictionary, locale: String) -> Array[String]:
	var issues: Array[String] = []
	var started := _start(config, locale)
	var viewport: SubViewport = started[0]
	var main: AppMain = started[1]
	var m: Node = MATRIX.new()
	add_child_autofree(m)
	m._save_rides(main)
	main.app_state.navigate(AppState.Screen.HISTORY)
	await wait_process_frames(3)
	var history := main.history_screen()
	var where := "%s %s delete_ride" % [config["id"], locale]
	if history.row_count() == 0:
		issues.append("%s: нет заездов" % where)
		main.queue_free()
		return issues
	history.select_index(0)
	await wait_process_frames(2)
	if not history.detail().request_delete():
		issues.append("%s: диалог не открылся" % where)
		main.queue_free()
		return issues
	await wait_process_frames(3)
	var dialog := history.detail().get_node("%DeleteDialog") as ConfirmationDialog
	issues.append_array(_scrim_issues(dialog, viewport, where))
	var cancel := dialog.get_cancel_button()
	var ok := dialog.get_ok_button()
	var shown: Array[String] = [String(cancel.atr(cancel.text)) if cancel.can_auto_translate() else cancel.text,
		String(ok.atr(ok.text)) if ok.can_auto_translate() else ok.text]
	gut.p("%s: text «%s»/«%s», показано «%s»/«%s»" % [where, cancel.text, ok.text, shown[0], shown[1]])
	var want: Array = BUTTON_TEXTS[locale]
	if shown[0] != want[0] or shown[1] != want[1]:
		issues.append("%s: кнопки показывают %s, ожидалось %s" % [where, shown, BUTTON_TEXTS[locale]])
	if not dialog.dialog_text.is_empty() and dialog.dialog_text.begins_with("ui."):
		issues.append("%s: текст диалога — ключ %s" % [where, dialog.dialog_text])
	history.detail().cancel_delete()
	await wait_process_frames(1)
	if DialogLayout.of(dialog).is_scrim_visible():
		issues.append("%s: после «Отмены» вуаль осталась" % where)
	if history.row_count() != 2:
		issues.append("%s: после «Отмены» заезд удалён" % where)
	main.queue_free()
	await wait_process_frames(2)
	return issues


func test_delete_ride_dialog_scrim_and_translated_buttons_all_resolutions_ru_en() -> void:
	var all: Array[String] = []
	for config in CONFIGS:
		for locale in ["ru", "en"]:
			all.append_array(await _delete_ride(config, locale))
	for issue in all:
		gut.p(issue)
	assert_eq(all.size(), 0, "нарушений %d (первые: %s)" % [all.size(), ", ".join(all.slice(0, 6))])
