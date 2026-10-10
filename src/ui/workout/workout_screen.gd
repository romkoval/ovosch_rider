class_name WorkoutScreen
extends Control
## Экран тренировки (`AppState.Screen.WORKOUT`): собирает `WorkoutSession`, один
## `SessionTicker`, `HudModel`, `KeepAwake` и отрисовывает HUD (REQ-HUD-01..14,
## REQ-WRK-03..07, REQ-NFR-04). Зависимости приходят через `setup()`; станок — любой
## `TrainerDevice` (в приложении — `SensorHub` из `ConnectionManager`, в режиме
## разработки — эмулятор из `TrainerFactory`). При переданном `ConnectionManager`
## экран ставит `ticks_devices = false` на время сессии, чтобы устройства не
## получали время дважды, и возвращает `true` по завершении.
##
## Раскладка HUD — `HudLayout` (`docs/game/hud.md` п. 4.1, REQ-HUD-13): панель цифр
## `HudMetricPanel` сверху по центру; левый слот — список интервалов `IntervalList`
## (HUD-13 крит. 2, 3); слот графика — `HudChart` во всю ширину низа с градиентом над
## подложкой (HUD-10..12, заменяет полосу прогресса HUD-07); слот подсказки — подсказка
## плана (HUD-08) или фишка «ДАЛЕЕ» `NextChip` за 5 с до смены шага (HUD-06 крит. 2, она
## вытесняет подсказку); фишки статусов и кнопка паузы справа сверху; панель инструментов
## `HudToolbar` (режим «план») у правого края. `PauseOverlay` — вуаль и карточка паузы с
## подтверждением досрочного завершения (WRK-05) — лежит между 3D и HUD.
## График и список синхронизируются с сессией на каждом пересчёте `HudModel` (сэмпл, смена
## шага, пропуск, множитель, пауза); на паузе исполнитель стоит — курсор и линии тоже.
## Общая с экраном свободной езды часть — фишки статусов, расстановка слотов, панель
## инструментов, плашки слота подсказки и Esc на карточке паузы — в `HudScreenFrame`.
##
## «Назад» (Esc — через панель инструментов или на карточке паузы; системный «назад» —
## оболочка): подтверждение досрочного завершения (REQ-UIX-04 крит. 2, WRK-05 крит. 4); пауза —
## кнопкой паузы.
##
## Тренировка по плану идёт на трассе `RideScene` по умолчанию (`flat`); уклон на станок
## не уходит (только ERG/сопротивление сессии), скорость — по D3D-02 в `RideScene`.
##
## 3D-фон — `RideScene` в `SubViewport` (REQ-D3D-01) в физическом разрешении окна
## (REQ-HUD-13 крит. 10, `hud.md` п. 3): размер вьюпорта = размер экрана в пикселях окна,
## контейнер уменьшен `scale` обратно в lp холста, поэтому при растяжении `canvas_items`
## сцена не растягивается из меньшего растра. Вьюпорт рисуется, только пока экран виден.
## На время экрана включается масштаб HUD (`UiScaleRuntime.set_mode(UiScale.Mode.HUD)`).
##
## Строки — через ключи `ui.workout.*`, `ui.hud.*` и `ui.hud_controls.*`; значения HUD
## берутся из `HudModel.state()`. После FINISHED показывается итог (`RideSummaryCard`, общий со
## свободной ездой; `ui.md` п. 8.8, REQ-HUD-14 крит. 7): карточка на вуали, «Тренировка завершена»,
## название тренировки, плитки — время, дистанция, ср. мощность, NP, ср. пульс, работа (по сводке
## LOC-04 потока сессии), паузы — только если были; «Открыть в истории» и «На главный».
## Сохранение заезда — по сигналу `session_finished(session)`; id сохранённого заезда владелец
## сообщает `set_saved_ride_id`.
##
## Режим сессии без управляемого станка (`power_meter`, REQ-WRK-09 п.5 (д), (е)): на панели
## инструментов нет ERG и сопротивления, E без действия (`HudToolbar.set_controls_trainer`);
## фишка режима вместо «ERG» — «БЕЗ СТАНКА» (точка `hud.text2`).

const UNIT_KEY: String = "ui.workout.unit_w"
const ICON_PAUSE: Texture2D = preload("res://assets/icons/lucide/pause.svg")
const ICON_PLAY: Texture2D = preload("res://assets/icons/lucide/play.svg")
## Ключи текстов списка интервалов и легенды графика (`strings_hud.csv`).
const LIST_FREE_KEY: String = "ui.hud.interval_list.free"
const LIST_REMAINING_KEY: String = "ui.hud.interval_list.remaining"
const LIST_STEP_OF_KEY: String = "ui.hud.interval_list.step_of"
const CHART_LEGEND_POWER_KEY: String = "ui.hud.chart.legend_power"
const CHART_LEGEND_HR_KEY: String = "ui.hud.chart.legend_hr"

