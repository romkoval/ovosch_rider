class_name WorkoutSession
extends RefCounted
## Сессия тренировки: связывает `IntervalExecutor` и `TrainerDevice`
## (REQ-WRK-01 крит. 5, REQ-WRK-02..08, REQ-NFR-01, REQ-DEV-08 крит. 3, REQ-DEV-09 крит. 6).
##
## Связующий слой: знает только интерфейс `TrainerDevice`, не реализацию.
## Подключением устройства не управляет — ему передают уже подключаемое/
## подключённое устройство; при переходе станка в CONNECTED во время RUNNING
## повторно отправляются режим ERG и текущая цель/уровень (первое подключение и
## переподключение, REQ-DEV-08 крит. 3). На паузе после CONNECTED ничего не шлётся —
## цель уйдёт при `resume()` (уточнение DEV-08.3, приоритет В-4).
##
## Команды на станок (все — в ту же секунду, что и событие, REQ-NFR-01):
## - старт: станок живёт дольше сессии и мог остаться в режиме прошлой тренировки,
##   поэтому режим сверяется с `trainer.is_erg_enabled()`: ERG выкл пользователем —
##   `erg=false` + уровень до запуска исполнителя; после входа в первый шаг при
##   расхождении действующего ERG со станком — `erg` + текущая цель/уровень;
## - `target_changed(w)` исполнителя при действующем ERG → `set_target_power(w)`,
##   в том числе 0 Вт (иначе станок держал бы прежнюю цель);
## - шаг FreeRide при включённом пользователем ERG (решение В-10, REQ-WRK-02 крит. 5):
##   ERG на станке приостанавливается — `set_erg_enabled(false)` + `set_resistance_level(level)`;
##   на следующем шаге с целью — `set_erg_enabled(true)` + цель. Флаг пользователя
##   `erg_enabled` при этом не меняется (это режим шага, не выбор пользователя);
## - `set_erg_enabled(false)` пользователем → `erg=false` + уровень; `true` → `erg=true` + цель
##   (REQ-WRK-03 крит. 2, 3); уровень при включённом ERG только запоминается (REQ-WRK-04 крит. 3);
## - на паузе не шлётся ничего (В-4, REQ-WRK-05 крит. 5); переключения ERG, смена цели,
##   интенсивности и уровня на паузе откладываются и уходят при `resume()`;
## - `error(WRITE_FAILED)` от устройства → один повтор текущей цели/уровня, не чаще
##   раза в секунду (REQ-NFR-01 крит. 2; BLE-реализация устройства сама повторяет
##   запись один раз, сессия страхует второй отказ). `CONTROL_POINT_REJECTED` не повторяется.
##
## Поток 1 Гц (`samples`): слот секунды t-1 закрывается на `second_elapsed(t)`
## последней телеметрией за секунду; без телеметрии — «нет данных» плюс возраст
## данных по источникам для HUD. Скорость — только `SpeedModel` по мощности, весу и уклону
## g(s) трассы сцены (экран тренировки передаёт трассу сцены, по умолчанию `flat`; без трассы —
## уклон 0; позиция `position` — интеграл скорости модели):
## `speed_source` = «модель» у всех заездов, поле скорости станка не используется (У-30,
## REQ-D3D-02 п.6, D3D-08 п.13, WRK-08 п.5). Станку уклон не передаётся — в плане ERG.
## На паузе слоты не пишутся, время паузы не идёт в elapsed.
##
## Журнал событий `events` (REQ-WRK-05 крит. 2, REQ-WRK-06 крит. 4, LOC-01):
## `{type, at_sec, value}`; типы — константы `EVENT_*`. `at_sec` — активное
## сессионное время (пауза в него не входит, В-4). У события паузы после
## возобновления появляются `duration_sec` — реальная длительность паузы по
## времени, прошедшему через `tick()` (станок тикает и на паузе), — и
## `until_sec = at_sec + duration_sec` — «конец паузы по часам устройства».
## Сумма длительностей всех пауз — `metadata()["paused_total_sec"]` (для FIT
## `timer_stopped/started` и истории). `stop()` на паузе закрывает текущую паузу
## так же, как `resume()`. Пульс 0 уд/мин от датчика считается отсутствием данных.
##
## Режим сессии `trainer_mode` (REQ-WRK-09) берётся у устройства один раз при создании
## (`TrainerDevice.trainer_mode()`) и до конца не меняется. В режиме `power_meter` сессия не
## вызывает ни одной команды управления: ERG выключен во всех сэмплах, `set_erg_enabled` и
## `set_resistance_level` ничего не меняют и событий не пишут; план идёт по таймеру, цель —
## плановая (с множителем), переходы и события — как в `smart` (WRK-09 п.3).
##
## Секунда без мощности — тяги нет: мощность в
## сэмпле «нет данных», скорость — шаг модели при 0 Вт (`SpeedModel.step_without_power`, D3D-02 п.7,
## У-33, У-34: на ровном остановка, на спуске накат), таймер плана идёт.

