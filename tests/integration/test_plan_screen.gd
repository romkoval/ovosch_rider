extends GutTest
## Интеграционные тесты экрана выбора тренировки PlanScreen (REQ-INT-04 крит. 1–3, REQ-INT-05 крит. 1–4,
## REQ-INT-07 крит. 2–5, REQ-IMP-03 крит. 1, 2 (хук), REQ-IMP-04 крит. 1, 3, REQ-IMP-05 крит. 1, 3, REQ-NFR-03 крит. 1, 2).
## Сеть — MockHttpTransport с фикстурами tests/fixtures/intervals/, кэш и библиотека — временные каталоги.

const SCENE: String = "res://src/ui/plan/plan_screen.tscn"
const MAIN_SCENE: String = "res://src/app/main.tscn"
const FIXTURES: String = "res://tests/fixtures/intervals/"
const WORKOUT_FIXTURES: String = "res://tests/fixtures/workouts/"
const TODAY: String = "2026-10-02"
const KEY: String = "fixture-api-key-9f8e7d6c"

var _dir: String
var _repo: ProfileRepository
var _state: AppState
var _store: MemorySecureStore
var _mock: MockHttpTransport
var _cache: PlanCache
var _library: WorkoutLibrary
var _profile: Profile


## Транспорт, задерживающий ответ до `release()`: позволяет сменить профиль, пока запрос «в сети».
class GatedTransport extends MockHttpTransport:
	signal released()
	var hold: bool = false

	func release() -> void:
		hold = false
		released.emit()

	func request(method: String, url: String, headers: Dictionary,
			body: PackedByteArray = PackedByteArray(), timeout_sec: float = DEFAULT_TIMEOUT_SEC) -> HttpResponse:
		if hold:
			await released
		return super.request(method, url, headers, body, timeout_sec)


func before_each() -> void:
	_dir = "user://test_plan_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_repo = ProfileRepository.new(_dir + "profiles/")
	_profile = _repo.create("Rider")
	_profile.ftp_w = 200
	_profile.intervals_athlete_id = "i12345"
	_repo.save(_profile)
	_state = AppState.new(_repo)
	_state.start()
	_store = MemorySecureStore.new()
	_mock = MockHttpTransport.new()
	_cache = PlanCache.new(_dir + "plans/")
	_library = WorkoutLibrary.new(_dir + "workouts/")
	TranslationServer.set_locale("en")


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


func _with_key() -> void:
	var client := IntervalsIcuClient.for_profile(_mock, _store, _profile)
	_store.set_secret(client.secret_key(), KEY)


func _events(file: String = "events_today.json") -> Variant:
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(FIXTURES + file)), OK)
	return json.data


## Велотренировка WORKOUT с неразбираемой структурой (REQ-INT-07 крит. 5) — из фикстуры парсера.
func _unparsable_event() -> Dictionary:
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(WORKOUT_FIXTURES + "intervals_event_unsupported.json")), OK)
	var ev: Dictionary = json.data
	ev["id"] = 2099
	ev["name"] = "Broken plan"
	ev["category"] = "WORKOUT"
	ev["type"] = "Ride"
	ev["start_date_local"] = TODAY + "T00:00:00"
	return ev


## Ключ Intervals.icu в хранилище `main` (у него своё, не тестовое).
func _give_main_key(main: AppMain) -> void:
	var client := IntervalsIcuClient.for_profile(_mock, main.secure_store, main.repo.get_active())
	main.secure_store.set_secret(client.secret_key(), KEY)


func _screen() -> PlanScreen:
	var s: PlanScreen = load(SCENE).instantiate()
	s.today = TODAY
	s.setup(_state, _repo, _store, _mock, _cache, _library)
	add_child_autofree(s)
	return s


func _main() -> AppMain:
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = _mock
	add_child_autofree(main)
	return main


# ---------------------------------------------------------------------------
# Intervals.icu: статусы и список (INT-04, INT-07)
# ---------------------------------------------------------------------------

