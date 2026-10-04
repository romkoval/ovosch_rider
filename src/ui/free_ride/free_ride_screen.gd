class_name FreeRideScreen
extends Control
## Экран свободной езды (`AppState.Screen.FREE_RIDE`; REQ-FRD-01 крит. 1, REQ-FRD-04 крит. 6,
## REQ-FRD-05 крит. 4–6, REQ-FRD-06 крит. 1–7, REQ-FRD-07 крит. 2, REQ-UIX-04 крит. 2).
##
## Собирает из готовых частей: `FreeRideSession` (T-077), один `SessionTicker` (сессия
## тикается через его сигнал `ticked`), модель `FreeRideHudModel`, 3D-сцену `RideScene` по
## трассе (`set_route`, T-070), раскладку `HudLayout` (T-073) с компонентами свободной езды
## (T-079): панель цифр `HudMetricPanel` в режиме `FREE_RIDE`, панель рельефа `ReliefPanel`
## в левом слоте, график «история усилия» `HudChart` (`set_window` / `sync_free_ride`), и
## органы управления (T-074): `HudToolbar` (SIM ↔ сопротивление, крутизна ±10 % или
## сопротивление ±5, «Завершить») и `PauseOverlay` (без «Пропустить шаг», «Завершить» —
## с подтверждением). Станок — любой `TrainerDevice` (в приложении — `SensorHub` из
## `ConnectionManager`, в отладке — эмулятор): реализацию экран не знает.
##
## Раскладка — как у экрана тренировки (`docs/game/hud.md` п. 4, 8): панель цифр сверху по
## центру, рельеф слева (ширина `w_l`, высота 0.40·H), график внизу во всю ширину, фишки
## статусов «СТАНОК», «ПУЛЬС», «SIM»/«СОПР.» и кнопка паузы справа сверху, панель
## инструментов у правого края. Слот подсказки занимает сообщение «станок не поддерживает
## SIM» (FRD-06 крит. 7): по `simulation_unavailable` оно видно `NOTICE_SEC` секунд, а фишка
## режима и карточка уклона показывают «СОПР.».
##
## 3D-фон — `RideScene` в `SubViewport` в физическом разрешении окна (HUD-13 крит. 10), как у
## тренировки; сцена создаётся при первом старте с трассой сессии (чтобы мир не строился
## дважды). Позиция сессии меняется раз в секунду, поэтому экран сам ведёт гонщика между
## сэмплами: положение экстраполируется по скорости модели от последнего сэмпла по времени
## сессии (`session_time_sec`, учитывает ускорение часов и паузу), а скачок на границе секунды
## (смена скорости) гасится плавно (`POSITION_BLEND_SEC`). Собственный `_process` сцены
## выключен — её `advance` вызывает экран после установки позиции.
##
## «Назад» (Esc — через панель инструментов, на карточке паузы или без панели; системный
## «назад» — `handle_back`): идёт сессия или пауза — подтверждение завершения (REQ-UIX-04
## крит. 2, как WRK-05 крит. 4; решение по Esc одно для обоих экранов заезда), без
## подтверждения сессия не завершается; пауза — кнопкой паузы. После «Завершить» сессия
## останавливается, запись заезда сохраняет `RideRecorder` владельца (по `session_created`),
## экран показывает итог (`ui.md` п. 8.8) с «Открыть в истории» и «На главный».
##
## Общая с экраном тренировки часть — фишки статусов, расстановка слотов, панель инструментов,
## плашка слота подсказки и Esc на карточке паузы — в `HudScreenFrame`.

## Сессия создана и сейчас стартует — владелец подключает запись заезда (`RideRecorder`).
signal session_created(session: FreeRideSession)
## Сессия завершена и записана (`FreeRideSession.session_finished`, после `RideRecorder`).
signal session_finished(session: FreeRideSession)
## Профиль изменён экраном (крутизна SIM, уровень сопротивления) — владелец сохраняет.
signal profile_updated(profile: Profile)
## «Открыть в истории» на итоге: `ride_id` сохранённого заезда ("" — неизвестен).
signal history_requested(ride_id: String)

