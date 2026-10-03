extends GutTest
## Приёмка T-064 (tester): хранилище свободной езды.
## REQ-FRD-07 крит. 3 (метаданные), крит. 4 (дистанция, высота, уклон в каждом сэмпле; набор
## по сэмплам = N × набор трассы ± 5 %), крит. 6 (сводка и серии без цели, без ошибок; заезд
## в списке наравне с тренировками), крит. 7 (название в Strava «Свободная езда — <трасса>» /
## «Free ride — <track>», выгрузка как STR-02..05); совместимость со старым `samples.bin` v1.
##
## Сессия свободной езды (T-077) ещё не написана: заезд пишет `RideRecorder` с подставной
## сессией `AccFreeRideSession`, которая выполняет только заявленный контракт записи —
## сигналы `state_changed`, `event_logged`, `second_elapsed`; методы `get_state`,
## `elapsed_sec`, `metadata`; свойства `samples`, `events`, `started_at_unix`.

const STARTED: int = 1_801_000_000
const NOW: int = 1_801_100_000


## Подставная сессия свободной езды строго по контракту `RideRecorder` / `Ride.from_session`.
class AccFreeRideSession:
	extends RefCounted
	signal state_changed(state: int)
	signal event_logged(event: Dictionary)
	signal second_elapsed(elapsed_sec: int)

	var samples := SampleStream.new()
	var events: Array[Dictionary] = []
	var started_at_unix: int = 0
	var route: RouteCatalog.RouteDef
	var steepness: float = 50.0
	var ftp: int = 250
	var distance: float = 0.0
	var _state: int = WorkoutSession.State.IDLE
	var _elapsed: int = 0
	var _paused_total: float = 0.0

	func _init(route_id: String, started: int) -> void:
		route = RouteCatalog.get_route(route_id)
		started_at_unix = started
		samples.speed_source = SampleStream.SPEED_SOURCE_MODEL

	func get_state() -> int:
		return _state

	func elapsed_sec() -> int:
		return _elapsed

	func metadata() -> Dictionary:
		var m := Ride.free_ride_metadata(route.id, steepness)
		m["started_at_unix"] = started_at_unix
		m["ftp_w"] = ftp
		m["weight_kg"] = 72.0
		m["paused_total_sec"] = _paused_total
		m["elapsed_sec"] = _elapsed
		m["stopped_early"] = false
		return m

	func start() -> void:
		_state = WorkoutSession.State.RUNNING
		state_changed.emit(_state)
		_log(WorkoutSession.EVENT_START, 0)

	## Одна секунда езды с мощностью `power` и скоростью `kmh` (модель скорости — у теста).
	func ride_second(power: int, kmh: float) -> void:
		distance += kmh / 3.6
		var p: RouteProfile = route.profile
		var t: int = _elapsed
		samples.append(t, TrainerSample.full(float(t), power, 88, 0.0), 140, 0, -1, false, kmh, {},
			{"distance_m": distance, "altitude_m": p.height_at(distance), "grade_pct": p.grade_at(distance)})
		_elapsed += 1
		second_elapsed.emit(_elapsed)

	func pause() -> void:
		_state = WorkoutSession.State.PAUSED
		state_changed.emit(_state)
		_log(WorkoutSession.EVENT_PAUSE, _elapsed)

	func resume(paused_sec: float) -> void:
		_paused_total += paused_sec
		_state = WorkoutSession.State.RUNNING
		state_changed.emit(_state)
		_log(WorkoutSession.EVENT_RESUME, _elapsed)

	func finish() -> void:
		_state = WorkoutSession.State.FINISHED
		_log(WorkoutSession.EVENT_FINISH, _elapsed)
		state_changed.emit(_state)

	func _log(type: String, value: Variant) -> void:
		var e := {"type": type, "at_sec": float(_elapsed), "value": value}
		events.append(e)
		event_logged.emit(e)


var _dir: String
var _repo: FileRideRepository
var _profile: Profile
var _previous_locale: String


