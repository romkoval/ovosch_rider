extends GutTest
## Экраны истории (REQ-LOC-02 крит. 1, 2; REQ-LOC-03 крит. 1–3; REQ-LOC-04 — сводка на экране;
## REQ-LOC-05 крит. 5, 6 — экспорт FIT; REQ-LOC-06 крит. 1–3; REQ-LOC-07 крит. 3 — восстановление;
## REQ-PRF-04 крит. 1; REQ-STR-05 крит. 2, 3; REQ-WRK-05 крит. 4 — заезд из эмуляторной тренировки
## попадает в историю через `main.tscn`).

const SCENE: String = "res://src/ui/history/history_screen.tscn"
const MAIN_SCENE: String = "res://src/app/main.tscn"
const FTP: int = 200

var _dir: String
var _profiles: ProfileRepository
var _rides: FileRideRepository
var _state: AppState
var _pa: Profile
var _pb: Profile
var _now_usec: int = 0


func before_each() -> void:
	TranslationServer.set_locale("en")
	_now_usec = 5_000_000
	_dir = "user://test_history_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_profiles = ProfileRepository.new(_dir + "profiles/")
	_rides = FileRideRepository.new(_dir + "rides/")
	_rides.attach_to_profiles(_profiles)
	_pa = _profiles.create("Alice")
	_pa.ftp_w = FTP
	_pa.max_hr = 180
	_profiles.save(_pa)
	_pb = _profiles.create("Bob")
	_profiles.active_profile_id = _pa.id
	_state = AppState.new(_profiles)
	_state.select_profile(_pa.id)


func after_each() -> void:
	AtomicFile.simulate_write_error_prefix = ""
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


func _clock() -> int:
	return _now_usec


## Заезд `n` секунд с постоянной мощностью `power`, пульсом 150, слот 2 без телеметрии.
func _ride(profile: Profile, started_at: int, n: int, name: String, power: int = 200) -> Ride:
	var r := Ride.new()
	r.id = Ride.generate_id(started_at)
	r.profile_id = profile.id
	r.started_at_unix = started_at
	r.name = name
	r.workout = WorkoutSerializer.to_dict(Workout.make(name, [WorkoutStep.watts(n, float(power))] as Array[WorkoutStep], "zwo"))
	r.metadata = {"workout_name": name, "workout_source": "zwo", "started_at_unix": started_at, "ftp_w": profile.ftp_w,
		"weight_kg": profile.weight_kg, "max_hr": profile.max_hr, "intensity": 1.0, "stopped_early": false,
		"speed_source": SampleStream.SPEED_SOURCE_TRAINER, "elapsed_sec": n, "paused_total_sec": 0.0,
		"in_progress": false, "recovered": false}
	r.samples.speed_source = SampleStream.SPEED_SOURCE_TRAINER
	for i in n:
		var sample: TrainerSample = TrainerSample.full(float(i + 1), power, 90, 36.0) if i != 2 else null
		r.samples.append(i, sample, 150, power, 0, true)
	r.events = [{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0}]
	r.compute_summary()
	return r


func _three_rides() -> Array[Ride]:
	var rides: Array[Ride] = [
		_ride(_pa, 1700000000, 60, "Old ride", 150),
		_ride(_pa, 1700200000, 120, "Newest ride", 250),
		_ride(_pa, 1700100000, 90, "Middle ride", 200),
	]
	for r in rides:
		_rides.save(r)
	return rides


func _screen() -> HistoryScreen:
	var s: HistoryScreen = load(SCENE).instantiate()
	s.setup(_rides, _profiles, _state)
	add_child_autofree(s)
	return s


# ---------------------------------------------------------------------------
# Список (REQ-LOC-02 крит. 1, REQ-PRF-04 крит. 1)
# ---------------------------------------------------------------------------

func test_empty_history_shows_hint() -> void:
	var s := _screen()
	assert_eq(s.row_count(), 0)
	assert_true(s.is_empty_label_visible())
	assert_false(s.is_detail_visible())


