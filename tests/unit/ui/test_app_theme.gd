extends GutTest
## Тема приложения и шрифт (T-060): REQ-UIX-01 крит. 1, 3, 4; REQ-HUD-14 крит. 1, 2.
## Дизайн — `docs/game/ui.md` п. 4, 9; `docs/game/hud.md` п. 5.2, 11.

const THEME_PATH: String = "res://src/ui/theme/app_theme.tres"
const INTER_TTF: String = "res://assets/fonts/inter/Inter-Variable.ttf"
const INTER_RES: String = "res://assets/fonts/inter/Inter-Variable.res"
const DEFAULT_FONT: String = "res://src/ui/theme/fonts/inter_400.tres"
## Экраны приложения, которые сейчас есть (`src/app/main.gd`), и карточка заезда.
const SCREENS: Array[String] = [
	"res://src/ui/profile_select/profile_select.tscn",
	"res://src/ui/home/home.tscn",
	"res://src/ui/dev/dev_screen.tscn",
	"res://src/ui/devices/devices_screen.tscn",
	"res://src/ui/workout/workout_screen.tscn",
	"res://src/ui/settings/settings_screen.tscn",
	"res://src/ui/plan/plan_screen.tscn",
	"res://src/ui/history/history_screen.tscn",
	"res://src/ui/history/ride_detail.tscn",
	"res://src/ui/tracks/route_select_screen.tscn",
	"res://src/ui/free_ride/free_ride_screen.tscn",
]
## Вариации `ui.md` п. 9.2 и их базовые типы.
const EXPECTED_VARIATIONS: Dictionary = {
	"DisplayLabel": "Label", "H1Label": "Label", "H2Label": "Label", "TitleLabel": "Label",
	"BodyStrongLabel": "Label", "SecondaryLabel": "Label", "CaptionLabel": "Label",
	"OverlineLabel": "Label", "StatLabel": "Label", "StatLargeLabel": "Label", "ErrorLabel": "Label",
	"PrimaryButton": "Button", "GhostButton": "Button", "DangerButton": "Button",
	"IconButton": "Button", "ChipButton": "Button", "CardButton": "Button",
	"ScenarioCard": "CardButton", "ListRowButton": "CardButton",
	"AppBar": "PanelContainer", "InsetPanel": "PanelContainer",
	"BannerWarn": "PanelContainer", "BannerError": "PanelContainer", "BannerInfo": "PanelContainer",
	"HudPlate": "PanelContainer", "HudCard": "PanelContainer",
	"HudHeroLabel": "Label", "HudTargetLabel": "Label", "HudValueLabel": "Label",
	"HudStripLabel": "Label", "HudUnitLabel": "Label", "HudCaptionLabel": "Label", "HudButton": "Button",
	"Stack8": "VBoxContainer", "Stack12": "VBoxContainer", "Stack16": "VBoxContainer", "Stack24": "VBoxContainer",
	"ScreenMargin": "MarginContainer", "CardMargin": "MarginContainer",
}
const CHANNEL_TOLERANCE: float = 1.0 / 255.0 + 0.0001

var _theme: Theme


func before_all() -> void:
	_theme = load(THEME_PATH)


# --- UIX-01 крит. 1: одна тема, назначенная проекту; её получает каждый экран -------------------

func test_req_uix_01_c1_project_theme_is_app_theme() -> void:
	assert_eq(ProjectSettings.get_setting("gui/theme/custom"), THEME_PATH)
	assert_eq(ProjectSettings.get_setting("gui/theme/custom_font"), DEFAULT_FONT)
	var project_theme := ThemeDB.get_project_theme()
	assert_not_null(project_theme, "тема проекта загружена")
	assert_eq(project_theme.resource_path, THEME_PATH)
	assert_eq(project_theme.default_font.resource_path, DEFAULT_FONT)


