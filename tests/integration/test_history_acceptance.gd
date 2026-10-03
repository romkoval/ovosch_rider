extends GutTest
## Приёмка экранов истории (T-043/T-045) — независимые тесты тестировщика.
## REQ-LOC-02 крит. 1, 2; REQ-LOC-03 (в карточке); REQ-LOC-04; REQ-LOC-05 крит. 6
## (механика диалога; сам критерий — ручная проверка); REQ-LOC-06 крит. 1, 2;
## REQ-LOC-07 крит. 3; REQ-STR-04 крит. 5; REQ-STR-05 крит. 3.
## Источник истины — `docs/requirements.md`. Хранилище — `FileRideRepository` во временном `user://`.

const SCENE: String = "res://src/ui/history/history_screen.tscn"
const MAIN_SCENE: String = "res://src/app/main.tscn"
const FTP: int = 250
## Префикс сообщений вспомогательных тестов к критерию [ручная проверка] (REQ-INF-04 крит. 3).
const MANUAL_AUX: String = "[вспомогательно, ручная проверка REQ-LOC-05 крит. 6] "

var _dir: String
var _profiles: ProfileRepository
var _rides: FileRideRepository
var _state: AppState
var _pa: Profile
var _pb: Profile


func before_each() -> void:
	TranslationServer.set_locale("en")
	_dir = "user://test_history_acc_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_profiles = ProfileRepository.new(_dir + "profiles/")
	_rides = FileRideRepository.new(_dir + "rides/")
	_rides.attach_to_profiles(_profiles)
	_pa = _profiles.create("Anna")
	_pa.ftp_w = FTP
	_pa.max_hr = 190
	_profiles.save(_pa)
	_pb = _profiles.create("Boris")
	_profiles.active_profile_id = _pa.id
	_state = AppState.new(_profiles)
	_state.select_profile(_pa.id)


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


## Заезд `n` с постоянной мощностью `power`; `hr` < 0 — без пульса.
func _ride(profile: Profile, started_at: int, n: int, ride_name: String, power: int = 200, hr: int = 140,
		status: String = Ride.UPLOAD_NONE, activity_id: String = "") -> Ride:
	var r := Ride.new()
	r.id = Ride.generate_id(started_at)
	r.profile_id = profile.id
	r.started_at_unix = started_at
	r.name = ride_name
	r.workout = WorkoutSerializer.to_dict(Workout.make(ride_name, [WorkoutStep.watts(maxi(n, 1), float(power))] as Array[WorkoutStep], "zwo"))
	r.metadata = {"workout_name": ride_name, "workout_source": "zwo", "started_at_unix": started_at, "ftp_w": profile.ftp_w,
		"weight_kg": profile.weight_kg, "max_hr": profile.max_hr, "intensity": 1.0, "stopped_early": false,
		"speed_source": SampleStream.SPEED_SOURCE_TRAINER, "elapsed_sec": n, "paused_total_sec": 0.0,
		"in_progress": false, "recovered": false}
	r.samples.speed_source = SampleStream.SPEED_SOURCE_TRAINER
	for i in n:
		r.samples.append(i, TrainerSample.full(float(i), power, 88, 32.0), hr, power, 0, true)
	r.events = [{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0}]
	r.upload["strava_status"] = status
	if not activity_id.is_empty():
		r.upload["strava_activity_id"] = activity_id
	r.compute_summary()
	return r


func _screen(repo: RideRepository = null) -> HistoryScreen:
	var s: HistoryScreen = load(SCENE).instantiate()
	s.setup(repo if repo != null else _rides, _profiles, _state)
	add_child_autofree(s)
	return s


func _ride_dir_exists(profile_id: String, ride_id: String) -> bool:
	return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir + "rides/").path_join(profile_id).path_join(ride_id))


func _main() -> AppMain:
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	add_child_autofree(main)
	return main


