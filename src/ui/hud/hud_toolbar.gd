class_name HudToolbar
extends PanelContainer
## Скрываемая панель инструментов заезда (`docs/game/hud.md` п. 10.3; REQ-WRK-03 крит. 1 —
## ERG одним действием, REQ-WRK-05 — пауза и завершение, REQ-FRD-05 крит. 4 — SIM ↔
## сопротивление одним действием, крит. 6 — органы управления крутизной и режимом).
##
## Самостоятельный компонент: не знает о сессии и экране, только отдаёт сигналы-запросы;
## состояние (ERG, SIM, проценты) ему сообщает экран методами `set_*`. Подключают T-078
## (режим «план») и T-084 (режим «свободная езда»).
##
## Поведение:
## - появляется по касанию, движению мыши, нажатию кнопки мыши или любой клавише и
##   прячется через 4 с без ввода (прозрачность за 200 мс); пока на экране, каждый ввод
##   продлевает показ;
## - режим «план»: ERG вкл/выкл; интенсивность −5 % / +5 % со значением между кнопками;
##   сопротивление −5 / +5 (только при ERG выкл); «Пропустить шаг»; «Завершить»;
## - режим «свободная езда»: SIM ↔ сопротивление; крутизна SIM −10 / +10 % или
##   сопротивление −5 / +5 (по режиму); «Завершить»;
## - колонка (компьютер, планшет): ряд на кнопку, регулятор — ряд [−] [подпись/значение] [+];
## - компактная раскладка (телефон, `set_compact(true)`; колонка не помещается в слот):
##   сетка в три колонки — ряд кнопок-действий (ERG или SIM ↔ сопротивление, «Пропустить шаг»,
##   «Завершить») и под ним регулятор [−] [подпись/значение] [+]; два ряда, без прокрутки.
##   Регулятор один: в плане при ERG выкл «интенсивность» уступает место «сопротивлению»;
## - горячие клавиши (`hud.md` п. 10.2–10.3): Esc — пауза; E — ERG (план) или SIM ↔
##   сопротивление (свободная езда); `+`/`−` — интенсивность (план), крутизна или
##   сопротивление (свободная езда); N — пропустить шаг (план). Буквы — по физической
##   клавише, поэтому работают и в русской раскладке;
## - без управления станком (`set_controls_trainer(false)`, режим сессии `power_meter`,
##   REQ-WRK-09 п.5 (д), п.7): кнопок ERG, сопротивления, SIM ↔ сопротивление и крутизны нет
##   (скрыты, а не недоступны); E ничего не делает. План — интенсивность, «Пропустить шаг»,
##   «Завершить» (телефон: ряд «Пропустить шаг» · «Завершить», под ним интенсивность), `+`/`−` —
##   интенсивность; свободная езда — только «Завершить», `+`/`−` ничего не делают;
## - `set_paused(true)` (экран на паузе): панель убрана, ввод её не показывает, горячие
##   клавиши молчат — паузой управляет `PauseOverlay`.
##
## Кнопки — вариация `HudToolButton` (иконка Lucide 24 и подпись 11 lp снизу внутри стороны
## 56), сторона `max(56, touch_hud)` lp HUD; `touch_hud` — из автозагрузки `UiScaleRuntime`.
## Кнопки не берут фокус: Пробел и Enter не должны повторно нажимать последнюю нажатую кнопку.

## Esc. Компонент называет его паузой (`hud.md` п. 10.2), экраны заезда трактуют Esc как
## системное «назад» — подтверждение досрочного завершения (REQ-UIX-04 крит. 2).
signal pause_requested
## E или кнопка ERG (план): переключить ERG.
signal erg_toggle_requested
## `+`/`−` или кнопки интенсивности (план): изменить множитель на ±5 процентных пунктов.
signal intensity_step_requested(delta_pct: int)
## Кнопки сопротивления (план при ERG выкл; свободная езда в фиксированном режиме), а в
## свободной езде в фиксированном режиме и `+`/`−`: уровень ±5 %.
signal resistance_step_requested(delta_pct: int)
## N или кнопка «Пропустить шаг» (план).
signal skip_requested
## Кнопка «Завершить»: экран показывает подтверждение (`PauseOverlay`).
signal finish_requested
## E или кнопка режима (свободная езда): SIM ↔ фиксированное сопротивление.
signal sim_toggle_requested
## `+`/`−` или кнопки крутизны (свободная езда в SIM): крутизна ±10 %.
signal steepness_step_requested(delta_pct: int)
## The panel appeared or started hiding (п. 10.3): elements shown together with it follow.
signal shown_changed(shown: bool)

