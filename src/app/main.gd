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
const DEVICES_SCENE: String = "res://src/ui/devices/devices_screen.tscn"
const WORKOUT_SCENE: String = "res://src/ui/workout/workout_screen.tscn"
const SETTINGS_SCENE: String = "res://src/ui/settings/settings_screen.tscn"
const PLAN_SCENE: String = "res://src/ui/plan/plan_screen.tscn"
const HISTORY_SCENE: String = "res://src/ui/history/history_screen.tscn"

@export var data_dir: String = "user://"
## Implementation of the trainer for `ConnectionManager`: "ble" (default) or "fake" (dev builds).
@export var trainer_kind: String = TrainerFactory.KIND_BLE

var repo: ProfileRepository
var secure_store: SecureStore
var devices: RememberedDevices
var app_state: AppState
var bridge: BleBridge
var connections: ConnectionManager
var app_settings: AppSettings
## HTTP transport for Intervals.icu/Strava; tests may inject `MockHttpTransport` before adding to the tree.
var transport: HttpTransport = null
var plan_cache: PlanCache
var workout_library: WorkoutLibrary
## План, ожидающий выбора станка (нет подключённого устройства).
var _pending_workout: Workout = null

## Хранилище заездов (REQ-LOC-01, В-3) и запись текущей тренировки (REQ-LOC-07).
var ride_repository: RideRepository
var ride_recorder: RideRecorder = null
## Strava активного профиля (T-049): OAuth, очередь выгрузки, статусы заездов.
var strava: StravaService = null
var _strava_config: StravaConfig = null
## Диалог восстановления незавершённых заездов (REQ-LOC-07 крит. 3).
var _recovery_dialog: RecoveryDialog
## Последняя завершённая сессия (заезд при этом уже сохранён `RideRecorder`).
var last_finished_session: WorkoutSession = null
## Эмулятор, созданный для «тренировки на эмуляторе» (временно, до этапа 4).
var _emulator_trainer: TrainerDevice = null

var _screens: Dictionary = {}

@onready var _screens_root: Control = %Screens


func _ready() -> void:
	var root: String = data_dir if data_dir.ends_with("/") else data_dir + "/"
	# Saved language wins over the system one (REQ-NFR-08 crit. 3).
	app_settings = AppSettings.load_from(root + "settings.json")
	TranslationServer.set_locale(app_settings.effective_locale())
	if transport == null:
		transport = GodotHttpTransport.new(self)
	repo = ProfileRepository.new(root + "profiles/")
	secure_store = SecureStore.create_default(root + "secure/")
	devices = RememberedDevices.new(root + "devices/")
	secure_store.attach_to_profiles(repo)
	devices.attach_to_profiles(repo)
	plan_cache = PlanCache.new(root + "plans/")
	plan_cache.attach_to_profiles(repo)
	workout_library = WorkoutLibrary.new(root + "workouts/")
	workout_library.attach_to_profiles(repo)
	ride_repository = FileRideRepository.new(root + "rides/")
	ride_repository.attach_to_profiles(repo)
	_recovery_dialog = RecoveryDialog.new()
	_recovery_dialog.resolved.connect(_on_recovery_resolved)
	add_child(_recovery_dialog)
	bridge = BleBridge.create_default()
	connections = ConnectionManager.new(bridge, devices, trainer_kind)
	app_state = AppState.new(repo, app_settings)
	app_state.screen_changed.connect(_show_screen)
	app_state.profile_selected.connect(_on_profile_selected)
	app_state.locale_changed.connect(_on_locale_changed)
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
	home.emulator_workout_requested.connect(start_emulator_workout)
	_add_screen(AppState.Screen.HOME, home)
	var workout: WorkoutScreen = load(WORKOUT_SCENE).instantiate()
	workout.session_created.connect(_on_session_created)
	workout.session_finished.connect(func(s: WorkoutSession) -> void: last_finished_session = s)
	workout.profile_updated.connect(func(p: Profile) -> void: repo.save(p))
	_add_screen(AppState.Screen.WORKOUT, workout)
	var dev: DevScreen = load(DEV_SCENE).instantiate()
	dev.setup(app_state)
	_add_screen(AppState.Screen.DEV, dev)
	var devices_screen: DevicesScreen = load(DEVICES_SCENE).instantiate()
	devices_screen.setup(connections, repo, app_state)
	_add_screen(AppState.Screen.DEVICES, devices_screen)
	var plan: PlanScreen = load(PLAN_SCENE).instantiate()
	plan.setup(app_state, repo, secure_store, transport, plan_cache, workout_library)
	plan.workout_chosen.connect(func(w: Workout, _source: String) -> void: start_workout(w))
	plan.emulator_chosen.connect(func() -> void:
		if _pending_workout != null:
			start_workout_on_emulator(_pending_workout))
	plan.profile_updated.connect(func(p: Profile) -> void: repo.save(p))
	_add_screen(AppState.Screen.PLAN, plan)
	var settings: SettingsScreen = load(SETTINGS_SCENE).instantiate()
	settings.setup(repo, app_state, secure_store, transport, connections)
	_add_screen(AppState.Screen.SETTINGS, settings)
	var history: HistoryScreen = load(HISTORY_SCENE).instantiate()
	history.setup(ride_repository, repo, app_state)
	history.upload_requested.connect(_on_upload_requested)
	history.ride_deleted.connect(_on_ride_deleted)
	_add_screen(AppState.Screen.HISTORY, history)


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


