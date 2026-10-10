extends GutTest
## FIT свободной езды (T-069): REQ-FRD-07 крит. 5 — `distance`, `altitude`/`enhanced_altitude`,
## `grade` в каждом `record`, `total_distance` и `total_ascent` в `session`, `lap` на круг
## трассы; регрессия REQ-LOC-05 крит. 1–4 — заезд по плану кодируется как раньше.
## Проверки — через `FitDecoder` (round-trip без внешнего SDK).

const D = preload("res://src/integrations/fit/fit_definitions.gd")
const STARTED: int = 1_790_000_000
## Трасса с подъёмами и спусками (уклон обоих знаков).
const ROUTE: String = RouteCatalog.HILLS
## Сэмплов на круг трассы.
const PER_LAP: int = 200


var _dir: String = ""


func after_each() -> void:
	if not _dir.is_empty():
		_remove_tree(ProjectSettings.globalize_path(_dir))
		_dir = ""


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


static func _lap_m(route_id: String = ROUTE) -> float:
	return RouteCatalog.get_route(route_id).profile.length_m()


## Свободная езда по трассе `route_id`: `laps` кругов, `PER_LAP` сэмплов на круг, позиция
## на трассе по профилю каталога. `off_route` — номера сэмплов без позиции на трассе.
func _free_ride(laps: float, route_id: String = ROUTE, off_route: Array[int] = []) -> Ride:
	var lap_m: float = _lap_m(ROUTE)
	var profile: RouteProfile = RouteCatalog.get_route(ROUTE).profile
	var step_m: float = lap_m / float(PER_LAP)
	var n: int = roundi(laps * PER_LAP)
	var r := Ride.new()
	r.id = Ride.generate_id(STARTED)
	r.profile_id = "p"
	r.started_at_unix = STARTED
	r.metadata = Ride.free_ride_metadata(route_id, 50.0)
	r.metadata["ftp_w"] = 250
	r.metadata["max_hr"] = 190
	r.metadata["elapsed_sec"] = n
	r.metadata["paused_total_sec"] = 0.0
	r.metadata["in_progress"] = false
	r.metadata["recovered"] = false
	r.samples.speed_source = SampleStream.SPEED_SOURCE_MODEL
	var speed_kmh: float = step_m * 3.6
	for i in n:
		var d: float = float(i + 1) * step_m
		var route: Dictionary = {}
		if not off_route.has(i):
			var s: float = fposmod(d, lap_m)
			route = {"distance_m": d, "altitude_m": profile.height_at(s), "grade_pct": profile.grade_at(s)}
		r.samples.append(i, TrainerSample.full(float(i), 200 + (i % 9) * 10, 88, 0.0), 130 + i % 25, 0, -1, false,
				speed_kmh, {}, route)
	r.events = [{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0}]
	r.update_route_totals()
	r.compute_summary()
	return r


## Заезд по плану: два шага по 3 с, как в тестах `FitEncoder`.
func _workout_ride() -> Ride:
	var r := Ride.new()
	r.id = "fit-workout"
	r.profile_id = "p"
	r.started_at_unix = STARTED
	r.name = "FIT plan"
	r.workout = WorkoutSerializer.to_dict(Workout.make("FIT plan", [WorkoutStep.watts(3, 200.0), WorkoutStep.watts(3, 250.0)] as Array[WorkoutStep]))
	r.metadata = {"ftp_w": 200, "weight_kg": 75.0, "max_hr": 185, "speed_source": Ride.SPEED_SOURCE_TRAINER_LEGACY,
		"stopped_early": false, "elapsed_sec": 6, "paused_total_sec": 0.0, "in_progress": false, "recovered": false}
	r.samples.speed_source = Ride.SPEED_SOURCE_TRAINER_LEGACY
	for i in 6:
		r.samples.append(i, TrainerSample.full(float(i + 1), 200 + i * 10, 85, 36.0), 140, 200, i / 3, true)
	r.events = [{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0}]
	r.compute_summary()
	return r


func _decode(ride: Ride) -> FitDecoder.Result:
	var res := FitDecoder.decode(FitEncoder.encode(ride))
	assert_true(res.ok, "файл декодируется: %s" % res.error)
	return res


func _f(msg: Dictionary, field: int) -> Variant:
	return (msg["fields"] as Dictionary).get(field, null)


## Номера полей в определении сообщения данного глобального типа.
func _field_nums(res: FitDecoder.Result, global_num: int) -> Array:
	return res.definition_of(global_num).keys()