func before_each() -> void:
	_previous_locale = TranslationServer.get_locale()
	_dir = "user://acc_free_ride_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_repo = FileRideRepository.new(_dir + "rides/")
	_profile = Profile.create("Тестер")
	_profile.max_hr = 186


func after_each() -> void:
	TranslationServer.set_locale(_previous_locale)
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


static func _copy_tree(from_abs: String, to_abs: String) -> void:
	DirAccess.make_dir_recursive_absolute(to_abs)
	var d := DirAccess.open(from_abs)
	for f in d.get_files():
		if f.ends_with(".import") or f.ends_with(".uid"):
			continue
		DirAccess.copy_absolute(from_abs.path_join(f), to_abs.path_join(f))
	for sub in d.get_directories():
		_copy_tree(from_abs.path_join(sub), to_abs.path_join(sub))


## Скорость «модели» для теста: на подъёме медленнее, на спуске быстрее (8…60 км/ч).
static func _kmh(grade_pct: float) -> float:
	return clampf(34.0 - 3.2 * grade_pct, 8.0, 60.0)


## Записать заезд через RideRecorder: `laps` кругов (или `seconds` секунд) по трассе.
func _record(route_id: String, laps: float, seconds: int = -1, pause_at: int = -1) -> Dictionary:
	var session := AccFreeRideSession.new(route_id, STARTED)
	var recorder := RideRecorder.new(_repo, _profile, session)
	session.start()
	var target: float = laps * session.route.profile.length_m()
	var n: int = 0
	while (seconds < 0 and session.distance < target) or (seconds >= 0 and n < seconds):
		if n == pause_at:
			session.pause()
			session.resume(30.0)
		var g: float = session.route.profile.grade_at(session.distance)
		session.ride_second(220, _kmh(g))
		n += 1
	session.finish()
	var id: String = recorder.ride_id()
	recorder.dispose()
	return {"id": id, "session": session}


# ---------------------------------------------------------------------------
# FRD-07 крит. 3 — метаданные
# ---------------------------------------------------------------------------

func test_req_frd_07_c3_metadata_of_saved_free_ride() -> void:
	var rec := _record("mountains", 0.0, 600, 300)
	var session: AccFreeRideSession = rec["session"]
	var ride := _repo.get_ride(rec["id"])
	assert_not_null(ride, "заезд сохранён через RideRepository")
	if ride == null:
		return
	var m: Dictionary = ride.metadata
	assert_eq(str(m.get("ride_type")), "free_ride", "тип «свободная езда»")
	assert_true(ride.is_free_ride())
	assert_eq(str(m.get("route_id")), "mountains", "идентификатор трассы")
	assert_eq(ride.route_id(), "mountains")
	assert_almost_eq(float(m.get("sim_steepness_start_pct", -1.0)), 50.0, 1e-6, "крутизна на старте")
	assert_almost_eq(float(m.get("total_distance_m", -1.0)), session.distance, 0.05, "итоговая дистанция, м")
	assert_almost_eq(float(m.get("total_ascent_m", -1.0)), session.samples.total_ascent_m(), 0.05, "набор высоты, м")
	assert_gt(float(m.get("total_ascent_m", 0.0)), 10.0, "на подъёме гор набор есть")
	assert_eq(str(m.get("speed_source")), SampleStream.SPEED_SOURCE_MODEL, "speed_source = модель")
	assert_eq(ride.samples.speed_source, SampleStream.SPEED_SOURCE_MODEL, "источник скорости в потоке")
	assert_false(m.has("workout_name"), "названия плана нет")
	assert_eq(ride.name, "", "название заезда — пустое (по умолчанию строится в Strava/истории)")
	assert_true(ride.workout.is_empty(), "плана нет")
	# LOC-01.1 сохраняется наравне с тренировкой.
	assert_eq(int(m.get("started_at_unix", 0)), STARTED, "дата/время старта")
	assert_eq(ride.started_at_unix, STARTED)
	assert_eq(int(m.get("ftp_w", 0)), 250, "FTP на момент заезда")
	assert_almost_eq(float(m.get("weight_kg", 0.0)), 72.0, 1e-6, "вес")
	assert_eq(int(m.get("max_hr", 0)), 186, "max_hr профиля")
	assert_almost_eq(float(m.get("paused_total_sec", -1.0)), 30.0, 1e-6, "paused_total_sec")
	assert_false(ride.is_in_progress(), "финальная запись")
	var types: Array = []
	for e in ride.events:
		types.append(e["type"])
	assert_true(types.has(WorkoutSession.EVENT_PAUSE) and types.has(WorkoutSession.EVENT_RESUME), "события паузы сохранены: %s" % str(types))


