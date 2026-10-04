extends GutTest
## T-103: диалоги подтверждения — компонент «Диалог» `ui.md` п. 6, REQ-UIX-01 крит. 8 (а)–(г):
## (а) ширина 480 lp во всех раскладках (компьютер 1280×720 и телефон 1280×590 с вырезом), текст
##     переносится, диалог в окне и в безопасной зоне;
## (б) кнопки у правого края: «Отмена» слева, основная/опасная — крайняя справа, по ширине
##     текста; цель нажатия ≥ `touch_ui` (и 44 по высоте);
## (в) в опасном диалоге фокус при открытии — «Отмена» (`gui_get_focus_owner()`): Enter сразу
##     после открытия закрывает без действия; Esc закрывает без действия;
## (г) опасная кнопка экрана открывает диалог и данных не меняет.
## Подтверждение завершения заезда (карточка `PauseOverlay`) — те же правила в холсте HUD.

const MAIN_SCENE: String = "res://src/app/main.tscn"
const SAFE_AREA_LP: Vector4 = Vector4(100.0, 0.0, 100.0, 13.0)
const KEY: String = "confirm-dialogs-key-0001"
const CONFIGS: Array[Dictionary] = [
	{"id": "1280x720", "px": Vector2i(1280, 720), "device": UiScale.Device.DESKTOP},
	{"id": "1280x590_safe_phone", "px": Vector2i(1280, 590), "device": UiScale.Device.PHONE, "safe": true},
]

var _dir: String = ""
var _prev_locale: String = ""
var _runtime: UiScale = null
var _prev_device: UiScale.Device = UiScale.Device.DESKTOP


func before_each() -> void:
	_dir = "user://test_confirm_dialogs_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_prev_locale = TranslationServer.get_locale()
	_runtime = get_tree().root.get_node_or_null(^"UiScaleRuntime") as UiScale
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


func _start(config: Dictionary, sub: String) -> Array:
	var dir := _dir + sub + "/"
	var settings := AppSettings.load_from(dir + "settings.json")
	settings.locale = "ru"
	settings.save()
	var repo := ProfileRepository.new(dir + "profiles/")
	repo.create("Даша")
	repo.create("Роман")
	if _runtime != null:
		_runtime.device = config["device"]
	if bool(config.get("safe", false)):
		Engine.set_meta(UiScale.DEBUG_SAFE_AREA_META, SAFE_AREA_LP)
	elif Engine.has_meta(UiScale.DEBUG_SAFE_AREA_META):
		Engine.remove_meta(UiScale.DEBUG_SAFE_AREA_META)
	var viewport := SubViewport.new()
	viewport.gui_embed_subwindows = true
	viewport.size = Vector2i(Vector2(config["px"]) / UiScale.scale_for(config["device"], UiScale.Mode.MENU))
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
	return [viewport, main]


func _safe(config: Dictionary) -> Vector4:
	return SAFE_AREA_LP if bool(config.get("safe", false)) else Vector4.ZERO


func _key(event_key: Key, pressed: bool = true) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = event_key
	e.physical_keycode = event_key
	e.pressed = pressed
	return e


## Нажать и отпустить клавишу в окне диалога (как пользователь).
func _tap(viewport: Viewport, event_key: Key) -> void:
	viewport.push_input(_key(event_key, true))
	viewport.push_input(_key(event_key, false))


