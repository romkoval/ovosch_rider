class_name FrameRateLimit
extends RefCounted
## Отладочное ограничение FPS (T-116a, п.5; инструмент для REQ-NFR-02 п.3): «ограничить FPS
## до 15» — `Engine.max_fps = 15` до перезапуска или выключения. В файлы не сохраняется:
## случайно оставленное ограничение не переживёт перезапуск, настройка проекта
## `application/run/max_fps` не меняется (REQ-D3D-05 п.2). Каждое переключение — в журнал.

const DEBUG_FPS: int = 15
const EVENT: String = "fps_limit"


## Включить или снять ограничение.
static func set_limited(limited: bool) -> void:
	Engine.max_fps = DEBUG_FPS if limited else project_max_fps()
	DiagLog.event(DiagLog.CAT_SETTINGS, EVENT, {"limited": limited, "max_fps": Engine.max_fps})


static func is_limited() -> bool:
	return Engine.max_fps == DEBUG_FPS


## Предел FPS из настроек проекта (0 — без предела).
static func project_max_fps() -> int:
	return int(ProjectSettings.get_setting("application/run/max_fps", 0))
