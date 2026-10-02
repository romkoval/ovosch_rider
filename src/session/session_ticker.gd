class_name SessionTicker
extends Node
## Источник времени для `WorkoutSession` (REQ-NFR-02 крит. 1, 2): тикает сессию
## по РЕАЛЬНО прошедшему времени системных часов, а не по delta кадра.
##
## На каждом `_process` (или при явном `poll()`) берётся `now_usec()`, считается
## прошедшее с предыдущего опроса время и передаётся в `session.tick()`. Если кадр
## завис на 2 с, следующий опрос отдаст ~2.0 — сессия сама нарежет дельту по
## секундным границам и допишет пропущенные сэмплы постфактум.
##
## Часы инъецируются (`now_usec: Callable`, по умолчанию `Time.get_ticks_usec`),
## поэтому в тестах время продвигается детерминированно без ожидания.
## `time_scale` ускоряет прогон (экран разработчика).

## Доставлена дельта в сессию (в секундах сессионного времени, с учётом `time_scale`).
signal ticked(delta_sec: float)

## Защита от абсурдного скачка часов (например, после сна машины): больше не передаём.
const MAX_DELTA_SEC: float = 3600.0
const MIN_TIME_SCALE: float = 0.01
const MAX_TIME_SCALE: float = 1000.0

var session: WorkoutSession = null
## Множитель времени: 10.0 → секунда реального времени = 10 с сессии.
var time_scale: float = 1.0
## Сумма доставленных в сессию дельт, с (сессионное время).
var delivered_sec: float = 0.0
## Сумма реального времени, учтённого в опросах, с.
var real_elapsed_sec: float = 0.0

var _now_usec: Callable
var _last_usec: int = 0
var _running: bool = false


func _init(now_usec: Callable = Callable()) -> void:
	_now_usec = now_usec if now_usec.is_valid() else Callable(Time, "get_ticks_usec")
	set_process(false)


## Привязать сессию (можно до или после `start()`).
func attach(workout_session: WorkoutSession) -> void:
	session = workout_session


## Запустить отсчёт: базовая отметка берётся сейчас, время до старта не догоняется.
func start() -> void:
	_last_usec = _read_now()
	_running = true
	set_process(true)


## Остановить: пока остановлен, опросы ничего не доставляют и не копят долг.
func stop() -> void:
	_running = false
	set_process(false)


func is_running() -> bool:
	return _running


## Множитель времени, ограничен [0.01; 1000].
func set_time_scale(scale: float) -> void:
	time_scale = clampf(scale, MIN_TIME_SCALE, MAX_TIME_SCALE)


## Опросить часы и доставить прошедшее время в сессию. Возвращает доставленную дельту
## (0, если остановлен или время не сдвинулось). Вызывается из `_process` и тестами.
func poll() -> float:
	if not _running:
		return 0.0
	var now: int = _read_now()
	var real_delta: float = float(now - _last_usec) / 1_000_000.0
	_last_usec = now
	if real_delta <= 0.0:
		return 0.0
	if real_delta > MAX_DELTA_SEC:
		push_warning("SessionTicker: скачок часов %.1f с обрезан до %.0f с" % [real_delta, MAX_DELTA_SEC])
		real_delta = MAX_DELTA_SEC
	real_elapsed_sec += real_delta
	var delta: float = real_delta * time_scale
	delivered_sec += delta
	if session != null:
		session.tick(delta)
	ticked.emit(delta)
	return delta


func _process(_frame_delta: float) -> void:
	poll()


func _read_now() -> int:
	return int(_now_usec.call())
