class_name WorkoutChart
extends PlanPreview
## Крупное превью плана на экране выбора тренировки — `PlanPreview` с `detailed = true`
## (шкала времени и пунктир FTP; рисовальщик и модель — общие с графиком HUD, REQ-UIX-03
## крит. 1, 4). Своей отрисовки у класса больше нет (T-082).
##
## Класс оставлен ради совместимости с приёмкой T-040 (`tests/integration/test_plan_acceptance.gd`,
## `test_plan_screen.gd`): тесты обращаются к `PlanScreen.chart()` как к `WorkoutChart` и к
## статическому `WorkoutChart.segment_color()`. Данные для них — прежние (REQ-INT-05 крит. 1–3):
## точки `Workout.power_points()`, сегменты `Workout.segments()` (модель HUD-07.1, зоны профиля),
## подписи оси времени в минутах. После перевода тестов на `PlanPreview` (решение tester) класс
## удаляется, а экран использует `PlanPreview` напрямую.

var _points := PackedVector2Array()
var _segments: Array[Dictionary] = []


func _init() -> void:
	super()
	detailed = true


## План с FTP, множителем и зонами профиля (null — пустое превью).
func set_workout(workout: Workout, ftp_w: int, intensity: float = 1.0, zones: PowerZones = null) -> void:
	if workout == null:
		_points = PackedVector2Array()
		_segments = []
	else:
		_points = workout.power_points(ftp_w, intensity)
		_segments = workout.segments(ftp_w, intensity, zones)
	super.set_workout(workout, ftp_w, intensity, zones)


## Точки (t, Вт) целевой мощности (REQ-INT-05 крит. 1, 2).
func points() -> PackedVector2Array:
	return _points


## Сегменты плана `Workout.segments()`: начало, длительность, цели начала и конца, зона.
func segments() -> Array[Dictionary]:
	return _segments


## Длительность плана, с.
func total_sec() -> int:
	var model := plan_model()
	return model.total_sec() if model != null else 0


## Подписи шкалы времени в минутах — те же, что рисует превью (`PlanChartModel.time_labels`).
func axis_minutes() -> Array[int]:
	var out: Array[int] = []
	var model := plan_model()
	if model == null:
		return out
	for label in model.time_labels():
		out.append(int(label["sec"]) / 60)
	return out


## Цвет сегмента по зоне (`ZonePalette`, как в HUD).
static func segment_color(segment: Dictionary) -> Color:
	return ZonePalette.color(ZonePalette.power_token(int(segment.get("zone", 0))))
