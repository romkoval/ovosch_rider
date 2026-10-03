extends GutTest
## Интеграционные тесты экрана настроек (REQ-NFR-08 крит. 3, 4; REQ-PRF-02 крит. 1;
## REQ-INT-06 крит. 4–6 (крит. 7 — ручная проверка; источник значений на экране проверяется попутно);
## REQ-WRK-04 крит. 1; REQ-DEV-05 крит. 2; REQ-PRF-03 крит. 2).

const SCENE: String = "res://src/ui/settings/settings_screen.tscn"
const MAIN_SCENE: String = "res://src/app/main.tscn"
const ATHLETE_FIXTURE: String = "res://tests/fixtures/intervals/athlete.json"

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


func before_each() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_dir = "user://test_settings_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_repo = ProfileRepository.new(_dir + "profiles/")
	_profile = _repo.create("Rider")
	_settings = AppSettings.new(_dir + "settings.json")
	_state = AppState.new(_repo, _settings)
	_state.start()
	_store = MemorySecureStore.new()
	_transport = MockHttpTransport.new()
	_bridge = StubBleBridge.new()
	_devices = RememberedDevices.new(_dir + "devices/")
	_cm = ConnectionManager.new(_bridge, _devices)


func after_each() -> void:
	TranslationServer.set_locale(_previous_locale)
	if _cm != null:
		_cm.dispose()
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


func _screen() -> SettingsScreen:
	var s: SettingsScreen = load(SCENE).instantiate()
	s.setup(_repo, _state, _store, _transport, _cm)
	add_child_autofree(s)
	return s


func _athlete_json() -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(ATHLETE_FIXTURE))


func _link(athlete_id: String = "i12345") -> void:
	_store.set_secret(SecureStore.key_for(_profile.id, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY), "secret-key")
	var p := _repo.get_active().duplicate_profile()
	p.intervals_athlete_id = athlete_id
	_repo.save(p)


func _main() -> AppMain:
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.transport = _transport
	add_child_autofree(main)
	return main


# ---------------------------------------------------------------------------
# Язык (REQ-NFR-08 крит. 3, 4)
# ---------------------------------------------------------------------------

func test_initial_render_in_english() -> void:
	var s := _screen()
	assert_eq((s.get_node("%SaveProfileButton") as Button).text, "Save profile")
	assert_eq(s.profile_status_text(), "Profile: Rider")
	assert_eq(s.intervals_status_text(), "Intervals.icu not linked")
	assert_eq((s.get_node("%LocaleOption") as OptionButton).get_item_text(0), "English")


func test_switching_language_changes_texts_without_restart_and_persists() -> void:
	var s := _screen()
	var emitted: Array[String] = []
	_state.locale_changed.connect(func(l: String) -> void: emitted.append(l))
	assert_true(s.set_locale("ru"))
	assert_eq(TranslationServer.get_locale(), "ru")
	assert_eq((s.get_node("%SaveProfileButton") as Button).text, "Сохранить профиль", "REQ-NFR-08 крит. 4: без перезапуска")
	assert_eq(s.profile_status_text(), "Профиль: Rider")
	assert_eq(emitted, ["ru"] as Array[String], "AppState.locale_changed для других экранов")
	assert_eq(_settings.locale, "ru")
	assert_eq(AppSettings.load_from(_settings.path()).locale, "ru", "REQ-NFR-08 крит. 3: сохранено на диск")
	assert_false(s.set_locale("de"), "неподдерживаемый язык отклонён")
	assert_eq(TranslationServer.get_locale(), "ru")
	assert_eq(_state.locale(), "ru")
	assert_eq(_state.settings(), _settings, "язык сохраняет AppState, а не экран (Н-5)")


func test_locale_option_selection_applies_language() -> void:
	var s := _screen()
	var option := s.get_node("%LocaleOption") as OptionButton
	option.select(1)
	option.item_selected.emit(1)
	assert_eq(TranslationServer.get_locale(), "ru")
	assert_eq(option.get_item_text(0), "Английский", "подписи самого списка переведены")


