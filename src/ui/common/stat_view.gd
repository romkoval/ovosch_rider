class_name StatView
extends VBoxContainer
## Стат — значение с единицей и подписью (`docs/game/ui.md` п. 5, 6; U4 чек-листа п. 11).
##
## Значение — вариация `StatLabel` (Inter `tnum`, 22 lp; `large = true` — `StatLargeLabel`, 32 lp,
## плитки итогов), единица рядом мельче и цветом `text2` (`SecondaryLabel`), подпись под ним
## (`CaptionLabel`). Без переопределений цвета и шрифта — только вариации темы.
##
## Значение — готовая строка данных (вызывающий форматирует: «38:00», «20.0»), не переводится.
## Единица и подпись — ключи перевода (`ui.menu.unit.w`, …) или готовый текст: строка без
## перевода возвращается `tr()` как есть. При смене языка тексты обновляются сами.

## Плитка итогов (`StatLargeLabel`) вместо обычного стата.
@export var large: bool = false:
	set(value):
		large = value
		_apply()
@export var value: String = "":
	set(v):
		value = v
		_apply()
## Единица: ключ перевода или текст; пусто — скрыта.
@export var unit: String = "":
	set(v):
		unit = v
		_apply()
## Подпись под значением: ключ перевода или текст; пусто — скрыта.
@export var caption: String = "":
	set(v):
		caption = v
		_apply()

@onready var _value: Label = %Value
@onready var _unit: Label = %Unit
@onready var _caption: Label = %Caption


func _ready() -> void:
	_apply()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_apply()


## Задать всё сразу.
func set_stat(value_text: String, unit_text: String = "", caption_text: String = "") -> void:
	value = value_text
	unit = unit_text
	caption = caption_text


func value_label() -> Label:
	return _value


func unit_label() -> Label:
	return _unit


func caption_label() -> Label:
	return _caption


func _apply() -> void:
	if _value == null:
		return
	_value.theme_type_variation = &"StatLargeLabel" if large else &"StatLabel"
	_value.text = value
	_unit.text = tr(unit) if not unit.is_empty() else ""
	_unit.visible = not unit.is_empty()
	_caption.text = tr(caption) if not caption.is_empty() else ""
	_caption.visible = not caption.is_empty()
