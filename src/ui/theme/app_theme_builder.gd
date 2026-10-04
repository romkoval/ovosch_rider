class_name AppThemeBuilder
extends RefCounted
## Сборка темы приложения `app_theme.tres` и начертаний Inter (`docs/game/ui.md` п. 9;
## REQ-UIX-01 крит. 1, 3, 4; REQ-HUD-14 крит. 1, 2).
##
## Тема — данные, но собирается кодом: цвета берутся только из `UiTokens`, поэтому стили
## не расходятся с палитрой. Готовые ресурсы (`app_theme.tres`, `fonts/*.tres`) лежат в
## репозитории; пересобрать их после правки токенов или этого файла:
## `godot --headless --path . -s res://src/ui/theme/tools/generate_theme.gd`.
## Тест `test_app_theme.gd` сверяет сохранённую тему со сборкой.
##
## Все начертания — `FontVariation` над одним файлом Inter (вариативные оси `wght`, `opsz`;
## для цифр — OpenType-фича `tnum`). Ключи осей и фич — числовые теги OpenType: строковые
## ключи `variation_opentype` Godot 4.7 молча игнорирует.

## Официальный файл Inter 4.1 (SIL OFL 1.1, `OFL.txt` рядом) — источник шрифта.
const INTER_TTF_PATH: String = "res://assets/fonts/inter/Inter-Variable.ttf"
## Тот же файл, сохранённый ресурсом `FontFile` с байтами TTF внутри. На него ссылаются
## все начертания: ресурс не требует импорта, поэтому тема проекта грузится без ошибок и
## на свежем клоне до первого `--import`. TTF не импортируется (`importer="skip"`).
const INTER_PATH: String = "res://assets/fonts/inter/Inter-Variable.res"
const FONT_DIR: String = "res://src/ui/theme/fonts/"
const THEME_PATH: String = "res://src/ui/theme/app_theme.tres"
const LUCIDE_DIR: String = "res://assets/icons/lucide/"

## Начертания: имя файла → [вес, оптический размер, моноширинные цифры, разрядка в px
## (необязательно)]. Оптический размер 32 — у крупных начертаний (Display, H1, цель и герой
## HUD), 16 — у текста.
##
## Разрядка Overline (`ui.md` п. 5: +6 %) — `FontVariation.spacing_glyph`. В Godot 4.7 это
## целое число пикселей кегля (не доля em), поэтому +6 % от 12 lp (0.72) округляется до 1 px
## (+8.3 %): ближайшее выразимое значение, дробную разрядку тема задать не может.
const FONT_SPECS: Dictionary = {
	"inter_400": [400, 16, false],
	"inter_500": [500, 16, false],
	"inter_600": [600, 16, false],
	"inter_650": [650, 16, false],
	"inter_700": [700, 16, false],
	"inter_700_overline": [700, 16, false, OVERLINE_SPACING_PX],
	"inter_750": [750, 32, false],
	"inter_num_600": [600, 16, true],
	"inter_num_650": [650, 16, true],
	"inter_num_700": [700, 16, true],
	"inter_num_750": [750, 32, true],
	"inter_num_800_display": [800, 32, true],
}
const DEFAULT_FONT: String = "inter_400"
const DEFAULT_FONT_SIZE: int = 16
## Кегль Overline и его разрядка в целых px (см. `FONT_SPECS`): round(12 × 0.06) = 1.
const OVERLINE_FONT_SIZE: int = 12
const OVERLINE_SPACING_PX: int = 1
## Внутреннее поле `SpinBox` в Godot 4.7 — `LineEdit` с вариацией `SpinBoxInnerLineEdit`:
## через неё полю задаётся шрифт цифр (`ui.md` п. 9.1), стили остаются от `LineEdit`.
const SPINBOX_FIELD: String = "SpinBoxInnerLineEdit"
## Шаги вертикальных (`StackN`) и горизонтальных (`RowN`) контейнеров, lp.
const STACK_GAPS: Array[int] = [0, 8, 12, 16, 24]
## Разрывы сеток (`GridN`: `h_separation` и `v_separation` = N) и переносимых рядов
## (`FlowN`: между элементами в строке N, между строками 8), lp.
const GRID_GAPS: Array[int] = [8, 12, 16, 24]
const FLOW_GAPS: Array[int] = [8, 12, 16]
const FLOW_LINE_GAP: int = 8

## Радиусы и поля (`ui.md` п. 3, 6, 9).
const RADIUS_CHIP: int = 6
const RADIUS_CONTROL: int = 12
const RADIUS_CARD: int = 16
const RADIUS_LARGE: int = 20
const BUTTON_MARGIN: Vector2 = Vector2(24, 14)
const FIELD_MARGIN: Vector2 = Vector2(14, 12)
const FOCUS_RING: int = 2
## Поля карточки паузы — как у `PauseOverlay.CARD_MARGIN` (T-074).
const HUD_PAUSE_CARD_MARGIN: Vector2 = Vector2(24, 20)
## Поля кнопки панели инструментов HUD: иконка 24 и подпись 11 (строка `Button` — 28) — 56 по высоте.
const HUD_TOOL_BUTTON_MARGIN: Vector2 = Vector2(8, 2)
## Кегль текста слота подсказки на телефоне, lp HUD (17 lp базы / s 1.2).
const HUD_HINT_COMPACT_FONT_SIZE: int = 14