func test_req_frd_07_c3_workout_ride_keeps_type_workout_and_old_fields() -> void:
	var r := Ride.new()
	r.id = Ride.generate_id(STARTED)
	r.profile_id = _profile.id
	r.started_at_unix = STARTED
	r.name = "Sweet Spot"
	r.workout = Workout.make("Sweet Spot", [WorkoutStep.watts(5, 200.0)] as Array[WorkoutStep]).to_dict()
	r.metadata = {"ftp_w": 200, "workout_name": "Sweet Spot", "speed_source": SampleStream.SPEED_SOURCE_TRAINER}
	for i in 5:
		r.samples.append(i, TrainerSample.full(float(i), 200, 85, 30.0), 140, 200, 0, true)
	r.compute_summary()
	_repo.save(r)
	var back := _repo.get_ride(r.id)
	assert_eq(back.ride_type(), "workout", "заезд без поля типа — тренировка")
	assert_false(back.is_free_ride())
	assert_eq(back.route_id(), "")
	assert_eq(str(back.metadata.get("workout_name")), "Sweet Spot")
	assert_eq(back.name, "Sweet Spot")


# ---------------------------------------------------------------------------
# FRD-07 крит. 4 — потоки и набор
# ---------------------------------------------------------------------------

func test_req_frd_07_c4_each_sample_has_distance_altitude_grade_after_save_and_read() -> void:
	var rec := _record("hills", 0.0, 900)
	var session: AccFreeRideSession = rec["session"]
	var ride := _repo.get_ride(rec["id"])
	assert_not_null(ride)
	if ride == null:
		return
	assert_eq(ride.samples.size(), session.samples.size(), "все сэмплы прочитаны")
	var bad: Array[String] = []
	for i in ride.samples.size():
		var row := ride.samples.row(i)
		var src := session.samples.row(i)
		if not bool(row["has_route"]):
			bad.append("#%d без позиции на трассе" % i)
		if absf(float(row["distance_m"]) - float(src["distance_m"])) > 0.01:
			bad.append("#%d дистанция %.4f ≠ %.4f" % [i, row["distance_m"], src["distance_m"]])
		if absf(float(row["altitude_m"]) - float(src["altitude_m"])) > 0.01:
			bad.append("#%d высота %.4f ≠ %.4f" % [i, row["altitude_m"], src["altitude_m"]])
		if absf(float(row["grade_pct"]) - float(src["grade_pct"])) > 0.001:
			bad.append("#%d уклон %.4f ≠ %.4f" % [i, row["grade_pct"], src["grade_pct"]])
	assert_eq(bad, [] as Array[String], str(bad.slice(0, 5)))
	# Дистанция — накопленная от старта, монотонно растёт.
	for i in range(1, ride.samples.size()):
		if ride.samples.distance_m[i] < ride.samples.distance_m[i - 1]:
			fail_test("дистанция убывает на #%d" % i)
			break


