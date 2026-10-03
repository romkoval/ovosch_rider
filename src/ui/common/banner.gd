class_name Banner
extends PanelContainer
## Баннер статуса (`docs/game/ui.md` п. 6, 9.2): предупреждение, ошибка или сведения.
##
## Фон, полоса слева и радиус — вариации темы `BannerWarn` / `BannerError` / `BannerInfo`
## (по `kind`), текст — Body (базовый `Label`, с переносом), справа действие — `GhostButton`
## (цель нажатия `touch_ui`). Иконка 20 lp (Lucide, имя файла без `.svg`) окрашивается цветом
## статуса через `self_modulate` (цвет статуса — данные, а не переопределение темы).
## Пример: `kind = WARN`, иконка `bluetooth-off`, «Bluetooth недоступен…», действие «Как включить».
##
## Текст и действие — ключи перевода (или готовый текст); обновляются при смене языка.

## Нажато действие баннера.
signal action_pressed()

enum Kind { INFO, WARN, ERROR }

const VARIATIONS: Dictionary = {
	Kind.INFO: &"BannerInfo",
	Kind.WARN: &"BannerWarn",
	Kind.ERROR: &"BannerError",
}
## Цвет статуса — тот же, что у полосы баннера в теме (`AppThemeBuilder._panel_variations`).
const STATUS_COLORS: Dictionary = {
	Kind.INFO: UiTokens.ACCENT,
	Kind.WARN: UiTokens.WARN,
	Kind.ERROR: UiTokens.DANGER_TEXT,
}
const ICON_DIR: String = "res://assets/icons/lucide/"

@export var kind: Kind = Kind.INFO:
	set(value):
		kind = value
		_apply()
## Текст: ключ перевода или готовый текст.
@export var text: String = "":
	set(value):
		text = value
		_apply()
## Подпись действия: ключ перевода или текст; пусто — кнопки нет.
@export var action: String = "":
	set(value):
		action = value
		_apply()
## Иконка Lucide (`bluetooth-off`, `refresh-cw`, …); пусто — без иконки.
@export var icon_name: String = "":
	set(value):
		icon_name = value
		_apply()

@onready var _icon: TextureRect = %Icon
@onready var _text: Label = %Text
@onready var _action: Button = %Action


func _ready() -> void:
	_action.pressed.connect(_on_action_pressed)
	TouchTarget.attach(_action, TouchTarget.Kind.UI)
	_apply()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_apply()


## Задать вид, текст, действие и иконку.
func show_banner(banner_kind: Kind, text_key: String, action_key: String = "", icon: String = "") -> void:
	kind = banner_kind
	text = text_key
	action = action_key
	icon_name = icon


func status_color() -> Color:
	return STATUS_COLORS[kind]


func text_label() -> Label:
	return _text


func action_button() -> Button:
	return _action


func icon_rect() -> TextureRect:
	return _icon


func _on_action_pressed() -> void:
	action_pressed.emit()


func _apply() -> void:
	theme_type_variation = VARIATIONS[kind]
	if _text == null:
		return
	_text.text = tr(text) if not text.is_empty() else ""
	_action.text = tr(action) if not action.is_empty() else ""
	_action.visible = not action.is_empty()
	_icon.visible = not icon_name.is_empty()
	_icon.texture = load(ICON_DIR + icon_name + ".svg") if not icon_name.is_empty() else null
	_icon.self_modulate = status_color()
