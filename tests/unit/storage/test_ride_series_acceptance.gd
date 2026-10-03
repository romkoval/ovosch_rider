extends GutTest
## Приёмка `RideSeries` (REQ-LOC-03 крит. 1–3) — независимые тесты тестировщика.
## Источник истины — критерии `docs/requirements.md`, не комментарии в коде.


## Поток `n` с: мощность/каденс/пульс задаются функциями от индекса;
## значение < 0 — «нет данных» по этому потоку (для мощности/каденса весь сэмпл
## станка отсутствует, если и мощности, и каденса нет).
func _stream(n: int, power_fn: Callable, hr_fn: Callable, target_fn: Callable = Callable()) -> SampleStream:
	var s := SampleStream.new()
	for i in n:
		var p: int = power_fn.call(i)
		var sample: TrainerSample = null
		if p >= 0:
			sample = TrainerSample.full(float(i), p, 90, 30.0)
		var target: int = target_fn.call(i) if target_fn.is_valid() else 200
		s.append(i, sample, hr_fn.call(i), target, 0, true)
	return s


static func _const_power(i: int) -> int:
	return 200 + 0 * i


static func _no_hr(_i: int) -> int:
	return -1


static func _hr_150(_i: int) -> int:
	return 150


## Пропуски «нет данных» в нерегулярных местах: каждые 5-й и 13-й слоты.
static func _gappy_power(i: int) -> int:
	if i % 5 == 3 or i % 13 == 0:
		return -1
	return 100 + (i * 7) % 180


static func _gappy_hr(i: int) -> int:
	return -1 if i % 4 == 1 else 120 + i % 30


## 7200 с: ровные 200 Вт, один спринт 1000 Вт на нечётном слоте 3001 и один
## провал 0 Вт (настоящий ноль с данными) на нечётном слоте 5001.
static func _spike_power(i: int) -> int:
	if i == 3001:
		return 1000
	if i == 5001:
		return 0
	return 200


static func _step_target(i: int) -> int:
	return 150 if i < 60 else 300


static func _y_extremes(points: PackedVector2Array) -> Vector2:
	var lo: float = INF
	var hi: float = -INF
	for p in points:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	return Vector2(lo, hi)


# ---------------------------------------------------------------------------
# REQ-LOC-03 крит. 1: точки (t, значение) без «нет данных»; длина серии мощности
# равна числу сэмплов с данными
# ---------------------------------------------------------------------------

func test_req_loc_03_c1_points_skip_no_data_and_match_samples_exactly() -> void:
	var s := _stream(900, _gappy_power, _gappy_hr)
	var series := RideSeries.from_samples(s)
	var power_pts := series.points(RideSeries.POWER)
	assert_eq(power_pts.size(), s.count_with_power(), "длина серии мощности = число сэмплов с данными мощности")
	# Каждая точка соответствует ровно одному сэмплу с данными: t и значение совпадают.
	var k: int = 0
	for i in s.size():
		if not s.has_power[i]:
			continue
		assert_almost_eq(power_pts[k].x, float(s.time_sec[i]), 1e-6, "t точки %d" % k)
		assert_almost_eq(power_pts[k].y, float(s.power_w[i]), 1e-6, "значение точки %d" % k)
		k += 1
	var hr_with_data: int = 0
	for ok in s.has_heart_rate:
		if ok:
			hr_with_data += 1
	assert_eq(series.points(RideSeries.HEART_RATE).size(), hr_with_data, "пульс: пропуски «нет данных»")
	var cad_with_data: int = 0
	for ok in s.has_cadence:
		if ok:
			cad_with_data += 1
	assert_eq(series.points(RideSeries.CADENCE).size(), cad_with_data, "каденс: пропуски «нет данных»")
	var vals := series.values(RideSeries.POWER)
	assert_true(is_nan(vals[3]), "слот без данных — NaN (разрыв), а не 0")
	assert_true(is_nan(vals[13]))


func test_req_loc_03_c1_real_zero_power_is_data_not_gap() -> void:
	# Свободный накат: станок шлёт 0 Вт — это данные, точка (t, 0) должна остаться.
	var s := SampleStream.new()
	for i in 10:
		var sample: TrainerSample = TrainerSample.full(float(i), 0 if i >= 5 else 180, 0 if i >= 5 else 85, 20.0)
		s.append(i, sample, -1, 0, 0, false)
	s.append(10, null, -1, 0, 0, false)
	var series := RideSeries.from_samples(s)
	var pts := series.points(RideSeries.POWER)
	assert_eq(pts.size(), 10, "10 сэмплов с данными (в т.ч. 5 нулей), 1 без данных")
	assert_almost_eq(pts[9].y, 0.0, 1e-6, "ноль мощности сохранён как значение")
	assert_eq(series.points(RideSeries.CADENCE).size(), 10, "каденс 0 — тоже данные")
	assert_eq(series.points(RideSeries.HEART_RATE).size(), 0, "пульса не было — пустая серия, без нулей")
	assert_false(series.has_data(RideSeries.HEART_RATE))