func test_req_frd_07_c4_flushed_in_progress_ride_keeps_route_fields() -> void:
	# Сбой посреди заезда (LOC-07): то, что успело на диск через append_samples, читается с позицией.
	var session := AccFreeRideSession.new("seaside", STARTED)
	var recorder := RideRecorder.new(_repo, _profile, session)
	session.start()
	for i in 95:
		session.ride_second(200, _kmh(session.route.profile.grade_at(session.distance)))
	var id := recorder.ride_id()
	recorder.dispose()  # «сбой»: финальной записи нет
	var fresh := FileRideRepository.new(_dir + "rides/")
	var recovered := fresh.recover_in_progress(_profile.id)
	assert_eq(recovered.size(), 1, "незавершённый заезд восстановлен")
	var ride := fresh.get_ride(id)
	assert_not_null(ride)
	if ride == null:
		return
	assert_gte(ride.samples.size(), 90, "на диске не старше 10 с")
	for i in ride.samples.size():
		assert_true(ride.samples.has_route[i], "#%d с позицией на трассе" % i)
		assert_almost_eq(ride.samples.altitude_m[i], session.samples.altitude_m[i], 0.01)
		assert_almost_eq(ride.samples.distance_m[i], session.samples.distance_m[i], 0.01)
		if not ride.samples.has_route[i]:
			break
	assert_true(ride.is_free_ride(), "восстановленный заезд — свободная езда")


func test_req_frd_07_c4_ascent_of_two_laps_is_twice_route_ascent_within_5pct() -> void:
	for route_id in ["hills", "seaside"]:
		var rec := _record(route_id, 2.0)
		var ride := _repo.get_ride(rec["id"])
		var route_ascent: float = RouteCatalog.get_route(route_id).profile.ascent_m()
		var expected: float = 2.0 * route_ascent
		assert_not_null(ride)
		if ride == null:
			continue
		var ascent: float = ride.total_ascent_m()
		assert_almost_eq(ascent, expected, expected * 0.05,
			"%s: набор 2 кругов %.1f м, 2 × набор трассы %.1f м" % [route_id, ascent, expected])
		# Набор — сумма положительных приращений высоты соседних сэмплов (считаем сами).
		var mine: float = 0.0
		for i in range(1, ride.samples.size()):
			mine += maxf(ride.samples.altitude_m[i] - ride.samples.altitude_m[i - 1], 0.0)
		assert_almost_eq(ascent, mine, 0.05, "%s: набор = Σ положительных приращений" % route_id)
		var listed: RideSummary = null
		for s in _repo.list(_profile.id):
			if s.ride_id == rec["id"]:
				listed = s
		assert_not_null(listed, "заезд в списке истории")
		if listed != null:
			assert_almost_eq(listed.ascent_m, ascent, 0.05, "%s: набор в сводке списка" % route_id)
			assert_almost_eq(listed.distance_m, ride.total_distance_m(), 0.05, "%s: дистанция в сводке" % route_id)


func test_req_frd_07_c4_ascent_mountains_two_laps_direct_stream() -> void:
	# Длинная трасса без записи на диск: поток из профиля гор с разной скоростью.
	var p := RouteCatalog.get_route("mountains").profile
	var s := SampleStream.new()
	var d: float = 0.0
	var t: int = 0
	while d < 2.0 * p.length_m():
		d += _kmh(p.grade_at(d)) / 3.6
		s.append(t, TrainerSample.full(float(t), 220, 88, 0.0), -1, 0, -1, false, 20.0, {},
			{"distance_m": d, "altitude_m": p.height_at(d), "grade_pct": p.grade_at(d)})
		t += 1
	assert_almost_eq(s.total_ascent_m(), 2.0 * p.ascent_m(), 2.0 * p.ascent_m() * 0.05,
		"горы: набор %.1f против %.1f" % [s.total_ascent_m(), 2.0 * p.ascent_m()])
	assert_almost_eq(s.total_distance_m(), d, 1e-3, "дистанция — накопленная от сессии")


# ---------------------------------------------------------------------------
# Совместимость: samples.bin v1 (до FRD-07)
# ---------------------------------------------------------------------------

