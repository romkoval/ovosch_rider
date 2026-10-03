extends GutTest
## Доработка темы перед экранами волны 3 (T-093): REQ-UIX-01 крит. 1, 3 (вариации и стили),
## REQ-UIX-05 (контраст состояний опасной кнопки), REQ-HUD-14 (цифры `tnum`).
## Дизайн — `docs/game/ui.md` п. 4, 5, 6, 9, 11, 13; `docs/game/hud.md` п. 10.

const THEME_PATH: String = "res://src/ui/theme/app_theme.tres"
const LUCIDE_DIR: String = "res://assets/icons/lucide/"
const NEW_VARIATIONS: Dictionary = {
	"NumLabel": "Label",
	"HudPauseCard": "PanelContainer", "HudChipLabel": "Label", "HudPauseTitle": "Label",
	"SpinBoxInnerLineEdit": "LineEdit",
	"Stack0": "VBoxContainer",
	"Row0": "HBoxContainer", "Row8": "HBoxContainer", "Row12": "HBoxContainer",
	"Row16": "HBoxContainer", "Row24": "HBoxContainer",
}
const BANNER_ICONS: Array[String] = ["info", "circle-alert", "triangle-alert"]
const CHANNEL_TOLERANCE: float = 1.0 / 255.0 + 0.0001

var _theme: Theme


func before_all() -> void:
	_theme = load(THEME_PATH)


# --- Вариации ---------------------------------------------------------------------------------

func test_new_variations_exist() -> void:
	for name: String in NEW_VARIATIONS:
		assert_true(_theme.is_type_variation(name, NEW_VARIATIONS[name]), "вариация %s от %s" % [name, NEW_VARIATIONS[name]])


func test_container_gaps() -> void:
	for gap in [0, 8, 12, 16, 24]:
		assert_eq(_theme.get_constant("separation", "Stack%d" % gap), gap, "Stack%d" % gap)
		assert_eq(_theme.get_constant("separation", "Row%d" % gap), gap, "Row%d" % gap)
	var row := HBoxContainer.new()
	row.theme_type_variation = &"Row12"
	add_child_autofree(row)
	assert_eq(row.get_theme_constant("separation"), 12, "HBox с Row12 получает отступ из темы проекта")


# --- Кнопки (`ui.md` п. 4, 9.2, 13) -------------------------------------------------------------

func test_danger_tokens_match_design() -> void:
	_assert_rgb(UiTokens.DANGER_HOVER, Color("#B23532"), "danger_hover")
	_assert_rgb(UiTokens.DANGER_PRESSED, Color("#A3312D"), "danger_pressed")


func test_danger_button_states() -> void:
	var hover := _flat("hover", "DangerButton")
	var pressed := _flat("pressed", "DangerButton")
	_assert_rgb(_flat("normal", "DangerButton").bg_color, UiTokens.DANGER, "normal — danger")
	_assert_rgb(hover.bg_color, UiTokens.DANGER_HOVER, "hover — danger_hover")
	_assert_rgb(pressed.bg_color, UiTokens.DANGER_PRESSED, "pressed — danger_pressed")
	_assert_rgb(_flat("hover_pressed", "DangerButton").bg_color, UiTokens.DANGER_PRESSED, "hover_pressed — danger_pressed")
	assert_eq(_border_sum(pressed), 0, "нажатие без рамки (белая рамка читается как фокус)")
	assert_eq(_border_sum(hover), 0, "наведение без рамки")
	_assert_rgb(_theme.get_color("font_hover_color", "DangerButton"), UiTokens.TEXT, "текст наведения — text")
	_assert_rgb(_theme.get_color("font_pressed_color", "DangerButton"), UiTokens.TEXT, "текст нажатия — text")