## Привязать Strava активного профиля в уже запущенном `main` (токены в его хранилище).
func _link_strava(main: AppMain) -> void:
	var o := main.strava.oauth
	main.secure_store.set_secret(o.secret_key(SecureStore.ITEM_REFRESH_TOKEN), "fixture-refresh")
	main.secure_store.set_secret(o.secret_key(SecureStore.ITEM_ACCESS_TOKEN), "fixture-access")
	main.secure_store.set_secret(o.secret_key(SecureStore.ITEM_EXPIRES_AT), str(int(Time.get_unix_time_from_system()) + 36000))
	main.strava.authorized_changed.emit(true)


func _single_profile() -> void:
	assert_eq(_profiles.delete(_pb.id), "")


# ---------------------------------------------------------------------------
# REQ-LOC-02 крит. 1: новые сверху; дата, название, длительность, средняя, статус Strava
# ---------------------------------------------------------------------------

func test_req_loc_02_c1_sorted_newest_first_with_all_row_fields() -> void:
	# Сохраняем не по порядку, с разными статусами Strava.
	var specs := [
		[1700300000, 4000, "Long ride", 180, Ride.UPLOAD_DONE],
		[1700000000, 600, "Oldest", 120, Ride.UPLOAD_NONE],
		[1700500000, 1800, "Newest", 260, Ride.UPLOAD_FAILED],
		[1700100000, 900, "Second", 150, Ride.UPLOAD_QUEUED],
		[1700400000, 300, "Short", 300, Ride.UPLOAD_DUPLICATE],
		[1700200000, 1200, "Middle", 210, Ride.UPLOAD_UPLOADING],
	]
	for sp in specs:
		_rides.save(_ride(_pa, sp[0], sp[1], sp[2], sp[3], 140, sp[4], "99" if sp[4] == Ride.UPLOAD_DONE else ""))
	var s := _screen()
	var rows := s.rows()
	assert_eq(rows.size(), 6)
	var expected_order := ["Newest", "Short", "Long ride", "Middle", "Second", "Oldest"]
	for i in expected_order.size():
		assert_string_contains(rows[i], expected_order[i], "строка %d" % i)
	var sums := s.summaries()
	for i in range(1, sums.size()):
		assert_true(sums[i - 1].started_at_unix > sums[i].started_at_unix, "убывание даты старта")
	# Поля строки «Newest»: дата, название, длительность 30:00, средняя 260 W, статус «Failed».
	assert_string_contains(rows[0], HistoryScreen.format_date_time(1700500000), "дата")
	assert_string_contains(rows[0], "30:00", "длительность")
	assert_string_contains(rows[0], "260 W", "средняя мощность")
	assert_string_contains(rows[0], "Failed", "статус Strava")
	assert_string_contains(rows[2], "1:06:40", "длительность > 1 ч")
	assert_string_contains(rows[2], "Uploaded")
	assert_string_contains(rows[1], "Duplicate")
	assert_string_contains(rows[3], "Processing")
	assert_string_contains(rows[4], "Queued")
	assert_string_contains(rows[5], "Not uploaded")
	for r in rows:
		assert_false(r.contains("ui.history"), "в строке нет непереведённых ключей: " + r)


func test_req_loc_02_c1_edge_ride_without_samples_and_untitled_in_russian() -> void:
	TranslationServer.set_locale("ru")
	_rides.save(_ride(_pa, 1700000000, 0, "", 200, -1))
	_rides.save(_ride(_pa, 1700000100, 1, "Один сэмпл", 333, -1))
	var s := _screen()
	var rows := s.rows()
	assert_eq(rows.size(), 2)
	assert_string_contains(rows[0], "Один сэмпл")
	assert_string_contains(rows[0], "00:01")
	assert_string_contains(rows[0], "333 Вт")
	assert_string_contains(rows[0], "Не выгружен")
	assert_string_contains(rows[1], "Тренировка", "без названия — подстановка")
	assert_string_contains(rows[1], "00:00")
	assert_string_contains(rows[1], "— Вт", "нет данных мощности — «—», не 0")
	TranslationServer.set_locale("en")