enum Mode { PLAN, FREE_RIDE }

## Действия горячих клавиш (`key_action`).
const ACTION_NONE: StringName = &""
const ACTION_PAUSE: StringName = &"pause"
const ACTION_TOGGLE: StringName = &"toggle"
const ACTION_PLUS: StringName = &"plus"
const ACTION_MINUS: StringName = &"minus"
const ACTION_SKIP: StringName = &"skip"

## Панель прячется через столько секунд без ввода (`hud.md` п. 10.3).
const HIDE_AFTER_SEC: float = 4.0
const FADE_SEC: float = 0.2
## Минимальная сторона кнопки панели, lp HUD (`hud.md` п. 10.3: `max(56, touch_hud)·s`).
const MIN_BUTTON_LP: float = 56.0
const INTENSITY_STEP_PCT: int = 5
const RESISTANCE_STEP_PCT: int = 5
const STEEPNESS_STEP_PCT: int = 10
const ICON_ERG: Texture2D = preload("res://assets/icons/lucide/zap.svg")
const ICON_SIM: Texture2D = preload("res://assets/icons/lucide/sliders-horizontal.svg")
const ICON_DOWN: Texture2D = preload("res://assets/icons/lucide/chevron-down.svg")
const ICON_UP: Texture2D = preload("res://assets/icons/lucide/chevron-up.svg")
const ICON_SKIP: Texture2D = preload("res://assets/icons/lucide/skip-forward.svg")
const ICON_FINISH: Texture2D = preload("res://assets/icons/lucide/square.svg")
## Префикс ключей перевода компонента (`assets/i18n/strings_hud_controls.csv`).
const KEY: String = "ui.hud_controls."
## Колонок в компактной раскладке (сетка в три колонки: ряд действий и ряд регулятора).
const COMPACT_COLUMNS: int = 3

var hotkeys_enabled: bool = true

var _mode: Mode = Mode.PLAN
var _compact: bool = false
var _erg_enabled: bool = true
var _erg_available: bool = true
var _sim_enabled: bool = true
## Сессия управляет станком (`smart`); false — `power_meter`: органов управления станком нет.
var _controls_trainer: bool = true
var _intensity_pct: int = 100
var _resistance_pct: int = 0
var _steepness_pct: int = 50
var _paused: bool = false
var _shown: bool = false
var _idle_sec: float = 0.0
var _touch: float = UiScale.TOUCH_HUD_DESKTOP
var _tween: Tween

var _erg_button: Button
var _sim_button: Button
var _intensity_down: Button
var _intensity_up: Button
var _resistance_down: Button
var _resistance_up: Button
var _steepness_down: Button
var _steepness_up: Button
var _skip_button: Button
var _finish_button: Button
var _intensity_caption: Label
var _intensity_value: Label
var _resistance_caption: Label
var _resistance_value: Label
var _steepness_caption: Label
var _steepness_value: Label

@onready var _rows: VBoxContainer = %Rows


func _ready() -> void:
	set_process(false)
	_build()
	var ui := get_node_or_null(^"/root/UiScaleRuntime") as UiScale
	if ui != null:
		_touch = ui.touch_hud()
		_compact = ui.device == UiScale.Device.PHONE
	_apply_touch()
	_relayout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_texts()
	elif what == NOTIFICATION_PREDELETE:
		# Кнопки и подписи, снятые с панели текущей раскладкой, не в дереве — освобождаем сами.
		if _erg_button == null:
			return
		for c: Control in _all_buttons():
			if c.get_parent() == null:
				c.free()
		for c: Control in _all_labels():
			if c.get_parent() == null:
				c.free()


func _process(delta: float) -> void:
	tick(delta)


# ---------------------------------------------------------------------------
# Состояние, которое сообщает экран
# ---------------------------------------------------------------------------

## Режим экрана: план или свободная езда.
func set_mode(mode: Mode) -> void:
	if _mode == mode:
		return
	_mode = mode
	_relayout()


func get_mode() -> Mode:
	return _mode


## Компактная раскладка (телефон): по две кнопки в ряд.
func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	_relayout()


func is_compact() -> bool:
	return _compact


## Сторона цели нажатия `touch_hud`, lp HUD (кнопки — не меньше 56).
func set_touch_target(lp: float) -> void:
	_touch = lp
	_apply_touch()


