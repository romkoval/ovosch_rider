extends GutTest
## Экран выбора тренировки карточками (T-082; `docs/game/ui.md` п. 8.3):
## REQ-UIX-03 крит. 1 (карточка: название, превью по модели HUD-10.1 с FTP профиля, длительность,
## шагов, макс. цель, источник; разделы и баннер без ключа; панель предпросмотра), крит. 3 (ровно
## одна «выбрано», запуск одним действием), крит. 4 (превью карточки и крупное превью — одна
## модель и один рисовальщик с HUD, на миниатюре нет факта, курсора и подписей);
## REQ-UIX-04 крит. 1 («назад» AppBar → `AppState.go_back()`); регрессия REQ-INT-04, INT-05.

const SCENE: String = "res://src/ui/plan/plan_screen.tscn"
const MAIN_SCENE: String = "res://src/app/main.tscn"
const ACC_FULL: String = "res://tests/fixtures/workouts_acceptance/acc_full.zwo"
const SIMPLE: String = "res://tests/fixtures/workouts/simple.zwo"
const SWEET_SPOT: String = "res://tests/fixtures/workouts/sweet_spot_text.mrc"
const FIXTURES: Array[String] = [ACC_FULL, SIMPLE, SWEET_SPOT]
const INTERVALS_FIXTURES: String = "res://tests/fixtures/intervals/"
const TODAY: String = "2026-10-02"
const KEY: String = "plan-cards-key-0001"
const FTP: int = 250
const PLAN_FILES: Array[String] = ["res://src/ui/plan/plan_screen.tscn", "res://src/ui/plan/plan_screen.gd"]

var _dir: String
var _repo: ProfileRepository
var _state: AppState
var _store: MemorySecureStore
var _mock: MockHttpTransport
var _cache: PlanCache
var _library: WorkoutLibrary
var _profile: Profile
var _locale: String
var _chosen: Array[Workout] = []


func before_each() -> void:
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_dir = "user://test_plan_cards_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_repo = ProfileRepository.new(_dir + "profiles/")
	_profile = _repo.create("Rider")
	_profile.ftp_w = FTP
	_profile.intervals_athlete_id = "i4242"
	_repo.save(_profile)
	_state = AppState.new(_repo)
	_state.start()
	_store = MemorySecureStore.new()
	_mock = MockHttpTransport.new()
	_cache = PlanCache.new(_dir + "plans/")
	_library = WorkoutLibrary.new(_dir + "workouts/")
	_chosen = []


func after_each() -> void:
	TranslationServer.set_locale(_locale)
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


func _screen() -> PlanScreen:
	var s: PlanScreen = load(SCENE).instantiate()
	s.today = TODAY
	s.setup(_state, _repo, _store, _mock, _cache, _library)
	add_child_autofree(s)
	return s


## Экран с тремя тренировками разной структуры в библиотеке (рампы и FreeRide, ступени, MRC).
func _screen_with_library() -> PlanScreen:
	for f in FIXTURES:
		assert_true(_library.import_file(_profile.id, f).ok(), "импорт %s" % f.get_file())
	return _screen()


func _with_key() -> void:
	var client := IntervalsIcuClient.for_profile(_mock, _store, _profile)
	_store.set_secret(client.secret_key(), KEY)


func _events() -> Array:
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(INTERVALS_FIXTURES + "events_today.json")), OK)
	return json.data


func _index_of(s: PlanScreen, workout_name: String) -> int:
	var all := s.items()
	for i in all.size():
		if str(all[i]["name"]) == workout_name:
			return i
	return -1


func _thumb(card: ListRow) -> PlanPreview:
	for child in card.leading_slot().get_children():
		if child is PlanPreview:
			return child
	return null


func _on_chosen(w: Workout, _source: String) -> void:
	_chosen.append(w)


