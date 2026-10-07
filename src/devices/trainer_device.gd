class_name TrainerDevice
extends RefCounted
## Интерфейс умного велостанка. Единственная точка общения игровой части со станком.
##
## Контракт (REQ-DEV-02, REQ-DEV-08, REQ-WRK-02/03/04, REQ-WRK-08, REQ-NFR-02, REQ-FRD-04):
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
## - Команды (цель мощности, ERG, сопротивление, SIM) должны уходить на станок не позже
##   1 с после вызова (REQ-NFR-01); у эмулятора — немедленно, с меткой времени.
## - Источник станка (`is_emulator`, `trainer_source`, T-160): эмулятор это или реальное
##   устройство. Сессия пишет его в метаданные заезда, не проверяя класс реализации
##   (REQ-DEV-09 крит. 1, REQ-NFR-06 крит. 3).
## - Режим сессии (`trainer_mode()`, REQ-WRK-09): `MODE_SMART` — управляемый станок (команды
##   уходят на него); `MODE_POWER_METER` — источник мощности без управления (`UncontrolledTrainer`):
##   команды управления не уходят никуда, сессия их и не вызывает. Сессия читает режим один раз
##   при создании и пишет его в метаданные заезда, не проверяя класс реализации.
## - Канал управления (`has_control()`, REQ-WRK-09 «Термины», DEV-10 п.4): есть ли у подключённого
##   станка Control Point. Станок без него — только источник данных. `set_control_allowed(false)`
##   запрещает станку брать управление (на время сессии `power_meter`: станок, подключившийся
##   посреди такой сессии, не получает ни одной записи, WRK-09 п.1).

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

## Поддержка SIM-режима (FTMS Indoor Bike Simulation, REQ-FRD-04 крит. 6).
## UNKNOWN — ещё не определена (не подключались, признаки станка не прочитаны);
## SUPPORTED — станок заявил поддержку или принял команду SIM;
## UNSUPPORTED — не заявил или отверг команду SIM (тогда — фиксированное сопротивление).
enum SimulationSupport {
	UNKNOWN,
	SUPPORTED,
	UNSUPPORTED,
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
	## Станок отверг команду SIM (FTMS 0x11, result != 0x01): поддержка SIM после этого
	## UNSUPPORTED (REQ-FRD-04 крит. 6).
	SIMULATION_REJECTED,
}

## Источник станка в метаданных заезда (`trainer_source`, T-160, Н-59): реальное устройство
## или эмулятор. Это ось «откуда данные», а не режим управления станком.
const SOURCE_BLE: String = "ble"
const SOURCE_EMULATOR: String = "emulator"

## Режим сессии в метаданных заезда (`trainer_mode`, REQ-WRK-09 п.8, LOC-01 п.1): управляемый
## станок или источник мощности без управления. Отдельная ось от `trainer_source`.
const MODE_SMART: String = "smart"
const MODE_POWER_METER: String = "power_meter"

## Допустимые диапазоны аргументов команд.
const MIN_TARGET_POWER_W: int = 0
const MAX_TARGET_POWER_W: int = 2000
const MIN_RESISTANCE_PERCENT: int = 0
const MAX_RESISTANCE_PERCENT: int = 100
## Параметры SIM: пределы — представимые в команде FTMS 0x11 значения (REQ-FRD-04 крит. 1).
const MAX_SIM_GRADE_PCT: float = 327.67
const MAX_SIM_WIND_MPS: float = 32.767
const MAX_SIM_CRR: float = 0.0255
const MAX_SIM_CW: float = 2.55
## Значения SIM по умолчанию (вводный абзац FRD): ветер 0, Crr 0.004, Cw 0.20 кг/м.
const DEFAULT_SIM_WIND_MPS: float = 0.0
const DEFAULT_SIM_CRR: float = 0.004
const DEFAULT_SIM_CW: float = 0.20
## Запасной диапазон уклона SIM, %, если станок не сообщил свой (REQ-FRD-04 крит. 3).
const DEFAULT_INCLINATION_MIN_PCT: float = -10.0
const DEFAULT_INCLINATION_MAX_PCT: float = 20.0

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
## Любой из вызовов завершает SIM-режим (`set_simulation`); `false` в SIM — переход
## на фиксированное сопротивление.
func set_erg_enabled(_enabled: bool) -> void:
	push_error("TrainerDevice.set_erg_enabled: not implemented")


## Режим ERG, в котором находится устройство по последней принятой команде
## (по умолчанию — включён). Устройство живёт дольше сессии тренировки: сессия
## сверяется с этим значением на старте и при расхождении отправляет режим заново.
func is_erg_enabled() -> bool:
	push_error("TrainerDevice.is_erg_enabled: not implemented")
	return true