## Сессия создана и сейчас стартует — владелец подключает запись заезда (`RideRecorder`, REQ-LOC-07).
signal session_created(session: WorkoutSession)
## Сессия завершена (по плану или досрочно) — хук для сохранения заезда (этап 5).
signal session_finished(session: WorkoutSession)
## Профиль изменён экраном (уровень сопротивления) — владелец сохраняет.
signal profile_updated(profile: Profile)
## «Открыть в истории» на итоге: `ride_id` сохранённого заезда ("" — неизвестен).
signal history_requested(ride_id: String)

## Плитки итога (`ui.md` п. 8.8): ключ → ключ подписи. У тренировки по плану набора нет
## (трасса по умолчанию ровная) — вместо него работа, кДж.
const SUMMARY_STATS: Array[Dictionary] = [
	{"key": "time", "caption": "ui.free_ride.summary.time"},
	{"key": "distance", "caption": "ui.free_ride.summary.distance"},
	{"key": "avg_power", "caption": "ui.free_ride.summary.avg_power"},
	{"key": "np", "caption": "ui.free_ride.summary.np"},
	{"key": "avg_hr", "caption": "ui.free_ride.summary.avg_hr"},
	{"key": "work", "caption": "ui.summary.work"},
]
const SUMMARY_TITLE_KEY: String = "ui.workout.finished"

## Подставляемые часы тикера (пусто — системные).
var clock_usec: Callable = Callable()
## Подставляемый сеттер KeepAwake (пусто — DisplayServer).
var keep_awake_setter: Callable = Callable()

var _workout: Workout
var _profile: Profile
var _trainer: TrainerDevice
var _app_state: AppState
var _connections: ConnectionManager
var _session: WorkoutSession
var _ticker: SessionTicker
var _hud: HudModel
var _keep_awake: KeepAwake
var _stop_pending: bool = false
var _ride_id: String = ""
## Общая рамка HUD: фишки, слоты, панель инструментов, слот подсказки, Esc на карточке паузы.
var _frame: HudScreenFrame
## Статистика кадров заезда в журнал (T-116a): от старта сессии до FINISHED.
var _frame_probe: FrameStatsProbe

@onready var _ride_scene: RideScene = %RideScene
@onready var _viewport_container: SubViewportContainer = %ViewportContainer
@onready var _viewport: SubViewport = %Viewport
@onready var _pause_overlay: PauseOverlay = %PauseOverlay
@onready var _hud_root: Control = %HudRoot
@onready var _summary_root: RideSummaryCard = %SummaryRoot
@onready var _no_session_label: Label = %NoSessionLabel
@onready var _metric_panel: HudMetricPanel = %MetricPanel
@onready var _list_slot: Control = %ListSlot
@onready var _interval_list: IntervalList = %IntervalList
@onready var _chart_slot: Control = %ChartSlot
@onready var _chart: HudChart = %Chart
@onready var _hint_slot: Control = %HintSlot
@onready var _cue_plate: PanelContainer = %CuePlate
@onready var _cue_label: Label = %CueLabel
@onready var _next_chip: NextChip = %NextChip
@onready var _status_slot: Control = %StatusSlot
@onready var _trainer_chip: Control = %TrainerChip
@onready var _connection_label: Label = %ConnectionLabel
@onready var _hr_chip: Control = %HrChip
@onready var _mode_chip: Control = %ModeChip
@onready var _mode_label: Label = %ModeStatusLabel
@onready var _intensity_chip: Control = %IntensityChip
@onready var _intensity_status_label: Label = %IntensityStatusLabel
@onready var _pause_button: Button = %PauseButton
@onready var _toolbar_slot: Control = %ToolbarSlot
@onready var _toolbar: HudToolbar = %Toolbar


## Подготовить тренировку. `connections` — опционально, для `ticks_devices`.
func setup(workout: Workout, profile: Profile, trainer: TrainerDevice, app_state: AppState,
		connections: ConnectionManager = null) -> void:
	_teardown()
	_workout = workout
	_profile = profile
	_trainer = trainer
	_app_state = app_state
	_connections = connections
	_ride_id = ""
	if is_node_ready():
		refresh()


