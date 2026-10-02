class_name KeepAwake
extends RefCounted
## Запрет гашения экрана во время тренировки (REQ-NFR-04 крит. 1, 2).
##
## Единственный вызов — `DisplayServer.screen_set_keep_on(bool)` (платформенно-
## нейтральный API движка, не `OS.*`). Вызов инъецируется (`setter: Callable`), чтобы
## в headless-тестах проверять только факт и порядок вызовов.
## Правило: RUNNING и PAUSED → запрет включён; IDLE и FINISHED → снят; уход с экрана
## тренировки (`on_screen_exited()`) — снят независимо от состояния сессии.
## Сеттер вызывается только при смене желаемого состояния.

## Изменилось желаемое состояние запрета.
signal changed(keep_on: bool)

var _setter: Callable
var _keep_on: bool = false
var _session: WorkoutSession = null


func _init(setter: Callable = Callable()) -> void:
	_setter = setter if setter.is_valid() else Callable(self, "_default_setter")


## Подписаться на сессию и применить её текущее состояние.
func attach(session: WorkoutSession) -> void:
	if _session != null:
		_session.state_changed.disconnect(_on_session_state)
	_session = session
	session.state_changed.connect(_on_session_state)
	_apply_for_state(session.get_state())


## Отписаться от сессии и снять запрет.
func detach() -> void:
	if _session != null and _session.state_changed.is_connected(_on_session_state):
		_session.state_changed.disconnect(_on_session_state)
	_session = null
	release()


## Экран тренировки закрыт — снять запрет (REQ-NFR-04 крит. 1).
func on_screen_exited() -> void:
	release()


## Экран тренировки снова открыт — применить состояние сессии.
func on_screen_entered() -> void:
	if _session != null:
		_apply_for_state(_session.get_state())


func release() -> void:
	_apply(false)


func is_on() -> bool:
	return _keep_on


## Нужен ли запрет для состояния сессии.
static func wants_keep_on(state: int) -> bool:
	return state == WorkoutSession.State.RUNNING or state == WorkoutSession.State.PAUSED


func _on_session_state(state: int) -> void:
	_apply_for_state(state)


func _apply_for_state(state: int) -> void:
	_apply(wants_keep_on(state))


func _apply(keep_on: bool) -> void:
	if keep_on == _keep_on:
		return
	_keep_on = keep_on
	_setter.call(keep_on)
	changed.emit(keep_on)


func _default_setter(keep_on: bool) -> void:
	DisplayServer.screen_set_keep_on(keep_on)