enum State { IDLE, RUNNING, PAUSED, FINISHED }

const EVENT_START: String = "start"
const EVENT_PAUSE: String = "pause"
const EVENT_RESUME: String = "resume"
const EVENT_SKIP: String = "skip"
const EVENT_STOP: String = "stop"
const EVENT_FINISH: String = "finish"
const EVENT_ERG_ON: String = "erg_on"
const EVENT_ERG_OFF: String = "erg_off"
const EVENT_RESISTANCE: String = "resistance"
const EVENT_INTENSITY: String = "intensity"
const EVENT_DISCONNECT: String = "disconnect"
const EVENT_RECONNECT: String = "reconnect"
const EVENT_RETRY: String = "retry"
## The trainer does not accept a power target (DEV-10 p.5 (b), LOC-01 p.4): logged once per
## connection with the session second — not an ERG toggle event.
const EVENT_ERG_UNAVAILABLE: String = "erg_unavailable"

## Шаг уровня сопротивления, % (REQ-WRK-04 крит. 1).
const RESISTANCE_STEP_PCT: int = 5
const DEFAULT_WEIGHT_KG: float = 75.0
## Ключ источника станка в метаданных заезда (T-160, Н-59): `TrainerDevice.SOURCE_BLE` |
## `TrainerDevice.SOURCE_EMULATOR` — по `TrainerDevice.trainer_source()`, без проверки класса.
const META_TRAINER_SOURCE: String = "trainer_source"
## Ключ режима сессии в метаданных заезда (REQ-WRK-09 п.8, LOC-01 п.1): `TrainerDevice.MODE_*`.
const META_TRAINER_MODE: String = "trainer_mode"

signal state_changed(state: int)
signal session_finished()
## Пользовательский режим ERG изменился (для HUD, REQ-WRK-03 крит. 1).
signal erg_changed(enabled: bool)
## Уровень сопротивления изменился (владелец сохраняет в профиль, REQ-WRK-04 крит. 1).
signal resistance_level_changed(percent: int)
## Множитель интенсивности изменился (REQ-WRK-07).
signal intensity_changed(factor: float)
## Добавлено событие в журнал.
signal event_logged(event: Dictionary)
## Доступность ERG на станке изменилась (`erg_available()`) — для HUD.
signal erg_availability_changed(available: bool)

var executor: IntervalExecutor
var trainer: TrainerDevice
var samples := SampleStream.new()
## Журнал событий заезда.
var events: Array[Dictionary] = []
## Режим ERG, выбранный пользователем (REQ-WRK-03). По умолчанию включён.
var erg_enabled: bool = true
## Уровень сопротивления вне ERG, % (REQ-WRK-04). По умолчанию 50.
var resistance_level: int = 50
## Вес всадника для модели скорости, кг.
var weight_kg: float = DEFAULT_WEIGHT_KG
## Время старта, unix-секунды (0 — не стартовала).
var started_at_unix: int = 0
## Режим сессии (`TrainerDevice.MODE_SMART` | `MODE_POWER_METER`), фиксирован при создании.
var trainer_mode: String = TrainerDevice.MODE_SMART
## Позиция на трассе сцены — только для уклона g(s) модели скорости (D3D-08 п.13). В сэмпл
## плана позиция не пишется (поток и FIT плана — как раньше).
var position: RoutePosition

