extends GutTest
## `FrameStats` (T-116a, п.3): сводка по синтетической серии длительностей кадров сходится
## с посчитанной вручную — средний FPS, 1 % low, перцентили, доля кадров > 16.7 и > 33 мс
## (инструмент для REQ-D3D-05 п.1, методика `docs/perf_budget.md`).


func _series(values: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for v in values:
		out.append(float(v))
	return out


func test_empty_stats_give_zero_summary_with_all_fields() -> void:
	var s := FrameStats.new().summary()
	for key in ["frames", "duration_s", "avg_fps", "avg_frame_ms", "low_1pct_fps", "p50_ms", "p95_ms",
			"p99_ms", "max_ms", "frames_over_16_7_ms", "frames_over_33_ms", "share_over_16_7_ms", "share_over_33_ms"]:
		assert_true(s.has(key), "поле %s есть и без кадров" % key)
	assert_eq(int(s["frames"]), 0)
	assert_eq(float(s["avg_fps"]), 0.0)


func test_steady_60_fps_series() -> void:
	var times := PackedFloat32Array()
	for i in 600:
		times.append(1000.0 / 60.0)
	var s := FrameStats.from_frame_times_ms(times).summary()
	assert_eq(int(s["frames"]), 600)
	assert_almost_eq(float(s["avg_fps"]), 60.0, 0.01)
	assert_almost_eq(float(s["low_1pct_fps"]), 60.0, 0.01)
	assert_almost_eq(float(s["p99_ms"]), 16.667, 0.001)
	assert_almost_eq(float(s["duration_s"]), 10.0, 0.01)
	assert_eq(int(s["frames_over_16_7_ms"]), 0, "16.667 мс не длиннее 16.7")
	assert_eq(float(s["share_over_33_ms"]), 0.0)


func test_mixed_series_matches_hand_computed_values() -> void:
	# 100 кадров: 90 × 10 мс, 8 × 20 мс, 2 × 50 мс. Сумма 900 + 160 + 100 = 1160 мс.
	var values: Array = []
	for i in 90:
		values.append(10.0)
	for i in 8:
		values.append(20.0)
	for i in 2:
		values.append(50.0)
	values.shuffle()
	var s := FrameStats.from_frame_times_ms(_series(values)).summary()
	assert_eq(int(s["frames"]), 100)
	assert_almost_eq(float(s["avg_fps"]), 100.0 * 1000.0 / 1160.0, 0.01, "кадры / суммарное время")
	assert_almost_eq(float(s["avg_frame_ms"]), 11.6, 0.001)
	assert_almost_eq(float(s["p50_ms"]), 10.0, 0.001, "50-й по рангу — 10 мс")
	assert_almost_eq(float(s["p95_ms"]), 20.0, 0.001, "95-й по рангу — 20 мс")
	assert_almost_eq(float(s["p99_ms"]), 50.0, 0.001, "99-й по рангу — 50 мс")
	assert_almost_eq(float(s["max_ms"]), 50.0, 0.001)
	# 1 % из 100 — один худший кадр (50 мс) → 20 FPS.
	assert_almost_eq(float(s["low_1pct_fps"]), 20.0, 0.01)
	assert_eq(int(s["frames_over_16_7_ms"]), 10)
	assert_eq(int(s["frames_over_33_ms"]), 2)
	assert_almost_eq(float(s["share_over_16_7_ms"]), 0.10, 1e-6)
	assert_almost_eq(float(s["share_over_33_ms"]), 0.02, 1e-6)


func test_one_percent_low_averages_worst_percent_of_frames() -> void:
	# 1000 кадров: 990 × 16 мс и 10 худших: 30, 32, …, 48 мс (среднее 39 мс).
	var values: Array = []
	for i in 990:
		values.append(16.0)
	for i in 10:
		values.append(30.0 + 2.0 * i)
	var s := FrameStats.from_frame_times_ms(_series(values)).summary()
	assert_almost_eq(float(s["low_1pct_fps"]), 1000.0 / 39.0, 0.01)
	assert_eq(int(s["frames_over_33_ms"]), 8, "34…48 мс — длиннее 33")


func test_non_positive_frames_are_ignored_and_reset_clears() -> void:
	var stats := FrameStats.new()
	stats.add_frame_ms(0.0)
	stats.add_frame_ms(-3.0)
	stats.add_frame_usec(20_000)
	assert_eq(stats.frame_count(), 1)
	assert_almost_eq(stats.total_ms(), 20.0, 1e-6)
	stats.reset()
	assert_eq(stats.frame_count(), 0)
	assert_eq(float(stats.summary()["max_ms"]), 0.0)


func test_capacity_grows_beyond_initial_buffer() -> void:
	var stats := FrameStats.new()
	for i in FrameStats.INITIAL_CAPACITY * 2 + 5:
		stats.add_frame_ms(10.0 if i % 100 != 0 else 40.0)
	var s := stats.summary()
	assert_eq(int(s["frames"]), FrameStats.INITIAL_CAPACITY * 2 + 5)
	assert_almost_eq(float(s["max_ms"]), 40.0, 1e-6)
	# 82 долгих кадра из 8197 (чуть больше 1 %) — 99-й перцентиль попадает на 40 мс.
	assert_eq(int(s["frames_over_33_ms"]), 82)
	assert_almost_eq(float(s["p99_ms"]), 40.0, 1e-6, "кадры сверх начальной ёмкости учтены в перцентилях")
