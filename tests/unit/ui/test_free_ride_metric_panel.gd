extends GutTest
## Панель цифр HUD в режиме свободной езды (T-079): REQ-FRD-06 крит. 1, 2 (отображение),
## REQ-FRD-05 крит. 6 (режим и крутизна на HUD), REQ-HUD-14 крит. 1, 3 для новых полей.
## Дизайн — `docs/game/hud.md` п. 8, 5.3.

const SCENE: String = "res://src/ui/hud/hud_metric_panel.tscn"
const INTER_RES: String = "res://assets/fonts/inter/Inter-Variable.res"

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


func _panel() -> HudMetricPanel:
	var p: HudMetricPanel = load(SCENE).instantiate()
	add_child_autofree(p)
	p.set_mode(HudMetricPanel.Mode.FREE_RIDE)
	return p


static func _state(over: Dictionary = {}) -> Dictionary:
	var s := {
		"elapsed_text": "1:12:40", "distance_m": 31449.0, "speed_text": "24.8",
		"smoothed_power_w": 312, "power_text": "312", "power_zone_text": "Z6", "power_zone_token": "z6",
		"hr_bpm": 152, "hr_text": "152", "hr_zone_text": "Z4", "hr_zone_token": "hr4", "cadence_text": "98",
		"grade_pct": 6.44, "load_mode": SimController.Mode.SIM, "steepness_pct": 50, "resistance_pct": 40,
		"ascent_m": 612.4, "lap_fraction": 0.32,
	}
	s.merge(over, true)
	return s


func _rect(p: HudMetricPanel, n: Control) -> Rect2:
	return Rect2(n.global_position - p.global_position, n.size)


# --- REQ-FRD-06 крит. 1: формат уклона ----------------------------------------------------------

func test_req_frd_06_c1_grade_format_sign_always_one_decimal() -> void:
	assert_eq(HudMetricPanel.format_grade(6.44), "+6.4")
	assert_eq(HudMetricPanel.format_grade(6.45), "+6.5")
	assert_eq(HudMetricPanel.format_grade(-3.0), "−3.0")
	assert_eq(HudMetricPanel.format_grade(-3.0).unicode_at(0), 0x2212, "минус — U+2212")
	assert_eq(HudMetricPanel.format_grade(0.0), "0.0")
	assert_eq(HudMetricPanel.format_grade(-0.04), "0.0", "без «−0.0»")
	assert_eq(HudMetricPanel.format_grade(0.04), "0.0")
	assert_eq(HudMetricPanel.format_grade(12.0), "+12.0")
	assert_eq(HudMetricPanel.format_grade(NAN), "—", "нет данных")


func test_req_frd_06_c1_free_ride_panel_contents() -> void:
	var p := _panel()
	p.set_state(_state())
	assert_eq(p.grade_text(), "+6.4", "карточка «УКЛОН»")
	assert_eq(p.grade_mode_text(), "SIM 50 %", "режим и крутизна")
	assert_eq(p.distance_text(), "31.4", "дистанция — км с одним знаком, накопленная")
	assert_eq(p.ascent_text(), "612", "набор — целые метры")
	assert_eq(p.elapsed_text(), "1:12:40")
	assert_eq(p.speed_text(), "24.8")
	assert_eq(p.power_text(), "312 Вт", "сглаженная мощность — герой")
	assert_eq([p.hr_text(), p.cadence_text()], ["152", "98"])
	assert_eq(p.power_zone_text(), "Z6", "фишка зоны факта")
	var nodes := p.free_ride_nodes()
	assert_eq(TranslationServer.translate((nodes["grade_title"] as Label).text), "Уклон")
	assert_true((nodes["grade_title"] as Label).uppercase, "«УКЛОН» заглавными")
	assert_eq((nodes["grade_unit"] as Label).text, "%")
	assert_eq((nodes["ascent_unit"] as Label).text, "м")
	assert_eq((nodes["ascent_icon"] as Label).text, "↑")


func test_req_frd_06_c1_no_target_deviation_countdown() -> void:
	var p := _panel()
	p.set_state(_state({"target_w": 300, "target_text": "300", "countdown_text": "00:20",
			"power_deviation": HudModel.DEVIATION_BELOW}))
	assert_false(p.target_card().visible, "карточки цели нет")
	assert_true(p.grade_card().visible, "на её месте — карточка уклона")
	assert_eq(p.deviation_text(), "", "индикации отклонения нет")
	assert_eq(p.deviation_delta_text(), "")
	assert_false(p.value_nodes()["countdown"].is_visible_in_tree(), "обратного отсчёта нет")
	assert_eq(_rect(p, p.grade_card()), _rect(p, p.target_card()), "уклон — на месте карточки цели")


func test_req_frd_06_c1_missing_values_are_dashes() -> void:
	var p := _panel()
	p.set_state({})
	assert_eq(p.grade_text(), "—")
	assert_eq(p.grade_mode_text(), "—")
	assert_eq(p.ascent_text(), "—")
	assert_eq(p.speed_text(), "—")
	assert_eq(p.power_text(), "—")
	assert_eq(p.hr_text(), "—")
	assert_eq(p.cadence_text(), "—")
	assert_eq(p.grade_wedge_color(), Color.TRANSPARENT, "без уклона клин не рисуется")
	assert_eq(p.grade_wedge_height(), 0.0)


