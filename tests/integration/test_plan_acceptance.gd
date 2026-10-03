extends GutTest
## Приёмка T-040 «Экран выбора тренировки и предпросмотра» (tester, независимо от test_plan_screen.gd).
## Критерии: REQ-INT-04 п.1–3, REQ-INT-05 п.1–3, REQ-IMP-03 п.2 (ручной; здесь — только
## автоматически проверяемая конфигурация диалога), REQ-IMP-05 п.1/3/4 (ошибка импорта на экране),
## связка «нет станка → эмулятор» (REQ-WRK-01 п.5 / T-040), строки UI через ключи `ui.plan.*`.
## Сеть — MockHttpTransport; события Intervals.icu строятся в тесте или берутся из tests/fixtures/intervals/.

const SCENE: String = "res://src/ui/plan/plan_screen.tscn"
const MAIN_SCENE: String = "res://src/app/main.tscn"
const SCRIPT_PATHS: Array[String] = ["res://src/ui/plan/plan_screen.gd", "res://src/ui/plan/workout_chart.gd"]
const STRINGS_CSV: String = "res://assets/i18n/strings.csv"
const INTERVALS_FIXTURES: String = "res://tests/fixtures/intervals/"
const WORKOUT_FIXTURES: String = "res://tests/fixtures/workouts/"
const TODAY: String = "2026-10-02"
const API_KEY: String = "acceptance-key-0000"

var _dir: String
var _repo: ProfileRepository
var _state: AppState
var _store: MemorySecureStore
var _http: MockHttpTransport
var _cache: PlanCache
var _library: WorkoutLibrary
var _profile: Profile
var _locale_before: String


func before_each() -> void:
	_locale_before = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_dir = "user://test_plan_acc_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	_repo = ProfileRepository.new(_dir + "profiles/")
	_profile = _repo.create("Acceptance")
	_profile.ftp_w = 200
	_profile.intervals_athlete_id = "i777"
	_repo.save(_profile)
	_state = AppState.new(_repo)
	_state.start()
	_store = MemorySecureStore.new()
	_http = MockHttpTransport.new()
	_cache = PlanCache.new(_dir + "plans/")
	_library = WorkoutLibrary.new(_dir + "workouts/")


func after_each() -> void:
	TranslationServer.set_locale(_locale_before)
	_rm_rf(ProjectSettings.globalize_path(_dir))


static func _rm_rf(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub in d.get_directories():
		_rm_rf(path.path_join(sub))
	DirAccess.remove_absolute(path)


# ---------------------------------------------------------------------------
# Помощники
# ---------------------------------------------------------------------------

func _give_key(store: SecureStore, profile: Profile) -> void:
	var client := IntervalsIcuClient.for_profile(_http, store, profile)
	store.set_secret(client.secret_key(), API_KEY)


static func _event(id: int, event_name: String, description: String, load: int = -1) -> Dictionary:
	var e := {
		"id": id, "start_date_local": TODAY + "T00:00:00", "category": "WORKOUT", "type": "Ride",
		"name": event_name, "description": description,
	}
	if load >= 0:
		e["icu_training_load"] = load
	return e


func _fixture_events(file: String) -> Variant:
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(INTERVALS_FIXTURES + file)), OK)
	return json.data


func _screen() -> PlanScreen:
	var s: PlanScreen = load(SCENE).instantiate()
	s.today = TODAY
	s.setup(_state, _repo, _store, _http, _cache, _library)
	add_child_autofree(s)
	return s


func _screen_with_events(events: Array) -> PlanScreen:
	_give_key(_store, _profile)
	_http.enqueue_json("GET", "/events", 200, events)
	var s := _screen()
	return s


func _write_file(rel: String, text: String) -> String:
	var path := _dir + rel
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return path


static func _zwo(workout_name: String, body: String) -> String:
	return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<workout_file>\n<name>%s</name>\n<sportType>bike</sportType>\n<workout>\n%s\n</workout>\n</workout_file>\n" % [workout_name, body]