## ERG включён (план): подпись кнопки и видимость кнопок сопротивления.
func set_erg_enabled(enabled: bool) -> void:
	if _erg_enabled == enabled:
		return
	_erg_enabled = enabled
	_relayout()


func is_erg_enabled() -> bool:
	return _erg_enabled


## ERG available on the trainer (DEV-10 p.5, WRK-03 p.6 (b), hud.md p. 17.1): no — the ERG button
## is hidden (not disabled) until the end of the connection, E does nothing; the column keeps
## intensity, resistance, «Skip step», «Finish» (phone: row 1 — skip · finish, row 2 — resistance).
func set_erg_available(available: bool) -> void:
	if _erg_available == available:
		return
	_erg_available = available
	if _erg_button != null:
		_erg_button.visible = available
		_erg_button.disabled = not available  # also inert if someone reaches it by focus
	_relayout()


func is_erg_available() -> bool:
	return _erg_available


## SIM включён (свободная езда): крутизна или сопротивление.
func set_sim_enabled(enabled: bool) -> void:
	if _sim_enabled == enabled:
		return
	_sim_enabled = enabled
	_relayout()


func is_sim_enabled() -> bool:
	return _sim_enabled


## Сессия управляет станком (`smart`). false (`power_meter`, REQ-WRK-09 п.5 (д)): кнопки ERG,
## сопротивления, SIM и крутизны скрыты, клавиша E (и `+`/`−` свободной езды) — без действия.
func set_controls_trainer(controls: bool) -> void:
	if _controls_trainer == controls:
		return
	_controls_trainer = controls
	_relayout()


func controls_trainer() -> bool:
	return _controls_trainer


func set_intensity_pct(pct: int) -> void:
	_intensity_pct = pct
	_refresh_texts()


func set_resistance_pct(pct: int) -> void:
	_resistance_pct = pct
	_refresh_texts()


func set_steepness_pct(pct: int) -> void:
	_steepness_pct = pct
	_refresh_texts()


## Пауза экрана: панель убрана, ввод её не показывает, горячие клавиши молчат.
func set_paused(paused: bool) -> void:
	_paused = paused
	if paused:
		_set_shown(false)


func is_paused() -> bool:
	return _paused


# ---------------------------------------------------------------------------
# Показ и скрытие
# ---------------------------------------------------------------------------

## Ввод пользователя: показать панель и начать отсчёт 4 с заново.
func poke() -> void:
	if _paused:
		return
	_idle_sec = 0.0
	_set_shown(true)


## Продвинуть таймер скрытия на `delta` секунд (вызывается из `_process`).
func tick(delta: float) -> void:
	if not _shown:
		return
	_idle_sec += delta
	if _idle_sec >= HIDE_AFTER_SEC:
		_set_shown(false)


## Панель на экране (или появляется).
func is_shown() -> bool:
	return _shown


## Секунды без ввода с последнего показа.
func idle_sec() -> float:
	return _idle_sec


# ---------------------------------------------------------------------------
# Состав (для экранов и проверок)
# ---------------------------------------------------------------------------

## Кнопки, которые сейчас есть на панели (в порядке раскладки).
func visible_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for b in _all_buttons():
		if b.is_inside_tree() and is_ancestor_of(b) and b.visible:
			out.append(b)
	out.sort_custom(_tree_order)
	return out


## Кнопки панели по имени: `erg`, `sim`, `intensity_down`, `intensity_up`, `resistance_down`,
## `resistance_up`, `steepness_down`, `steepness_up`, `skip`, `finish`.
func button(id: StringName) -> Button:
	match id:
		&"erg": return _erg_button
		&"sim": return _sim_button
		&"intensity_down": return _intensity_down
		&"intensity_up": return _intensity_up
		&"resistance_down": return _resistance_down
		&"resistance_up": return _resistance_up
		&"steepness_down": return _steepness_down
		&"steepness_up": return _steepness_up
		&"skip": return _skip_button
		&"finish": return _finish_button
	return null


## Строки значений регуляторов: `intensity`, `resistance`, `steepness`.
func value_text(id: StringName) -> String:
	match id:
		&"intensity": return _intensity_value.text
		&"resistance": return _resistance_value.text
		&"steepness": return _steepness_value.text
	return ""


