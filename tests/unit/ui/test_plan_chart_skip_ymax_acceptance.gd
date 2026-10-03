extends GutTest
## Приёмка T-094 (tester): REQ-HUD-10 крит. 2 (y_max = max(1.25 × макс. цели с множителем,
## 1.1 × FTP), у плана без целей — 1.25 × FTP; пунктир FTP в поле), крит. 5 и REQ-HUD-11
## крит. 1, 2 (курсор и линии факта по позиции в плане после пропуска шага; разрыв над
## пропущенным остатком; результат не зависит от частоты синхронизации — решение У-1).
##
## Отличия от тестов разработчика: примеры критерия на планах из ZWO (рампы, FreeRide,
## MaxEffort); множитель меняется в идущей `WorkoutSession` и проверяется на следующем
## сэмпле; пример HUD-10.5 (3 × 300 с, 900 px) — через `HudChart` в дереве сцены, по
## пикселям; пропуск в середине секунды и на паузе — точка факта каждый сэмпл совпадает с
## курсором (нет точек правее курсора); синхронизация каждый сэмпл / раз в 7 с / один раз
## в конце дают одинаковые серии.

const FTP: int = 250


func _zwo(body: String) -> Workout:
	var xml := "<workout_file><name>T094</name><sportType>bike</sportType><workout>%s</workout></workout_file>" % body
	var res: ParseResult = ZwoParser.parse(xml)
	assert_not_null(res.workout, "ZWO разобран")
	return res.workout


func _session(w: Workout, ftp: int = FTP) -> Dictionary:
	var ft := FakeTrainer.new(5)
	ft.connect_delay_sec = 0.0
	ft.set_heart_rate(130)
	ft.connect_device("fake")
	var s := WorkoutSession.new(w, ft, ftp)
	return {"ft": ft, "s": s}


# ---------------------------------------------------------------------------
# REQ-HUD-10 крит. 2 — y_max
# ---------------------------------------------------------------------------

func test_req_hud_10_c2_examples_at_ftp_250_from_zwo_plans() -> void:
	# Максимальная цель 150 Вт (60 % FTP) — в рампе (конец), остальное ниже.
	var low := _zwo('<Warmup Duration="300" PowerLow="0.40" PowerHigh="0.60"/><SteadyState Duration="600" Power="0.55"/>')
	assert_almost_eq(PlanChartModel.new(low, FTP).y_max(), 275.0, 0.5, "макс. цель 150 Вт → 275 Вт (1.1 × FTP)")
	# 300 Вт (120 %) в начале рампы-заминки.
	var high := _zwo('<SteadyState Duration="300" Power="0.80"/><Cooldown Duration="300" PowerLow="1.20" PowerHigh="0.50"/>')
	assert_almost_eq(PlanChartModel.new(high, FTP).y_max(), 375.0, 0.5, "макс. цель 300 Вт → 375 Вт")
	# Без целей: FreeRide и MaxEffort.
	var free := _zwo('<FreeRide Duration="600"/><MaxEffort Duration="30"/><FreeRide Duration="300"/>')
	assert_almost_eq(PlanChartModel.new(free, FTP).y_max(), 312.5, 0.5, "план без целей → 312.5 Вт")
	# Граница: 1.25 × 220 = 275 = 1.1 × 250 — обе ветки дают 275.
	var edge := _zwo('<SteadyState Duration="300" Power="0.88"/>')
	assert_almost_eq(PlanChartModel.new(edge, FTP).y_max(), 275.0, 0.5, "220 Вт → 275 Вт")


func test_req_hud_10_c2_ftp_dash_always_inside_field_for_any_plan() -> void:
	for pct in [0.30, 0.50, 0.70, 0.88, 0.90, 1.00, 1.50]:
		var w := _zwo('<SteadyState Duration="600" Power="%.2f"/>' % pct)
		var m := PlanChartModel.new(w, FTP)
		assert_true(m.ftp_visible(), "%.0f %%: пунктир FTP виден" % (pct * 100.0))
		assert_lte(m.ftp_fraction(), 1.0 / 1.1 + 1e-6, "%.0f %%: FTP на высоте ≤ 1/1.1 поля" % (pct * 100.0))
		assert_almost_eq(m.y_of(float(FTP), 200.0), 200.0 * (1.0 - float(FTP) / m.y_max()), 1.0, "y(FTP) ±1 px")


