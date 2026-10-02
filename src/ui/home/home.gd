class_name HomeScreen
extends Control
## Главный экран — заглушка этапа 1: имя активного профиля, переходы на будущие
## экраны (через `AppState.navigate`) и смена профиля. Строки — через ключи переводов.

var _repo: ProfileRepository
var _app_state: AppState

@onready var _profile_label: Label = %ProfileLabel
@onready var _workout_button: Button = %WorkoutButton
@onready var _history_button: Button = %HistoryButton
@onready var _settings_button: Button = %SettingsButton
@onready var _devices_button: Button = %DevicesButton
@onready var _dev_button: Button = %DevButton
@onready var _switch_button: Button = %SwitchProfileButton


func setup(repo: ProfileRepository, app_state: AppState) -> void:
	_repo = repo
	_app_state = app_state
	if is_node_ready():
		refresh()


func _ready() -> void:
	_workout_button.pressed.connect(func() -> void: _navigate(AppState.Screen.WORKOUT))
	_history_button.pressed.connect(func() -> void: _navigate(AppState.Screen.HISTORY))
	_settings_button.pressed.connect(func() -> void: _navigate(AppState.Screen.SETTINGS))
	_devices_button.pressed.connect(func() -> void: _navigate(AppState.Screen.DEVICES))
	_dev_button.pressed.connect(func() -> void: _navigate(AppState.Screen.DEV))
	_switch_button.pressed.connect(switch_profile)
	if _repo != null:
		refresh()


## Обновить имя активного профиля.
func refresh() -> void:
	var active: Profile = _repo.get_active() if _repo != null else null
	var profile_name: String = active.name if active != null else "—"
	_profile_label.text = tr("ui.home.active_profile").format({"name": profile_name})


func active_profile_text() -> String:
	return _profile_label.text


func switch_profile() -> void:
	if _app_state != null:
		_app_state.switch_profile()


func _navigate(screen: int) -> void:
	if _app_state != null:
		_app_state.navigate(screen)