# ---------------------------------------------------------------------------
# REQ-FRD-07 крит. 5: record — дистанция, высота, уклон
# ---------------------------------------------------------------------------

func test_req_frd_07_c5_records_carry_distance_altitude_grade_matching_samples() -> void:
	var ride := _free_ride(2.5)
	var s := ride.samples
	var res := _decode(ride)
	var records := res.messages_of(D.MSG_RECORD)
	assert_eq(records.size(), s.size(), "REQ-LOC-05 крит. 4: record на каждый сэмпл")
	var negative_grade: bool = false
	var positive_grade: bool = false
	for i in records.size():
		var m := records[i]
		assert_almost_eq(FitDecoder.distance_m(m), float(s.distance_m[i]), 0.01, "дистанция record %d" % i)
		assert_almost_eq(FitDecoder.altitude_m(m), float(s.altitude_m[i]), 0.2, "enhanced_altitude record %d" % i)
		assert_not_null(_f(m, D.RECORD_ALTITUDE), "altitude (поле 2) record %d" % i)
		assert_almost_eq(D.altitude_from_raw(int(_f(m, D.RECORD_ALTITUDE))), float(s.altitude_m[i]), 0.2,
				"altitude (поле 2) record %d" % i)
		assert_almost_eq(FitDecoder.grade_pct(m), float(s.grade_pct[i]), 0.01, "уклон record %d" % i)
		negative_grade = negative_grade or s.grade_pct[i] < -0.5
		positive_grade = positive_grade or s.grade_pct[i] > 0.5
	assert_true(negative_grade and positive_grade, "трасса проверяет уклон обоих знаков (sint16)")


func test_req_frd_07_c5_record_definition_has_fit_profile_types() -> void:
	var types := _decode(_free_ride(0.5)).definition_of(D.MSG_RECORD)
	assert_eq(types.get(D.RECORD_DISTANCE), [4, D.T_UINT32], "distance: uint32, м × 100")
	assert_eq(types.get(D.RECORD_ALTITUDE), [2, D.T_UINT16], "altitude: uint16, (м + 500) × 5")
	assert_eq(types.get(D.RECORD_ENHANCED_ALTITUDE), [4, D.T_UINT32], "enhanced_altitude: uint32")
	assert_eq(types.get(D.RECORD_GRADE), [2, D.T_SINT16], "grade: sint16, % × 100")


func test_req_frd_07_c5_sample_without_route_position_has_invalid_altitude_and_grade() -> void:
	var off: Array[int] = [3]
	var ride := _free_ride(0.1, ROUTE, off)
	var records := _decode(ride).messages_of(D.MSG_RECORD)
	assert_null(_f(records[3], D.RECORD_ALTITUDE), "нет позиции → altitude invalid (REQ-LOC-05 крит. 3)")
	assert_null(_f(records[3], D.RECORD_ENHANCED_ALTITUDE), "нет позиции → enhanced_altitude invalid")
	assert_null(_f(records[3], D.RECORD_GRADE), "нет позиции → grade invalid")
	assert_almost_eq(FitDecoder.distance_m(records[3]), float(ride.samples.distance_m[3]), 0.01, "дистанция пишется всегда")
	assert_not_null(_f(records[4], D.RECORD_GRADE), "соседний сэмпл с позицией — с уклоном")


# ---------------------------------------------------------------------------
# REQ-FRD-07 крит. 5: session — total_distance и total_ascent
# ---------------------------------------------------------------------------

func test_req_frd_07_c5_session_total_distance_and_ascent() -> void:
	var ride := _free_ride(2.5)
	var res := _decode(ride)
	var session: Dictionary = res.messages_of(D.MSG_SESSION)[0]
	assert_eq(res.definition_of(D.MSG_SESSION).get(D.SESSION_TOTAL_ASCENT), [2, D.T_UINT16], "total_ascent: uint16, м")
	assert_almost_eq(FitDecoder.distance_m(session, D.SESSION_TOTAL_DISTANCE), ride.samples.total_distance_m(), 0.01,
			"total_distance = дистанция последнего сэмпла")
	assert_gt(ride.total_ascent_m(), 10.0, "на трассе есть набор")
	assert_almost_eq(FitDecoder.total_ascent_m(session), ride.total_ascent_m(), 1.0, "total_ascent = набор п.4 ±1 м")
	assert_almost_eq(FitDecoder.total_ascent_m(session), ride.samples.total_ascent_m(), 1.0, "total_ascent по сэмплам")


# ---------------------------------------------------------------------------
# REQ-FRD-07 крит. 5: lap — по кругу трассы
# ---------------------------------------------------------------------------