## Независимый расчёт ключевых цифр: длительность мм:сс / ч:мм:сс, число шагов, наибольшая цель
## ненулевых (не «свободно») шагов по `Workout.segments()` с FTP профиля.
func _expected_numbers(w: Workout, steps_word: String, max_word: String) -> String:
	var top := 0
	var segs := w.segments(FTP, 1.0, _profile.effective_power_zones())
	for seg in segs:
		if w.steps[int(seg["index"])].is_free_ride():
			continue
		top = maxi(top, maxi(int(seg["start_watts"]), int(seg["end_watts"])))
	var total := w.total_duration_sec()
	var duration := "%02d:%02d" % [total / 60, total % 60] if total < 3600 else "%d:%02d:%02d" % [total / 3600, (total % 3600) / 60, total % 60]
	return "%s · %d %s · %s" % [duration, w.steps.size(), steps_word, max_word % top]


# ---------------------------------------------------------------------------
# REQ-UIX-03 крит. 1 — карточка: название, цифры, источник, разделы
# ---------------------------------------------------------------------------

func test_card_numbers_follow_fixture_plan_en() -> void:
	var s := _screen_with_library()
	assert_eq(s.cards().size(), 3, "три карточки — по одной на тренировку")
	var i := _index_of(s, "Acceptance Full")
	assert_true(i >= 0)
	if i < 0:
		return
	var card := s.cards()[i]
	assert_eq(card.title, "Acceptance Full")
	assert_eq(card.subtitle, "38:00 · 12 steps · max 300 W", "длительность · шагов · макс. цель при FTP 250")


func test_card_numbers_follow_fixture_plan_ru() -> void:
	TranslationServer.set_locale("ru")
	var s := _screen_with_library()
	var i := _index_of(s, "Acceptance Full")
	assert_true(i >= 0)
	if i < 0:
		return
	assert_eq(s.cards()[i].subtitle, "38:00 · 12 шагов · макс. 300 Вт")


func test_card_numbers_match_independent_calculation_for_three_structures() -> void:
	var s := _screen_with_library()
	for i in s.items().size():
		var w: Workout = s.items()[i]["workout"]
		assert_not_null(w)
		if w == null:
			continue
		var words := "step" if w.steps.size() == 1 else "steps"
		assert_eq(s.cards()[i].subtitle, _expected_numbers(w, words, "max %d W"), "цифры карточки «%s»" % w.name)


func test_card_shows_source_and_sections_split_today_and_library() -> void:
	_with_key()
	_mock.enqueue_json("GET", "/events", 200, _events())
	assert_true(_library.import_file(_profile.id, SIMPLE).ok())
	var s := _screen()
	await s.load_today()
	var today_box: VBoxContainer = s.get_node("%TodayCards")
	var library_box: VBoxContainer = s.get_node("%LibraryCards")
	assert_eq(today_box.get_child_count(), s.intervals_items().size(), "раздел «Сегодня в Intervals.icu»")
	assert_eq(library_box.get_child_count(), s.library_items().size(), "раздел «Библиотека»")
	for i in s.items().size():
		var card := s.cards()[i]
		var source := card.trailing_slot().get_node("Source") as Label
		var expected := "library" if s.items()[i]["source"] == PlanScreen.SOURCE_LIBRARY else "Intervals.icu"
		assert_eq(source.text, expected, "значок источника карточки %d" % i)
		assert_eq(card.get_parent(), today_box if s.items()[i]["source"] == PlanScreen.SOURCE_INTERVALS else library_box)
	assert_false(s.key_banner().visible, "ключ задан — баннера нет")
	assert_eq((s.get_node("%TodayHeader") as Label).text, "Today in Intervals.icu")


func test_without_key_banner_with_set_key_action() -> void:
	var s := _screen()
	await s.load_today()
	var banner := s.key_banner()
	assert_true(banner.visible, "без ключа — баннер в разделе Intervals.icu")
	assert_eq(banner.text_label().text, "Connect Intervals.icu to see today's plan")
	assert_eq(banner.action_button().text, "Add key")
	assert_eq(s.status_text(), "Intervals.icu API key is not set", "строка статуса сохраняется")
	banner.action_button().pressed.emit()
	assert_true(s.is_key_form_open(), "«Указать ключ» открывает форму ключа")
	s.close_key_form()


