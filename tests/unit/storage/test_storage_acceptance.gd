extends GutTest
## Приёмочные тесты хранилища заездов, сводки и потоковой записи
## (REQ-LOC-01, REQ-LOC-02 крит. 1–2, REQ-LOC-04, REQ-LOC-06 крит. 1, REQ-LOC-07,
## REQ-STR-05 крит. 2, REQ-PRF-04 крит. 1, REQ-WRK-05 крит. 2, REQ-NFR-09 крит. 1).
## Станок — только `FakeTrainer` (детерминированный: без шума, мгновенный отклик).

const FTP: int = 200
const MAX_HR: int = 180
const A: String = "acc-rider-a"
const B: String = "acc-rider-b"
const START_UNIX: int = 1_790_000_000

var _dir: String
var _repo: FileRideRepository
var _recorder: RideRecorder = null
var _recorder2: RideRecorder = null
var _session: WorkoutSession = null
var _trainer: FakeTrainer = null


func before_each() -> void:
	_dir = "user://acc_storage_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_repo = FileRideRepository.new(_dir)


func after_each() -> void:
	if _recorder != null:
		_recorder.dispose()
		_recorder = null
	if _recorder2 != null:
		_recorder2.dispose()
		_recorder2 = null
	_session = null
	_trainer = null
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
# Хелперы
# ---------------------------------------------------------------------------

## Поток из списков значений; -1 в power/hr/cadence — «нет данных».
static func _stream(powers: Array, hrs: Array = [], cadences: Array = [], step: int = 0) -> SampleStream:
	var s := SampleStream.new()
	s.speed_source = Ride.SPEED_SOURCE_TRAINER_LEGACY
	for i in powers.size():
		var p: int = int(powers[i])
		var hr: int = int(hrs[i]) if i < hrs.size() else -1
		var cad: int = int(cadences[i]) if i < cadences.size() else -1
		var sample: TrainerSample = null
		if p >= 0 or cad >= 0:
			sample = TrainerSample.new()
			sample.timestamp_sec = float(i + 1)
			sample.has_power = p >= 0
			sample.power_w = maxi(p, 0)
			sample.has_cadence = cad >= 0
			sample.cadence_rpm = maxi(cad, 0)
			sample.has_speed = p >= 0
			sample.speed_kmh = 30.0 if p >= 0 else 0.0
		s.append(i, sample, hr, 200, step, true)
	return s


func _profile(name: String = "Acc", id: String = A, max_hr: int = MAX_HR) -> Profile:
	var p := Profile.create(name)
	p.id = id
	p.ftp_w = FTP
	p.weight_kg = 70.0
	p.max_hr = max_hr
	return p


## Заезд «вручную» (без сессии) для тестов репозитория.
func _ride(profile_id: String, started: int, name: String, samples: SampleStream, max_hr: int = MAX_HR) -> Ride:
	var r := Ride.new()
	r.id = Ride.generate_id(started)
	r.profile_id = profile_id
	r.started_at_unix = started
	r.name = name
	r.workout = {"name": name, "source": "zwo", "steps": []}
	r.metadata = {"ftp_w": FTP, "weight_kg": 70.0, "max_hr": max_hr, "intensity": 1.0, "stopped_early": false,
		"paused_total_sec": 0.0, "speed_source": samples.speed_source, "workout_name": name, "workout_source": "zwo",
		"in_progress": false, "recovered": false}
	r.samples = samples
	r.compute_summary()
	return r


func _plan(steps: Array[WorkoutStep], name: String = "Acceptance plan") -> Workout:
	return Workout.make(name, steps, "zwo")


func _deterministic_trainer(hr: int = 150, emit_speed: bool = true) -> FakeTrainer:
	var t := FakeTrainer.new(7)
	t.connect_delay_sec = 0.0
	t.power_noise_w = 0.0
	t.cadence_noise_rpm = 0.0
	t.power_tau_sec = 0.001
	t.emit_speed = emit_speed
	t.set_heart_rate(hr)
	t.connect_device("fake-acc")
	return t


func _start_session(plan: Workout, profile: Profile, hr: int = 150, emit_speed: bool = true, with_recorder: bool = true) -> WorkoutSession:
	_trainer = _deterministic_trainer(hr, emit_speed)
	_session = WorkoutSession.new(plan, _trainer, profile.ftp_w, 1.0, profile.weight_kg)
	if with_recorder:
		_recorder = RideRecorder.new(_repo, profile, _session)
	_session.start()
	return _session


func _ticks(n: int) -> void:
	for i in n:
		_session.tick(1.0)


static func _event_of(events: Array[Dictionary], type: String) -> Dictionary:
	for e in events:
		if str(e.get("type", "")) == type:
			return e
	return {}


static func _count_events(events: Array[Dictionary], type: String) -> int:
	var n := 0
	for e in events:
		if str(e.get("type", "")) == type:
			n += 1
	return n


## Строгий Coggan: только полные 30-с окна (TrainingPeaks/GoldenCheetah).
static func _np_strict(values: Array) -> float:
	var w := 30
	if values.size() < w:
		return -1.0
	var sum4 := 0.0
	var count := 0
	for i in range(w - 1, values.size()):
		var acc := 0.0
		for j in range(i - w + 1, i + 1):
			acc += float(values[j])
		var avg := acc / float(w)
		sum4 += avg * avg * avg * avg
		count += 1
	return pow(sum4 / float(count), 0.25)


# ===========================================================================
# REQ-LOC-01 — сохранение заезда со всеми потоками в профиле
# ===========================================================================

func test_req_loc_01_c1_ride_from_session_has_required_metadata_and_samples() -> void:
	var profile := _profile()
	_start_session(_plan([WorkoutStep.watts(20, 150.0), WorkoutStep.watts(20, 250.0)]), profile)
	_ticks(40)
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED, "сессия завершилась по плану")
	var list := _repo.list(profile.id)
	assert_eq(list.size(), 1, "ровно один заезд после завершения")
	var ride := _repo.get_ride(_recorder.ride_id())
	assert_not_null(ride)
	if ride == null:
		return
	var m := ride.metadata
	for key in ["started_at_unix", "workout_name", "workout_source", "ftp_w", "weight_kg", "max_hr", "intensity",
			"stopped_early", "paused_total_sec", "speed_source"]:
		assert_true(m.has(key), "метаданные содержат '%s'" % key)
	assert_eq(ride.started_at_unix, _session.started_at_unix, "дата/время старта")
	assert_gt(ride.started_at_unix, 0)
	assert_eq(str(m.get("workout_name")), "Acceptance plan", "название плана")
	assert_eq(str(m.get("workout_source")), "zwo", "источник плана")
	assert_eq(ride.ftp_w(), FTP, "FTP на момент заезда")
	assert_almost_eq(float(m.get("weight_kg")), 70.0, 1e-6, "вес на момент заезда")
	assert_eq(ride.max_hr(), MAX_HR, "max_hr")
	assert_almost_eq(float(m.get("intensity")), 1.0, 1e-6, "множитель")
	assert_false(ride.stopped_early(), "не досрочно")
	assert_almost_eq(ride.paused_total_sec(), 0.0, 1e-6)
	assert_eq(ride.speed_source(), SampleStream.SPEED_SOURCE_MODEL, "speed_source = модель, хотя FakeTrainer отдаёт скорость (У-30)")
	assert_eq(ride.samples.size(), 40, "все сэмплы WRK-08")
	assert_false(ride.is_in_progress())
	assert_eq(ride.name, "Acceptance plan")
	assert_eq(str(ride.workout.get("source", "")), "zwo", "план сохранён вместе с заездом")


func test_req_loc_01_c1_speed_source_model_when_trainer_has_no_speed() -> void:
	var profile := _profile()
	_start_session(_plan([WorkoutStep.watts(10, 150.0)]), profile, 150, false)
	_ticks(10)
	var ride := _repo.get_ride(_recorder.ride_id())
	assert_not_null(ride)
	if ride != null:
		assert_eq(ride.speed_source(), SampleStream.SPEED_SOURCE_MODEL, "speed_source = модель")
		assert_eq(ride.samples.speed_source, SampleStream.SPEED_SOURCE_MODEL, "поток помечен моделью")
		assert_true(ride.samples.has_speed[5], "скорость модели записана в поток")
		assert_gt(ride.samples.total_distance_m(), 0.0, "дистанция по модели > 0")


