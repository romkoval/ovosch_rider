extends GutTest
## Сводка заезда `RideSummary` (REQ-LOC-04 крит. 1–6; REQ-NFR-09 крит. 1 — расчёт сводки).

const FTP: int = 200


## Синтетический поток: `power` на каждую секунду; -1 — «нет данных» мощности.
func _stream(powers: Array, hr: int = -1, cadence: int = -1) -> SampleStream:
	var s := SampleStream.new()
	for i in powers.size():
		var p: int = int(powers[i])
		var sample: TrainerSample = null
		if p >= 0:
			sample = TrainerSample.new()
			sample.power_w = p
			sample.has_power = true
			if cadence >= 0:
				sample.cadence_rpm = cadence
				sample.has_cadence = true
		s.append(i, sample, hr, 0, 0, true)
	return s


func _constant(power: int, seconds: int, hr: int = -1, cadence: int = -1) -> SampleStream:
	var arr: Array = []
	arr.resize(seconds)
	arr.fill(power)
	return _stream(arr, hr, cadence)


func _compute(s: SampleStream, hr_zones: HrZones = null) -> RideSummary:
	return RideSummary.compute(s, FTP, PowerZones.coggan(FTP), hr_zones)


# --- REQ-LOC-04 крит. 1: средняя мощность ---

func test_avg_power_counts_zeros_and_skips_no_data() -> void:
	var s := _stream([200, 0, 100, -1, -1])
	var r := _compute(s)
	assert_eq(r.avg_power_w, 100, "(200+0+100)/3; «нет данных» не входит")
	assert_eq(r.power_sample_count, 3)
	assert_eq(r.duration_sec, 5, "длительность — все слоты")


func test_avg_power_is_rounded_to_integer() -> void:
	var r := _compute(_stream([100, 101, 101]))
	assert_eq(r.avg_power_w, 101, "100.67 → 101")


# --- REQ-LOC-04 крит. 2: нормализованная мощность ---

func test_np_equals_avg_for_constant_200w_10min() -> void:
	var r := _compute(_constant(200, 600))
	assert_eq(r.avg_power_w, 200)
	assert_eq(r.normalized_power_w, 200)


func test_np_exceeds_avg_for_alternating_300_100_by_30s() -> void:
	var arr: Array = []
	for block in 10:
		for i in 30:
			arr.append(300 if block % 2 == 0 else 100)
	var r := _compute(_stream(arr))
	assert_eq(r.avg_power_w, 200)
	assert_gt(r.normalized_power_w, r.avg_power_w, "NP > средней при чередовании")
	assert_lt(r.normalized_power_w, 300, "NP ниже пиковой")


func test_np_is_never_below_avg_on_noisy_stream() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var arr: Array = []
	for i in 900:
		arr.append(rng.randi_range(50, 400))
	var r := _compute(_stream(arr))
	assert_gte(r.normalized_power_w, r.avg_power_w)


func test_np_for_stream_shorter_than_30s_equals_avg_when_constant() -> void:
	var r := _compute(_constant(150, 10))
	assert_eq(r.normalized_power_w, 150)
	assert_eq(RideSummary.normalized_power(_constant(150, 10)), 150)


func test_np_with_no_power_is_no_data() -> void:
	var r := _compute(_stream([-1, -1, -1]))
	assert_eq(r.avg_power_w, RideSummary.NO_DATA)
	assert_eq(r.normalized_power_w, RideSummary.NO_DATA)
	assert_eq(r.max_power_w, RideSummary.NO_DATA)
	assert_false(r.has_power())


# --- REQ-LOC-04 крит. 3: работа ---

func test_work_200w_600s_is_120kj() -> void:
	assert_almost_eq(_compute(_constant(200, 600)).work_kj, 120.0, 1e-6)


func test_work_200w_3600s_is_720kj() -> void:
	assert_almost_eq(_compute(_constant(200, 3600)).work_kj, 720.0, 1e-6)


# --- REQ-LOC-04 крит. 4: средний пульс и каденс ---

func test_avg_hr_and_cadence_over_samples_with_data() -> void:
	var s := SampleStream.new()
	s.append(0, TrainerSample.full(1.0, 200, 90, 30.0), 150, 0, 0, true)
	s.append(1, TrainerSample.full(2.0, 200, 0, 30.0), 160, 0, 0, true)   # каденс 0 учитывается
	s.append(2, TrainerSample.full(3.0, 200, 90, 30.0), -1, 0, 0, true)   # нет пульса
	var no_cadence := TrainerSample.new()
	no_cadence.power_w = 200
	no_cadence.has_power = true
	s.append(3, no_cadence, 170, 0, 0, true)                                # нет каденса
	var r := _compute(s)
	assert_eq(r.avg_hr, 160, "(150+160+170)/3")
	assert_eq(r.hr_sample_count, 3)
	assert_eq(r.avg_cadence, 60, "(90+0+90)/3")
	assert_eq(r.cadence_sample_count, 3)
	assert_eq(r.max_hr, 170)
	assert_eq(r.max_cadence, 90)