func test_rejected_key_shows_warning_banner() -> void:
	_with_key()
	_mock.enqueue_json("GET", "/events", 401, {})
	var s := _screen()
	await s.load_today()
	assert_true(s.key_banner().visible)
	assert_eq(s.key_banner().kind, Banner.Kind.WARN)
	assert_eq(s.key_banner().action_button().text, "Add key")


func test_unparsed_event_card_is_disabled_with_reason() -> void:
	_with_key()
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string("res://tests/fixtures/workouts/intervals_event_unsupported.json")), OK)
	var ev: Dictionary = json.data
	ev["id"] = 7001
	ev["name"] = "Broken plan"
	ev["category"] = "WORKOUT"
	ev["type"] = "Ride"
	ev["start_date_local"] = TODAY + "T00:00:00"
	_mock.enqueue_json("GET", "/events", 200, [ev])
	var s := _screen()
	await s.load_today()
	assert_eq(s.cards().size(), 1)
	var card := s.cards()[0]
	assert_true(card.disabled, "неразобранный план нельзя выбрать")
	assert_false(card.tooltip_text.is_empty(), "причина — в подсказке")
	assert_eq(card.subtitle, "could not be parsed")
	assert_null(s.selected_workout())


func test_empty_library_shows_empty_state_with_import_action() -> void:
	var s := _screen()
	var empty := s.library_empty_state()
	assert_true(empty.visible, "пустая библиотека — пустое состояние")
	assert_eq(empty.title_label().text, "The library is empty")
	assert_eq(empty.action_button().text, "Import file")
	empty.action_button().pressed.emit()
	var dialog: FileDialog = s.get_node("%ImportDialog")
	assert_true(dialog.visible, "действие открывает диалог импорта")
	dialog.hide()
	assert_true(s.import_path(SIMPLE).ok())
	assert_false(empty.visible, "после импорта пустого состояния нет")


func test_preview_panel_shows_name_stats_and_zone_time() -> void:
	var s := _screen_with_library()
	var i := _index_of(s, "Acceptance Full")
	s.select_index(i)
	var w := s.selected_workout()
	assert_eq(s.preview_name_text(), "Acceptance Full")
	assert_eq(s.preview_stat_values(), ["38:00", str(w.steps.size()), "300"] as Array[String], "длительность, шагов, макс. цель")
	var captions := s.zone_caption_texts()
	assert_true(captions.size() >= 2, "время в зонах: %s" % str(captions))
	assert_true(captions.back().begins_with("free"), "«свободно» — последней (в acc_full есть FreeRide)")
	assert_string_contains(s.preview_duration_text(), "FTP 250")


# ---------------------------------------------------------------------------
# REQ-UIX-03 крит. 4 — один рисовальщик и одна модель (HUD-10.1)
# ---------------------------------------------------------------------------

func test_thumbnails_and_large_preview_use_hud_chart_and_plan_model() -> void:
	var s := _screen_with_library()
	var zones := _profile.effective_power_zones()
	for i in s.cards().size():
		var w: Workout = s.items()[i]["workout"]
		var thumb := _thumb(s.cards()[i])
		assert_not_null(thumb, "миниатюра в карточке %d" % i)
		if thumb == null:
			continue
		assert_true(thumb is HudChart, "миниатюра — рисовальщик HUD")
		assert_false(thumb.detailed)
		assert_false(thumb.show_fact or thumb.show_cursor or thumb.show_time_axis or thumb.show_ftp_label, "на миниатюре нет факта, курсора и подписей")
		var expected := PlanChartModel.new(w, FTP, 1.0, zones)
		assert_eq(thumb.plan_model().pieces(), expected.pieces(), "куски миниатюры = модель HUD-10.1 (%s)" % w.name)
		s.select_index(i)
		var chart := s.chart()
		assert_true(chart is PlanPreview and chart.detailed, "крупное превью — PlanPreview со шкалой и FTP")
		assert_eq(chart.plan_model().pieces(), expected.pieces(), "крупное превью — та же модель")