func test_req_uix_01_c1_every_screen_gets_project_theme() -> void:
	var label_font: Font = _theme.get_font("font", "Label")
	for path in SCREENS:
		var scene: PackedScene = load(path)
		assert_not_null(scene, path)
		var root := scene.instantiate() as Control
		assert_not_null(root, "%s: корень — Control" % path)
		if root == null:
			continue
		assert_null(root.theme, "%s: своя тема у корня не задана" % path)
		assert_eq(root.get_theme_font("font", "Label"), label_font, "%s: шрифт Label из темы проекта" % path)
		assert_eq(root.get_theme_color("font_color", "Label"), UiTokens.TEXT, "%s: цвет текста из темы проекта" % path)
		assert_eq(root.get_theme_stylebox("normal", "Button"), _theme.get_stylebox("normal", "Button"), "%s: стиль кнопки из темы проекта" % path)
		root.free()


func test_req_uix_01_c4_screen_background_is_bg() -> void:
	var clear: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color")
	_assert_rgb(clear, UiTokens.BG, "фон экранов (цвет очистки окна) — bg")


# --- UIX-01 крит. 3: стили компонентов и вариации ---------------------------------------------

func test_req_uix_01_c3_variations_exist() -> void:
	for name: String in EXPECTED_VARIATIONS:
		assert_true(_theme.is_type_variation(name, EXPECTED_VARIATIONS[name]), "вариация %s от %s" % [name, EXPECTED_VARIATIONS[name]])


func test_req_uix_01_c3_base_types_styled() -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		assert_true(_theme.has_stylebox(state, "Button"), "Button.%s" % state)
		for variation in ["PrimaryButton", "GhostButton", "DangerButton", "IconButton", "ChipButton", "CardButton", "ScenarioCard", "ListRowButton", "HudButton"]:
			assert_true(_theme.has_stylebox(state, variation), "%s.%s" % [variation, state])
	for pair in [["normal", "LineEdit"], ["focus", "LineEdit"], ["read_only", "LineEdit"], ["normal", "OptionButton"],
			["panel", "PanelContainer"], ["panel", "PopupMenu"], ["slider", "HSlider"], ["grabber_area", "HSlider"],
			["background", "ProgressBar"], ["fill", "ProgressBar"], ["grabber", "VScrollBar"], ["panel", "TooltipPanel"],
			["separator", "HSeparator"], ["panel", "ItemList"], ["selected", "ItemList"], ["embedded_border", "Window"],
			["panel", "AcceptDialog"], ["panel", "AppBar"], ["panel", "InsetPanel"], ["panel", "BannerWarn"],
			["panel", "BannerError"], ["panel", "BannerInfo"], ["panel", "HudPlate"], ["panel", "HudCard"]]:
		assert_true(_theme.has_stylebox(pair[0], pair[1]), "%s.%s" % [pair[1], pair[0]])
	for pair in [["checked", "CheckButton"], ["unchecked", "CheckButton"], ["grabber", "HSlider"], ["arrow", "OptionButton"], ["up", "SpinBox"], ["down", "SpinBox"]]:
		var icon := _theme.get_icon(pair[0], pair[1])
		assert_not_null(icon, "%s.%s" % [pair[1], pair[0]])
	assert_eq(_theme.get_icon("checked", "CheckButton").get_size(), Vector2(44, 26), "переключатель 44×26")
	assert_eq(_theme.get_icon("grabber", "HSlider").get_size(), Vector2(22, 22), "бегунок 22")
	assert_eq(_theme.get_icon("arrow", "OptionButton").get_size(), Vector2(16, 16), "шеврон 16")
	assert_eq(_theme.get_constant("icon_max_width", "CheckButton"), 0, "переключатель не сжимается до icon_max_width кнопки")
	assert_eq(_theme.get_constant("separation", "Stack16"), 16)
	assert_eq(_theme.get_constant("margin_left", "ScreenMargin"), 32)
	assert_eq(_theme.get_constant("margin_top", "ScreenMargin"), 24)


