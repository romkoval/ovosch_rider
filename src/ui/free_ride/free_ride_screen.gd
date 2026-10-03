class_name FreeRideScreen
extends Control
## Свободная езда (REQ-FRD-01, REQ-FRD-06) — заготовка навигационного каркаса (T-061):
## экран в навигации и «назад». Сцена по трассе, сессия, HUD, пауза и стоп — T-084.

var _app_state: AppState

@onready var _back_button: Button = %BackButton


func setup(app_state: AppState) -> void:
	_app_state = app_state


func _ready() -> void:
	_back_button.pressed.connect(back)


## Системный «назад» (Esc, Android) на экране сессии (REQ-UIX-04 крит. 2): true — экран
## перехватил его (идёт сессия → запрос досрочного завершения с подтверждением, как
## WRK-05 крит. 4; это делает T-084); false — сессии нет, оболочка ведёт на главный.
func handle_back() -> bool:
	return false


## Кнопка заготовки: сессии нет — на главный.
func back() -> void:
	if _app_state != null:
		_app_state.navigate(AppState.Screen.HOME)
