class_name FakeTrainer
extends TrainerDevice
## Детерминированный эмулятор станка (REQ-DEV-09) для тестов и разработки без железа.
##
## Время полностью управляется извне через `tick(delta_sec)`: часы эмулятора
## накапливают дельты и на каждой целой секунде выдают один сэмпл телеметрии
## (за 600 с ровно 600 сэмплов). Весь шум берётся из RandomNumberGenerator
## с фиксированным seed — при одинаковом seed и одинаковых вызовах результат
## побайтно совпадает.
##
## Модель «всадника»:
## - В ERG с ненулевой целью выдаваемая мощность экспоненциально стремится к цели
##   с постоянной времени `power_tau_sec` (через 3 с отклонение ≤ 5 %, REQ-DEV-09 крит. 2).
## - Вне ERG или при цели 0 (FreeRide) мощность стремится к `rider_power_w` —
##   тому, что «крутит человек».
## - Каденс ~ `rider_cadence_rpm` ± шум; при каденсе 0 всадник не педалирует и
##   мощность стремится к 0.
## - Скорость — по кубическому корню из мощности: 34 км/ч при 200 Вт
##   (опорная точка из «Открытых решений», п. 15).
##
## Журнал команд `commands`: каждый вызов команды записывается словарём
## `{type: "target_power"|"erg"|"resistance", value, at_sec}`, где `at_sec` —
## показание часов эмулятора в момент вызова. Журнал фиксирует, что послал
## исполнитель, включая отклонённые команды; отклонение сообщается только
## сигналом `error`. По `at_sec` тесты проверяют задержку отправки команд
## (REQ-WRK-02 крит. 2, REQ-WRK-03 крит. 2/3, REQ-WRK-04 крит. 2).
##
## Команды принимаются в состояниях CONNECTED и RECONNECTING (во втором случае
## применяются сразу — так исполнитель может повторно послать цель при
## переподключении, REQ-DEV-08 крит. 3). В DISCONNECTED/SCANNING/CONNECTING
## команда отклоняется с `error(NOT_CONNECTED)` и не применяется.

## Тип команды в журнале.
const CMD_TARGET_POWER: String = "target_power"
const CMD_ERG: String = "erg"
const CMD_RESISTANCE: String = "resistance"

## Допуск сравнения времени с целой секундой (защита от накопления ошибки float).
const TIME_EPSILON: float = 1e-6
## Максимальная дельта одного тика, с (сутки); большее — ошибка вызывающего, клампится.
const MAX_TICK_SEC: float = 86400.0
## Порог защёлкивания мощности на цель, Вт: ближе этого модель считает цель достигнутой.
const POWER_SNAP_W: float = 1.0
## Коэффициент модели скорости: 34 км/ч при 200 Вт → k = 34 / 200^(1/3).
const SPEED_COEFF: float = 34.0 / 5.848035476

# --- Настройки сценария (меняются тестом до или во время прогона) ---

## Задержка CONNECTING → CONNECTED, с.
var connect_delay_sec: float = 0.5
## Постоянная времени сходимости мощности к цели, с. При 0.4 через 3 с от
## перепада остаётся 0.055 % (2000→100 Вт: ~1 Вт), что укладывается в 5 % цели.
var power_tau_sec: float = 0.4
## Амплитуда равномерного шума мощности, Вт (±).
var power_noise_w: float = 1.0
## Амплитуда равномерного шума каденса, об/мин (±).
var cadence_noise_rpm: float = 3.0
## Мощность всадника вне ERG / при цели 0, Вт.
var rider_power_w: int = 150
## Каденс всадника, об/мин. 0 — всадник не педалирует.
var rider_cadence_rpm: int = 85
## Передавать ли поле скорости в телеметрии (false — станок без поля скорости,
## сессия берёт скорость из модели, REQ-WRK-08 крит. 5).
var emit_speed: bool = true

# --- Журнал и состояние, доступные тестам на чтение ---

## Журнал команд: `{type, value, at_sec}` в порядке вызова.
var commands: Array[Dictionary] = []
## Идентификатор устройства, переданный в `connect_device`.
var device_id: String = ""
## Текущие параметры, принятые станком.
var erg_enabled: bool = true
var target_power_w: int = 0
var resistance_percent: int = 0
## Число выданных сэмплов телеметрии (без потерянных пакетов).
var samples_emitted: int = 0