func test_without_api_key_shows_not_configured_and_key_form_opens() -> void:
	var s := _screen()
	var r: ApiResult = await s.load_today()
	assert_eq(r.code, ApiResult.CODE_NOT_CONFIGURED)
	assert_eq(s.status_text(), "Intervals.icu API key is not set")
	assert_eq(_mock.request_count(), 0, "без ключа запросов нет")
	assert_false(s.is_key_form_open())
	s.open_key_form()
	assert_true(s.is_key_form_open())
	assert_eq(s.key_dialog().athlete_id(), "i12345", "athlete_id из профиля подставлен (общий IntervalsKeyDialog)")


func test_events_fixture_lists_bike_workouts_with_duration_and_load() -> void:
	_with_key()
	_mock.enqueue_json("GET", "/events", 200, _events())
	var s := _screen()
	var r: ApiResult = await s.load_today()
	assert_true(r.ok)
	var items := s.intervals_items()
	assert_true(items.size() >= 2, "REQ-INT-04 крит. 2: ≥ 2 велотренировок из фикстуры")
	var list: ItemList = s.get_node("%WorkoutList")
	assert_eq(list.item_count, s.items().size())
	assert_string_contains(list.get_item_text(0), "Threshold 3x5")
	assert_string_contains(list.get_item_text(0), "39:00", "длительность плана мм:сс")
	assert_string_contains(list.get_item_text(0), "load 65", "целевая нагрузка")
	assert_string_contains(list.get_item_text(0), "Intervals.icu", "пометка источника")
	assert_string_contains(list.get_item_text(1), "Endurance text")
	assert_eq(s.status_text(), "Workouts loaded: %d" % items.size())
	assert_null(s.selected_workout(), "при нескольких тренировках авто-выбора нет")


func test_unparsable_event_stays_in_list_disabled_with_reason() -> void:
	_with_key()
	var events: Array = _events()
	events.append(_unparsable_event())
	_mock.enqueue_json("GET", "/events", 200, events)
	var s := _screen()
	await s.load_today()
	var broken: Array[Dictionary] = []
	for it in s.intervals_items():
		if it["workout"] == null:
			broken.append(it)
	assert_eq(broken.size(), 1, "REQ-INT-07 крит. 5: событие с неразбираемым планом остаётся в выдаче")
	if broken.is_empty():
		return
	assert_eq(broken[0]["name"], "Broken plan")
	assert_false(str(broken[0]["error"]).is_empty(), "с сообщением об ошибке разбора")
	var list: ItemList = s.get_node("%WorkoutList")
	var idx := s.items().find(broken[0])
	assert_true(list.is_item_disabled(idx), "нельзя выбрать для запуска")


func test_single_workout_is_preselected_without_choosing() -> void:
	_with_key()
	var events: Array = _events()
	_mock.enqueue_json("GET", "/events", 200, [events[0]])
	var s := _screen()
	await s.load_today()
	assert_eq(s.intervals_items().size(), 1)
	assert_not_null(s.selected_workout(), "REQ-INT-04 крит. 1: единственная тренировка предложена к запуску")
	assert_eq(s.preview_name_text(), "Threshold 3x5")
	assert_false((s.get_node("%StartButton") as Button).disabled)


func test_select_shows_preview_with_power_points_and_zone_colored_segments() -> void:
	_with_key()
	_mock.enqueue_json("GET", "/events", 200, _events())
	var s := _screen()
	await s.load_today()
	s.select_index(0)
	var w := s.selected_workout()
	assert_not_null(w)
	assert_eq(s.preview_name_text(), "Threshold 3x5")
	assert_eq(s.preview_points(), w.power_points(200, 1.0), "REQ-INT-05 крит. 1: точки графика = power_points")
	assert_string_contains(s.preview_duration_text(), "Duration 39:00")
	assert_string_contains(s.preview_duration_text(), "FTP 200")
	var chart := s.chart()
	assert_eq(chart.segments().size(), w.steps.size())
	for seg in chart.segments():
		if int(seg["start_watts"]) > 0:
			assert_eq(WorkoutChart.segment_color(seg), ZonePalette.color(ZonePalette.power_token(int(seg["zone"]))), "REQ-INT-05 крит. 3: цвет по зоне")
	assert_eq(chart.axis_minutes()[0], 0)
	assert_eq(chart.axis_minutes()[1], 5, "ось времени в минутах, шаг 5")
	assert_true(chart.axis_minutes().back() >= 35)


