class_name FakePowerMeter
extends BlePowerMeter
## Симулятор измерителя мощности CPS без управления (REQ-WRK-09 п.12 — дополнение к REQ-DEV-09)
## для тестов и разработки без железа.
##
## Это настоящий `BlePowerMeter` (подключение, подписка на `2A63`, разбор, каденс по оборотам
## шатуна, переподключение DEV-08) поверх `StubBleBridge`, а симулятор играет роль периферии:
## на каждой целой секунде своих часов (`tick`, инъекция времени — DEV-09 п.4) шлёт в мост
## нотификацию Cycling Power Measurement с мощностью и данными оборотов шатуна
## (`CpsCodec.encode_cycling_power_measurement`). Мост — свой (по умолчанию) или общий,
## переданный в конструктор, — тогда его журнал `calls` покрывает и датчик (WRK-09 п.4).
##
## Сценарии (DEV-09 п.3):
## - постоянная мощность и каденс — `power_w`, `cadence_rpm` (по умолчанию 200 Вт, 90 об/мин);
## - рывки — `set_power_sequence` (по значению в секунду, последнее удерживается);
## - нулевой каденс — `set_zero_cadence()` (педали стоят: обороты не растут, мощность 0);
## - пропуск пакетов — `inject_silence(сек)`: связь есть, нотификаций нет;
## - обрыв и восстановление — `inject_dropout(сек)`: `disconnected` в мост, на время обрыва
##   периферия «выключена» (попытки `connect_peripheral` датчика без ответа), по истечении —
##   `connected` на ждущую попытку (как отложенный запрос подключения CoreBluetooth); в секунду
##   восстановления пакета ещё нет, пакеты — со следующей секунды.
## На время обрыва у моста выключается `auto_connect` (у общего моста — для всех устройств).
##
## Обороты шатуна: фаза копится по каденсу (об/мин / 60 за секунду); время последнего полного
## оборота — линейной интерполяцией внутри секунды, в единицах 1/1024 с (CPS). Каденс,
## пересчитанный `CscCadenceCalculator`, совпадает с заданным (со второго пакета).

## Допуск сравнения времени с целой секундой.
const TIME_EPSILON: float = 1e-6

## Мощность, Вт, когда последовательность не задана.
var power_w: int = 200
## Каденс, об/мин, когда последовательность не задана; 0 — педали стоят.
var cadence_rpm: int = 90
## Отправлено нотификаций 2A63.
var packets_sent: int = 0
## Мост симулятора (тот же объект, что `bridge`).
var stub: StubBleBridge

var _owns_bridge: bool = false
var _power_sequence: Array[int] = []
var _power_index: int = 0
var _cadence_sequence: Array[int] = []
var _cadence_index: int = 0
var _next_packet_sec: int = 1
var _silence_until_sec: float = -1.0
var _absent_until_sec: float = -1.0
var _connect_calls_at_drop: int = 0
var _crank_phase: float = 0.0
var _crank_revs: int = 0
var _crank_event_ticks: int = 0


## `shared_bridge` — общий мост теста (журнал вызовов на всё устройство сценария); null — свой.
func _init(shared_bridge: StubBleBridge = null) -> void:
	var b: StubBleBridge = shared_bridge if shared_bridge != null else StubBleBridge.new()
	super(b)
	stub = b
	_owns_bridge = shared_bridge == null


## Эмулятор: данные не настоящие (T-160, WRK-09 п.8 — `trainer_source = emulator`).
func is_emulator() -> bool:
	return true


## Подключение: периферия с CPS `1818`/`2A63` объявляется в мосте; ответы моста доставляются
## сразу — датчик в CONNECTED уже по выходе из вызова.
func connect_device(id: String) -> void:
	if stub != null:
		stub.set_device_services(id, {BleUuids.CPS_SERVICE: PackedStringArray([BleUuids.CYCLING_POWER_MEASUREMENT])})
	super.connect_device(id)
	_pump()


func dispose() -> void:
	var own: StubBleBridge = stub if _owns_bridge else null
	super.dispose()
	stub = null
	if own != null:
		own.dispose()


func tick(delta_sec: float) -> void:
	if delta_sec <= 0.0:
		return
	var end_sec: float = _time_sec + delta_sec
	if absf(end_sec - roundf(end_sec)) < TIME_EPSILON:
		end_sec = roundf(end_sec)
	while float(_next_packet_sec) <= end_sec + TIME_EPSILON:
		var step: float = float(_next_packet_sec) - _time_sec
		if step > 0.0:
			super.tick(step)
		_time_sec = float(_next_packet_sec)
		_pump()
		_second(_next_packet_sec)
		_pump()
		_next_packet_sec += 1
	if end_sec - _time_sec > 0.0:
		super.tick(end_sec - _time_sec)
	_time_sec = end_sec
	_pump()