## Вариации типов (`ui.md` п. 9.2): имя → базовый тип.
const VARIATIONS: Dictionary = {
	"DisplayLabel": "Label", "H1Label": "Label", "H2Label": "Label", "TitleLabel": "Label",
	"BodyStrongLabel": "Label", "SecondaryLabel": "Label", "CaptionLabel": "Label",
	"OverlineLabel": "Label", "StatLabel": "Label", "StatLargeLabel": "Label", "ErrorLabel": "Label",
	"OverlineAccent": "OverlineLabel", "OverlineSim": "OverlineLabel",
	"LogoLabel": "Label", "LogoAccentLabel": "LogoLabel",
	"DisplayAccentLabel": "DisplayLabel", "H1AccentLabel": "H1Label", "H2SecondaryLabel": "H2Label",
	"PrimaryButton": "Button", "GhostButton": "Button", "DangerButton": "Button",
	"IconButton": "Button", "ChipButton": "Button", "CardButton": "Button",
	"ScenarioCard": "CardButton", "ListRowButton": "CardButton",
	"AppBar": "PanelContainer", "InsetPanel": "PanelContainer",
	"BannerWarn": "PanelContainer", "BannerError": "PanelContainer", "BannerInfo": "PanelContainer",
	"SheetPanel": "PanelContainer",
	"HudPlate": "PanelContainer", "HudCard": "PanelContainer",
	"HudHeroLabel": "Label", "HudTargetLabel": "Label", "HudValueLabel": "Label",
	"HudStripLabel": "Label", "HudUnitLabel": "Label", "HudCaptionLabel": "Label",
	"HudZoneChipLabel": "Label", "HudButton": "Button",
	"HudHeroUnit": "Label", "HudTargetUnit": "Label", "HudCountdown": "Label", "HudDelta": "Label",
	"HudGradeValue": "Label", "HudGradeUnit": "Label", "HudModeLabel": "Label", "HudStepLabel": "Label",
	"HudPauseCard": "PanelContainer", "HudSummaryCard": "PanelContainer", "HudChipLabel": "Label", "HudPauseTitle": "Label",
	"HudChipSeconds": "HudChipLabel", "HudChipLabelCompact": "HudChipLabel",
	"HudChipSecondsCompact": "HudChipSeconds", "HudHintCompact": "BodyStrongLabel",
	"HudToolButton": "HudButton",
	"NumLabel": "Label", "CaptionNumLabel": "CaptionLabel", SPINBOX_FIELD: "LineEdit",
	"FormDialog": "AcceptDialog",
	"Stack0": "VBoxContainer", "Stack8": "VBoxContainer", "Stack12": "VBoxContainer", "Stack16": "VBoxContainer", "Stack24": "VBoxContainer",
	"Row0": "HBoxContainer", "Row8": "HBoxContainer", "Row12": "HBoxContainer", "Row16": "HBoxContainer", "Row24": "HBoxContainer",
	"Grid8": "GridContainer", "Grid12": "GridContainer", "Grid16": "GridContainer", "Grid24": "GridContainer",
	"Flow8": "HFlowContainer", "Flow12": "HFlowContainer", "Flow16": "HFlowContainer",
	"ScreenMargin": "MarginContainer", "ScreenMarginCompact": "MarginContainer", "CardMargin": "MarginContainer",
}

const _BUTTON_STATES: Array[String] = ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]
const _BUTTON_FONT_COLORS: Array[String] = ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]
const _BUTTON_ICON_COLORS: Array[String] = ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]


## Ресурс шрифта из байтов официального TTF (настройки растеризации — по умолчанию Godot).
static func make_font_file() -> FontFile:
	var ff := FontFile.new()
	ff.data = FileAccess.get_file_as_bytes(INTER_TTF_PATH)
	return ff


## Тег OpenType по имени (`"wght"` → число).
static func tag(name: String) -> int:
	return TextServerManager.get_primary_interface().name_to_tag(name)


## Новое начертание по спецификации `FONT_SPECS[name]`.
static func make_font(name: String, base: FontFile) -> FontVariation:
	var spec: Array = FONT_SPECS[name]
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {tag("wght"): int(spec[0]), tag("opsz"): int(spec[1])}
	if bool(spec[2]):
		fv.opentype_features = {tag("tnum"): 1}
	if spec.size() > 3:
		fv.spacing_glyph = int(spec[3])
	return fv


## Сохранённые начертания: имя → `FontVariation` из `FONT_DIR`.
static func load_fonts() -> Dictionary:
	var fonts: Dictionary = {}
	for name: String in FONT_SPECS:
		fonts[name] = load(FONT_DIR + name + ".tres")
	return fonts


## Собирает тему по токенам. `fonts` — имя → `Font` (обычно `load_fonts()`).
static func build(fonts: Dictionary) -> Theme:
	var t := Theme.new()
	t.default_font = fonts[DEFAULT_FONT]
	t.default_font_size = DEFAULT_FONT_SIZE
	for variation: String in VARIATIONS:
		t.set_type_variation(variation, VARIATIONS[variation])
	_base_types(t, fonts)
	_label_variations(t, fonts)
	_button_variations(t, fonts)
	_panel_variations(t)
	_hud_variations(t, fonts)
	_container_variations(t)
	return t


# --- Базовые типы (`ui.md` п. 9.1) ---------------------------------------------------------

