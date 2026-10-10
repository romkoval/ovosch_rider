extends GutTest
## Приёмка T-057 «Экран настроек» (tester, независимо от тестов разработчика).
## Критерии: REQ-NFR-08 крит. 3, 4; REQ-INT-06 крит. 5, 6 (крит. 7 — ручная, здесь только
## вспомогательная проверка текста); REQ-PRF-03 крит. 2; REQ-DEV-05 крит. 2 (хранение в профиле,
## решение Н-8); REQ-PRF-02 крит. 1 (UI-валидация). Архитектурные ограничения: Н-5
## (REQ-NFR-06 крит. 3), REQ-NFR-05 / REQ-INT-01 крит. 2 (ключ не в файлах и не в текстах
## ошибок), REQ-NFR-08 крит. 1, 2 (строки экрана — через ключи strings.csv).
## Раздел Strava (StravaConnectButton, T-049) здесь не проверяется.

const SCENE: String = "res://src/ui/settings/settings_screen.tscn"
const MAIN_SCENE: String = "res://src/app/main.tscn"
const ATHLETE_FIXTURE: String = "res://tests/fixtures/intervals/athlete.json"
## Таблицы переводов: `strings.csv` и файлы по областям `strings_<область>.csv` (T-060).
const CSV_DIR: String = "res://assets/i18n/"
const SECRET: String = "SECRETKEY-q7w8e9r0t1y2"
const ATHLETE_ID: String = "i12345"
## Префикс сообщений вспомогательного теста к критерию [ручная проверка] (REQ-INF-04 крит. 3).
const MANUAL_AUX: String = "[вспомогательно, ручная проверка REQ-INT-06 крит. 7] "

## Файлы экрана настроек и диалога ключа (объект приёмки T-057).
const SETTINGS_FILES: Array[String] = [
	"res://src/ui/settings/settings_screen.gd",
	"res://src/ui/settings/settings_screen.tscn",
	"res://src/ui/common/intervals_key_dialog.gd",
	"res://src/ui/common/intervals_key_dialog.tscn",
]

var _dir: String
var _repo: ProfileRepository
var _state: AppState
var _settings: AppSettings
var _store: MemorySecureStore
var _transport: MockHttpTransport
var _bridge: StubBleBridge
var _devices: RememberedDevices
var _cm: ConnectionManager
var _profile: Profile
var _previous_locale: String
var _csv: Dictionary = {}
var _pm: BlePowerMeter = null


func before_all() -> void:
	var files: Array[String] = []
	for name in DirAccess.get_files_at(CSV_DIR):
		if name.begins_with("strings") and name.ends_with(".csv"):
			files.append(CSV_DIR + name)
	assert_true(files.has(CSV_DIR + "strings.csv"), "предусловие: strings.csv найден")
	for path in files:
		var f := FileAccess.open(path, FileAccess.READ)
		var header := f.get_csv_line()
		while not f.eof_reached():
			var line := f.get_csv_line()
			if line.size() < header.size() or line[0].is_empty():
				continue
			var row: Dictionary = {}
			for i in range(1, header.size()):
				row[header[i]] = line[i]
			_csv[line[0]] = row
		f.close()


func before_each() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_dir = "user://test_settings_acc_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_repo = ProfileRepository.new(_dir + "profiles/")
	_profile = _repo.create("Rider")
	_settings = AppSettings.new(_dir + "settings.json")
	_state = AppState.new(_repo, _settings)
	_state.start()
	_store = MemorySecureStore.new()
	_transport = MockHttpTransport.new()
	_bridge = StubBleBridge.new()
	_devices = RememberedDevices.new(_dir + "devices/")
	_cm = ConnectionManager.new(_bridge, _devices, TrainerFactory.KIND_FAKE)
	_pm = null


func after_each() -> void:
	TranslationServer.set_locale(_previous_locale)
	if _pm != null:
		_pm.dispose()
		_pm = null
	if _cm != null:
		_cm.dispose()
		_cm = null
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


static func _all_files(abs_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(abs_path)
	if d == null:
		return
	for f in d.get_files():
		out.append(abs_path.path_join(f))
	for sub in d.get_directories():
		_all_files(abs_path.path_join(sub), out)


# ---------------------------------------------------------------------------
# Утилиты
# ---------------------------------------------------------------------------

func _screen() -> SettingsScreen:
	var s: SettingsScreen = load(SCENE).instantiate()
	s.setup(_repo, _state, _store, _transport, _cm)
	add_child_autofree(s)
	return s


func _main() -> AppMain:
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.transport = _transport
	add_child_autofree(main)
	return main


func _drop_main(main: AppMain) -> void:
	remove_child(main)
	main.free()


func _api_key_id(profile_id: String) -> String:
	return SecureStore.key_for(profile_id, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY)


func _link(store: SecureStore = null) -> void:
	var st: SecureStore = store if store != null else _store
	st.set_secret(_api_key_id(_profile.id), SECRET)
	var p := _repo.get_active().duplicate_profile()
	p.intervals_athlete_id = ATHLETE_ID
	_repo.save(p)


func _athlete_json() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(ATHLETE_FIXTURE))


## Фикстура атлета с подменёнными велосипедными настройками (повторная синхронизация).
func _athlete_variant(ftp: Variant, power_zones: Array, hr_zones: Array, max_hr: int) -> Dictionary:
	var d := _athlete_json()
	for ss in d["sportSettings"]:
		var types: Array = ss.get("types", [])
		if types.has("Ride"):
			ss["ftp"] = ftp
			ss["power_zones"] = power_zones
			ss["power_zone_names"] = []
			ss["hr_zones"] = hr_zones
			ss["hr_zone_names"] = []
			ss["max_hr"] = max_hr
	return d


func _csv_text(key: String, locale: String) -> String:
	return str((_csv.get(key, {}) as Dictionary).get(locale, "<missing %s>" % key))


func _code_lines(path: String) -> String:
	var kept: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var idx := line.find("#")
		kept.append(line.substr(0, idx) if idx != -1 else line)
	return "\n".join(kept)


