extends GutTest
## Рисовальщик нижнего графика HUD и превью плана (T-071): REQ-HUD-10 крит. 6, 7,
## REQ-HUD-11 крит. 6, 7, REQ-HUD-12 крит. 3–5, REQ-UIX-03 крит. 4; `docs/game/hud.md` п. 7, 11.
## Проверки — по журналу вызовов отрисовки (`HudChart.debug_draw_commands()`), без холста.

const FTP: int = 200
const WIDTH: float = 1100.0
const HEIGHT: float = 140.0

var _trainer: FakeTrainer
var _session: WorkoutSession


func before_each() -> void:
	_trainer = FakeTrainer.new(7)
	_trainer.connect_delay_sec = 0.0
	_trainer.power_noise_w = 0.0
	_trainer.power_tau_sec = 0.01
	_trainer.cadence_noise_rpm = 0.0
	_trainer.connect_device("chart")


func _steps(arr: Array) -> Array[WorkoutStep]:
	var out: Array[WorkoutStep] = []
	for s in arr:
		out.append(s)
	return out


## 10 мин разминка 40 → 70 %, 5 мин 100 %, 2 мин свободно, 3 мин 120 % (граница Z5 — Z5).
func _plan() -> Workout:
	return Workout.make("chart", _steps([
		WorkoutStep.ramp_percent(600, 40.0, 70.0, WorkoutStep.StepKind.WARMUP),
		WorkoutStep.percent(300, 100.0),
		WorkoutStep.free_ride(120),
		WorkoutStep.percent(180, 120.0),
	]))


func _chart(chart: HudChart = null) -> HudChart:
	var c: HudChart = chart if chart != null else HudChart.new()
	c.size = Vector2(WIDTH, HEIGHT)
	autofree(c)
	return c


## График, привязанный к сессии, после `seconds` секунд езды (пульс по желанию).
func _running_chart(seconds: int, hr_bpm: int = 0) -> HudChart:
	if hr_bpm > 0:
		_trainer.set_heart_rate(hr_bpm)
	_session = WorkoutSession.new(_plan(), _trainer, FTP)
	var chart := _chart()
	chart.set_plan(PlanChartModel.for_session(_session), EffortSeries.new(EffortSeries.MODE_PLAN, FTP, 190))
	_session.start()
	for i in seconds:
		_session.tick(1.0)
	chart.sync(_session)
	return chart