func test_three_structures_have_distinct_previews() -> void:
	var s := _screen_with_library()
	var seen: Array = []
	for card in s.cards():
		var pieces := _thumb(card).plan_model().pieces()
		assert_false(seen.has(pieces), "превью различимы между собой")
		seen.append(pieces)


func test_zone_shares_cover_plan_and_free_is_last() -> void:
	var s := _screen_with_library()
	assert_null(s.selected_workout(), "в библиотеке три записи — без автовыбора")
	s.select_index(_index_of(s, "Acceptance Full"))
	var model := s.chart().plan_model()
	var shares := PlanScreen.zone_shares(model)
	var total := 0.0
	for share in shares:
		total += float(share["sec"])
	assert_almost_eq(total, float(model.total_sec()), 0.01, "доли зон покрывают весь план")
	assert_true(bool(shares.back()["free"]), "FreeRide — последней долей")
	for k in range(1, shares.size() - 1):
		assert_true(int(shares[k]["zone"]) > int(shares[k - 1]["zone"]), "зоны по возрастанию")


# ---------------------------------------------------------------------------
# REQ-UIX-03 крит. 3 — ровно одна «выбрано», запуск одним действием
# ---------------------------------------------------------------------------

func test_exactly_one_card_selected_and_follows_selection() -> void:
	var s := _screen_with_library()
	assert_eq(s.selected_cards().size(), 0, "до выбора — ни одной")
	s.cards()[1].pressed.emit()
	assert_eq(s.selected_index(), 1, "нажатие на карточку выбирает тренировку")
	assert_eq(s.selected_cards(), [s.cards()[1]] as Array[ListRow], "ровно одна «выбрано»")
	s.cards()[2].pressed.emit()
	assert_eq(s.selected_cards(), [s.cards()[2]] as Array[ListRow], "выбор переходит на другую")
	s.cards()[2].pressed.emit()
	assert_eq(s.selected_cards(), [s.cards()[2]] as Array[ListRow], "повторное нажатие не снимает выбор")
	s.select_index(-1)
	assert_eq(s.selected_cards().size(), 0)


func test_selected_card_uses_card_variation_with_toggle() -> void:
	var s := _screen_with_library()
	for card in s.cards():
		assert_eq(card.theme_type_variation, &"CardButton", "карточка — вариация CardButton (рамка акцента у выбранной)")
		assert_true(card.toggle_mode)
		assert_ne(card.focus_mode, Control.FOCUS_NONE, "карточка достижима с клавиатуры")
		assert_true(card.custom_minimum_size.y >= UiScale.TOUCH_UI_DESKTOP, "цель нажатия ≥ touch_ui")


func test_start_launches_selected_card_workout() -> void:
	var s := _screen_with_library()
	s.workout_chosen.connect(_on_chosen)
	var i := _index_of(s, "Simple Endurance")
	s.cards()[i].pressed.emit()
	(s.get_node("%StartButton") as Button).pressed.emit()
	assert_eq(_chosen.size(), 1, "запуск одним действием")
	if _chosen.size() == 1:
		assert_eq(_chosen[0].name, "Simple Endurance", "запускается выбранная")


func test_single_today_workout_card_preselected() -> void:
	_with_key()
	_mock.enqueue_json("GET", "/events", 200, [_events()[0]])
	assert_true(_library.import_file(_profile.id, SIMPLE).ok())
	var s := _screen()
	await s.load_today()
	assert_eq(s.selected_cards().size(), 1, "REQ-INT-04 крит. 1: единственная на сегодня выбрана")
	assert_eq(s.selected_cards()[0], s.cards()[s.selected_index()])
	assert_false((s.get_node("%StartButton") as Button).disabled)


