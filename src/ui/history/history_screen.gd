class_name HistoryScreen
extends Control
## Экран истории заездов (`AppState.Screen.HISTORY`; REQ-LOC-02 крит. 1, REQ-PRF-04 крит. 1,
## REQ-LOC-06, REQ-STR-05 крит. 2). Список заездов активного профиля через
## `RideRepository.list` (новые сверху): дата-время, название, длительность,
## дистанция, средняя/NP мощность, статус Strava. Выбор строки открывает
## карточку `RideDetail`; удаление возвращает к списку. Строки — ключи `ui.history.*`.

## Пользователь запросил выгрузку заезда в Strava (из карточки) с названием и описанием
## из её полей (REQ-STR-03 крит. 3; пустые — значения по умолчанию).
signal upload_requested(ride_id: String, ride_name: String, description: String)
## Заезд удалён из хранилища через карточку (REQ-LOC-06 крит. 1): владелец убирает
## элемент очереди Strava, если он был.
signal ride_deleted(ride_id: String)

var _rides: RideRepository = null
var _profiles: ProfileRepository = null
var _app_state: AppState = null
var _summaries: Array[RideSummary] = []
var _strava_linked: bool = false

@onready var _list_panel: Control = %ListPanel
@onready var _ride_list: ItemList = %RideList
@onready var _empty_label: Label = %EmptyLabel
@onready var _home_button: Button = %HomeButton
@onready var _detail: RideDetail = %Detail


func setup(rides: RideRepository, profiles: ProfileRepository, app_state: AppState) -> void:
	if _rides != null and _rides.rides_changed.is_connected(_on_rides_changed):
		_rides.rides_changed.disconnect(_on_rides_changed)
	_rides = rides
	_profiles = profiles
	_app_state = app_state
	if _rides != null:
		_rides.rides_changed.connect(_on_rides_changed)
	if is_node_ready():
		refresh()


func _ready() -> void:
	_ride_list.item_selected.connect(select_index)
	_home_button.pressed.connect(go_home)
	_detail.back_requested.connect(back_to_list)
	_detail.deleted.connect(_on_ride_deleted)
	_detail.upload_requested.connect(_on_detail_upload_requested)
	_detail.set_strava_linked(_strava_linked)
	if _rides != null:
		refresh()
	else:
		back_to_list()


## Перечитать список заездов активного профиля и показать его.
func refresh() -> void:
	if not is_node_ready():
		return
	_summaries = []
	var profile: Profile = _profiles.get_active() if _profiles != null else null
	if _rides != null and profile != null:
		_summaries = _rides.list(profile.id)
	_ride_list.clear()
	for s in _summaries:
		_ride_list.add_item(row_text(s))
	_empty_label.visible = _summaries.is_empty()
	_ride_list.visible = not _summaries.is_empty()
	# Если открытая карточка ещё в списке — перечитываем заезд (статус Strava
	# и т.п., REQ-STR-05 крит. 2) и оставляем её; иначе — к списку.
	var shown := _detail.ride()
	if shown != null and _find_index(shown.id) >= 0 and _detail.visible and _detail.reload():
		return
	back_to_list()


## Строка списка (REQ-LOC-02 крит. 1).
func row_text(s: RideSummary) -> String:
	var ride_name: String = s.name if not s.name.is_empty() else tr("ui.history.untitled")
	var flags: String = ""
	if s.in_progress:
		flags = tr("ui.history.row.in_progress")
	elif s.recovered:
		flags = tr("ui.history.detail.recovered")
	elif s.stopped_early:
		flags = tr("ui.history.detail.stopped_early")
	return tr("ui.history.row").format({
		"date": format_date_time(s.started_at_unix),
		"name": ride_name,
		"time": HudModel.format_elapsed(s.duration_sec),
		"distance": "%.1f" % (s.distance_m / 1000.0),
		"avg": RideDetail.number_text(s.avg_power_w),
		"np": RideDetail.number_text(s.normalized_power_w),
		"strava": tr(strava_status_key(s.strava_status)),
		"flags": flags,
	}).strip_edges()


func rows() -> Array[String]:
	var out: Array[String] = []
	for i in _ride_list.item_count:
		out.append(_ride_list.get_item_text(i))
	return out


func summaries() -> Array[RideSummary]:
	return _summaries


func row_count() -> int:
	return _summaries.size()


## Открыть карточку заезда по индексу строки.
func select_index(index: int) -> void:
	if index < 0 or index >= _summaries.size():
		return
	show_ride(_summaries[index].ride_id)


## Открыть карточку заезда по id. false — заезда нет.
func show_ride(ride_id: String) -> bool:
	if _rides == null:
		return false
	var ride := _rides.get_ride(ride_id)
	if ride == null:
		return false
	_detail.show_ride(ride, _rides)
	_detail.visible = true
	_list_panel.visible = false
	return true


func back_to_list() -> void:
	_detail.visible = false
	_list_panel.visible = true


func detail() -> RideDetail:
	return _detail


func is_detail_visible() -> bool:
	return _detail.visible


func is_empty_label_visible() -> bool:
	return _empty_label.visible


func set_strava_linked(linked: bool) -> void:
	_strava_linked = linked
	if is_node_ready():
		_detail.set_strava_linked(linked)


func go_home() -> void:
	if _app_state != null:
		_app_state.navigate(AppState.Screen.HOME)


## Дата и время старта в локальном времени: `ГГГГ-ММ-ДД ЧЧ:ММ`.
static func format_date_time(unix: int) -> String:
	var bias_sec: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix + bias_sec)
	return "%04d-%02d-%02d %02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"]]


## Ключ перевода статуса Strava (REQ-STR-05 крит. 1).
static func strava_status_key(status: String) -> String:
	return "ui.history.strava." + (status if Ride.UPLOAD_STATUSES.has(status) else Ride.UPLOAD_NONE)


func _find_index(ride_id: String) -> int:
	for i in _summaries.size():
		if _summaries[i].ride_id == ride_id:
			return i
	return -1


func _on_rides_changed(_profile_id: String) -> void:
	if visible and is_node_ready():
		refresh()


func _on_detail_upload_requested(ride_id: String, ride_name: String, description: String) -> void:
	upload_requested.emit(ride_id, ride_name, description)


func _on_ride_deleted(ride_id: String) -> void:
	back_to_list()
	refresh()
	ride_deleted.emit(ride_id)
