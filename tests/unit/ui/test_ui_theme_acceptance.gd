extends GutTest
## Независимые приёмочные тесты темы, шрифта и переводов (тестировщик, T-060).
## Покрытие: REQ-UIX-01 крит. 1, 3, 4; REQ-HUD-14 крит. 1, 2; REQ-NFR-08 крит. 2.
## Эталон цветов — таблицы `docs/game/ui.md` п. 4 и `docs/game/hud.md` п. 11, разобранные
## из самих документов (не `UiTokens`). Стили проверяются так, как их получает узел:
## через `theme_type_variation` у узла в дереве (эффективная тема, с цепочкой баз).

const MAIN_SCENE: String = "res://src/app/main.tscn"
const UI_MD: String = "res://docs/game/ui.md"
const HUD_MD: String = "res://docs/game/hud.md"
const TOL: float = 1.0 / 255.0 + 0.0001

var _palette: Dictionary = {}
var _hud: Dictionary = {}
var _dir: String = ""
var _prev_locale: String = ""


func before_all() -> void:
	_palette = _parse_tokens(UI_MD, "^\\|\\s*`([a-z0-9_]+)`\\s*\\|\\s*`(#[0-9A-Fa-f]{6})`")
	_hud = _parse_tokens(HUD_MD, "^\\|\\s*`(hud\\.[a-z0-9_]+)`\\s*\\|\\s*`(#[0-9A-Fa-f]{6})`")


func before_each() -> void:
	_dir = "user://test_theme_acc_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_prev_locale = TranslationServer.get_locale()


func after_each() -> void:
	TranslationServer.set_locale(_prev_locale)
	_remove_tree(ProjectSettings.globalize_path(_dir))


static func _parse_tokens(path: String, pattern: String) -> Dictionary:
	var re := RegEx.create_from_string(pattern)
	var out := {}
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var m := re.search(line)
		if m != null:
			out[m.get_string(1)] = Color(m.get_string(2))
	return out


