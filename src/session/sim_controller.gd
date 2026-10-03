class_name SimController
extends RefCounted
## Управление нагрузкой станка в свободной езде: уклон трассы в SIM-режиме или
## фиксированное сопротивление (REQ-FRD-04 крит. 2–6, REQ-FRD-05 крит. 1–4, REQ-FRD-01 крит. 2).
##
## Связующий слой сессии: знает только интерфейс `TrainerDevice`, не реализацию.
## Время — извне: владелец (сессия свободной езды) вызывает `tick(delta_sec, route_grade_pct)`
## после `trainer.tick` с той же дельтой (часы контроллера и станка идут вместе, сигналы
## станка за тик уже обработаны). Тикать нужно и на паузе: ограничение частоты считает
## реальное время между командами.
##
## Режимы (`Mode`):
## - SIM — на станок уходит `set_simulation(g)`, где g = round(g(s) · k / 100, 0.01 %),
##   ограниченный `trainer.inclination_range()` (k — крутизна 0..100 % с шагом 5,
##   одинаково для подъёмов и спусков). Команда — не чаще раза в `MIN_SIM_INTERVAL_SEC`
##   и только при отличии от последнего отправленного ≥ `GRADE_THRESHOLD_PCT`.
##   Принудительная отправка (без порога, но с тем же ограничением частоты, то есть не
##   позже 1 с) — при `start()`, `resume()`, восстановлении связи (переход станка в
##   CONNECTED), смене крутизны и возврате в SIM;
## - FIXED — `set_resistance_level(level)` (проценты по WRK-04.2, перевод в единицы
##   станка — забота устройства), команд SIM нет до возврата в SIM. Если станок в ERG,
##   уровень уходит вместе с `set_erg_enabled(false)` (сначала уровень запоминается,
##   затем выключение ERG пишет `0x04` с ним), иначе — одним `set_resistance_level`.
## `set_target_power` и `set_erg_enabled(true)` не вызываются никогда: первая команда
## управления на станок — SIM `0x11` или уровень `0x04` (FRD-01 крит. 2).
##
## Команды уходят только в состоянии станка CONNECTED; без связи их отправка
## откладывается и выполняется в ближайший тик после CONNECTED (принудительно).
## Команды из обработчиков сигналов станка не отправляются (только флаги) — их
## отправляет следующий `tick`, когда часы контроллера и станка совпадают.
##
## Нет SIM: если `trainer.simulation_support() == UNSUPPORTED` (на старте, в любой тик
## SIM-режима или при попытке вернуться в SIM) или станок отверг команду SIM
## (`error(SIMULATION_REJECTED)`), контроллер переходит в FIXED и испускает
## `simulation_unavailable` (текст сообщения на HUD — дело экрана). Попытка
## `set_mode(SIM)` без поддержки режим не меняет и снова испускает сигнал.
## При UNKNOWN команда SIM отправляется: ответ станка решает.
##
## События заезда — сигналом `ride_event(type, value)`; время ставит владелец:
## `EVENT_MODE` ("sim" | "fixed"), `EVENT_STEEPNESS` (k, %), `EVENT_RESISTANCE` (уровень, %).
## До `start()` и после `stop()` настройки меняются без событий и без команд.
## Пауза: на станок ничего не уходит, настройки и события принимаются; `resume()`
## отправляет текущий режим принудительно.
##
## Подписки на сигналы станка — связанными методами; `dispose()` отключает их.

enum Mode { SIM, FIXED }

enum State { IDLE, RUNNING, PAUSED, STOPPED }

## Крутизна по умолчанию, % (решение владельца 2026-10-03, FRD-05 крит. 1); диапазон и шаг —
## те же, что у профиля (`Profile.*_SIM_STEEPNESS_PCT`; слой сессии профиль не импортирует).
const DEFAULT_STEEPNESS_PCT: int = 50
const MIN_STEEPNESS_PCT: int = 0
const MAX_STEEPNESS_PCT: int = 100
const STEEPNESS_STEP_PCT: int = 5
## Уровень сопротивления по умолчанию, % (как у `WorkoutSession`).
const DEFAULT_RESISTANCE_PCT: int = 50
## Минимальный интервал между командами SIM, с (FRD-04 крит. 4).
const MIN_SIM_INTERVAL_SEC: float = 1.0
## Порог изменения передаваемого уклона для обычной отправки, % (FRD-04 крит. 4).
const GRADE_THRESHOLD_PCT: float = 0.1
## Округление передаваемого уклона, % (FRD-04 крит. 2).
const GRADE_RESOLUTION_PCT: float = 0.01
## Допуск сравнения времени и уклона (накопление ошибки float).
const EPSILON: float = 1e-6