# ---------------------------------------------------------------------------
# REQ-LOC-02 крит. 2: список из 500 заездов ≤ 1 с
# ---------------------------------------------------------------------------

func _save_many(count: int) -> void:
	for i in count:
		_rides.save(_ride(_pa, 1690000000 + i * 3600, 30, "Ride %03d" % i, 150 + i % 100))


func test_req_loc_02_c2_500_rides_cold_repository_list_and_screen_within_1s() -> void:
	_save_many(500)
	var t0 := Time.get_ticks_usec()
	var cold := FileRideRepository.new(_dir + "rides/")  # новый экземпляр — без кэша индекса
	var s := _screen(cold)
	var elapsed_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	gut.p("500 заездов: холодный репозиторий + экран = %.1f мс" % elapsed_ms)
	assert_eq(s.row_count(), 500)
	assert_string_contains(s.rows()[0], "Ride 499", "новейший сверху")
	assert_string_contains(s.rows()[499], "Ride 000")
	assert_lte(elapsed_ms, 1000.0, "REQ-LOC-02 крит. 2: ≤ 1 с")


func test_req_loc_02_c2_500_rides_with_missing_index_within_1s() -> void:
	_save_many(500)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir + "rides/").path_join(_pa.id).path_join(FileRideRepository.INDEX_FILE))
	var t0 := Time.get_ticks_usec()
	var cold := FileRideRepository.new(_dir + "rides/")
	var s := _screen(cold)
	var elapsed_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	gut.p("500 заездов без index.json: %.1f мс" % elapsed_ms)
	assert_eq(s.row_count(), 500)
	assert_lte(elapsed_ms, 1000.0, "REQ-LOC-02 крит. 2: ≤ 1 с и при перестроении индекса")


# ---------------------------------------------------------------------------
# REQ-LOC-03 в карточке: серии, цель, прореживание, граничные заезды
# ---------------------------------------------------------------------------

func test_req_loc_03_c2_card_7200_samples_chart_keeps_sprint_peak() -> void:
	var r := _ride(_pa, 1700000000, 7200, "Two hours", 200, 140)
	r.samples.power_w[3001] = 1000  # спринт 1 с
	r.compute_summary()
	_rides.save(r)
	var s := _screen()
	s.select_index(0)
	var d := s.detail()
	assert_lte(d.series().size(), 3600, "≤ 3600 точек")
	var chart: RideChart = d.get_node("%PowerChart")
	assert_lte(chart.point_count(), 3600)
	assert_true(chart.has_target(), "крит. 3: цель поверх мощности")
	assert_almost_eq(chart.max_value(), 1000.0, 1e-3, "крит. 2: максимум (спринт) виден на графике мощности")


func test_req_loc_03_c3_card_target_series_for_free_ride() -> void:
	var r := _ride(_pa, 1700000000, 90, "Free ride", 180)
	for i in r.samples.size():
		r.samples.target_w[i] = 0
	_rides.save(r)
	var s := _screen()
	s.select_index(0)
	var d := s.detail()
	assert_eq(d.series().count(RideSeries.TARGET), 90, "серия цели есть и в свободной езде (0)")
	assert_true((d.get_node("%PowerChart") as RideChart).has_target())


func test_req_loc_03_c1_card_edge_ride_without_samples_and_with_one_sample() -> void:
	_rides.save(_ride(_pa, 1700000000, 0, "Empty", 200, -1))
	_rides.save(_ride(_pa, 1700000500, 1, "One", 210, 130))
	var s := _screen()
	assert_true(s.show_ride(s.summaries()[1].ride_id), "карточка заезда без сэмплов открывается")
	var d := s.detail()
	assert_eq(d.series().size(), 0)
	assert_eq((d.get_node("%PowerChart") as RideChart).point_count(), 0)
	assert_string_contains(d.summary_text(), "avg — W", "мощности нет — «—»")
	assert_true(s.show_ride(s.summaries()[0].ride_id))
	assert_eq(d.series().points(RideSeries.POWER).size(), 1)
	assert_eq((d.get_node("%PowerChart") as RideChart).point_count(), 1)
	assert_eq((d.get_node("%HrChart") as RideChart).point_count(), 1)


