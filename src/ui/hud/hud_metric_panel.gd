class_name HudMetricPanel
extends PanelContainer
## Панель ключевых цифр HUD заезда (`docs/game/hud.md` п. 5, 5.3, 9, 11; REQ-HUD-01..06,
## REQ-HUD-13 крит. 1, REQ-HUD-14 крит. 3, 4). Подложка — вариация `HudPlate`, 640×166 lp.
##
## Состав (режим `PLAN`, сверху вниз):
## - ряд A (32): прошедшее время с иконкой часов, дистанция, скорость — три равные ячейки;
## - полоса шага (6): пройденная доля текущего шага цветом зоны шага (FreeRide — `hud.free`);
## - ряд C (100): карточка цели (172) — «ЦЕЛЬ», целевой каденс, фишка зоны цели, цель в Вт,
##   «ещё» + обратный отсчёт; герой (264) — сглаженная мощность, фишка и полоса зоны факта,
##   отклонение ●/▲/▼ с разницей; пульс (иконка цветом зоны пульса, фишка зоны) и каденс (150).
##
## Цифры — `Hud*`-вариации темы (шрифт Inter с `tnum`); каждое поле резервирует ширину по
## шаблону максимального значения (`hud.md` п. 5.3), значение выровнено вправо внутри резерва,
## единица стоит за резервом, поэтому смена разрядов не двигает соседей. Узлы расставляются
## по базовым линиям от метрик шрифта (`_relayout`): плотная типографика макета не помещается
## в контейнеры с полными межстрочными интервалами.
##
## Цвета-данные (зоны, отклонение, акцент отсчёта) задаются модуляцией белой основы или
## рисуются (`_draw_*`); стили, шрифты и размеры — только из темы, без `theme_override_*`.
## Фишка зоны — белая плашка 32×18 (r 5) под текстом `hud.ink`, тонированная `modulate` цветом
## зоны; «нет данных» — без заливки, рамка и «—» цветом `hud.text2`.
##
## Режим `FREE_RIDE` (`hud.md` п. 8) наполняет T-079: сейчас он только прячет карточку цели и
## отклонение. Вход данных — `set_state(state)`: словарь `HudModel.state()` плюс поля экрана
## (см. `set_state`).

enum Mode { PLAN, FREE_RIDE }

## Шаблоны резерва разрядов (`hud.md` п. 5.3, REQ-HUD-14 крит. 3).
const TEMPLATE_POWER: String = "8888"
const TEMPLATE_HR: String = "888"
const TEMPLATE_CADENCE: String = "888"
const TEMPLATE_SPEED: String = "88.8"
const TEMPLATE_DISTANCE: String = "888.8"
const TEMPLATE_ELAPSED: String = "8:88:88"
const TEMPLATE_COUNTDOWN: String = "88:88"
const TEMPLATE_DELTA: String = "−8888"

const MINUS: String = "−"
const DEVIATION_GLYPHS: Dictionary = {
	HudModel.DEVIATION_ON: "●", HudModel.DEVIATION_ABOVE: "▲", HudModel.DEVIATION_BELOW: "▼",
}
const DEVIATION_COLORS: Dictionary = {
	HudModel.DEVIATION_ON: UiTokens.HUD_DEV_ON, HudModel.DEVIATION_ABOVE: UiTokens.HUD_WARN,
	HudModel.DEVIATION_BELOW: UiTokens.HUD_DEV_BELOW,
}

