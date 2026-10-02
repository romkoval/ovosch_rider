class_name WorkoutScreen
extends Control
## Экран тренировки (`AppState.Screen.WORKOUT`): собирает `WorkoutSession`, один
## `SessionTicker`, `HudModel`, `KeepAwake` и отрисовывает HUD (REQ-HUD-01..09,
## REQ-WRK-03..07, REQ-NFR-04). Зависимости приходят через `setup()`; станок — любой
## `TrainerDevice` (в приложении — `SensorHub` из `ConnectionManager`, в режиме
## разработки — эмулятор из `TrainerFactory`). При переданном `ConnectionManager`
## экран ставит `ticks_devices = false` на время сессии, чтобы устройства не
## получали время дважды, и возвращает `true` по завершении.
##
## Строки — через ключи `ui.workout.*`; значения HUD берутся из `HudModel.state()`.
## После FINISHED показывается сводка-заглушка с кнопкой «На главный»; сохранение
## заезда — этап 5, для него есть сигнал `session_finished(session)`.

const UNIT_KEY: String = "ui.workout.unit_w"
const RESISTANCE_STEP: int = 5
const INTENSITY_STEP: float = 0.05
## Размер шрифта цели (≥ 2× метрик, REQ-HUD-01 крит. 3).
const TARGET_FONT_SIZE: int = 96
const METRIC_FONT_SIZE: int = 40

## Сессия завершена (по плану или досрочно) — хук для сохранения заезда (этап 5).
signal session_finished(session: WorkoutSession)
## Профиль изменён экраном (уровень сопротивления) — владелец сохраняет.
signal profile_updated(profile: Profile)

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

@onready var _hud_root: Control = %HudRoot
@onready var _summary_root: Control = %SummaryRoot
@onready var _no_session_label: Label = %NoSessionLabel
@onready var _target_label: Label = %TargetLabel
@onready var _power_label: Label = %PowerLabel
@onready var _deviation_label: Label = %DeviationLabel
@onready var _power_zone_label: Label = %PowerZoneLabel
@onready var _hr_label: Label = %HrLabel
@onready var _hr_zone_label: Label = %HrZoneLabel
@onready var _cadence_label: Label = %CadenceLabel
@onready var _speed_label: Label = %SpeedLabel
@onready var _elapsed_label: Label = %ElapsedLabel
@onready var _countdown_label: Label = %CountdownLabel
@onready var _step_label: Label = %StepLabel
@onready var _connection_label: Label = %ConnectionLabel
@onready var _cue_label: Label = %CueLabel
@onready var _progress_bar: WorkoutProgressBar = %ProgressBar
@onready var _pause_button: Button = %PauseButton
@onready var _skip_button: Button = %SkipButton
@onready var _stop_button: Button = %StopButton
@onready var _erg_button: Button = %ErgButton
@onready var _resistance_row: Control = %ResistanceRow
@onready var _resistance_label: Label = %ResistanceLabel
@onready var _resistance_minus: Button = %ResistanceMinus
@onready var _resistance_plus: Button = %ResistancePlus
@onready var _intensity_label: Label = %IntensityLabel
@onready var _intensity_minus: Button = %IntensityMinus
@onready var _intensity_plus: Button = %IntensityPlus
@onready var _stop_dialog: ConfirmationDialog = %StopDialog
@onready var _summary_label: Label = %SummaryLabel
@onready var _home_button: Button = %HomeButton


## Подготовить тренировку. `connections` — опционально, для `ticks_devices`.
func setup(workout: Workout, profile: Profile, trainer: TrainerDevice, app_state: AppState,
		connections: ConnectionManager = null) -> void:
	_teardown()
	_workout = workout
	_profile = profile
	_trainer = trainer
	_app_state = app_state
	_connections = connections
	if is_node_ready():
		refresh()


