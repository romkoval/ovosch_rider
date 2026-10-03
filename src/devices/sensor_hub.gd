class_name SensorHub
extends TrainerDevice
## Объединяет станок и внешние датчики в один `TrainerDevice` для сессии
## (REQ-DEV-03 крит. 3, REQ-DEV-04 крит. 4, REQ-DEV-05 крит. 2, 3, REQ-WRK-08 крит. 4,
## REQ-DEV-08 крит. 2; решения 12 и 13).
##
## Команды и состояние подключения делегируются станку; телеметрия агрегируется:
## - пульс: датчик HRS > пульс станка;
## - каденс: датчик CSC > crank data измерителя мощности > станок;
## - мощность: `power_source` ("trainer" по умолчанию | "power_meter"), затем другой;
## - скорость: только станок.
## Источник, молчавший `SOURCE_TIMEOUT_SEC` (5 с), считается «нет данных» и уступает
## следующему по приоритету; если никого — `has_* == false`. Для каденса порог
## короче — `CADENCE_TIMEOUT_SEC` (3 с, решение Н-4): датчик каденса, переставший
## слать пакеты, уступает сразу, без ложного нуля; каденс станка подчиняется тому же порогу.
##
## Хаб выдаёт ровно один объединённый `TrainerSample` на каждую целую секунду
## собственных часов (`tick`), независимо от того, жив ли станок — так при обрыве
## станка пульс/каденс датчиков продолжают записываться (REQ-DEV-08 крит. 2).
## `heart_rate(bpm)` испускается в ту же секунду, если пульс есть хоть у кого-то.
## Датчики подключает владелец (`connect_device` у каждого); хаб только тикает их.

const SOURCE_TIMEOUT_SEC: float = 5.0
## Порог свежести источников каденса (REQ-DEV-04 крит. 3, решение Н-4).
const CADENCE_TIMEOUT_SEC: float = 3.0
const TIME_EPSILON: float = 1e-6

const SOURCE_TRAINER: String = "trainer"
const SOURCE_POWER_METER: String = "power_meter"
const SOURCE_HEART_RATE_SENSOR: String = "heart_rate_sensor"
const SOURCE_CADENCE_SENSOR: String = "cadence_sensor"
const SOURCE_NONE: String = "none"

var trainer: TrainerDevice
var heart_rate_sensor: SensorDevice = null
var cadence_sensor: SensorDevice = null
var power_meter: SensorDevice = null
## Выбор источника мощности (REQ-DEV-05 крит. 2).
var power_source: String = SOURCE_TRAINER

var _time_sec: float = 0.0
var _next_sample_sec: int = 1

var _trainer_sample: TrainerSample = null
var _trainer_sample_at: float = -INF
var _trainer_hr: int = 0
var _trainer_hr_at: float = -INF
var _hrs_bpm: int = 0
var _hrs_at: float = -INF
var _csc_rpm: int = 0
var _csc_at: float = -INF
var _pm_power: int = 0
var _pm_power_at: float = -INF
var _pm_rpm: int = 0
var _pm_rpm_at: float = -INF

var _power_source_in_use: String = SOURCE_NONE
var _cadence_source_in_use: String = SOURCE_NONE
var _heart_rate_source_in_use: String = SOURCE_NONE


func _init(trainer_device: TrainerDevice) -> void:
	trainer = trainer_device
	trainer.telemetry.connect(_on_trainer_telemetry)
	trainer.heart_rate.connect(_on_trainer_heart_rate)
	trainer.connection_state_changed.connect(_forward_state)
	trainer.error.connect(_forward_error)


## Отключить обработчики сигналов станка и датчиков и забыть их (разрыв циклов
## хаб ↔ станок/датчики). Сами устройства не освобождаются — это дело владельца.
func dispose() -> void:
	if trainer != null:
		for pair in [[trainer.telemetry, _on_trainer_telemetry], [trainer.heart_rate, _on_trainer_heart_rate],
				[trainer.connection_state_changed, _forward_state], [trainer.error, _forward_error]]:
			var sig: Signal = pair[0]
			var cb: Callable = pair[1]
			if sig.is_connected(cb):
				sig.disconnect(cb)
		trainer = null
	set_heart_rate_sensor(null)
	set_cadence_sensor(null)
	set_power_meter(null)
	_trainer_sample = null


func _forward_state(state: int) -> void:
	connection_state_changed.emit(state)


func _forward_error(code: int, message: String) -> void:
	error.emit(code, message)


# ---------------------------------------------------------------------------
# Датчики
# ---------------------------------------------------------------------------

func set_heart_rate_sensor(sensor: SensorDevice) -> void:
	_swap_sensor(heart_rate_sensor, sensor, {"heart_rate": _on_hrs_heart_rate})
	heart_rate_sensor = sensor


func set_cadence_sensor(sensor: SensorDevice) -> void:
	_swap_sensor(cadence_sensor, sensor, {"cadence": _on_csc_cadence})
	cadence_sensor = sensor


func set_power_meter(sensor: SensorDevice) -> void:
	_swap_sensor(power_meter, sensor, {"power": _on_pm_power, "cadence": _on_pm_cadence})
	power_meter = sensor


## false — неизвестный источник (предупреждение, выбор не меняется).
func set_power_source(source: String) -> bool:
	if source != SOURCE_TRAINER and source != SOURCE_POWER_METER:
		push_warning("SensorHub.set_power_source: неизвестный источник '%s'" % source)
		return false
	power_source = source
	return true


## Источник, давший значение в последнем объединённом сэмпле.
func power_source_in_use() -> String:
	return _power_source_in_use


func cadence_source_in_use() -> String:
	return _cadence_source_in_use


func heart_rate_source_in_use() -> String:
	return _heart_rate_source_in_use