## Геометрия (lp HUD, `hud.md` п. 5): содержимое 616×150 внутри полей `HudPlate` 12/8.
const CONTENT_SIZE: Vector2 = Vector2(616, 150)
const ROW_A_BASELINE: float = 25.0
const ICON_SIZE: float = 18.0
const ICON_GAP: float = 6.0
const UNIT_GAP: float = 4.0
const STEP_BAR_RECT: Rect2 = Rect2(0, 38, 616, 6)
const STEP_BAR_RADIUS: float = 3.0
const STEP_BAR_TRACK: Color = Color(1, 1, 1, 0.14)
const ROW_C_Y: float = 50.0
const CARD_RECT: Rect2 = Rect2(0, ROW_C_Y, 172, 100)
const CARD_STRIPE_WIDTH: float = 6.0
const CARD_INNER_LEFT: float = 16.0
const CARD_INNER_RIGHT: float = 162.0
const CARD_ROW1_BASELINE: float = 24.0
const CARD_ROW2_BASELINE: float = 66.0
const CARD_ROW3_BASELINE: float = 92.0
const CARD_CHIP_Y: float = 10.0
const HERO_RECT: Rect2 = Rect2(182, ROW_C_Y, 264, 100)
const HERO_BASELINE: float = 70.0
## Строка зоны под героем (координаты героя).
const ZONE_ROW_Y: float = 80.0
const ZONE_BAR_HEIGHT: float = 5.0
const DELTA_AREA_WIDTH: float = 76.0
const DELTA_FONT_SIZE: int = 15
const GLYPH_SIZE: float = 12.0
const VITALS_RECT: Rect2 = Rect2(462, ROW_C_Y, 150, 100)
const VITALS_ROW1_BASELINE: float = 44.0
const VITALS_ROW2_BASELINE: float = 90.0
const VITALS_VALUE_X: float = 24.0
const VITALS_SIDE_GAP: float = 8.0
const CHIP_SIZE: Vector2 = UiTokens.HUD_ZONE_CHIP_SIZE

var _mode: Mode = Mode.PLAN
var _state: Dictionary = {}
var _step_fraction: float = 0.0
var _step_color: Color = UiTokens.HUD_FREE
var _target_color: Color = UiTokens.HUD_FREE
var _power_zone_color: Color = Color.TRANSPARENT
var _deviation: String = HudModel.DEVIATION_HIDDEN
var _delta_text: String = ""
var _unit_texts: Array[String] = []
## Фишка → есть ли у неё зона (заливка) — для отрисовки подложки.
var _chip_filled: Dictionary = {}
var _bar_box: StyleBoxFlat
var _stripe_box: StyleBoxFlat
var _chip_fill_box: StyleBoxFlat
var _chip_empty_box: StyleBoxFlat

@onready var _content: Control = %Content
@onready var _elapsed_icon: TextureRect = %ElapsedIcon
@onready var _elapsed_label: Label = %ElapsedLabel
@onready var _distance_label: Label = %DistanceLabel
@onready var _distance_unit: Label = %DistanceUnit
@onready var _speed_label: Label = %SpeedLabel
@onready var _speed_unit: Label = %SpeedUnit
@onready var _step_bar: Control = %StepBar
@onready var _target_card: Control = %TargetCard
@onready var _target_title: Label = %TargetTitle
@onready var _target_cadence: Label = %TargetCadenceLabel
@onready var _target_zone_label: Label = %TargetZoneLabel
@onready var _target_label: Label = %TargetLabel
@onready var _target_unit: Label = %TargetUnit
@onready var _countdown_prefix: Label = %CountdownPrefix
@onready var _countdown_label: Label = %CountdownLabel
@onready var _hero: Control = %Hero
@onready var _power_label: Label = %PowerLabel
@onready var _power_unit: Label = %PowerUnit
@onready var _zone_row: Control = %ZoneRow
@onready var _power_zone_label: Label = %PowerZoneLabel
@onready var _vitals: Control = %Vitals
@onready var _hr_icon: TextureRect = %HrIcon
@onready var _hr_label: Label = %HrLabel
@onready var _hr_zone_label: Label = %HrZoneLabel
@onready var _hr_unit: Label = %HrUnit
@onready var _cadence_icon: TextureRect = %CadenceIcon
@onready var _cadence_label: Label = %CadenceLabel
@onready var _cadence_unit: Label = %CadenceUnit


func _ready() -> void:
	_make_boxes()
	_step_bar.draw.connect(_draw_step_bar)
	_target_card.draw.connect(_draw_target_card)
	_zone_row.draw.connect(_draw_zone_row)
	for chip: Label in [_target_zone_label, _power_zone_label, _hr_zone_label]:
		var fill: Control = chip.get_node("Fill")
		fill.draw.connect(_draw_chip_fill.bind(chip, fill))
		_set_chip(chip, "", "")
	_set_static_texts()
	_relayout()
	if not _state.is_empty():
		_apply_state()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_relayout()
	elif what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_set_static_texts()
		_relayout()


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

## Режим панели: план (по умолчанию) или свободная езда (наполнение — T-079).
func set_mode(new_mode: Mode) -> void:
	_mode = new_mode
	if is_node_ready():
		_apply_state()


func mode() -> Mode:
	return _mode


