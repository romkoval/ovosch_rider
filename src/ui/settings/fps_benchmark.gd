class_name FpsBenchmark
extends Control
## «Замер FPS» без станка (T-116a, п.4; инструмент для REQ-D3D-05 п.1, 3, D3D-07 п.7,
## D3D-08 п.9): сцена заезда `RideScene` выбранной трассы (по умолчанию «Перевал») в
## `SubViewport` в физическом разрешении окна, как на экранах заезда, гонщик едет с
## постоянной скоростью и каденсом заданное время (по умолчанию 3 мин). После прогрева
## (`warmup_sec`: сборка шейдеров и первая подгрузка не входят в замер) кадры меряет
## `FrameStatsProbe`; итог — в журнал (`DiagLog`, событие `fps_benchmark`) и на экран:
## средний FPS, 1 % low, время кадра p95/p99, доля кадров > 16.7 и > 33 мс, рендерер,
## разрешение, draw calls.
##
## HUD поверх 3D в замер не входит (его стоимость видна в статистике кадров заезда, п.3).
## Станок, сессия и поток 1 Гц не создаются. Экран — поверх настроек; «Отмена» и Esc
## прерывают прогон без записи итога (в журнал уходит событие `fps_benchmark_cancelled`).
##
## Оформление: решения `ui.md` для экрана разработчика нет — элементы взяты из темы как есть
## (карточка `HudPauseCard`, подписи `H2Label`/`SecondaryLabel`, кнопки `PrimaryButton`/обычные).

## Замер завершён: сводка (поля `FrameStatsProbe.finish`).
signal finished(summary: Dictionary)
## Пользователь закрыл экран (после итога или отменой).
signal closed

const EVENT: String = "fps_benchmark"
const EVENT_CANCELLED: String = "fps_benchmark_cancelled"
const DEFAULT_ROUTE: String = RouteCatalog.MOUNTAINS
const DEFAULT_DURATION_SEC: float = 180.0
const DEFAULT_SPEED_KMH: float = 30.0
const DEFAULT_CADENCE_RPM: int = 85
const DEFAULT_WARMUP_SEC: float = 2.0
## Длительности на выбор в настройках, с (20 мин — методика D3D-05 п.1).
const DURATIONS_SEC: Array[int] = [60, 180, 300, 1200]
## Отступ полосы прогресса от краёв безопасной зоны, lp.
const EDGE_MARGIN: float = 16.0
const RIDE_SCENE: PackedScene = preload("res://src/scene3d/ride_scene.tscn")

var route_id: String = DEFAULT_ROUTE
var duration_sec: float = DEFAULT_DURATION_SEC
var speed_kmh: float = DEFAULT_SPEED_KMH
var cadence_rpm: int = DEFAULT_CADENCE_RPM
var warmup_sec: float = DEFAULT_WARMUP_SEC
## Подставляемые часы (мкс) для прогона и замера; пусто — `Time.get_ticks_usec`.
var clock_usec: Callable = Callable()

var _container: SubViewportContainer
var _viewport: SubViewport
var _scene: RideScene = null
var _probe: FrameStatsProbe
var _top_bar: HBoxContainer
var _result_center: CenterContainer
var _progress_label: Label
var _cancel_button: Button
var _result_card: PanelContainer
var _result_title: Label
var _result_label: Label
var _repeat_button: Button
var _close_button: Button
var _running: bool = false
var _measuring: bool = false
var _started_usec: int = 0
var _last_shown_sec: int = -1
var _summary: Dictionary = {}


func _init() -> void:
	name = "FpsBenchmark"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _ready() -> void:
	resized.connect(_on_resized)
	var runtime := TouchTarget.default_runtime()
	if runtime != null:
		runtime.scale_changed.connect(_on_scale_changed)
	_on_resized()
	_render_texts()


func _on_resized() -> void:
	_fit_viewport()
	_apply_safe_area()


func _on_scale_changed(_scale: float) -> void:
	_apply_safe_area()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_render_texts()


## Запустить замер с текущими параметрами. false — не в дереве.
func start() -> bool:
	if not is_inside_tree():
		return false
	route_id = RouteCatalog.resolve_id(route_id)
	if _scene == null:
		_scene = RIDE_SCENE.instantiate() as RideScene
		_scene.name = "RideScene"
		_scene.route_id = route_id
		_viewport.add_child(_scene)
	elif _scene.route_id != route_id:
		_scene.set_route(route_id)
	_scene.distance_m = 0.0
	_scene.speed_kmh = speed_kmh
	_scene.cadence_rpm = cadence_rpm
	_scene.rider().set_cadence(cadence_rpm)
	_scene.rider().set_wheel_speed(speed_kmh)
	_scene.set_process(true)
	_probe.clock_usec = clock_usec
	_summary = {}
	_result_card.visible = false
	_progress_label.visible = true
	_cancel_button.visible = true
	_running = true
	_measuring = false
	_started_usec = _now()
	_last_shown_sec = -1
	set_process(true)
	DiagLog.event(DiagLog.CAT_FRAMES, EVENT + "_started", _params())
	if warmup_sec <= 0.0:
		_begin_measure()
	_render_progress(0.0)
	return true