## Число рядов кнопок в текущей раскладке.
func button_row_count() -> int:
	var n := 0
	for row in _rows.get_children():
		for child in row.get_children():
			if child is Button:
				n += 1
				break
	return n


## Наибольшее число кнопок в одном ряду.
func max_buttons_per_row() -> int:
	var best := 0
	for row in _rows.get_children():
		var n := 0
		for child in row.get_children():
			if child is Button:
				n += 1
		best = maxi(best, n)
	return best


# ---------------------------------------------------------------------------
# Горячие клавиши
# ---------------------------------------------------------------------------

## Действие клавиши: Esc — пауза, E — переключатель режима, `+`/`=`/Num+ — плюс,
## `−`/Num− — минус, N — пропуск; буквы — по физической клавише.
static func key_action(key: InputEventKey) -> StringName:
	var codes: Array[Key] = [key.keycode, key.physical_keycode]
	if KEY_ESCAPE in codes:
		return ACTION_PAUSE
	if key.physical_keycode == KEY_E or (key.physical_keycode == KEY_NONE and key.keycode == KEY_E):
		return ACTION_TOGGLE
	if key.physical_keycode == KEY_N or (key.physical_keycode == KEY_NONE and key.keycode == KEY_N):
		return ACTION_SKIP
	if KEY_PLUS in codes or KEY_KP_ADD in codes or KEY_EQUAL in codes or key.unicode == 0x2B:
		return ACTION_PLUS
	if KEY_MINUS in codes or KEY_KP_SUBTRACT in codes or key.unicode == 0x2D or key.unicode == 0x2212:
		return ACTION_MINUS
	return ACTION_NONE


## Выполнить действие горячей клавиши в текущем режиме. `true` — сигнал отдан.
func trigger(action: StringName) -> bool:
	match action:
		ACTION_PAUSE:
			pause_requested.emit()
		ACTION_TOGGLE:
			if not _controls_trainer:
				return false
			if _mode == Mode.PLAN:
				if not _erg_available:
					return false
				erg_toggle_requested.emit()
			else:
				sim_toggle_requested.emit()
		ACTION_PLUS, ACTION_MINUS:
			var sign := 1 if action == ACTION_PLUS else -1
			if _mode != Mode.PLAN and not _controls_trainer:
				return false
			if _mode == Mode.PLAN and _controls_trainer and not (_erg_available and _erg_enabled):
				# WRK-03 p.7: `+`/`−` change the resistance level whenever the ERG toggle is off
				# (by the player) or ERG is unavailable (p.6 (b)); intensity only with the toggle on.
				resistance_step_requested.emit(sign * RESISTANCE_STEP_PCT)
			elif _mode == Mode.PLAN:
				intensity_step_requested.emit(sign * INTENSITY_STEP_PCT)
			elif _sim_enabled:
				steepness_step_requested.emit(sign * STEEPNESS_STEP_PCT)
			else:
				resistance_step_requested.emit(sign * RESISTANCE_STEP_PCT)
		ACTION_SKIP:
			if _mode != Mode.PLAN:
				return false
			skip_requested.emit()
		_:
			return false
	return true


func _input(event: InputEvent) -> void:
	if _is_activity(event):
		poke()


func _unhandled_key_input(event: InputEvent) -> void:
	if not hotkeys_enabled or _paused:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if trigger(key_action(key)):
		get_viewport().set_input_as_handled()


static func _is_activity(event: InputEvent) -> bool:
	if event is InputEventMouseMotion or event is InputEventScreenDrag:
		return true
	if event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey or event is InputEventJoypadButton:
		return event.is_pressed()
	return false


# ---------------------------------------------------------------------------
# Сборка и раскладка
# ---------------------------------------------------------------------------

