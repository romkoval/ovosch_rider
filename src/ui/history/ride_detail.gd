class_name RideDetail
extends Control
## Карточка заезда (REQ-LOC-02 крит. 1, REQ-LOC-03, REQ-LOC-04 — сводка на экране,
## REQ-LOC-05 крит. 5, 6 — экспорт FIT через системный диалог сохранения,
## REQ-LOC-06 — удаление с подтверждением и статус Strava, REQ-STR-05 крит. 2, 3).
##
## Показывает все поля `RideSummary`, полосы времени в зонах (`ZoneBar`), три
## графика (`RideChart` по `RideSeries`: мощность с целью плана, пульс, каденс),
## кнопки «Экспорт FIT» (`FileDialog` → `FitEncoder.encode` → файл), «Удалить»
## (подтверждение → `RideRepository.delete`), «Выгрузить в Strava» (сигнал
## `upload_requested`; без привязки недоступна с подсказкой). Перед выгрузкой название и
## описание можно изменить в полях карточки (REQ-STR-03 крит. 3): они заполнены значениями
## по умолчанию на текущем языке и доступны, пока заезд не выгружен. Ошибка выгрузки
## показывается переведённой причиной по коду (`Ride.upload.last_error_code`), ответ Strava —
## только деталью после неё. Строки — ключи `ui.history.*`.