static func _base_types(t: Theme, fonts: Dictionary) -> void:
	_label(t, "Label", fonts["inter_400"], 16, UiTokens.TEXT)
	t.set_constant("line_spacing", "Label", 4)

	# Button = вторичная кнопка.
	var normal := _box(UiTokens.SURFACE2, RADIUS_CONTROL, BUTTON_MARGIN, 1, UiTokens.LINE_STRONG)
	var hover := _box(UiTokens.SURFACE3, RADIUS_CONTROL, BUTTON_MARGIN, 1, UiTokens.LINE_STRONG)
	var pressed := _box(UiTokens.SURFACE3, RADIUS_CONTROL, BUTTON_MARGIN, 1, UiTokens.ACCENT)
	var disabled := _box(UiTokens.SURFACE1, RADIUS_CONTROL, BUTTON_MARGIN, 1, UiTokens.LINE)
	_button_styles(t, "Button", normal, hover, pressed, _focus_ring(RADIUS_CONTROL), disabled)
	_button_colors(t, "Button", UiTokens.TEXT, UiTokens.TEXT, UiTokens.TEXT_DISABLED)
	t.set_font("font", "Button", fonts["inter_650"])
	t.set_font_size("font_size", "Button", 16)
	t.set_constant("h_separation", "Button", 8)
	t.set_constant("icon_max_width", "Button", 24)

	# Поля ввода.
	var field := _box(UiTokens.INSET, RADIUS_CONTROL, FIELD_MARGIN, 1, UiTokens.LINE_STRONG)
	var field_focus := _box(Color.TRANSPARENT, RADIUS_CONTROL, FIELD_MARGIN, FOCUS_RING, UiTokens.ACCENT)
	field_focus.draw_center = false
	var field_read_only := _box(UiTokens.SURFACE1, RADIUS_CONTROL, FIELD_MARGIN, 1, UiTokens.LINE)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_stylebox("read_only", "LineEdit", field_read_only)
	t.set_font("font", "LineEdit", fonts["inter_500"])
	t.set_font_size("font_size", "LineEdit", 16)
	t.set_color("font_color", "LineEdit", UiTokens.TEXT)
	t.set_color("font_selected_color", "LineEdit", UiTokens.TEXT)
	t.set_color("font_uneditable_color", "LineEdit", UiTokens.TEXT2)
	t.set_color("font_placeholder_color", "LineEdit", UiTokens.TEXT_DISABLED)
	t.set_color("caret_color", "LineEdit", UiTokens.ACCENT)
	t.set_color("selection_color", "LineEdit", Color(UiTokens.ACCENT, UiTokens.SELECTION_ALPHA))
	t.set_color("clear_button_color", "LineEdit", UiTokens.TEXT2)
	t.set_color("clear_button_color_pressed", "LineEdit", UiTokens.TEXT)
	t.set_constant("minimum_character_width", "LineEdit", 4)
	# Многострочное поле (описание заезда для Strava, `ui.md` п. 8.5) — как `LineEdit`.
	t.set_stylebox("normal", "TextEdit", field)
	t.set_stylebox("focus", "TextEdit", field_focus)
	t.set_stylebox("read_only", "TextEdit", field_read_only)
	t.set_font("font", "TextEdit", fonts["inter_500"])
	t.set_font_size("font_size", "TextEdit", 16)
	t.set_color("font_color", "TextEdit", UiTokens.TEXT)
	t.set_color("font_selected_color", "TextEdit", UiTokens.TEXT)
	t.set_color("font_readonly_color", "TextEdit", UiTokens.TEXT2)
	t.set_color("font_placeholder_color", "TextEdit", UiTokens.TEXT_DISABLED)
	t.set_color("caret_color", "TextEdit", UiTokens.ACCENT)
	t.set_color("selection_color", "TextEdit", Color(UiTokens.ACCENT, UiTokens.SELECTION_ALPHA))
	t.set_constant("line_spacing", "TextEdit", 4)

	# SpinBox: поле — LineEdit; стрелки — шевроны Lucide 16 lp.
	var up := _lucide("chevron-up", 16)
	var down := _lucide("chevron-down", 16)
	for state in ["", "_hover", "_pressed", "_disabled"]:
		t.set_icon("up" + state, "SpinBox", up)
		t.set_icon("down" + state, "SpinBox", down)
		t.set_stylebox("up_background" + (state if state != "_hover" else "_hovered"), "SpinBox", StyleBoxEmpty.new())
		t.set_stylebox("down_background" + (state if state != "_hover" else "_hovered"), "SpinBox", StyleBoxEmpty.new())
	for prefix in ["up", "down"]:
		t.set_color(prefix + "_icon_modulate", "SpinBox", UiTokens.TEXT2)
		t.set_color(prefix + "_hover_icon_modulate", "SpinBox", UiTokens.TEXT)
		t.set_color(prefix + "_pressed_icon_modulate", "SpinBox", UiTokens.ACCENT)
		t.set_color(prefix + "_disabled_icon_modulate", "SpinBox", UiTokens.TEXT_DISABLED)
	t.set_stylebox("field_and_buttons_separator", "SpinBox", StyleBoxEmpty.new())
	t.set_stylebox("up_down_buttons_separator", "SpinBox", StyleBoxEmpty.new())
	t.set_font("font", SPINBOX_FIELD, fonts["inter_num_600"])
	t.set_font_size("font_size", SPINBOX_FIELD, 16)

	# OptionButton — как поле + шеврон.
	var option_hover := _box(UiTokens.INSET, RADIUS_CONTROL, FIELD_MARGIN, 1, Color(UiTokens.ACCENT, UiTokens.CARD_HOVER_BORDER_ALPHA))
	var option_pressed := _box(UiTokens.INSET, RADIUS_CONTROL, FIELD_MARGIN, FOCUS_RING, UiTokens.ACCENT)
	var option_focus := field_focus.duplicate() as StyleBoxFlat
	for suffix in ["", "_mirrored"]:
		t.set_stylebox("normal" + suffix, "OptionButton", field)
		t.set_stylebox("hover" + suffix, "OptionButton", option_hover)
		t.set_stylebox("pressed" + suffix, "OptionButton", option_pressed)
		t.set_stylebox("disabled" + suffix, "OptionButton", field_read_only)
	t.set_stylebox("focus", "OptionButton", option_focus)
	t.set_icon("arrow", "OptionButton", down)
	_button_colors(t, "OptionButton", UiTokens.TEXT, UiTokens.TEXT, UiTokens.TEXT_DISABLED)
	t.set_font("font", "OptionButton", fonts["inter_500"])
	t.set_font_size("font_size", "OptionButton", 16)
	t.set_constant("arrow_margin", "OptionButton", 12)
	t.set_constant("modulate_arrow", "OptionButton", 1)

	# PopupMenu (меню OptionButton и контекстные меню).
	var popup := _box(UiTokens.SURFACE2, RADIUS_CONTROL, Vector2(8, 8))
	_shadow(popup)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _box(UiTokens.SURFACE3, RADIUS_CHIP, Vector2.ZERO))
	t.set_stylebox("separator", "PopupMenu", _line(UiTokens.LINE, false))
	t.set_font("font", "PopupMenu", fonts["inter_500"])
	t.set_font_size("font_size", "PopupMenu", 16)
	t.set_color("font_color", "PopupMenu", UiTokens.TEXT)
	t.set_color("font_hover_color", "PopupMenu", UiTokens.TEXT)
	t.set_color("font_disabled_color", "PopupMenu", UiTokens.TEXT_DISABLED)
	t.set_color("font_accelerator_color", "PopupMenu", UiTokens.TEXT2)
	t.set_color("font_separator_color", "PopupMenu", UiTokens.TEXT2)
	t.set_constant("v_separation", "PopupMenu", 12)
	t.set_constant("item_start_padding", "PopupMenu", 16)
	t.set_constant("item_end_padding", "PopupMenu", 16)

	# CheckButton — свои переключатели 44×26.
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "pressed", "hover", "hover_pressed", "disabled"]:
		t.set_stylebox(state, "CheckButton", empty)
	t.set_stylebox("focus", "CheckButton", _focus_ring(RADIUS_CONTROL))
	var on := _switch_icon(true, 1.0)
	var off := _switch_icon(false, 1.0)
	var on_disabled := _switch_icon(true, 0.4)
	var off_disabled := _switch_icon(false, 0.4)
	for suffix in ["", "_mirrored"]:
		t.set_icon("checked" + suffix, "CheckButton", on)
		t.set_icon("unchecked" + suffix, "CheckButton", off)
		t.set_icon("checked_disabled" + suffix, "CheckButton", on_disabled)
		t.set_icon("unchecked_disabled" + suffix, "CheckButton", off_disabled)
	_button_colors(t, "CheckButton", UiTokens.TEXT, UiTokens.TEXT, UiTokens.TEXT_DISABLED)
	t.set_font("font", "CheckButton", fonts["inter_500"])
	t.set_font_size("font_size", "CheckButton", 16)
	t.set_constant("h_separation", "CheckButton", 12)
	# CheckButton наследует константы Button: без сброса `icon_max_width` 24 сжимает
	# переключатель 44×26 до 24×14.
	t.set_constant("icon_max_width", "CheckButton", 0)

	# HSlider: дорожка 6, бегунок 22.
	t.set_stylebox("slider", "HSlider", _box(UiTokens.SURFACE3, 3, Vector2(0, 3)))
	t.set_stylebox("grabber_area", "HSlider", _box(UiTokens.ACCENT, 3, Vector2(0, 3)))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(UiTokens.ACCENT, 3, Vector2(0, 3)))
	var grabber := _circle_icon(22, UiTokens.TEXT)
	t.set_icon("grabber", "HSlider", grabber)
	t.set_icon("grabber_highlight", "HSlider", grabber)
	t.set_icon("grabber_disabled", "HSlider", _circle_icon(22, UiTokens.TEXT_DISABLED))

	# ProgressBar.
	t.set_stylebox("background", "ProgressBar", _box(UiTokens.SURFACE3, 3, Vector2.ZERO))
	t.set_stylebox("fill", "ProgressBar", _box(UiTokens.ACCENT, 3, Vector2.ZERO))
	t.set_font("font", "ProgressBar", fonts["inter_num_600"])
	t.set_font_size("font_size", "ProgressBar", 13)
	t.set_color("font_color", "ProgressBar", UiTokens.TEXT)

	# Панели и прокрутка.
	t.set_stylebox("panel", "PanelContainer", _box(UiTokens.SURFACE1, RADIUS_CARD, Vector2(16, 16), 1, UiTokens.LINE))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("focus", "ScrollContainer", StyleBoxEmpty.new())
	for bar in ["VScrollBar", "HScrollBar"]:
		var vertical: bool = bar == "VScrollBar"
		var track := StyleBoxEmpty.new()
		var grabber_margin := Vector2(3, 3)
		if vertical:
			track.content_margin_left = 3
			track.content_margin_right = 3
		else:
			track.content_margin_top = 3
			track.content_margin_bottom = 3
		t.set_stylebox("scroll", bar, track)
		t.set_stylebox("scroll_focus", bar, track)
		t.set_stylebox("grabber", bar, _box(UiTokens.SURFACE3, 3, grabber_margin))
		t.set_stylebox("grabber_highlight", bar, _box(UiTokens.LINE_STRONG, 3, grabber_margin))
		t.set_stylebox("grabber_pressed", bar, _box(UiTokens.LINE_STRONG, 3, grabber_margin))

	# Диалоги (окна встроены в корневой вьюпорт).
	var default_theme := ThemeDB.get_default_theme()
	for state in ["embedded_border", "embedded_unfocused_border"]:
		var border := default_theme.get_stylebox(state, "Window").duplicate() as StyleBoxFlat
		border.bg_color = UiTokens.SURFACE1
		border.set_border_width_all(0)
		border.set_corner_radius_all(RADIUS_LARGE)
		_shadow(border)
		t.set_stylebox(state, "Window", border)
	t.set_font("title_font", "Window", fonts["inter_700"])
	t.set_font_size("title_font_size", "Window", 20)
	t.set_color("title_color", "Window", UiTokens.TEXT)
	t.set_stylebox("panel", "AcceptDialog", _box(UiTokens.SURFACE1, 0, Vector2(24, 24)))
	t.set_constant("buttons_separation", "AcceptDialog", 12)
	# Диалог-форма со своими кнопками внутри содержимого (создание профиля): ряд кнопок окна
	# скрыт, поэтому разрыв до него не нужен — снизу остаётся только поле 24, как сверху.
	t.set_constant("buttons_separation", "FormDialog", 0)

	# Подсказки.
	t.set_stylebox("panel", "TooltipPanel", _box(UiTokens.SURFACE3, 8, Vector2(10, 6)))
	t.set_font("font", "TooltipLabel", fonts["inter_500"])
	t.set_font_size("font_size", "TooltipLabel", 13)
	t.set_color("font_color", "TooltipLabel", UiTokens.TEXT)

	# Разделители.
	t.set_stylebox("separator", "HSeparator", _line(UiTokens.LINE, false))
	t.set_constant("separation", "HSeparator", 17)
	t.set_stylebox("separator", "VSeparator", _line(UiTokens.LINE, true))
	t.set_constant("separation", "VSeparator", 17)

	# ItemList (пока остаётся на старых экранах).
	t.set_stylebox("panel", "ItemList", _box(UiTokens.SURFACE1, RADIUS_CARD, Vector2(8, 8)))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	var selected := _box(UiTokens.SURFACE3, 0, Vector2(12, 0))
	selected.border_width_left = 4
	selected.border_color = UiTokens.ACCENT
	for state in ["selected", "selected_focus", "hovered_selected", "hovered_selected_focus"]:
		t.set_stylebox(state, "ItemList", selected)
	t.set_stylebox("hovered", "ItemList", _box(UiTokens.SURFACE2, 0, Vector2(12, 0)))
	t.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	t.set_font("font", "ItemList", fonts["inter_500"])
	t.set_font_size("font_size", "ItemList", 16)
	for c in ["font_color", "font_hovered_color", "font_selected_color", "font_hovered_selected_color"]:
		t.set_color(c, "ItemList", UiTokens.TEXT)
	t.set_constant("v_separation", "ItemList", 12)


