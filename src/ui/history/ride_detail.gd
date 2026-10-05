class_name RideDetail
extends Control
## Карточка заезда (`docs/game/ui.md` п. 8.5): REQ-UIX-04 крит. 1, 3 (история), REQ-FRD-07
## крит. 6 (свободная езда: профиль высоты и набор, без цели плана), REQ-LOC-02 крит. 1,
## REQ-LOC-03, REQ-LOC-04 — сводка на экране, REQ-LOC-05 крит. 5, 6 — экспорт FIT через
## системный диалог сохранения, REQ-LOC-06 — удаление с подтверждением и статус Strava,
## REQ-STR-03 крит. 3, REQ-STR-04 крит. 5, REQ-STR-05 крит. 2, 3.
##
## Раскладка: `AppBar` — «назад» (к списку: сигнал `back_requested`, стек `AppState` не
## трогается) и название заезда; справа «⋯» — меню «Экспорт FIT» / «Удалить заезд». Под ним
## метка режима «ПЛАН»/«SIM» и дата с отметками; сетка плиток Stat Large (время, дистанция,
## ср. мощность, NP, макс., работа, ср. пульс, ср. каденс; у свободной езды — набор), regular —
## 4 в ряд, compact — 3; строка параметров заезда (FTP, вес, интенсивность, источник скорости;
## у плана — средняя цель, у свободной езды вместо неё — трасса и крутизна SIM). Общий график
## мощности и пульса (`RideEffortChart` — рисовальщик HUD: план призраком + белая линия факта +
## красная линия пульса со своей шкалой; у свободной езды мощность — площадь по зонам, как в HUD
## свободной езды); у свободной езды — профиль высоты по дистанции (`RideAltitudeChart`: круги
## подряд, граница круга пунктиром); каденс (`RideChart`, высота 96, шкала 40…120+, подписи 60
## и 90, поля и шкала времени — как у графика мощности; без данных каденса блока нет); время
## в зонах (полосы 12 lp с подписями долей); карточка «Strava»: статус, поля «Название»
## и «Описание» (REQ-STR-03 крит. 3: значения по умолчанию на языке интерфейса, доступны,
## пока заезд не выгружен), «Выгрузить в Strava» (без привязки недоступна с подсказкой).
## Заезд на эмуляторе (T-160): рядом с меткой режима — метка «ЭМУЛЯТОР» (Overline `text2`);
## «Выгрузить в Strava» сначала открывает диалог подтверждения «данные не настоящие» (опасная
## кнопка «Выгрузить» справа, фокус на «Отмена»; REQ-STR-04 крит. 5, UIX-01 крит. 8, 9) —
## `upload_requested` уходит только после подтверждения.
## Ошибка выгрузки — переведённая причина по коду (`Ride.upload.last_error_code`), ответ
## Strava — деталью после неё.
##
## Сводка текстом — `summary_text()` (прежние строки `ui.history.detail.*`), на экране — плитки.
## Строки — ключи `ui.history.*`.

const EXPORT_FILTERS: PackedStringArray = ["*.fit ; FIT"]
const STRAVA_ACTIVITY_URL: String = "https://www.strava.com/activities/{id}"
## Серия графика каденса (цвет — токен `ui.md` п. 4).
const CADENCE_COLOR := UiTokens.TEXT2
## Причина ошибки выгрузки по коду (`UploadResult.code` → `Ride.upload.last_error_code`).
const STRAVA_ERROR_KEYS: Dictionary = {
	ApiResult.CODE_NETWORK: "ui.history.strava.error.network",
	ApiResult.CODE_RATE_LIMITED: "ui.history.strava.error.rate_limited",
	ApiResult.CODE_REAUTH_REQUIRED: "ui.history.strava.error.reauth_required",
	ApiResult.CODE_AUTH_FAILED: "ui.history.strava.error.reauth_required",
	ApiResult.CODE_NOT_CONFIGURED: "ui.history.strava.error.not_configured",
	ApiResult.CODE_BAD_RESPONSE: "ui.history.strava.error.bad_response",
	ApiResult.CODE_STORAGE_FAILED: "ui.history.strava.error.storage_failed",
}
const STRAVA_ERROR_UNKNOWN_KEY: String = "ui.history.strava.error.unknown"
## Причина неудачного экспорта FIT по коду `Error` (вместо `error_string()` движка).
const EXPORT_ERROR_KEYS: Dictionary = {
	ERR_FILE_NO_PERMISSION: "ui.history.export.error.no_permission",
	ERR_FILE_BAD_PATH: "ui.history.export.error.bad_path",
	ERR_FILE_NOT_FOUND: "ui.history.export.error.bad_path",
	ERR_FILE_CANT_OPEN: "ui.history.export.error.cant_open",
	ERR_FILE_CANT_WRITE: "ui.history.export.error.cant_write",
	ERR_FILE_ALREADY_IN_USE: "ui.history.export.error.in_use",
}
const EXPORT_ERROR_UNKNOWN_KEY: String = "ui.history.export.error.unknown"