func _ready() -> void:
	# Узлы-значения панели доступны по уникальным именам и от экрана (`%TargetLabel` и др.).
	_metric_panel.share_unique_names(self)
	var chips: Array[Control] = [_trainer_chip, _hr_chip, _mode_chip, _intensity_chip]
	_frame = HudScreenFrame.new(self, chips)
	_chart.legend_power_key = CHART_LEGEND_POWER_KEY
	_chart.legend_hr_key = CHART_LEGEND_HR_KEY
	_interval_list.free_text_key = LIST_FREE_KEY
	_interval_list.remaining_key = LIST_REMAINING_KEY
	_interval_list.step_counter_key = LIST_STEP_OF_KEY
	_toolbar.set_mode(HudToolbar.Mode.PLAN)
	_toolbar.pause_requested.connect(_on_toolbar_escape)
	_toolbar.erg_toggle_requested.connect(toggle_erg)
	_toolbar.intensity_step_requested.connect(_on_intensity_step)
	_toolbar.resistance_step_requested.connect(adjust_resistance)
	_toolbar.skip_requested.connect(skip_step)
	_toolbar.finish_requested.connect(_on_finish_requested)
	_pause_overlay.set_mode(HudToolbar.Mode.PLAN)
	_pause_overlay.resume_requested.connect(_on_resume_requested)
	_pause_overlay.skip_requested.connect(skip_step)
	_pause_overlay.finish_confirmed.connect(confirm_stop)
	_pause_overlay.finish_cancelled.connect(_on_finish_cancelled)
	_next_chip.minimum_size_changed.connect(_place_next_chip)
	resized.connect(_on_resized)
	visibility_changed.connect(_update_hotkeys)
	get_viewport().size_changed.connect(_on_resized)
	_pause_button.pressed.connect(toggle_pause)
	# Итог: кнопки — цель `touch_hud` (их цепляет `RideSummaryCard`), узлы — `%HomeButton`, `%HistoryButton`.
	_summary_root.share_unique_names(self)
	_summary_root.setup_stats(SUMMARY_STATS)
	_summary_root.set_title(SUMMARY_TITLE_KEY)
	_summary_root.home_requested.connect(go_home)
	_summary_root.history_requested.connect(open_history)
	_frame.install_escape_guard(_on_escape_on_pause_card)
	_frame_probe = FrameStatsProbe.attach(self)
	_fit_viewport()
	refresh()


# ---------------------------------------------------------------------------
# Жизненный цикл сессии
# ---------------------------------------------------------------------------

## Создать сессию, HUD, KeepAwake и тикер; запустить. false — не настроен.
func start() -> bool:
	if _workout == null or _trainer == null or not is_node_ready():
		return false
	_teardown_session()
	var ftp: int = _profile.ftp_w if _profile != null else 200
	var intensity: float = float(_profile.intensity_default) / 100.0 if _profile != null else 1.0
	var weight: float = _profile.weight_kg if _profile != null else WorkoutSession.DEFAULT_WEIGHT_KG
	# Уклон модели скорости — по трассе сцены (D3D-08 п.13, У-30).
	_session = WorkoutSession.new(_workout, _trainer, ftp, intensity, weight, _ride_scene.route_id)
	if _profile != null:
		_session.resistance_level = WorkoutSession.snap_resistance(_profile.resistance_level_default)
	_session.resistance_level_changed.connect(_on_resistance_level_changed)
	_session.state_changed.connect(_on_session_state)
	_toolbar.set_controls_trainer(_session.controls_trainer())
	_hud = HudModel.new(_session, _profile)
	_hud.changed.connect(_on_hud_changed)
	_bind_plan_views()
	_keep_awake = KeepAwake.new(keep_awake_setter)
	_keep_awake.attach(_session)
	_ticker = SessionTicker.new(clock_usec)
	_ticker.name = "SessionTicker"
	_ticker.attach(_session)
	add_child(_ticker)
	if _connections != null:
		_connections.ticks_devices = false
	_stop_pending = false
	_ride_scene.bind(_session, _profile)
	_frame_probe.begin({"mode": "workout", "route": _ride_scene.route_id}, _viewport)
	session_created.emit(_session)
	_session.start()
	_ticker.start()
	refresh()
	return true


## График и список — по плану сессии, зонам и пульсу профиля (REQ-HUD-10..13).
func _bind_plan_views() -> void:
	var zones: PowerZones = _profile.effective_power_zones() if _profile != null else null
	var max_hr: int = _profile.max_hr if _profile != null else 0
	_chart.set_plan(PlanChartModel.for_session(_session, zones),
			EffortSeries.new(EffortSeries.MODE_PLAN, _session.executor.ftp_w, max_hr))
	_interval_list.setup(_session, zones)
	_interval_list.skip_animation()
	_next_chip.hide_chip()
	_pause_overlay.hide_overlay()
	_toolbar.set_paused(false)