func test_preview_for_steps_and_ramp_uses_power_points_rules() -> void:
	var steps: Array[WorkoutStep] = [WorkoutStep.percent(600, 50.0), WorkoutStep.percent(300, 100.0), WorkoutStep.ramp_percent(120, 50.0, 100.0)]
	var w := Workout.make("steps", steps)
	var s := _screen()
	s.chart().set_workout(w, 200)
	var pts := s.chart().points()
	assert_eq(pts[0], Vector2(0, 100))
	assert_eq(pts[1], Vector2(600, 100), "REQ-INT-05 крит. 1: 100 Вт на [0; 600)")
	assert_eq(pts[2], Vector2(600, 200))
	assert_eq(pts[3], Vector2(900, 200), "200 Вт на [600; 900)")
	assert_eq(pts[4], Vector2(900, 100), "REQ-INT-05 крит. 2: рампа — начало")
	assert_eq(pts[5], Vector2(1020, 200), "конец рампы = цель конца")


func test_offline_uses_cache_with_loaded_time_label() -> void:
	_with_key()
	_mock.enqueue_json("GET", "/events", 200, _events())
	var s := _screen()
	var online: ApiResult = await s.load_today()
	assert_true(online.ok and not online.from_cache)
	_mock.offline = true
	var offline: ApiResult = await s.load_today()
	assert_true(offline.ok and offline.from_cache, "REQ-INT-07 крит. 2")
	assert_string_contains(s.status_text(), "from cache; loaded ")
	# Метка «загружен ЧЧ:ММ» — в локальном времени устройства, не в UTC: сверка с локальными
	# часами системы (загрузка была только что — допускается переход через границу минуты).
	var now_local := Time.get_datetime_dict_from_system(false)
	var now_min: int = int(now_local["hour"]) * 60 + int(now_local["minute"])
	var prev_min: int = (now_min + 1439) % 1440
	var now_text := "%02d:%02d" % [floori(now_min / 60.0), now_min % 60]
	var prev_text := "%02d:%02d" % [floori(prev_min / 60.0), prev_min % 60]
	var label := s.status_text()
	assert_true(label.contains(now_text) or label.contains(prev_text), "локальное время загрузки (%s или %s): %s" % [now_text, prev_text, label])
	assert_eq(s.intervals_items().size(), 2, "в кэше только разобранные тренировки")
	s.select_index(0)
	assert_not_null(s.selected_workout())


func test_loaded_time_label_matches_local_time_of_history_and_cache() -> void:
	# Ревью инфраструктуры: «загружен ЧЧ:ММ» — тот же локальный час, что в истории и в кэше плана.
	var unix := 1_790_000_000
	var local := PlanCache.local_datetime(unix)
	assert_eq(PlanScreen._format_time(unix), "%02d:%02d" % [local["hour"], local["minute"]])
	assert_eq(PlanScreen._format_time(unix), HistoryScreen.format_date_time(unix).substr(11, 5))
	assert_eq(PlanScreen._format_time(0), "—")


func test_offline_without_cache_shows_network_error() -> void:
	_with_key()
	_mock.offline = true
	var s := _screen()
	var r: ApiResult = await s.load_today()
	assert_false(r.ok)
	assert_eq(r.code, ApiResult.CODE_NETWORK)
	assert_eq(s.status_text(), "Network unavailable; no cached plan for today")
	assert_eq(s.items().size(), 0)


func test_empty_events_show_no_workout_today() -> void:
	_with_key()
	_mock.enqueue_json("GET", "/events", 200, _events("events_empty.json"))
	var s := _screen()
	var r: ApiResult = await s.load_today()
	assert_true(r.ok)
	assert_eq(r.code, ApiResult.CODE_NO_WORKOUT_TODAY)
	assert_eq(s.status_text(), "No workout today")
	assert_null(s.selected_workout())


