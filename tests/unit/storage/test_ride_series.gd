extends GutTest
## Серии для графиков `RideSeries` (REQ-LOC-03 крит. 1–3, решения 17 и В-18).


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
	assert_eq(series.size(), 3600, "по два слота на корзину: 1800 корзин × 2")
	assert_eq(series.bucket_sec, 4)
	assert_eq(series.duration_sec, 7200)
	for i in range(1, series.size()):
		assert_true(series.time_sec[i] > series.time_sec[i - 1], "время слотов строго возрастает")
	assert_almost_eq(series.time_sec[0], 0.0, 1e-6)
	assert_almost_eq(series.time_sec[1], 2.0, 1e-6, "второй слот корзины — её середина")
	assert_almost_eq(series.time_sec[2], 4.0, 1e-6)


func test_decimation_keeps_min_and_max_among_points() -> void:
	# Решение В-18: экстремумы — среди самих точек серии, а не в отдельных массивах.
	var s := _stream(7200)
	var series := RideSeries.from_samples(s)
	var true_max: int = 0
	var true_min: int = 1000000
	for i in s.size():
		if s.has_power[i]:
			true_max = maxi(true_max, s.power_w[i])
			true_min = mini(true_min, s.power_w[i])
	var pts_lo: float = INF
	var pts_hi: float = -INF
	for p in series.points(RideSeries.POWER):
		pts_lo = minf(pts_lo, p.y)
		pts_hi = maxf(pts_hi, p.y)
	assert_almost_eq(pts_hi, float(true_max), 1e-6, "максимум среди точек")
	assert_almost_eq(pts_lo, float(true_min), 1e-6, "минимум среди точек")
	assert_almost_eq(series.peak(RideSeries.POWER), float(true_max), 1e-6)
	assert_almost_eq(series.low(RideSeries.POWER), float(true_min), 1e-6)
	assert_lte(series.points(RideSeries.POWER).size(), 3600)


func test_decimation_bucket_slots_are_min_and_max_in_time_order() -> void:
	# Корзина 4 с: [200, 1000, 200, 200] → слоты (200, 1000); [200, 200, 0, 200] → (0, 200).
	var s := SampleStream.new()
	var power: Array[int] = [200, 1000, 200, 200, 200, 200, 0, 200]
	for i in power.size():
		s.append(i, TrainerSample.full(float(i), power[i], 90, 30.0), -1, 150, 0, true)
	var series := RideSeries.from_samples(s, 4)  # 2 корзины по 4 с, 4 слота
	assert_eq(series.bucket_sec, 4)
	assert_eq(series.size(), 4)
	var v := series.values(RideSeries.POWER)
	assert_almost_eq(v[0], 200.0, 1e-6, "min раньше max → min в первом слоте")
	assert_almost_eq(v[1], 1000.0, 1e-6)
	assert_almost_eq(v[2], 0.0, 1e-6, "min (слот 6) раньше max (слот 7) → min первым")
	assert_almost_eq(v[3], 200.0, 1e-6)
	# Цель постоянна: оба слота заполнены одним значением (точки есть в каждом слоте).
	assert_eq(series.points(RideSeries.TARGET).size(), 4)
	for p in series.points(RideSeries.TARGET):
		assert_almost_eq(p.y, 150.0, 1e-6)


func test_decimation_single_value_bucket_gives_one_point() -> void:
	# Корзина 3 с: слоты 0 и 2 без данных, слот 1 = 101 Вт → одна точка 101 (не среднее с нулями
	# и не два слота); пульс есть на всех трёх → два слота с 140.
	var s := SampleStream.new()
	for i in 6:
		s.append(i, TrainerSample.full(float(i), 101, 90, 30.0) if i == 1 else null, 140, 200, 0, true)
	var series := RideSeries.from_samples(s, 4)  # корзины по 3 с
	assert_eq(series.bucket_sec, 3)
	assert_eq(series.size(), 4)
	var v := series.values(RideSeries.POWER)
	assert_almost_eq(v[0], 101.0, 1e-6)
	assert_true(is_nan(v[1]), "второй слот корзины с одним значением — пусто")
	assert_true(is_nan(v[2]))
	assert_true(is_nan(v[3]))
	assert_eq(series.points(RideSeries.POWER).size(), 1)
	var hr := series.values(RideSeries.HEART_RATE)
	assert_almost_eq(hr[0], 140.0, 1e-6)
	assert_almost_eq(hr[1], 140.0, 1e-6)
	assert_eq(series.points(RideSeries.HEART_RATE).size(), 4)


func test_bucket_without_any_data_is_gap() -> void:
	var s := SampleStream.new()
	for i in 10:
		s.append(i, TrainerSample.full(float(i), 200, 90, 30.0) if i >= 4 else null, -1, 0, 0, true)
	var series := RideSeries.from_samples(s, 4)  # корзины по 5 с, 2 корзины × 2 слота
	assert_eq(series.bucket_sec, 5)
	var power := series.values(RideSeries.POWER)
	assert_eq(power.size(), 4)
	assert_almost_eq(power[0], 200.0, 1e-6, "корзина 0–4: единственное значение 200 (слот 4) → первый слот")
	assert_true(is_nan(power[1]), "второй слот этой корзины пуст")
	assert_almost_eq(power[2], 200.0, 1e-6)
	assert_almost_eq(power[3], 200.0, 1e-6)
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
	assert_eq(series.bucket_sec, 20, "50 корзин × 2 слота")
	assert_eq(series.size(), 100)
	assert_almost_eq(series.time_sec[1], 10.0, 1e-6)
	assert_almost_eq(series.time_sec[2], 20.0, 1e-6)


func test_decimation_last_partial_bucket_with_single_sample_has_one_slot() -> void:
	# 7201 с → корзины по 5 с; последняя корзина — один сэмпл → один слот.
	var series := RideSeries.from_samples(_stream(7201))
	assert_eq(series.bucket_sec, 5)
	assert_eq(series.size(), 1440 * 2 + 1)
	assert_almost_eq(series.time_sec[series.size() - 1], 7200.0, 1e-6)
	for i in range(1, series.size()):
		assert_true(series.time_sec[i] > series.time_sec[i - 1])