func _list(s: PlanScreen) -> ItemList:
	return s.get_node("%WorkoutList") as ItemList


func _start_button(s: PlanScreen) -> Button:
	return s.get_node("%StartButton") as Button


func _index_by_name(s: PlanScreen, item_name: String) -> int:
	var all := s.items()
	for i in all.size():
		if str(all[i]["name"]) == item_name:
			return i
	return -1


static func _has_cyrillic(text: String) -> bool:
	for i in text.length():
		var c := text.unicode_at(i)
		if c >= 0x0400 and c <= 0x04FF:
			return true
	return false


func _main() -> AppMain:
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir  # тот же каталог, где создан активный профиль
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = _http
	add_child_autofree(main)
	return main


## Таблица переводов: ключ → {ru, en}.
func _strings() -> Dictionary:
	var out := {}
	var f := FileAccess.open(STRINGS_CSV, FileAccess.READ)
	assert_not_null(f, "strings.csv читается")
	if f == null:
		return out
	var header := f.get_csv_line()
	var ru_col := header.find("ru")
	var en_col := header.find("en")
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() <= maxi(ru_col, en_col) or row[0].is_empty():
			continue
		out[row[0]] = {"ru": row[ru_col], "en": row[en_col]}
	f.close()
	return out


# ---------------------------------------------------------------------------
# REQ-INT-04 п.1 — одна тренировка на сегодня предлагается к запуску без выбора
# ---------------------------------------------------------------------------

func test_req_int_04_c1_single_today_workout_is_offered_and_start_launches_it() -> void:
	var s := _screen_with_events([_event(3001, "Solo Steps", "- 10m 50%\n- 5m 100%", 30)])
	var chosen: Array = []
	s.workout_chosen.connect(func(w: Workout, src: String) -> void: chosen.append([w, src]))
	var r: ApiResult = await s.load_today()
	assert_true(r.ok, "план загружен")
	assert_eq(s.intervals_items().size(), 1)
	assert_not_null(s.selected_workout(), "единственная тренировка выбрана без действия пользователя")
	assert_eq(s.preview_name_text(), "Solo Steps", "предпросмотр показан сразу")
	assert_false(_start_button(s).disabled, "«Начать» доступна без выбора из списка")
	_start_button(s).pressed.emit()
	assert_eq(chosen.size(), 1, "нажатие «Начать» запускает тренировку")
	if chosen.size() == 1:
		assert_eq((chosen[0][0] as Workout).name, "Solo Steps")
		assert_eq((chosen[0][0] as Workout).total_duration_sec(), 900)
		assert_eq(chosen[0][1], PlanScreen.SOURCE_INTERVALS)


func test_req_int_04_c1_single_today_workout_preselected_even_with_library_entries() -> void:
	assert_true(_library.import_file(_profile.id, WORKOUT_FIXTURES + "simple.zwo").ok())
	assert_true(_library.import_file(_profile.id, WORKOUT_FIXTURES + "sweet_spot_text.mrc").ok())
	var s := _screen_with_events([_event(3002, "Only Today", "- 20m 65%")])
	await s.load_today()
	assert_eq(s.items().size(), 3, "1 из Intervals.icu + 2 из библиотеки")
	assert_eq(str(s.selected_item().get("name", "")), "Only Today", "единственная на сегодня предложена, библиотека не мешает")
	assert_eq(s.selected_item().get("source", ""), PlanScreen.SOURCE_INTERVALS)


func test_req_int_04_c1_single_cached_workout_preselected_on_open_offline() -> void:
	var first := _screen_with_events([_event(3003, "Cached Solo", "- 15m 70%")])
	await first.load_today()
	_http.offline = true
	var second := _screen()
	assert_eq(second.intervals_items().size(), 1, "план из кэша при открытии")
	assert_not_null(second.selected_workout(), "единственная тренировка из кэша тоже предложена сразу")
	assert_false(_start_button(second).disabled)


# ---------------------------------------------------------------------------
# REQ-INT-04 п.2 — список: название, длительность мм:сс / ч:мм:сс, нагрузка; выбор → текущий план
# ---------------------------------------------------------------------------