## Сообщение «станок не поддерживает SIM» видно столько секунд времени сессии (FRD-06 крит. 7: ≥ 5).
const NOTICE_SEC: float = 8.0
## Скачок экстраполированной позиции на границе секунды гасится за столько секунд сессии.
const POSITION_BLEND_SEC: float = 0.5
## Расхождение больше этого (м) не сглаживается, а применяется сразу.
const POSITION_SNAP_M: float = 50.0
const RIDE_SCENE: PackedScene = preload("res://src/scene3d/ride_scene.tscn")
const ICON_PAUSE: Texture2D = preload("res://assets/icons/lucide/pause.svg")
const ICON_PLAY: Texture2D = preload("res://assets/icons/lucide/play.svg")
## Плитки итога (`ui.md` п. 8.8): ключ плитки; подпись — `ui.free_ride.summary.<ключ>`.
const SUMMARY_STATS: Array[String] = ["time", "distance", "avg_power", "np", "avg_hr", "ascent"]

## Подставляемые часы тикера (пусто — системные).
var clock_usec: Callable = Callable()
## Подставляемый сеттер запрета гашения экрана (пусто — `DisplayServer.screen_set_keep_on`).
var keep_awake_setter: Callable = Callable()

var _app_state: AppState
var _profile: Profile
var _trainer: TrainerDevice
var _connections: ConnectionManager
var _route_id: String = RouteCatalog.DEFAULT_ID
var _steepness_pct: int = SimController.DEFAULT_STEEPNESS_PCT
var _session: FreeRideSession
var _ticker: SessionTicker
var _hud: FreeRideHudModel
var _ride_scene: RideScene
## Общая рамка HUD: фишки, слоты, панель инструментов, слот подсказки, Esc на карточке паузы.
var _frame: HudScreenFrame
## Статистика кадров заезда в журнал (T-116a): от старта сессии до FINISHED.
var _frame_probe: FrameStatsProbe
var _keep_on: bool = false
var _notice_left_sec: float = 0.0
var _ride_id: String = ""
var _summary: RideSummary = null
## Ведение гонщика между сэмплами: база (дистанция, м; скорость, м/с; секунда) и сглаживание.
var _base_distance_m: float = 0.0
var _base_speed_mps: float = 0.0
var _base_sec: int = -1
var _blend_offset_m: float = 0.0
var _last_session_time: float = 0.0

@onready var _viewport_container: SubViewportContainer = %ViewportContainer
@onready var _viewport: SubViewport = %Viewport
@onready var _pause_overlay: PauseOverlay = %PauseOverlay
@onready var _hud_root: Control = %HudRoot
@onready var _chart_slot: Control = %ChartSlot
@onready var _chart: HudChart = %Chart
@onready var _list_slot: Control = %ListSlot
@onready var _relief: ReliefPanel = %Relief
@onready var _metric_panel: HudMetricPanel = %MetricPanel
@onready var _hint_slot: Control = %HintSlot
@onready var _notice_plate: PanelContainer = %NoticePlate
@onready var _notice_label: Label = %NoticeLabel
@onready var _status_slot: Control = %StatusSlot
@onready var _trainer_chip: Control = %TrainerChip
@onready var _hr_chip: Control = %HrChip
@onready var _mode_chip: Control = %ModeChip
@onready var _mode_label: Label = %ModeStatusLabel
@onready var _pause_button: Button = %PauseButton
@onready var _toolbar_slot: Control = %ToolbarSlot
@onready var _toolbar: HudToolbar = %Toolbar
@onready var _no_session_root: Control = %NoSessionRoot
@onready var _back_button: Button = %BackButton
@onready var _summary_root: RideSummaryCard = %SummaryRoot


## Подготовить заезд: профиль (вес, FTP, зоны, уровень сопротивления), станок, трасса и
## крутизна SIM на старте. `connections` — опционально, для `ticks_devices`.
func setup(app_state: AppState, profile: Profile = null, trainer: TrainerDevice = null,
		route_id: String = RouteCatalog.DEFAULT_ID, steepness_pct: int = SimController.DEFAULT_STEEPNESS_PCT,
		connections: ConnectionManager = null) -> void:
	_teardown_session()
	_app_state = app_state
	_profile = profile
	_trainer = trainer
	_route_id = RouteCatalog.resolve_id(route_id)
	_steepness_pct = steepness_pct
	_connections = connections
	_summary = null
	_ride_id = ""
	if is_node_ready():
		refresh()