func test_main_rerenders_home_on_locale_change_and_boots_with_saved_locale() -> void:
	var main := _main()
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME)
	var home := main.screen_node(AppState.Screen.HOME) as HomeScreen
	assert_eq(home.active_profile_text(), "Profile: Rider")
	assert_true(main.app_state.navigate(AppState.Screen.SETTINGS))
	assert_true(main.visible_screen_node() is SettingsScreen, "экран настроек вместо заглушки")
	main.settings_screen().set_locale("ru")
	assert_eq(home.active_profile_text(), "Профиль: Rider", "Home перерисован по locale_changed")
	assert_eq(main.app_settings.locale, "ru")
	main.queue_free()
	remove_child(main)
	TranslationServer.set_locale("en")
	var again := _main()
	assert_eq(TranslationServer.get_locale(), "ru", "новый main стартует на сохранённом языке")
	assert_eq((again.screen_node(AppState.Screen.HOME) as HomeScreen).active_profile_text(), "Профиль: Rider")


# ---------------------------------------------------------------------------
# Профиль (REQ-PRF-02 крит. 1, REQ-WRK-04 крит. 1, REQ-DEV-05 крит. 2)
# ---------------------------------------------------------------------------

func test_form_prefilled_from_active_profile() -> void:
	var p := _repo.get_active().duplicate_profile()
	p.ftp_w = 230
	p.weight_kg = 81.5
	p.max_hr = 185
	p.resistance_level_default = 35
	p.power_source = Profile.POWER_SOURCE_POWER_METER
	_repo.save(p)
	var s := _screen()
	assert_eq((s.get_node("%NameEdit") as LineEdit).text, "Rider")
	assert_eq(int((s.get_node("%FtpSpin") as SpinBox).value), 230)
	assert_almost_eq((s.get_node("%WeightSpin") as SpinBox).value, 81.5, 1e-6)
	assert_eq(int((s.get_node("%MaxHrSpin") as SpinBox).value), 185)
	assert_eq(int((s.get_node("%ResistanceSpin") as SpinBox).value), 35)
	assert_eq((s.get_node("%PowerSourceOption") as OptionButton).selected, 1)


func test_ftp_601_rejected_with_translated_error_and_nothing_saved() -> void:
	var s := _screen()
	s.fill_profile_form("Rider", 601, 75.0, 0)
	var errors := s.save_profile()
	assert_eq(errors, [Profile.ERR_FTP_OUT_OF_RANGE] as Array[String])
	assert_eq(s.profile_error_text(), "FTP must be between 50 and 600 W", "REQ-PRF-02 крит. 1: ошибка по коду")
	assert_eq(_repo.get_active().ftp_w, 200, "в репозитории прежнее значение")
	assert_eq(ProfileRepository.new(_dir + "profiles/").get_active().ftp_w, 200)


func test_ftp_250_saved_and_visible_to_new_repository_instance() -> void:
	var s := _screen()
	s.fill_profile_form("Rider", 250, 76.3, 180, 40, Profile.POWER_SOURCE_TRAINER)
	assert_eq(s.save_profile().size(), 0)
	assert_eq(s.profile_error_text(), "")
	assert_eq(s.profile_status_text(), "Profile “Rider” saved")
	var fresh := ProfileRepository.new(_dir + "profiles/").get_active()
	assert_eq(fresh.ftp_w, 250)
	assert_almost_eq(fresh.weight_kg, 76.3, 1e-6)
	assert_eq(fresh.max_hr, 180)
	assert_eq(fresh.resistance_level_default, 40, "REQ-WRK-04 крит. 1: уровень по умолчанию сохранён")


func test_manual_ftp_edit_resets_source_to_local() -> void:
	var p := _repo.get_active().duplicate_profile()
	p.ftp_w = 250
	p.ftp_source = "intervals:2026-10-01"
	_repo.save(p)
	var s := _screen()
	assert_string_contains(s.sources_text(), "Intervals.icu as of 2026-10-01")
	s.fill_profile_form("Rider", 255, 75.0, 0)
	assert_eq(s.save_profile().size(), 0)
	assert_eq(_repo.get_active().ftp_source, Profile.SOURCE_LOCAL, "REQ-INT-06 крит. 4")
	assert_string_contains(s.sources_text(), "FTP source: local")
	# Сохранение без изменения FTP источник не трогает.
	p = _repo.get_active().duplicate_profile()
	p.ftp_source = "intervals:2026-10-02"
	_repo.save(p)
	s.refresh()
	s.fill_profile_form("Rider", 255, 80.0, 0)
	s.save_profile()
	assert_eq(_repo.get_active().ftp_source, "intervals:2026-10-02", "FTP не менялся — источник сохранён")