func test_req_loc_01_c1_stopped_early_and_paused_total_persisted() -> void:
	var profile := _profile()
	_start_session(_plan([WorkoutStep.watts(600, 150.0)]), profile)
	_ticks(120)
	_session.pause()
	_ticks(30)
	_session.resume()
	_ticks(10)
	_session.stop()
	var ride := _repo.get_ride(_recorder.ride_id())
	assert_not_null(ride)
	if ride == null:
		return
	assert_true(ride.stopped_early(), "флаг досрочного завершения")
	assert_almost_eq(ride.paused_total_sec(), 30.0, 1e-6, "paused_total_sec = 30")
	assert_eq(ride.samples.size(), 130, "120 + 10 сэмплов, на паузе не пишутся")
	assert_eq(ride.samples.time_sec[120], 120, "сэмплы продолжаются с t = 120 после паузы")
	assert_true(ride.samples.is_monotonic())


func test_req_loc_01_c2_get_ride_returns_samples_in_order_and_count() -> void:
	var powers: Array = []
	var hrs: Array = []
	var cads: Array = []
	for i in 300:
		powers.append(100 + (i * 7) % 250 if i % 17 != 0 else -1)
		hrs.append(120 + i % 50 if i % 23 != 0 else -1)
		cads.append((80 + i % 20) if i % 11 != 0 else -1)
	var src := _stream(powers, hrs, cads)
	var ride := _ride(A, START_UNIX, "Order", src)
	var id := _repo.save(ride)
	assert_false(id.is_empty())
	var back := _repo.get_ride(id)
	assert_not_null(back)
	if back == null:
		return
	var s := back.samples
	assert_eq(s.size(), 300, "число сэмплов")
	assert_eq(Array(s.time_sec), Array(src.time_sec), "time_sec по порядку")
	assert_eq(Array(s.power_w), Array(src.power_w), "power_w")
	assert_eq(s.has_power, src.has_power, "has_power")
	assert_eq(Array(s.heart_rate_bpm), Array(src.heart_rate_bpm), "heart_rate_bpm")
	assert_eq(s.has_heart_rate, src.has_heart_rate, "has_heart_rate")
	assert_eq(Array(s.cadence_rpm), Array(src.cadence_rpm), "cadence_rpm")
	assert_eq(s.has_cadence, src.has_cadence, "has_cadence")
	assert_eq(Array(s.target_w), Array(src.target_w), "target_w")
	assert_eq(Array(s.step_index), Array(src.step_index), "step_index")
	assert_eq(s.erg_enabled, src.erg_enabled, "erg_enabled")
	assert_eq(s.has_speed, src.has_speed, "has_speed")
	for i in 300:
		assert_almost_eq(s.speed_kmh[i], src.speed_kmh[i], 1e-4)
		assert_almost_eq(s.distance_m[i], src.distance_m[i], 1e-2)
	assert_eq(Array(s.power_age_sec), Array(src.power_age_sec), "power_age_sec")
	assert_eq(Array(s.heart_rate_age_sec), Array(src.heart_rate_age_sec), "heart_rate_age_sec")
	assert_eq(s.speed_source, src.speed_source, "speed_source потока")


func test_req_loc_01_c3_rides_bound_to_profile() -> void:
	_repo.save(_ride(A, START_UNIX, "A1", _stream([100, 100])))
	_repo.save(_ride(A, START_UNIX + 10, "A2", _stream([100, 100])))
	var b_id := _repo.save(_ride(B, START_UNIX + 20, "B1", _stream([100, 100])))
	assert_eq(_repo.list(A).size(), 2)
	assert_eq(_repo.list(B).size(), 1)
	for s in _repo.list(A):
		assert_ne(s.ride_id, b_id, "заезд B не в списке A")
		assert_eq(s.profile_id, A)
	assert_eq(_repo.list("nobody").size(), 0)


func test_req_loc_01_c4_session_events_saved_with_ride() -> void:
	var profile := _profile()
	_start_session(_plan([WorkoutStep.watts(60, 150.0), WorkoutStep.watts(60, 250.0), WorkoutStep.watts(60, 100.0)]), profile)
	_ticks(20)
	_session.pause()
	_ticks(5)
	_session.resume()
	_ticks(5)
	_session.skip_step()
	_ticks(5)
	_session.set_erg_enabled(false)
	_ticks(5)
	_session.set_erg_enabled(true)
	_ticks(5)
	_trainer.inject_dropout(3.0)
	_ticks(10)
	_session.stop()
	var ride := _repo.get_ride(_recorder.ride_id())
	assert_not_null(ride)
	if ride == null:
		return
	var ev := ride.events
	assert_eq(_count_events(ev, WorkoutSession.EVENT_START), 1, "start")
	var pause := _event_of(ev, WorkoutSession.EVENT_PAUSE)
	assert_false(pause.is_empty(), "пауза в журнале")
	assert_almost_eq(float(pause.get("at_sec", -1)), 20.0, 1e-6, "pause.at_sec")
	assert_almost_eq(float(pause.get("duration_sec", -1)), 5.0, 1e-6, "pause.duration_sec")
	assert_almost_eq(float(pause.get("until_sec", -1)), 25.0, 1e-6, "pause.until_sec")
	assert_eq(_count_events(ev, WorkoutSession.EVENT_RESUME), 1, "resume")
	assert_eq(_count_events(ev, WorkoutSession.EVENT_SKIP), 1, "skip")
	assert_eq(_count_events(ev, WorkoutSession.EVENT_ERG_OFF), 1, "erg_off")
	assert_eq(_count_events(ev, WorkoutSession.EVENT_ERG_ON), 1, "erg_on")
	assert_eq(_count_events(ev, WorkoutSession.EVENT_DISCONNECT), 1, "disconnect")
	assert_eq(_count_events(ev, WorkoutSession.EVENT_RECONNECT), 1, "reconnect")
	assert_eq(_count_events(ev, WorkoutSession.EVENT_STOP), 1, "stop")
	# События переживают перезапуск хранилища.
	var again := FileRideRepository.new(_dir).get_ride(ride.id)
	assert_not_null(again)
	if again != null:
		assert_eq(again.events.size(), ev.size(), "число событий после перечитывания")


func test_req_loc_01_c5_file_layout_meta_and_binary_stream() -> void:
	var ride := _ride(A, START_UNIX, "Layout", _stream([100, 120, 140]))
	var id := _repo.save(ride)
	var ride_dir := ProjectSettings.globalize_path(_dir).path_join(A).path_join(id)
	assert_true(DirAccess.dir_exists_absolute(ride_dir), "каталог заезда <dir>/<profile>/<ride_id>")
	assert_true(FileAccess.file_exists(ride_dir.path_join("meta.json")), "meta.json")
	assert_true(FileAccess.file_exists(ride_dir.path_join("samples.bin")), "samples.bin")
	var meta_text := FileAccess.get_file_as_string(ride_dir.path_join("meta.json"))
	var json := JSON.new()
	assert_eq(json.parse(meta_text), OK, "meta.json — валидный JSON")
	if json.data is Dictionary:
		var d: Dictionary = json.data
		assert_true(d.has("metadata") and d.has("events") and d.has("upload"), "meta.json содержит метаданные, события, статус Strava")
		assert_false(d.has("samples") or d.has("time_sec"), "поток не в meta.json")
	var bin := FileAccess.get_file_as_bytes(ride_dir.path_join("samples.bin"))
	assert_gt(bin.size(), 0)
	assert_false(bin.slice(0, 4).get_string_from_ascii().begins_with("{"), "поток в бинарном формате, не JSON")


func test_req_loc_01_c5_no_code_outside_storage_touches_ride_files() -> void:
	var offenders: Array[String] = []
	_scan_sources("res://src", offenders)
	assert_eq(offenders, [], "файлы заезда (meta.json/samples.bin/index.json) упоминаются вне src/storage: " + str(offenders))