func test_list_is_sorted_newest_first_with_row_fields() -> void:
	_three_rides()
	var s := _screen()
	var rows := s.rows()
	assert_eq(rows.size(), 3)
	assert_string_contains(rows[0], "Newest ride")
	assert_string_contains(rows[1], "Middle ride")
	assert_string_contains(rows[2], "Old ride")
	assert_string_contains(rows[0], "02:00", "длительность 120 с")
	assert_string_contains(rows[0], "250 W", "средняя мощность")
	assert_string_contains(rows[0], "NP 250")
	assert_string_contains(rows[0], "Not uploaded", "статус Strava")
	assert_string_contains(rows[0], HistoryScreen.format_date_time(1700200000), "дата-время")
	assert_string_contains(rows[0], "1.2 km", "дистанция 119 × 10 м")
	assert_false(s.is_empty_label_visible())


func test_switching_profile_shows_other_history() -> void:
	_three_rides()
	_rides.save(_ride(_pb, 1700300000, 30, "Bob ride"))
	var s := _screen()
	assert_eq(s.row_count(), 3, "REQ-PRF-04 крит. 1: только заезды Alice")
	_state.select_profile(_pb.id)
	s.refresh()
	assert_eq(s.row_count(), 1)
	assert_string_contains(s.rows()[0], "Bob ride")


func test_list_refreshes_on_repository_change() -> void:
	var s := _screen()
	assert_eq(s.row_count(), 0)
	_rides.save(_ride(_pa, 1700000000, 10, "Fresh"))
	assert_eq(s.row_count(), 1, "сигнал rides_changed обновил список")


func test_row_marks_stopped_early_and_strava_done() -> void:
	var r := _ride(_pa, 1700000000, 60, "Early")
	r.metadata["stopped_early"] = true
	r.upload["strava_status"] = Ride.UPLOAD_DONE
	r.upload["strava_activity_id"] = "42"
	_rides.save(r)
	var s := _screen()
	assert_string_contains(s.rows()[0], "ended early")
	assert_string_contains(s.rows()[0], "Uploaded")


# ---------------------------------------------------------------------------
# Карточка (REQ-LOC-03, REQ-LOC-04, REQ-STR-05)
# ---------------------------------------------------------------------------

func test_select_row_opens_detail_with_summary_and_series() -> void:
	var rides := _three_rides()
	var s := _screen()
	s.select_index(0)
	assert_true(s.is_detail_visible())
	var d := s.detail()
	assert_eq(d.ride().id, rides[1].id, "первая строка — новейший заезд")
	assert_string_contains(d.title_text(), "Newest ride")
	assert_string_contains(d.summary_text(), "02:00")
	assert_string_contains(d.summary_text(), "avg 250 W")
	assert_string_contains(d.summary_text(), "NP 250 W")
	assert_string_contains(d.summary_text(), "max 250 W")
	assert_string_contains(d.summary_text(), "30 kJ", "250 Вт × 119 с = 29.75 кДж")
	assert_string_contains(d.summary_text(), "avg 150")
	assert_string_contains(d.summary_text(), "avg 90")
	assert_string_contains(d.summary_text(), "FTP 200 W")
	assert_string_contains(d.summary_text(), "trainer")
	assert_string_contains(d.status_text(), "Not uploaded")
	var series := d.series()
	assert_eq(series.points(RideSeries.POWER).size(), 119, "REQ-LOC-03 крит. 1: без слота 2")
	assert_eq(series.count(RideSeries.HEART_RATE), 120)
	assert_eq(series.count(RideSeries.TARGET), 120, "REQ-LOC-03 крит. 3: серия цели")
	var power_chart: RideChart = d.get_node("%PowerChart")
	assert_eq(power_chart.point_count(), 119)
	assert_true(power_chart.has_target())
	var hr_chart: RideChart = d.get_node("%HrChart")
	assert_eq(hr_chart.point_count(), 120)
	var cadence_chart: RideChart = d.get_node("%CadenceChart")
	assert_eq(cadence_chart.point_count(), 119)
	var power_bar: ZoneBar = d.get_node("%PowerZoneBar")
	assert_eq(power_bar.zone_count(), 7)
	assert_eq(power_bar.total_sec(), 119, "REQ-LOC-04 крит. 5")
	var hr_bar: ZoneBar = d.get_node("%HrZoneBar")
	assert_eq(hr_bar.zone_count(), 5)
	assert_eq(hr_bar.total_sec(), 120)