func test_max_hr_zero_marks_hr_zones_unavailable() -> void:
	var s := _screen()
	assert_eq(s.hr_zones_text(), "Heart-rate zones unavailable: set max heart rate or sync zones", "REQ-PRF-02 крит. 4")
	s.fill_profile_form("Rider", 200, 75.0, 180)
	s.save_profile()
	assert_eq(s.hr_zones_text(), "Heart-rate zones available")
	s.fill_profile_form("Rider", 200, 75.0, 0)
	s.save_profile()
	assert_eq(s.hr_zones_text(), "Heart-rate zones unavailable: set max heart rate or sync zones")
	assert_false(_repo.get_active().has_hr_zones())


func test_power_source_saved_and_applied_to_hub() -> void:
	var s := _screen()
	assert_eq(_cm.hub.power_source, SensorHub.SOURCE_TRAINER)
	s.fill_profile_form("Rider", 200, 75.0, 0, 50, Profile.POWER_SOURCE_POWER_METER)
	assert_eq(s.save_profile().size(), 0)
	assert_eq(_cm.hub.power_source, SensorHub.SOURCE_POWER_METER, "REQ-DEV-05 крит. 2 / Н-8: hub.set_power_source")
	assert_eq(ProfileRepository.new(_dir + "profiles/").get_active().power_source, Profile.POWER_SOURCE_POWER_METER, "сохранено в профиле")
	s.fill_profile_form("Rider", 200, 75.0, 0, 50, Profile.POWER_SOURCE_TRAINER)
	s.save_profile()
	assert_eq(_cm.hub.power_source, SensorHub.SOURCE_TRAINER)


func test_main_applies_profile_power_source_on_profile_selection() -> void:
	var p := _repo.get_active().duplicate_profile()
	p.power_source = Profile.POWER_SOURCE_POWER_METER
	_repo.save(p)
	var main := _main()
	assert_eq(main.connections.hub.power_source, SensorHub.SOURCE_POWER_METER, "при выборе профиля источник применён к хабу")


func test_name_and_weight_validation_errors_listed() -> void:
	var s := _screen()
	s.fill_profile_form("   ", 200, 10.0, 0)
	var errors := s.save_profile()
	assert_has(errors, Profile.ERR_NAME_EMPTY)
	assert_has(errors, Profile.ERR_WEIGHT_OUT_OF_RANGE)
	assert_string_contains(s.profile_error_text(), "Enter a profile name")
	assert_string_contains(s.profile_error_text(), "Weight must be between 20 and 250 kg")


# ---------------------------------------------------------------------------
# Intervals.icu (REQ-INT-06 крит. 5, 6, REQ-PRF-03 крит. 2)
# ---------------------------------------------------------------------------

func test_intervals_status_and_buttons_follow_link_state() -> void:
	var s := _screen()
	assert_eq(s.intervals_status_text(), "Intervals.icu not linked")
	assert_true((s.get_node("%IntervalsSyncButton") as Button).disabled)
	assert_true((s.get_node("%IntervalsForgetButton") as Button).disabled)
	assert_false((s.get_node("%IntervalsKeyButton") as Button).disabled)
	_link()
	s.refresh()
	assert_eq(s.intervals_status_text(), "Intervals.icu linked (athlete i12345)", "статус привязки к Intervals.icu")
	assert_false((s.get_node("%IntervalsSyncButton") as Button).disabled)
	assert_false((s.get_node("%IntervalsForgetButton") as Button).disabled)


func test_sync_applies_ftp_250_and_intervals_source() -> void:
	_link()
	_transport.enqueue_json("GET", "api/v1/athlete/i12345", 200, _athlete_json())
	var s := _screen()
	var result: ApiResult = await s.sync_intervals()
	assert_true(result.ok)
	var p := _repo.get_active()
	assert_eq(p.ftp_w, 250, "REQ-INT-06 крит. 6: без переопределения синхронизация обновляет FTP")
	assert_true(p.ftp_source.begins_with("intervals:"), "источник intervals:<дата>, факт %s" % p.ftp_source)
	assert_eq(p.ftp_source, "intervals:" + IntervalsIcuClient.local_date())
	assert_true(p.zones_source.begins_with("intervals:"))
	assert_eq(p.max_hr, 192)
	assert_true(p.has_hr_zones())
	assert_string_contains(s.sources_text(), "Intervals.icu as of")
	assert_string_contains(s.intervals_message_text(), "Profile updated from Intervals.icu")
	assert_eq(_transport.request_count("GET", "api/v1/athlete/i12345"), 1)
	assert_eq(s.hr_zones_text(), "Heart-rate zones available")


