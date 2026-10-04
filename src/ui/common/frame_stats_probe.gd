class_name FrameStatsProbe
extends Node
## Замер кадров заезда (T-116a, п.3): между `begin` и `finish` меряет длительность каждого
## кадра по системным часам (`Time.get_ticks_usec`, а не `delta` движка), считает
## `FrameStats` и draw calls 3D-вьюпорта (видимые + тени), при `finish` пишет сводку в журнал (`DiagLog`,
## категория `frames`) и отдаёт её сигналом `finished`.
##
## Экраны заезда (тренировка, свободная езда) создают узел `attach(self)`, вызывают `begin`
## при старте сессии и `finish` при её завершении; экран замера FPS — так же. Сводка кроме
## `FrameStats.summary()` содержит окружение (`render_info`): рендерер, драйвер, видеоадаптер,
## разрешение окна и 3D, vsync, частоту экрана, ограничение FPS, версию приложения и движка,
## тип сборки — и контекст вызывающего (режим, трасса).

## Сводка записана в журнал (и при пустом замере тоже).
signal finished(summary: Dictionary)

const NODE_NAME: String = "FrameStatsProbe"
const EVENT_RIDE: String = "ride_frame_stats"

## Подставляемые часы (мкс); пусто — `Time.get_ticks_usec`.
var clock_usec: Callable = Callable()
## Имя события журнала.
var event_name: String = EVENT_RIDE

var _stats: FrameStats = FrameStats.new()
var _running: bool = false
var _last_usec: int = -1
var _context: Dictionary = {}
var _viewport: SubViewport = null
var _draw_calls_sum: int = 0
var _draw_calls_max: int = 0
var _draw_samples: int = 0


## Создать замер дочерним узлом `owner_node`.
static func attach(owner_node: Node) -> FrameStatsProbe:
	var probe := FrameStatsProbe.new()
	probe.name = NODE_NAME
	owner_node.add_child(probe)
	return probe


func _init() -> void:
	set_process(false)


## Начать замер. `context` — поля вызывающего (режим, трасса); `viewport` — 3D-вьюпорт
## (его разрешение и draw calls попадут в сводку). Идущий замер сбрасывается без записи.
func begin(context: Dictionary = {}, viewport: SubViewport = null) -> void:
	_stats.reset()
	_context = context.duplicate()
	_viewport = viewport
	_draw_calls_sum = 0
	_draw_calls_max = 0
	_draw_samples = 0
	_last_usec = -1
	_running = true
	set_process(true)


func is_running() -> bool:
	return _running


func stats() -> FrameStats:
	return _stats


## Учесть кадр заданной длительности (синтетические кадры в тестах).
func add_frame_ms(ms: float) -> void:
	if _running:
		_stats.add_frame_ms(ms)


## Завершить замер: сводка в журнал и сигналом. Не идёт — {} без записи.
func finish(extra: Dictionary = {}) -> Dictionary:
	if not _running:
		return {}
	_running = false
	set_process(false)
	var summary := render_info(self, _viewport)
	summary.merge(_context, true)
	summary.merge(extra, true)
	summary.merge(_stats.summary(), true)
	summary["draw_calls_avg"] = roundi(float(_draw_calls_sum) / float(_draw_samples)) if _draw_samples > 0 else 0
	summary["draw_calls_max"] = _draw_calls_max
	DiagLog.event(DiagLog.CAT_FRAMES, event_name, summary)
	finished.emit(summary)
	return summary


## Прервать замер без записи в журнал.
func abort() -> void:
	_running = false
	set_process(false)


## Окружение замера: рендерер, драйвер, адаптер, окно и 3D, vsync, частота, предел FPS, версии.
static func render_info(node: Node, viewport: SubViewport = null) -> Dictionary:
	var window: Window = node.get_window() if node != null and node.is_inside_tree() else null
	var info := {
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"adapter_vendor": RenderingServer.get_video_adapter_vendor(),
		"window_px": _size_text(window.size) if window != null else "",
		"viewport_3d_px": _size_text(viewport.size) if viewport != null else "",
		"scaling_3d": snappedf(viewport.scaling_3d_scale, 0.01) if viewport != null else 1.0,
		"msaa_3d": int(viewport.msaa_3d) if viewport != null else 0,
		"vsync": DisplayServer.window_get_vsync_mode(),
		"refresh_hz": snappedf(DisplayServer.screen_get_refresh_rate(), 0.01),
		"max_fps": Engine.max_fps,
		"app_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"engine": str(Engine.get_version_info().get("string", "")),
		"build": "debug" if is_debug_build() else "release",
	}
	return info


## Отладочная сборка: `assert` выполняется только в ней (без обращения к `OS`, NFR-06 п.1).
static func is_debug_build() -> bool:
	var probe: Array[bool] = [false]
	assert(_mark(probe))
	return probe[0]


static func _mark(probe: Array[bool]) -> bool:
	probe[0] = true
	return true


static func _size_text(v: Vector2i) -> String:
	return "%dx%d" % [v.x, v.y]


func _process(_delta: float) -> void:
	var now: int = int(clock_usec.call()) if clock_usec.is_valid() else Time.get_ticks_usec()
	if _last_usec >= 0 and now > _last_usec:
		_stats.add_frame_usec(now - _last_usec)
	_last_usec = now
	if _viewport != null:
		var calls := _viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME) \
				+ _viewport.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		_draw_calls_sum += calls
		_draw_samples += 1
		if calls > _draw_calls_max:
			_draw_calls_max = calls