func _scan_sources(dir: String, offenders: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if not f.ends_with(".gd"):
			continue
		var path := dir.path_join(f)
		if path.begins_with("res://src/storage/"):
			continue
		var text := FileAccess.get_file_as_string(path)
		if text.contains("meta.json") or text.contains("samples.bin") or text.contains("index.json"):
			offenders.append(path)
	for sub in d.get_directories():
		_scan_sources(dir.path_join(sub), offenders)


func test_req_loc_01_meta_dict_round_trip() -> void:
	var ride := _ride(A, START_UNIX, "RT", _stream([100, 200, 300], [120, 130, 140], [80, 0, 90]))
	ride.events = [{"type": "start", "at_sec": 0.0, "value": 0}, {"type": "pause", "at_sec": 1.0, "value": 1, "duration_sec": 2.5, "until_sec": 3.5}]
	ride.upload["strava_status"] = Ride.UPLOAD_QUEUED
	var d := ride.to_meta_dict()
	var back := Ride.from_meta_dict(d)
	assert_not_null(back)
	if back == null:
		return
	assert_eq_deep(back.to_meta_dict(), d)
	assert_eq(back.id, ride.id)
	assert_eq(back.events.size(), 2)
	assert_almost_eq(float(back.events[1]["duration_sec"]), 2.5, 1e-9)
	assert_eq(back.summary.avg_power_w, 200)
	assert_eq(back.summary.strava_status, Ride.UPLOAD_QUEUED)
	assert_null(Ride.from_meta_dict({}), "без id → null")
	assert_null(Ride.from_meta_dict({"name": "x"}))


# ===========================================================================
# REQ-LOC-02 — список заездов
# ===========================================================================

func test_req_loc_02_c1_list_sorted_desc_with_required_fields() -> void:
	_repo.save(_ride(A, START_UNIX + 100, "Middle", _stream([150, 150, 150, 150])))
	_repo.save(_ride(A, START_UNIX + 300, "Newest", _stream([200, 200])))
	var oldest := _ride(A, START_UNIX, "Oldest", _stream([100, 100, 100]))
	oldest.upload["strava_status"] = Ride.UPLOAD_DONE
	oldest.upload["strava_activity_id"] = "987654"
	_repo.save(oldest)
	var list := _repo.list(A)
	assert_eq(list.size(), 3)
	if list.size() != 3:
		return
	assert_eq(list[0].name, "Newest", "сортировка по дате старта по убыванию")
	assert_eq(list[1].name, "Middle")
	assert_eq(list[2].name, "Oldest")
	assert_eq(list[0].started_at_unix, START_UNIX + 300, "дата")
	assert_eq(list[0].duration_sec, 2, "длительность")
	assert_eq(list[0].avg_power_w, 200, "средняя мощность")
	assert_eq(list[0].strava_status, Ride.UPLOAD_NONE, "статус Strava по умолчанию")
	assert_eq(list[2].strava_status, Ride.UPLOAD_DONE, "статус Strava")
	assert_eq(list[2].strava_activity_id, "987654")
	assert_eq(list[1].avg_power_w, 150)
	# Список после перезапуска такой же.
	var reopened := FileRideRepository.new(_dir).list(A)
	assert_eq(reopened.size(), 3)
	if reopened.size() == 3:
		assert_eq(reopened[0].name, "Newest")
		assert_eq(reopened[2].strava_status, Ride.UPLOAD_DONE)


func test_req_loc_02_c2_list_of_500_rides_under_1s() -> void:
	var stream := _stream([150, 160, 170])
	for i in 500:
		var r := _ride(A, START_UNIX + i * 60, "Ride %d" % i, stream)
		_repo.save(r)
	# Холодный старт: новый экземпляр читает индекс с диска.
	var cold := FileRideRepository.new(_dir)
	var t0 := Time.get_ticks_usec()
	var list := cold.list(A)
	var cold_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var t1 := Time.get_ticks_usec()
	var list2 := cold.list(A)
	var warm_ms := (Time.get_ticks_usec() - t1) / 1000.0
	gut.p("list(500): cold %.1f ms, warm %.1f ms" % [cold_ms, warm_ms])
	assert_eq(list.size(), 500)
	assert_eq(list2.size(), 500)
	assert_lt(cold_ms, 1000.0, "список из 500 заездов ≤ 1 с (холодный): %.1f мс" % cold_ms)
	assert_lt(warm_ms, 1000.0, "список из 500 заездов ≤ 1 с (тёплый): %.1f мс" % warm_ms)
	if list.size() == 500:
		assert_eq(list[0].name, "Ride 499", "новые сверху")
		assert_eq(list[499].name, "Ride 0")


# ===========================================================================
# REQ-LOC-04 — сводка заезда
# ===========================================================================

func test_req_loc_04_c1_avg_power_counts_zeros_skips_no_data() -> void:
	var s := RideSummary.compute(_stream([200, 0, 100, -1, -1]), FTP, PowerZones.coggan(FTP), null)
	assert_eq(s.power_sample_count, 3)
	assert_eq(s.avg_power_w, 100, "(200 + 0 + 100) / 3 = 100; «нет данных» не учитываются")
	assert_eq(s.max_power_w, 200)
	var s2 := RideSummary.compute(_stream([100, 101]), FTP, PowerZones.coggan(FTP), null)
	assert_eq(s2.avg_power_w, 101, "100.5 → округление до целого (101)")
	var none := RideSummary.compute(_stream([-1, -1]), FTP, PowerZones.coggan(FTP), null)
	assert_eq(none.avg_power_w, RideSummary.NO_DATA, "без мощности — «нет данных», не 0")


func test_req_loc_04_c2_np_constant_200_for_10_min_is_200() -> void:
	var powers: Array = []
	for i in 600:
		powers.append(200)
	var s := RideSummary.compute(_stream(powers), FTP, PowerZones.coggan(FTP), null)
	assert_eq(s.normalized_power_w, 200, "NP постоянных 200 Вт = 200")
	assert_eq(s.avg_power_w, 200)


func test_req_loc_04_c2_np_30s_300_30s_100_above_avg_and_matches_coggan_reference() -> void:
	var powers: Array = []
	for i in 30:
		powers.append(300)
	for i in 30:
		powers.append(100)
	var s := RideSummary.compute(_stream(powers), FTP, PowerZones.coggan(FTP), null)
	assert_eq(s.avg_power_w, 200)
	assert_gt(s.normalized_power_w, s.avg_power_w, "NP > средней для переменной мощности")
	var reference := _np_strict(powers)  # 223.07 — только полные 30-с окна
	gut.p("NP 30s@300/30s@100: реализация %d, эталон Coggan (полные окна) %.2f" % [s.normalized_power_w, reference])
	assert_almost_eq(float(s.normalized_power_w), reference, 1.0,
			"NP = Coggan (30-с окна → ^4 → среднее → корень): ожидалось %.1f, получено %d" % [reference, s.normalized_power_w])


func test_req_loc_04_c2_np_600s_alternating_matches_coggan_reference() -> void:
	var powers: Array = []
	for k in 10:
		for i in 30:
			powers.append(300)
		for i in 30:
			powers.append(100)
	var s := RideSummary.compute(_stream(powers), FTP, PowerZones.coggan(FTP), null)
	var reference := _np_strict(powers)  # 221.9
	gut.p("NP 600s alt: реализация %d, эталон %.2f" % [s.normalized_power_w, reference])
	assert_almost_eq(float(s.normalized_power_w), reference, 1.0, "NP по Coggan на 10-минутном потоке")
	assert_gte(s.normalized_power_w, s.avg_power_w)


func test_req_loc_04_c2_np_never_below_avg_short_and_sparse() -> void:
	for powers in [[300, 100], [50, 50, 50, 400], [0, 0, 0, 0, 0, 500]]:
		var s := RideSummary.compute(_stream(powers), FTP, PowerZones.coggan(FTP), null)
		assert_gte(s.normalized_power_w, s.avg_power_w, "NP ≥ средней для %s" % str(powers))


func test_req_loc_04_c3_work_kj() -> void:
	var p600: Array = []
	for i in 600:
		p600.append(200)
	var s := RideSummary.compute(_stream(p600), FTP, PowerZones.coggan(FTP), null)
	assert_almost_eq(s.work_kj, 120.0, 1e-6, "200 Вт × 600 с = 120 кДж")
	var p3600: Array = []
	for i in 3600:
		p3600.append(200)
	var s2 := RideSummary.compute(_stream(p3600), FTP, PowerZones.coggan(FTP), null)
	assert_almost_eq(s2.work_kj, 720.0, 1e-6, "200 Вт × 3600 с = 720 кДж")
	var s3 := RideSummary.compute(_stream([250, -1, 250]), FTP, PowerZones.coggan(FTP), null)
	assert_almost_eq(s3.work_kj, 0.5, 1e-9, "«нет данных» не добавляет работы")


func test_req_loc_04_c4_avg_hr_and_cadence_zero_counted_no_data_skipped() -> void:
	var s := RideSummary.compute(_stream([200, 200, 200, 200], [150, -1, 170, -1], [90, 0, -1, 60]), FTP,
			PowerZones.coggan(FTP), HrZones.five_zone(MAX_HR))
	assert_eq(s.hr_sample_count, 2)
	assert_eq(s.avg_hr, 160, "(150 + 170) / 2")
	assert_eq(s.max_hr, 170)
	assert_eq(s.cadence_sample_count, 3)
	assert_eq(s.avg_cadence, 50, "(90 + 0 + 60) / 3 = 50 — ноль учитывается")
	assert_eq(s.max_cadence, 90)


func test_req_loc_04_c5_time_in_power_and_hr_zones() -> void:
	# FTP 200, Coggan: Z1 ≤ 110, Z2 ≤ 150, Z3 ≤ 180, Z4 ≤ 210, Z5 ≤ 240, Z6 ≤ 300, Z7 > 300.
	var powers: Array = [100, 100, 130, 170, 170, 170, 200, 230, 280, 350, 350, -1, -1]
	# max_hr 180: границы 108 / 126 / 144 / 162.
	var hrs: Array = [100, 115, 115, 130, 150, 170, 170, 170, -1, -1, -1, -1, -1]
	var s := RideSummary.compute(_stream(powers, hrs), FTP, PowerZones.coggan(FTP), HrZones.five_zone(MAX_HR))
	assert_eq(s.time_in_power_zones.size(), 7, "7 зон мощности")
	assert_eq(Array(s.time_in_power_zones), [2, 1, 3, 1, 1, 1, 2], "секунды по зонам мощности")
	assert_eq(s.total_power_zone_sec(), s.power_sample_count, "сумма = число сэмплов с мощностью (11)")
	assert_eq(s.power_sample_count, 11)
	assert_eq(s.time_in_hr_zones.size(), 5, "5 зон пульса")
	assert_eq(Array(s.time_in_hr_zones), [1, 2, 1, 1, 3], "секунды по зонам пульса")
	assert_eq(s.total_hr_zone_sec(), s.hr_sample_count, "сумма = число сэмплов с пульсом (8)")


func test_req_loc_04_c5_zones_from_profile_at_ride_time_persist() -> void:
	var profile := _profile()
	profile.power_zones = PowerZones.custom(FTP, [50.0, 100.0])  # 3 зоны
	_start_session(_plan([WorkoutStep.watts(10, 150.0), WorkoutStep.watts(10, 250.0)]), profile)
	_ticks(20)
	var ride := _repo.get_ride(_recorder.ride_id())
	assert_not_null(ride)
	if ride == null:
		return
	assert_eq(ride.summary.time_in_power_zones.size(), 3, "зоны профиля на момент заезда (3 зоны)")
	assert_eq(Array(ride.summary.time_in_power_zones), [0, 10, 10], "150 Вт → Z2 (≤ 200), 250 Вт → Z3")
	# Смена зон профиля после заезда не меняет сводку сохранённого заезда.
	profile.power_zones = null
	var again := FileRideRepository.new(_dir).get_ride(ride.id)
	assert_eq(again.summary.time_in_power_zones.size(), 3)
	assert_eq(again.compute_summary().time_in_power_zones.size(), 3, "пересчёт по границам, сохранённым в заезде")


func test_req_loc_04_c6_ride_without_hr_shows_no_data_not_zero() -> void:
	var s := RideSummary.compute(_stream([200, 200, 200]), FTP, PowerZones.coggan(FTP), HrZones.five_zone(MAX_HR))
	assert_eq(s.avg_hr, RideSummary.NO_DATA, "средний пульс — «нет данных» (-1), не 0")
	assert_eq(s.max_hr, RideSummary.NO_DATA)
	assert_false(s.has_heart_rate())
	assert_eq(s.total_hr_zone_sec(), 0)
	# Профиль без max_hr → зон пульса нет, сводка считается без ошибок.
	var s2 := RideSummary.compute(_stream([200, 200], [150, 150]), FTP, PowerZones.coggan(FTP), null)
	assert_eq(s2.avg_hr, 150, "пульс есть, зон нет — среднее считается")
	assert_eq(s2.time_in_hr_zones.size(), 0, "без зон пульса массив пуст")
	# Через сессию: станок без пульса.
	var profile := _profile("NoHr", A, 0)
	_start_session(_plan([WorkoutStep.watts(10, 150.0)]), profile, 0)
	_ticks(10)
	var ride := _repo.get_ride(_recorder.ride_id())
	assert_not_null(ride)
	if ride != null:
		assert_eq(ride.summary.avg_hr, RideSummary.NO_DATA)
		assert_eq(ride.summary.hr_sample_count, 0)
		assert_null(ride.hr_zones(), "max_hr не задан → зон пульса нет")
		assert_eq(ride.summary.avg_power_w, 150)


# ===========================================================================
# REQ-LOC-06 крит. 1 — удаление
# ===========================================================================

func test_req_loc_06_c1_delete_removes_ride_and_directory() -> void:
	var id := _repo.save(_ride(A, START_UNIX, "Del", _stream([100, 100])))
	var keep := _repo.save(_ride(A, START_UNIX + 1, "Keep", _stream([100, 100])))
	var ride_dir := ProjectSettings.globalize_path(_dir).path_join(A).path_join(id)
	assert_true(DirAccess.dir_exists_absolute(ride_dir))
	assert_true(_repo.delete(id), "удаление существующего")
	assert_false(DirAccess.dir_exists_absolute(ride_dir), "каталог заезда удалён")
	assert_null(_repo.get_ride(id), "заезд не читается")
	assert_eq(_repo.list(A).size(), 1)
	assert_eq(_repo.list(A)[0].ride_id, keep, "другой заезд цел")
	assert_not_null(_repo.get_ride(keep))
	assert_false(_repo.delete(id), "повторное удаление → false")
	assert_false(_repo.delete("no-such-ride"), "несуществующий → false")
	assert_null(FileRideRepository.new(_dir).get_ride(id), "удаление пережило перезапуск")
	assert_eq(FileRideRepository.new(_dir).list(A).size(), 1)


# ===========================================================================
# REQ-STR-05 крит. 2 — статус выгрузки в метаданных
# ===========================================================================

func test_req_str_05_c2_upload_status_persisted_in_meta_and_list() -> void:
	var id := _repo.save(_ride(A, START_UNIX, "Upl", _stream([100, 100])))
	assert_true(_repo.update_upload_status(id, {"strava_status": Ride.UPLOAD_QUEUED}))
	assert_eq(_repo.list(A)[0].strava_status, Ride.UPLOAD_QUEUED, "список видит «в очереди»")
	assert_true(_repo.update_upload_status(id, {"strava_status": Ride.UPLOAD_DONE, "strava_activity_id": "123456789", "attempts": 2}))
	var ride := _repo.get_ride(id)
	assert_eq(str(ride.upload["strava_status"]), Ride.UPLOAD_DONE)
	assert_eq(str(ride.upload["strava_activity_id"]), "123456789")
	assert_eq(int(ride.upload["attempts"]), 2)
	var reopened := FileRideRepository.new(_dir)
	assert_eq(reopened.list(A)[0].strava_status, Ride.UPLOAD_DONE, "статус сохранён на диске (список)")
	assert_eq(reopened.list(A)[0].strava_activity_id, "123456789")
	assert_eq(str(reopened.get_ride(id).upload["strava_status"]), Ride.UPLOAD_DONE, "статус сохранён на диске (карточка)")
	assert_true(_repo.update_upload_status(id, {"strava_status": Ride.UPLOAD_FAILED, "last_error": "HTTP 500"}))
	assert_eq(str(_repo.get_ride(id).upload["last_error"]), "HTTP 500", "текст ошибки")
	assert_eq(_repo.get_ride(id).samples.size(), 2, "смена статуса не трогает поток")


func test_req_str_05_c2_upload_status_negative() -> void:
	var id := _repo.save(_ride(A, START_UNIX, "Upl", _stream([100, 100])))
	assert_false(_repo.update_upload_status(id, {"strava_status": "bananas"}), "неизвестный статус отклоняется")
	assert_eq(_repo.get_ride(id).upload["strava_status"], Ride.UPLOAD_NONE, "статус не изменился")
	assert_false(_repo.update_upload_status("no-such-ride", {"strava_status": Ride.UPLOAD_QUEUED}), "несуществующий id")
	for st in Ride.UPLOAD_STATUSES:
		assert_true(_repo.update_upload_status(id, {"strava_status": st}), "статус '%s' принимается" % st)


# ===========================================================================
# REQ-PRF-04 крит. 1 — своя история; каскад с ProfileRepository
# ===========================================================================

func test_req_prf_04_c1_history_isolated_and_cascade_on_profile_delete() -> void:
	var profiles := ProfileRepository.new(_dir + "profiles/")
	var pa := profiles.create("Alpha")
	var pb := profiles.create("Beta")
	assert_not_null(pa)
	assert_not_null(pb)
	if pa == null or pb == null:
		return
	_repo.attach_to_profiles(profiles)
	_repo.save(_ride(pa.id, START_UNIX, "A1", _stream([100, 100])))
	_repo.save(_ride(pa.id, START_UNIX + 1, "A2", _stream([100, 100])))
	var b_id := _repo.save(_ride(pb.id, START_UNIX + 2, "B1", _stream([100, 100])))
	assert_eq(_repo.list(pa.id).size(), 2)
	assert_eq(_repo.list(pb.id).size(), 1)
	for s in _repo.list(pb.id):
		assert_eq(s.name, "B1", "в истории B нет заездов A")
	var changed: Array[String] = []
	_repo.rides_changed.connect(func(pid: String) -> void: changed.append(pid))
	assert_eq(profiles.delete(pa.id), "")
	assert_eq(_repo.list(pa.id).size(), 0, "каскад: заезды A удалены")
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir).path_join(pa.id)), "каталог профиля A удалён")
	assert_eq(_repo.list(pb.id).size(), 1, "B не тронут")
	assert_not_null(_repo.get_ride(b_id))
	assert_true(changed.has(pa.id), "сигнал rides_changed для A")
	assert_eq(FileRideRepository.new(_dir).list(pa.id).size(), 0, "после перезапуска A пуст")


