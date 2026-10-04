class_name ListRow
extends Button
## Строка списка (`docs/game/ui.md` п. 6, 8.5, 8.7, 9.2; REQ-UIX-04 крит. 3 — вариация строки).
##
## Сама строка — `Button` с вариацией темы `ListRowButton` (фокус, Enter и клавиатура работают
## сразу), содержимое — дочерняя раскладка с `mouse_filter = PASS` (нажатие уходит строке):
##
##   [ведущий слот] [надпись над заголовком / заголовок / подзаголовок] [колонки] [хвост] [›]
##   [нижний слот на всю ширину — полоса зон в истории]
##
## - ведущий слот: иконка Lucide (`set_icon("bike")`) или свой узел (`leading_slot()`);
## - тексты: `overline` (`CaptionNumLabel`, дата), `title` (`TitleLabel`), `subtitle`
##   (`SecondaryLabel`); заголовок — пользовательские данные (название тренировки, заезда,
##   устройства), длинный сокращается «…»; подзаголовок (цифры, тип) не сокращается, а
##   переносится на следующую строку (UIX-05 крит. 3);
## - колонки значений фиксированной ширины, выравнивание вправо (`set_columns`);
## - хвост (`trailing_slot()`): значок Strava, метка режима, кнопка «Подключить»; свои
##   интерактивные узлы в слотах сохраняют свой `mouse_filter`;
## - шеврон `chevron-right` цветом `text_disabled` (`show_chevron`).
##
## Высота 64 lp (одна строка текста) или 76 lp (две и больше), но не меньше содержимого и
## цели нажатия `touch_ui` (`TouchTarget`). Выбор (`selectable`) — `toggle_mode`, стиль
## «нажата» темы (`surface3`); единственность выбора — `ButtonGroup` экрана. Разделитель 1 lp
## `line` снизу — `divider` (у последней строки списка выключен).
##
## Текстовые поля — готовые строки (данные). Колонки — тоже: числа форматирует экран.

## Строка выбрана нажатием (`pressed` у `Button` тоже есть; этот сигнал несёт `row_id`).
signal activated(row_id: String)

const HEIGHT: float = 64.0
const HEIGHT_TWO_LINES: float = 76.0
const ICON_DIR: String = "res://assets/icons/lucide/"
const CHEVRON_ICON: Texture2D = preload("res://assets/icons/lucide/chevron-right.svg")
const DIVIDER_WIDTH: float = 1.0
## Вариация подписей колонок по умолчанию.
## TODO: нужна вариация темы с `tnum` размера Body (п. 5: «все цифры в строках — с tnum»),
## сейчас в теме такой нет (`StatLabel` — 22 lp); см. отчёт T-076.
const COLUMN_VARIATION: StringName = &"BodyStrongLabel"

## Идентификатор строки для `activated` (id заезда, адрес устройства…).
@export var row_id: String = ""
@export var title: String = "":
	set(value):
		title = value
		_apply_texts()
@export var subtitle: String = "":
	set(value):
		subtitle = value
		_apply_texts()
@export var overline: String = "":
	set(value):
		overline = value
		_apply_texts()
@export var show_chevron: bool = true:
	set(value):
		show_chevron = value
		if _chevron != null:
			_chevron.visible = value
@export var divider: bool = false:
	set(value):
		divider = value
		queue_redraw()
## Строку можно выбрать (`toggle_mode`): выбранная — стиль «нажата» темы.
@export var selectable: bool = false:
	set(value):
		selectable = value
		toggle_mode = value

var _touch: TouchTarget = null

@onready var _content: Control = %Content
@onready var _leading: HBoxContainer = %Leading
@onready var _overline: Label = %Overline
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _columns: HBoxContainer = %Columns
@onready var _trailing: HBoxContainer = %Trailing
@onready var _chevron: TextureRect = %Chevron
@onready var _bottom: VBoxContainer = %Bottom


func _ready() -> void:
	text = ""
	toggle_mode = selectable
	_chevron.texture = CHEVRON_ICON
	_chevron.self_modulate = UiTokens.TEXT_DISABLED
	_chevron.visible = show_chevron
	_set_pass_filter(_content)
	_content.minimum_size_changed.connect(_update_height)
	pressed.connect(_on_pressed)
	_touch = TouchTarget.attach(self, TouchTarget.Kind.UI)
	_apply_texts()


