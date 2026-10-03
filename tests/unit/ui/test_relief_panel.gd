extends GutTest
## Панель рельефа HUD свободной езды (T-079): REQ-FRD-06 крит. 3 (а, б) — круг целиком с маркером
## гонщика, профиль «впереди 2 км», подвал «до вершины / подъём через»; `docs/game/hud.md` п. 8.
## Модель (`ReliefPanelModel`) и отрисовка (`ReliefPanel.debug_draw_commands`) — headless.

const W: float = 282.0
const H: float = 288.0

var _previous_locale: String
var _ft: FakeTrainer
var _session: FreeRideSession


func before_each() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("ru")


func after_each() -> void:
	TranslationServer.set_locale(_previous_locale)
	if _session != null:
		_session.dispose()
		_session = null


func _panel(route_id: String, distance_m: float, ascent_m: float = 0.0) -> ReliefPanel:
	var panel := ReliefPanel.new()
	panel.panel_width = W
	panel.panel_height = H
	add_child_autofree(panel)
	var route := RouteCatalog.get_route(route_id)
	var length: float = route.profile.length_m()
	var model := ReliefPanelModel.for_route(route)
	model.set_position(distance_m, floori(distance_m / length) + 1, fposmod(distance_m, length), ascent_m)
	panel.set_model(model)
	return panel


func _session_on(route_id: String) -> FreeRideSession:
	_ft = FakeTrainer.new(7)
	_ft.connect_delay_sec = 0.0
	_ft.set_rider_power(250)
	_ft.connect_device("fake")
	_session = FreeRideSession.new(_ft, route_id, 50, 75.0, 250)
	return _session