# ===========================================================================
# REQ-LOC-07 — запись в процессе тренировки
# ===========================================================================

func test_req_loc_07_c1_flush_at_least_every_10s_of_session_time() -> void:
	var profile := _profile()
	var flushes: Array[int] = []
	_start_session(_plan([WorkoutStep.watts(120, 150.0)]), profile)
	_recorder.flushed.connect(func(t: int) -> void: flushes.append(t))
	_ticks(55)
	assert_eq(flushes, [10, 20, 30, 40, 50], "сбросы на каждой 10-й секунде сессионного времени")
	var crash_view := FileRideRepository.new(_dir).get_ride(_recorder.ride_id())
	assert_not_null(crash_view)
	if crash_view != null:
		assert_eq(crash_view.samples.size(), 50, "на диске сэмплы до последнего сброса (50 с)")
		assert_true(crash_view.is_in_progress())
	# На паузе сессионное время стоит — сбросов нет.
	_session.pause()
	_ticks(30)
	assert_eq(flushes.size(), 5, "на паузе сбросов нет")
	_session.resume()
	_ticks(5)
	assert_eq(flushes, [10, 20, 30, 40, 50, 60], "после возобновления сброс на 60-й секунде")


func test_req_loc_07_c2_crash_recovery_restores_samples_within_10s() -> void:
	var profile := _profile()
	_start_session(_plan([WorkoutStep.watts(60, 150.0), WorkoutStep.watts(60, 250.0)]), profile)
	_ticks(73)  # последний сброс на 70 с
	var expected_power: Array = Array(_session.samples.power_w).slice(0, 70)
	var ride_id := _recorder.ride_id()
	# «Сбой»: сессия не завершена, новый экземпляр хранилища на том же каталоге.
	_recorder.dispose()
	_recorder = null
	var fresh := FileRideRepository.new(_dir)
	var recovered := fresh.recover_in_progress(profile.id)
	assert_eq(recovered.size(), 1, "один незавершённый заезд восстановлен")
	if recovered.size() != 1:
		return
	var r := recovered[0]
	assert_eq(r.id, ride_id)
	assert_eq(r.samples.size(), 70, "сэмплы до последнего сброса (потеря 3 с ≤ 10 с)")
	assert_true(r.samples.is_monotonic())
	assert_eq(Array(r.samples.power_w), expected_power, "значения мощности совпадают")
	assert_true(r.is_recovered(), "recovered")
	assert_true(r.stopped_early(), "stopped_early")
	assert_false(r.is_in_progress(), "in_progress снят")
	assert_eq(r.summary.duration_sec, 70, "сводка по имеющимся данным")
	assert_gt(r.summary.avg_power_w, 0)
	assert_eq(r.summary.power_sample_count, 70)
	assert_eq(r.summary.total_power_zone_sec(), 70)
	assert_eq(int(r.metadata.get("elapsed_sec", -1)), 70)
	# Сохранено: третий экземпляр видит завершённый восстановленный заезд.
	var third := FileRideRepository.new(_dir)
	var list := third.list(profile.id)
	assert_eq(list.size(), 1)
	if list.size() == 1:
		assert_true(list[0].recovered)
		assert_true(list[0].stopped_early)
		assert_false(list[0].in_progress)
		assert_eq(list[0].duration_sec, 70)
		assert_eq(list[0].avg_power_w, r.summary.avg_power_w)
	assert_eq(third.recover_in_progress(profile.id).size(), 0, "повторное восстановление — нечего")
	assert_eq(fresh.recover_in_progress(B).size(), 0, "другой профиль — нечего")


