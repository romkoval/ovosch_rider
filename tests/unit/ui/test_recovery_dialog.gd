extends GutTest
## T-114: диалог восстановления заезда на общем `DialogLayout` (REQ-UIX-01 крит. 8, 9;
## регрессия REQ-LOC-07 крит. 3): «Удалить» — опасная кнопка, ширина 480, ряд справа,
## фокус при открытии — «Сохранить»; Enter и Esc сразу после открытия сохраняют заезд,
## удаление — только нажатием «Удалить».

const THEME_PATH: String = "res://src/ui/theme/app_theme.tres"

var _viewport: SubViewport = null
var _dialog: RecoveryDialog = null
var _decisions: Array = []


func before_each() -> void:
	_decisions = []
	_viewport = SubViewport.new()
	_viewport.gui_embed_subwindows = true
	_viewport.size = Vector2i(1280, 720)
	add_child_autofree(_viewport)
	var host := Control.new()
	host.theme = load(THEME_PATH) as Theme
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(host)
	_dialog = RecoveryDialog.new()
	_dialog.resolved.connect(_on_resolved)
	host.add_child(_dialog)


func _on_resolved(id: String, action: String) -> void:
	_decisions.append([id, action])


func _ride(ride_name: String, offset_sec: int) -> Ride:
	var ride := Ride.new()
	ride.started_at_unix = int(Time.get_unix_time_from_system()) - offset_sec
	ride.id = Ride.generate_id(ride.started_at_unix)
	ride.name = ride_name
	ride.compute_summary()
	return ride


func _open(count: int = 1) -> Array[Ride]:
	var rides: Array[Ride] = []
	for i in count:
		rides.append(_ride("Заезд %d" % i, 3600 * (i + 1)))
	_dialog.show_for(rides)
	await wait_process_frames(3)
	return rides


