class_name HomeScreen
extends Control
## Главный экран (REQ-UIX-02 крит. 1–6, REQ-FRD-01 крит. 1 — вход; `docs/game/ui.md` п. 8.2,
## макет `shots/2026-10-03-ui-mockups/home_1280.png`).
##
## Сверху — словесный знак `ovosch·rider`, фишки статуса станка и запомненных датчиков
## (состояние DEV-07.1, заряд DEV-07.2; нажатие → «Устройства») и фишка профиля (при двух и
## более профилях — меню «Сменить профиль»). Под ними две карточки сценариев `ScenarioCard`:
## - «Тренировка по плану · ERG»: план на сегодня из кэша Intervals.icu (без сети), иначе
##   последний выбранный в этом запуске (`remember_workout`), иначе последний импортированный
##   в библиотеку; превью `PlanPreview`, длительность, макс. цель, шагов; «Начать»
##   (`workout_start_requested`) и «Другая тренировка» (→ PLAN). Плана нет — пустое состояние
##   с «Из библиотеки» (→ PLAN) и «Импорт файла» (`import_requested`), «Начать» нет.
## - «Свободная езда · SIM»: трасса профиля (`Profile.effective_route_id`), превью
##   `RoutePreview`, круг, набор, макс. уклон; «Поехать» (`free_ride_requested(route_id)`) и
##   «Сменить трассу» (→ ROUTE_SELECT).
## Ниже — плитки «История», «Устройства», «Настройки» (одно нажатие); на compact (ширина
## холста < 1100 lp) — три кнопки-иконки в панели. Кнопки «Тренировка на эмуляторе» и
## «Режим разработки» — только при `dev_tools_enabled` (оболочка включает их в отладочной
## сборке); на compact — за кнопкой «⋯».
##
## Раскладка: контент не шире 1216 lp по центру, поля `ScreenMargin` (compact —
## `ScreenMarginCompact`) плюс безопасная зона `UiScaleRuntime`; высота карточек
## clamp(0.56·H, 300, 460), но не больше остатка окна — плитки и отладочные кнопки
## без прокрутки. Все стили — вариации темы, включая знак (`LogoLabel` / `LogoAccentLabel`) и
## надзаголовки сценариев (`OverlineAccent` / `OverlineSim`).
## Строки — ключи `ui.home.*` (`strings_menu.csv`, `strings.csv`).

## Временная кнопка (отладка): тренировка на эмуляторе.
signal emulator_workout_requested()
## «Начать» в карточке плана: запустить показанную тренировку (решает оболочка).
signal workout_start_requested(workout: Workout)
## «Импорт файла» в пустом состоянии карточки плана.
signal import_requested()
## «Поехать» в карточке свободной езды: трасса карточки.
signal free_ride_requested(route_id: String)

const CONTENT_MAX_WIDTH: float = 1216.0
const COMPACT_MAX_WIDTH: float = AppBar.COMPACT_MAX_WIDTH
const BAR_HEIGHT: float = AppBar.HEIGHT
const BAR_HEIGHT_COMPACT: float = AppBar.HEIGHT_COMPACT
const TILE_HEIGHT: float = 88.0
## Высота карточек сценариев: clamp(доля · H, мин, макс) (`ui.md` п. 8.2).
const CARD_HEIGHT_FRACTION: float = 0.56
const CARD_MIN_HEIGHT: float = 300.0
const CARD_MAX_HEIGHT: float = 460.0
## Основная кнопка карточки на компьютере и планшете — 200 lp.
const PRIMARY_MIN_WIDTH: float = 200.0
const DOT_DIAMETER: float = 10.0
const AVATAR_DIAMETER: float = 24.0
const AVATAR_FONT_SIZE: int = 12
const CHEVRON_SIZE: float = 24.0
## Вторая (пустая) строка текста плитки: под неё ложится подпись; неразрывный пробел —
## чтобы строка не схлопнулась.
const TILE_SECOND_LINE: String = "\n\u00A0"

## Словесный знак (`ui.md` п. 6): имя продукта, не переводится; «·rider» — цветом `accent`.
const LOGO_MAIN: String = "ovosch"
const LOGO_ACCENT: String = "·rider"

const SOURCE_INTERVALS: String = "intervals"
const SOURCE_LIBRARY: String = "library"

const CHIP_KIND_KEYS: Dictionary = {
	RememberedDevices.KIND_TRAINER: "ui.home.chip.trainer",
	RememberedDevices.KIND_HR: "ui.home.chip.hr",
	RememberedDevices.KIND_CADENCE: "ui.home.chip.cadence",
	RememberedDevices.KIND_POWER: "ui.home.chip.power",
}
const MENU_SWITCH_PROFILE: int = 0
const MENU_DEV_EMULATOR: int = 0
const MENU_DEV_SCREEN: int = 1

## Кнопки «Тренировка на эмуляторе» и «Режим разработки» (REQ-UIX-02 крит. 6). Оболочка
## включает их только в отладочной сборке; по умолчанию скрыты (как в релизе).
var dev_tools_enabled: bool = false:
	set(value):
		dev_tools_enabled = value
		if is_node_ready():
			_update_layout()

## Дата «сегодня» для кэша плана (YYYY-MM-DD); пусто — локальная дата. Для тестов.
var today: String = ""

var _repo: ProfileRepository
var _app_state: AppState
var _connections: ConnectionManager = null
var _plan_cache: PlanCache = null
var _library: WorkoutLibrary = null
var _rides: RideRepository = null