var _state: State = State.IDLE
var _current_target_w: int = 0
var _latest_sample: TrainerSample = null
var _latest_hr_bpm: int = -1
## На паузе изменился режим ERG (пользователь или шаг FreeRide): при `resume()`
## заново уходит и состояние ERG, иначе — только цель/уровень (ровно одна команда).
var _erg_pending: bool = false
## ERG приостановлен режимом шага FreeRide (В-10).
var _freeride_suspended: bool = false
var _speed_model := SpeedModel.new()
var _last_retry_sec: int = -1
var _pause_event_index: int = -1
## Всё протиканное время, включая паузы, с (для длительности пауз).
var _wall_sec: float = 0.0
var _pause_started_wall_sec: float = 0.0
var _paused_total_sec: float = 0.0
var _power_age: int = -1
var _cadence_age: int = -1
var _hr_age: int = -1
## ERG доступен на станке (по последнему `capabilities_changed`).
var _erg_available: bool = true
## The "ERG unavailable" event was logged in the current connection.
var _erg_unavailable_logged: bool = false


## `route_id` — трасса сцены (`RouteCatalog`), по её профилю берётся уклон модели скорости;
## "" — без профиля (уклон 0: процедурная петля сцены, сессия без сцены).
func _init(workout: Workout, device: TrainerDevice, ftp_w: int, intensity: float = 1.0,
		rider_weight_kg: float = DEFAULT_WEIGHT_KG, route_id: String = "") -> void:
	trainer = device
	weight_kg = rider_weight_kg
	trainer_mode = device.trainer_mode()
	samples.speed_source = SampleStream.SPEED_SOURCE_MODEL
	position = RoutePosition.new(RouteCatalog.get_route(RouteCatalog.resolve_id(route_id)).profile \
		if not route_id.is_empty() else null)
	if not controls_trainer():
		erg_enabled = false
	executor = IntervalExecutor.new(workout, ftp_w, intensity)
	executor.step_changed.connect(_on_step_changed)
	executor.target_changed.connect(_on_target_changed)
	executor.second_elapsed.connect(_on_second_elapsed)
	executor.finished.connect(_on_executor_finished)
	trainer.telemetry.connect(_on_telemetry)
	trainer.heart_rate.connect(_on_heart_rate)
	trainer.connection_state_changed.connect(_on_connection_state_changed)
	trainer.error.connect(_on_trainer_error)
	trainer.capabilities_changed.connect(_on_trainer_capabilities)
	_erg_available = trainer.is_erg_available() if controls_trainer() else false


# ---------------------------------------------------------------------------
# Управление
# ---------------------------------------------------------------------------

## Старт: если ERG выключен пользователем — на станок уходят `erg=false` и уровень;
## затем стартует исполнитель (первая цель/режим шага уходит из его событий).
## Если после этого режим станка (`is_erg_enabled()`) расходится с действующим ERG
## сессии — станок остался в режиме прошлой тренировки — режим и текущая
## цель/уровень отправляются заново.
func start() -> void:
	if _state != State.IDLE:
		push_warning("WorkoutSession.start: сессия уже запущена")
		return
	started_at_unix = int(Time.get_unix_time_from_system())
	_set_state(State.RUNNING)
	_log(EVENT_START, 0)
	if controls_trainer() and not _erg_available:
		_log_erg_unavailable()
	if not erg_enabled and controls_trainer():
		trainer.set_erg_enabled(false)
		trainer.set_resistance_level(resistance_level)
	executor.start()
	# Не подключён — режим и цель уйдут при CONNECTED (_on_connection_state_changed).
	if _state == State.RUNNING and controls_trainer() and trainer.get_connection_state() == TrainerDevice.ConnectionState.CONNECTED \
			and trainer.is_erg_enabled() != _effective_erg():
		_resend(true)


