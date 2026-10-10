extends GutTest
## T-160: заезды на эмуляторе в приложении (`main.tscn`). REQ-STR-04 крит. 1 (без автовыгрузки,
## Н-52 (а), Н-59), крит. 5 (ручная выгрузка — через диалог подтверждения), REQ-UIX-04 крит. 3
## (метка «Эмулятор» рядом с меткой режима в строке истории и в карточке), REQ-NFR-08 (ru/en без
## переполнения); регрессия REQ-STR-05 крит. 1, 2, REQ-LOC-02 крит. 1.

const MAIN_SCENE: String = "res://src/app/main.tscn"
const HISTORY_SCENE: String = "res://src/ui/history/history_screen.tscn"
## 2026-10-02 12:00 UTC.
const STARTED: int = 1_790_942_400

var _dir: String
var _profiles: ProfileRepository
var _profile: Profile
var _mains: Array[AppMain] = []
var _locale_before: String


func before_each() -> void:
	_locale_before = TranslationServer.get_locale()
	_dir = "user://test_emulator_rides_ui_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	_write_locale("ru")
	_profiles = ProfileRepository.new(_dir + "profiles/")
	_profile = _profiles.create("Даша")
	_profile.ftp_w = 200
	_profiles.save(_profile)
	_mains = []


func after_each() -> void:
	for m in _mains:
		if is_instance_valid(m):
			if m.get_parent() != null:
				m.get_parent().remove_child(m)
			m.free()
	_mains = []
	TranslationServer.set_locale(_locale_before)
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


# ---------------------------------------------------------------------------
# Окружение
# ---------------------------------------------------------------------------

func _write_locale(locale: String) -> void:
	var s := AppSettings.new(_dir + "settings.json")
	s.locale = locale
	s.save()


## Привязка Strava до запуска: токены в том же защищённом хранилище, что откроет `main`.
func _prelink(profile_id: String) -> void:
	var store := SecureStore.create_default(_dir + "secure/")
	var now := int(Time.get_unix_time_from_system())
	store.set_secret(SecureStore.key_for(profile_id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN), "fixture-access-token")
	store.set_secret(SecureStore.key_for(profile_id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_REFRESH_TOKEN), "fixture-refresh-token")
	store.set_secret(SecureStore.key_for(profile_id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_EXPIRES_AT), str(now + 36000))


func _main() -> AppMain:
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	add_child(main)
	main.set_process(false)
	_mains.append(main)
	return main


static func _short_workout(name: String) -> Workout:
	return Workout.make(name, [
		WorkoutStep.percent(20, 55.0, WorkoutStep.StepKind.WARMUP),
		WorkoutStep.percent(15, 100.0, WorkoutStep.StepKind.INTERVAL_ON),
		WorkoutStep.percent(10, 50.0, WorkoutStep.StepKind.COOLDOWN),
	] as Array[WorkoutStep])


## Тренировка на эмуляторе приложения до естественного завершения: id заезда.
func _ride_on_emulator(main: AppMain, workout: Workout) -> String:
	assert_true(main.start_workout_on_emulator(workout), "тренировка на эмуляторе запущена")
	var session := main.workout_screen().session()
	var guard := 0
	while session.get_state() != WorkoutSession.State.FINISHED and guard < 5000:
		session.tick(1.0)
		guard += 1
	assert_eq(session.get_state(), WorkoutSession.State.FINISHED)
	return main.ride_recorder.ride_id()


## Завершённый заезд на реальном станке (источник `ble`) или без поля (`source` пусто).
func _ride(profile_id: String, name: String, started: int, source: String, n: int = 20) -> Ride:
	var r := Ride.new()
	r.id = Ride.generate_id(started)
	r.profile_id = profile_id
	r.started_at_unix = started
	r.name = name
	r.workout = Workout.make(name, [WorkoutStep.watts(n, 200.0)] as Array[WorkoutStep]).to_dict()
	r.metadata = {"ftp_w": 200, "weight_kg": 75.0, "max_hr": 185, "speed_source": Ride.SPEED_SOURCE_TRAINER_LEGACY,
		"stopped_early": false, "elapsed_sec": n, "paused_total_sec": 0.0, "in_progress": false, "recovered": false}
	if not source.is_empty():
		r.metadata[Ride.KEY_TRAINER_SOURCE] = source
	r.samples.speed_source = Ride.SPEED_SOURCE_TRAINER_LEGACY
	for i in n:
		r.samples.append(i, TrainerSample.full(float(i + 1), 200, 88, 36.0), 140, 200, 0, true)
	r.events = [{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0}]
	r.compute_summary()
	return r


static func _confirm_dialog(detail: RideDetail) -> ConfirmationDialog:
	return detail.get_node("%UploadEmulatorDialog") as ConfirmationDialog


# ---------------------------------------------------------------------------
# REQ-STR-04 крит. 1: без автовыгрузки; регрессия — заезд на станке в очереди
# ---------------------------------------------------------------------------