func test_req_uix_01_c3_typography_sizes() -> void:
	var sizes := {
		"Label": 16, "DisplayLabel": 40, "H1Label": 28, "H2Label": 22, "TitleLabel": 18,
		"BodyStrongLabel": 16, "SecondaryLabel": 14, "CaptionLabel": 13, "OverlineLabel": 12,
		"StatLabel": 22, "StatLargeLabel": 32, "ErrorLabel": 13,
		"HudHeroLabel": 88, "HudTargetLabel": 40, "HudValueLabel": 34, "HudStripLabel": 24,
		"HudUnitLabel": 14, "HudCaptionLabel": 12, "HudZoneChipLabel": 12,
	}
	for type: String in sizes:
		assert_eq(_theme.get_font_size("font_size", type), sizes[type], "%s: размер" % type)
	var weights := {
		"Label": 400, "DisplayLabel": 750, "H1Label": 750, "H2Label": 700, "TitleLabel": 650,
		"BodyStrongLabel": 600, "SecondaryLabel": 500, "CaptionLabel": 500, "OverlineLabel": 700,
		"StatLabel": 700, "StatLargeLabel": 750, "HudHeroLabel": 800, "HudTargetLabel": 750,
		"HudValueLabel": 700, "HudStripLabel": 650, "HudUnitLabel": 500, "HudCaptionLabel": 650,
	}
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	for type: String in weights:
		var fv := _theme.get_font("font", type) as FontVariation
		assert_not_null(fv, type)
		if fv != null:
			assert_eq(int(fv.variation_opentype.get(wght, 0)), weights[type], "%s: вес" % type)
	for type in ["StatLabel", "StatLargeLabel", "HudHeroLabel", "HudTargetLabel", "HudValueLabel", "HudStripLabel"]:
		assert_true(_has_tnum(_theme.get_font("font", type)), "%s: моноширинные цифры" % type)


# --- UIX-01 крит. 4: цвета стилей равны палитре -------------------------------------------------

func test_req_uix_01_c4_key_colors() -> void:
	_assert_rgb(UiTokens.BG, Color("#0E1116"), "bg")
	_assert_rgb(UiTokens.ACCENT, Color("#2CC9B4"), "accent — решение владельца")
	_assert_rgb(_flat("normal", "Button").bg_color, UiTokens.SURFACE2, "вторичная кнопка — surface2")
	_assert_rgb(_flat("normal", "Button").border_color, UiTokens.LINE_STRONG, "рамка вторичной кнопки")
	_assert_rgb(_flat("normal", "PrimaryButton").bg_color, UiTokens.ACCENT, "основная кнопка — accent")
	_assert_rgb(_flat("pressed", "PrimaryButton").bg_color, UiTokens.ACCENT_PRESSED, "нажатая основная")
	_assert_rgb(_theme.get_color("font_color", "PrimaryButton"), UiTokens.ON_ACCENT, "текст на accent")
	_assert_rgb(_flat("normal", "DangerButton").bg_color, UiTokens.DANGER, "опасная кнопка")
	_assert_rgb(_flat("normal", "LineEdit").bg_color, UiTokens.INSET, "поле — inset")
	_assert_rgb(_flat("focus", "LineEdit").border_color, UiTokens.ACCENT, "фокус поля — accent")
	_assert_rgb(_flat("panel", "PanelContainer").bg_color, UiTokens.SURFACE1, "карточка — surface1")
	_assert_rgb(_flat("panel", "AppBar").bg_color, UiTokens.BG, "панель приложения — bg")
	_assert_rgb(_flat("normal", "CardButton").border_color, UiTokens.LINE, "рамка карточки — line")
	_assert_rgb(_flat("pressed", "CardButton").border_color, UiTokens.ACCENT, "выбранная карточка — accent")
	_assert_rgb(_flat("focus", "Button").border_color, UiTokens.TEXT, "кольцо фокуса — text")
	_assert_rgb(_flat("panel", "HudPlate").bg_color, UiTokens.HUD_INK, "подложка HUD — hud.plate")
	assert_almost_eq(_flat("panel", "HudPlate").bg_color.a, 0.78, 0.002, "альфа hud.plate")
	assert_almost_eq(_flat("panel", "HudCard").bg_color.a, 0.55, 0.002, "альфа карточки цели")
	_assert_rgb(_theme.get_color("font_color", "Label"), UiTokens.TEXT, "текст — text")
	_assert_rgb(_theme.get_color("font_color", "SecondaryLabel"), UiTokens.TEXT2, "вторичный — text2")
	_assert_rgb(_theme.get_color("font_color", "HudHeroLabel"), UiTokens.HUD_TEXT, "цифры HUD — hud.text")
	_assert_rgb(_theme.get_color("font_color", "HudZoneChipLabel"), UiTokens.HUD_INK, "текст фишки зоны — hud.ink")