func _ready() -> void:
	var chips: Array[Control] = [_trainer_chip, _hr_chip, _mode_chip]
	_frame = HudScreenFrame.new(self, chips)
	_summary_root.share_unique_names(self)
	_metric_panel.set_mode(HudMetricPanel.Mode.FREE_RIDE)
	_toolbar.set_mode(HudToolbar.Mode.FREE_RIDE)
	_pause_overlay.set_mode(HudToolbar.Mode.FREE_RIDE)
	_build_summary_stats()
	resized.connect(_on_resized)
	get_viewport().size_changed.connect(_on_resized)
	_pause_button.pressed.connect(toggle_pause)
	_back_button.pressed.connect(back)
	_summary_root.home_requested.connect(go_home)
	_summary_root.history_requested.connect(open_history)
	_toolbar.pause_requested.connect(_on_toolbar_escape)
	_toolbar.sim_toggle_requested.connect(toggle_mode)
	_toolbar.steepness_step_requested.connect(adjust_steepness)
	_toolbar.resistance_step_requested.connect(adjust_resistance)
	_toolbar.finish_requested.connect(request_finish)
	_pause_overlay.resume_requested.connect(resume)
	_pause_overlay.finish_confirmed.connect(confirm_finish)
	# Экран в масштабе HUD: кнопка «назад» — цель `touch_hud` (на телефоне 72 lp HUD,
	# UIX-05 крит. 1), как у кнопок HUD; кнопки итога цепляет сам `RideSummaryCard`.
	for b: Button in [_back_button, _pause_button]:
		TouchTarget.attach(b, TouchTarget.Kind.HUD)
	_frame.install_escape_guard(_on_escape_on_pause_card)
	_frame_probe = FrameStatsProbe.attach(self)
	set_process(false)
	_fit_viewport()
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready():
		_update_input_gates()
	elif what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		refresh()


# ---------------------------------------------------------------------------
# Жизненный цикл сессии
# ---------------------------------------------------------------------------

## Создать сессию, 3D-сцену трассы, HUD и тикер; запустить. false — не настроен.
func start() -> bool:
	if _trainer == null or not is_node_ready():
		return false
	_teardown_session()
	_summary = null
	_ride_id = ""
	var ftp: int = _profile.ftp_w if _profile != null else 0
	var weight: float = _profile.weight_kg if _profile != null else FreeRideSession.DEFAULT_WEIGHT_KG
	var resistance: int = _profile.resistance_level_default if _profile != null else SimController.DEFAULT_RESISTANCE_PCT
	_session = FreeRideSession.new(_trainer, _route_id, _steepness_pct, weight, ftp,
			SimController.Mode.SIM, resistance)
	_session.state_changed.connect(_on_session_state)
	_session.session_finished.connect(_on_session_finished)
	_session.second_elapsed.connect(_on_second_elapsed)
	_session.mode_changed.connect(_on_mode_changed)
	_session.steepness_changed.connect(_on_steepness_changed)
	_session.resistance_level_changed.connect(_on_resistance_changed)
	_session.simulation_unavailable.connect(_on_simulation_unavailable)
	_hud = FreeRideHudModel.new(_session, _profile)
	_hud.changed.connect(_on_hud_changed)
	_ensure_ride_scene(_session.route.id)
	_relief.setup(_session)
	var max_hr: int = _profile.max_hr if _profile != null and _profile.has_max_hr() else 0
	var zones: PowerZones = _profile.effective_power_zones() if _profile != null else null
	_chart.set_window(EffortSeries.sliding_window(ftp, max_hr), ftp, zones)
	_ticker = SessionTicker.new(clock_usec)
	_ticker.name = "SessionTicker"
	_ticker.ticked.connect(_on_ticked)
	add_child(_ticker)
	if _connections != null:
		_connections.ticks_devices = false
	_notice_left_sec = 0.0
	_reset_rider_tracking()
	_frame_probe.begin({"mode": "free_ride", "route": _session.route.id}, _viewport)
	session_created.emit(_session)
	_session.start()
	_ticker.start()
	set_process(true)
	_apply_keep_awake()
	refresh()
	return true


func session() -> FreeRideSession:
	return _session


func ticker() -> SessionTicker:
	return _ticker


func hud() -> FreeRideHudModel:
	return _hud


## 3D-фон под HUD (null — заезд ещё не запускался).
func ride_scene() -> RideScene:
	return _ride_scene


## Размер изображения 3D-сцены в пикселях (REQ-HUD-13 крит. 10).
func ride_viewport_size() -> Vector2i:
	return _viewport.size


func metric_panel() -> HudMetricPanel:
	return _metric_panel


func relief_panel() -> ReliefPanel:
	return _relief


func chart() -> HudChart:
	return _chart


func toolbar() -> HudToolbar:
	return _toolbar


func pause_overlay() -> PauseOverlay:
	return _pause_overlay


