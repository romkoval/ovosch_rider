class_name PlanPreview
extends HudChart
## Превью плана тренировки в меню (REQ-UIX-03 крит. 1, 4; `docs/game/ui.md` п. 5 «PlanThumb»).
##
## Тот же рисовальщик, что нижний график HUD (`HudChart`), и та же модель (`PlanChartModel`):
## сегменты по зонам, рампы кусками по зонам, «свободно» со штриховкой, зазоры 1 lp,
## скруглённые верхние углы. Фон — `inset` со скруглением 12 и полями 12.
## - Миниатюра (`detailed = false`, по умолчанию): без факта, курсора и подписей (UIX-03.4).
## - Крупное превью (`detailed = true`): плюс шкала времени и пунктир FTP с подписью (UIX-03.1).
## Заменит `src/ui/plan/workout_chart.gd` в T-082.

## Поля превью (`ui.md` п. 5): 12 lp.
const PREVIEW_PADDING: float = 12.0
## Крупное превью: слева место под подпись FTP, снизу — под шкалу времени.
const DETAILED_INSET_LEFT: float = 40.0
const DETAILED_INSET_BOTTOM: float = 30.0

## Крупное превью со шкалой времени и пунктиром FTP.
@export var detailed: bool = false:
	set(value):
		detailed = value
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
	inset_left = DETAILED_INSET_LEFT if detailed else PREVIEW_PADDING
	inset_right = PREVIEW_PADDING
	inset_top = PREVIEW_PADDING
	inset_bottom = DETAILED_INSET_BOTTOM if detailed else PREVIEW_PADDING