## Продвигает время. Большая дельта (заморозка кадра) нарезается по границам
## целых секунд исполнителя, чтобы станок и исполнитель шли вперемежку:
## телеметрия секунды t попадает в слот t-1, а команда перехода уходит
## с меткой ровно на границе (REQ-NFR-02 крит. 2, REQ-NFR-01).
func tick(delta_sec: float) -> void:
	if delta_sec > 0.0:
		_wall_sec += delta_sec
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
	_pause_event_index = events.size()
	_pause_started_wall_sec = _wall_sec
	_log(EVENT_PAUSE, executor.elapsed_sec())


## Возобновление: текущая цель (ERG) или уровень (не ERG) уходит немедленно
## (REQ-WRK-05 крит. 3), вместе с отложенными на паузе изменениями режима.
func resume() -> void:
	if _state != State.PAUSED:
		return
	_set_state(State.RUNNING)
	executor.resume()
	_close_pause()
	_log(EVENT_RESUME, executor.elapsed_sec())
	_resend(_erg_pending)
	_erg_pending = false


## Пропуск текущего шага (REQ-WRK-06): переход немедленно, цель — в ту же секунду.
func skip_step() -> void:
	if _state != State.RUNNING and _state != State.PAUSED:
		return
	var skipped: int = executor.current_step_index()
	_log(EVENT_SKIP, skipped)
	executor.skip_step()


## Досрочное завершение (REQ-WRK-05 крит. 4): подтверждение — на стороне UI.
## На паузе сначала закрывается текущая пауза (её время идёт в `paused_total_sec`,
## у события паузы появляется `duration_sec`, REQ-WRK-05 крит. 2, REQ-LOC-01 крит. 1).
func stop() -> void:
	if _state != State.RUNNING and _state != State.PAUSED:
		return
	_close_pause()
	_log(EVENT_STOP, executor.elapsed_sec())
	executor.stop()


## Множитель интенсивности 0.5..1.5 с шагом 0.05 (REQ-WRK-07). В ERG новая цель
## уходит в ту же секунду через `target_changed` исполнителя; на паузе — при `resume()`.
func set_intensity(value: float) -> void:
	var snapped: float = IntervalExecutor.snap_intensity(value)
	if is_equal_approx(snapped, executor.intensity):
		return
	executor.set_intensity(snapped)
	_log(EVENT_INTENSITY, executor.intensity)
	intensity_changed.emit(executor.intensity)


func intensity() -> float:
	return executor.intensity


## Переключение ERG пользователем (REQ-WRK-03). Одно действие — `toggle_erg()`.
## На паузе — откладывается до `resume()`.
func set_erg_enabled(enabled: bool) -> void:
	if enabled == erg_enabled or not controls_trainer():
		return
	erg_enabled = enabled
	_freeride_suspended = enabled and _current_step_is_free_ride()
	_log(EVENT_ERG_ON if enabled else EVENT_ERG_OFF, executor.elapsed_sec())
	erg_changed.emit(enabled)
	match _state:
		State.RUNNING:
			_resend(true)
		State.PAUSED:
			_erg_pending = true
		_:
			pass


func toggle_erg() -> void:
	set_erg_enabled(not erg_enabled)


## Уровень сопротивления 0..100 % с шагом 5 (REQ-WRK-04 крит. 1); вне действующего
## ERG в RUNNING уходит сразу, при включённом ERG — только запоминается (крит. 3).
func set_resistance_level(percent: int) -> void:
	var snapped: int = snap_resistance(percent)
	if snapped == resistance_level or not controls_trainer():
		return
	resistance_level = snapped
	_log(EVENT_RESISTANCE, snapped)
	resistance_level_changed.emit(snapped)
	if _state == State.RUNNING and not _effective_erg():
		trainer.set_resistance_level(resistance_level)
	# На паузе уровень уйдёт при resume() через _resend (REQ-WRK-05 крит. 3).


## Приведение уровня к 0..100 с шагом 5.
static func snap_resistance(percent: int) -> int:
	var clamped: int = clampi(percent, TrainerDevice.MIN_RESISTANCE_PERCENT, TrainerDevice.MAX_RESISTANCE_PERCENT)
	return roundi(float(clamped) / RESISTANCE_STEP_PCT) * RESISTANCE_STEP_PCT


