class_name UncontrolledTrainer
extends TrainerDevice
## Источник мощности без управления — `TrainerDevice` режима сессии `power_meter`
## (REQ-WRK-09 п.1, 4, 6, 12; REQ-DEV-05 п.5; DEV-10 п.4).
##
## Обёртка над `SensorHub`: телеметрия и пульс — объединённые хабом (мощность: измеритель
## мощности CPS, при его отсутствии — станок без управления; каденс: CSC > CPS > станок;
## пульс: HRS > станок). Хабу на время жизни обёртки ставится источник мощности
## `power_source` (по умолчанию — измеритель, WRK-09 п.1: при двух источниках — измеритель),
## при его отсутствии хаб берёт другой и возвращается к нему, когда тот ожил.
##
## Команды управления (`set_target_power`, `set_erg_enabled`, `set_resistance_level`,
## `set_simulation`) — пустые: ни одна не доходит ни до станка, ни до моста (WRK-09 п.4).
## Станку хаба на время жизни обёртки запрещено брать управление (`set_control_allowed(false)`):
## управляемый станок, подключившийся посреди сессии, подключается «только данные» и не
## получает ни одной записи (WRK-09 п.1). `dispose()` возвращает хабу прежний источник
## мощности и разрешение на управление.
##
## Состояние подключения — состояние источника мощности (измерителя или станка): обрыв и
## восстановление видны сессии как у станка (события журнала, DEV-08). `trainer_mode()` —
## `MODE_POWER_METER`; `is_emulator()` — по источнику мощности (симулятор CPS — эмулятор, T-160).
## Подписки — связанными методами; владелец вызывает `dispose()`.

var hub: SensorHub
## `SensorHub.SOURCE_POWER_METER` или `SensorHub.SOURCE_TRAINER` (станок без управления).
var power_source: String = SensorHub.SOURCE_POWER_METER
## Обёртка владеет хабом и его устройствами (эмулятор из `TrainerFactory`): `dispose()` их освобождает.
var owns_hub: bool = false

var _previous_power_source: String = SensorHub.SOURCE_TRAINER
## Устройство-источник, на чей сигнал состояния подписана обёртка (`SensorDevice` или `TrainerDevice`).
var _source: Object = null


func _init(sensor_hub: SensorHub, source: String = SensorHub.SOURCE_POWER_METER) -> void:
	hub = sensor_hub
	power_source = SensorHub.SOURCE_TRAINER if source == SensorHub.SOURCE_TRAINER else SensorHub.SOURCE_POWER_METER
	_previous_power_source = hub.power_source
	hub.set_power_source(power_source)
	hub.set_control_allowed(false)
	hub.telemetry.connect(_on_hub_telemetry)
	hub.heart_rate.connect(_on_hub_heart_rate)
	_source = hub.power_meter if power_source == SensorHub.SOURCE_POWER_METER else hub.trainer
	if _source != null:
		_source.connect("connection_state_changed", _on_source_state)


## Отключить обработчики, вернуть хабу источник мощности и разрешение на управление.
## При `owns_hub` — освободить хаб и его датчики. Повторный вызов ничего не делает.
func dispose() -> void:
	if hub == null:
		return
	if hub.telemetry.is_connected(_on_hub_telemetry):
		hub.telemetry.disconnect(_on_hub_telemetry)
	if hub.heart_rate.is_connected(_on_hub_heart_rate):
		hub.heart_rate.disconnect(_on_hub_heart_rate)
	if _source != null and _source.is_connected("connection_state_changed", _on_source_state):
		_source.disconnect("connection_state_changed", _on_source_state)
	_source = null
	hub.set_power_source(_previous_power_source)
	hub.set_control_allowed(true)
	if owns_hub:
		var devices: Array = [hub.trainer, hub.power_meter, hub.cadence_sensor, hub.heart_rate_sensor]
		hub.dispose()
		for d: Variant in devices:
			if d != null and (d as Object).has_method("dispose"):
				(d as Object).call("dispose")
	hub = null


# ---------------------------------------------------------------------------
# TrainerDevice
# ---------------------------------------------------------------------------

## Подключение источника мощности (подключением датчиков обычно управляет `ConnectionManager`).
func connect_device(id: String) -> void:
	if _source != null:
		_source.call("connect_device", id)


func disconnect_device() -> void:
	if _source != null:
		_source.call("disconnect_device")


## Команды управления не уходят никуда (WRK-09 п.4).
func set_target_power(_watts: int) -> void:
	pass


func set_erg_enabled(_enabled: bool) -> void:
	pass


func is_erg_enabled() -> bool:
	return false


func set_resistance_level(_percent: int) -> void:
	pass


func set_simulation(_grade_pct: float, _wind_mps: float = DEFAULT_SIM_WIND_MPS,
		_crr: float = DEFAULT_SIM_CRR, _cw: float = DEFAULT_SIM_CW) -> void:
	pass


func simulation_support() -> int:
	return SimulationSupport.UNSUPPORTED


func inclination_range() -> Vector2:
	return Vector2(DEFAULT_INCLINATION_MIN_PCT, DEFAULT_INCLINATION_MAX_PCT)


func trainer_mode() -> String:
	return MODE_POWER_METER


func has_control() -> bool:
	return false


## Разрешение на управление у обёртки не меняется: пока она жива, станок хаба без управления.
func set_control_allowed(_allowed: bool) -> void:
	pass


func is_emulator() -> bool:
	return bool(_source.call("is_emulator")) if _source != null else false


func get_connection_state() -> int:
	return int(_source.call("get_connection_state")) if _source != null else ConnectionState.DISCONNECTED


func tick(delta_sec: float) -> void:
	if hub != null:
		hub.tick(delta_sec)


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _on_hub_telemetry(sample: TrainerSample) -> void:
	telemetry.emit(sample)


func _on_hub_heart_rate(bpm: int) -> void:
	heart_rate.emit(bpm)


func _on_source_state(state: int) -> void:
	connection_state_changed.emit(state)
