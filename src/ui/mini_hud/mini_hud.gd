class_name MiniHud
extends PanelContainer
## Mini-HUD (T-177 spike): a compact plate with the workout numbers only, shown in a small
## always-on-top window over other apps (`OverlayWindow`). Plain, functional look — the final design
## is game-designer's (no `hud.md` decision yet).
##
## Contents: power and target, HR, cadence, step countdown, next step; buttons pause / resume, skip
## step and "back to full". Values come from the same `HudModel.state()` the full HUD renders
## (`set_values`), there is no second source of truth.

signal pause_requested
signal skip_requested
signal exit_requested

## Plate size in lp of the mini window canvas (`OverlayWindow` sizes the window to it).
const SIZE_LP: Vector2i = Vector2i(460, 132)
const ICON_PAUSE: Texture2D = preload("res://assets/icons/lucide/pause.svg")
const ICON_PLAY: Texture2D = preload("res://assets/icons/lucide/play.svg")
const ICON_SKIP: Texture2D = preload("res://assets/icons/lucide/skip-forward.svg")
## Back to the full HUD — Lucide `maximize-2` (hud.md 18.2: no `chevron-up`).
const ICON_FULL: Texture2D = preload("res://assets/icons/lucide/maximize-2.svg")
const BUTTON_SIZE: Vector2 = Vector2(40, 40)
const NO_DATA: String = HudModel.NO_DATA_TEXT

var _power: Label
var _target: Label
var _hr: Label
var _cadence: Label
var _timer: Label
var _next: Label
var _pause_button: Button
var _skip_button: Button
var _exit_button: Button
var _paused: bool = false


func _init() -> void:
	name = "MiniHud"
	theme_type_variation = &"HudPlate"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


## Numbers of one tick: `state` — `HudModel.state()`, `next_text` — the next step line ("" — none).
func set_values(state: Dictionary, next_text: String) -> void:
	_power.text = "%s %s" % [str(state.get("power_text", NO_DATA)), tr("ui.workout.unit_w")]
	var target := str(state.get("target_text", NO_DATA))
	_target.text = tr("ui.workout.mini_hud.target").format({"value": target})
	_hr.text = "%s %s" % [str(state.get("hr_text", NO_DATA)), tr("ui.hud.unit.bpm")]
	_cadence.text = "%s %s" % [str(state.get("cadence_text", NO_DATA)), tr("ui.hud.unit.rpm")]
	_timer.text = str(state.get("countdown_text", NO_DATA))
	_next.text = tr("ui.workout.mini_hud.next").format({"line": next_text}) if not next_text.is_empty() else ""
	_paused = int(state.get("session_state", -1)) == WorkoutSession.State.PAUSED
	_pause_button.icon = ICON_PLAY if _paused else ICON_PAUSE
	_pause_button.tooltip_text = tr("ui.workout.resume") if _paused else tr("ui.workout.pause")


func power_text() -> String:
	return _power.text


func target_text() -> String:
	return _target.text


func hr_text() -> String:
	return _hr.text


func cadence_text() -> String:
	return _cadence.text


func timer_text() -> String:
	return _timer.text


func next_text() -> String:
	return _next.text


## Buttons by id: `pause`, `skip`, `exit`.
func button(id: StringName) -> Button:
	match id:
		&"pause": return _pause_button
		&"skip": return _skip_button
		&"exit": return _exit_button
	return null


func _build() -> void:
	var rows := VBoxContainer.new()
	rows.theme_type_variation = &"Stack8"
	add_child(rows)
	var top := HBoxContainer.new()
	top.theme_type_variation = &"Row16"
	rows.add_child(top)
	_power = _label("Power", &"HudValueLabel", top)
	_target = _label("Target", &"HudCaptionLabel", top)
	_hr = _label("Hr", &"HudCaptionLabel", top)
	_cadence = _label("Cadence", &"HudCaptionLabel", top)
	var bottom := HBoxContainer.new()
	bottom.theme_type_variation = &"Row8"
	rows.add_child(bottom)
	_timer = _label("Timer", &"HudValueLabel", bottom)
	_next = _label("Next", &"HudCaptionLabel", bottom)
	_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pause_button = _button("PauseButton", ICON_PAUSE, "ui.workout.pause", bottom)
	_skip_button = _button("SkipButton", ICON_SKIP, "ui.hud_controls.pause.skip", bottom)
	_exit_button = _button("ExitButton", ICON_FULL, "ui.workout.mini_hud.exit", bottom)
	_pause_button.pressed.connect(pause_requested.emit)
	_skip_button.pressed.connect(skip_requested.emit)
	_exit_button.pressed.connect(exit_requested.emit)


func _label(node_name: String, variation: StringName, parent: Control) -> Label:
	var l := Label.new()
	l.name = node_name
	l.theme_type_variation = variation
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.text = NO_DATA
	parent.add_child(l)
	return l


func _button(node_name: String, icon_texture: Texture2D, tooltip_key: String, parent: Control) -> Button:
	var b := Button.new()
	b.name = node_name
	b.theme_type_variation = &"HudToolButton"
	b.icon = icon_texture
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = true
	b.custom_minimum_size = BUTTON_SIZE
	b.tooltip_text = tooltip_key
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b