## Общие проверки открытого диалога (а), (б), (в — фокус).
func _check_dialog(dialog: ConfirmationDialog, viewport: SubViewport, config: Dictionary, where: String) -> void:
	assert_true(dialog.visible, "%s: диалог открыт" % where)
	assert_almost_eq(float(dialog.size.x), 480.0, 1.0, "%s: ширина 480 lp" % where)
	assert_true(dialog.dialog_autowrap, "%s: текст переносится" % where)
	var safe := _safe(config)
	var canvas := Vector2(viewport.size)
	var bounds := Rect2(Vector2(safe.x, safe.y), canvas - Vector2(safe.x + safe.z, safe.y + safe.w))
	assert_true(bounds.grow(0.5).encloses(Rect2(Vector2(dialog.position), Vector2(dialog.size))),
			"%s: диалог в окне и безопасной зоне" % where)
	var ok := dialog.get_ok_button()
	var cancel := dialog.get_cancel_button()
	var visible: Array[Button] = []
	for b in DialogLayout.row_buttons(dialog):
		if b.visible:
			visible.append(b)
	visible.sort_custom(func(a: Button, b: Button) -> bool: return a.position.x < b.position.x)
	assert_eq(visible[0], cancel, "%s: «Отмена» — слева" % where)
	assert_eq(visible[visible.size() - 1], ok, "%s: основная/опасная — крайняя справа" % where)
	var row := ok.get_parent() as Control
	assert_almost_eq(ok.position.x + ok.size.x, row.size.x, 1.0, "%s: ряд прижат к правому краю" % where)
	for k in range(1, visible.size()):
		var between := visible[k].position.x - (visible[k - 1].position.x + visible[k - 1].size.x)
		assert_almost_eq(between, DialogLayout.BUTTON_GAP, 1.0, "%s: зазор между кнопками 12" % where)
	for b in visible:
		assert_almost_eq(b.size.x, b.get_combined_minimum_size().x, 1.0, "%s: «%s» по ширине текста" % [where, b.text])
		assert_gte(b.size.y, 44.0, "%s: высота «%s» ≥ 44" % [where, b.text])
	if DialogLayout.is_danger(dialog):
		# Фокус — во вьюпорте самой кнопки (диалог — отдельное окно).
		assert_eq(cancel.get_viewport().gui_get_focus_owner(), cancel, "%s: фокус на «Отмена»" % where)


func test_a_b_c_d_settings_forget_intervals_dialog() -> void:
	for config in CONFIGS:
		var started := _start(config, config["id"])
		var viewport: SubViewport = started[0]
		var main: AppMain = started[1]
		var profile := main.repo.get_active()
		profile.intervals_athlete_id = "i4242"
		main.repo.save(profile)
		var client := IntervalsIcuClient.for_profile(main.transport, main.secure_store, profile)
		main.secure_store.set_secret(client.secret_key(), KEY)
		main.app_state.navigate(AppState.Screen.SETTINGS)
		var settings := main.settings_screen()
		await wait_process_frames(3)
		var dialog := settings.get_node("%ForgetIntervalsDialog") as ConfirmationDialog
		# (г) «Отвязать» на экране только открывает диалог.
		(settings.get_node("%IntervalsForgetButton") as Button).pressed.emit()
		await wait_process_frames(2)
		var where := "%s forget_intervals" % config["id"]
		assert_eq(main.secure_store.get_secret(client.secret_key()), KEY, "%s: (г) ключ на месте до подтверждения" % where)
		_check_dialog(dialog, viewport, config, where)
		# (в) Enter сразу после открытия — «Отмена».
		_tap(viewport, KEY_ENTER)
		await wait_process_frames(2)
		assert_false(dialog.visible, "%s: Enter закрыл диалог" % where)
		assert_eq(main.secure_store.get_secret(client.secret_key()), KEY, "%s: Enter не отвязал" % where)
		# Esc — «Отмена».
		settings.request_forget_intervals()
		await wait_process_frames(2)
		_tap(viewport, KEY_ESCAPE)
		await wait_process_frames(2)
		assert_false(dialog.visible, "%s: Esc закрыл диалог" % where)
		assert_eq(main.secure_store.get_secret(client.secret_key()), KEY, "%s: Esc не отвязал" % where)
		viewport.queue_free()
		await wait_process_frames(1)