# --- REQ-LOC-04 крит. 5: время в зонах ---

func test_time_in_power_zones_sums_to_power_sample_count() -> void:
	# FTP 200: 100 → Z1 (≤110), 140 → Z2 (≤150), 170 → Z3 (≤180), 200 → Z4 (≤210), 230 → Z5, 280 → Z6, 400 → Z7
	var s := _stream([100, 100, 140, 170, 200, 230, 280, 400, -1])
	var r := _compute(s)
	assert_eq(r.time_in_power_zones.size(), 7)
	assert_eq(Array(r.time_in_power_zones), [2, 1, 1, 1, 1, 1, 1])
	assert_eq(r.total_power_zone_sec(), r.power_sample_count)
	assert_eq(r.total_power_zone_sec(), 8)


func test_time_in_hr_zones_sums_to_hr_sample_count() -> void:
	# max 180: 100 → Z1, 108 → Z2, 130 → Z3, 150 → Z4, 170 → Z5
	var s := SampleStream.new()
	for hr in [100, 108, 130, 150, 170, 170]:
		s.append(s.size(), TrainerSample.full(1.0, 200, 90, 30.0), hr, 0, 0, true)
	s.append(s.size(), TrainerSample.full(1.0, 200, 90, 30.0), -1, 0, 0, true)
	var r := _compute(s, HrZones.five_zone(180))
	assert_eq(Array(r.time_in_hr_zones), [1, 1, 1, 1, 2])
	assert_eq(r.total_hr_zone_sec(), r.hr_sample_count)
	assert_eq(r.total_power_zone_sec(), 7)


func test_zones_of_profile_at_ride_time_are_used() -> void:
	var custom := PowerZones.custom(FTP, [50.0, 100.0])
	var r := RideSummary.compute(_stream([90, 150, 250]), FTP, custom, null)
	assert_eq(Array(r.time_in_power_zones), [1, 1, 1], "3 зоны по пользовательским границам")


# --- REQ-LOC-04 крит. 6: без пульса ---

func test_ride_without_hr_has_no_data_and_empty_hr_zones() -> void:
	var r := _compute(_constant(200, 60))
	assert_eq(r.avg_hr, RideSummary.NO_DATA)
	assert_eq(r.max_hr, RideSummary.NO_DATA)
	assert_false(r.has_heart_rate())
	assert_eq(r.time_in_hr_zones.size(), 0, "зоны пульса недоступны без max_hr")


func test_ride_with_hr_but_without_hr_zones_keeps_avg() -> void:
	var r := _compute(_constant(200, 60, 140))
	assert_eq(r.avg_hr, 140)
	assert_eq(r.time_in_hr_zones.size(), 0)


func test_empty_stream_is_safe() -> void:
	var r := _compute(SampleStream.new())
	assert_eq(r.duration_sec, 0)
	assert_eq(r.avg_power_w, RideSummary.NO_DATA)
	assert_almost_eq(r.work_kj, 0.0, 1e-9)
	assert_eq(r.total_power_zone_sec(), 0)


# --- Сериализация ---

func test_to_dict_from_dict_round_trip() -> void:
	var r := _compute(_constant(250, 120, 150, 88), HrZones.five_zone(190))
	r.ride_id = "r1"
	r.name = "Sweet spot"
	r.started_at_unix = 1700000000
	r.strava_status = Ride.UPLOAD_DONE
	r.strava_activity_id = "123"
	r.stopped_early = true
	var json := JSON.new()
	assert_eq(json.parse(JSON.stringify(r.to_dict())), OK)
	var back := RideSummary.from_dict(json.data)
	assert_eq(back.ride_id, "r1")
	assert_eq(back.name, "Sweet spot")
	assert_eq(back.started_at_unix, 1700000000)
	assert_eq(back.strava_status, Ride.UPLOAD_DONE)
	assert_eq(back.strava_activity_id, "123")
	assert_true(back.stopped_early)
	assert_eq(back.avg_power_w, 250)
	assert_eq(back.normalized_power_w, 250)
	assert_eq(back.avg_hr, 150)
	assert_eq(back.avg_cadence, 88)
	assert_eq(back.duration_sec, 120)
	assert_almost_eq(back.work_kj, 30.0, 1e-6)
	assert_eq(Array(back.time_in_power_zones), Array(r.time_in_power_zones))
	assert_eq(Array(back.time_in_hr_zones), Array(r.time_in_hr_zones))


func test_from_dict_tolerates_garbage() -> void:
	var back := RideSummary.from_dict({"avg_power_w": "x", "time_in_power_zones": "nope", "duration_sec": null})
	assert_eq(back.avg_power_w, RideSummary.NO_DATA)
	assert_eq(back.time_in_power_zones.size(), 0)
	assert_eq(back.duration_sec, 0)