func test_req_frd_07_c5_two_and_a_half_laps_give_three_laps() -> void:
	var ride := _free_ride(2.5)
	var res := _decode(ride)
	var laps := res.messages_of(D.MSG_LAP)
	assert_eq(laps.size(), 3, "2 полных круга + неполный последний")
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_NUM_LAPS), 3, "session.num_laps")
	var lap_m: float = _lap_m()
	var sum_m: float = 0.0
	var sum_timer_ms: int = 0
	for k in laps.size():
		assert_eq(_f(laps[k], D.F_MESSAGE_INDEX), k, "message_index lap %d" % k)
		sum_m += FitDecoder.distance_m(laps[k], D.LAP_TOTAL_DISTANCE)
		sum_timer_ms += int(_f(laps[k], D.LAP_TOTAL_TIMER_TIME))
	assert_almost_eq(FitDecoder.distance_m(laps[0], D.LAP_TOTAL_DISTANCE), lap_m, 0.05, "первый круг — длина трассы")
	assert_almost_eq(FitDecoder.distance_m(laps[1], D.LAP_TOTAL_DISTANCE), lap_m, 0.05, "второй круг — длина трассы")
	assert_almost_eq(FitDecoder.distance_m(laps[2], D.LAP_TOTAL_DISTANCE), lap_m * 0.5, 0.05, "последний — полкруга")
	assert_almost_eq(sum_m, ride.samples.total_distance_m(), 0.05, "сумма кругов = дистанция заезда")
	assert_eq(sum_timer_ms, ride.samples.size() * 1000, "круги покрывают все сэмплы")
	assert_eq(_f(laps[0], D.LAP_LAP_TRIGGER), D.LAP_TRIGGER_POSITION_LAP)
	assert_eq(_f(laps[1], D.LAP_LAP_TRIGGER), D.LAP_TRIGGER_POSITION_LAP)
	assert_eq(_f(laps[2], D.LAP_LAP_TRIGGER), D.LAP_TRIGGER_SESSION_END)


func test_req_frd_07_c5_exact_laps_have_no_empty_tail_lap() -> void:
	var res := _decode(_free_ride(2.0))
	assert_eq(res.count(D.MSG_LAP), 2, "ровно 2 круга → 2 lap, без пустого третьего")


func test_req_frd_07_c5_less_than_one_lap_gives_single_lap() -> void:
	var res := _decode(_free_ride(0.3))
	assert_eq(res.count(D.MSG_LAP), 1)


func test_req_frd_07_c5_unknown_route_gives_single_lap() -> void:
	var res := _decode(_free_ride(2.5, "no-such-route"))
	assert_eq(res.count(D.MSG_LAP), 1, "без длины трассы — один lap на весь заезд")
	assert_eq(res.count(D.MSG_RECORD), roundi(2.5 * PER_LAP))


func test_req_frd_07_c5_saved_and_loaded_free_ride_encodes_the_same() -> void:
	var ride := _free_ride(1.5)
	_dir = "user://test_fit_free_ride_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	var repo := FileRideRepository.new(_dir)
	assert_ne(repo.save(ride), "")
	var back := FileRideRepository.new(_dir).get_ride(ride.id)
	assert_not_null(back)
	assert_eq(FitEncoder.encode(back), FitEncoder.encode(ride), "FIT из хранилища = FIT исходного заезда")
	assert_eq(_decode(back).count(D.MSG_LAP), 2)


# ---------------------------------------------------------------------------
# Регрессия REQ-LOC-05 крит. 1–4: заезд по плану
# ---------------------------------------------------------------------------

func test_req_loc_05_workout_fit_has_no_route_fields_and_laps_by_steps() -> void:
	var res := _decode(_workout_ride())
	var record_fields := _field_nums(res, D.MSG_RECORD)
	assert_false(record_fields.has(D.RECORD_ALTITUDE), "без altitude")
	assert_false(record_fields.has(D.RECORD_ENHANCED_ALTITUDE), "без enhanced_altitude")
	assert_false(record_fields.has(D.RECORD_GRADE), "без grade")
	assert_true(record_fields.has(D.RECORD_DISTANCE), "distance — как раньше")
	assert_false(_field_nums(res, D.MSG_SESSION).has(D.SESSION_TOTAL_ASCENT), "session без total_ascent")
	var laps := res.messages_of(D.MSG_LAP)
	assert_eq(laps.size(), 2, "lap на каждый шаг плана")
	for lap in laps:
		assert_eq(_f(lap, D.LAP_LAP_TRIGGER), D.LAP_TRIGGER_MANUAL)
