extends GutTest
## Общие компоненты меню (T-076; `docs/game/ui.md` п. 6, 9.2): AppBar, StatView, Banner,
## ListRow, EmptyState. REQ-UIX-04 крит. 1 (компонент «назад» вызывает `AppState.go_back()`),
## REQ-UIX-01 крит. 2, 3 (только вариации темы, без локальных переопределений), REQ-UIX-05
## крит. 1 (цели нажатия: сенсорные — 52 lp ≥ 44, компьютер — 40 lp).

const APP_BAR := preload("res://src/ui/common/app_bar.tscn")
const STAT := preload("res://src/ui/common/stat_view.tscn")
const BANNER := preload("res://src/ui/common/banner.tscn")
const ROW := preload("res://src/ui/common/list_row.tscn")
const EMPTY := preload("res://src/ui/common/empty_state.tscn")
const STAND := preload("res://src/ui/common/components_stand.tscn")
const COMPONENT_FILES: Array[String] = [
	"res://src/ui/common/app_bar.tscn", "res://src/ui/common/app_bar.gd",
	"res://src/ui/common/stat_view.tscn", "res://src/ui/common/stat_view.gd",
	"res://src/ui/common/banner.tscn", "res://src/ui/common/banner.gd",
	"res://src/ui/common/list_row.tscn", "res://src/ui/common/list_row.gd",
	"res://src/ui/common/empty_state.tscn", "res://src/ui/common/empty_state.gd",
	"res://src/ui/common/components_stand.tscn", "res://src/ui/common/components_stand.gd",
	"res://src/ui/common/touch_target.gd",
]

var _dir: String
var _repo: ProfileRepository
var _locale: String
var _back_results: Array[bool] = []
var _signals: Array[String] = []


func before_each() -> void:
	_dir = "user://test_menu_components_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_repo = ProfileRepository.new(_dir)
	_locale = TranslationServer.get_locale()
	_back_results = []
	_signals = []


func after_each() -> void:
	TranslationServer.set_locale(_locale)
	_remove_tree(ProjectSettings.globalize_path(_dir))


static func _remove_tree(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var d := DirAccess.open(abs_path)
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)


func _on_back(handled: bool) -> void:
	_back_results.append(handled)


func _on_signal(name: String) -> void:
	_signals.append(name)


func _started_state() -> AppState:
	_repo.create("One")
	var s := AppState.new(_repo)
	s.start()
	return s


func _bar() -> AppBar:
	var bar: AppBar = APP_BAR.instantiate()
	add_child_autofree(bar)
	return bar


# --- AppBar: «назад» -----------------------------------------------------------------------

func test_req_uix_04_c1_back_button_calls_go_back() -> void:
	var state := _started_state()
	assert_true(state.navigate(AppState.Screen.HISTORY))
	var bar := _bar()
	bar.setup(state)
	bar.back_pressed.connect(_on_back)
	bar.back_button().pressed.emit()
	assert_eq(state.current_screen, AppState.Screen.HOME, "«назад» AppBar → AppState.go_back() → главный")
	assert_eq(_back_results, [true] as Array[bool], "back_pressed(handled = true)")


func test_req_uix_04_c1_back_returns_to_screen_we_came_from() -> void:
	var state := _started_state()
	state.navigate(AppState.Screen.PLAN)
	state.navigate(AppState.Screen.DEVICES)
	var bar := _bar()
	bar.setup(state)
	bar.back_button().pressed.emit()
	assert_eq(state.current_screen, AppState.Screen.PLAN, "с устройств — туда, откуда пришли (план)")


func test_back_on_root_screen_does_nothing() -> void:
	var state := _started_state()
	var bar := _bar()
	bar.setup(state)
	bar.back_pressed.connect(_on_back)
	assert_false(bar.press_back())
	assert_eq(state.current_screen, AppState.Screen.HOME)
	assert_eq(_back_results, [false] as Array[bool])


func test_back_without_navigation_only_emits_signal() -> void:
	var state := _started_state()
	state.navigate(AppState.Screen.HISTORY)
	var bar := _bar()
	bar.setup(state)
	bar.navigate_on_back = false
	bar.back_pressed.connect(_on_back)
	bar.back_button().pressed.emit()
	assert_eq(state.current_screen, AppState.Screen.HISTORY, "навигация выключена — экран решает сам (карточка заезда → список)")
	assert_eq(_back_results, [false] as Array[bool])


