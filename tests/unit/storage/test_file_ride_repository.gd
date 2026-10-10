extends GutTest
## Файловое хранилище заездов (REQ-LOC-01 крит. 1–5, REQ-LOC-02 крит. 1, 2,
## REQ-LOC-06 крит. 1, REQ-STR-05 крит. 2, REQ-PRF-04 крит. 1, решение В-3/В-8).
## Тесты формулируются через интерфейс `RideRepository`; файлы читаются напрямую
## только для порчи (устойчивость).

const FTP: int = 200
const PROFILE_A: String = "profile-a"
const PROFILE_B: String = "profile-b"

var _dir: String
var _repo: FileRideRepository
var _changed: Array[String] = []


func before_each() -> void:
	_dir = "user://test_rides_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_changed = []
	_repo = _open()


func after_each() -> void:
	_remove_tree(ProjectSettings.globalize_path(_dir))


func _open() -> FileRideRepository:
	var r := FileRideRepository.new(_dir)
	r.rides_changed.connect(func(pid: String) -> void: _changed.append(pid))
	return r


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


func _abs(rel: String) -> String:
	return ProjectSettings.globalize_path(_dir).path_join(rel)


## Поток с данными и пропусками: слот 2 без телеметрии, слот 3 без пульса.
func _stream(n: int = 6) -> SampleStream:
	var s := SampleStream.new()
	s.speed_source = Ride.SPEED_SOURCE_TRAINER_LEGACY
	for i in n:
		var sample: TrainerSample = TrainerSample.full(float(i + 1), 200 + i, 90, 30.0 + i) if i != 2 else null
		var hr: int = 140 + i if i != 3 else -1
		s.append(i, sample, hr, 210, i / 3, i % 2 == 0, -1.0, {"power": 1, "cadence": 1, "heart_rate": 2})
	return s


func _ride(profile_id: String = PROFILE_A, started_at: int = 1700000000, n: int = 6, name: String = "Test ride") -> Ride:
	var r := Ride.new()
	r.id = Ride.generate_id(started_at)
	r.profile_id = profile_id
	r.started_at_unix = started_at
	r.name = name
	r.description = "desc"
	r.workout = WorkoutSerializer.to_dict(Workout.make(name, [WorkoutStep.watts(60, 200.0)] as Array[WorkoutStep], "zwo"))
	r.metadata = {
		"workout_name": name, "workout_source": "zwo", "started_at_unix": started_at,
		"ftp_w": FTP, "weight_kg": 75.5, "max_hr": 185, "intensity": 1.05, "stopped_early": true,
		"speed_source": Ride.SPEED_SOURCE_TRAINER_LEGACY, "elapsed_sec": n, "paused_total_sec": 3.0,
		"in_progress": false, "recovered": false,
	}
	r.events = [
		{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0},
		{"type": WorkoutSession.EVENT_PAUSE, "at_sec": 2.0, "value": 2, "duration_sec": 3.0, "until_sec": 5.0},
		{"type": WorkoutSession.EVENT_RESUME, "at_sec": 2.0, "value": 2},
		{"type": WorkoutSession.EVENT_SKIP, "at_sec": 4.0, "value": 0},
		{"type": WorkoutSession.EVENT_ERG_OFF, "at_sec": 4.5, "value": 4.5},
		{"type": WorkoutSession.EVENT_DISCONNECT, "at_sec": 5.0, "value": "RECONNECTING"},
	]
	r.samples = _stream(n)
	r.compute_summary()
	return r


# ---------------------------------------------------------------------------
# REQ-LOC-01 крит. 1, 2, 4: round-trip
# ---------------------------------------------------------------------------