static func _remove_tree(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var d := DirAccess.open(abs_path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)


func _rgb_eq(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) <= TOL and absf(a.g - b.g) <= TOL and absf(a.b - b.b) <= TOL


func _assert_rgb(actual: Color, token: String, what: String, alpha: float = -1.0) -> void:
	var expected: Color = _palette[token] if _palette.has(token) else _hud[token]
	assert_true(_rgb_eq(actual, expected), "%s: %s, ожидался %s (%s)" % [what, actual.to_html(), token, expected.to_html()])
	if alpha >= 0.0:
		assert_almost_eq(actual.a, alpha, 0.01, "%s: альфа" % what)


func _node(cls: String, variation: String) -> Control:
	var n: Control = ClassDB.instantiate(cls)
	n.theme_type_variation = variation
	add_child_autofree(n)
	return n


func _flat(n: Control, name: String) -> StyleBoxFlat:
	var sb := n.get_theme_stylebox(name)
	assert_true(sb is StyleBoxFlat, "%s.%s — StyleBoxFlat (факт %s)" % [n.theme_type_variation, name, sb])
	return sb as StyleBoxFlat


func _main() -> AppMain:
	ProfileRepository.new(_dir + "profiles/").create("Ника")
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	add_child_autofree(main)
	return main


static func _collect(node: Node, out: Array[Node], include_internal: bool = true) -> void:
	out.append(node)
	for c in node.get_children(include_internal):
		_collect(c, out, include_internal)


func test_preconditions_palette_parsed_from_docs() -> void:
	for token in ["bg", "surface1", "surface2", "surface3", "inset", "line", "line_strong", "text", "text2",
			"text_disabled", "accent", "accent_pressed", "on_accent", "sim", "warn", "danger", "danger_text"]:
		assert_true(_palette.has(token), "ui.md п. 4: токен %s" % token)
	assert_true(_hud.has("hud.ink") and _hud.has("hud.text") and _hud.has("hud.text2"))


# ===========================================================================
# REQ-UIX-01 крит. 1 — одна тема проекта, её получает каждый экран
# ===========================================================================

func test_req_uix_01_c1_exactly_one_theme_resource_and_it_is_project_theme() -> void:
	var themes: Array[String] = []
	for root in ["res://src", "res://assets"]:
		_find_themes(root, themes)
	assert_eq(themes.size(), 1, "в проекте один ресурс темы: %s" % str(themes))
	var path: String = str(ProjectSettings.get_setting("gui/theme/custom", ""))
	assert_eq(themes, [path] as Array[String], "этот ресурс назначен темой проекта")
	assert_eq(ThemeDB.get_project_theme().resource_path, path, "движок загрузил его как тему проекта")


func _find_themes(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".tres") or f.ends_with(".res"):
			var p := dir_path.path_join(f)
			if f.ends_with(".tres"):
				var head := FileAccess.get_file_as_string(p).substr(0, 200)
				if head.contains("type=\"Theme\""):
					out.append(p)
	for sub in d.get_directories():
		_find_themes(dir_path.path_join(sub), out)


func test_req_uix_01_c1_every_app_screen_effective_theme_is_project_theme() -> void:
	TranslationServer.set_locale("ru")
	var main := _main()
	var project_theme := ThemeDB.get_project_theme()
	var button_normal := project_theme.get_stylebox("normal", "Button")
	var label_font := project_theme.get_font("font", "Label")
	var foreign: Array[String] = []
	for screen: int in AppState.Screen.values():
		var node: Control = main.screen_node(screen)
		assert_not_null(node, "экран %s в оболочке" % AppState.screen_name(screen))
		if node == null:
			continue
		# Ни у экрана, ни у его предков нет своей темы — эффективная тема = тема проекта.
		var p: Node = node
		while p != null:
			if p is Control and (p as Control).theme != null and (p as Control).theme != project_theme:
				foreign.append("%s: предок %s" % [AppState.screen_name(screen), p.name])
			p = p.get_parent()
		var all: Array[Node] = []
		_collect(node, all)
		for n in all:
			if n is Control and (n as Control).theme != null and (n as Control).theme != project_theme:
				foreign.append("%s/%s" % [AppState.screen_name(screen), node.get_path_to(n)])
			if n is Window and (n as Window).theme != null and (n as Window).theme != project_theme:
				foreign.append("%s/%s (окно)" % [AppState.screen_name(screen), node.get_path_to(n)])
		assert_eq(node.get_theme_stylebox("normal", "Button"), button_normal, "%s: стиль Button из темы проекта" % AppState.screen_name(screen))
		assert_eq(node.get_theme_font("font", "Label"), label_font, "%s: шрифт Label из темы проекта" % AppState.screen_name(screen))
	assert_eq(foreign, [] as Array[String], "узлы со своей (чужой) темой")


# ===========================================================================
# REQ-UIX-01 крит. 3 — стили компонентов и вариации
# ===========================================================================

const BUTTON_VARIATIONS: Array[String] = ["PrimaryButton", "GhostButton", "DangerButton", "IconButton",
	"ChipButton", "CardButton", "ScenarioCard", "ListRowButton"]
const LABEL_VARIATIONS: Dictionary = {"H1Label": 28, "H2Label": 22, "TitleLabel": 18, "CaptionLabel": 13,
	"OverlineLabel": 12, "StatLabel": 22}
const PANEL_VARIATIONS: Array[String] = ["AppBar", "BannerWarn", "BannerError", "BannerInfo"]


func _base_chain(theme: Theme, variation: String) -> Array[String]:
	var chain: Array[String] = [variation]
	var cur := variation
	for i in 8:
		var base: StringName = theme.get_type_variation_base(cur)
		if base == &"":
			break
		chain.append(str(base))
		cur = str(base)
	return chain


func test_req_uix_01_c3_required_component_variations_resolve_to_proper_base() -> void:
	var theme := ThemeDB.get_project_theme()
	for v in BUTTON_VARIATIONS:
		var chain := _base_chain(theme, v)
		assert_eq(chain[chain.size() - 1], "Button", "%s — вариация кнопки (%s)" % [v, " → ".join(chain)])
		var b := _node("Button", v)
		for state in ["normal", "hover", "pressed", "focus"]:
			assert_true(theme.has_stylebox(state, v) or chain.size() > 2, "%s.%s задан в теме" % [v, state])
		assert_ne(b.get_theme_stylebox("normal"), theme.get_stylebox("normal", "Button"), "%s отличается от базовой кнопки" % v)
	for v: String in LABEL_VARIATIONS:
		assert_eq(_base_chain(theme, v).back(), "Label", "%s — вариация Label" % v)
		assert_eq(_node("Label", v).get_theme_font_size("font_size"), LABEL_VARIATIONS[v], "%s: размер (ui.md п. 5)" % v)
	for v in PANEL_VARIATIONS:
		assert_eq(_base_chain(theme, v).back(), "PanelContainer", "%s — вариация панели" % v)
		assert_true(theme.has_stylebox("panel", v), "%s.panel задан" % v)
	# Базовые типы.
	for pair in [["normal", "Button"], ["normal", "LineEdit"], ["panel", "PanelContainer"]]:
		assert_true(theme.has_stylebox(pair[0], pair[1]), "%s.%s" % [pair[1], pair[0]])


func test_req_uix_01_c3_every_button_on_screens_uses_theme_button_or_its_variation() -> void:
	TranslationServer.set_locale("ru")
	var main := _main()
	var theme := ThemeDB.get_project_theme()
	var bad: Array[String] = []
	var checked: int = 0
	for screen: int in AppState.Screen.values():
		var node: Control = main.screen_node(screen)
		var all: Array[Node] = []
		# Только кнопки сцен экранов; внутренние узлы движковых диалогов (FileDialog) не в счёт.
		_collect(node, all, false)
		for n in all:
			if not (n is Button):
				continue
			# «Connect with Strava» — фирменная кнопка по брендбуку Strava (STR-01), см. отчёт.
			if _inside_strava_button(n):
				continue
			checked += 1
			var b := n as Button
			var where := "%s/%s" % [AppState.screen_name(screen), node.get_path_to(b)]
			var v: String = str(b.theme_type_variation)
			if not v.is_empty():
				var chain := _base_chain(theme, v)
				if chain.size() < 2 or not (chain.back() in ["Button", b.get_class()]):
					bad.append("%s: вариация %s не из темы" % [where, v])
			for state in ["normal", "hover", "pressed"]:
				if b.has_theme_stylebox_override(state):
					bad.append("%s: свой стиль %s" % [where, state])
	assert_gt(checked, 10, "кнопки на экранах найдены")
	assert_eq(bad, [] as Array[String], "кнопки только со стилем темы")


static func _inside_strava_button(n: Node) -> bool:
	var p: Node = n
	while p != null:
		if p is StravaConnectButton:
			return true
		p = p.get_parent()
	return false


# ===========================================================================
# REQ-UIX-01 крит. 4 — тёмная тема, акцент, цвета стилей = палитра ui.md п. 4
# ===========================================================================

func test_req_uix_01_c4_background_bg_and_accent_value() -> void:
	var clear: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color")
	_assert_rgb(clear, "bg", "фон окна (цвет очистки)")
	assert_eq(_palette["bg"], Color("#0E1116"), "bg — решение владельца")
	assert_eq(_palette["accent"], Color("#2CC9B4"), "accent — решение владельца")


func test_req_uix_01_c4_button_family_colors() -> void:
	var b := _node("Button", "")
	_assert_rgb(_flat(b, "normal").bg_color, "surface2", "Button.normal фон")
	_assert_rgb(_flat(b, "normal").border_color, "line_strong", "Button.normal рамка")
	_assert_rgb(_flat(b, "hover").bg_color, "surface3", "Button.hover фон")
	_assert_rgb(_flat(b, "pressed").border_color, "accent", "Button.pressed рамка")
	_assert_rgb(_flat(b, "focus").border_color, "text", "Button.focus кольцо")
	_assert_rgb(b.get_theme_color("font_color"), "text", "Button.font_color")
	_assert_rgb(b.get_theme_color("font_disabled_color"), "text_disabled", "Button.font_disabled_color")
	var primary := _node("Button", "PrimaryButton")
	_assert_rgb(_flat(primary, "normal").bg_color, "accent", "PrimaryButton.normal")
	_assert_rgb(_flat(primary, "pressed").bg_color, "accent_pressed", "PrimaryButton.pressed")
	_assert_rgb(primary.get_theme_color("font_color"), "on_accent", "PrimaryButton.font_color")
	var hover := _flat(primary, "hover").bg_color
	assert_gt(hover.get_luminance(), (_palette["accent"] as Color).get_luminance(), "наведение основной — светлее акцента")
	var ghost := _node("Button", "GhostButton")
	assert_true(ghost.get_theme_stylebox("normal") is StyleBoxEmpty, "GhostButton без фона")
	_assert_rgb(_flat(ghost, "hover").bg_color, "surface2", "GhostButton.hover")
	_assert_rgb(ghost.get_theme_color("font_color"), "text2", "GhostButton.font_color")
	_assert_rgb(ghost.get_theme_color("font_hover_color"), "text", "GhostButton.font_hover_color")
	var danger := _node("Button", "DangerButton")
	_assert_rgb(_flat(danger, "normal").bg_color, "danger", "DangerButton.normal")
	_assert_rgb(danger.get_theme_color("font_color"), "text", "DangerButton.font_color")
	_assert_rgb(_flat(_node("Button", "IconButton"), "normal").bg_color, "surface1", "IconButton.normal")
	_assert_rgb(_flat(_node("Button", "ChipButton"), "normal").bg_color, "surface1", "ChipButton.normal")
	var card := _node("Button", "CardButton")
	_assert_rgb(_flat(card, "normal").bg_color, "surface1", "CardButton.normal фон")
	_assert_rgb(_flat(card, "normal").border_color, "line", "CardButton.normal рамка")
	_assert_rgb(_flat(card, "hover").border_color, "accent", "CardButton.hover рамка", 0.6)
	_assert_rgb(_flat(card, "pressed").bg_color, "surface2", "CardButton выбрана — фон")
	_assert_rgb(_flat(card, "pressed").border_color, "accent", "CardButton выбрана — рамка")
	_assert_rgb(_flat(card, "focus").border_color, "text", "CardButton фокус")
	var row := _node("Button", "ListRowButton")
	_assert_rgb(_flat(row, "hover").bg_color, "surface2", "ListRowButton.hover")
	_assert_rgb(_flat(row, "pressed").bg_color, "surface3", "ListRowButton.pressed")


func test_req_uix_01_c4_fields_panels_banners_labels_colors() -> void:
	var le := _node("LineEdit", "")
	_assert_rgb(_flat(le, "normal").bg_color, "inset", "LineEdit.normal фон")
	_assert_rgb(_flat(le, "normal").border_color, "line_strong", "LineEdit.normal рамка")
	_assert_rgb(_flat(le, "focus").border_color, "accent", "LineEdit.focus рамка")
	_assert_rgb(le.get_theme_color("caret_color"), "accent", "LineEdit.caret_color")
	_assert_rgb(le.get_theme_color("font_placeholder_color"), "text_disabled", "LineEdit.placeholder")
	var panel := _node("PanelContainer", "")
	_assert_rgb(_flat(panel, "panel").bg_color, "surface1", "PanelContainer фон")
	_assert_rgb(_flat(panel, "panel").border_color, "line", "PanelContainer рамка")
	_assert_rgb(_flat(_node("PanelContainer", "AppBar"), "panel").bg_color, "bg", "AppBar")
	_assert_rgb(_flat(_node("PanelContainer", "InsetPanel"), "panel").bg_color, "inset", "InsetPanel")
	_assert_rgb(_flat(_node("PanelContainer", "BannerWarn"), "panel").bg_color, "warn", "BannerWarn", 0.12)
	_assert_rgb(_flat(_node("PanelContainer", "BannerError"), "panel").bg_color, "danger_text", "BannerError", 0.12)
	_assert_rgb(_flat(_node("PanelContainer", "BannerInfo"), "panel").bg_color, "accent", "BannerInfo", 0.12)
	_assert_rgb(_node("Label", "").get_theme_color("font_color"), "text", "Label")
	_assert_rgb(_node("Label", "SecondaryLabel").get_theme_color("font_color"), "text2", "SecondaryLabel")
	_assert_rgb(_node("Label", "CaptionLabel").get_theme_color("font_color"), "text2", "CaptionLabel")
	_assert_rgb(_node("Label", "ErrorLabel").get_theme_color("font_color"), "danger_text", "ErrorLabel")


## Все цвета стилей и шрифтов темы — из палитры ui.md п. 4 / hud.md п. 11 (±1/255 по каналу,
## любая альфа); исключения — производные «наведение светлее на 6 %» и нейтральные
## чёрный/белый (тень, штриховка). Цвета зон — из `ZonePalette` (фишка зоны).
func test_req_uix_01_c4_all_theme_colors_belong_to_palette() -> void:
	var theme := ThemeDB.get_project_theme()
	var allowed: Array[Color] = []
	for c: Color in _palette.values():
		allowed.append(c)
	for c: Color in _hud.values():
		allowed.append(c)
	allowed.append(Color(0.62, 0.65, 0.72)) # hud.free (hud.md п. 11, задан кортежем)
	allowed.append(Color.BLACK)
	allowed.append(Color.WHITE)
	for c: Color in ZonePalette.COLORS.values():
		allowed.append(c)
	var foreign: Array[String] = []
	for type in theme.get_type_list():
		for name in theme.get_color_list(type):
			_check_color(theme.get_color(name, type), "%s.%s" % [type, name], allowed, foreign)
		for name in theme.get_stylebox_list(type):
			var sb := theme.get_stylebox(name, type) as StyleBoxFlat
			if sb == null:
				continue
			_check_color(sb.bg_color, "%s.%s.bg" % [type, name], allowed, foreign)
			if sb.border_width_left + sb.border_width_top + sb.border_width_right + sb.border_width_bottom > 0:
				_check_color(sb.border_color, "%s.%s.border" % [type, name], allowed, foreign)
	assert_eq(foreign, [] as Array[String], "цвета вне палитры")


func _check_color(c: Color, where: String, allowed: Array[Color], foreign: Array[String]) -> void:
	if c.a <= 0.001:
		return
	for a in allowed:
		if _rgb_eq(c, a):
			return
	# «Наведение светлее на 6 %» (ui.md п. 9.2): светлее одного из цветов палитры не больше чем на 0.1 по каналу.
	if where.contains("hover"):
		for a in allowed:
			if c.get_luminance() > a.get_luminance() and absf(c.r - a.r) <= 0.1 and absf(c.g - a.g) <= 0.1 and absf(c.b - a.b) <= 0.1:
				return
	foreign.append("%s = %s" % [where, c.to_html()])


func test_req_uix_01_c4_no_light_theme_switch_in_settings() -> void:
	TranslationServer.set_locale("ru")
	var main := _main()
	main.app_state.navigate(AppState.Screen.SETTINGS)
	var all: Array[Node] = []
	_collect(main.screen_node(AppState.Screen.SETTINGS), all)
	var found: Array[String] = []
	for n in all:
		var text := ""
		if n is Button:
			text = (n as Button).text
		elif n is Label:
			text = (n as Label).text
		if n is OptionButton:
			for i in (n as OptionButton).item_count:
				text += " " + (n as OptionButton).get_item_text(i)
		var low := text.to_lower()
		if low.contains("светл") or low.contains("тёмн") or low.contains("темн") or low.contains("тема") or low.contains("theme"):
			found.append(text)
	assert_eq(found, [] as Array[String], "переключателя темы нет")


# ===========================================================================
# REQ-HUD-14 крит. 1, 2 — один файл Inter, моноширинные цифры
# ===========================================================================

const HUD_NUMERIC: Array[String] = ["HudHeroLabel", "HudTargetLabel", "HudValueLabel", "HudStripLabel"]


static func _font_file(font: Font) -> Resource:
	var f: Font = font
	for i in 8:
		if f is FontVariation and (f as FontVariation).base_font != null:
			f = (f as FontVariation).base_font
		else:
			break
	return f


func test_req_hud_14_c1_hud_and_menu_fonts_resolve_to_one_inter_file() -> void:
	var menu_file := _font_file(_node("Label", "").get_theme_font("font"))
	assert_true(menu_file is FontFile, "шрифт меню — файл шрифта")
	if menu_file is FontFile:
		assert_string_contains((menu_file as FontFile).get_font_name(), "Inter", "шрифт темы — Inter")
	for v in HUD_NUMERIC + ["HudUnitLabel", "HudCaptionLabel", "StatLabel", "StatLargeLabel"]:
		var f := _font_file(_node("Label", v).get_theme_font("font"))
		assert_eq(f, menu_file, "%s — тот же файл, что шрифт меню" % v)
	assert_eq(_font_file(_node("Button", "HudButton").get_theme_font("font")), menu_file, "HudButton")


func test_req_hud_14_c1_live_workout_screen_numeric_labels_use_inter_file() -> void:
	var screen: WorkoutScreen = load("res://src/ui/workout/workout_screen.tscn").instantiate()
	add_child_autofree(screen)
	var menu_file := _font_file(_node("Label", "").get_theme_font("font"))
	for name in ["TargetLabel", "PowerLabel", "HrLabel", "CadenceLabel", "SpeedLabel", "ElapsedLabel", "CountdownLabel"]:
		var label := screen.get_node("%" + name) as Label
		assert_eq(_font_file(label.get_theme_font("font")), menu_file, "%s — Inter темы" % name)


func test_req_hud_14_c2_hud_numeric_fonts_tabular_from_11s_to_88s() -> void:
	var mismatches: Array[String] = []
	for v in HUD_NUMERIC + ["StatLabel", "StatLargeLabel"]:
		var font := _node("Label", v).get_theme_font("font")
		for s in [1.0, 1.2]:
			for size in range(int(ceil(11.0 * s)), int(floor(88.0 * s)) + 1):
				var w0 := font.get_string_size("0000", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
				var w1 := font.get_string_size("1111", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
				var w8 := font.get_string_size("8888", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
				if absf(w0 - w1) > 0.5 or absf(w0 - w8) > 0.5:
					mismatches.append("%s @%d: %.1f/%.1f/%.1f" % [v, size, w0, w1, w8])
	assert_eq(mismatches.slice(0, 10), [] as Array, "«0000» = «1111» = «8888» ±0.5 px (всего расхождений %d)" % mismatches.size())


# ===========================================================================
# REQ-NFR-08 крит. 2 — каждый ключ с непустым ru и en
# ===========================================================================

func test_req_nfr_08_c2_every_key_in_all_csv_has_ru_and_en_and_is_unique() -> void:
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://assets/i18n"):
		if f.begins_with("strings") and f.ends_with(".csv"):
			files.append("res://assets/i18n/" + f)
	assert_gte(files.size(), 7, "strings.csv и файлы по областям: %s" % str(files))
	var seen := {}
	var problems: Array[String] = []
	var registered: PackedStringArray = ProjectSettings.get_setting("internationalization/locale/translations")
	for path in files:
		var fa := FileAccess.open(path, FileAccess.READ)
		var header := fa.get_csv_line()
		var ru: int = Array(header).find("ru")
		var en: int = Array(header).find("en")
		if ru < 0 or en < 0:
			problems.append("%s: нет колонок ru/en" % path)
			continue
		while not fa.eof_reached():
			var row := fa.get_csv_line()
			if row.size() == 1 and row[0].strip_edges().is_empty():
				continue
			var key := row[0]
			if seen.has(key):
				problems.append("ключ %s повторяется (%s и %s)" % [key, seen[key], path.get_file()])
			seen[key] = path.get_file()
			if row.size() <= maxi(ru, en) or row[ru].strip_edges().is_empty() or row[en].strip_edges().is_empty():
				problems.append("%s: %s без перевода" % [path.get_file(), key])
		for lang in ["ru", "en"]:
			var tr_path: String = path.get_basename() + "." + str(lang) + ".translation"
			if not registered.has(tr_path):
				problems.append("%s не зарегистрирован в project.godot" % tr_path)
	assert_eq(problems, [] as Array[String])
	# Движок отдаёт перевод для ключей областей на обоих языках.
	for key in ["track.flat.name", "ride.free_ride.default_name", "meta.area.hud"]:
		assert_true(seen.has(key), "ключ %s есть" % key)
		for lang in ["ru", "en"]:
			TranslationServer.set_locale(lang)
			assert_ne(tr(key), key, "%s переведён на %s" % [key, lang])
	TranslationServer.set_locale("ru")
	var ru_name := tr("track.flat.name")
	TranslationServer.set_locale("en")
	assert_ne(tr("track.flat.name"), ru_name, "ru и en различаются")
