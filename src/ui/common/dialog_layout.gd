class_name DialogLayout
extends Node
## Общее устройство диалогов `AcceptDialog` / `ConfirmationDialog` (`docs/game/ui.md` п. 6
## «Диалог»; REQ-UIX-01 крит. 8):
## - ширина 480 lp на всех устройствах, текст переносится по словам (`dialog_autowrap`);
## - ряд кнопок прижат вправо: «Отмена» (вторичная) слева, дополнительные кнопки — между ними,
##   основная или опасная — крайняя справа; кнопки по ширине текста, зазор 12 (тема);
##   область нажатия — `TouchTarget.Kind.BUTTON` (UIX-05 крит. 1);
## - основная кнопка (OK) — вариация `PrimaryButton`, если диалог не сделал её опасной
##   (`DangerButton`): в обычном диалоге ровно одна кнопка с заливкой (T-145; у «диалога-выбора»
##   `RecoveryDialog` их две — опасная слева и основная справа, `ui.md` п. 6);
## - подписи с переносом получают ширину содержимого до раскладки, окно — их минимум: при первом
##   открытии в сессии диалог того же размера, что при повторном (`fit_wrapped_text`, T-145);
## - фокус при открытии: в диалоге с опасной кнопкой (`DangerButton`) — «Отмена» (Enter сразу
##   после открытия закрывает без действия), в остальных — основная кнопка (поведение движка);
##   в диалоге-форме (`FormDialog`) фокус ставит сама форма;
## - Esc, «назад» и «×» — «Отмена» (`dialog_close_on_escape` движка → `canceled`);
## - под видимым диалогом — вуаль `scrim` (`UiTokens.SCRIM`, `ui.md` п. 6; REQ-UIX-01 п.9, T-142)
##   на весь вьюпорт, в котором диалог встроен: слой `CanvasLayer` с `custom_viewport` =
##   вьюпорт родителя диалога, ниже встроенных окон (они рисуются над всеми слоями холста),
##   выше экранов. Нажатия не перехватывает (диалоги модальные и так).
##
## Помощник — внутренний дочерний узел диалога (как `TouchTarget`): `DialogLayout.attach(dialog)`
## или `attach_all(root)` для всех диалогов поддерева экрана. Ряд кнопок раскладывается заново
## перед каждым показом (`about_to_popup`), поэтому кнопки, добавленные `add_button` позже,
## тоже встают на место.

## Ширина диалога, lp (`ui.md` п. 6).
const WIDTH: int = 480
const NODE_NAME: StringName = &"DialogLayout"
const DANGER_VARIATION: StringName = &"DangerButton"
const PRIMARY_VARIATION: StringName = &"PrimaryButton"
const FORM_VARIATION: StringName = &"FormDialog"
## Зазор между кнопками ряда, lp (`ui.md` п. 6).
const BUTTON_GAP: float = 12.0
## Слой вуали: над экранами и HUD, под встроенными окнами (слой окон движка — 1024).
const SCRIM_LAYER: int = 1000
const SCRIM_NAME: StringName = &"DialogScrim"

## Выставлять ли ширину 480 (у листа лицензий своя раскладка — false).
var fixed_width: bool = true