# ---------------------------------------------------------------------------
# REQ-LOC-04: сводка в карточке
# ---------------------------------------------------------------------------

func test_req_loc_04_card_summary_avg_np_work_and_zones_for_200w_hour() -> void:
	_rides.save(_ride(_pa, 1700000000, 3600, "Hour at 200", 200, 150))
	var s := _screen()
	s.select_index(0)
	var d := s.detail()
	var text := d.summary_text()
	assert_string_contains(text, "avg 200 W", "крит. 1: средняя")
	assert_string_contains(text, "NP 200 W", "крит. 2: NP постоянной мощности")
	assert_string_contains(text, "work 720 kJ", "крит. 3: 200 Вт × 3600 с = 720 кДж")
	assert_string_contains(text, "Heart rate: avg 150", "крит. 4: средний пульс")
	var pbar: ZoneBar = d.get_node("%PowerZoneBar")
	assert_eq(pbar.zone_count(), 7, "крит. 5: 7 зон мощности")
	assert_eq(pbar.total_sec(), 3600, "крит. 5: сумма = числу сэмплов с мощностью")
	var hbar: ZoneBar = d.get_node("%HrZoneBar")
	assert_eq(hbar.zone_count(), 5, "5 зон пульса")
	assert_eq(hbar.total_sec(), 3600)
	assert_true(hbar.visible)


func test_req_loc_04_c6_card_without_hr_shows_dash_without_errors() -> void:
	_rides.save(_ride(_pa, 1700000000, 600, "No strap", 220, -1))
	var s := _screen()
	s.select_index(0)
	var d := s.detail()
	assert_string_contains(d.summary_text(), "Heart rate: avg — · max —", "«—» в полях пульса")
	assert_false(d.summary_text().contains("avg 0 ·"), "не 0 вместо «нет данных»")
	assert_eq((d.get_node("%HrChart") as RideChart).point_count(), 0, "график пульса пуст, без нулей")
	var hbar: ZoneBar = d.get_node("%HrZoneBar")
	assert_true(not hbar.visible or hbar.total_sec() == 0, "в зонах пульса нет времени без данных пульса (крит. 5)")
	assert_string_contains(d.summary_text(), "avg 220 W", "мощность при этом показана")


# ---------------------------------------------------------------------------
# REQ-LOC-05 крит. 6 [ручная проверка] — механика диалога экспорта (вспомогательно).
# Тесты `*_c6_manual_aux_*` — автоматическая часть ручного критерия (REQ-INF-04 крит. 3),
# критерий ими не закрывается: системный диалог сохранения проверяется вручную.
# ---------------------------------------------------------------------------

