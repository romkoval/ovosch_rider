extends GutTest
## T-103 (`ui.md` п. 8.2, решение ред. 2; REQ-UIX-05 крит. 3): надзаголовок карточки главного
## рядом с текстовой кнопкой на узком телефоне делится на две строки по фактическому зазору до
## кнопки; короткое слово (≤ 2 букв) не остаётся последним в строке; на месте переноса « · » не
## рисуется. Ожидаемо для плана на телефоне 1280×590 с вырезом (ru): «ПО ПЛАНУ» / «ERG» (кадр
## `screen_home_1280x590_ru_safe_phone`).



func _overline_label() -> Label:
	var l := Label.new()
	l.theme_type_variation = &"OverlineAccent"
	l.uppercase = true
	add_child_autofree(l)
	return l


func _width(l: Label, text: String) -> float:
	return l.get_theme_font("font").get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1,
			l.get_theme_font_size("font_size")).x


func test_split_rules_short_word_and_separator() -> void:
	var l := _overline_label()
	var text := "по плану · ERG"
	var gap := _width(l, "по плану") + 4.0
	assert_eq(HomeScreen.split_to_fit(l, text, gap), "по плану\nERG", "перенос на « · »: разделитель не рисуется")
	assert_eq(HomeScreen.split_to_fit(l, text, _width(l, text) + 1.0), text, "помещается — как есть")
	var narrow := _width(l, "плану · ERG") + 1.0
	var two := HomeScreen.split_to_fit(l, "в плане сегодня", _width(l, "плане сегодня") + 1.0)
	assert_eq(two, "в плане\nсегодня", "«в» не остаётся последним словом строки")
	assert_false(HomeScreen.split_to_fit(l, text, narrow).begins_with("по\n"), "«ПО» одно в строке не остаётся")
	assert_eq(HomeScreen.split_to_fit(l, "свободная езда · SIM", _width(l, "свободная") + 1.0),
			"свободная\nезда · SIM", "езда: правилам не противоречит")


const MAIN_SCENE: String = "res://src/app/main.tscn"
const PLAN_FIXTURE: String = "res://tests/fixtures/workouts_acceptance/acc_full.zwo"
const SAFE_AREA_LP: Vector4 = Vector4(100.0, 0.0, 100.0, 13.0)


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


## Телефон 1280×590 с вырезом, ru: «ПО ПЛАНУ» / «ERG», строки не шире зазора до кнопки.
func test_phone_safe_area_ru_plan_overline_two_lines() -> void:
	var dir := "user://test_home_overline_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	var prev_locale := TranslationServer.get_locale()
	var runtime := get_tree().root.get_node_or_null(^"UiScaleRuntime") as UiScale
	var prev_device := runtime.device if runtime != null else UiScale.Device.DESKTOP
	var settings := AppSettings.load_from(dir + "settings.json")
	settings.locale = "ru"
	settings.save()
	ProfileRepository.new(dir + "profiles/").create("Даша")
	if runtime != null:
		runtime.device = UiScale.Device.PHONE
	Engine.set_meta(UiScale.DEBUG_SAFE_AREA_META, SAFE_AREA_LP)
	var viewport := SubViewport.new()
	viewport.gui_embed_subwindows = true
	viewport.size = Vector2i(Vector2(1280, 590) / UiScale.scale_for(UiScale.Device.PHONE, UiScale.Mode.MENU))
	add_child_autofree(viewport)
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	viewport.add_child(main)
	if runtime != null:
		runtime.set_mode(UiScale.Mode.MENU)
	main.app_state.select_profile(main.repo.list()[0].id)
	main.app_state.navigate(AppState.Screen.PLAN)
	assert_true(main.plan_screen().import_path(ProjectSettings.globalize_path(PLAN_FIXTURE)).ok())
	main.app_state.navigate(AppState.Screen.HOME)
	await wait_process_frames(8)
	var home := main.screen_node(AppState.Screen.HOME) as HomeScreen
	var label := home.get_node("%PlanOverline") as Label
	var button := home.get_node("%WorkoutButton") as Button
	assert_eq(button.get_parent(), label.get_parent(), "предусловие: кнопка рядом с надзаголовком")
	assert_eq(label.text.to_upper(), "ПО ПЛАНУ\nERG", "ожидаемо «ПО ПЛАНУ» / «ERG»")
	var header := label.get_parent() as Control
	var gap: float = header.size.x - float(header.get_theme_constant("separation")) - button.size.x
	for line in label.text.split("\n"):
		assert_lte(_width(label, line), gap + 0.5, "строка «%s» не шире зазора %.1f" % [line, gap])
	assert_eq(label.get_line_count(), 2, "движок не переносит строки сверх двух")
	Engine.remove_meta(UiScale.DEBUG_SAFE_AREA_META)
	if runtime != null:
		runtime.device = prev_device
		runtime.set_mode(UiScale.Mode.MENU)
	TranslationServer.set_locale(prev_locale)
	viewport.queue_free()
	await wait_process_frames(1)
	_remove_tree(ProjectSettings.globalize_path(dir))