func test_save_and_get_ride_round_trip_metadata_events_and_samples() -> void:
	var ride := _ride()
	var id := _repo.save(ride)
	assert_eq(id, ride.id)
	var back := _repo.get_ride(id)
	assert_not_null(back)
	assert_eq(back.id, ride.id)
	assert_eq(back.profile_id, PROFILE_A)
	assert_eq(back.started_at_unix, 1700000000)
	assert_eq(back.name, "Test ride")
	assert_eq(back.description, "desc")
	# Метаданные LOC-01 крит. 1
	assert_eq(back.metadata["workout_name"], "Test ride")
	assert_eq(back.metadata["workout_source"], "zwo")
	assert_eq(back.ftp_w(), FTP)
	assert_almost_eq(float(back.metadata["weight_kg"]), 75.5, 1e-6)
	assert_eq(back.max_hr(), 185)
	assert_almost_eq(float(back.metadata["intensity"]), 1.05, 1e-6)
	assert_true(back.stopped_early())
	assert_eq(back.speed_source(), Ride.SPEED_SOURCE_TRAINER_LEGACY, "speed_source (В-8)")
	# План
	assert_eq(back.workout["name"], "Test ride")
	assert_eq((back.workout["steps"] as Array).size(), 1)
	# События LOC-01 крит. 4
	assert_eq(back.events.size(), 6)
	assert_eq(back.events[1]["type"], WorkoutSession.EVENT_PAUSE)
	assert_almost_eq(float(back.events[1]["duration_sec"]), 3.0, 1e-6)
	assert_eq(back.events[5]["value"], "RECONNECTING")
	# Сэмплы LOC-01 крит. 2
	assert_eq(back.samples.size(), 6)
	assert_eq(back.samples.speed_source, Ride.SPEED_SOURCE_TRAINER_LEGACY)
	for i in 6:
		assert_eq_deep(back.samples.row(i), ride.samples.row(i))


func test_has_flags_survive_round_trip() -> void:
	var ride := _ride()
	_repo.save(ride)
	var back := _repo.get_ride(ride.id)
	assert_false(back.samples.has_power[2], "слот без телеметрии")
	assert_false(back.samples.has_cadence[2])
	assert_false(back.samples.has_speed[2])
	assert_true(back.samples.has_power[1])
	assert_false(back.samples.has_heart_rate[3], "слот без пульса")
	assert_true(back.samples.has_heart_rate[1])
	assert_eq(back.samples.heart_rate_age_sec[3], 2)
	assert_eq(back.samples.power_age_sec[2], 1)
	assert_eq(Array(back.samples.erg_enabled), [true, false, true, false, true, false])
	assert_eq(Array(back.samples.step_index), [0, 0, 0, 1, 1, 1])
	assert_eq(Array(back.samples.target_w), [210, 210, 210, 210, 210, 210])


func test_summary_and_upload_round_trip() -> void:
	var ride := _ride()
	ride.upload["strava_status"] = Ride.UPLOAD_QUEUED
	ride.upload["attempts"] = 2
	_repo.save(ride)
	var back := _repo.get_ride(ride.id)
	assert_eq(back.upload["strava_status"], Ride.UPLOAD_QUEUED)
	assert_eq(int(back.upload["attempts"]), 2)
	assert_eq(back.summary.avg_power_w, ride.summary.avg_power_w)
	assert_eq(back.summary.duration_sec, 6)
	assert_eq(Array(back.summary.time_in_power_zones), Array(ride.summary.time_in_power_zones))


func test_get_unknown_ride_returns_null() -> void:
	assert_null(_repo.get_ride("nope"))
	assert_null(_repo.get_ride(""))


func test_save_without_profile_is_rejected() -> void:
	var ride := _ride()
	ride.profile_id = ""
	assert_eq(_repo.save(ride), "")


func test_save_generates_id_when_missing() -> void:
	var ride := _ride()
	ride.id = ""
	var id := _repo.save(ride)
	assert_false(id.is_empty())
	assert_not_null(_repo.get_ride(id))


func test_new_repository_instance_on_same_dir_sees_rides() -> void:
	var ride := _ride()
	_repo.save(ride)
	var other := FileRideRepository.new(_dir)
	assert_eq(other.list(PROFILE_A).size(), 1)
	var back := other.get_ride(ride.id)
	assert_not_null(back)
	assert_eq(back.samples.size(), 6)


