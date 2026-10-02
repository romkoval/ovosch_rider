class_name BleReconnectPolicy
extends RefCounted
## Политика переподключения BLE-устройств (REQ-DEV-08 крит. 1, решение 12):
## после обрыва — попытка сразу, затем каждые `interval_sec` (5 с) без
## ограничения числа попыток, пока владелец не вызовет `stop()`.
## Время подаётся снаружи (`now_sec`), чтобы тесты шли быстрее реального.

const TIME_EPSILON: float = 1e-6

var interval_sec: float = 5.0
var active: bool = false
var attempts: int = 0
var _next_sec: float = 0.0


func _init(interval: float = 5.0) -> void:
	interval_sec = maxf(interval, 0.0)


## Начать серию попыток; первая — немедленно (следующий `due(now)` → true).
func start(now_sec: float) -> void:
	active = true
	attempts = 0
	_next_sec = now_sec


## true, если пора делать попытку; при этом планирует следующую через `interval_sec`.
func due(now_sec: float) -> bool:
	if not active or now_sec + TIME_EPSILON < _next_sec:
		return false
	_next_sec = now_sec + interval_sec
	attempts += 1
	return true


func stop() -> void:
	active = false


func next_attempt_sec() -> float:
	return _next_sec