## Обновить панель. `state` — словарь `HudModel.state()`; экран добавляет поля:
## `step_fraction` (0..1, пройденная доля шага), `step_free` (bool, шаг FreeRide),
## `target_zone_token` (зона цели), `target_cadence_rpm` (0 — нет), `resistance_pct`
## (уровень сопротивления для FreeRide-шага). Отсутствующие поля — «нет данных».
func set_state(state: Dictionary) -> void:
	_state = state
	if is_node_ready():
		_apply_state()


## Цель с единицей («300 Вт»/«300 W») или «—» (REQ-HUD-01 крит. 1, 2).
func target_text() -> String:
	return _with_unit(_target_label.text) if int(_state.get("target_w", HudModel.NO_DATA)) >= 0 else HudModel.NO_DATA_TEXT


## Сглаженная мощность с единицей или «—» (REQ-HUD-02 крит. 1).
func power_text() -> String:
	return _with_unit(_power_label.text) if int(_state.get("smoothed_power_w", HudModel.NO_DATA)) >= 0 else HudModel.NO_DATA_TEXT


## Значок отклонения ●/▲/▼ или "" (скрыто) (REQ-HUD-02 крит. 3, 4).
func deviation_text() -> String:
	return str(DEVIATION_GLYPHS.get(_deviation, ""))


## Разница факт − цель со знаком («−53», «+12», «0») или "" (REQ-HUD-02 крит. 4).
func deviation_delta_text() -> String:
	return _delta_text


## Цвет значка отклонения — токен `hud.dev_on` / `hud.warn` / `hud.dev_below` (REQ-HUD-02 крит. 4).
func deviation_color() -> Color:
	return DEVIATION_COLORS.get(_deviation, Color.TRANSPARENT)


func power_zone_text() -> String:
	return _power_zone_label.text


## Цвет заливки фишки зоны факта (прозрачный — «нет данных»).
func power_zone_color() -> Color:
	return chip_fill_color(_power_zone_label)


func hr_zone_text() -> String:
	return _hr_zone_label.text


func hr_zone_color() -> Color:
	return chip_fill_color(_hr_zone_label)


func target_zone_text() -> String:
	return _target_zone_label.text


func target_zone_color() -> Color:
	return chip_fill_color(_target_zone_label)


func hr_text() -> String:
	return _hr_label.text


func cadence_text() -> String:
	return _cadence_label.text


func speed_text() -> String:
	return _speed_label.text


func distance_text() -> String:
	return _distance_label.text


func elapsed_text() -> String:
	return _elapsed_label.text


func countdown_text() -> String:
	return _countdown_label.text


## «Скоро смена» (REQ-HUD-06 крит. 2): отсчёт цветом `hud.warn`.
func is_countdown_accented() -> bool:
	return bool(_state.get("about_to_change", false))


## Пройденная доля текущего шага на полосе шага.
func step_fraction() -> float:
	return _step_fraction


func step_bar_color() -> Color:
	return _step_color


## Цвет заливки фишки: цвет зоны или прозрачный («нет данных»).
func chip_fill_color(chip: Label) -> Color:
	return chip.modulate if bool(_chip_filled.get(chip, false)) else Color.TRANSPARENT


## Узлы-значения по именам — для тестов раскладки и экрана (подписи и соседи).
func value_nodes() -> Dictionary:
	return {
		"elapsed": _elapsed_label, "distance": _distance_label, "distance_unit": _distance_unit,
		"speed": _speed_label, "speed_unit": _speed_unit,
		"target": _target_label, "target_unit": _target_unit, "target_zone": _target_zone_label,
		"target_cadence": _target_cadence,
		"countdown_prefix": _countdown_prefix, "countdown": _countdown_label,
		"power": _power_label, "power_unit": _power_unit, "power_zone": _power_zone_label,
		"hr": _hr_label, "hr_zone": _hr_zone_label, "hr_unit": _hr_unit,
		"cadence": _cadence_label, "cadence_unit": _cadence_unit,
		"target_card": _target_card, "hero": _hero, "zone_row": _zone_row, "vitals": _vitals,
	}


## Карточка цели — контейнер, в котором лежат цель и отсчёт (REQ-HUD-01 крит. 4).
func target_card() -> Control:
	return _target_card