func test_detail_without_hr_shows_dashes() -> void:
	var r := _ride(_pa, 1700000000, 30, "No HR")
	r.samples = SampleStream.new()
	for i in 30:
		r.samples.append(i, TrainerSample.full(float(i), 200, 90, 30.0), -1, 200, 0, true)
	r.metadata["max_hr"] = 0
	r.compute_summary()
	_rides.save(r)
	var s := _screen()
	s.select_index(0)
	assert_string_contains(s.detail().summary_text(), "Heart rate: avg — · max —", "REQ-LOC-04 крит. 6")
	assert_false((s.detail().get_node("%HrZoneBar") as Control).visible)


func test_back_returns_to_list() -> void:
	_three_rides()
	var s := _screen()
	s.select_index(1)
	assert_true(s.is_detail_visible())
	s.back_to_list()
	assert_false(s.is_detail_visible())
	assert_eq(s.row_count(), 3)


func test_strava_status_and_link_in_detail() -> void:
	var r := _ride(_pa, 1700000000, 60, "Uploaded")
	r.upload["strava_status"] = Ride.UPLOAD_DONE
	r.upload["strava_activity_id"] = "123456"
	_rides.save(r)
	var s := _screen()
	s.select_index(0)
	assert_string_contains(s.detail().status_text(), "Uploaded")
	assert_eq(s.detail().strava_activity_url(), "https://www.strava.com/activities/123456", "REQ-STR-05 крит. 3")
	_rides.update_upload_status(r.id, {"strava_status": Ride.UPLOAD_FAILED, "last_error": "Strava отклонила выгрузку",
		"last_error_code": ApiResult.CODE_BAD_RESPONSE, "last_error_detail": "Improperly formatted data."})
	# Открытая карточка перерисовывается по `rides_changed` без повторного show_ride.
	assert_string_contains(s.detail().status_text(), "Failed", "REQ-STR-05 крит. 2: статус в открытой карточке")
	assert_string_contains(s.detail().status_text(), "Strava did not accept the file", "REQ-NFR-08: причина переведена по коду")
	assert_string_contains(s.detail().status_text(), "Improperly formatted data.", "ответ Strava — деталь после причины")
	assert_false(s.detail().status_text().contains("отклонила"), "сырой текст выгрузчика не показывается")
	assert_eq(s.detail().strava_activity_url(), "")


func test_open_detail_refreshes_status_and_upload_button_on_repository_change() -> void:
	var r := _ride(_pa, 1700000000, 60, "Retry me")
	r.upload["strava_status"] = Ride.UPLOAD_FAILED
	r.upload["last_error"] = "boom"
	_rides.save(r)
	var s := _screen()
	s.set_strava_linked(true)
	s.select_index(0)
	assert_string_contains(s.detail().status_text(), "Failed")
	assert_true(s.detail().is_upload_enabled())
	_rides.update_upload_status(r.id, {"strava_status": Ride.UPLOAD_QUEUED})
	assert_string_contains(s.detail().status_text(), "Queued", "карточка показывает «в очереди»")
	assert_true(s.is_detail_visible(), "карточка остаётся открытой")
	_rides.update_upload_status(r.id, {"strava_status": Ride.UPLOAD_DONE, "strava_activity_id": "42"})
	assert_string_contains(s.detail().status_text(), "Uploaded")
	assert_false(s.detail().is_upload_enabled(), "«выгружено» — кнопка недоступна")