# --- Вариации (`ui.md` п. 9.2) ---------------------------------------------------------------

static func _label_variations(t: Theme, fonts: Dictionary) -> void:
	_label(t, "DisplayLabel", fonts["inter_750"], 40)
	_label(t, "H1Label", fonts["inter_750"], 28)
	_label(t, "H2Label", fonts["inter_700"], 22)
	_label(t, "TitleLabel", fonts["inter_650"], 18)
	_label(t, "BodyStrongLabel", fonts["inter_600"], 16)
	_label(t, "SecondaryLabel", fonts["inter_500"], 14, UiTokens.TEXT2)
	_label(t, "CaptionLabel", fonts["inter_500"], 13, UiTokens.TEXT2)
	_label(t, "OverlineLabel", fonts["inter_700_overline"], OVERLINE_FONT_SIZE, UiTokens.TEXT2)
	# Цифры в колонках списков (U4, `ui.md` п. 11): Body 16 с `tnum`.
	_label(t, "NumLabel", fonts["inter_num_600"], 16)
	# Caption с цифрами (дата, «вчера · 1:02:15 · 34.1 км», доли зон): Caption 13 `text2` с `tnum`.
	# Вес 600, а не 500: цифрового начертания 500 нет — то же решение, что у `HudStepLabel`
	# (`hud.md` п. 6), отдельное начертание ради подписи не заводится.
	_label(t, "CaptionNumLabel", fonts["inter_num_600"], 13, UiTokens.TEXT2)
	_label(t, "StatLabel", fonts["inter_num_700"], 22)
	_label(t, "StatLargeLabel", fonts["inter_num_750"], 32)
	_label(t, "ErrorLabel", fonts["inter_500"], 13, UiTokens.DANGER_TEXT)
	# Надзаголовки сценариев (`ui.md` п. 5, 8.2): шрифт и кегль — от `OverlineLabel`, цвет —
	# `accent` («ТРЕНИРОВКА ПО ПЛАНУ · ERG») или `sim` («СВОБОДНАЯ ЕЗДА · SIM»).
	t.set_color("font_color", "OverlineAccent", UiTokens.ACCENT)
	t.set_color("font_color", "OverlineSim", UiTokens.SIM)
	# Словесный знак `ovosch·rider` в AppBar главного экрана (`ui.md` п. 6, 8.2): H1 28, вес 800;
	# «·rider» — отдельная подпись `LogoAccentLabel` цветом `accent`. Вес 800 есть только у
	# `inter_num_800_display` (`tnum` на буквы не влияет) — новое начертание не нужно.
	_label(t, "LogoLabel", fonts["inter_num_800_display"], 28)
	t.set_color("font_color", "LogoAccentLabel", UiTokens.ACCENT)
	# Экран выбора профиля (T-103): «·rider» крупного словесного знака цветом `accent` в размерах
	# Display (regular) и H1 (compact), подпись «Кто едет?» — H2 цветом `text2` (без self_modulate).
	t.set_color("font_color", "DisplayAccentLabel", UiTokens.ACCENT)
	t.set_color("font_color", "H1AccentLabel", UiTokens.ACCENT)
	t.set_color("font_color", "H2SecondaryLabel", UiTokens.TEXT2)