## Передать владение узлами-значениями `new_owner` (экрану): тогда `%TargetLabel`, `%PowerLabel`
## и др. находятся по уникальному имени и от экрана — как до выноса панели в отдельную сцену.
## Ссылки панели на узлы уже закэшированы в `@onready`, поэтому панель от этого не зависит.
func share_unique_names(new_owner: Node) -> void:
	for node: Node in [_elapsed_label, _speed_label, _target_label, _countdown_label, _power_label,
			_power_zone_label, _hr_label, _hr_zone_label, _cadence_label]:
		node.owner = new_owner
		node.unique_name_in_owner = true


# ---------------------------------------------------------------------------
# Отрисовка состояния
# ---------------------------------------------------------------------------

func _apply_state() -> void:
	var s := _state
	var free_mode := _mode == Mode.FREE_RIDE
	# Ряд A.
	_elapsed_label.text = str(s.get("elapsed_text", HudModel.format_elapsed(0)))
	_distance_label.text = "%.1f" % (float(s.get("distance_m", 0.0)) / 1000.0)
	_speed_label.text = str(s.get("speed_text", HudModel.NO_DATA_TEXT))
	# Полоса шага.
	var step_free := bool(s.get("step_free", false))
	_step_fraction = clampf(float(s.get("step_fraction", 0.0)), 0.0, 1.0)
	var target_token := str(s.get("target_zone_token", ""))
	_step_color = UiTokens.HUD_FREE if step_free or target_token.is_empty() else ZonePalette.color(target_token)
	_target_color = _step_color
	_step_bar.queue_redraw()
	# Карточка цели.
	_target_card.visible = not free_mode
	var has_target := int(s.get("target_w", HudModel.NO_DATA)) >= 0
	_target_title.text = tr("ui.hud.target.free") if step_free else tr("ui.hud.target.title")
	_target_label.text = str(s.get("target_text", HudModel.NO_DATA_TEXT)) if has_target else HudModel.NO_DATA_TEXT
	var cadence := int(s.get("target_cadence_rpm", 0))
	if step_free:
		_target_cadence.text = tr("ui.hud.target.resistance").format({"value": int(s.get("resistance_pct", 0))})
	else:
		_target_cadence.text = tr("ui.hud.target.cadence").format({"value": cadence}) if cadence > 0 else ""
	_set_chip(_target_zone_label, "" if step_free else target_token, ("Z%d" % (ZonePalette.POWER_TOKENS.find(target_token) + 1)) if ZonePalette.POWER_TOKENS.has(target_token) else HudModel.NO_DATA_TEXT)
	_target_zone_label.visible = not step_free
	# Каденс (или сопротивление FreeRide-шага) — справа в строке 1, перед фишкой зоны.
	var cadence_right := _target_zone_label.position.x - ICON_GAP if _target_zone_label.visible else CARD_INNER_RIGHT
	var cadence_w := ceilf(_text_width(_target_cadence, _target_cadence.text))
	_place_right(_target_cadence, cadence_right - cadence_w, cadence_w, CARD_ROW1_BASELINE)
	_countdown_label.text = str(s.get("countdown_text", HudModel.NO_DATA_TEXT))
	_countdown_label.modulate = UiTokens.HUD_WARN if is_countdown_accented() else Color.WHITE
	_target_card.queue_redraw()
	# Герой.
	var has_power := int(s.get("smoothed_power_w", HudModel.NO_DATA)) >= 0
	_power_label.text = str(s.get("power_text", HudModel.NO_DATA_TEXT)) if has_power else HudModel.NO_DATA_TEXT
	var power_token := str(s.get("power_zone_token", ""))
	_set_chip(_power_zone_label, power_token, str(s.get("power_zone_text", HudModel.NO_DATA_TEXT)))
	_power_zone_color = ZonePalette.color(power_token) if not power_token.is_empty() else Color.TRANSPARENT
	_deviation = HudModel.DEVIATION_HIDDEN if free_mode else str(s.get("power_deviation", HudModel.DEVIATION_HIDDEN))
	_delta_text = ""
	if _deviation != HudModel.DEVIATION_HIDDEN:
		var diff := int(s.get("smoothed_power_w", 0)) - int(s.get("target_w", 0))
		_delta_text = ("+%d" % diff) if diff > 0 else (("%s%d" % [MINUS, -diff]) if diff < 0 else "0")
	_zone_row.queue_redraw()
	# Пульс и каденс.
	_hr_label.text = str(s.get("hr_text", HudModel.NO_DATA_TEXT))
	var hr_token := str(s.get("hr_zone_token", ""))
	_set_chip(_hr_zone_label, hr_token, str(s.get("hr_zone_text", HudModel.NO_DATA_TEXT)))
	_hr_icon.modulate = ZonePalette.color(hr_token) if not hr_token.is_empty() else UiTokens.HUD_TEXT2
	_cadence_label.text = str(s.get("cadence_text", HudModel.NO_DATA_TEXT))