## Поток в формате v1 (запись 36 байт, без высоты/уклона) — по описанию формата до T-064.
static func _v1_bytes(s: SampleStream, source_code: int) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u32(0x5253564F)
	buf.put_u16(1)
	buf.put_u16(36)
	buf.put_u8(source_code)
	for i in 7:
		buf.put_u8(0)
	for i in s.size():
		buf.put_32(s.time_sec[i])
		buf.put_32(s.power_w[i])
		buf.put_32(s.target_w[i])
		buf.put_32(s.step_index[i])
		buf.put_float(s.speed_kmh[i])
		buf.put_float(s.distance_m[i])
		buf.put_16(s.cadence_rpm[i])
		buf.put_16(s.heart_rate_bpm[i])
		buf.put_16(s.power_age_sec[i])
		buf.put_16(s.cadence_age_sec[i])
		buf.put_16(s.heart_rate_age_sec[i])
		var flags: int = 0
		flags |= 1 if s.has_power[i] else 0
		flags |= 2 if s.has_cadence[i] else 0
		flags |= 4 if s.has_speed[i] else 0
		flags |= 8 if s.has_heart_rate[i] else 0
		flags |= 16 if s.erg_enabled[i] else 0
		buf.put_u8(flags)
		buf.put_u8(0)
	return buf.data_array


func _old_workout_ride(n: int) -> Ride:
	var r := Ride.new()
	r.id = Ride.generate_id(STARTED - 86400)
	r.profile_id = _profile.id
	r.started_at_unix = STARTED - 86400
	r.name = "Старый заезд"
	r.workout = Workout.make("Старый заезд", [WorkoutStep.watts(n, 180.0)] as Array[WorkoutStep]).to_dict()
	r.metadata = {"ftp_w": 200, "workout_name": "Старый заезд", "speed_source": SampleStream.SPEED_SOURCE_TRAINER}
	r.samples.speed_source = SampleStream.SPEED_SOURCE_TRAINER
	for i in n:
		var hr: int = -1 if i % 7 == 3 else 130 + i % 10
		r.samples.append(i, TrainerSample.full(float(i), 170 + i % 20, 80 + i % 9, 28.0 + float(i % 5)), hr, 180, 0, true)
	return r


func test_req_frd_07_c4_v1_samples_written_by_old_format_read_without_errors() -> void:
	var r := _old_workout_ride(25)
	r.compute_summary()
	_repo.save(r)
	var samples_path := ProjectSettings.globalize_path(_dir + "rides/").path_join(_profile.id).path_join(r.id).path_join("samples.bin")
	assert_true(FileAccess.file_exists(samples_path), "samples.bin на месте: %s" % samples_path)
	var f := FileAccess.open(samples_path, FileAccess.WRITE)
	f.store_buffer(_v1_bytes(r.samples, 1))
	f.close()
	var fresh := FileRideRepository.new(_dir + "rides/")
	var back := fresh.get_ride(r.id)
	assert_not_null(back, "заезд v1 читается")
	if back == null:
		return
	assert_eq(back.samples.size(), 25, "все сэмплы v1")
	for i in 25:
		assert_eq(back.samples.power_w[i], r.samples.power_w[i], "#%d мощность" % i)
		assert_eq(back.samples.has_heart_rate[i], r.samples.has_heart_rate[i], "#%d флаг пульса" % i)
		assert_almost_eq(back.samples.distance_m[i], r.samples.distance_m[i], 1e-3, "#%d дистанция" % i)
		assert_false(back.samples.has_route[i], "#%d без позиции на трассе" % i)
	assert_eq(back.samples.speed_source, SampleStream.SPEED_SOURCE_TRAINER)
	assert_eq(back.ride_type(), "workout")
	assert_almost_eq(back.total_ascent_m(), 0.0, 1e-9, "набор старого заезда — 0")
	var summary := RideSummary.compute(back.samples, 200, back.power_zones(), back.hr_zones())
	assert_eq(summary.avg_target_w, 180, "у старой тренировки цель есть")


func test_req_frd_07_c4_append_to_v1_file_keeps_old_and_new_samples() -> void:
	var r := _old_workout_ride(12)
	r.metadata["in_progress"] = true
	_repo.save(r)
	var samples_path := ProjectSettings.globalize_path(_dir + "rides/").path_join(_profile.id).path_join(r.id).path_join("samples.bin")
	var f := FileAccess.open(samples_path, FileAccess.WRITE)
	f.store_buffer(_v1_bytes(r.samples, 1))
	f.close()
	for i in range(12, 20):
		r.samples.append(i, TrainerSample.full(float(i), 210, 90, 30.0), 140, 180, 0, true)
	var fresh := FileRideRepository.new(_dir + "rides/")
	assert_true(fresh.append_samples(r.id, r.samples, 12), "дозапись в файл v1")
	var back := fresh.get_ride(r.id)
	assert_eq(back.samples.size(), 20, "старые 12 + новые 8")
	assert_eq(back.samples.power_w[5], r.samples.power_w[5])
	assert_eq(back.samples.power_w[15], 210)


