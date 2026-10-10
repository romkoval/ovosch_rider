extends GutTest
## Приёмка T-145 (tester, независимо от `test_menu_dialogs_ui6.gd` исполнителя): диалоги меню по
## `ui.md` п. 6 «Диалог» / «Диалог-выбор» (REQ-UIX-01 п.8, REQ-UIX-05 п.2, REQ-LOC-07 п.3).
## Отличия от теста исполнителя:
## - все шесть разрешений вводного абзаца UIX (у исполнителя — 1280×720 и 1280×590), телефоны —
##   с имитацией безопасной зоны;
## - диалоги открываются настоящим путём приложения (`request_delete`, `show_trainer_choice`,
##   `start_free_ride`, `import_path`, …) — с теми текстами, что видит игрок: длинное имя профиля,
##   длинное название заезда; у исполнителя — `popup_centered()` без текста;
## - на каждом открытии (первом в сессии и повторном): заголовок окна 20 / `inter_700`, правило
##   заливки, окно вместе с полосой заголовка в холсте и безопасной зоне, размер первого и
##   повторного открытия совпадает (±2 lp), текст и подписи кнопок не обрезаны, кнопки ряда в
##   одну строку, вуаль `scrim` под диалогом (регрессия T-142), у опасного — фокус на «Отмена»;
##   Esc закрывает без действия (`confirmed` не приходит);
## - ширина 480 ± 1 lp — у подтверждений из UIX-01 п.8 (удаление заезда и профиля, отвязка
##   Intervals.icu и Strava); у остальных диалогов ширина печатается в лог (п. 6 `ui.md`, не
##   критерий requirements);
## - диалог восстановления при запуске (настоящий путь: незавершённый заезд на диске): опасная
##   «Удалить» слева, основная `PrimaryButton` «Сохранить досрочно» справа с фокусом, «Отмены»
##   нет, заголовок 20 / 700, вуаль, окно в безопасной зоне.

const MAIN_SCENE: String = "res://src/app/main.tscn"
const MATRIX := preload("res://tests/unit/ui/test_ui_matrix.gd")
const TITLE_FONT: String = "res://src/ui/theme/fonts/inter_700.tres"
const SAFE_AREA_LP: Vector4 = Vector4(100.0, 0.0, 100.0, 13.0)
const CONFIGS: Array[Dictionary] = [
	{"id": "1280x720", "px": Vector2i(1280, 720), "device": UiScale.Device.DESKTOP},
	{"id": "1920x1080", "px": Vector2i(1920, 1080), "device": UiScale.Device.DESKTOP},
	{"id": "2732x2048", "px": Vector2i(2732, 2048), "device": UiScale.Device.TABLET},
	{"id": "1024x768", "px": Vector2i(1024, 768), "device": UiScale.Device.TABLET},
	{"id": "2556x1179_safe", "px": Vector2i(2556, 1179), "device": UiScale.Device.PHONE, "safe": true},
	{"id": "1280x590_safe", "px": Vector2i(1280, 590), "device": UiScale.Device.PHONE, "safe": true},
]
const FILLED: Array[StringName] = [&"PrimaryButton", &"DangerButton"]
## Имя профиля — до `Profile.MAX_NAME_LENGTH` (40) символов.
const LONG_PROFILE: String = "Константин Константинопольский Иванович"
const LONG_RIDE: String = "Sweet Spot 3×10 с длинным названием тренировки и подъёмом"
## Подтверждения из REQ-UIX-01 п.8 (ширина 480 — критерий).
const CONFIRMATIONS: Array[String] = ["delete_ride", "delete_profile", "forget_intervals", "disconnect_strava"]
const KEY: String = "t145-accept-key-0001"

var _dir: String = ""
var _prev_locale: String = ""
var _runtime: UiScale = null
var _prev_device: UiScale.Device = UiScale.Device.DESKTOP
var _m: Node = null
var _confirmed: int = 0


func before_each() -> void:
	_dir = "user://test_t145_accept_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_prev_locale = TranslationServer.get_locale()
	_runtime = TouchTarget.default_runtime()
	if _runtime != null:
		_prev_device = _runtime.device
	_m = MATRIX.new()
	add_child_autofree(_m)


func after_each() -> void:
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


static func _key(code: Key, pressed: bool = true) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	return e