# ---------------------------------------------------------------------------
# REQ-LOC-02 крит. 1, REQ-LOC-01 крит. 3, REQ-PRF-04 крит. 1: список
# ---------------------------------------------------------------------------

func test_list_is_sorted_newest_first_and_has_list_fields() -> void:
	_repo.save(_ride(PROFILE_A, 1700000000, 6, "old"))
	_repo.save(_ride(PROFILE_A, 1700009000, 6, "new"))
	_repo.save(_ride(PROFILE_A, 1700005000, 6, "mid"))
	var list := _repo.list(PROFILE_A)
	assert_eq(list.size(), 3)
	assert_eq([list[0].name, list[1].name, list[2].name], ["new", "mid", "old"])
	assert_eq(list[0].started_at_unix, 1700009000)
	assert_eq(list[0].duration_sec, 6)
	assert_eq(list[0].avg_power_w, 203, "(200+201+203+204+205)/5 = 202.6")
	assert_eq(list[0].strava_status, Ride.UPLOAD_NONE)
	assert_true(list[0].stopped_early)


func test_rides_are_isolated_per_profile() -> void:
	var a := _ride(PROFILE_A)
	var b := _ride(PROFILE_B)
	_repo.save(a)
	_repo.save(b)
	var list_a := _repo.list(PROFILE_A)
	var list_b := _repo.list(PROFILE_B)
	assert_eq(list_a.size(), 1)
	assert_eq(list_a[0].ride_id, a.id)
	assert_eq(list_b.size(), 1)
	assert_eq(list_b[0].ride_id, b.id)
	assert_eq(_repo.list("profile-c").size(), 0)


func test_list_returns_copies() -> void:
	_repo.save(_ride())
	var list := _repo.list(PROFILE_A)
	list[0].name = "mutated"
	assert_eq(_repo.list(PROFILE_A)[0].name, "Test ride")


func test_list_of_500_rides_takes_at_most_one_second() -> void:
	for i in 500:
		var r := _ride(PROFILE_A, 1700000000 + i * 60, 3, "ride %d" % i)
		_repo.save(r)
	var fresh := FileRideRepository.new(_dir)
	var t0: int = Time.get_ticks_msec()
	var list := fresh.list(PROFILE_A)
	var cold_ms: int = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	fresh.list(PROFILE_A)
	var warm_ms: int = Time.get_ticks_msec() - t0
	gut.p("list(500): холодный %d мс, тёплый %d мс" % [cold_ms, warm_ms])
	assert_eq(list.size(), 500)
	assert_lte(cold_ms, 1000, "REQ-LOC-02 крит. 2: 500 заездов ≤ 1 с")
	assert_eq(list[0].name, "ride 499", "новые сверху")


# ---------------------------------------------------------------------------
# REQ-LOC-06 крит. 1: удаление
# ---------------------------------------------------------------------------

func test_delete_removes_ride_directory_and_list_entry() -> void:
	var ride := _ride()
	_repo.save(ride)
	var ride_dir := _abs(PROFILE_A).path_join(ride.id)
	assert_true(DirAccess.dir_exists_absolute(ride_dir), "каталог заезда создан")
	assert_true(_repo.delete(ride.id))
	assert_false(DirAccess.dir_exists_absolute(ride_dir), "каталог заезда удалён")
	assert_null(_repo.get_ride(ride.id))
	assert_eq(_repo.list(PROFILE_A).size(), 0)
	assert_eq(FileRideRepository.new(_dir).list(PROFILE_A).size(), 0, "и после перечитывания")


func test_delete_unknown_returns_false() -> void:
	assert_false(_repo.delete("nope"))


func test_delete_profile_rides_removes_all_and_returns_count() -> void:
	_repo.save(_ride(PROFILE_A, 1700000000))
	_repo.save(_ride(PROFILE_A, 1700001000))
	_repo.save(_ride(PROFILE_B, 1700002000))
	assert_eq(_repo.delete_profile_rides(PROFILE_A), 2)
	assert_eq(_repo.list(PROFILE_A).size(), 0)
	assert_eq(_repo.list(PROFILE_B).size(), 1, "другой профиль не тронут")
	assert_false(DirAccess.dir_exists_absolute(_abs(PROFILE_A)))