func test_401_shows_reauth_required_and_does_not_use_cache() -> void:
	_with_key()
	_mock.enqueue_json("GET", "/events", 200, _events())
	var s := _screen()
	await s.load_today()
	_mock.enqueue_json("GET", "/events", 401, _events("error_401.json"))
	var r: ApiResult = await s.load_today()
	assert_false(r.ok)
	assert_eq(r.code, ApiResult.CODE_AUTH_FAILED)
	assert_eq(s.status_text(), "Re-authorisation with Intervals.icu required — enter the API key again", "REQ-INT-07 крит. 3")
	assert_eq(s.intervals_items().size(), 0, "кэшированный план не предлагается как актуальный")


func test_cached_plan_is_shown_on_open_without_network_requests() -> void:
	_with_key()
	_mock.enqueue_json("GET", "/events", 200, _events())
	var first := _screen()
	await first.load_today()
	var before := _mock.request_count()
	var second := _screen()
	assert_eq(second.intervals_items().size(), 2, "при открытии экрана план берётся из кэша")
	assert_string_contains(second.status_text(), "from cache")
	assert_eq(_mock.request_count(), before, "REQ-NFR-03 крит. 2: без сетевых запросов")


# ---------------------------------------------------------------------------
# Ключ API
# ---------------------------------------------------------------------------

func test_verify_key_401_shows_error_and_stores_nothing() -> void:
	_mock.enqueue_json("GET", "/athlete/", 401, _events("error_401.json"))
	var s := _screen()
	s.open_key_form()
	var r: ApiResult = await s.submit_key("i12345", "bad-key")
	assert_false(r.ok)
	assert_eq(s.key_error_text(), "Key rejected by Intervals.icu (401)")
	assert_true(s.is_key_form_open(), "форма остаётся открытой")
	assert_eq(_store.list_keys().size(), 0, "ключ не сохранён")


func test_verify_key_success_syncs_profile_and_loads_plan() -> void:
	_mock.enqueue_json("GET", "/athlete/", 200, _events("athlete.json"))
	_mock.enqueue_json("GET", "/events", 200, _events())
	var s := _screen()
	var updated: Array[Profile] = []
	s.profile_updated.connect(func(p: Profile) -> void: updated.append(p))
	s.open_key_form()
	var r: ApiResult = await s.submit_key("i12345", KEY)
	assert_true(r.ok)
	assert_false(s.is_key_form_open())
	assert_eq(_store.list_keys().size(), 1, "ключ в защищённом хранилище под профилем")
	assert_true(_store.list_keys()[0].begins_with(_profile.id + "/"))
	assert_eq(updated.size(), 1)
	var saved := _repo.get_by_id(_profile.id)
	assert_eq(saved.intervals_athlete_id, "i12345")
	assert_true(saved.ftp_source.begins_with("intervals"), "профиль синхронизирован из athlete.json")
	assert_eq(s.intervals_items().size(), 2, "план загружен сразу после проверки ключа")
	assert_string_contains(s.status_text(), "Workouts loaded")


func test_submit_key_with_empty_fields_shows_hint_without_request() -> void:
	var s := _screen()
	var r: ApiResult = await s.submit_key("", "")
	assert_false(r.ok)
	assert_eq(s.key_error_text(), "Enter Athlete ID and API key")
	assert_eq(_mock.request_count(), 0)


# ---------------------------------------------------------------------------
# Импорт файлов (IMP-03, IMP-04, IMP-05)
# ---------------------------------------------------------------------------

func test_import_valid_file_adds_library_entry_and_selects_it() -> void:
	var s := _screen()
	var r := s.on_import_file_selected(WORKOUT_FIXTURES + "simple.zwo")
	assert_true(r.ok(), "REQ-IMP-03 крит. 1: .zwo разобран")
	assert_eq(_library.count(_profile.id), 1, "REQ-IMP-04 крит. 1: запись в библиотеке")
	assert_eq(s.library_items().size(), 1)
	var list: ItemList = s.get_node("%WorkoutList")
	assert_string_contains(list.get_item_text(0), "library", "REQ-INT-04 крит. 3: пометка источника")
	assert_not_null(s.selected_workout(), "импортированная выбрана")
	assert_eq(s.selected_item()["source"], PlanScreen.SOURCE_LIBRARY)
	assert_string_contains(s.library_status_text(), "Imported: ")
	assert_eq(s.preview_points(), s.selected_workout().power_points(200, 1.0))