# ---------------------------------------------------------------------------
# AppBar и «назад» (REQ-UIX-04 крит. 1)
# ---------------------------------------------------------------------------

func test_app_bar_title_and_back_goes_back_in_stack() -> void:
	assert_true(_state.navigate(AppState.Screen.DEVICES))
	assert_true(_state.navigate(AppState.Screen.PLAN))
	var s := _screen()
	assert_eq(s.app_bar().title_text(), "Planned workout")
	assert_true(s.app_bar().show_back)
	s.app_bar().back_button().pressed.emit()
	assert_eq(_state.current_screen, AppState.Screen.DEVICES, "«назад» → предыдущий экран (go_back), а не HOME")


func test_import_and_reload_are_app_bar_actions() -> void:
	var s := _screen()
	var slot := s.app_bar().actions_slot()
	assert_eq((s.get_node("%ImportButton") as Button).get_parent(), slot, "«Импорт файла» в AppBar")
	assert_eq((s.get_node("%ReloadButton") as Button).get_parent(), slot, "«Обновить» в AppBar")
	assert_eq((s.get_node("%ImportButton") as Button).text, "Import file")
	assert_not_null((s.get_node("%ImportButton") as Button).icon, "иконка upload")


# ---------------------------------------------------------------------------
# Compact: предпросмотр листом снизу
# ---------------------------------------------------------------------------

func test_compact_layout_opens_preview_sheet_on_card_press() -> void:
	var root := get_tree().root
	var before := root.content_scale_factor
	root.content_scale_factor = 2.0
	var s := _screen_with_library()
	await get_tree().process_frame
	if not s.is_compact():
		root.content_scale_factor = before
		pending("холст тестового окна не уже 1100 lp — compact не проверяется (%s)" % str(s.get_viewport_rect().size))
		return
	assert_false((s.get_node("%PreviewSlot") as Control).visible, "compact: список во всю ширину")
	s.cards()[0].pressed.emit()
	assert_true(s.is_preview_sheet_open(), "нажатие на карточку открывает лист")
	var start := s.get_node("%StartButton") as Button
	assert_true(start.is_visible_in_tree(), "«Начать» видна в листе")
	assert_true(s.handle_back(), "«назад» закрывает лист")
	assert_false(s.is_preview_sheet_open())
	root.content_scale_factor = before
	await get_tree().process_frame
	assert_false(s.is_compact(), "обратно в regular")
	assert_true(start.is_visible_in_tree(), "«Начать» вернулась в панель предпросмотра")


# ---------------------------------------------------------------------------
# Строки и тема
# ---------------------------------------------------------------------------

func test_card_texts_follow_locale_change() -> void:
	var s := _screen_with_library()
	var i := _index_of(s, "Acceptance Full")
	TranslationServer.set_locale("ru")
	await get_tree().process_frame
	assert_eq(s.cards()[i].subtitle, "38:00 · 12 шагов · макс. 300 Вт")
	assert_eq(s.app_bar().title_text(), "Тренировка по плану")


func test_plural_forms_ru_and_en() -> void:
	var cases := {1: "one", 2: "few", 4: "few", 5: "many", 11: "many", 12: "many", 21: "one", 22: "few", 111: "many", 0: "many"}
	for n: int in cases:
		assert_eq(PlanScreen.plural_form(n, "ru"), cases[n], "ru %d" % n)
	assert_eq(PlanScreen.plural_form(1, "en"), "one")
	assert_eq(PlanScreen.plural_form(2, "en"), "many")


func test_plan_files_have_no_theme_overrides() -> void:
	for path in PLAN_FILES:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.contains("theme_override_"), "%s: без theme_override_*" % path)
		assert_false(text.contains("add_theme_"), "%s: без add_theme_*_override" % path)
