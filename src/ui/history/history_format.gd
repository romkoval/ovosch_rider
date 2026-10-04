class_name HistoryFormat
extends RefCounted
## Тексты и значения экранов истории (`docs/game/ui.md` п. 8.5; REQ-UIX-04 крит. 3, REQ-LOC-02
## крит. 1, REQ-FRD-07 крит. 6). Чистые функции без узлов: экран списка и карточка заезда
## берут отсюда даты, название заезда, значения колонок, метку режима и значок статуса Strava.
##
## - Дата строки — «3 окт, 21:12» / «Oct 3, 21:12», дата карточки — с годом, заголовок группы —
##   «Октябрь 2026» (в сцене `uppercase`). Время локальное, как у `HistoryScreen.format_date_time`.
## - Название: название плана; у свободной езды без названия — «Свободная езда — <трасса>»
##   на языке интерфейса (то же правило, что название выгрузки, REQ-FRD-07 крит. 7); у плана
##   без названия — «Тренировка».
## - Колонки строки (числа без единиц, единицы — в заголовке колонок): время, км, ср. Вт, NP,
##   набор (у свободной езды; у плана — «—»); на compact — время, км, ср. Вт.
## - Значок Strava: `check` (`accent`) — выгружено, `cloud-upload` (`text2`) — не выгружен,
##   `triangle-alert` (`warn`) — ошибка, `refresh-cw` (`text2`) — в очереди / обрабатывается,
##   `check` (`text2`) — дубликат. Подсказка — статус словами (`ui.history.strava.*`).
## Строки — ключи `ui.history.*` (`strings_menu_lists.csv`, прежние — `strings.csv`).

## Фильтры списка (`ui.md` п. 8.5: «Все / План / Свободная»).
enum Filter { ALL, PLAN, FREE }

const KEY_DATE_ROW: String = "ui.history.date.row"
const KEY_DATE_FULL: String = "ui.history.date.full"
const KEY_MONTH_HEADER: String = "ui.history.month_header"
const KEY_MONTH_PREFIX: String = "ui.history.month."
const KEY_MON_PREFIX: String = "ui.history.mon."
const KEY_UNTITLED: String = "ui.history.untitled"
const KEY_MODE_PLAN: String = "ui.history.mode.plan"
const KEY_MODE_SIM: String = "ui.history.mode.sim"
const KEY_FLAG_STOPPED_EARLY: String = "ui.history.flag.stopped_early"
const KEY_FLAG_RECOVERED: String = "ui.history.flag.recovered"
const KEY_FLAG_IN_PROGRESS: String = "ui.history.flag.in_progress"
## Заголовки колонок (единицы — здесь, а не в каждой строке; U4 чек-листа `ui.md` п. 11).
const COLUMN_KEYS: Array[String] = [
	"ui.history.col.time", "ui.history.col.km", "ui.history.col.avg", "ui.history.col.np",
	"ui.history.col.ascent",
]
## Ширины колонок, lp: время, км, ср. Вт, NP, набор (фиксированные — колонки ровные, UIX-04 крит. 3).
const COLUMN_WIDTHS: Array[float] = [80.0, 64.0, 64.0, 56.0, 80.0]
## На compact в строке три колонки: время, км, ср. Вт (`ui.md` п. 8.5).
const COMPACT_COLUMNS: int = 3
## Разделитель частей подписи.
const DOT: String = " · "

const ICON_DONE: String = "check"
const ICON_NONE: String = "cloud-upload"
const ICON_FAILED: String = "triangle-alert"
const ICON_PENDING: String = "refresh-cw"


## Локальные дата и время заезда (тот же сдвиг, что `HistoryScreen.format_date_time`).
static func local_datetime(unix: int) -> Dictionary:
	var bias_sec: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return Time.get_datetime_dict_from_unix_time(unix + bias_sec)


## «3 окт, 21:12» / «Oct 3, 21:12».
static func short_date(unix: int) -> String:
	return _date(unix, KEY_DATE_ROW)


## «3 окт 2026, 21:12» / «Oct 3, 2026, 21:12».
static func full_date(unix: int) -> String:
	return _date(unix, KEY_DATE_FULL)


## Ключ группы по месяцам: год × 100 + месяц (локальная дата).
static func month_key(unix: int) -> int:
	var d := local_datetime(unix)
	return int(d["year"]) * 100 + int(d["month"])


## Заголовок группы: «Октябрь 2026» (в сцене — заглавными, вариация `OverlineLabel`).
static func month_header(unix: int) -> String:
	var d := local_datetime(unix)
	return _tr(KEY_MONTH_HEADER).format({
		"month": _tr(KEY_MONTH_PREFIX + str(int(d["month"]))), "year": str(int(d["year"])),
	})