## Текущая геометрия HUD (пересчитывается при смене размера и на каждой отрисовке).
func hud_layout() -> HudLayout:
	if _frame.current_layout() == null:
		_layout_hud()
	return _frame.current_layout()


func list_slot() -> Control:
	return _list_slot


func chart_slot() -> Control:
	return _chart_slot


func hint_slot() -> Control:
	return _hint_slot


func toolbar_slot() -> Control:
	return _toolbar_slot


## Уход с экрана: снять запрет гашения (REQ-NFR-04 крит. 1) и вернуть масштаб меню.
func on_screen_exited() -> void:
	_set_keep_on(false)
	var ui := _ui_scale()
	if ui != null and ui.mode == UiScale.Mode.HUD:
		ui.set_mode(UiScale.Mode.MENU)


## Вход на экран: запрет гашения по состоянию сессии и масштаб HUD (`hud.md` п. 3).
func on_screen_entered() -> void:
	_apply_keep_awake()
	var ui := _ui_scale()
	if ui != null and ui.mode != UiScale.Mode.HUD:
		ui.set_mode(UiScale.Mode.HUD)
	_fit_viewport()
	refresh()


# ---------------------------------------------------------------------------
# Управление
# ---------------------------------------------------------------------------

## Пауза ↔ продолжение (кнопка паузы).
func toggle_pause() -> void:
	if _session == null:
		return
	match _session.get_state():
		WorkoutSession.State.RUNNING:
			pause()
		WorkoutSession.State.PAUSED:
			resume()


## Пауза (кнопка паузы): на станок ничего не уходит, время и дистанция стоят (FRD-07 крит. 2).
func pause() -> void:
	if _session != null and _session.get_state() == WorkoutSession.State.RUNNING:
		_session.pause()


func resume() -> void:
	if _session != null and _session.get_state() == WorkoutSession.State.PAUSED:
		_session.resume()


## Запрос досрочного завершения: подтверждение (FRD-07 крит. 2, WRK-05 крит. 4). false — сессии нет.
func request_finish() -> bool:
	if not is_session_active():
		return false
	_pause_overlay.show_finish_confirmation()
	_update_input_gates()
	return true


## Подтверждение принято: сессия останавливается, запись сохраняет `RideRecorder` владельца.
func confirm_finish() -> void:
	if not is_session_active():
		return
	if _pause_overlay.is_shown():
		_pause_overlay.hide_overlay()
	_session.stop()


func cancel_finish() -> void:
	_pause_overlay.cancel_finish()
	_update_input_gates()


func is_finish_confirmation_pending() -> bool:
	return _pause_overlay.view() == PauseOverlay.View.CONFIRM


## SIM ↔ фиксированное сопротивление одним действием (FRD-05 крит. 4).
func toggle_mode() -> bool:
	if _session == null:
		return false
	return _session.toggle_mode()


## Крутизна SIM ±10 % (FRD-05 крит. 3).
func adjust_steepness(delta_pct: int) -> void:
	if _session != null:
		_session.set_steepness(_session.steepness_pct() + delta_pct)


## Уровень фиксированного сопротивления ±5 % (FRD-05 крит. 4).
func adjust_resistance(delta_pct: int) -> void:
	if _session != null:
		_session.set_resistance_level(_session.resistance_level() + delta_pct)


## Системный «назад» (Esc без панели инструментов, Android; REQ-UIX-04 крит. 2): true — экран
## перехватил его (открыто подтверждение — отмена; идёт сессия — запрос завершения с
## подтверждением); false — сессии нет или она завершена, оболочка ведёт на главный.
func handle_back() -> bool:
	if not is_session_active():
		return false
	if is_finish_confirmation_pending():
		cancel_finish()
		return true
	return request_finish()


## Esc панели инструментов (`pause_requested`): как системное «назад» — идёт заезд —
## подтверждение завершения (REQ-UIX-04 крит. 2); пауза — кнопкой паузы.
func _on_toolbar_escape() -> void:
	if _session != null and _session.get_state() == WorkoutSession.State.RUNNING:
		request_finish()


## Esc на карточке паузы — подтверждение завершения, как системное «назад». `PauseOverlay` на
## карточке паузы клавишу поглощает, поэтому её раньше перехватывает `HudScreenFrame.EscapeGuard`.
func _on_escape_on_pause_card() -> bool:
	if not is_visible_in_tree() or _pause_overlay.view() != PauseOverlay.View.PAUSE:
		return false
	return request_finish()


## Кнопка экрана без сессии: на главный.
func back() -> void:
	go_home()


