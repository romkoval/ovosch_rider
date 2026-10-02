class_name IntervalExecutor
extends RefCounted
## Исполнитель интервалов (REQ-WRK-01, REQ-WRK-05, REQ-WRK-06, REQ-WRK-07, REQ-NFR-02).
##
## Чистая логика без Node/SceneTree: время подаётся снаружи через `tick(delta_sec)`.
## Внутренний аккумулятор превращает произвольные дельты в целые секунды —
## все события испускаются только на целых секундах активного времени
## (пропущенные кадры догоняются: `tick(2.5)` даст две секунды и остаток 0.5).
##
## Порядок событий на секунде t:
## 1. `second_elapsed(t, offset, remaining)` — для шага, который шёл эту секунду
##    (на границе: offset == duration, remaining == 0);
## 2. если шаг закончился — `step_changed(i+1, step)` и `target_changed(w)`
##    в ту же секунду (REQ-NFR-01: команда уходит без задержки),
##    либо `finished()` после последнего шага;
## 3. иначе — `cue(text)` для подсказок на этом смещении и `target_changed(w)`,
##    если цель рампы изменилась на ≥ 1 Вт (не чаще 1 Гц, REQ-WRK-02 крит. 3).
##
## `target_changed` несёт 0 для шага без цели (свободная езда).
## Пауза: `tick` не продвигает время и не порождает событий; дробная часть
## аккумулятора сохраняется (REQ-WRK-05 крит. 1).
## `skip_step()` — немедленный переход (REQ-WRK-06); `stop()` — досрочное
## завершение, `finished` при этом тоже испускается ровно один раз.

enum State { IDLE, RUNNING, PAUSED, FINISHED }

## Множитель интенсивности: диапазон и шаг (REQ-WRK-07 крит. 1).
const INTENSITY_MIN: float = 0.5
const INTENSITY_MAX: float = 1.5
const INTENSITY_STEP: float = 0.05
## Допуск сравнения аккумулятора с целой секундой (накопление ошибки float).
const TIME_EPSILON: float = 1e-6

signal state_changed(state: int)
signal step_changed(index: int, step: WorkoutStep)
signal target_changed(watts: int)
signal second_elapsed(elapsed_sec: int, step_offset_sec: int, remaining_in_step_sec: int)
signal cue(text: String)
signal finished()

var workout: Workout
var ftp_w: int = 0
## Текущий множитель (только чтение; менять через `set_intensity`).
var intensity: float = 1.0
## true, если тренировка завершена через `stop()`, а не по плану.
var stopped_early: bool = false

var _state: State = State.IDLE
var _accum_sec: float = 0.0
var _elapsed_sec: int = 0
var _step_index: int = -1
var _step_offset_sec: int = 0
var _last_target_w: int = -1
var _finished_emitted: bool = false


func _init(plan: Workout, ftp: int, intensity_factor: float = 1.0) -> void:
	workout = plan
	ftp_w = ftp
	intensity = snap_intensity(intensity_factor)


## Приводит множитель к диапазону 0.5..1.5 и шагу 0.05.
static func snap_intensity(value: float) -> float:
	var clamped: float = clampf(value, INTENSITY_MIN, INTENSITY_MAX)
	return roundi(clamped / INTENSITY_STEP) * INTENSITY_STEP


# ---------------------------------------------------------------------------
# Управление
# ---------------------------------------------------------------------------

## Запуск: состояние RUNNING, вход в первый шаг (step_changed + target_changed).
## Повторный вызов игнорируется. Пустой план завершается сразу.
func start() -> void:
	if _state != State.IDLE:
		push_warning("IntervalExecutor.start: уже запущен (state=%d)" % _state)
		return
	_elapsed_sec = 0
	_accum_sec = 0.0
	_set_state(State.RUNNING)
	_enter_step(0)


## Продвинуть активное время на `delta_sec`. Вне RUNNING и при delta <= 0 — ничего.
func tick(delta_sec: float) -> void:
	if _state != State.RUNNING or delta_sec <= 0.0:
		return
	_accum_sec += delta_sec
	while _accum_sec >= 1.0 - TIME_EPSILON and _state == State.RUNNING:
		_accum_sec -= 1.0
		if absf(_accum_sec) < TIME_EPSILON:
			_accum_sec = 0.0
		_advance_second()


func pause() -> void:
	if _state == State.RUNNING:
		_set_state(State.PAUSED)


func resume() -> void:
	if _state == State.PAUSED:
		_set_state(State.RUNNING)