func test_req_frd_07_c4_developer_v1_fixture_reads() -> void:
	var dst := ProjectSettings.globalize_path(_dir + "legacy/")
	_copy_tree(ProjectSettings.globalize_path("res://tests/fixtures/rides_v1/"), dst)
	var repo := FileRideRepository.new(_dir + "legacy/")
	var ride := repo.get_ride("1700000000-0a1b2c3d")
	assert_not_null(ride, "фикстура v1 читается")
	if ride == null:
		return
	assert_gt(ride.samples.size(), 0)
	assert_eq(ride.ride_type(), "workout")
	assert_false(ride.samples.has_route_data())
	assert_eq(repo.list("legacy-profile").size(), 1, "в списке истории")


# ---------------------------------------------------------------------------
# FRD-07 крит. 6 — сводка, серии, список
# ---------------------------------------------------------------------------

func test_req_frd_07_c6_summary_and_series_without_target_no_errors() -> void:
	var rec := _record("flat", 0.0, 120)
	var ride := _repo.get_ride(rec["id"])
	assert_not_null(ride)
	if ride == null:
		return
	var summary := ride.compute_summary()
	assert_eq(summary.avg_target_w, RideSummary.NO_DATA, "средняя цель — «нет значения»")
	assert_false(summary.has_target(), "цели нет")
	assert_true(summary.is_free_ride())
	assert_eq(summary.route_id, "flat")
	assert_eq(summary.avg_power_w, 220, "LOC-04: средняя мощность считается")
	assert_eq(summary.normalized_power_w, 220, "NP постоянной мощности")
	assert_almost_eq(summary.work_kj, 220.0 * 120.0 / 1000.0, 0.01, "работа")
	assert_eq(summary.total_power_zone_sec(), 120, "время в зонах = сэмплам с мощностью")
	assert_eq(HudModel.NO_DATA_TEXT, "—")
	var series := RideSeries.from_samples(ride.samples)
	assert_false(series.has_target, "серии цели нет")
	assert_eq(series.values(RideSeries.TARGET).size(), 0, "серия цели пустая")
	assert_eq(series.count(RideSeries.POWER), 120, "LOC-03.1: серия мощности = сэмплам с данными")
	var alt := RideSeries.altitude_by_distance(ride.samples)
	assert_eq(alt.size(), 120, "профиль высоты по дистанции")
	if alt.size() > 0:
		assert_almost_eq(alt[alt.size() - 1].x, ride.total_distance_m(), 0.01)


func test_req_frd_07_c6_free_ride_listed_with_workouts_newest_first() -> void:
	var old := _old_workout_ride(10)
	old.compute_summary()
	_repo.save(old)
	var rec := _record("seaside", 0.0, 30)
	var list := _repo.list(_profile.id)
	assert_eq(list.size(), 2, "оба заезда в истории")
	if list.size() == 2:
		assert_eq(list[0].ride_id, rec["id"], "новее — сверху")
		assert_true(list[0].is_free_ride())
		assert_eq(list[0].avg_target_w, RideSummary.NO_DATA)
		assert_false(list[1].is_free_ride())
		assert_eq(list[1].avg_target_w, 180)
	var series_old := RideSeries.from_samples(_repo.get_ride(old.id).samples)
	assert_true(series_old.has_target, "у тренировки серия цели осталась (LOC-03.3)")


# ---------------------------------------------------------------------------
# FRD-07 крит. 7 — Strava
# ---------------------------------------------------------------------------