var _scrim_layer: CanvasLayer = null
var _scrim: ColorRect = null
var _scrim_viewport: Viewport = null


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
	# Прозрачный фон вьюпорта окна: при дробном масштабе холста (телефон, ×1.475) последняя строка
	# пикселей окна частичная, и непрозрачный фон вьюпорта давал под кнопками тёмный шов; под ней —
	# рамка `embedded_border` того же `surface1`. Фон содержимого рисует панель `panel`.
	d.transparent_bg = true
	var ok := d.get_ok_button()
	# Основная кнопка неопасного диалога — с заливкой `accent` (`ui.md` п. 6). Явно заданную
	# вариацию (`DangerButton`) не трогает. У диалога-формы ряд окна скрыт, кнопки — в форме.
	if ok.theme_type_variation == &"" and not is_form(d):
		ok.theme_type_variation = PRIMARY_VARIATION
	var row := ok.get_parent() as BoxContainer
	if row == null:
		return
	# Распорки движка (движок держит их видимыми вместе с кнопками): первая видимая растягивается
	# и прижимает ряд вправо; между соседними видимыми кнопками — по одной видимой распорке
	# шириной, дающей зазор `BUTTON_GAP` (с учётом `separation` ряда); лишние распорки и скрытые
	# кнопки (например, скрытая «Отмена», T-114) — нулевой ширины слева. Скрытая кнопка прячет
	# и свою распорку, поэтому видимых распорок хватает на ведущую и зазоры.
	var visible_spacers: Array[Control] = []
	var hidden: Array[Control] = []
	var cancel: Button = (d as ConfirmationDialog).get_cancel_button() if d is ConfirmationDialog else null
	for child in row.get_children(true):
		if child is Control and not child is Button:
			if (child as Control).visible:
				visible_spacers.append(child)
			else:
				hidden.append(child)
	var buttons: Array[Button] = []
	if cancel != null and cancel.get_parent() == row:
		buttons.append(cancel)
	for b in row_buttons(d):
		if b != cancel and b != ok:
			buttons.append(b)
	buttons.append(ok)
	var shown: Array[Button] = []
	for b in buttons:
		if b.visible:
			shown.append(b)
		else:
			hidden.append(b)
	var separation := float(row.get_theme_constant("separation"))
	var gap_width := maxf(BUTTON_GAP - 2.0 * separation, 0.0)
	var order: Array[Control] = []
	var free_spacers := visible_spacers.duplicate()
	var leading: Control = free_spacers.pop_front() if not free_spacers.is_empty() else null
	for i in shown.size():
		if i > 0 and not free_spacers.is_empty():
			var gap: Control = free_spacers.pop_back()
			gap.size_flags_horizontal = Control.SIZE_FILL
			gap.custom_minimum_size.x = gap_width
			order.append(gap)
		order.append(shown[i])
	for rest: Control in free_spacers + hidden:
		if not rest is Button:
			rest.size_flags_horizontal = Control.SIZE_FILL
			rest.custom_minimum_size.x = 0.0
		order.push_front(rest)
	if leading != null:
		leading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		leading.custom_minimum_size.x = 0.0
		order.push_front(leading)
	for k in order.size():
		row.move_child(order[k], k)
	for b in buttons:
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		TouchTarget.attach(b, TouchTarget.Kind.BUTTON)


## Вуаль под диалогом (null — не создана: диалог ещё не показывался).
func scrim() -> ColorRect:
	return _scrim


## Вуаль видна (диалог на экране).
func is_scrim_visible() -> bool:
	return _scrim_layer != null and _scrim_layer.visible


## Подписи с переносом по словам — по ширине содержимого диалога, окно — по их минимуму
## (T-144, T-145; REQ-UIX-05 п.2). Пока окно скрыто, раскладка содержимого не идёт: у ни разу не
## показанной подписи в форме ширина 1 px (минимальная высота — текст по букве в строке,
## ~2000 lp), у текста диалога — ширина окна до `attach` (без переноса — во всю строку, до 930 lp).
## `popup_centered()` берёт размер окна из этого минимума: при первом открытии диалог уходил за
## край окна или был шире 480, при втором — уже нет.
## - Свои подписи содержимого получают ширину, которую им даст раскладка (содержимое окна минус
##   поля панели и полей-контейнеров на пути), и пересчитывают минимум.
## - Текст диалога (`get_label()`, растянут якорями на окно) раскладывает сам движок, когда окно
##   видно и меняет размер: видимому окну задаётся ширина, минимум текста пересчитывается.
## Окно сжимается до минимума, видимое — с сохранением центра. Подписи в рядах и сетках (ширину
## заранее не узнать) и диалоги со своей раскладкой (`attach(dialog, false)`, лист лицензий)
## не трогаются.
static func fit_wrapped_text(d: AcceptDialog) -> void:
	var helper := of(d)
	if helper != null and not helper.fixed_width:
		return
	var center := Vector2(d.position) + Vector2(d.size) / 2.0
	var text_label := d.get_label()
	var panel := d.get_theme_stylebox(&"panel")
	var margins := panel.get_minimum_size().x if panel != null else 0.0
	var outer := float(d.min_size.x)
	if is_form(d):
		outer = maxf(outer, float(d.size.x))
	else:
		outer = maxf(outer, float(WIDTH))
		# Ряд кнопок шире 480 (три кнопки) — и содержимое шире.
		var row := d.get_ok_button().get_parent() as Control
		if row != null and row.visible:
			outer = maxf(outer, row.get_combined_minimum_size().x + margins)
		# Минимум текста диалога движок обновляет отложенно: после включения переноса он ещё
		# держит ширину строки без переноса, а высоту — по прошлой ширине подписи.
		text_label.update_minimum_size()
		if d.visible:
			if d.size.x != int(outer):
				d.size = Vector2i(int(outer), d.size.y)
			text_label.update_minimum_size()
	var content := outer - margins
	for node in d.find_children("*", "Label", true, false):
		var label := node as Label
		if label == text_label or label.autowrap_mode == TextServer.AUTOWRAP_OFF:
			continue
		# Растянутую якорями подпись раскладывает родитель, размер ей не задаётся.
		if label.anchor_left != label.anchor_right or label.anchor_top != label.anchor_bottom:
			continue
		var width := _label_width(d, label, content)
		if width <= 0.0:
			continue
		width = maxf(width, label.custom_minimum_size.x)
		if absf(label.size.x - width) > 0.5:
			label.size = Vector2(width, label.size.y)
		label.update_minimum_size()
	d.reset_size()
	if d.visible:
		d.position = Vector2i((center - Vector2(d.size) / 2.0).round())


