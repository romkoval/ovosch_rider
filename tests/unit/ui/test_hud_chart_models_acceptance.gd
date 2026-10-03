extends GutTest
## Независимые приёмочные тесты моделей нижнего графика HUD (тестировщик, T-065).
## Покрытие: REQ-HUD-10 крит. 1–5, REQ-HUD-11 крит. 1–5, REQ-HUD-12 крит. 1, 2, 5–7,
## REQ-FRD-06 крит. 4 (модель окна и шкалы).
## Источник истины — `docs/requirements.md`; план — `acc_full.zwo` (38 мин, все типы шагов),
## телеметрия — `FakeTrainer` с ручной подачей сэмплов (`inject_silence`), как в
## `test_hud_acceptance.gd`. Пиксели считаются по формулам критериев от ширины/высоты поля.

const FTP: int = 200
const ACC_FULL: String = "res://tests/fixtures/workouts_acceptance/acc_full.zwo"
const W: float = 1280.0
const H: float = 122.0

var _trainer: FakeTrainer
var _session: WorkoutSession


func before_each() -> void:
	_trainer = FakeTrainer.new(11)
	_trainer.connect_delay_sec = 0.0
	_trainer.connect_device("chart")
	_trainer.inject_silence(1_000_000.0)


func _acc_full() -> Workout:
	var result: ParseResult = ZwoParser.parse(FileAccess.get_file_as_string(ACC_FULL))
	assert_true(result.ok(), "предусловие: acc_full.zwo разбирается")
	return result.workout


static func _plan(steps: Array) -> Workout:
	var typed: Array[WorkoutStep] = []
	for s in steps:
		typed.append(s)
	return Workout.make("chart", typed)


func _start(plan: Workout, intensity: float = 1.0) -> WorkoutSession:
	_session = WorkoutSession.new(plan, _trainer, FTP, intensity)
	_session.start()
	return _session


## Одна секунда: мощность (-1 — нет сэмпла станка), пульс (-1 — нет).
func _second(power: int = -1, hr: int = -1) -> void:
	if power >= 0:
		var s := TrainerSample.new()
		s.timestamp_sec = _trainer.get_time_sec()
		s.power_w = power
		s.has_power = true
		_trainer.telemetry.emit(s)
	if hr >= 0:
		_trainer.heart_rate.emit(hr)
	_session.tick(1.0)