const EVENT_MODE: String = "sim_mode"
const EVENT_STEEPNESS: String = "sim_steepness"
const EVENT_RESISTANCE: String = "resistance"
const MODE_NAME_SIM: String = "sim"
const MODE_NAME_FIXED: String = "fixed"

## Режим сменился (пользователем или переходом на сопротивление без SIM).
signal mode_changed(mode: int)
## Крутизна сменилась (владелец сохраняет её в профиль, FRD-05 крит. 1).
signal steepness_changed(percent: int)
## Уровень сопротивления сменился.
signal resistance_level_changed(percent: int)
## Станок не поддерживает SIM или отверг команду SIM: режим — FIXED (FRD-04 крит. 6).
signal simulation_unavailable()
## Событие для журнала заезда (FRD-05 крит. 6); время ставит владелец.
signal ride_event(type: String, value: Variant)

var trainer: TrainerDevice

var _mode: Mode = Mode.SIM
var _state: State = State.IDLE
var _steepness_pct: int = DEFAULT_STEEPNESS_PCT
var _resistance_pct: int = DEFAULT_RESISTANCE_PCT
var _route_grade_pct: float = 0.0
## Часы контроллера, с (всё протиканное время, включая паузы).
var _time_sec: float = 0.0
var _sim_sent: bool = false
var _last_sim_grade_pct: float = 0.0
var _last_sim_at_sec: float = 0.0
var _sim_command_count: int = 0
## Отправить уклон без порога (при первой возможности по частоте).
var _sim_force_pending: bool = false
## Отправить уровень сопротивления (режим FIXED).
var _fixed_pending: bool = false


## `steepness_pct` и `resistance_pct` приводятся к шагу 5 %; `initial_mode` — режим,
## выбранный пользователем до старта (FIXED — первая команда `0x04`, FRD-01 крит. 2).
func _init(device: TrainerDevice, steepness_pct: int = DEFAULT_STEEPNESS_PCT,
		initial_mode: Mode = Mode.SIM, resistance_pct: int = DEFAULT_RESISTANCE_PCT) -> void:
	trainer = device
	_steepness_pct = snap_steepness(steepness_pct)
	_resistance_pct = WorkoutSession.snap_resistance(resistance_pct)
	_mode = initial_mode
	trainer.connection_state_changed.connect(_on_connection_state_changed)
	trainer.error.connect(_on_trainer_error)


## Отключить обработчики сигналов станка и забыть его (разрыв цикла станок ↔ контроллер).
func dispose() -> void:
	if trainer == null:
		return
	if trainer.connection_state_changed.is_connected(_on_connection_state_changed):
		trainer.connection_state_changed.disconnect(_on_connection_state_changed)
	if trainer.error.is_connected(_on_trainer_error):
		trainer.error.disconnect(_on_trainer_error)
	_state = State.STOPPED
	trainer = null


# ---------------------------------------------------------------------------
# Управление
# ---------------------------------------------------------------------------

## Старт: текущий режим уходит на станок принудительно (SIM — уклон `route_grade_pct`
## с крутизной, FIXED — уровень). Без поддержки SIM — сразу FIXED и `simulation_unavailable`.
func start(route_grade_pct: float) -> void:
	if _state != State.IDLE or trainer == null:
		return
	_set_route_grade(route_grade_pct)
	_state = State.RUNNING
	if _mode == Mode.SIM and trainer.simulation_support() == TrainerDevice.SimulationSupport.UNSUPPORTED:
		_fall_back_to_fixed()
	_mark_mode_pending()
	_service()


## Завершение: дальше команд нет, настройки меняются без событий.
func stop() -> void:
	if _state == State.IDLE or _state == State.STOPPED:
		return
	_state = State.STOPPED
	_sim_force_pending = false
	_fixed_pending = false