func _tap(viewport: Viewport, code: Key) -> void:
	viewport.push_input(_key(code, true))
	viewport.push_input(_key(code, false))


func _on_confirmed() -> void:
	_confirmed += 1


## Профили и (по `in_progress_rides`) незавершённые заезды на диске, затем запуск оболочки.
func _start(config: Dictionary, locale: String, in_progress_rides: int = 0) -> Array:
	var dir := _dir + "%s_%s_%d/" % [config["id"], locale, in_progress_rides]
	var settings := AppSettings.load_from(dir + "settings.json")
	settings.locale = locale
	settings.save()
	var repo := ProfileRepository.new(dir + "profiles/")
	var profile := repo.create("Даша")
	repo.create(LONG_PROFILE)
	if in_progress_rides > 0:
		var rides := FileRideRepository.new(dir + "rides/")
		var now: int = int(Time.get_unix_time_from_system())
		for k in in_progress_rides:
			var r: Ride = MATRIX._plan_ride(profile, now - 86400 * (in_progress_rides - k), 600)
			r.name = "%s %d" % [LONG_RIDE, k]
			r.metadata["in_progress"] = true
			r.summary = RideSummary.new()
			rides.save(r)
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
	return [viewport, main]


static func _bounds(viewport: Viewport, config: Dictionary) -> Rect2:
	var safe: Vector4 = SAFE_AREA_LP if bool(config.get("safe", false)) else Vector4.ZERO
	var canvas := Vector2(viewport.size)
	return Rect2(Vector2(safe.x, safe.y), canvas - Vector2(safe.x + safe.z, safe.y + safe.w))


## Видимые кнопки диалога (ряд окна и содержимое), кроме выпадающих списков и переключателей.
static func _shown_buttons(dialog: AcceptDialog) -> Array[Button]:
	var out: Array[Button] = []
	for node in dialog.find_children("*", "Button", true, false):
		var b := node as Button
		if b.is_visible_in_tree() and not b is OptionButton and not b is CheckButton:
			out.append(b)
	for b in DialogLayout.row_buttons(dialog):
		if b.is_visible_in_tree() and not out.has(b):
			out.append(b)
	return out


static func _names(buttons: Array[Button]) -> String:
	return ", ".join(buttons.map(func(b: Button) -> String: return "«%s»[%s]" % [b.atr(b.text), b.theme_type_variation]))