static func _tagged(log: Array[Dictionary], tag: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in log:
		if str(e["tag"]) == tag:
			out.append(e)
	return out


# --- REQ-FRD-06 крит. 3 (а): круг целиком --------------------------------------------------------

func test_req_frd_06_c3a_lap_marker_x_is_s_over_length() -> void:
	for route_id: String in RouteCatalog.IDS:
		var length: float = RouteCatalog.get_route(route_id).profile.length_m()
		for frac: float in [0.0, 0.13, 0.5, 0.87, 0.999]:
			var panel := _panel(route_id, frac * length)
			var field := panel.lap_field_rect()
			var at := panel.lap_marker_position()
			assert_almost_eq(at.x, field.position.x + frac * field.size.x, 1.0,
					"%s: s = %.3f·L → x = s/L × ширина (±1 px)" % [route_id, frac])
			var plot := panel.model.lap_plot(field)
			assert_almost_eq(at.y, plot.y(panel.model.profile().height_at(frac * length)), 1.0,
					"%s: маркер на высоте профиля в s" % route_id)
			assert_between(at.y, field.position.y - 0.01, field.end.y + 0.01, "маркер внутри поля")


func test_req_frd_06_c3a_marker_returns_to_left_edge_after_full_lap() -> void:
	var length: float = RouteCatalog.get_route(RouteCatalog.MOUNTAINS).profile.length_m()
	var before := _panel(RouteCatalog.MOUNTAINS, length - 5.0)
	var field := before.lap_field_rect()
	assert_almost_eq(before.lap_marker_position().x, field.end.x, 1.0, "перед концом круга — у правого края")
	var after := _panel(RouteCatalog.MOUNTAINS, length + 5.0)
	assert_almost_eq(after.lap_marker_position().x, field.position.x, 1.0, "после полного круга — у левого края")
	assert_eq(after.lap_text(), "круг 2")
	var third := _panel(RouteCatalog.MOUNTAINS, 2.0 * length + 0.25 * length)
	assert_almost_eq(third.lap_marker_position().x, field.position.x + 0.25 * field.size.x, 1.0, "s mod L на 3-м круге")


func test_req_frd_06_c3a_lap_uses_same_series_as_preview() -> void:
	for route_id: String in RouteCatalog.IDS:
		var panel := _panel(route_id, 1000.0)
		var field := panel.lap_field_rect()
		var preview := RoutePreviewModel.for_route(RouteCatalog.get_route(route_id))
		var mine := panel.model.preview.series(panel.model.lap_plot(field))
		assert_eq(mine, preview.lap_series(field.size.x), "%s: та же серия, что превью FRD-03 крит. 3" % route_id)
		assert_lte(mine.size(), 2 * int(field.size.x), "точек ≤ 2 × ширины")


func test_lap_scale_from_min_to_max_with_floor() -> void:
	var mountains := _panel(RouteCatalog.MOUNTAINS, 0.0)
	var p := mountains.model.lap_plot(mountains.lap_field_rect())
	var prof := RouteCatalog.get_route(RouteCatalog.MOUNTAINS).profile
	assert_almost_eq(p.h_bottom, prof.min_height_m(), 1e-6, "низ — минимум трассы")
	assert_almost_eq(p.h_top, prof.max_height_m(), 1e-6, "верх — максимум трассы")
	var flat := _panel(RouteCatalog.FLAT, 0.0)
	var pf := flat.model.lap_plot(flat.lap_field_rect())
	assert_almost_eq(pf.h_top - pf.h_bottom, ReliefPanelModel.LAP_MIN_SPAN_M, 1e-6, "равнина не растягивается в горы")


func test_lap_passed_part_is_dimmed() -> void:
	var length: float = RouteCatalog.get_route(RouteCatalog.HILLS).profile.length_m()
	var panel := _panel(RouteCatalog.HILLS, length + 0.4 * length)
	assert_eq(panel.model.passed_ranges(), [Vector2(0.0, 0.4 * length)] as Array[Vector2], "пройдено на круге — от старта до s")
	var log := panel.debug_draw_commands()
	var x_marker: float = panel.lap_marker_position().x
	var passed := 0
	var ahead := 0
	for e in _tagged(log, ReliefPanel.TAG_LAP_FILL):
		var pts: PackedVector2Array = e["points"]
		var color: Color = e["color"]
		if bool(e["meta"]["passed"]):
			passed += 1
			assert_almost_eq(color.a, ReliefPanel.PASSED_ALPHA, 1e-6)
			assert_lte(pts[pts.size() - 1].x, x_marker + 0.5, "пройденное — левее маркера")
		else:
			ahead += 1
			assert_almost_eq(color.a, 1.0, 1e-6)
			assert_gte(pts[0].x, x_marker - 0.5, "непройденное — правее маркера")
	assert_gt(passed, 0)
	assert_gt(ahead, 0)
	var outline := _tagged(log, ReliefPanel.TAG_LAP_OUTLINE)
	assert_eq(outline.size(), 1)
	assert_almost_eq(float(outline[0]["width"]), 1.5, 1e-6, "контур 1.5")
	assert_eq(outline[0]["color"], Color(1, 1, 1, 0.85))


func test_passed_ranges_wrap_when_start_is_offset() -> void:
	var model := ReliefPanelModel.for_route(RouteCatalog.get_route(RouteCatalog.FLAT))
	model.set_position(300.0, 1, 500.0, 0.0)
	assert_eq(model.passed_ranges(), [Vector2(9800.0, 10000.0), Vector2(0.0, 300.0)] as Array[Vector2])
	model.set_position(0.0, 2, 0.0, 0.0)
	assert_eq(model.passed_ranges().size(), 0, "начало круга — ничего не пройдено")


# --- REQ-FRD-06 крит. 3 (б): впереди 2 км -------------------------------------------------------

func test_req_frd_06_c3b_ahead_window_and_marker() -> void:
	for route_id: String in RouteCatalog.IDS:
		var panel := _panel(route_id, 4321.0)
		var field := panel.ahead_field_rect()
		var plot := panel.model.ahead_plot(field)
		assert_almost_eq(plot.s_from, 4321.0 - 200.0, 1e-6, "%s: от s − 200 м" % route_id)
		assert_almost_eq(plot.s_to, 4321.0 + 2000.0, 1e-6, "%s: до s + 2000 м" % route_id)
		var at := panel.ahead_marker_position()
		assert_almost_eq(at.x, field.position.x + 200.0 / 2200.0 * field.size.x, 1.0, "%s: маркер на 200/2200 ширины" % route_id)
		assert_almost_eq(at.y, plot.y(panel.model.profile().height_at(4321.0)), 1.0, "%s: маркер на профиле" % route_id)
		assert_gte(plot.h_top - plot.h_bottom, 40.0 - 1e-6, "%s: размах шкалы Y ≥ 40 м" % route_id)


func test_req_frd_06_c3b_flat_window_has_min_span() -> void:
	var panel := _panel(RouteCatalog.FLAT, 5000.0)
	var plot := panel.model.ahead_plot(panel.ahead_field_rect())
	var lo := INF
	var hi := -INF
	for pt in panel.model.preview.series(plot):
		lo = minf(lo, pt.y)
		hi = maxf(hi, pt.y)
	assert_lt(hi - lo, 40.0, "на равнине перепад окна меньше 40 м")
	assert_gte(plot.h_top - plot.h_bottom, 40.0 - 1e-6, "шкала всё равно ≥ 40 м")
	assert_lte(plot.y(lo) - plot.y(hi), plot.rect.size.y * 0.5, "равнина не выглядит горами")


func test_ahead_window_passes_through_lap_junction() -> void:
	var prof := RouteCatalog.get_route(RouteCatalog.HILLS).profile
	var length: float = prof.length_m()
	var panel := _panel(RouteCatalog.HILLS, length - 500.0)
	var plot := panel.model.ahead_plot(panel.ahead_field_rect())
	assert_almost_eq(plot.s_to, length + 1500.0, 1e-6, "окно продолжается за стык")
	var pts := panel.model.preview.series(plot)
	assert_almost_eq(pts[pts.size() - 1].x, length + 1500.0, 1e-6)
	for pt in pts:
		assert_almost_eq(pt.y, prof.height_at(pt.x), 1e-3, "высоты за стыком — следующий круг")
	var fill := _tagged(panel.debug_draw_commands(), ReliefPanel.TAG_AHEAD_FILL)
	assert_gt(fill.size(), 0)
	var right: float = 0.0
	for e in fill:
		var top: PackedVector2Array = e["points"]
		right = maxf(right, top[top.size() - 1].x)
	assert_almost_eq(right, plot.rect.end.x, 0.5, "заливка до правого края без дыры на стыке")


func test_steepest_place_ahead_is_labelled() -> void:
	var panel := _panel(RouteCatalog.MOUNTAINS, 6400.0)
	var steep := panel.model.steepest_ahead()
	assert_false(steep.is_empty(), "на подъёме впереди есть крутое место")
	var prof := RouteCatalog.get_route(RouteCatalog.MOUNTAINS).profile
	var best := -INF
	var s := 6410.0
	while s <= 8400.0 + 1e-6:
		best = maxf(best, prof.grade_at(s))
		s += prof.sample_step_m()
	assert_almost_eq(float(steep["grade_pct"]), best, 1e-6, "самое крутое место окна впереди")
	assert_eq(str(steep["text"]), "%s %%" % RoutePreviewModel.grade_value(best))
	var labels := _tagged(panel.debug_draw_commands(), ReliefPanel.TAG_GRADE_LABEL)
	assert_eq(labels.size(), 1)
	assert_eq(str(labels[0]["meta"]["text"]), str(steep["text"]))
	var flat := _panel(RouteCatalog.FLAT, 6400.0)
	assert_true(flat.model.steepest_ahead().is_empty(), "на равнине подъёма впереди нет")
	assert_eq(_tagged(flat.debug_draw_commands(), ReliefPanel.TAG_GRADE_LABEL).size(), 0)


# --- Подвал ------------------------------------------------------------------------------------

func test_footer_to_summit_on_climb() -> void:
	var climb: RouteProfile.Climb = RouteCatalog.get_route(RouteCatalog.MOUNTAINS).profile.climbs()[0]
	var s: float = climb.start_m + 1000.0
	var panel := _panel(RouteCatalog.MOUNTAINS, s)
	var f := panel.model.footer()
	assert_eq(str(f["kind"]), ReliefPanelModel.FOOTER_SUMMIT)
	var remaining: float = climb.end_m() - s
	assert_almost_eq(float(f["distance_m"]), remaining, 1e-6)
	var prof := panel.model.profile()
	var gain: float = prof.height_at(climb.end_m()) - prof.height_at(s)
	assert_eq(panel.footer_text(), "до вершины %s км · +%d м" % [RoutePreviewModel.length_value(remaining), roundi(gain)])
	TranslationServer.set_locale("en")
	assert_eq(panel.footer_text(), "to summit %s km · +%d m" % [RoutePreviewModel.length_value(remaining), roundi(gain)])


func test_footer_empty_near_summit() -> void:
	var climb: RouteProfile.Climb = RouteCatalog.get_route(RouteCatalog.MOUNTAINS).profile.climbs()[0]
	var panel := _panel(RouteCatalog.MOUNTAINS, climb.end_m() - 200.0)
	assert_eq(str(panel.model.footer()["kind"]), ReliefPanelModel.FOOTER_NONE, "до вершины < 300 м — пусто")
	assert_eq(_tagged(panel.debug_draw_commands(), ReliefPanel.TAG_FOOTER).size(), 0)


func test_footer_climb_in_when_closer_than_3_km() -> void:
	var climbs := RouteCatalog.get_route(RouteCatalog.HILLS).profile.climbs()
	var second: RouteProfile.Climb = climbs[1]
	var panel := _panel(RouteCatalog.HILLS, second.start_m - 1300.0)
	var f := panel.model.footer()
	assert_eq(str(f["kind"]), ReliefPanelModel.FOOTER_CLIMB_IN)
	assert_almost_eq(float(f["distance_m"]), 1300.0, 1e-6)
	assert_eq(panel.footer_text(), "подъём через 1.3 км")
	var far := _panel(RouteCatalog.MOUNTAINS, 12000.0)
	assert_eq(far.footer_text(), "", "подъём дальше 3 км — пусто")
	var flat := _panel(RouteCatalog.FLAT, 100.0)
	assert_eq(flat.footer_text(), "", "без подъёмов — пусто")


func test_footer_climb_in_across_junction() -> void:
	var prof := RouteCatalog.get_route(RouteCatalog.HILLS).profile
	var climbs := prof.climbs()
	var first: RouteProfile.Climb = climbs[0]
	var last: RouteProfile.Climb = climbs[climbs.size() - 1]
	var s: float = prof.length_m() - 500.0
	assert_gt(s, last.end_m(), "после последнего подъёма круга")
	var panel := _panel(RouteCatalog.HILLS, s)
	var f := panel.model.footer()
	assert_eq(str(f["kind"]), ReliefPanelModel.FOOTER_CLIMB_IN)
	assert_almost_eq(float(f["distance_m"]), 500.0 + first.start_m, 1e-6, "подъём следующего круга через стык")


# --- Тексты ------------------------------------------------------------------------------------

func test_texts_ru_en() -> void:
	var panel := _panel(RouteCatalog.MOUNTAINS, 26400.0, 612.4)
	assert_eq(panel.title_text(), tr("track.mountains.name"))
	assert_eq(panel.lap_text(), "круг 2")
	assert_eq(panel.lap_distance_text(), "6.4 / 20.0 км")
	assert_eq(panel.ascent_text(), "↑ 612 м")
	TranslationServer.set_locale("en")
	assert_eq(panel.lap_text(), "lap 2")
	assert_eq(panel.lap_distance_text(), "6.4 / 20.0 km")
	assert_eq(panel.ascent_text(), "↑ 612 m")
	assert_eq(ReliefPanelModel.ahead_caption(), "Next 2 km")


# --- Отрисовка -----------------------------------------------------------------------------------

func test_draw_order_and_marker_style() -> void:
	var panel := _panel(RouteCatalog.MOUNTAINS, 6400.0, 300.0)
	var log := panel.debug_draw_commands()
	assert_eq(str(log[0]["tag"]), ReliefPanel.TAG_PLATE, "сначала подложка")
	assert_eq(log[0]["color"], UiTokens.HUD_PLATE)
	var markers := _tagged(log, ReliefPanel.TAG_MARKER)
	assert_eq(markers.size(), 4, "две точки: на круге и впереди (кольцо + середина)")
	assert_eq(markers[0]["color"], UiTokens.HUD_INK)
	assert_almost_eq(float(markers[0]["meta"]["radius"]), 6.0, 1e-6)
	assert_eq(markers[1]["color"], UiTokens.HUD_TEXT)
	assert_almost_eq(float(markers[1]["meta"]["radius"]), 4.5, 1e-6)
	assert_eq((markers[0]["points"] as PackedVector2Array)[0], panel.lap_marker_position())
	assert_eq((markers[2]["points"] as PackedVector2Array)[0], panel.ahead_marker_position())
	var tags: Array[String] = []
	for e in log:
		tags.append(str(e["tag"]))
	assert_lt(tags.find(ReliefPanel.TAG_LAP_FILL), tags.find(ReliefPanel.TAG_LAP_OUTLINE), "заливка под контуром")
	assert_lt(tags.find(ReliefPanel.TAG_LAP_OUTLINE), tags.find(ReliefPanel.TAG_MARKER), "маркер поверх профиля")
	assert_lt(tags.find(ReliefPanel.TAG_AHEAD_CAPTION), tags.find(ReliefPanel.TAG_AHEAD_FILL))
	assert_eq(str(_tagged(log, ReliefPanel.TAG_AHEAD_CAPTION)[0]["meta"]["text"]), "ВПЕРЕДИ 2 КМ")
	var ahead_field := panel.ahead_field_rect()
	for e in _tagged(log, ReliefPanel.TAG_AHEAD_FILL):
		assert_almost_eq(float(e["meta"]["base"]), ahead_field.end.y, 1e-6, "заливка впереди до низа поля")


func test_fill_colors_follow_grade_palette() -> void:
	var panel := _panel(RouteCatalog.MOUNTAINS, 6400.0)
	var palette: Array[Color] = []
	for c in UiTokens.GRADE_COLORS:
		palette.append(c)
	for tag: String in [ReliefPanel.TAG_LAP_FILL, ReliefPanel.TAG_AHEAD_FILL]:
		for e in _tagged(panel.debug_draw_commands(), tag):
			var c: Color = e["color"]
			assert_true(palette.has(Color(c, 1.0)), "%s: цвет из палитры уклона" % tag)


func test_layout_inside_panel_and_fields_do_not_overlap() -> void:
	for h: float in [288.0, 240.0, 200.0]:
		var panel := _panel(RouteCatalog.HILLS, 1000.0)
		panel.panel_height = h
		var bounds := Rect2(Vector2.ZERO, panel.size)
		var lap := panel.lap_field_rect()
		var ahead := panel.ahead_field_rect()
		assert_true(bounds.encloses(lap), "круг внутри панели (h=%d)" % h)
		assert_true(bounds.encloses(ahead), "впереди внутри панели (h=%d)" % h)
		assert_lt(lap.end.y, panel.row_baseline(), "строка под профилем круга")
		assert_lt(panel.caption_baseline(), ahead.position.y, "подпись над окном впереди")
		assert_lt(ahead.end.y, panel.footer_baseline() - 9.0, "подвал под окном впереди")
	assert_almost_eq(ReliefPanel.preferred_height(720.0), 288.0, 1e-6, "0.40·H")
	assert_almost_eq(ReliefPanel.preferred_height(720.0, 250.0), 250.0, 1e-6, "не выше слота")


# --- setup / sync с сессией ---------------------------------------------------------------------

func test_setup_and_sync_with_session() -> void:
	var session := _session_on(RouteCatalog.HILLS)
	session.start()
	var panel := ReliefPanel.new()
	add_child_autofree(panel)
	panel.setup(session)
	assert_eq(panel.title_text(), tr("track.hills.name"))
	assert_almost_eq(panel.model.s_m(), session.position.s_m(), 1e-6)
	var redraws := panel.redraw_requests()
	assert_false(panel.sync(session), "без движения — без перерисовки")
	assert_eq(panel.redraw_requests(), redraws)
	for i in 300:
		session.tick(0.1)
	assert_gt(session.distance_m(), 0.0, "сессия проехала")
	assert_true(panel.sync(session))
	assert_gt(panel.redraw_requests(), redraws)
	var field := panel.lap_field_rect()
	assert_almost_eq(panel.lap_marker_position().x,
			field.position.x + session.position.s_m() / session.position.length_m() * field.size.x, 1.0)
	assert_eq(panel.model.ascent_m(), session.ascent_m())