func test_import_broken_file_shows_dialog_with_user_message() -> void:
	var s := _screen()
	var r := s.on_import_file_selected(WORKOUT_FIXTURES + "unknown_element.zwo")
	assert_false(r.ok())
	var msg := s.import_error_text()
	assert_string_contains(msg, "unknown_element.zwo", "REQ-IMP-05 крит. 1: имя файла")
	assert_false(msg.contains("res://"), "без внутренних путей")
	assert_false(msg.contains("ParseResult") or msg.contains("ZwoParser"), "REQ-IMP-05 крит. 3: без имён классов")
	assert_eq(_library.count(_profile.id), 0)
	assert_eq(s.library_status_text(), "Import failed")


func test_import_unsupported_extension_and_missing_file_are_errors() -> void:
	var s := _screen()
	var bad := s.on_import_file_selected(WORKOUT_FIXTURES + "corrupted.json")
	assert_false(bad.ok(), "REQ-IMP-03 крит. 1: иное расширение — ошибка")
	assert_string_contains(s.import_error_text(), "corrupted.json")
	var missing := s.import_path(_dir + "nope.zwo")
	assert_false(missing.ok())
	assert_string_contains(s.import_error_text(), "nope.zwo")


func test_import_error_text_is_localized_by_key_en_and_ru() -> void:
	# REQ-IMP-05 крит. 1: тип проблемы — на языке интерфейса (по `ParseResult.key`), имя файла один раз.
	var s := _screen()
	s.import_path(WORKOUT_FIXTURES + "unknown_element.zwo")
	var en := s.import_error_text()
	assert_string_contains(en, "unknown_element.zwo: element SolidState is not supported (line 6)")
	assert_eq(en.count("unknown_element.zwo"), 1, "имя файла один раз")
	TranslationServer.set_locale("ru")
	s.import_path(WORKOUT_FIXTURES + "unknown_element.zwo")
	var ru := s.import_error_text()
	assert_string_contains(ru, "unknown_element.zwo: элемент SolidState не поддерживается (строка 6)")
	TranslationServer.set_locale("en")


func test_import_unsupported_extension_message_has_file_name_once() -> void:
	var s := _screen()
	s.import_path(WORKOUT_FIXTURES + "corrupted.json")
	var msg := s.import_error_text()
	assert_eq(msg, "corrupted.json: unsupported file type (expected .zwo, .erg or .mrc)")


func test_unknown_parse_key_falls_back_to_generic_text() -> void:
	var s := _screen()
	var entry := {"line": 3, "column": 2, "element": "x", "message": "внутренний текст", "key": "no_such_key"}
	assert_eq(s.localized_error(entry, "f.zwo"), "f.zwo: could not parse the file (element x, line 3, column 2)")
	assert_eq(s.localized_error({"key": "empty_file"}), "the file is empty")


func test_unparsable_event_tooltip_is_in_interface_language() -> void:
	_with_key()
	var events: Array = [_unparsable_event()]
	_mock.enqueue_json("GET", "/events", 200, events)
	var s := _screen()
	await s.load_today()
	var list: ItemList = s.get_node("%WorkoutList")
	var tip := list.get_item_tooltip(0)
	assert_false(tip.is_empty())
	var cyr := RegEx.create_from_string("[\\p{Cyrillic}]")
	assert_null(cyr.search(tip), "подсказка неразобранного события без кириллицы в en: " + tip)


func test_import_same_name_selects_new_entry_by_entry_id() -> void:
	# D3: после импорта выбирается запись с `metadata.entry_id`, а не старая с тем же именем.
	var zwo := "<workout_file><name>Same</name><sportType>bike</sportType><workout>%s</workout></workout_file>"
	var a := _dir + "a.zwo"
	var b := _dir + "b.zwo"
	for pair in [[a, "<SteadyState Duration=\"600\" Power=\"0.5\"/>"], [b, "<SteadyState Duration=\"900\" Power=\"0.9\"/>"]]:
		var f := FileAccess.open(pair[0], FileAccess.WRITE)
		f.store_string(zwo % pair[1])
		f.close()
	var s := _screen()
	assert_true(s.import_path(a).ok())
	var rb := s.import_path(b)
	assert_true(rb.ok())
	assert_eq(_library.count(_profile.id), 2)
	assert_eq(str(s.selected_item()["id"]), str(rb.metadata["entry_id"]))
	assert_eq(s.selected_workout().total_duration_sec(), 900)