func test_req_loc_07_c2_crash_during_pause_keeps_pause_event() -> void:
	var profile := _profile()
	_start_session(_plan([WorkoutStep.watts(600, 150.0)]), profile)
	_ticks(25)
	_session.pause()
	_ticks(100)
	var recovered := FileRideRepository.new(_dir).recover_in_progress(profile.id)
	assert_eq(recovered.size(), 1)
	if recovered.size() == 1:
		assert_eq(recovered[0].samples.size(), 20, "сэмплы до сброса на 20 с")
		var pause := _event_of(recovered[0].events, WorkoutSession.EVENT_PAUSE)
		assert_false(pause.is_empty(), "событие паузы сброшено сразу при постановке на паузу")
		assert_almost_eq(float(pause.get("at_sec", -1)), 25.0, 1e-6)


func test_req_loc_07_c3_recovered_ride_can_be_kept_or_deleted() -> void:
	var profile := _profile()
	_start_session(_plan([WorkoutStep.watts(600, 150.0)]), profile)
	_ticks(31)
	var fresh := FileRideRepository.new(_dir)
	var before := fresh.list(profile.id)
	assert_eq(before.size(), 1)
	assert_true(before[0].in_progress, "до восстановления виден как незавершённый")
	var recovered := fresh.recover_in_progress(profile.id)
	assert_eq(recovered.size(), 1)
	if recovered.is_empty():
		return
	# Вариант «сохранить как завершённый досрочно» — уже сохранён; вариант «удалить».
	assert_true(fresh.list(profile.id)[0].stopped_early)
	assert_true(fresh.delete(recovered[0].id))
	assert_eq(fresh.list(profile.id).size(), 0)
	assert_eq(FileRideRepository.new(_dir).list(profile.id).size(), 0)