static func _button_variations(t: Theme, fonts: Dictionary) -> void:
	# Основная.
	_button_styles(t, "PrimaryButton",
		_box(UiTokens.ACCENT, RADIUS_CONTROL, BUTTON_MARGIN),
		_box(UiTokens.ACCENT.lightened(UiTokens.ACCENT_HOVER_LIGHTEN), RADIUS_CONTROL, BUTTON_MARGIN),
		_box(UiTokens.ACCENT_PRESSED, RADIUS_CONTROL, BUTTON_MARGIN),
		null,
		_box(Color(UiTokens.ACCENT, 0.4), RADIUS_CONTROL, BUTTON_MARGIN))
	_button_colors(t, "PrimaryButton", UiTokens.ON_ACCENT, UiTokens.ON_ACCENT, Color(UiTokens.ON_ACCENT, 0.4))
	t.set_font("font", "PrimaryButton", fonts["inter_700"])

	# Текстовая.
	var ghost_margin := Vector2(16, 10)
	var ghost_empty := StyleBoxEmpty.new()
	_set_margin(ghost_empty, ghost_margin)
	_button_styles(t, "GhostButton", ghost_empty,
		_box(UiTokens.SURFACE2, RADIUS_CONTROL, ghost_margin),
		_box(UiTokens.SURFACE3, RADIUS_CONTROL, ghost_margin),
		null, ghost_empty)
	_button_colors(t, "GhostButton", UiTokens.TEXT2, UiTokens.TEXT, UiTokens.TEXT_DISABLED)

	# Опасная: наведение и нажатие темнее (`ui.md` п. 4, 9.2, 13); нажатие без рамки —
	# белая рамка читалась бы как фокус.
	_button_styles(t, "DangerButton",
		_box(UiTokens.DANGER, RADIUS_CONTROL, BUTTON_MARGIN),
		_box(UiTokens.DANGER_HOVER, RADIUS_CONTROL, BUTTON_MARGIN),
		_box(UiTokens.DANGER_PRESSED, RADIUS_CONTROL, BUTTON_MARGIN),
		null,
		_box(Color(UiTokens.DANGER, 0.4), RADIUS_CONTROL, BUTTON_MARGIN))
	_button_colors(t, "DangerButton", UiTokens.TEXT, UiTokens.TEXT, Color(UiTokens.TEXT, 0.4))

	# Кнопка-иконка: квадрат 40 lp на компьютере (24 + 2 × 8); на сенсорных — `touch_ui`.
	var icon_margin := Vector2(8, 8)
	_button_styles(t, "IconButton",
		_box(UiTokens.SURFACE1, RADIUS_CONTROL, icon_margin),
		_box(UiTokens.SURFACE2, RADIUS_CONTROL, icon_margin),
		_box(UiTokens.SURFACE3, RADIUS_CONTROL, icon_margin),
		null,
		_box(UiTokens.SURFACE1, RADIUS_CONTROL, icon_margin))
	t.set_constant("icon_max_width", "IconButton", 24)

	# Фишка: высота 36 на компьютере.
	var chip_margin := Vector2(14, 10)
	_button_styles(t, "ChipButton",
		_box(UiTokens.SURFACE1, 18, chip_margin),
		_box(UiTokens.SURFACE2, 18, chip_margin),
		_box(UiTokens.SURFACE3, 18, chip_margin),
		_focus_ring(18),
		_box(UiTokens.SURFACE1, 18, chip_margin))
	t.set_font("font", "ChipButton", fonts["inter_600"])
	t.set_font_size("font_size", "ChipButton", 13)
	t.set_constant("h_separation", "ChipButton", 8)

	# Карточки.
	_card_styles(t, "CardButton", RADIUS_CARD, Vector2(16, 16), 1)
	_card_styles(t, "ScenarioCard", RADIUS_LARGE, Vector2(24, 24), 1)
	var row_margin := Vector2(16, 16)
	_button_styles(t, "ListRowButton",
		_box(UiTokens.SURFACE1, 0, row_margin),
		_box(UiTokens.SURFACE2, 0, row_margin),
		_box(UiTokens.SURFACE3, 0, row_margin),
		_focus_ring(0),
		_box(UiTokens.SURFACE1, 0, row_margin))