func test_req_uix_01_c4_all_style_colors_come_from_tokens() -> void:
	var palette := _palette()
	var offenders: Array[String] = []
	for type in _theme.get_type_list():
		for name in _theme.get_stylebox_list(type):
			var box := _theme.get_stylebox(name, type) as StyleBoxFlat
			if box == null:
				continue
			if box.draw_center and box.bg_color.a > 0.0 and not _in_palette(box.bg_color, palette):
				offenders.append("%s.%s bg %s" % [type, name, box.bg_color.to_html()])
			var has_border := box.border_width_left + box.border_width_top + box.border_width_right + box.border_width_bottom > 0
			if has_border and not _in_palette(box.border_color, palette):
				offenders.append("%s.%s border %s" % [type, name, box.border_color.to_html()])
			if box.shadow_size > 0 and not _in_palette(box.shadow_color, palette):
				offenders.append("%s.%s shadow %s" % [type, name, box.shadow_color.to_html()])
		for name in _theme.get_color_list(type):
			var c := _theme.get_color(name, type)
			if not _in_palette(c, palette):
				offenders.append("%s.%s %s" % [type, name, c.to_html()])
	assert_eq(offenders, [] as Array[String], "цвета темы вне палитры UiTokens (±1/255)")


func test_tokens_contrast_matches_design() -> void:
	# ui.md п. 4 (UIX-01 крит. 5) и hud.md п. 9 (HUD-14 крит. 4) — проверка значений токенов.
	for bg in [UiTokens.BG, UiTokens.SURFACE1, UiTokens.SURFACE2]:
		assert_gte(UiTokens.contrast_ratio(UiTokens.TEXT, bg), 4.5)
		assert_gte(UiTokens.contrast_ratio(UiTokens.TEXT2, bg), 4.5)
	assert_gte(UiTokens.contrast_ratio(UiTokens.ON_ACCENT, UiTokens.ACCENT), 4.5)
	var lightest := UiTokens.blend_over(UiTokens.HUD_PLATE, Color(0.95, 0.96, 0.98))
	assert_gte(UiTokens.contrast_ratio(UiTokens.HUD_TEXT, lightest), 4.5)
	assert_gte(UiTokens.contrast_ratio(UiTokens.HUD_TEXT2, lightest), 4.5)


func test_grade_palette() -> void:
	assert_eq(UiTokens.grade_color(-5.0), UiTokens.GRADE_COLORS[0])
	assert_eq(UiTokens.grade_color(-2.0), UiTokens.GRADE_COLORS[1])
	assert_eq(UiTokens.grade_color(0.0), UiTokens.GRADE_COLORS[1])
	assert_eq(UiTokens.grade_color(3.0), UiTokens.GRADE_COLORS[2])
	assert_eq(UiTokens.grade_color(6.9), UiTokens.GRADE_COLORS[3])
	assert_eq(UiTokens.grade_color(7.0), UiTokens.GRADE_COLORS[4])
	assert_eq(UiTokens.grade_color(12.0), UiTokens.GRADE_COLORS[5])


# --- HUD-14 крит. 1, 2 и UIX-01 крит. 6 (часть «шрифт»): один файл Inter, tnum -------------------

func test_req_hud_14_c1_all_theme_fonts_from_one_inter_file() -> void:
	var fonts: Array[Font] = [_theme.default_font]
	for type in _theme.get_type_list():
		for name in _theme.get_font_list(type):
			fonts.append(_theme.get_font(name, type))
	for path in DirAccess.get_files_at("res://src/ui/theme/fonts"):
		if path.ends_with(".tres"):
			fonts.append(load("res://src/ui/theme/fonts/" + path))
	assert_gt(fonts.size(), 20)
	for font in fonts:
		var fv := font as FontVariation
		assert_not_null(fv, "начертание %s — FontVariation" % font)
		if fv != null:
			assert_eq(fv.base_font.resource_path, INTER_RES, "%s: файл Inter" % fv.resource_path)