func test_req_int_04_c2_list_shows_name_duration_and_load_when_present() -> void:
	var s := _screen_with_events([
		_event(3101, "Short Steps", "- 10m 50%\n- 5m 100%", 42),
		_event(3102, "Long Endurance", "- 70m 60%"),
	])
	await s.load_today()
	assert_eq(s.intervals_items().size(), 2)
	assert_null(s.selected_workout(), "при двух и более — без автоматического выбора")
	assert_true(_start_button(s).disabled, "до выбора «Начать» недоступна")
	var list := _list(s)
	var i_short := _index_by_name(s, "Short Steps")
	var i_long := _index_by_name(s, "Long Endurance")
	assert_true(i_short >= 0 and i_long >= 0)
	if i_short < 0 or i_long < 0:
		return
	var t_short := list.get_item_text(i_short)
	var t_long := list.get_item_text(i_long)
	gut.p("item texts: [%s] [%s]" % [t_short, t_long])
	assert_string_contains(t_short, "Short Steps")
	assert_string_contains(t_short, "15:00", "длительность мм:сс")
	assert_string_contains(t_short, "42", "целевая нагрузка из ответа")
	assert_string_contains(t_long, "Long Endurance")
	assert_string_contains(t_long, "1:10:00", "длительность ≥ 1 ч — ч:мм:сс")
	assert_false(t_long.contains("load"), "нагрузки нет в ответе — не показывается")


func test_req_int_04_c2_selecting_list_item_makes_it_current_plan() -> void:
	var s := _screen_with_events([
		_event(3201, "First", "- 10m 50%"),
		_event(3202, "Second", "- 20m 80%"),
	])
	var chosen: Array[Workout] = []
	s.workout_chosen.connect(func(w: Workout, _src: String) -> void: chosen.append(w))
	await s.load_today()
	var idx := _index_by_name(s, "Second")
	assert_true(idx >= 0)
	_list(s).item_selected.emit(idx)  # клик пользователя по строке
	assert_eq(s.selected_index(), idx)
	assert_eq(s.preview_name_text(), "Second", "предпросмотр выбранной")
	assert_false(_start_button(s).disabled)
	_start_button(s).pressed.emit()
	assert_eq(chosen.size(), 1)
	if chosen.size() == 1:
		assert_eq(chosen[0].name, "Second", "запускается именно выбранная")
		assert_eq(chosen[0].total_duration_sec(), 1200)
	# Переключение выбора меняет текущий план.
	var first := _index_by_name(s, "First")
	_list(s).item_selected.emit(first)
	_start_button(s).pressed.emit()
	assert_eq(chosen.size(), 2)
	if chosen.size() == 2:
		assert_eq(chosen[1].name, "First")


# ---------------------------------------------------------------------------
# REQ-INT-04 п.3 — библиотека в общем списке с пометкой источника
# ---------------------------------------------------------------------------

func test_req_int_04_c3_library_items_listed_with_source_mark_and_startable() -> void:
	assert_true(_library.import_file(_profile.id, WORKOUT_FIXTURES + "simple.zwo").ok())
	var s := _screen_with_events([_event(3301, "Today A", "- 10m 50%"), _event(3302, "Today B", "- 10m 60%")])
	await s.load_today()
	assert_eq(s.items().size(), 3, "Intervals.icu и библиотека в одном списке")
	var lib_idx := _index_by_name(s, "Simple Endurance")
	assert_true(lib_idx >= 0)
	if lib_idx < 0:
		return
	var text_en := _list(s).get_item_text(lib_idx)
	assert_string_contains(text_en, "library", "пометка источника (en)")
	assert_false(text_en.contains("Intervals.icu"), "библиотечная запись не помечена как Intervals.icu")
	var icu_text := _list(s).get_item_text(_index_by_name(s, "Today A"))
	assert_false(icu_text.contains("library"), "запись Intervals.icu не помечена как библиотека")
	var chosen: Array = []
	s.workout_chosen.connect(func(w: Workout, src: String) -> void: chosen.append([w, src]))
	_list(s).item_selected.emit(lib_idx)
	_start_button(s).pressed.emit()
	assert_eq(chosen.size(), 1)
	if chosen.size() == 1:
		assert_eq((chosen[0][0] as Workout).name, "Simple Endurance")
		assert_eq(chosen[0][1], PlanScreen.SOURCE_LIBRARY)