static func _pieces_of(model: PlanChartModel, step_index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in model.pieces():
		if int(p["step_index"]) == step_index:
			out.append(p)
	return out


static func _all_values(runs: Array[Dictionary]) -> Array[float]:
	var out: Array[float] = []
	for r in runs:
		for v: Vector2 in (r["points"] as PackedVector2Array):
			out.append(v.y)
	return out


static func _all_times(runs: Array[Dictionary]) -> Array[float]:
	var out: Array[float] = []
	for r in runs:
		for v: Vector2 in (r["points"] as PackedVector2Array):
			out.append(v.x)
	return out


# ===========================================================================
# REQ-HUD-10 крит. 1 — модель сегментов
# ===========================================================================

func test_req_hud_10_c1_acc_full_segments_start_duration_targets_zone_and_sum() -> void:
	var plan := _acc_full()
	var model := PlanChartModel.new(plan, FTP)
	var segs := model.segments()
	assert_eq(segs.size(), plan.steps.size(), "по сегменту на каждый шаг")
	var sum: int = 0
	var expected_start: int = 0
	for seg in segs:
		var i: int = int(seg["index"])
		var step: WorkoutStep = plan.steps[i]
		assert_eq(int(seg["start_sec"]), expected_start, "шаг %d: начало сразу за предыдущим" % i)
		assert_eq(int(seg["duration_sec"]), step.duration_sec, "шаг %d: длительность" % i)
		assert_eq(int(seg["start_watts"]), step.start_watts(FTP, 1.0), "шаг %d: цель в начале" % i)
		assert_eq(int(seg["end_watts"]), step.end_watts(FTP, 1.0), "шаг %d: цель в конце" % i)
		expected_start += step.duration_sec
		sum += int(seg["duration_sec"])
	assert_eq(sum, plan.total_duration_sec(), "сумма длительностей = длительность плана")
	assert_eq(sum, 2280, "acc_full — 38 мин")
	assert_eq(model.total_sec(), 2280)
	# Ровные шаги: зона по цели (Coggan от FTP 200).
	assert_eq(int(segs[1]["zone"]), 4, "SteadyState 100 % FTP → Z4")
	assert_eq(int(segs[2]["zone"]), 5, "IntervalsT on 120 % → Z5 (граница 120 — нижней зоне)")
	assert_eq(int(segs[3]["zone"]), 1, "IntervalsT off 50 % → Z1")
	assert_eq(str(segs[1]["zone_token"]), "z4")


func test_req_hud_10_c1_rampa_has_different_start_and_end_targets() -> void:
	var model := PlanChartModel.new(_acc_full(), FTP)
	var warmup: Dictionary = model.segments()[0]
	assert_eq(int(warmup["start_watts"]), 80, "разминка 40 % → 80 Вт")
	assert_eq(int(warmup["end_watts"]), 140, "разминка 70 % → 140 Вт")
	assert_true(bool(warmup["ramp"]), "признак рампы")
	var steady: Dictionary = model.segments()[1]
	assert_eq(int(steady["start_watts"]), int(steady["end_watts"]))
	assert_false(bool(steady["ramp"]))


func test_req_hud_10_c1_free_ride_and_max_effort_are_free_without_zone() -> void:
	var plan := _acc_full()
	var model := PlanChartModel.new(plan, FTP)
	var segs := model.segments()
	# FreeRide — шаг 10, MaxEffort — шаг 11 (парсер: как FreeRide), cooldown — 12... индекс по плану.
	var free_count: int = 0
	for seg in segs:
		var step: WorkoutStep = plan.steps[int(seg["index"])]
		if step.is_free_ride():
			free_count += 1
			assert_true(bool(seg["free"]), "шаг %d без цели — «свободно»" % int(seg["index"]))
			assert_eq(int(seg["zone"]), 0, "у «свободно» нет зоны")
			assert_ne(str(seg["color_token"]), "z1", "не цвет зоны")
		else:
			assert_false(bool(seg["free"]))
			assert_between(int(seg["zone"]), 1, 7)
	assert_eq(free_count, 2, "FreeRide и MaxEffort")


func test_req_hud_10_c1_zone_accounts_for_intensity_multiplier() -> void:
	var model := PlanChartModel.new(_acc_full(), FTP, 1.1)
	var steady: Dictionary = model.segments()[1]
	assert_eq(int(steady["start_watts"]), 220, "100 % × 200 × 1.1")
	assert_eq(int(steady["zone"]), 5, "220 Вт = 110 % FTP → Z5 (без множителя было бы Z4)")


func test_req_hud_10_c1_zero_duration_and_empty_plan_do_not_break() -> void:
	var model := PlanChartModel.new(_plan([WorkoutStep.percent(0, 50.0), WorkoutStep.percent(60, 80.0)]), FTP)
	var sum: int = 0
	for seg in model.segments():
		sum += int(seg["duration_sec"])
	assert_eq(sum, 60)
	assert_eq(model.x_of(60.0, W), W)
	var empty := PlanChartModel.new(_plan([]), FTP)
	assert_eq(empty.segments().size(), 0)
	assert_eq(empty.pieces().size(), 0)
	assert_eq(empty.x_of(10.0, W), 0.0, "пустой план — без деления на 0")


# ===========================================================================
# REQ-HUD-10 крит. 2 — оси
# ===========================================================================

func test_req_hud_10_c2_whole_plan_fits_width_for_any_length() -> void:
	for minutes in [5, 38, 60, 180, 360]:
		var total: int = minutes * 60
		var model := PlanChartModel.new(_plan([WorkoutStep.percent(total, 70.0)]), FTP)
		assert_almost_eq(model.x_of(0.0, W), 0.0, 1.0, "%d мин: x(0) — левый край" % minutes)
		assert_almost_eq(model.x_of(float(total), W), W, 1.0, "%d мин: x(конец) — правый край" % minutes)
		for k in 11:
			var t: float = float(total) * float(k) / 10.0
			assert_almost_eq(model.x_of(t, W), t / float(total) * W, 1.0, "%d мин: x линейна (t=%s)" % [minutes, t])


func test_req_hud_10_c2_y_max_is_125_percent_of_max_target_with_multiplier() -> void:
	var plan := _acc_full()
	var model := PlanChartModel.new(plan, FTP)
	assert_eq(model.max_target_w(), 240, "максимальная цель — IntervalsT on 120 %")
	assert_almost_eq(model.y_max(), 300.0, 0.01, "1.25 × 240")
	model.set_intensity(1.1)
	assert_almost_eq(model.y_max(), 1.25 * 264.0, 0.01, "1.25 × 240 × 1.1")
	# Высоты сегментов пересчитаны: верх SteadyState (220 Вт) от нового y_max.
	var top: float = float(_pieces_of(model, 1)[0]["top_start"])
	assert_almost_eq(top * H, 220.0 / 330.0 * H, 1.0, "высота ровного шага от нового y_max")


func test_req_hud_10_c2_multiplier_change_applied_by_next_sample() -> void:
	_start(_acc_full())
	var model := PlanChartModel.for_session(_session)
	assert_almost_eq(model.y_max(), 300.0, 0.01)
	_second(100)
	_session.set_intensity(0.8)
	_second(100)
	model.sync(_session)
	assert_almost_eq(model.y_max(), 1.25 * 192.0, 0.01, "y_max после смены множителя — к следующему сэмплу")
	var seg: Dictionary = model.segments()[1]
	assert_eq(int(seg["start_watts"]), 160, "цель шага пересчитана: 200 × 0.8")


func test_req_hud_10_c2_ftp_dash_at_y_of_ftp() -> void:
	var model := PlanChartModel.new(_acc_full(), FTP)
	var expected_y: float = H * (1.0 - float(FTP) / 300.0)
	assert_true(model.ftp_visible(), "FTP 200 внутри шкалы 0…300")
	assert_almost_eq(H * (1.0 - model.ftp_fraction()), expected_y, 1.0, "y(FTP) ±1 px")
	assert_almost_eq(model.y_of(float(FTP), H), expected_y, 1.0)
	assert_eq(model.ftp_w, FTP, "значение FTP профиля для подписи")


# ===========================================================================
# REQ-HUD-10 крит. 3 — рампы кусками по зонам
# ===========================================================================

func test_req_hud_10_c3_ramp_40_70_gives_two_pieces_z1_z2() -> void:
	var model := PlanChartModel.new(_plan([WorkoutStep.ramp_percent(300, 40.0, 70.0)]), FTP)
	var pieces := _pieces_of(model, 0)
	assert_eq(pieces.size(), 2, "40 → 70 % FTP: Z1 и Z2")
	assert_eq(str(pieces[0]["zone_token"]), "z1")
	assert_eq(str(pieces[1]["zone_token"]), "z2")
	# Точка пересечения 55 %: (55 − 40) / 30 × 300 = 150 с.
	assert_almost_eq(float(pieces[0]["end_sec"]), 150.0, 0.5)
	assert_almost_eq(float(pieces[1]["start_sec"]), 150.0, 0.5)
	assert_almost_eq(float(pieces[0]["start_sec"]), 0.0, 0.01)
	assert_almost_eq(float(pieces[1]["end_sec"]), 300.0, 0.01)


func test_req_hud_10_c3_ramp_top_is_slanted_with_heights_of_targets() -> void:
	var model := PlanChartModel.new(_plan([WorkoutStep.ramp_percent(300, 40.0, 70.0), WorkoutStep.percent(60, 100.0)]), FTP)
	var y_max: float = model.y_max()
	assert_almost_eq(y_max, 250.0, 0.01, "1.25 × 200")
	var ramp := _pieces_of(model, 0)
	assert_almost_eq(float(ramp[0]["top_start"]) * H, 80.0 / y_max * H, 1.0, "высота в начале = цель 80 Вт")
	assert_almost_eq(float(ramp[ramp.size() - 1]["top_end"]) * H, 140.0 / y_max * H, 1.0, "высота в конце = цель 140 Вт")
	assert_almost_eq(float(ramp[0]["top_end"]), float(ramp[1]["top_start"]), 0.0001, "верх рампы непрерывен на стыке кусков")
	var flat := _pieces_of(model, 1)
	assert_eq(flat.size(), 1, "ровный шаг — 1 кусок")
	assert_eq(float(flat[0]["top_start"]), float(flat[0]["top_end"]), "ровный шаг — горизонтальный верх")
	assert_almost_eq(float(flat[0]["top_start"]) * H, 200.0 / y_max * H, 1.0)


func test_req_hud_10_c3_acc_full_ramps_split_by_zones() -> void:
	var plan := _acc_full()
	var model := PlanChartModel.new(plan, FTP)
	var last: int = plan.steps.size() - 1
	# Ramp 50 → 90 %: Z1 (≤55), Z2 (≤75), Z3 (≤90) → 3 куска.
	var ramp_index: int = -1
	for i in plan.steps.size():
		if is_equal_approx(plan.steps[i].target_start, 50.0) and is_equal_approx(plan.steps[i].target_end, 90.0):
			ramp_index = i
	assert_ne(ramp_index, -1, "предусловие: рампа 50 → 90 найдена")
	var tokens: Array[String] = []
	for p in _pieces_of(model, ramp_index):
		tokens.append(str(p["zone_token"]))
	assert_eq(tokens, ["z1", "z2", "z3"] as Array[String], "рампа 50 → 90 %")
	# Cooldown 60 → 30 % (нисходящая): Z2, Z1.
	tokens.clear()
	for p in _pieces_of(model, last):
		tokens.append(str(p["zone_token"]))
	assert_eq(tokens, ["z2", "z1"] as Array[String], "заминка 60 → 30 %")


func test_req_hud_10_c3_descending_ramp_through_six_zones() -> void:
	var model := PlanChartModel.new(_plan([WorkoutStep.ramp_percent(600, 130.0, 50.0)]), FTP)
	var tokens: Array[String] = []
	for p in _pieces_of(model, 0):
		tokens.append(str(p["zone_token"]))
	assert_eq(tokens, ["z6", "z5", "z4", "z3", "z2", "z1"] as Array[String], "130 → 50 %: шесть зон, шесть кусков")


func test_req_hud_10_c3_ramp_within_one_zone_is_single_piece() -> void:
	var model := PlanChartModel.new(_plan([WorkoutStep.ramp_percent(120, 60.0, 70.0)]), FTP)
	assert_eq(_pieces_of(model, 0).size(), 1, "60 → 70 % целиком в Z2")


func test_req_hud_10_c3_pieces_cover_whole_plan_without_gaps() -> void:
	var model := PlanChartModel.new(_acc_full(), FTP)
	var prev_end: float = 0.0
	for p in model.pieces():
		assert_almost_eq(float(p["start_sec"]), prev_end, 0.001, "кусок %s начинается там, где кончился предыдущий" % p["step_index"])
		assert_gt(float(p["end_sec"]), float(p["start_sec"]))
		prev_end = float(p["end_sec"])
	assert_almost_eq(prev_end, 2280.0, 0.001, "куски покрывают план целиком (в т.ч. FreeRide/MaxEffort)")


func test_req_hud_10_c3_custom_profile_zones_used_for_split() -> void:
	var zones := PowerZones.custom(FTP, [60.0, 80.0] as Array[float])
	var model := PlanChartModel.new(_plan([WorkoutStep.ramp_percent(300, 40.0, 70.0)]), FTP, 1.0, zones)
	var pieces := _pieces_of(model, 0)
	assert_eq(pieces.size(), 2, "граница профиля 60 %")
	assert_almost_eq(float(pieces[0]["end_sec"]), 200.0, 0.5, "(60 − 40) / 30 × 300")


# ===========================================================================
# REQ-HUD-10 крит. 4 — шкала времени
# ===========================================================================

func test_req_hud_10_c4_examples_60_and_20_min() -> void:
	var l60 := TimeAxis.labels(3600)
	var t60: Array[String] = []
	for l in l60:
		t60.append(str(l["text"]))
	assert_eq(t60, ["0", "10", "20", "30", "40", "50", "1:00"] as Array[String], "60 мин: шаг 10, от часа — ч:мм")
	var t20: Array[String] = []
	for l in TimeAxis.labels(1200):
		t20.append(str(l["text"]))
	assert_eq(t20, ["0", "5", "10", "15", "20"] as Array[String], "20 мин: шаг 5")


func test_req_hud_10_c4_step_rule_brute_force() -> void:
	var series: Array[int] = [1, 2, 5, 10, 15, 30, 60]
	var bad: Array[String] = []
	for minutes in range(1, 541):
		var total: int = minutes * 60
		var expected: int = -1
		for step in series:
			if total / (step * 60) + 1 <= 10:
				expected = step
				break
		var labels := TimeAxis.labels(total)
		if expected < 0:
			continue
		var ok: bool = labels.size() <= 10 and labels.size() == total / (expected * 60) + 1
		for k in labels.size():
			if int(labels[k]["sec"]) != k * expected * 60:
				ok = false
		if not ok:
			bad.append("%d мин" % minutes)
	assert_eq(bad, [] as Array[String], "шаг — наименьший из ряда, при котором подписей ≤ 10 (включая 0)")


func test_req_hud_10_c4_labels_positions_and_hour_format() -> void:
	var labels := TimeAxis.labels(5400) # 90 мин → шаг 10
	assert_eq(labels.size(), 10)
	assert_eq(str(labels[6]["text"]), "1:00")
	assert_eq(str(labels[9]["text"]), "1:30")
	for l in labels:
		assert_almost_eq(float(l["fraction"]) * W, float(l["sec"]) / 5400.0 * W, 1.0, "подпись на x(t)")
	var acc := PlanChartModel.new(_acc_full(), FTP).time_labels()
	assert_eq(acc.size(), 8, "38 мин: шаг 5 → 0…35")
	assert_eq(str(acc[7]["text"]), "35")


# ===========================================================================
# REQ-HUD-10 крит. 5 — курсор и состояния
# ===========================================================================

func test_req_hud_10_c5_cursor_follows_elapsed_each_sample_and_stops_on_pause() -> void:
	_start(_acc_full())
	var model := PlanChartModel.for_session(_session)
	for t in range(1, 401):
		_second(150)
		model.sync(_session)
		var expected: float = float(_session.executor.elapsed_sec()) / 2280.0 * W
		if absf(model.cursor_fraction() * W - expected) > 1.0:
			fail_test("t=%d: курсор %.2f, ожидалось %.2f" % [t, model.cursor_fraction() * W, expected])
			return
	assert_almost_eq(model.cursor_fraction() * W, 400.0 / 2280.0 * W, 1.0, "курсор на 400 с")
	_session.pause()
	for i in 30:
		_session.tick(1.0)
	model.sync(_session)
	assert_almost_eq(model.cursor_fraction() * W, 400.0 / 2280.0 * W, 0.001, "на паузе курсор стоит")
	_session.resume()
	_second(150)
	model.sync(_session)
	assert_almost_eq(model.cursor_fraction() * W, 401.0 / 2280.0 * W, 1.0, "после паузы — дальше от того же места")


func test_req_hud_10_c5_done_and_upcoming_states_split_by_cursor() -> void:
	_start(_acc_full())
	var model := PlanChartModel.for_session(_session)
	for t in 400:
		_second(150)
	model.sync(_session)
	var cursor: float = model.cursor_sec()
	assert_almost_eq(cursor, 400.0, 0.001)
	var saw_done := false
	var saw_upcoming := false
	for p in model.pieces():
		var status: String = str(p["status"])
		if float(p["end_sec"]) <= cursor + 0.001:
			assert_eq(status, PlanChartModel.STATUS_DONE, "кусок [%s; %s] левее курсора — пройдено" % [p["start_sec"], p["end_sec"]])
			saw_done = true
		elif float(p["start_sec"]) >= cursor - 0.001:
			assert_eq(status, PlanChartModel.STATUS_UPCOMING, "кусок [%s; %s] правее курсора — предстоит" % [p["start_sec"], p["end_sec"]])
			saw_upcoming = true
		else:
			fail_test("кусок пересекает курсор: %s" % p)
	assert_true(saw_done and saw_upcoming)


func test_req_hud_10_c5_skipped_step_has_skipped_state() -> void:
	_start(_acc_full())
	var model := PlanChartModel.for_session(_session)
	for t in 320:
		_second(150) # шаг 1 (SteadyState) идёт с 300 с
	_session.skip_step()
	_second(150)
	model.sync(_session)
	assert_eq(str(model.segments()[1]["status"]), PlanChartModel.STATUS_SKIPPED, "пропущенный шаг — «пропущено»")
	for p in _pieces_of(model, 1):
		assert_eq(str(p["status"]), PlanChartModel.STATUS_SKIPPED)
	assert_eq(str(model.segments()[0]["status"]), PlanChartModel.STATUS_DONE, "разминка пройдена")


# ===========================================================================
# REQ-HUD-11 — линия факта мощности
# ===========================================================================

func test_req_hud_11_c1_stream_100_200_300_300_gives_smoothed_points() -> void:
	_start(_plan([WorkoutStep.percent(600, 70.0)]))
	var series := EffortSeries.new()
	for p in [100, 200, 300, 300]:
		_second(p)
	series.sync_from_stream(_session.samples)
	var pts := series.raw_points(EffortSeries.SERIES_POWER)
	assert_eq(pts.size(), 4, "одна точка на сэмпл")
	var values: Array[int] = []
	var times: Array[int] = []
	for v in pts:
		values.append(int(v.y))
		times.append(int(v.x))
	assert_eq(values, [100, 150, 200, 267] as Array[int], "сглаженная HUD-09")
	assert_eq(times, [1, 2, 3, 4] as Array[int], "t = 1..4")
	var model := PlanChartModel.for_session(_session)
	var runs := series.power_runs(0.0, 600.0, int(W), model.y_max())
	assert_eq(EffortSeries.point_count(runs), 4)


func test_req_hud_11_c2_new_point_each_sample_and_none_right_of_cursor() -> void:
	_start(_acc_full())
	var model := PlanChartModel.for_session(_session)
	var series := EffortSeries.new()
	for t in range(1, 301):
		_second(120 + t % 50)
		model.sync(_session)
		var added: int = series.sync_from_stream(_session.samples, model.time_shift_sec())
		if added != 1:
			fail_test("t=%d: добавлено %d точек вместо 1" % [t, added])
			return
		var times := _all_times(series.power_runs(0.0, 2280.0, int(W), model.y_max()))
		if times.is_empty() or times.max() > model.cursor_sec() + 0.001:
			fail_test("t=%d: точка правее курсора (%s > %s)" % [t, times.max() if not times.is_empty() else -1, model.cursor_sec()])
			return
		if absf(times.max() - model.cursor_sec()) > 1.0:
			fail_test("t=%d: последняя точка отстаёт от курсора больше чем на сэмпл" % t)
			return
	pass_test("300 сэмплов: точка на каждом, правее курсора нет")


func test_req_hud_11_c3_missing_power_breaks_line_not_zero() -> void:
	_start(_plan([WorkoutStep.percent(600, 70.0)]))
	var series := EffortSeries.new()
	for p in [150, 150, 150]:
		_second(p)
	_second(-1) # нет данных мощности
	_second(-1)
	for p in [150, 150, 150]:
		_second(p)
	series.sync_from_stream(_session.samples)
	var runs := series.power_runs(0.0, 600.0, int(W), 300.0)
	assert_eq(runs.size(), 2, "разрыв линии на «нет данных»")
	assert_false(_all_values(runs).has(0.0), "нет точек 0 Вт")
	assert_false(_all_times(runs).has(4.0) or _all_times(runs).has(5.0), "на t=4,5 точек нет")


func test_req_hud_11_c3_pause_adds_no_points_line_continues_from_same_x() -> void:
	_start(_plan([WorkoutStep.percent(600, 70.0)]))
	var series := EffortSeries.new()
	for i in 10:
		_second(150)
	_session.pause()
	for i in 20:
		_second(150)
	series.sync_from_stream(_session.samples)
	assert_eq(series.size(), 10, "пауза не добавляет точек")
	_session.resume()
	for i in 5:
		_second(150)
	series.sync_from_stream(_session.samples)
	var runs := series.power_runs(0.0, 600.0, int(W), 300.0)
	assert_eq(runs.size(), 1, "после возобновления линия продолжается без разрыва")
	assert_eq(_all_times(runs), [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0] as Array[float], "x продолжается с того же места")


func test_req_hud_11_c4_value_above_y_max_clamped_and_marked() -> void:
	var series := EffortSeries.new()
	for t in range(1, 6):
		series.push(t, 900, true, 0, false)
	var runs := series.power_runs(0.0, 10.0, int(W), 300.0)
	var vals := _all_values(runs)
	assert_eq(vals.max(), 300.0, "точка на верхней границе")
	var clipped: PackedByteArray = runs[0]["clipped"]
	assert_eq(clipped[clipped.size() - 1], 1, "помечена как обрезанная")
	var low := EffortSeries.new()
	low.push(1, 100, true, 0, false)
	assert_eq((low.power_runs(0.0, 10.0, int(W), 300.0)[0]["clipped"] as PackedByteArray)[0], 0, "в пределах шкалы — не обрезана")


func test_req_hud_11_c5_three_hours_on_1280_px_thinned_with_sprint_peak() -> void:
	var series := EffortSeries.new()
	var peak: int = 0
	for t in range(1, 10801):
		var p: int = 200 + (t * 37) % 21
		if t >= 5000 and t < 5030:
			p = 950
		series.push(t, p, true, 0, false)
	for v in series.raw_points(EffortSeries.SERIES_POWER):
		peak = maxi(peak, int(v.y))
	var runs := series.power_runs(0.0, 10800.0, 1280, 2000.0)
	var n := EffortSeries.point_count(runs)
	assert_lte(n, 2560, "не больше 2 × ширины")
	assert_gt(n, 1280, "прореживание не выбрасывает лишнего")
	assert_true(_all_values(runs).has(float(peak)), "пик 30-с спринта (%d Вт) среди точек" % peak)
	var times := _all_times(runs)
	for i in range(1, times.size()):
		if times[i] <= times[i - 1]:
			fail_test("точки не по возрастанию времени: %s, %s" % [times[i - 1], times[i]])
			return
	pass_test("%d точек" % n)


func test_req_hud_11_c5_bucket_keeps_min_too() -> void:
	var series := EffortSeries.new()
	for t in range(1, 10801):
		var p: int = 250
		if t >= 7000 and t < 7030:
			p = 0 # провал (реальный 0 Вт, не «нет данных»)
		series.push(t, p, true, 0, false)
	var low: float = INF
	for v in series.raw_points(EffortSeries.SERIES_POWER):
		low = minf(low, v.y)
	var runs := series.power_runs(0.0, 10800.0, 1280, 400.0)
	assert_true(_all_values(runs).has(low), "минимум корзины сохранён (%s)" % low)


# ===========================================================================
# REQ-HUD-12 — пульс
# ===========================================================================

func test_req_hud_12_c1_point_per_hr_sample_zero_and_missing_are_gaps() -> void:
	_start(_plan([WorkoutStep.percent(600, 70.0)]))
	for i in 3:
		_second(150, 120)
	_second(150, 0) # датчик прислал 0
	_second(150, -1) # пульса нет
	for i in 3:
		_second(150, 125)
	var series := EffortSeries.new(EffortSeries.MODE_PLAN, FTP, 190)
	series.sync_from_stream(_session.samples)
	var runs := series.hr_runs(0.0, 600.0, int(W))
	assert_eq(runs.size(), 2, "0 уд/мин и «нет данных» — разрыв")
	assert_eq(EffortSeries.point_count(runs), 6, "одна точка на сэмпл с пульсом")
	assert_false(_all_values(runs).has(0.0), "нет точки 0")
	# Ось X — общая с мощностью.
	assert_eq(_all_times(runs)[0], series.raw_points(EffortSeries.SERIES_POWER)[0].x)


func test_req_hud_12_c2_own_scale_50_to_max_hr_or_200_clamped() -> void:
	var with_max := EffortSeries.new(EffortSeries.MODE_PLAN, FTP, 180)
	assert_eq(with_max.hr_scale_min(), 50)
	assert_eq(with_max.hr_scale_max(), 180, "max_hr профиля")
	var without := EffortSeries.new(EffortSeries.MODE_PLAN, FTP, 0)
	assert_eq(without.hr_scale_max(), 200, "без max_hr — 200")
	with_max.push(1, 100, true, 40, true)
	with_max.push(2, 100, true, 120, true)
	with_max.push(3, 100, true, 195, true)
	var runs := with_max.hr_runs(0.0, 10.0, int(W))
	assert_eq(_all_values(runs), [50.0, 120.0, 180.0] as Array[float], "вне диапазона — на границе")
	assert_almost_eq(with_max.hr_fraction(50.0), 0.0, 0.0001)
	assert_almost_eq(with_max.hr_fraction(180.0), 1.0, 0.0001)
	assert_almost_eq(with_max.hr_fraction(115.0), 0.5, 0.0001)


func test_req_hud_12_c2_power_and_multiplier_do_not_move_hr_points() -> void:
	_start(_plan([WorkoutStep.percent(600, 70.0)]))
	var series := EffortSeries.new(EffortSeries.MODE_PLAN, FTP, 180)
	for i in 10:
		_second(150, 130 + i)
	series.sync_from_stream(_session.samples)
	var before := series.hr_runs(0.0, 600.0, int(W))
	var fractions_before: Array[float] = []
	for v in _all_values(before):
		fractions_before.append(series.hr_fraction(v))
	_session.set_intensity(1.3)
	for i in 5:
		_second(900, -1)
	series.sync_from_stream(_session.samples)
	var after := series.hr_runs(0.0, 10.0, int(W))
	var fractions_after: Array[float] = []
	for v in _all_values(after):
		fractions_after.append(series.hr_fraction(v))
	assert_eq(fractions_after, fractions_before, "положение точек пульса не зависит от мощности/множителя")


func test_req_hud_12_c5_labels_100_150_on_right_power_on_left() -> void:
	var series := EffortSeries.new(EffortSeries.MODE_PLAN, FTP, 185)
	series.push(1, 100, true, 120, true)
	assert_eq(series.hr_scale_labels(), [100, 150] as Array[int])
	assert_eq(str(series.style(EffortSeries.SERIES_HR)["scale_side"]), "right", "шкала пульса справа")
	assert_eq(str(series.style(EffortSeries.SERIES_POWER)["scale_side"]), "left", "мощность/FTP слева")
	assert_eq(str(series.style(EffortSeries.SERIES_HR)["label_token"]), "hud.hr_label")
	var low_max := EffortSeries.new(EffortSeries.MODE_PLAN, FTP, 140)
	low_max.push(1, 100, true, 120, true)
	assert_eq(low_max.hr_scale_labels(), [100] as Array[int], "150 вне шкалы 50…140 — не показывается")
	assert_true(series.hr_scale_visible(), "легенда «пульс» при данных")


func test_req_hud_12_c6_without_hr_sensor_empty_series_hidden_scale() -> void:
	_start(_plan([WorkoutStep.percent(600, 70.0)]))
	for i in 20:
		_second(150, -1)
	var series := EffortSeries.new(EffortSeries.MODE_PLAN, FTP, 180)
	series.sync_from_stream(_session.samples)
	assert_eq(series.hr_runs(0.0, 600.0, int(W)).size(), 0, "серия пустая")
	assert_false(series.hr_scale_visible(), "шкала и половина легенды скрыты")
	assert_eq(series.hr_scale_labels().size(), 0)
	assert_eq(EffortSeries.point_count(series.power_runs(0.0, 600.0, int(W), 300.0)), 20, "мощность есть, ошибок нет")


func test_req_hud_12_c7_hr_thinned_like_power_with_peak() -> void:
	var series := EffortSeries.new(EffortSeries.MODE_PLAN, FTP, 200)
	for t in range(1, 10801):
		var hr: int = 130 + (t * 13) % 7
		if t == 6000:
			hr = 191
		series.push(t, 200, true, hr, true)
	var runs := series.hr_runs(0.0, 10800.0, 1280)
	assert_lte(EffortSeries.point_count(runs), 2560)
	assert_true(_all_values(runs).has(191.0), "пик пульса сохранён")


func test_req_hud_12_c7_new_hr_point_by_next_sample() -> void:
	_start(_plan([WorkoutStep.percent(600, 70.0)]))
	var series := EffortSeries.new(EffortSeries.MODE_PLAN, FTP, 180)
	for t in range(1, 21):
		_second(150, 100 + t)
		series.sync_from_stream(_session.samples)
		var pts := series.raw_points(EffortSeries.SERIES_HR)
		if pts.size() != t or int(pts[pts.size() - 1].y) != 100 + t:
			fail_test("t=%d: точка пульса не появилась к сэмплу" % t)
			return
	pass_test("точка пульса на каждом сэмпле")


# ===========================================================================
# REQ-FRD-06 крит. 4 — окно свободной езды (модель)
# ===========================================================================

func test_req_frd_06_c4_first_30_min_axis_0_30_line_grows_left_to_right() -> void:
	var s := EffortSeries.sliding_window(FTP)
	for t in range(1, 601):
		s.push(t, 200, true, 120, true)
	assert_eq(s.visible_range(), Vector2(0.0, 1800.0), "первые 30 мин — шкала 0…30 мин")
	assert_almost_eq(s.window_x_of(600.0, W), 600.0 / 1800.0 * W, 1.0, "линия растёт слева направо")
	assert_almost_eq(s.window_x_of(0.0, W), 0.0, 0.01)


func test_req_frd_06_c4_after_30_min_sliding_window_now_at_right_edge() -> void:
	var s := EffortSeries.sliding_window(FTP)
	for t in range(1, 2701):
		s.push(t, 200, true, 120, true)
	assert_eq(s.visible_range(), Vector2(900.0, 2700.0), "последние 30 мин")
	assert_almost_eq(s.window_x_of(2700.0, W), W, 1.0, "текущий момент у правого края")
	assert_almost_eq(s.window_x_of(900.0, W), 0.0, 1.0)
	var r := s.visible_range()
	var runs := s.power_runs(r.x, r.y, 600, s.power_y_max())
	assert_lte(EffortSeries.point_count(runs), 1200, "прореживание HUD-11.5 в окне")
	assert_gte(_all_times(runs).min(), 900.0, "старше окна точек нет")


func test_req_frd_06_c4_y_max_floor_is_1_5_ftp_and_rounds_up_to_50() -> void:
	var s := EffortSeries.sliding_window(FTP)
	s.push(1, 150, true, 0, false)
	assert_almost_eq(s.power_y_max(), 300.0, 0.01, "max(1.5 × 200, …)")
	for t in range(2, 5):
		s.push(t, 333, true, 0, false)
	# Сглаженная на t=4: 333 → y_max = ⌈333 / 50⌉ × 50 = 350.
	assert_almost_eq(s.power_y_max(), 350.0, 0.01, "округление вверх до 50 Вт")


func test_req_frd_06_c4_y_max_grows_by_next_sample() -> void:
	var s := EffortSeries.sliding_window(FTP)
	for t in range(1, 101):
		s.push(t, 200, true, 0, false)
	assert_almost_eq(s.power_y_max(), 300.0, 0.01)
	s.push(101, 700, true, 0, false) # сглаженная (200+200+700)/3 = 367
	assert_almost_eq(s.power_y_max(), 400.0, 0.01, "рост — на этом же сэмпле")


func test_req_frd_06_c4_y_max_shrinks_not_more_than_once_per_60_s() -> void:
	var s := EffortSeries.sliding_window(FTP)
	var history: Array[float] = []
	var times: Array[int] = []
	for t in range(1, 2101):
		var p: int = 200
		if t >= 100 and t < 103:
			p = 600 # сглаженная до 600 → y_max 600
		elif t >= 130 and t < 133:
			p = 450 # → 450
		s.push(t, p, true, 0, false)
		if history.is_empty() or not is_equal_approx(history[history.size() - 1], s.power_y_max()):
			history.append(s.power_y_max())
			times.append(t)
	# Уменьшения: моменты, когда y_max падал.
	var shrinks: Array[int] = []
	for i in range(1, history.size()):
		if history[i] < history[i - 1]:
			shrinks.append(times[i])
	assert_gte(shrinks.size(), 2, "после выхода спринтов из окна шкала уменьшается (факт: %s → %s)" % [str(times), str(history)])
	for i in range(1, shrinks.size()):
		assert_gte(shrinks[i] - shrinks[i - 1], 60, "уменьшения не чаще раза в 60 с: %s" % str(shrinks))
	assert_almost_eq(s.power_y_max(), 300.0, 0.01, "в итоге — 1.5 × FTP")