func test_upload_button_disabled_without_link_and_emits_when_linked() -> void:
	var r := _ride(_pa, 1700000000, 60, "To upload")
	_rides.save(r)
	var s := _screen()
	s.select_index(0)
	var d := s.detail()
	assert_false(d.is_upload_enabled(), "без привязки недоступна")
	assert_eq(d.upload_tooltip(), "Strava is not linked")
	var requested: Array[String] = []
	s.upload_requested.connect(func(id: String, _n: String, _d: String) -> void: requested.append(id))
	d.request_upload()
	assert_eq(requested, [], "без привязки сигнала нет")
	s.set_strava_linked(true)
	assert_true(d.is_upload_enabled())
	d.request_upload()
	assert_eq(requested, [r.id])


## REQ-STR-03 крит. 1–3: поля названия/описания в карточке — значения по умолчанию на языке
## интерфейса, правка пользователя уходит с сигналом, после выгрузки поля недоступны.
func test_upload_fields_default_values_edits_and_locale() -> void:
	var untitled := _ride(_pa, 1700000000, 60, "")
	_rides.save(untitled)
	var s := _screen()
	s.set_strava_linked(true)
	s.select_index(0)
	var d := s.detail()
	var name_edit := d.get_node("%UploadNameEdit") as LineEdit
	var desc_edit := d.get_node("%UploadDescriptionEdit") as TextEdit
	var date := HistoryScreen.format_date_time(untitled.started_at_unix).substr(0, 10)
	assert_eq(name_edit.text, "Workout " + date, "название по умолчанию на английском")
	assert_eq(desc_edit.text, "Recorded in ovosch-rider")
	assert_true(d.is_upload_fields_editable())
	# Смена языка: непередактированные поля следуют языку, изменённые — нет.
	desc_edit.text = "legs"
	TranslationServer.set_locale("ru")
	s.refresh()
	assert_eq(name_edit.text, "Тренировка " + date, "название перерисовано на русском")
	assert_eq(desc_edit.text, "legs", "правка пользователя сохранена")
	TranslationServer.set_locale("en")
	var got: Array = []
	s.upload_requested.connect(func(id: String, n: String, desc: String) -> void: got.append([id, n, desc]))
	name_edit.text = "  Morning Neo  "
	d.request_upload()
	assert_eq(got, [[untitled.id, "Morning Neo", "legs"]], "значения полей уходят с сигналом")
	_rides.update_upload_status(untitled.id, {"strava_status": Ride.UPLOAD_DONE, "strava_activity_id": "1"})
	assert_false(d.is_upload_fields_editable(), "выгруженный заезд — поля недоступны")


# ---------------------------------------------------------------------------
# Экспорт FIT (REQ-LOC-05 крит. 5, 6)
# ---------------------------------------------------------------------------

func test_default_export_file_name_is_date_and_name() -> void:
	var r := _ride(_pa, 1700000000, 60, "Sweet spot 3x10")
	_rides.save(r)
	var s := _screen()
	s.select_index(0)
	# Дата — локальная, как в списке (REQ-LOC-05 крит. 6): заезд в 01:00 MSK не должен
	# получать вчерашнюю дату UTC.
	var local_date: String = HistoryScreen.format_date_time(1700000000).substr(0, 10)
	assert_eq(s.detail().default_export_file_name(), "%s_Sweet_spot_3x10.fit" % local_date)
	assert_eq(s.rows()[0].substr(0, 10), local_date, "та же дата, что в списке")
	assert_eq(RideDetail.sanitize_file_name("  a/b:c*d  "), "abcd")
	assert_eq(RideDetail.sanitize_file_name("///"), "ride")