func test_sync_with_override_local_keeps_ftp() -> void:
	_link()
	var p := _repo.get_active().duplicate_profile()
	p.intervals_override_local = true
	_repo.save(p)
	_transport.enqueue_json("GET", "api/v1/athlete/i12345", 200, _athlete_json())
	var s := _screen()
	assert_true((s.get_node("%OverrideCheck") as CheckButton).button_pressed)
	var result: ApiResult = await s.sync_intervals()
	assert_true(result.ok)
	assert_eq(_repo.get_active().ftp_w, 200, "REQ-INT-06 крит. 5: переопределение локально — FTP не меняется")
	assert_eq(_repo.get_active().ftp_source, Profile.SOURCE_LOCAL)
	assert_eq(s.intervals_message_text(), "Sync skipped: local override is enabled")


func test_override_toggle_persists_in_profile() -> void:
	var s := _screen()
	s.set_override_local(true)
	assert_true(_repo.get_active().intervals_override_local, "REQ-INT-06 крит. 5: флаг переопределения сохранён")
	assert_true(ProfileRepository.new(_dir + "profiles/").get_active().intervals_override_local)
	s.set_override_local(false)
	assert_false(_repo.get_active().intervals_override_local)


func test_sync_failure_shows_code_and_keeps_profile() -> void:
	_link()
	_transport.enqueue_json("GET", "api/v1/athlete/i12345", 401, {"error": "unauthorized"})
	var s := _screen()
	var result: ApiResult = await s.sync_intervals()
	assert_false(result.ok)
	assert_eq(_repo.get_active().ftp_w, 200)
	assert_eq(s.intervals_message_text(), "Sync failed: Intervals.icu key rejected",
		"REQ-NFR-08 крит. 1: причина переведена, а не сырой код")
	assert_false(s.intervals_message_text().contains(result.code))


func test_sync_not_configured_without_key() -> void:
	var s := _screen()
	var result: ApiResult = await s.sync_intervals()
	assert_false(result.ok)
	assert_eq(result.code, ApiResult.CODE_NOT_CONFIGURED)
	assert_eq(_transport.request_count(), 0, "запросов не было")


func test_forget_removes_key_from_secure_store_and_keeps_sources() -> void:
	_link()
	var p := _repo.get_active().duplicate_profile()
	p.ftp_source = "intervals:2026-10-01"
	_repo.save(p)
	var s := _screen()
	s.forget_intervals()
	assert_eq(_store.size(), 0, "REQ-PRF-03 крит. 2: ключ удалён")
	assert_eq(_repo.get_active().intervals_athlete_id, "")
	assert_eq(s.intervals_status_text(), "Intervals.icu not linked")
	assert_eq(s.intervals_message_text(), "Intervals.icu key removed")
	assert_eq(_repo.get_active().ftp_source, "intervals:2026-10-01", "источник FTP при отвязке не сбрасывается")


func test_key_dialog_verifies_and_stores_key() -> void:
	_transport.enqueue_json("GET", "api/v1/athlete/i12345", 200, _athlete_json())
	var s := _screen()
	s.open_key_dialog()
	var dialog := s.key_dialog()
	dialog.fill("i12345", "my-secret")
	var result: ApiResult = await s.submit_key(dialog.athlete_id(), dialog.key())
	assert_true(result.ok)
	assert_eq(_store.get_secret(SecureStore.key_for(_profile.id, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY)), "my-secret")
	assert_eq(_repo.get_active().intervals_athlete_id, "i12345")
	assert_eq(s.intervals_status_text(), "Intervals.icu linked (athlete i12345)")
	assert_eq(s.intervals_message_text(), "Key saved: Test Athlete", "REQ-INT-01 крит. 4: имя атлета из ответа")
	assert_false(dialog.visible, "диалог закрыт после успеха")
	assert_eq(_transport.last_request()["headers"].get("Authorization", "").is_empty(), false, "ключ ушёл в заголовке")