func test_profile_deletion_cascades_to_rides_via_hook() -> void:
	var profiles := ProfileRepository.new(_dir + "profiles/")
	var pa := profiles.create("A")
	var pb := profiles.create("B")
	assert_not_null(pa)
	assert_not_null(pb)
	_repo.attach_to_profiles(profiles)
	_repo.save(_ride(pa.id))
	_repo.save(_ride(pb.id))
	assert_eq(profiles.delete(pa.id), "")
	assert_eq(_repo.list(pa.id).size(), 0, "REQ-PRF-04 крит. 1: заезды удалённого профиля удалены")
	assert_eq(_repo.list(pb.id).size(), 1)


# ---------------------------------------------------------------------------
# REQ-STR-05 крит. 2: статус выгрузки
# ---------------------------------------------------------------------------

func test_update_upload_status_persists_in_metadata_and_list() -> void:
	var ride := _ride()
	_repo.save(ride)
	assert_true(_repo.update_upload_status(ride.id, {"strava_status": Ride.UPLOAD_DONE, "strava_activity_id": "987", "attempts": 1}))
	var back := _repo.get_ride(ride.id)
	assert_eq(back.upload["strava_status"], Ride.UPLOAD_DONE)
	assert_eq(back.upload["strava_activity_id"], "987")
	assert_eq(int(back.upload["attempts"]), 1)
	var entry := _repo.list(PROFILE_A)[0]
	assert_eq(entry.strava_status, Ride.UPLOAD_DONE)
	assert_eq(entry.strava_activity_id, "987")
	assert_eq(back.samples.size(), 6, "поток не тронут")


func test_update_upload_status_rejects_unknown_status_and_missing_ride() -> void:
	var ride := _ride()
	_repo.save(ride)
	assert_false(_repo.update_upload_status(ride.id, {"strava_status": "bogus"}))
	assert_eq(_repo.get_ride(ride.id).upload["strava_status"], Ride.UPLOAD_NONE)
	assert_false(_repo.update_upload_status("nope", {"strava_status": Ride.UPLOAD_DONE}))


func test_rides_changed_signal_on_save_delete_and_status() -> void:
	var ride := _ride()
	_repo.save(ride)
	_repo.update_upload_status(ride.id, {"strava_status": Ride.UPLOAD_QUEUED})
	_repo.delete(ride.id)
	assert_eq(_changed, [PROFILE_A, PROFILE_A, PROFILE_A])


# ---------------------------------------------------------------------------
# Дозапись потока (LOC-07 крит. 1) и устойчивость к повреждениям (В-3)
# ---------------------------------------------------------------------------

func test_append_samples_incrementally_equals_full_save() -> void:
	var ride := _ride(PROFILE_A, 1700000000, 0)
	ride.samples = SampleStream.new()
	_repo.save(ride)
	var full := _stream(25)
	var partial := SampleStream.new()
	partial.speed_source = full.speed_source
	for i in 25:
		var sample: TrainerSample = null
		if full.has_power[i]:
			sample = TrainerSample.full(float(i), full.power_w[i], full.cadence_rpm[i], full.speed_kmh[i])
		partial.append(i, sample, full.heart_rate_bpm[i] if full.has_heart_rate[i] else -1, full.target_w[i],
			full.step_index[i], full.erg_enabled[i], -1.0, {"power": 1, "cadence": 1, "heart_rate": 2})
		if (i + 1) % 10 == 0:
			assert_true(_repo.append_samples(ride.id, partial, i + 1 - 10))
	assert_true(_repo.append_samples(ride.id, partial, 20))
	var back := _repo.get_ride(ride.id)
	assert_eq(back.samples.size(), 25)
	for i in 25:
		assert_eq_deep(back.samples.row(i), full.row(i))
	assert_eq(back.samples.speed_source, Ride.SPEED_SOURCE_TRAINER_LEGACY)