static func _tagged(log: Array[Dictionary], tag: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in log:
		if e["tag"] == tag:
			out.append(e)
	return out


static func _first(log: Array[Dictionary], tag: String) -> int:
	for i in log.size():
		if log[i]["tag"] == tag:
			return i
	return -1


static func _last(log: Array[Dictionary], tag: String) -> int:
	for i in range(log.size() - 1, -1, -1):
		if log[i]["tag"] == tag:
			return i
	return -1


static func _rgb_eq(a: Color, b: Color) -> bool:
	return is_equal_approx(a.r, b.r) and is_equal_approx(a.g, b.g) and is_equal_approx(a.b, b.b)


# ---------------------------------------------------------------------------
# REQ-HUD-10 крит. 6 — цвет сегментов, «свободно», прозрачность
# ---------------------------------------------------------------------------

func test_segment_colors_match_zone_tokens_and_free_is_neutral() -> void:
	var chart := _chart()
	chart.set_plan(PlanChartModel.new(_plan(), FTP))
	var segs := _tagged(chart.debug_draw_commands(), HudChart.TAG_SEGMENT)
	# Рампа 40 → 70 % — два куска (Z1, Z2), ровный шаг, свободно, 120 %.
	assert_eq(segs.size(), 5)
	var tokens: Array[String] = []
	for e in segs:
		var meta: Dictionary = e["meta"]
		tokens.append(str(meta["token"]))
		if meta["free"]:
			assert_eq(str(meta["token"]), PlanChartModel.FREE_TOKEN, "«свободно» — токен hud.free")
			assert_true(_rgb_eq(e["color"], UiTokens.HUD_FREE), "«свободно» — нейтральный цвет, не зона")
			assert_almost_eq((e["color"] as Color).a, HudChart.FREE_ALPHA, 1e-6)
		else:
			assert_true(_rgb_eq(e["color"], ZonePalette.color(str(meta["token"]))), "цвет = палитра зоны %s" % meta["token"])
			assert_almost_eq((e["color"] as Color).a, HudChart.UPCOMING_ALPHA, 1e-6, "предстоит — альфа 1.0")
	assert_eq(tokens, ["z1", "z2", "z4", "hud.free", "z5"] as Array[String])


func test_free_segment_is_30_percent_high_hatched_and_without_gap_in_x() -> void:
	var chart := _chart()
	var model := PlanChartModel.new(_plan(), FTP)
	chart.set_plan(model)
	var log := chart.debug_draw_commands()
	var f := chart.field_rect()
	var free: Dictionary = {}
	for e in _tagged(log, HudChart.TAG_SEGMENT):
		if e["meta"]["free"]:
			free = e
	assert_false(free.is_empty())
	var meta: Dictionary = free["meta"]
	assert_almost_eq(float(meta["base"]) - float(meta["y0"]), 0.30 * f.size.y, 1.0, "высота 30 % поля")
	# Покрывает весь интервал шага (900…1020 с) за вычетом зазора.
	assert_almost_eq(float(meta["x0"]), chart.x_at(900.0), 0.5 + 1e-3)
	assert_almost_eq(float(meta["x1"]), chart.x_at(1020.0), 0.5 + 1e-3)
	var hatch := _tagged(log, HudChart.TAG_HATCH)
	assert_eq(hatch.size(), 1, "штриховка только у «свободно»")
	assert_true(_rgb_eq(hatch[0]["color"], UiTokens.HUD_FREE_HATCH))
	assert_almost_eq((hatch[0]["color"] as Color).a, 0.18, 1e-6)
	# Все штрихи внутри куска.
	for pt: Vector2 in hatch[0]["points"]:
		assert_between(pt.x, float(meta["x0"]) - 0.01, float(meta["x1"]) + 0.01)
		assert_between(pt.y, float(meta["y0"]) - 0.01, float(meta["base"]) + 0.01)


func test_done_segments_are_ghosted_with_zone_edge() -> void:
	var chart := _running_chart(650)
	var log := chart.debug_draw_commands()
	var seen_done := false
	var seen_upcoming := false
	for e in _tagged(log, HudChart.TAG_SEGMENT):
		var meta: Dictionary = e["meta"]
		var alpha: float = (e["color"] as Color).a
		if meta["status"] == PlanChartModel.STATUS_DONE:
			seen_done = true
			assert_almost_eq(alpha, HudChart.DONE_ALPHA, 1e-6, "пройдено — альфа 0.30")
		elif not meta["free"]:
			seen_upcoming = true
			assert_almost_eq(alpha, 1.0, 1e-6)
	assert_true(seen_done and seen_upcoming)
	# «Призрак»: линия 2 lp цвета зоны по верху у пройденных шагов (разминка — 2 куска).
	var edges := _tagged(log, HudChart.TAG_SEGMENT_EDGE)
	assert_eq(edges.size(), 2)
	for e in edges:
		assert_eq(float(e["width"]), 2.0)
		assert_true(_rgb_eq(e["color"], ZonePalette.color(str(e["meta"]["token"]))))
	# Текущий шаг: белая линия по верху, кусок слева от курсора — пройдено, справа — предстоит.
	var cur := _tagged(log, HudChart.TAG_CURRENT_EDGE)
	assert_eq(cur.size(), 1)
	assert_true(_rgb_eq(cur[0]["color"], UiTokens.HUD_TEXT))
	assert_almost_eq((cur[0]["color"] as Color).a, 0.95, 1e-6)
	var current: Array[Dictionary] = []
	for e in _tagged(log, HudChart.TAG_SEGMENT):
		if e["meta"]["current"]:
			current.append(e)
	assert_eq(current.size(), 2)
	assert_eq(str(current[0]["meta"]["status"]), PlanChartModel.STATUS_DONE)
	assert_eq(str(current[1]["meta"]["status"]), PlanChartModel.STATUS_UPCOMING)
	assert_almost_eq(float(current[0]["meta"]["x1"]), chart.cursor_x(), 1.0)


func test_skipped_step_is_ghosted_and_hatched_with_ink() -> void:
	var chart := _running_chart(700)
	_session.skip_step()
	for i in 10:
		_session.tick(1.0)
	chart.sync(_session)
	var log := chart.debug_draw_commands()
	var skipped := 0
	for e in _tagged(log, HudChart.TAG_SEGMENT):
		if e["meta"]["status"] == PlanChartModel.STATUS_SKIPPED:
			skipped += 1
			assert_almost_eq((e["color"] as Color).a, HudChart.DONE_ALPHA, 1e-6)
	assert_eq(skipped, 1)
	var ink_hatch := 0
	for e in _tagged(log, HudChart.TAG_HATCH):
		if _rgb_eq(e["color"], UiTokens.HUD_INK):
			ink_hatch += 1
			assert_almost_eq((e["color"] as Color).a, 0.6, 1e-6)
	assert_eq(ink_hatch, 1)
	# Курсор — в позиции плана: начало следующего шага (900 с) + 10 с.
	assert_almost_eq(chart.cursor_x(), chart.x_at(910.0), 1.0)


# ---------------------------------------------------------------------------
# REQ-HUD-10 крит. 7 — зазор и скругление
# ---------------------------------------------------------------------------

func test_gap_between_steps_and_rounded_top_corners() -> void:
	var chart := _chart()
	chart.set_plan(PlanChartModel.new(_plan(), FTP))
	var segs := _tagged(chart.debug_draw_commands(), HudChart.TAG_SEGMENT)
	# Рампа (куски 0, 1) → ровный шаг (2): зазор 1 lp ±0.5.
	assert_almost_eq(float(segs[2]["meta"]["x0"]) - float(segs[1]["meta"]["x1"]), 1.0, 0.5)
	# Между кусками одной рампы зазора нет.
	assert_almost_eq(float(segs[1]["meta"]["x0"]), float(segs[0]["meta"]["x1"]), 1e-3)
	# Ровный шаг: радиус min(5, ширина / 2), верхние углы скруглены (дуги), нижние прямые.
	var flat: Dictionary = segs[2]
	var w: float = float(flat["meta"]["x1"]) - float(flat["meta"]["x0"])
	assert_almost_eq(float(flat["meta"]["radius"]), minf(5.0, w / 2.0), 1e-3)
	var pts: PackedVector2Array = flat["points"]
	assert_gt(pts.size(), 4, "скруглённый верх — больше четырёх вершин")
	var base: float = float(flat["meta"]["base"])
	var top: float = float(flat["meta"]["y0"])
	assert_eq(pts[0], Vector2(float(flat["meta"]["x0"]), base), "нижний левый угол прямой")
	assert_eq(pts[pts.size() - 1], Vector2(float(flat["meta"]["x1"]), base), "нижний правый угол прямой")
	# Верхний левый угол срезан дугой: в точке (x0, top) вершины нет.
	for pt in pts:
		assert_false(pt.is_equal_approx(Vector2(float(flat["meta"]["x0"]), top)))
	# Рампа — наклонный верх по целям (80 → 110 Вт на первом куске).
	var ramp: Dictionary = segs[0]
	assert_almost_eq(float(ramp["meta"]["y0"]), chart.y_power(80.0), 1.0)
	assert_almost_eq(float(ramp["meta"]["y1"]), chart.y_power(110.0), 1.0)


func test_narrow_step_radius_limited_by_half_width() -> void:
	var plan := Workout.make("n", _steps([WorkoutStep.percent(3600, 60.0), WorkoutStep.percent(20, 100.0),
			WorkoutStep.percent(3600, 60.0)]))
	var chart := _chart()
	chart.set_plan(PlanChartModel.new(plan, FTP))
	var segs := _tagged(chart.debug_draw_commands(), HudChart.TAG_SEGMENT)
	var w: float = float(segs[1]["meta"]["x1"]) - float(segs[1]["meta"]["x0"])
	assert_lt(w, 10.0)
	assert_almost_eq(float(segs[1]["meta"]["radius"]), w / 2.0, 1e-3)


# ---------------------------------------------------------------------------
# REQ-HUD-11 крит. 6, 7; REQ-HUD-12 крит. 3, 4 — порядок, линии, обводка
# ---------------------------------------------------------------------------

func test_draw_order_plate_ftp_segments_hr_power_cursor() -> void:
	var chart := _running_chart(650, 140)
	var log := chart.debug_draw_commands()
	var order: Array[String] = [HudChart.TAG_BACKGROUND, HudChart.TAG_FTP, HudChart.TAG_SEGMENT,
		HudChart.TAG_HR_OUTLINE, HudChart.TAG_HR_LINE, HudChart.TAG_POWER_OUTLINE, HudChart.TAG_POWER_LINE,
		HudChart.TAG_CURSOR]
	for tag in order:
		assert_gt(_first(log, tag), -1, "есть вызов %s" % tag)
	for k in order.size() - 1:
		assert_lt(_last(log, order[k]), _first(log, order[k + 1]), "%s раньше %s" % [order[k], order[k + 1]])


func test_hr_is_polyline_only_without_fill() -> void:
	var chart := _running_chart(300, 140)
	var log := chart.debug_draw_commands()
	var hr := _tagged(log, HudChart.TAG_HR_LINE) + _tagged(log, HudChart.TAG_HR_OUTLINE)
	assert_gt(hr.size(), 0)
	for e in hr:
		assert_eq(str(e["op"]), "polyline", "у пульса только полилиния")
		assert_false(e["filled"], "ни одного залитого полигона под пульсом")
		assert_eq(str(e["meta"]["style"]), EffortSeries.STYLE_LINE)
	# Других залитых фигур с цветом пульса тоже нет.
	for e in log:
		if e["filled"]:
			assert_false(_rgb_eq(e["color"], UiTokens.HUD_HR_LINE), "залитая фигура цвета пульса: %s" % e["tag"])


func test_hr_color_hue_and_saturation() -> void:
	var chart := _running_chart(120, 140)
	var lines := _tagged(chart.debug_draw_commands(), HudChart.TAG_HR_LINE)
	assert_gt(lines.size(), 0)
	for e in lines:
		var c: Color = e["color"]
		assert_true(_rgb_eq(c, UiTokens.HUD_HR_LINE), "токен hud.hr_line")
		var hue: float = c.h * 360.0
		assert_true(hue >= 345.0 or hue <= 15.0, "тон %.1f° в 345–15°" % hue)
		assert_gte(c.s, 0.6, "насыщенность ≥ 0.6")
		assert_eq(float(e["width"]), 2.0)


func test_lines_have_ink_outline_drawn_first() -> void:
	var chart := _running_chart(200, 140)
	var log := chart.debug_draw_commands()
	for pair in [[HudChart.TAG_HR_OUTLINE, HudChart.TAG_HR_LINE], [HudChart.TAG_POWER_OUTLINE, HudChart.TAG_POWER_LINE]]:
		var outlines := _tagged(log, pair[0])
		var lines := _tagged(log, pair[1])
		assert_eq(outlines.size(), lines.size())
		assert_lt(_last(log, pair[0]), _first(log, pair[1]), "обводка раньше линии")
		for e in outlines:
			assert_true(_rgb_eq(e["color"], UiTokens.HUD_INK))
			assert_almost_eq((e["color"] as Color).a, 0.9, 1e-6)
			assert_eq(float(e["width"]), 5.0)
	for e in _tagged(log, HudChart.TAG_POWER_LINE):
		assert_true(_rgb_eq(e["color"], UiTokens.HUD_POWER_LINE))
		assert_eq(float(e["width"]), 2.0)


func test_fact_lines_stay_left_of_cursor_and_inside_field() -> void:
	var chart := _running_chart(650, 140)
	var log := chart.debug_draw_commands()
	var f := chart.field_rect()
	for tag in [HudChart.TAG_POWER_LINE, HudChart.TAG_HR_LINE]:
		for e in _tagged(log, tag):
			for pt: Vector2 in e["points"]:
				assert_lte(pt.x, chart.cursor_x() + 1.0, "точка правее курсора")
				assert_between(pt.y, f.position.y - 1e-3, f.end.y + 1e-3)


func test_scales_on_opposite_sides_and_hidden_without_hr() -> void:
	var chart := _running_chart(120, 140)
	chart.legend_power_key = "hud.chart.legend.power"
	chart.legend_hr_key = "hud.chart.legend.hr"
	var log := chart.debug_draw_commands()
	var f := chart.field_rect()
	var ftp_labels := _tagged(log, HudChart.TAG_FTP_LABEL)
	assert_eq(ftp_labels.size(), 2, "«FTP» и значение")
	assert_eq(str(ftp_labels[1]["meta"]["text"]), str(FTP))
	for e in ftp_labels:
		assert_lt((e["points"] as PackedVector2Array)[0].x, f.position.x, "подписи мощности слева")
	var hr_labels := _tagged(log, HudChart.TAG_HR_LABEL)
	assert_eq(hr_labels.size(), 2, "100 и 150")
	for e in hr_labels:
		assert_gt((e["points"] as PackedVector2Array)[0].x, f.end.x, "шкала пульса справа")
		assert_true(_rgb_eq(e["color"], UiTokens.HUD_HR_LABEL))
	assert_eq(_tagged(log, HudChart.TAG_LEGEND).size(), 4, "легенда: два штриха и две подписи")
	# Без датчика пульса: ни линии, ни шкалы, ни половины легенды.
	before_each()
	var no_hr := _running_chart(120)
	no_hr.legend_power_key = "hud.chart.legend.power"
	no_hr.legend_hr_key = "hud.chart.legend.hr"
	var log2 := no_hr.debug_draw_commands()
	assert_eq(_tagged(log2, HudChart.TAG_HR_LINE).size(), 0)
	assert_eq(_tagged(log2, HudChart.TAG_HR_LABEL).size(), 0)
	assert_eq(_tagged(log2, HudChart.TAG_LEGEND).size(), 2)


func test_ftp_dash_at_ftp_height() -> void:
	var chart := _chart()
	chart.set_plan(PlanChartModel.new(_plan(), FTP))
	var ftp := _tagged(chart.debug_draw_commands(), HudChart.TAG_FTP)
	assert_eq(ftp.size(), 1)
	var pts: PackedVector2Array = ftp[0]["points"]
	assert_almost_eq(pts[0].y, chart.y_power(float(FTP)), 1.0)
	# Штрих 6, шаг 10.
	assert_almost_eq(pts[1].x - pts[0].x, 6.0, 1e-3)
	assert_almost_eq(pts[2].x - pts[0].x, 10.0, 1e-3)


func test_time_axis_labels_under_field() -> void:
	var chart := _chart()
	chart.set_plan(PlanChartModel.new(_plan(), FTP))
	var labels := _tagged(chart.debug_draw_commands(), HudChart.TAG_TIME_LABEL)
	# План 20 мин → шаг 5 мин: 0, 5, 10, 15, 20.
	var texts: Array[String] = []
	for e in labels:
		texts.append(str(e["meta"]["text"]))
		assert_gt((e["points"] as PackedVector2Array)[0].y, chart.field_rect().end.y)
	assert_eq(texts, ["0", "5", "10", "15", "20"] as Array[String])


# ---------------------------------------------------------------------------
# Кэш слоя плана и перерисовка по сэмплу
# ---------------------------------------------------------------------------

func test_plan_layer_redrawn_only_on_revision_change() -> void:
	var chart := _running_chart(10, 140)
	var plan0: int = chart.plan_redraw_requests()
	var fact0: int = chart.fact_redraw_requests()
	for i in 5:
		_session.tick(1.0)
		chart.sync(_session)
	assert_eq(chart.plan_redraw_requests(), plan0, "внутри шага кэш плана не перерисовывается")
	assert_eq(chart.fact_redraw_requests(), fact0 + 5, "слой факта — раз в сэмпл")
	# Смена множителя → новая версия модели → перерисовка кэша.
	_session.set_intensity(1.05)
	_session.tick(1.0)
	chart.sync(_session)
	assert_eq(chart.plan_redraw_requests(), plan0 + 1)


func test_draws_in_tree_without_errors() -> void:
	var chart := _running_chart(650, 140)
	add_child(chart)
	await wait_process_frames(2)
	var preview := PlanPreview.new()
	preview.size = Vector2(320, 80)
	add_child_autofree(preview)
	preview.set_workout(_plan(), FTP)
	await wait_process_frames(2)
	assert_eq(_tagged(preview.debug_draw_commands(), HudChart.TAG_SEGMENT).size(), 5)


# ---------------------------------------------------------------------------
# REQ-UIX-03 крит. 4 — превью из той же модели тем же рисовальщиком
# ---------------------------------------------------------------------------

func test_preview_uses_same_model_and_painter_without_fact_cursor_labels() -> void:
	var preview: PlanPreview = _chart(PlanPreview.new())
	preview.set_workout(_plan(), FTP)
	assert_true(preview is HudChart, "тот же рисовальщик")
	var log := preview.debug_draw_commands()
	for tag in [HudChart.TAG_CURSOR, HudChart.TAG_POWER_LINE, HudChart.TAG_HR_LINE, HudChart.TAG_TIME_LABEL,
			HudChart.TAG_FTP_LABEL, HudChart.TAG_HR_LABEL, HudChart.TAG_LEGEND, HudChart.TAG_FTP]:
		assert_eq(_tagged(log, tag).size(), 0, "на миниатюре нет %s" % tag)
	# Сегменты совпадают с графиком HUD по той же модели: токены и доли ширины.
	var chart := _chart()
	chart.set_plan(PlanChartModel.new(_plan(), FTP))
	var a := _tagged(log, HudChart.TAG_SEGMENT)
	var b := _tagged(chart.debug_draw_commands(), HudChart.TAG_SEGMENT)
	assert_eq(a.size(), b.size())
	var fa := preview.field_rect()
	var fb := chart.field_rect()
	for k in a.size():
		assert_eq(str(a[k]["meta"]["token"]), str(b[k]["meta"]["token"]))
		assert_true(_rgb_eq(a[k]["color"], b[k]["color"]))
		var xa: float = (float(a[k]["meta"]["x0"]) - fa.position.x) / fa.size.x
		var xb: float = (float(b[k]["meta"]["x0"]) - fb.position.x) / fb.size.x
		assert_almost_eq(xa, xb, 2.0 / fa.size.x)
	# Фон превью — `inset` со скруглением.
	var bg := _tagged(log, HudChart.TAG_BACKGROUND)
	assert_eq(str(bg[0]["op"]), "rounded_rect")
	assert_true(_rgb_eq(bg[0]["color"], UiTokens.INSET))


func test_detailed_preview_has_time_axis_and_ftp() -> void:
	var preview: PlanPreview = _chart(PlanPreview.new())
	preview.detailed = true
	preview.set_workout(_plan(), FTP)
	var log := preview.debug_draw_commands()
	assert_eq(_tagged(log, HudChart.TAG_FTP).size(), 1)
	assert_gt(_tagged(log, HudChart.TAG_TIME_LABEL).size(), 0)
	assert_eq(_tagged(log, HudChart.TAG_CURSOR).size(), 0)
	assert_eq(_tagged(log, HudChart.TAG_POWER_LINE).size(), 0)


# ---------------------------------------------------------------------------
# Режим окна (заготовка для T-079)
# ---------------------------------------------------------------------------

func test_window_mode_draws_lines_without_plan_and_cursor() -> void:
	var series := EffortSeries.sliding_window(FTP)
	for t in range(1, 121):
		series.push(t, 180 + (t % 7) * 10, true, 130, true)
	var chart := _chart()
	chart.set_window(series, FTP)
	var log := chart.debug_draw_commands()
	assert_eq(_tagged(log, HudChart.TAG_SEGMENT).size(), 0)
	assert_eq(_tagged(log, HudChart.TAG_CURSOR).size(), 0)
	assert_gt(_tagged(log, HudChart.TAG_POWER_LINE).size(), 0)
	assert_gt(_tagged(log, HudChart.TAG_HR_LINE).size(), 0)
	assert_almost_eq(chart.y_power(float(FTP)), _tagged(log, HudChart.TAG_FTP)[0]["points"][0].y, 1e-3)
