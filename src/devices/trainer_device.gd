class_name TrainerDevice
extends RefCounted
## Интерфейс умного велостанка. Единственная точка общения игровой части со станком.
##
## Контракт (REQ-DEV-02, REQ-DEV-08, REQ-WRK-02/03/04, REQ-WRK-08, REQ-NFR-02):
## - Реализации: `BleTrainer` (нативный FTMS-мост) и `FakeTrainer` (эмулятор).
##   Какая реализация подключена, знает только `src/devices/` (см. `TrainerFactory`).
## - Класс не является Node: время продвигается извне через `tick(delta_sec)`.
##   Исполнитель тренировки вызывает `tick` из собственного источника времени
##   (таймер/поток), а не из `_process`, чтобы приём данных не зависел от кадров.
## - Все сигналы испускаются синхронно внутри `tick()` или внутри вызова метода
##   (для немедленных переходов состояния). Подписчик не должен рассчитывать на
##   вызов из главного потока сцены.
## - Телеметрия идёт потоком ~1 Гц; отсутствующие значения помечены флагами
##   `has_*` в `TrainerSample`, а не нулями.
## - Команды (цель мощности, ERG, сопротивление) должны уходить на станок не позже
##   1 с после вызова (REQ-NFR-01); у эмулятора — немедленно, с меткой времени.

## Состояние подключения. Переходы:
## DISCONNECTED → SCANNING (опционально) → CONNECTING → CONNECTED;
## CONNECTED → RECONNECTING (обрыв связи) → CONNECTED (восстановление);
## любое → DISCONNECTED (по `disconnect_device()` или окончательной ошибке).
enum ConnectionState {
	DISCONNECTED,
	SCANNING,
	CONNECTING,
	CONNECTED,
	RECONNECTING,
}

## Коды ошибок сигнала `error`.
enum ErrorCode {
	NONE,
	## Не удалось установить соединение (устройство не найдено, отказ, таймаут).
	CONNECTION_FAILED,
	## Станок отверг команду Control Point (FTMS result != 0x01, REQ-DEV-02 крит. 3).
	CONTROL_POINT_REJECTED,
	## Запись характеристики не удалась на транспортном уровне (REQ-NFR-01 крит. 2).
	WRITE_FAILED,
	## Команда (цель мощности, ERG, сопротивление) вызвана в состоянии
	## DISCONNECTED, SCANNING или CONNECTING: отклонена и не применена.
	## В RECONNECTING команды принимаются (реализация доставит их после восстановления).
	NOT_CONNECTED,
}

## Допустимые диапазоны аргументов команд.
const MIN_TARGET_POWER_W: int = 0
const MAX_TARGET_POWER_W: int = 2000
const MIN_RESISTANCE_PERCENT: int = 0
const MAX_RESISTANCE_PERCENT: int = 100

## Изменилось состояние подключения; `state` — значение `ConnectionState`.
signal connection_state_changed(state: int)
## Новый сэмпл телеметрии станка (мощность/каденс/скорость), ~1 Гц.
signal telemetry(sample: TrainerSample)
## Пульс, уд/мин, если станок передаёт его в Indoor Bike Data (или эмулятор его выдаёт).
signal heart_rate(bpm: int)
## Ошибка устройства или команды; `code` — значение `ErrorCode`, `message` — текст для журнала/HUD.
signal error(code: int, message: String)


## Начать подключение к устройству с идентификатором `id`
## (для BLE — идентификатор периферии, для эмулятора — произвольная строка).
## Асинхронно: результат приходит через `connection_state_changed`.
func connect_device(_id: String) -> void:
	push_error("TrainerDevice.connect_device: not implemented")


## Разорвать соединение. Переводит состояние в DISCONNECTED; переподключение не выполняется.
func disconnect_device() -> void:
	push_error("TrainerDevice.disconnect_device: not implemented")


## Установить целевую мощность, Вт (целые, 0..2000). Действует в ERG-режиме
## (FTMS Set Target Power 0x05). Вне ERG значение запоминается и применяется
## при включении ERG (REQ-WRK-03 крит. 3).
func set_target_power(_watts: int) -> void:
	push_error("TrainerDevice.set_target_power: not implemented")


## Включить/выключить ERG-режим. При выключении станок переходит на фиксированное
## сопротивление `set_resistance_level` (REQ-WRK-03 крит. 2, REQ-WRK-04).
func set_erg_enabled(_enabled: bool) -> void:
	push_error("TrainerDevice.set_erg_enabled: not implemented")


## Установить уровень сопротивления в процентах 0..100 (REQ-WRK-04). Перевод
## в единицы станка (FTMS Set Target Resistance Level 0x04, единицы 0.1) —
## забота реализации. При включённом ERG значение запоминается, но не применяется.
func set_resistance_level(_percent: int) -> void:
	push_error("TrainerDevice.set_resistance_level: not implemented")


## Текущее состояние подключения (`ConnectionState`).
func get_connection_state() -> int:
	push_error("TrainerDevice.get_connection_state: not implemented")
	return ConnectionState.DISCONNECTED


## Продвинуть внутренние часы устройства на `delta_sec` секунд (> 0).
## Вызывается исполнителем из его источника времени, не из `_process`.
## Внутри реализация обрабатывает таймеры подключения и выдаёт накопленные события.
func tick(_delta_sec: float) -> void:
	push_error("TrainerDevice.tick: not implemented")


## Человекочитаемое имя состояния — для журнала и HUD.
static func state_name(state: int) -> String:
	match state:
		ConnectionState.DISCONNECTED:
			return "disconnected"
		ConnectionState.SCANNING:
			return "scanning"
		ConnectionState.CONNECTING:
			return "connecting"
		ConnectionState.CONNECTED:
			return "connected"
		ConnectionState.RECONNECTING:
			return "reconnecting"
	return "unknown"