func test_export_writes_valid_fit_file() -> void:
	var rides := _three_rides()
	var s := _screen()
	s.show_ride(rides[2].id)
	var path := ProjectSettings.globalize_path(_dir).path_join("export.fit")
	var dialog: FileDialog = s.detail().get_node("%ExportDialog")
	dialog.file_selected.emit(path)  # как после системного диалога сохранения
	assert_true(FileAccess.file_exists(path))
	var res := FitDecoder.decode(FileAccess.get_file_as_bytes(path))
	assert_true(res.ok, "FIT валиден: %s" % res.error)
	assert_true(res.header_crc_ok)
	assert_true(res.file_crc_ok)
	assert_eq(res.count(FitDefinitions.MSG_RECORD), 90)
	assert_eq(res.first_field(FitDefinitions.MSG_SESSION, FitDefinitions.SESSION_SUB_SPORT), 58)
	assert_string_contains(s.detail().export_status_text(), "export.fit")


func test_export_to_unwritable_path_reports_failure() -> void:
	_three_rides()
	var s := _screen()
	s.select_index(0)
	assert_false(s.detail().export_to_path(ProjectSettings.globalize_path(_dir).path_join("no_such_dir/x.fit")))
	assert_push_error("AtomicFile", "запись через AtomicFile: ошибка открытия временного файла в журнале")
	var err := FileAccess.get_open_error()
	assert_string_contains(s.detail().export_status_text(), "Export failed")
	assert_eq(s.detail().export_status_text(), tr("ui.history.export.failed").format({"reason": s.detail().export_error_text(err)}),
		"причина — переведённый ключ, не error_string()")
	assert_false(s.detail().export_status_text().contains(error_string(err)), "текст движка не показывается")


func test_export_is_atomic_write_error_keeps_existing_file() -> void:
	var rides := _three_rides()
	var s := _screen()
	s.show_ride(rides[2].id)
	var path := ProjectSettings.globalize_path(_dir).path_join("export.fit")
	assert_true(s.detail().export_to_path(path))
	var before := FileAccess.get_file_as_bytes(path)
	s.show_ride(rides[0].id)
	AtomicFile.simulate_write_error_prefix = path
	assert_false(s.detail().export_to_path(path), "сбой записи — экспорт не удался")
	assert_push_error("AtomicFile")
	assert_eq(FileAccess.get_file_as_bytes(path), before, "прежний файл по этому пути цел")
	assert_false(FileAccess.file_exists(AtomicFile.tmp_path(path)), "временный файл удалён")
	assert_eq(s.detail().export_status_text(),
		tr("ui.history.export.failed").format({"reason": tr("ui.history.export.error.cant_write")}))


func test_strava_storage_failed_error_is_translated_in_detail() -> void:
	var r := _ride(_pa, 1700000000, 60, "Token lost")
	r.upload["strava_status"] = Ride.UPLOAD_FAILED
	r.upload["last_error_code"] = ApiResult.CODE_STORAGE_FAILED
	r.upload["last_error"] = "не удалось сохранить токены Strava в защищённое хранилище"
	_rides.save(r)
	var s := _screen()
	s.select_index(0)
	assert_string_contains(s.detail().status_text(), "could not save to secure storage", "REQ-NFR-08: причина по коду")
	assert_false(s.detail().status_text().contains(ApiResult.CODE_STORAGE_FAILED), "без сырого кода")
	assert_false(s.detail().status_text().contains(tr("ui.history.strava.error.unknown")), "не «неизвестная ошибка»")
	TranslationServer.set_locale("ru")
	assert_string_contains(s.detail().strava_error_text(ApiResult.CODE_STORAGE_FAILED), "защищённое хранилище")
	TranslationServer.set_locale("en")


# ---------------------------------------------------------------------------
# Удаление (REQ-LOC-06 крит. 1, 2)
# ---------------------------------------------------------------------------

func test_delete_requires_confirmation_and_cancel_keeps_ride() -> void:
	var rides := _three_rides()
	var s := _screen()
	s.show_ride(rides[0].id)
	assert_true(s.detail().request_delete())
	assert_true(s.detail().is_delete_pending())
	s.detail().cancel_delete()
	assert_false(s.detail().is_delete_pending())
	assert_not_null(_rides.get_ride(rides[0].id), "отмена ничего не удаляет")
	assert_true(s.is_detail_visible())
	assert_eq(_rides.list(_pa.id).size(), 3)


