extends GutTest
## Потоковая запись заезда и восстановление после сбоя (REQ-LOC-07 крит. 1–4;
## REQ-LOC-01 крит. 1 — заезд из `WorkoutSession` через `Ride.from_session`;
## REQ-WRK-05 крит. 4 — досрочное завершение помечается). Часы — тики сессии с `FakeTrainer`.

const FTP: int = 200
const SEED: int = 11

var _dir: String
var _repo: FileRideRepository
var _trainer: FakeTrainer
var _session: WorkoutSession
var _profile: Profile
var _recorder: RideRecorder


func before_each() -> void:
	_dir = "user://test_recorder_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_repo = FileRideRepository.new(_dir)
	_trainer = FakeTrainer.new(SEED)
	_trainer.connect_delay_sec = 0.0
	_trainer.set_heart_rate(150)
	_trainer.connect_device("fake-rec")
	_profile = Profile.create("Rider")
	_profile.ftp_w = FTP
	_profile.weight_kg = 72.0
	_profile.max_hr = 185


func after_each() -> void:
	if _recorder != null:
		_recorder.dispose()
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


func _plan(total_sec: int = 60) -> Workout:
	var steps: Array[WorkoutStep] = [WorkoutStep.watts(total_sec / 2, 150.0), WorkoutStep.watts(total_sec - total_sec / 2, 250.0)]
	return Workout.make("Recorder plan", steps, "zwo")


func _start(total_sec: int = 60) -> void:
	_session = WorkoutSession.new(_plan(total_sec), _trainer, FTP, 1.0, _profile.weight_kg)
	_recorder = RideRecorder.new(_repo, _profile, _session)
	_session.start()


func _ticks(n: int, delta: float = 1.0) -> void:
	for i in n:
		_session.tick(delta)


# ---------------------------------------------------------------------------
# Старт
# ---------------------------------------------------------------------------

func test_start_creates_in_progress_ride_with_session_and_profile_metadata() -> void:
	_start()
	assert_false(_recorder.ride_id().is_empty())
	assert_true(_recorder.is_recording())
	var list := _repo.list(_profile.id)
	assert_eq(list.size(), 1)
	assert_true(list[0].in_progress, "metadata.in_progress = true")
	var ride := _repo.get_ride(_recorder.ride_id())
	assert_true(ride.is_in_progress())
	assert_eq(ride.ftp_w(), FTP)
	assert_eq(ride.max_hr(), 185)
	assert_almost_eq(float(ride.metadata["weight_kg"]), 72.0, 1e-6)
	assert_eq(ride.metadata["workout_name"], "Recorder plan")
	assert_eq(ride.metadata["workout_source"], "zwo")
	assert_eq(ride.name, "Recorder plan")
	assert_eq(ride.started_at_unix, _session.started_at_unix)
	assert_eq(ride.samples.size(), 0)


func test_nothing_is_written_before_start() -> void:
	_session = WorkoutSession.new(_plan(), _trainer, FTP)
	_recorder = RideRecorder.new(_repo, _profile, _session)
	assert_eq(_recorder.ride_id(), "")
	assert_false(_recorder.is_recording())
	assert_eq(_repo.list(_profile.id).size(), 0)


# ---------------------------------------------------------------------------
# REQ-LOC-07 крит. 1: сброс каждые 10 с сессионного времени
# ---------------------------------------------------------------------------

func test_samples_are_flushed_every_10_seconds() -> void:
	_start()
	_ticks(9)
	assert_eq(_recorder.flush_count, 0)
	assert_eq(_repo.get_ride(_recorder.ride_id()).samples.size(), 0, "до 10 с на диске пусто")
	_ticks(1)
	assert_eq(_recorder.flush_count, 1)
	assert_eq(_repo.get_ride(_recorder.ride_id()).samples.size(), 10)
	_ticks(15)
	assert_eq(_recorder.flush_count, 2)
	assert_eq(_repo.get_ride(_recorder.ride_id()).samples.size(), 20, "на диске — до последнего сброса")
	assert_eq(_session.samples.size(), 25)


func test_flush_interval_counts_session_time_not_pause() -> void:
	_start()
	_ticks(5)
	_session.pause()
	_ticks(30, 1.0)  # 30 с реального времени на паузе
	_session.resume()
	_ticks(4)
	assert_eq(_recorder.flush_count, 0, "на паузе сессионное время не идёт")
	_ticks(1)
	assert_eq(_recorder.flush_count, 1)
	var ride := _repo.get_ride(_recorder.ride_id())
	assert_eq(ride.samples.size(), 10)
	var pauses := ride.pause_events()
	assert_eq(pauses.size(), 1, "событие паузы сброшено вместе с метаданными")
	assert_almost_eq(float(pauses[0]["duration_sec"]), 30.0, 1e-6)
	assert_almost_eq(ride.paused_total_sec(), 30.0, 1e-6)


