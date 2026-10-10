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
## Режим `FREE_RIDE` (`hud.md` п. 8; REQ-FRD-06 крит. 1, 2, REQ-FRD-05 крит. 6 — отображение):
## - ряд A — четыре равные ячейки: время, дистанция (км с одним знаком, накопленная за заезд),
##   скорость, набор за заезд «↑ 612 м» (целые метры);
## - полоса — прогресс круга трассы, заливка `hud.text` с альфой 0.85;
## - вместо карточки цели — карточка «УКЛОН»: полный уклон трассы g(s) (не переданный станку),
##   знак всегда, один знак после точки («+6.4», «−3.0» с U+2212, «0.0»), белым; справа в строке
##   заголовка клин 32 × 14 цвета палитры уклона (`UiTokens.grade_color`): заполняет рамку при
##   |g| ≥ 8 %, ниже — пропорционально (иначе реальные 3–7 % дают едва заметные 2–4 lp);
##   строка 3 — режим нагрузки и крутизна «SIM 50 %» или уровень «СОПР. 40 %»;
## - герой — факт мощности с фишкой и полосой зоны, без отклонения; пульс и каденс — как в плане;
##   цели, отсчёта и списка нет. Отсутствующее значение — «—».
##
## Вход данных — `set_state(state)`: словарь `HudModel.state()` (или такой же словарь экрана
## свободной езды) плюс поля экрана (см. `set_state`); поля свободной езды из сессии —
## `free_ride_fields(session)`. Пауза — `set_dimmed(true)`: значения получают альфу 0.6
## (`hud.md` п. 10.2), подложка остаётся.

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
const TEMPLATE_GRADE: String = "+88.8"
const TEMPLATE_ASCENT: String = "8888"

## Поля состояния свободной езды (`set_state`).
const KEY_GRADE_PCT: String = "grade_pct"
const KEY_LOAD_MODE: String = "load_mode"
const KEY_STEEPNESS_PCT: String = "steepness_pct"
const KEY_RESISTANCE_PCT: String = "resistance_pct"
const KEY_ASCENT_M: String = "ascent_m"
const KEY_LAP_FRACTION: String = "lap_fraction"

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
## Разница отклонения — вариация темы `HudDelta` (15 / 700 `tnum`); кегль — для справки и тестов.
const DELTA_VARIATION: StringName = &"HudDelta"
const DELTA_FONT_SIZE: int = 15
const GLYPH_SIZE: float = 12.0
const VITALS_RECT: Rect2 = Rect2(462, ROW_C_Y, 150, 100)
const VITALS_ROW1_BASELINE: float = 44.0
const VITALS_ROW2_BASELINE: float = 90.0
const VITALS_VALUE_X: float = 24.0
const VITALS_SIDE_GAP: float = 8.0
const CHIP_SIZE: Vector2 = UiTokens.HUD_ZONE_CHIP_SIZE
## Полоса круга в свободной езде (`hud.md` п. 8).
const LAP_BAR_COLOR: Color = Color(UiTokens.HUD_TEXT, 0.85)
## Клин уклона: рамка 32 × 14; высота = высота рамки × min(|g| / `WEDGE_FULL_GRADE_PCT`, 1) —
## при |g| ≥ 8 % клин заполняет рамку, ниже пропорционально (не меньше `WEDGE_MIN_HEIGHT`);
## ровно (|g| < 0.05 %) — полоска `WEDGE_MIN_HEIGHT`.
const WEDGE_SIZE: Vector2 = Vector2(32, 14)
const WEDGE_FULL_GRADE_PCT: float = 8.0
const WEDGE_MIN_HEIGHT: float = 2.0
## Альфа значений на паузе (`hud.md` п. 10.2).
const DIMMED_ALPHA: float = 0.6
## Tolerance scale in place of the zone bar (`hud.md` p. 16.2, T-175): track, band, marker, triangles.
const SCALE_TRACK_HEIGHT: float = 10.0
const SCALE_TRACK_RADIUS: float = 5.0
const SCALE_TRACK_COLOR: Color = Color(1, 1, 1, 0.14)
const SCALE_BAND_COLOR: Color = Color(UiTokens.HUD_DEV_ON, 0.30)
const SCALE_BAND_EDGE: float = 1.5
const SCALE_MARKER_SIZE: Vector2 = Vector2(4, 16)
const SCALE_MARKER_OUTLINE: float = 1.0
const SCALE_TRIANGLE: float = 10.0
## Marker glide to the new position (ease-out).
const SCALE_MOVE_SEC: float = 0.3