func test_danger_contrast_with_text() -> void:
	for c: Color in [UiTokens.DANGER, UiTokens.DANGER_HOVER, UiTokens.DANGER_PRESSED]:
		assert_gte(UiTokens.contrast_ratio(UiTokens.TEXT, c), 4.5, "text на %s ≥ 4.5:1" % c.to_html(false))
	assert_gte(UiTokens.contrast_ratio(UiTokens.TEXT, _flat("hover", "DangerButton").bg_color), 4.5, "контраст стиля hover")
	assert_gte(UiTokens.contrast_ratio(UiTokens.TEXT, _flat("pressed", "DangerButton").bg_color), 4.5, "контраст стиля pressed")


func test_ghost_button_pressed_is_surface3() -> void:
	_assert_rgb(_flat("hover", "GhostButton").bg_color, UiTokens.SURFACE2, "наведение — surface2")
	_assert_rgb(_flat("pressed", "GhostButton").bg_color, UiTokens.SURFACE3, "нажатие — surface3")
	_assert_rgb(_flat("hover_pressed", "GhostButton").bg_color, UiTokens.SURFACE3, "hover_pressed — surface3")


# --- Цифры и надписи ------------------------------------------------------------------------

func test_num_label() -> void:
	assert_eq(_theme.get_font_size("font_size", "NumLabel"), 16)
	assert_eq(_weight(_theme.get_font("font", "NumLabel")), 600)
	assert_eq(_theme.get_font("font", "NumLabel").resource_path, "res://src/ui/theme/fonts/inter_num_600.tres")
	_assert_rgb(_theme.get_color("font_color", "NumLabel"), UiTokens.TEXT, "цвет — text")
	_assert_tabular("NumLabel", 16)


func test_hud_chip_label() -> void:
	assert_eq(_theme.get_font_size("font_size", "HudChipLabel"), 18)
	assert_eq(_weight(_theme.get_font("font", "HudChipLabel")), 750)
	_assert_rgb(_theme.get_color("font_color", "HudChipLabel"), UiTokens.HUD_TEXT, "цвет — hud.text")
	_assert_tabular("HudChipLabel", 18)


func test_hud_pause_card_and_title() -> void:
	var card := _flat("panel", "HudPauseCard")
	assert_not_null(card)
	if card != null:
		_assert_rgb(card.bg_color, UiTokens.SURFACE1, "фон — surface1 (#171B22)")
		assert_almost_eq(card.bg_color.a, 0.94, 0.002, "альфа 0.94")
		assert_eq(card.corner_radius_top_left, 18, "радиус 18")
		assert_eq(card.corner_radius_bottom_right, 18, "радиус 18")
		assert_eq(_border_sum(card), 0, "без рамки")
	assert_eq(_theme.get_font_size("font_size", "HudPauseTitle"), 30)
	assert_eq(_weight(_theme.get_font("font", "HudPauseTitle")), 750)
	_assert_rgb(_theme.get_color("font_color", "HudPauseTitle"), UiTokens.HUD_TEXT, "цвет — hud.text")


func test_spinbox_field_uses_tabular_font() -> void:
	var font := _theme.get_font("font", "SpinBoxInnerLineEdit")
	assert_eq(font.resource_path, "res://src/ui/theme/fonts/inter_num_600.tres", "шрифт поля SpinBox — inter_num_600")
	assert_eq(_theme.get_font_size("font_size", "SpinBoxInnerLineEdit"), 16)
	var spin := SpinBox.new()
	add_child_autofree(spin)
	var field := spin.get_line_edit()
	assert_eq(field.theme_type_variation, &"SpinBoxInnerLineEdit", "Godot 4.7: вариация внутреннего поля")
	assert_eq(field.get_theme_font("font"), font, "поле SpinBox получает шрифт цифр из темы проекта")
	assert_eq(field.get_theme_stylebox("normal"), _theme.get_stylebox("normal", "LineEdit"), "стиль поля — от LineEdit")