# ---------------------------------------------------------------------------
# Состояние
# ---------------------------------------------------------------------------

func get_state() -> State:
	return _state


## Сессия управляет станком (`smart`); в `power_meter` — нет (WRK-09 п.4).
func controls_trainer() -> bool:
	return trainer_mode == TrainerDevice.MODE_SMART


## Текущая цель, Вт — фактически заданная станку (REQ-DEV-10 п.6, У-26): пока ERG действует на
## станке, цель плана (с множителем WRK-07) приводится к диапазону станка
## (`TrainerDevice.applied_target_power`); иначе (ERG выключен или недоступен, FreeRide, режим
## `power_meter`) — цель плана как есть. Её показывает HUD и пишет сэмпл.
func current_target_watts() -> int:
	return applied_target(_current_target_w)


## Target `watts` as the HUD shows it (HUD-01 p.7, HUD-10 p.1, U-37): in ERG mode
## (`is_erg_mode`) — limited to the trainer's range, as the trainer gets it on steps with a target;
## otherwise the plan target as is. Keyed on the ERG mode, not on the step: a FreeRide step does
## not switch rows, bars and y_max to plan targets (hud.md 17.3).
func applied_target(watts: int) -> int:
	if watts <= 0 or not is_erg_mode():
		return watts
	return trainer.applied_target_power(watts)


## Цель плана (с множителем WRK-07) без ограничения станком.
func planned_target_watts() -> int:
	return _current_target_w


## ERG доступен на станке (REQ-DEV-10 п.4–5, DEV-11 п.7–8): управляемый станок принимает цель
## мощности. Недоступен — ERG на станке не действует (режим — фиксированное сопротивление).
func erg_available() -> bool:
	return controls_trainer() and trainer.is_erg_available()


## "ERG acts" — the single project-wide definition (WRK-08 p.7): `smart` mode, ERG available on the
## trainer (DEV-10 p.5), the ERG toggle on and the current step has a target (not FreeRide, В-10).
## The sample flag, the trainer-limited target (DEV-10 p.6), the HUD and the saved ride use it; a
## lost connection (DEV-08) does not change it.
func is_erg_active_on_trainer() -> bool:
	return controls_trainer() and _effective_erg()


## ERG mode (HUD-01 p.7, HUD-10 p.1, WRK-03 p.7): `smart`, ERG available on the trainer and the
## ERG toggle on — regardless of the current step (on a FreeRide step the mode stays, while
## `is_erg_active_on_trainer` is off). The HUD display rule and the `+`/`−` mapping key on it.
func is_erg_mode() -> bool:
	return controls_trainer() and erg_enabled and _erg_available


func is_freeride_suspended() -> bool:
	return _freeride_suspended


## Сессионное время с дробной частью, с.
func session_time_sec() -> float:
	return float(executor.elapsed_sec()) + executor.pending_fraction_sec()


## Возраст данных источника (`"power"|"cadence"|"heart_rate"`) на момент последнего слота, с; -1 — не было.
func data_age_sec(source: String) -> int:
	match source:
		"power":
			return _power_age
		"cadence":
			return _cadence_age
		"heart_rate":
			return _hr_age
	return -1


## Метаданные заезда (LOC-01 крит. 1): FTP, вес, множитель, источник скорости, досрочность,
## источник станка (эмулятор / реальное устройство, T-160).
func metadata() -> Dictionary:
	return {
		"workout_name": executor.workout.name,
		META_TRAINER_SOURCE: trainer.trainer_source() if trainer != null else TrainerDevice.SOURCE_BLE,
		META_TRAINER_MODE: trainer_mode,
		"workout_source": executor.workout.source,
		"started_at_unix": started_at_unix,
		"ftp_w": executor.ftp_w,
		"weight_kg": weight_kg,
		"intensity": executor.intensity,
		# The ride's "ERG" mark comes from the sample flags (LOC-01 p.4, WRK-08 p.7), never from the
		# toggle: ERG acted in at least one sample; before the first sample — whether it acts now.
		"erg_enabled": samples.erg_enabled.has(true) if samples.size() > 0 else is_erg_active_on_trainer(),
		"resistance_level": resistance_level,
		"speed_source": samples.speed_source,
		"stopped_early": executor.stopped_early,
		"elapsed_sec": executor.elapsed_sec(),
		"paused_total_sec": _paused_total_sec,
		"planned_sec": executor.workout.total_duration_sec(),
		"distance_m": samples.total_distance_m(),
		"sample_count": samples.size(),
		"event_count": events.size(),
	}


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _set_state(state: State) -> void:
	if state == _state:
		return
	_state = state
	state_changed.emit(state)