## Фишка зоны: токен → белая плашка, тонированная цветом зоны; пустой токен → рамка и «—».
func _set_chip(chip: Label, token: String, text: String) -> void:
	var filled := not token.is_empty()
	_chip_filled[chip] = filled
	chip.text = text if filled else HudModel.NO_DATA_TEXT
	chip.theme_type_variation = &"HudZoneChipLabel" if filled else &"HudCaptionLabel"
	chip.modulate = ZonePalette.color(token) if filled else Color.WHITE
	(chip.get_node("Fill") as Control).queue_redraw()


func _set_static_texts() -> void:
	var unit_w := tr("ui.workout.unit_w")
	_target_unit.text = unit_w
	_power_unit.text = unit_w
	_distance_unit.text = tr("ui.hud.unit.km")
	_speed_unit.text = tr("ui.hud.unit.kmh")
	_hr_unit.text = tr("ui.hud.unit.bpm")
	_cadence_unit.text = tr("ui.hud.unit.rpm")
	_countdown_prefix.text = tr("ui.hud.target.remaining")
	if not _state.is_empty():
		_apply_state()


func _with_unit(value: String) -> String:
	return tr("ui.workout.target_value").format({"value": value})


# ---------------------------------------------------------------------------
# Раскладка по базовым линиям
# ---------------------------------------------------------------------------

func _relayout() -> void:
	_content.custom_minimum_size = CONTENT_SIZE
	_step_bar.position = STEP_BAR_RECT.position
	_step_bar.size = STEP_BAR_RECT.size
	# Ряд A: три равные ячейки, группа «значение + единица» по центру ячейки.
	var cell_w := CONTENT_SIZE.x / 3.0
	var elapsed_w := _reserve(_elapsed_label, TEMPLATE_ELAPSED)
	var group_w := ICON_SIZE + ICON_GAP + elapsed_w
	var x := (cell_w - group_w) * 0.5
	_place_icon(_elapsed_icon, Vector2(x, ROW_A_BASELINE - _cap_height(_elapsed_label) * 0.5 - ICON_SIZE * 0.5))
	_place_right(_elapsed_label, x + ICON_SIZE + ICON_GAP, elapsed_w, ROW_A_BASELINE)
	_place_value_unit(_distance_label, _distance_unit, TEMPLATE_DISTANCE, cell_w, cell_w, ROW_A_BASELINE)
	_place_value_unit(_speed_label, _speed_unit, TEMPLATE_SPEED, cell_w * 2.0, cell_w, ROW_A_BASELINE)
	# Карточка цели (координаты карточки).
	_target_card.position = CARD_RECT.position
	_target_card.size = CARD_RECT.size
	_place(_target_title, Vector2(CARD_INNER_LEFT, 0), CARD_ROW1_BASELINE)
	_place_chip(_target_zone_label, Vector2(CARD_INNER_RIGHT - CHIP_SIZE.x, CARD_CHIP_Y))
	var target_w := _reserve(_target_label, TEMPLATE_POWER)
	_place_right(_target_label, CARD_INNER_LEFT, target_w, CARD_ROW2_BASELINE)
	_place(_target_unit, Vector2(CARD_INNER_LEFT + target_w + UNIT_GAP, 0), CARD_ROW2_BASELINE)
	_place(_countdown_prefix, Vector2(CARD_INNER_LEFT, 0), CARD_ROW3_BASELINE)
	var prefix_w := _text_width(_countdown_prefix, _countdown_prefix.text)
	_place_right(_countdown_label, CARD_INNER_LEFT + prefix_w + ICON_GAP, _reserve(_countdown_label, TEMPLATE_COUNTDOWN), CARD_ROW3_BASELINE)
	# Герой (координаты героя).
	_hero.position = HERO_RECT.position
	_hero.size = HERO_RECT.size
	var power_w := _reserve(_power_label, TEMPLATE_POWER)
	_place_right(_power_label, 0, power_w, HERO_BASELINE)
	_place(_power_unit, Vector2(power_w + UNIT_GAP, 0), HERO_BASELINE)
	_zone_row.position = Vector2(0, ZONE_ROW_Y)
	_zone_row.size = Vector2(HERO_RECT.size.x, CHIP_SIZE.y)
	_place_chip(_power_zone_label, Vector2.ZERO)
	# Пульс и каденс (координаты блока).
	_vitals.position = VITALS_RECT.position
	_vitals.size = VITALS_RECT.size
	var hr_w := _reserve(_hr_label, TEMPLATE_HR)
	_place_icon(_hr_icon, Vector2(0, VITALS_ROW1_BASELINE - _cap_height(_hr_label) * 0.5 - ICON_SIZE * 0.5))
	_place_right(_hr_label, VITALS_VALUE_X, hr_w, VITALS_ROW1_BASELINE)
	var side_x := VITALS_VALUE_X + hr_w + VITALS_SIDE_GAP
	_place_chip(_hr_zone_label, Vector2(side_x, VITALS_ROW1_BASELINE - _cap_height(_hr_label) - 4.0))
	_place(_hr_unit, Vector2(side_x, 0), VITALS_ROW1_BASELINE + 2.0)
	var cad_w := _reserve(_cadence_label, TEMPLATE_CADENCE)
	_place_icon(_cadence_icon, Vector2(0, VITALS_ROW2_BASELINE - _cap_height(_cadence_label) * 0.5 - ICON_SIZE * 0.5))
	_place_right(_cadence_label, VITALS_VALUE_X, cad_w, VITALS_ROW2_BASELINE)
	_place(_cadence_unit, Vector2(VITALS_VALUE_X + cad_w + VITALS_SIDE_GAP, 0), VITALS_ROW2_BASELINE)


