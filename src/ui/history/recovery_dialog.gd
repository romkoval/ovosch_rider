class_name RecoveryDialog
extends ConfirmationDialog
## Диалог восстановления незавершённых заездов при запуске (REQ-LOC-07 крит. 3):
## для каждого заезда из `RideRepository.recover_in_progress` предлагает
## «сохранить как завершённый досрочно» (OK; заезд уже сохранён восстановленным)
## или «удалить» (дополнительная кнопка). Закрытие диалога равносильно «сохранить».
## Решение сообщается сигналом `resolved(ride_id, action)`; удаление выполняет владелец.
##
## Раскладка — общий `DialogLayout` (`ui.md` п. 6, REQ-UIX-01 крит. 8, 9): 480 lp, перенос,
## ряд справа: «Удалить» (опасная, `DangerButton`) · «Сохранить досрочно» (основная, крайняя
## справа). Кнопки «Отмена» в ряду нет: она дублировала бы «сохранить», а три кнопки с текущими
## подписями в 480 lp не помещаются (ru ≈ 523 lp). Удаление без возврата, поэтому безопасное
## действие — везде по умолчанию: фокус при открытии на «Сохранить досрочно» (Enter сохраняет),
## Esc / «назад» / «×» — `canceled` = сохранить; удалить можно только нажатием «Удалить».

const ACTION_KEEP: String = "keep"
const ACTION_DELETE: String = "delete"

signal resolved(ride_id: String, action: String)

var _queue: Array[Ride] = []
var _current: Ride = null
var _delete_button: Button = null


func _init() -> void:
	title = "ui.history.recovery.title"
	size = Vector2i(DialogLayout.WIDTH, 160)
	ok_button_text = "ui.history.recovery.keep"
	# Без явного ключа ConfirmationDialog показывает встроенное «Cancel» движка (не из strings.csv);
	# сама кнопка скрыта (см. описание класса), Esc / «×» по-прежнему дают `canceled`.
	cancel_button_text = "ui.common.cancel"
	get_cancel_button().hide()
	_delete_button = add_button("ui.history.recovery.delete", true, ACTION_DELETE)
	_delete_button.theme_type_variation = DialogLayout.DANGER_VARIATION
	# Ширина 480, перенос, порядок кнопок и цели нажатия; фокус на основной (сохранить):
	# опасная здесь — дополнительная кнопка, а не OK, поэтому `DialogLayout` фокус не переносит.
	DialogLayout.attach(self)
	confirmed.connect(keep)
	canceled.connect(keep)
	custom_action.connect(_on_custom_action)


## Показать диалог для списка заездов по очереди.
func show_for(rides: Array[Ride]) -> void:
	_queue = rides.duplicate()
	_show_next()


func current_ride() -> Ride:
	return _current


func pending_count() -> int:
	return _queue.size()


## Кнопка «Удалить» (опасная, дополнительная в ряду).
func delete_button() -> Button:
	return _delete_button


## «Сохранить как завершённый досрочно» для текущего заезда.
func keep() -> void:
	_resolve(ACTION_KEEP)


## «Удалить» текущий заезд.
func delete_current() -> void:
	_resolve(ACTION_DELETE)


func _on_custom_action(action: StringName) -> void:
	if action == StringName(ACTION_DELETE):
		delete_current()


func _resolve(action: String) -> void:
	if _current == null:
		return
	var ride := _current
	_current = null
	if visible:
		hide()
	resolved.emit(ride.id, action)
	# Следующий заезд — сразу (current_ride() обновляется синхронно), а окно — после кадра:
	# Esc / «×» движок закрывает отложенным hide() уже после `canceled`, и немедленный показ
	# следующего заезда тут же скрылся бы.
	_show_next(true)


func _show_next(deferred_popup: bool = false) -> void:
	if _queue.is_empty():
		return
	_current = _queue.pop_front()
	var ride_name: String = _current.name if not _current.name.is_empty() else tr("ui.history.untitled")
	dialog_text = tr("ui.history.recovery.text").format({
		"name": ride_name,
		"date": HistoryScreen.format_date_time(_current.started_at_unix),
		"time": HudModel.format_elapsed(_current.summary.duration_sec),
	})
	if not is_inside_tree():
		return
	if deferred_popup:
		_popup_current.call_deferred()
	else:
		popup_centered()


func _popup_current() -> void:
	if _current != null and is_inside_tree() and not visible:
		popup_centered()
