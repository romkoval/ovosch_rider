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
const ROUTE_SELECT_SCENE: String = "res://src/ui/tracks/route_select_screen.tscn"
const FREE_RIDE_SCENE: String = "res://src/ui/free_ride/free_ride_screen.tscn"

@export var data_dir: String = "user://"
## Implementation of the trainer for `ConnectionManager`: "ble" (default) or "fake" (dev builds).
@export var trainer_kind: String = TrainerFactory.KIND_BLE
## Признак отладочной сборки для оболочки (по умолчанию — `is_debug_build()`). Тесты ставят false
## до входа в дерево, чтобы проверить поведение release-сборки.
var debug_build: bool = is_debug_build()

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
## Чтение переменных окружения для `StravaConfig` (`func(name: String) -> String`).
## Тесты подменяют до входа в дерево (например, на пустой ответ), чтобы окружение машины
## (`OVOSCH_STRAVA_CLIENT_ID/SECRET`) не влияло на результат; невалидный Callable —
## окружение не читается.
var env_reader: Callable = SecureStore.read_env
## Диалог восстановления незавершённых заездов (REQ-LOC-07 крит. 3).
var _recovery_dialog: RecoveryDialog
## Последняя завершённая сессия (заезд при этом уже сохранён `RideRecorder`).
var last_finished_session: WorkoutSession = null
## Эмулятор, созданный для «тренировки на эмуляторе» (временно, до этапа 4).
var _emulator_trainer: TrainerDevice = null
## Эмулятор включён скрытой строкой разработчика «О программе» (до перезапуска, не сохраняется).
var _emulator_unlocked: bool = false
## Кнопка «Эмулятор» диалога свободной езды (есть всегда, видна по `emulator_enabled()`).
var _free_ride_emulator_button: Button = null
## Свободная езда, ожидающая станка: `{route_id, steepness_pct}` (пусто — нет).
var _pending_free_ride: Dictionary = {}
## Диалог «станок не подключён» при старте свободной езды (FRD-01 крит. 4).
var _free_ride_trainer_dialog: ConfirmationDialog
## Последняя завершённая свободная езда (заезд уже сохранён `RideRecorder`).
var last_finished_free_ride: FreeRideSession = null

var _screens: Dictionary = {}
## Диагностический журнал запуска (T-116a): `<data_dir>/logs/`, общий для приложения
## (`DiagLog.install`), значения `SecureStore` в него не попадают (`SecureStoreFilter`).
var journal: DiagLog = null

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
	_open_journal(root + "logs/")
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
	DialogLayout.attach(_recovery_dialog)
	_build_free_ride_trainer_dialog()
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
	home.setup(repo, app_state, connections, plan_cache, workout_library, ride_repository)
	home.dev_tools_enabled = emulator_enabled()
	home.emulator_workout_requested.connect(start_emulator_workout)
	home.workout_start_requested.connect(_on_home_workout_start)
	home.import_requested.connect(_on_home_import)
	home.free_ride_requested.connect(_on_home_free_ride)
	_add_screen(AppState.Screen.HOME, home)
	var workout: WorkoutScreen = load(WORKOUT_SCENE).instantiate()
	workout.session_created.connect(_on_session_created)
	workout.session_finished.connect(_on_workout_finished)
	workout.history_requested.connect(open_ride_in_history)
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
	plan.workout_chosen.connect(_on_plan_workout_chosen)
	plan.emulator_chosen.connect(func() -> void:
		if _pending_workout != null:
			start_workout_on_emulator(_pending_workout))
	plan.dev_tools_enabled = emulator_enabled()
	plan.emulator_workout_requested.connect(_on_plan_emulator_workout)
	plan.profile_updated.connect(func(p: Profile) -> void: repo.save(p))
	_add_screen(AppState.Screen.PLAN, plan)
	var settings: SettingsScreen = load(SETTINGS_SCENE).instantiate()
	settings.setup(repo, app_state, secure_store, transport, connections)
	_add_screen(AppState.Screen.SETTINGS, settings)
	settings.diagnostics().emulator_toggled.connect(set_emulator_unlocked)
	settings.diagnostics().show_emulator_state(emulator_enabled(), debug_build)
	var history: HistoryScreen = load(HISTORY_SCENE).instantiate()
	history.setup(ride_repository, repo, app_state)
	history.upload_requested.connect(_on_upload_requested)
	history.ride_deleted.connect(_on_ride_deleted)
	_add_screen(AppState.Screen.HISTORY, history)
	var route_select: RouteSelectScreen = load(ROUTE_SELECT_SCENE).instantiate()
	route_select.setup(repo, app_state)
	route_select.start_requested.connect(start_free_ride)
	_add_screen(AppState.Screen.ROUTE_SELECT, route_select)
	var free_ride: FreeRideScreen = load(FREE_RIDE_SCENE).instantiate()
	free_ride.setup(app_state)
	free_ride.session_created.connect(_on_free_ride_created)
	free_ride.session_finished.connect(_on_free_ride_finished)
	free_ride.profile_updated.connect(func(p: Profile) -> void: repo.save(p))
	free_ride.history_requested.connect(open_ride_in_history)
	_add_screen(AppState.Screen.FREE_RIDE, free_ride)


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


