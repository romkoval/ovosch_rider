extends GutTest
## Вуаль `scrim` под диалогами меню (T-142; REQ-UIX-01 п.9, `ui.md` п. 6 «Диалог»: «scrim под ним»):
## у каждого диалога оболочки и экранов меню есть `DialogLayout`; пока диалог виден, под ним
## вуаль `UiTokens.SCRIM` на всю видимую область вьюпорта, ниже встроенных окон; скрыт — вуали нет.

const MAIN_SCENE: String = "res://src/app/main.tscn"

var _dir: String


func before_each() -> void:
	_dir = "user://test_dialog_scrim_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]


func after_each() -> void:
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
	return main


func _assert_scrim_under(dialog: AcceptDialog, where: String) -> void:
	var layout := DialogLayout.of(dialog)
	assert_not_null(layout, "%s: DialogLayout прикреплён" % where)
	if layout == null:
		return
	assert_true(layout.is_scrim_visible(), "%s: вуаль видна" % where)
	var scrim := layout.scrim()
	assert_eq(scrim.color, UiTokens.SCRIM, "%s: цвет — токен scrim" % where)
	var rect := dialog.get_parent().get_viewport().get_visible_rect()
	assert_eq(Rect2(scrim.position, scrim.size), rect, "%s: на всю видимую область" % where)
	assert_eq(scrim.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	var layer := scrim.get_parent() as CanvasLayer
	assert_lt(layer.layer, 1024, "%s: ниже встроенных окон" % where)
	assert_eq(layer.custom_viewport, dialog.get_parent().get_viewport(), "%s: во вьюпорте родителя" % where)


func test_every_menu_dialog_has_layout_helper() -> void:
	var main := _main()
	var dialogs := main.find_children("*", "AcceptDialog", true, false)
	assert_gt(dialogs.size(), 5, "диалоги найдены")
	for node in dialogs:
		if node is FileDialog:
			continue
		assert_not_null(DialogLayout.of(node as AcceptDialog), "%s: DialogLayout" % (node as Node).get_path())


func test_forget_intervals_dialog_shows_scrim_and_hides_it() -> void:
	var main := _main()
	main.app_state.navigate(AppState.Screen.SETTINGS)
	var settings := main.settings_screen()
	var dialog := settings.get_node("%ForgetIntervalsDialog") as ConfirmationDialog
	dialog.popup_centered()
	await wait_process_frames(2)
	_assert_scrim_under(dialog, "Отвязать Intervals.icu")
	dialog.hide()
	assert_false(DialogLayout.of(dialog).is_scrim_visible(), "после закрытия вуали нет")


func test_licenses_sheet_and_free_ride_dialog_have_scrim() -> void:
	var main := _main()
	main.app_state.navigate(AppState.Screen.SETTINGS)
	main.settings_screen().open_licenses()
	await wait_process_frames(2)
	var licenses := main.settings_screen().get_node("%LicensesDialog") as AcceptDialog
	_assert_scrim_under(licenses, "лицензии")
	licenses.hide()
	main.app_state.navigate(AppState.Screen.HOME)
	main.start_free_ride(RouteCatalog.FLAT, 50)
	await wait_process_frames(2)
	var trainer := main.free_ride_trainer_dialog()
	assert_true(trainer.visible)
	_assert_scrim_under(trainer, "станок не подключён")
	trainer.hide()
	assert_false(DialogLayout.of(trainer).is_scrim_visible())


func test_scrim_follows_viewport_resize() -> void:
	var main := _main()
	main.app_state.navigate(AppState.Screen.SETTINGS)
	var dialog := main.settings_screen().get_node("%ForgetIntervalsDialog") as ConfirmationDialog
	dialog.popup_centered()
	await wait_process_frames(1)
	var vp := dialog.get_parent().get_viewport()
	vp.size_changed.emit()
	assert_eq(DialogLayout.of(dialog).scrim().size, vp.get_visible_rect().size)
	dialog.hide()