func test_req_hud_10_c2_multiplier_change_in_running_session_updates_y_max_by_next_sample() -> void:
	var w := _zwo('<SteadyState Duration="600" Power="1.20"/><SteadyState Duration="600" Power="0.60"/>')
	var ctx := _session(w)
	var s: WorkoutSession = ctx["s"]
	var m := PlanChartModel.for_session(s)
	s.start()
	for i in 10:
		s.tick(1.0)
	m.sync(s)
	assert_almost_eq(m.y_max(), 375.0, 0.5, "×1.0: 300 Вт → 375")
	s.set_intensity(1.2)
	s.tick(1.0)
	m.sync(s)
	assert_almost_eq(m.y_max(), 450.0, 0.5, "×1.2: 360 Вт → 450 к следующему сэмплу")
	s.set_intensity(0.5)
	s.tick(1.0)
	m.sync(s)
	assert_almost_eq(m.y_max(), 275.0, 0.5, "×0.5: 150 Вт → нижняя граница 1.1 × FTP = 275")
	var top: float = 0.0
	for p in m.pieces():
		top = maxf(top, maxf(float(p["top_start"]), float(p["top_end"])))
	assert_almost_eq(top, 150.0 / 275.0, 0.005, "высота сегментов пересчитана от нового y_max")
	s.stop()


# ---------------------------------------------------------------------------
# REQ-HUD-10 крит. 5, REQ-HUD-11 крит. 1, 2 — пропуск шага
# ---------------------------------------------------------------------------

func _three_by_300() -> Workout:
	return _zwo('<SteadyState Duration="300" Power="0.60"/><SteadyState Duration="300" Power="0.80"/><SteadyState Duration="300" Power="0.70"/>')


func test_req_hud_10_c5_example_3x300_900px_via_hud_chart() -> void:
	var ctx := _session(_three_by_300())
	var s: WorkoutSession = ctx["s"]
	var chart := HudChart.new()
	chart.size = Vector2(900.0, 200.0)
	add_child_autofree(chart)
	var m := PlanChartModel.for_session(s)
	var series := EffortSeries.new(EffortSeries.MODE_PLAN, FTP)
	chart.set_plan(m, series)
	s.start()
	for i in 100:
		s.tick(1.0)
		chart.sync(s)
	s.skip_step()
	for i in 50:
		s.tick(1.0)
		chart.sync(s)
	var field: Rect2 = chart.field_rect()
	var px: float = 900.0 / field.size.x  # перевод в «пиксели примера» при другой ширине поля
	assert_almost_eq((chart.cursor_x() - field.position.x) * px, 350.0, 1.0, "через 50 с после пропуска курсор на 350 px")
	var pts := series.raw_points(EffortSeries.SERIES_POWER)
	var inside: Array = []
	for p in pts:
		var x: float = m.x_of(p.x, 900.0)
		if x > 100.0 + 1e-6 and x < 300.0 - 1e-6:
			inside.append(p)
	assert_eq(inside, [], "над пропущенным остатком (100…300 px) точек нет")
	var runs := series.power_runs(0.0, float(m.total_sec()), 900, m.y_max())
	for r in runs:
		var rp: PackedVector2Array = r["points"]
		for k in range(1, rp.size()):
			var x0: float = m.x_of(rp[k - 1].x, 900.0)
			var x1: float = m.x_of(rp[k].x, 900.0)
			assert_false(x0 <= 100.0 and x1 >= 300.0, "нет отрезка через пропуск: %.0f → %.0f px" % [x0, x1])
	assert_eq(pts[pts.size() - 1].x, m.cursor_sec(), "последняя точка — на курсоре")
	s.stop()