func session() -> WorkoutSession:
	return _session


func ticker() -> SessionTicker:
	return _ticker


func hud() -> HudModel:
	return _hud


func keep_awake() -> KeepAwake:
	return _keep_awake


## 3D-фон под HUD.
func ride_scene() -> RideScene:
	return _ride_scene


## Размер изображения 3D-сцены в пикселях (REQ-HUD-13 крит. 10).
func ride_viewport_size() -> Vector2i:
	return _viewport.size


## Панель цифр HUD (`HudMetricPanel`).
func metric_panel() -> HudMetricPanel:
	return _metric_panel


## Нижний график плана (`HudChart`, REQ-HUD-10..12).
func chart() -> HudChart:
	return _chart


## Список интервалов (`IntervalList`, REQ-HUD-13 крит. 2, 3).
func interval_list() -> IntervalList:
	return _interval_list


## Фишка «ДАЛЕЕ» в слоте подсказки (`NextChip`, REQ-HUD-06 крит. 2).
func next_chip() -> NextChip:
	return _next_chip


## Вуаль и карточка паузы с подтверждением завершения (`PauseOverlay`, REQ-WRK-05).
func pause_overlay() -> PauseOverlay:
	return _pause_overlay


## Панель инструментов (`HudToolbar`, режим «план»).
func toolbar() -> HudToolbar:
	return _toolbar


## Текущая геометрия HUD (пересчитывается при смене размера и на каждой отрисовке).
func hud_layout() -> HudLayout:
	if _frame.current_layout() == null:
		_layout_hud()
	return _frame.current_layout()


## Левый слот (список интервалов). Содержимое ставится от его левого верхнего угла.
func list_slot() -> Control:
	return _list_slot


## Слот графика: прямоугольник градиента и графика (`hud_layout().chart_gradient` ∪ `chart`).
func chart_slot() -> Control:
	return _chart_slot


## Слот подсказки и фишки «ДАЛЕЕ».
func hint_slot() -> Control:
	return _hint_slot


## Колонка панели инструментов у правого края.
func toolbar_slot() -> Control:
	return _toolbar_slot


## Уход с экрана тренировки: снимаем запрет гашения (REQ-NFR-04 крит. 1) и возвращаем
## масштаб меню.
func on_screen_exited() -> void:
	if _keep_awake != null:
		_keep_awake.on_screen_exited()
	var ui := _ui_scale()
	if ui != null and ui.mode == UiScale.Mode.HUD:
		ui.set_mode(UiScale.Mode.MENU)


## Вход на экран: запрет гашения и масштаб HUD (`hud.md` п. 3).
func on_screen_entered() -> void:
	if _keep_awake != null:
		_keep_awake.on_screen_entered()
	var ui := _ui_scale()
	if ui != null and ui.mode != UiScale.Mode.HUD:
		ui.set_mode(UiScale.Mode.HUD)
	refresh()


# ---------------------------------------------------------------------------
# Управление
# ---------------------------------------------------------------------------

func toggle_pause() -> void:
	if _session == null:
		return
	match _session.get_state():
		WorkoutSession.State.RUNNING:
			_session.pause()
		WorkoutSession.State.PAUSED:
			_session.resume()
	refresh()


func skip_step() -> void:
	if _is_live():
		_session.skip_step()
		refresh()


## Стоп требует подтверждения (REQ-WRK-05 крит. 4): карточка подтверждения `PauseOverlay`.
func request_stop() -> bool:
	if not _is_live():
		return false
	_stop_pending = true
	_pause_overlay.show_finish_confirmation()
	return true


func confirm_stop() -> void:
	_stop_pending = false
	if _pause_overlay.view() == PauseOverlay.View.CONFIRM:
		_pause_overlay.hide_overlay()
	if _session != null:
		_session.stop()
	refresh()


func cancel_stop() -> void:
	_stop_pending = false
	# Карточка сама вернётся к паузе или уберёт вуаль и испустит `finish_cancelled`.
	_pause_overlay.cancel_finish()


func is_stop_confirmation_pending() -> bool:
	return _stop_pending


## ERG вкл/выкл одним нажатием (REQ-WRK-03 крит. 1).
func toggle_erg() -> void:
	if _is_live():
		_session.toggle_erg()
		refresh()


## Уровень сопротивления ±5 % (REQ-WRK-04 крит. 1).
func adjust_resistance(delta_pct: int) -> void:
	if _is_live():
		_session.set_resistance_level(_session.resistance_level + delta_pct)
		refresh()


