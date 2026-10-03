extends GutTest
## Панель цифр HUD (T-073): REQ-HUD-01 (новая редакция) крит. 1–4, REQ-HUD-02 крит. 3, 4,
## REQ-HUD-03 крит. 2, 3, REQ-HUD-04 крит. 2, REQ-HUD-06 крит. 2, REQ-HUD-13 крит. 1 (состав),
## REQ-HUD-14 крит. 1, 3, 4. Дизайн — `docs/game/hud.md` п. 5, 5.3, 9, 11.

const SCENE: String = "res://src/ui/hud/hud_metric_panel.tscn"
const INTER_RES: String = "res://assets/fonts/inter/Inter-Variable.res"
## Самый светлый фон кадра (облако), `hud.md` п. 9.
const LIGHTEST_BG: Color = Color(0.95, 0.96, 0.98)
const NUMERIC_NODES: Array[String] = ["elapsed", "distance", "speed", "target", "target_cadence", "countdown", "power", "hr", "cadence"]

var _previous_locale: String


func before_each() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_each() -> void:
	TranslationServer.set_locale(_previous_locale)


func _panel() -> HudMetricPanel:
	var p: HudMetricPanel = load(SCENE).instantiate()
	add_child_autofree(p)
	return p


## Состояние в форме `HudModel.state()` + поля экрана.
static func _state(over: Dictionary = {}) -> Dictionary:
	var s := {
		"elapsed_text": "16:40", "distance_m": 9400.0, "speed_text": "33.6",
		"target_w": 300, "target_text": "300", "target_zone_token": "z5", "target_cadence_rpm": 100,
		"step_fraction": 0.25, "step_free": false, "resistance_pct": 50,
		"countdown_text": "00:20", "about_to_change": false,
		"smoothed_power_w": 247, "power_text": "247", "power_deviation": HudModel.DEVIATION_BELOW,
		"power_zone_text": "Z4", "power_zone_token": "z4",
		"hr_bpm": 152, "hr_text": "152", "hr_zone_text": "Z4", "hr_zone_token": "hr4",
		"cadence_text": "98",
	}
	s.merge(over, true)
	return s


func _node(p: HudMetricPanel, key: String) -> Control:
	return p.value_nodes()[key] as Control


func _font_size(p: HudMetricPanel, key: String) -> int:
	return (_node(p, key) as Label).get_theme_font_size(&"font_size")


# --- REQ-HUD-01 ----------------------------------------------------------------------------------

func test_req_hud_01_c1_c2_target_text_with_unit_and_dash() -> void:
	var p := _panel()
	p.set_state(_state())
	assert_eq(p.target_text(), "300 W")
	TranslationServer.set_locale("ru")
	assert_eq(p.target_text(), "300 Вт")
	TranslationServer.set_locale("en")
	p.set_state(_state({"target_w": -1, "target_text": "—", "power_deviation": HudModel.DEVIATION_HIDDEN}))
	assert_eq(p.target_text(), "—", "шаг без цели")
	assert_eq(p.deviation_text(), "", "без цели отклонение скрыто")


func test_req_hud_01_c3_hero_is_largest_target_between() -> void:
	var p := _panel()
	var hero := _font_size(p, "power")
	var target := _font_size(p, "target")
	for key in ["hr", "cadence"]:
		assert_true(hero >= 2 * _font_size(p, key), "факт %d ≥ 2× %s %d" % [hero, key, _font_size(p, key)])
		assert_true(target >= _font_size(p, key), "цель не меньше %s" % key)
	assert_lt(target, hero, "цель мельче факта")
	assert_eq([hero, target, _font_size(p, "hr")], [88, 40, 34], "88·s / 40·s / 34·s (hud.md п. 5)")
	for key in NUMERIC_NODES:
		if key != "power":
			assert_lt(_font_size(p, key), hero, "%s мельче факта" % key)


func test_req_hud_01_c4_target_and_countdown_in_one_card_without_hero() -> void:
	var p := _panel()
	var card := p.target_card()
	assert_true(card.is_ancestor_of(_node(p, "target")), "цель в карточке")
	assert_true(card.is_ancestor_of(_node(p, "countdown")), "отсчёт в карточке")
	assert_false(card.is_ancestor_of(_node(p, "power")), "факт не в карточке")
	assert_true(p.is_ancestor_of(card), "карточка внутри панели цифр")


# --- REQ-HUD-02, 03, 04, 06 -----------------------------------------------------------------------