var _profile: Profile = null
var _active_profile_text: String = ""
var _plan_workout: Workout = null
var _plan_source: String = ""
var _remembered_workout: Workout = null
var _remembered_source: String = ""
var _remembered_profile_id: String = ""
var _route_id: String = ""
var _route_models: Dictionary = {}
## Устройства, не найденные автоподключением (id → true), до следующей попытки.
var _not_found: Dictionary = {}
var _not_found_profile_id: String = ""
var _compact: bool = false
var _chips: Array[Button] = []
var _tile_keys: Dictionary = {}
var _tile_captions: Dictionary = {}

@onready var _column: VBoxContainer = %Column
@onready var _bar: HBoxContainer = %Bar
@onready var _logo_accent: Label = %LogoAccent
@onready var _nav_icons: HBoxContainer = %NavIcons
@onready var _device_chips: HBoxContainer = %DeviceChips
@onready var _profile_chip: Button = %SwitchProfileButton
@onready var _dev_menu_button: Button = %DevMenuButton
@onready var _cards: HBoxContainer = %Cards
## Ширина колонки контента (без полей и безопасной зоны), lp; считается в `_update_layout`.
var _content_width: float = 0.0
@onready var _plan_card: Button = %PlanCard
@onready var _plan_content: VBoxContainer = %PlanContent
@onready var _plan_header: HBoxContainer = %PlanHeader
@onready var _plan_overline: Label = %PlanOverline
@onready var _plan_body: VBoxContainer = %PlanBody
@onready var _plan_title: Label = %PlanTitle
@onready var _plan_source_label: Label = %PlanSource
@onready var _plan_preview: PlanPreview = %PlanPreview
@onready var _plan_duration: StatView = %PlanDuration
@onready var _plan_max_target: StatView = %PlanMaxTarget
@onready var _plan_steps: StatView = %PlanSteps
@onready var _plan_empty: VBoxContainer = %PlanEmpty
@onready var _empty_icon: TextureRect = %EmptyIcon
@onready var _plan_buttons: HBoxContainer = %PlanButtons
@onready var _start_button: Button = %StartWorkoutButton
@onready var _workout_button: Button = %WorkoutButton
@onready var _import_button: Button = %ImportButton
@onready var _ride_card: Button = %RideCard
@onready var _ride_content: VBoxContainer = %RideContent
@onready var _ride_header: HBoxContainer = %RideHeader
@onready var _ride_overline: Label = %RideOverline
@onready var _ride_title: Label = %RideTitle
@onready var _ride_kind: Label = %RideKind
@onready var _route_preview: RoutePreview = %RoutePreview
@onready var _ride_length: StatView = %RideLength
@onready var _ride_ascent: StatView = %RideAscent
@onready var _ride_max_grade: StatView = %RideMaxGrade
@onready var _ride_buttons: HBoxContainer = %RideButtons
@onready var _ride_button: Button = %RideButton
@onready var _route_button: Button = %RouteButton
@onready var _tiles: HBoxContainer = %Tiles
@onready var _history_button: Button = %HistoryButton
@onready var _devices_button: Button = %DevicesButton
@onready var _settings_button: Button = %SettingsButton
@onready var _dev_row: HBoxContainer = %DevRow
@onready var _emulator_button: Button = %EmulatorWorkoutButton
@onready var _dev_button: Button = %DevButton
@onready var _profile_menu: PopupMenu = %ProfileMenu
@onready var _dev_menu: PopupMenu = %DevMenu

static var _placeholders: Dictionary = {}


## Зависимости экрана. `connections` — статус устройств (null — фишка станка «не подключено»),
## `plan_cache` и `library` — план карточки, `rides` — подпись плитки истории.
func setup(repo: ProfileRepository, app_state: AppState, connections: ConnectionManager = null,
		plan_cache: PlanCache = null, library: WorkoutLibrary = null, rides: RideRepository = null) -> void:
	_disconnect_connections()
	_repo = repo
	_app_state = app_state
	_connections = connections
	_plan_cache = plan_cache
	_library = library
	_rides = rides
	if _connections != null:
		_connections.state_changed.connect(_on_device_state_changed)
		_connections.devices_changed.connect(_refresh_devices)
		_connections.auto_connect_timed_out.connect(_on_auto_connect_timed_out)
	if is_node_ready():
		refresh()