## Значение с единицей по центру ячейки `[cell_x, cell_x + cell_w]`.
func _place_value_unit(value: Label, unit: Label, template: String, cell_x: float, cell_w: float, baseline: float) -> void:
	var value_w := _reserve(value, template)
	var unit_w := _text_width(unit, unit.text)
	var x := cell_x + (cell_w - value_w - UNIT_GAP - unit_w) * 0.5
	_place_right(value, x, value_w, baseline)
	_place(unit, Vector2(x + value_w + UNIT_GAP, 0), baseline)


## Ширина шаблона максимального значения шрифтом подписи (резерв разрядов).
func _reserve(label: Label, template: String) -> float:
	return ceilf(_text_width(label, template))


func _text_width(label: Label, text: String) -> float:
	var font := label.get_theme_font(&"font")
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size(&"font_size")).x


func _ascent(label: Label) -> float:
	return label.get_theme_font(&"font").get_ascent(label.get_theme_font_size(&"font_size"))


## Высота прописных цифр (≈ 0.727 em у Inter) — для центровки иконок по цифрам.
func _cap_height(label: Label) -> float:
	return 0.727 * float(label.get_theme_font_size(&"font_size"))


## Подпись по левому краю `pos.x` с базовой линией `baseline` (y относительно родителя).
func _place(label: Label, pos: Vector2, baseline: float) -> void:
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.position = Vector2(pos.x, baseline - _ascent(label))
	label.size = label.get_combined_minimum_size()


## Значение в резерве ширины `width` от `x`, выравнивание вправо.
func _place_right(label: Label, x: float, width: float, baseline: float) -> void:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.custom_minimum_size = Vector2(width, 0)
	label.position = Vector2(x, baseline - _ascent(label))
	label.size = Vector2(width, label.get_combined_minimum_size().y)


func _place_chip(chip: Label, pos: Vector2) -> void:
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.custom_minimum_size = CHIP_SIZE
	chip.position = pos
	chip.size = CHIP_SIZE


func _place_icon(icon: TextureRect, pos: Vector2) -> void:
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = pos
	icon.size = Vector2(ICON_SIZE, ICON_SIZE)


# ---------------------------------------------------------------------------
# Рисование
# ---------------------------------------------------------------------------

func _draw_step_bar() -> void:
	var rect := Rect2(Vector2.ZERO, _step_bar.size)
	_bar_box.bg_color = STEP_BAR_TRACK
	_step_bar.draw_style_box(_bar_box, rect)
	if _step_fraction > 0.0:
		var fill := Rect2(rect.position, Vector2(maxf(rect.size.x * _step_fraction, STEP_BAR_RADIUS * 2.0), rect.size.y))
		_bar_box.bg_color = _step_color
		_step_bar.draw_style_box(_bar_box, fill)


