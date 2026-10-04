extends GutTest
## Повторная приёмка T-103 (tester, независимо от `test_confirm_dialogs.gd` исполнителя):
## REQ-UIX-01 крит. 8 (а)–(г) на **всех** разрешениях вводного абзаца UIX (у исполнителя —
## 1280×720 и 1280×590) и на ru и en (у исполнителя — только ru), для всех подтверждений
## приложения: отвязка Intervals.icu и Strava (REQ-PRF-03 крит. 2, REQ-STR-01 крит. 8), удаление
## заезда (LOC-06.1), удаление профиля (PRF-01.4), диалог «нет станка» свободной езды; плюс
## подтверждение завершения заезда в холсте HUD (WRK-05.4, FRD-07.2; UIX-04 крит. 2).
## (а) ширина 480 lp (±1), текст сообщения переносится и помещается (все строки видны, подпись
##     внутри диалога), заголовок не шире диалога, кнопки не обрезаны, диалог в окне и в
##     безопасной зоне;
## (б) «Отмена» слева, основная/опасная — крайняя справа у правого края; область нажатия — по
##     UIX-05 крит. 1 (на экранах заезда — `touch_hud·s`);
## (в) у опасного диалога фокус на «Отмена»; Enter сразу после открытия, Esc и системный «назад»
##     (`NOTIFICATION_WM_GO_BACK_REQUEST` оболочке) закрывают без действия;
## (г) опасная кнопка экрана только открывает диалог.

const MAIN_SCENE: String = "res://src/app/main.tscn"
const MATRIX := preload("res://tests/unit/ui/test_ui_matrix.gd")
const SAFE_AREA_LP: Vector4 = Vector4(100.0, 0.0, 100.0, 13.0)
const KEY: String = "reaccept-dialogs-key-0001"
## Набор разрешений вводного абзаца UIX: 1024×768 — планшет; iPhone — с безопасной зоной.
const CONFIGS: Array[Dictionary] = [
	{"id": "1280x720", "px": Vector2i(1280, 720), "device": UiScale.Device.DESKTOP},
	{"id": "1920x1080", "px": Vector2i(1920, 1080), "device": UiScale.Device.DESKTOP},
	{"id": "2732x2048", "px": Vector2i(2732, 2048), "device": UiScale.Device.TABLET},
	{"id": "1024x768", "px": Vector2i(1024, 768), "device": UiScale.Device.TABLET},
	{"id": "2556x1179_safe", "px": Vector2i(2556, 1179), "device": UiScale.Device.PHONE, "safe": true},
	{"id": "1280x590_safe", "px": Vector2i(1280, 590), "device": UiScale.Device.PHONE, "safe": true},
]
const PHONE_TOUCH_BASE_LP: float = 86.0
const IPHONE_TOUCH_PX: float = 132.0
const WIDTH: float = 480.0

var _dir: String = ""
var _prev_locale: String = ""
var _runtime: UiScale = null
var _prev_device: UiScale.Device = UiScale.Device.DESKTOP
var _m: Node = null
var _now_usec: int = 0


func before_each() -> void:
	_dir = "user://test_confirm_dialogs_reaccept_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_prev_locale = TranslationServer.get_locale()
	_runtime = TouchTarget.default_runtime()
	if _runtime != null:
		_prev_device = _runtime.device
	_m = MATRIX.new()
	add_child_autofree(_m)
	_now_usec = 3_000_000


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


func _clock() -> int:
	return _now_usec


func _keep(_on: bool) -> void:
	pass


func _start(config: Dictionary, locale: String, sub: String) -> Array:
	var dir := _dir + sub + "/"
	var settings := AppSettings.load_from(dir + "settings.json")
	settings.locale = locale
	settings.save()
	var repo := ProfileRepository.new(dir + "profiles/")
	repo.create("Даша")
	repo.create("Константин Константинопольский")
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


static func _safe(config: Dictionary) -> Vector4:
	return SAFE_AREA_LP if bool(config.get("safe", false)) else Vector4.ZERO