func _strava() -> Array:
	var mock := MockHttpTransport.new()
	var store := MemorySecureStore.new()
	var svc := StravaService.new(_profile, mock, store, _repo, StravaConfig.from_values("4242", "acc-client-secret-value"),
		func() -> int: return NOW, _dir)
	svc.attach()
	store.set_secret(svc.oauth.secret_key(SecureStore.ITEM_ACCESS_TOKEN), "acc-access-token-aaaa")
	store.set_secret(svc.oauth.secret_key(SecureStore.ITEM_REFRESH_TOKEN), "acc-refresh-token-rrrr")
	store.set_secret(svc.oauth.secret_key(SecureStore.ITEM_EXPIRES_AT), str(NOW + 99999))
	return [svc, mock]


func test_req_frd_07_c7_default_name_ru_and_en_with_track_name_from_catalog() -> void:
	var pair := _strava()
	var svc: StravaService = pair[0]
	var expected: Dictionary = {
		"ru": {"mountains": "Свободная езда — Перевал", "flat": "Свободная езда — Пшеничные поля",
			"hills": "Свободная езда — Зелёные холмы", "seaside": "Свободная езда — Приморье"},
		"en": {"mountains": "Free ride — Mountain Pass", "flat": "Free ride — Wheat Fields",
			"hills": "Free ride — Green Hills", "seaside": "Free ride — Seaside"},
	}
	var rides: Dictionary = {}
	for route_id in ["mountains", "flat", "hills", "seaside"]:
		var r := Ride.new()
		r.id = Ride.generate_id(STARTED)
		r.profile_id = _profile.id
		r.metadata = Ride.free_ride_metadata(route_id, 50.0)
		rides[route_id] = r
	for locale in ["ru", "en"]:
		TranslationServer.set_locale(locale)
		for route_id in rides:
			assert_eq(svc.default_name(rides[route_id]), expected[locale][route_id], "%s/%s" % [locale, route_id])
	svc.dispose()


func test_req_frd_07_c7_upload_request_is_virtual_ride_with_free_ride_name_and_not_duplicated() -> void:
	TranslationServer.set_locale("ru")
	var pair := _strava()
	var svc: StravaService = pair[0]
	var mock: MockHttpTransport = pair[1]
	mock.enqueue_json("POST", "uploads", 201, {"id": 5551, "status": "Your activity is ready.", "error": null, "activity_id": 9991})
	mock.enqueue_json("GET", "uploads/5551", 200, {"id": 5551, "status": "Your activity is ready.", "error": null, "activity_id": 9991}, {}, -1)
	var rec := _record("mountains", 0.0, 60)
	assert_true(svc.queue.has(rec["id"]), "STR-02: свободная езда автоматически в очереди")
	if svc.queue.has(rec["id"]):
		assert_eq(str(svc.queue.get_item(rec["id"])["name"]), "Свободная езда — Перевал")
	await svc.step_queue()
	await svc.step_queue()
	var posts: Array[Dictionary] = []
	for q in mock.requests:
		if q["method"] == "POST" and str(q["url"]).contains("uploads"):
			posts.append(q)
	assert_eq(posts.size(), 1, "один POST /uploads")
	if posts.size() == 1:
		var body: String = (posts[0]["body"] as PackedByteArray).get_string_from_utf8()
		assert_true(body.contains("Свободная езда — Перевал"), "название в запросе")
		assert_true(body.contains("VirtualRide"), "тип VirtualRide")
		assert_true(body.contains("fit"), "data_type fit")
	var after := _repo.get_ride(rec["id"])
	assert_eq(str(after.upload.get("strava_status")), Ride.UPLOAD_DONE, "статус выгрузки — done: %s" % str(after.upload))
	# Повторная выгрузка той же поездки: сохранение заново и ручная выгрузка не создают дубль.
	_repo.save(after)
	assert_false(svc.upload_now(rec["id"]), "выгруженный заезд повторно не выгружается")
	await svc.step_queue()
	var posts_after: int = 0
	for q in mock.requests:
		if q["method"] == "POST" and str(q["url"]).contains("uploads"):
			posts_after += 1
	assert_eq(posts_after, 1, "второго POST /uploads нет")
	svc.dispose()
