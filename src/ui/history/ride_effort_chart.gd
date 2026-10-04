class_name RideEffortChart
extends HudChart
## Общий график мощности и пульса в карточке заезда (REQ-LOC-03, `docs/game/ui.md` п. 8.5 п. 2,
## U8 чек-листа п. 11) — тот же рисовальщик, что нижний график HUD (`HudChart`, `hud.md` п. 7).
##
## - Тренировка по плану: план целиком «призраком», как пройденная часть в HUD (сегменты по
##   зонам с линией по верху, рампы кусками, «свободно» со штриховкой, пропущенные шаги
##   заштрихованы — по журналу событий заезда), поверх — белая линия факта мощности и красная
##   линия пульса (без заливки) со своей шкалой справа; пунктир FTP и шкала времени.
## - Свободная езда (или заезд без сохранённого плана): серии на всю длительность заезда
##   (`EffortSeries` в режиме окна, окно = длительность), без цели плана (REQ-FRD-07 крит. 6);
##   мощность — площадь цветами зон заезда, как в HUD свободной езды.
## Мощность — сырые сэмплы без сглаживания 3 с (оно только для HUD, HUD-09 крит. 4; LOC-03
## крит. 2): прореживание по корзинам min/max сохраняет пики (спринт 1 с виден целиком).
## Фон — `inset` со скруглением; курсора нет. Легенда «мощность / пульс» — над полем справа.

## Место над полем под легенду, lp.
const LEGEND_HEIGHT: float = 22.0
## Окно серий свободной езды не короче минуты (шкала времени не вырождается).
const MIN_WINDOW_SEC: int = 60
const LEGEND_POWER_KEY: String = "ui.hud.chart.legend_power"
const LEGEND_HR_KEY: String = "ui.hud.chart.legend_hr"

var _has_plan: bool = false


func _init() -> void:
	super()
	background = Background.INSET
	fade_height = LEGEND_HEIGHT
	show_cursor = false
	show_fact = true
	show_hr_scale = true
	show_time_axis = true
	show_ftp_line = true
	show_ftp_label = true
	legend_power_key = LEGEND_POWER_KEY
	legend_hr_key = LEGEND_HR_KEY


## Показать заезд (null — пустой график).
func set_ride(ride: Ride) -> void:
	_has_plan = false
	if ride == null:
		set_plan(null, null)
		return
	var ftp: int = ride.ftp_w()
	var plan: Workout = null
	if not ride.is_free_ride() and not ride.workout.is_empty():
		plan = WorkoutSerializer.from_dict(ride.workout)
	if plan != null and plan.total_duration_sec() > 0:
		var intensity: float = float(ride.metadata.get("intensity", 1.0))
		var model := PlanChartModel.new(plan, ftp, intensity if intensity > 0.0 else 1.0, ride.power_zones())
		model.set_skip_log(ride.events)
		model.set_progress(float(model.total_sec()), -1, PlanChartModel.skipped_indices(ride.events))
		var series := EffortSeries.new(EffortSeries.MODE_PLAN, ftp, ride.max_hr())
		series.set_smoothing(1)
		series.sync_from_plan(ride.samples, model)
		_has_plan = true
		set_plan(model, series)
		return
	var window: int = maxi(ride.samples.size(), MIN_WINDOW_SEC)
	var free := EffortSeries.sliding_window(ftp, ride.max_hr(), window)
	free.set_smoothing(1)
	free.sync_from_stream(ride.samples)
	# Площадь мощности по зонам заезда — как график HUD свободной езды (`hud.md` п. 8).
	set_window(free, ftp, ride.power_zones())


## Нарисован ли план (цель) под фактом.
func has_plan() -> bool:
	return _has_plan


## Длительность оси времени графика, с: у плана — длительность плана, у свободной езды — окно
## (весь заезд). 0 — график пуст. По ней каденс в карточке рисуется в той же шкале времени.
func time_span_sec() -> float:
	var model := plan_model()
	if model != null:
		return float(model.total_sec())
	var series := effort_series()
	if series != null:
		var r: Vector2 = series.visible_range()
		return r.y - r.x
	return 0.0