var _mode: Mode = Mode.PLAN
var _state: Dictionary = {}
var _step_fraction: float = 0.0
var _step_color: Color = UiTokens.HUD_FREE
var _target_color: Color = UiTokens.HUD_FREE
var _power_zone_color: Color = Color.TRANSPARENT
## Уклон трассы для клина (NAN — нет данных).
var _grade: float = NAN
var _deviation: String = HudModel.DEVIATION_HIDDEN
var _delta_text: String = ""
## Tolerance scale of `HudModel.state()["tolerance_scale"]` (empty — zone bar) and the drawn marker.
var _scale: Dictionary = {}
var _marker_fraction: float = 0.5
var _marker_tween: Tween = null
var _marker_goal: float = 0.5
var _scale_track_box: StyleBoxFlat
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
@onready var _ascent_icon: Label = %AscentIcon
@onready var _ascent_label: Label = %AscentLabel
@onready var _ascent_unit: Label = %AscentUnit
@onready var _step_bar: Control = %StepBar
@onready var _target_card: Control = %TargetCard
@onready var _target_title: Label = %TargetTitle
@onready var _target_cadence: Label = %TargetCadenceLabel
@onready var _target_zone_label: Label = %TargetZoneLabel
@onready var _target_label: Label = %TargetLabel
@onready var _target_unit: Label = %TargetUnit
@onready var _countdown_prefix: Label = %CountdownPrefix
@onready var _countdown_label: Label = %CountdownLabel
@onready var _grade_card: Control = %GradeCard
@onready var _grade_title: Label = %GradeTitle
@onready var _grade_wedge: Control = %GradeWedge
@onready var _grade_label: Label = %GradeLabel
@onready var _grade_unit: Label = %GradeUnit
@onready var _grade_mode_label: Label = %GradeModeLabel
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
	_grade_card.draw.connect(_draw_grade_card)
	_grade_wedge.draw.connect(_draw_grade_wedge)
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

## Режим панели: план (по умолчанию) или свободная езда. Меняет состав ряда A и карточку.
func set_mode(new_mode: Mode) -> void:
	_mode = new_mode
	if is_node_ready():
		_relayout()
		_apply_state()


func mode() -> Mode:
	return _mode


## Обновить панель. `state` — словарь `HudModel.state()`; экран добавляет поля:
## `step_fraction` (0..1, пройденная доля шага), `step_free` (bool, шаг FreeRide),
## `target_zone_token` (зона цели), `target_cadence_rpm` (0 — нет), `resistance_pct`
## (уровень сопротивления для FreeRide-шага). Отсутствующие поля — «нет данных».
## Свободная езда (`Mode.FREE_RIDE`), см. `free_ride_fields`: `grade_pct` (float, полный уклон
## трассы g(s), %), `load_mode` (`SimController.Mode`), `steepness_pct`, `resistance_pct`
## (уровень фиксированного сопротивления), `distance_m` (накопленная дистанция), `ascent_m`
## (набор за заезд), `lap_fraction` (0..1, пройденная доля круга).
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


## Пройденная доля на полосе: текущего шага (план) или круга (свободная езда).
func step_fraction() -> float:
	return _step_fraction


func step_bar_color() -> Color:
	return _step_color


## Цвет заливки фишки: цвет зоны или прозрачный («нет данных»).
func chip_fill_color(chip: Label) -> Color:
	return chip.modulate if bool(_chip_filled.get(chip, false)) else Color.TRANSPARENT


