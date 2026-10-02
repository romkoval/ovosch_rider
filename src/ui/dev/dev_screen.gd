class_name DevScreen
extends Control
## Экран разработчика (`AppState.Screen.DEV`): проигрывает тестовый план на
## эмуляторе станка без железа (REQ-DEV-09 крит. 6, REQ-WRK-01 крит. 5, REQ-NFR-02 крит. 1).
##
## Устройство создаётся ТОЛЬКО через `TrainerFactory.create("fake")` — экран знает
## лишь интерфейс `TrainerDevice`; журнал команд эмулятора читается динамически
## (`get("commands")`), чтобы не зависеть от конкретной реализации.
## Время сессии ведёт `SessionTicker` от системных часов с `time_scale` 10;
## часы можно подставить через `clock_usec` (тесты).

const TRAINER_KIND: String = "fake"
const DEFAULT_FTP_W: int = 200
const DEFAULT_TIME_SCALE: float = 10.0
const COMMANDS_SHOWN: int = 5

## Подставляемые часы для `SessionTicker` (пусто — системные).
var clock_usec: Callable = Callable()
var ftp_w: int = DEFAULT_FTP_W

var _app_state: AppState
var _trainer: TrainerDevice
var _session: WorkoutSession
var _ticker: SessionTicker

@onready var _status_label: Label = %StatusLabel
@onready var _commands_label: Label = %CommandsLabel
@onready var _play_button: Button = %PlayButton
@onready var _pause_button: Button = %PauseButton
@onready var _skip_button: Button = %SkipButton
@onready var _stop_button: Button = %StopButton
@onready var _erg_button: Button = %ErgButton
@onready var _back_button: Button = %BackButton


func setup(app_state: AppState, ftp: int = DEFAULT_FTP_W) -> void:
	_app_state = app_state
	ftp_w = maxi(ftp, 1)
	if is_node_ready():
		refresh()


func _ready() -> void:
	_play_button.pressed.connect(play)
	_pause_button.pressed.connect(toggle_pause)
	_skip_button.pressed.connect(skip)
	_stop_button.pressed.connect(stop)
	_erg_button.pressed.connect(toggle_erg)
	_back_button.pressed.connect(back)
	refresh()


## Тестовый план: 60 с 50 %, 30 с 100 %, 90 с 60 % FTP (180 с).
static func test_workout() -> Workout:
	var steps: Array[WorkoutStep] = [
		WorkoutStep.percent(60, 50.0, WorkoutStep.StepKind.WARMUP),
		WorkoutStep.percent(30, 100.0, WorkoutStep.StepKind.INTERVAL_ON),
		WorkoutStep.percent(90, 60.0, WorkoutStep.StepKind.COOLDOWN),
	]
	return Workout.make("dev-3-steps", steps)


## «Проиграть на эмуляторе»: создать устройство, сессию и тикер; старт.
## Повторное нажатие перезапускает прогон. false — устройство недоступно.
func play() -> bool:
	_teardown()
	_trainer = TrainerFactory.create(TRAINER_KIND)
	if _trainer == null:
		_status_label.text = tr("ui.dev.trainer_unavailable")
		return false
	_trainer.set("connect_delay_sec", 0.0)
	_trainer.connect_device("dev-" + TRAINER_KIND)
	_session = WorkoutSession.new(test_workout(), _trainer, ftp_w)
	_ticker = SessionTicker.new(clock_usec)
	_ticker.name = "SessionTicker"
	_ticker.attach(_session)
	_ticker.set_time_scale(DEFAULT_TIME_SCALE)
	_ticker.ticked.connect(func(_delta: float) -> void: refresh())
	_session.state_changed.connect(func(_state: int) -> void: refresh())
	add_child(_ticker)
	_session.start()
	_ticker.start()
	refresh()
	return true


## Пауза ↔ возобновление.
func toggle_pause() -> void:
	if _session == null:
		return
	match _session.get_state():
		WorkoutSession.State.RUNNING:
			_session.pause()
		WorkoutSession.State.PAUSED:
			_session.resume()
	refresh()