func test_req_loc_05_c6_manual_aux_export_dialog_default_name_and_decodable_file() -> void:
	# Вспомогательный автотест (REQ-INF-04 крит. 3): автоматическая часть критерия
	# REQ-LOC-05 крит. 6 [ручная проверка]; критерий не закрывает — системный диалог проверяется вручную.
	var r := _ride(_pa, 1700000000, 120, "Sweet spot 3x10", 230, 150)
	_rides.save(r)
	var s := _screen()
	s.select_index(0)
	var d := s.detail()
	var dialog: FileDialog = d.get_node("%ExportDialog")
	assert_eq(dialog.file_mode, FileDialog.FILE_MODE_SAVE_FILE, MANUAL_AUX + "диалог сохранения")
	assert_true(Array(dialog.filters).any(func(f: String) -> bool: return f.contains("*.fit")), MANUAL_AUX + "фильтр *.fit")
	d.request_export()
	var expected_date: String = HistoryScreen.format_date_time(1700000000).substr(0, 10)
	assert_eq(dialog.current_file, "%s_Sweet_spot_3x10.fit" % expected_date, MANUAL_AUX + "имя по умолчанию <дата>_<название>.fit")
	dialog.hide()
	var path := ProjectSettings.globalize_path(_dir).path_join(dialog.current_file)
	dialog.file_selected.emit(path)
	assert_true(FileAccess.file_exists(path), MANUAL_AUX + "файл записан по выбранному пути")
	var res := FitDecoder.decode(FileAccess.get_file_as_bytes(path))
	assert_true(res.ok, MANUAL_AUX + ("FitDecoder: %s" % res.error))
	assert_true(res.file_crc_ok, MANUAL_AUX + "CRC файла верна")
	assert_eq(res.count(FitDefinitions.MSG_RECORD), 120, MANUAL_AUX + "все записи выгружены")


func test_req_loc_05_c6_manual_aux_export_file_date_matches_local_ride_date() -> void:
	# Вспомогательный автотест (REQ-INF-04 крит. 3): автоматическая часть критерия
	# REQ-LOC-05 крит. 6 [ручная проверка]; критерий не закрывает — системный диалог проверяется вручную.
	# Дата в имени файла должна совпадать с датой заезда, показанной пользователю (локальное время).
	# 1700000000 = 2023-11-14 22:13:20 UTC; в UTC+N (N ≥ 2) это уже 15.11.
	_rides.save(_ride(_pa, 1700000000, 10, "Late", 200, -1))
	var s := _screen()
	s.select_index(0)
	var shown_date: String = HistoryScreen.format_date_time(1700000000).substr(0, 10)
	assert_true(s.detail().default_export_file_name().begins_with(shown_date + "_"),
		MANUAL_AUX + ("имя %s начинается с даты из списка %s" % [s.detail().default_export_file_name(), shown_date]))


func test_req_loc_05_c6_manual_aux_default_name_keeps_cyrillic_and_strips_path_chars() -> void:
	# Вспомогательный автотест (REQ-INF-04 крит. 3): автоматическая часть критерия
	# REQ-LOC-05 крит. 6 [ручная проверка]; критерий не закрывает — системный диалог проверяется вручную.
	_rides.save(_ride(_pa, 1700000000, 10, "Свит-спот 3/10: база", 200, -1))
	var s := _screen()
	s.select_index(0)
	var file_name := s.detail().default_export_file_name()
	assert_true(file_name.ends_with("_Свит-спот_310_база.fit"), MANUAL_AUX + file_name)
	assert_false(file_name.contains("/"), MANUAL_AUX + "нет «/» в имени: " + file_name)
	assert_false(file_name.contains(":"), MANUAL_AUX + "нет «:» в имени: " + file_name)


# ---------------------------------------------------------------------------
# REQ-LOC-06 крит. 1: удаление с подтверждением; отмена ничего не меняет; очередь Strava
# ---------------------------------------------------------------------------

func test_req_loc_06_c1_delete_button_asks_and_cancel_changes_nothing() -> void:
	var keep := _ride(_pa, 1700000000, 60, "Keep me")
	_rides.save(keep)
	_rides.save(_ride(_pa, 1700100000, 60, "Other"))
	var s := _screen()
	s.show_ride(keep.id)
	var d := s.detail()
	var deleted: Array[String] = []
	s.ride_deleted.connect(func(id: String) -> void: deleted.append(id))
	(d.get_node("%DeleteButton") as Button).pressed.emit()
	var dlg: ConfirmationDialog = d.get_node("%DeleteDialog")
	assert_true(dlg.visible, "показан диалог подтверждения")
	assert_string_contains(dlg.dialog_text, "Keep me")
	assert_true(_ride_dir_exists(_pa.id, keep.id), "до подтверждения ничего не удалено")
	dlg.canceled.emit()  # «Отмена»
	assert_false(dlg.visible)
	assert_true(_ride_dir_exists(_pa.id, keep.id), "отмена: каталог на месте")
	assert_not_null(_rides.get_ride(keep.id))
	assert_eq(_rides.get_ride(keep.id).samples.size(), 60, "сэмплы целы")
	assert_eq(_rides.list(_pa.id).size(), 2)
	assert_eq(deleted, [], "сигнала удаления нет")
	assert_true(s.is_detail_visible(), "карточка остаётся открытой")
	assert_eq(d.ride().id, keep.id)