## Пауза: на станок ничего не уходит до `resume()`.
func pause() -> void:
	if _state == State.RUNNING:
		_state = State.PAUSED


## Возобновление: текущий режим уходит принудительно (не позже 1 с, FRD-04 крит. 5).
func resume() -> void:
	if _state != State.PAUSED:
		return
	_state = State.RUNNING
	_mark_mode_pending()
	_service()


## Продвинуть часы на `delta_sec` и принять уклон трассы g(s) в текущей позиции, %.
## Вызывать после `trainer.tick(delta_sec)`.
func tick(delta_sec: float, route_grade_pct: float) -> void:
	if delta_sec > 0.0:
		_time_sec += delta_sec
		# Выравнивание на целую секунду, как у часов устройства (0.1 × 10 ≠ ровно 1.0).
		if absf(_time_sec - roundf(_time_sec)) < EPSILON:
			_time_sec = roundf(_time_sec)
	_set_route_grade(route_grade_pct)
	_service()


## Крутизна k, % (0..100, шаг 5; FRD-05 крит. 1). В SIM во время езды новый уклон
## уходит не позже 1 с, без порога (FRD-05 крит. 3).
func set_steepness(percent: int) -> void:
	var snapped: int = snap_steepness(percent)
	if snapped == _steepness_pct:
		return
	_steepness_pct = snapped
	steepness_changed.emit(snapped)
	_log(EVENT_STEEPNESS, snapped)
	if _mode == Mode.SIM:
		_sim_force_pending = true
		_service()


## Уровень фиксированного сопротивления, % (0..100, шаг 5; WRK-04 крит. 1, 2).
## В FIXED во время езды уходит сразу; в SIM — только запоминается.
func set_resistance_level(percent: int) -> void:
	var snapped: int = WorkoutSession.snap_resistance(percent)
	if snapped == _resistance_pct:
		return
	_resistance_pct = snapped
	resistance_level_changed.emit(snapped)
	_log(EVENT_RESISTANCE, snapped)
	if _mode == Mode.FIXED:
		_fixed_pending = true
		_service()


## Переключить режим SIM ↔ FIXED (FRD-05 крит. 4). Возврат в SIM без поддержки SIM
## отклоняется: режим не меняется, испускается `simulation_unavailable`. Возвращает,
## действует ли после вызова запрошенный режим.
func set_mode(new_mode: Mode) -> bool:
	if new_mode == _mode:
		return true
	if new_mode == Mode.SIM and trainer != null \
			and trainer.simulation_support() == TrainerDevice.SimulationSupport.UNSUPPORTED:
		simulation_unavailable.emit()
		return false
	_apply_mode(new_mode)
	_service()
	return true


## Одно действие пользователя «SIM ↔ сопротивление».
func toggle_mode() -> bool:
	return set_mode(Mode.FIXED if _mode == Mode.SIM else Mode.SIM)


# ---------------------------------------------------------------------------
# Состояние
# ---------------------------------------------------------------------------

func mode() -> Mode:
	return _mode


func mode_name() -> String:
	return MODE_NAME_SIM if _mode == Mode.SIM else MODE_NAME_FIXED


func get_state() -> State:
	return _state


func steepness_pct() -> int:
	return _steepness_pct


func resistance_level() -> int:
	return _resistance_pct


## Уклон трассы g(s), принятый последним, % (полный, без крутизны).
func route_grade_pct() -> float:
	return _route_grade_pct


## Уклон, который ушёл бы на станок сейчас: g · k / 100, округление, диапазон станка.
func target_grade_pct() -> float:
	var grade_range := Vector2(TrainerDevice.DEFAULT_INCLINATION_MIN_PCT, TrainerDevice.DEFAULT_INCLINATION_MAX_PCT)
	if trainer != null:
		grade_range = trainer.inclination_range()
	return transmitted_grade(_route_grade_pct, _steepness_pct, grade_range)


## Последний отправленный уклон, % (NAN — ещё не отправлялся).
func last_sent_grade_pct() -> float:
	return _last_sim_grade_pct if _sim_sent else NAN


## Число вызовов `set_simulation` за жизнь контроллера.
func sim_command_count() -> int:
	return _sim_command_count