## Ширина, которую раскладка даст подписи в содержимом шириной `content`; -1 — заранее не известна
## (подпись в ряду, сетке или прижата, а не растянута).
static func _label_width(d: AcceptDialog, label: Label, content: float) -> float:
	var width := content
	var node: Node = label
	while node != null and node != d:
		var parent := node.get_parent()
		if parent is HBoxContainer or parent is GridContainer or parent is FlowContainer:
			return -1.0
		if parent is Container and node is Control \
				and ((node as Control).size_flags_horizontal & Control.SIZE_FILL) == 0:
			return -1.0
		if parent is MarginContainer:
			var m := parent as MarginContainer
			width -= float(m.get_theme_constant(&"margin_left") + m.get_theme_constant(&"margin_right"))
		elif parent is PanelContainer:
			var box := (parent as PanelContainer).get_theme_stylebox(&"panel")
			width -= box.get_minimum_size().x if box != null else 0.0
		node = parent
	return width


func _on_visibility_changed() -> void:
	var d := dialog()
	if d == null:
		return
	if d.visible:
		# Раньше вуали: окно уже стоит на месте и размере `popup_centered()`, движок ещё не
		# проверил, помещается ли оно в родителя.
		fit_wrapped_text(d)
	_sync_scrim(d.visible)
	if not d.visible or is_form(d) or not is_danger(d) or not d is ConfirmationDialog:
		return
	var cancel := (d as ConfirmationDialog).get_cancel_button()
	# Движок при показе ставит фокус на основную кнопку; опасному диалогу — «Отмена» (сразу и
	# после кадра: показ встроенного окна мог ещё не закончиться).
	cancel.grab_focus()
	cancel.grab_focus.call_deferred()


## Показать или убрать вуаль под диалогом. Вуаль — во вьюпорте родителя диалога (встроенное окно
## рисуется в нём), размер — видимая область этого вьюпорта, следит за её изменением.
func _sync_scrim(shown: bool) -> void:
	if not shown:
		if _scrim_layer != null:
			_scrim_layer.visible = false
		_watch_viewport(null)
		return
	var d := dialog()
	var host: Node = d.get_parent() if d != null else null
	var viewport: Viewport = host.get_viewport() if host != null and host.is_inside_tree() else null
	if viewport == null:
		return
	# `custom_viewport` задаётся до входа слоя в дерево: смена на ходу ломает отписку движка
	# от `child_order_changed` при выходе. Другой вьюпорт — слой создаётся заново.
	if _scrim_layer != null and _scrim_layer.custom_viewport != viewport:
		_scrim_layer.queue_free()
		_scrim_layer = null
		_scrim = null
	if _scrim_layer == null:
		_scrim_layer = CanvasLayer.new()
		_scrim_layer.name = SCRIM_NAME
		_scrim_layer.layer = SCRIM_LAYER
		_scrim_layer.custom_viewport = viewport
		_scrim = ColorRect.new()
		_scrim.name = &"Scrim"
		_scrim.color = UiTokens.SCRIM
		_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scrim_layer.add_child(_scrim)
		add_child(_scrim_layer)
	_watch_viewport(viewport)
	_fit_scrim()
	_scrim_layer.visible = true


func _watch_viewport(viewport: Viewport) -> void:
	if _scrim_viewport == viewport:
		return
	if _scrim_viewport != null and is_instance_valid(_scrim_viewport) \
			and _scrim_viewport.size_changed.is_connected(_fit_scrim):
		_scrim_viewport.size_changed.disconnect(_fit_scrim)
	_scrim_viewport = viewport
	if viewport != null and not viewport.size_changed.is_connected(_fit_scrim):
		viewport.size_changed.connect(_fit_scrim)


func _fit_scrim() -> void:
	if _scrim == null or _scrim_viewport == null or not is_instance_valid(_scrim_viewport):
		return
	var rect := _scrim_viewport.get_visible_rect()
	_scrim.position = rect.position
	_scrim.size = rect.size


func _exit_tree() -> void:
	_watch_viewport(null)