## LOC-07 крит. 4: бюджет тика вместе со сбросом на диск.
const TICK_BUDGET_US: int = 50_000
## Серия до замера худшего случая (критерий — 600 сэмплов, здесь в 6 раз больше).
const BUDGET_SERIES_TICKS: int = 3650
## Повторы худшего случая: столько тиков со сбросом (и 9× столько без) после серии.
const BUDGET_REPEATS: int = 9
## Доля тиков серии дольше бюджета, допустимая как одиночные выбросы машины.
const BUDGET_OUTLIER_SHARE: float = 0.01


static func _median_int(values: Array[int]) -> int:
	if values.is_empty():
		return 0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


## Тик сессии: длительность в мкс и был ли в нём сброс на диск.
func _timed_tick() -> Vector2i:
	var flushes_before := _recorder.flush_count
	var t0 := Time.get_ticks_usec()
	_session.tick(1.0)
	var dt := Time.get_ticks_usec() - t0
	return Vector2i(dt, 1 if _recorder.flush_count > flushes_before else 0)


## Стоимость тика меряется устойчиво к шуму машины (вытеснение планировщиком, параллельный
## прогон, сборка мусора ОС): одиночный выброс в стене времени — не стоимость тика.
## 1) Худший случай — тик со сбросом при наибольшем числе сэмплов (> 3650) — повторяется
##    BUDGET_REPEATS раз; медиана тиков со сбросом, медиана тиков без сброса и медиана
##    собственного замера сброса рекордером — каждая ≤ 50 мс.
## 2) Вся серия от 600 сэмплов: тиков дольше 50 мс не больше 1 % и не больше 10 % тиков
##    со сбросом — сброс, систематически превышающий бюджет, превышал бы его на каждом
##    сбросе (≈ 10 % тиков), поэтому такой дефект не прячется за допуском.
func test_req_loc_07_c4_tick_budget_50ms_with_3600_samples() -> void:
	var profile := _profile()
	var total_ticks: int = BUDGET_SERIES_TICKS + BUDGET_REPEATS * RideRecorder.FLUSH_INTERVAL_SEC
	_start_session(_plan([WorkoutStep.watts(total_ticks + 60, 150.0)]), profile)
	var max_tick_us: int = 0
	var slow_ticks: int = 0
	var series_ticks: int = 0
	var flush_ticks: int = 0
	var slow_flush_ticks: int = 0
	for i in BUDGET_SERIES_TICKS:
		var t := _timed_tick()
		if i + 1 < 600:
			continue
		series_ticks += 1
		max_tick_us = maxi(max_tick_us, t.x)
		if t.y == 1:
			flush_ticks += 1
		if t.x > TICK_BUDGET_US:
			slow_ticks += 1
			if t.y == 1:
				slow_flush_ticks += 1
	# Худший случай: тики после серии, накопленных сэмплов больше всего.
	var flush_us: Array[int] = []
	var plain_us: Array[int] = []
	var recorder_flush_ms: Array[int] = []
	for i in BUDGET_REPEATS * RideRecorder.FLUSH_INTERVAL_SEC:
		var t := _timed_tick()
		if t.y == 1:
			flush_us.append(t.x)
			recorder_flush_ms.append(_recorder.last_flush_ms)
		else:
			plain_us.append(t.x)
	var med_flush := _median_int(flush_us)
	var med_plain := _median_int(plain_us)
	var med_recorder := _median_int(recorder_flush_ms)
	gut.p("tick budget: серия от 600 сэмплов — %d тиков, max %.2f мс, > 50 мс: %d (со сбросом %d из %d); худший случай: медиана тика со сбросом %.2f мс (%d замеров), без сброса %.2f мс, сброс рекордера %d мс"
		% [series_ticks, max_tick_us / 1000.0, slow_ticks, slow_flush_ticks, flush_ticks, med_flush / 1000.0, flush_us.size(), med_plain / 1000.0, med_recorder])
	assert_eq(_session.samples.size(), total_ticks)
	assert_eq(flush_us.size(), BUDGET_REPEATS, "предусловие: сброс раз в 10 с — %d тиков со сбросом в худшем случае" % BUDGET_REPEATS)
	assert_lte(med_flush, TICK_BUDGET_US, "тик со сбросом при %d+ сэмплах ≤ 50 мс (медиана %.2f мс)" % [BUDGET_SERIES_TICKS, med_flush / 1000.0])
	assert_lte(med_plain, TICK_BUDGET_US, "тик без сброса ≤ 50 мс (медиана %.2f мс)" % (med_plain / 1000.0))
	assert_lte(med_recorder, 50, "сброс рекордера ≤ 50 мс (медиана %d мс)" % med_recorder)
	assert_lte(slow_ticks, int(floor(series_ticks * BUDGET_OUTLIER_SHARE)),
		"тики дольше 50 мс — только одиночные выбросы (%d из %d)" % [slow_ticks, series_ticks])
	assert_lte(slow_flush_ticks, flush_ticks / 10,
		"сброс не превышает бюджет систематически (%d из %d тиков со сбросом)" % [slow_flush_ticks, flush_ticks])
	var on_disk := FileRideRepository.new(_dir).get_ride(_recorder.ride_id())
	assert_eq(on_disk.samples.size(), total_ticks, "после сброса на %d с на диске все сэмплы" % total_ticks)


func test_req_loc_07_finish_writes_final_ride_once_and_detaches() -> void:
	var profile := _profile()
	_start_session(_plan([WorkoutStep.watts(15, 150.0)]), profile)
	_ticks(15)
	assert_false(_recorder.is_recording(), "после FINISHED запись окончена")
	assert_eq(_repo.list(profile.id).size(), 1)
	var ride := _repo.get_ride(_recorder.ride_id())
	assert_eq(ride.samples.size(), 15)
	assert_false(ride.is_in_progress())
	assert_eq(ride.summary.duration_sec, 15)
	# dispose дважды — без ошибок; flush после финала — ничего не делает.
	_recorder.dispose()
	_recorder.dispose()
	var count := _recorder.flush_count
	_recorder.flush()
	assert_eq(_recorder.flush_count, count, "flush после финала не пишет")


# ===========================================================================
# REQ-WRK-05 крит. 2 — пауза в метаданных и журнале
# ===========================================================================

func test_req_wrk_05_c2_pause_at_120_for_30_recorded() -> void:
	var profile := _profile()
	_start_session(_plan([WorkoutStep.watts(600, 150.0)]), profile)
	_ticks(120)
	_session.pause()
	_ticks(30)
	_session.resume()
	_ticks(10)
	_session.stop()
	var ride := _repo.get_ride(_recorder.ride_id())
	var pause := _event_of(ride.events, WorkoutSession.EVENT_PAUSE)
	assert_almost_eq(float(pause.get("at_sec", -1)), 120.0, 1e-6, "at_sec = 120")
	assert_almost_eq(float(pause.get("duration_sec", -1)), 30.0, 1e-6, "duration_sec = 30")
	assert_almost_eq(float(pause.get("until_sec", -1)), 150.0, 1e-6, "until_sec = 150")
	assert_almost_eq(ride.paused_total_sec(), 30.0, 1e-6, "paused_total_sec = 30")
	assert_eq(ride.samples.time_sec[120], 120, "сэмплы продолжаются с t = 120 (слот 121-й секунды)")
	assert_eq(ride.samples.size(), 130)
	var pauses := ride.pause_events()
	assert_eq(pauses.size(), 1)
	if pauses.size() == 1:
		assert_true(bool(pauses[0]["resumed"]))


func test_req_wrk_05_c2_two_pauses_sum() -> void:
	var profile := _profile()
	_start_session(_plan([WorkoutStep.watts(600, 150.0)]), profile)
	_ticks(10)
	_session.pause()
	_ticks(5)
	_session.resume()
	_ticks(10)
	_session.pause()
	_ticks(7)
	_session.resume()
	_ticks(5)
	_session.stop()
	var ride := _repo.get_ride(_recorder.ride_id())
	assert_almost_eq(ride.paused_total_sec(), 12.0, 1e-6, "Σ duration_sec = 5 + 7")
	assert_eq(ride.pause_events().size(), 2)
	assert_eq(ride.samples.size(), 25)
	assert_true(ride.samples.is_monotonic())