func _ride_with_skips(skip_at: Array[float], pause_skip: bool, sync_every: int) -> Dictionary:
	var ctx := _session(_three_by_300())
	var s: WorkoutSession = ctx["s"]
	var m := PlanChartModel.for_session(s)
	var series := EffortSeries.new(EffortSeries.MODE_PLAN, FTP)
	var right_of_cursor: Array[String] = []
	var lag: Array[String] = []
	s.start()
	var t: float = 0.0
	var sec: int = 0
	var next_skip: int = 0
	while t < 500.0 - 1e-6:
		if next_skip < skip_at.size() and t >= skip_at[next_skip] - 1e-6:
			if pause_skip:
				s.pause()
				s.tick(3.0)
				s.skip_step()
				s.tick(2.0)
				s.resume()
			else:
				s.skip_step()
			next_skip += 1
		s.tick(0.1)
		t += 0.1
		if s.executor.elapsed_sec() != sec:
			sec = s.executor.elapsed_sec()
			if sync_every > 0 and sec % sync_every == 0:
				m.sync(s)
				series.sync_from_plan(s.samples, m)
				var last: float = float(series.last_time_sec())
				if last > m.cursor_sec() + 1e-6 and right_of_cursor.size() < 5:
					right_of_cursor.append("сэмпл %d: точка %.1f > курсора %.1f" % [sec, last, m.cursor_sec()])
				if m.cursor_sec() - last >= 1.0 and lag.size() < 5:
					lag.append("сэмпл %d: точка %.1f отстаёт от курсора %.1f" % [sec, last, m.cursor_sec()])
	m.sync(s)
	series.sync_from_plan(s.samples, m)
	s.stop()
	return {"series": series, "model": m, "right": right_of_cursor, "lag": lag}


func test_req_hud_11_c2_fractional_time_skip_points_never_right_of_cursor_and_on_cursor() -> void:
	for skip_t in [100.3, 100.7, 42.95]:
		var r := _ride_with_skips([skip_t] as Array[float], false, 1)
		assert_eq(r["right"], [] as Array[String], "пропуск на %.2f с: точек правее курсора нет" % skip_t)
		assert_eq(r["lag"], [] as Array[String], "пропуск на %.2f с: точка факта — в позиции курсора" % skip_t)


func test_req_hud_10_c5_skip_on_pause_keeps_points_on_cursor() -> void:
	var r := _ride_with_skips([120.0] as Array[float], true, 1)
	assert_eq(r["right"], [] as Array[String], "пропуск на паузе: точек правее курсора нет")
	assert_eq(r["lag"], [] as Array[String], "пропуск на паузе: точка в позиции курсора")
	var m: PlanChartModel = r["model"]
	for p in (r["series"] as EffortSeries).raw_points(EffortSeries.SERIES_POWER):
		assert_false(p.x > 120.0 + 1e-6 and p.x < 300.0 - 1e-6, "над пропущенным остатком нет точки t=%.0f" % p.x)
	assert_almost_eq(m.cursor_sec(), 300.0 + (500.0 - 120.0), 1.0, "курсор: начало шага 2 + время в нём")


func test_req_hud_11_c1_series_independent_of_sync_rate_with_two_skips() -> void:
	var skips: Array[float] = [60.0, 160.0]
	var every := _ride_with_skips(skips, false, 1)
	var seven := _ride_with_skips(skips, false, 7)
	var once := _ride_with_skips(skips, false, 0)
	var a := (every["series"] as EffortSeries).raw_points(EffortSeries.SERIES_POWER)
	var b := (seven["series"] as EffortSeries).raw_points(EffortSeries.SERIES_POWER)
	var c := (once["series"] as EffortSeries).raw_points(EffortSeries.SERIES_POWER)
	assert_eq(a.size(), b.size())
	assert_eq(a.size(), c.size())
	assert_eq(a, b, "каждый сэмпл = раз в 7 с")
	assert_eq(a, c, "каждый сэмпл = один раз в конце")
	var ha := (every["series"] as EffortSeries).raw_points(EffortSeries.SERIES_HR)
	var hc := (once["series"] as EffortSeries).raw_points(EffortSeries.SERIES_HR)
	assert_eq(ha, hc, "пульс — так же")
	# Пропуски: шаг 0 на 60 с (остаток 240 с), шаг 1 на 160 с (позиция 400, остаток 200 с).
	for p in a:
		assert_false(p.x > 60.0 + 1e-6 and p.x < 300.0 - 1e-6, "нет точек в 60…300: %.0f" % p.x)
		assert_false(p.x > 400.0 + 1e-6 and p.x < 600.0 - 1e-6, "нет точек в 400…600: %.0f" % p.x)
	assert_eq(int(a[a.size() - 1].x), int((every["model"] as PlanChartModel).cursor_sec()), "последняя точка на курсоре")