func test_req_int_04_c3_library_source_mark_in_russian() -> void:
	assert_true(_library.import_file(_profile.id, WORKOUT_FIXTURES + "simple.zwo").ok())
	TranslationServer.set_locale("ru")
	var s := _screen()
	assert_eq(s.library_items().size(), 1)
	var text_ru := _list(s).get_item_text(0)
	gut.p("ru item: " + text_ru)
	assert_string_contains(text_ru, "библиотек", "пометка источника (ru)")


# ---------------------------------------------------------------------------
# Граничные: пустой план, ошибка сети, кэш
# ---------------------------------------------------------------------------

func test_edge_empty_plan_today_nothing_selected_library_still_available() -> void:
	assert_true(_library.import_file(_profile.id, WORKOUT_FIXTURES + "simple.zwo").ok())
	var s := _screen_with_events(_fixture_events("events_empty.json"))
	var r: ApiResult = await s.load_today()
	assert_true(r.ok)
	assert_eq(s.status_text(), "No workout today")
	assert_eq(s.intervals_items().size(), 0)
	assert_null(s.selected_workout(), "пустой план — ничего не выбрано")
	assert_true(_start_button(s).disabled, "«Начать» недоступна без выбора")
	assert_eq(s.preview_name_text(), "Select a workout")
	assert_eq(s.preview_points().size(), 0, "пустой график")
	assert_eq(s.library_items().size(), 1, "библиотека доступна при пустом плане")
	s.select_index(0)
	assert_false(_start_button(s).disabled)


func test_edge_network_error_without_cache_keeps_library_runnable() -> void:
	assert_true(_library.import_file(_profile.id, WORKOUT_FIXTURES + "sweet_spot_text.mrc").ok())
	_give_key(_store, _profile)
	_http.offline = true
	var s := _screen()
	var r: ApiResult = await s.load_today()
	assert_false(r.ok)
	assert_eq(s.status_text(), "Network unavailable; no cached plan for today")
	assert_eq(s.intervals_items().size(), 0)
	assert_eq(s.library_items().size(), 1, "без сети тренировки из библиотеки доступны")
	s.select_index(0)
	assert_not_null(s.selected_workout())
	assert_true(s.start_selected())


func test_edge_server_5xx_uses_cache_with_mark() -> void:
	var s := _screen_with_events([_event(3401, "Cache A", "- 10m 50%"), _event(3402, "Cache B", "- 10m 60%")])
	await s.load_today()
	_http.enqueue_json("GET", "/events", 503, {})
	var r: ApiResult = await s.load_today()
	assert_true(r.ok and r.from_cache, "5xx → кэш на сегодня")
	assert_string_contains(s.status_text(), "from cache")
	assert_eq(s.intervals_items().size(), 2)


func test_edge_cache_of_other_date_not_offered_as_today() -> void:
	var s := _screen_with_events([_event(3501, "Yesterday", "- 10m 50%")])
	await s.load_today()
	_http.offline = true
	var next: PlanScreen = load(SCENE).instantiate()
	next.today = "2026-10-03"
	next.setup(_state, _repo, _store, _http, _cache, _library)
	add_child_autofree(next)
	await next.load_today()
	assert_eq(next.intervals_items().size(), 0, "кэш другой даты не предлагается")
	assert_null(next.selected_workout())


# ---------------------------------------------------------------------------
# REQ-INT-05 п.1 — точки (t, Вт) предпросмотра
# ---------------------------------------------------------------------------