## Кнопка Home «Тренировка на эмуляторе» (временно): тестовый план на эмуляторе.
func start_emulator_workout() -> void:
	start_workout_on_emulator(DevScreen.test_workout())


## Запуск выбранного плана на эмуляторе станка (`TrainerFactory.create("fake")`).
func start_workout_on_emulator(workout: Workout) -> bool:
	var screen := workout_screen()
	if screen == null or workout == null:
		return false
	if _emulator_trainer != null:
		_emulator_trainer.disconnect_device()
	_emulator_trainer = TrainerFactory.create(TrainerFactory.KIND_FAKE)
	if _emulator_trainer == null:
		return false
	_emulator_trainer.set("connect_delay_sec", 0.0)
	_emulator_trainer.connect_device("emulator")
	_pending_workout = null
	return _launch(screen, workout, _emulator_trainer, null)


## Станок подключён через `ConnectionManager` (хаб готов к сессии).
func is_trainer_ready() -> bool:
	return connections != null and connections.hub != null and connections.trainer != null \
		and connections.trainer.get_connection_state() == TrainerDevice.ConnectionState.CONNECTED


## Запуск плана (из экрана выбора, REQ-IMP-04 крит. 3): на реальном станке через хаб, если он
## подключён; иначе — экран выбора просит выбрать «эмулятор» или «подключить устройства».
## Возвращает true, если тренировка запущена сразу.
func start_workout(workout: Workout) -> bool:
	var screen := workout_screen()
	if screen == null or workout == null:
		return false
	if is_trainer_ready():
		_pending_workout = null
		return _launch(screen, workout, connections.hub, connections)
	_pending_workout = workout
	var plan := plan_screen()
	if plan != null:
		plan.show_trainer_choice()
	return false


func pending_workout() -> Workout:
	return _pending_workout


func _launch(screen: WorkoutScreen, workout: Workout, trainer: TrainerDevice, manager: ConnectionManager) -> bool:
	var profile: Profile = repo.get_active()
	if profile == null:
		profile = Profile.create("—")
	screen.setup(workout, profile, trainer, app_state, manager)
	if app_state.navigate(AppState.Screen.WORKOUT):
		return screen.start()
	return false


func plan_screen() -> PlanScreen:
	return screen_node(AppState.Screen.PLAN) as PlanScreen


func workout_screen() -> WorkoutScreen:
	return screen_node(AppState.Screen.WORKOUT) as WorkoutScreen


func history_screen() -> HistoryScreen:
	return screen_node(AppState.Screen.HISTORY) as HistoryScreen


func recovery_dialog() -> RecoveryDialog:
	return _recovery_dialog


## Сессия создана экраном тренировки (до старта): начать запись заезда на диск (REQ-LOC-07).
func _on_session_created(session: WorkoutSession) -> void:
	if ride_recorder != null:
		ride_recorder.dispose()
	var profile: Profile = repo.get_active()
	ride_recorder = RideRecorder.new(ride_repository, profile, session)


## Незавершённые заезды профиля: восстановить и спросить «сохранить досрочно / удалить».
func _recover_rides(profile_id: String) -> void:
	var rides: Array[Ride] = ride_repository.recover_in_progress(profile_id)
	if not rides.is_empty():
		_recovery_dialog.show_for(rides)