# --- REQ-FRD-06 крит. 2: на HUD уклон трассы, а не переданный станку ------------------------------

func test_req_frd_06_c2_hud_shows_route_grade_not_trainer_grade() -> void:
	_ft = FakeTrainer.new(3)
	_ft.connect_delay_sec = 0.0
	_ft.set_rider_power(250)
	_ft.connect_device("fake")
	_session = FreeRideSession.new(_ft, RouteCatalog.MOUNTAINS, 50, 75.0, 250)
	_session.position.reset(6400.0)
	_session.start()
	var fields := HudMetricPanel.free_ride_fields(_session)
	var g: float = RouteCatalog.get_route(RouteCatalog.MOUNTAINS).profile.grade_at(6400.0)
	assert_gt(g, 2.0, "точка на подъёме")
	assert_almost_eq(float(fields[HudMetricPanel.KEY_GRADE_PCT]), g, 1e-9, "полный g(s)")
	var sent: float = _session.sim.target_grade_pct()
	assert_almost_eq(sent, snappedf(g * 0.5, 0.01), 0.011, "на станок уходит g × k / 100")
	var p := _panel()
	var state := _state()
	state.merge(fields, true)
	p.set_state(state)
	assert_eq(p.grade_text(), HudMetricPanel.format_grade(g), "крутизна 50 % не меняет число на HUD")
	assert_ne(p.grade_text(), HudMetricPanel.format_grade(g * 0.5))
	assert_eq(p.grade_mode_text(), "SIM 50 %")


func test_free_ride_fields_from_session() -> void:
	_ft = FakeTrainer.new(5)
	_ft.connect_delay_sec = 0.0
	_ft.set_rider_power(250)
	_ft.connect_device("fake")
	_session = FreeRideSession.new(_ft, RouteCatalog.HILLS, 35, 75.0, 250, SimController.Mode.FIXED, 40)
	_session.start()
	for i in 200:
		_session.tick(0.1)
	var f := HudMetricPanel.free_ride_fields(_session)
	assert_eq(int(f[HudMetricPanel.KEY_LOAD_MODE]), SimController.Mode.FIXED)
	assert_eq(int(f[HudMetricPanel.KEY_RESISTANCE_PCT]), 40)
	assert_eq(int(f[HudMetricPanel.KEY_STEEPNESS_PCT]), 35)
	assert_almost_eq(float(f["distance_m"]), _session.distance_m(), 1e-9)
	assert_almost_eq(float(f[HudMetricPanel.KEY_ASCENT_M]), _session.ascent_m(), 1e-9)
	assert_almost_eq(float(f[HudMetricPanel.KEY_LAP_FRACTION]),
			_session.position.lap_distance_m() / _session.position.length_m(), 1e-9)


# --- REQ-FRD-05 крит. 6: режим и крутизна --------------------------------------------------------

func test_req_frd_05_c6_mode_and_steepness_ru_en() -> void:
	var p := _panel()
	p.set_state(_state({"load_mode": SimController.Mode.SIM, "steepness_pct": 75}))
	assert_eq(p.grade_mode_text(), "SIM 75 %")
	p.set_state(_state({"load_mode": SimController.Mode.FIXED, "resistance_pct": 40}))
	assert_eq(p.grade_mode_text(), "СОПР. 40 %", "фиксированное сопротивление — уровень")
	TranslationServer.set_locale("en")
	p.set_state(_state({"load_mode": SimController.Mode.FIXED, "resistance_pct": 40}))
	assert_eq(p.grade_mode_text(), "RES. 40 %")
	p.set_state(_state({"load_mode": SimController.Mode.SIM, "steepness_pct": 50}))
	assert_eq(p.grade_mode_text(), "SIM 50 %")


# --- Полоса круга и клин -------------------------------------------------------------------------

func test_lap_progress_bar() -> void:
	var p := _panel()
	p.set_state(_state({"lap_fraction": 0.32, "step_fraction": 0.9}))
	assert_almost_eq(p.step_fraction(), 0.32, 1e-6, "полоса — доля круга, а не шага")
	assert_eq(p.step_bar_color(), Color(UiTokens.HUD_TEXT, 0.85), "заливка hud.text, альфа 0.85")
	p.set_mode(HudMetricPanel.Mode.PLAN)
	p.set_state(_state({"step_fraction": 0.9, "target_zone_token": "z3"}))
	assert_almost_eq(p.step_fraction(), 0.9, 1e-6, "в плане — снова шаг")
	assert_eq(p.step_bar_color(), ZonePalette.color("z3"))