## Прервать прогон без итога.
func cancel() -> void:
	if not _running:
		return
	_running = false
	_measuring = false
	set_process(false)
	if _scene != null:
		_scene.set_process(false)
	_probe.abort()
	DiagLog.event(DiagLog.CAT_FRAMES, EVENT_CANCELLED, _params())


func is_running() -> bool:
	return _running


func is_measuring() -> bool:
	return _measuring


func summary() -> Dictionary:
	return _summary.duplicate()


func ride_scene() -> RideScene:
	return _scene


func viewport() -> SubViewport:
	return _viewport


func probe() -> FrameStatsProbe:
	return _probe


func result_text() -> String:
	return _result_label.text


func is_result_visible() -> bool:
	return _result_card.visible


func repeat_button() -> Button:
	return _repeat_button


func close_button() -> Button:
	return _close_button


func cancel_button() -> Button:
	return _cancel_button


## «Назад»/Esc: идёт прогон — отмена; итог — закрыть. true — обработано.
func handle_back() -> bool:
	if _running:
		cancel()
	close()
	return true


func close() -> void:
	if _running:
		cancel()
	closed.emit()


## Текст итога по сводке (строки через перевод).
static func format_summary(s: Dictionary) -> String:
	var lines: Array[String] = [
		TranslationServer.translate("ui.fps_bench.avg_fps").format({"value": "%.1f" % float(s.get("avg_fps", 0.0))}),
		TranslationServer.translate("ui.fps_bench.low_1pct").format({"value": "%.1f" % float(s.get("low_1pct_fps", 0.0))}),
		TranslationServer.translate("ui.fps_bench.frame_time").format({
			"p95": "%.1f" % float(s.get("p95_ms", 0.0)), "p99": "%.1f" % float(s.get("p99_ms", 0.0)),
			"max": "%.1f" % float(s.get("max_ms", 0.0))}),
		TranslationServer.translate("ui.fps_bench.slow_frames").format({
			"slow": "%.1f" % (float(s.get("share_over_16_7_ms", 0.0)) * 100.0),
			"very_slow": "%.1f" % (float(s.get("share_over_33_ms", 0.0)) * 100.0)}),
		TranslationServer.translate("ui.fps_bench.frames").format({
			"frames": str(int(s.get("frames", 0))), "duration": "%.0f" % float(s.get("duration_s", 0.0))}),
		TranslationServer.translate("ui.fps_bench.render").format({
			"renderer": str(s.get("renderer", "")), "window": str(s.get("window_px", "")),
			"viewport": str(s.get("viewport_3d_px", "")), "draw_calls": str(int(s.get("draw_calls_max", 0)))}),
	]
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not _running:
		return
	var elapsed: float = float(_now() - _started_usec) / 1_000_000.0
	if not _measuring and elapsed >= warmup_sec:
		_begin_measure()
	var measured: float = maxf(elapsed - warmup_sec, 0.0)
	_render_progress(measured)
	if _measuring and measured >= duration_sec:
		_finish()


func _begin_measure() -> void:
	_measuring = true
	_probe.event_name = EVENT
	var context := _params()
	context["mode"] = "fps_benchmark"
	_probe.begin(context, _viewport)


func _finish() -> void:
	_running = false
	_measuring = false
	set_process(false)
	if _scene != null:
		_scene.set_process(false)
	var extra := {"distance_m": roundi(_scene.distance_m) if _scene != null else 0}
	_summary = _probe.finish(extra)
	_progress_label.visible = false
	_cancel_button.visible = false
	_result_label.text = format_summary(_summary)
	_result_card.visible = true
	_repeat_button.grab_focus.call_deferred()
	finished.emit(_summary)


func _params() -> Dictionary:
	return {
		"route": route_id,
		"duration_s": duration_sec,
		"speed_kmh": speed_kmh,
		"cadence_rpm": cadence_rpm,
		"warmup_s": warmup_sec,
	}


func _now() -> int:
	return int(clock_usec.call()) if clock_usec.is_valid() else Time.get_ticks_usec()


func _render_progress(measured_sec: float) -> void:
	var shown := int(measured_sec)
	if shown == _last_shown_sec:
		return
	_last_shown_sec = shown
	var key := "ui.fps_bench.progress" if _measuring else "ui.fps_bench.warmup"
	_progress_label.text = tr(key).format({
		"route": tr(RouteCatalog.get_route(route_id).name_key),
		"elapsed": _mmss(shown),
		"total": _mmss(int(duration_sec)),
	})