## Брейкпоинт compact и предел ширины контента, lp (`ui.md` п. 3).
const COMPACT_MAX_WIDTH: float = AppBar.COMPACT_MAX_WIDTH
const CONTENT_MAX_WIDTH: float = 1216.0
## Плиток в ряд: regular — 4, compact — 3 (`ui.md` п. 8.5).
const STAT_COLUMNS: int = 4
const STAT_COLUMNS_COMPACT: int = 3
## Высота плитки Stat Large (значение 38 + подпись 18 + 4), lp; разрыв рядов — `Grid16` сетки.
const STAT_TILE_HEIGHT: float = 60.0
## Высоты графиков, lp: regular / compact.
const EFFORT_HEIGHT: float = 240.0
const EFFORT_HEIGHT_COMPACT: float = 180.0
const ALTITUDE_HEIGHT: float = 160.0
const ALTITUDE_HEIGHT_COMPACT: float = 120.0
## Каденс — отдельный график высотой 96 (`ui.md` п. 8.5, решение ред. 2).
const CADENCE_HEIGHT: float = 96.0
const CADENCE_HEIGHT_COMPACT: float = 96.0
## Цветная метка доли зоны, lp (разрыв между подписями — вариация `Flow16` ряда подписей).
const ZONE_SWATCH: float = 12.0
## Меню «⋯»: отступ панели от правого края (поля AppBar), lp.
const MENU_RIGHT_INSET: float = 24.0
const KEY_ZONE_SHARE: String = "ui.plan.zones.share"
const KEY_MENU_MORE: String = "ui.history.menu.more"
const KEY_TARGET: String = "ui.history.detail.target"
const KEY_TRACK: String = "ui.history.detail.track"
const KEY_UPLOAD_EMULATOR_TEXT: String = "ui.history.upload_emulator.text"
const STAT_SCENE: PackedScene = preload("res://src/ui/common/stat_view.tscn")
const STAT_IDS: Array[String] = ["time", "distance", "avg_power", "np", "max_power", "work", "avg_hr", "avg_cadence", "ascent"]

signal back_requested()
## Заезд удалён из хранилища.
signal deleted(ride_id: String)
## Пользователь запросил выгрузку в Strava: название и описание — из полей карточки
## (REQ-STR-03 крит. 3; подключается очередью T-048/T-049).
signal upload_requested(ride_id: String, ride_name: String, description: String)

var _ride: Ride = null
var _repository: RideRepository = null
var _series: RideSeries = null
var _strava_linked: bool = false
var _delete_pending: bool = false
## Открыт диалог подтверждения выгрузки заезда на эмуляторе (T-160).
var _upload_confirm_pending: bool = false
var _compact: bool = false
## Значения по умолчанию, показанные в полях выгрузки: поле, которое пользователь не менял,
## обновляется при перерисовке (например, после смены языка); изменённое — сохраняется.
var _shown_default_name: String = ""
var _shown_default_description: String = ""
var _summary_text: String = ""
## Плитки сводки по `STAT_IDS`.
var _stats: Dictionary = {}
var _more_button: Button = null

@onready var _root: VBoxContainer = %Root
@onready var _app_bar: AppBar = %AppBar
@onready var _margin: MarginContainer = %Margin
@onready var _column: VBoxContainer = %Column
@onready var _mode_label: Label = %ModeLabel
@onready var _emulator_label: Label = %EmulatorLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _stats_grid: GridContainer = %StatsGrid
@onready var _meta_label: Label = %MetaLabel
@onready var _effort_chart: RideEffortChart = %EffortChart
@onready var _altitude_section: Control = %AltitudeSection
@onready var _altitude_chart: RideAltitudeChart = %AltitudeChart
@onready var _status_label: Label = %StatusLabel
@onready var _upload_name_edit: LineEdit = %UploadNameEdit
@onready var _upload_description_edit: TextEdit = %UploadDescriptionEdit
@onready var _power_zone_bar: ZoneBar = %PowerZoneBar
@onready var _power_zone_captions: HFlowContainer = %PowerZoneCaptions
@onready var _hr_zone_bar: ZoneBar = %HrZoneBar
@onready var _hr_zones_label: Label = %HrZonesLabel
@onready var _hr_zone_captions: HFlowContainer = %HrZoneCaptions
@onready var _cadence_section: Control = %CadenceSection
@onready var _cadence_chart: RideChart = %CadenceChart
@onready var _menu_layer: Control = %MenuLayer
@onready var _menu_panel: PanelContainer = %MenuPanel
@onready var _export_button: Button = %ExportButton
@onready var _delete_button: Button = %DeleteButton
@onready var _upload_button: Button = %UploadButton
@onready var _export_status_label: Label = %ExportStatusLabel
@onready var _export_dialog: FileDialog = %ExportDialog
@onready var _delete_dialog: ConfirmationDialog = %DeleteDialog
@onready var _upload_emulator_dialog: ConfirmationDialog = %UploadEmulatorDialog