static func _panel_variations(t: Theme) -> void:
	t.set_stylebox("panel", "AppBar", _box(UiTokens.BG, 0, Vector2(24, 12)))
	# Лист снизу (`ui.md` п. 6 «Диалог / лист»; compact-предпросмотр плана и трассы): `surface1`,
	# скругление 20 только сверху, поля 24, тень диалогов.
	var sheet := _box(UiTokens.SURFACE1, RADIUS_LARGE, Vector2(24, 24))
	sheet.corner_radius_bottom_left = 0
	sheet.corner_radius_bottom_right = 0
	_shadow(sheet)
	t.set_stylebox("panel", "SheetPanel", sheet)
	t.set_stylebox("panel", "InsetPanel", _box(UiTokens.INSET, RADIUS_CONTROL, Vector2(12, 12)))
	var banners := {"BannerWarn": UiTokens.WARN, "BannerError": UiTokens.DANGER_TEXT, "BannerInfo": UiTokens.ACCENT}
	for name: String in banners:
		var color: Color = banners[name]
		var box := _box(Color(color, UiTokens.BANNER_ALPHA), RADIUS_CONTROL, Vector2(16, 16))
		box.border_width_left = 4
		box.border_color = color
		t.set_stylebox("panel", name, box)


static func _hud_variations(t: Theme, fonts: Dictionary) -> void:
	t.set_stylebox("panel", "HudPlate", _box(UiTokens.HUD_PLATE, RADIUS_CARD, Vector2(12, 8)))
	t.set_stylebox("panel", "HudCard", _box(UiTokens.HUD_CARD, RADIUS_CONTROL, Vector2(16, 10)))
	_label(t, "HudHeroLabel", fonts["inter_num_800_display"], 88, UiTokens.HUD_TEXT)
	_label(t, "HudTargetLabel", fonts["inter_num_750"], 40, UiTokens.HUD_TEXT)
	_label(t, "HudValueLabel", fonts["inter_num_700"], 34, UiTokens.HUD_TEXT)
	_label(t, "HudStripLabel", fonts["inter_num_650"], 24, UiTokens.HUD_TEXT)
	_label(t, "HudUnitLabel", fonts["inter_500"], 14, UiTokens.HUD_TEXT2)
	# Подписи HUD с цифрами («Сопротивление 50 %», «105 %») — `tnum` (HUD-14 крит. 2).
	_label(t, "HudCaptionLabel", fonts["inter_num_650"], 12, UiTokens.HUD_TEXT2)
	# Фишка зоны (`hud.md` п. 11): заливка — цвет зоны (данные), текст `hud.ink`, «Z4» — `tnum`.
	_label(t, "HudZoneChipLabel", fonts["inter_num_750"], UiTokens.HUD_ZONE_CHIP_FONT_SIZE, UiTokens.HUD_ZONE_CHIP_TEXT)
	# Номер шага «Шаг 3 из 12» (`hud.md` п. 6: 13·s / 500 `hud.text2`). Цифрам нужен `tnum`, а
	# начертания 500 с `tnum` нет: ближайшее из пяти цифровых — 600.
	_label(t, "HudStepLabel", fonts["inter_num_600"], 13, UiTokens.HUD_TEXT2)
	# Карточка цели и герой (`hud.md` п. 5): «Вт» героя 22·s / 600, «Вт» цели 16·s / 600 —
	# `hud.text2`; отсчёт 22·s / 700 `tnum` и разница отклонения 15·s / 700 `tnum` — `hud.text`
	# (цвет состояния — `hud.warn`, `hud.dev_*` — задаёт компонент).
	_label(t, "HudHeroUnit", fonts["inter_600"], 22, UiTokens.HUD_TEXT2)
	_label(t, "HudTargetUnit", fonts["inter_600"], 16, UiTokens.HUD_TEXT2)
	_label(t, "HudCountdown", fonts["inter_num_700"], 22, UiTokens.HUD_TEXT)
	_label(t, "HudDelta", fonts["inter_num_700"], 15, UiTokens.HUD_TEXT)
	# Карточка «УКЛОН» свободной езды (`hud.md` п. 8): `+6.4` 44·s / 750 `tnum` белым, « %» 18·s / 600
	# `hud.text2`, режим «SIM 50 %» / «СОПР. 40 %» 16·s / 600 `hud.text2` (с цифрами — `tnum`).
	_label(t, "HudGradeValue", fonts["inter_num_750"], 44, UiTokens.HUD_TEXT)
	_label(t, "HudGradeUnit", fonts["inter_600"], 18, UiTokens.HUD_TEXT2)
	_label(t, "HudModeLabel", fonts["inter_num_600"], 16, UiTokens.HUD_TEXT2)
	# Фишка «ДАЛЕЕ» (`hud.md` п. 10.1): строка и секунды 18·s / 750 `tnum`; цвет секунд
	# (`hud.warn`) — состояние, задаётся в компоненте.
	_label(t, "HudChipLabel", fonts["inter_num_750"], 18, UiTokens.HUD_TEXT)
	_label(t, "HudChipSeconds", fonts["inter_num_750"], 18, UiTokens.HUD_WARN)
	# Слот подсказки телефона (`hud.md` п. 4.1): 40 lp базы при тексте 17 lp базы — на холсте HUD
	# (s = 1.2) это 33 lp и 14 lp: фишка «ДАЛЕЕ» и подсказка (Body Strong) на телефоне — кеглем 14.
	_label(t, "HudChipLabelCompact", fonts["inter_num_750"], HUD_HINT_COMPACT_FONT_SIZE, UiTokens.HUD_TEXT)
	_label(t, "HudChipSecondsCompact", fonts["inter_num_750"], HUD_HINT_COMPACT_FONT_SIZE, UiTokens.HUD_WARN)
	_label(t, "HudHintCompact", fonts["inter_600"], HUD_HINT_COMPACT_FONT_SIZE)
	# Карточка паузы (`hud.md` п. 10.2): `surface1` с альфой 0.94, радиус 18·s; «Пауза» — 30·s / 750.
	t.set_stylebox("panel", "HudPauseCard", _box(UiTokens.HUD_PAUSE_CARD, UiTokens.HUD_PAUSE_CARD_RADIUS, HUD_PAUSE_CARD_MARGIN))
	_label(t, "HudPauseTitle", fonts["inter_750"], 30, UiTokens.HUD_TEXT)
	# Карточка итога заезда (`ui.md` п. 8.8): форма карточки паузы (радиус 18, поля 24/20), но
	# непрозрачнее — `surface1` с альфой 0.97 (REQ-HUD-14 крит. 7: не ниже 0.96).
	t.set_stylebox("panel", "HudSummaryCard", _box(UiTokens.SUMMARY_CARD, UiTokens.HUD_PAUSE_CARD_RADIUS, HUD_PAUSE_CARD_MARGIN))
	# Кнопка HUD 56×56: иконка 24 + поля 16.
	var hud_margin := Vector2(16, 16)
	_button_styles(t, "HudButton",
		_box(UiTokens.HUD_PLATE, RADIUS_CONTROL, hud_margin),
		_box(Color(UiTokens.SURFACE2, UiTokens.HUD_PLATE_ALPHA), RADIUS_CONTROL, hud_margin),
		_box(Color(UiTokens.SURFACE3, UiTokens.HUD_PLATE_ALPHA), RADIUS_CONTROL, hud_margin),
		null,
		_box(UiTokens.HUD_PLATE, RADIUS_CONTROL, hud_margin))
	_button_colors(t, "HudButton", UiTokens.HUD_TEXT, UiTokens.HUD_TEXT, UiTokens.TEXT_DISABLED)
	t.set_font("font", "HudButton", fonts["inter_600"])
	t.set_font_size("font_size", "HudButton", 11)
	t.set_constant("icon_max_width", "HudButton", 24)
	# Кнопка панели инструментов (`hud.md` п. 10.3): сторона `max(56, touch_hud)·s`, иконка 24 и
	# подпись 11 снизу внутри стороны 56 — поля по вертикали меньше, чем у кнопки паузы.
	var tool_margin := HUD_TOOL_BUTTON_MARGIN
	_button_styles(t, "HudToolButton",
		_box(UiTokens.HUD_PLATE, RADIUS_CONTROL, tool_margin),
		_box(Color(UiTokens.SURFACE2, UiTokens.HUD_PLATE_ALPHA), RADIUS_CONTROL, tool_margin),
		_box(Color(UiTokens.SURFACE3, UiTokens.HUD_PLATE_ALPHA), RADIUS_CONTROL, tool_margin),
		null,
		_box(UiTokens.HUD_PLATE, RADIUS_CONTROL, tool_margin))