# ---------------------------------------------------------------------------
# Сценарии
# ---------------------------------------------------------------------------

func set_power(watts: int) -> void:
	power_w = maxi(watts, 0)
	_power_sequence.clear()
	_power_index = 0


## Мощность по секундам («рывки»); последнее значение удерживается. Пустой — `power_w`.
func set_power_sequence(values: Array[int]) -> void:
	_power_sequence = values.duplicate()
	_power_index = 0


func set_cadence(rpm: int) -> void:
	cadence_rpm = maxi(rpm, 0)
	_cadence_sequence.clear()
	_cadence_index = 0


func set_cadence_sequence(values: Array[int]) -> void:
	_cadence_sequence = values.duplicate()
	_cadence_index = 0


## Педали стоят: каденс 0 (обороты не растут, пакеты идут) и мощность 0.
func set_zero_cadence() -> void:
	set_cadence(0)
	set_power(0)


## Пропуск пакетов `duration_sec` секунд при сохранённой связи.
func inject_silence(duration_sec: float) -> void:
	_silence_until_sec = _time_sec + maxf(duration_sec, 0.0)


## Обрыв на `duration_sec` секунд с восстановлением (см. шапку). Только из CONNECTED.
func inject_dropout(duration_sec: float) -> void:
	if _state != TrainerDevice.ConnectionState.CONNECTED or stub == null:
		push_warning("FakePowerMeter.inject_dropout: датчик не подключён, обрыв проигнорирован")
		return
	_absent_until_sec = _time_sec + maxf(duration_sec, 0.0)
	_connect_calls_at_drop = _connect_calls()
	stub.auto_connect = false
	stub.emit_disconnected(device_id, BleBridge.DisconnectReason.LINK_LOSS)


func is_absent() -> bool:
	return _absent_until_sec >= 0.0


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _pump() -> void:
	if stub != null:
		stub.pump()


func _connect_calls() -> int:
	var n: int = 0
	if stub == null:
		return n
	for c in stub.calls_of("connect_peripheral"):
		if str(c.get("id", "")) == device_id:
			n += 1
	return n


## Секунда `sec` периферии: всадник (мощность, обороты), восстановление после обрыва, пакет.
func _second(sec: int) -> void:
	var watts: int = _next_value(_power_sequence, power_w, true)
	var rpm: int = _next_value(_cadence_sequence, cadence_rpm, false)
	_advance_crank(sec, rpm)
	if _absent_until_sec >= 0.0:
		if float(sec) + TIME_EPSILON < _absent_until_sec:
			return
		_absent_until_sec = -1.0
		stub.auto_connect = true
		if _state == TrainerDevice.ConnectionState.RECONNECTING and _connect_calls() > _connect_calls_at_drop:
			stub.emit_connected(device_id)
			_pump()
		return  # в секунду восстановления пакета ещё нет
	if _silence_until_sec >= 0.0:
		if float(sec) <= _silence_until_sec + TIME_EPSILON:
			return
		_silence_until_sec = -1.0
	if stub == null or not stub.is_subscribed(device_id, BleUuids.CPS_SERVICE, BleUuids.CYCLING_POWER_MEASUREMENT):
		return
	packets_sent += 1
	stub.emit_notification(device_id, BleUuids.CYCLING_POWER_MEASUREMENT,
		CpsCodec.encode_cycling_power_measurement(watts, _crank_revs, _crank_event_ticks))


func _next_value(sequence: Array[int], fallback: int, is_power: bool) -> int:
	if sequence.is_empty():
		return fallback
	var idx: int = mini(_power_index if is_power else _cadence_index, sequence.size() - 1)
	if is_power:
		_power_index += 1
	else:
		_cadence_index += 1
	return maxi(sequence[idx], 0)


## Обороты за секунду (sec − 1, sec]: целые обороты и время последнего, 1/1024 с.
func _advance_crank(sec: int, rpm: int) -> void:
	if rpm <= 0:
		return
	var per_sec: float = float(rpm) / 60.0
	var start: float = _crank_phase
	_crank_phase += per_sec
	var whole: int = floori(_crank_phase + TIME_EPSILON)
	if whole > _crank_revs:
		var event_sec: float = float(sec - 1) + (float(whole) - start) / per_sec
		_crank_revs = whole
		_crank_event_ticks = roundi(event_sec * 1024.0) & 0xFFFF