## Отладочная сборка (редактор, отладочный экспорт): `assert` выполняется только в ней, поэтому
## флаг ставится без обращения к `OS` (REQ-NFR-06 крит. 1). Для эмулятора — `emulator_enabled()`.
static func is_debug_build() -> bool:
	var probe: Array[bool] = [false]
	assert(_mark_debug(probe))
	return probe[0]


static func _mark_debug(probe: Array[bool]) -> bool:
	probe[0] = true
	return true


## Эмулятор станка доступен (REQ-DEV-09 крит. 6, FRD-01 крит. 4): в отладочной сборке — всегда,
## в release — после включения скрытой строкой «Эмулятор станка» в «О программе». Единственный
## признак для «Режима разработки» и «На эмуляторе» главного, «На эмуляторе» и «Эмулятора»
## экрана выбора тренировки и «Эмулятора» диалога свободной езды.
func emulator_enabled() -> bool:
	return debug_build or _emulator_unlocked


## Включить или выключить эмулятор (скрытая строка «О программе»): действует до перезапуска,
## уже созданные экраны и диалоги обновляются сразу; переключение — в журнал. Идущий заезд на
## эмуляторе не прерывается.
func set_emulator_unlocked(enabled: bool) -> void:
	if enabled != _emulator_unlocked:
		_emulator_unlocked = enabled
		DiagLog.event(DiagLog.CAT_APP, "emulator", {"enabled": enabled, "debug_build": debug_build})
	_apply_emulator_access()


func _apply_emulator_access() -> void:
	var enabled := emulator_enabled()
	var home := home_screen()
	if home != null:
		home.dev_tools_enabled = enabled
	var plan := plan_screen()
	if plan != null:
		plan.dev_tools_enabled = enabled
	if _free_ride_emulator_button != null:
		_free_ride_emulator_button.visible = enabled
	var settings := settings_screen()
	if settings != null and settings.diagnostics() != null:
		settings.diagnostics().show_emulator_state(enabled, debug_build)


func home_screen() -> HomeScreen:
	return screen_node(AppState.Screen.HOME) as HomeScreen


## План выбран на экране выбора: он же — «последний выбранный» карточки главного экрана.
func _on_plan_workout_chosen(workout: Workout, source: String) -> void:
	var home := home_screen()
	if home != null:
		home.remember_workout(workout, source)
	start_workout(workout)


## «Начать» в карточке плана (REQ-UIX-02 крит. 1): то же правило станка, что у экрана выбора;
## без станка выбор «эмулятор / устройства» показывает экран выбора тренировки.
func _on_home_workout_start(workout: Workout) -> void:
	if not is_trainer_ready():
		app_state.navigate(AppState.Screen.PLAN)
	start_workout(workout)


## «Импорт файла» в пустой карточке плана: экран выбора тренировки и диалог файла.
func _on_home_import() -> void:
	if app_state.navigate(AppState.Screen.PLAN) and plan_screen() != null:
		plan_screen().open_import_dialog()


## «Поехать» в карточке свободной езды (FRD-01 крит. 1): трасса карточки и крутизна SIM профиля.
func _on_home_free_ride(route_id: String) -> void:
	var profile: Profile = repo.get_active()
	start_free_ride(route_id, profile.sim_steepness_pct if profile != null else Profile.DEFAULT_SIM_STEEPNESS_PCT)


## Кнопка Home «Тренировка на эмуляторе» (временно): тестовый план на эмуляторе.
func start_emulator_workout() -> void:
	start_workout_on_emulator(DevScreen.test_workout())