func test_confirm_delete_removes_ride_and_returns_to_list() -> void:
	var rides := _three_rides()
	var s := _screen()
	var deleted: Array[String] = []
	s.detail().deleted.connect(func(id: String) -> void: deleted.append(id))
	s.show_ride(rides[0].id)
	s.detail().request_delete()
	s.detail().confirm_delete()
	assert_eq(deleted, [rides[0].id])
	assert_null(_rides.get_ride(rides[0].id), "REQ-LOC-06 крит. 1: заезда нет в хранилище")
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir + "rides/").path_join(_pa.id).path_join(rides[0].id)), "каталог удалён")
	assert_false(s.is_detail_visible())
	assert_eq(s.row_count(), 2)
	assert_null(s.detail().ride())


func test_deleting_uploaded_ride_does_not_touch_strava() -> void:
	var r := _ride(_pa, 1700000000, 60, "Uploaded")
	r.upload["strava_status"] = Ride.UPLOAD_DONE
	r.upload["strava_activity_id"] = "777"
	_rides.save(r)
	var transport := MockHttpTransport.new()
	var s := _screen()
	s.show_ride(r.id)
	s.detail().request_delete()
	s.detail().confirm_delete()
	assert_null(_rides.get_ride(r.id))
	assert_eq(transport.requests.size(), 0, "REQ-LOC-06 крит. 2: HTTP-запросов на удаление нет")


# ---------------------------------------------------------------------------
# main.tscn: восстановление (REQ-LOC-07 крит. 3) и запись заезда из тренировки
# ---------------------------------------------------------------------------

func _main() -> AppMain:
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	add_child_autofree(main)
	return main


func _single_profile() -> void:
	# Один профиль → правило старта выбирает его автоматически и испускает profile_selected.
	assert_eq(_profiles.delete(_pb.id), "")


func _in_progress_ride(n: int) -> Ride:
	var r := _ride(_pa, 1700000000, n, "Crashed ride")
	r.metadata["in_progress"] = true
	r.summary = RideSummary.new()
	_rides.save(r)
	return r


func test_main_recovers_in_progress_ride_and_keep_saves_it_as_stopped_early() -> void:
	_single_profile()
	var r := _in_progress_ride(25)
	var main := _main()
	var dialog := main.recovery_dialog()
	assert_not_null(dialog.current_ride(), "диалог восстановления показан")
	assert_eq(dialog.current_ride().id, r.id)
	assert_string_contains(dialog.dialog_text, "Crashed ride")
	dialog.keep()
	assert_null(dialog.current_ride())
	var back := main.ride_repository.get_ride(r.id)
	assert_not_null(back)
	assert_true(back.is_recovered())
	assert_false(back.is_in_progress())
	assert_true(back.stopped_early(), "сохранён как завершённый досрочно")
	assert_eq(back.samples.size(), 25)
	assert_eq(back.summary.duration_sec, 25, "сводка по имеющимся данным")
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	assert_true(main.visible_screen_node() == history)
	assert_eq(history.row_count(), 1)
	assert_string_contains(history.rows()[0], "recovered")


func test_main_recovery_delete_removes_ride() -> void:
	_single_profile()
	var r := _in_progress_ride(12)
	var main := _main()
	var dialog := main.recovery_dialog()
	assert_eq(dialog.current_ride().id, r.id)
	dialog.delete_current()
	assert_null(main.ride_repository.get_ride(r.id))
	assert_eq(main.ride_repository.list(_pa.id).size(), 0)
	assert_eq(main.ride_repository.recover_in_progress(_pa.id).size(), 0)


func test_main_without_in_progress_rides_shows_no_dialog() -> void:
	_single_profile()
	_rides.save(_ride(_pa, 1700000000, 10, "Done"))
	var main := _main()
	assert_null(main.recovery_dialog().current_ride())
	assert_false(main.recovery_dialog().visible)


