class_name WorkoutSession
extends RefCounted
## Сессия тренировки: связывает `IntervalExecutor` и `TrainerDevice`
## (REQ-WRK-01 крит. 5, REQ-WRK-02, REQ-WRK-05, REQ-WRK-06, REQ-WRK-08, REQ-DEV-08 крит. 3, REQ-DEV-09 крит. 6).
##
## Связующий слой: знает только интерфейс `TrainerDevice`, не реализацию.
## Подключением устройства не управляет — ему передают уже подключаемое/
## подключённое устройство; при любом переходе станка в CONNECTED во время
## RUNNING повторно отправляются состояние ERG и текущая цель/уровень
## (покрывает и первое подключение, и переподключение, REQ-DEV-08 крит. 3).
##
## Команды на станок:
## - `target_changed(w)` исполнителя в ERG при w > 0 → `set_target_power(w)`
##   в ту же секунду; w == 0 (свободная езда) — ничего не шлётся (REQ-WRK-02 крит. 5);
## - `set_erg_enabled(false)` → `set_erg_enabled(false)` + `set_resistance_level(level)`;
##   `set_erg_enabled(true)` → `set_erg_enabled(true)` + текущая цель;
## - на паузе не шлётся ничего (решение В-4, REQ-WRK-05 крит. 5); переключение
##   ERG и смена цели на паузе откладываются и уходят при `resume()`.
##
## Поток 1 Гц (`samples`): слот секунды t-1 закрывается на событии
## `second_elapsed(t)` исполнителя последней телеметрией, пришедшей с момента
## предыдущего слота; без телеметрии — «нет данных». На паузе слоты не пишутся.
##
## `tick(delta)` всегда продвигает станок (его часы идут и на паузе), а
## исполнитель — только в RUNNING.

enum State { IDLE, RUNNING, PAUSED, FINISHED }

signal state_changed(state: int)
signal session_finished()

var executor: IntervalExecutor
var trainer: TrainerDevice
var samples := SampleStream.new()
## Режим ERG (REQ-WRK-03). По умолчанию включён.
var erg_enabled: bool = true
## Уровень сопротивления вне ERG, % (REQ-WRK-04). По умолчанию 50.
var resistance_level: int = 50

var _state: State = State.IDLE
var _current_target_w: int = 0
var _latest_sample: TrainerSample = null
var _latest_hr_bpm: int = -1
var _erg_pending: bool = false


func _init(workout: Workout, device: TrainerDevice, ftp_w: int, intensity: float = 1.0) -> void:
	trainer = device
	executor = IntervalExecutor.new(workout, ftp_w, intensity)
	executor.target_changed.connect(_on_target_changed)
	executor.second_elapsed.connect(_on_second_elapsed)
	executor.finished.connect(_on_executor_finished)
	trainer.telemetry.connect(_on_telemetry)
	trainer.heart_rate.connect(_on_heart_rate)
	trainer.connection_state_changed.connect(_on_connection_state_changed)


# ---------------------------------------------------------------------------
# Управление
# ---------------------------------------------------------------------------

## Старт: если ERG выключен — на станок уходят `erg=false` и уровень;
## затем стартует исполнитель (первая цель уходит из его `target_changed`).
func start() -> void:
	if _state != State.IDLE:
		push_warning("WorkoutSession.start: сессия уже запущена")
		return
	_set_state(State.RUNNING)
	if not erg_enabled:
		trainer.set_erg_enabled(false)
		trainer.set_resistance_level(resistance_level)
	executor.start()


## Продвигает время. Большая дельта (заморозка кадра) нарезается по границам
## целых секунд исполнителя, чтобы станок и исполнитель шли вперемежку:
## телеметрия секунды t попадает в слот t-1, а команда перехода уходит
## с меткой ровно на границе (REQ-NFR-02 крит. 2, REQ-NFR-01).
func tick(delta_sec: float) -> void:
	var remaining: float = delta_sec
	while remaining > 0.0:
		var piece: float = remaining
		if _state == State.RUNNING:
			var to_boundary: float = 1.0 - executor.pending_fraction_sec()
			if to_boundary > IntervalExecutor.TIME_EPSILON:
				piece = minf(remaining, to_boundary)
		trainer.tick(piece)
		if _state == State.RUNNING:
			executor.tick(piece)
		remaining -= piece


func pause() -> void:
	if _state != State.RUNNING:
		return
	executor.pause()
	_set_state(State.PAUSED)


## Возобновление: текущая цель (ERG) или уровень (не ERG) уходит немедленно
## (REQ-WRK-05 крит. 3), вместе с отложенным на паузе переключением ERG.
func resume() -> void:
	if _state != State.PAUSED:
		return
	_set_state(State.RUNNING)
	executor.resume()
	_resend(_erg_pending)
	_erg_pending = false


func skip_step() -> void:
	executor.skip_step()


func stop() -> void:
	if _state != State.RUNNING and _state != State.PAUSED:
		return
	executor.stop()


func set_intensity(value: float) -> void:
	executor.set_intensity(value)


## Переключение ERG (REQ-WRK-03/04). На паузе — откладывается до `resume()`.
func set_erg_enabled(enabled: bool) -> void:
	if enabled == erg_enabled:
		return
	erg_enabled = enabled
	match _state:
		State.RUNNING:
			_resend(true)
		State.PAUSED:
			_erg_pending = true
		_:
			pass


## Уровень сопротивления 0..100 %; вне ERG в RUNNING уходит сразу.
func set_resistance_level(percent: int) -> void:
	resistance_level = clampi(percent, TrainerDevice.MIN_RESISTANCE_PERCENT, TrainerDevice.MAX_RESISTANCE_PERCENT)
	if _state == State.RUNNING and not erg_enabled:
		trainer.set_resistance_level(resistance_level)


# ---------------------------------------------------------------------------
# Состояние
# ---------------------------------------------------------------------------

func get_state() -> State:
	return _state


func current_target_watts() -> int:
	return _current_target_w


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _set_state(state: State) -> void:
	if state == _state:
		return
	_state = state
	state_changed.emit(state)


## Повторная отправка текущего режима на станок: при `with_erg` — сначала
## состояние ERG; затем цель (ERG, если > 0) или уровень (не ERG).
func _resend(with_erg: bool) -> void:
	if with_erg:
		trainer.set_erg_enabled(erg_enabled)
	if erg_enabled:
		if _current_target_w > 0:
			trainer.set_target_power(_current_target_w)
	else:
		trainer.set_resistance_level(resistance_level)


func _on_target_changed(watts: int) -> void:
	_current_target_w = watts
	# На паузе ничего не шлём; цель уйдёт при resume() (REQ-WRK-05 крит. 5).
	if _state == State.RUNNING and erg_enabled and watts > 0:
		trainer.set_target_power(watts)


func _on_second_elapsed(elapsed_sec: int, _step_offset_sec: int, _remaining_sec: int) -> void:
	samples.append(elapsed_sec - 1, _latest_sample, _latest_hr_bpm, _current_target_w,
		executor.current_step_index(), erg_enabled)
	_latest_sample = null
	_latest_hr_bpm = -1


func _on_executor_finished() -> void:
	_set_state(State.FINISHED)
	session_finished.emit()


func _on_telemetry(sample: TrainerSample) -> void:
	_latest_sample = sample


func _on_heart_rate(bpm: int) -> void:
	_latest_hr_bpm = bpm


func _on_connection_state_changed(state: int) -> void:
	if state == TrainerDevice.ConnectionState.CONNECTED and _state == State.RUNNING:
		_resend(true)
