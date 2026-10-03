extends GutTest
## Тесты EffortSeries: серии факта мощности и пульса на нижнем графике
## (REQ-HUD-11 крит. 1–5, REQ-HUD-12 крит. 1, 2, 3 — стиль, 5–7, REQ-FRD-06 крит. 4 — модель окна).

const FTP: int = 200

var _trainer: FakeTrainer
var _session: WorkoutSession


func before_each() -> void:
	_trainer = FakeTrainer.new(5)
	_trainer.connect_delay_sec = 0.0
	_trainer.power_noise_w = 0.0
	_trainer.power_tau_sec = 0.01
	_trainer.cadence_noise_rpm = 0.0
	_trainer.connect_device("effort")


func _plan(minutes: int = 20) -> Workout:
	var steps: Array[WorkoutStep] = [WorkoutStep.percent(minutes * 60, 75.0)]
	return Workout.make("effort", steps)


func _values(run: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for p in (run["points"] as PackedVector2Array):
		out.append(roundi(p.y))
	return out


# ---------------------------------------------------------------------------
# HUD-11.1 — сглаженная мощность, одна точка на сэмпл
# ---------------------------------------------------------------------------

func test_smoothed_power_100_200_300_300() -> void:
	var s := EffortSeries.new()
	var t: int = 1
	for w in [100, 200, 300, 300]:
		s.push(t, w, true, -1, false)
		t += 1
	var runs := s.power_runs(0.0, 10.0, 1280, 1000.0)
	assert_eq(runs.size(), 1)
	assert_eq(_values(runs[0]), [100, 150, 200, 267] as Array[int])
	var pts: PackedVector2Array = runs[0]["points"]
	assert_eq(pts[0].x, 1.0)
	assert_eq(pts[3].x, 4.0)


# ---------------------------------------------------------------------------
# HUD-11.3 — разрывы и пауза
# ---------------------------------------------------------------------------

func test_missing_power_is_gap_not_zero() -> void:
	var s := EffortSeries.new()
	s.push(1, 200, true, -1, false)
	s.push(2, 200, true, -1, false)
	s.push(3, 0, false, -1, false)
	s.push(4, 200, true, -1, false)
	var runs := s.power_runs(0.0, 10.0, 1280, 1000.0)
	assert_eq(runs.size(), 2)
	assert_eq(EffortSeries.point_count(runs), 3)
	for r in runs:
		for v in _values(r):
			assert_gt(v, 0)


func test_time_jump_breaks_line() -> void:
	var s := EffortSeries.new()
	s.push(1, 200, true, 120, true)
	s.push(2, 200, true, 120, true)
	s.push(10, 200, true, 120, true)
	assert_eq(s.power_runs(0.0, 20.0, 100, 1000.0).size(), 2)
	assert_eq(s.hr_runs(0.0, 20.0, 100).size(), 2)
	assert_false(s.push(10, 300, true, 120, true), "время не растёт — сэмпл отброшен")


func test_pause_adds_no_points_and_line_continues() -> void:
	_session = WorkoutSession.new(_plan(), _trainer, FTP)
	var s := EffortSeries.new()
	_session.start()
	for i in 10:
		_session.tick(1.0)
		assert_eq(s.sync_from_stream(_session.samples), 1, "точка — не позже следующего сэмпла")
	_session.pause()
	for i in 20:
		_session.tick(1.0)
		assert_eq(s.sync_from_stream(_session.samples), 0)
	_session.resume()
	for i in 5:
		_session.tick(1.0)
		s.sync_from_stream(_session.samples)
	var runs := s.power_runs(0.0, 1200.0, 1280, 1000.0)
	assert_eq(runs.size(), 1, "после паузы линия продолжается без разрыва")
	assert_eq(EffortSeries.point_count(runs), 15)
	var pts: PackedVector2Array = runs[0]["points"]
	assert_eq(pts[10].x, 11.0, "продолжение с того же x")


func test_no_points_right_of_cursor() -> void:
	_session = WorkoutSession.new(_plan(), _trainer, FTP)
	var plan := PlanChartModel.for_session(_session)
	var s := EffortSeries.new()
	_session.start()
	for i in 90:
		_session.tick(1.0)
		plan.sync(_session)
		s.sync_from_stream(_session.samples, plan.time_shift_sec())
		for r in s.power_runs(0.0, float(plan.total_sec()), 1280, plan.y_max()):
			for p in (r["points"] as PackedVector2Array):
				assert_lte(p.x, plan.cursor_sec())
	assert_eq(s.last_time_sec(), 90)


func test_skip_shifts_points_into_plan_time() -> void:
	var steps: Array[WorkoutStep] = [WorkoutStep.percent(600, 50.0), WorkoutStep.percent(600, 80.0)]
	_session = WorkoutSession.new(Workout.make("skip", steps), _trainer, FTP)
	var plan := PlanChartModel.for_session(_session)
	var s := EffortSeries.new()
	_session.start()
	for i in 30:
		_session.tick(1.0)
		plan.sync(_session)
		s.sync_from_stream(_session.samples, plan.time_shift_sec())
	_session.skip_step()
	for i in 5:
		_session.tick(1.0)
		plan.sync(_session)
		s.sync_from_stream(_session.samples, plan.time_shift_sec())
	var runs := s.power_runs(0.0, 1200.0, 1280, plan.y_max())
	assert_eq(runs.size(), 2, "над остатком пропущенного шага линии нет")
	var last: PackedVector2Array = runs[1]["points"]
	assert_eq(last[last.size() - 1].x, plan.cursor_sec())


## HUD-10.5, HUD-11.1 (У-1): сдвиг привязан к строке — точки до пропуска не сдвигаются, даже если
## синхронизация была реже раза в сэмпл; одна синхронизация в конце == синхронизация на каждом.
func _run_with_skips(sync_every: int) -> EffortSeries:
	var steps: Array[WorkoutStep] = [WorkoutStep.percent(300, 50.0), WorkoutStep.percent(300, 80.0),
			WorkoutStep.percent(300, 60.0)]
	_session = WorkoutSession.new(Workout.make("skip", steps), _trainer, FTP)
	var plan := PlanChartModel.for_session(_session)
	var s := EffortSeries.new(EffortSeries.MODE_PLAN, FTP, 190)
	_session.start()
	var n: int = 0
	for action in [100, "skip", 50, "skip", 40]:
		if action is String:
			_session.skip_step()
			continue
		for i in int(action):
			_session.tick(1.0)
			n += 1
			if sync_every > 0 and n % sync_every == 0:
				plan.sync(_session)
				s.sync_from_plan(_session.samples, plan)
	plan.sync(_session)
	s.sync_from_plan(_session.samples, plan)
	return s


func test_sync_rate_does_not_change_points_after_skip() -> void:
	var every := _run_with_skips(1)
	var sparse := _run_with_skips(7)
	var once := _run_with_skips(0)
	var expected := every.raw_points(EffortSeries.SERIES_POWER)
	assert_eq(expected.size(), 190)
	assert_eq(sparse.raw_points(EffortSeries.SERIES_POWER), expected)
	assert_eq(once.raw_points(EffortSeries.SERIES_POWER), expected)
	assert_eq(once.raw_points(EffortSeries.SERIES_HR), every.raw_points(EffortSeries.SERIES_HR))
	# Пропуск шага 0 на 100-й секунде (сдвиг 200), шага 1 на 150-й, позиция 350 (сдвиг 450).
	assert_eq(expected[0].x, 1.0)
	assert_eq(expected[99].x, 100.0, "точки до пропуска не сдвинуты")
	assert_eq(expected[100].x, 301.0)
	assert_eq(expected[149].x, 350.0)
	assert_eq(expected[150].x, 601.0)
	assert_eq(expected[189].x, 640.0)
	var runs := once.power_runs(0.0, 900.0, 900, 1000.0)
	assert_eq(runs.size(), 3, "в местах пропуска — разрывы")
	for r in runs:
		for p in (r["points"] as PackedVector2Array):
			assert_false(p.x > 100.0 and p.x < 300.0, "над остатком шага 0 точек нет")
			assert_false(p.x > 350.0 and p.x < 600.0, "над остатком шага 1 точек нет")


# ---------------------------------------------------------------------------
# HUD-11.4 — обрезка по y_max
# ---------------------------------------------------------------------------

func test_values_above_y_max_clamped_and_flagged() -> void:
	var s := EffortSeries.new()
	for t in range(1, 6):
		s.push(t, 500, true, -1, false)
	var runs := s.power_runs(0.0, 10.0, 100, 300.0)
	var pts: PackedVector2Array = runs[0]["points"]
	var clipped: PackedByteArray = runs[0]["clipped"]
	for i in pts.size():
		assert_eq(pts[i].y, 300.0)
		assert_eq(clipped[i], 1)
	var free := s.power_runs(0.0, 10.0, 100, 600.0)
	assert_eq((free[0]["clipped"] as PackedByteArray)[0], 0)


# ---------------------------------------------------------------------------
# HUD-11.5, HUD-12.7 — прореживание min/max
# ---------------------------------------------------------------------------

func test_three_hour_plan_decimated_keeps_sprint_peak() -> void:
	var s := EffortSeries.new()
	var total: int = 3 * 3600
	for t in range(1, total + 1):
		var w: int = 1000 if t > 5000 and t <= 5030 else 200
		var hr: int = 160 if t > 5000 and t <= 5060 else 130
		s.push(t, w, true, hr, true)
	var runs := s.power_runs(0.0, float(total), 1280, 2000.0)
	assert_lte(EffortSeries.point_count(runs), 2560)
	assert_gt(EffortSeries.point_count(runs), 1280)
	var peak: float = 0.0
	var prev_t: float = -1.0
	for r in runs:
		for p in (r["points"] as PackedVector2Array):
			peak = maxf(peak, p.y)
			assert_gt(p.x, prev_t, "точки идут по времени")
			prev_t = p.x
	assert_eq(peak, 1000.0, "пик 30-секундного спринта среди точек")
	var hr_runs := s.hr_runs(0.0, float(total), 1280)
	assert_lte(EffortSeries.point_count(hr_runs), 2560)
	var hr_peak: float = 0.0
	for r in hr_runs:
		for p in (r["points"] as PackedVector2Array):
			hr_peak = maxf(hr_peak, p.y)
	assert_eq(hr_peak, 160.0)


func test_decimation_keeps_gaps() -> void:
	var s := EffortSeries.new()
	for t in range(1, 3001):
		s.push(t, 200, t < 1500 or t > 1600, -1, false)
	var runs := s.power_runs(0.0, 3000.0, 100, 1000.0)
	assert_lte(EffortSeries.point_count(runs), 200)
	assert_eq(runs.size(), 2)


# ---------------------------------------------------------------------------
# HUD-12 — пульс
# ---------------------------------------------------------------------------

func test_hr_zero_and_missing_are_gaps() -> void:
	var s := EffortSeries.new(EffortSeries.MODE_PLAN, FTP, 180)
	s.push(1, 200, true, 120, true)
	s.push(2, 200, true, 0, true)
	s.push(3, 200, true, 125, true)
	s.push(4, 200, true, -1, false)
	s.push(5, 200, true, 130, true)
	var runs := s.hr_runs(0.0, 10.0, 100)
	assert_eq(runs.size(), 3)
	assert_eq(EffortSeries.point_count(runs), 3)
	assert_eq(s.power_runs(0.0, 10.0, 100, 1000.0).size(), 1, "пульс не рвёт мощность")


func test_hr_scale_own_range_and_clamp() -> void:
	var s := EffortSeries.new(EffortSeries.MODE_PLAN, FTP, 180)
	assert_eq(s.hr_scale_min(), 50)
	assert_eq(s.hr_scale_max(), 180)
	s.set_max_hr(0)
	assert_eq(s.hr_scale_max(), 200)
	s.push(1, 900, true, 40, true)
	s.push(2, 100, true, 210, true)
	var runs := s.hr_runs(0.0, 10.0, 100)
	var pts: PackedVector2Array = runs[0]["points"]
	var clipped: PackedByteArray = runs[0]["clipped"]
	assert_eq(pts[0].y, 50.0)
	assert_eq(pts[1].y, 200.0)
	assert_eq(clipped[0], 1)
	assert_eq(clipped[1], 1)
	# Шкала пульса не зависит от мощности.
	assert_almost_eq(s.hr_fraction(125.0), 75.0 / 150.0, 1e-6)
	s.push(3, 2000, true, 125, true)
	assert_almost_eq(s.hr_fraction(125.0), 75.0 / 150.0, 1e-6)


func test_hr_style_is_line_without_area_on_right_side() -> void:
	var s := EffortSeries.new()
	var hr := s.style(EffortSeries.SERIES_HR)
	assert_eq(str(hr["style"]), EffortSeries.STYLE_LINE)
	assert_false(hr["fill"])
	assert_eq(str(hr["color_token"]), "hud.hr_line")
	assert_eq(str(hr["outline_token"]), "hud.ink")
	assert_eq(str(hr["scale_side"]), EffortSeries.SIDE_RIGHT)
	assert_eq(str(hr["label_token"]), "hud.hr_label")
	var power := s.style(EffortSeries.SERIES_POWER)
	assert_eq(str(power["color_token"]), "hud.power_line")
	assert_eq(str(power["style"]), EffortSeries.STYLE_LINE)
	assert_eq(str(power["scale_side"]), EffortSeries.SIDE_LEFT)
	assert_ne(str(power["scale_side"]), str(hr["scale_side"]))
	# В окне свободной езды мощность — площадь с линией, пульс — по-прежнему только линия.
	var w := EffortSeries.sliding_window(FTP)
	assert_eq(str(w.style(EffortSeries.SERIES_POWER)["style"]), EffortSeries.STYLE_AREA_LINE)
	assert_false(w.style(EffortSeries.SERIES_HR)["fill"])


func test_hr_labels_and_scale_hidden_without_sensor() -> void:
	var s := EffortSeries.new(EffortSeries.MODE_PLAN, FTP, 180)
	for t in range(1, 30):
		s.push(t, 200, true, -1, false)
	assert_false(s.hr_scale_visible())
	assert_eq(s.hr_scale_labels().size(), 0)
	assert_eq(s.hr_runs(0.0, 100.0, 100).size(), 0)
	s.push(30, 200, true, 120, true)
	assert_true(s.hr_scale_visible())
	assert_eq(s.hr_scale_labels(), [100, 150] as Array[int])
	s.set_max_hr(140)
	assert_eq(s.hr_scale_labels(), [100] as Array[int])


func test_hr_from_session_stream() -> void:
	_session = WorkoutSession.new(_plan(), _trainer, FTP)
	var s := EffortSeries.new(EffortSeries.MODE_PLAN, FTP, 180)
	_trainer.set_heart_rate(140)
	_session.start()
	for i in 5:
		_session.tick(1.0)
	_trainer.set_heart_rate(0)
	for i in 3:
		_session.tick(1.0)
	_trainer.set_heart_rate(150)
	for i in 3:
		_session.tick(1.0)
	s.sync_from_stream(_session.samples)
	var runs := s.hr_runs(0.0, 1200.0, 1280)
	assert_eq(runs.size(), 2)
	assert_eq(_values(runs[0])[0], 140)
	assert_eq(_values(runs[1])[0], 150)


# ---------------------------------------------------------------------------
# FRD-06.4 — скользящее окно и шкала мощности свободной езды
# ---------------------------------------------------------------------------

func test_window_defaults_30_min_and_1_5_ftp() -> void:
	var s := EffortSeries.sliding_window(FTP)
	assert_eq(s.window_sec, 1800)
	assert_almost_eq(s.ftp_factor, 1.5, 1e-6)
	assert_almost_eq(s.power_y_max(), 300.0, 1e-6)
	var custom := EffortSeries.sliding_window(FTP, 0, 1200, 1.25)
	assert_eq(custom.window_sec, 1200)
	assert_almost_eq(custom.power_y_max(), 250.0, 1e-6)


func test_window_grows_then_slides() -> void:
	var s := EffortSeries.sliding_window(FTP)
	for t in range(1, 601):
		s.push(t, 200, true, -1, false)
	assert_eq(s.visible_range(), Vector2(0.0, 1800.0))
	assert_almost_eq(s.window_x_of(600.0, 1800.0), 600.0, 1.0, "линия растёт слева направо")
	for t in range(601, 2001):
		s.push(t, 200, true, -1, false)
	assert_eq(s.visible_range(), Vector2(200.0, 2000.0))
	assert_almost_eq(s.window_x_of(2000.0, 1280.0), 1280.0, 1.0, "сейчас — у правого края")
	assert_almost_eq(s.window_x_of(200.0, 1280.0), 0.0, 1.0)
	var r := s.visible_range()
	var runs := s.power_runs(r.x, r.y, 1280, s.power_y_max())
	assert_eq(EffortSeries.point_count(runs), 1801)
	var pts: PackedVector2Array = runs[0]["points"]
	assert_eq(pts[0].x, 200.0)
	assert_eq(s.window_time_labels().size(), 7)
	assert_true(s.window_time_labels()[6]["is_now"])


func test_window_y_max_grows_immediately_rounded_to_50() -> void:
	var s := EffortSeries.sliding_window(FTP)
	for t in range(1, 11):
		s.push(t, 200, true, -1, false)
	assert_almost_eq(s.power_y_max(), 300.0, 1e-6)
	for t in range(11, 14):
		s.push(t, 420, true, -1, false)
	# Сглаженная 420 Вт → ⌈420 / 50⌉ · 50 = 450 сразу на этом сэмпле.
	assert_almost_eq(s.power_y_max(), 450.0, 1e-6)


func test_window_y_max_shrinks_not_more_often_than_60_s() -> void:
	var s := EffortSeries.sliding_window(FTP, 0, 120)
	var power: Array[int] = []
	for t in range(1, 601):
		var w: int = 200
		if t <= 3:
			w = 650
		elif t >= 40 and t <= 42:
			w = 520
		elif t >= 70 and t <= 72:
			w = 420
		power.append(w)
	var prev: float = s.power_y_max()
	var shrink_times: Array[int] = []
	var t: int = 1
	for w in power:
		s.push(t, w, true, -1, false)
		var now: float = s.power_y_max()
		assert_gte(now, s.target_power_y_max(), "потолок не ниже нужного — рост сразу")
		if now < prev:
			shrink_times.append(t)
		prev = now
		t += 1
	assert_gt(shrink_times.size(), 1)
	for i in range(1, shrink_times.size()):
		assert_gte(shrink_times[i] - shrink_times[i - 1], 60)
	assert_almost_eq(s.power_y_max(), 300.0, 1e-6, "в итоге вернулся к 1.5 × FTP")