func test_req_str_04_c1_emulator_ride_not_queued_real_ride_queued() -> void:
	_prelink(_profile.id)
	var main := _main()
	assert_true(main.strava.is_authorized(), "предусловие: Strava привязана")
	var emu_id := _ride_on_emulator(main, _short_workout("Sweet Spot"))
	assert_false(emu_id.is_empty())
	var emu := main.ride_repository.get_ride(emu_id)
	assert_true(emu.is_emulator(), "заезд на эмуляторе помечен источником")
	assert_eq(main.strava.queue.size(), 0, "очередь пуста")
	assert_eq(str(emu.upload["strava_status"]), Ride.UPLOAD_NONE, "статус «не выгружен»")
	var real := _ride(_profile.id, "Real", STARTED, Ride.TRAINER_SOURCE_BLE)
	main.ride_repository.save(real)
	assert_true(main.strava.queue.has(real.id), "заезд на станке — в очереди (регрессия T-049)")
	var legacy := _ride(_profile.id, "Legacy", STARTED + 100, "")
	main.ride_repository.save(legacy)
	assert_true(main.strava.queue.has(legacy.id), "заезд без поля — как раньше")
	assert_eq(main.strava.queue.size(), 2)
	assert_eq(_mock_posts(main), 0, "выгрузка — только шагом очереди")


func _mock_posts(main: AppMain) -> int:
	return (main.transport as MockHttpTransport).request_count("POST")


# ---------------------------------------------------------------------------
# REQ-UIX-04 крит. 3: метка «Эмулятор» в строке истории и в карточке
# ---------------------------------------------------------------------------

func test_req_uix_04_c3_history_row_and_card_show_emulator_label() -> void:
	var main := _main()
	var emu_id := _ride_on_emulator(main, _short_workout("Sweet Spot"))
	var real := _ride(_profile.id, "Real", STARTED, Ride.TRAINER_SOURCE_BLE)
	main.ride_repository.save(real)
	var legacy := _ride(_profile.id, "Legacy", STARTED - 100, "")
	main.ride_repository.save(legacy)
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	assert_eq(history.row_count(), 3)
	history.ensure_row(2)
	assert_eq(history.row_emulator_text(emu_id), "Эмулятор", "строка заезда на эмуляторе — с меткой")
	assert_eq(history.row_emulator_text(real.id), "", "у заезда на станке метки нет")
	assert_eq(history.row_emulator_text(legacy.id), "", "у старого заезда метки нет")
	var row := history.row_for(emu_id)
	var mode := row.leading_slot().get_child(0) as Label
	var badge := row.leading_slot().get_child(1) as Label
	assert_eq(mode.text, HistoryFormat.mode_text(false), "метка режима на месте, первой")
	assert_eq(badge.theme_type_variation, &"OverlineLabel", "метка — Overline, как метка режима")
	assert_true(badge.uppercase, "Overline заглавными")
	assert_eq(row.leading_slot().get_child_count(), 2, "рядом с меткой режима")
	assert_eq(history.row_for(real.id).leading_slot().get_child_count(), 1, "у обычного заезда — только режим")
	assert_true(history.show_ride(emu_id))
	var detail := history.detail()
	assert_eq(detail.emulator_text(), "Эмулятор", "карточка заезда на эмуляторе — с меткой")
	assert_true((detail.get_node("%EmulatorLabel") as Label).visible)
	assert_true(history.show_ride(real.id))
	assert_eq(detail.emulator_text(), "", "у заезда на станке метки нет")
	assert_false((detail.get_node("%EmulatorLabel") as Label).visible)
	assert_true(history.show_ride(legacy.id))
	assert_eq(detail.emulator_text(), "")


# ---------------------------------------------------------------------------
# REQ-STR-04 крит. 5: ручная выгрузка заезда на эмуляторе — через подтверждение
# ---------------------------------------------------------------------------

func test_req_str_04_c5_manual_upload_of_emulator_ride_asks_confirmation() -> void:
	_prelink(_profile.id)
	var main := _main()
	var emu_id := _ride_on_emulator(main, _short_workout("Sweet Spot"))
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	assert_true(history.show_ride(emu_id))
	var detail := history.detail()
	var button := detail.get_node("%UploadButton") as Button
	assert_false(button.disabled, "ручная выгрузка доступна")
	var dialog := _confirm_dialog(detail)
	button.pressed.emit()
	assert_true(detail.is_upload_confirmation_pending(), "показан диалог подтверждения")
	assert_true(dialog.visible)
	assert_eq(dialog.dialog_text, tr("ui.history.upload_emulator.text"))
	assert_string_contains(dialog.dialog_text, "эмулятор")
	assert_eq(dialog.get_ok_button().theme_type_variation, DialogLayout.DANGER_VARIATION, "«Выгрузить» — опасная кнопка")
	assert_eq(main.strava.queue.size(), 0, "до подтверждения очередь пуста")
	dialog.get_cancel_button().pressed.emit()
	assert_false(detail.is_upload_confirmation_pending(), "«Отмена» закрыла подтверждение")
	assert_false(dialog.visible)
	assert_eq(main.strava.queue.size(), 0, "«Отмена» — очередь пуста")
	assert_eq(str(main.ride_repository.get_ride(emu_id).upload["strava_status"]), Ride.UPLOAD_NONE)
	button.pressed.emit()
	assert_true(dialog.visible, "повторное нажатие — снова диалог")
	dialog.get_ok_button().pressed.emit()
	assert_false(detail.is_upload_confirmation_pending())
	assert_true(main.strava.queue.has(emu_id), "«Выгрузить» — элемент очереди создан")
	assert_eq(str(main.ride_repository.get_ride(emu_id).upload["strava_status"]), Ride.UPLOAD_QUEUED)