func go_home() -> void:
	on_screen_exited()
	if _app_state != null:
		_app_state.navigate(AppState.Screen.HOME)


## «Открыть в истории» на итоге.
func open_history() -> void:
	history_requested.emit(_ride_id)


## Идёт или стоит на паузе.
func is_session_active() -> bool:
	return _session != null and _session.get_state() in [WorkoutSession.State.RUNNING, WorkoutSession.State.PAUSED]


## Владелец сообщает сохранённый заезд: итог берётся из его сводки, «Открыть в истории» ведёт к нему.
func show_saved_ride(ride: Ride) -> void:
	if ride == null:
		return
	_ride_id = ride.id
	_summary = ride.summary
	refresh()


func saved_ride_id() -> String:
	return _ride_id


# ---------------------------------------------------------------------------
# Тексты и состояние (для тестов)
# ---------------------------------------------------------------------------

func is_hud_visible() -> bool:
	return _hud_root.visible


func is_summary_visible() -> bool:
	return _summary_root.visible


func is_notice_visible() -> bool:
	return _notice_plate.visible


func notice_text() -> String:
	return _notice_label.text if _notice_plate.visible else ""


## Подпись фишки режима: «SIM» или «СОПР.».
func mode_chip_text() -> String:
	return _mode_label.text


func summary_value_text(stat: String) -> String:
	return _summary_root.value_text(stat)


## Карточка итога (`RideSummaryCard`).
func summary_card() -> RideSummaryCard:
	return _summary_root


# ---------------------------------------------------------------------------
# Отрисовка
# ---------------------------------------------------------------------------

## Перечитать состояние и обновить узлы.
func refresh() -> void:
	if not is_node_ready():
		return
	var finished: bool = _session != null and _session.get_state() == WorkoutSession.State.FINISHED
	_no_session_root.visible = _session == null
	_hud_root.visible = _session != null and not finished
	_summary_root.visible = finished
	_viewport_container.visible = _session != null
	if finished:
		_render_summary()
	elif _session != null:
		_render()
	_update_input_gates()


func _render() -> void:
	if _hud == null:
		return
	var s := _hud.state()
	_metric_panel.set_state(s)
	var paused: bool = int(s["session_state"]) == WorkoutSession.State.PAUSED
	_metric_panel.set_dimmed(paused)
	_pause_button.icon = ICON_PLAY if paused else ICON_PAUSE
	_pause_button.tooltip_text = tr("ui.workout.resume") if paused else tr("ui.workout.pause")
	_toolbar.set_paused(paused)
	_toolbar.set_sim_enabled(int(s[HudMetricPanel.KEY_LOAD_MODE]) == SimController.Mode.SIM)
	_toolbar.set_steepness_pct(int(s[HudMetricPanel.KEY_STEEPNESS_PCT]))
	_toolbar.set_resistance_pct(int(s[HudMetricPanel.KEY_RESISTANCE_PCT]))
	_render_status(s)
	_notice_plate.visible = _notice_left_sec > 0.0
	_notice_label.text = tr("ui.free_ride.notice.no_sim")
	_layout_hud()


## Фишки статусов: станок, пульс, режим нагрузки (SIM / СОПР.).
func _render_status(s: Dictionary) -> void:
	_trainer_chip.tooltip_text = tr(s["connection_key"])
	_frame.set_dot(_trainer_chip, HudScreenFrame.connection_dot(int(s["connection_state"])))
	var has_hr: bool = int(s["hr_bpm"]) >= 0
	_hr_chip.tooltip_text = tr("ui.hud.status.hr_ok") if has_hr else tr("ui.hud.status.hr_missing")
	_frame.set_dot(_hr_chip, UiTokens.HUD_OK if has_hr else UiTokens.HUD_ERR)
	var sim: bool = int(s[HudMetricPanel.KEY_LOAD_MODE]) == SimController.Mode.SIM
	_mode_label.text = tr("ui.free_ride.status.sim") if sim else tr("ui.free_ride.status.fixed")
	if sim:
		_mode_chip.tooltip_text = tr("ui.free_ride.status.sim_hint").format({"value": int(s[HudMetricPanel.KEY_STEEPNESS_PCT])})
		_frame.set_dot(_mode_chip, UiTokens.HUD_OK)
	else:
		_mode_chip.tooltip_text = tr("ui.free_ride.status.fixed_hint").format({"value": int(s[HudMetricPanel.KEY_RESISTANCE_PCT])})
		_frame.set_dot(_mode_chip, UiTokens.HUD_WARN if bool(s.get("sim_unavailable", false)) else UiTokens.HUD_TEXT2)
	_frame.redraw_chips()


