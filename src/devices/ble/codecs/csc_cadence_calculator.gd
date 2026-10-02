class_name CscCadenceCalculator
extends RefCounted
## Каденс из потока CSC/CPS crank data с учётом времени (REQ-DEV-04 крит. 1–3).
##
## `push(measurement, now_sec)` принимает словарь с `has_crank`, `crank_revolutions`,
## `crank_event_time` и возвращает каденс (целые rpm) или -1 («нет данных»).
## Правила: первое измерение → -1 (нужна пара); новое событие → расчёт по
## `CscCodec.cadence_from_pair`; измерение без нового события → удерживается
## последнее значение, пока с последнего нового оборота не пройдёт
## `zero_timeout_sec` (3 с по умолчанию) — затем 0 (и если пары ещё не было).
##
## Два разных «молчания» (решение Н-4, REQ-DEV-04 крит. 3 / REQ-DEV-05 крит. 3):
## - пакеты идут, обороты стоят ≥ 3 с → каденс 0 (`current()`, `value()`);
## - пакетов нет ≥ 3 с → «нет данных» (`is_silent()`, `value()` → -1), чтобы
##   `SensorHub` сразу уступил следующему источнику без ложного нуля.
## `current()` намеренно не смотрит на пакеты (чистый расчёт по оборотам);
## потребителям нужен `value()`.

var zero_timeout_sec: float = 3.0

var _prev: Dictionary = {}
var _last_rpm: int = -1
## Время последнего измерения с новыми оборотами.
var _last_event_at_sec: float = -INF
## Время последнего пакета с crank data (с новыми оборотами или без).
var _last_packet_at_sec: float = -INF


func push(measurement: Dictionary, now_sec: float) -> int:
	if not measurement.get("has_crank", false):
		return current(now_sec)
	_last_packet_at_sec = now_sec
	if _prev.is_empty():
		_prev = measurement.duplicate()
		_last_event_at_sec = now_sec
		return -1
	var rpm: float = CscCodec.cadence_from_pair(_prev, measurement)
	if rpm >= 0.0:
		_prev = measurement.duplicate()
		_last_event_at_sec = now_sec
		_last_rpm = roundi(rpm)
		return _last_rpm
	return current(now_sec)


## Пакеты с crank data не приходили ≥ `zero_timeout_sec` (или их не было вовсе).
func is_silent(now_sec: float) -> bool:
	return now_sec - _last_packet_at_sec >= zero_timeout_sec


## Значение для потребителя: -1 при молчании датчика (нет пакетов ≥ 3 с), иначе `current()`.
func value(now_sec: float) -> int:
	if is_silent(now_sec):
		return -1
	return current(now_sec)


## Текущее значение в момент `now_sec`: последнее значение, либо 0, если с
## последнего измерения с новыми оборотами прошло ≥ `zero_timeout_sec` — в том
## числе когда валидной пары ещё не было (педали стоят с самого подключения,
## REQ-DEV-04 крит. 3 безусловен). -1 — только до первого измерения или пока
## не прошло 3 с без двух различающихся измерений.
func current(now_sec: float) -> int:
	if _prev.is_empty():
		return -1
	if now_sec - _last_event_at_sec >= zero_timeout_sec:
		return 0
	return _last_rpm


func reset() -> void:
	_prev = {}
	_last_rpm = -1
	_last_event_at_sec = -INF
	_last_packet_at_sec = -INF