func _log(type: String, value: Variant) -> void:
	var event := {"type": type, "at_sec": session_time_sec(), "value": value}
	events.append(event)
	event_logged.emit(event)


## Закрыть открытую паузу: учесть её длительность по протиканному времени и
## дописать `duration_sec`/`until_sec` в событие паузы. Без открытой паузы — ничего.
func _close_pause() -> void:
	if _pause_event_index < 0:
		return
	if _pause_event_index < events.size():
		var paused_for: float = maxf(_wall_sec - _pause_started_wall_sec, 0.0)
		_paused_total_sec += paused_for
		events[_pause_event_index]["duration_sec"] = paused_for
		events[_pause_event_index]["until_sec"] = float(events[_pause_event_index]["at_sec"]) + paused_for
	_pause_event_index = -1


func _effective_erg() -> bool:
	return erg_enabled and not _freeride_suspended and _erg_available


func _current_step_is_free_ride() -> bool:
	var step := executor.current_step()
	return step != null and step.is_free_ride()


## Повторная отправка текущего режима на станок: при `with_erg` — сначала
## действующее состояние ERG; затем цель (ERG, в том числе 0 Вт) или уровень (не ERG).
func _resend(with_erg: bool) -> void:
	if not controls_trainer():
		return
	var erg_now: bool = _effective_erg()
	if with_erg:
		trainer.set_erg_enabled(erg_now)
	if erg_now:
		trainer.set_target_power(_current_target_w)
	else:
		trainer.set_resistance_level(resistance_level)


## Смена шага: режим FreeRide по В-10 — приостановить/вернуть ERG на станке.
func _on_step_changed(_index: int, step: WorkoutStep) -> void:
	if not controls_trainer():
		return
	var want_suspended: bool = erg_enabled and step.is_free_ride()
	if want_suspended == _freeride_suspended:
		return
	_freeride_suspended = want_suspended
	if not _erg_available:
		# ERG unavailable (U-36, WRK-02 p.7): the trainer stays on fixed resistance, a FreeRide
		# step neither suspends nor resumes ERG on it.
		return
	match _state:
		State.RUNNING:
			if want_suspended:
				trainer.set_erg_enabled(false)
				trainer.set_resistance_level(resistance_level)
			else:
				trainer.set_erg_enabled(true)
				# Цель уйдёт следом из target_changed той же секунды.
		State.PAUSED:
			_erg_pending = true
		_:
			pass


func _on_target_changed(watts: int) -> void:
	_current_target_w = watts
	# На паузе ничего не шлём; цель уйдёт при resume() (REQ-WRK-05 крит. 5).
	# Цель 0 Вт тоже уходит: иначе станок держал бы прежнюю цель.
	if _state == State.RUNNING and _effective_erg():
		trainer.set_target_power(watts)