func _build_summary_stats() -> void:
	var stats: Array[Dictionary] = []
	for key in SUMMARY_STATS:
		stats.append({"key": key, "caption": "ui.free_ride.summary." + key})
	_summary_root.setup_stats(stats)
	_summary_root.set_title("ui.free_ride.summary.title")


## Итог (`ui.md` п. 8.8): время, дистанция, ср. мощность, NP, ср. пульс, набор. Сводка —
## сохранённого заезда (`show_saved_ride`), до неё — посчитанная по потоку сессии.
func _render_summary() -> void:
	var summary := _summary
	if summary == null and _session != null:
		var zones: PowerZones = _profile.effective_power_zones() if _profile != null else PowerZones.coggan(_session.ftp_w)
		var hr_zones: HrZones = _profile.effective_hr_zones() if _profile != null else null
		summary = RideSummary.compute(_session.samples, _session.ftp_w, zones, hr_zones)
	var km := tr("ui.hud.unit.km")
	var unit_w := tr("ui.workout.unit_w")
	var distance_m: float = _session.distance_m() if _session != null else (summary.distance_m if summary != null else 0.0)
	var ascent_m: float = _session.ascent_m() if _session != null else (summary.ascent_m if summary != null else 0.0)
	var elapsed: int = _session.elapsed_sec() if _session != null else (summary.duration_sec if summary != null else 0)
	var card := _summary_root
	card.set_value("time", HudModel.format_elapsed(elapsed))
	card.set_value("distance", "%.1f %s" % [distance_m / 1000.0, km])
	card.set_value("avg_power", _with_unit(summary.avg_power_w if summary != null else -1, unit_w))
	card.set_value("np", _with_unit(summary.normalized_power_w if summary != null else -1, unit_w))
	card.set_value("avg_hr", _with_unit(summary.avg_hr if summary != null else -1, tr("ui.hud.unit.bpm")))
	card.set_value("ascent", "%d %s" % [roundi(ascent_m), tr("ui.free_ride.unit.m")])
	card.set_subtitle(tr(_session.route.name_key) if _session != null else "")
	card.set_paused_sec(float(_session.metadata().get("paused_total_sec", 0.0)) if _session != null else 0.0)
	card.set_history_enabled(not _ride_id.is_empty())
	card.fit()


static func _with_unit(value: int, unit: String) -> String:
	return ("%d %s" % [value, unit]) if value >= 0 else HudModel.NO_DATA_TEXT


# ---------------------------------------------------------------------------
# Раскладка и 3D в физическом разрешении
# ---------------------------------------------------------------------------

func _on_resized() -> void:
	_fit_viewport()
	_layout_hud()


## Вьюпорт 3D — в пикселях окна; контейнер уменьшен `scale` обратно до размера экрана.
func _fit_viewport() -> void:
	var lp := size
	if lp.x <= 0.0 or lp.y <= 0.0:
		return
	var px_per_lp := _px_per_lp()
	var px := Vector2i(maxi(roundi(lp.x * px_per_lp.x), 1), maxi(roundi(lp.y * px_per_lp.y), 1))
	_viewport_container.position = Vector2.ZERO
	_viewport_container.scale = lp / Vector2(px)
	_viewport_container.size = Vector2(px)
	if _viewport.size != px:
		_viewport.size = px


func _px_per_lp() -> Vector2:
	var visible_lp := get_viewport_rect().size
	var window := get_window()
	if window == null or visible_lp.x <= 0.0 or visible_lp.y <= 0.0:
		return Vector2.ONE
	return Vector2(window.size) / visible_lp


## Расставить слоты HUD по `HudLayout` (общая часть — `HudScreenFrame`): рельеф — 0.40·H в
## левом слоте, сообщение «нет SIM» — в слоте подсказки.
func _layout_hud() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return
	var layout := _frame.layout()
	if layout == null:
		return
	_relief.position = Vector2.ZERO
	_relief.panel_width = layout.list_slot.size.x
	_relief.panel_height = ReliefPanel.preferred_height(size.y, layout.list_slot.size.y)
	_frame.place_hint_plate(_notice_plate, _notice_label)


func _ui_scale() -> UiScale:
	return get_node_or_null(^"/root/UiScaleRuntime") as UiScale


# ---------------------------------------------------------------------------
# 3D-сцена и плавное движение гонщика
# ---------------------------------------------------------------------------