func test_req_hud_02_c4_deviation_glyph_delta_and_tokens() -> void:
	var p := _panel()
	p.set_state(_state())
	assert_eq(p.power_text(), "247 W")
	assert_eq(p.deviation_text(), "▼")
	assert_eq(p.deviation_delta_text(), "−53", "факт 247, цель 300")
	assert_eq(p.deviation_color(), UiTokens.HUD_DEV_BELOW)
	p.set_state(_state({"smoothed_power_w": 330, "power_text": "330", "power_deviation": HudModel.DEVIATION_ABOVE}))
	assert_eq([p.deviation_text(), p.deviation_delta_text(), p.deviation_color()], ["▲", "+30", UiTokens.HUD_WARN])
	p.set_state(_state({"smoothed_power_w": 300, "power_text": "300", "power_deviation": HudModel.DEVIATION_ON}))
	assert_eq([p.deviation_text(), p.deviation_delta_text(), p.deviation_color()], ["●", "0", UiTokens.HUD_DEV_ON])
	for token: String in ZonePalette.POWER_TOKENS:
		for c: Color in [UiTokens.HUD_DEV_ON, UiTokens.HUD_WARN, UiTokens.HUD_DEV_BELOW]:
			assert_ne(c, ZonePalette.color(token), "цвет отклонения не совпадает с зоной %s" % token)


func test_req_hud_03_04_zone_chips_fill_and_no_data() -> void:
	var p := _panel()
	p.set_state(_state())
	assert_eq(p.power_zone_text(), "Z4")
	assert_eq(p.power_zone_color(), ZonePalette.color("z4"), "фишка зоны факта — цвет зоны")
	assert_eq(p.hr_zone_text(), "Z4")
	assert_eq(p.hr_zone_color(), ZonePalette.color("hr4"))
	assert_eq(p.target_zone_text(), "Z5")
	assert_eq(p.target_zone_color(), ZonePalette.color("z5"))
	assert_eq((_node(p, "hr_zone") as Label).get_theme_color(&"font_color"), UiTokens.HUD_INK, "текст на заливке — hud.ink")
	p.set_state(_state({"smoothed_power_w": -1, "power_text": "—", "power_zone_text": "—", "power_zone_token": "",
		"hr_bpm": -1, "hr_text": "—", "hr_zone_text": "—", "hr_zone_token": "", "power_deviation": HudModel.DEVIATION_HIDDEN}))
	assert_eq(p.power_zone_text(), "—", "нет данных мощности")
	assert_eq(p.power_zone_color(), Color.TRANSPARENT, "без заливки")
	assert_eq(p.hr_zone_text(), "—", "нет датчика пульса")
	assert_eq(p.hr_zone_color(), Color.TRANSPARENT, "без цвета зоны (HUD-04 крит. 2)")
	assert_eq((_node(p, "hr_zone") as Label).get_theme_color(&"font_color"), UiTokens.HUD_TEXT2, "«—» цветом hud.text2")
	assert_eq(p.power_text(), "—")


func test_req_hud_06_c2_countdown_accent_is_warn() -> void:
	var p := _panel()
	p.set_state(_state())
	assert_false(p.is_countdown_accented())
	p.set_state(_state({"countdown_text": "00:05", "about_to_change": true}))
	assert_true(p.is_countdown_accented())
	assert_eq(_node(p, "countdown").modulate, UiTokens.HUD_WARN, "отсчёт цветом hud.warn (hud.md п. 10.1)")


func test_step_bar_fraction_and_zone_color() -> void:
	var p := _panel()
	p.set_state(_state())
	assert_almost_eq(p.step_fraction(), 0.25, 1e-6)
	assert_eq(p.step_bar_color(), ZonePalette.color("z5"), "полоса шага — цвет зоны шага")
	p.set_state(_state({"step_free": true, "target_w": -1, "target_zone_token": ""}))
	assert_eq(p.step_bar_color(), UiTokens.HUD_FREE, "FreeRide — hud.free")


func test_free_ride_mode_hides_target_card_and_deviation() -> void:
	var p := _panel()
	p.set_state(_state())
	p.set_mode(HudMetricPanel.Mode.FREE_RIDE)
	assert_eq(p.mode(), HudMetricPanel.Mode.FREE_RIDE)
	assert_false(p.target_card().visible)
	assert_eq(p.deviation_text(), "", "без цели — без отклонения")
	assert_eq(p.power_zone_text(), "Z4", "фишка зоны факта остаётся")


# --- REQ-HUD-13 крит. 1: состав панели --------------------------------------------------------

func test_req_hud_13_c1_panel_composition() -> void:
	var p := _panel()
	p.set_state(_state())
	assert_eq(p.size, HudLayout.PANEL_SIZE, "панель 640×166")
	assert_eq([p.elapsed_text(), p.distance_text(), p.speed_text()], ["16:40", "9.4", "33.6"], "ряд «где я»")
	assert_eq([p.hr_text(), p.cadence_text(), p.countdown_text()], ["152", "98", "00:20"])
	for key: String in p.value_nodes():
		var n := _node(p, key)
		var r := Rect2(n.global_position - p.global_position, n.size)
		assert_true(Rect2(Vector2(-1, -40), p.size + Vector2(2, 41)).encloses(r), "%s внутри панели: %s" % [key, r])


# --- REQ-HUD-14 ---------------------------------------------------------------------------------