## Уклон в карточке «УКЛОН» («+6.4», «−3.0», «0.0») или «—» (REQ-FRD-06 крит. 1, 2).
func grade_text() -> String:
	return _grade_label.text


## Строка режима в карточке уклона: «SIM 50 %», «СОПР. 40 %» или «—» (REQ-FRD-05 крит. 6).
func grade_mode_text() -> String:
	return _grade_mode_label.text


## Цвет клина уклона (палитра уклона); прозрачный — нет данных.
func grade_wedge_color() -> Color:
	return UiTokens.grade_color(_grade) if not is_nan(_grade) else Color.TRANSPARENT


## Высота клина уклона, lp (0 — нет данных).
func grade_wedge_height() -> float:
	if is_nan(_grade):
		return 0.0
	var g := roundf(_grade * 10.0) / 10.0
	if g == 0.0:
		return WEDGE_MIN_HEIGHT
	return clampf(WEDGE_SIZE.y * absf(g) / WEDGE_FULL_GRADE_PCT, WEDGE_MIN_HEIGHT, WEDGE_SIZE.y)


## Набор за заезд — целые метры или «—» (REQ-FRD-06 крит. 1).
func ascent_text() -> String:
	return _ascent_label.text


## Карточка уклона (на месте карточки цели в свободной езде).
func grade_card() -> Control:
	return _grade_card


## Узлы свободной езды по именам — для тестов раскладки и экрана.
func free_ride_nodes() -> Dictionary:
	return {
		"ascent_icon": _ascent_icon, "ascent": _ascent_label, "ascent_unit": _ascent_unit,
		"grade_card": _grade_card, "grade_title": _grade_title, "grade_wedge": _grade_wedge,
		"grade": _grade_label, "grade_unit": _grade_unit, "grade_mode": _grade_mode_label,
	}


## Поля свободной езды для `set_state` из сессии: уклон трассы (не переданный станку,
## FRD-06 крит. 2), режим нагрузки, крутизна и уровень, накопленная дистанция, набор,
## пройденная доля круга. Остальные поля (время, мощность, пульс…) даёт модель экрана.
static func free_ride_fields(session: FreeRideSession) -> Dictionary:
	var length: float = session.position.length_m()
	return {
		KEY_GRADE_PCT: session.route_grade_pct(),
		KEY_LOAD_MODE: int(session.mode()),
		KEY_STEEPNESS_PCT: session.steepness_pct(),
		KEY_RESISTANCE_PCT: session.resistance_level(),
		"distance_m": session.distance_m(),
		KEY_ASCENT_M: session.ascent_m(),
		KEY_LAP_FRACTION: session.position.lap_distance_m() / length if length > 0.0 else 0.0,
	}


## Уклон со знаком всегда и одним знаком после точки: «+6.4», «−3.0» (U+2212), «0.0»;
## NAN/бесконечность — «—» (REQ-FRD-06 крит. 1).
static func format_grade(grade_pct: float) -> String:
	if not is_finite(grade_pct):
		return HudModel.NO_DATA_TEXT
	var r: float = roundf(grade_pct * 10.0) / 10.0
	if r == 0.0:
		return "0.0"
	return ("+%.1f" % r) if r > 0.0 else ("%s%.1f" % [MINUS, -r])


## Набор — целые метры; отрицательное/NAN — «—».
static func format_ascent(ascent_m: float) -> String:
	if not is_finite(ascent_m) or ascent_m < 0.0:
		return HudModel.NO_DATA_TEXT
	return "%d" % roundi(ascent_m)


## Строка режима нагрузки: SIM — «SIM {крутизна} %», фиксированное — «СОПР. {уровень} %».
static func load_mode_text(load_mode: int, steepness_pct: int, resistance_pct: int) -> String:
	match load_mode:
		SimController.Mode.SIM:
			return String(TranslationServer.translate("ui.free_ride.grade.sim")).format({"value": steepness_pct})
		SimController.Mode.FIXED:
			return String(TranslationServer.translate("ui.free_ride.grade.fixed")).format({"value": resistance_pct})
	return HudModel.NO_DATA_TEXT


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