## Сцена трассы: создаётся при первом старте с нужной трассой, дальше — `set_route` при смене.
func _ensure_ride_scene(route_id: String) -> void:
	if _ride_scene == null:
		_ride_scene = RIDE_SCENE.instantiate() as RideScene
		_ride_scene.name = "RideScene"
		_ride_scene.route_id = route_id
		_viewport.add_child(_ride_scene)
	elif _ride_scene.route_id != route_id:
		_ride_scene.set_route(route_id)
	# Гонщика ведёт экран (`_drive_rider`), собственный кадр сцены не нужен.
	_ride_scene.set_process(false)
	_ride_scene.speed_kmh = 0.0
	_ride_scene.distance_m = 0.0


func _reset_rider_tracking() -> void:
	_base_distance_m = _session.distance_m() if _session != null else 0.0
	_base_speed_mps = 0.0
	_base_sec = _session.elapsed_sec() if _session != null else -1
	_blend_offset_m = 0.0
	_last_session_time = _session.session_time_sec() if _session != null else 0.0


## Дистанция гонщика в сцене сейчас: от последнего сэмпла по скорости модели и времени сессии.
## На границе секунды база сменилась — разница старого и нового прогноза уходит в сдвиг,
## который гаснет за `POSITION_BLEND_SEC` секунд сессии (без рывков и без отставания).
func _tracked_distance_m() -> float:
	if _session == null:
		return 0.0
	var t: float = _session.session_time_sec()
	var old_prediction: float = _base_distance_m + _base_speed_mps * (t - float(_base_sec))
	if _session.elapsed_sec() != _base_sec:
		_base_distance_m = _session.distance_m()
		_base_speed_mps = _session.speed_kmh() / 3.6
		_base_sec = _session.elapsed_sec()
		var prediction: float = _base_distance_m + _base_speed_mps * (t - float(_base_sec))
		_blend_offset_m += old_prediction - prediction
		if absf(_blend_offset_m) > POSITION_SNAP_M:
			_blend_offset_m = 0.0
	var dt: float = maxf(t - _last_session_time, 0.0)
	_last_session_time = t
	_blend_offset_m *= exp(-dt / POSITION_BLEND_SEC)
	var predicted: float = _base_distance_m + _base_speed_mps * (t - float(_base_sec))
	return maxf(predicted + _blend_offset_m, 0.0)


## Кадр: поставить гонщика в позицию сессии (по модулю длины трассы сцены) и продвинуть сцену.
func _drive_rider(delta: float) -> void:
	if _ride_scene == null or _session == null or _ride_scene.track == null:
		return
	var running: bool = _session.get_state() == WorkoutSession.State.RUNNING
	var speed: float = _session.speed_kmh() if running else 0.0
	var route_len: float = _session.position.length_m()
	var track_len: float = _ride_scene.track.length_m()
	var k: float = track_len / route_len if route_len > 0.0 else 1.0
	var s: float = fposmod((_session.position.start_s_m() + _tracked_distance_m()) * k, track_len)
	# `advance` прибавит speed·dt — вычитаем заранее, чтобы после кадра гонщик стоял ровно в s.
	var dt: float = minf(delta, RideScene.MAX_FRAME_DELTA_SEC)
	_ride_scene.speed_kmh = speed
	_ride_scene.distance_m = fposmod(s - speed / 3.6 * dt, track_len)
	_ride_scene.advance(delta)


func _process(delta: float) -> void:
	_drive_rider(delta)


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

## Время от тикера: в сессию и в отсчёт показа сообщения «нет SIM».
func _on_ticked(delta_sec: float) -> void:
	if _session == null:
		return
	_session.tick(delta_sec)
	if _notice_left_sec > 0.0:
		_notice_left_sec = maxf(_notice_left_sec - delta_sec, 0.0)
		if _notice_left_sec <= 0.0 and _hud != null:
			_render()


func _on_second_elapsed(_elapsed_sec: int) -> void:
	_relief.sync(_session)
	_chart.sync_free_ride(_session)
	if _ride_scene != null and _ride_scene.is_node_ready():
		var row: Dictionary = _session.samples.last_row()
		var cadence: int = int(row["cadence_rpm"]) if row.get("has_cadence", false) else 0
		_ride_scene.cadence_rpm = cadence
		_ride_scene.rider().set_cadence(cadence)
		_ride_scene.rider().set_wheel_speed(_session.speed_kmh())


func _on_hud_changed(_state: Dictionary) -> void:
	if _session != null and _session.get_state() != WorkoutSession.State.FINISHED:
		_render()


