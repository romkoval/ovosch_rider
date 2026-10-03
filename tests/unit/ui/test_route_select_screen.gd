extends GutTest
## Экран выбора трассы (T-080): REQ-FRD-02 крит. 1–3, REQ-FRD-03 крит. 4–6 (что проверяется
## автоматически), REQ-FRD-05 крит. 1 (UI), REQ-UIX-03 крит. 2, 3, REQ-UIX-04 крит. 1,
## REQ-UIX-05 крит. 1, 4, REQ-D3D-08 крит. 1 (названия на экране). Раскладка — `docs/game/ui.md` п. 8.4.

const SCENE: String = "res://src/ui/tracks/route_select_screen.tscn"
const SCENE_FILE: String = "res://src/ui/tracks/route_select_screen.tscn"
const NAMES: Dictionary = {
	"flat": ["Пшеничные поля", "Wheat Fields"],
	"hills": ["Зелёные холмы", "Green Hills"],
	"mountains": ["Перевал", "Mountain Pass"],
	"seaside": ["Приморье", "Seaside"],
}

var _dir: String
var _repo: ProfileRepository
var _state: AppState
var _previous_locale: String


func before_each() -> void:
	_dir = "user://test_route_select_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	_repo = ProfileRepository.new(_dir + "profiles/")
	_repo.create("Solo")
	_state = AppState.new(_repo)
	_state.start()


func after_each() -> void:
	TranslationServer.set_locale(_previous_locale)
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


## Экран в окне размера `canvas` (lp): `SubViewport` задаёт ширину холста для брейкпоинтов.
func _screen(canvas: Vector2i = Vector2i(1280, 720)) -> RouteSelectScreen:
	var viewport := SubViewport.new()
	viewport.size = canvas
	add_child_autofree(viewport)
	var screen: RouteSelectScreen = (load(SCENE) as PackedScene).instantiate()
	screen.setup(_repo, _state)
	viewport.add_child(screen)
	screen.refresh()
	return screen


func _active() -> Profile:
	return _repo.get_active()


# --- FRD-02 крит. 1, UIX-03 крит. 2, 3: четыре карточки, ровно одна выбрана --------------------

func test_four_cards_in_catalog_order_one_selected() -> void:
	var s := _screen()
	var ids: Array[String] = []
	for card in s.cards():
		ids.append(card.route_id)
	assert_eq(ids, RouteCatalog.ids(), "карточки всех трасс каталога по порядку")
	assert_eq(s.cards().size(), 4)
	assert_eq(s.selected_card_count(), 1, "ровно одна выбрана")
	for card in s.cards():
		assert_eq(card.theme_type_variation, &"CardButton")
		assert_true(card.toggle_mode)
		assert_eq(card.preview.mode, RoutePreviewModel.Mode.THUMB)
		assert_eq(card.stats.size(), 3, "три цифры")


func test_cards_grid_is_two_by_two() -> void:
	var s := _screen()
	await wait_process_frames(2)
	var a := s.card_for("flat").get_global_rect()
	var b := s.card_for("hills").get_global_rect()
	var c := s.card_for("mountains").get_global_rect()
	var d := s.card_for("seaside").get_global_rect()
	assert_almost_eq(a.position.y, b.position.y, 0.5, "первый ряд")
	assert_almost_eq(c.position.y, d.position.y, 0.5, "второй ряд")
	assert_almost_eq(a.position.x, c.position.x, 0.5, "первая колонка")
	assert_gt(c.position.y, a.end.y - 0.5, "второй ряд ниже первого")


func test_only_one_selected_after_presses() -> void:
	var s := _screen()
	for id in ["hills", "seaside", "mountains"]:
		s.card_for(id).pressed.emit()
		assert_eq(s.selected_route_id(), id)
		assert_eq(s.selected_card_count(), 1)
		assert_true(s.card_for(id).is_selected())


# --- FRD-02 крит. 3: первый запуск — flat, далее последняя выбранная; сохраняется ------------

func test_first_open_preselects_flat() -> void:
	var s := _screen()
	assert_eq(s.selected_route_id(), "flat")
	assert_true(s.card_for("flat").is_selected())


func test_preselects_last_route_from_profile() -> void:
	assert_eq(_repo.set_last_route_id(_active().id, "mountains"), [] as Array[String])
	var s := _screen()
	assert_eq(s.selected_route_id(), "mountains")
	assert_true(s.card_for("mountains").is_selected())


func test_unknown_route_in_profile_falls_back_to_flat() -> void:
	assert_eq(_repo.set_last_route_id(_active().id, "volcano"), [] as Array[String])
	var s := _screen()
	assert_eq(s.preselected_route_id(), "flat")
	assert_eq(s.selected_route_id(), "flat")
	assert_eq(s.selected_card_count(), 1)