func test_a_b_c_ride_and_profile_delete_dialogs() -> void:
	for config in CONFIGS:
		var started := _start(config, config["id"])
		var viewport: SubViewport = started[0]
		var main: AppMain = started[1]
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
		history.select_index(0)
		await wait_process_frames(3)
		var where := "%s delete_ride" % config["id"]
		(history.detail().get_node("%DeleteButton") as Button).pressed.emit()
		await wait_process_frames(2)
		var dialog := history.detail().get_node("%DeleteDialog") as ConfirmationDialog
		assert_not_null(main.ride_repository.get_ride(ride.id), "%s: (г) заезд на месте до подтверждения" % where)
		_check_dialog(dialog, viewport, config, where)
		_tap(viewport, KEY_ESCAPE)
		await wait_process_frames(2)
		assert_false(dialog.visible, "%s: Esc закрыл" % where)
		assert_false(history.detail().is_delete_pending(), "%s: удаление отменено" % where)
		assert_not_null(main.ride_repository.get_ride(ride.id), "%s: Esc не удалил" % where)
		history.back_to_list()
		main.app_state.switch_profile()
		await wait_process_frames(2)
		var select := main.screen_node(AppState.Screen.PROFILE_SELECT) as ProfileSelectScreen
		select.select_index(1)
		assert_true(select.request_delete(), "удаление профиля запрошено")
		await wait_process_frames(2)
		_check_dialog(select.get_node("%DeleteDialog") as ConfirmationDialog, viewport, config, "%s delete_profile" % config["id"])
		assert_eq(main.repo.count(), 2, "до подтверждения профиль не удалён")
		viewport.queue_free()
		await wait_process_frames(1)


func test_a_b_free_ride_no_trainer_dialog() -> void:
	var config: Dictionary = CONFIGS[1]
	var started := _start(config, "free")
	var viewport: SubViewport = started[0]
	var main: AppMain = started[1]
	assert_false(main.start_free_ride(RouteCatalog.DEFAULT_ID, 50), "станка нет — диалог")
	await wait_process_frames(2)
	var dialog := main.free_ride_trainer_dialog()
	_check_dialog(dialog, viewport, config, "free_ride_no_trainer")
	assert_eq(dialog.get_ok_button().get_viewport().gui_get_focus_owner(), dialog.get_ok_button(), "обычный диалог: фокус на основной кнопке")
	_tap(viewport, KEY_ESCAPE)
	await wait_process_frames(2)
	assert_false(dialog.visible)
	assert_eq(main.pending_free_ride(), {}, "Esc — отмена")


func test_finish_confirmation_card_follows_dialog_rules() -> void:
	var overlay: PauseOverlay = load("res://src/ui/hud/pause_overlay.tscn").instantiate()
	add_child_autofree(overlay)
	overlay.show_pause()
	overlay.finish_button().pressed.emit()
	await wait_process_frames(3)
	assert_eq(overlay.view(), PauseOverlay.View.CONFIRM, "(г) «Завершить» открывает подтверждение")
	assert_eq(get_viewport().gui_get_focus_owner(), overlay.cancel_button(), "фокус на «Отмена»")
	var card := overlay.cancel_button().get_parent().get_parent().get_parent() as Control
	assert_almost_eq(card.size.x, 480.0, 1.0, "карточка подтверждения 480 lp")
	var cancel := overlay.cancel_button()
	var confirm := overlay.confirm_button()
	assert_lt(cancel.global_position.x, confirm.global_position.x, "«Отмена» слева")
	var row := confirm.get_parent() as Control
	assert_almost_eq(confirm.position.x + confirm.size.x, row.size.x, 1.0, "ряд прижат вправо")
	assert_eq(confirm.theme_type_variation, &"DangerButton")
	watch_signals(overlay)
	var esc := _key(KEY_ESCAPE)
	overlay._input(esc)
	assert_signal_not_emitted(overlay, "finish_confirmed", "Esc не завершает")
	assert_eq(overlay.view(), PauseOverlay.View.PAUSE, "Esc — назад к паузе")