## «На эмуляторе» на экране выбора тренировки (отладочная сборка): выбранный план — на эмуляторе.
func _on_plan_emulator_workout(workout: Workout) -> void:
	start_workout_on_emulator(workout)


## Запуск выбранного плана на эмуляторе станка (`TrainerFactory.create("fake")`).
func start_workout_on_emulator(workout: Workout) -> bool:
	var screen := workout_screen()
	if screen == null or workout == null:
		return false
	if not _make_emulator():
		return false
	_pending_workout = null
	return _launch(screen, workout, _emulator_trainer, null)


## Новый эмулятор станка (`TrainerFactory.create("fake")`, подключён сразу); прежний отключается.
func _make_emulator() -> bool:
	if _emulator_trainer != null:
		_emulator_trainer.disconnect_device()
	_emulator_trainer = TrainerFactory.create(TrainerFactory.KIND_FAKE)
	if _emulator_trainer == null:
		return false
	_emulator_trainer.set("connect_delay_sec", 0.0)
	_emulator_trainer.connect_device("emulator")
	return true


## Эмулятор последнего запуска «на эмуляторе» (null — не создавался).
func emulator_trainer() -> TrainerDevice:
	return _emulator_trainer


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


# ---------------------------------------------------------------------------
# Свободная езда (REQ-FRD-01 крит. 1, 4; REQ-FRD-07 крит. 2, 6, 7)
# ---------------------------------------------------------------------------

## Запуск свободной езды по трассе с крутизной SIM («Поехать» на главном и на экране выбора
## трассы). Правило станка — как у плана: подключён станок (хаб `ConnectionManager`) — заезд
## стартует на нём; нет — сессия не создаётся, диалог поясняет и ведёт на «Устройства», а при
## `emulator_enabled()` предлагает эмулятор (FRD-01 крит. 4). true — заезд запущен сразу.
func start_free_ride(route_id: String, steepness_pct: int) -> bool:
	if free_ride_screen() == null:
		return false
	if is_trainer_ready():
		_pending_free_ride = {}
		return launch_free_ride(connections.hub, route_id, steepness_pct, connections)
	_pending_free_ride = {"route_id": route_id, "steepness_pct": steepness_pct}
	_free_ride_trainer_dialog.popup_centered()
	return false


## Свободная езда на эмуляторе станка (отладка, снимки UI).
func start_free_ride_on_emulator(route_id: String, steepness_pct: int) -> bool:
	if not _make_emulator():
		return false
	_pending_free_ride = {}
	return launch_free_ride(_emulator_trainer, route_id, steepness_pct, null)


## Свободная езда на заданном станке: экран свободной езды, затем старт сессии.
func launch_free_ride(trainer: TrainerDevice, route_id: String, steepness_pct: int,
		manager: ConnectionManager = null) -> bool:
	var screen := free_ride_screen()
	if screen == null or trainer == null:
		return false
	var profile: Profile = repo.get_active()
	if profile == null:
		profile = Profile.create("—")
	screen.setup(app_state, profile, trainer, route_id, steepness_pct, manager)
	if app_state.navigate(AppState.Screen.FREE_RIDE):
		return screen.start()
	return false


## Заезд, ожидающий станка (`{route_id, steepness_pct}`; пусто — нет).
func pending_free_ride() -> Dictionary:
	return _pending_free_ride.duplicate()


func free_ride_trainer_dialog() -> ConfirmationDialog:
	return _free_ride_trainer_dialog


## Кнопка «Эмулятор» диалога свободной езды (видна по `emulator_enabled()`).
func free_ride_emulator_button() -> Button:
	return _free_ride_emulator_button