func test_selection_is_saved_to_profile_and_restored_on_refresh() -> void:
	var s := _screen()
	s.card_for("seaside").pressed.emit()
	assert_eq(s.last_save_errors(), [] as Array[String])
	var reread := ProfileRepository.new(_dir + "profiles/")
	assert_eq(reread.get_active().effective_route_id(), "seaside", "на диске")
	_repo.set_last_route_id(_active().id, "hills")
	s.refresh()
	assert_eq(s.selected_route_id(), "hills", "refresh перечитывает профиль")


# --- FRD-05 крит. 1: слайдер 0–100 шаг 5, по умолчанию из профиля, сохраняется ---------------

func test_slider_range_default_and_label() -> void:
	var s := _screen()
	var slider := s.steepness_slider()
	assert_eq(slider.min_value, 0.0)
	assert_eq(slider.max_value, 100.0)
	assert_eq(slider.step, 5.0)
	assert_eq(s.steepness_pct(), 50, "по умолчанию 50 %")
	assert_eq(s.steepness_value_text(), "50 %")


func test_slider_value_from_profile_and_saved_on_change() -> void:
	_repo.set_sim_steepness_pct(_active().id, 35)
	var s := _screen()
	assert_eq(s.steepness_pct(), 35)
	s.steepness_slider().value = 70
	assert_eq(s.steepness_value_text(), "70 %")
	var reread := ProfileRepository.new(_dir + "profiles/")
	assert_eq(reread.get_active().sim_steepness_pct, 70, "сохранено на диск")
	s.set_steepness_pct(83)
	assert_eq(s.steepness_pct(), 85, "шаг 5 %")


# --- FRD-02 крит. 2 (передача id), UIX-03 крит. 3: «Поехать» одним действием ------------------

func test_start_emits_selected_route_and_steepness() -> void:
	var s := _screen()
	watch_signals(s)
	s.card_for("hills").pressed.emit()
	s.steepness_slider().value = 25
	s.start_button().pressed.emit()
	assert_signal_emitted_with_parameters(s, "start_requested", ["hills", 25])
	assert_eq(_active().effective_route_id(), "hills")
	assert_eq(_active().sim_steepness_pct, 25)


func test_start_button_is_primary_and_translated() -> void:
	var s := _screen()
	assert_eq(s.start_button().theme_type_variation, &"PrimaryButton")
	assert_eq(s.start_button().text, "Поехать")
	TranslationServer.set_locale("en")
	await wait_process_frames(1)
	assert_eq(s.start_button().text, "Ride")


# --- D3D-08 крит. 1, FRD-02 крит. 1: названия на языке интерфейса ------------------------------

func test_card_names_and_kinds_ru_en() -> void:
	var s := _screen()
	for id: String in NAMES:
		assert_eq(s.card_for(id).title_label.text, NAMES[id][0], id + " [ru]")
	assert_eq(s.card_for("seaside").kind_label.text, "море и мост")
	TranslationServer.set_locale("en")
	await wait_process_frames(1)
	for id: String in NAMES:
		assert_eq(s.card_for(id).title_label.text, NAMES[id][1], id + " [en]")
	assert_eq(s.card_for("seaside").kind_label.text, "sea & bridge")
	assert_eq(s.app_bar().title_text(), "Free ride")


# --- FRD-03 крит. 2, 4–6, UIX-03 крит. 2: цифры с единицами, деталь выбранной ------------------

func test_card_stats_with_units() -> void:
	var s := _screen()
	var stats := s.card_for("mountains").stats
	assert_eq(stats[0].value_label().text, "20.0")
	assert_eq(stats[0].unit_label().text, "км")
	assert_eq(stats[0].caption_label().text, "круг")
	assert_eq(stats[1].value_label().text, "441")
	assert_eq(stats[1].unit_label().text, "м")
	assert_eq(stats[2].value_label().text, "9.4")
	assert_eq(stats[2].unit_label().text, "%")


func test_detail_follows_selection() -> void:
	var s := _screen()
	s.card_for("mountains").pressed.emit()
	assert_eq(s.detail_name_text(), "Перевал")
	assert_eq(s.detail_subtitle_text(), "Mountain Pass · горы")
	assert_eq(s.large_preview().mode, RoutePreviewModel.Mode.LARGE)
	assert_eq(s.large_preview().model.route_id, "mountains")
	var stats := s.detail_stats()
	assert_eq(stats.size(), 3)
	assert_eq(stats[0].value_label().text, "20.0")
	assert_eq(stats[2].value_label().text, "9.4")
	TranslationServer.set_locale("en")
	await wait_process_frames(1)
	assert_eq(s.detail_name_text(), "Mountain Pass")
	assert_eq(s.detail_subtitle_text(), "mountains", "на английском название уже в заголовке")


func test_large_preview_takes_about_38_percent_of_detail() -> void:
	var s := _screen()
	await wait_process_frames(3)
	var ratio := s.large_preview().size.y / s.detail_panel().size.y
	assert_between(ratio, 0.33, 0.45, "≈ 38 %% панели (%.2f)" % ratio)


# --- UIX-04 крит. 1: AppBar с H1 и «назад» -----------------------------------------------------