func _ready() -> void:
	_target_label.add_theme_font_size_override("font_size", TARGET_FONT_SIZE)
	for label in [_power_label, _hr_label, _cadence_label, _speed_label, _elapsed_label, _countdown_label]:
		(label as Label).add_theme_font_size_override("font_size", METRIC_FONT_SIZE)
	_pause_button.pressed.connect(toggle_pause)
	_skip_button.pressed.connect(skip_step)
	_stop_button.pressed.connect(func() -> void: request_stop())
	_erg_button.pressed.connect(toggle_erg)
	_resistance_minus.pressed.connect(func() -> void: adjust_resistance(-RESISTANCE_STEP))
	_resistance_plus.pressed.connect(func() -> void: adjust_resistance(RESISTANCE_STEP))
	_intensity_minus.pressed.connect(func() -> void: adjust_intensity(-INTENSITY_STEP))
	_intensity_plus.pressed.connect(func() -> void: adjust_intensity(INTENSITY_STEP))
	_stop_dialog.confirmed.connect(func() -> void: confirm_stop())
	_stop_dialog.canceled.connect(func() -> void: _stop_pending = false)
	_home_button.pressed.connect(go_home)
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
	_session = WorkoutSession.new(_workout, _trainer, ftp, intensity, weight)
	if _profile != null:
		_session.resistance_level = WorkoutSession.snap_resistance(_profile.resistance_level_default)
	_session.resistance_level_changed.connect(_on_resistance_level_changed)
	_session.state_changed.connect(_on_session_state)
	_hud = HudModel.new(_session, _profile)
	_hud.changed.connect(func(_s: Dictionary) -> void: _render())
	_keep_awake = KeepAwake.new(keep_awake_setter)
	_keep_awake.attach(_session)
	_ticker = SessionTicker.new(clock_usec)
	_ticker.name = "SessionTicker"
	_ticker.attach(_session)
	add_child(_ticker)
	if _connections != null:
		_connections.ticks_devices = false
	_stop_pending = false
	_session.start()
	_ticker.start()
	refresh()
	return true


func session() -> WorkoutSession:
	return _session


func ticker() -> SessionTicker:
	return _ticker


func hud() -> HudModel:
	return _hud


func keep_awake() -> KeepAwake:
	return _keep_awake


func progress_bar() -> WorkoutProgressBar:
	return _progress_bar


## Уход с экрана тренировки: снимаем запрет гашения (REQ-NFR-04 крит. 1).
func on_screen_exited() -> void:
	if _keep_awake != null:
		_keep_awake.on_screen_exited()


func on_screen_entered() -> void:
	if _keep_awake != null:
		_keep_awake.on_screen_entered()
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
	if _session != null:
		_session.skip_step()
		refresh()


## Стоп требует подтверждения (REQ-WRK-05 крит. 4): показывает диалог.
func request_stop() -> bool:
	if _session == null or _session.get_state() == WorkoutSession.State.FINISHED:
		return false
	_stop_pending = true
	_stop_dialog.popup_centered()
	return true


func confirm_stop() -> void:
	_stop_pending = false
	if _session != null:
		_session.stop()
	refresh()


func cancel_stop() -> void:
	_stop_pending = false
	_stop_dialog.hide()


func is_stop_confirmation_pending() -> bool:
	return _stop_pending


## ERG вкл/выкл одним нажатием (REQ-WRK-03 крит. 1).
func toggle_erg() -> void:
	if _session != null:
		_session.toggle_erg()
		refresh()


## Уровень сопротивления ±5 % (REQ-WRK-04 крит. 1).
func adjust_resistance(delta_pct: int) -> void:
	if _session != null:
		_session.set_resistance_level(_session.resistance_level + delta_pct)
		refresh()


## Множитель интенсивности ±5 % (REQ-WRK-07 крит. 1).
func adjust_intensity(delta: float) -> void:
	if _session != null:
		_session.set_intensity(_session.intensity() + delta)
		refresh()


func go_home() -> void:
	on_screen_exited()
	if _app_state != null:
		_app_state.navigate(AppState.Screen.HOME)


# ---------------------------------------------------------------------------
# Тексты (для тестов и отрисовки)
# ---------------------------------------------------------------------------

func target_text() -> String:
	return _target_label.text


func power_text() -> String:
	return _power_label.text


func deviation_text() -> String:
	return _deviation_label.text


func power_zone_text() -> String:
	return _power_zone_label.text


func hr_text() -> String:
	return _hr_label.text


func cadence_text() -> String:
	return _cadence_label.text


func speed_text() -> String:
	return _speed_label.text


func elapsed_text() -> String:
	return _elapsed_label.text