func _ready() -> void:
	_app_bar.navigate_on_back = false
	_app_bar.back_pressed.connect(_on_back_pressed)
	_expose_back_button()
	_more_button = Button.new()
	_more_button.name = "MoreButton"
	_more_button.theme_type_variation = &"IconButton"
	_more_button.icon = UiIcons.icon("ellipsis")
	_more_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_more_button.tooltip_text = KEY_MENU_MORE
	_more_button.pressed.connect(toggle_menu)
	_app_bar.add_action(_more_button)
	TouchTarget.attach(_more_button, TouchTarget.Kind.UI)
	_export_button.icon = UiIcons.icon("upload")
	_delete_button.icon = UiIcons.icon("trash-2")
	for button: Button in [_export_button, _delete_button]:
		TouchTarget.attach(button, TouchTarget.Kind.UI)
	TouchTarget.attach(_upload_button, TouchTarget.Kind.BUTTON)
	TouchTarget.attach(_upload_name_edit, TouchTarget.Kind.UI)
	_menu_layer.gui_input.connect(_on_menu_layer_input)
	_build_stats()
	_export_dialog.filters = EXPORT_FILTERS
	_export_dialog.file_selected.connect(_on_export_file_selected)
	_export_button.pressed.connect(_on_export_pressed)
	_delete_button.pressed.connect(_on_delete_pressed)
	_delete_dialog.confirmed.connect(confirm_delete)
	_delete_dialog.canceled.connect(cancel_delete)
	_delete_dialog.get_ok_button().theme_type_variation = &"DangerButton"
	_upload_emulator_dialog.confirmed.connect(confirm_emulator_upload)
	_upload_emulator_dialog.canceled.connect(cancel_emulator_upload)
	_upload_emulator_dialog.get_ok_button().theme_type_variation = &"DangerButton"
	DialogLayout.attach_all(self)
	_upload_button.pressed.connect(request_upload)
	resized.connect(_update_content_width)
	_update_layout()
	_render()


func _enter_tree() -> void:
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_update_layout):
		viewport.size_changed.connect(_update_layout)
	var scale_source := TouchTarget.default_runtime()
	if scale_source != null and not scale_source.scale_changed.is_connected(_on_scale_changed):
		scale_source.scale_changed.connect(_on_scale_changed)