func test_req_loc_06_c1_confirm_deletes_and_removes_persisted_strava_queue_item() -> void:
	_single_profile()
	var r := _ride(_pa, 1700000000, 60, "Queued ride", 200, 140, Ride.UPLOAD_FAILED)
	var other := _ride(_pa, 1700100000, 60, "Other queued", 200, 140, Ride.UPLOAD_FAILED)
	_rides.save(r)
	_rides.save(other)
	var main := _main()
	_link_strava(main)
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	assert_true(history.show_ride(r.id))
	history.detail().request_upload()
	history.show_ride(other.id)
	history.detail().request_upload()
	assert_true(main.strava.queue.has(r.id) and main.strava.queue.has(other.id), "оба в очереди")
	history.show_ride(r.id)
	(history.detail().get_node("%DeleteButton") as Button).pressed.emit()
	(history.detail().get_node("%DeleteDialog") as ConfirmationDialog).confirmed.emit()  # «Удалить»
	assert_null(main.ride_repository.get_ride(r.id))
	assert_false(_ride_dir_exists(_pa.id, r.id), "каталог заезда удалён")
	assert_false(main.strava.queue.has(r.id), "элемент очереди удалён")
	assert_true(main.strava.queue.has(other.id), "чужой элемент очереди не тронут")
	# Очередь на диске (переживает перезапуск) — тоже без удалённого заезда.
	var reloaded := UploadQueue.new(main.strava.uploader, main.strava.status_store, Callable(), _pa.id, _dir)
	assert_false(reloaded.has(r.id), "после перезапуска элемента нет")
	assert_true(reloaded.has(other.id))
	assert_eq(history.row_count(), 1)


# ---------------------------------------------------------------------------
# REQ-LOC-06 крит. 2: удаление выгруженного заезда не трогает активность в Strava
# ---------------------------------------------------------------------------

func test_req_loc_06_c2_deleting_uploaded_ride_makes_no_strava_requests() -> void:
	_single_profile()
	var r := _ride(_pa, 1700000000, 60, "Uploaded", 200, 140, Ride.UPLOAD_DONE, "555")
	_rides.save(r)
	var main := _main()
	_link_strava(main)
	var transport := main.transport as MockHttpTransport
	transport.clear()
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	assert_true(history.show_ride(r.id))
	history.detail().request_delete()
	history.detail().confirm_delete()
	assert_null(main.ride_repository.get_ride(r.id))
	await main.strava.step_queue()
	main.strava.tick(StravaService.QUEUE_TICK_INTERVAL_SEC + 1.0)
	await wait_physics_frames(2)
	assert_eq(transport.request_count(), 0, "ни одного HTTP-запроса (в т.ч. DELETE) к Strava")
	assert_eq(transport.request_count("DELETE"), 0)


# ---------------------------------------------------------------------------
# REQ-LOC-07 крит. 3: при запуске — «сохранить досрочно / удалить»
# ---------------------------------------------------------------------------

func _in_progress(profile: Profile, started_at: int, n: int, ride_name: String) -> Ride:
	var r := _ride(profile, started_at, n, ride_name)
	r.metadata["in_progress"] = true
	r.summary = RideSummary.new()
	_rides.save(r)
	return r