func test_req_int_05_c1_preview_points_steps_10m50_5m100_ftp200() -> void:
	var s := _screen_with_events([_event(3601, "Steps", "- 10m 50%\n- 5m 100%")])
	await s.load_today()
	var pts := s.preview_points()
	gut.p("points: " + str(pts))
	var expected := PackedVector2Array([Vector2(0, 100), Vector2(600, 100), Vector2(600, 200), Vector2(900, 200)])
	assert_eq(pts, expected, "100 Вт на [0; 600), 200 Вт на [600; 900)")
	assert_eq(s.chart().total_sec(), 900)


func test_req_int_05_c1_preview_uses_profile_ftp() -> void:
	_profile.ftp_w = 250
	_repo.save(_profile)
	var s := _screen_with_events([_event(3602, "Steps", "- 10m 50%\n- 5m 100%")])
	await s.load_today()
	var pts := s.preview_points()
	assert_eq(pts.size(), 4)
	if pts.size() == 4:
		assert_eq(pts[0], Vector2(0, 125), "50 % от FTP профиля 250")
		assert_eq(pts[3], Vector2(900, 250))
	assert_string_contains(s.preview_duration_text(), "250")


# ---------------------------------------------------------------------------
# REQ-INT-05 п.2 — рампа: линейный участок от цели начала до цели конца
# ---------------------------------------------------------------------------

func test_req_int_05_c2_ramp_from_imported_zwo_start_and_end_points() -> void:
	var path := _write_file("files/ramp.zwo", _zwo("Ramp Only",
			"<Ramp Duration=\"600\" PowerLow=\"0.50\" PowerHigh=\"1.00\"/>\n<SteadyState Duration=\"300\" Power=\"0.75\"/>"))
	var s := _screen()
	var r := s.import_path(path)
	assert_true(r != null and r.ok(), "ZWO с рампой импортирован")
	assert_eq(str(s.selected_item().get("name", "")), "Ramp Only")
	var pts := s.preview_points()
	gut.p("ramp points: " + str(pts))
	assert_eq(pts.size(), 4)
	if pts.size() == 4:
		assert_eq(pts[0], Vector2(0, 100), "начало рампы = 50 % FTP")
		assert_eq(pts[1], Vector2(600, 200), "конец рампы = 100 % FTP")
		assert_eq(pts[2], Vector2(600, 150))
		assert_eq(pts[3], Vector2(900, 150))
	var seg: Dictionary = s.chart().segments()[0]
	assert_eq(int(seg["start_watts"]), 100)
	assert_eq(int(seg["end_watts"]), 200, "сегмент рампы рисуется трапецией начало→конец")


func test_req_int_05_c2_warmup_and_cooldown_ramps_of_fixture() -> void:
	var s := _screen()
	assert_true(s.import_path(WORKOUT_FIXTURES + "simple.zwo").ok())
	var pts := s.preview_points()
	assert_eq(pts.size(), 8)
	if pts.size() == 8:
		assert_eq(pts[0], Vector2(0, 80), "Warmup 40 %")
		assert_eq(pts[1], Vector2(300, 130), "→ 65 %")
		assert_eq(pts[6], Vector2(1620, 110), "Cooldown 55 %")
		assert_eq(pts[7], Vector2(1800, 70), "→ 35 %")


# ---------------------------------------------------------------------------
# REQ-INT-05 п.3 — цвет сегмента по зоне мощности цели
# ---------------------------------------------------------------------------

func test_req_int_05_c3_segment_colors_follow_default_zones() -> void:
	var s := _screen_with_events([_event(3701, "Zones", "- 1m 50%\n- 1m 65%\n- 1m 80%\n- 1m 100%\n- 1m 110%\n- 1m 130%\n- 1m 160%")])
	await s.load_today()
	var segs := s.chart().segments()
	assert_eq(segs.size(), 7)
	var names := ["gray", "blue", "green", "yellow", "orange", "red", "purple"]
	for i in mini(segs.size(), 7):
		assert_eq(int(segs[i]["zone"]), i + 1, "шаг %d → Z%d" % [i, i + 1])
		assert_eq(WorkoutChart.segment_color(segs[i]), ZonePalette.COLORS[names[i]], "Z%d — %s" % [i + 1, names[i]])


