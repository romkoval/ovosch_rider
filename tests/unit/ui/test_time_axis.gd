extends GutTest
## Тесты TimeAxis: шкала времени графика плана (REQ-HUD-10 крит. 4) и окна свободной езды
## (REQ-FRD-06 крит. 4 — модель; `docs/game/hud.md` п. 8).


func _texts(labels: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for l in labels:
		out.append(str(l["text"]))
	return out


func test_plan_60_min_step_10() -> void:
	assert_eq(TimeAxis.step_minutes(3600), 10)
	var labels := TimeAxis.labels(3600)
	assert_eq(_texts(labels), ["0", "10", "20", "30", "40", "50", "1:00"] as Array[String])
	assert_almost_eq(float(labels[0]["fraction"]), 0.0, 1e-6)
	assert_almost_eq(float(labels[6]["fraction"]), 1.0, 1e-6)
	assert_almost_eq(float(labels[3]["fraction"]), 0.5, 1e-6)
	assert_eq(int(labels[2]["sec"]), 1200)


func test_plan_20_min_step_5() -> void:
	assert_eq(TimeAxis.step_minutes(1200), 5)
	assert_eq(_texts(TimeAxis.labels(1200)), ["0", "5", "10", "15", "20"] as Array[String])


func test_smallest_step_from_series() -> void:
	assert_eq(TimeAxis.step_minutes(5 * 60), 1)  # 6 подписей
	assert_eq(TimeAxis.step_minutes(9 * 60), 1)  # 10 подписей — ещё можно
	assert_eq(TimeAxis.step_minutes(10 * 60), 2)  # 11 подписей при шаге 1 — много
	assert_eq(TimeAxis.step_minutes(3 * 3600), 30)  # 7 подписей
	assert_eq(TimeAxis.step_minutes(9 * 3600), 60)
	assert_eq(TimeAxis.step_minutes(10 * 3600), 120)  # за пределами ряда — кратное часу


func test_never_more_than_10_labels_and_step_multiple() -> void:
	for minutes in [1, 3, 7, 12, 25, 45, 61, 90, 135, 200, 299, 480, 600, 1000]:
		var span: int = int(minutes) * 60 + 17
		var labels := TimeAxis.labels(span)
		var step_sec: int = TimeAxis.step_minutes(span) * 60
		assert_lte(labels.size(), TimeAxis.MAX_LABELS, "план %d мин" % minutes)
		assert_gt(labels.size(), 1, "план %d мин" % minutes)
		for l in labels:
			assert_eq(int(l["sec"]) % step_sec, 0)
			assert_lte(int(l["sec"]), span)
			assert_almost_eq(float(l["fraction"]), float(l["sec"]) / float(span), 1e-6)
		# Шаг наименьший: предыдущий из ряда дал бы больше 10 подписей.
		var idx: int = TimeAxis.STEP_SERIES_MIN.find(step_sec / 60)
		if idx > 0:
			assert_gt(TimeAxis.label_count(span, TimeAxis.STEP_SERIES_MIN[idx - 1]), TimeAxis.MAX_LABELS)


func test_format_minutes_and_hours() -> void:
	assert_eq(TimeAxis.format_minutes(0), "0")
	assert_eq(TimeAxis.format_minutes(300), "5")
	assert_eq(TimeAxis.format_minutes(59 * 60), "59")
	assert_eq(TimeAxis.format_minutes(3600), "1:00")
	assert_eq(TimeAxis.format_minutes(5400), "1:30")
	assert_eq(TimeAxis.format_minutes(2 * 3600 + 5 * 60), "2:05")
	assert_eq(TimeAxis.format_minutes(-300), "−5")


func test_empty_plan_single_zero_label() -> void:
	var labels := TimeAxis.labels(0)
	assert_eq(labels.size(), 1)
	assert_eq(str(labels[0]["text"]), "0")


func test_window_growing_phase_absolute_0_to_30() -> void:
	var labels := TimeAxis.window_labels(600, 1800)
	assert_eq(_texts(labels), ["0", "5", "10", "15", "20", "25", "30"] as Array[String])
	for l in labels:
		assert_false(l["is_now"])
	# Ровно на границе окна — ещё растущая шкала.
	assert_eq(_texts(TimeAxis.window_labels(1800, 1800)), _texts(labels))


func test_window_sliding_relative_labels_with_now() -> void:
	var labels := TimeAxis.window_labels(4000, 1800)
	assert_eq(_texts(labels), ["−30", "−25", "−20", "−15", "−10", "−5", ""] as Array[String])
	assert_true(labels[6]["is_now"])
	assert_almost_eq(float(labels[6]["fraction"]), 1.0, 1e-6)
	assert_almost_eq(float(labels[0]["fraction"]), 0.0, 1e-6)
	assert_eq(int(labels[0]["sec"]), 2200)
	assert_eq(int(labels[6]["sec"]), 4000)
	# Подписи стоят на месте при движении времени.
	var later := TimeAxis.window_labels(4100, 1800)
	for i in labels.size():
		assert_almost_eq(float(later[i]["fraction"]), float(labels[i]["fraction"]), 1e-6)