func _key(code: Key, pressed: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	return e


func _tap(viewport: Viewport, code: Key) -> void:
	viewport.push_input(_key(code, true))
	viewport.push_input(_key(code, false))


## Системный «назад» Android — уведомление оболочке (как от движка).
func _android_back(main: AppMain) -> void:
	main.notification(NOTIFICATION_WM_GO_BACK_REQUEST)


## (а), (б), (в — фокус) для открытого диалога-окна.
func _check_dialog(dialog: ConfirmationDialog, viewport: SubViewport, config: Dictionary, where: String) -> void:
	assert_true(dialog.visible, "%s: диалог открыт" % where)
	if not dialog.visible:
		return
	var canvas := Vector2(viewport.size)
	var safe := _safe(config)
	assert_almost_eq(float(dialog.size.x), WIDTH, 1.0, "%s: (а) ширина 480 lp" % where)
	var bounds := Rect2(Vector2(safe.x, safe.y), canvas - Vector2(safe.x + safe.z, safe.y + safe.w))
	var drect := Rect2(Vector2(dialog.position), Vector2(dialog.size))
	assert_true(bounds.grow(0.5).encloses(drect), "%s: (а) диалог %s в окне и безопасной зоне %s" % [where, drect, bounds])
	# Текст: перенос по словам, все строки видны, подпись внутри диалога.
	var label := dialog.get_label()
	assert_ne(label.autowrap_mode, TextServer.AUTOWRAP_OFF, "%s: (а) текст переносится" % where)
	assert_false(label.text.is_empty(), "%s: предусловие — текст сообщения есть" % where)
	assert_eq(label.get_visible_line_count(), label.get_line_count(), "%s: (а) все строки текста видны" % where)
	var local := Rect2(Vector2.ZERO, Vector2(dialog.size))
	var lrect := Rect2(label.position, label.size)
	assert_true(local.grow(0.5).encloses(lrect), "%s: (а) текст %s внутри диалога %s" % [where, lrect, local])
	var font := label.get_theme_font("font")
	var fsize := label.get_theme_font_size("font_size")
	for word in label.text.split(" ", false):
		var w := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		assert_lte(w, label.size.x + 1.0, "%s: (а) слово «%s» помещается в строку" % [where, word])
	# Заголовок окна не шире диалога.
	var title_font := dialog.get_theme_font("title_font")
	if title_font != null:
		var tw := title_font.get_string_size(dialog.title, HORIZONTAL_ALIGNMENT_LEFT, -1,
				dialog.get_theme_font_size("title_font_size")).x
		assert_lte(tw, float(dialog.size.x), "%s: (а) заголовок «%s» помещается" % [where, dialog.title])
	# Кнопки.
	var ok := dialog.get_ok_button()
	var cancel := dialog.get_cancel_button()
	var visible: Array[Button] = []
	for b in DialogLayout.row_buttons(dialog):
		if b.visible:
			visible.append(b)
	visible.sort_custom(func(a: Button, b: Button) -> bool: return a.global_position.x < b.global_position.x)
	assert_gte(visible.size(), 2, "%s: предусловие — «Отмена» и основная" % where)
	assert_eq(visible[0], cancel, "%s: (б) «Отмена» слева" % where)
	assert_eq(visible[visible.size() - 1], ok, "%s: (б) основная/опасная — крайняя справа" % where)
	var row := ok.get_parent() as Control
	assert_almost_eq(ok.position.x + ok.size.x, row.size.x, 1.0, "%s: (б) у правого края" % where)
	var threshold := MATRIX.min_target_lp(config["device"], canvas)
	var issues: Array[String] = []
	for k in visible.size():
		var b := visible[k]
		assert_gte(b.size.x + 0.01, threshold, "%s: (б) ширина «%s» %.1f ≥ %.1f" % [where, b.text, b.size.x, threshold])
		assert_gte(b.size.y + 0.01, threshold, "%s: (б) высота «%s» %.1f ≥ %.1f" % [where, b.text, b.size.y, threshold])
		assert_true(local.grow(0.5).encloses(b.get_global_rect()), "%s: «%s» %s внутри диалога %s" % [where, b.text, b.get_global_rect(), local])
		_m._check_button_text(b, dialog.get_ok_button().get_parent() as Control, where, issues)
		if k > 0:
			var prev := visible[k - 1]
			assert_false(Rect2(prev.position, prev.size).intersects(Rect2(b.position, b.size)), "%s: (б) кнопки не перекрываются" % where)
	assert_eq(issues, [] as Array[String], "%s: (а) текст кнопок не обрезан" % where)
	gut.p("%s: диалог %s, строк текста %d, кнопки %s, порог %.1f" % [where, drect, label.get_line_count(),
			", ".join(visible.map(func(b: Button) -> String: return "«%s» %dx%d" % [b.text, roundi(b.size.x), roundi(b.size.y)])),
			threshold])
	if DialogLayout.is_danger(dialog):
		assert_eq(cancel.get_viewport().gui_get_focus_owner(), cancel, "%s: (в) фокус на «Отмена»" % where)


## Отвязка Intervals.icu: (г) кнопка экрана; (в) Enter, Esc, «назад» — без действия.
func _forget_intervals(main: AppMain, viewport: SubViewport, config: Dictionary, tag: String) -> void:
	var profile := main.repo.get_active()
	profile.intervals_athlete_id = "i4242"
	main.repo.save(profile)
	var client := IntervalsIcuClient.for_profile(main.transport, main.secure_store, profile)
	main.secure_store.set_secret(client.secret_key(), KEY)
	main.app_state.navigate(AppState.Screen.SETTINGS)
	var settings := main.settings_screen()
	settings.refresh()
	await wait_process_frames(3)
	var dialog := settings.get_node("%ForgetIntervalsDialog") as ConfirmationDialog
	var where := tag + " forget_intervals"
	(settings.get_node("%IntervalsForgetButton") as Button).pressed.emit()
	await wait_process_frames(3)
	assert_eq(main.secure_store.get_secret(client.secret_key()), KEY, "%s: (г) ключ на месте" % where)
	_check_dialog(dialog, viewport, config, where)
	_tap(viewport, KEY_ENTER)
	await wait_process_frames(2)
	assert_false(dialog.visible, "%s: (в) Enter закрыл" % where)
	assert_eq(main.secure_store.get_secret(client.secret_key()), KEY, "%s: (в) Enter не отвязал" % where)
	settings.request_forget_intervals()
	await wait_process_frames(2)
	_tap(viewport, KEY_ESCAPE)
	await wait_process_frames(2)
	assert_false(dialog.visible, "%s: (в) Esc закрыл" % where)
	settings.request_forget_intervals()
	await wait_process_frames(2)
	_android_back(main)
	await wait_process_frames(2)
	assert_false(dialog.visible, "%s: (в) «назад» закрыл" % where)
	assert_eq(main.app_state.current_screen, AppState.Screen.SETTINGS, "%s: «назад» закрыл только диалог" % where)
	assert_eq(main.secure_store.get_secret(client.secret_key()), KEY, "%s: (в) Esc/«назад» не отвязали" % where)
	assert_eq(main.repo.get_active().intervals_athlete_id, "i4242", "%s: статус привязки прежний" % where)


## Отвязка Strava (PRF-03 крит. 2, STR-01 крит. 8): токены на месте после Enter, Esc, «назад».
func _disconnect_strava(main: AppMain, viewport: SubViewport, config: Dictionary, tag: String) -> void:
	var settings := main.settings_screen()
	var service := StravaService.new(main.repo.get_active(), main.transport, main.secure_store, main.ride_repository,
		StravaConfig.from_values("4242", "fixture-client-secret-value"), func() -> int: return 1_790_000_000,
		_dir + tag.replace(" ", "_") + "_strava/")
	var access := service.oauth.secret_key(SecureStore.ITEM_ACCESS_TOKEN)
	main.secure_store.set_secret(access, "a-access")
	main.secure_store.set_secret(service.oauth.secret_key(SecureStore.ITEM_REFRESH_TOKEN), "a-refresh")
	main.secure_store.set_secret(service.oauth.secret_key(SecureStore.ITEM_EXPIRES_AT), str(1_790_000_000 + 99999))
	settings.set_strava_service(service)
	await wait_process_frames(2)
	var where := tag + " disconnect_strava"
	assert_true(settings.strava_button().is_authorized(), "%s: предусловие — Strava привязана" % where)
	var pressed := false
	var sb := settings.strava_button()
	for n in sb.find_children("*", "Button", true, false):
		var btn := n as Button
		if btn.is_visible_in_tree() and btn.text == sb.button_text():
			btn.pressed.emit()
			pressed = true
			break
	assert_true(pressed, "%s: кнопка «Отвязать Strava» найдена" % where)
	await wait_process_frames(3)
	var dialog := settings.get_node("%DisconnectStravaDialog") as ConfirmationDialog
	assert_eq(main.secure_store.get_secret(access), "a-access", "%s: (г) токены на месте" % where)
	_check_dialog(dialog, viewport, config, where)
	_tap(viewport, KEY_ENTER)
	await wait_process_frames(2)
	assert_false(dialog.visible, "%s: (в) Enter закрыл" % where)
	settings.request_disconnect_strava()
	await wait_process_frames(2)
	_tap(viewport, KEY_ESCAPE)
	await wait_process_frames(2)
	assert_false(dialog.visible, "%s: (в) Esc закрыл" % where)
	settings.request_disconnect_strava()
	await wait_process_frames(2)
	_android_back(main)
	await wait_process_frames(2)
	assert_false(dialog.visible, "%s: (в) «назад» закрыл" % where)
	assert_eq(main.secure_store.get_secret(access), "a-access", "%s: Enter/Esc/«назад» токены не удалили" % where)
	assert_true(service.is_authorized(), "%s: Strava по-прежнему привязана" % where)
	assert_eq((main.transport as MockHttpTransport).request_count("POST", "deauthorize"), 0, "%s: отзыва токена в Strava не было" % where)
	settings.set_strava_service(null)
	service.dispose()


## Удаление заезда из карточки истории.
func _delete_ride(main: AppMain, viewport: SubViewport, config: Dictionary, tag: String) -> void:
	var profile := main.repo.get_active()
	var ride := Ride.new()
	ride.id = Ride.generate_id()
	ride.profile_id = profile.id
	ride.name = "Утро"
	ride.started_at_unix = int(Time.get_unix_time_from_system()) - 3600
	ride.compute_summary()
	assert_false(str(main.ride_repository.save(ride)).is_empty(), "заезд сохранён")
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	history.refresh()
	history.select_index(0)
	await wait_process_frames(3)
	var where := tag + " delete_ride"
	(history.detail().get_node("%DeleteButton") as Button).pressed.emit()
	await wait_process_frames(3)
	var dialog := history.detail().get_node("%DeleteDialog") as ConfirmationDialog
	assert_not_null(main.ride_repository.get_ride(ride.id), "%s: (г) заезд на месте" % where)
	_check_dialog(dialog, viewport, config, where)
	_tap(viewport, KEY_ENTER)
	await wait_process_frames(2)
	assert_false(dialog.visible, "%s: (в) Enter закрыл" % where)
	assert_not_null(main.ride_repository.get_ride(ride.id), "%s: (в) Enter не удалил" % where)
	history.detail().request_delete()
	await wait_process_frames(2)
	_tap(viewport, KEY_ESCAPE)
	await wait_process_frames(2)
	assert_false(dialog.visible, "%s: (в) Esc закрыл" % where)
	history.detail().request_delete()
	await wait_process_frames(2)
	_android_back(main)
	await wait_process_frames(2)
	assert_false(dialog.visible, "%s: (в) «назад» закрыл" % where)
	assert_true(history.is_detail_visible(), "%s: «назад» закрыл только диалог" % where)
	assert_not_null(main.ride_repository.get_ride(ride.id), "%s: Esc/«назад» не удалили" % where)
	history.back_to_list()


## Удаление профиля (меню карточки профиля).
func _delete_profile(main: AppMain, viewport: SubViewport, config: Dictionary, tag: String) -> void:
	main.app_state.switch_profile()
	await wait_process_frames(3)
	var select := main.screen_node(AppState.Screen.PROFILE_SELECT) as ProfileSelectScreen
	select.select_index(1)
	assert_true(select.request_delete(), "удаление профиля запрошено")
	await wait_process_frames(3)
	var where := tag + " delete_profile"
	var dialog := select.get_node("%DeleteDialog") as ConfirmationDialog
	_check_dialog(dialog, viewport, config, where)
	_tap(viewport, KEY_ENTER)
	await wait_process_frames(2)
	assert_false(dialog.visible, "%s: (в) Enter закрыл" % where)
	assert_eq(main.repo.count(), 2, "%s: (в) Enter не удалил профиль" % where)
	select.request_delete()
	await wait_process_frames(2)
	_tap(viewport, KEY_ESCAPE)
	await wait_process_frames(2)
	assert_false(dialog.visible, "%s: (в) Esc закрыл" % where)
	select.request_delete()
	await wait_process_frames(2)
	_android_back(main)
	await wait_process_frames(2)
	assert_false(dialog.visible, "%s: (в) «назад» закрыл" % where)
	assert_eq(main.repo.count(), 2, "%s: Esc/«назад» не удалили профиль" % where)
	main.app_state.select_profile(main.repo.list()[0].id)


## Диалог «нет станка» свободной езды (обычный, не опасный).
func _free_ride_no_trainer(main: AppMain, viewport: SubViewport, config: Dictionary, tag: String) -> void:
	var where := tag + " free_ride_no_trainer"
	assert_false(main.start_free_ride(RouteCatalog.DEFAULT_ID, 50), "%s: станка нет — диалог" % where)
	await wait_process_frames(3)
	var dialog := main.free_ride_trainer_dialog()
	_check_dialog(dialog, viewport, config, where)
	_android_back(main)
	await wait_process_frames(2)
	assert_false(dialog.visible, "%s: (в) «назад» закрыл" % where)
	assert_eq(main.pending_free_ride(), {}, "%s: «назад» — отмена" % where)


func _run_menu(config: Dictionary, locale: String) -> void:
	var tag := "%s %s" % [config["id"], locale]
	var started := _start(config, locale, "%s_%s" % [config["id"], locale])
	var viewport: SubViewport = started[0]
	var main: AppMain = started[1]
	await _forget_intervals(main, viewport, config, tag)
	await _disconnect_strava(main, viewport, config, tag)
	await _delete_ride(main, viewport, config, tag)
	await _delete_profile(main, viewport, config, tag)
	main.app_state.navigate(AppState.Screen.HOME)
	await wait_process_frames(2)
	await _free_ride_no_trainer(main, viewport, config, tag)
	main.queue_free()
	await wait_process_frames(2)


func test_req_uix_01_c8_menu_dialogs_all_resolutions_ru() -> void:
	for config in CONFIGS:
		await _run_menu(config, "ru")


func test_req_uix_01_c8_menu_dialogs_all_resolutions_en() -> void:
	for config in CONFIGS:
		await _run_menu(config, "en")


# --- Подтверждение завершения заезда (холст HUD) ----------------------------------------------

static func _hud_threshold(config: Dictionary, canvas: Vector2) -> float:
	var device: UiScale.Device = config["device"]
	if device == UiScale.Device.PHONE:
		var lp := PHONE_TOUCH_BASE_LP / UiScale.scale_for(device, UiScale.Mode.HUD)
		var px_per_lp := float(Vector2i(config["px"]).x) / canvas.x
		return maxf(lp, IPHONE_TOUCH_PX / px_per_lp if str(config["id"]).begins_with("2556") else 0.0)
	return MATRIX.min_target_lp(device, canvas)


func _check_finish_card(overlay: PauseOverlay, viewport: SubViewport, config: Dictionary, where: String) -> void:
	assert_eq(overlay.view(), PauseOverlay.View.CONFIRM, "%s: подтверждение открыто" % where)
	var canvas := Vector2(viewport.size)
	var cancel := overlay.cancel_button()
	var confirm := overlay.confirm_button()
	var card := cancel.get_parent().get_parent().get_parent() as Control
	assert_almost_eq(card.size.x, WIDTH, 1.0, "%s: (а) карточка 480 lp" % where)
	var safe := _safe(config)
	var bounds := Rect2(Vector2(safe.x, safe.y), canvas - Vector2(safe.x + safe.z, safe.y + safe.w))
	assert_true(bounds.grow(0.5).encloses(card.get_global_rect()), "%s: (а) в окне и безопасной зоне" % where)
	var issues: Array[String] = []
	for l in card.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree():
			_m._check_label(l as Label, card, where, issues)
			assert_true(card.get_global_rect().grow(0.5).encloses((l as Label).get_global_rect()), "%s: подпись внутри" % where)
	assert_lt(cancel.global_position.x, confirm.global_position.x, "%s: (б) «Отмена» слева" % where)
	var row := confirm.get_parent() as Control
	assert_almost_eq(confirm.position.x + confirm.size.x, row.size.x, 1.0, "%s: (б) у правого края" % where)
	var threshold := _hud_threshold(config, canvas)
	for b: Button in [cancel, confirm]:
		assert_gte(b.size.x + 0.01, threshold, "%s: (б) ширина «%s» %.1f ≥ %.1f" % [where, b.text, b.size.x, threshold])
		assert_gte(b.size.y + 0.01, threshold, "%s: (б) высота «%s» %.1f ≥ %.1f" % [where, b.text, b.size.y, threshold])
		_m._check_button_text(b, card, where, issues)
	assert_false(cancel.get_global_rect().intersects(confirm.get_global_rect()), "%s: (б) не перекрываются" % where)
	assert_eq(issues, [] as Array[String], "%s: (а) текст не обрезан" % where)
	assert_eq(cancel.get_viewport().gui_get_focus_owner(), cancel, "%s: (в) фокус на «Отмена»" % where)


func _run_finish(config: Dictionary, locale: String) -> void:
	var tag := "%s %s" % [config["id"], locale]
	var started := _start(config, locale, "finish_%s_%s" % [config["id"], locale])
	var viewport: SubViewport = started[0]
	var main: AppMain = started[1]
	viewport.size = Vector2i(MATRIX.canvas_lp(config["px"], UiScale.scale_for(config["device"], UiScale.Mode.HUD)))
	# План.
	var ws := main.workout_screen()
	ws.clock_usec = _clock
	ws.keep_awake_setter = _keep
	assert_true(main.start_workout_on_emulator(DevScreen.test_workout()))
	for i in 5:
		_now_usec += 1_000_000
		ws.ticker().poll()
	await wait_process_frames(3)
	var where := tag + " finish_plan"
	assert_true(ws.request_stop())
	await wait_process_frames(3)
	_check_finish_card(ws.pause_overlay(), viewport, config, where)
	_tap(viewport, KEY_ENTER)
	await wait_process_frames(2)
	assert_ne(ws.pause_overlay().view(), PauseOverlay.View.CONFIRM, "%s: (в) Enter закрыл" % where)
	assert_true(ws.session() != null and ws.session().get_state() != WorkoutSession.State.FINISHED, "%s: (в) Enter не завершил" % where)
	assert_true(ws.request_stop())
	await wait_process_frames(2)
	_android_back(main)
	await wait_process_frames(2)
	assert_ne(ws.pause_overlay().view(), PauseOverlay.View.CONFIRM, "%s: (в) «назад» закрыл" % where)
	assert_true(ws.session().get_state() != WorkoutSession.State.FINISHED, "%s: (в) «назад» не завершил" % where)
	assert_eq(main.app_state.current_screen, AppState.Screen.WORKOUT, "%s: экран тот же" % where)
	ws.request_stop()
	ws.confirm_stop()
	await wait_process_frames(2)
	ws.go_home()
	await wait_process_frames(2)
	# Свободная езда.
	var fr := main.free_ride_screen()
	fr.clock_usec = _clock
	fr.keep_awake_setter = _keep
	assert_true(main.start_free_ride_on_emulator("flat", 50))
	for i in 5:
		_now_usec += 1_000_000
		fr.ticker().poll()
	await wait_process_frames(3)
	where = tag + " finish_free"
	assert_true(fr.request_finish())
	await wait_process_frames(3)
	_check_finish_card(fr.pause_overlay(), viewport, config, where)
	_tap(viewport, KEY_ENTER)
	await wait_process_frames(2)
	assert_false(fr.is_finish_confirmation_pending(), "%s: (в) Enter закрыл" % where)
	assert_true(fr.is_session_active(), "%s: (в) Enter не завершил" % where)
	assert_true(fr.request_finish())
	await wait_process_frames(2)
	_android_back(main)
	await wait_process_frames(2)
	assert_false(fr.is_finish_confirmation_pending(), "%s: (в) «назад» закрыл" % where)
	assert_true(fr.is_session_active(), "%s: (в) «назад» не завершил" % where)
	fr.request_finish()
	fr.confirm_finish()
	await wait_process_frames(2)
	main.queue_free()
	await wait_process_frames(2)


func test_req_uix_01_c8_finish_confirmation_hud_all_resolutions_ru() -> void:
	for config in CONFIGS:
		await _run_finish(config, "ru")


func test_req_uix_01_c8_finish_confirmation_hud_all_resolutions_en() -> void:
	for config in CONFIGS:
		await _run_finish(config, "en")