## Название заезда для списка и карточки (см. шапку класса).
static func ride_title(ride_name: String, is_free_ride: bool, route_id: String) -> String:
	if not ride_name.strip_edges().is_empty():
		return ride_name
	if is_free_ride:
		return StravaService.free_ride_default_name(route_id)
	return _tr(KEY_UNTITLED)


static func summary_title(s: RideSummary) -> String:
	return ride_title(s.name, s.is_free_ride(), s.route_id)


static func ride_display_title(ride: Ride) -> String:
	return ride_title(ride.name, ride.is_free_ride(), ride.route_id())


## Метка режима: «План» / «SIM» (в сцене — заглавными).
static func mode_text(is_free_ride: bool) -> String:
	return _tr(KEY_MODE_SIM if is_free_ride else KEY_MODE_PLAN)


## Вариация темы метки режима (`ui.md` п. 4, 5, 9.2): план — `OverlineAccent` (цвет `accent`),
## свободная езда — `OverlineSim` (цвет `sim`); цвет задаёт тема, без `self_modulate`.
static func mode_variation(is_free_ride: bool) -> StringName:
	return &"OverlineSim" if is_free_ride else &"OverlineAccent"


## Отметки заезда словами: не завершён / восстановлен / завершён досрочно (пусто — нет).
static func flags_text(in_progress: bool, recovered: bool, stopped_early: bool) -> String:
	if in_progress:
		return _tr(KEY_FLAG_IN_PROGRESS)
	if recovered:
		return _tr(KEY_FLAG_RECOVERED)
	if stopped_early:
		return _tr(KEY_FLAG_STOPPED_EARLY)
	return ""


## Надпись над названием в строке: дата и отметка.
static func row_overline(s: RideSummary) -> String:
	var flags := flags_text(s.in_progress, s.recovered, s.stopped_early)
	var date := short_date(s.started_at_unix)
	return date if flags.is_empty() else date + DOT + flags


## Целое или «—» для `RideSummary.NO_DATA`.
static func number_text(value: int) -> String:
	return HudModel.NO_DATA_TEXT if value == RideSummary.NO_DATA else str(value)


## Километры с одним знаком: «34.1».
static func km_text(distance_m: float) -> String:
	return "%.1f" % (maxf(distance_m, 0.0) / 1000.0)


## Длительность: «38:00», «1:02:15».
static func duration_text(sec: int) -> String:
	return HudModel.format_elapsed(maxi(sec, 0))


## Значения колонок строки: время, км, ср. Вт, NP, набор (свободная езда; у плана — «—»).
## `compact` — первые три.
static func columns(s: RideSummary, compact: bool = false) -> Array[String]:
	var out: Array[String] = [
		duration_text(s.duration_sec),
		km_text(s.distance_m),
		number_text(s.avg_power_w),
		number_text(s.normalized_power_w),
		RoutePreviewModel.ascent_value(s.ascent_m) if s.is_free_ride() else HudModel.NO_DATA_TEXT,
	]
	return out.slice(0, column_count(compact))


static func column_count(compact: bool) -> int:
	return COMPACT_COLUMNS if compact else COLUMN_WIDTHS.size()


static func column_widths(compact: bool) -> Array[float]:
	return COLUMN_WIDTHS.slice(0, column_count(compact))


## Подписи заголовков колонок на текущем языке.
static func column_titles(compact: bool) -> Array[String]:
	var out: Array[String] = []
	for i in column_count(compact):
		out.append(_tr(COLUMN_KEYS[i]))
	return out


## Значок статуса Strava: `{icon, color}` (см. шапку класса).
static func strava_icon(status: String) -> Dictionary:
	match status:
		Ride.UPLOAD_DONE:
			return {"icon": ICON_DONE, "color": UiTokens.ACCENT}
		Ride.UPLOAD_DUPLICATE:
			return {"icon": ICON_DONE, "color": UiTokens.TEXT2}
		Ride.UPLOAD_FAILED:
			return {"icon": ICON_FAILED, "color": UiTokens.WARN}
		Ride.UPLOAD_QUEUED, Ride.UPLOAD_UPLOADING:
			return {"icon": ICON_PENDING, "color": UiTokens.TEXT2}
	return {"icon": ICON_NONE, "color": UiTokens.TEXT2}


## Попадает ли заезд в фильтр списка.
static func matches(s: RideSummary, filter: Filter) -> bool:
	match filter:
		Filter.PLAN:
			return not s.is_free_ride()
		Filter.FREE:
			return s.is_free_ride()
	return true


static func _date(unix: int, key: String) -> String:
	var d := local_datetime(unix)
	return _tr(key).format({
		"day": str(int(d["day"])),
		"mon": _tr(KEY_MON_PREFIX + str(int(d["month"]))),
		"year": str(int(d["year"])),
		"time": "%02d:%02d" % [int(d["hour"]), int(d["minute"])],
	})


static func _tr(key: String) -> String:
	return String(TranslationServer.translate(key))