func test_req_loc_07_c3_dialog_on_start_offers_keep_and_delete() -> void:
	_single_profile()
	var r := _in_progress(_pa, 1700000000, 40, "Crashed")
	var main := _main()
	var dialog := main.recovery_dialog()
	assert_true(dialog.visible, "диалог показан при запуске")
	assert_eq(dialog.current_ride().id, r.id)
	assert_string_contains(dialog.dialog_text, "Crashed")
	assert_eq(dialog.get_ok_button().text, "ui.history.recovery.keep", "кнопка «сохранить досрочно»")
	var labels: Array[String] = []
	for b in _buttons(dialog):
		labels.append(b.text)
	assert_has(labels, "ui.history.recovery.delete", "кнопка «удалить»")
	dialog.get_ok_button().pressed.emit()
	var back := main.ride_repository.get_ride(r.id)
	assert_not_null(back)
	assert_true(back.stopped_early(), "сохранён как завершённый досрочно")
	assert_false(back.is_in_progress())
	assert_eq(back.samples.size(), 40)


func _buttons(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	for c in node.get_children(true):
		if c is Button:
			out.append(c)
		out.append_array(_buttons(c))
	return out


func test_req_loc_07_c3_delete_button_removes_ride_and_shows_next() -> void:
	_single_profile()
	var a := _in_progress(_pa, 1700000000, 20, "Crash A")
	var b := _in_progress(_pa, 1700100000, 30, "Crash B")
	var main := _main()
	var dialog := main.recovery_dialog()
	var first := dialog.current_ride()
	assert_not_null(first)
	assert_eq(dialog.pending_count(), 1, "второй заезд ждёт своей очереди")
	dialog.custom_action.emit(StringName(RecoveryDialog.ACTION_DELETE))  # кнопка «Удалить»
	assert_null(main.ride_repository.get_ride(first.id), "удалён")
	var second := dialog.current_ride()
	assert_not_null(second, "диалог для второго незавершённого заезда")
	assert_ne(second.id, first.id)
	dialog.keep()
	assert_null(dialog.current_ride())
	var ids: Array[String] = []
	for s in main.ride_repository.list(_pa.id):
		ids.append(s.ride_id)
	assert_eq(ids.size(), 1)
	assert_true(ids[0] == a.id or ids[0] == b.id)
	assert_ne(ids[0], first.id)


func test_req_loc_07_c3_two_profiles_dialog_after_choice_only_for_that_profile() -> void:
	var mine := _in_progress(_pa, 1700000000, 20, "Anna crash")
	_in_progress(_pb, 1700000100, 20, "Boris crash")
	var main := _main()
	assert_eq(main.app_state.current_screen, AppState.Screen.PROFILE_SELECT)
	assert_null(main.recovery_dialog().current_ride(), "до выбора профиля диалога нет")
	main.app_state.select_profile(_pa.id)
	var dialog := main.recovery_dialog()
	assert_not_null(dialog.current_ride())
	assert_eq(dialog.current_ride().id, mine.id)
	assert_eq(dialog.pending_count(), 0, "заезд другого профиля не предлагается")


func test_req_loc_07_c3_no_dialog_on_second_start_after_keep() -> void:
	_single_profile()
	_in_progress(_pa, 1700000000, 20, "Crashed once")
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	add_child(main)
	main.recovery_dialog().keep()
	remove_child(main)
	main.free()
	var main2 := _main()
	assert_null(main2.recovery_dialog().current_ride(), "решение запомнено, повторно не спрашивает")


# ---------------------------------------------------------------------------
# REQ-STR-04 крит. 5: «выгрузить в Strava» из карточки для заездов без статуса «выгружено»
# ---------------------------------------------------------------------------

func test_req_str_04_c5_retry_from_card_enqueues_immediately() -> void:
	_single_profile()
	var failed := _ride(_pa, 1700000000, 60, "Failed upload", 200, 140, Ride.UPLOAD_FAILED)
	failed.upload["last_error"] = "timeout"
	_rides.save(failed)
	var main := _main()
	_link_strava(main)
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	history.show_ride(failed.id)
	var d := history.detail()
	assert_true(d.is_upload_enabled(), "для «ошибка» действие доступно")
	(d.get_node("%UploadButton") as Button).pressed.emit()
	assert_true(main.strava.queue.has(failed.id), "заезд в очереди сразу")
	var item := main.strava.queue.get_item(failed.id)
	assert_lte(int(item.get("next_attempt_at", 1 << 40)), int(Time.get_unix_time_from_system()) + 1, "попытка — немедленно")
	assert_eq(str(main.ride_repository.get_ride(failed.id).upload.get("strava_status")), Ride.UPLOAD_QUEUED, "статус «в очереди»")


func test_req_str_04_c5_action_per_status() -> void:
	_single_profile()
	var by_status: Dictionary = {}
	var t: int = 1700000000
	for st in Ride.UPLOAD_STATUSES:
		var r := _ride(_pa, t, 30, "S " + st, 200, 140, st, "1" if st == Ride.UPLOAD_DONE else "")
		_rides.save(r)
		by_status[st] = r.id
		t += 1000
	var main := _main()
	_link_strava(main)
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	for st in Ride.UPLOAD_STATUSES:
		history.show_ride(by_status[st])
		if st == Ride.UPLOAD_DONE:
			assert_false(history.detail().is_upload_enabled(), "«выгружено» — действия нет")
			history.detail().request_upload()
			assert_false(main.strava.queue.has(by_status[st]), "«выгружено» в очередь не ставится")
		else:
			assert_true(history.detail().is_upload_enabled(), "статус %s — действие доступно" % st)


# ---------------------------------------------------------------------------
# REQ-STR-05 крит. 3: ссылка на активность для «выгружено»
# ---------------------------------------------------------------------------

func test_req_str_05_c3_activity_link_only_for_uploaded() -> void:
	_rides.save(_ride(_pa, 1700000000, 30, "Done", 200, 140, Ride.UPLOAD_DONE, "9876543210"))
	_rides.save(_ride(_pa, 1700001000, 30, "Dup", 200, 140, Ride.UPLOAD_DUPLICATE))
	_rides.save(_ride(_pa, 1700002000, 30, "Queued", 200, 140, Ride.UPLOAD_QUEUED))
	var s := _screen()
	s.select_index(2)  # «Done» — самый старый
	var d := s.detail()
	assert_eq(d.strava_activity_url(), "https://www.strava.com/activities/9876543210")
	assert_string_contains(d.status_text(), "https://www.strava.com/activities/9876543210", "ссылка видна в карточке")
	s.select_index(1)
	assert_eq(d.strava_activity_url(), "", "«дубликат» — без ссылки")
	s.select_index(0)
	assert_eq(d.strava_activity_url(), "", "«в очереди» — без ссылки")


# ---------------------------------------------------------------------------
# Дополнительно (REQ-STR-05 крит. 2 / REQ-LOC-06 крит. 3 — вне списка задачи):
# статус в открытой карточке после «выгрузить в Strava»
# ---------------------------------------------------------------------------

func test_extra_str_05_c2_open_card_status_refreshes_after_upload_request() -> void:
	_single_profile()
	var r := _ride(_pa, 1700000000, 60, "Retry me", 200, 140, Ride.UPLOAD_FAILED)
	r.upload["last_error"] = "boom"
	_rides.save(r)
	var main := _main()
	_link_strava(main)
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	history.show_ride(r.id)
	assert_string_contains(history.detail().status_text(), "Failed")
	history.detail().request_upload()
	assert_eq(str(main.ride_repository.get_ride(r.id).upload.get("strava_status")), Ride.UPLOAD_QUEUED)
	assert_string_contains(history.detail().status_text(), "Queued", "карточка показывает «в очереди»")