## Пауза: значения панели приглушены (альфа `DIMMED_ALPHA`), подложка остаётся (`hud.md` п. 10.2).
func set_dimmed(dimmed: bool) -> void:
	_content.modulate.a = DIMMED_ALPHA if dimmed else 1.0


func is_dimmed() -> bool:
	return _content.modulate.a < 1.0


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
	_ascent_label.text = format_ascent(float(s.get(KEY_ASCENT_M, -1.0)))
	for node: Control in [_ascent_icon, _ascent_label, _ascent_unit]:
		node.visible = free_mode
	# Полоса шага (план) или круга (свободная езда).
	var step_free := bool(s.get("step_free", false))
	var target_token := str(s.get("target_zone_token", ""))
	if free_mode:
		_step_fraction = clampf(float(s.get(KEY_LAP_FRACTION, 0.0)), 0.0, 1.0)
		_step_color = LAP_BAR_COLOR
	else:
		_step_fraction = clampf(float(s.get("step_fraction", 0.0)), 0.0, 1.0)
		_step_color = UiTokens.HUD_FREE if step_free or target_token.is_empty() else ZonePalette.color(target_token)
	_target_color = _step_color
	_step_bar.queue_redraw()
	# Карточка уклона (свободная езда).
	_grade_card.visible = free_mode
	_grade = float(s.get(KEY_GRADE_PCT, NAN))
	_grade_label.text = format_grade(_grade)
	_grade_mode_label.text = load_mode_text(int(s.get(KEY_LOAD_MODE, -1)), int(s.get(KEY_STEEPNESS_PCT, 0)),
			int(s.get(KEY_RESISTANCE_PCT, 0)))
	_grade_wedge.queue_redraw()
	_grade_card.queue_redraw()
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
	_apply_scale(s.get("tolerance_scale", {}) if not free_mode else {})
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
	_ascent_unit.text = tr("ui.free_ride.unit.m")
	_grade_unit.text = tr("ui.free_ride.unit.pct")
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
	# Ряд A: три (план) или четыре (свободная езда: + набор) равные ячейки, группа «значение +
	# единица» по центру ячейки.
	var cell_w := CONTENT_SIZE.x / (4.0 if _mode == Mode.FREE_RIDE else 3.0)
	var elapsed_w := _reserve(_elapsed_label, TEMPLATE_ELAPSED)
	var group_w := ICON_SIZE + ICON_GAP + elapsed_w
	var x := (cell_w - group_w) * 0.5
	_place_icon(_elapsed_icon, Vector2(x, ROW_A_BASELINE - _cap_height(_elapsed_label) * 0.5 - ICON_SIZE * 0.5))
	_place_right(_elapsed_label, x + ICON_SIZE + ICON_GAP, elapsed_w, ROW_A_BASELINE)
	_place_value_unit(_distance_label, _distance_unit, TEMPLATE_DISTANCE, cell_w, cell_w, ROW_A_BASELINE)
	_place_value_unit(_speed_label, _speed_unit, TEMPLATE_SPEED, cell_w * 2.0, cell_w, ROW_A_BASELINE)
	# Набор: «↑» + значение в резерве `8888` + «м».
	var arrow_w := ceilf(_text_width(_ascent_icon, _ascent_icon.text))
	var ascent_w := _reserve(_ascent_label, TEMPLATE_ASCENT)
	var ascent_unit_w := _text_width(_ascent_unit, _ascent_unit.text)
	var ax := cell_w * 3.0 + (cell_w - arrow_w - ICON_GAP - ascent_w - UNIT_GAP - ascent_unit_w) * 0.5
	_place(_ascent_icon, Vector2(ax, 0), ROW_A_BASELINE)
	_place_right(_ascent_label, ax + arrow_w + ICON_GAP, ascent_w, ROW_A_BASELINE)
	_place(_ascent_unit, Vector2(ax + arrow_w + ICON_GAP + ascent_w + UNIT_GAP, 0), ROW_A_BASELINE)
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
	# Карточка уклона — в тех же границах и по тем же строкам, что карточка цели.
	_grade_card.position = CARD_RECT.position
	_grade_card.size = CARD_RECT.size
	_place(_grade_title, Vector2(CARD_INNER_LEFT, 0), CARD_ROW1_BASELINE)
	_grade_wedge.position = Vector2(CARD_INNER_RIGHT - WEDGE_SIZE.x, CARD_CHIP_Y + (CHIP_SIZE.y - WEDGE_SIZE.y) * 0.5)
	_grade_wedge.size = WEDGE_SIZE
	var grade_w := _reserve(_grade_label, TEMPLATE_GRADE)
	_place_right(_grade_label, CARD_INNER_LEFT, grade_w, CARD_ROW2_BASELINE)
	_place(_grade_unit, Vector2(CARD_INNER_LEFT + grade_w + UNIT_GAP, 0), CARD_ROW2_BASELINE)
	_place(_grade_mode_label, Vector2(CARD_INNER_LEFT, 0), CARD_ROW3_BASELINE)
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


