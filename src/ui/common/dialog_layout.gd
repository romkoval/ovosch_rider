class_name DialogLayout
extends Node
## Общее устройство диалогов `AcceptDialog` / `ConfirmationDialog` (`docs/game/ui.md` п. 6
## «Диалог»; REQ-UIX-01 крит. 8):
## - ширина 480 lp на всех устройствах, текст переносится по словам (`dialog_autowrap`);
## - ряд кнопок прижат вправо: «Отмена» (вторичная) слева, дополнительные кнопки — между ними,
##   основная или опасная — крайняя справа; кнопки по ширине текста, зазор 12 (тема);
##   область нажатия — `TouchTarget.Kind.BUTTON` (UIX-05 крит. 1);
## - фокус при открытии: в диалоге с опасной кнопкой (`DangerButton`) — «Отмена» (Enter сразу
##   после открытия закрывает без действия), в остальных — основная кнопка (поведение движка);
##   в диалоге-форме (`FormDialog`) фокус ставит сама форма;
## - Esc, «назад» и «×» — «Отмена» (`dialog_close_on_escape` движка → `canceled`).
##
## Помощник — внутренний дочерний узел диалога (как `TouchTarget`): `DialogLayout.attach(dialog)`
## или `attach_all(root)` для всех диалогов поддерева экрана. Ряд кнопок раскладывается заново
## перед каждым показом (`about_to_popup`), поэтому кнопки, добавленные `add_button` позже,
## тоже встают на место.

## Ширина диалога, lp (`ui.md` п. 6).
const WIDTH: int = 480
const NODE_NAME: StringName = &"DialogLayout"
const DANGER_VARIATION: StringName = &"DangerButton"
const FORM_VARIATION: StringName = &"FormDialog"

## Выставлять ли ширину 480 (у листа лицензий своя раскладка — false).
var fixed_width: bool = true


## Прикрепить помощника к диалогу (повторный вызов возвращает уже прикреплённый).
static func attach(dialog: AcceptDialog, with_fixed_width: bool = true) -> DialogLayout:
	var existing := of(dialog)
	if existing != null:
		existing.fixed_width = with_fixed_width
		existing.arrange()
		return existing
	var helper := DialogLayout.new()
	helper.name = NODE_NAME
	helper.fixed_width = with_fixed_width
	dialog.add_child(helper, false, Node.INTERNAL_MODE_BACK)
	dialog.about_to_popup.connect(helper.arrange)
	dialog.visibility_changed.connect(helper._on_visibility_changed)
	helper.arrange()
	return helper


## Прикрепить ко всем диалогам поддерева (кроме `FileDialog` — системный диалог файлов).
static func attach_all(root: Node) -> int:
	var count := 0
	for node in root.find_children("*", "AcceptDialog", true, false):
		if node is FileDialog or of(node as AcceptDialog) != null:
			continue
		attach(node as AcceptDialog)
		count += 1
	return count


static func of(dialog: AcceptDialog) -> DialogLayout:
	for child in dialog.get_children(true):
		if child is DialogLayout:
			return child
	return null


## Опасный диалог: основная кнопка — вариация `DangerButton`.
static func is_danger(dialog: AcceptDialog) -> bool:
	return dialog.get_ok_button().theme_type_variation == DANGER_VARIATION


static func is_form(dialog: AcceptDialog) -> bool:
	return dialog.theme_type_variation == FORM_VARIATION


## Кнопки ряда слева направо (видимые и скрытые).
static func row_buttons(dialog: AcceptDialog) -> Array[Button]:
	var out: Array[Button] = []
	var row := dialog.get_ok_button().get_parent()
	if row == null:
		return out
	for child in row.get_children(true):
		if child is Button:
			out.append(child)
	return out


func dialog() -> AcceptDialog:
	return get_parent() as AcceptDialog


## Ширина, перенос и порядок кнопок.
func arrange() -> void:
	var d := dialog()
	if d == null:
		return
	if fixed_width and not is_form(d):
		d.dialog_autowrap = true
		# `popup_centered()` сжимает окно до минимума содержимого: ширину держит `min_size`.
		d.min_size.x = WIDTH
		if d.size.x != WIDTH:
			d.size = Vector2i(WIDTH, d.size.y)
	var ok := d.get_ok_button()
	var row := ok.get_parent() as BoxContainer
	if row == null:
		return
	# Распорки движка: первая (слева) растягивается и прижимает ряд вправо, остальные скрыты.
	var spacers: Array[Control] = []
	var cancel: Button = (d as ConfirmationDialog).get_cancel_button() if d is ConfirmationDialog else null
	for child in row.get_children(true):
		if child is Control and not child is Button:
			spacers.append(child)
	for i in spacers.size():
		spacers[i].visible = i == 0
		if i == 0:
			spacers[i].size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.move_child(spacers[i], 0)
	var index := 1 if not spacers.is_empty() else 0
	if cancel != null and cancel.get_parent() == row:
		row.move_child(cancel, index)
	row.move_child(ok, row.get_child_count(true) - 1)
	for b in row_buttons(d):
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		TouchTarget.attach(b, TouchTarget.Kind.BUTTON)


func _on_visibility_changed() -> void:
	var d := dialog()
	if d == null or not d.visible or is_form(d) or not is_danger(d) or not d is ConfirmationDialog:
		return
	var cancel := (d as ConfirmationDialog).get_cancel_button()
	# Движок при показе ставит фокус на основную кнопку; опасному диалогу — «Отмена» (сразу и
	# после кадра: показ встроенного окна мог ещё не закончиться).
	cancel.grab_focus()
	cancel.grab_focus.call_deferred()