func _build() -> void:
	_erg_button = _make_button("ErgButton", ICON_ERG)
	_sim_button = _make_button("SimButton", ICON_SIM)
	_intensity_down = _make_button("IntensityDown", ICON_DOWN)
	_intensity_up = _make_button("IntensityUp", ICON_UP)
	_resistance_down = _make_button("ResistanceDown", ICON_DOWN)
	_resistance_up = _make_button("ResistanceUp", ICON_UP)
	_steepness_down = _make_button("SteepnessDown", ICON_DOWN)
	_steepness_up = _make_button("SteepnessUp", ICON_UP)
	_skip_button = _make_button("SkipButton", ICON_SKIP)
	_finish_button = _make_button("FinishButton", ICON_FINISH)
	_erg_button.pressed.connect(_on_erg_pressed)
	_sim_button.pressed.connect(_on_sim_pressed)
	_intensity_down.pressed.connect(_on_intensity_down)
	_intensity_up.pressed.connect(_on_intensity_up)
	_resistance_down.pressed.connect(_on_resistance_down)
	_resistance_up.pressed.connect(_on_resistance_up)
	_steepness_down.pressed.connect(_on_steepness_down)
	_steepness_up.pressed.connect(_on_steepness_up)
	_skip_button.pressed.connect(_on_skip_pressed)
	_finish_button.pressed.connect(_on_finish_pressed)
	_intensity_caption = _make_label("IntensityCaption", &"HudCaptionLabel")
	_intensity_value = _make_label("IntensityValue", &"HudStripLabel")
	_resistance_caption = _make_label("ResistanceCaption", &"HudCaptionLabel")
	_resistance_value = _make_label("ResistanceValue", &"HudStripLabel")
	_steepness_caption = _make_label("SteepnessCaption", &"HudCaptionLabel")
	_steepness_value = _make_label("SteepnessValue", &"HudStripLabel")


func _make_button(node_name: String, icon: Texture2D) -> Button:
	var b := Button.new()
	b.name = node_name
	b.theme_type_variation = &"HudToolButton"
	b.icon = icon
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return b


func _make_label(node_name: String, variation: StringName) -> Label:
	var l := Label.new()
	l.name = node_name
	l.theme_type_variation = variation
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _all_buttons() -> Array[Button]:
	return [_erg_button, _sim_button, _intensity_down, _intensity_up, _resistance_down, _resistance_up,
		_steepness_down, _steepness_up, _skip_button, _finish_button]


func _all_labels() -> Array[Label]:
	return [_intensity_caption, _intensity_value, _resistance_caption, _resistance_value,
		_steepness_caption, _steepness_value]


func _apply_touch() -> void:
	if _erg_button == null:
		return
	var side := maxf(MIN_BUTTON_LP, _touch)
	for b in _all_buttons():
		b.custom_minimum_size = Vector2(side, side)


## Пересобрать ряды под режим, раскладку и состояние ERG/SIM.
func _relayout() -> void:
	if not is_node_ready():
		return
	for c: Control in _all_buttons():
		_detach(c)
	for c: Control in _all_labels():
		_detach(c)
	# Ряды пусты (кнопки и подписи сняты выше) — освобождаем сразу, чтобы не копить узлы.
	for row in _rows.get_children():
		_rows.remove_child(row)
		row.free()
	var stepper := _active_stepper()
	if not _controls_trainer:
		if _mode == Mode.PLAN:
			if _compact:
				_add_row([_skip_button, _finish_button])
				_add_stepper(&"intensity")
			else:
				_add_stepper(&"intensity")
				_add_row([_skip_button])
				_add_row([_finish_button])
		else:
			_add_row([_finish_button])
	elif _mode == Mode.PLAN and not _erg_available:
		if _compact:
			_add_row([_skip_button, _finish_button])
			_add_stepper(&"resistance")
		else:
			_add_stepper(&"intensity")
			_add_stepper(&"resistance")
			_add_row([_skip_button])
			_add_row([_finish_button])
	elif _mode == Mode.PLAN:
		if _compact:
			_add_row([_erg_button, _skip_button, _finish_button])
			_add_stepper(stepper)
		else:
			_add_row([_erg_button])
			_add_stepper(&"intensity")
			if not _erg_enabled:
				_add_stepper(&"resistance")
			_add_row([_skip_button])
			_add_row([_finish_button])
	else:
		if _compact:
			_add_row([_sim_button, _finish_button])
			_add_stepper(stepper)
		else:
			_add_row([_sim_button])
			_add_stepper(stepper)
			_add_row([_finish_button])
	_refresh_texts()


## Регулятор режима: план — интенсивность (на телефоне при ERG выкл — сопротивление),
## свободная езда — крутизна в SIM или сопротивление.
func _active_stepper() -> StringName:
	if _mode == Mode.PLAN:
		return &"resistance" if _compact and not _erg_enabled and _controls_trainer else &"intensity"
	return &"steepness" if _sim_enabled else &"resistance"


func _add_row(controls: Array) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_child(row)
	# Кнопки ряда делят его ширину поровну: одиночные кнопки — во всю ширину колонки.
	for c: Control in controls:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(c)


