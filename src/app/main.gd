class_name AppMain
extends Node
## Корневая сцена приложения: собирает зависимости (репозиторий профилей,
## защищённое хранилище, реестр устройств, состояние навигации), подключает
## каскады удаления профиля и показывает экран по `AppState.screen_changed`.
##
## `data_dir` — корень данных (`user://` в приложении; в тестах — временный каталог).

const PROFILE_SELECT_SCENE: String = "res://src/ui/profile_select/profile_select.tscn"
const HOME_SCENE: String = "res://src/ui/home/home.tscn"
const DEV_SCENE: String = "res://src/ui/dev/dev_screen.tscn"

@export var data_dir: String = "user://"

var repo: ProfileRepository
var secure_store: SecureStore
var devices: RememberedDevices
var app_state: AppState

var _screens: Dictionary = {}

@onready var _screens_root: Control = %Screens


func _ready() -> void:
	TranslationServer.set_locale(AppLocale.detect())
	var root: String = data_dir if data_dir.ends_with("/") else data_dir + "/"
	repo = ProfileRepository.new(root + "profiles/")
	secure_store = SecureStore.create_default(root + "secure/")
	devices = RememberedDevices.new(root + "devices/")
	secure_store.attach_to_profiles(repo)
	devices.attach_to_profiles(repo)
	app_state = AppState.new(repo)
	app_state.screen_changed.connect(_show_screen)
	_build_screens()
	app_state.start()
	_show_screen(app_state.current_screen)


## Узел экрана по `AppState.Screen`.
func screen_node(screen: int) -> Control:
	return _screens.get(screen, null)


## Видимый сейчас экран.
func visible_screen_node() -> Control:
	for node in _screens.values():
		if (node as Control).visible:
			return node
	return null


func _build_screens() -> void:
	var select: ProfileSelectScreen = load(PROFILE_SELECT_SCENE).instantiate()
	select.setup(repo, app_state)
	_add_screen(AppState.Screen.PROFILE_SELECT, select)
	var home: HomeScreen = load(HOME_SCENE).instantiate()
	home.setup(repo, app_state)
	_add_screen(AppState.Screen.HOME, home)
	var dev: DevScreen = load(DEV_SCENE).instantiate()
	dev.setup(app_state)
	_add_screen(AppState.Screen.DEV, dev)
	for screen in [AppState.Screen.WORKOUT, AppState.Screen.HISTORY, AppState.Screen.SETTINGS]:
		_add_screen(screen, _make_placeholder(screen))


func _add_screen(screen: int, node: Control) -> void:
	node.visible = false
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screens_root.add_child(node)
	_screens[screen] = node


func _make_placeholder(screen: int) -> Control:
	var panel := CenterContainer.new()
	panel.name = "Placeholder_" + AppState.screen_name(screen)
	var vbox := VBoxContainer.new()
	var label := Label.new()
	label.text = "ui.common.coming_soon"
	var back := Button.new()
	back.text = "ui.home.title"
	back.pressed.connect(func() -> void: app_state.navigate(AppState.Screen.HOME))
	vbox.add_child(label)
	vbox.add_child(back)
	panel.add_child(vbox)
	return panel


func _show_screen(screen: int) -> void:
	for key in _screens:
		(_screens[key] as Control).visible = key == screen
	var node := screen_node(screen)
	if node is HomeScreen:
		(node as HomeScreen).refresh()
	elif node is ProfileSelectScreen:
		(node as ProfileSelectScreen).refresh()
	elif node is DevScreen:
		var active: Profile = repo.get_active()
		(node as DevScreen).setup(app_state, active.ftp_w if active != null else DevScreen.DEFAULT_FTP_W)