func test_req_int_05_c3_segment_colors_follow_profile_custom_zones() -> void:
	# PRF-02/HUD-03 п.1: зона — по зонам профиля. Пользовательские границы: Z1 ≤ 70 %.
	var bounds: Array[float] = [70.0, 85.0, 95.0, 110.0, 125.0, 155.0]
	_profile.set_power_zones_local(PowerZones.custom(200, bounds))
	_repo.save(_profile)
	var saved := _repo.get_by_id(_profile.id)
	assert_eq(saved.power_zone_of(130), 1, "предусловие: 130 Вт (65 %) — Z1 по зонам профиля")
	var s := _screen_with_events([_event(3702, "Custom Zones", "- 5m 65%\n- 5m 100%")])
	await s.load_today()
	var segs := s.chart().segments()
	assert_eq(segs.size(), 2)
	for seg in segs:
		var w := int(seg["start_watts"])
		var expected_zone := saved.power_zone_of(w)
		gut.p("seg %d W: chart zone %d, profile zone %d" % [w, int(seg["zone"]), expected_zone])
		assert_eq(WorkoutChart.segment_color(seg), ZonePalette.color(ZonePalette.power_token(expected_zone)),
				"%d Вт окрашен по зоне профиля Z%d" % [w, expected_zone])


# ---------------------------------------------------------------------------
# REQ-IMP-03 п.2 (ручной) — конфигурация диалога импорта, проверяемая автоматически
# ---------------------------------------------------------------------------

func test_req_imp_03_c2_import_button_opens_file_dialog_with_three_filters() -> void:
	var s := _screen()
	var dialog: FileDialog = s.get_node("%ImportDialog")
	assert_eq(dialog.file_mode, FileDialog.FILE_MODE_OPEN_FILE, "один файл на открытие")
	var patterns: Array[String] = []
	for f in dialog.filters:
		for p in f.split(";")[0].split(","):
			patterns.append(p.strip_edges().to_lower())
	patterns.sort()
	assert_eq(patterns, ["*.erg", "*.mrc", "*.zwo"] as Array[String], "фильтры ровно *.zwo, *.erg, *.mrc")
	(s.get_node("%ImportButton") as Button).pressed.emit()
	assert_true(dialog.visible, "кнопка «Импортировать файл…» открывает диалог")
	dialog.hide()


func test_req_imp_03_c2_selected_file_from_dialog_is_imported_case_insensitive() -> void:
	var src := FileAccess.get_file_as_string(WORKOUT_FIXTURES + "sweet_spot_text.mrc")
	var path := _write_file("files/SWEET.MRC", src)
	var s := _screen()
	var dialog: FileDialog = s.get_node("%ImportDialog")
	dialog.file_selected.emit(path)  # пользователь выбрал файл в диалоге
	assert_eq(_library.count(_profile.id), 1, ".MRC в верхнем регистре импортирован")
	assert_eq(s.library_items().size(), 1)
	assert_not_null(s.selected_workout())


# ---------------------------------------------------------------------------
# REQ-IMP-05 — понятная ошибка импорта на экране
# ---------------------------------------------------------------------------

func test_req_imp_05_unsupported_extension_shows_error_with_file_name() -> void:
	var path := _write_file("files/ride.fit", "not a workout")
	var s := _screen()
	var r := s.import_path(path)
	assert_not_null(r)
	if r == null:
		return
	assert_false(r.ok())
	var dialog: AcceptDialog = s.get_node("%ImportErrorDialog")
	assert_true(dialog.visible, "ошибка показана диалогом")
	var msg := s.import_error_text()
	gut.p("error (en): " + msg)
	assert_string_contains(msg, "ride.fit", "имя файла в сообщении")
	assert_false(msg.contains("user://") or msg.contains("res://"), "без внутренних путей")
	assert_false(msg.contains("ParseResult") or msg.contains("WorkoutLibrary") or msg.contains(".gd"), "без имён классов")
	assert_eq(_library.count(_profile.id), 0, "ничего не импортировано")
	assert_eq(get_errors().size(), 0, "ни одной ошибки движка (IMP-05 п.4)")