func _on_session_state(state: int) -> void:
	match state:
		WorkoutSession.State.PAUSED:
			_pause_overlay.show_pause()
			if _ride_scene != null and _ride_scene.is_node_ready():
				_ride_scene.rider().set_cadence(0)
				_ride_scene.rider().set_wheel_speed(0.0)
		WorkoutSession.State.RUNNING:
			if _pause_overlay.view() == PauseOverlay.View.PAUSE:
				_pause_overlay.hide_overlay()
		WorkoutSession.State.FINISHED:
			_frame_probe.finish({"elapsed_s": _session.elapsed_sec(), "distance_m": roundi(_session.distance_m())})
			if _ticker != null:
				_ticker.stop()
			if _connections != null:
				_connections.ticks_devices = true
			if _ride_scene != null and _ride_scene.is_node_ready():
				_ride_scene.speed_kmh = 0.0
				_ride_scene.rider().set_cadence(0)
				_ride_scene.rider().set_wheel_speed(0.0)
			_pause_overlay.hide_overlay()
	_apply_keep_awake()
	refresh()


## После `RideRecorder` (он подписан на `state_changed` раньше) — владелец забирает заезд.
func _on_session_finished() -> void:
	session_finished.emit(_session)
	refresh()


func _on_mode_changed(_mode: int) -> void:
	if _hud != null:
		_render()


func _on_steepness_changed(percent: int) -> void:
	if _profile != null:
		_profile.sim_steepness_pct = percent
		profile_updated.emit(_profile)


func _on_resistance_changed(percent: int) -> void:
	if _profile != null:
		_profile.resistance_level_default = percent
		profile_updated.emit(_profile)


## Станок не поддерживает SIM (FRD-04 крит. 6): сообщение в слоте подсказки на `NOTICE_SEC`.
func _on_simulation_unavailable() -> void:
	_notice_left_sec = NOTICE_SEC
	if _hud != null:
		_render()


## Горячие клавиши и показ панели инструментов — только пока экран виден и идёт сессия:
## скрытый экран не должен перехватывать Esc и `+`/`−` у других экранов.
func _update_input_gates() -> void:
	var active := is_visible_in_tree() and is_session_active()
	_toolbar.hotkeys_enabled = active and not is_finish_confirmation_pending()
	_toolbar.set_process_input(active)
	_toolbar.set_process_unhandled_key_input(active)
	_pause_overlay.set_process_input(is_visible_in_tree())


func _apply_keep_awake() -> void:
	var state: int = _session.get_state() if _session != null else WorkoutSession.State.IDLE
	_set_keep_on(is_visible_in_tree() and KeepAwake.wants_keep_on(state))


## Запрет гашения экрана (REQ-NFR-04): тот же вызов, что у `KeepAwake`, только при смене.
func _set_keep_on(keep_on: bool) -> void:
	if keep_on == _keep_on:
		return
	_keep_on = keep_on
	if keep_awake_setter.is_valid():
		keep_awake_setter.call(keep_on)
	else:
		DisplayServer.screen_set_keep_on(keep_on)


func is_keep_awake_on() -> bool:
	return _keep_on


func _teardown_session() -> void:
	if _ticker != null:
		_ticker.stop()
		if _ticker.ticked.is_connected(_on_ticked):
			_ticker.ticked.disconnect(_on_ticked)
		_ticker.queue_free()
		_ticker = null
	if _hud != null:
		if _hud.changed.is_connected(_on_hud_changed):
			_hud.changed.disconnect(_on_hud_changed)
		_hud.dispose()
		_hud = null
	if _session != null:
		if is_session_active():
			_session.stop()
		for pair: Array in [[_session.state_changed, _on_session_state],
				[_session.session_finished, _on_session_finished],
				[_session.second_elapsed, _on_second_elapsed],
				[_session.mode_changed, _on_mode_changed],
				[_session.steepness_changed, _on_steepness_changed],
				[_session.resistance_level_changed, _on_resistance_changed],
				[_session.simulation_unavailable, _on_simulation_unavailable]]:
			var sig: Signal = pair[0]
			if sig.is_connected(pair[1]):
				sig.disconnect(pair[1])
		_session.dispose()
		_session = null
	if _connections != null:
		_connections.ticks_devices = true
	if is_node_ready():
		_pause_overlay.hide_overlay()
	set_process(false)
	_set_keep_on(false)


func _exit_tree() -> void:
	on_screen_exited()