# ===========================================================================
# Негатив: повреждённые файлы и неверное использование
# ===========================================================================

func test_req_loc_neg_corrupted_index_rebuilt_from_meta() -> void:
	var id1 := _repo.save(_ride(A, START_UNIX, "One", _stream([100, 100])))
	var id2 := _repo.save(_ride(A, START_UNIX + 5, "Two", _stream([120, 120, 120])))
	var index_path := ProjectSettings.globalize_path(_dir).path_join(A).path_join("index.json")
	assert_true(FileAccess.file_exists(index_path))
	var f := FileAccess.open(index_path, FileAccess.WRITE)
	f.store_string("{ not json at all")
	f.close()
	var fresh := FileRideRepository.new(_dir)
	var list := fresh.list(A)
	assert_eq(list.size(), 2, "индекс перестроен по meta.json")
	if list.size() == 2:
		assert_eq(list[0].ride_id, id2, "порядок сохранён")
		assert_eq(list[1].ride_id, id1)
		assert_eq(list[1].avg_power_w, 100)
	assert_not_null(fresh.get_ride(id1))
	# Удалённый index.json тоже перестраивается.
	DirAccess.remove_absolute(index_path)
	assert_eq(FileRideRepository.new(_dir).list(A).size(), 2, "без index.json список восстанавливается")


func test_req_loc_neg_corrupted_meta_excludes_ride_only() -> void:
	var bad := _repo.save(_ride(A, START_UNIX, "Bad", _stream([100, 100])))
	var good := _repo.save(_ride(A, START_UNIX + 5, "Good", _stream([120, 120])))
	var meta_path := ProjectSettings.globalize_path(_dir).path_join(A).path_join(bad).path_join("meta.json")
	var f := FileAccess.open(meta_path, FileAccess.WRITE)
	f.store_string("\u0000\u0001 garbage")
	f.close()
	var fresh := FileRideRepository.new(_dir)
	assert_null(fresh.get_ride(bad), "повреждённый meta.json → заезд не читается")
	assert_not_null(fresh.get_ride(good), "соседний заезд читается")
	var rebuilt := fresh.rebuild_index(A)
	assert_eq(rebuilt.size(), 1, "после перестройки индекса битый заезд исключён")
	assert_eq(fresh.list(A).size(), 1)
	assert_eq(fresh.list(A)[0].ride_id, good)
	assert_false(fresh.update_upload_status(bad, {"strava_status": Ride.UPLOAD_QUEUED}), "статус битого заезда не обновляется")


func test_req_loc_neg_truncated_samples_bin_yields_whole_records() -> void:
	var id := _repo.save(_ride(A, START_UNIX, "Trunc", _stream([100, 110, 120, 130, 140])))
	var bin_path := ProjectSettings.globalize_path(_dir).path_join(A).path_join(id).path_join("samples.bin")
	var bytes := FileAccess.get_file_as_bytes(bin_path)
	var header := FileRideRepository.SAMPLES_HEADER_SIZE
	var rec := FileRideRepository.SAMPLES_RECORD_SIZE
	assert_eq(bytes.size(), header + 5 * rec, "размер файла = заголовок + 5 записей")
	var truncated := bytes.slice(0, header + 3 * rec + rec / 2)
	var f := FileAccess.open(bin_path, FileAccess.WRITE)
	f.store_buffer(truncated)
	f.close()
	var ride := FileRideRepository.new(_dir).get_ride(id)
	assert_not_null(ride, "заезд читается")
	if ride != null:
		assert_eq(ride.samples.size(), 3, "читаются только целые записи, хвост отброшен")
		assert_eq(Array(ride.samples.power_w), [100, 110, 120])
	# Полностью битый заголовок → пустой поток, без падения.
	var g := FileAccess.open(bin_path, FileAccess.WRITE)
	g.store_string("junk")
	g.close()
	var ride2 := FileRideRepository.new(_dir).get_ride(id)
	assert_not_null(ride2)
	if ride2 != null:
		assert_eq(ride2.samples.size(), 0)


func test_req_loc_neg_save_without_profile_and_bad_ids() -> void:
	var r := _ride("", START_UNIX, "NoProfile", _stream([100, 100]))
	assert_eq(_repo.save(r), "", "без профиля не сохраняется")
	assert_eq(_repo.list("").size(), 0)
	assert_false(_repo.save_meta(r))
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir).path_join(r.id)), "каталог не создан")
	assert_eq(_repo.save(null), "", "null-заезд не сохраняется")
	assert_null(_repo.get_ride(""), "пустой id")
	assert_null(_repo.get_ride("missing"))
	assert_false(_repo.append_samples("missing", _stream([1]), 0), "дозапись в несуществующий заезд")
	assert_eq(_repo.delete_profile_rides(""), 0)
	var r2 := _ride(A, START_UNIX, "NoId", _stream([100, 100]))
	r2.id = ""
	var id := _repo.save(r2)
	assert_false(id.is_empty(), "без id — id генерируется")
	assert_not_null(_repo.get_ride(id))


func test_req_loc_neg_two_recorders_on_one_session_and_empty_session() -> void:
	var profile := _profile()
	_trainer = _deterministic_trainer()
	_session = WorkoutSession.new(_plan([WorkoutStep.watts(12, 150.0)]), _trainer, FTP, 1.0, 70.0)
	_recorder = RideRecorder.new(_repo, profile, _session)
	_recorder2 = RideRecorder.new(_repo, profile, _session)
	_session.start()
	_ticks(12)
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)
	var list := _repo.list(profile.id)
	gut.p("two recorders → %d rides in list" % list.size())
	assert_gte(list.size(), 1, "запись не упала")
	for s in list:
		assert_eq(s.duration_sec, 12)
		assert_false(s.in_progress)
	# Пустой поток: стоп сразу после старта.
	var repo2 := FileRideRepository.new(_dir + "empty/")
	var trainer := _deterministic_trainer()
	var session := WorkoutSession.new(_plan([WorkoutStep.watts(60, 150.0)]), trainer, FTP, 1.0, 70.0)
	var rec := RideRecorder.new(repo2, profile, session)
	session.start()
	session.stop()
	var ride := repo2.get_ride(rec.ride_id())
	assert_not_null(ride, "заезд без сэмплов сохранён")
	if ride != null:
		assert_eq(ride.samples.size(), 0)
		assert_true(ride.stopped_early())
		assert_eq(ride.summary.avg_power_w, RideSummary.NO_DATA, "без сэмплов — «нет данных»")
		assert_almost_eq(ride.summary.work_kj, 0.0, 1e-9)
	rec.dispose()


# ===========================================================================
# REQ-NFR-09 крит. 1 — наличие тестовых файлов
# ===========================================================================

func test_req_nfr_09_c1_storage_test_files_exist() -> void:
	for f in ["res://tests/unit/storage/test_ride_summary.gd", "res://tests/unit/storage/test_file_ride_repository.gd",
			"res://tests/unit/storage/test_ride_recorder.gd", "res://tests/unit/integrations/fit/test_fit_encoder.gd",
			"res://tests/unit/integrations/fit/test_fit_crc.gd", "res://tests/unit/integrations/fit/test_fit_decoder.gd"]:
		assert_true(FileAccess.file_exists(f), f + " существует")


# ===========================================================================
# Дополнение приёмки (второй проход): NP — границы алгоритма, зоны пульса при 0,
# recorder на уже идущей сессии, потеря ≤ 10 с, диалог восстановления.
# ===========================================================================