## Подложка карточки — стиль `HudCard` из темы; слева полоса цвета зоны цели.
func _draw_target_card() -> void:
	var rect := Rect2(Vector2.ZERO, _target_card.size)
	var box := get_theme_stylebox(&"panel", &"HudCard")
	_target_card.draw_style_box(box, rect)
	var radius := (box as StyleBoxFlat).corner_radius_top_left if box is StyleBoxFlat else 12
	_stripe_box.bg_color = _target_color
	_stripe_box.corner_radius_top_left = radius
	_stripe_box.corner_radius_bottom_left = radius
	_target_card.draw_style_box(_stripe_box, Rect2(Vector2.ZERO, Vector2(CARD_STRIPE_WIDTH, rect.size.y)))


## Строка зоны под героем: полоса цвета зоны факта (скрыта без данных), справа значок
## отклонения и разница факт − цель (цифры `tnum`) цветом токена отклонения.
func _draw_zone_row() -> void:
	var h := _zone_row.size.y
	var bar_x := CHIP_SIZE.x + ICON_GAP
	var bar_end := _zone_row.size.x - DELTA_AREA_WIDTH
	if _power_zone_color.a > 0.0:
		_zone_row.draw_rect(Rect2(bar_x, (h - ZONE_BAR_HEIGHT) * 0.5, bar_end - bar_x, ZONE_BAR_HEIGHT), _power_zone_color)
	if _deviation == HudModel.DEVIATION_HIDDEN:
		return
	var color := deviation_color()
	var font := _countdown_label.get_theme_font(&"font")
	var delta_w := font.get_string_size(_delta_text, HORIZONTAL_ALIGNMENT_LEFT, -1, DELTA_FONT_SIZE).x
	var right := _zone_row.size.x
	# Базовая линия — так, чтобы прописные цифры (≈ 0.727 em) стояли по центру строки.
	var baseline := (h + 0.727 * DELTA_FONT_SIZE) * 0.5
	_zone_row.draw_string(font, Vector2(right - delta_w, baseline), _delta_text, HORIZONTAL_ALIGNMENT_LEFT, -1, DELTA_FONT_SIZE, color)
	var g := GLYPH_SIZE
	var gx := right - delta_w - ICON_GAP - g
	var gy := (h - g) * 0.5
	match _deviation:
		HudModel.DEVIATION_ABOVE:
			_zone_row.draw_colored_polygon(PackedVector2Array([Vector2(gx + g * 0.5, gy), Vector2(gx + g, gy + g), Vector2(gx, gy + g)]), color)
		HudModel.DEVIATION_BELOW:
			_zone_row.draw_colored_polygon(PackedVector2Array([Vector2(gx, gy), Vector2(gx + g, gy), Vector2(gx + g * 0.5, gy + g)]), color)
		_:
			_zone_row.draw_circle(Vector2(gx + g * 0.5, gy + g * 0.5), g * 0.42, color)


## Подложка фишки: белая плашка (тонируется `modulate` подписи) или рамка `hud.text2`.
func _draw_chip_fill(chip: Label, fill: Control) -> void:
	var rect := Rect2(Vector2.ZERO, chip.size)
	fill.draw_style_box(_chip_fill_box if bool(_chip_filled.get(chip, false)) else _chip_empty_box, rect)


func _make_boxes() -> void:
	_bar_box = _flat_box(STEP_BAR_TRACK, STEP_BAR_RADIUS)
	_stripe_box = _flat_box(UiTokens.HUD_FREE, 0)
	_chip_fill_box = _flat_box(Color.WHITE, UiTokens.HUD_ZONE_CHIP_RADIUS)
	_chip_empty_box = _flat_box(Color.TRANSPARENT, UiTokens.HUD_ZONE_CHIP_RADIUS)
	_chip_empty_box.draw_center = false
	_chip_empty_box.set_border_width_all(UiTokens.HUD_ZONE_CHIP_EMPTY_BORDER)
	_chip_empty_box.border_color = UiTokens.HUD_ZONE_CHIP_EMPTY_TEXT


static func _flat_box(color: Color, radius: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(int(radius))
	box.anti_aliasing = true
	return box
