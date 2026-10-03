extends GutTest
## Серии для графиков `RideSeries` (REQ-LOC-03 крит. 1–3, решение 17).


## Поток `n` секунд: мощность 100 + (i % 50), слоты кратные 7 — без телеметрии;
## пульс есть только на чётных слотах; цель 200.
func _stream(n: int) -> SampleStream:
	var s := SampleStream.new()
	for i in n:
		var sample: TrainerSample = null
		if i % 7 != 0:
			sample = TrainerSample.full(float(i), 100 + i % 50, 80 + i % 10, 30.0)
		s.append(i, sample, 140 if i % 2 == 0 else -1, 200, 0, true)
	return s


func test_without_decimation_bucket_is_one_second_and_time_is_monotonic() -> void:
	var series := RideSeries.from_samples(_stream(600))
	assert_eq(series.bucket_sec, 1)
	assert_eq(series.size(), 600)
	assert_eq(series.duration_sec, 600)
	for i in range(1, series.size()):
		assert_true(series.time_sec[i] > series.time_sec[i - 1], "время строго возрастает")
	assert_almost_eq(series.time_sec[0], 0.0, 1e-6)


func test_power_points_count_equals_samples_with_power_data() -> void:
	var s := _stream(600)
	var series := RideSeries.from_samples(s)
	assert_eq(series.points(RideSeries.POWER).size(), s.count_with_power(), "REQ-LOC-03 крит. 1")
	assert_eq(series.count(RideSeries.POWER), s.count_with_power())
	assert_lt(series.count(RideSeries.POWER), 600, "слоты без телеметрии пропущены")


func test_no_data_is_nan_not_zero() -> void:
	var series := RideSeries.from_samples(_stream(20))
	var power := series.values(RideSeries.POWER)
	assert_true(is_nan(power[0]), "слот 0 без телеметрии → NAN")
	assert_true(is_nan(power[7]))
	assert_almost_eq(power[1], 101.0, 1e-6)
	var hr := series.values(RideSeries.HEART_RATE)
	assert_true(is_nan(hr[1]), "нечётный слот без пульса")
	assert_almost_eq(hr[2], 140.0, 1e-6)
	for p in series.points(RideSeries.HEART_RATE):
		assert_almost_eq(p.y, 140.0, 1e-6, "в точках только данные")


func test_decimation_7200_to_at_most_3600_points() -> void:
	var series := RideSeries.from_samples(_stream(7200))
	assert_lte(series.size(), 3600, "REQ-LOC-03 крит. 2")
	assert_eq(series.size(), 3600)
	assert_eq(series.bucket_sec, 2)
	assert_eq(series.duration_sec, 7200)
	for i in range(1, series.size()):
		assert_true(series.time_sec[i] > series.time_sec[i - 1])


func test_decimation_preserves_min_and_max() -> void:
	var s := _stream(7200)
	var series := RideSeries.from_samples(s)
	var true_max: int = 0
	var true_min: int = 1000000
	for i in s.size():
		if s.has_power[i]:
			true_max = maxi(true_max, s.power_w[i])
			true_min = mini(true_min, s.power_w[i])
	assert_almost_eq(series.peak(RideSeries.POWER), float(true_max), 1e-6, "максимум сохранён")
	assert_almost_eq(series.low(RideSeries.POWER), float(true_min), 1e-6, "минимум сохранён")
	var mx := series.max_values(RideSeries.POWER)
	var mn := series.min_values(RideSeries.POWER)
	var avg := series.values(RideSeries.POWER)
	for i in series.size():
		if not is_nan(avg[i]):
			assert_true(mn[i] <= avg[i] and avg[i] <= mx[i], "min ≤ avg ≤ max в корзине %d" % i)


func test_decimation_does_not_average_gaps_with_zeros() -> void:
	# Корзина из 2 слотов: слот 0 без данных, слот 1 = 101 Вт → среднее 101, не 50.5.
	var series := RideSeries.from_samples(_stream(7200))
	assert_almost_eq(series.values(RideSeries.POWER)[0], 101.0, 1e-6)
	# Пульс только на чётных: корзина (0,1) → 140, не 70.
	assert_almost_eq(series.values(RideSeries.HEART_RATE)[0], 140.0, 1e-6)


func test_bucket_without_any_data_is_gap() -> void:
	var s := SampleStream.new()
	for i in 10:
		s.append(i, TrainerSample.full(float(i), 200, 90, 30.0) if i >= 4 else null, -1, 0, 0, true)
	var series := RideSeries.from_samples(s, 5)  # корзины по 2 с
	var power := series.values(RideSeries.POWER)
	assert_eq(power.size(), 5)
	assert_true(is_nan(power[0]))
	assert_true(is_nan(power[1]))
	assert_almost_eq(power[2], 200.0, 1e-6)
	assert_false(series.has_data(RideSeries.HEART_RATE))
	assert_true(is_nan(series.peak(RideSeries.HEART_RATE)))


func test_target_series_is_always_present() -> void:
	var series := RideSeries.from_samples(_stream(100))
	assert_eq(series.count(RideSeries.TARGET), 100, "REQ-LOC-03 крит. 3: серия цели плана")
	for v in series.values(RideSeries.TARGET):
		assert_almost_eq(v, 200.0, 1e-6)


func test_empty_stream_gives_empty_series() -> void:
	var series := RideSeries.from_samples(SampleStream.new())
	assert_eq(series.size(), 0)
	assert_eq(series.points(RideSeries.POWER).size(), 0)
	assert_eq(series.duration_sec, 0)
	assert_true(is_nan(series.peak(RideSeries.POWER)))


func test_custom_max_points_limit() -> void:
	var series := RideSeries.from_samples(_stream(1000), 100)
	assert_eq(series.bucket_sec, 10)
	assert_eq(series.size(), 100)
	assert_almost_eq(series.time_sec[1], 10.0, 1e-6)