func test_app_bar_structure_and_title() -> void:
	var bar := _bar()
	assert_eq(bar.theme_type_variation, &"AppBar")
	assert_eq(bar.back_button().theme_type_variation, &"IconButton")
	assert_not_null(bar.back_button().icon, "иконка chevron-left")
	assert_eq(bar.back_button().tooltip_text, "ui.menu.back")
	assert_true(bar.back_button().focus_mode != Control.FOCUS_NONE, "«назад» достижима с клавиатуры")
	var title := bar.get_node("%Title") as Label
	assert_eq(title.theme_type_variation, &"H1Label", "заголовок — вариация H1 (UIX-04 крит. 1)")
	assert_eq(title.get_theme_font_size(&"font_size"), 28, "H1 28 lp из темы проекта")
	TranslationServer.set_locale("ru")
	bar.set_title("ui.menu.stand.title")
	assert_eq(bar.title_text(), "Компоненты меню")
	TranslationServer.set_locale("en")
	bar.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
	assert_eq(bar.title_text(), "Menu components", "смена языка обновляет заголовок")
	bar.set_title("ui.menu.stand.title", false)
	assert_eq(bar.title_text(), "ui.menu.stand.title", "пользовательские данные не переводятся")
	assert_eq(title.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "…и сокращаются «…»")
	bar.show_back = false
	assert_false(bar.back_button().visible)
	var action := Button.new()
	bar.add_action(action)
	assert_eq(action.get_parent(), bar.actions_slot())


func test_app_bar_height() -> void:
	var bar := _bar()
	await wait_physics_frames(2)
	var expected := AppBar.HEIGHT_COMPACT if get_viewport().get_visible_rect().size.x < AppBar.COMPACT_MAX_WIDTH else AppBar.HEIGHT
	assert_eq(bar.custom_minimum_size.y, expected, "72 lp (compact — 64)")
	assert_gte(bar.get_combined_minimum_size().y, expected)


# --- Цели нажатия (REQ-UIX-05 крит. 1) -----------------------------------------------------

func _interactive(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	var c := root as Control
	if c != null and c.focus_mode != Control.FOCUS_NONE and c.is_visible_in_tree():
		out.append(c)
	for child in root.get_children():
		out.append_array(_interactive(child))
	return out


func _populated_stand() -> Control:
	var stand: Control = STAND.instantiate()
	add_child_autofree(stand)
	return stand


func _assert_targets(root: Node, ui: UiScale, min_side: float, what: String) -> void:
	var controls := _interactive(root)
	assert_gt(controls.size(), 5, "на стенде есть интерактивные элементы")
	for c in controls:
		var helper := TouchTarget.of(c)
		assert_not_null(helper, "%s: у %s есть TouchTarget" % [what, c.get_path()])
		if helper == null:
			continue
		helper.set_runtime(ui)
	await wait_physics_frames(2)
	for c in controls:
		var s := c.get_combined_minimum_size()
		assert_true(s.x >= min_side and s.y >= min_side, "%s: %s — %s ≥ %s lp" % [what, c.name, s, min_side])
		assert_true(c.size.x >= min_side and c.size.y >= min_side, "%s: %s — размер после раскладки %s" % [what, c.name, c.size])


func test_req_uix_05_c1_touch_targets_on_touch_devices() -> void:
	var stand := _populated_stand()
	await wait_physics_frames(2)
	var tablet: UiScale = autofree(UiScale.new())
	tablet.device = UiScale.Device.TABLET
	await _assert_targets(stand, tablet, 44.0, "сенсорные (≥ 44 pt)")
	var phone: UiScale = autofree(UiScale.new())
	phone.device = UiScale.Device.PHONE
	await _assert_targets(stand, phone, UiScale.TOUCH_UI_TOUCH, "телефон (touch_ui 52)")


func test_req_uix_05_c1_touch_targets_on_desktop() -> void:
	var stand := _populated_stand()
	await wait_physics_frames(2)
	var desktop: UiScale = autofree(UiScale.new())
	desktop.device = UiScale.Device.DESKTOP
	await _assert_targets(stand, desktop, UiScale.TOUCH_UI_DESKTOP, "компьютер (40 lp)")


func test_back_button_at_least_48_on_desktop() -> void:
	var bar := _bar()
	var desktop: UiScale = autofree(UiScale.new())
	desktop.device = UiScale.Device.DESKTOP
	TouchTarget.of(bar.back_button()).set_runtime(desktop)
	assert_eq(bar.back_button().custom_minimum_size, Vector2(48, 48), "ui.md п. 6: не меньше 48 на компьютере")
	desktop.device = UiScale.Device.PHONE
	desktop.scale_changed.emit(1.8)
	assert_eq(bar.back_button().custom_minimum_size, Vector2(52, 52), "на сенсорных — touch_ui 52")


# --- Только вариации темы (REQ-UIX-01 крит. 2, 3) -------------------------------------------

func test_req_uix_01_c2_no_local_overrides_in_components() -> void:
	var forbidden := RegEx.create_from_string("theme_override_|add_theme_[a-z_]+_override")
	for path in COMPONENT_FILES:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), "%s прочитан" % path)
		var m := forbidden.search(text)
		assert_null(m, "%s: локальное переопределение темы «%s»" % [path, m.get_string() if m != null else ""])


