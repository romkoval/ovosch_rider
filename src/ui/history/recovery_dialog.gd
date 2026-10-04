class_name RecoveryDialog
extends ConfirmationDialog
## Диалог восстановления незавершённых заездов при запуске (REQ-LOC-07 крит. 3):
## для каждого заезда из `RideRepository.recover_in_progress` предлагает
## «сохранить как завершённый досрочно» (OK; заезд уже сохранён восстановленным)
## или «удалить» (дополнительная кнопка). Закрытие диалога равносильно «сохранить».
## Решение сообщается сигналом `resolved(ride_id, action)`; удаление выполняет владелец.

const ACTION_KEEP: String = "keep"
const ACTION_DELETE: String = "delete"

signal resolved(ride_id: String, action: String)

var _queue: Array[Ride] = []
var _current: Ride = null


func _init() -> void:
	title = "ui.history.recovery.title"
	# Ширина диалога 480 lp, текст переносится (`ui.md` п. 6 «Диалог / лист»).
	size = Vector2i(480, 160)
	dialog_autowrap = true
	ok_button_text = "ui.history.recovery.keep"
	# Без явного ключа ConfirmationDialog показывает встроенное «Cancel» движка (не из strings.csv).
	cancel_button_text = "ui.common.cancel"
	add_button("ui.history.recovery.delete", true, ACTION_DELETE)
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
	_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		return
	_current = _queue.pop_front()
	var ride_name: String = _current.name if not _current.name.is_empty() else tr("ui.history.untitled")
	dialog_text = tr("ui.history.recovery.text").format({
		"name": ride_name,
		"date": HistoryScreen.format_date_time(_current.started_at_unix),
		"time": HudModel.format_elapsed(_current.summary.duration_sec),
	})
	if is_inside_tree():
		popup_centered()