func test_key_dialog_rejected_key_shows_error_and_stores_nothing() -> void:
	_transport.enqueue_json("GET", "api/v1/athlete/i12345", 401, {"error": "unauthorized"})
	var s := _screen()
	s.open_key_dialog()
	var result: ApiResult = await s.submit_key("i12345", "bad")
	assert_false(result.ok)
	assert_eq(_store.size(), 0, "REQ-INT-01 крит. 3: ключ не сохраняется")
	assert_eq(s.key_dialog().error_text(), "Key rejected by Intervals.icu: check the Athlete ID and API key")
	assert_eq(s.intervals_status_text(), "Intervals.icu not linked")


func test_key_dialog_ok_button_keeps_dialog_open_with_error_until_success() -> void:
	_transport.enqueue_json("GET", "api/v1/athlete/i12345", 401, {"error": "unauthorized"})
	var s := _screen()
	s.open_key_dialog()
	var dialog := s.key_dialog()
	dialog.fill("i12345", "bad")
	dialog.get_ok_button().pressed.emit()
	for i in 3:
		await get_tree().process_frame
	assert_eq(_transport.request_count("GET", "api/v1/athlete/i12345"), 1)
	assert_true(dialog.visible, "REQ-INT-01 крит. 3: диалог с ошибкой остаётся открытым")
	assert_eq(dialog.error_text(), "Key rejected by Intervals.icu: check the Athlete ID and API key")
	assert_eq(_store.size(), 0)
	# Повторная попытка с верным ключом закрывает диалог.
	_transport.enqueue_json("GET", "api/v1/athlete/i12345", 200, _athlete_json())
	dialog.fill("i12345", "good")
	dialog.get_ok_button().pressed.emit()
	for i in 3:
		await get_tree().process_frame
	assert_false(dialog.visible, "диалог закрыт после успешной проверки")
	assert_eq(dialog.error_text(), "")
	assert_eq(_repo.get_active().intervals_athlete_id, "i12345")


func test_key_dialog_empty_fields_show_fill_both_message_without_request() -> void:
	var s := _screen()
	s.open_key_dialog()
	var result: ApiResult = await s.submit_key("", "")
	assert_false(result.ok)
	assert_eq(_transport.request_count(), 0)
	assert_eq(s.key_dialog().error_text(), "Enter Athlete ID and API key")
	assert_true(s.key_dialog().visible)


func test_key_dialog_network_error_translated_without_raw_code() -> void:
	_transport.enqueue_failure("GET", "api/v1/athlete/i12345", HttpResponse.ERR_OFFLINE)
	var s := _screen()
	s.open_key_dialog()
	var result: ApiResult = await s.submit_key("i12345", "key")
	assert_false(result.ok)
	assert_eq(s.key_dialog().error_text(), "Could not verify the key: no connection to Intervals.icu")
	assert_false(s.key_dialog().error_text().contains(result.code))


func test_sync_warnings_translated_in_both_languages() -> void:
	_link()
	var s := _screen()
	var athlete: Dictionary = _athlete_json()
	var ss: Array = athlete.get("sportSettings", [])
	for entry in ss:
		(entry as Dictionary).erase("ftp")
		(entry as Dictionary).erase("indoor_ftp")
	_transport.enqueue_json("GET", "api/v1/athlete/i12345", 200, athlete)
	var result: ApiResult = await s.sync_intervals()
	assert_true(result.ok)
	assert_string_contains(s.intervals_message_text(), "Synced with warnings: ")
	assert_string_contains(s.intervals_message_text(), "FTP is not set in Intervals.icu")
	assert_false(s.intervals_message_text().contains(IntervalsSync.WARN_FTP_MISSING), "без сырого кода")
	s.set_locale("ru")
	assert_string_contains(s.intervals_message_text(), "FTP не задан в Intervals.icu")


func test_locale_switch_and_override_toggle_keep_unsaved_form_input() -> void:
	var s := _screen()
	s.fill_profile_form("Draft", 333, 66.6, 177)
	s.set_locale("ru")
	assert_eq((s.get_node("%NameEdit") as LineEdit).text, "Draft", "смена языка не затирает ввод")
	assert_eq(int((s.get_node("%FtpSpin") as SpinBox).value), 333)
	s.set_override_local(true)
	assert_eq((s.get_node("%NameEdit") as LineEdit).text, "Draft", "переключатель не затирает ввод")
	assert_eq(int((s.get_node("%MaxHrSpin") as SpinBox).value), 177)
	assert_true(_repo.get_active().intervals_override_local)
	assert_eq(_repo.get_active().ftp_w, 200, "в профиль ничего не записано")
	s.refresh()
	assert_eq((s.get_node("%NameEdit") as LineEdit).text, "Rider", "явный refresh() заполняет форму из профиля")
	assert_eq(int((s.get_node("%FtpSpin") as SpinBox).value), 200)