func test_req_imp_05_c1_error_message_in_interface_language_en() -> void:
	var s := _screen()
	var r := s.import_path(WORKOUT_FIXTURES + "unknown_element.zwo")
	assert_false(r.ok())
	var msg := s.import_error_text()
	gut.p("error (en): " + msg)
	assert_string_contains(msg, "unknown_element.zwo")
	assert_string_contains(msg, "SolidState", "имя элемента")
	assert_string_contains(msg, "6", "номер строки")
	assert_false(_has_cyrillic(msg), "интерфейс на английском — сообщение без кириллицы (тип проблемы на языке интерфейса)")


func test_req_imp_05_c1_error_message_in_interface_language_ru() -> void:
	TranslationServer.set_locale("ru")
	var s := _screen()
	s.import_path(WORKOUT_FIXTURES + "unknown_element.zwo")
	var msg := s.import_error_text()
	gut.p("error (ru): " + msg)
	assert_string_contains(msg, "unknown_element.zwo")
	assert_string_contains(msg, "SolidState")
	assert_true(_has_cyrillic(msg), "сообщение на русском")


# ---------------------------------------------------------------------------
# Импорт: выбирается именно импортированная запись
# ---------------------------------------------------------------------------

func test_edge_import_same_name_different_content_selects_new_entry() -> void:
	var a := _write_file("a/plan.zwo", _zwo("Same Name", "<SteadyState Duration=\"600\" Power=\"0.50\"/>"))
	var b := _write_file("b/plan.zwo", _zwo("Same Name", "<SteadyState Duration=\"900\" Power=\"0.90\"/>"))
	var s := _screen()
	assert_true(s.import_path(a).ok())
	await wait_seconds(1.1)  # разные imported_at — порядок в библиотеке детерминирован
	var rb := s.import_path(b)
	assert_true(rb.ok())
	assert_eq(_library.count(_profile.id), 2, "IMP-04 п.4: другое содержимое — отдельная запись")
	var sel := s.selected_workout()
	assert_not_null(sel)
	if sel != null:
		assert_eq(sel.total_duration_sec(), 900, "после импорта выбран и показан только что импортированный план")
	assert_eq(str(s.selected_item().get("id", "")), str(rb.metadata.get("entry_id", "")), "выбрана запись с id импорта")


# ---------------------------------------------------------------------------
# Старт без станка → эмулятор (T-040, REQ-WRK-01 п.5); со станком — без вопроса
# ---------------------------------------------------------------------------

func test_trainer_start_without_trainer_offers_emulator_and_runs_on_fake_trainer() -> void:
	var main := _main()
	assert_true(main.app_state.navigate(AppState.Screen.PLAN))
	var plan := main.plan_screen()
	assert_true(plan.import_path(WORKOUT_FIXTURES + "simple.zwo").ok())
	assert_false(main.is_trainer_ready())
	(plan.get_node("%StartButton") as Button).pressed.emit()
	var dialog: ConfirmationDialog = plan.get_node("%TrainerDialog")
	assert_true(dialog.visible, "показан выбор: эмулятор / подключить устройства")
	assert_eq(dialog.dialog_text, tr("ui.plan.trainer_choice.text"))
	assert_eq(main.app_state.current_screen, AppState.Screen.PLAN, "до выбора тренировка не стартует")
	var has_emulator_button := false
	for child in dialog.find_children("*", "Button", true, false):
		if child is Button and (child as Button).text == tr("ui.plan.trainer_choice.emulator"):
			has_emulator_button = true
	assert_true(has_emulator_button, "кнопка «Эмулятор» в диалоге")
	dialog.custom_action.emit(&"emulator")
	assert_eq(main.app_state.current_screen, AppState.Screen.WORKOUT)
	var ws := main.workout_screen()
	assert_not_null(ws.session())
	if ws.session() == null:
		return
	assert_true(ws.session().trainer is FakeTrainer, "сессия на эмуляторе станка")
	assert_eq(ws.session().executor.workout.name, "Simple Endurance")
	for i in 5:
		ws.session().tick(1.0)
	assert_eq(ws.session().get_state(), WorkoutSession.State.RUNNING, "эмулятор ведёт тренировку")
	ws.confirm_stop()