func _key(code: Key, pressed: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	return e


func _tap(code: Key) -> void:
	_viewport.push_input(_key(code, true))
	_viewport.push_input(_key(code, false))


func _visible_row() -> Array[Button]:
	var out: Array[Button] = []
	for b in DialogLayout.row_buttons(_dialog):
		if b.visible:
			out.append(b)
	out.sort_custom(func(a: Button, b: Button) -> bool: return a.position.x < b.position.x)
	return out


func test_delete_is_danger_button_and_dialog_uses_dialog_layout() -> void:
	assert_not_null(DialogLayout.of(_dialog), "диалог прикреплён к DialogLayout")
	assert_eq(_dialog.delete_button().theme_type_variation, DialogLayout.DANGER_VARIATION, "«Удалить» — опасная")
	assert_ne(_dialog.get_ok_button().theme_type_variation, DialogLayout.DANGER_VARIATION, "«Сохранить» — не опасная")
	assert_ne(_dialog.get_cancel_button().theme_type_variation, DialogLayout.DANGER_VARIATION)


## Вердикт game-designer по T-114 (`ui.md` п. 6 «Диалог-выбор», п. 13.3; REQ-LOC-07 крит. 3,
## REQ-UIX-01 крит. 8): безопасное действие «Сохранить досрочно» — основная `PrimaryButton`
## и стоит крайней справа, слева от неё — опасная «Удалить».
func test_keep_is_primary_button_rightmost() -> void:
	assert_eq(_dialog.get_ok_button().theme_type_variation, &"PrimaryButton", "«Сохранить досрочно» — PrimaryButton")
	var prev_locale := TranslationServer.get_locale()
	for loc in ["ru", "en"]:
		TranslationServer.set_locale(loc)
		await _open()
		var row := _visible_row()
		assert_eq(row.size(), 2, "%s: две кнопки" % loc)
		if row.size() == 2:
			assert_eq(row[1], _dialog.get_ok_button(), "%s: PrimaryButton — крайняя справа" % loc)
			assert_eq(row[0].theme_type_variation, DialogLayout.DANGER_VARIATION, "%s: слева — DangerButton" % loc)
		assert_eq(_dialog.get_ok_button().theme_type_variation, &"PrimaryButton", "%s: вариация после показа" % loc)
		_dialog.keep()
		await wait_process_frames(2)
	TranslationServer.set_locale(prev_locale)


func test_width_480_wrap_and_buttons_at_right_edge() -> void:
	var prev_locale := TranslationServer.get_locale()
	for loc in ["ru", "en"]:
		TranslationServer.set_locale(loc)
		await _open()
		_check_layout(loc)
		_dialog.keep()
		await wait_process_frames(2)
	TranslationServer.set_locale(prev_locale)


func _check_layout(loc: String) -> void:
	assert_true(_dialog.visible, "%s: диалог открыт" % loc)
	assert_almost_eq(float(_dialog.size.x), float(DialogLayout.WIDTH), 1.0, "%s: ширина 480 lp" % loc)
	assert_true(_dialog.dialog_autowrap, "%s: текст переносится" % loc)
	assert_false(_dialog.get_cancel_button().visible, "%s: «Отмена» не показывается (дублирует «сохранить»)" % loc)
	var row := _visible_row()
	assert_eq(row.size(), 2, "%s: две кнопки" % loc)
	if row.size() != 2:
		return
	assert_eq(row[0], _dialog.delete_button(), "%s: «Удалить» — слева" % loc)
	assert_eq(row[1], _dialog.get_ok_button(), "%s: «Сохранить досрочно» — крайняя справа" % loc)
	var ok := _dialog.get_ok_button()
	var parent := ok.get_parent() as Control
	assert_almost_eq(ok.position.x + ok.size.x, parent.size.x, 1.0, "%s: ряд прижат к правому краю" % loc)
	var between := row[1].position.x - (row[0].position.x + row[0].size.x)
	assert_almost_eq(between, DialogLayout.BUTTON_GAP, 1.0, "%s: зазор 12 между кнопками" % loc)
	for b in row:
		assert_almost_eq(b.size.x, b.get_combined_minimum_size().x, 1.0, "%s: «%s» по ширине текста" % [loc, b.text])
		assert_gte(b.size.y, 44.0, "%s: высота «%s» ≥ 44" % [loc, b.text])


func test_default_focus_is_keep_not_delete() -> void:
	await _open()
	var owner := _dialog.get_ok_button().get_viewport().gui_get_focus_owner()
	assert_eq(owner, _dialog.get_ok_button(), "фокус на «Сохранить»")
	assert_ne(owner, _dialog.delete_button(), "фокус не на «Удалить»")


func test_enter_right_after_open_keeps_ride() -> void:
	var rides := await _open()
	_tap(KEY_ENTER)
	await wait_process_frames(2)
	assert_false(_dialog.visible, "Enter закрыл диалог")
	assert_eq(_decisions, [[rides[0].id, RecoveryDialog.ACTION_KEEP]], "Enter — «сохранить»")


func test_escape_right_after_open_keeps_ride() -> void:
	var rides := await _open()
	_tap(KEY_ESCAPE)
	await wait_process_frames(2)
	assert_false(_dialog.visible, "Esc закрыл диалог")
	assert_eq(_decisions, [[rides[0].id, RecoveryDialog.ACTION_KEEP]], "Esc — «сохранить»")


func test_escape_and_close_keep_and_show_next_ride() -> void:
	var rides := await _open(3)
	_tap(KEY_ESCAPE)
	await wait_process_frames(3)
	assert_eq(_decisions, [[rides[0].id, RecoveryDialog.ACTION_KEEP]], "Esc — сохранить")
	assert_eq(_dialog.current_ride().id, rides[1].id, "следующий заезд")
	assert_true(_dialog.visible, "после Esc следующий заезд показан (не скрыт отложенным hide)")
	# «×» в заголовке встроенного окна — уведомление закрытия окна.
	_dialog.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	await wait_process_frames(3)
	assert_eq(_decisions.size(), 2)
	if _decisions.size() == 2:
		assert_eq(_decisions[1], [rides[1].id, RecoveryDialog.ACTION_KEEP], "«×» — сохранить")
	assert_true(_dialog.visible, "после «×» показан третий заезд")
	assert_eq(_dialog.current_ride().id, rides[2].id)


func test_only_delete_button_deletes() -> void:
	var rides := await _open(2)
	_dialog.delete_button().pressed.emit()
	await wait_process_frames(2)
	assert_eq(_decisions, [[rides[0].id, RecoveryDialog.ACTION_DELETE]], "«Удалить» — удаление")
	assert_eq(_dialog.current_ride().id, rides[1].id, "после решения — следующий")
	assert_true(_dialog.visible, "следующий заезд показан")
	# Фокус у следующего заезда снова на безопасном действии: Enter сохраняет.
	assert_eq(_dialog.get_ok_button().get_viewport().gui_get_focus_owner(), _dialog.get_ok_button())
	_tap(KEY_ENTER)
	await wait_process_frames(2)
	assert_eq(_decisions.size(), 2)
	if _decisions.size() == 2:
		assert_eq(_decisions[1], [rides[1].id, RecoveryDialog.ACTION_KEEP], "Enter у второго — сохранить")
	assert_false(_dialog.visible)


## T-173 (REQ-LOC-07 п.3, NFR-08): дата старта — как в истории (`HistoryFormat.full_date`), ru и en.
func test_date_is_history_full_date_in_current_locale() -> void:
	var before := TranslationServer.get_locale()
	var ride := _ride("Утро", 600)
	for loc in ["ru", "en"]:
		TranslationServer.set_locale(loc)
		_dialog.show_for([ride] as Array[Ride])
		await wait_process_frames(2)
		var expected := HistoryFormat.full_date(ride.started_at_unix)
		assert_string_contains(_dialog.dialog_text, expected, "%s: дата как в истории" % loc)
		var machine := RegEx.create_from_string("\\d{4}-\\d{2}-\\d{2}")
		assert_null(machine.search(_dialog.dialog_text), "%s: без ГГГГ-ММ-ДД" % loc)
		_dialog.hide()
	TranslationServer.set_locale(before)