func skip() -> void:
	if _session != null:
		_session.skip_step()
		refresh()


func stop() -> void:
	if _session != null:
		_session.stop()
		if _ticker != null:
			_ticker.stop()
		refresh()


func toggle_erg() -> void:
	if _session != null:
		_session.set_erg_enabled(not _session.erg_enabled)
		refresh()


func back() -> void:
	if _app_state != null:
		_app_state.navigate(AppState.Screen.HOME)


func session() -> WorkoutSession:
	return _session


func ticker() -> SessionTicker:
	return _ticker


func trainer() -> TrainerDevice:
	return _trainer


## Журнал команд эмулятора (пустой, если устройство его не ведёт).
func commands() -> Array:
	if _trainer == null:
		return []
	var journal: Variant = _trainer.get("commands")
	return journal if journal is Array else []


func status_text() -> String:
	return _status_label.text


func commands_text() -> String:
	return _commands_label.text


## Перерисовать текст состояния и журнала.
func refresh() -> void:
	if _session == null:
		_status_label.text = tr("ui.dev.no_session")
		_commands_label.text = ""
		_set_buttons(false)
		return
	var ex := _session.executor
	var last_row: Dictionary = _session.samples.row(_session.samples.size() - 1) if _session.samples.size() > 0 else {}
	var total_steps: int = ex.workout.steps.size()
	_status_label.text = tr("ui.dev.status").format({
		"state": tr("ui.dev.state." + _state_key(_session.get_state())),
		"connection": tr("ui.dev.connection." + TrainerDevice.state_name(_trainer.get_connection_state())),
		"step": mini(ex.current_step_index() + 1, total_steps),
		"steps": total_steps,
		"target": _session.current_target_watts(),
		"power": str(last_row["power_w"]) if bool(last_row.get("has_power", false)) else "—",
		"cadence": str(last_row["cadence_rpm"]) if bool(last_row.get("has_cadence", false)) else "—",
		"time": _format_time(ex.elapsed_sec()),
		"samples": _session.samples.size(),
		"erg": tr("ui.dev.erg_on") if _session.erg_enabled else tr("ui.dev.erg_off"),
	})
	var lines: Array[String] = [tr("ui.dev.commands_title")]
	var journal := commands()
	for i in range(maxi(journal.size() - COMMANDS_SHOWN, 0), journal.size()):
		var c: Dictionary = journal[i]
		lines.append("%7.1f  %-12s %s" % [float(c.get("at_sec", 0.0)), str(c.get("type", "")), str(c.get("value", ""))])
	_commands_label.text = "\n".join(lines)
	_set_buttons(true)
	_pause_button.text = tr("ui.dev.resume") if _session.get_state() == WorkoutSession.State.PAUSED else tr("ui.dev.pause")
	_erg_button.text = tr("ui.dev.erg_off") if _session.erg_enabled else tr("ui.dev.erg_on")


func _set_buttons(has_session: bool) -> void:
	_pause_button.disabled = not has_session
	_skip_button.disabled = not has_session
	_stop_button.disabled = not has_session
	_erg_button.disabled = not has_session


func _teardown() -> void:
	if _ticker != null:
		_ticker.stop()
		_ticker.queue_free()
		_ticker = null
	if _session != null and _session.get_state() in [WorkoutSession.State.RUNNING, WorkoutSession.State.PAUSED]:
		_session.stop()
	_session = null
	if _trainer != null:
		_trainer.disconnect_device()
		_trainer = null


static func _state_key(state: int) -> String:
	match state:
		WorkoutSession.State.IDLE:
			return "idle"
		WorkoutSession.State.RUNNING:
			return "running"
		WorkoutSession.State.PAUSED:
			return "paused"
		WorkoutSession.State.FINISHED:
			return "finished"
	return "idle"


static func _format_time(total_sec: int) -> String:
	return "%02d:%02d" % [total_sec / 60, total_sec % 60]