## Диалог «станок не подключён»: «Устройства» (основная), «Отмена»; «Эмулятор» — по `emulator_enabled()`.
func _build_free_ride_trainer_dialog() -> void:
	_free_ride_trainer_dialog = ConfirmationDialog.new()
	_free_ride_trainer_dialog.name = "FreeRideTrainerDialog"
	_free_ride_trainer_dialog.title = "ui.free_ride.no_trainer.title"
	_free_ride_trainer_dialog.dialog_text = "ui.free_ride.no_trainer.text"
	# 480 lp с переносом и кнопки справа — общий помощник диалогов (`ui.md` п. 6).
	_free_ride_trainer_dialog.size = Vector2i(DialogLayout.WIDTH, 160)
	_free_ride_trainer_dialog.dialog_autowrap = true
	_free_ride_trainer_dialog.ok_button_text = "ui.free_ride.no_trainer.devices"
	_free_ride_trainer_dialog.cancel_button_text = "ui.common.cancel"
	_free_ride_emulator_button = _free_ride_trainer_dialog.add_button("ui.free_ride.no_trainer.emulator", true, &"emulator")
	_free_ride_emulator_button.visible = emulator_enabled()
	_free_ride_trainer_dialog.custom_action.connect(_on_free_ride_trainer_action)
	_free_ride_trainer_dialog.confirmed.connect(_on_free_ride_devices_chosen)
	_free_ride_trainer_dialog.canceled.connect(_on_free_ride_choice_canceled)
	add_child(_free_ride_trainer_dialog)
	DialogLayout.attach(_free_ride_trainer_dialog)


## «Эмулятор» в диалоге (при `emulator_enabled()`, FRD-01 крит. 4): ожидающий заезд — на эмуляторе.
func choose_free_ride_emulator() -> bool:
	if _pending_free_ride.is_empty() or not emulator_enabled():
		return false
	var pending := _pending_free_ride
	_free_ride_trainer_dialog.hide()
	return start_free_ride_on_emulator(str(pending["route_id"]), int(pending["steepness_pct"]))


func _on_free_ride_trainer_action(action: StringName) -> void:
	if action == &"emulator":
		choose_free_ride_emulator()


func _on_free_ride_devices_chosen() -> void:
	_pending_free_ride = {}
	app_state.navigate(AppState.Screen.DEVICES)


func _on_free_ride_choice_canceled() -> void:
	_pending_free_ride = {}


## Сессия свободной езды создана (до старта): запись заезда на диск (REQ-LOC-07, FRD-07 крит. 2–4).
func _on_free_ride_created(session: FreeRideSession) -> void:
	if ride_recorder != null:
		ride_recorder.dispose()
	ride_recorder = RideRecorder.new(ride_repository, repo.get_active(), session)


## Заезд завершён и сохранён `RideRecorder` (`RideRepository.save` → очередь Strava по
## `ride_saved`, FRD-07 крит. 7): экран показывает итог сохранённого заезда.
func _on_free_ride_finished(session: FreeRideSession) -> void:
	last_finished_free_ride = session
	if ride_recorder != null and ride_recorder.session == session and ride_recorder.ride != null:
		free_ride_screen().show_saved_ride(ride_recorder.ride)


## Тренировка завершена: заезд уже начат `RideRecorder` (id известен с первой секунды), сводку он
## пишет следом в том же сигнале. Итог получает id для «Открыть в истории».
func _on_workout_finished(session: WorkoutSession) -> void:
	last_finished_session = session
	if ride_recorder != null and ride_recorder.session == session and ride_recorder.ride != null:
		workout_screen().set_saved_ride_id(ride_recorder.ride_id())


## Открыть заезд в истории (итог заезда): список истории и карточка заезда.
func open_ride_in_history(ride_id: String) -> void:
	if not app_state.navigate(AppState.Screen.HISTORY):
		return
	var history := history_screen()
	if history != null and not ride_id.is_empty():
		history.show_ride(ride_id)


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


## Решение по восстановленному заезду (REQ-LOC-07 крит. 3, REQ-STR-04 крит. 1): только
## «сохранить» передаёт заезд Strava (очередь при привязке и автовыгрузке); «удалить» —
## заезд удаляется, в Strava ничего не уходит.
func _on_recovery_resolved(ride_id: String, action: String) -> void:
	if action == RecoveryDialog.ACTION_DELETE:
		ride_repository.delete(ride_id)
		_on_ride_deleted(ride_id)
	elif action == RecoveryDialog.ACTION_KEEP and strava != null:
		strava.on_ride_saved(ride_id)


## Заезд удалён (карточка истории или диалог восстановления): элемент очереди Strava,
## если был, убирается (REQ-LOC-06 крит. 1); активность в Strava не трогается (крит. 2).
func _on_ride_deleted(ride_id: String) -> void:
	if strava != null:
		strava.on_ride_deleted(ride_id)