## Множитель интенсивности ±5 % (REQ-WRK-07 крит. 1).
func adjust_intensity(delta: float) -> void:
	if _is_live():
		_session.set_intensity(_session.intensity() + delta)
		refresh()


## «Открыть в истории» на итоге.
func open_history() -> void:
	history_requested.emit(_ride_id)


## Владелец сообщает id сохранённого заезда этой сессии: «Открыть в истории» ведёт к нему.
func set_saved_ride_id(ride_id: String) -> void:
	_ride_id = ride_id
	if is_node_ready() and _summary_root.visible:
		_render_summary()


func saved_ride_id() -> String:
	return _ride_id


func go_home() -> void:
	on_screen_exited()
	if _app_state != null:
		_app_state.navigate(AppState.Screen.HOME)


## Сессия идёт или на паузе — органы управления действуют.
func _is_live() -> bool:
	return _session != null and _session.get_state() in [WorkoutSession.State.RUNNING, WorkoutSession.State.PAUSED]


## Esc панели инструментов (`pause_requested`) — как системное «назад» на этом экране:
## подтверждение досрочного завершения (REQ-UIX-04 крит. 2; решение по Esc одно для обоих
## экранов заезда). `hud.md` п. 10.3 называет Esc паузой, но панель ловит клавишу раньше
## `AppMain._unhandled_input`, и без этого Esc ставил бы паузу вместо подтверждения.
func _on_toolbar_escape() -> void:
	if _session != null and _session.get_state() == WorkoutSession.State.RUNNING:
		request_stop()


func _on_resume_requested() -> void:
	if _session != null and _session.get_state() == WorkoutSession.State.PAUSED:
		toggle_pause()


func _on_intensity_step(delta_pct: int) -> void:
	adjust_intensity(float(delta_pct) / 100.0)


func _on_finish_requested() -> void:
	request_stop()


## Esc на карточке паузы — подтверждение досрочного завершения, как системное «назад»
## (REQ-UIX-04 крит. 2: «назад» на паузе не завершает, а спрашивает). `PauseOverlay` на
## карточке паузы клавишу поглощает, поэтому её раньше перехватывает `_EscapeGuard`.
func _on_escape_on_pause_card() -> bool:
	if not is_visible_in_tree() or _pause_overlay.view() != PauseOverlay.View.PAUSE:
		return false
	return request_stop()


## «Отмена» на карточке подтверждения или Esc: тренировка продолжается.
func _on_finish_cancelled() -> void:
	_stop_pending = false
	refresh()


# ---------------------------------------------------------------------------
# Тексты (для тестов и отрисовки)
# ---------------------------------------------------------------------------

func target_text() -> String:
	return _metric_panel.target_text()


func power_text() -> String:
	return _metric_panel.power_text()


func deviation_text() -> String:
	return _metric_panel.deviation_text()


func power_zone_text() -> String:
	return _metric_panel.power_zone_text()


func hr_text() -> String:
	return _metric_panel.hr_text()


func cadence_text() -> String:
	return _metric_panel.cadence_text()


func speed_text() -> String:
	return _metric_panel.speed_text()


func elapsed_text() -> String:
	return _metric_panel.elapsed_text()


func countdown_text() -> String:
	return _metric_panel.countdown_text()


## «Шаг N/M» (`ui.workout.step`); на экране номер шага — в подвале списка интервалов.
func step_text() -> String:
	if _hud == null:
		return ""
	return tr("ui.workout.step").format({"step": _hud.state()["step_text"]})


## Полный текст состояния станка (подсказка фишки «СТАНОК»).
func connection_text() -> String:
	return _trainer_chip.tooltip_text


func cue_text() -> String:
	return _cue_label.text


## Сводка одной строкой (`{name} · {time} · {distance} км · сэмплов N`, паузы) — для проверок и
## журнала; на экране её нет: итог — карточка `RideSummaryCard` без служебных полей.
func summary_text() -> String:
	if _session == null or _session.get_state() != WorkoutSession.State.FINISHED:
		return ""
	var m := _session.metadata()
	return tr("ui.workout.summary").format({
		"name": m["workout_name"],
		"time": HudModel.format_elapsed(int(m["elapsed_sec"])),
		"distance": "%.1f" % (float(m["distance_m"]) / 1000.0),
		"samples": m["sample_count"],
		"early": tr("ui.workout.stopped_early") if m["stopped_early"] else "",
	}) + "\n" + tr("ui.workout.summary_paused").format({
		"paused": HudModel.format_elapsed(int(round(float(m["paused_total_sec"])))),
	})