# --- Внутреннее состояние ---

var _rng := RandomNumberGenerator.new()
var _seed: int = 0
var _state: int = ConnectionState.DISCONNECTED
var _time_sec: float = 0.0
var _next_sample_sec: int = 1
var _power_w: float = 0.0
var _connect_at_sec: float = -1.0
var _dropout_until_sec: float = -1.0
var _silence_until_sec: float = -1.0
var _packet_loss_ratio: float = 0.0
var _fail_next_connect: bool = false
var _fail_next_command: bool = false
var _fail_next_code: int = ErrorCode.CONTROL_POINT_REJECTED
var _heart_rate_sequence: Array[int] = []
var _heart_rate_index: int = 0
var _cadence_sequence: Array[int] = []
var _cadence_index: int = 0


func _init(seed: int = 42) -> void:
	_seed = seed
	_rng.seed = seed


## Seed генератора шума (для воспроизведения прогона).
func get_seed() -> int:
	return _seed


## Показание часов эмулятора, с.
func get_time_sec() -> float:
	return _time_sec


# ---------------------------------------------------------------------------
# TrainerDevice
# ---------------------------------------------------------------------------

func connect_device(id: String) -> void:
	if _state == ConnectionState.CONNECTED or _state == ConnectionState.CONNECTING:
		return
	if _state == ConnectionState.RECONNECTING:
		# Переподключение уже идёт (восстановится по таймеру обрыва).
		return
	device_id = id
	_connect_at_sec = _time_sec + maxf(connect_delay_sec, 0.0)
	_set_state(ConnectionState.CONNECTING)
	if connect_delay_sec <= 0.0:
		_finish_connect()


func disconnect_device() -> void:
	_connect_at_sec = -1.0
	_dropout_until_sec = -1.0
	if _state != ConnectionState.DISCONNECTED:
		_set_state(ConnectionState.DISCONNECTED)


func set_target_power(watts: int) -> void:
	var value: int = clampi(watts, MIN_TARGET_POWER_W, MAX_TARGET_POWER_W)
	if watts != value:
		push_warning("FakeTrainer.set_target_power: %d вне диапазона, обрезано до %d" % [watts, value])
	if _accept_command(CMD_TARGET_POWER, value):
		target_power_w = value


func set_erg_enabled(enabled: bool) -> void:
	if _accept_command(CMD_ERG, enabled):
		erg_enabled = enabled


func is_erg_enabled() -> bool:
	return erg_enabled


func set_resistance_level(percent: int) -> void:
	var value: int = clampi(percent, MIN_RESISTANCE_PERCENT, MAX_RESISTANCE_PERCENT)
	if percent != value:
		push_warning("FakeTrainer.set_resistance_level: %d вне диапазона, обрезано до %d" % [percent, value])
	if _accept_command(CMD_RESISTANCE, value):
		resistance_percent = value


func get_connection_state() -> int:
	return _state


func tick(delta_sec: float) -> void:
	if delta_sec <= 0.0:
		return
	if delta_sec > MAX_TICK_SEC:
		push_warning("FakeTrainer.tick: delta %.1f с больше суток, обрезано до %.0f" % [delta_sec, MAX_TICK_SEC])
		delta_sec = MAX_TICK_SEC
	var end_sec: float = _time_sec + delta_sec
	# Накопление float: 50 × 0.2 с ≠ ровно 10.0 — выравниваем на целую секунду, чтобы метки
	# команд совпадали с границами исполнителя (REQ-NFR-01 крит. 1 при кадрах 0.2 с).
	if absf(end_sec - roundf(end_sec)) < TIME_EPSILON:
		end_sec = roundf(end_sec)
	# Проходим все целые секунды внутри интервала (прошлое, end_sec]: сначала
	# применяем переходы состояния, наступившие к этой секунде, затем выдаём сэмпл.
	# Переход, приходящийся ровно на целую секунду, применяется после слота
	# сэмпла этой секунды: обрыв на N с глотает ровно N сэмплов.
	while float(_next_sample_sec) <= end_sec + TIME_EPSILON:
		var sample_sec: int = _next_sample_sec
		_time_sec = float(sample_sec)
		_advance_state(true)
		if _state == ConnectionState.CONNECTED:
			_emit_sample(sample_sec)
		_next_sample_sec += 1
	_time_sec = end_sec
	_advance_state(false)


