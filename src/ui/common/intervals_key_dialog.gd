class_name IntervalsKeyDialog
extends ConfirmationDialog
## Mini-form for the Intervals.icu API key (REQ-INT-01 crit. 1-3, REQ-PRF-03): Athlete ID + key.
## Shared by the settings screen and the plan screen (T-040). The dialog only collects
## input and emits `submitted`; the owner verifies the key and calls `show_error()` or `hide()`.

signal submitted(athlete_id: String, key: String)

@onready var _athlete_edit: LineEdit = %AthleteIdEdit
@onready var _key_edit: LineEdit = %KeyEdit
@onready var _error_label: Label = %ErrorLabel


func _ready() -> void:
	confirmed.connect(submit)


## Open with the current Athlete ID prefilled; the key field is always empty.
func open(current_athlete_id: String = "") -> void:
	_athlete_edit.text = current_athlete_id
	_key_edit.text = ""
	_error_label.visible = false
	_error_label.text = ""
	popup_centered()


func fill(athlete_id: String, key: String) -> void:
	_athlete_edit.text = athlete_id
	_key_edit.text = key


func athlete_id() -> String:
	return _athlete_edit.text.strip_edges()


func key() -> String:
	return _key_edit.text.strip_edges()


func submit() -> void:
	submitted.emit(athlete_id(), key())


func show_error(text: String) -> void:
	_error_label.text = text
	_error_label.visible = not text.is_empty()


func error_text() -> String:
	return _error_label.text if _error_label.visible else ""
