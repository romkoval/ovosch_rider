class_name PlanPreview
extends HudChart
## Превью плана тренировки в меню (REQ-UIX-03 крит. 1, 4; `docs/game/ui.md` п. 5 «PlanThumb»).
##
## Тот же рисовальщик, что нижний график HUD (`HudChart`), и та же модель (`PlanChartModel`):
## сегменты по зонам, рампы кусками по зонам, «свободно» со штриховкой, зазоры 1 lp,
## скруглённые верхние углы. Фон — `inset` со скруглением 12 и полями 12; миниатюра в строке
## списка (`row_thumb`) — 128×52, поля 6, скругление 10.
## - Миниатюра (`detailed = false`, по умолчанию): без факта, курсора и подписей (UIX-03.4).
## - Крупное превью (`detailed = true`): плюс шкала времени и пунктир FTP с подписью (UIX-03.1).
## Крупное превью экрана выбора тренировки — этот же класс (`PlanScreen.chart()`).

## Поля превью (`ui.md` п. 5): 12 lp.
const PREVIEW_PADDING: float = 12.0
## Миниатюра в строке списка (`ui.md` п. 6, 8.3, решение ред. 2): 128×52, поля 6, радиус 10 —
## видимая часть графика ≈ 116×40, короткие шаги и рампы различимы.
const ROW_THUMB_SIZE: Vector2 = Vector2(128, 52)
const ROW_THUMB_PADDING: float = 6.0
const ROW_THUMB_RADIUS: float = 10.0
## Крупное превью: слева место под подпись FTP, снизу — под шкалу времени.
const DETAILED_INSET_LEFT: float = 40.0
const DETAILED_INSET_BOTTOM: float = 30.0

## Крупное превью со шкалой времени и пунктиром FTP.
@export var detailed: bool = false:
	set(value):
		detailed = value
		_apply_preset()
## Миниатюра в строке списка: размер `ROW_THUMB_SIZE`, поля 6, радиус 10.
@export var row_thumb: bool = false:
	set(value):
		row_thumb = value
		_apply_preset()


func _init() -> void:
	super()
	_apply_preset()


## План с FTP, множителем и зонами профиля — как у сессии (null — пустое превью).
func set_workout(workout: Workout, ftp_w: int, intensity: float = 1.0, zones: PowerZones = null) -> void:
	set_plan(PlanChartModel.new(workout, ftp_w, intensity, zones) if workout != null else null)


func _apply_preset() -> void:
	background = Background.INSET
	fade_height = 0.0
	show_fact = false
	show_cursor = false
	show_hr_scale = false
	legend_power_key = ""
	legend_hr_key = ""
	show_time_axis = detailed
	show_ftp_line = detailed
	show_ftp_label = detailed
	var pad: float = ROW_THUMB_PADDING if row_thumb and not detailed else PREVIEW_PADDING
	inset_radius = ROW_THUMB_RADIUS if row_thumb and not detailed else INSET_RADIUS
	inset_left = DETAILED_INSET_LEFT if detailed else pad
	inset_right = pad
	inset_top = pad
	inset_bottom = DETAILED_INSET_BOTTOM if detailed else pad
	if row_thumb and not detailed:
		custom_minimum_size = ROW_THUMB_SIZE