func _draw() -> void:
	if divider:
		var y := size.y - DIVIDER_WIDTH * 0.5
		draw_line(Vector2(0, y), Vector2(size.x, y), UiTokens.LINE, DIVIDER_WIDTH)


## Тексты строки (готовые строки данных; пустые скрываются).
func set_texts(title_text: String, subtitle_text: String = "", overline_text: String = "") -> void:
	title = title_text
	subtitle = subtitle_text
	overline = overline_text


## Иконка Lucide в ведущем слоте (пусто — убрать). Цвет — `text` (модуляция белой иконки).
func set_icon(icon_name: String) -> void:
	_clear(_leading, false)
	if icon_name.is_empty():
		_leading.visible = false
		return
	var icon := TextureRect.new()
	icon.texture = load(ICON_DIR + icon_name + ".svg")
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_leading(icon)


## Колонки значений: `values[i]` в колонке ширины `widths[i]` lp (по правому краю). Ширин
## меньше, чем значений, — недостающие колонки по ширине содержимого. `variation` — вариация
## подписи (по умолчанию `COLUMN_VARIATION`).
func set_columns(values: Array, widths: Array = [], variation: StringName = COLUMN_VARIATION) -> void:
	_clear(_columns, true)
	for i in values.size():
		var label := Label.new()
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.theme_type_variation = variation
		label.text = str(values[i])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		if i < widths.size():
			label.custom_minimum_size.x = float(widths[i])
		_columns.add_child(label)
	_columns.visible = not values.is_empty()


## Подписи колонок (для тестов и экранов): тексты по порядку.
func column_texts() -> Array[String]:
	var out: Array[String] = []
	for child in _columns.get_children():
		out.append((child as Label).text)
	return out


## Добавить свой узел в ведущий слот (мини-превью и т.п.).
func add_leading(control: Control) -> void:
	_add_to_slot(_leading, control)


## Добавить свой узел в хвост (перед шевроном).
func add_trailing(control: Control) -> void:
	_add_to_slot(_trailing, control)


## Добавить узел в нижний слот на всю ширину (полоса времени в зонах).
func add_bottom(control: Control) -> void:
	_add_to_slot(_bottom, control)


func leading_slot() -> HBoxContainer:
	return _leading


func trailing_slot() -> HBoxContainer:
	return _trailing


func bottom_slot() -> VBoxContainer:
	return _bottom


## Выбрать/снять выбор без сигналов `pressed`/`toggled`.
func set_selected(value: bool) -> void:
	set_pressed_no_signal(value and toggle_mode)


func is_selected() -> bool:
	return toggle_mode and button_pressed


## Число видимых строк текста (определяет высоту 64/76).
func text_lines() -> int:
	var lines := 0
	for label: Label in [_overline, _title, _subtitle]:
		if label.visible:
			lines += 1
	return lines


func _on_pressed() -> void:
	activated.emit(row_id)


func _apply_texts() -> void:
	if _title == null:
		return
	_overline.text = overline
	_overline.visible = not overline.is_empty()
	_title.text = title
	_title.visible = not title.is_empty()
	_subtitle.text = subtitle
	_subtitle.visible = not subtitle.is_empty()
	_update_height()


func _update_height() -> void:
	if _touch == null:
		return
	var base := HEIGHT_TWO_LINES if text_lines() >= 2 else HEIGHT
	var content := _content.get_combined_minimum_size()
	_touch.set_floor(Vector2(content.x, maxf(base, content.y)))


func _add_to_slot(slot: Container, control: Control) -> void:
	slot.add_child(control)
	_set_pass_filter(control)
	slot.visible = true


## Неинтерактивное содержимое пропускает нажатие строке; интерактивные узлы не трогаются.
static func _set_pass_filter(node: Node) -> void:
	var control := node as Control
	if control != null:
		if control.focus_mode != Control.FOCUS_NONE:
			return
		control.mouse_filter = Control.MOUSE_FILTER_PASS
	for child in node.get_children():
		_set_pass_filter(child)


## Убрать содержимое слота. `immediate` — только для собственных узлов строки (подписи
## колонок): освобождаются сразу; узлы, добавленные экраном, — через `queue_free`.
static func _clear(slot: Container, immediate: bool) -> void:
	for child in slot.get_children():
		slot.remove_child(child)
		if immediate:
			child.free()
		else:
			child.queue_free()