# ---------------------------------------------------------------------------
# Сценарии для тестов
# ---------------------------------------------------------------------------

## Мощность, которую всадник выдаёт вне ERG (или при цели 0), Вт.
func set_rider_power(watts: int) -> void:
	rider_power_w = maxi(watts, 0)


## Каденс всадника, об/мин; 0 — остановка педалирования (мощность падает до 0).
## Сбрасывает последовательность каденса, заданную `set_cadence_sequence`.
func set_rider_cadence(rpm: int) -> void:
	rider_cadence_rpm = maxi(rpm, 0)
	_cadence_sequence.clear()
	_cadence_index = 0


## Сценарий «нулевой каденс»: всадник перестал педалировать.
func set_zero_cadence() -> void:
	set_rider_cadence(0)


## Обрыв связи на `duration_sec` секунд: состояние → RECONNECTING, телеметрия
## не идёт; по истечении — CONNECTED и телеметрия возобновляется (REQ-DEV-08).
## Журнал команд при этом сохраняется.
func inject_dropout(duration_sec: float) -> void:
	if _state != ConnectionState.CONNECTED:
		push_warning("FakeTrainer.inject_dropout: станок не подключён, обрыв проигнорирован")
		return
	_dropout_until_sec = _time_sec + maxf(duration_sec, 0.0)
	_set_state(ConnectionState.RECONNECTING)
	_advance_state(false)


## Доля случайно теряемых сэмплов 0..1 (детерминированно по seed).
func inject_packet_loss(ratio: float) -> void:
	_packet_loss_ratio = clampf(ratio, 0.0, 1.0)


## Пропуск пакетов: `duration_sec` секунд без телеметрии при сохранении
## состояния CONNECTED (REQ-DEV-09 крит. 3, REQ-WRK-08 крит. 4).
func inject_silence(duration_sec: float) -> void:
	_silence_until_sec = _time_sec + maxf(duration_sec, 0.0)


## Следующая команда (target_power/erg/resistance) будет отвергнута станком:
## попадёт в журнал, но не применится, и придёт `error(code)` — по умолчанию
## CONTROL_POINT_REJECTED; `WRITE_FAILED` эмулирует двойной отказ записи (REQ-NFR-01 крит. 2).
func fail_next_command(code: int = ErrorCode.CONTROL_POINT_REJECTED) -> void:
	_fail_next_command = true
	_fail_next_code = code


## Следующий `connect_device` завершится ошибкой: `error(CONNECTION_FAILED)` и DISCONNECTED.
func fail_next_connect() -> void:
	_fail_next_connect = true


## Последовательность пульса, уд/мин, по одному значению в секунду; последнее
## значение удерживается. Пустой массив выключает сигнал `heart_rate`.
func set_heart_rate_sequence(values: Array[int]) -> void:
	_heart_rate_sequence = values.duplicate()
	_heart_rate_index = 0


## Постоянный пульс, уд/мин (0 — выключить).
func set_heart_rate(bpm: int) -> void:
	if bpm <= 0:
		set_heart_rate_sequence([])
	else:
		set_heart_rate_sequence([bpm])


## Последовательность каденса, об/мин, по одному значению в секунду вместо
## модели всадника; последнее значение удерживается. Пустой массив — вернуться к модели.
func set_cadence_sequence(values: Array[int]) -> void:
	_cadence_sequence = values.duplicate()
	_cadence_index = 0


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _set_state(state: int) -> void:
	if state == _state:
		return
	_state = state
	connection_state_changed.emit(state)


## Применяет переходы, время которых ≤ текущих часов (или строго < при `strict`).
func _advance_state(strict: bool) -> void:
	if _state == ConnectionState.CONNECTING and _connect_at_sec >= 0.0 \
			and _is_due(_connect_at_sec, strict):
		_finish_connect()
	if _state == ConnectionState.RECONNECTING and _dropout_until_sec >= 0.0 \
			and _is_due(_dropout_until_sec, strict):
		_dropout_until_sec = -1.0
		_set_state(ConnectionState.CONNECTED)