## Проверки открытого диалога. Возвращает нарушения; размер окна — в `sizes`.
func _inspect(dialog: AcceptDialog, viewport: SubViewport, config: Dictionary, where: String,
		kind: String, sizes: Array[Vector2]) -> Array[String]:
	var issues: Array[String] = []
	if not dialog.visible:
		issues.append("%s: диалог не открылся" % where)
		return issues
	sizes.append(Vector2(dialog.size))
	# Заголовок окна 20 / 700 (ui.md п. 6, 9.1; Н-38).
	if dialog.get_theme_font_size(&"title_font_size") != 20:
		issues.append("%s: кегль заголовка %d ≠ 20" % [where, dialog.get_theme_font_size(&"title_font_size")])
	var tfont := dialog.get_theme_font(&"title_font")
	if tfont == null or tfont.resource_path != TITLE_FONT:
		issues.append("%s: шрифт заголовка %s ≠ inter_700" % [where, tfont.resource_path if tfont != null else "null"])
	if dialog.title.is_empty() or dialog.atr(dialog.title).begins_with("ui."):
		issues.append("%s: заголовок пуст или ключ («%s»)" % [where, dialog.title])
	elif tfont != null:
		var tw := tfont.get_string_size(dialog.atr(dialog.title), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		if tw > float(dialog.size.x):
			issues.append("%s: заголовок %.0f шире окна %d" % [where, tw, dialog.size.x])
	# Окно вместе с полосой заголовка — в холсте и безопасной зоне (UIX-05 п.2).
	var title_h := float(dialog.get_theme_constant(&"title_height"))
	var full := Rect2(Vector2(dialog.position) - Vector2(0.0, title_h), Vector2(dialog.size) + Vector2(0.0, title_h))
	var bounds := _bounds(viewport, config)
	if not bounds.grow(0.5).encloses(full):
		issues.append("%s: окно с заголовком %s вне холста/безопасной зоны %s" % [where, full, bounds])
	# Ширина 480 — у подтверждений UIX-01 п.8 (а).
	if CONFIRMATIONS.has(kind) and absf(float(dialog.size.x) - 480.0) > 1.0:
		issues.append("%s: ширина %d ≠ 480" % [where, dialog.size.x])
	# Текст сообщения не обрезан.
	var label := dialog.get_label()
	if label.is_visible_in_tree() and label.get_visible_line_count() < label.get_line_count():
		issues.append("%s: текст обрезан (%d из %d строк)" % [where, label.get_visible_line_count(), label.get_line_count()])
	# Кнопки: внутри окна, подписи не обрезаны, ряд окна — одна строка.
	var shown := _shown_buttons(dialog)
	var window := Rect2(Vector2.ZERO, Vector2(dialog.size))
	var row_y := NAN
	var row_issues: Array[String] = []
	for b in shown:
		if not window.grow(0.5).encloses(b.get_global_rect()):
			issues.append("%s: кнопка «%s» %s вне окна %s" % [where, b.atr(b.text), b.get_global_rect(), window])
		_m._check_button_text(b, dialog.get_ok_button().get_parent() as Control, where, row_issues)
		if b.get_parent() == dialog.get_ok_button().get_parent():
			if is_nan(row_y):
				row_y = b.global_position.y
			elif absf(b.global_position.y - row_y) > 0.5:
				issues.append("%s: ряд кнопок не в одну строку (%s)" % [where, _names(shown)])
	issues.append_array(row_issues)
	# Заливка (ui.md п. 6, T-145).
	var filled: Array[Button] = []
	var primary := 0
	var rightmost: Button = null
	for b in shown:
		if FILLED.has(b.theme_type_variation):
			filled.append(b)
		if b.theme_type_variation == &"PrimaryButton":
			primary += 1
		if rightmost == null or b.get_global_rect().end.x > rightmost.get_global_rect().end.x + 0.5:
			rightmost = b
	if primary > 1:
		issues.append("%s: две PrimaryButton (%s)" % [where, _names(shown)])
	if dialog is RecoveryDialog:
		var rec := dialog as RecoveryDialog
		if filled.size() != 2 or rec.delete_button().theme_type_variation != &"DangerButton" \
				or rec.get_ok_button().theme_type_variation != &"PrimaryButton":
			issues.append("%s: диалог-выбор — ожидались Danger + Primary (%s)" % [where, _names(shown)])
		if rightmost != rec.get_ok_button():
			issues.append("%s: основная не крайняя справа (%s)" % [where, _names(shown)])
		if rec.delete_button().get_global_rect().position.x >= rec.get_ok_button().get_global_rect().position.x:
			issues.append("%s: «Удалить» не слева от основной" % where)
		if rec.get_cancel_button().is_visible_in_tree():
			issues.append("%s: у диалога-выбора видна «Отмена»" % where)
	else:
		if filled.size() != 1:
			issues.append("%s: кнопок с заливкой %d ≠ 1 (%s)" % [where, filled.size(), _names(shown)])
		elif filled[0] != rightmost:
			issues.append("%s: залитая кнопка не крайняя справа (%s)" % [where, _names(shown)])
	# Фокус: у опасного — «Отмена» (UIX-01 п.8 (в)); у диалога-выбора — основная.
	var focus := dialog.get_ok_button().get_viewport().gui_get_focus_owner()
	if dialog is RecoveryDialog:
		if focus != dialog.get_ok_button():
			issues.append("%s: фокус не на «Сохранить досрочно» (%s)" % [where, focus])
	elif DialogLayout.is_danger(dialog) and dialog is ConfirmationDialog:
		if focus != (dialog as ConfirmationDialog).get_cancel_button():
			issues.append("%s: у опасного диалога фокус не на «Отмена» (%s)" % [where, focus])
	# Вуаль (T-142).
	var layout := DialogLayout.of(dialog)
	if layout == null or not layout.is_scrim_visible():
		issues.append("%s: нет вуали под диалогом" % where)
	else:
		var host := dialog.get_parent().get_viewport()
		var canvas := Rect2(Vector2.ZERO, Vector2(host.get_visible_rect().size))
		if not layout.scrim().get_global_rect().grow(0.5).encloses(canvas):
			issues.append("%s: вуаль %s не на весь холст %s" % [where, layout.scrim().get_global_rect(), canvas])
	# Лист лицензий — своя раскладка; в headless движок сжимает `popup(rect)` до минимума (128),
	# с дисплеем — нет, поэтому его размер здесь не оценивается.
	if absf(float(dialog.size.x) - 480.0) > 1.0 and not CONFIRMATIONS.has(kind) and kind != "licenses":
		gut.p("НАБЛЮДЕНИЕ %s: ширина %d (ui.md п. 6 — 480), кнопки %s" % [where, dialog.size.x, _names(shown)])
	return issues


## Открыть диалог настоящим путём; вернуть его (null — путь не сработал).
func _open(main: AppMain, kind: String) -> AcceptDialog:
	match kind:
		"delete_profile":
			main.app_state.switch_profile()
			await wait_process_frames(2)
			var select := main.screen_node(AppState.Screen.PROFILE_SELECT) as ProfileSelectScreen
			var found := false
			for i in 8:
				select.select_index(i)
				var p := main.repo.get_by_id(select.selected_profile_id())
				if p != null and p.name == LONG_PROFILE:
					found = true
					break
			if not found:
				return null
			select.request_delete()
			await wait_process_frames(3)
			return select.get_node("%DeleteDialog") as AcceptDialog
		"create_profile":
			main.app_state.switch_profile()
			await wait_process_frames(2)
			var select := main.screen_node(AppState.Screen.PROFILE_SELECT) as ProfileSelectScreen
			select.open_create_form()
			await wait_process_frames(3)
			return select.get_node("%CreateDialog") as AcceptDialog
		"delete_ride":
			main.app_state.navigate(AppState.Screen.HISTORY)
			var history := main.history_screen()
			history.refresh()
			history.select_index(0)
			await wait_process_frames(2)
			(history.detail().get_node("%DeleteButton") as Button).pressed.emit()
			await wait_process_frames(3)
			return history.detail().get_node("%DeleteDialog") as AcceptDialog
		"forget_intervals":
			main.app_state.navigate(AppState.Screen.SETTINGS)
			var settings := main.settings_screen()
			settings.refresh()
			await wait_process_frames(2)
			(settings.get_node("%IntervalsForgetButton") as Button).pressed.emit()
			await wait_process_frames(3)
			return settings.get_node("%ForgetIntervalsDialog") as AcceptDialog
		"disconnect_strava":
			main.app_state.navigate(AppState.Screen.SETTINGS)
			await wait_process_frames(2)
			main.settings_screen().request_disconnect_strava()
			await wait_process_frames(3)
			return main.settings_screen().get_node("%DisconnectStravaDialog") as AcceptDialog
		"intervals_key":
			main.app_state.navigate(AppState.Screen.SETTINGS)
			await wait_process_frames(2)
			main.settings_screen().open_key_dialog()
			await wait_process_frames(3)
			return main.settings_screen().find_child("IntervalsKeyDialog", true, false) as AcceptDialog
		"licenses":
			main.app_state.navigate(AppState.Screen.SETTINGS)
			await wait_process_frames(2)
			main.settings_screen().open_licenses()
			await wait_process_frames(3)
			return main.settings_screen().get_node("%LicensesDialog") as AcceptDialog
		"trainer_choice":
			main.app_state.navigate(AppState.Screen.PLAN)
			await wait_process_frames(2)
			main.plan_screen().show_trainer_choice()
			await wait_process_frames(3)
			return main.plan_screen().get_node("%TrainerDialog") as AcceptDialog
		"import_error":
			main.app_state.navigate(AppState.Screen.PLAN)
			await wait_process_frames(2)
			var bad := ProjectSettings.globalize_path(_dir + "broken_workout_file_with_long_name.zwo")
			var f := FileAccess.open(bad, FileAccess.WRITE)
			f.store_string("<workout_file><workout><SteadyState Duration=")
			f.close()
			main.plan_screen().import_path(bad)
			await wait_process_frames(3)
			return main.plan_screen().get_node("%ImportErrorDialog") as AcceptDialog
		"ble_help":
			main.app_state.navigate(AppState.Screen.DEVICES)
			await wait_process_frames(2)
			(main.screen_node(AppState.Screen.DEVICES) as DevicesScreen).show_ble_help()
			await wait_process_frames(3)
			return main.screen_node(AppState.Screen.DEVICES).get_node("%BleHelpDialog") as AcceptDialog
		"free_ride_no_trainer":
			main.app_state.navigate(AppState.Screen.HOME)
			await wait_process_frames(2)
			main.start_free_ride(RouteCatalog.DEFAULT_ID, 50)
			await wait_process_frames(3)
			return main.free_ride_trainer_dialog()
	return null


func _prepare(main: AppMain, tag: String) -> Variant:
	var profile := main.repo.get_active()
	profile.intervals_athlete_id = "i4242"
	main.repo.save(profile)
	var client := IntervalsIcuClient.for_profile(main.transport, main.secure_store, profile)
	main.secure_store.set_secret(client.secret_key(), KEY)
	var ride := MATRIX._plan_ride(profile, int(Time.get_unix_time_from_system()) - 3600, 600)
	ride.name = LONG_RIDE
	main.ride_repository.save(ride)
	var service := StravaService.new(profile, main.transport, main.secure_store, main.ride_repository,
		StravaConfig.from_values("4242", "fixture-client-secret-value"), func() -> int: return 1_790_000_000,
		_dir + tag.replace(" ", "_") + "_strava/")
	main.secure_store.set_secret(service.oauth.secret_key(SecureStore.ITEM_ACCESS_TOKEN), "a-access")
	main.secure_store.set_secret(service.oauth.secret_key(SecureStore.ITEM_REFRESH_TOKEN), "a-refresh")
	main.secure_store.set_secret(service.oauth.secret_key(SecureStore.ITEM_EXPIRES_AT), str(1_790_000_000 + 99999))
	main.app_state.navigate(AppState.Screen.SETTINGS)
	await wait_process_frames(2)
	main.settings_screen().set_strava_service(service)
	await wait_process_frames(2)
	return service


func _walk(config: Dictionary, locale: String) -> Array[String]:
	var issues: Array[String] = []
	var tag := "%s %s" % [config["id"], locale]
	var started := _start(config, locale)
	var viewport: SubViewport = started[0]
	var main: AppMain = started[1]
	main.app_state.select_profile(main.repo.list()[0].id)
	await wait_process_frames(2)
	var service: StravaService = await _prepare(main, tag)
	for kind in ["delete_ride", "delete_profile", "forget_intervals", "disconnect_strava", "intervals_key",
			"licenses", "trainer_choice", "import_error", "ble_help", "free_ride_no_trainer", "create_profile"]:
		var where := "%s %s" % [tag, kind]
		var sizes: Array[Vector2] = []
		for attempt in 2:
			var dialog: AcceptDialog = await _open(main, kind)
			if dialog == null:
				issues.append("%s: путь открытия не найден" % where)
				break
			issues.append_array(_inspect(dialog, viewport, config, "%s (открытие %d)" % [where, attempt + 1], kind, sizes))
			if attempt == 0:
				gut.p("%s: окно %s, кнопки %s" % [where, Rect2(Vector2(dialog.position), Vector2(dialog.size)), _names(_shown_buttons(dialog))])
			# Esc закрывает без действия (UIX-01 п.8 (в)).
			_confirmed = 0
			dialog.confirmed.connect(_on_confirmed)
			_tap(viewport, KEY_ESCAPE)
			await wait_process_frames(3)
			dialog.confirmed.disconnect(_on_confirmed)
			if dialog.visible:
				issues.append("%s: Esc не закрыл диалог" % where)
				dialog.hide()
				await wait_process_frames(2)
			if _confirmed != 0:
				issues.append("%s: Esc вызвал основное действие" % where)
			var layout := DialogLayout.of(dialog)
			if layout != null and layout.is_scrim_visible():
				issues.append("%s: после закрытия вуаль осталась" % where)
			if kind == "delete_profile" or kind == "create_profile":
				main.app_state.select_profile(main.repo.list()[0].id)
				await wait_process_frames(2)
		if sizes.size() == 2 and (absf(sizes[0].x - sizes[1].x) > 2.0 or absf(sizes[0].y - sizes[1].y) > 2.0):
			issues.append("%s: размер первого открытия %s ≠ повторного %s" % [where, sizes[0], sizes[1]])
	# Данные не тронуты: Esc ничего не удалил и не отвязал.
	if main.repo.count() != 2:
		issues.append("%s: профилей %d ≠ 2 после Esc" % [tag, main.repo.count()])
	var rides_left := main.ride_repository.list(main.repo.get_active().id).size()
	if rides_left != 1:
		issues.append("%s: заездов %d ≠ 1 после Esc" % [tag, rides_left])
	if not service.is_authorized():
		issues.append("%s: Strava отвязана после Esc" % tag)
	main.settings_screen().set_strava_service(null)
	service.dispose()
	main.queue_free()
	await wait_process_frames(2)
	return issues


func _report(all: Array[String]) -> void:
	for e in get_errors():
		if e.contains_text("spawned at invalid position"):
			all.append("движок: %s" % str(e.code))
			e.handled = true
		elif e.contains_text("found in argument passed to JSON.stringify"):
			# Только с дисплеем (xvfb): журнал диагностики пишет запись с NaN — к диалогам не
			# относится, вынесено в отчёт приёмки отдельно.
			gut.p("НАБЛЮДЕНИЕ (вне T-145): NaN в JSON журнала диагностики")
			e.handled = true
	for issue in all:
		gut.p(issue)
	assert_eq(all.size(), 0, "нарушений %d (первые: %s)" % [all.size(), ", ".join(all.slice(0, 6))])


func test_req_uix_01_c8_t145_menu_dialogs_real_paths_all_resolutions_ru() -> void:
	var all: Array[String] = []
	for config in CONFIGS:
		all.append_array(await _walk(config, "ru"))
	_report(all)


func test_req_uix_01_c8_t145_menu_dialogs_real_paths_all_resolutions_en() -> void:
	var all: Array[String] = []
	for config in CONFIGS:
		all.append_array(await _walk(config, "en"))
	_report(all)


# ---------------------------------------------------------------------------
# Диалог восстановления при запуске (LOC-07 п.3, «диалог-выбор» ui.md п. 6)
# ---------------------------------------------------------------------------

func _recovery(config: Dictionary, locale: String) -> Array[String]:
	var issues: Array[String] = []
	var tag := "%s %s recovery" % [config["id"], locale]
	var started := _start(config, locale, 2)
	var viewport: SubViewport = started[0]
	var main: AppMain = started[1]
	if main.app_state.current_screen == AppState.Screen.PROFILE_SELECT or main.repo.get_active() == null:
		main.app_state.select_profile(main.repo.list()[0].id)
	await wait_process_frames(4)
	var dialog := main.recovery_dialog()
	var sizes: Array[Vector2] = []
	issues.append_array(_inspect(dialog, viewport, config, tag + " (заезд 1, первое открытие)", "recovery", sizes))
	if not dialog.visible:
		main.queue_free()
		return issues
	var first := dialog.current_ride().id
	# Enter — «Сохранить досрочно».
	_tap(viewport, KEY_ENTER)
	await wait_process_frames(4)
	var r1 := main.ride_repository.get_ride(first)
	if r1 == null or r1.is_in_progress():
		issues.append("%s: Enter не сохранил заезд" % tag)
	issues.append_array(_inspect(dialog, viewport, config, tag + " (заезд 2)", "recovery", sizes))
	if sizes.size() == 2 and absf(sizes[0].x - sizes[1].x) > 2.0:
		issues.append("%s: ширина первого открытия %s ≠ второго %s" % [tag, sizes[0], sizes[1]])
	# Удаление — только кнопкой: «×»/Esc сохраняет.
	if dialog.visible and dialog.current_ride() != null:
		var second := dialog.current_ride().id
		_tap(viewport, KEY_ESCAPE)
		await wait_process_frames(4)
		var r2 := main.ride_repository.get_ride(second)
		if r2 == null or r2.is_in_progress():
			issues.append("%s: Esc не сохранил второй заезд" % tag)
	if DialogLayout.of(dialog).is_scrim_visible():
		issues.append("%s: вуаль осталась после последнего заезда" % tag)
	main.queue_free()
	await wait_process_frames(2)
	return issues


func test_req_loc_07_c3_recovery_dialog_choice_layout_all_resolutions_ru_en() -> void:
	var all: Array[String] = []
	for config in CONFIGS:
		for locale in ["ru", "en"]:
			all.append_array(await _recovery(config, locale))
	_report(all)
