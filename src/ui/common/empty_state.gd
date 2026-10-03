class_name EmptyState
extends CenterContainer
## Пустое состояние (`docs/game/ui.md` п. 6, 8.5, 8.7; REQ-UIX-04 крит. 4, U7 чек-листа п. 11).
##
## По центру области: иконка Lucide 48 lp цветом `text_disabled`, заголовок (`H2Label`),
## пояснение одной фразой (`SecondaryLabel`, с переносом на узком экране) и основная кнопка
## с действием (`PrimaryButton`, цель нажатия `TouchTarget.Kind.BUTTON`). Пример — пустая
## история: `history`, «Заездов пока нет», «Первая тренировка появится здесь», «На главный».
##
## Тексты — ключи перевода (или готовый текст); обновляются при смене языка.

## Нажата кнопка действия.
signal action_pressed()

const ICON_DIR: String = "res://assets/icons/lucide/"

## Иконка Lucide (имя файла без `.svg`); пусто — без иконки.
@export var icon_name: String = "":
	set(value):
		icon_name = value
		_apply()
@export var title: String = "":
	set(value):
		title = value
		_apply()
@export var text: String = "":
	set(value):
		text = value
		_apply()
## Подпись кнопки; пусто — кнопки нет.
@export var action: String = "":
	set(value):
		action = value
		_apply()

@onready var _icon: TextureRect = %Icon
@onready var _title: Label = %Title
@onready var _text: Label = %Text
@onready var _action: Button = %Action


func _ready() -> void:
	_icon.self_modulate = UiTokens.TEXT_DISABLED
	_action.pressed.connect(_on_action_pressed)
	TouchTarget.attach(_action, TouchTarget.Kind.BUTTON)
	_apply()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_apply()


## Задать иконку, заголовок, пояснение и действие.
func setup(icon: String, title_key: String, text_key: String = "", action_key: String = "") -> void:
	icon_name = icon
	title = title_key
	text = text_key
	action = action_key


func title_label() -> Label:
	return _title


func text_label() -> Label:
	return _text


func action_button() -> Button:
	return _action


func icon_rect() -> TextureRect:
	return _icon


func _on_action_pressed() -> void:
	action_pressed.emit()


func _apply() -> void:
	if _title == null:
		return
	_icon.visible = not icon_name.is_empty()
	_icon.texture = load(ICON_DIR + icon_name + ".svg") if not icon_name.is_empty() else null
	_title.text = tr(title) if not title.is_empty() else ""
	_title.visible = not title.is_empty()
	_text.text = tr(text) if not text.is_empty() else ""
	_text.visible = not text.is_empty()
	_action.text = tr(action) if not action.is_empty() else ""
	_action.visible = not action.is_empty()