## Подложка карточки уклона — стиль `HudCard` темы, без полосы зоны (цвет есть только у клина).
func _draw_grade_card() -> void:
	_grade_card.draw_style_box(get_theme_stylebox(&"panel", &"HudCard"), Rect2(Vector2.ZERO, _grade_card.size))


## Клин уклона: прямоугольный треугольник на нижней стороне рамки, подъём — вверх вправо,
## спуск — вниз вправо; ровно — полоска (`grade_wedge_height`).
func _draw_grade_wedge() -> void:
	if is_nan(_grade):
		return
	var w := WEDGE_SIZE.x
	var bottom := WEDGE_SIZE.y
	var h := grade_wedge_height()
	var color := grade_wedge_color()
	var g := roundf(_grade * 10.0) / 10.0
	if g == 0.0:
		_grade_wedge.draw_rect(Rect2(0, bottom - h, w, h), color)
		return
	var tip_x := w if g > 0.0 else 0.0
	_grade_wedge.draw_colored_polygon(PackedVector2Array([
		Vector2(0, bottom), Vector2(w, bottom), Vector2(tip_x, bottom - h),
	]), color)


## Tolerance scale shown in place of the zone bar (T-175).
func is_tolerance_scale_shown() -> bool:
	return not _scale.is_empty()


## Where the marker goes, share of the scale width (the drawn marker glides there in 300 ms).
func scale_marker_fraction() -> float:
	return float(_scale.get("fraction", 0.5))


## Marker visible (power has data and is within the scale).
func is_scale_marker_shown() -> bool:
	return not _scale.is_empty() and bool(_scale.get("marker", false)) and int(_scale.get("edge", 0)) == 0


## −1 / 1 — triangle at the left / right edge, 0 — none.
func scale_edge() -> int:
	return int(_scale.get("edge", 0)) if not _scale.is_empty() and bool(_scale.get("marker", false)) else 0


## Marker colour = deviation glyph colour; `hud.text` in the acclimatisation window.
func scale_marker_color() -> Color:
	var state := str(_scale.get("state", ""))
	return DEVIATION_COLORS.get(state, UiTokens.HUD_TEXT)


func _apply_scale(scale: Dictionary) -> void:
	var was_shown := not _scale.is_empty()
	_scale = scale
	if _scale.is_empty():
		return
	var to := float(_scale.get("fraction", 0.5))
	if not was_shown or not is_inside_tree():
		_marker_goal = to
		_set_marker_fraction(to)
		return
	if is_equal_approx(to, _marker_goal):
		return  # refresh without a new sample: the glide in progress continues
	_marker_goal = to
	if _marker_tween != null:
		_marker_tween.kill()
	_marker_tween = create_tween()
	_marker_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_marker_tween.tween_method(_set_marker_fraction, _marker_fraction, to, SCALE_MOVE_SEC)


