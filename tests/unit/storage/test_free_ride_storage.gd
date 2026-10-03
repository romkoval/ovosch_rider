extends GutTest
## Хранилище свободной езды (T-064): REQ-FRD-07 крит. 3 (метаданные), крит. 4 (дистанция,
## высота и уклон в каждом сэмпле, набор высоты по сэмплам), крит. 6 (сводка и серии без
## цели); регрессия REQ-LOC-01 (запись и чтение), REQ-LOC-07 (дозапись и восстановление,
## в том числе потока старого формата), REQ-LOC-04 (сводка).

const FIXTURE_DIR: String = "res://tests/fixtures/rides_v1/"
const LEGACY_PROFILE: String = "legacy-profile"
const LEGACY_RIDE: String = "1700000000-0a1b2c3d"
const PROFILE: String = "profile-free"
const STARTED: int = 1_790_000_000
const ROUTE: String = "mountains"
## Синтетическая трасса: длина круга, м, и рельеф h(s) = BASE + AMP · sin(2πs / L).
const LAP_M: float = 2000.0
const BASE_M: float = 300.0
const AMP_M: float = 40.0
## Скорость модели, км/ч (10 м/с → 200 сэмплов на круг).
const SPEED_KMH: float = 36.0


## Сессия свободной езды для `RideRecorder` и `Ride.from_session` (контракт записи).
class FakeFreeRideSession:
	extends RefCounted
	signal state_changed(state: int)
	signal event_logged(event: Dictionary)
	signal second_elapsed(elapsed_sec: int)

	var samples := SampleStream.new()
	var events: Array[Dictionary] = []
	var started_at_unix: int = 0
	var route_id: String = ""
	var steepness_pct: float = 50.0
	var _state: int = WorkoutSession.State.IDLE
	var _elapsed: int = 0

	func get_state() -> int:
		return _state

	func elapsed_sec() -> int:
		return _elapsed

	func metadata() -> Dictionary:
		var m := Ride.free_ride_metadata(route_id, steepness_pct)
		m["started_at_unix"] = started_at_unix
		m["ftp_w"] = 250
		m["weight_kg"] = 72.0
		m["elapsed_sec"] = _elapsed
		m["paused_total_sec"] = 0.0
		m["stopped_early"] = false
		m["sample_count"] = samples.size()
		m["event_count"] = events.size()
		return m

	func start() -> void:
		samples.speed_source = SampleStream.SPEED_SOURCE_MODEL
		events.append({"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0})
		_state = WorkoutSession.State.RUNNING
		state_changed.emit(_state)

	func tick_second(route: Dictionary) -> void:
		samples.append(_elapsed, TrainerSample.full(float(_elapsed), 250, 90, 0.0), 140, 0, -1, false, SPEED_KMH, {}, route)
		_elapsed += 1
		second_elapsed.emit(_elapsed)

	func pause() -> void:
		_state = WorkoutSession.State.PAUSED
		state_changed.emit(_state)
		var e := {"type": WorkoutSession.EVENT_PAUSE, "at_sec": float(_elapsed), "value": _elapsed}
		events.append(e)
		event_logged.emit(e)

	func resume() -> void:
		_state = WorkoutSession.State.RUNNING
		state_changed.emit(_state)

	func stop() -> void:
		events.append({"type": WorkoutSession.EVENT_STOP, "at_sec": float(_elapsed), "value": _elapsed})
		_state = WorkoutSession.State.FINISHED
		state_changed.emit(_state)


var _dir: String
var _repo: RideRepository


func before_each() -> void:
	_dir = "user://test_free_ride_storage_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_repo = FileRideRepository.new(_dir)


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


static func _copy_tree(from_dir: String, to_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(to_dir)
	var d := DirAccess.open(from_dir)
	for f in d.get_files():
		DirAccess.copy_absolute(from_dir.path_join(f), to_dir.path_join(f))
	for sub in d.get_directories():
		_copy_tree(from_dir.path_join(sub), to_dir.path_join(sub))


## Позиция на синтетической трассе по накопленной дистанции.
static func _route_at(distance: float) -> Dictionary:
	var s: float = fposmod(distance, LAP_M)
	var phase: float = TAU * s / LAP_M
	return {
		"distance_m": distance,
		"altitude_m": BASE_M + AMP_M * sin(phase),
		"grade_pct": 100.0 * AMP_M * TAU / LAP_M * cos(phase),
	}


## Поток свободной езды на `seconds` с: 10 м/с, позиция по `_route_at`.
static func _free_stream(seconds: int) -> SampleStream:
	var s := SampleStream.new()
	s.speed_source = SampleStream.SPEED_SOURCE_MODEL
	for i in seconds:
		var p: int = 200 + (i % 7) * 10
		s.append(i, TrainerSample.full(float(i), p, 88, 0.0), 130 + i % 20, 0, -1, false,
				SPEED_KMH, {}, _route_at(float(i + 1) * SPEED_KMH / 3.6))
	return s


func _free_ride(seconds: int = 30) -> Ride:
	var r := Ride.new()
	r.id = Ride.generate_id(STARTED)
	r.profile_id = PROFILE
	r.started_at_unix = STARTED
	r.metadata = Ride.free_ride_metadata(ROUTE, 50.0)
	r.metadata["ftp_w"] = 250
	r.metadata["max_hr"] = 190
	r.metadata["in_progress"] = false
	r.metadata["recovered"] = false
	r.samples = _free_stream(seconds)
	r.events = [{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0}]
	r.compute_summary()
	return r


# ---------------------------------------------------------------------------
# REQ-FRD-07 крит. 4 — дистанция, высота и уклон каждого сэмпла через RideRepository
# ---------------------------------------------------------------------------

func test_req_frd_07_c4_save_and_read_returns_distance_altitude_grade_per_sample() -> void:
	var ride := _free_ride(45)
	assert_ne(_repo.save(ride), "")
	var back := FileRideRepository.new(_dir).get_ride(ride.id)  # новый экземпляр — чтение с диска
	assert_not_null(back)
	assert_eq(back.samples.size(), 45)
	assert_true(back.samples.has_route_data(), "REQ-FRD-07 крит. 4: позиция на трассе сохранена")
	for i in 45:
		var expected := _route_at(float(i + 1) * SPEED_KMH / 3.6)
		assert_true(back.samples.has_route[i])
		assert_almost_eq(back.samples.distance_m[i], float(expected["distance_m"]), 0.01, "дистанция сэмпла %d" % i)
		assert_almost_eq(back.samples.altitude_m[i], float(expected["altitude_m"]), 0.001, "высота сэмпла %d" % i)
		assert_almost_eq(back.samples.grade_pct[i], float(expected["grade_pct"]), 0.001, "уклон сэмпла %d" % i)
	assert_eq(back.samples.power_w, ride.samples.power_w, "остальные колонки не пострадали")
	assert_eq(back.samples.heart_rate_bpm, ride.samples.heart_rate_bpm)
	assert_eq(back.samples.speed_source, SampleStream.SPEED_SOURCE_MODEL)


func test_req_frd_07_c4_session_distance_replaces_speed_integral() -> void:
	var s := SampleStream.new()
	# Скорость 36 км/ч, а позиция от сессии — 7 м за секунду: в потоке — дистанция сессии.
	for i in 3:
		s.append(i, TrainerSample.full(0.0, 200, 90, 36.0), -1, 0, -1, false, -1.0, {},
				{"distance_m": 7.0 * (i + 1), "altitude_m": 100.0 + i, "grade_pct": 1.5})
	assert_almost_eq(s.total_distance_m(), 21.0, 1e-4)
	assert_almost_eq(s.total_ascent_m(), 2.0, 1e-4)
	var row := s.row(2)
	assert_true(bool(row["has_route"]))
	assert_almost_eq(float(row["altitude_m"]), 102.0, 1e-4)
	assert_almost_eq(float(row["grade_pct"]), 1.5, 1e-4)


func test_req_frd_07_c4_workout_samples_have_no_route_fields() -> void:
	var s := SampleStream.new()
	s.append(0, TrainerSample.full(0.0, 200, 90, 36.0), 140, 200, 0, true)
	assert_false(s.has_route_data(), "у заезда по плану позиции на трассе нет")
	assert_eq(s.total_ascent_m(), 0.0)
	assert_almost_eq(s.total_distance_m(), 10.0, 1e-4, "дистанция — интеграл скорости, как раньше")


func test_req_frd_07_c4_stream_dict_roundtrip_and_old_dict_without_route() -> void:
	var s := _free_stream(5)
	var back := SampleStream.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(back.size(), 5)
	for i in 5:
		assert_eq(back.has_route[i], true)
		assert_almost_eq(back.altitude_m[i], s.altitude_m[i], 1e-3)
		assert_almost_eq(back.grade_pct[i], s.grade_pct[i], 1e-3)
		assert_almost_eq(back.distance_m[i], s.distance_m[i], 1e-3)
	var old := SampleStream.from_dict({"time_sec": [0, 1], "power_w": [100, 110], "has_power": [true, true]})
	assert_eq(old.size(), 2)
	assert_false(old.has_route_data(), "словарь без колонок позиции — «нет позиции»")
	assert_eq(old.altitude_m.size(), 2, "колонки одинаковой длины")


# ---------------------------------------------------------------------------
# REQ-FRD-07 крит. 4 — набор высоты = сумма положительных приращений; N кругов = N × круг
# ---------------------------------------------------------------------------

func test_req_frd_07_c4_ascent_two_laps_equals_twice_one_lap_within_5_pct() -> void:
	var per_lap: int = roundi(LAP_M / (SPEED_KMH / 3.6))  # 200 сэмплов
	var one := _free_stream(per_lap)
	var two := _free_stream(2 * per_lap)
	var lap_ascent: float = one.total_ascent_m()
	assert_almost_eq(lap_ascent, 2.0 * AMP_M, 2.0 * AMP_M * 0.05, "набор круга ≈ размах рельефа")
	assert_almost_eq(two.total_ascent_m(), 2.0 * lap_ascent, 2.0 * lap_ascent * 0.05,
			"REQ-FRD-07 крит. 4: набор двух кругов = 2 × набор круга ± 5 %")
	var ride := _free_ride(2 * per_lap)
	assert_almost_eq(ride.total_ascent_m(), two.total_ascent_m(), 1e-3, "в метаданных — набор по сэмплам")
	assert_almost_eq(ride.summary.ascent_m, two.total_ascent_m(), 1e-3, "и в сводке")


func test_req_frd_07_c4_ascent_counts_only_positive_increments() -> void:
	var s := SampleStream.new()
	var heights: Array[float] = [100.0, 105.0, 103.0, 103.0, 110.0, 90.0, 91.0]
	for i in heights.size():
		s.append(i, null, -1, 0, -1, false, 10.0, {}, {"distance_m": float(i), "altitude_m": heights[i], "grade_pct": 0.0})
	assert_almost_eq(s.total_ascent_m(), 5.0 + 7.0 + 1.0, 1e-4)


# ---------------------------------------------------------------------------
# REQ-FRD-07 крит. 3 — метаданные свободной езды
# ---------------------------------------------------------------------------

func test_req_frd_07_c3_free_ride_metadata_saved_and_read() -> void:
	var ride := _free_ride(60)
	ride.name = "План, которого быть не должно"
	ride.workout = {"name": "x"}
	ride.metadata["workout_name"] = "x"
	ride.refresh_from_session(_session_stub(ride))
	_repo.save(ride)
	var back := FileRideRepository.new(_dir).get_ride(ride.id)
	assert_eq(back.ride_type(), Ride.RIDE_TYPE_FREE_RIDE, "REQ-FRD-07 крит. 3: тип «свободная езда»")
	assert_true(back.is_free_ride())
	assert_eq(back.route_id(), ROUTE, "идентификатор трассы")
	assert_almost_eq(back.sim_steepness_start_pct(), 50.0, 1e-6, "крутизна на старте")
	assert_almost_eq(back.total_distance_m(), 600.0, 0.01, "итоговая дистанция, м")
	assert_almost_eq(back.total_ascent_m(), back.samples.total_ascent_m(), 1e-3, "набор высоты, м")
	assert_eq(back.speed_source(), SampleStream.SPEED_SOURCE_MODEL, "speed_source = модель")
	assert_eq(back.name, "", "названия плана нет")
	assert_true(back.workout.is_empty(), "плана нет")
	assert_false(back.metadata.has("workout_name"))
	var listed := _repo.list(PROFILE)
	assert_eq(listed.size(), 1)
	assert_eq(listed[0].ride_type, Ride.RIDE_TYPE_FREE_RIDE, "строка истории знает тип без чтения потока")
	assert_eq(listed[0].route_id, ROUTE)
	assert_almost_eq(listed[0].distance_m, 600.0, 0.01)


## Сессия-заглушка, отдающая метаданные заезда (для `refresh_from_session`).
func _session_stub(ride: Ride) -> FakeFreeRideSession:
	var s := FakeFreeRideSession.new()
	s.samples = ride.samples
	s.events = ride.events
	s.route_id = ROUTE
	s.started_at_unix = ride.started_at_unix
	return s


func test_req_frd_07_c3_workout_rides_are_typed_workout() -> void:
	var r := Ride.new()
	assert_eq(r.ride_type(), Ride.RIDE_TYPE_WORKOUT, "без поля — тренировка по плану")
	assert_eq(r.route_id(), "")
	r.metadata = {"ride_type": "garbage"}
	assert_eq(r.ride_type(), Ride.RIDE_TYPE_WORKOUT)


# ---------------------------------------------------------------------------
# Старые заезды (samples.bin v1, без типа) читаются без миграции — REQ-LOC-01, LOC-07
# ---------------------------------------------------------------------------

func _legacy_repo() -> FileRideRepository:
	_copy_tree(ProjectSettings.globalize_path(FIXTURE_DIR), ProjectSettings.globalize_path(_dir))
	return FileRideRepository.new(_dir)


func test_req_loc_01_legacy_ride_from_fixture_reads_without_errors() -> void:
	var repo := _legacy_repo()
	var listed := repo.list(LEGACY_PROFILE)
	assert_eq(listed.size(), 1, "REQ-LOC-02: старый индекс читается")
	assert_eq(listed[0].ride_type, Ride.RIDE_TYPE_WORKOUT)
	assert_eq(listed[0].avg_power_w, 218)
	var ride := repo.get_ride(LEGACY_RIDE)
	assert_not_null(ride, "REQ-LOC-01: старый заезд читается")
	assert_eq(ride.name, "Legacy sweet spot")
	assert_eq(ride.ride_type(), Ride.RIDE_TYPE_WORKOUT, "без типа — тренировка по плану")
	assert_eq(ride.samples.size(), 8, "все записи потока v1")
	assert_false(ride.samples.has_route_data(), "в старом потоке позиции на трассе нет")
	assert_eq(ride.samples.power_w[7], 235)
	assert_false(ride.samples.has_power[3], "слот без телеметрии сохранил «нет данных»")
	assert_eq(ride.samples.heart_rate_bpm[0], 140)
	assert_almost_eq(ride.samples.total_distance_m(), float(ride.metadata["distance_m"]), 1e-3)
	var summary := ride.compute_summary()
	assert_eq(summary.avg_power_w, 218, "REQ-LOC-04: сводка старого заезда считается как раньше")
	assert_eq(summary.avg_target_w, 200)
	assert_eq(summary.ascent_m, 0.0)
	var series := RideSeries.from_samples(ride.samples)
	assert_true(series.has_target, "REQ-LOC-03 крит. 3: у тренировки серия цели есть")
	assert_eq(series.count(RideSeries.TARGET), 8)


func test_req_loc_07_append_to_legacy_stream_rewrites_in_current_format() -> void:
	var repo := _legacy_repo()
	var ride := repo.get_ride(LEGACY_RIDE)
	var stream := ride.samples
	for i in range(8, 12):
		stream.append(i, TrainerSample.full(1.0, 240, 90, 30.0), 150, 200, 0, true)
	assert_true(repo.append_samples(LEGACY_RIDE, stream, 8), "дозапись в поток v1")
	var back := FileRideRepository.new(_dir).get_ride(LEGACY_RIDE)
	assert_eq(back.samples.size(), 12, "REQ-LOC-07: ни одна секунда не потеряна")
	assert_eq(back.samples.power_w[11], 240)
	assert_eq(back.samples.power_w[7], 235)
	assert_true(repo.append_samples(LEGACY_RIDE, stream, 12), "дальше — обычная дозапись")


# ---------------------------------------------------------------------------
# REQ-FRD-07 крит. 6 — сводка и серии без цели, профиль высоты по дистанции
# ---------------------------------------------------------------------------

func test_req_frd_07_c6_summary_without_target_has_no_data_fields() -> void:
	var ride := _free_ride(120)
	var s := ride.compute_summary()
	assert_eq(s.avg_target_w, RideSummary.NO_DATA, "REQ-FRD-07 крит. 6: поле цели — «нет значения»")
	assert_false(s.has_target())
	assert_eq(RideDetail.number_text(s.avg_target_w), "—", "в карточке — «—»")
	assert_true(s.is_free_ride())
	assert_eq(s.duration_sec, 120)
	assert_eq(s.power_sample_count, 120)
	assert_gt(s.avg_power_w, 0, "остальная сводка считается")
	assert_gt(s.normalized_power_w, 0)
	assert_almost_eq(s.distance_m, 1200.0, 0.01)
	var copy := RideSummary.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(copy.avg_target_w, RideSummary.NO_DATA)
	assert_eq(copy.ride_type, Ride.RIDE_TYPE_FREE_RIDE)
	assert_eq(copy.route_id, ROUTE)
	assert_almost_eq(copy.ascent_m, s.ascent_m, 1e-3)


func test_req_frd_07_c6_series_without_target_and_altitude_by_distance() -> void:
	var ride := _free_ride(600)
	var series := RideSeries.from_samples(ride.samples)
	assert_false(series.has_target, "REQ-FRD-07 крит. 6: без серии цели")
	assert_eq(series.values(RideSeries.TARGET).size(), 0)
	assert_eq(series.count(RideSeries.TARGET), 0)
	assert_eq(series.points(RideSeries.TARGET).size(), 0)
	assert_eq(series.count(RideSeries.POWER), 600, "серия мощности как обычно")
	var profile := RideSeries.altitude_by_distance(ride.samples)
	assert_eq(profile.size(), 600, "точка на сэмпл без прореживания")
	assert_almost_eq(profile[0].x, 10.0, 1e-3)
	assert_almost_eq(profile[599].x, 6000.0, 0.01, "дистанция накопленная — круги подряд")
	for i in range(1, profile.size()):
		assert_true(profile[i].x > profile[i - 1].x, "x монотонно растёт")
	var thin := RideSeries.altitude_by_distance(ride.samples, 100)
	assert_lte(thin.size(), 100, "прореживание")
	var hi: float = -INF
	var lo: float = INF
	for p in thin:
		hi = maxf(hi, p.y)
		lo = minf(lo, p.y)
	assert_almost_eq(hi, Array(ride.samples.altitude_m).max(), 1e-3, "вершина среди точек")
	assert_almost_eq(lo, Array(ride.samples.altitude_m).min(), 1e-3, "впадина среди точек")
	var workout := SampleStream.new()
	workout.append(0, TrainerSample.full(0.0, 200, 90, 30.0), 140, 200, 0, true)
	assert_eq(RideSeries.altitude_by_distance(workout).size(), 0, "у тренировки по плану профиля нет")


# ---------------------------------------------------------------------------
# REQ-FRD-07 крит. 2–4 / REQ-LOC-07 — запись свободной езды через RideRecorder
# ---------------------------------------------------------------------------

func test_req_frd_07_c3_recorder_writes_free_ride_with_metadata_and_streams() -> void:
	var profile := Profile.create("Райдер")
	var session := FakeFreeRideSession.new()
	session.route_id = ROUTE
	session.started_at_unix = STARTED
	var recorder := RideRecorder.new(_repo, profile, session)
	session.start()
	assert_true(recorder.is_recording(), "запись начата при старте")
	var id := recorder.ride_id()
	for i in 25:
		session.tick_second(_route_at(float(i + 1) * 10.0))
	assert_eq(recorder.flushed_samples, 20, "REQ-LOC-07: сброс каждые 10 с сессионного времени")
	var mid := FileRideRepository.new(_dir).get_ride(id)
	assert_true(mid.is_in_progress())
	assert_true(mid.is_free_ride())
	assert_eq(mid.samples.size(), 20)
	assert_true(mid.samples.has_route[19], "позиция на трассе — уже в промежуточной записи")
	session.pause()
	session.resume()
	session.stop()
	assert_false(recorder.is_recording())
	var back := FileRideRepository.new(_dir).get_ride(id)
	assert_false(back.is_in_progress())
	assert_eq(back.samples.size(), 25)
	assert_eq(back.route_id(), ROUTE)
	assert_almost_eq(back.sim_steepness_start_pct(), 50.0, 1e-6)
	assert_almost_eq(back.total_distance_m(), 250.0, 0.01)
	assert_almost_eq(back.total_ascent_m(), back.samples.total_ascent_m(), 1e-3)
	assert_gt(back.total_ascent_m(), 0.0)
	assert_eq(back.speed_source(), SampleStream.SPEED_SOURCE_MODEL)
	assert_eq(back.name, "")
	assert_eq(back.summary.ride_type, Ride.RIDE_TYPE_FREE_RIDE)
	assert_eq(back.pause_events().size(), 1, "пауза в журнале")
	assert_false(session.second_elapsed.is_connected(recorder._on_session_second), "подписки сняты")


func test_req_loc_07_free_ride_recovery_keeps_route_data() -> void:
	var profile := Profile.create("Райдер")
	var session := FakeFreeRideSession.new()
	session.route_id = ROUTE
	session.started_at_unix = STARTED
	var recorder := RideRecorder.new(_repo, profile, session)
	session.start()
	for i in 30:
		session.tick_second(_route_at(float(i + 1) * 10.0))
	var id := recorder.ride_id()
	recorder.dispose()  # «сбой»: финальной записи нет
	var repo2 := FileRideRepository.new(_dir)
	var recovered := repo2.recover_in_progress(profile.id)
	assert_eq(recovered.size(), 1)
	var back := repo2.get_ride(id)
	assert_true(back.is_recovered())
	assert_true(back.is_free_ride())
	assert_eq(back.samples.size(), 30)
	assert_true(back.samples.has_route_data())
	assert_almost_eq(back.total_distance_m(), 300.0, 0.01, "итоги пересчитаны по сэмплам")
	assert_almost_eq(back.total_ascent_m(), back.samples.total_ascent_m(), 1e-3)