func test_req_hud_14_c1_numbers_use_inter_with_tnum() -> void:
	var p := _panel()
	var tnum := TextServerManager.get_primary_interface().name_to_tag("tnum")
	for key in NUMERIC_NODES:
		var font := (_node(p, key) as Label).get_theme_font(&"font") as FontVariation
		assert_not_null(font, "%s: начертание темы" % key)
		if font == null:
			continue
		assert_eq(font.base_font.resource_path, INTER_RES, "%s: файл Inter" % key)
		assert_eq(int(font.opentype_features.get(tnum, 0)), 1, "%s: tnum" % key)
		# REQ-HUD-14 крит. 2: «0000», «1111», «8888» одной ширины шрифтом и кеглем узла.
		var size := (_node(p, key) as Label).get_theme_font_size(&"font_size")
		var w8 := font.get_string_size("8888", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		for probe in ["0000", "1111"]:
			assert_almost_eq(font.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x, w8, 0.5, "%s: «%s» = «8888»" % [key, probe])


func _rects(p: HudMetricPanel) -> Dictionary:
	var out := {}
	for key: String in p.value_nodes():
		var n := _node(p, key)
		out[key] = Rect2(n.global_position, n.size)
	return out


func _assert_same_rects(before: Dictionary, after: Dictionary, msg: String) -> void:
	for key: String in before:
		var a: Rect2 = before[key]
		var b: Rect2 = after[key]
		assert_true(a.position.distance_to(b.position) <= 1.0 and a.size.distance_to(b.size) <= 1.0,
			"%s: %s не сдвинулся (%s → %s)" % [msg, key, a, b])


func test_req_hud_14_c3_values_do_not_jump() -> void:
	var p := _panel()
	var sequences := {
		"power": [["9", "99", "100", "999", "9999"], "smoothed_power_w", "power_text"],
		"target": [["9", "99", "100", "999", "9999"], "target_w", "target_text"],
		"hr": [["9", "99", "100", "999"], "hr_bpm", "hr_text"],
		"cadence": [["9", "99", "100", "999"], "", "cadence_text"],
		"speed": [["9.9", "99.9"], "", "speed_text"],
		"elapsed": [["9:59", "10:00", "1:00:00"], "", "elapsed_text"],
		"countdown": [["00:09", "09:59", "59:59"], "", "countdown_text"],
	}
	for field: String in sequences:
		var seq: Array = sequences[field][0]
		var num_key: String = sequences[field][1]
		var text_key: String = sequences[field][2]
		p.set_state(_state())
		var base := _rects(p)
		for value: String in seq:
			var over := {text_key: value}
			if not num_key.is_empty():
				over[num_key] = int(value)
			p.set_state(_state(over))
			_assert_same_rects(base, _rects(p), "%s = %s" % [field, value])
	p.set_state(_state())
	var base_d := _rects(p)
	for m in [9000.0, 99000.0, 100000.0, 999000.0]:
		p.set_state(_state({"distance_m": m}))
		_assert_same_rects(base_d, _rects(p), "дистанция %.0f м" % m)


func test_req_hud_14_c4_plate_alpha_and_contrast() -> void:
	var p := _panel()
	var plate := p.get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_not_null(plate, "подложка HudPlate")
	assert_true(plate.bg_color.a >= 0.78 - 1e-6, "альфа подложки ≥ 0.78")
	assert_eq(Color(plate.bg_color, 1.0), Color(UiTokens.HUD_INK, 1.0), "цвет hud.plate")
	var under := UiTokens.blend_over(plate.bg_color, LIGHTEST_BG)
	for key: String in ["power", "power_unit", "hr", "hr_unit", "elapsed", "distance_unit", "target", "countdown_prefix"]:
		var c := (_node(p, key) as Label).get_theme_color(&"font_color")
		assert_true(UiTokens.contrast_ratio(c, under) >= 4.5, "%s: контраст %.2f ≥ 4.5" % [key, UiTokens.contrast_ratio(c, under)])
	# Текст фишки — hud.ink, тонированный цветом зоны, на заливке цветом зоны.
	p.set_state(_state())
	var ink := (_node(p, "power_zone") as Label).get_theme_color(&"font_color")
	assert_eq(ink, UiTokens.HUD_INK)
	for token: String in ZonePalette.POWER_TOKENS + ZonePalette.HR_TOKENS:
		var zone := ZonePalette.color(token)
		var ratio := UiTokens.contrast_ratio(ink * zone, zone)
		assert_true(ratio >= 4.5, "фишка %s: контраст %.2f ≥ 4.5" % [token, ratio])
	# Отклонение и акцент отсчёта — над подложкой.
	for c: Color in [UiTokens.HUD_DEV_ON, UiTokens.HUD_WARN, UiTokens.HUD_DEV_BELOW]:
		assert_true(UiTokens.contrast_ratio(c, under) >= 4.5, "токен %s читается" % c)


func test_no_theme_overrides_in_panel_and_screen_scenes() -> void:
	for path in [SCENE, "res://src/ui/workout/workout_screen.tscn"]:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.contains("theme_override_"), "%s без theme_override_*" % path)
	for path in ["res://src/ui/hud/hud_metric_panel.gd", "res://src/ui/workout/workout_screen.gd"]:
		var src := FileAccess.get_file_as_string(path)
		assert_false(src.contains("add_theme_"), "%s без add_theme_*_override" % path)