func _is_due(at_sec: float, strict: bool) -> bool:
	if strict:
		return _time_sec > at_sec + TIME_EPSILON
	return _time_sec + TIME_EPSILON >= at_sec


func _finish_connect() -> void:
	_connect_at_sec = -1.0
	if _fail_next_connect:
		_fail_next_connect = false
		_set_state(ConnectionState.DISCONNECTED)
		error.emit(ErrorCode.CONNECTION_FAILED, "FakeTrainer: сценарий «ошибка подключения» для %s" % device_id)
		return
	_power_w = float(_rider_goal_power())
	_set_state(ConnectionState.CONNECTED)


## Записывает вызов в журнал и решает, принимает ли команду станок.
## Возвращает true, если команду нужно применить к модели; иначе испускает `error`.
func _accept_command(type: String, value: Variant) -> bool:
	var accepted: bool = true
	var code: int = ErrorCode.NONE
	var message: String = ""
	if _state != ConnectionState.CONNECTED and _state != ConnectionState.RECONNECTING:
		accepted = false
		code = ErrorCode.NOT_CONNECTED
		message = "FakeTrainer: команда %s в состоянии %s — станок не подключён" % [type, state_name(_state)]
	elif _fail_next_command:
		_fail_next_command = false
		accepted = false
		code = _fail_next_code
		_fail_next_code = ErrorCode.CONTROL_POINT_REJECTED
		message = "FakeTrainer: станок отверг команду %s (%s)" % [type, "write failed" if code == ErrorCode.WRITE_FAILED else "control point"]
	commands.append({"type": type, "value": value, "at_sec": _time_sec})
	if not accepted:
		error.emit(code, message)
	return accepted


## Мощность, к которой стремится всадник в текущем режиме.
func _rider_goal_power() -> int:
	if _current_cadence_base() <= 0:
		return 0
	if erg_enabled and target_power_w > 0:
		return target_power_w
	return rider_power_w


func _current_cadence_base() -> int:
	if not _cadence_sequence.is_empty():
		var idx: int = mini(_cadence_index, _cadence_sequence.size() - 1)
		return _cadence_sequence[idx]
	return rider_cadence_rpm


func _emit_sample(sample_sec: int) -> void:
	# Модель продвигается всегда — даже если пакет потерян, физика не стоит.
	var goal: float = float(_rider_goal_power())
	var alpha: float = 1.0 - exp(-1.0 / maxf(power_tau_sec, 1e-3))
	_power_w += (goal - _power_w) * alpha
	if absf(_power_w - goal) < POWER_SNAP_W:
		_power_w = goal
	var noise: float = _rng.randf_range(-power_noise_w, power_noise_w) if goal > 0.0 else 0.0
	var power: int = maxi(int(round(_power_w + noise)), 0)

	var cadence_base: int = _current_cadence_base()
	var cadence: int = 0
	if cadence_base > 0:
		if _cadence_sequence.is_empty():
			cadence = maxi(int(round(cadence_base + _rng.randf_range(-cadence_noise_rpm, cadence_noise_rpm))), 0)
		else:
			cadence = cadence_base
	if not _cadence_sequence.is_empty():
		_cadence_index += 1

	var speed: float = SPEED_COEFF * pow(float(power), 1.0 / 3.0) if power > 0 else 0.0

	var lost: bool = _packet_loss_ratio > 0.0 and _rng.randf() < _packet_loss_ratio
	var silent: bool = _silence_until_sec >= 0.0 and float(sample_sec) <= _silence_until_sec + TIME_EPSILON
	if _silence_until_sec >= 0.0 and not silent:
		_silence_until_sec = -1.0

	if not (lost or silent):
		samples_emitted += 1
		var out := TrainerSample.full(float(sample_sec), power, cadence, speed)
		if not emit_speed:
			out.has_speed = false
			out.speed_kmh = 0.0
		telemetry.emit(out)

	if not _heart_rate_sequence.is_empty():
		var idx: int = mini(_heart_rate_index, _heart_rate_sequence.size() - 1)
		_heart_rate_index += 1
		if not (lost or silent):
			heart_rate.emit(_heart_rate_sequence[idx])