# ---------------------------------------------------------------------------
# TrainerDevice — делегирование станку
# ---------------------------------------------------------------------------

func connect_device(id: String) -> void:
	if trainer != null:
		trainer.connect_device(id)


func disconnect_device() -> void:
	if trainer != null:
		trainer.disconnect_device()


func set_target_power(watts: int) -> void:
	if trainer != null:
		trainer.set_target_power(watts)


func set_erg_enabled(enabled: bool) -> void:
	if trainer != null:
		trainer.set_erg_enabled(enabled)


func is_erg_enabled() -> bool:
	return trainer.is_erg_enabled() if trainer != null else true


func set_resistance_level(percent: int) -> void:
	if trainer != null:
		trainer.set_resistance_level(percent)


func get_connection_state() -> int:
	return trainer.get_connection_state() if trainer != null else ConnectionState.DISCONNECTED


func tick(delta_sec: float) -> void:
	if delta_sec <= 0.0:
		return
	var end_sec: float = _time_sec + delta_sec
	# Сначала продвигаем часы: приём от станка/датчиков внутри их tick штампуется end_sec.
	_time_sec = end_sec
	if trainer != null:
		trainer.tick(delta_sec)
	for s in [heart_rate_sensor, cadence_sensor, power_meter]:
		if s != null:
			(s as SensorDevice).tick(delta_sec)
	while float(_next_sample_sec) <= end_sec + TIME_EPSILON:
		_emit_merged(float(_next_sample_sec))
		_next_sample_sec += 1


# ---------------------------------------------------------------------------
# Приём от источников
# ---------------------------------------------------------------------------

func _on_trainer_telemetry(sample: TrainerSample) -> void:
	_trainer_sample = sample
	_trainer_sample_at = _time_sec


func _on_trainer_heart_rate(bpm: int) -> void:
	_trainer_hr = bpm
	_trainer_hr_at = _time_sec


func _on_hrs_heart_rate(bpm: int) -> void:
	_hrs_bpm = bpm
	_hrs_at = _time_sec


func _on_csc_cadence(rpm: int) -> void:
	_csc_rpm = rpm
	_csc_at = _time_sec


func _on_pm_power(watts: int) -> void:
	_pm_power = watts
	_pm_power_at = _time_sec


func _on_pm_cadence(rpm: int) -> void:
	_pm_rpm = rpm
	_pm_rpm_at = _time_sec


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _fresh(at_sec: float) -> bool:
	return _time_sec - at_sec < SOURCE_TIMEOUT_SEC


func _fresh_cadence(at_sec: float) -> bool:
	return _time_sec - at_sec < CADENCE_TIMEOUT_SEC


func _trainer_fresh() -> bool:
	return _trainer_sample != null and _fresh(_trainer_sample_at)


func _emit_merged(ts_sec: float) -> void:
	var s := TrainerSample.new()
	s.timestamp_sec = ts_sec
	# Мощность: выбранный источник, затем другой.
	_power_source_in_use = SOURCE_NONE
	var order: Array[String] = [power_source,
		SOURCE_POWER_METER if power_source == SOURCE_TRAINER else SOURCE_TRAINER]
	for src in order:
		if src == SOURCE_TRAINER and _trainer_fresh() and _trainer_sample.has_power:
			s.has_power = true
			s.power_w = _trainer_sample.power_w
			_power_source_in_use = SOURCE_TRAINER
			break
		if src == SOURCE_POWER_METER and power_meter != null and _fresh(_pm_power_at):
			s.has_power = true
			s.power_w = _pm_power
			_power_source_in_use = SOURCE_POWER_METER
			break
	# Каденс: CSC > CPS > станок; порог свежести 3 с.
	_cadence_source_in_use = SOURCE_NONE
	if cadence_sensor != null and _fresh_cadence(_csc_at):
		s.has_cadence = true
		s.cadence_rpm = _csc_rpm
		_cadence_source_in_use = SOURCE_CADENCE_SENSOR
	elif power_meter != null and _fresh_cadence(_pm_rpm_at):
		s.has_cadence = true
		s.cadence_rpm = _pm_rpm
		_cadence_source_in_use = SOURCE_POWER_METER
	elif _trainer_sample != null and _fresh_cadence(_trainer_sample_at) and _trainer_sample.has_cadence:
		s.has_cadence = true
		s.cadence_rpm = _trainer_sample.cadence_rpm
		_cadence_source_in_use = SOURCE_TRAINER
	# Скорость: только станок.
	if _trainer_fresh() and _trainer_sample.has_speed:
		s.has_speed = true
		s.speed_kmh = _trainer_sample.speed_kmh
	telemetry.emit(s)
	# Пульс: HRS > станок.
	_heart_rate_source_in_use = SOURCE_NONE
	if heart_rate_sensor != null and _fresh(_hrs_at):
		_heart_rate_source_in_use = SOURCE_HEART_RATE_SENSOR
		heart_rate.emit(_hrs_bpm)
	elif _fresh(_trainer_hr_at):
		_heart_rate_source_in_use = SOURCE_TRAINER
		heart_rate.emit(_trainer_hr)


## Переподключает обработчики `handlers` ({signal_name: Callable}) с `old` на `new`.
func _swap_sensor(old: SensorDevice, new: SensorDevice, handlers: Dictionary) -> void:
	if old != null:
		for sig in handlers:
			if old.has_signal(sig) and old.is_connected(sig, handlers[sig]):
				old.disconnect(sig, handlers[sig])
	if new == null:
		return
	for sig in handlers:
		if not new.has_signal(sig):
			push_error("SensorHub: у датчика %s нет сигнала %s" % [new.kind(), sig])
			continue
		new.connect(sig, handlers[sig])