func test_main_delete_from_history_removes_strava_queue_item_without_requests() -> void:
	_single_profile()
	var r := _ride(_pa, 1700000000, 60, "Queued")
	_rides.save(r)
	var main := _main()
	var transport := main.transport as MockHttpTransport
	assert_not_null(main.strava, "сервис Strava активного профиля создан")
	main.strava.queue.enqueue(r.id, Callable(), "Queued", "", r.started_at_unix)
	assert_true(main.strava.queue.has(r.id))
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	assert_true(history.show_ride(r.id))
	var deleted: Array[String] = []
	history.ride_deleted.connect(func(id: String) -> void: deleted.append(id))
	history.detail().request_delete()
	history.detail().confirm_delete()
	assert_eq(deleted, [r.id], "экран сообщил владельцу об удалении")
	assert_null(main.ride_repository.get_ride(r.id))
	assert_false(main.strava.queue.has(r.id), "REQ-LOC-06 крит. 1: элемент очереди Strava удалён")
	assert_eq(history.row_count(), 0)
	assert_eq(transport.request_count(), 0, "REQ-LOC-06 крит. 2: HTTP-запросов нет")


func test_main_emulator_workout_to_finish_appears_in_history_with_samples_and_summary() -> void:
	_single_profile()
	var main := _main()
	var ws := main.workout_screen()
	ws.clock_usec = _clock
	var home: HomeScreen = main.screen_node(AppState.Screen.HOME)
	home.emulator_workout_requested.emit()
	assert_eq(main.app_state.current_screen, AppState.Screen.WORKOUT)
	assert_not_null(main.ride_recorder, "запись заезда началась вместе с сессией")
	assert_true(main.ride_recorder.is_recording())
	var ride_id := main.ride_recorder.ride_id()
	assert_eq(main.ride_repository.list(_pa.id).size(), 1)
	assert_true(main.ride_repository.list(_pa.id)[0].in_progress)
	_now_usec += 180 * 1_000_000
	ws.ticker().poll()
	assert_eq(ws.session().get_state(), WorkoutSession.State.FINISHED)
	assert_not_null(main.last_finished_session)
	assert_false(main.ride_recorder.is_recording())
	var ride := main.ride_repository.get_ride(ride_id)
	assert_not_null(ride)
	assert_eq(ride.samples.size(), 180, "тестовый план 60+30+90 с")
	assert_false(ride.is_in_progress())
	assert_eq(ride.summary.duration_sec, 180)
	assert_gt(ride.summary.avg_power_w, 50)
	assert_eq(ride.summary.total_power_zone_sec(), ride.summary.power_sample_count)
	assert_eq(ride.ftp_w(), FTP)
	assert_eq(ride.name, "dev-3-steps")
	ws.go_home()
	main.app_state.navigate(AppState.Screen.HISTORY)
	var history := main.history_screen()
	assert_eq(history.row_count(), 1)
	assert_string_contains(history.rows()[0], "dev-3-steps")
	assert_string_contains(history.rows()[0], "03:00")
	history.select_index(0)
	assert_eq(history.detail().series().count(RideSeries.POWER), 180)


func test_main_early_stop_saves_ride_marked_stopped_early() -> void:
	_single_profile()
	var main := _main()
	var ws := main.workout_screen()
	ws.clock_usec = _clock
	(main.screen_node(AppState.Screen.HOME) as HomeScreen).emulator_workout_requested.emit()
	_now_usec += 45 * 1_000_000
	ws.ticker().poll()
	ws.confirm_stop()
	var ride := main.ride_repository.get_ride(main.ride_recorder.ride_id())
	assert_true(ride.stopped_early(), "REQ-WRK-05 крит. 4")
	assert_eq(ride.samples.size(), 45, "фактическая длительность")
	assert_false(ride.is_in_progress())