func test_chart_segment_zones_follow_profile_zones_not_coggan() -> void:
	# D1 / REQ-INT-05 крит. 3 + REQ-HUD-03 крит. 1: зона сегмента — по границам профиля.
	var bounds: Array[float] = [70.0, 85.0, 95.0, 110.0, 125.0, 155.0]
	_profile.set_power_zones_local(PowerZones.custom(200, bounds))
	_repo.save(_profile)
	var s := _screen()
	assert_true(s.import_path(WORKOUT_FIXTURES + "simple.zwo").ok())
	var segs := s.chart().segments()
	assert_true(segs.size() > 0)
	var saw_difference := false
	for seg in segs:
		var w := int(seg["start_watts"])
		assert_eq(int(seg["zone"]), _profile.power_zone_of(w), "%d Вт — зона профиля" % w)
		if _profile.power_zone_of(w) != Zones.power_zone(w, 200):
			saw_difference = true
	assert_true(saw_difference, "фикстура содержит шаг, где зоны профиля и Coggan расходятся")
	# Без профильных границ — Coggan (контракт домена сохранён).
	var w0 := s.selected_workout()
	assert_eq(w0.segments(200)[0]["zone"], Zones.power_zone(int(w0.segments(200)[0]["start_watts"]), 200))


func test_emulator_button_text_follows_locale_change() -> void:
	# O2: текст кнопки «Эмулятор» (добавлена из кода) обновляется при смене языка.
	var s := _screen()
	var dialog: ConfirmationDialog = s.get_node("%TrainerDialog")
	var button: Button = null
	for child in dialog.find_children("*", "Button", true, false):
		if (child as Button).text == "Emulator":
			button = child
	assert_not_null(button, "кнопка «Эмулятор» (en)")
	TranslationServer.set_locale("ru")
	await get_tree().process_frame
	assert_eq(button.text, "Эмулятор")
	TranslationServer.set_locale("en")
	await get_tree().process_frame
	assert_eq(button.text, "Emulator")


func test_duplicate_import_updates_instead_of_adding() -> void:
	var s := _screen()
	s.on_import_file_selected(WORKOUT_FIXTURES + "simple.zwo")
	var r := s.on_import_file_selected(WORKOUT_FIXTURES + "simple.zwo")
	assert_true(r.ok())
	assert_eq(_library.count(_profile.id), 1, "REQ-IMP-04 крит. 4: число записей не растёт")
	assert_eq(s.library_items().size(), 1)
	assert_eq(s.library_status_text(), "Workout already in the library — updated")


func test_file_dialog_has_workout_filters_and_open_file_mode() -> void:
	var s := _screen()
	var dialog: FileDialog = s.get_node("%ImportDialog")
	assert_eq(dialog.file_mode, FileDialog.FILE_MODE_OPEN_FILE)
	assert_eq(dialog.access, FileDialog.ACCESS_FILESYSTEM)
	var joined := " ".join(dialog.filters)
	for ext in ["*.zwo", "*.erg", "*.mrc"]:
		assert_string_contains(joined, ext, "REQ-IMP-03 крит. 2: фильтр %s" % ext)


# ---------------------------------------------------------------------------
# Запуск (IMP-04 крит. 3, NFR-03)
# ---------------------------------------------------------------------------

func test_start_emits_workout_chosen_with_selected_plan() -> void:
	var s := _screen()
	s.on_import_file_selected(WORKOUT_FIXTURES + "simple.zwo")
	var chosen: Array[Workout] = []
	s.workout_chosen.connect(func(w: Workout, _src: String) -> void: chosen.append(w))
	assert_true(s.start_selected())
	assert_eq(chosen.size(), 1)
	assert_eq(chosen[0].name, s.selected_workout().name)
	s.select_index(99)
	assert_false(s.start_selected(), "без выбора — ничего")