func test_req_uix_01_c3_component_variations_exist_in_project_theme() -> void:
	var theme := ThemeDB.get_project_theme()
	assert_not_null(theme)
	var used: Dictionary = {}
	# Имена вариаций в сценах и скриптах — литералы StringName с заглавной буквы.
	var re := RegEx.create_from_string("&\"([A-Z][A-Za-z0-9]*)\"")
	for path in COMPONENT_FILES:
		if path.ends_with("touch_target.gd"):
			continue
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			used[m.get_string(1)] = path
	for name: String in ["AppBar", "H1Label", "IconButton", "StatLabel", "StatLargeLabel", "SecondaryLabel", "CaptionLabel", "BannerWarn", "BannerError", "BannerInfo", "GhostButton", "ListRowButton", "TitleLabel", "H2Label", "PrimaryButton"]:
		assert_true(used.has(name), "компоненты используют вариацию %s" % name)
	for name: String in used:
		assert_ne(theme.get_type_variation_base(name), &"", "вариация %s (%s) есть в теме проекта" % [name, used[name]])


func test_stat_view() -> void:
	var stat: StatView = STAT.instantiate()
	add_child_autofree(stat)
	TranslationServer.set_locale("ru")
	stat.set_stat("300", "ui.menu.unit.w", "ui.menu.stand.stat_max_target")
	assert_eq(stat.value_label().text, "300")
	assert_eq(stat.value_label().theme_type_variation, &"StatLabel", "цифры — Stat с tnum")
	assert_eq(stat.unit_label().text, "Вт")
	assert_eq(stat.unit_label().theme_type_variation, &"SecondaryLabel", "единица мельче, text2")
	assert_eq(stat.unit_label().get_theme_color(&"font_color"), UiTokens.TEXT2)
	assert_eq(stat.caption_label().theme_type_variation, &"CaptionLabel")
	assert_eq(stat.caption_label().text, "макс. цель")
	TranslationServer.set_locale("en")
	stat.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
	assert_eq(stat.unit_label().text, "W")
	stat.large = true
	assert_eq(stat.value_label().theme_type_variation, &"StatLargeLabel")
	assert_eq(stat.value_label().get_theme_font_size(&"font_size"), 32)
	stat.set_stat("38:00")
	assert_false(stat.unit_label().visible, "без единицы — скрыта")
	assert_false(stat.caption_label().visible)


func test_banner_kinds_and_action() -> void:
	var banner: Banner = BANNER.instantiate()
	add_child_autofree(banner)
	banner.action_pressed.connect(_on_signal.bind("banner"))
	var kinds := {Banner.Kind.INFO: &"BannerInfo", Banner.Kind.WARN: &"BannerWarn", Banner.Kind.ERROR: &"BannerError"}
	for kind: Banner.Kind in kinds:
		banner.show_banner(kind, "ui.menu.stand.banner_warn", "ui.menu.stand.banner_warn_action", "bluetooth-off")
		assert_eq(banner.theme_type_variation, kinds[kind])
		assert_eq(banner.icon_rect().self_modulate, banner.status_color(), "иконка цветом статуса")
	assert_eq(banner.status_color(), UiTokens.DANGER_TEXT)
	assert_true(banner.icon_rect().visible)
	assert_eq(banner.action_button().theme_type_variation, &"GhostButton", "действие — текстовая кнопка")
	assert_true(banner.action_button().visible)
	assert_eq(banner.text_label().autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "длинный текст переносится, не обрезается")
	banner.action_button().pressed.emit()
	assert_eq(_signals, ["banner"] as Array[String])
	banner.show_banner(Banner.Kind.INFO, "ui.menu.stand.banner_info")
	assert_false(banner.action_button().visible, "без действия — кнопки нет")
	assert_false(banner.icon_rect().visible)