func test_pause_flushes_metadata_immediately() -> void:
	_start()
	_ticks(3)
	_session.pause()
	var ride := _repo.get_ride(_recorder.ride_id())
	assert_eq(ride.pause_events().size(), 1)
	assert_true(ride.is_in_progress())


func test_flushed_signal_reports_session_time() -> void:
	_start()
	var times: Array[int] = []
	_recorder.flushed.connect(func(t: int) -> void: times.append(t))
	_ticks(30)
	assert_eq(times, [10, 20, 30])


func test_flush_works_with_fractional_ticks() -> void:
	_start()
	_ticks(100, 0.2)  # 20 с
	assert_eq(_recorder.flush_count, 2)
	assert_eq(_repo.get_ride(_recorder.ride_id()).samples.size(), 20)


# ---------------------------------------------------------------------------
# Завершение
# ---------------------------------------------------------------------------

func test_finish_writes_summary_and_clears_in_progress() -> void:
	_start(30)
	_ticks(30)
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)
	assert_false(_recorder.is_recording())
	assert_false(_session.state_changed.is_connected(_recorder._on_state_changed), "после FINISHED подписки сняты")
	var ride := _repo.get_ride(_recorder.ride_id())
	assert_false(ride.is_in_progress())
	assert_false(ride.is_recovered())
	assert_false(ride.stopped_early())
	assert_eq(ride.samples.size(), 30)
	assert_eq(ride.summary.duration_sec, 30)
	assert_gt(ride.summary.avg_power_w, 100)
	assert_eq(ride.summary.avg_hr, 150)
	assert_eq(ride.summary.total_power_zone_sec(), ride.summary.power_sample_count)
	assert_eq(ride.summary.time_in_hr_zones.size(), 5, "зоны пульса профиля (max_hr 185)")
	assert_eq(ride.speed_source(), SampleStream.SPEED_SOURCE_MODEL, "новый заезд — модель (У-30)")
	assert_eq(ride.samples.speed_source, SampleStream.SPEED_SOURCE_MODEL)
	var list := _repo.list(_profile.id)
	assert_eq(list.size(), 1)
	assert_false(list[0].in_progress)
	assert_eq(list[0].avg_power_w, ride.summary.avg_power_w)


func test_early_stop_marks_ride_stopped_early_with_actual_duration() -> void:
	_start(60)
	_ticks(17)
	_session.stop()
	var ride := _repo.get_ride(_recorder.ride_id())
	assert_true(ride.stopped_early(), "REQ-WRK-05 крит. 4")
	assert_false(ride.is_in_progress())
	assert_eq(ride.samples.size(), 17)
	assert_eq(ride.summary.duration_sec, 17)
	assert_eq(int(ride.metadata["elapsed_sec"]), 17)


func test_model_speed_source_is_recorded_when_trainer_has_no_speed() -> void:
	_trainer.emit_speed = false
	_start(20)
	_ticks(20)
	var ride := _repo.get_ride(_recorder.ride_id())
	assert_eq(ride.speed_source(), SampleStream.SPEED_SOURCE_MODEL, "В-8")
	assert_eq(ride.samples.speed_source, SampleStream.SPEED_SOURCE_MODEL)
	assert_gt(ride.samples.total_distance_m(), 0.0)


# ---------------------------------------------------------------------------
# REQ-LOC-07 крит. 2, 3: сбой и восстановление
# ---------------------------------------------------------------------------

func test_crash_recovery_keeps_samples_up_to_last_flush_with_loss_at_most_10s() -> void:
	_start(120)
	_ticks(7)
	_session.pause()
	_ticks(4)
	_session.resume()
	_ticks(18)  # активное время 25 с, последний сброс на 20 с
	# «Сбой»: сессия и записывающий просто исчезают без завершения (dispose ничего не пишет).
	var ride_id := _recorder.ride_id()
	_recorder.dispose()
	_recorder = null
	_session = null
	var fresh := FileRideRepository.new(_dir)
	var before := fresh.list(_profile.id)
	assert_eq(before.size(), 1)
	assert_true(before[0].in_progress, "незавершённый заезд виден")
	var recovered := fresh.recover_in_progress(_profile.id)
	assert_eq(recovered.size(), 1)
	var ride := recovered[0]
	assert_eq(ride.id, ride_id)
	assert_eq(ride.samples.size(), 20, "все сэмплы до последнего сброса")
	assert_lte(25 - ride.samples.size(), 10, "потеря ≤ 10 с")
	assert_true(ride.is_recovered())
	assert_false(ride.is_in_progress())
	assert_true(ride.stopped_early(), "предлагается как «завершённый досрочно»")
	assert_eq(ride.summary.duration_sec, 20)
	assert_gt(ride.summary.avg_power_w, 0)
	assert_eq(ride.pause_events().size(), 1, "события сохранены")
	assert_true(ride.samples.is_monotonic())