func _on_second_elapsed(elapsed_sec: int, _step_offset_sec: int, _remaining_sec: int) -> void:
	var sample := _latest_sample
	_power_age = 0 if sample != null and sample.has_power else (_power_age + 1 if _power_age >= 0 else -1)
	_cadence_age = 0 if sample != null and sample.has_cadence else (_cadence_age + 1 if _cadence_age >= 0 else -1)
	_hr_age = 0 if _latest_hr_bpm >= 0 else (_hr_age + 1 if _hr_age >= 0 else -1)
	# Скорость — только модель с уклоном трассы (У-30); поле скорости станка не используется.
	var grade: float = position.grade_pct()
	var model_speed: float
	if sample != null and sample.has_power:
		model_speed = _speed_model.step(float(sample.power_w), weight_kg, 1.0, grade)
	else:
		# Источников мощности нет — тяги нет: скорость — шаг модели при 0 Вт (D3D-02 п.7, У-33, У-34).
		model_speed = _speed_model.step_without_power(weight_kg, 1.0, grade)
	position.advance(model_speed, 1.0)
	samples.append(elapsed_sec - 1, sample, _latest_hr_bpm, current_target_watts(),
		executor.current_step_index(), is_erg_active_on_trainer(), model_speed,
		{"power": _power_age, "cadence": _cadence_age, "heart_rate": _hr_age})
	_latest_sample = null
	_latest_hr_bpm = -1


## Финиш (в том числе пропуском последнего шага на паузе): открытая пауза
## закрывается так же, как при `stop()` — её время идёт в `paused_total_sec`.
func _on_executor_finished() -> void:
	_close_pause()
	_log(EVENT_FINISH, executor.elapsed_sec())
	_set_state(State.FINISHED)
	session_finished.emit()


func _on_telemetry(sample: TrainerSample) -> void:
	_latest_sample = sample


## Пульс 0 от датчика — «нет данных» (решение по REQ-LOC-04 крит. 5: 0 уд/мин
## не попадает ни в одну зону, поэтому в сэмпле это отсутствие пульса).
func _on_heart_rate(bpm: int) -> void:
	_latest_hr_bpm = bpm if bpm > 0 else -1


func _on_connection_state_changed(state: int) -> void:
	if _state != State.RUNNING and _state != State.PAUSED:
		return
	match state:
		TrainerDevice.ConnectionState.RECONNECTING, TrainerDevice.ConnectionState.DISCONNECTED:
			_log(EVENT_DISCONNECT, TrainerDevice.state_name(state))
			_erg_unavailable_logged = false  # a new connection starts
		TrainerDevice.ConnectionState.CONNECTED:
			_log(EVENT_RECONNECT, TrainerDevice.state_name(state))
			# На паузе — ничего: цель уйдёт при resume() (уточнение DEV-08.3, приоритет В-4).
			if _state == State.RUNNING:
				_resend(true)


## Возможности станка изменились: ERG стал недоступен (или снова доступен) — режим станка
## переотправляется (без ERG — уровень сопротивления), HUD узнаёт сигналом.
func _on_trainer_capabilities() -> void:
	var available: bool = erg_available()
	if available == _erg_available:
		return
	_erg_available = available
	erg_availability_changed.emit(available)
	if not available and (_state == State.RUNNING or _state == State.PAUSED):
		_log_erg_unavailable()
	if _state == State.RUNNING and controls_trainer():
		_resend(true)
	elif _state == State.PAUSED:
		_erg_pending = true


## "ERG unavailable" ride event: once per connection (a new refusal after a reconnect logs again).
func _log_erg_unavailable() -> void:
	if _erg_unavailable_logged:
		return
	_erg_unavailable_logged = true
	_log(EVENT_ERG_UNAVAILABLE, executor.elapsed_sec())


## Key of the rule that turns plan targets into what HUD shows (DEV-10 p.6, U-37): empty outside
## ERG mode (`is_erg_mode`; plan targets everywhere), otherwise the trainer's target range.
## Models rebuild their targets when it changes.
func target_rule_key() -> String:
	if not is_erg_mode():
		return ""
	return var_to_str(trainer.target_power_range())


## Ошибка записи на станок: один повтор текущей цели/уровня, не чаще раза в секунду (REQ-NFR-01 крит. 2).
func _on_trainer_error(code: int, _message: String) -> void:
	if code != TrainerDevice.ErrorCode.WRITE_FAILED or _state != State.RUNNING:
		return
	var now_sec: int = executor.elapsed_sec()
	if now_sec == _last_retry_sec:
		return
	_last_retry_sec = now_sec
	_log(EVENT_RETRY, now_sec)
	_resend(false)