func countdown_text() -> String:
	return _countdown_label.text


func step_text() -> String:
	return _step_label.text


func connection_text() -> String:
	return _connection_label.text


func cue_text() -> String:
	return _cue_label.text


func summary_text() -> String:
	return _summary_label.text


func is_resistance_row_visible() -> bool:
	return _resistance_row.visible


func is_summary_visible() -> bool:
	return _summary_root.visible


func is_countdown_accented() -> bool:
	return _countdown_label.modulate != Color.WHITE


# ---------------------------------------------------------------------------
# Отрисовка
# ---------------------------------------------------------------------------

## Перечитать модель и обновить все узлы.
func refresh() -> void:
	if not is_node_ready():
		return
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
		_render_summary()
	else:
		_render()


func _render() -> void:
	if _hud == null or _session == null or _session.get_state() == WorkoutSession.State.FINISHED:
		return
	var s := _hud.state()
	_target_label.text = tr("ui.workout.target_value").format({"value": s["target_text"]}) if s["target_w"] >= 0 else HudModel.NO_DATA_TEXT
	_power_label.text = tr("ui.workout.target_value").format({"value": s["power_text"]}) if s["smoothed_power_w"] >= 0 else HudModel.NO_DATA_TEXT
	match str(s["power_deviation"]):
		HudModel.DEVIATION_ABOVE:
			_deviation_label.text = "▲"
			_deviation_label.modulate = ZonePalette.COLORS["orange"]
		HudModel.DEVIATION_BELOW:
			_deviation_label.text = "▼"
			_deviation_label.modulate = ZonePalette.COLORS["blue"]
		HudModel.DEVIATION_ON:
			_deviation_label.text = "●"
			_deviation_label.modulate = ZonePalette.COLORS["green"]
		_:
			_deviation_label.text = ""
			_deviation_label.modulate = Color.WHITE
	_power_zone_label.text = s["power_zone_text"]
	_power_zone_label.modulate = ZonePalette.color(s["power_zone_token"])
	_hr_label.text = s["hr_text"]
	_hr_zone_label.text = s["hr_zone_text"]
	_hr_zone_label.modulate = ZonePalette.color(s["hr_zone_token"])
	_cadence_label.text = s["cadence_text"]
	_speed_label.text = s["speed_text"]
	_elapsed_label.text = s["elapsed_text"]
	_countdown_label.text = s["countdown_text"]
	_countdown_label.modulate = ZonePalette.COLORS["orange"] if s["about_to_change"] else Color.WHITE
	_step_label.text = tr("ui.workout.step").format({"step": s["step_text"]})
	_connection_label.text = s["connection_text"]
	_cue_label.text = s["cue_text"]
	_cue_label.visible = not str(s["cue_text"]).is_empty()
	_pause_button.text = tr("ui.workout.resume") if s["session_state"] == WorkoutSession.State.PAUSED else tr("ui.workout.pause")
	_erg_button.text = tr("ui.workout.erg_on") if s["erg_enabled"] else tr("ui.workout.erg_off")
	_resistance_row.visible = not s["erg_enabled"]
	_resistance_label.text = tr("ui.workout.resistance").format({"value": _session.resistance_level})
	_intensity_label.text = tr("ui.workout.intensity").format({"value": s["intensity_pct"]})
	_progress_bar.set_segments(_hud.progress_segments(), _hud.cursor())


func _render_summary() -> void:
	var m := _session.metadata()
	_summary_label.text = tr("ui.workout.summary").format({
		"name": m["workout_name"],
		"time": HudModel.format_elapsed(int(m["elapsed_sec"])),
		"distance": "%.1f" % (float(m["distance_m"]) / 1000.0),
		"samples": m["sample_count"],
		"early": tr("ui.workout.stopped_early") if m["stopped_early"] else "",
	})


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _on_session_state(state: int) -> void:
	if state == WorkoutSession.State.FINISHED:
		if _ticker != null:
			_ticker.stop()
		if _connections != null:
			_connections.ticks_devices = true
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
	_session = null
	_hud = null


func _teardown() -> void:
	_teardown_session()
	_workout = null
	_trainer = null


func _exit_tree() -> void:
	on_screen_exited()