func test_recovered_ride_is_persisted_and_not_recovered_twice() -> void:
	_start(120)
	_ticks(31)
	_recorder.dispose()
	_recorder = null
	_session = null
	var fresh := FileRideRepository.new(_dir)
	assert_eq(fresh.recover_in_progress(_profile.id).size(), 1)
	var again := FileRideRepository.new(_dir)
	assert_eq(again.recover_in_progress(_profile.id).size(), 0, "повторно не поднимается")
	var list := again.list(_profile.id)
	assert_eq(list.size(), 1)
	assert_true(list[0].recovered)
	assert_false(list[0].in_progress)
	assert_eq(list[0].duration_sec, 30)
	assert_eq(again.get_ride(list[0].ride_id).samples.size(), 30)


func test_recovered_ride_can_be_deleted_instead() -> void:
	_start(120)
	_ticks(12)
	var ride_id := _recorder.ride_id()
	_recorder.dispose()
	_recorder = null
	_session = null
	var fresh := FileRideRepository.new(_dir)
	assert_true(fresh.delete(ride_id), "вариант «удалить»")
	assert_eq(fresh.recover_in_progress(_profile.id).size(), 0)
	assert_eq(fresh.list(_profile.id).size(), 0)


func test_recover_ignores_other_profiles_and_finished_rides() -> void:
	_start(20)
	_ticks(20)  # завершён
	var other := Profile.create("Other")
	other.ftp_w = 250
	var t2 := FakeTrainer.new(SEED)
	t2.connect_delay_sec = 0.0
	t2.connect_device("fake-2")
	var s2 := WorkoutSession.new(_plan(100), t2, 250)
	var r2 := RideRecorder.new(_repo, other, s2)
	s2.start()
	for i in 15:
		s2.tick(1.0)
	var fresh := FileRideRepository.new(_dir)
	assert_eq(fresh.recover_in_progress(_profile.id).size(), 0, "завершённый заезд не трогается")
	var rec := fresh.recover_in_progress(other.id)
	assert_eq(rec.size(), 1)
	assert_eq(rec[0].id, r2.ride_id())
	assert_eq(rec[0].samples.size(), 10)
	r2.dispose()


# ---------------------------------------------------------------------------
# REQ-LOC-07 крит. 4: бюджет тика
# ---------------------------------------------------------------------------

func test_flush_tick_with_600_accumulated_samples_takes_at_most_50ms() -> void:
	_start(1200)
	_ticks(600)
	var t0: int = Time.get_ticks_msec()
	_session.tick(1.0)  # 601-я секунда: без сброса
	var plain_ms: int = Time.get_ticks_msec() - t0
	_ticks(8)
	t0 = Time.get_ticks_msec()
	_session.tick(1.0)  # 610-я секунда: сброс
	var flush_tick_ms: int = Time.get_ticks_msec() - t0
	gut.p("тик без сброса %d мс, тик со сбросом (610 сэмплов) %d мс, сам сброс %d мс" % [plain_ms, flush_tick_ms, _recorder.last_flush_ms])
	assert_eq(_recorder.flush_count, 61)
	assert_lte(flush_tick_ms, 50, "REQ-LOC-07 крит. 4")


func test_final_save_of_3600_samples_is_fast() -> void:
	_start(3600)
	_ticks(3599)
	var t0: int = Time.get_ticks_msec()
	_session.tick(1.0)  # финальная запись: сводка + полный поток
	var ms: int = Time.get_ticks_msec() - t0
	gut.p("финальная запись 3600 сэмплов: %d мс (сам сброс %d мс)" % [ms, _recorder.last_flush_ms])
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)
	assert_lte(_recorder.last_flush_ms, 200, "полная перезапись 3600 сэмплов укладывается в бюджет")
	assert_eq(_repo.get_ride(_recorder.ride_id()).samples.size(), 3600)