static func _ui_files(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd") or f.ends_with(".tscn"):
			out.append(dir_path.path_join(f))
	for sub in d.get_directories():
		_ui_files(dir_path.path_join(sub), out)


## Байтовый поиск подстроки (без разбора UTF-8 бинарных файлов): совпадение по чётному смещению hex.
static func _hex_contains(hex: String, needle: String) -> bool:
	var n := needle.to_utf8_buffer().hex_encode()
	var at := hex.find(n)
	while at != -1:
		if at % 2 == 0:
			return true
		at = hex.find(n, at + 1)
	return false


func _set_profile(mut: Callable) -> void:
	var p := _repo.get_active().duplicate_profile()
	mut.call(p)
	assert_eq(_repo.save(p), [] as Array[String], "подготовка профиля")


# ===========================================================================
# REQ-NFR-08 крит. 3 — язык по умолчанию, переключение, сохранение
# ===========================================================================

func test_req_nfr_08_c3_default_is_system_language_if_ru_or_en_else_en() -> void:
	assert_eq(AppLocale.pick("ru_RU"), "ru")
	assert_eq(AppLocale.pick("en_GB"), "en")
	assert_eq(AppLocale.pick("de_DE"), "en", "не ru/en → en")
	assert_eq(AppLocale.pick("uk"), "en")
	assert_eq(AppLocale.pick(""), "en")
	var fresh := AppSettings.load_from(_dir + "settings.json")
	assert_false(fresh.has_locale(), "выбора ещё нет")
	assert_eq(fresh.effective_locale(), AppLocale.detect())
	TranslationServer.set_locale("ru" if AppLocale.detect() == "en" else "en")
	var main := _main()
	assert_eq(TranslationServer.get_locale().substr(0, 2), AppLocale.detect(),
		"без сохранённого выбора приложение стартует на языке системы")
	assert_false(FileAccess.file_exists(_dir + "settings.json"), "старт без выбора ничего не записывает")
	_drop_main(main)


func test_req_nfr_08_c3_choice_in_settings_applies_without_restart_and_persists() -> void:
	var main := _main()
	var home := main.screen_node(AppState.Screen.HOME) as HomeScreen
	assert_true(main.app_state.navigate(AppState.Screen.SETTINGS))
	var s := main.settings_screen()
	var option := s.get_node("%LocaleOption") as OptionButton
	var ru_idx := SettingsScreen.LOCALE_IDS.find("ru")
	assert_gt(ru_idx, -1, "ru есть в списке")
	option.select(ru_idx)
	option.item_selected.emit(ru_idx)
	assert_eq(TranslationServer.get_locale(), "ru", "применено без перезапуска")
	assert_eq((s.get_node("%SaveProfileButton") as Button).text, _csv_text("ui.settings.save_profile", "ru"))
	assert_eq(home.active_profile_text(), _csv_text("ui.home.active_profile", "ru").format({"name": "Rider"}),
		"другие экраны перерисованы без перезапуска")
	var raw := FileAccess.get_file_as_string(_dir + "settings.json")
	var data: Variant = JSON.parse_string(raw)
	assert_true(data is Dictionary, "settings.json — JSON")
	assert_eq(str((data as Dictionary).get("locale", "")), "ru", "выбор сохранён в data_dir/settings.json")
	_drop_main(main)
	TranslationServer.set_locale("en")
	var again := _main()
	assert_eq(TranslationServer.get_locale(), "ru", "после перезапуска действует сохранённый выбор")
	assert_true(again.app_state.navigate(AppState.Screen.SETTINGS))
	var opt2 := again.settings_screen().get_node("%LocaleOption") as OptionButton
	assert_eq(opt2.selected, ru_idx, "в списке выбран сохранённый язык")
	# Обратно на en — тоже сохраняется.
	opt2.select(SettingsScreen.LOCALE_IDS.find("en"))
	opt2.item_selected.emit(SettingsScreen.LOCALE_IDS.find("en"))
	assert_eq(AppSettings.load_from(_dir + "settings.json").locale, "en")
	_drop_main(again)


func test_req_nfr_08_c3_corrupted_or_unsupported_saved_locale_falls_back_to_system() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	var f := FileAccess.open(_dir + "settings.json", FileAccess.WRITE)
	f.store_string("{\"schema\": 1, \"locale\": \"de\"}")
	f.close()
	TranslationServer.set_locale("ru" if AppLocale.detect() == "en" else "en")
	var main := _main()
	assert_eq(TranslationServer.get_locale().substr(0, 2), AppLocale.detect(), "неподдерживаемый язык → системный")
	_drop_main(main)
	f = FileAccess.open(_dir + "settings.json", FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	TranslationServer.set_locale("ru" if AppLocale.detect() == "en" else "en")
	var main2 := _main()
	assert_eq(TranslationServer.get_locale().substr(0, 2), AppLocale.detect(), "повреждённый файл → системный")
	_drop_main(main2)


func test_req_nfr_08_c3_every_static_settings_text_follows_language_switch() -> void:
	var s := _screen()
	for locale in ["en", "ru", "en"]:
		assert_true(s.set_locale(locale))
		for path: String in SettingsScreen.STATIC_TEXTS:
			var node := s.get_node_or_null(path)
			assert_not_null(node, "узел %s" % path)
			if node == null:
				continue
			var key: String = SettingsScreen.STATIC_TEXTS[path]
			assert_eq(str(node.get("text")), _csv_text(key, locale), "%s [%s]" % [path, locale])
		assert_eq(s.profile_status_text(), _csv_text("ui.settings.profile_title", locale).format({"name": "Rider"}))


# ===========================================================================
# REQ-NFR-08 крит. 4 — форматы чисел и времени одинаковы в обоих языках
# ===========================================================================

func test_req_nfr_08_c4_time_and_number_formats_identical_in_ru_and_en() -> void:
	var out: Dictionary = {}
	for locale in ["en", "ru"]:
		TranslationServer.set_locale(locale)
		out[locale] = [
			HudModel.format_elapsed(65), HudModel.format_elapsed(3725),
			HudModel.format_countdown(9), HudModel.format_speed(32.5),
			IntervalsPlanService.format_duration(3725),
		]
	assert_eq(out["en"], out["ru"], "форматы не зависят от языка")
	assert_eq(out["ru"][0], "01:05", "мм:сс")
	assert_eq(out["ru"][3], "32.5", "точка как десятичный разделитель")


func test_req_nfr_08_c4_settings_numbers_and_dates_use_same_format_in_ru() -> void:
	_set_profile(func(p: Profile) -> void:
		p.weight_kg = 81.5
		p.ftp_source = "intervals:2026-10-01")
	var s := _screen()
	var weight := s.get_node("%WeightSpin") as SpinBox
	var texts: Dictionary = {}
	for locale in ["en", "ru"]:
		s.set_locale(locale)
		weight.value = 70.0
		weight.value = 81.5
		await get_tree().process_frame
		await get_tree().process_frame
		texts[locale] = weight.get_line_edit().text
		assert_string_contains(s.sources_text(), "2026-10-01", "дата ГГГГ-ММ-ДД [%s]" % locale)
	assert_eq(texts["en"], "81.5", "вес с точкой и одним знаком")
	assert_eq(texts["en"], texts["ru"], "вес отображается одинаково в ru и en")
	assert_false(str(texts["ru"]).contains(","), "в ru нет запятой как разделителя: %s" % texts["ru"])


# ===========================================================================
# REQ-PRF-02 крит. 1 — UI-валидация FTP / вес / max HR с переведёнными сообщениями
# ===========================================================================

func test_req_prf_02_c1_boundaries_accept_and_reject_through_form() -> void:
	var s := _screen()
	# [ftp, weight, max_hr, ожидаемый код или ""]
	var cases: Array = [
		[50, 75.0, 0, ""], [600, 75.0, 0, ""], [49, 75.0, 0, Profile.ERR_FTP_OUT_OF_RANGE],
		[601, 75.0, 0, Profile.ERR_FTP_OUT_OF_RANGE], [200, 20.0, 0, ""], [200, 250.0, 0, ""],
		[200, 19.9, 0, Profile.ERR_WEIGHT_OUT_OF_RANGE], [200, 250.1, 0, Profile.ERR_WEIGHT_OUT_OF_RANGE],
		[200, 75.0, 100, ""], [200, 75.0, 220, ""], [200, 75.0, 99, Profile.ERR_MAX_HR_OUT_OF_RANGE],
		[200, 75.0, 221, Profile.ERR_MAX_HR_OUT_OF_RANGE], [200, 75.0, 0, ""],
	]
	for c in cases:
		var before := _repo.get_active().duplicate_profile()
		s.fill_profile_form("Rider", int(c[0]), float(c[1]), int(c[2]))
		var errors := s.save_profile()
		var label := "ftp=%s weight=%s max_hr=%s" % [c[0], c[1], c[2]]
		if str(c[3]).is_empty():
			assert_eq(errors, [] as Array[String], "принято: " + label)
			assert_eq(s.profile_error_text(), "", "нет ошибки: " + label)
			var saved := ProfileRepository.new(_dir + "profiles/").get_active()
			assert_eq(saved.ftp_w, int(c[0]), "сохранено на диск: " + label)
			assert_almost_eq(saved.weight_kg, float(c[1]), 1e-6, "вес: " + label)
			assert_eq(saved.max_hr, int(c[2]), "max_hr: " + label)
		else:
			assert_eq(errors, [str(c[3])] as Array[String], "отклонено: " + label)
			assert_eq(s.profile_error_text(), _csv_text("error.profile." + str(c[3]), "en"), "сообщение: " + label)
			var stored := ProfileRepository.new(_dir + "profiles/").get_active()
			assert_eq(stored.ftp_w, before.ftp_w, "не сохранено: " + label)
			assert_almost_eq(stored.weight_kg, before.weight_kg, 1e-6, "не сохранено: " + label)
			assert_eq(stored.max_hr, before.max_hr, "не сохранено: " + label)


func test_req_prf_02_c1_all_errors_listed_and_translated_in_russian() -> void:
	var other := _repo.create("Other")
	assert_not_null(other)
	var s := _screen()
	s.set_locale("ru")
	s.fill_profile_form("Rider", 700, 300.0, 50)
	var errors := s.save_profile()
	assert_has(errors, Profile.ERR_FTP_OUT_OF_RANGE)
	assert_has(errors, Profile.ERR_WEIGHT_OUT_OF_RANGE)
	assert_has(errors, Profile.ERR_MAX_HR_OUT_OF_RANGE)
	var text := s.profile_error_text()
	for code in [Profile.ERR_FTP_OUT_OF_RANGE, Profile.ERR_WEIGHT_OUT_OF_RANGE, Profile.ERR_MAX_HR_OUT_OF_RANGE]:
		assert_string_contains(text, _csv_text("error.profile." + code, "ru"), "переведено на ru: %s" % code)
	assert_false(text.contains("error.profile."), "нет сырых ключей: %s" % text)
	assert_false(text.contains("_out_of_range"), "нет сырых кодов: %s" % text)
	s.fill_profile_form("Other", 200, 75.0, 0)
	assert_eq(s.save_profile(), [ProfileRepository.ERR_NAME_NOT_UNIQUE] as Array[String])
	assert_eq(s.profile_error_text(), _csv_text("error.profile.name_not_unique", "ru"))
	assert_eq(_repo.get_active().name, "Rider", "имя не изменено")


# ===========================================================================
# REQ-INT-06 крит. 5 — «переопределить локально» защищает FTP и зоны от синхронизации
# ===========================================================================

func test_req_int_06_c5_override_via_checkbox_keeps_ftp_power_and_hr_zones() -> void:
	_set_profile(func(p: Profile) -> void:
		p.set_ftp_local(210)
		p.max_hr = 180
		p.set_power_zones_local(PowerZones.custom(210, [50.0, 70.0, 85.0, 100.0, 115.0, 140.0] as Array[float]))
		p.set_hr_zones_local(HrZones.custom_bpm([110, 130, 150, 170] as Array[int])))
	_link()
	var s := _screen()
	var check := s.get_node("%OverrideCheck") as CheckButton
	check.button_pressed = true  # пользователь включает переключатель
	assert_true(ProfileRepository.new(_dir + "profiles/").get_active().intervals_override_local,
		"флаг сохранён в профиле на диск")
	_transport.enqueue_json("GET", "api/v1/athlete/" + ATHLETE_ID, 200, _athlete_json())
	var result: ApiResult = await s.sync_intervals()
	assert_true(result.ok)
	var p := ProfileRepository.new(_dir + "profiles/").get_active()
	assert_eq(p.ftp_w, 210, "FTP не изменён")
	assert_eq(p.effective_power_zones().boundaries_pct, [50.0, 70.0, 85.0, 100.0, 115.0, 140.0] as Array[float], "зоны мощности не изменены")
	assert_not_null(p.hr_zones)
	if p.hr_zones != null:
		assert_eq(p.hr_zones.boundaries_bpm, [110, 130, 150, 170] as Array[int], "зоны пульса не изменены")
	assert_eq(p.max_hr, 180, "max_hr (база зон пульса) не изменён")
	assert_eq(p.ftp_source, Profile.SOURCE_LOCAL)
	assert_eq(p.zones_source, Profile.SOURCE_LOCAL)
	assert_eq(s.intervals_message_text(), _csv_text("ui.settings.sync_skipped_override", "en"))


func test_req_int_06_c5_override_after_previous_sync_and_manual_edit_survives_resync() -> void:
	_link()
	var s := _screen()
	_transport.enqueue_json("GET", "api/v1/athlete/" + ATHLETE_ID, 200, _athlete_json())
	assert_true((await s.sync_intervals()).ok)
	assert_eq(_repo.get_active().ftp_w, 250, "первая синхронизация применилась")
	s.fill_profile_form("Rider", 230, 75.0, _repo.get_active().max_hr)
	assert_eq(s.save_profile(), [] as Array[String])
	s.set_override_local(true)
	var zones_before := _repo.get_active().effective_power_zones().boundaries_pct.duplicate()
	var hr_before: Array[int] = _repo.get_active().hr_zones.boundaries_bpm.duplicate()
	_transport.enqueue_json("GET", "api/v1/athlete/" + ATHLETE_ID, 200,
		_athlete_variant(280, [50, 70, 85, 100, 115, 140, 999], [118, 138, 158, 175, 185, 199], 199))
	assert_true((await s.sync_intervals()).ok)
	var p := _repo.get_active()
	assert_eq(p.ftp_w, 230, "ручной FTP сохранён при переопределении")
	assert_eq(p.effective_power_zones().boundaries_pct, zones_before)
	assert_eq(p.hr_zones.boundaries_bpm, hr_before)
	assert_eq(p.max_hr, 192, "max_hr из первой синхронизации, не 199")


# ===========================================================================
# REQ-INT-06 крит. 6 — без переопределения повторная синхронизация обновляет значения
# ===========================================================================

func test_req_int_06_c6_resync_without_override_updates_ftp_and_zones() -> void:
	_link()
	var s := _screen()
	_transport.enqueue_json("GET", "api/v1/athlete/" + ATHLETE_ID, 200, _athlete_json())
	assert_true((await s.sync_intervals()).ok)
	assert_eq(_repo.get_active().ftp_w, 250)
	_transport.enqueue_json("GET", "api/v1/athlete/" + ATHLETE_ID, 200,
		_athlete_variant(270, [56, 76, 91, 106, 121, 151, 999], [118, 138, 158, 175, 185, 195], 195))
	var r: ApiResult = await s.sync_intervals()
	assert_true(r.ok)
	var p := ProfileRepository.new(_dir + "profiles/").get_active()
	assert_eq(p.ftp_w, 270, "FTP обновлён")
	assert_eq(p.effective_power_zones().boundaries_pct, [56.0, 76.0, 91.0, 106.0, 121.0, 151.0] as Array[float], "зоны мощности обновлены")
	assert_not_null(p.hr_zones)
	if p.hr_zones != null:
		assert_eq(p.hr_zones.boundaries_bpm, [119, 139, 159, 176, 186] as Array[int], "зоны пульса обновлены")
	assert_eq(p.max_hr, 195)
	var today := "intervals:" + IntervalsIcuClient.local_date()
	assert_eq(p.ftp_source, today)
	assert_eq(p.zones_source, today)
	assert_eq(_transport.request_count("GET", "api/v1/athlete/" + ATHLETE_ID), 2)


func test_req_int_06_c6_turning_override_off_via_checkbox_lets_sync_overwrite_local_values() -> void:
	_link()
	var s := _screen()
	var check := s.get_node("%OverrideCheck") as CheckButton
	s.fill_profile_form("Rider", 230, 75.0, 0)
	assert_eq(s.save_profile(), [] as Array[String])
	check.button_pressed = true
	_transport.enqueue_json("GET", "api/v1/athlete/" + ATHLETE_ID, 200, _athlete_json())
	await s.sync_intervals()
	assert_eq(_repo.get_active().ftp_w, 230, "пока переопределение включено — без изменений")
	check.button_pressed = false
	assert_false(ProfileRepository.new(_dir + "profiles/").get_active().intervals_override_local)
	_transport.enqueue_json("GET", "api/v1/athlete/" + ATHLETE_ID, 200, _athlete_json())
	assert_true((await s.sync_intervals()).ok)
	var p := _repo.get_active()
	assert_eq(p.ftp_w, 250, "после выключения синхронизация обновляет FTP")
	assert_true(p.zones_source.begins_with("intervals:"))
	assert_eq(s.intervals_message_text(), _csv_text("ui.settings.sync_done", "en"))


# ===========================================================================
# REQ-INT-06 крит. 7 — [ручная проверка]; здесь только вспомогательная проверка текста.
# Тест `*_c7_manual_aux_*` — автоматическая часть ручного критерия (REQ-INF-04 крит. 3),
# критерий им не закрывается: видимость источника на экране профиля проверяется вручную.
# ===========================================================================

func test_req_int_06_c7_manual_aux_source_text_reflects_ftp_and_zones_source() -> void:
	# Вспомогательный автотест (REQ-INF-04 крит. 3): автоматическая часть критерия
	# REQ-INT-06 крит. 7 [ручная проверка]; критерий не закрывает.
	_set_profile(func(p: Profile) -> void:
		p.ftp_source = "intervals:2026-10-01"
		p.zones_source = Profile.SOURCE_LOCAL)
	var s := _screen()
	for locale in ["en", "ru"]:
		s.set_locale(locale)
		var expected := _csv_text("ui.settings.sources", locale).format({
			"ftp": _csv_text("ui.settings.source_intervals", locale).format({"date": "2026-10-01"}),
			"zones": _csv_text("ui.settings.source_local", locale)})
		assert_eq(s.sources_text(), expected, MANUAL_AUX + ("[%s] текст источника FTP/зон" % locale))


# ===========================================================================
# REQ-PRF-03 крит. 2 — отвязка удаляет только ключ Intervals.icu этого профиля
# ===========================================================================

func test_req_prf_03_c2_unlink_button_removes_only_this_profile_intervals_key() -> void:
	var b := _repo.create("Bob")
	var b_edit := b.duplicate_profile()
	b_edit.intervals_athlete_id = "i999"
	_repo.save(b_edit)
	_repo.active_profile_id = _profile.id
	_link()
	var a_strava := SecureStore.key_for(_profile.id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN)
	var a_refresh := SecureStore.key_for(_profile.id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_REFRESH_TOKEN)
	var b_key := _api_key_id(b.id)
	var b_strava := SecureStore.key_for(b.id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN)
	_store.set_secret(a_strava, "a-strava")
	_store.set_secret(a_refresh, "a-refresh")
	_store.set_secret(b_key, "b-intervals")
	_store.set_secret(b_strava, "b-strava")
	var s := _screen()
	var forget := s.get_node("%IntervalsForgetButton") as Button
	assert_false(forget.disabled, "кнопка «Отвязать» доступна при привязке")
	# Решение ред. 2 (`ui.md` п. 8.6): кнопка только спрашивает подтверждение.
	forget.pressed.emit()
	assert_true(s.is_forget_intervals_pending(), "кнопка открыла диалог подтверждения")
	assert_eq(_store.get_secret(_api_key_id(_profile.id)), SECRET, "без подтверждения ключ на месте")
	assert_eq(_store.size(), 5, "без подтверждения ничего не удалено")
	var dialog := s.get_node("%ForgetIntervalsDialog") as ConfirmationDialog
	dialog.get_cancel_button().pressed.emit()
	await wait_process_frames(2)
	assert_false(s.is_forget_intervals_pending(), "«Отмена» закрыла диалог")
	assert_eq(_store.get_secret(_api_key_id(_profile.id)), SECRET, "«Отмена» ключ не удаляет")
	assert_eq(_store.size(), 5)
	assert_false(forget.disabled, "после «Отмены» привязка осталась")
	assert_eq(_repo.get_by_id(_profile.id).intervals_athlete_id, ATHLETE_ID, "после «Отмены» атлет привязан")
	# Подтверждение — удаление.
	assert_true(s.request_forget_intervals())
	assert_true(s.is_forget_intervals_pending())
	s.confirm_forget_intervals()
	assert_false(s.is_forget_intervals_pending(), "после подтверждения диалог закрыт")
	assert_false(_store.has_secret(_api_key_id(_profile.id)), "ключ Intervals.icu профиля A удалён")
	assert_eq(_store.get_secret(a_strava), "a-strava", "Strava профиля A не тронута")
	assert_eq(_store.get_secret(a_refresh), "a-refresh")
	assert_eq(_store.get_secret(b_key), "b-intervals", "Intervals.icu профиля B не тронут")
	assert_eq(_store.get_secret(b_strava), "b-strava")
	assert_eq(_store.size(), 4)
	assert_eq(_repo.get_by_id(b.id).intervals_athlete_id, "i999", "профиль B не изменён")
	assert_true((s.get_node("%IntervalsSyncButton") as Button).disabled, "синхронизация недоступна после отвязки")
	assert_true(forget.disabled)


func test_req_prf_03_c2_unlink_in_app_persists_in_encrypted_store() -> void:
	var b := _repo.create("Bob")
	_repo.active_profile_id = _profile.id
	var main := _main()
	assert_true(main.app_state.select_profile(_profile.id))
	var store := main.secure_store
	_link(store)
	store.set_secret(_api_key_id(b.id), "b-intervals")
	store.set_secret(SecureStore.key_for(_profile.id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN), "a-strava")
	assert_true(main.app_state.navigate(AppState.Screen.SETTINGS))
	var settings := main.settings_screen()
	settings.refresh()
	(settings.get_node("%IntervalsForgetButton") as Button).pressed.emit()
	assert_true(settings.is_forget_intervals_pending(), "кнопка открыла подтверждение")
	assert_true(store.has_secret(_api_key_id(_profile.id)), "без подтверждения ключ A на месте")
	settings.confirm_forget_intervals()
	_drop_main(main)
	var reopened := EncryptedFileSecureStore.new(_dir + "secure/", SecureStore.derive_device_password())
	assert_true(reopened.loaded_ok())
	assert_false(reopened.has_secret(_api_key_id(_profile.id)), "после перезапуска ключа A нет")
	assert_eq(reopened.get_secret(_api_key_id(b.id)), "b-intervals", "ключ B на месте")
	assert_eq(reopened.get_secret(SecureStore.key_for(_profile.id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN)), "a-strava")


func test_req_prf_03_c2_unlink_not_confirmed_survives_restart() -> void:
	_repo.active_profile_id = _profile.id
	var main := _main()
	assert_true(main.app_state.select_profile(_profile.id))
	var store := main.secure_store
	_link(store)
	assert_true(main.app_state.navigate(AppState.Screen.SETTINGS))
	var settings := main.settings_screen()
	settings.refresh()
	(settings.get_node("%IntervalsForgetButton") as Button).pressed.emit()
	assert_true(settings.is_forget_intervals_pending())
	_drop_main(main)  # приложение закрыто с открытым диалогом — подтверждения не было
	var reopened := EncryptedFileSecureStore.new(_dir + "secure/", SecureStore.derive_device_password())
	assert_true(reopened.loaded_ok())
	assert_eq(reopened.get_secret(_api_key_id(_profile.id)), SECRET, "без подтверждения ключ сохранился и после перезапуска")


## Strava профиля A с токенами; профиль B со своими токенами и ключ Intervals.icu у A.
func _strava_setup() -> Dictionary:
	var b := _repo.create("Bob")
	_repo.active_profile_id = _profile.id
	var rides := FileRideRepository.new(_dir + "rides/")
	var service := StravaService.new(_repo.get_active(), _transport, _store, rides,
		StravaConfig.from_values("4242", "fixture-client-secret-value"), func() -> int: return 1_790_000_000, _dir + "strava/")
	service.oauth.base_url = "https://mock.strava.test"
	_store.set_secret(service.oauth.secret_key(SecureStore.ITEM_ACCESS_TOKEN), "a-access")
	_store.set_secret(service.oauth.secret_key(SecureStore.ITEM_REFRESH_TOKEN), "a-refresh")
	_store.set_secret(service.oauth.secret_key(SecureStore.ITEM_EXPIRES_AT), str(1_790_000_000 + 99999))
	_store.set_secret(SecureStore.key_for(b.id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN), "b-access")
	_store.set_secret(_api_key_id(_profile.id), SECRET)
	assert_true(service.is_authorized(), "предусловие: Strava профиля A привязана")
	return {"service": service, "b": b}


func _strava_press(s: SettingsScreen) -> void:
	var sb := s.strava_button()
	for n in sb.find_children("*", "Button", true, false):
		var btn := n as Button
		if btn.is_visible_in_tree() and btn.text == sb.button_text():
			btn.pressed.emit()
			return
	fail_test("кнопка «Отвязать Strava» не найдена")


func test_req_prf_03_c2_unlink_strava_asks_and_removes_only_this_profile_strava() -> void:
	var ctx := _strava_setup()
	var service: StravaService = ctx["service"]
	var b: Profile = ctx["b"]
	var a_access := service.oauth.secret_key(SecureStore.ITEM_ACCESS_TOKEN)
	var b_access := SecureStore.key_for(b.id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN)
	var s := _screen()
	s.set_strava_service(service)
	await wait_process_frames(1)
	assert_true(s.strava_button().is_authorized(), "предусловие: кнопка в режиме «Отвязать»")
	_strava_press(s)
	assert_true(s.is_disconnect_strava_pending(), "«Отвязать Strava» открывает подтверждение")
	assert_eq(_store.get_secret(a_access), "a-access", "без подтверждения токены Strava на месте")
	var dialog := s.get_node("%DisconnectStravaDialog") as ConfirmationDialog
	dialog.get_cancel_button().pressed.emit()
	await wait_process_frames(2)
	assert_false(s.is_disconnect_strava_pending(), "«Отмена» закрыла диалог")
	assert_eq(_store.get_secret(a_access), "a-access", "«Отмена» токены не удаляет")
	assert_true(service.is_authorized(), "после «Отмены» Strava привязана")
	assert_eq(_store.size(), 5)
	_transport.enqueue_json("POST", "/oauth/deauthorize", 200, {})
	assert_true(s.request_disconnect_strava())
	s.confirm_disconnect_strava()
	for i in 30:
		if not _store.has_secret(a_access):
			break
		await wait_process_frames(1)
	assert_false(s.is_disconnect_strava_pending())
	assert_false(_store.has_secret(a_access), "токены Strava профиля A удалены")
	assert_false(_store.has_secret(service.oauth.secret_key(SecureStore.ITEM_REFRESH_TOKEN)))
	assert_eq(_store.get_secret(b_access), "b-access", "Strava профиля B не тронута")
	assert_eq(_store.get_secret(_api_key_id(_profile.id)), SECRET, "Intervals.icu профиля A не тронут")
	assert_eq(_store.size(), 2)
	s.set_strava_service(null)
	service.dispose()


## Опасное действие: после открытия диалога (и после кадров) фокус — на «Отмена», чтобы Enter
## не отвязывал (заявлено T-089, `settings_screen.gd`: «по Enter — «Отмена», а не «Отвязать»»).
func _assert_cancel_focused(dialog: ConfirmationDialog, what: String) -> void:
	var owner := dialog.gui_get_focus_owner()
	gut.p("%s: фокус у %s (%s)" % [what, owner, (owner as Button).text if owner is Button else "—"])
	assert_true(dialog.get_cancel_button().has_focus(), "%s: фокус на «Отмена»" % what)
	assert_false(dialog.get_ok_button().has_focus(), "%s: опасная «Отвязать» не в фокусе" % what)


func test_unlink_dialogs_focus_cancel_after_open() -> void:
	var ctx := _strava_setup()
	var service: StravaService = ctx["service"]
	_link()
	var s := _screen()
	s.set_strava_service(service)
	s.refresh()
	await wait_process_frames(1)
	(s.get_node("%IntervalsForgetButton") as Button).pressed.emit()
	await wait_process_frames(3)
	var forget := s.get_node("%ForgetIntervalsDialog") as ConfirmationDialog
	assert_true(forget.visible)
	_assert_cancel_focused(forget, "«Отвязать Intervals.icu?»")
	forget.hide()
	await wait_process_frames(1)
	_strava_press(s)
	await wait_process_frames(3)
	var strava := s.get_node("%DisconnectStravaDialog") as ConfirmationDialog
	assert_true(strava.visible)
	_assert_cancel_focused(strava, "«Отвязать Strava?»")
	strava.hide()
	s.set_strava_service(null)
	service.dispose()


## То же в приложении целиком (как в сценарии снимков `dialog_forget_intervals`): главная сцена,
## переход в настройки, диалог открыт кнопкой; проверка после 0.5 с и кадров.
func test_unlink_dialog_focus_cancel_in_app() -> void:
	_repo.active_profile_id = _profile.id
	var main := _main()
	assert_true(main.app_state.select_profile(_profile.id))
	_link(main.secure_store)
	assert_true(main.app_state.navigate(AppState.Screen.SETTINGS))
	var settings := main.settings_screen()
	settings.refresh()
	await wait_process_frames(2)
	(settings.get_node("%IntervalsForgetButton") as Button).pressed.emit()
	await wait_seconds(0.5)
	await wait_process_frames(6)
	var forget := settings.get_node("%ForgetIntervalsDialog") as ConfirmationDialog
	assert_true(forget.visible)
	_assert_cancel_focused(forget, "приложение, «Отвязать Intervals.icu?»")
	forget.hide()
	await wait_process_frames(1)
	# Повторное открытие — тоже на «Отмена».
	settings.request_forget_intervals()
	await wait_process_frames(3)
	_assert_cancel_focused(forget, "приложение, повторное открытие")
	forget.hide()
	# Диалог открыт в том же кадре, что и переход в настройки (сценарий скрипта снимков).
	assert_true(main.app_state.navigate(AppState.Screen.HOME))
	await wait_process_frames(2)
	assert_true(main.app_state.navigate(AppState.Screen.SETTINGS))
	main.settings_screen().request_forget_intervals()
	await wait_seconds(0.5)
	await wait_process_frames(6)
	_assert_cancel_focused(forget, "приложение, открыт сразу после перехода")
	forget.hide()
	_drop_main(main)


# ===========================================================================
# REQ-DEV-05 крит. 2 — источник мощности в профиле (Н-8), применяется к SensorHub
# ===========================================================================

func _attach_power_meter() -> BlePowerMeter:
	var pm := BlePowerMeter.new(_bridge)
	pm.connect_device("pm")
	_bridge.pump()
	_cm.hub.set_power_meter(pm)
	_pm = pm
	return pm


## DEV-05 п.2 и WRK-09 п.14 (г) в редакции У-32 (T-170): выбора источника нет, поток мощности
## хаба — от измерителя, пока он шлёт пакеты; замолчал на 5 с — от станка.
func test_req_dev_05_c2_choice_saved_in_profile_and_drives_hub_stream() -> void:
	var trainer := _cm.trainer as FakeTrainer
	trainer.connect_delay_sec = 0.0
	trainer.power_noise_w = 0.0
	trainer.connect_device("fake")
	trainer.set_rider_power(150)
	_bridge.set_device_services("pm", {"1818": ["2A63"]})
	_attach_power_meter()
	var samples: Array[TrainerSample] = []
	_cm.hub.telemetry.connect(func(sm: TrainerSample) -> void: samples.append(sm))
	var s := _screen()
	assert_null(s.get_node_or_null("%PowerSourceOption"), "выбора «Источник мощности» в настройках нет")
	_bridge.emit_notification("pm", "2A63", BleBytes.from_hex("00 00 2C 01"))  # 300 Вт
	_cm.hub.tick(1.0)
	assert_false(samples.is_empty())
	if not samples.is_empty():
		assert_eq(samples.back().power_w, 300, "поток мощности — от измерителя")
	assert_eq(_cm.hub.power_source_in_use(), SensorHub.SOURCE_POWER_METER)
	for i in 5:
		_cm.hub.tick(1.0)
	assert_eq(_cm.hub.power_source_in_use(), SensorHub.SOURCE_TRAINER, "измеритель молчит 5 с — станок")
	if not samples.is_empty():
		assert_ne(samples.back().power_w, 300, "поток мощности — от станка")


## Старый профиль с полем «power_source» загружается; после смены профиля приоритет тот же.
func test_req_dev_05_c2_restored_on_start_and_follows_profile_switch() -> void:
	var bob := _repo.create("Bob")
	var main := _main()
	assert_eq(main.app_state.current_screen, AppState.Screen.PROFILE_SELECT)
	assert_true(main.app_state.select_profile(_profile.id))
	assert_true(main.app_state.navigate(AppState.Screen.SETTINGS))
	assert_null(main.settings_screen().get_node_or_null("%PowerSourceOption"), "выбора нет")
	main.app_state.switch_profile()
	assert_true(main.app_state.select_profile(bob.id))
	assert_false("power_source" in main.connections.hub, "у хаба нет выбора источника")
	_drop_main(main)
	var legacy := Profile.from_dict({"id": "old", "name": "Old", "power_source": "power_meter"})
	assert_not_null(legacy, "старый профиль с полем загружается")
	assert_eq(legacy.validate(), [] as Array[String], "без ошибок")
	assert_false(legacy.to_dict().has("power_source"), "поле больше не пишется")


# ===========================================================================
# Н-5 / REQ-NFR-06 крит. 3 — экран зависит от AppState, а не от main.gd / locale.gd
# ===========================================================================

func test_n5_settings_ui_does_not_reference_app_shell_or_locale() -> void:
	var forbidden: Array[String] = ["AppMain", "AppLocale", "AppSettings", "res://src/app/main",
		"res://src/app/locale", "res://src/app/app_settings", "TranslationServer.set_locale"]
	var files: Array[String] = []
	_ui_files("res://src/ui", files)
	assert_gt(files.size(), 10)
	for path in files:
		var code := _code_lines(path)
		for ident in forbidden:
			assert_false(code.contains(ident), "Н-5: %s ссылается на %s" % [path, ident])
	var screen_code := _code_lines("res://src/ui/settings/settings_screen.gd")
	assert_string_contains(screen_code, "AppState", "экран работает через контракт AppState")


func test_n5_language_and_navigation_go_through_app_state() -> void:
	var s := _screen()
	var events: Array[String] = []
	_state.locale_changed.connect(func(l: String) -> void: events.append(l))
	assert_true(s.set_locale("ru"))
	assert_eq(events, ["ru"] as Array[String], "смена языка — через AppState.set_locale")
	assert_eq(_settings.locale, "ru", "сохраняет модель AppState/AppSettings, не экран")
	assert_false(s.set_locale("de"))
	var main := _main()
	(main.screen_node(AppState.Screen.HOME).get_node("%SettingsButton") as Button).pressed.emit()
	assert_eq(main.app_state.current_screen, AppState.Screen.SETTINGS, "вход с Home через AppState")
	assert_true(main.visible_screen_node() is SettingsScreen)
	(main.settings_screen().get_node("%BackButton") as Button).pressed.emit()
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME)
	_drop_main(main)


# ===========================================================================
# REQ-NFR-05 / REQ-INT-01 крит. 2 — ключ не в user://settings.json и не в текстах ошибок
# ===========================================================================

func test_nfr_05_api_key_not_written_to_any_user_file_in_app() -> void:
	var main := _main()
	assert_true(main.app_state.navigate(AppState.Screen.SETTINGS))
	var s := main.settings_screen()
	_transport.enqueue_json("GET", "api/v1/athlete/" + ATHLETE_ID, 200, _athlete_json())
	var r: ApiResult = await s.submit_key(ATHLETE_ID, SECRET)
	assert_true(r.ok, "ключ принят")
	assert_eq(main.secure_store.get_secret(_api_key_id(_profile.id)), SECRET, "ключ в SecureStore")
	_transport.enqueue_json("GET", "api/v1/athlete/" + ATHLETE_ID, 200, _athlete_json())
	await s.sync_intervals()
	s.set_locale("ru")
	s.fill_profile_form("Rider", 240, 70.0, 0)
	s.save_profile()
	s.set_override_local(true)
	assert_true(FileAccess.file_exists(_dir + "settings.json"))
	var settings_text := FileAccess.get_file_as_string(_dir + "settings.json")
	assert_false(settings_text.contains(SECRET), "ключа нет в settings.json")
	var settings_data: Dictionary = JSON.parse_string(settings_text)
	for k in settings_data:
		assert_true(["schema", "locale"].has(str(k)), "settings.json содержит только язык: %s" % k)
	var b64 := Marshalls.utf8_to_base64("API_KEY:" + SECRET)
	var files: Array[String] = []
	_all_files(ProjectSettings.globalize_path(_dir), files)
	assert_gt(files.size(), 2)
	for path in files:
		var hex := FileAccess.get_file_as_bytes(path).hex_encode()
		assert_false(_hex_contains(hex, SECRET), "ключ в открытом виде в %s" % path)
		assert_false(_hex_contains(hex, b64), "ключ (base64) в %s" % path)
	_drop_main(main)


func test_nfr_05_api_key_absent_from_error_texts() -> void:
	var s := _screen()
	var texts: Array[String] = []
	var failures: Array = [
		[401, null], [403, null], [500, null], [404, null], [0, HttpResponse.ERR_OFFLINE],
	]
	for f in failures:
		if f[1] == null:
			_transport.enqueue_json("GET", "api/v1/athlete/" + ATHLETE_ID, int(f[0]), {"error": "x " + SECRET.substr(0, 3)})
		else:
			_transport.enqueue_failure("GET", "api/v1/athlete/" + ATHLETE_ID, str(f[1]))
		s.open_key_dialog()
		var r: ApiResult = await s.submit_key(ATHLETE_ID, SECRET)
		assert_false(r.ok, "ошибка %s" % str(f))
		texts.append(r.message)
		texts.append(s.key_dialog().error_text())
		texts.append(s.intervals_message_text())
		texts.append(s.intervals_status_text())
	assert_false(_store.has_secret(_api_key_id(_profile.id)), "отклонённый ключ не сохранён")
	_link()
	s.refresh()
	for f in failures:
		if f[1] == null:
			_transport.enqueue_json("GET", "api/v1/athlete/" + ATHLETE_ID, int(f[0]), {})
		else:
			_transport.enqueue_failure("GET", "api/v1/athlete/" + ATHLETE_ID, str(f[1]))
		var r2: ApiResult = await s.sync_intervals()
		assert_false(r2.ok)
		texts.append(r2.message)
		texts.append(s.intervals_message_text())
	for t in texts:
		assert_false(t.contains(SECRET), "ключ в тексте ошибки: %s" % t)
	assert_false(str(IntervalsIcuClient.for_profile(_transport, _store, _repo.get_active())).contains(SECRET))


# ===========================================================================
# REQ-NFR-08 крит. 1, 2 — строки экрана настроек через ключи strings.csv
# ===========================================================================

func test_i18n_settings_keys_exist_in_csv_with_ru_and_en() -> void:
	var re := RegEx.create_from_string('"((?:ui|error)\\.[a-z0-9_]+(?:\\.[a-z0-9_]+)+)"')
	var cyr := RegEx.create_from_string("[\\p{Cyrillic}]")
	var used: Dictionary = {}
	for path in SETTINGS_FILES:
		var code := _code_lines(path)
		assert_null(cyr.search(code), "кириллица в литералах %s" % path)
		for m in re.search_all(code):
			used[m.get_string(1)] = path
	assert_gt(used.size(), 40, "ключи экрана найдены")
	for key in used:
		assert_true(_csv.has(key), "ключ %s (%s) отсутствует в strings*.csv" % [key, used[key]])
		for locale in ["ru", "en"]:
			assert_false(_csv_text(key, locale).strip_edges().is_empty(), "пустой перевод %s [%s]" % [key, locale])


func test_i18n_every_profile_error_code_shown_by_settings_has_translation() -> void:
	var codes: Array[String] = []
	for script: Script in [Profile, ProfileRepository]:
		var consts: Dictionary = script.get_script_constant_map()
		for name in consts:
			if str(name).begins_with("ERR_"):
				codes.append(str(consts[name]))
	assert_gt(codes.size(), 12)
	for code in codes:
		var key := SettingsScreen.ERROR_KEY_PREFIX + code
		assert_true(_csv.has(key), "нет перевода для кода %s (ключ %s)" % [code, key])


func test_i18n_settings_texts_never_show_raw_keys_in_both_languages() -> void:
	_link()
	var s := _screen()
	for locale in ["en", "ru"]:
		s.set_locale(locale)
		var stack: Array[Node] = [s]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for c in n.get_children(true):
				stack.append(c)
			if n is StravaConnectButton or (n.get_parent() != null and n.get_parent() is StravaConnectButton):
				continue
			if n is Label or n is Button:
				var t := str(n.get("text"))
				if not (t.begins_with("ui.") or t.begins_with("error.")):
					continue
				# Ключ в `text` допустим только у узла с автопереводом: на экран выводится перевод.
				assert_true(n.can_auto_translate(), "сырой ключ без автоперевода в %s [%s]: %s" % [n.get_path(), locale, t])
				assert_eq(TranslationServer.translate(t), _csv_text(t, locale), "перевод ключа %s [%s]" % [t, locale])


func test_i18n_sync_warning_message_is_translated_not_raw_codes() -> void:
	_link()
	var s := _screen()
	_transport.enqueue_json("GET", "api/v1/athlete/" + ATHLETE_ID, 200,
		_athlete_variant(null, [55, 75, 90, 105, 120, 150, 999], [115, 134, 153, 172, 182, 192], 192))
	var r: ApiResult = await s.sync_intervals()
	assert_true(r.ok)
	var msg := s.intervals_message_text()
	assert_false(msg.is_empty(), "предупреждение показано")
	assert_false(msg.contains(IntervalsSync.WARN_FTP_MISSING),
		"в UI машинный код предупреждения вместо переведённого текста: «%s»" % msg)


# ===========================================================================
# REQ-INT-01 крит. 3 (вне списка T-057, компонент T-057) — «ключ не принят» видно в диалоге
# ===========================================================================

func test_req_int_01_c3_rejected_key_message_visible_after_ok_in_dialog() -> void:
	var s := _screen()
	_transport.enqueue_json("GET", "api/v1/athlete/" + ATHLETE_ID, 401, {"error": "unauthorized"})
	s.open_key_dialog()
	var dialog := s.key_dialog()
	assert_true(dialog.visible, "диалог открыт")
	dialog.fill(ATHLETE_ID, "bad-key")
	dialog.get_ok_button().pressed.emit()  # пользователь нажимает «Проверить и сохранить»
	for i in 3:
		await get_tree().process_frame
	assert_eq(_transport.request_count("GET", "api/v1/athlete/" + ATHLETE_ID), 1, "проверочный запрос ушёл")
	assert_false(_store.has_secret(_api_key_id(_profile.id)), "ключ не сохранён")
	assert_ne(dialog.error_text(), "", "текст ошибки выставлен")
	assert_true(dialog.visible, "диалог с сообщением «ключ не принят» должен остаться на экране, факт: скрыт")