func _ready() -> void:
	(%LogoMain as Label).text = LOGO_MAIN
	_logo_accent.text = LOGO_ACCENT
	_setup_icons()
	_setup_tiles()
	_profile_chip.icon = _placeholder(AVATAR_DIAMETER)
	_profile_chip.draw.connect(_draw_profile_avatar)
	_profile_chip.pressed.connect(_on_profile_chip_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	_workout_button.pressed.connect(_navigate.bind(AppState.Screen.PLAN))
	_import_button.pressed.connect(_on_import_pressed)
	_ride_button.pressed.connect(_on_ride_pressed)
	_route_button.pressed.connect(_navigate.bind(AppState.Screen.ROUTE_SELECT))
	_history_button.pressed.connect(_navigate.bind(AppState.Screen.HISTORY))
	_devices_button.pressed.connect(_navigate.bind(AppState.Screen.DEVICES))
	_settings_button.pressed.connect(_navigate.bind(AppState.Screen.SETTINGS))
	(%HistoryIconButton as Button).pressed.connect(_navigate.bind(AppState.Screen.HISTORY))
	(%DevicesIconButton as Button).pressed.connect(_navigate.bind(AppState.Screen.DEVICES))
	(%SettingsIconButton as Button).pressed.connect(_navigate.bind(AppState.Screen.SETTINGS))
	_dev_button.pressed.connect(_navigate.bind(AppState.Screen.DEV))
	_emulator_button.pressed.connect(_on_emulator_pressed)
	_dev_menu_button.pressed.connect(_on_dev_menu_pressed)
	_profile_menu.add_item("ui.home.switch_profile", MENU_SWITCH_PROFILE)
	_profile_menu.id_pressed.connect(_on_profile_menu_id)
	_dev_menu.add_item("ui.home.workout_emulator", MENU_DEV_EMULATOR)
	_dev_menu.add_item("ui.home.dev", MENU_DEV_SCREEN)
	_dev_menu.id_pressed.connect(_on_dev_menu_id)
	for button: Button in [_start_button, _workout_button, _import_button, _ride_button, _route_button]:
		TouchTarget.attach(button, TouchTarget.Kind.BUTTON)
	for button: Button in [_profile_chip, _dev_menu_button, _emulator_button, _dev_button,
			%HistoryIconButton, %DevicesIconButton, %SettingsIconButton]:
		TouchTarget.attach(button, TouchTarget.Kind.UI)
	for tile: Button in [_history_button, _devices_button, _settings_button]:
		TouchTarget.attach(tile, TouchTarget.Kind.UI, Vector2(0, TILE_HEIGHT))
	resized.connect(_update_layout)
	var runtime := TouchTarget.default_runtime()
	if runtime != null:
		runtime.scale_changed.connect(_on_scale_changed)
	_apply_card_insets()
	refresh()


func _exit_tree() -> void:
	var runtime := TouchTarget.default_runtime()
	if runtime != null and runtime.scale_changed.is_connected(_on_scale_changed):
		runtime.scale_changed.disconnect(_on_scale_changed)


func _enter_tree() -> void:
	if not is_node_ready():
		return
	var runtime := TouchTarget.default_runtime()
	if runtime != null and not runtime.scale_changed.is_connected(_on_scale_changed):
		runtime.scale_changed.connect(_on_scale_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_disconnect_connections()
	elif what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_apply_card_insets()
	elif what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		# Надзаголовки задаются переведённым текстом (`_set_overline`) — пересчитать.
		_update_layout()


# ---------------------------------------------------------------------------
# Данные
# ---------------------------------------------------------------------------

## Перечитать профиль, план, трассу, устройства и подписи плиток (вход на экран, смена языка).
func refresh() -> void:
	if not is_node_ready():
		return
	_profile = _repo.get_active() if _repo != null else null
	var profile_name: String = _profile.name if _profile != null else "—"
	_active_profile_text = tr("ui.home.active_profile").format({"name": profile_name})
	_refresh_profile_chip()
	_refresh_plan()
	_refresh_route()
	_refresh_tiles()
	_refresh_devices()
	_update_layout()


## Подпись профиля для доступности и тестов: «Профиль: <имя>» (подсказка фишки профиля).
func active_profile_text() -> String:
	return _active_profile_text


## Запомнить тренировку, выбранную на экране выбора (`PlanScreen.SOURCE_*`): она становится
## «последней выбранной» карточки плана, пока на сегодня нет плана Intervals.icu.
func remember_workout(workout: Workout, source: String) -> void:
	_remembered_workout = workout
	_remembered_source = source
	_remembered_profile_id = _repo.active_profile_id if _repo != null else ""
	if is_node_ready():
		_refresh_plan()
		_update_layout()


func switch_profile() -> void:
	if _app_state != null:
		_app_state.switch_profile()


## Тренировка карточки плана (null — пустое состояние).
func card_workout() -> Workout:
	return _plan_workout


## Источник тренировки карточки: `SOURCE_INTERVALS`, `SOURCE_LIBRARY` или "".
func card_workout_source() -> String:
	return _plan_source


## Трасса карточки свободной езды.
func card_route_id() -> String:
	return _route_id


func plan_title_text() -> String:
	return _plan_title.text


func plan_source_text() -> String:
	return _plan_source_label.text


## Цифры карточки плана: длительность, макс. цель, шагов (значения без единиц).
func plan_stat_values() -> Array[String]:
	return [_plan_duration.value, _plan_max_target.value, _plan_steps.value] as Array[String]


func route_title_text() -> String:
	return _ride_title.text


func route_kind_text() -> String:
	return _ride_kind.text


## Цифры карточки трассы: круг (км), набор (м), макс. уклон (%).
func route_stat_values() -> Array[String]:
	return [_ride_length.value, _ride_ascent.value, _ride_max_grade.value] as Array[String]


func is_plan_empty() -> bool:
	return _plan_workout == null


## Две карточки сценариев (план, свободная езда).
func scenario_cards() -> Array[Control]:
	return [_plan_card, _ride_card] as Array[Control]


## Фишки статуса устройств (станок первым).
func device_chips() -> Array[Button]:
	return _chips.duplicate()


## Тексты фишек устройств по порядку.
func device_chip_texts() -> Array[String]:
	var out: Array[String] = []
	for chip in _chips:
		out.append(chip.text)
	return out


## Цвет точки фишки устройства (`UiTokens`): состояние DEV-07.1.
func device_chip_color(index: int) -> Color:
	return _chips[index].get_meta(&"dot_color", UiTokens.TEXT_DISABLED) if index < _chips.size() else Color()


## Подпись плитки («История», «Устройства», «Настройки»): вторая строка.
func tile_caption(tile: Button) -> String:
	var label: Label = _tile_captions.get(tile, null)
	return label.text if label != null else ""


func is_compact() -> bool:
	return _compact


func profile_menu() -> PopupMenu:
	return _profile_menu


func dev_menu() -> PopupMenu:
	return _dev_menu


func _refresh_profile_chip() -> void:
	if _profile == null:
		_profile_chip.text = "—"
	elif _compact:
		_profile_chip.text = _profile.name
	else:
		_profile_chip.text = "%s · %d %s" % [_profile.name, _profile.ftp_w, tr("ui.menu.unit.w")]
	var can_switch: bool = _repo != null and _repo.count() >= 2
	_profile_chip.tooltip_text = _active_profile_text + ("\n" + tr("ui.home.switch_profile") if can_switch else "")
	_profile_chip.focus_mode = Control.FOCUS_ALL if can_switch else Control.FOCUS_NONE
	_profile_chip.mouse_filter = Control.MOUSE_FILTER_STOP if can_switch else Control.MOUSE_FILTER_IGNORE
	_profile_chip.queue_redraw()


func _refresh_plan() -> void:
	var picked := _pick_plan()
	_plan_workout = picked.get("workout", null)
	_plan_source = str(picked.get("source", ""))
	var has_plan: bool = _plan_workout != null
	_plan_body.visible = has_plan
	_plan_empty.visible = not has_plan
	_start_button.visible = has_plan
	_import_button.visible = not has_plan
	_workout_button.text = "ui.home.plan.other" if has_plan else "ui.home.plan.from_library"
	if not has_plan:
		_plan_title.text = ""
		_plan_source_label.text = ""
		_plan_preview.set_workout(null, 0)
		return
	var ftp: int = _profile.ftp_w if _profile != null else 200
	var intensity: float = float(_profile.intensity_default) / 100.0 if _profile != null else 1.0
	var zones: PowerZones = _profile.effective_power_zones() if _profile != null else null
	_plan_title.text = _plan_workout.name
	_plan_source_label.text = tr("ui.home.plan.source_today") if _plan_source == SOURCE_INTERVALS else tr("ui.home.plan.source_library")
	_plan_preview.set_workout(_plan_workout, ftp, intensity, zones)
	_plan_duration.value = IntervalsPlanService.format_duration(_plan_workout.total_duration_sec())
	var max_w := max_target_watts(_plan_workout, ftp, intensity)
	_plan_max_target.value = str(max_w) if max_w > 0 else "—"
	_plan_steps.value = str(_plan_workout.steps.size())


## План карточки: на сегодня из кэша Intervals.icu (без сети) → выбранный в этом запуске →
## последний импортированный в библиотеку. `{workout, source}` или пустой словарь.
func _pick_plan() -> Dictionary:
	if _profile == null:
		return {}
	if _plan_cache != null:
		var cached: Dictionary = _plan_cache.get_today(_profile.id, today)
		for entry in cached.get("workouts", []):
			var w: Variant = (entry as Dictionary).get("workout", null)
			if w is Workout:
				return {"workout": w, "source": SOURCE_INTERVALS}
	if _remembered_workout != null and _remembered_profile_id == _profile.id:
		return {"workout": _remembered_workout, "source": _remembered_source}
	if _library != null:
		var entries := _library.list(_profile.id)
		for i in range(entries.size() - 1, -1, -1):
			var w := _library.get_workout(_profile.id, str(entries[i]["id"]))
			if w != null:
				return {"workout": w, "source": SOURCE_LIBRARY}
	return {}


## Максимальная цель плана, Вт (шаги «свободно» не в счёт).
static func max_target_watts(workout: Workout, ftp_w: int, intensity: float = 1.0) -> int:
	var best: int = 0
	for step in workout.steps:
		if step.is_free_ride():
			continue
		best = maxi(best, maxi(step.start_watts(ftp_w, intensity), step.end_watts(ftp_w, intensity)))
	return best


func _refresh_route() -> void:
	var route_id: String = _profile.effective_route_id() if _profile != null else Profile.DEFAULT_ROUTE_ID
	_route_id = RouteCatalog.resolve_id(route_id)
	var model: RoutePreviewModel = _route_models.get(_route_id, null)
	if model == null:
		model = RoutePreviewModel.for_route(RouteCatalog.get_route(_route_id))
		_route_models[_route_id] = model
	_ride_title.text = tr(model.name_key)
	_ride_kind.text = tr(model.kind_key)
	_route_preview.model = model
	var stat_views: Array[StatView] = [_ride_length, _ride_ascent, _ride_max_grade]
	var stats := model.stats()
	for i in mini(stats.size(), stat_views.size()):
		stat_views[i].set_stat(str(stats[i]["value"]), str(stats[i]["unit"]), str(stats[i]["caption"]))


func _refresh_tiles() -> void:
	for tile: Button in _tile_keys:
		tile.text = tr(_tile_keys[tile]) + TILE_SECOND_LINE
	(_tile_captions[_history_button] as Label).text = _history_caption()
	(_tile_captions[_settings_button] as Label).text = tr("ui.home.tile.settings").format({
		"ftp": _profile.ftp_w if _profile != null else 0,
		"weight": _format_weight(_profile.weight_kg if _profile != null else 0.0),
	})


func _history_caption() -> String:
	if _rides == null or _profile == null:
		return tr("ui.home.tile.history.empty")
	var last: RideSummary = null
	for s in _rides.list(_profile.id):
		if s.in_progress:
			continue
		if last == null or s.started_at_unix > last.started_at_unix:
			last = s
	if last == null:
		return tr("ui.home.tile.history.empty")
	var parts := PackedStringArray([
		_relative_day(last.started_at_unix),
		IntervalsPlanService.format_duration(last.duration_sec),
	])
	if last.distance_m > 0.0:
		parts.append("%s %s" % [RoutePreviewModel.length_value(last.distance_m), tr("ui.menu.unit.km")])
	return " · ".join(parts)


## «сегодня», «вчера» или дата `ГГГГ-ММ-ДД` (локальное время устройства).
func _relative_day(unix: int) -> String:
	var day := PlanCache.local_datetime(unix)
	var now := PlanCache.local_datetime(int(Time.get_unix_time_from_system()))
	var yesterday := PlanCache.local_datetime(int(Time.get_unix_time_from_system()) - 86400)
	if _same_day(day, now):
		return tr("ui.home.tile.history.today")
	if _same_day(day, yesterday):
		return tr("ui.home.tile.history.yesterday")
	return "%04d-%02d-%02d" % [day["year"], day["month"], day["day"]]


static func _same_day(a: Dictionary, b: Dictionary) -> bool:
	return a["year"] == b["year"] and a["month"] == b["month"] and a["day"] == b["day"]


static func _format_weight(kg: float) -> String:
	return str(roundi(kg)) if is_equal_approx(kg, roundf(kg)) else "%.1f" % kg


# ---------------------------------------------------------------------------
# Устройства (REQ-UIX-02 крит. 3)
# ---------------------------------------------------------------------------

func _refresh_devices() -> void:
	if not is_node_ready():
		return
	var profile_id: String = _repo.active_profile_id if _repo != null else ""
	if profile_id != _not_found_profile_id or (_connections != null and _connections.is_auto_connecting()):
		_not_found.clear()
	_not_found_profile_id = profile_id
	var entries: Array[Dictionary] = [_trainer_entry()]
	if _connections != null and not profile_id.is_empty():
		for record in _connections.remembered.sensors(profile_id):
			entries.append({"kind": str(record.get("kind", "")), "id": str(record.get("id", "")), "name": str(record.get("name", ""))})
	while _chips.size() < entries.size():
		_chips.append(_make_chip())
	while _chips.size() > entries.size():
		var extra: Button = _chips.pop_back()
		_device_chips.remove_child(extra)
		extra.queue_free()
	for i in entries.size():
		_update_chip(_chips[i], entries[i])
	var tile_key := "ui.home.tile.devices.disconnected"
	if _trainer_state() == TrainerDevice.ConnectionState.CONNECTED:
		tile_key = "ui.home.tile.devices.connected"
	elif _connections != null and not _connections.is_ble_available():
		tile_key = "ui.home.tile.devices.ble_off"
	(_tile_captions[_devices_button] as Label).text = tr(tile_key)


func _trainer_entry() -> Dictionary:
	var entry := {"kind": RememberedDevices.KIND_TRAINER, "id": "", "name": ""}
	if _connections == null:
		return entry
	var record := _connections.remembered.trainer()
	var id: String = _connections.trainer_id if not _connections.trainer_id.is_empty() else str(record.get("id", ""))
	entry["id"] = id
	entry["name"] = str(record.get("name", "")) if str(record.get("id", "")) == id else ""
	return entry


func _trainer_state() -> int:
	var entry := _trainer_entry()
	if _connections == null or str(entry["id"]).is_empty():
		return TrainerDevice.ConnectionState.DISCONNECTED
	return _connections.state_of(str(entry["id"]))


func _make_chip() -> Button:
	var chip := Button.new()
	chip.theme_type_variation = &"ChipButton"
	chip.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.icon = _placeholder(DOT_DIAMETER)
	chip.pressed.connect(_navigate.bind(AppState.Screen.DEVICES))
	chip.draw.connect(_draw_chip_dot.bind(chip))
	_device_chips.add_child(chip)
	TouchTarget.attach(chip, TouchTarget.Kind.UI)
	return chip


func _update_chip(chip: Button, entry: Dictionary) -> void:
	var id: String = entry["id"]
	var state: int = TrainerDevice.ConnectionState.DISCONNECTED
	var battery: int = -1
	if _connections != null and not id.is_empty():
		state = _connections.state_of(id)
		battery = _connections.battery_of(id)
		if state != TrainerDevice.ConnectionState.DISCONNECTED:
			_not_found.erase(id)
	var not_found: bool = _not_found.has(id)
	var kind_text: String = tr(CHIP_KIND_KEYS.get(entry["kind"], "ui.devices.kind.unknown"))
	var detail: String
	if state == TrainerDevice.ConnectionState.CONNECTED:
		detail = str(entry["name"]) if not str(entry["name"]).is_empty() else tr(DevicesScreen.state_key(state))
	elif not_found:
		detail = tr("ui.home.chip.not_found")
	else:
		detail = tr(DevicesScreen.state_key(state))
	var full := "%s · %s" % [kind_text, detail]
	var short := kind_text
	if battery >= 0:
		var charge := "%d %s" % [battery, tr("ui.menu.unit.pct")]
		full += " · " + charge
		short += " · " + charge
	chip.text = short if _compact else full
	chip.tooltip_text = full
	chip.set_meta(&"dot_color", chip_dot_color(state, not_found))
	chip.queue_redraw()


## Цвет точки фишки (`ui.md` п. 6): подключено — `accent`; ищет, подключается,
## переподключается или не найдено — `warn`; не подключено — `text_disabled`.
static func chip_dot_color(state: int, not_found: bool = false) -> Color:
	match state:
		TrainerDevice.ConnectionState.CONNECTED:
			return UiTokens.ACCENT
		TrainerDevice.ConnectionState.SCANNING, TrainerDevice.ConnectionState.CONNECTING, \
				TrainerDevice.ConnectionState.RECONNECTING:
			return UiTokens.WARN
	return UiTokens.WARN if not_found else UiTokens.TEXT_DISABLED


func _on_device_state_changed(_id: String) -> void:
	_refresh_devices()


func _on_auto_connect_timed_out(ids: Array[String]) -> void:
	for id in ids:
		_not_found[id] = true
	_refresh_devices()


func _disconnect_connections() -> void:
	if _connections == null:
		return
	if _connections.state_changed.is_connected(_on_device_state_changed):
		_connections.state_changed.disconnect(_on_device_state_changed)
	if _connections.devices_changed.is_connected(_refresh_devices):
		_connections.devices_changed.disconnect(_refresh_devices)
	if _connections.auto_connect_timed_out.is_connected(_on_auto_connect_timed_out):
		_connections.auto_connect_timed_out.disconnect(_on_auto_connect_timed_out)


# ---------------------------------------------------------------------------
# Раскладка
# ---------------------------------------------------------------------------

func _update_layout() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return
	var compact: bool = size.x < COMPACT_MAX_WIDTH
	var compact_changed: bool = compact != _compact
	_compact = compact
	var margin_type: StringName = &"ScreenMarginCompact" if compact else &"ScreenMargin"
	var mh := float(get_theme_constant("margin_left", margin_type))
	var mv := float(get_theme_constant("margin_top", margin_type))
	var safe := _safe_margins()
	var left: float = mh + safe.x
	var right: float = mh + safe.z
	var extra: float = maxf(0.0, (size.x - left - right - CONTENT_MAX_WIDTH) * 0.5)
	_content_width = size.x - left - right - 2.0 * extra
	_column.offset_left = left + extra
	_column.offset_right = -(right + extra)
	# Панель сверху — как `AppBar`: от верхнего края (её высота 72/64 уже включает поля).
	_column.offset_top = safe.y
	_column.offset_bottom = -(mv + safe.w)
	_column.theme_type_variation = &"Stack16" if compact else &"Stack24"
	_bar.custom_minimum_size.y = BAR_HEIGHT_COMPACT if compact else BAR_HEIGHT
	_tiles.visible = not compact
	_nav_icons.visible = compact
	_dev_row.visible = dev_tools_enabled and not compact
	_dev_menu_button.visible = dev_tools_enabled and compact
	_plan_title.theme_type_variation = &"H2Label" if compact else &"H1Label"
	_ride_title.theme_type_variation = &"H2Label" if compact else &"H1Label"
	_plan_steps.visible = not compact
	_ride_max_grade.visible = not compact
	_plan_source_label.visible = not compact
	_ride_kind.visible = not compact
	_apply_card_insets()
	_apply_card_buttons()
	# На compact рядом с надзаголовком стоит «Другая тренировка»: полный надзаголовок не влезает (U9).
	_set_overline(_plan_overline, "ui.home.plan.overline_short" if compact else "ui.home.plan.overline", _workout_button)
	_set_overline(_ride_overline, "ui.home.ride.overline", _route_button)
	if compact_changed:
		_refresh_profile_chip()
		_refresh_devices()
	_cards.custom_minimum_size.y = card_height_for(size.y, _available_card_height(mv + safe.y + safe.w), _card_content_min_height())


## Высота карточек: clamp(0.56·H, 300, 460), но не больше остатка окна и не меньше содержимого.
static func card_height_for(window_height: float, available: float, content_min: float) -> float:
	var target := clampf(window_height * CARD_HEIGHT_FRACTION, CARD_MIN_HEIGHT, CARD_MAX_HEIGHT)
	return maxf(minf(target, available), content_min)


func _available_card_height(vertical_margins: float) -> float:
	var gap := float(_column.get_theme_constant("separation"))
	var used: float = _bar.custom_minimum_size.y + gap
	if _tiles.visible:
		used += gap + _tiles.get_combined_minimum_size().y
	if _dev_row.visible:
		used += gap + _dev_row.get_combined_minimum_size().y
	return size.y - vertical_margins - used


func _card_content_min_height() -> float:
	var card_insets := _card_insets(_plan_card)
	var insets: float = card_insets.y + card_insets.w
	return maxf(_plan_content.get_combined_minimum_size().y, _ride_content.get_combined_minimum_size().y) + insets


## Кнопки карточек: regular — основная 200 lp и вторичная рядом; compact — основная на всю
## ширину, вторичная текстовой кнопкой справа от надзаголовка (`_set_overline`). Пустой план:
## «Из библиотеки» основной, «Импорт файла» вторичной в ряду кнопок.
func _apply_card_buttons() -> void:
	var has_plan: bool = _plan_workout != null
	_place_secondary(_workout_button, _plan_header, _plan_buttons, _compact and has_plan)
	_workout_button.theme_type_variation = &"PrimaryButton" if not has_plan else (&"GhostButton" if _compact else &"")
	_place_secondary(_route_button, _ride_header, _ride_buttons, _compact)
	_route_button.theme_type_variation = &"GhostButton" if _compact else &""
	var fill := Control.SIZE_EXPAND_FILL if _compact else Control.SIZE_FILL
	_start_button.size_flags_horizontal = fill
	_ride_button.size_flags_horizontal = fill
	_workout_button.size_flags_horizontal = fill if not has_plan else Control.SIZE_FILL
	_import_button.size_flags_horizontal = fill
	_workout_button.custom_minimum_size.x = 0.0 if has_plan or _compact else PRIMARY_MIN_WIDTH
	var start_w: float = 0.0 if _compact else PRIMARY_MIN_WIDTH
	_start_button.custom_minimum_size.x = start_w
	_ride_button.custom_minimum_size.x = start_w
	for button: Button in [_start_button, _ride_button, _workout_button]:
		var helper := TouchTarget.of(button)
		if helper != null:
			helper.floor_size.x = button.custom_minimum_size.x
			helper.apply()


## Надзаголовок карточки — ключ `key` на языке интерфейса. Если рядом в той же строке стоит
## текстовая кнопка `beside` и вместе они не помещаются (узкая карточка: телефон с вырезом,
## ru), надзаголовок делится по словам на две строки, а не обрезается (UIX-05 крит. 3); две
## строки Overline (32 lp) ниже кнопки (52 lp), высота карточки не меняется.
func _set_overline(label: Label, key: String, beside: Button) -> void:
	var text := tr(key)
	if _compact and beside.get_parent() == label.get_parent():
		var avail: float = card_inner_width() - float(label.get_parent().get_theme_constant("separation")) \
				- beside.get_combined_minimum_size().x
		text = split_to_fit(label, text, avail)
	label.text = text


## Ширина содержимого карточки сценария, lp (0 — раскладки ещё не было).
func card_inner_width() -> float:
	if _content_width <= 0.0:
		return 0.0
	var card_w: float = (_content_width - float(_cards.get_theme_constant("separation"))) * 0.5
	var insets := _card_insets(_plan_card)
	return card_w - insets.x - insets.z


## Текст подписи `label`, который не шире `width`: как есть, если помещается, иначе две
## строки — первая из стольких слов, сколько помещается.
static func split_to_fit(label: Label, text: String, width: float) -> String:
	if width <= 0.0 or _text_width(label, text) <= width:
		return text
	var words := text.split(" ")
	for i in range(words.size() - 1, 0, -1):
		var first := " ".join(words.slice(0, i))
		if _text_width(label, first) <= width:
			return first + "\n" + " ".join(words.slice(i))
	return text


static func _text_width(label: Label, text: String) -> float:
	var shown := text.to_upper() if label.uppercase else text
	return label.get_theme_font("font").get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1,
		label.get_theme_font_size("font_size")).x


static func _place_secondary(button: Button, header: HBoxContainer, row: HBoxContainer, in_header: bool) -> void:
	var target: HBoxContainer = header if in_header else row
	if button.get_parent() != target:
		button.reparent(target, false)


func _safe_margins() -> Vector4:
	var runtime := TouchTarget.default_runtime()
	return runtime.safe_margins() if runtime != null else Vector4.ZERO


func _on_scale_changed(_scale: float) -> void:
	_update_layout()


## Поля содержимого карточек — из стиля `ScenarioCard` (24 lp); на compact — `CardMargin`
## (16 lp): карточка ≈ 410×290 lp вмещает надзаголовок, название, превью, цифры и кнопку.
func _apply_card_insets() -> void:
	for pair in [[_plan_card, _plan_content], [_ride_card, _ride_content]]:
		var card: Button = pair[0]
		var content: Control = pair[1]
		var insets := _card_insets(card)
		content.offset_left = insets.x
		content.offset_top = insets.y
		content.offset_right = -insets.z
		content.offset_bottom = -insets.w


## Поля карточки: `Vector4(слева, сверху, справа, снизу)`.
func _card_insets(card: Button) -> Vector4:
	if _compact:
		return Vector4(
			float(get_theme_constant("margin_left", &"CardMargin")), float(get_theme_constant("margin_top", &"CardMargin")),
			float(get_theme_constant("margin_right", &"CardMargin")), float(get_theme_constant("margin_bottom", &"CardMargin")))
	var box := card.get_theme_stylebox("normal")
	if box == null:
		return Vector4.ZERO
	return Vector4(box.get_margin(SIDE_LEFT), box.get_margin(SIDE_TOP), box.get_margin(SIDE_RIGHT), box.get_margin(SIDE_BOTTOM))


## Модуляция, переводящая цвет `base` в `target` (покомпонентно; каналы > 1 допустимы).
static func tint_for(base: Color, target: Color) -> Color:
	return Color(
		target.r / maxf(base.r, 0.001), target.g / maxf(base.g, 0.001),
		target.b / maxf(base.b, 0.001), target.a / maxf(base.a, 0.001))


func _setup_icons() -> void:
	(%HistoryIconButton as Button).icon = UiIcons.icon("history")
	(%DevicesIconButton as Button).icon = UiIcons.icon("bluetooth")
	(%SettingsIconButton as Button).icon = UiIcons.icon("settings")
	_dev_menu_button.icon = UiIcons.icon("ellipsis")
	_empty_icon.texture = UiIcons.icon("zap")
	_empty_icon.self_modulate = UiTokens.TEXT_DISABLED


## Плитка: иконка и заголовок — сама кнопка `CardButton` (заголовок первой строкой текста,
## вторая строка пустая — под подпись), подпись `CaptionNumLabel` и шеврон — дочерние узлы.
func _setup_tiles() -> void:
	var tiles := {
		_history_button: ["history", "ui.home.history"],
		_devices_button: ["bluetooth", "ui.home.devices"],
		_settings_button: ["settings", "ui.home.settings"],
	}
	for tile: Button in tiles:
		var spec: Array = tiles[tile]
		tile.icon = UiIcons.icon(spec[0])
		tile.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_tile_keys[tile] = spec[1]
		var box := tile.get_theme_stylebox("normal")
		var pad_left: float = box.get_margin(SIDE_LEFT) if box != null else 16.0
		var pad_right: float = box.get_margin(SIDE_RIGHT) if box != null else 16.0
		var text_x: float = pad_left + float(tile.get_theme_constant("icon_max_width")) + float(tile.get_theme_constant("h_separation"))
		var caption := Label.new()
		caption.name = "Caption"
		caption.theme_type_variation = &"CaptionNumLabel"
		caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.clip_text = true
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		caption.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		caption.anchor_top = 0.5
		caption.anchor_bottom = 1.0
		caption.anchor_right = 1.0
		caption.offset_left = text_x
		caption.offset_top = 2.0
		caption.offset_right = -(pad_right + CHEVRON_SIZE + 8.0)
		caption.offset_bottom = -4.0
		tile.add_child(caption)
		_tile_captions[tile] = caption
		var chevron := TextureRect.new()
		chevron.name = "Chevron"
		chevron.texture = UiIcons.icon("chevron-right")
		chevron.self_modulate = UiTokens.TEXT_DISABLED
		chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chevron.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		chevron.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chevron.anchor_left = 1.0
		chevron.anchor_right = 1.0
		chevron.anchor_top = 0.5
		chevron.anchor_bottom = 0.5
		chevron.offset_left = -(pad_right + CHEVRON_SIZE)
		chevron.offset_right = -pad_right
		chevron.offset_top = -CHEVRON_SIZE * 0.5
		chevron.offset_bottom = CHEVRON_SIZE * 0.5
		tile.add_child(chevron)


# ---------------------------------------------------------------------------
# Отрисовка фишек
# ---------------------------------------------------------------------------

## Прозрачная заглушка иконки кнопки: держит место под точку или аватар, которые рисуются
## поверх (`draw`) векторно — чётко при любом масштабе.
static func _placeholder(side: float) -> Texture2D:
	var key := int(side)
	if not _placeholders.has(key):
		_placeholders[key] = ImageTexture.create_from_image(Image.create_empty(key, key, false, Image.FORMAT_RGBA8))
	return _placeholders[key]


func _lead_center(button: Button, side: float) -> Vector2:
	var box := button.get_theme_stylebox("normal")
	var left: float = box.get_margin(SIDE_LEFT) if box != null else 0.0
	return Vector2(left + side * 0.5, button.size.y * 0.5)


func _draw_chip_dot(chip: Button) -> void:
	var color: Color = chip.get_meta(&"dot_color", UiTokens.TEXT_DISABLED)
	chip.draw_circle(_lead_center(chip, DOT_DIAMETER), DOT_DIAMETER * 0.5, color, true, -1.0, true)


func _draw_profile_avatar() -> void:
	if _profile == null:
		return
	var center := _lead_center(_profile_chip, AVATAR_DIAMETER)
	_profile_chip.draw_circle(center, AVATAR_DIAMETER * 0.5, UiTokens.avatar_color(_profile.id), true, -1.0, true)
	var initial: String = _profile.name.strip_edges().left(1).to_upper()
	if initial.is_empty():
		return
	var font := _profile_chip.get_theme_font("font")
	var text_size := font.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, AVATAR_FONT_SIZE)
	var baseline := center + Vector2(-text_size.x * 0.5, (font.get_ascent(AVATAR_FONT_SIZE) - font.get_descent(AVATAR_FONT_SIZE)) * 0.5)
	_profile_chip.draw_string(font, baseline, initial, HORIZONTAL_ALIGNMENT_LEFT, -1, AVATAR_FONT_SIZE, UiTokens.TEXT)