func test_req_hud_14_c1_inter_resource_is_the_official_ttf() -> void:
	var ff: FontFile = load(INTER_RES)
	assert_eq(ff.data, FileAccess.get_file_as_bytes(INTER_TTF), "ресурс шрифта — байты официального Inter-Variable.ttf")
	assert_eq(ff.get_font_name(), "Inter Variable")
	assert_true(FileAccess.file_exists("res://assets/fonts/inter/OFL.txt"), "лицензия OFL рядом со шрифтом")
	assert_string_contains(FileAccess.get_file_as_string("res://assets/fonts/inter/OFL.txt"), "SIL OPEN FONT LICENSE Version 1.1")
	var axes := ff.get_supported_variation_list()
	var ts := TextServerManager.get_primary_interface()
	assert_true(axes.has(ts.name_to_tag("wght")) and axes.has(ts.name_to_tag("opsz")), "оси wght и opsz")
	assert_true(ff.has_char(0x0416), "кириллица (Ж)")


func test_req_hud_14_c2_tabular_digits_same_width() -> void:
	var numeric: Array[FontVariation] = []
	for path in DirAccess.get_files_at("res://src/ui/theme/fonts"):
		if path.begins_with("inter_num_") and path.ends_with(".tres"):
			numeric.append(load("res://src/ui/theme/fonts/" + path))
	assert_eq(numeric.size(), 5, "начертания цифр: 600, 650, 700, 750, 800")
	var mismatches: Array[String] = []
	for fv in numeric:
		assert_true(_has_tnum(fv), fv.resource_path)
		# 11·s … 88·s при s = 1.0 и 1.2.
		for size in range(11, 107):
			var w0 := fv.get_string_size("0000", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var w1 := fv.get_string_size("1111", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var w8 := fv.get_string_size("8888", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			if absf(w0 - w1) > 0.5 or absf(w0 - w8) > 0.5:
				mismatches.append("%s @%d: %s %s %s" % [fv.resource_path.get_file(), size, w0, w1, w8])
	assert_eq(mismatches, [] as Array[String], "REQ-HUD-14 крит. 2: «0000» = «1111» = «8888»")


# --- Иконки -------------------------------------------------------------------------------

func test_lucide_icons_present_with_license() -> void:
	var names := ["play", "pause", "square", "skip-forward", "bike", "mountain", "waves", "map", "history",
		"settings", "bluetooth", "bluetooth-off", "heart", "gauge", "refresh-cw", "clock", "flag",
		"trending-up", "chevron-left", "chevron-right", "chevron-up", "chevron-down", "plus", "upload",
		"cloud-upload", "check", "x", "trash-2", "ellipsis", "user", "zap", "sliders-horizontal", "battery", "signal"]
	for name in names:
		var tex: Texture2D = load("res://assets/icons/lucide/%s.svg" % name)
		assert_not_null(tex, name)
		if tex != null:
			assert_eq(tex.get_size(), Vector2(24, 24), "%s: 24×24 lp" % name)
	var license := FileAccess.get_file_as_string("res://assets/icons/lucide/LICENSE")
	assert_string_contains(license, "ISC License")
	assert_string_contains(license, "Cole Bemis")


# --- Сохранённая тема совпадает со сборкой по токенам ---------------------------------------

func test_saved_theme_matches_builder() -> void:
	var built := AppThemeBuilder.build(AppThemeBuilder.load_fonts())
	var diffs: Array[String] = []
	var types := built.get_type_list()
	types.sort()
	var saved_types := _theme.get_type_list()
	saved_types.sort()
	assert_eq(saved_types, types, "набор типов темы")
	for type in types:
		if built.get_type_variation_base(type) != _theme.get_type_variation_base(type):
			diffs.append("%s: базовый тип" % type)
		for name in built.get_color_list(type):
			if not _theme.has_color(name, type) or not _theme.get_color(name, type).is_equal_approx(built.get_color(name, type)):
				diffs.append("%s.%s color" % [type, name])
		for name in built.get_constant_list(type):
			if _theme.get_constant(name, type) != built.get_constant(name, type):
				diffs.append("%s.%s constant" % [type, name])
		for name in built.get_font_size_list(type):
			if _theme.get_font_size(name, type) != built.get_font_size(name, type):
				diffs.append("%s.%s font_size" % [type, name])
		for name in built.get_font_list(type):
			if _theme.get_font(name, type).resource_path != built.get_font(name, type).resource_path:
				diffs.append("%s.%s font" % [type, name])
		for name in built.get_stylebox_list(type):
			if not _theme.has_stylebox(name, type) or not _same_resource(_theme.get_stylebox(name, type), built.get_stylebox(name, type)):
				diffs.append("%s.%s stylebox" % [type, name])
		for name in built.get_icon_list(type):
			if not _theme.has_icon(name, type) or not _same_resource(_theme.get_icon(name, type), built.get_icon(name, type)):
				diffs.append("%s.%s icon" % [type, name])
	assert_eq(diffs, [] as Array[String], "app_theme.tres устарела — пересоберите src/ui/theme/tools/generate_theme.gd")


# --- Помощники ------------------------------------------------------------------------------

func _flat(name: String, type: String) -> StyleBoxFlat:
	return _theme.get_stylebox(name, type) as StyleBoxFlat


func _assert_rgb(actual: Color, expected: Color, msg: String) -> void:
	var ok := absf(actual.r - expected.r) <= CHANNEL_TOLERANCE and absf(actual.g - expected.g) <= CHANNEL_TOLERANCE and absf(actual.b - expected.b) <= CHANNEL_TOLERANCE
	assert_true(ok, "%s: %s ≠ %s" % [msg, actual.to_html(), expected.to_html()])


func _has_tnum(font: Font) -> bool:
	var fv := font as FontVariation
	if fv == null:
		return false
	return int(fv.opentype_features.get(TextServerManager.get_primary_interface().name_to_tag("tnum"), 0)) == 1


## Все цвета-токены `UiTokens` плюс производные, описанные в `ui.md` п. 9.2 (наведение
## основной и опасной кнопки светлее на 6 %).
func _palette() -> Array[Color]:
	var out: Array[Color] = []
	var constants: Dictionary = (UiTokens as Script).get_script_constant_map()
	for key in constants:
		var value: Variant = constants[key]
		if value is Color:
			out.append(value)
		elif value is Array:
			for item: Variant in value:
				if item is Color:
					out.append(item)
	out.append(UiTokens.ACCENT.lightened(UiTokens.ACCENT_HOVER_LIGHTEN))
	out.append(UiTokens.DANGER.lightened(UiTokens.ACCENT_HOVER_LIGHTEN))
	return out


func _in_palette(c: Color, palette: Array[Color]) -> bool:
	for p in palette:
		if absf(c.r - p.r) <= CHANNEL_TOLERANCE and absf(c.g - p.g) <= CHANNEL_TOLERANCE and absf(c.b - p.b) <= CHANNEL_TOLERANCE:
			return true
	return false


func _same_resource(a: Resource, b: Resource) -> bool:
	if a == null or b == null:
		return a == b
	if a.get_class() != b.get_class():
		return false
	for prop in a.get_property_list():
		if not (prop["usage"] & PROPERTY_USAGE_STORAGE):
			continue
		var name: String = prop["name"]
		if name.begins_with("resource_") or name == "script":
			continue
		var va: Variant = a.get(name)
		var vb: Variant = b.get(name)
		if va is Resource or vb is Resource:
			if not _same_resource(va, vb):
				return false
		elif va is Color and vb is Color:
			if not (va as Color).is_equal_approx(vb):
				return false
		elif va is float and vb is float:
			if not is_equal_approx(va, vb):
				return false
		elif va != vb:
			return false
	return true