const EXPORT_FILTERS: PackedStringArray = ["*.fit ; FIT"]
const STRAVA_ACTIVITY_URL: String = "https://www.strava.com/activities/{id}"
const POWER_COLOR := Color(0.95, 0.75, 0.25)
const HR_COLOR := Color(0.90, 0.30, 0.30)
const CADENCE_COLOR := Color(0.35, 0.65, 0.95)
## Причина ошибки выгрузки по коду (`UploadResult.code` → `Ride.upload.last_error_code`).
const STRAVA_ERROR_KEYS: Dictionary = {
	ApiResult.CODE_NETWORK: "ui.history.strava.error.network",
	ApiResult.CODE_RATE_LIMITED: "ui.history.strava.error.rate_limited",
	ApiResult.CODE_REAUTH_REQUIRED: "ui.history.strava.error.reauth_required",
	ApiResult.CODE_AUTH_FAILED: "ui.history.strava.error.reauth_required",
	ApiResult.CODE_NOT_CONFIGURED: "ui.history.strava.error.not_configured",
	ApiResult.CODE_BAD_RESPONSE: "ui.history.strava.error.bad_response",
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
## Значения по умолчанию, показанные в полях выгрузки: поле, которое пользователь не менял,
## обновляется при перерисовке (например, после смены языка); изменённое — сохраняется.
var _shown_default_name: String = ""
var _shown_default_description: String = ""

@onready var _title_label: Label = %TitleLabel
@onready var _summary_label: Label = %SummaryLabel
@onready var _status_label: Label = %StatusLabel
@onready var _upload_name_edit: LineEdit = %UploadNameEdit
@onready var _upload_description_edit: TextEdit = %UploadDescriptionEdit
@onready var _power_zone_bar: ZoneBar = %PowerZoneBar
@onready var _hr_zone_bar: ZoneBar = %HrZoneBar
@onready var _hr_zones_label: Label = %HrZonesLabel
@onready var _power_chart: RideChart = %PowerChart
@onready var _hr_chart: RideChart = %HrChart
@onready var _cadence_chart: RideChart = %CadenceChart
@onready var _export_button: Button = %ExportButton
@onready var _delete_button: Button = %DeleteButton
@onready var _upload_button: Button = %UploadButton
@onready var _back_button: Button = %BackButton
@onready var _export_status_label: Label = %ExportStatusLabel
@onready var _export_dialog: FileDialog = %ExportDialog
@onready var _delete_dialog: ConfirmationDialog = %DeleteDialog


func _ready() -> void:
	_export_dialog.filters = EXPORT_FILTERS
	_export_dialog.file_selected.connect(_on_export_file_selected)
	_export_button.pressed.connect(request_export)
	_delete_button.pressed.connect(request_delete)
	_delete_dialog.confirmed.connect(confirm_delete)
	_delete_dialog.canceled.connect(cancel_delete)
	_upload_button.pressed.connect(request_upload)
	_back_button.pressed.connect(func() -> void: back_requested.emit())
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
		_export_status_label.text = ""
		_upload_name_edit.text = ""
		_upload_description_edit.text = ""
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


# ---------------------------------------------------------------------------
# Экспорт FIT (REQ-LOC-05 крит. 5, 6)
# ---------------------------------------------------------------------------

## Имя файла по умолчанию: `<дата>_<название>.fit`. Дата — локальная, та же,
## что в списке и заголовке карточки (`HistoryScreen.format_date_time`).
func default_export_file_name() -> String:
	if _ride == null:
		return "ride.fit"
	var date := HistoryScreen.format_date_time(_ride.started_at_unix).substr(0, 10)
	var raw_name: String = _ride.name if not _ride.name.is_empty() else tr("ui.history.untitled")
	return "%s_%s.fit" % [date, sanitize_file_name(raw_name)]


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


## Записать FIT по пути. true — файл записан.
func export_to_path(path: String) -> bool:
	if _ride == null:
		return false
	var bytes := FitEncoder.encode(_ride)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_export_status_label.text = tr("ui.history.export.failed").format({"reason": export_error_text(FileAccess.get_open_error())})
		return false
	file.store_buffer(bytes)
	file.close()
	_export_status_label.text = tr("ui.history.export.done").format({"path": path})
	return true


func _on_export_file_selected(path: String) -> void:
	export_to_path(path)


func export_status_text() -> String:
	return _export_status_label.text


## Переведённая причина неудачного экспорта по коду `Error`.
func export_error_text(err: Error) -> String:
	return tr(str(EXPORT_ERROR_KEYS.get(err, EXPORT_ERROR_UNKNOWN_KEY)))


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

func request_upload() -> void:
	if _ride != null and _strava_linked and _can_upload():
		upload_requested.emit(_ride.id, upload_name(), upload_description())


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

func title_text() -> String:
	return _title_label.text


func summary_text() -> String:
	return _summary_label.text


func status_text() -> String:
	return _status_label.text


func is_upload_enabled() -> bool:
	return not _upload_button.disabled


func upload_tooltip() -> String:
	return _upload_button.tooltip_text


## Текст числа или «—» для `RideSummary.NO_DATA`.
static func number_text(value: int) -> String:
	return HudModel.NO_DATA_TEXT if value == RideSummary.NO_DATA else str(value)


# ---------------------------------------------------------------------------
# Отрисовка
# ---------------------------------------------------------------------------

func _display_name() -> String:
	if _ride == null:
		return ""
	return _ride.name if not _ride.name.is_empty() else tr("ui.history.untitled")


func _render() -> void:
	if not is_node_ready():
		return
	if _ride == null:
		_title_label.text = ""
		_summary_label.text = tr("ui.history.detail.no_ride")
		_status_label.text = ""
		_power_zone_bar.set_zones(PackedInt32Array(), [])
		_hr_zone_bar.set_zones(PackedInt32Array(), [])
		_power_chart.clear()
		_hr_chart.clear()
		_cadence_chart.clear()
		_render_upload_fields()
		_render_buttons()
		return
	var s := _ride.summary
	var flags: Array[String] = []
	if _ride.stopped_early():
		flags.append(tr("ui.history.detail.stopped_early"))
	if _ride.is_recovered():
		flags.append(tr("ui.history.detail.recovered"))
	_title_label.text = "%s · %s %s" % [HistoryScreen.format_date_time(_ride.started_at_unix), _display_name(), " ".join(flags)]
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
	lines.append(tr("ui.history.detail.meta").format({
		"ftp": _ride.ftp_w(), "weight": "%.1f" % float(_ride.metadata.get("weight_kg", 0.0)),
		"intensity": roundi(float(_ride.metadata.get("intensity", 1.0)) * 100.0),
		"speed_source": tr("ui.history.speed_source.trainer") if _ride.speed_source() == SampleStream.SPEED_SOURCE_TRAINER else tr("ui.history.speed_source.model"),
	}))
	_summary_label.text = "\n".join(lines)
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
	var power_tokens: Array[String] = []
	for i in s.time_in_power_zones.size():
		power_tokens.append(ZonePalette.power_token(i + 1))
	_power_zone_bar.set_zones(s.time_in_power_zones, power_tokens)
	var hr_tokens: Array[String] = []
	for i in s.time_in_hr_zones.size():
		hr_tokens.append(ZonePalette.hr_token(i + 1))
	_hr_zone_bar.set_zones(s.time_in_hr_zones, hr_tokens)
	_hr_zones_label.visible = s.time_in_hr_zones.size() > 0
	_hr_zone_bar.visible = s.time_in_hr_zones.size() > 0
	var duration := float(maxi(_series.duration_sec, 1))
	_power_chart.set_series(_series.time_sec, _series.values(RideSeries.POWER), POWER_COLOR, duration, _series.values(RideSeries.TARGET))
	_hr_chart.set_series(_series.time_sec, _series.values(RideSeries.HEART_RATE), HR_COLOR, duration)
	_cadence_chart.set_series(_series.time_sec, _series.values(RideSeries.CADENCE), CADENCE_COLOR, duration)
	_render_upload_fields()
	_render_buttons()


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