## Передаваемый станку уклон, %: g · k / 100, округлённый до 0.01 и ограниченный
## диапазоном станка `grade_range` (x — минимум, y — максимум) (FRD-04 крит. 2, 3; FRD-05 крит. 1, 2).
static func transmitted_grade(route_grade_pct: float, steepness_pct: int, grade_range: Vector2) -> float:
	var g: float = snappedf(route_grade_pct * float(steepness_pct) / 100.0, GRADE_RESOLUTION_PCT)
	var lo: float = minf(grade_range.x, grade_range.y)
	var hi: float = maxf(grade_range.x, grade_range.y)
	# −0.0 после округления малого спуска → 0.
	return clampf(g, lo, hi) + 0.0


## Крутизна к 0..100 % с шагом 5 (FRD-05 крит. 1).
static func snap_steepness(percent: int) -> int:
	var clamped: int = clampi(percent, MIN_STEEPNESS_PCT, MAX_STEEPNESS_PCT)
	return roundi(float(clamped) / STEEPNESS_STEP_PCT) * STEEPNESS_STEP_PCT


static func mode_to_name(value: Mode) -> String:
	return MODE_NAME_SIM if value == Mode.SIM else MODE_NAME_FIXED


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _set_route_grade(value: float) -> void:
	if is_finite(value):
		_route_grade_pct = value
	else:
		push_warning("SimController: уклон трассы %s не число, оставлен %.2f" % [value, _route_grade_pct])


func _is_started() -> bool:
	return _state == State.RUNNING or _state == State.PAUSED


func _log(type: String, value: Variant) -> void:
	if _is_started():
		ride_event.emit(type, value)


func _apply_mode(new_mode: Mode) -> void:
	_mode = new_mode
	_sim_force_pending = false
	_fixed_pending = false
	mode_changed.emit(new_mode)
	_log(EVENT_MODE, mode_to_name(new_mode))
	_mark_mode_pending()


func _fall_back_to_fixed() -> void:
	if _mode == Mode.SIM:
		_apply_mode(Mode.FIXED)
	simulation_unavailable.emit()


func _mark_mode_pending() -> void:
	if _mode == Mode.SIM:
		_sim_force_pending = true
	else:
		_fixed_pending = true


## Отправить на станок то, что положено сейчас (только RUNNING и CONNECTED).
func _service() -> void:
	if _state != State.RUNNING or trainer == null:
		return
	if trainer.get_connection_state() != TrainerDevice.ConnectionState.CONNECTED:
		return
	if _mode == Mode.SIM:
		if trainer.simulation_support() == TrainerDevice.SimulationSupport.UNSUPPORTED:
			_fall_back_to_fixed()
		else:
			_maybe_send_sim()
	# Отказ SIM, пришедший синхронно внутри `set_simulation`, переводит в FIXED здесь же.
	if _mode == Mode.FIXED and _fixed_pending:
		_send_fixed()


func _maybe_send_sim() -> void:
	if _sim_sent and _time_sec - _last_sim_at_sec < MIN_SIM_INTERVAL_SEC - EPSILON:
		return
	var grade: float = target_grade_pct()
	if not _sim_force_pending and _sim_sent \
			and absf(grade - _last_sim_grade_pct) < GRADE_THRESHOLD_PCT - EPSILON:
		return
	_sim_force_pending = false
	_sim_sent = true
	_last_sim_grade_pct = grade
	_last_sim_at_sec = _time_sec
	_sim_command_count += 1
	trainer.set_simulation(grade)


func _send_fixed() -> void:
	_fixed_pending = false
	# Уровень сначала запоминается: при включённом ERG его применит выключение ERG
	# (одна команда 0x04), в SIM — `set_resistance_level` сам переводит на сопротивление.
	trainer.set_resistance_level(_resistance_pct)
	if trainer.is_erg_enabled():
		trainer.set_erg_enabled(false)


func _on_connection_state_changed(state: int) -> void:
	# Старт, обрыв и восстановление: текущий режим — принудительно в ближайший тик.
	if state == TrainerDevice.ConnectionState.CONNECTED and _is_started():
		_mark_mode_pending()


func _on_trainer_error(code: int, _message: String) -> void:
	if code == TrainerDevice.ErrorCode.SIMULATION_REJECTED and _is_started() and _mode == Mode.SIM:
		_fall_back_to_fixed()