func _render_texts() -> void:
	_cancel_button.text = tr("ui.common.cancel")
	_result_title.text = tr("ui.fps_bench.result_title").format({"route": tr(RouteCatalog.get_route(route_id).name_key)})
	_repeat_button.text = tr("ui.fps_bench.repeat")
	_close_button.text = tr("ui.fps_bench.close")
	if not _summary.is_empty():
		_result_label.text = format_summary(_summary)
	_last_shown_sec = -1
	if _running:
		_render_progress(0.0)


static func _mmss(sec: int) -> String:
	return "%d:%02d" % [sec / 60, sec % 60]


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color.BLACK
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_container = SubViewportContainer.new()
	_container.name = "ViewportContainer"
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.name = "Viewport"
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = false
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_container.add_child(_viewport)
	_probe = FrameStatsProbe.attach(self)

	var top := HBoxContainer.new()
	top.name = "TopBar"
	top.theme_type_variation = &"Row16"
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(top)
	_top_bar = top
	_progress_label = Label.new()
	_progress_label.name = "ProgressLabel"
	_progress_label.theme_type_variation = &"H2Label"
	_progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_progress_label)
	_cancel_button = Button.new()
	_cancel_button.name = "CancelButton"
	_cancel_button.pressed.connect(close)
	top.add_child(_cancel_button)
	TouchTarget.attach(_cancel_button, TouchTarget.Kind.BUTTON)

	var center := CenterContainer.new()
	center.name = "ResultCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_result_center = center
	_result_card = PanelContainer.new()
	_result_card.name = "ResultCard"
	_result_card.theme_type_variation = &"HudPauseCard"
	_result_card.visible = false
	center.add_child(_result_card)
	var stack := VBoxContainer.new()
	stack.theme_type_variation = &"Stack16"
	_result_card.add_child(stack)
	_result_title = Label.new()
	_result_title.name = "ResultTitle"
	_result_title.theme_type_variation = &"H2Label"
	stack.add_child(_result_title)
	_result_label = Label.new()
	_result_label.name = "ResultLabel"
	_result_label.theme_type_variation = &"SecondaryLabel"
	stack.add_child(_result_label)
	var buttons := HBoxContainer.new()
	buttons.theme_type_variation = &"Row12"
	buttons.alignment = BoxContainer.ALIGNMENT_END
	stack.add_child(buttons)
	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.pressed.connect(close)
	buttons.add_child(_close_button)
	_repeat_button = Button.new()
	_repeat_button.name = "RepeatButton"
	_repeat_button.theme_type_variation = &"PrimaryButton"
	_repeat_button.pressed.connect(start)
	buttons.add_child(_repeat_button)
	for b: Button in [_close_button, _repeat_button]:
		TouchTarget.attach(b, TouchTarget.Kind.BUTTON)
	set_process(false)


## Полоса прогресса и карточка итога — внутри безопасной зоны (`UiScale.safe_margins`,
## UIX-05 крит. 2), полоса — ещё на `EDGE_MARGIN` от её краёв; 3D-картинка — на всё окно, как
## на экранах заезда.
func _apply_safe_area() -> void:
	var safe := Vector4.ZERO
	var runtime := TouchTarget.default_runtime()
	if runtime != null:
		safe = runtime.safe_margins()
	_top_bar.offset_left = safe.x + EDGE_MARGIN
	_top_bar.offset_right = -(safe.z + EDGE_MARGIN)
	_top_bar.offset_top = safe.y + EDGE_MARGIN
	_result_center.offset_left = safe.x
	_result_center.offset_top = safe.y
	_result_center.offset_right = -safe.z
	_result_center.offset_bottom = -safe.w


## Вьюпорт 3D — в пикселях окна (как `FreeRideScreen._fit_viewport`): контейнер уменьшен
## `scale` обратно до размера экрана.
func _fit_viewport() -> void:
	var lp := size
	if lp.x <= 0.0 or lp.y <= 0.0 or not is_inside_tree():
		return
	var px_per_lp := Vector2.ONE
	var visible_lp := get_viewport_rect().size
	var window := get_window()
	if window != null and visible_lp.x > 0.0 and visible_lp.y > 0.0:
		px_per_lp = Vector2(window.size) / visible_lp
	var px := Vector2i(maxi(roundi(lp.x * px_per_lp.x), 1), maxi(roundi(lp.y * px_per_lp.y), 1))
	_container.position = Vector2.ZERO
	_container.scale = lp / Vector2(px)
	_container.size = Vector2(px)
	if _viewport.size != px:
		_viewport.size = px
