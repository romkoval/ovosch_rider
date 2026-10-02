class_name SensorDevice
extends RefCounted
## Интерфейс внешнего датчика (пульс, каденс, измеритель мощности): REQ-DEV-03/04/05/07.
##
## Состояния подключения — значения `TrainerDevice.ConnectionState` (общая модель
## REQ-DEV-07 крит. 1). Время продвигается извне через `tick(delta_sec)`.
## Конкретные измерения — сигналами наследников (`heart_rate`, `cadence`, `power`);
## `SensorHub` подключается к ним по имени сигнала.

enum ErrorCode { NONE, CONNECTION_FAILED, SUBSCRIBE_FAILED, NOT_CONNECTED }

## Тип датчика: "heart_rate" | "cadence" | "power".
const KIND_HEART_RATE: String = "heart_rate"
const KIND_CADENCE: String = "cadence"
const KIND_POWER: String = "power"

## `state` — `TrainerDevice.ConnectionState`.
signal connection_state_changed(state: int)
## Заряд батареи 0..100 % (REQ-DEV-07 крит. 2).
signal battery_level(percent: int)
signal error(code: int, message: String)


func kind() -> String:
	return ""


func connect_device(_id: String) -> void:
	push_error("SensorDevice.connect_device: not implemented")


func disconnect_device() -> void:
	push_error("SensorDevice.disconnect_device: not implemented")


func tick(_delta_sec: float) -> void:
	push_error("SensorDevice.tick: not implemented")


func get_connection_state() -> int:
	push_error("SensorDevice.get_connection_state: not implemented")
	return TrainerDevice.ConnectionState.DISCONNECTED


## Последний известный заряд, %; -1 — неизвестен / сервиса нет («—», REQ-DEV-07 крит. 3).
func get_battery_level() -> int:
	return -1