func test_trainer_start_with_connected_trainer_runs_without_emulator_prompt() -> void:
	var main := _main()
	main.connections.trainer.set("connect_delay_sec", 0.0)
	main.connections.connect_trainer("neo-1")
	assert_true(main.is_trainer_ready(), "предусловие: станок подключён")
	main.app_state.navigate(AppState.Screen.PLAN)
	var plan := main.plan_screen()
	assert_true(plan.import_path(WORKOUT_FIXTURES + "simple.zwo").ok())
	(plan.get_node("%StartButton") as Button).pressed.emit()
	assert_false(plan.is_trainer_choice_pending(), "станок есть — эмулятор не предлагается")
	assert_false((plan.get_node("%TrainerDialog") as ConfirmationDialog).visible)
	assert_eq(main.app_state.current_screen, AppState.Screen.WORKOUT)
	var ws := main.workout_screen()
	if ws.session() != null:
		assert_true(ws.session().trainer == main.connections.hub, "сессия на подключённом станке (хаб)")
		ws.confirm_stop()


# ---------------------------------------------------------------------------
# Строки UI — через ключи ui.plan.* в strings.csv
# ---------------------------------------------------------------------------

func test_i18n_all_tr_keys_and_scene_texts_exist_with_ru_and_en() -> void:
	var table := _strings()
	var used: Array[String] = []
	var rx := RegEx.create_from_string("tr\\(\"([^\"]+)\"\\)")
	for p in SCRIPT_PATHS:
		for m in rx.search_all(FileAccess.get_file_as_string(p)):
			used.append(m.get_string(1))
	var scene_rx := RegEx.create_from_string("(?m)^(?:text|title|ok_button_text|cancel_button_text|dialog_text) = \"([^\"]*)\"")
	for m in scene_rx.search_all(FileAccess.get_file_as_string(SCENE)):
		used.append(m.get_string(1))
	assert_true(used.size() > 20, "найдено ключей: %d" % used.size())
	for key in used:
		assert_true(key.begins_with("ui.plan.") or key.begins_with("ui.common."), "строка экрана — ключ ui.plan.*/ui.common.*: '%s'" % key)
		assert_true(table.has(key), "ключ есть в strings.csv: %s" % key)
		if table.has(key):
			assert_false(str(table[key]["ru"]).strip_edges().is_empty(), "ru не пуст: %s" % key)
			assert_false(str(table[key]["en"]).strip_edges().is_empty(), "en не пуст: %s" % key)


func test_i18n_no_cyrillic_literals_in_plan_screen_code() -> void:
	for p in SCRIPT_PATHS:
		var lines := FileAccess.get_file_as_string(p).split("\n")
		for i in lines.size():
			var code := lines[i].strip_edges()
			if code.begins_with("#"):
				continue
			var hash_pos := code.find(" #")
			if hash_pos >= 0:
				code = code.substr(0, hash_pos)
			assert_false(_has_cyrillic(code), "%s:%d — кириллица в литерале: %s" % [p.get_file(), i + 1, code])


func test_i18n_screen_renders_in_russian_without_english_keys_left() -> void:
	assert_true(_library.import_file(_profile.id, WORKOUT_FIXTURES + "simple.zwo").ok())
	TranslationServer.set_locale("ru")
	var s := _screen()
	s.select_index(0)
	assert_string_contains(s.preview_duration_text(), "Длительность")
	assert_string_contains(s.status_text(), "Ключ API", "статус без ключа — на русском")
	assert_false(s.preview_duration_text().contains("ui.plan"), "ключ переведён")
	assert_false(_list(s).get_item_text(0).contains("ui.plan"))