func test_main_start_without_trainer_offers_emulator_then_opens_workout_screen() -> void:
	_with_key()
	_mock.enqueue_json("GET", "/events", 200, _events())
	var main := _main()
	_give_main_key(main)
	assert_true(main.app_state.navigate(AppState.Screen.PLAN))
	var plan := main.plan_screen()
	assert_true(main.visible_screen_node() == plan)
	plan.today = TODAY
	await plan.load_today()
	plan.select_index(0)
	var workout := plan.selected_workout()
	assert_not_null(workout, "план выбран")
	assert_false(main.is_trainer_ready(), "станок не подключён")
	assert_false(main.start_workout(workout), "сразу не стартует")
	assert_true(plan.is_trainer_choice_pending(), "предложен выбор эмулятор/устройства")
	assert_eq(main.pending_workout(), workout)
	plan.choose_emulator()
	assert_eq(main.app_state.current_screen, AppState.Screen.WORKOUT)
	var ws := main.workout_screen()
	assert_not_null(ws.session())
	assert_eq(ws.session().executor.workout.name, "Threshold 3x5", "REQ-IMP-04 крит. 3 / INT-04: запущен выбранный план")
	assert_eq(ws.session().executor.ftp_w, 200)
	ws.confirm_stop()


func test_library_workout_starts_the_same_way_and_makes_no_network_requests() -> void:
	var main := _main()
	main.app_state.navigate(AppState.Screen.PLAN)
	var plan := main.plan_screen()
	plan.on_import_file_selected(WORKOUT_FIXTURES + "simple.zwo")
	var workout := plan.selected_workout()
	assert_not_null(workout)
	var before := _mock.request_count()
	assert_true(main.start_workout_on_emulator(workout), "библиотечная тренировка стартует наравне с планом")
	var ws := main.workout_screen()
	assert_eq(ws.session().executor.workout.name, workout.name)
	for i in 30:
		ws.session().tick(1.0)
	ws.toggle_pause()
	ws.toggle_pause()
	ws.confirm_stop()
	assert_eq(ws.session().get_state(), WorkoutSession.State.FINISHED)
	assert_eq(_mock.request_count(), before, "REQ-NFR-03 крит. 2: 0 сетевых запросов за тренировку")


func test_devices_choice_navigates_to_devices_screen() -> void:
	var main := _main()
	main.app_state.navigate(AppState.Screen.PLAN)
	var plan := main.plan_screen()
	plan.on_import_file_selected(WORKOUT_FIXTURES + "simple.zwo")
	main.start_workout(plan.selected_workout())
	assert_true(plan.is_trainer_choice_pending())
	(plan.get_node("%TrainerDialog") as ConfirmationDialog).confirmed.emit()
	assert_false(plan.is_trainer_choice_pending())
	assert_eq(main.app_state.current_screen, AppState.Screen.DEVICES)


func test_home_workout_button_opens_plan_screen() -> void:
	var main := _main()
	var home: HomeScreen = main.screen_node(AppState.Screen.HOME)
	(home.get_node("%WorkoutButton") as Button).pressed.emit()
	assert_eq(main.app_state.current_screen, AppState.Screen.PLAN)
	assert_true(main.visible_screen_node() is PlanScreen)


# ---------------------------------------------------------------------------
# Смена профиля (ревью: план и асинхронные ответы не переходят к другому профилю)
# ---------------------------------------------------------------------------

