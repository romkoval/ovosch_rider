class_name IntervalsKeyDialog
extends ConfirmationDialog
## Mini-form for the Intervals.icu API key (REQ-INT-01 crit. 1-3, REQ-PRF-03): Athlete ID + key.
## Shared by the settings screen and the plan screen (T-040). The dialog only collects
## input and emits `submitted`; the owner verifies the key and calls `show_error()` or `hide()`.
## OK does not close the dialog (`dialog_hide_on_ok = false`): the verification request is
## asynchronous, and a rejected key must stay visible to the user (REQ-INT-01 crit. 3).

signal submitted(athlete_id: String, key: String)

@onready var _athlete_edit: LineEdit = %AthleteIdEdit
@onready var _key_edit: LineEdit = %KeyEdit
@onready var _error_label: Label = %ErrorLabel
@onready var _hint_label: Label = $VBox/Hint


func _ready() -> void:
	dialog_hide_on_ok = false
	confirmed.connect(submit)


## Open with the current Athlete ID prefilled; the key field is always empty.
func open(current_athlete_id: String = "") -> void:
	_athlete_edit.text = current_athlete_id
	_key_edit.text = ""
	_error_label.visible = false
	_error_label.text = ""
	_fit_wrapped_text()
	popup_centered()


## Перенос подсказки — по ширине содержимого до показа (T-144, REQ-UIX-05 п.2). Пока окно
## скрыто, контейнер содержимого детей не раскладывает: у переносимой по словам подписи, ни разу
## не показанной, ширина 1 px, и её минимальная высота — текст по букве в строке (~2000 lp).
## Окно с `wrap_controls` дорастает до этого минимума и остаётся таким к `popup_centered()`:
## при первом открытии форма уходила за низ окна. Подписи получают ширину содержимого диалога
## (ширина окна минус поля панели `panel`), минимум пересчитывается, окно сжимается до него.
func _fit_wrapped_text() -> void:
	var panel := get_theme_stylebox(&"panel")
	var width := float(maxi(size.x, min_size.x)) - (panel.get_minimum_size().x if panel != null else 0.0)
	for label: Label in [_hint_label, _error_label]:
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF or width <= 0.0:
			continue
		label.size = Vector2(width, label.size.y)
		label.update_minimum_size()
	reset_size()


func fill(athlete_id: String, key: String) -> void:
	_athlete_edit.text = athlete_id
	_key_edit.text = key


func athlete_id() -> String:
	return _athlete_edit.text.strip_edges()


func key() -> String:
	return _key_edit.text.strip_edges()


## Emit the entered values; the previous error is cleared so a new attempt starts clean.
func submit() -> void:
	show_error("")
	submitted.emit(athlete_id(), key())


func show_error(text: String) -> void:
	_error_label.text = text
	_error_label.visible = not text.is_empty()


func error_text() -> String:
	return _error_label.text if _error_label.visible else ""