func test_grade_wedge_color_and_height() -> void:
	var p := _panel()
	for g: float in [-8.0, -3.0, 0.0, 1.5, 3.0, 6.4, 8.0, 12.0]:
		p.set_state(_state({"grade_pct": g}))
		assert_eq(p.grade_wedge_color(), UiTokens.grade_color(g), "клин цвета палитры уклона (%s)" % g)
		var expected: float = HudMetricPanel.WEDGE_MIN_HEIGHT if g == 0.0 else \
				clampf(32.0 * 2.0 * absf(g) / 100.0, HudMetricPanel.WEDGE_MIN_HEIGHT, 14.0)
		assert_almost_eq(p.grade_wedge_height(), expected, 1e-6, "наклон ×2 в рамке 32 × 14 (%s)" % g)
	var wedge: Control = p.free_ride_nodes()["grade_wedge"]
	assert_eq(wedge.size, Vector2(32, 14))
	assert_true(Rect2(Vector2.ZERO, p.grade_card().size).encloses(Rect2(wedge.position, wedge.size)), "клин внутри карточки")
	assert_eq((p.free_ride_nodes()["grade"] as Label).modulate, Color.WHITE, "само число белое на любом склоне")


# --- Раскладка: ряд A из четырёх ячеек, резерв и tnum (HUD-14) ------------------------------------

func test_row_a_four_cells_without_overlap() -> void:
	var p := _panel()
	p.set_state(_state())
	var v := p.value_nodes()
	var f := p.free_ride_nodes()
	var groups: Array = [
		[v["elapsed"]], [v["distance"], v["distance_unit"]], [v["speed"], v["speed_unit"]],
		[f["ascent_icon"], f["ascent"], f["ascent_unit"]],
	]
	var cell_w: float = HudMetricPanel.CONTENT_SIZE.x / 4.0
	var content: Control = v["elapsed"].get_parent()
	for i in groups.size():
		for n: Control in groups[i]:
			assert_true(n.visible, "%s виден" % n.name)
			var r := Rect2(n.global_position - content.global_position, n.size)
			assert_gte(r.position.x, cell_w * i - 0.5, "%s в своей ячейке %d" % [n.name, i])
			assert_lte(r.end.x, cell_w * (i + 1) + 0.5, "%s в своей ячейке %d" % [n.name, i])
	for key: String in ["grade", "grade_unit", "grade_mode", "grade_title", "grade_wedge"]:
		var n: Control = f[key]
		var r := Rect2(n.global_position - p.global_position, n.size)
		assert_true(Rect2(Vector2(-1, -40), p.size + Vector2(2, 41)).encloses(r), "%s внутри панели: %s" % [key, r])


func test_plan_mode_keeps_three_cells_and_hides_free_ride_nodes() -> void:
	var p := _panel()
	p.set_mode(HudMetricPanel.Mode.PLAN)
	p.set_state(_state({"target_w": 300, "target_text": "300", "target_zone_token": "z5"}))
	var f := p.free_ride_nodes()
	for key: String in ["ascent_icon", "ascent", "ascent_unit", "grade_card"]:
		assert_false((f[key] as Control).visible, "%s скрыт в плане" % key)
	assert_true(p.target_card().visible)
	var speed: Control = p.value_nodes()["speed"]
	var content: Control = speed.get_parent()
	assert_gte(speed.global_position.x - content.global_position.x, HudMetricPanel.CONTENT_SIZE.x * 2.0 / 3.0 - 0.5,
			"скорость — в третьей из трёх ячеек")


func test_req_hud_14_grade_and_ascent_reserve_and_tnum() -> void:
	var p := _panel()
	var f := p.free_ride_nodes()
	var tnum := TextServerManager.get_primary_interface().name_to_tag("tnum")
	for pair: Array in [["grade", HudMetricPanel.TEMPLATE_GRADE], ["ascent", HudMetricPanel.TEMPLATE_ASCENT]]:
		var label: Label = f[pair[0]]
		var font := label.get_theme_font(&"font") as FontVariation
		assert_not_null(font)
		if font == null:
			continue
		assert_eq(font.base_font.resource_path, INTER_RES, "%s: Inter" % pair[0])
		assert_eq(int(font.opentype_features.get(tnum, 0)), 1, "%s: tnum" % pair[0])
		var w := ceilf(font.get_string_size(pair[1], HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size(&"font_size")).x)
		assert_almost_eq(label.size.x, w, 0.5, "%s: резерв по шаблону «%s»" % [pair[0], pair[1]])
		assert_eq(label.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT, "%s: вправо внутри резерва" % pair[0])
	# Смена разрядов не двигает соседей.
	p.set_state(_state({"grade_pct": 0.0, "ascent_m": 5.0}))
	var unit_before := (f["grade_unit"] as Control).position
	var ascent_unit_before := (f["ascent_unit"] as Control).position
	p.set_state(_state({"grade_pct": -12.3, "ascent_m": 1234.0}))
	assert_eq((f["grade_unit"] as Control).position, unit_before, "«%» стоит на месте")
	assert_eq((f["ascent_unit"] as Control).position, ascent_unit_before, "«м» стоит на месте")


func test_no_theme_overrides_on_free_ride_nodes() -> void:
	var p := _panel()
	for n: Control in p.free_ride_nodes().values():
		for prop in n.get_property_list():
			var name: String = prop["name"]
			if name.begins_with("theme_override_"):
				assert_null(n.get(name), "%s: %s" % [n.name, name])
