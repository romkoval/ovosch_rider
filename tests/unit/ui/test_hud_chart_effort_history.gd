extends GutTest
## Нижний график свободной езды «история усилия» (T-079): REQ-FRD-06 крит. 4 — окно 30 мин,
## площадь мощности по зонам с белой линией, пульс красной линией без заливки, FTP пунктиром,
## шкала окна, подпись «сейчас»; правила HUD-11 (разрывы, прореживание) и HUD-12 на окне.
## `docs/game/hud.md` п. 8. Отрисовка — журнал `HudChart.debug_draw_commands()` (headless).

const FTP: int = 250
const SIZE: Vector2 = Vector2(1280, 150)

var _previous_locale: String


func before_each() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("ru")


func after_each() -> void:
	TranslationServer.set_locale(_previous_locale)


func _chart(series: EffortSeries, zones: PowerZones = null) -> HudChart:
	var chart := HudChart.new()
	chart.size = SIZE
	chart.fade_height = 28.0
	add_child_autofree(chart)
	chart.set_window(series, FTP, zones)
	return chart


static func _series(seconds: int, power: Callable, gap: Vector2i = Vector2i(-1, -1), with_hr: bool = true) -> EffortSeries:
	var s := EffortSeries.sliding_window(FTP, 190)
	for t in range(1, seconds + 1):
		var has_power: bool = not (t >= gap.x and t <= gap.y)
		s.push(t, int(power.call(t)), has_power, 140, with_hr)
	return s