## Установить уровень сопротивления в процентах 0..100 (REQ-WRK-04). Перевод
## в единицы станка (FTMS Set Target Resistance Level 0x04, единицы 0.1) —
## забота реализации. При включённом ERG значение запоминается, но не применяется.
## В SIM-режиме — применяется и переводит станок на фиксированное сопротивление
## (REQ-FRD-05 крит. 4).
func set_resistance_level(_percent: int) -> void:
	push_error("TrainerDevice.set_resistance_level: not implemented")


## Включить SIM-режим и передать станку параметры симуляции: уклон, %
## (округляется до 0.01), ветер, м/с, Crr, Cw, кг/м (FTMS Set Indoor Bike
## Simulation Parameters 0x11, REQ-FRD-04 крит. 1). Значения вне пределов
## `MAX_SIM_*` обрезаются с предупреждением. Команда переводит станок из ERG и
## фиксированного сопротивления в SIM: после неё `is_erg_enabled() == false`.
## Выход из SIM — `set_resistance_level` (фиксированное сопротивление) или
## `set_erg_enabled`. Ограничение уклона диапазоном `inclination_range()`, частоту
## и порог отправки выдерживает вызывающий. Вне подключения — как у остальных команд.
## Отказ станка → `error(SIMULATION_REJECTED)` и `simulation_support() == UNSUPPORTED`.
func set_simulation(_grade_pct: float, _wind_mps: float = DEFAULT_SIM_WIND_MPS,
		_crr: float = DEFAULT_SIM_CRR, _cw: float = DEFAULT_SIM_CW) -> void:
	push_error("TrainerDevice.set_simulation: not implemented")


## Поддерживает ли станок SIM (`SimulationSupport`, REQ-FRD-04 крит. 6).
func simulation_support() -> int:
	push_error("TrainerDevice.simulation_support: not implemented")
	return SimulationSupport.UNKNOWN


## Допустимый диапазон уклона SIM, % (x — минимум, y — максимум): сообщённый станком
## или запасной `DEFAULT_INCLINATION_MIN_PCT..DEFAULT_INCLINATION_MAX_PCT` (REQ-FRD-04 крит. 3).
func inclination_range() -> Vector2:
	push_error("TrainerDevice.inclination_range: not implemented")
	return Vector2(DEFAULT_INCLINATION_MIN_PCT, DEFAULT_INCLINATION_MAX_PCT)


## Параметры SIM, приведённые к допустимым пределам, с уклоном, округлённым до 0.01 %:
## `[grade_pct, wind_mps, crr, cw]`. Общая часть реализаций `set_simulation`; выход
## за пределы или нечисловое значение — предупреждение с именем реализации `who`.
static func clamp_simulation_params(who: String, grade_pct: float, wind_mps: float, crr: float,
		cw: float) -> Array[float]:
	var grade: float = _clamp_sim_param(who, "grade_pct", grade_pct, -MAX_SIM_GRADE_PCT, MAX_SIM_GRADE_PCT, 0.0)
	var wind: float = _clamp_sim_param(who, "wind_mps", wind_mps, -MAX_SIM_WIND_MPS, MAX_SIM_WIND_MPS,
		DEFAULT_SIM_WIND_MPS)
	var c_rr: float = _clamp_sim_param(who, "crr", crr, 0.0, MAX_SIM_CRR, DEFAULT_SIM_CRR)
	var c_w: float = _clamp_sim_param(who, "cw", cw, 0.0, MAX_SIM_CW, DEFAULT_SIM_CW)
	return [snappedf(grade, 0.01), wind, c_rr, c_w]


static func _clamp_sim_param(who: String, param: String, value: float, lo: float, hi: float,
		fallback: float) -> float:
	var v: float = clampf(value, lo, hi) if is_finite(value) else fallback
	if v != value:
		push_warning("%s.set_simulation: %s = %s вне диапазона %s..%s, заменён на %s" % [who, param, value, lo, hi, v])
	return v


## Эмулятор ли это (данные не с настоящего станка). `FakeTrainer` — да, `BleTrainer` — нет;
## обёртки (`SensorHub`) отвечают за свой станок (T-160).
func is_emulator() -> bool:
	push_error("TrainerDevice.is_emulator: not implemented")
	return false


## Режим сессии с этим устройством: `MODE_SMART` (по умолчанию) или `MODE_POWER_METER`
## (устройство без управления, REQ-WRK-09).
func trainer_mode() -> String:
	return MODE_SMART


## Есть ли у станка канал управления (FTMS Control Point, REQ-WRK-09 «Термины», DEV-10 п.4).
## Смысл имеет в состоянии CONNECTED; по умолчанию — есть.
func has_control() -> bool:
	return true


## Разрешить или запретить станку брать управление (Request Control и любые записи команд).
## По умолчанию разрешено; реализации без автоматических записей могут ничего не делать.
func set_control_allowed(_allowed: bool) -> void:
	pass


## Источник станка для метаданных заезда: `SOURCE_EMULATOR` или `SOURCE_BLE` (T-160).
func trainer_source() -> String:
	return SOURCE_EMULATOR if is_emulator() else SOURCE_BLE


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