func test_empty_state() -> void:
	var empty: EmptyState = EMPTY.instantiate()
	add_child_autofree(empty)
	empty.action_pressed.connect(_on_signal.bind("empty"))
	TranslationServer.set_locale("ru")
	empty.setup("history", "ui.menu.stand.empty_title", "ui.menu.stand.empty_text", "ui.menu.stand.empty_action")
	assert_true(empty.icon_rect().visible)
	assert_not_null(empty.icon_rect().texture)
	assert_eq(empty.icon_rect().self_modulate, UiTokens.TEXT_DISABLED, "иконка text_disabled")
	assert_eq(empty.title_label().theme_type_variation, &"H2Label")
	assert_eq(empty.title_label().text, "Заездов пока нет")
	assert_eq(empty.text_label().theme_type_variation, &"SecondaryLabel")
	assert_eq(empty.action_button().theme_type_variation, &"PrimaryButton", "действие — основная кнопка")
	assert_eq(empty.action_button().text, "На главный")
	empty.action_button().pressed.emit()
	assert_eq(_signals, ["empty"] as Array[String])
	empty.setup("history", "ui.menu.stand.empty_title")
	assert_false(empty.action_button().visible)


# --- ListRow -------------------------------------------------------------------------------

func _row() -> ListRow:
	var row: ListRow = ROW.instantiate()
	add_child_autofree(row)
	row.size.x = 900
	return row


func test_list_row_heights() -> void:
	var row := _row()
	row.set_texts("Tacx Neo 2T")
	assert_eq(row.theme_type_variation, &"ListRowButton", "вариация строки списка (UIX-04 крит. 3)")
	assert_eq(row.text_lines(), 1)
	assert_eq(row.custom_minimum_size.y, ListRow.HEIGHT, "одна строка — 64 lp")
	row.set_texts("Sweet Spot", "", "3 Oct, 21:12")
	assert_eq(row.text_lines(), 2)
	assert_eq(row.custom_minimum_size.y, ListRow.HEIGHT_TWO_LINES, "две строки — 76 lp")
	row.set_texts("Mountain Pass", "+412 m", "2 Oct, 19:40")
	var content := (row.get_node("%Content") as Control).get_combined_minimum_size()
	assert_gte(row.custom_minimum_size.y, content.y, "три строки — по содержимому")


func test_list_row_columns_and_slots() -> void:
	var row := _row()
	row.set_texts("Sweet Spot")
	row.set_columns(["1:02:15", "32.4", "212"], [72, 56, 56])
	assert_eq(row.column_texts(), ["1:02:15", "32.4", "212"] as Array[String])
	var columns := row.get_node("%Columns").get_children()
	assert_eq((columns[0] as Label).custom_minimum_size.x, 72.0, "фиксированная ширина колонки")
	assert_eq((columns[1] as Label).horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT, "значения по правому краю")
	assert_eq((columns[0] as Label).mouse_filter, Control.MOUSE_FILTER_PASS)
	row.set_icon("bike")
	assert_true(row.leading_slot().visible)
	var tag := Label.new()
	row.add_trailing(tag)
	assert_eq(tag.mouse_filter, Control.MOUSE_FILTER_PASS, "содержимое пропускает нажатие строке")
	var button := Button.new()
	row.add_trailing(button)
	assert_eq(button.mouse_filter, Control.MOUSE_FILTER_STOP, "свои кнопки в слоте остаются интерактивными")
	assert_eq(row.get_node("%Title").theme_type_variation, &"TitleLabel")
	assert_eq((row.get_node("%Chevron") as TextureRect).self_modulate, UiTokens.TEXT_DISABLED, "шеврон text_disabled")
	row.set_columns([])
	assert_eq(row.column_texts().size(), 0)


func test_list_row_selection_single_in_group() -> void:
	var group := ButtonGroup.new()
	var a := _row()
	var b := _row()
	for r: ListRow in [a, b]:
		r.selectable = true
		r.button_group = group
	a.set_selected(true)
	assert_true(a.is_selected())
	b.button_pressed = true
	assert_true(b.is_selected())
	assert_false(a.is_selected(), "в группе выбрана ровно одна строка")
	var plain := _row()
	plain.set_selected(true)
	assert_false(plain.is_selected(), "невыбираемая строка не залипает")


func test_list_row_click_on_content_activates_row() -> void:
	var row := _row()
	row.row_id = "ride-42"
	row.set_texts("Sweet Spot", "", "3 Oct")
	row.position = Vector2(10, 10)
	row.activated.connect(_on_signal)
	await wait_physics_frames(2)
	var title := row.get_node("%Title") as Control
	var at := title.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		# Координаты холста (local): окно headless крошечное, растяжение canvas_items.
		get_viewport().push_input(ev, true)
	await wait_physics_frames(1)
	assert_eq(_signals, ["ride-42"] as Array[String], "нажатие на заголовок активирует строку (mouse_filter PASS)")