static func _tagged(log: Array[Dictionary], tag: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in log:
		if str(e["tag"]) == tag:
			out.append(e)
	return out


static func _steps(t: int) -> int:
	# 10 мин Z2 (150 Вт), 10 мин Z4 (250 Вт), дальше Z6 (330 Вт).
	if t <= 600:
		return 150
	if t <= 1200:
		return 250
	return 330


# --- Площадь мощности по зонам ---------------------------------------------------------------

func test_req_frd_06_c4_power_area_coloured_by_zone_of_each_point() -> void:
	var series := _series(1500, _steps)
	var chart := _chart(series)
	var log := chart.debug_draw_commands()
	var areas := _tagged(log, HudChart.TAG_POWER_AREA)
	# Ожидаемые зоны — по каждой сглаженной точке серии, подряд идущие одинаковые — одна площадь.
	var zones := PowerZones.coggan(FTP)
	var expected: Array[String] = []
	for pt in series.raw_points(EffortSeries.SERIES_POWER):
		var token := ZonePalette.power_token(zones.zone_of(roundi(pt.y)))
		if expected.is_empty() or expected[-1] != token:
			expected.append(token)
	assert_gte(expected.size(), 3, "в данных есть Z2, Z4 и Z6 (и переходы сглаживания)")
	assert_eq(areas.size(), expected.size(), "смена зоны точки — новая площадь")
	var f := chart.field_rect()
	for i in areas.size():
		var e: Dictionary = areas[i]
		assert_eq(str(e["meta"]["token"]), expected[i], "зона точки → цвет площади")
		assert_eq(e["color"], Color(ZonePalette.color(expected[i]), HudChart.AREA_ALPHA), "альфа 0.55")
		assert_true(bool(e["filled"]))
		assert_almost_eq(float(e["meta"]["base"]), f.end.y, 1e-6, "площадь до низа поля")
	# Стык зон — посередине между соседними точками (600 и 601 с — после сглаживания 3 с).
	var first_end: Vector2 = (areas[0]["points"] as PackedVector2Array)[-1]
	var second_start: Vector2 = (areas[1]["points"] as PackedVector2Array)[0]
	assert_eq(first_end, second_start, "соседние площади стыкуются без щели")


func test_area_top_matches_power_line() -> void:
	var chart := _chart(_series(900, func(t: int) -> int: return 120 + (t % 60) * 2))
	var log := chart.debug_draw_commands()
	var line: PackedVector2Array = _tagged(log, HudChart.TAG_POWER_LINE)[0]["points"]
	var tops := {}
	for e in _tagged(log, HudChart.TAG_POWER_AREA):
		for pt in (e["points"] as PackedVector2Array):
			tops[pt] = true
	var missing := 0
	for pt in line:
		if not tops.has(pt):
			missing += 1
	assert_eq(missing, 0, "каждая точка линии лежит на верхнем контуре площади")


func test_custom_profile_zones_are_used() -> void:
	# Свои границы: всё до 100 % FTP — Z1, выше — Z2.
	var zones := PowerZones.custom(FTP, [100.0] as Array[float])
	var chart := _chart(_series(1500, _steps), zones)
	var tokens: Array[String] = []
	for e in _tagged(chart.debug_draw_commands(), HudChart.TAG_POWER_AREA):
		tokens.append(str(e["meta"]["token"]))
	assert_eq(tokens, ["z1", "z2"] as Array[String], "зоны профиля, а не Коган")
	assert_eq(chart.window_zones(), zones)


func test_draw_order_area_hr_power_and_no_plan_cursor() -> void:
	var chart := _chart(_series(900, _steps))
	chart.legend_power_key = "ui.hud.chart.legend_power"
	chart.legend_hr_key = "ui.hud.chart.legend_hr"
	var log := chart.debug_draw_commands()
	var tags: Array[String] = []
	for e in log:
		tags.append(str(e["tag"]))
	var area_last: int = tags.rfind(HudChart.TAG_POWER_AREA)
	assert_gt(area_last, -1)
	assert_lt(area_last, tags.find(HudChart.TAG_HR_OUTLINE), "площадь под пульсом")
	assert_lt(tags.find(HudChart.TAG_HR_LINE), tags.find(HudChart.TAG_POWER_OUTLINE), "пульс под мощностью")
	assert_lt(tags.find(HudChart.TAG_FTP), tags.find(HudChart.TAG_POWER_AREA), "FTP в слое под фактом")
	assert_eq(_tagged(log, HudChart.TAG_SEGMENT).size(), 0, "профиля плана нет")
	assert_eq(_tagged(log, HudChart.TAG_CURSOR).size(), 0, "курсора нет")
	for e in _tagged(log, HudChart.TAG_HR_LINE):
		assert_false(bool(e["filled"]), "пульс — линия без заливки")
		assert_eq(e["color"], UiTokens.HUD_HR_LINE)
	for e in _tagged(log, HudChart.TAG_HR_OUTLINE):
		assert_eq(e["color"], Color(UiTokens.HUD_INK, 0.9), "обводка тушью")
	for e in _tagged(log, HudChart.TAG_POWER_LINE):
		assert_eq(e["color"], UiTokens.HUD_POWER_LINE, "белая линия мощности")
		assert_almost_eq(float(e["width"]), 2.0, 1e-6)
	assert_gt(_tagged(log, HudChart.TAG_HR_LABEL).size(), 0, "своя шкала пульса справа")


# --- HUD-11: разрывы и прореживание на окне ------------------------------------------------------

func test_hud_11_gap_breaks_line_and_area() -> void:
	var chart := _chart(_series(900, func(_t: int) -> int: return 200, Vector2i(300, 330)))
	var log := chart.debug_draw_commands()
	assert_eq(_tagged(log, HudChart.TAG_POWER_LINE).size(), 2, "«нет данных» — разрыв линии")
	var areas := _tagged(log, HudChart.TAG_POWER_AREA)
	assert_eq(areas.size(), 2, "и разрыв площади")
	var gap_from: float = chart.x_at(300.0)
	var gap_to: float = chart.x_at(330.0)
	for e in areas:
		var pts: PackedVector2Array = e["points"]
		assert_true(pts[-1].x <= gap_from + 0.5 or pts[0].x >= gap_to - 0.5, "площадь не заходит в разрыв")


func test_hud_11_decimation_keeps_points_within_twice_width() -> void:
	var chart := _chart(_series(3 * 3600, func(t: int) -> int: return 150 + (t * 37) % 200))
	chart.size = Vector2(600, 150)
	assert_gt(1800, 2 * int(chart.field_rect().size.x), "в окне больше точек, чем 2 × ширины")
	var log := chart.debug_draw_commands()
	var n := 0
	for e in _tagged(log, HudChart.TAG_POWER_LINE):
		n += (e["points"] as PackedVector2Array).size()
	assert_lte(n, 2 * int(chart.field_rect().size.x), "≤ 2 × ширины точек")
	var area_pts := 0
	for e in _tagged(log, HudChart.TAG_POWER_AREA):
		area_pts += (e["points"] as PackedVector2Array).size()
	assert_lte(area_pts, 3 * 2 * int(chart.field_rect().size.x), "площадь по тем же точкам (+ стыки зон)")


# --- Ось X: 0…30 мин, затем окно и «сейчас» -------------------------------------------------------

func test_req_frd_06_c4_first_30_minutes_grow_left_to_right() -> void:
	var chart := _chart(_series(600, _steps))
	var f := chart.field_rect()
	var line: PackedVector2Array = _tagged(chart.debug_draw_commands(), HudChart.TAG_POWER_LINE)[0]["points"]
	assert_almost_eq(line[-1].x, f.position.x + 600.0 / 1800.0 * f.size.x, 1.0, "10 мин — треть ширины")
	var labels := _tagged(chart.debug_draw_commands(), HudChart.TAG_TIME_LABEL)
	var texts: Array[String] = []
	for e in labels:
		texts.append(str(e["meta"]["text"]))
	assert_eq(texts[0], "0")
	assert_eq(texts[-1], "30")
	assert_false(texts.has("сейчас"), "до 30 мин «сейчас» не подписывается")


func test_req_frd_06_c4_after_30_minutes_now_at_right_edge() -> void:
	var chart := _chart(_series(2700, _steps))
	var f := chart.field_rect()
	var log := chart.debug_draw_commands()
	var lines := _tagged(log, HudChart.TAG_POWER_LINE)
	var last: PackedVector2Array = lines[-1]["points"]
	assert_almost_eq(last[-1].x, f.end.x, 1.0, "«сейчас» у правого края")
	var first: PackedVector2Array = lines[0]["points"]
	assert_almost_eq(first[0].x, f.position.x, 1.0, "окно — последние 30 мин")
	var now: Array[Dictionary] = []
	var texts: Array[String] = []
	for e in _tagged(log, HudChart.TAG_TIME_LABEL):
		texts.append(str(e["meta"]["text"]))
		if str(e["meta"]["text"]) == "сейчас":
			now.append(e)
	assert_eq(now.size(), 1, "подпись «сейчас»")
	assert_eq(texts[0], "−30")
	var font: Font = HudChart._font("inter_num_600", 550)
	var w: float = font.get_string_size("сейчас", HORIZONTAL_ALIGNMENT_LEFT, -1.0, HudChart.SCALE_FONT_SIZE).x
	var x: float = (now[0]["points"] as PackedVector2Array)[0].x
	assert_lte(x + w, SIZE.x, "подпись не выходит за подложку")
	assert_gt(x, f.end.x - w, "подпись у правого края поля")
	TranslationServer.set_locale("en")
	var en: Array[String] = []
	for e in _tagged(chart.debug_draw_commands(), HudChart.TAG_TIME_LABEL):
		en.append(str(e["meta"]["text"]))
	assert_true(en.has("now"))


func test_now_label_can_be_disabled() -> void:
	var chart := _chart(_series(2700, _steps))
	chart.now_label_key = ""
	for e in _tagged(chart.debug_draw_commands(), HudChart.TAG_TIME_LABEL):
		assert_ne(str(e["meta"]["text"]), "", "пустых подписей нет")
		assert_ne(str(e["meta"]["text"]), "сейчас")


# --- Ось Y: y_max окна и FTP -----------------------------------------------------------------------

func test_req_frd_06_c4_y_scale_and_ftp_line() -> void:
	var chart := _chart(_series(600, func(_t: int) -> int: return 200))
	assert_almost_eq(chart.power_y_max(), 1.5 * FTP, 1e-6, "y_max ≥ 1.5 × FTP")
	var log := chart.debug_draw_commands()
	var ftp: Array[Dictionary] = _tagged(log, HudChart.TAG_FTP)
	assert_eq(ftp.size(), 1, "FTP пунктиром")
	assert_almost_eq((ftp[0]["points"] as PackedVector2Array)[0].y, chart.y_power(float(FTP)), 1e-3)
	var spiky := _chart(_series(600, func(t: int) -> int: return 610 if t > 590 else 200))
	assert_almost_eq(spiky.power_y_max(), 650.0, 1e-6, "максимум окна, округлённый вверх до 50 Вт")


# --- Сессия свободной езды ---------------------------------------------------------------------------

func test_sync_free_ride_consumes_session_samples() -> void:
	var ft := FakeTrainer.new(11)
	ft.connect_delay_sec = 0.0
	ft.set_rider_power(220)
	ft.connect_device("fake")
	var session := FreeRideSession.new(ft, RouteCatalog.FLAT, 50, 75.0, FTP)
	session.start()
	var chart := _chart(EffortSeries.sliding_window(FTP))
	for i in 150:
		session.tick(0.1)
	chart.sync_free_ride(session)
	assert_eq(chart.effort_series().size(), session.samples.size(), "все сэмплы сессии в серии")
	assert_eq(chart.effort_series().last_time_sec(), session.elapsed_sec(), "последняя точка — «сейчас»")
	var before := chart.fact_redraw_requests()
	chart.sync_free_ride(session)
	assert_gt(chart.fact_redraw_requests(), before)
	assert_gt(_tagged(chart.debug_draw_commands(), HudChart.TAG_POWER_AREA).size(), 0)
	session.dispose()