## Крит. 2: «по алгоритму … и для любого заезда NP ≥ средней». На потоке, где
## строгий Coggan даёт NP < средней (вся мощность в первых 10 с), реализация
## обязана вернуть ≥ средней. Фиксируем, что это достигается клампом, а не
## алгоритмом (эталон ниже средней) — решение для владельца.
func test_req_loc_04_c2_np_strict_reference_below_avg_edge_returns_at_least_avg() -> void:
	var powers: Array = []
	for i in 10:
		powers.append(500)
	for i in 50:
		powers.append(100)
	var s := RideSummary.compute(_stream(powers), FTP, PowerZones.coggan(FTP), null)
	var reference := _np_strict(powers)
	gut.p("NP edge 10s@500/50s@100: средняя %d, строгий Coggan %.1f, реализация %d" % [s.avg_power_w, reference, s.normalized_power_w])
	assert_eq(s.avg_power_w, 167)
	assert_lt(reference, float(s.avg_power_w), "предпосылка: строгий Coggan здесь ниже средней")
	assert_gte(s.normalized_power_w, s.avg_power_w, "крит. 2: NP ≥ средней для любого заезда")
	assert_eq(s.normalized_power_w, s.avg_power_w, "реализация клампит NP к средней (не алгоритм) — подтвердить владельцу")


## Крит. 2: пропуски «нет данных» внутри потока — окно считается по сэмплам с
## данными (30 значений, а не 30 с). Фиксируем текущую семантику и NP ≥ средней.
func test_req_loc_04_c2_np_with_no_data_gaps_matches_reference_over_valid_samples() -> void:
	var powers: Array = []
	var valid: Array = []
	for i in 660:
		if i % 11 == 10:
			powers.append(-1)
		else:
			var p: int = 300 if (i / 30) % 2 == 0 else 100
			powers.append(p)
			valid.append(p)
	var s := RideSummary.compute(_stream(powers), FTP, PowerZones.coggan(FTP), null)
	assert_eq(s.power_sample_count, 600)
	assert_gte(s.normalized_power_w, s.avg_power_w)
	assert_almost_eq(float(s.normalized_power_w), _np_strict(valid), 1.0, "NP = Coggan по сэмплам с данными (пропуски не входят в окно)")


## Крит. 5: «сумма равна числу сэмплов с данными … аналогично для 5 зон пульса».
## Показание пульса 0 уд/мин — «нет данных» (решение менеджера В-17): не входит ни в счётчик, ни в среднее, ни в зоны.
func test_req_loc_04_c5_hr_zone_sum_equals_hr_sample_count_with_zero_reading() -> void:
	var s := RideSummary.compute(_stream([200, 200, 200], [0, 150, 150]), FTP, PowerZones.coggan(FTP), HrZones.five_zone(MAX_HR))
	assert_eq(s.hr_sample_count, 2, "пульс 0 — нет данных (В-17)")
	assert_eq(s.avg_hr, 150, "0 не входит в среднее (В-17)")
	assert_eq(s.total_hr_zone_sec(), s.hr_sample_count, "сумма секунд по зонам пульса = число сэмплов с пульсом")
	# Через сессию: датчик прислал 0 на первой секунде.
	var profile := _profile()
	_trainer = _deterministic_trainer(150)
	_trainer.set_heart_rate_sequence([0, 150, 150, 150, 150])
	_session = WorkoutSession.new(_plan([WorkoutStep.watts(5, 150.0)]), _trainer, profile.ftp_w, 1.0, profile.weight_kg)
	_recorder = RideRecorder.new(_repo, profile, _session)
	_session.start()
	_ticks(5)
	var ride := _repo.get_ride(_recorder.ride_id())
	assert_not_null(ride)
	if ride != null:
		assert_eq(ride.summary.hr_sample_count, 4, "слот с пульсом 0 — без данных (В-17), остальные 4 — с пульсом")
		assert_eq(ride.summary.total_hr_zone_sec(), ride.summary.hr_sample_count, "сумма зон пульса = сэмплы с пульсом (сессия)")


## Крит. 1, 2: recorder подключён к уже идущей сессии (новое поведение _init).
func test_req_loc_07_c1_recorder_attached_to_running_session_flushes_and_recovers() -> void:
	var profile := _profile()
	_start_session(_plan([WorkoutStep.watts(600, 150.0)]), profile, 150, true, false)
	_ticks(5)
	_recorder = RideRecorder.new(_repo, profile, _session)
	assert_true(_recorder.is_recording(), "заезд создан сразу для идущей сессии")
	var on_disk := FileRideRepository.new(_dir).get_ride(_recorder.ride_id())
	assert_not_null(on_disk)
	if on_disk != null:
		assert_eq(on_disk.samples.size(), 5, "накопленные 5 сэмплов записаны при подключении")
		assert_true(on_disk.is_in_progress())
	_ticks(17)  # сбросы на 10 и 20
	assert_eq(_recorder.flushed_samples, 20)
	var recovered := FileRideRepository.new(_dir).recover_in_progress(profile.id)
	assert_eq(recovered.size(), 1)
	if recovered.size() == 1:
		assert_eq(recovered[0].samples.size(), 20, "восстановлено до последнего сброса, потеря 2 с")
		assert_true(recovered[0].samples.is_monotonic())
		assert_eq(recovered[0].samples.time_sec[0], 0)


## Крит. 2: сбой за секунду до сброса — потеря ровно 9 с (≤ 10).
func test_req_loc_07_c2_crash_just_before_flush_loses_at_most_10s() -> void:
	var profile := _profile()
	_start_session(_plan([WorkoutStep.watts(600, 150.0)]), profile)
	_ticks(19)
	var recovered := FileRideRepository.new(_dir).recover_in_progress(profile.id)
	assert_eq(recovered.size(), 1)
	if recovered.size() == 1:
		assert_eq(recovered[0].samples.size(), 10, "на диске сброс 10 с; потеряно 9 с")
		assert_gte(10, 19 - recovered[0].samples.size(), "потеря ≤ 10 с")
	# Сбой до первого сброса: заезд есть, сэмплов 0, восстановление не падает.
	_recorder.dispose()
	_recorder = null
	_repo = FileRideRepository.new(_dir + "early/")
	_start_session(_plan([WorkoutStep.watts(600, 150.0)]), profile)
	_ticks(4)
	var early := FileRideRepository.new(_dir + "early/").recover_in_progress(profile.id)
	assert_eq(early.size(), 1)
	if early.size() == 1:
		assert_eq(early[0].samples.size(), 0)
		assert_true(early[0].stopped_early())
		assert_eq(early[0].summary.avg_power_w, RideSummary.NO_DATA)


## Крит. 3: диалог восстановления предлагает «сохранить как завершённый досрочно»
## или «удалить»; оба решения доходят до хранилища.
func test_req_loc_07_c3_recovery_dialog_offers_keep_or_delete() -> void:
	var profile := _profile()
	_start_session(_plan([WorkoutStep.watts(600, 150.0)]), profile)
	_ticks(31)
	_recorder.dispose()
	_recorder = null
	_repo = FileRideRepository.new(_dir + "second/")
	_start_session(_plan([WorkoutStep.watts(600, 150.0)]), profile)
	_ticks(12)
	var fresh := FileRideRepository.new(_dir)
	var fresh2 := FileRideRepository.new(_dir + "second/")
	var rides: Array[Ride] = fresh.recover_in_progress(profile.id)
	rides.append_array(fresh2.recover_in_progress(profile.id))
	assert_eq(rides.size(), 2)
	if rides.size() != 2:
		return
	var dialog: RecoveryDialog = autofree(RecoveryDialog.new())
	var decisions: Array = []
	dialog.resolved.connect(func(id: String, action: String) -> void: decisions.append([id, action]))
	dialog.show_for(rides)
	assert_eq(dialog.current_ride().id, rides[0].id, "первый заезд предложен")
	assert_eq(dialog.pending_count(), 1)
	dialog.keep()
	assert_eq(dialog.current_ride().id, rides[1].id, "после решения — следующий")
	dialog.delete_current()
	assert_null(dialog.current_ride())
	assert_eq(decisions, [[rides[0].id, RecoveryDialog.ACTION_KEEP], [rides[1].id, RecoveryDialog.ACTION_DELETE]])
	# «Сохранить» — заезд уже сохранён как завершённый досрочно; «удалить» — владелец вызывает delete.
	var kept := fresh.get_ride(rides[0].id)
	assert_not_null(kept)
	if kept != null:
		assert_true(kept.stopped_early())
		assert_true(kept.is_recovered())
		assert_eq(kept.samples.size(), 30)
	assert_true(fresh2.delete(rides[1].id))
	assert_null(fresh2.get_ride(rides[1].id))
	assert_eq(fresh2.list(profile.id).size(), 0)