func test_append_with_mismatched_offset_rewrites_whole_stream() -> void:
	var ride := _ride(PROFILE_A, 1700000000, 6)
	_repo.save(ride)
	var s := _stream(9)
	assert_true(_repo.append_samples(ride.id, s, 2), "рассинхрон (2 вместо 6) → переписать")
	assert_eq(_repo.get_ride(ride.id).samples.size(), 9)


func test_corrupted_meta_json_excludes_ride_from_list_and_get() -> void:
	var good := _ride(PROFILE_A, 1700000000)
	var bad := _ride(PROFILE_A, 1700001000)
	_repo.save(good)
	_repo.save(bad)
	var meta := FileAccess.open(_abs(PROFILE_A).path_join(bad.id).path_join("meta.json"), FileAccess.WRITE)
	meta.store_string("{ not json")
	meta.close()
	# Индекс повреждаем тоже, чтобы список перестроился по meta.json.
	var index := FileAccess.open(_abs(PROFILE_A).path_join("index.json"), FileAccess.WRITE)
	index.store_string("garbage")
	index.close()
	var fresh := FileRideRepository.new(_dir)
	assert_null(fresh.get_ride(bad.id))
	var list := fresh.list(PROFILE_A)
	assert_eq(list.size(), 1)
	assert_eq(list[0].ride_id, good.id)
	assert_not_null(fresh.get_ride(good.id))


func test_corrupted_samples_bin_yields_ride_with_empty_stream() -> void:
	var ride := _ride()
	_repo.save(ride)
	var f := FileAccess.open(_abs(PROFILE_A).path_join(ride.id).path_join("samples.bin"), FileAccess.WRITE)
	f.store_string("XXXX this is not a sample file at all")
	f.close()
	var back := FileRideRepository.new(_dir).get_ride(ride.id)
	assert_not_null(back, "метаданные читаются")
	assert_eq(back.samples.size(), 0)
	assert_eq(back.name, "Test ride")


func test_truncated_samples_bin_keeps_whole_records_only() -> void:
	var ride := _ride(PROFILE_A, 1700000000, 10)
	_repo.save(ride)
	var path := _abs(PROFILE_A).path_join(ride.id).path_join("samples.bin")
	var bytes := FileAccess.get_file_as_bytes(path)
	var cut := bytes.slice(0, FileRideRepository.SAMPLES_HEADER_SIZE + FileRideRepository.SAMPLES_RECORD_SIZE * 7 + 5)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(cut)
	f.close()
	var back := FileRideRepository.new(_dir).get_ride(ride.id)
	assert_eq(back.samples.size(), 7, "усечённая 8-я запись отброшена")
	assert_eq_deep(back.samples.row(6), ride.samples.row(6))


func test_missing_index_is_rebuilt_from_ride_directories() -> void:
	_repo.save(_ride(PROFILE_A, 1700000000, 6, "one"))
	_repo.save(_ride(PROFILE_A, 1700001000, 6, "two"))
	DirAccess.remove_absolute(_abs(PROFILE_A).path_join("index.json"))
	var fresh := FileRideRepository.new(_dir)
	var list := fresh.list(PROFILE_A)
	assert_eq(list.size(), 2)
	assert_eq(list[0].name, "two")
	assert_true(FileAccess.file_exists(_abs(PROFILE_A).path_join("index.json")), "индекс записан заново")


func test_no_code_outside_storage_touches_ride_files() -> void:
	# REQ-LOC-01 крит. 5: имена файлов заезда известны только src/storage/.
	var offenders: Array[String] = []
	_scan("res://src", offenders)
	assert_eq(offenders, [], "файлы заезда упомянуты вне src/storage/: %s" % str(offenders))


static func _scan(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			var path := dir_path.path_join(f)
			if path.begins_with("res://src/storage/"):
				continue
			var text := FileAccess.get_file_as_string(path)
			if text.contains("samples.bin") or text.contains("rides/") and text.contains("meta.json"):
				out.append(path)
	for sub in d.get_directories():
		_scan(dir_path.path_join(sub), out)