func _show_screen(screen: int) -> void:
	var previous := visible_screen_node()
	if previous is WorkoutScreen and screen != AppState.Screen.WORKOUT:
		(previous as WorkoutScreen).on_screen_exited()
	if previous is FreeRideScreen and screen != AppState.Screen.FREE_RIDE:
		(previous as FreeRideScreen).on_screen_exited()
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
	elif node is RouteSelectScreen:
		(node as RouteSelectScreen).refresh()
	elif node is FreeRideScreen:
		(node as FreeRideScreen).on_screen_entered()
	_sync_go_back_policy()


func route_select_screen() -> RouteSelectScreen:
	return screen_node(AppState.Screen.ROUTE_SELECT) as RouteSelectScreen


func free_ride_screen() -> FreeRideScreen:
	return screen_node(AppState.Screen.FREE_RIDE) as FreeRideScreen


# ---------------------------------------------------------------------------
# «Назад»: Esc на компьютере и системный «назад» Android (REQ-UIX-04 крит. 1, 2)
# ---------------------------------------------------------------------------

## Единая обработка «назад» для Esc и Android. По порядку: открытый диалог экрана закрывается
## как отменённый; экран перехватывает «назад» сам (тренировка — запрос досрочного завершения
## с подтверждением, WRK-05 крит. 4; история — карточка заезда → список; режим разработки —
## остановка прогона); на экране сессии без идущей сессии — на главный; иначе — стек
## `AppState.go_back`. true — «назад» обработан.
func handle_back() -> bool:
	if app_state == null:
		return false
	if _close_top_dialog():
		return true
	if _screen_handles_back(visible_screen_node()):
		return true
	if AppState.is_session_screen(app_state.current_screen):
		return app_state.navigate(AppState.Screen.HOME)
	return app_state.go_back()


func _screen_handles_back(node: Control) -> bool:
	if node is WorkoutScreen:
		var workout := node as WorkoutScreen
		if workout.is_stop_confirmation_pending():
			workout.cancel_stop()
			return true
		return workout.request_stop()
	if node is FreeRideScreen:
		return (node as FreeRideScreen).handle_back()
	if node is HistoryScreen:
		var history := node as HistoryScreen
		if history.is_detail_visible():
			history.back_to_list()
			return true
		return false
	if node is DevScreen:
		# Прогон на эмуляторе останавливается так же, как кнопкой экрана (на главный).
		(node as DevScreen).back()
		return true
	if node is RouteSelectScreen:
		return (node as RouteSelectScreen).handle_back()
	if node is PlanScreen:
		# Открытый на телефоне лист предпросмотра закрывается, экран остаётся.
		return (node as PlanScreen).handle_back()
	if node is SettingsScreen:
		# Идущий замер FPS (T-116a) прерывается, экран настроек остаётся.
		return (node as SettingsScreen).handle_back()
	return false


## Закрыть верхний видимый диалог (окно) внутри оболочки так же, как крестиком или Esc:
## `NOTIFICATION_WM_CLOSE_REQUEST` → у `AcceptDialog` это «Отмена» (сигнал `canceled`).
## Нужно для Android: системный «назад» приходит уведомлением, а не событием ввода в окно.
func _close_top_dialog() -> bool:
	var window := _top_dialog()
	if window == null:
		return false
	window.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	if window.visible:
		window.hide()
	return true


## Верхний видимый диалог внутри оболочки или null.
func _top_dialog() -> Window:
	var windows: Array[Window] = get_viewport().get_embedded_subwindows()
	for i in range(windows.size() - 1, -1, -1):
		var window: Window = windows[i]
		if window.visible and is_ancestor_of(window):
			return window
	return null


## Системный «назад» Android на корне стека навигации (главный, выбор профиля) приложение
## не перехватывает (REQ-UIX-04 крит. 1, У-4): штатное поведение движка — закрыть
## приложение (`SceneTree.quit_on_go_back`). Открытый диалог закрывается «назад» и на корне;
## на остальных экранах «назад» обрабатывает оболочка (`handle_back`). Политика сверяется
## при смене экрана и каждый кадр (диалоги открываются без смены экрана).
func _sync_go_back_policy() -> void:
	if not is_inside_tree() or app_state == null:
		return
	var native := AppState.is_root_screen(app_state.current_screen) and _top_dialog() == null
	if get_tree().quit_on_go_back != native:
		get_tree().quit_on_go_back = native


## Приложение отдаёт «назад» движку (корень стека, диалогов нет).
func is_go_back_native() -> bool:
	return is_inside_tree() and get_tree().quit_on_go_back


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel", false, true) and handle_back():
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# На корне событие не поглощается: приложение закрывает движок (`quit_on_go_back`).
		if not is_go_back_native():
			handle_back()