func test_req_str_04_c5_real_ride_uploads_without_confirmation() -> void:
	_prelink(_profile.id)
	_profile.strava_auto_upload = false
	_profiles.save(_profile)
	var main := _main()
	var real := _ride(_profile.id, "Real", STARTED, Ride.TRAINER_SOURCE_BLE)
	main.ride_repository.save(real)
	assert_eq(main.strava.queue.size(), 0, "автовыгрузка выключена")
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	assert_true(history.show_ride(real.id))
	var detail := history.detail()
	(detail.get_node("%UploadButton") as Button).pressed.emit()
	assert_false(detail.is_upload_confirmation_pending(), "у заезда на станке подтверждения нет")
	assert_false(_confirm_dialog(detail).visible)
	assert_true(main.strava.queue.has(real.id), "в очереди сразу")


func test_confirm_without_pending_request_does_nothing() -> void:
	_prelink(_profile.id)
	var main := _main()
	var emu_id := _ride_on_emulator(main, _short_workout("Sweet Spot"))
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	assert_true(history.show_ride(emu_id))
	history.detail().confirm_emulator_upload()
	assert_eq(main.strava.queue.size(), 0, "без открытого диалога выгрузки нет")


# ---------------------------------------------------------------------------
# REQ-NFR-08, REQ-UIX-05 крит. 3: переводы ru/en и место под метку
# ---------------------------------------------------------------------------

func test_req_nfr_08_new_keys_translated_ru_and_en() -> void:
	var keys: Array[String] = [HistoryFormat.KEY_EMULATOR, "ui.history.upload_emulator.title",
		"ui.history.upload_emulator.text", "ui.history.upload_emulator.ok"]
	for locale in ["ru", "en"]:
		TranslationServer.set_locale(locale)
		for key in keys:
			assert_ne(tr(key), key, "%s: перевод %s" % [locale, key])
	TranslationServer.set_locale("en")
	assert_eq(HistoryFormat.emulator_text(true), "Emulator")
	assert_eq(HistoryFormat.emulator_text(false), "")


func test_req_nfr_08_emulator_label_fits_row_and_card_ru_en() -> void:
	var rides := FileRideRepository.new(_dir + "rides_fit/")
	rides.attach_to_profiles(_profiles)
	var state := AppState.new(_profiles)
	state.select_profile(_profile.id)
	var r := _ride(_profile.id, "Очень длинное название тренировки на эмуляторе с порогами", STARTED, Ride.TRAINER_SOURCE_EMULATOR)
	rides.save(r)
	for locale in ["ru", "en"]:
		TranslationServer.set_locale(locale)
		for canvas: Vector2i in [Vector2i(1280, 720), Vector2i(867, 400)]:
			var where := "%s %s" % [locale, canvas]
			var viewport := SubViewport.new()
			viewport.size = canvas
			add_child_autofree(viewport)
			var screen: HistoryScreen = (load(HISTORY_SCENE) as PackedScene).instantiate()
			screen.setup(rides, _profiles, state)
			viewport.add_child(screen)
			await wait_process_frames(3)
			var row := screen.row_for(r.id)
			assert_not_null(row, where)
			var badge := row.leading_slot().get_node("EmulatorLabel") as Label
			assert_eq(badge.text, HistoryFormat.emulator_text(true), where)
			assert_gte(badge.size.x + 0.5, badge.get_minimum_size().x, "%s: метка строки не обрезана" % where)
			var content := row.get_node("%Content") as Control
			assert_lte(content.get_combined_minimum_size().x, row.size.x + 0.5, "%s: строка не переполнена" % where)
			assert_lte(row.get_global_rect().end.x, float(canvas.x) + 0.5, "%s: строка в окне" % where)
			var title := row.get_node("%Title") as Label
			assert_gt(title.size.x, 0.0, "%s: место под название осталось" % where)
			screen.show_ride(r.id)
			await wait_process_frames(3)
			var card_badge := screen.detail().get_node("%EmulatorLabel") as Label
			var meta := card_badge.get_parent() as Control
			assert_true(card_badge.visible, where)
			assert_gte(card_badge.size.x + 0.5, card_badge.get_minimum_size().x, "%s: метка карточки не обрезана" % where)
			assert_lte(meta.get_combined_minimum_size().x, meta.size.x + 0.5, "%s: строка метки карточки не переполнена" % where)