func _exit_tree() -> void:
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_update_layout):
		viewport.size_changed.disconnect(_update_layout)
	var scale_source := TouchTarget.default_runtime()
	if scale_source != null and scale_source.scale_changed.is_connected(_on_scale_changed):
		scale_source.scale_changed.disconnect(_on_scale_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_render()


## Показать заезд. `repository` нужен для удаления.
func show_ride(ride: Ride, repository: RideRepository) -> void:
	_ride = ride
	_repository = repository
	_series = RideSeries.from_samples(ride.samples) if ride != null else null
	_delete_pending = false
	_shown_default_name = ""
	_shown_default_description = ""
	if is_node_ready():
		cancel_emulator_upload()
		close_menu()
		_set_export_status("")
		_upload_name_edit.text = ""
		_upload_description_edit.text = ""
		(%Scroll as ScrollContainer).scroll_vertical = 0
		_render()


func ride() -> Ride:
	return _ride


## Перечитать открытый заезд из репозитория и перерисовать карточку (статус Strava
## и прочие метаданные; REQ-STR-05 крит. 2). false — заезда больше нет.
func reload() -> bool:
	if _ride == null or _repository == null:
		return false
	var fresh := _repository.get_ride(_ride.id)
	if fresh == null:
		return false
	_ride = fresh
	_series = RideSeries.from_samples(fresh.samples)
	_render()
	return true


func series() -> RideSeries:
	return _series


## Привязана ли Strava (кнопка выгрузки активна только с привязкой).
func set_strava_linked(linked: bool) -> void:
	_strava_linked = linked
	if is_node_ready():
		_render_buttons()


func app_bar() -> AppBar:
	return _app_bar


func effort_chart() -> RideEffortChart:
	return _effort_chart


func altitude_chart() -> RideAltitudeChart:
	return _altitude_chart


func is_altitude_visible() -> bool:
	return _altitude_section.visible


## Плитка сводки по id (`STAT_IDS`).
func stat(id: String) -> StatView:
	return _stats.get(id)


## Видимые плитки сводки по порядку.
func visible_stats() -> Array[StatView]:
	var out: Array[StatView] = []
	for id in STAT_IDS:
		var view: StatView = _stats[id]
		if view.visible:
			out.append(view)
	return out


func stats_columns() -> int:
	return _stats_grid.columns


func is_compact() -> bool:
	return _compact


# ---------------------------------------------------------------------------
# Меню «⋯» (экспорт FIT, удаление)
# ---------------------------------------------------------------------------

func more_button() -> Button:
	return _more_button


func is_menu_open() -> bool:
	return _menu_layer.visible


func toggle_menu() -> void:
	if is_menu_open():
		close_menu()
	else:
		open_menu()


func open_menu() -> void:
	if _ride == null:
		return
	_place_menu()
	_menu_layer.visible = true
	_export_button.grab_focus.call_deferred()


func close_menu() -> void:
	if _menu_layer == null or not _menu_layer.visible:
		return
	_menu_layer.visible = false
	if _more_button != null and _more_button.is_inside_tree() and is_visible_in_tree():
		_more_button.grab_focus()


## Панель меню — под AppBar у правого края (с учётом безопасной зоны).
func _place_menu() -> void:
	var min_size := _menu_panel.get_combined_minimum_size()
	_menu_panel.offset_top = _app_bar.get_global_rect().end.y - get_global_rect().position.y
	_menu_panel.offset_right = _root.offset_right - MENU_RIGHT_INSET
	_menu_panel.offset_left = _menu_panel.offset_right - min_size.x
	_menu_panel.offset_bottom = _menu_panel.offset_top + min_size.y


func _on_menu_layer_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	var mouse := event as InputEventMouseButton
	if (touch != null and touch.pressed) or (mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT):
		close_menu()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if is_menu_open() and event.is_action_pressed("ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()


func _on_export_pressed() -> void:
	close_menu()
	request_export()


func _on_delete_pressed() -> void:
	close_menu()
	request_delete()


# ---------------------------------------------------------------------------
# Экспорт FIT (REQ-LOC-05 крит. 5, 6)
# ---------------------------------------------------------------------------

## Имя файла по умолчанию: `<дата>_<название>.fit`. Дата — локальная, та же,
## что в списке и заголовке карточки (`HistoryScreen.format_date_time`).
func default_export_file_name() -> String:
	if _ride == null:
		return "ride.fit"
	var date := HistoryScreen.format_date_time(_ride.started_at_unix).substr(0, 10)
	return "%s_%s.fit" % [date, sanitize_file_name(_display_name())]


## Только буквы/цифры/`-`/`_`; пробелы → `_`; пусто → `ride`.
static func sanitize_file_name(text: String) -> String:
	var out := ""
	for ch in text.strip_edges():
		if ch == " ":
			out += "_"
		elif ch.is_valid_identifier() or ch.is_valid_int() or ch == "-" or ch == "_" or ch.unicode_at(0) > 127:
			out += ch
	return out if not out.is_empty() else "ride"


func request_export() -> void:
	if _ride == null:
		return
	_export_dialog.current_file = default_export_file_name()
	_export_dialog.popup_centered_ratio(0.8)


## Записать FIT по пути атомарно (`AtomicFile`: временный файл → rename). true — файл записан;
## при ошибке прежний файл по этому пути не тронут, причина — в статусе экспорта.
func export_to_path(path: String) -> bool:
	if _ride == null:
		return false
	var bytes := FitEncoder.encode(_ride)
	var err := AtomicFile.write_bytes(path, bytes)
	if err != OK:
		_set_export_status(tr("ui.history.export.failed").format({"reason": export_error_text(err)}))
		return false
	_set_export_status(tr("ui.history.export.done").format({"path": path}))
	return true


func _on_export_file_selected(path: String) -> void:
	export_to_path(path)


func export_status_text() -> String:
	return _export_status_label.text


## Переведённая причина неудачного экспорта по коду `Error`.
func export_error_text(err: Error) -> String:
	return tr(str(EXPORT_ERROR_KEYS.get(err, EXPORT_ERROR_UNKNOWN_KEY)))


func _set_export_status(text: String) -> void:
	_export_status_label.text = text
	_export_status_label.visible = not text.is_empty()


# ---------------------------------------------------------------------------
# Удаление (REQ-LOC-06 крит. 1, 2)
# ---------------------------------------------------------------------------

func request_delete() -> bool:
	if _ride == null:
		return false
	_delete_pending = true
	_delete_dialog.dialog_text = tr("ui.history.delete_confirm").format({"name": _display_name()})
	_delete_dialog.popup_centered()
	return true


## Подтверждение: заезд удаляется из хранилища; активность Strava не трогается.
func confirm_delete() -> void:
	_delete_pending = false
	if _ride == null or _repository == null:
		return
	var id := _ride.id
	if _repository.delete(id):
		_ride = null
		_series = null
		_render()
		deleted.emit(id)


func cancel_delete() -> void:
	_delete_pending = false
	if _delete_dialog.visible:
		_delete_dialog.hide()


func is_delete_pending() -> bool:
	return _delete_pending


# ---------------------------------------------------------------------------
# Strava (REQ-STR-05 крит. 2, 3)
# ---------------------------------------------------------------------------

## «Выгрузить в Strava». Заезд на эмуляторе — сначала диалог подтверждения (T-160).
func request_upload() -> void:
	if _ride == null or not _strava_linked or not _can_upload():
		return
	if _ride.is_emulator():
		_upload_confirm_pending = true
		_upload_emulator_dialog.dialog_text = tr(KEY_UPLOAD_EMULATOR_TEXT)
		_upload_emulator_dialog.popup_centered()
		return
	upload_requested.emit(_ride.id, upload_name(), upload_description())


## «Выгрузить» в диалоге подтверждения: заезд на эмуляторе уходит в очередь как обычно.
func confirm_emulator_upload() -> void:
	if not _upload_confirm_pending:
		return
	_upload_confirm_pending = false
	if _ride != null and _strava_linked and _can_upload():
		upload_requested.emit(_ride.id, upload_name(), upload_description())


## «Отмена», Esc или «назад» в диалоге подтверждения: ничего не выгружается.
func cancel_emulator_upload() -> void:
	_upload_confirm_pending = false
	if _upload_emulator_dialog.visible:
		_upload_emulator_dialog.hide()


func is_upload_confirmation_pending() -> bool:
	return _upload_confirm_pending


## Название для выгрузки из поля карточки (REQ-STR-03 крит. 3).
func upload_name() -> String:
	return _upload_name_edit.text.strip_edges()


## Описание для выгрузки из поля карточки (REQ-STR-03 крит. 3).
func upload_description() -> String:
	return _upload_description_edit.text.strip_edges()


func is_upload_fields_editable() -> bool:
	return _upload_name_edit.editable and _upload_description_edit.editable


## Переведённая причина ошибки выгрузки по коду; `detail` (ответ Strava) — после причины.
func strava_error_text(code: String, detail: String = "") -> String:
	var reason := tr(str(STRAVA_ERROR_KEYS.get(code, STRAVA_ERROR_UNKNOWN_KEY)))
	var extra := detail.strip_edges()
	return reason if extra.is_empty() else "%s (%s)" % [reason, extra]


func _can_upload() -> bool:
	return _ride != null and str(_ride.upload.get("strava_status", Ride.UPLOAD_NONE)) != Ride.UPLOAD_DONE


## Ссылка на активность Strava или "" (REQ-STR-05 крит. 3).
func strava_activity_url() -> String:
	if _ride == null:
		return ""
	var activity_id := str(_ride.upload.get("strava_activity_id", ""))
	if str(_ride.upload.get("strava_status", "")) != Ride.UPLOAD_DONE or activity_id.is_empty():
		return ""
	return STRAVA_ACTIVITY_URL.format({"id": activity_id})


# ---------------------------------------------------------------------------
# Тексты
# ---------------------------------------------------------------------------

## Заголовок карточки (название заезда в AppBar).
func title_text() -> String:
	return _app_bar.title_text()


## Сводка текстом (строки `ui.history.detail.*`): то же, что плитки и строка параметров.
func summary_text() -> String:
	return _summary_text


func status_text() -> String:
	return _status_label.text


## Подпись под заголовком: дата, отметки.
func subtitle_text() -> String:
	return _subtitle_label.text


func mode_text() -> String:
	return _mode_label.text


## Метка «Эмулятор» карточки ("" — заезд на станке, T-160).
func emulator_text() -> String:
	return _emulator_label.text if _emulator_label.visible else ""


func meta_text() -> String:
	return _meta_label.text


func is_upload_enabled() -> bool:
	return not _upload_button.disabled


func upload_tooltip() -> String:
	return _upload_button.tooltip_text


## Текст числа или «—» для `RideSummary.NO_DATA`.
static func number_text(value: int) -> String:
	return HistoryFormat.number_text(value)


# ---------------------------------------------------------------------------
# Отрисовка
# ---------------------------------------------------------------------------

func _display_name() -> String:
	if _ride == null:
		return ""
	return HistoryFormat.ride_display_title(_ride)


func _render() -> void:
	if not is_node_ready():
		return
	if _ride == null:
		_app_bar.set_title("", false)
		_mode_label.text = ""
		_emulator_label.text = ""
		_emulator_label.visible = false
		_subtitle_label.text = tr("ui.history.detail.no_ride")
		_summary_text = tr("ui.history.detail.no_ride")
		_meta_label.text = ""
		_status_label.text = ""
		for id in STAT_IDS:
			(_stats[id] as StatView).visible = false
		_power_zone_bar.set_zones(PackedInt32Array(), [])
		_hr_zone_bar.set_zones(PackedInt32Array(), [])
		_fill_zone_captions(_power_zone_captions, _power_zone_bar)
		_fill_zone_captions(_hr_zone_captions, _hr_zone_bar)
		_effort_chart.set_ride(null)
		_altitude_chart.clear()
		_altitude_section.visible = false
		_cadence_chart.clear()
		_cadence_section.visible = false
		_render_upload_fields()
		_render_buttons()
		return
	var s := _ride.summary
	var free_ride := _ride.is_free_ride()
	_app_bar.set_title(_display_name(), false)
	_mode_label.text = HistoryFormat.mode_text(free_ride)
	_mode_label.theme_type_variation = HistoryFormat.mode_variation(free_ride)
	_emulator_label.text = HistoryFormat.emulator_text(_ride.is_emulator())
	_emulator_label.visible = _ride.is_emulator()
	var flags := HistoryFormat.flags_text(_ride.is_in_progress(), _ride.is_recovered(), _ride.stopped_early())
	var subtitle := HistoryFormat.full_date(_ride.started_at_unix)
	_subtitle_label.text = subtitle if flags.is_empty() else subtitle + HistoryFormat.DOT + flags
	_render_stats(s, free_ride)
	_render_summary_text(s)
	_render_status()
	_render_zones(s)
	_effort_chart.set_ride(_ride)
	_altitude_section.visible = free_ride
	if free_ride:
		_altitude_chart.set_profile(RideSeries.altitude_by_distance(_ride.samples), _lap_length_m(_ride.route_id()))
	else:
		_altitude_chart.clear()
	# Каденс — в той же шкале времени и с теми же полями, что общий график мощности: минуты
	# совпадают по вертикали (`ui.md` п. 8.5). Без данных каденса блока нет.
	var span: float = _effort_chart.time_span_sec()
	if span <= 0.0:
		span = float(maxi(_series.duration_sec, 1))
	_cadence_chart.field_left = _effort_chart.inset_left
	_cadence_chart.field_right = _effort_chart.inset_right
	_cadence_chart.set_series(_series.time_sec, _series.values(RideSeries.CADENCE), CADENCE_COLOR, span)
	_cadence_section.visible = _cadence_chart.point_count() > 0
	_render_upload_fields()
	_render_buttons()


## Плитки Stat Large (`ui.md` п. 8.5 п. 1); набор — только у свободной езды.
func _render_stats(s: RideSummary, free_ride: bool) -> void:
	_set_stat("time", HistoryFormat.duration_text(s.duration_sec), "")
	_set_stat("distance", HistoryFormat.km_text(s.distance_m), "ui.menu.unit.km")
	_set_stat("avg_power", number_text(s.avg_power_w), "ui.menu.unit.w")
	_set_stat("np", number_text(s.normalized_power_w), "ui.menu.unit.w")
	_set_stat("max_power", number_text(s.max_power_w), "ui.menu.unit.w")
	_set_stat("work", "%.0f" % s.work_kj, "ui.menu.unit.kj")
	_set_stat("avg_hr", number_text(s.avg_hr), "ui.menu.unit.bpm")
	_set_stat("avg_cadence", number_text(s.avg_cadence), "ui.menu.unit.rpm")
	_set_stat("ascent", RoutePreviewModel.ascent_value(s.ascent_m), "ui.menu.unit.m")
	for id in STAT_IDS:
		(_stats[id] as StatView).visible = id != "ascent" or free_ride


func _set_stat(id: String, value: String, unit_key: String) -> void:
	var view: StatView = _stats[id]
	view.value = value
	view.unit = unit_key


## Строка параметров на экране и сводка текстом (`summary_text`).
func _render_summary_text(s: RideSummary) -> void:
	var lines: Array[String] = []
	lines.append(tr("ui.history.detail.duration").format({
		"time": HudModel.format_elapsed(s.duration_sec),
		"distance": "%.1f" % (s.distance_m / 1000.0),
		"paused": HudModel.format_elapsed(roundi(_ride.paused_total_sec())),
	}))
	lines.append(tr("ui.history.detail.power").format({
		"avg": number_text(s.avg_power_w), "np": number_text(s.normalized_power_w),
		"max": number_text(s.max_power_w), "work": "%.0f" % s.work_kj,
	}))
	lines.append(tr("ui.history.detail.hr").format({"avg": number_text(s.avg_hr), "max": number_text(s.max_hr)}))
	lines.append(tr("ui.history.detail.cadence").format({"avg": number_text(s.avg_cadence), "max": number_text(s.max_cadence)}))
	var meta: Array[String] = [tr("ui.history.detail.meta").format({
		"ftp": _ride.ftp_w(), "weight": "%.1f" % float(_ride.metadata.get("weight_kg", 0.0)),
		"intensity": roundi(float(_ride.metadata.get("intensity", 1.0)) * 100.0),
		"speed_source": tr("ui.history.speed_source.trainer") if _ride.speed_source() == SampleStream.SPEED_SOURCE_TRAINER else tr("ui.history.speed_source.model"),
	})]
	var target := tr(KEY_TARGET).format({"target": number_text(s.avg_target_w)})
	if _ride.is_free_ride():
		# Свободная езда: цели плана нет — в строке параметров её не показываем (`ui.md` п. 8.5,
		# решение ред. 2), в сводке текстом поле остаётся «—» (REQ-FRD-07 крит. 6).
		lines.append_array(meta)
		lines.append(target)
		meta.append(tr(KEY_TRACK).format({
			"track": StravaService.track_display_name(_ride.route_id()),
			"pct": roundi(_ride.sim_steepness_start_pct()),
		}))
		lines.append(meta[-1])
	else:
		meta.append(target)
		lines.append_array(meta)
	_summary_text = "\n".join(lines)
	_meta_label.text = HistoryFormat.DOT.join(meta)


func _render_status() -> void:
	var status := str(_ride.upload.get("strava_status", Ride.UPLOAD_NONE))
	var status_text := tr(HistoryScreen.strava_status_key(status))
	match status:
		Ride.UPLOAD_DONE:
			status_text += " " + strava_activity_url()
		Ride.UPLOAD_FAILED:
			status_text += ": " + strava_error_text(
				str(_ride.upload.get(RideRepositoryUploadStore.KEY_ERROR_CODE, "")),
				str(_ride.upload.get(RideRepositoryUploadStore.KEY_ERROR_DETAIL, "")))
	_status_label.text = tr("ui.history.detail.strava").format({"status": status_text})


func _render_zones(s: RideSummary) -> void:
	var power_tokens: Array[String] = []
	for i in s.time_in_power_zones.size():
		power_tokens.append(ZonePalette.power_token(i + 1))
	_power_zone_bar.set_zones(s.time_in_power_zones, power_tokens)
	var hr_tokens: Array[String] = []
	for i in s.time_in_hr_zones.size():
		hr_tokens.append(ZonePalette.hr_token(i + 1))
	_hr_zone_bar.set_zones(s.time_in_hr_zones, hr_tokens)
	var has_hr_zones: bool = s.time_in_hr_zones.size() > 0
	_hr_zones_label.visible = has_hr_zones
	_hr_zone_bar.visible = has_hr_zones
	_fill_zone_captions(_power_zone_captions, _power_zone_bar)
	_fill_zone_captions(_hr_zone_captions, _hr_zone_bar)
	_hr_zone_captions.visible = has_hr_zones


## Подписи долей зон под полосой: цветная метка и «Z2 35 %».
func _fill_zone_captions(flow: HFlowContainer, bar: ZoneBar) -> void:
	for child in flow.get_children():
		flow.remove_child(child)
		child.free()
	for share in bar.shares():
		var item := HBoxContainer.new()
		item.theme_type_variation = &"Row8"
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var swatch := ColorRect.new()
		swatch.color = ZonePalette.color(str(share["token"]))
		swatch.custom_minimum_size = Vector2(ZONE_SWATCH, ZONE_SWATCH)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(swatch)
		var label := Label.new()
		label.theme_type_variation = &"CaptionNumLabel"
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.text = tr(KEY_ZONE_SHARE).format({"zone": share["zone"], "pct": share["pct"]})
		item.add_child(label)
		flow.add_child(item)
	flow.visible = flow.get_child_count() > 0


## Поля названия/описания: значения по умолчанию на текущем языке (REQ-STR-03 крит. 1, 2);
## изменённое пользователем поле не перезаписывается.
func _render_upload_fields() -> void:
	if _ride == null:
		_upload_name_edit.text = ""
		_upload_description_edit.text = ""
		_shown_default_name = ""
		_shown_default_description = ""
		return
	var default_name := StravaService.compose_default_name(_ride, tr(StravaService.KEY_DEFAULT_NAME))
	var default_description := StravaService.compose_default_description(_ride, tr(StravaService.KEY_DEFAULT_DESCRIPTION))
	if _upload_name_edit.text == _shown_default_name:
		_upload_name_edit.text = default_name
	if _upload_description_edit.text == _shown_default_description:
		_upload_description_edit.text = default_description
	_shown_default_name = default_name
	_shown_default_description = default_description


func _render_buttons() -> void:
	var has_ride: bool = _ride != null
	_export_button.disabled = not has_ride
	_delete_button.disabled = not has_ride
	if _more_button != null:
		_more_button.disabled = not has_ride
	var can_upload: bool = has_ride and _strava_linked and _can_upload()
	_upload_button.disabled = not can_upload
	# Поля доступны, пока заезд не выгружен (REQ-STR-03 крит. 3).
	var editable: bool = has_ride and _can_upload()
	_upload_name_edit.editable = editable
	_upload_description_edit.editable = editable
	if not has_ride:
		_upload_button.tooltip_text = ""
	elif not _strava_linked:
		_upload_button.tooltip_text = tr("ui.history.strava_not_linked")
	elif not _can_upload():
		_upload_button.tooltip_text = tr("ui.history.strava.done")
	else:
		_upload_button.tooltip_text = ""


## Плитки сводки (Stat Large) в сетке, по `STAT_IDS`.
func _build_stats() -> void:
	for id in STAT_IDS:
		var view: StatView = STAT_SCENE.instantiate()
		view.large = true
		view.caption = "ui.history.stat." + id
		view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		view.custom_minimum_size.y = STAT_TILE_HEIGHT
		_stats_grid.add_child(view)
		_stats[id] = view


## Длина круга трассы, м (0 — трассы нет в каталоге: границы кругов не рисуются).
static func _lap_length_m(route_id: String) -> float:
	if not RouteCatalog.has_route(route_id):
		return 0.0
	var route := RouteCatalog.get_route(route_id)
	return route.profile.length_m() if route != null and route.profile != null else 0.0


## Кнопка «назад» AppBar доступна карточке как `%BackButton` (прежнее имя кнопки «К списку»).
func _expose_back_button() -> void:
	var back_button := _app_bar.back_button()
	back_button.name = "BackButton"
	back_button.owner = self
	back_button.unique_name_in_owner = true


func _on_back_pressed(_handled: bool) -> void:
	close_menu()
	back_requested.emit()


func _on_scale_changed(_scale: float) -> void:
	_update_layout()


## Раскладка по ширине холста: compact — 3 плитки в ряд, ниже графики, плотные поля.
## Отступы корня — безопасная зона (`UiScale.safe_margins`, UIX-05 крит. 2).
func _update_layout() -> void:
	if not is_node_ready() or not is_inside_tree():
		return
	var safe := Vector4.ZERO
	var scale_source := TouchTarget.default_runtime()
	if scale_source != null:
		safe = scale_source.safe_margins()
	_root.offset_left = safe.x
	_root.offset_top = safe.y
	_root.offset_right = -safe.z
	_root.offset_bottom = -safe.w
	_compact = get_viewport_rect().size.x < COMPACT_MAX_WIDTH
	_margin.theme_type_variation = &"ScreenMarginCompact" if _compact else &"ScreenMargin"
	_stats_grid.columns = STAT_COLUMNS_COMPACT if _compact else STAT_COLUMNS
	_effort_chart.custom_minimum_size.y = EFFORT_HEIGHT_COMPACT if _compact else EFFORT_HEIGHT
	_altitude_chart.custom_minimum_size.y = ALTITUDE_HEIGHT_COMPACT if _compact else ALTITUDE_HEIGHT
	_cadence_chart.custom_minimum_size.y = CADENCE_HEIGHT_COMPACT if _compact else CADENCE_HEIGHT
	_update_content_width()


## Ширина контента — не больше `CONTENT_MAX_WIDTH`, по центру (от размера экрана, а не содержимого).
func _update_content_width() -> void:
	if not is_node_ready():
		return
	var inner: float = size.x + _root.offset_right - _root.offset_left \
			- float(_margin.get_theme_constant("margin_left") + _margin.get_theme_constant("margin_right"))
	_column.custom_minimum_size.x = clampf(inner, 0.0, CONTENT_MAX_WIDTH)