func settings_screen() -> SettingsScreen:
	return screen_node(AppState.Screen.SETTINGS) as SettingsScreen


func _on_profile_selected(id: String) -> void:
	connections.auto_connect(id)
	var profile: Profile = repo.get_by_id(id)
	if profile != null and connections.hub != null:
		connections.hub.set_power_source(profile.power_source)
	# Восстановление — до создания сервиса Strava: `recover_in_progress` сохраняет заезды,
	# и подписанный сервис поставил бы их в очередь до ответа пользователя (REQ-STR-04 крит. 1).
	_dispose_strava()
	_recover_rides(id)
	_setup_strava(profile)


## Сервис Strava для выбранного профиля (T-049): секреты приложения — `user://secrets.cfg`
## или окружение (`SecureStore.read_env`), токены — в `secure_store`, очередь — в данных.
func _setup_strava(profile: Profile) -> void:
	_dispose_strava()
	if profile == null:
		return
	var root: String = data_dir if data_dir.ends_with("/") else data_dir + "/"
	if _strava_config == null:
		_strava_config = StravaConfig.load(root + "secrets.cfg", env_reader)
	strava = StravaService.new(profile, transport, secure_store, ride_repository, _strava_config, Callable(), root)
	# Название «Тренировка <дата>» и строку приложения сервис переводит сам в момент постановки
	# в очередь (текущий язык интерфейса, REQ-STR-03 крит. 1, 2).
	strava.attach()
	strava.authorized_changed.connect(_on_strava_authorized_changed)
	var settings := settings_screen()
	if settings != null:
		settings.set_strava_service(strava)
	var history := history_screen()
	if history != null:
		history.set_strava_linked(strava.is_authorized())


func _dispose_strava() -> void:
	if strava == null:
		return
	if strava.authorized_changed.is_connected(_on_strava_authorized_changed):
		strava.authorized_changed.disconnect(_on_strava_authorized_changed)
	strava.dispose()
	strava = null


func _on_strava_authorized_changed(authorized: bool) -> void:
	var history := history_screen()
	if history != null:
		history.set_strava_linked(authorized)


## «Выгрузить в Strava» из карточки заезда (REQ-STR-04 крит. 5): название и описание из полей
## карточки попадают в запрос (REQ-STR-03 крит. 3); пустые — значения по умолчанию.
func _on_upload_requested(ride_id: String, ride_name: String = "", description: String = "") -> void:
	if strava != null:
		strava.upload_now(ride_id, ride_name, description)


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
			# Только тексты: полный `refresh()` затёр бы несохранённый ввод формы профиля.
			(node as SettingsScreen).refresh_texts()
		elif node is PlanScreen:
			(node as PlanScreen).refresh()
		elif node is HistoryScreen:
			(node as HistoryScreen).refresh()


## Scanner timeouts, auto-connect timer and device clocks advance with the frame;
## a workout session later takes over device ticking via `SessionTicker`
## (`connections.ticks_devices = false`).
func _process(delta: float) -> void:
	_sync_go_back_policy()
	if connections != null:
		connections.tick(delta)
	if strava != null:
		strava.set_session_active(ride_recorder != null and ride_recorder.is_recording())
		strava.tick(delta)


## Открыть журнал запуска и сделать его общим; первая запись — версия и окружение.
func _open_journal(dir_path: String) -> void:
	journal = DiagLog.new(dir_path)
	journal.filter().set_store(secure_store)
	if journal.open() != OK:
		push_warning("AppMain: diagnostic log not opened (%s)" % error_string(journal.last_error()))
		return
	DiagLog.install(journal)
	var info := FrameStatsProbe.render_info(self)
	info["locale"] = TranslationServer.get_locale()
	info["format"] = DiagLog.FORMAT_VERSION
	journal.write(DiagLog.CAT_APP, "app_started", info)


func _exit_tree() -> void:
	# Оболочки нет — «назад» снова решает движок (значение по умолчанию).
	get_tree().quit_on_go_back = true
	if journal != null:
		journal.write(DiagLog.CAT_APP, "app_stopped")
		journal.close()
		DiagLog.uninstall(journal)
	if strava != null:
		strava.dispose()
	if ride_recorder != null:
		ride_recorder.dispose()
	if connections != null:
		connections.dispose()