func test_main_profile_switch_drops_previous_profile_plan_and_uses_new_profile_cache() -> void:
	# HIGH-1: план Intervals.icu профиля A не виден и не запускается у профиля B без ключа;
	# при возврате к A его план берётся из кэша A.
	var other := _repo.create("Other")
	_mock.enqueue_json("GET", "/events", 200, _events())
	var main := _main()
	assert_true(main.app_state.select_profile(_profile.id))
	_give_main_key(main)
	assert_true(main.app_state.navigate(AppState.Screen.PLAN))
	var plan := main.plan_screen()
	plan.today = TODAY
	await plan.load_today()
	assert_eq(plan.intervals_items().size(), 2, "план A загружен")
	plan.select_index(0)
	assert_not_null(plan.selected_workout())
	main.app_state.switch_profile()
	assert_true(main.app_state.select_profile(other.id))
	assert_true(main.app_state.navigate(AppState.Screen.PLAN))
	assert_eq(plan.intervals_items().size(), 0, "у B нет плана A")
	assert_eq(plan.selected_index(), -1, "выбор A сброшен")
	assert_null(plan.selected_workout())
	assert_false(plan.start_selected(), "B не может запустить тренировку A")
	assert_true((plan.get_node("%StartButton") as Button).disabled)
	assert_eq(plan.status_text(), "Intervals.icu API key is not set")
	assert_null(plan.last_result())
	var before := _mock.request_count()
	main.app_state.switch_profile()
	assert_true(main.app_state.select_profile(_profile.id))
	assert_true(main.app_state.navigate(AppState.Screen.PLAN))
	assert_eq(plan.intervals_items().size(), 2, "A снова видит свой план — из кэша A")
	assert_string_contains(plan.status_text(), "from cache")
	assert_eq(_mock.request_count(), before, "без сетевых запросов")


func test_load_today_response_for_previous_profile_is_dropped_after_switch() -> void:
	# MEDIUM-3: ответ, запрошенный для A, не попадает на экран профиля B.
	var gate := GatedTransport.new()
	_mock = gate
	_with_key()
	_mock.enqueue_json("GET", "/events", 200, _events())
	var s := _screen()
	var loaded: Array[ApiResult] = []
	s.plan_loaded.connect(func(r: ApiResult) -> void: loaded.append(r))
	gate.hold = true
	s.load_today()
	assert_eq(s.status_text(), "Loading plan…", "запрос A в полёте")
	var other := _repo.create("Other")
	assert_true(_state.select_profile(other.id))
	s.refresh()
	gate.release()
	await get_tree().process_frame
	assert_eq(gate.request_count("GET", "/events"), 1, "ответ A получен")
	assert_eq(s.intervals_items().size(), 0, "план A не показан профилю B")
	assert_null(s.last_result())
	assert_null(s.selected_workout())
	assert_eq(s.status_text(), "Intervals.icu API key is not set", "статус — профиля B")
	assert_eq(loaded.size(), 0, "plan_loaded для устаревшего ответа не испускается")


func test_submit_key_response_after_profile_switch_does_not_touch_new_profile() -> void:
	# MEDIUM-3: проверка ключа, начатая для A, не пишет Athlete ID и данные атлета в B.
	var gate := GatedTransport.new()
	_mock = gate
	_mock.enqueue_json("GET", "/athlete/", 200, _events("athlete.json"))
	_mock.enqueue_json("GET", "/events", 200, _events())
	var s := _screen()
	var updated: Array[Profile] = []
	s.profile_updated.connect(func(p: Profile) -> void: updated.append(p))
	gate.hold = true
	s.open_key_form()
	s.submit_key("i12345", KEY)
	var other := _repo.create("Other")
	var other_ftp := other.ftp_w
	var other_source := other.ftp_source
	assert_true(_state.select_profile(other.id))
	s.refresh()
	gate.release()
	await get_tree().process_frame
	var b := _repo.get_by_id(other.id)
	assert_eq(b.intervals_athlete_id, "", "Athlete ID A не записан в B")
	assert_eq(b.ftp_w, other_ftp, "FTP B не изменён")
	assert_eq(b.ftp_source, other_source, "источник FTP B не изменён")
	assert_eq(updated.size(), 0, "profile_updated не испускается для чужого ответа")
	assert_false(s.status_text().begins_with("Athlete:"), "сообщение об A не показано на экране B")
	assert_eq(s.intervals_items().size(), 0)
	assert_eq(gate.request_count("GET", "/events"), 0, "план после чужой проверки ключа не загружается")
	assert_eq(_store.list_keys().size(), 1)
	assert_true(_store.list_keys()[0].begins_with(_profile.id + "/"), "ключ — под профилем A")
	assert_true(_repo.get_by_id(_profile.id).ftp_source.begins_with("intervals"), "данные атлета — в профиле A")