## Значение плитки итога по ключу (`SUMMARY_STATS`).
func summary_value_text(stat: String) -> String:
	return _summary_root.value_text(stat)


## Карточка итога (`RideSummaryCard`).
func summary_card() -> RideSummaryCard:
	return _summary_root


## Регулятор сопротивления есть на панели инструментов (только при выключенном ERG).
func is_resistance_row_visible() -> bool:
	return _toolbar.visible_buttons().has(_toolbar.button(&"resistance_up"))


func is_summary_visible() -> bool:
	return _summary_root.visible


func is_countdown_accented() -> bool:
	return _metric_panel.is_countdown_accented()


# ---------------------------------------------------------------------------
# Отрисовка
# ---------------------------------------------------------------------------

## Перечитать модель и обновить все узлы.
func refresh() -> void:
	if not is_node_ready():
		return
	_update_hotkeys()
	if _session == null:
		_hud_root.visible = false
		_summary_root.visible = false
		_no_session_label.visible = true
		return
	_no_session_label.visible = false
	var finished: bool = _session.get_state() == WorkoutSession.State.FINISHED
	_hud_root.visible = not finished
	_summary_root.visible = finished
	if finished:
		_stop_pending = false
		_pause_overlay.hide_overlay()
		_toolbar.set_paused(true)
		_render_summary()
	else:
		_render()


func _on_hud_changed(_state: Dictionary) -> void:
	_render()


func _render() -> void:
	if _hud == null or _session == null or _session.get_state() == WorkoutSession.State.FINISHED:
		return
	var s := _hud.state()
	var paused: bool = s["session_state"] == WorkoutSession.State.PAUSED
	_metric_panel.set_state(_panel_state(s))
	_metric_panel.set_dimmed(paused)
	_render_status(s)
	# График и список — на каждом пересчёте: сэмпл, смена шага, пропуск, множитель, пауза.
	_chart.sync(_session)
	_interval_list.sync(_session)
	var segments := _hud.progress_segments()
	_render_hint(s, segments)
	_pause_button.text = tr("ui.workout.resume") if paused else tr("ui.workout.pause")
	_pause_button.icon = ICON_PLAY if paused else ICON_PAUSE
	_render_toolbar(s, paused)
	_render_pause(paused)
	_layout_hud()


## Состояние для панели цифр: `HudModel.state()` + доля шага, зона цели, каденс шага.
func _panel_state(s: Dictionary) -> Dictionary:
	var ex := _session.executor
	var step := ex.current_step()
	var duration: int = step.duration_sec if step != null else 0
	var target: int = int(s["target_w"])
	var zone: int = 0
	if target > 0:
		zone = _profile.power_zone_of(target) if _profile != null else Zones.power_zone(target, ex.ftp_w)
	s["step_fraction"] = 1.0 - float(ex.step_remaining_sec()) / float(duration) if duration > 0 else 0.0
	s["step_free"] = step != null and step.is_free_ride()
	s["target_zone_token"] = ZonePalette.power_token(zone)
	s["target_cadence_rpm"] = step.cadence_rpm if step != null else 0
	s["resistance_pct"] = _session.resistance_level
	return s


## Слот подсказки: за 5 с до смены шага — фишка «ДАЛЕЕ» со следующим шагом и секундами
## (HUD-06 крит. 2, `hud.md` п. 10.1), она вытесняет подсказку плана; иначе — подсказка HUD-08.
func _render_hint(s: Dictionary, segments: Array[Dictionary]) -> void:
	var next_index: int = int(s["step_index"]) + 1
	var steps := _session.executor.workout.steps
	# Секунды на фишке — 5…1; на 0 шаг уже сменяется (фишка уходит).
	var upcoming: bool = bool(s["about_to_change"]) and int(s["step_remaining_sec"]) >= 1 \
			and next_index > 0 and next_index < steps.size()
	if upcoming:
		var step: WorkoutStep = steps[next_index]
		var seg: Dictionary = segments[next_index] if next_index < segments.size() else {}
		var text: String
		var color: Color = UiTokens.HUD_FREE
		if step.is_free_ride() or seg.is_empty():
			text = NextChip.format_target(-1)
		else:
			text = NextChip.format_target(int(seg["start_watts"]), int(seg["end_watts"]))
			color = ZonePalette.color(str(seg["zone_token"]))
		_next_chip.show_next(step.duration_sec, text, color)
		_next_chip.set_seconds_left(int(s["step_remaining_sec"]))
	else:
		_next_chip.hide_chip()
	_cue_label.text = s["cue_text"]
	var has_cue := not str(s["cue_text"]).is_empty() and not _next_chip.is_shown()
	_cue_label.visible = has_cue
	_cue_plate.visible = has_cue