## Немедленный переход к следующему шагу; пропуск последнего завершает
## тренировку (REQ-WRK-06 крит. 1, 3). Допустим в RUNNING и PAUSED.
func skip_step() -> void:
	if _state != State.RUNNING and _state != State.PAUSED:
		return
	_enter_step(_step_index + 1)


## Досрочное завершение (REQ-WRK-05 крит. 4): FINISHED, `finished` один раз.
func stop() -> void:
	if _state == State.IDLE or _state == State.FINISHED:
		return
	stopped_early = true
	_finish()


## Множитель интенсивности (REQ-WRK-07): клампится и округляется к шагу 0.05.
## Во время тренировки (RUNNING/PAUSED) при изменении цели на ≥ 1 Вт
## испускается `target_changed`.
func set_intensity(value: float) -> void:
	intensity = snap_intensity(value)
	if _state == State.RUNNING or _state == State.PAUSED:
		_emit_target(false)


# ---------------------------------------------------------------------------
# Состояние
# ---------------------------------------------------------------------------

func get_state() -> State:
	return _state


func is_finished() -> bool:
	return _state == State.FINISHED


## Индекс текущего шага; -1 в IDLE и FINISHED.
func current_step_index() -> int:
	if _state == State.IDLE or _state == State.FINISHED:
		return -1
	return _step_index


func current_step() -> WorkoutStep:
	var idx := current_step_index()
	return workout.steps[idx] if idx >= 0 else null


## Активное время от старта, с (без пауз).
func elapsed_sec() -> int:
	return _elapsed_sec


## Накопленная дробная часть секунды [0; 1) — сколько уже прошло до следующего
## целого тика. Нужна владельцу, чтобы нарезать большие дельты по границам секунд.
func pending_fraction_sec() -> float:
	return _accum_sec


## Прошедшее время текущего шага, с.
func step_offset_sec() -> int:
	return _step_offset_sec if current_step_index() >= 0 else 0


## Остаток текущего шага, с.
func step_remaining_sec() -> int:
	var step := current_step()
	if step == null:
		return 0
	return maxi(step.duration_sec - _step_offset_sec, 0)


## Остаток тренировки, с: остаток текущего шага плюс все следующие
## (после пропуска уменьшается на остаток пропущенного шага).
func total_remaining_sec() -> int:
	var idx := current_step_index()
	if idx < 0:
		return 0
	var total: int = step_remaining_sec()
	for i in range(idx + 1, workout.steps.size()):
		total += workout.steps[i].duration_sec
	return total


## Текущая целевая мощность, Вт (0 — нет цели / не запущено).
func current_target_watts() -> int:
	return maxi(_last_target_w, 0)


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _set_state(state: State) -> void:
	if state == _state:
		return
	_state = state
	state_changed.emit(state)


func _advance_second() -> void:
	_elapsed_sec += 1
	_step_offset_sec += 1
	var step: WorkoutStep = workout.steps[_step_index]
	second_elapsed.emit(_elapsed_sec, _step_offset_sec, maxi(step.duration_sec - _step_offset_sec, 0))
	if _step_offset_sec >= step.duration_sec:
		_enter_step(_step_index + 1)
		return
	_emit_cues_at(_step_offset_sec)
	_emit_target(false)


## Вход в шаг `index`; шаги нулевой длительности пропускаются; за концом плана — финиш.
func _enter_step(index: int) -> void:
	var i: int = index
	while i < workout.steps.size() and workout.steps[i].duration_sec <= 0:
		i += 1
	if i >= workout.steps.size():
		_finish()
		return
	_step_index = i
	_step_offset_sec = 0
	step_changed.emit(i, workout.steps[i])
	_emit_target(true)
	_emit_cues_at(0)


func _compute_target() -> int:
	if _step_index < 0 or _step_index >= workout.steps.size():
		return 0
	return workout.steps[_step_index].target_watts_at(float(_step_offset_sec), ftp_w, intensity)


func _emit_target(force: bool) -> void:
	var w: int = _compute_target()
	if force or absi(w - _last_target_w) >= 1:
		_last_target_w = w
		target_changed.emit(w)


func _emit_cues_at(offset_sec: int) -> void:
	for c in workout.steps[_step_index].text_cues:
		if c.at_sec == offset_sec:
			cue.emit(c.text)


func _finish() -> void:
	_set_state(State.FINISHED)
	if not _finished_emitted:
		_finished_emitted = true
		finished.emit()