## Регулятор — ряд [−] [подпись/значение] [+] (и в колонке, и в сетке).
func _add_stepper(id: StringName) -> void:
	var parts := _stepper_parts(id)
	var down: Button = parts[0]
	var up: Button = parts[1]
	var caption: Label = parts[2]
	var value: Label = parts[3]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_child(row)
	down.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	up.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var middle := VBoxContainer.new()
	middle.alignment = BoxContainer.ALIGNMENT_CENTER
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(caption)
	middle.add_child(value)
	row.add_child(down)
	row.add_child(middle)
	row.add_child(up)


func _stepper_parts(id: StringName) -> Array:
	match id:
		&"resistance":
			return [_resistance_down, _resistance_up, _resistance_caption, _resistance_value]
		&"steepness":
			return [_steepness_down, _steepness_up, _steepness_caption, _steepness_value]
	return [_intensity_down, _intensity_up, _intensity_caption, _intensity_value]


func _detach(c: Control) -> void:
	var parent := c.get_parent()
	if parent != null:
		parent.remove_child(c)


func _refresh_texts() -> void:
	if _erg_button == null:
		return
	_erg_button.text = tr(KEY + "toolbar.erg_on" if _erg_enabled else KEY + "toolbar.erg_off")
	_sim_button.text = tr(KEY + "toolbar.sim" if _sim_enabled else KEY + "toolbar.fixed")
	_intensity_down.text = tr(KEY + "toolbar.minus_pct").format({"value": INTENSITY_STEP_PCT})
	_intensity_up.text = tr(KEY + "toolbar.plus_pct").format({"value": INTENSITY_STEP_PCT})
	_steepness_down.text = tr(KEY + "toolbar.minus_pct").format({"value": STEEPNESS_STEP_PCT})
	_steepness_up.text = tr(KEY + "toolbar.plus_pct").format({"value": STEEPNESS_STEP_PCT})
	_resistance_down.text = tr(KEY + "toolbar.minus").format({"value": RESISTANCE_STEP_PCT})
	_resistance_up.text = tr(KEY + "toolbar.plus").format({"value": RESISTANCE_STEP_PCT})
	_skip_button.text = tr(KEY + "toolbar.skip")
	_finish_button.text = tr(KEY + "toolbar.finish")
	_intensity_caption.text = tr(KEY + "toolbar.intensity")
	_resistance_caption.text = tr(KEY + "toolbar.resistance")
	_steepness_caption.text = tr(KEY + "toolbar.steepness")
	var percent := tr(KEY + "toolbar.percent")
	_intensity_value.text = percent.format({"value": _intensity_pct})
	_resistance_value.text = percent.format({"value": _resistance_pct})
	_steepness_value.text = percent.format({"value": _steepness_pct})


func _set_shown(on: bool) -> void:
	if _shown == on:
		return
	_shown = on
	shown_changed.emit(on)
	# Таймер скрытия нужен только пока панель на экране.
	set_process(on)
	if _tween != null:
		_tween.kill()
	if on:
		visible = true
	if not is_inside_tree():
		modulate.a = 1.0 if on else 0.0
		visible = on
		return
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0 if on else 0.0, FADE_SEC)
	if not on:
		_tween.tween_callback(_after_hide)


func _after_hide() -> void:
	if not _shown:
		visible = false


static func _tree_order(a: Node, b: Node) -> bool:
	return b.is_greater_than(a)


# ---------------------------------------------------------------------------
# Нажатия
# ---------------------------------------------------------------------------

func _on_erg_pressed() -> void:
	if _erg_available:
		erg_toggle_requested.emit()


func _on_sim_pressed() -> void:
	sim_toggle_requested.emit()


func _on_intensity_down() -> void:
	intensity_step_requested.emit(-INTENSITY_STEP_PCT)


func _on_intensity_up() -> void:
	intensity_step_requested.emit(INTENSITY_STEP_PCT)


func _on_resistance_down() -> void:
	resistance_step_requested.emit(-RESISTANCE_STEP_PCT)


func _on_resistance_up() -> void:
	resistance_step_requested.emit(RESISTANCE_STEP_PCT)


func _on_steepness_down() -> void:
	steepness_step_requested.emit(-STEEPNESS_STEP_PCT)


func _on_steepness_up() -> void:
	steepness_step_requested.emit(STEEPNESS_STEP_PCT)


func _on_skip_pressed() -> void:
	skip_requested.emit()


func _on_finish_pressed() -> void:
	finish_requested.emit()