## Панель инструментов: ERG, множитель, сопротивление; на паузе молчит (паузой ведает карточка).
func _render_toolbar(s: Dictionary, paused: bool) -> void:
	# ERG недоступен на станке (DEV-10 п.5) — панель как при выключенном ERG, кнопка ERG неактивна.
	_toolbar.set_erg_available(bool(s["erg_available"]))
	_toolbar.set_erg_enabled(bool(s["erg_enabled"]) and bool(s["erg_available"]))
	_toolbar.set_intensity_pct(int(s["intensity_pct"]))
	_toolbar.set_resistance_pct(_session.resistance_level)
	_toolbar.set_paused(paused)


## Вуаль и карточка паузы следуют за состоянием сессии; открытое подтверждение не трогаем.
func _render_pause(paused: bool) -> void:
	var view := _pause_overlay.view()
	if paused and view == PauseOverlay.View.HIDDEN:
		_pause_overlay.show_pause()
	elif not paused and view == PauseOverlay.View.PAUSE:
		_pause_overlay.hide_overlay()


## Горячие клавиши панели — только пока экран виден и сессия идёт.
func _update_hotkeys() -> void:
	if _toolbar != null:
		_toolbar.hotkeys_enabled = is_visible_in_tree() and _is_live()


## Фишка режима: «ERG» или, без управляемого станка, «БЕЗ СТАНКА» (`hud.md` п. 16.1).
func mode_chip_text() -> String:
	return _mode_label.text


## Заезд идёт на эмуляторе станка (T-150 п.3): признак интерфейса `TrainerDevice`, без
## проверки класса реализации.
func is_emulator_ride() -> bool:
	return _trainer != null and _trainer.is_emulator()


## Фишки статусов (`hud.md` п. 10.3): станок (у эмулятора — «ЭМУЛЯТОР»), пульс, ERG
## (без станка — «БЕЗ СТАНКА»),
## интенсивность ≠ 100 %.
func _render_status(s: Dictionary) -> void:
	# Заезд на эмуляторе: фишка станка подписана «ЭМУЛЯТОР», чтобы фиктивный заезд не приняли
	# за настоящий (T-150 п.3); место и вид фишки те же.
	var emulator := is_emulator_ride()
	_connection_label.text = tr(HudScreenFrame.KEY_STATUS_EMULATOR if emulator else HudScreenFrame.KEY_STATUS_TRAINER)
	_trainer_chip.tooltip_text = tr(s["connection_key"])
	_frame.set_dot(_trainer_chip, HudScreenFrame.connection_dot(int(s["connection_state"])))
	var has_hr: bool = int(s["hr_bpm"]) >= 0
	_hr_chip.tooltip_text = tr("ui.hud.status.hr_ok") if has_hr else tr("ui.hud.status.hr_missing")
	_frame.set_dot(_hr_chip, UiTokens.HUD_OK if has_hr else UiTokens.HUD_ERR)
	var erg_on: bool = s["erg_enabled"]
	_mode_label.text = tr("ui.hud.status.erg")
	_mode_chip.tooltip_text = tr("ui.workout.erg_on") if erg_on else tr("ui.workout.erg_off")
	if not _session.controls_trainer():
		_mode_label.text = tr("ui.hud.status.no_trainer")
		_mode_chip.tooltip_text = tr("ui.hud.status.no_trainer_hint")
		_frame.set_dot(_mode_chip, UiTokens.HUD_TEXT2)
	elif not bool(s["erg_available"]):
		# ERG недоступен — отдельное состояние, не ошибка команды (DEV-10 п.5, T-162).
		_mode_chip.tooltip_text = tr("ui.workout.erg_unavailable")
		_frame.set_dot(_mode_chip, UiTokens.HUD_TEXT2)
	elif not erg_on:
		_frame.set_dot(_mode_chip, UiTokens.HUD_TEXT2)
	else:
		_frame.set_dot(_mode_chip, UiTokens.HUD_OK if s["erg_active_on_trainer"] else UiTokens.HUD_WARN)
	var pct: int = int(s["intensity_pct"])
	_intensity_chip.visible = pct != 100
	_intensity_status_label.text = tr("ui.hud.status.intensity").format({"value": pct})
	_intensity_chip.tooltip_text = tr("ui.hud.status.intensity_hint").format({"value": pct})
	_frame.set_dot(_intensity_chip, UiTokens.HUD_WARN)
	_frame.redraw_chips()


# ---------------------------------------------------------------------------
# Раскладка и 3D в физическом разрешении
# ---------------------------------------------------------------------------