func test_req_loc_03_c1_edge_ride_without_samples() -> void:
	var series := RideSeries.from_samples(SampleStream.new())
	assert_eq(series.size(), 0)
	for name in RideSeries.NAMES:
		assert_eq(series.points(name).size(), 0, "пустая серия %s" % name)
	assert_true(is_nan(series.peak(RideSeries.POWER)), "максимум пустой серии — нет данных")
	assert_true(is_nan(series.low(RideSeries.POWER)))


func test_req_loc_03_c1_edge_single_sample() -> void:
	var s := _stream(1, _const_power, _hr_150)
	var series := RideSeries.from_samples(s)
	assert_eq(series.points(RideSeries.POWER).size(), 1)
	assert_eq(series.points(RideSeries.POWER)[0], Vector2(0.0, 200.0))
	assert_eq(series.points(RideSeries.HEART_RATE)[0], Vector2(0.0, 150.0))
	assert_eq(series.points(RideSeries.TARGET).size(), 1)
	var only_gap := SampleStream.new()
	only_gap.append(0, null, -1, 200, 0, true)
	var gap_series := RideSeries.from_samples(only_gap)
	assert_eq(gap_series.points(RideSeries.POWER).size(), 0, "единственный сэмпл без данных — нет точек")
	assert_eq(gap_series.points(RideSeries.TARGET).size(), 1, "цель есть и тогда")


# ---------------------------------------------------------------------------
# REQ-LOC-03 крит. 2: > 1 ч — прореживание до ≤ 3600 точек с сохранением min/max
# ---------------------------------------------------------------------------

func test_req_loc_03_c2_boundary_one_hour_and_lengths_up_to_10h() -> void:
	var exact := RideSeries.from_samples(_stream(3600, _gappy_power, _hr_150))
	assert_eq(exact.size(), 3600, "ровно 1 ч — без прореживания")
	assert_eq(exact.bucket_sec, 1)
	for n in [3601, 5000, 7199, 7200, 7201, 10801, 36000]:
		var s := _stream(n, _gappy_power, _hr_150)
		var series := RideSeries.from_samples(s)
		assert_lte(series.size(), 3600, "n=%d: ≤ 3600 точек" % n)
		assert_lte(series.points(RideSeries.POWER).size(), 3600, "n=%d: точек мощности ≤ 3600" % n)
		assert_gt(series.size(), 1800, "n=%d: прореживание не грубее необходимого" % n)
		var last_t: float = series.time_sec[series.size() - 1]
		assert_gte(last_t + float(series.bucket_sec), float(n), "n=%d: серия покрывает весь заезд" % n)


func test_req_loc_03_c2_7200_samples_min_max_kept_in_bucket_extremes() -> void:
	var s := _stream(7200, _spike_power, _hr_150)
	var series := RideSeries.from_samples(s)
	assert_lte(series.size(), 3600)
	assert_almost_eq(series.peak(RideSeries.POWER), 1000.0, 1e-6, "максимум (спринт 1 с) сохранён")
	assert_almost_eq(series.low(RideSeries.POWER), 0.0, 1e-6, "минимум (0 Вт с данными) сохранён")


func test_req_loc_03_c2_7200_samples_decimated_points_keep_min_and_max() -> void:
	# Критерий: «серии прореживаются до ≤ 3600 точек с сохранением минимумов и максимумов».
	# Серия по крит. 1 — точки (t, значение); после прореживания в ней должны остаться
	# экстремумы потока, иначе график теряет спринт и провал.
	var s := _stream(7200, _spike_power, _hr_150)
	var series := RideSeries.from_samples(s)
	var pts := series.points(RideSeries.POWER)
	assert_lte(pts.size(), 3600)
	var ext := _y_extremes(pts)
	assert_almost_eq(ext.y, 1000.0, 1e-6, "максимум 1000 Вт есть среди точек серии мощности")
	assert_almost_eq(ext.x, 0.0, 1e-6, "минимум 0 Вт есть среди точек серии мощности")


# ---------------------------------------------------------------------------
# REQ-LOC-03 крит. 3: серия цели плана всегда есть
# ---------------------------------------------------------------------------

func test_req_loc_03_c3_target_series_present_and_follows_plan() -> void:
	var s := _stream(120, _gappy_power, _no_hr, _step_target)
	var series := RideSeries.from_samples(s)
	var target := series.points(RideSeries.TARGET)
	assert_eq(target.size(), 120, "цель — на каждый сэмпл, даже где нет мощности")
	assert_almost_eq(target[0].y, 150.0, 1e-6)
	assert_almost_eq(target[59].y, 150.0, 1e-6)
	assert_almost_eq(target[60].y, 300.0, 1e-6)
	assert_eq(series.values(RideSeries.TARGET).size(), series.values(RideSeries.POWER).size(),
		"серия цели той же длины, что и мощность (накладывается поверх)")


func test_req_loc_03_c3_target_present_without_power_and_when_decimated() -> void:
	var no_power := _stream(30, _no_hr, _no_hr)
	var s1 := RideSeries.from_samples(no_power)
	assert_eq(s1.points(RideSeries.POWER).size(), 0)
	assert_eq(s1.points(RideSeries.TARGET).size(), 30, "цель есть и без телеметрии")
	var long := RideSeries.from_samples(_stream(7200, _spike_power, _hr_150))
	assert_eq(long.points(RideSeries.TARGET).size(), long.size(), "после прореживания цель — в каждой точке")