func _on_recovery_resolved(ride_id: String, action: String) -> void:
	if action == RecoveryDialog.ACTION_DELETE:
		ride_repository.delete(ride_id)
		_on_ride_deleted(ride_id)


## Заезд удалён (карточка истории или диалог восстановления): элемент очереди Strava,
## если был, убирается (REQ-LOC-06 крит. 1); активность в Strava не трогается (крит. 2).
func _on_ride_deleted(ride_id: String) -> void:
	if strava != null:
		strava.on_ride_deleted(ride_id)


func _show_screen(screen: int) -> void:
	var previous := visible_screen_node()
	if previous is WorkoutScreen and screen != AppState.Screen.WORKOUT:
		(previous as WorkoutScreen).on_screen_exited()
	# Leaving the devices screen stops manual scanning (REQ-DEV-01 crit. 4, D-5);
	# a running auto-connect keeps its own scan and stops it by itself.
	if previous is DevicesScreen and screen != AppState.Screen.DEVICES and connections != null:
		connections.stop_scan()
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
	elif node is DevicesScreen:
		(node as DevicesScreen).refresh()
	elif node is WorkoutScreen:
		(node as WorkoutScreen).on_screen_entered()
	elif node is SettingsScreen:
		(node as SettingsScreen).refresh()
	elif node is PlanScreen:
		(node as PlanScreen).refresh()
	elif node is HistoryScreen:
		(node as HistoryScreen).refresh()


func settings_screen() -> SettingsScreen:
	return screen_node(AppState.Screen.SETTINGS) as SettingsScreen


func _on_profile_selected(id: String) -> void:
	connections.auto_connect(id)
	var profile: Profile = repo.get_by_id(id)
	if profile != null and connections.hub != null:
		connections.hub.set_power_source(profile.power_source)
	_setup_strava(profile)
	_recover_rides(id)


## Сервис Strava для выбранного профиля (T-049): секреты приложения — `user://secrets.cfg`
## или окружение (`SecureStore.read_env`), токены — в `secure_store`, очередь — в данных.
func _setup_strava(profile: Profile) -> void:
	if strava != null:
		strava.dispose()
		strava = null
	if profile == null:
		return
	var root: String = data_dir if data_dir.ends_with("/") else data_dir + "/"
	if _strava_config == null:
		_strava_config = StravaConfig.load(root + "secrets.cfg", SecureStore.read_env)
	strava = StravaService.new(profile, transport, secure_store, ride_repository, _strava_config, Callable(), root)
	strava.name_template = tr("ui.strava.default_name")
	strava.description_app_line = tr("ui.strava.default_description")
	strava.attach()
	strava.authorized_changed.connect(_on_strava_authorized_changed)
	var settings := settings_screen()
	if settings != null:
		settings.set_strava_service(strava)
	var history := history_screen()
	if history != null:
		history.set_strava_linked(strava.is_authorized())


func _on_strava_authorized_changed(authorized: bool) -> void:
	var history := history_screen()
	if history != null:
		history.set_strava_linked(authorized)


## «Выгрузить в Strava» из карточки заезда (REQ-STR-04 крит. 5).
func _on_upload_requested(ride_id: String) -> void:
	if strava != null:
		strava.upload_now(ride_id)


## Language changed at runtime (REQ-NFR-08 crit. 4): scene texts re-translate by themselves,
## code-built texts are re-rendered here.
func _on_locale_changed(_locale: String) -> void:
	for node in _screens.values():
		if node is HomeScreen:
			(node as HomeScreen).refresh()
		elif node is ProfileSelectScreen:
			(node as ProfileSelectScreen).refresh()
		elif node is DevicesScreen:
			(node as DevicesScreen).refresh()
		elif node is SettingsScreen:
			(node as SettingsScreen).refresh()
		elif node is PlanScreen:
			(node as PlanScreen).refresh()
		elif node is HistoryScreen:
			(node as HistoryScreen).refresh()


## Scanner timeouts, auto-connect timer and device clocks advance with the frame;
## a workout session later takes over device ticking via `SessionTicker`
## (`connections.ticks_devices = false`).
func _process(delta: float) -> void:
	if connections != null:
		connections.tick(delta)
	if strava != null:
		strava.set_session_active(ride_recorder != null and ride_recorder.is_recording())
		strava.tick(delta)


func _exit_tree() -> void:
	if strava != null:
		strava.dispose()
	if ride_recorder != null:
		ride_recorder.dispose()
	if connections != null:
		connections.dispose()