# ---------------------------------------------------------------------------
# Действия
# ---------------------------------------------------------------------------

func _on_start_pressed() -> void:
	if _plan_workout != null:
		workout_start_requested.emit(_plan_workout)


func _on_import_pressed() -> void:
	import_requested.emit()


func _on_ride_pressed() -> void:
	free_ride_requested.emit(_route_id)


func _on_emulator_pressed() -> void:
	emulator_workout_requested.emit()


func _on_profile_chip_pressed() -> void:
	if _repo == null or _repo.count() < 2:
		return
	_popup_below(_profile_menu, _profile_chip)


func _on_profile_menu_id(id: int) -> void:
	if id == MENU_SWITCH_PROFILE:
		switch_profile()


func _on_dev_menu_pressed() -> void:
	_popup_below(_dev_menu, _dev_menu_button)


func _on_dev_menu_id(id: int) -> void:
	match id:
		MENU_DEV_EMULATOR:
			_on_emulator_pressed()
		MENU_DEV_SCREEN:
			_navigate(AppState.Screen.DEV)


func _popup_below(menu: PopupMenu, anchor: Control) -> void:
	var rect := anchor.get_global_rect()
	menu.popup(Rect2i(Vector2i(rect.position + Vector2(0.0, rect.size.y)), Vector2i.ZERO))


func _navigate(screen: int) -> void:
	if _app_state != null:
		_app_state.navigate(screen)