func test_overline_tracking() -> void:
	var fv := _theme.get_font("font", "OverlineLabel") as FontVariation
	assert_not_null(fv)
	if fv == null:
		return
	assert_eq(_weight(fv), 700, "вес 700")
	assert_eq(_theme.get_font_size("font_size", "OverlineLabel"), 12)
	assert_eq(fv.spacing_glyph, roundi(12 * UiTokens.OVERLINE_TRACKING), "разрядка +6 % от 12 — ближайшее целое px")
	var plain: Font = load("res://src/ui/theme/fonts/inter_700.tres")
	var text := "ТРЕНИРОВКА ПО ПЛАНУ"
	var w_plain := plain.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var w_tracked := fv.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	assert_gt(w_tracked, w_plain, "разрядка видна в ширине строки")


# --- Иконки баннера и помощник --------------------------------------------------------------

func test_banner_icons_imported_like_others() -> void:
	for name in BANNER_ICONS:
		var tex: Texture2D = load(LUCIDE_DIR + name + ".svg")
		assert_not_null(tex, name)
		if tex == null:
			continue
		assert_true(tex is DPITexture, "%s: DPITexture" % name)
		assert_eq(tex.get_size(), Vector2(24, 24), "%s: 24×24 lp" % name)
		var svg := FileAccess.get_file_as_string(LUCIDE_DIR + name + ".svg")
		assert_false(svg.contains("currentColor"), "%s: currentColor заменён" % name)
		assert_string_contains(svg, "stroke=\"#ffffff\"")
	var readme := FileAccess.get_file_as_string(LUCIDE_DIR + "README.md")
	for name in BANNER_ICONS:
		assert_string_contains(readme, "`%s`" % name)


func test_ui_icons_helper() -> void:
	UiIcons.clear_cache()
	var a := UiIcons.icon("bluetooth-off")
	assert_not_null(a)
	assert_true(a is DPITexture, "иконка — импортированная DPITexture")
	assert_eq(a.resource_path, LUCIDE_DIR + "bluetooth-off.svg")
	assert_same(UiIcons.icon("bluetooth-off"), a, "кэш: та же текстура")
	assert_null(UiIcons.icon(""), "пустое имя — без иконки")
	assert_true(UiIcons.has("info"))
	assert_false(UiIcons.has("no-such-icon"))
	assert_false(UiIcons.has(""))
	for name in [UiIcons.BANNER_INFO, UiIcons.BANNER_WARN, UiIcons.BANNER_ERROR]:
		assert_not_null(UiIcons.icon(name), "иконка баннера %s" % name)


# --- Помощники ------------------------------------------------------------------------------

func _flat(name: String, type: String) -> StyleBoxFlat:
	return _theme.get_stylebox(name, type) as StyleBoxFlat


func _border_sum(box: StyleBoxFlat) -> int:
	return box.border_width_left + box.border_width_top + box.border_width_right + box.border_width_bottom


func _weight(font: Font) -> int:
	var fv := font as FontVariation
	if fv == null:
		return 0
	return int(fv.variation_opentype.get(TextServerManager.get_primary_interface().name_to_tag("wght"), 0))


func _assert_tabular(type: String, base_size: int) -> void:
	var fv := _theme.get_font("font", type) as FontVariation
	assert_not_null(fv, type)
	if fv == null:
		return
	assert_eq(int(fv.opentype_features.get(TextServerManager.get_primary_interface().name_to_tag("tnum"), 0)), 1, "%s: tnum" % type)
	# Кегль при `s` 1.0 … 1.8.
	for size in [base_size, roundi(base_size * 1.2), roundi(base_size * 1.8)]:
		var w0 := fv.get_string_size("0000", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var w1 := fv.get_string_size("1111", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var w8 := fv.get_string_size("8888", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		assert_almost_eq(w1, w0, 0.5, "%s @%d: «1111» = «0000»" % [type, size])
		assert_almost_eq(w8, w0, 0.5, "%s @%d: «8888» = «0000»" % [type, size])


func _assert_rgb(actual: Color, expected: Color, msg: String) -> void:
	var ok := absf(actual.r - expected.r) <= CHANNEL_TOLERANCE and absf(actual.g - expected.g) <= CHANNEL_TOLERANCE and absf(actual.b - expected.b) <= CHANNEL_TOLERANCE
	assert_true(ok, "%s: %s ≠ %s" % [msg, actual.to_html(), expected.to_html()])