func test_app_bar_title_and_back_goes_back() -> void:
	var s := _screen()
	assert_eq(s.app_bar().title_text(), "Свободная езда")
	assert_true(_state.navigate(AppState.Screen.ROUTE_SELECT))
	s.app_bar().back_button().pressed.emit()  # видимая кнопка «назад» AppBar
	assert_eq(_state.current_screen, AppState.Screen.HOME, "«назад» — откуда пришли")
	assert_false(s.handle_back(), "regular: «назад» решает стек")


# --- UIX-05 крит. 4: compact — деталь в листе снизу; ширина контента ≤ 1216 ---------------------

func test_regular_layout_detail_beside_grid() -> void:
	var s := _screen(Vector2i(1280, 720))
	await wait_process_frames(2)
	assert_false(s.is_compact())
	assert_true(s.detail_panel().is_visible_in_tree())
	var grid_rect := s.card_for("hills").get_global_rect()
	assert_gt(s.detail_panel().get_global_rect().position.x, grid_rect.end.x - 0.5, "деталь справа от сетки")


func test_compact_detail_in_bottom_sheet() -> void:
	var s := _screen(Vector2i(867, 400))
	await wait_process_frames(2)
	assert_true(s.is_compact())
	assert_false(s.is_sheet_open())
	assert_false(s.detail_panel().is_visible_in_tree(), "деталь скрыта до нажатия")
	var a := s.card_for("flat").get_global_rect()
	var b := s.card_for("hills").get_global_rect()
	assert_almost_eq(a.position.y, b.position.y, 0.5, "сетка 2 × 2 сохраняется")
	s.card_for("mountains").pressed.emit()
	assert_true(s.is_sheet_open(), "нажатие на карточку открывает лист")
	assert_true(s.detail_panel().is_visible_in_tree())
	assert_eq(s.detail_name_text(), "Перевал")
	assert_true(s.handle_back(), "«назад» закрывает лист")
	assert_false(s.is_sheet_open())
	assert_eq(s.selected_route_id(), "mountains", "выбор остаётся")


func test_compact_start_from_sheet() -> void:
	var s := _screen(Vector2i(867, 400))
	await wait_process_frames(2)
	watch_signals(s)
	s.card_for("seaside").pressed.emit()
	s.start_button().pressed.emit()
	assert_signal_emitted_with_parameters(s, "start_requested", ["seaside", 50])
	assert_false(s.is_sheet_open())


func test_content_width_is_capped_on_wide_canvas() -> void:
	var s := _screen(Vector2i(1920, 720))
	await wait_process_frames(3)
	var body := s.get_node("%Body") as Control
	assert_lte(body.size.x, RouteSelectScreen.CONTENT_MAX_WIDTH + 0.5)
	assert_almost_eq(body.get_global_rect().get_center().x, 960.0, 1.0, "по центру")


func test_no_element_outside_canvas() -> void:
	for canvas in [Vector2i(1280, 720), Vector2i(1280, 960), Vector2i(867, 400)]:
		var s := _screen(canvas)
		await wait_process_frames(3)
		var bounds := Rect2(Vector2.ZERO, Vector2(canvas))
		for node in [s.app_bar(), s.get_node("%Body")]:
			var r: Rect2 = (node as Control).get_global_rect()
			assert_true(bounds.grow(0.5).encloses(r), "%s внутри %s (%s)" % [node.name, canvas, r])


# --- UIX-05 крит. 1, 5: цели нажатия и обход фокуса --------------------------------------------

func test_touch_targets_and_focusable_controls() -> void:
	var s := _screen()
	await wait_process_frames(2)
	var focusable: Array[Control] = []
	_collect_focusable(s, focusable)
	assert_true(focusable.has(s.steepness_slider()))
	assert_true(focusable.has(s.start_button()))
	for card in s.cards():
		assert_true(focusable.has(card))
	for c in focusable:
		if not c.is_visible_in_tree():
			continue
		assert_gte(c.size.x, UiScale.TOUCH_UI_DESKTOP - 0.01, "%s ширина" % c.name)
		assert_gte(c.size.y, UiScale.TOUCH_UI_DESKTOP - 0.01, "%s высота" % c.name)
	assert_gte(s.start_button().size.y, TouchTarget.BUTTON_MIN_HEIGHT - 0.01)


func _collect_focusable(node: Node, out: Array[Control]) -> void:
	var c := node as Control
	if c != null and c.focus_mode != Control.FOCUS_NONE:
		out.append(c)
	for child in node.get_children():
		_collect_focusable(child, out)


# --- UIX-01 крит. 3: без локальных переопределений темы ----------------------------------------

func test_scene_has_no_theme_overrides() -> void:
	var text := FileAccess.get_file_as_string(SCENE_FILE)
	assert_eq(text.find("theme_override_"), -1)
	var script_text := FileAccess.get_file_as_string("res://src/ui/tracks/route_select_screen.gd")
	assert_eq(script_text.find("add_theme_"), -1)