func test_main_locale_switch_keeps_unsaved_form_input() -> void:
	# Ревью MEDIUM-4: `main._on_locale_changed` не затирает несохранённый ввод формы.
	var main := _main()
	assert_true(main.app_state.navigate(AppState.Screen.SETTINGS))
	var s := main.settings_screen()
	s.fill_profile_form("Draft", 333, 66.6, 177)
	var option := s.get_node("%LocaleOption") as OptionButton
	option.select(1)
	option.item_selected.emit(1)
	assert_eq(TranslationServer.get_locale(), "ru")
	assert_eq((s.get_node("%SaveProfileButton") as Button).text, "Сохранить профиль", "тексты переведены")
	assert_eq(int((s.get_node("%FtpSpin") as SpinBox).value), 333, "введённый FTP остался в поле")
	assert_eq((s.get_node("%NameEdit") as LineEdit).text, "Draft")
	assert_eq(int((s.get_node("%MaxHrSpin") as SpinBox).value), 177)
	assert_eq(main.repo.get_active().ftp_w, 200, "в профиль ничего не записано")

func test_main_env_reader_is_injectable_for_strava_config() -> void:
	# Ревью инфраструктуры: окружение машины не влияет на тесты через main.tscn —
	# читатель окружения подменяется до входа в дерево.
	var env := {StravaConfig.ENV_CLIENT_ID: "12345", StravaConfig.ENV_CLIENT_SECRET: "env-secret-value"}
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.transport = _transport
	main.env_reader = func(name: String) -> String: return str(env.get(name, ""))
	add_child_autofree(main)
	assert_not_null(main.strava)
	assert_true(main.strava.is_configured(), "значения — из подменённого окружения")
	assert_eq(main.strava.config.source, StravaConfig.SOURCE_ENVIRONMENT)
	assert_eq(main.strava.config.client_id, "12345")
	var isolated: AppMain = load(MAIN_SCENE).instantiate()
	isolated.data_dir = _dir
	isolated.transport = _transport
	isolated.env_reader = func(_name: String) -> String: return ""
	add_child_autofree(isolated)
	assert_ne(isolated.strava.config.source, StravaConfig.SOURCE_ENVIRONMENT, "пустое окружение — не источник настроек")


func test_main_env_reader_defaults_to_system_environment() -> void:
	var main: AppMain = load(MAIN_SCENE).instantiate()
	assert_true(main.env_reader.is_valid(), "по умолчанию окружение читается")
	assert_eq(main.env_reader.call("PATH"), SecureStore.read_env("PATH"))
	main.free()

# ---------------------------------------------------------------------------
# Strava, «О программе», навигация
# ---------------------------------------------------------------------------

func test_strava_placeholder_and_about() -> void:
	var s := _screen()
	assert_eq(s.strava_status_text(), "Strava not linked")
	var strava := s.strava_button()
	assert_not_null(strava, "компонент StravaConnectButton (T-049) встроен в раздел Strava")
	assert_true(strava.is_button_disabled(), "без StravaService привязка недоступна — кнопка выключена")
	assert_false(strava.is_authorized())
	assert_eq(strava.button_text(), "Connect with Strava", "REQ-STR-01 крит. 7: текст по брендбуку")
	assert_eq(s.version_text(), "ovosch-rider " + str(ProjectSettings.get_setting("application/config/version")))
	assert_string_contains(s.licenses_text(), "Godot Engine — MIT")
	assert_string_contains(s.licenses_text(), "GUT (Godot Unit Test) — MIT")
	assert_string_contains(s.licenses_text(), "godot-cpp — MIT")
	assert_string_contains(s.licenses_text(), SettingsScreen.LICENSES_DOC)


func test_back_and_switch_profile_navigation() -> void:
	var s := _screen()
	_state.navigate(AppState.Screen.SETTINGS)
	(s.get_node("%BackButton") as Button).pressed.emit()
	assert_eq(_state.current_screen, AppState.Screen.HOME)
	(s.get_node("%SwitchProfileButton") as Button).pressed.emit()
	assert_eq(_state.current_screen, AppState.Screen.PROFILE_SELECT, "REQ-PRF-01 крит. 4: удаление — на экране выбора")