func _on_resized() -> void:
	_fit_viewport()
	_layout_hud()


## Вьюпорт 3D — в пикселях окна: размер экрана в lp × пикселей на lp; контейнер уменьшен
## `scale` обратно до размера экрана (REQ-HUD-13 крит. 10).
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


## Пикселей окна в одном lp холста этого экрана (по осям).
func _px_per_lp() -> Vector2:
	var visible_lp := get_viewport_rect().size
	var window := get_window()
	if window == null or visible_lp.x <= 0.0 or visible_lp.y <= 0.0:
		return Vector2.ONE
	return Vector2(window.size) / visible_lp


## Расставить слоты HUD по `HudLayout` (общая часть — `HudScreenFrame`) и компоненты в слотах:
## список интервалов в левом слоте, подсказку и фишку «ДАЛЕЕ» в слоте подсказки.
func _layout_hud() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return
	var layout := _frame.layout()
	if layout == null:
		return
	# Список интервалов: ширина `w_l`, высота по содержимому, не выше слота.
	_interval_list.position = Vector2.ZERO
	_interval_list.list_width = layout.list_slot.size.x
	_interval_list.max_height = layout.list_slot.size.y
	_frame.place_hint_plate(_cue_plate, _cue_label)
	_place_next_chip()


func _place_next_chip() -> void:
	_frame.place_next_chip(_next_chip)


func _ui_scale() -> UiScale:
	return get_node_or_null(^"/root/UiScaleRuntime") as UiScale


## Итог (`ui.md` п. 8.8): значения — сводка LOC-04 по потоку сессии с зонами профиля (та же, что
## `RideRecorder` сохраняет в заезд); подзаголовок — название тренировки (и «завершена досрочно»).
func _render_summary() -> void:
	var m := _session.metadata()
	var zones: PowerZones = _profile.effective_power_zones() if _profile != null else PowerZones.coggan(_session.executor.ftp_w)
	var hr_zones: HrZones = _profile.effective_hr_zones() if _profile != null else null
	var summary := RideSummary.compute(_session.samples, _session.executor.ftp_w, zones, hr_zones)
	var unit_w := tr(UNIT_KEY)
	var card := _summary_root
	card.set_value("time", HudModel.format_elapsed(summary.duration_sec))
	card.set_value("distance", "%.1f %s" % [summary.distance_m / 1000.0, tr("ui.hud.unit.km")])
	card.set_value("avg_power", _with_unit(summary.avg_power_w, unit_w))
	card.set_value("np", _with_unit(summary.normalized_power_w, unit_w))
	card.set_value("avg_hr", _with_unit(summary.avg_hr, tr("ui.hud.unit.bpm")))
	card.set_value("work", _with_unit(roundi(summary.work_kj) if summary.has_power() else -1, tr("ui.menu.unit.kj")))
	var subtitle := str(m["workout_name"])
	if bool(m["stopped_early"]):
		subtitle += HistoryFormat.DOT + tr("ui.summary.stopped_early")
	card.set_subtitle(subtitle)
	card.set_paused_sec(float(m["paused_total_sec"]))
	card.set_history_enabled(not _ride_id.is_empty())
	card.fit()


static func _with_unit(value: int, unit: String) -> String:
	return ("%d %s" % [value, unit]) if value >= 0 else HudModel.NO_DATA_TEXT


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _on_session_state(state: int) -> void:
	if state == WorkoutSession.State.FINISHED:
		_frame_probe.finish({"elapsed_s": _session.executor.elapsed_sec()})
		if _ticker != null:
			_ticker.stop()
		if _connections != null:
			_connections.ticks_devices = true
		if _ride_scene != null:
			_ride_scene.unbind()
		session_finished.emit(_session)
	refresh()


func _on_resistance_level_changed(percent: int) -> void:
	if _profile != null:
		_profile.resistance_level_default = percent
		profile_updated.emit(_profile)


func _teardown_session() -> void:
	if _ticker != null:
		_ticker.stop()
		_ticker.queue_free()
		_ticker = null
	if _keep_awake != null:
		_keep_awake.detach()
		_keep_awake = null
	if _session != null and _session.get_state() in [WorkoutSession.State.RUNNING, WorkoutSession.State.PAUSED]:
		_session.stop()
	if _connections != null:
		_connections.ticks_devices = true
	if _ride_scene != null:
		_ride_scene.unbind()
	_session = null
	_hud = null
	_stop_pending = false


func _teardown() -> void:
	_teardown_session()
	_workout = null
	_trainer = null


func _exit_tree() -> void:
	on_screen_exited()