static func _container_variations(t: Theme) -> void:
	for gap in STACK_GAPS:
		t.set_constant("separation", "Stack%d" % gap, gap)
		t.set_constant("separation", "Row%d" % gap, gap)
	for gap in GRID_GAPS:
		t.set_constant("h_separation", "Grid%d" % gap, gap)
		t.set_constant("v_separation", "Grid%d" % gap, gap)
	for gap in FLOW_GAPS:
		t.set_constant("h_separation", "Flow%d" % gap, gap)
		t.set_constant("v_separation", "Flow%d" % gap, FLOW_LINE_GAP)
	_margins(t, "ScreenMargin", 32, 24)
	_margins(t, "ScreenMarginCompact", 24, 16)
	_margins(t, "CardMargin", 16, 16)


# --- Помощники ---------------------------------------------------------------------------

static func _label(t: Theme, type: String, font: Font, size: int, color: Color = UiTokens.TEXT) -> void:
	t.set_font("font", type, font)
	t.set_font_size("font_size", type, size)
	t.set_color("font_color", type, color)


static func _box(bg: Color, radius: int, margin: Vector2, border: int = 0, border_color: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	_set_margin(box, margin)
	if border > 0:
		box.set_border_width_all(border)
		box.border_color = border_color
	return box


static func _set_margin(box: StyleBox, margin: Vector2) -> void:
	box.content_margin_left = margin.x
	box.content_margin_right = margin.x
	box.content_margin_top = margin.y
	box.content_margin_bottom = margin.y


## Кольцо фокуса: без заливки, рамка 2 lp `text` с отступом 2 lp.
static func _focus_ring(radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.bg_color = Color(UiTokens.TEXT, 0.0)
	box.set_border_width_all(FOCUS_RING)
	box.border_color = UiTokens.TEXT
	box.set_corner_radius_all(radius + FOCUS_RING if radius > 0 else 0)
	box.set_expand_margin_all(FOCUS_RING)
	return box


static func _shadow(box: StyleBoxFlat) -> void:
	box.shadow_color = UiTokens.SHADOW
	box.shadow_size = UiTokens.SHADOW_SIZE
	box.shadow_offset = UiTokens.SHADOW_OFFSET


static func _line(color: Color, vertical: bool) -> StyleBoxLine:
	var line := StyleBoxLine.new()
	line.color = color
	line.thickness = 1
	line.vertical = vertical
	return line


static func _margins(t: Theme, type: String, horizontal: int, vertical: int) -> void:
	t.set_constant("margin_left", type, horizontal)
	t.set_constant("margin_right", type, horizontal)
	t.set_constant("margin_top", type, vertical)
	t.set_constant("margin_bottom", type, vertical)


## Стили кнопки; `focus == null` — кольцо фокуса по радиусу `normal`.
static func _button_styles(t: Theme, type: String, normal: StyleBox, hover: StyleBox, pressed: StyleBox, focus: StyleBox, disabled: StyleBox) -> void:
	if focus == null:
		var radius := (normal as StyleBoxFlat).corner_radius_top_left if normal is StyleBoxFlat else RADIUS_CONTROL
		focus = _focus_ring(radius)
	var styles := {"normal": normal, "hover": hover, "pressed": pressed, "hover_pressed": pressed, "focus": focus, "disabled": disabled}
	for state: String in _BUTTON_STATES:
		t.set_stylebox(state, type, styles[state])


static func _button_colors(t: Theme, type: String, color: Color, hover_color: Color, disabled_color: Color) -> void:
	for name in _BUTTON_FONT_COLORS:
		t.set_color(name, type, color)
	t.set_color("font_hover_color", type, hover_color)
	t.set_color("font_hover_pressed_color", type, hover_color)
	t.set_color("font_disabled_color", type, disabled_color)
	if type == "OptionButton" or type == "CheckButton":
		return
	for name in _BUTTON_ICON_COLORS:
		t.set_color(name, type, color)
	t.set_color("icon_hover_color", type, hover_color)
	t.set_color("icon_hover_pressed_color", type, hover_color)
	t.set_color("icon_disabled_color", type, disabled_color)


## Карточка-кнопка: рамка `line`; наведение — рамка `accent` 0.6; выбрана — `surface2` и
## рамка 2 `accent`; фокус — рамка 2 `text`.
static func _card_styles(t: Theme, type: String, radius: int, margin: Vector2, border: int) -> void:
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.bg_color = Color(UiTokens.TEXT, 0.0)
	focus.set_border_width_all(FOCUS_RING)
	focus.border_color = UiTokens.TEXT
	focus.set_corner_radius_all(radius)
	_button_styles(t, type,
		_box(UiTokens.SURFACE1, radius, margin, border, UiTokens.LINE),
		_box(UiTokens.SURFACE1, radius, margin, border, Color(UiTokens.ACCENT, UiTokens.CARD_HOVER_BORDER_ALPHA)),
		_box(UiTokens.SURFACE2, radius, margin, FOCUS_RING, UiTokens.ACCENT),
		focus,
		_box(UiTokens.SURFACE1, radius, margin, border, UiTokens.LINE))


## Иконка Lucide размера `size` lp (`DPITexture`: чёткая при любом масштабе экрана).
static func _lucide(name: String, size: int) -> DPITexture:
	var source := FileAccess.get_file_as_string(LUCIDE_DIR + name + ".svg")
	return DPITexture.create_from_string(source, size / 24.0)


## Переключатель 44×26 (`ui.md` п. 9.1): дорожка `accent` / `surface3`, бегунок 20 `text`.
static func _switch_icon(checked: bool, opacity: float) -> DPITexture:
	var track := UiTokens.ACCENT if checked else UiTokens.SURFACE3
	var knob_x := 31 if checked else 13
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"44\" height=\"26\" viewBox=\"0 0 44 26\">" \
		+ "<g opacity=\"%s\"><rect width=\"44\" height=\"26\" rx=\"13\" fill=\"#%s\"/>" % [opacity, track.to_html(false)] \
		+ "<circle cx=\"%d\" cy=\"13\" r=\"10\" fill=\"#%s\"/></g></svg>" % [knob_x, UiTokens.TEXT.to_html(false)]
	return DPITexture.create_from_string(svg)


## Круглый бегунок слайдера диаметром `size` lp.
static func _circle_icon(size: int, color: Color) -> DPITexture:
	var r := size / 2.0
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\">" % [size, size, size, size] \
		+ "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"#%s\"/></svg>" % [r, r, r, color.to_html(false)]
	return DPITexture.create_from_string(svg)