func _set_marker_fraction(value: float) -> void:
	_marker_fraction = value
	_zone_row.queue_redraw()


## Tolerance scale (`hud.md` p. 16.2): track, the band ±tol in the middle third, the marker of the
## smoothed power (or ◀ / ▶ beyond the range); "no data" — track and band only.
func _draw_scale(x: float, width: float, h: float) -> void:
	var cy := h * 0.5
	var track := Rect2(x, cy - SCALE_TRACK_HEIGHT * 0.5, width, SCALE_TRACK_HEIGHT)
	_zone_row.draw_style_box(_scale_track_box, track)
	var b: Vector2 = _scale.get("band", ToleranceScale.band())
	var band := Rect2(x + width * b.x, track.position.y, width * (b.y - b.x), SCALE_TRACK_HEIGHT)
	_zone_row.draw_rect(band, SCALE_BAND_COLOR)
	_zone_row.draw_line(Vector2(band.position.x, band.position.y), Vector2(band.position.x, band.end.y), UiTokens.HUD_DEV_ON, SCALE_BAND_EDGE)
	_zone_row.draw_line(Vector2(band.end.x, band.position.y), Vector2(band.end.x, band.end.y), UiTokens.HUD_DEV_ON, SCALE_BAND_EDGE)
	if not bool(_scale.get("marker", false)):
		return
	var color := scale_marker_color()
	var t := SCALE_TRIANGLE
	match scale_edge():
		-1:
			_zone_row.draw_colored_polygon(PackedVector2Array([Vector2(x, cy), Vector2(x + t, cy - t * 0.5), Vector2(x + t, cy + t * 0.5)]), color)
		1:
			var r := x + width
			_zone_row.draw_colored_polygon(PackedVector2Array([Vector2(r, cy), Vector2(r - t, cy - t * 0.5), Vector2(r - t, cy + t * 0.5)]), color)
		_:
			var mx := x + width * clampf(_marker_fraction, 0.0, 1.0)
			var marker := Rect2(mx - SCALE_MARKER_SIZE.x * 0.5, cy - SCALE_MARKER_SIZE.y * 0.5, SCALE_MARKER_SIZE.x, SCALE_MARKER_SIZE.y)
			_zone_row.draw_rect(marker.grow(SCALE_MARKER_OUTLINE), UiTokens.HUD_INK)
			_zone_row.draw_rect(marker, color)


## Строка зоны под героем: полоса цвета зоны факта (скрыта без данных) или шкала допуска (T-175),
## справа значок отклонения и разница факт − цель (цифры `tnum`) цветом токена отклонения.
func _draw_zone_row() -> void:
	var h := _zone_row.size.y
	var bar_x := CHIP_SIZE.x + ICON_GAP
	var bar_end := _zone_row.size.x - DELTA_AREA_WIDTH
	if not _scale.is_empty():
		_draw_scale(bar_x, bar_end - bar_x, h)
	elif _power_zone_color.a > 0.0:
		_zone_row.draw_rect(Rect2(bar_x, (h - ZONE_BAR_HEIGHT) * 0.5, bar_end - bar_x, ZONE_BAR_HEIGHT), _power_zone_color)
	if _deviation == HudModel.DEVIATION_HIDDEN:
		return
	var color := deviation_color()
	var font := get_theme_font(&"font", DELTA_VARIATION)
	var font_size := get_theme_font_size(&"font_size", DELTA_VARIATION)
	var delta_w := font.get_string_size(_delta_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var right := _zone_row.size.x
	# Базовая линия — так, чтобы прописные цифры (≈ 0.727 em) стояли по центру строки.
	var baseline := (h + 0.727 * font_size) * 0.5
	_zone_row.draw_string(font, Vector2(right - delta_w, baseline), _delta_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
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
	_scale_track_box = _flat_box(SCALE_TRACK_COLOR, SCALE_TRACK_RADIUS)
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
