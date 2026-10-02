class_name BleTrainer
extends TrainerDevice
## Станок по FTMS поверх `BleBridge` (REQ-DEV-02, REQ-DEV-08, REQ-WRK-02/03/04, REQ-NFR-01).
##
## Последовательность подключения (REQ-DEV-02 крит. 1):
## `connect_device(id)` → `connect_peripheral` → `connected` → `discover_services` →
## подписки 2AD2 (Indoor Bike Data), 2ADA (Status), 2AD9 (Control Point) →
## запись Request Control `00` → чтение 2AD6 (Supported Resistance Level Range,
## если характеристика заявлена или список сервисов неизвестен) →
## **CONNECTED только после ответа `80 00 01`**. Отказ в Request Control
## → `error(CONTROL_POINT_REJECTED)` и DISCONNECTED без переподключения.
##
## Команды: Set Target Power `05 <s16 LE>`, Set Target Resistance Level `04 <uint8>`
## (процент → уровень по 2AD6 через `FtmsCodec.percent_to_resistance_level`),
## всегда `with_response = true`. Вне CONNECTED значения запоминаются, на станок
## не пишутся (сессия повторяет цель после CONNECTED, REQ-DEV-08 крит. 3).
## Ответ Control Point с `result != 0x01` → `error(CONTROL_POINT_REJECTED)`.
## `write_done(ok = false)` → один немедленный повтор той же команды
## (REQ-NFR-01 крит. 2, решение 24); второй отказ → `error(WRITE_FAILED)`.
##
## Обрыв не по запросу → RECONNECTING, `connect_peripheral` сразу и далее каждые
## 5 с через `tick(delta)` без лимита попыток (REQ-DEV-08 крит. 1, решение 12);
## после `connected` — заново discover/subscribe/Request Control → CONNECTED.
## `disconnect_device()` → DISCONNECTED, переподключение не выполняется.

const RECONNECT_INTERVAL_SEC: float = 5.0
const FTMS: String = BleUuids.FTMS_SERVICE

var bridge: BleBridge
var device_id: String = ""
## Текущие параметры (принятые или ожидающие подключения).
var erg_enabled: bool = true
var target_power_w: int = 0
var resistance_percent: int = 0
## Диапазон уровней из 2AD6 (`FtmsCodec.decode_resistance_range`); пустой — не прочитан.
var resistance_range: Dictionary = {}
## Сервисы устройства из `services_discovered`.
var services: Dictionary = {}
## Станок подтвердил Request Control.
var control_granted: bool = false

var _state: int = ConnectionState.DISCONNECTED
var _time_sec: float = 0.0
var _reconnect := BleReconnectPolicy.new(RECONNECT_INTERVAL_SEC)
var _disconnect_requested: bool = false
## char_uuid → {"bytes": PackedByteArray, "retried": bool} — записи, ждущие write_done.
var _pending_writes: Dictionary = {}


func _init(ble_bridge: BleBridge) -> void:
	bridge = ble_bridge
	bridge.connected.connect(_on_connected)
	bridge.disconnected.connect(_on_disconnected)
	bridge.services_discovered.connect(_on_services_discovered)
	bridge.notification.connect(_on_notification)
	bridge.characteristic_read.connect(_on_characteristic_read)
	bridge.write_done.connect(_on_write_done)
	bridge.error.connect(_on_bridge_error)


func get_time_sec() -> float:
	return _time_sec


# ---------------------------------------------------------------------------
# TrainerDevice
# ---------------------------------------------------------------------------

func connect_device(id: String) -> void:
	if _state == ConnectionState.CONNECTED or _state == ConnectionState.CONNECTING:
		return
	if _state == ConnectionState.RECONNECTING and id == device_id:
		return
	device_id = id
	_disconnect_requested = false
	control_granted = false
	_reconnect.stop()
	_set_state(ConnectionState.CONNECTING)
	bridge.connect_peripheral(id)


func disconnect_device() -> void:
	_disconnect_requested = true
	_reconnect.stop()
	_pending_writes.clear()
	control_granted = false
	if device_id != "" and _state != ConnectionState.DISCONNECTED:
		bridge.disconnect_peripheral(device_id)
	_set_state(ConnectionState.DISCONNECTED)


func set_target_power(watts: int) -> void:
	var value: int = clampi(watts, MIN_TARGET_POWER_W, MAX_TARGET_POWER_W)
	if value != watts:
		push_warning("BleTrainer.set_target_power: %d вне диапазона, обрезано до %d" % [watts, value])
	target_power_w = value
	if _state != ConnectionState.CONNECTED:
		return
	if erg_enabled:
		_write_control_point(FtmsCodec.encode_set_target_power(value))


func set_erg_enabled(enabled: bool) -> void:
	erg_enabled = enabled
	if _state != ConnectionState.CONNECTED:
		return
	if enabled:
		if target_power_w > 0:
			_write_control_point(FtmsCodec.encode_set_target_power(target_power_w))
	else:
		_write_resistance()


func set_resistance_level(percent: int) -> void:
	var value: int = clampi(percent, MIN_RESISTANCE_PERCENT, MAX_RESISTANCE_PERCENT)
	if value != percent:
		push_warning("BleTrainer.set_resistance_level: %d вне диапазона, обрезано до %d" % [percent, value])
	resistance_percent = value
	if _state == ConnectionState.CONNECTED and not erg_enabled:
		_write_resistance()


func get_connection_state() -> int:
	return _state


func tick(delta_sec: float) -> void:
	if delta_sec <= 0.0:
		return
	_time_sec += delta_sec
	if _state == ConnectionState.RECONNECTING and _reconnect.due(_time_sec):
		bridge.connect_peripheral(device_id)


## Число попыток переподключения в текущей серии.
func reconnect_attempts() -> int:
	return _reconnect.attempts


# ---------------------------------------------------------------------------
# События моста
# ---------------------------------------------------------------------------

func _on_connected(id: String) -> void:
	if id != device_id or _disconnect_requested:
		return
	bridge.discover_services(id)


func _on_services_discovered(id: String, svc: Dictionary) -> void:
	if id != device_id or _disconnect_requested:
		return
	services = svc
	bridge.subscribe(id, FTMS, BleUuids.INDOOR_BIKE_DATA)
	bridge.subscribe(id, FTMS, BleUuids.FTMS_STATUS)
	bridge.subscribe(id, FTMS, BleUuids.FTMS_CONTROL_POINT)
	_write_control_point(FtmsCodec.encode_request_control())
	if _has_characteristic(FTMS, BleUuids.SUPPORTED_RESISTANCE_RANGE):
		bridge.read_characteristic(id, FTMS, BleUuids.SUPPORTED_RESISTANCE_RANGE)


func _on_notification(id: String, char_uuid: String, bytes: PackedByteArray) -> void:
	if id != device_id:
		return
	match BleUuids.normalize(char_uuid):
		BleUuids.FTMS_CONTROL_POINT:
			_on_control_point_response(bytes)
		BleUuids.INDOOR_BIKE_DATA:
			_on_indoor_bike_data(bytes)
		BleUuids.FTMS_STATUS:
			_on_machine_status(bytes)


func _on_control_point_response(bytes: PackedByteArray) -> void:
	var r := FtmsCodec.decode_control_point_response(bytes)
	if not r["ok"]:
		return
	var opcode: int = r["request_opcode"]
	if opcode == FtmsCodec.OP_REQUEST_CONTROL:
		if r["success"]:
			control_granted = true
			if _state == ConnectionState.CONNECTING or _state == ConnectionState.RECONNECTING:
				_reconnect.stop()
				_set_state(ConnectionState.CONNECTED)
		else:
			error.emit(ErrorCode.CONTROL_POINT_REJECTED,
				"Станок не передал управление (Request Control: %s)" % FtmsCodec.result_name(r["result"]))
			if _state != ConnectionState.CONNECTED:
				disconnect_device()
		return
	if not r["success"]:
		error.emit(ErrorCode.CONTROL_POINT_REJECTED, "Станок отверг команду %s: %s" % [
			FtmsCodec.opcode_name(opcode), FtmsCodec.result_name(r["result"])])


func _on_indoor_bike_data(bytes: PackedByteArray) -> void:
	var d := FtmsCodec.decode_indoor_bike_data(bytes)
	if not d["ok"]:
		return
	var s := TrainerSample.new()
	s.timestamp_sec = _time_sec
	s.has_power = d["has_power"]
	s.power_w = d["power_w"]
	s.has_cadence = d["has_cadence"]
	s.cadence_rpm = roundi(d["cadence_rpm"])
	s.has_speed = d["has_speed"]
	s.speed_kmh = d["speed_kmh"]
	telemetry.emit(s)
	if d["has_heart_rate"]:
		heart_rate.emit(d["heart_rate_bpm"])


func _on_machine_status(bytes: PackedByteArray) -> void:
	var st := FtmsCodec.decode_machine_status(bytes)
	if st["ok"] and st["opcode"] == FtmsCodec.STATUS_CONTROL_PERMISSION_LOST:
		control_granted = false
		push_warning("BleTrainer: станок отозвал управление, повторяем Request Control")
		if _state == ConnectionState.CONNECTED:
			_write_control_point(FtmsCodec.encode_request_control())


func _on_characteristic_read(id: String, char_uuid: String, bytes: PackedByteArray) -> void:
	if id != device_id:
		return
	if BleUuids.normalize(char_uuid) == BleUuids.SUPPORTED_RESISTANCE_RANGE:
		var r := FtmsCodec.decode_resistance_range(bytes)
		if r["ok"]:
			resistance_range = r


func _on_write_done(id: String, char_uuid: String, ok: bool) -> void:
	if id != device_id:
		return
	var ch := BleUuids.normalize(char_uuid)
	if ok:
		_pending_writes.erase(ch)
		return
	if _pending_writes.has(ch) and not _pending_writes[ch]["retried"]:
		_pending_writes[ch]["retried"] = true
		bridge.write(device_id, FTMS, ch, _pending_writes[ch]["bytes"], true)
		return
	_pending_writes.erase(ch)
	error.emit(ErrorCode.WRITE_FAILED, "Запись %s не удалась дважды" % ch)


func _on_disconnected(id: String, reason: int) -> void:
	if id != device_id:
		return
	control_granted = false
	_pending_writes.clear()
	if _disconnect_requested or reason == BleBridge.DisconnectReason.REQUESTED:
		_set_state(ConnectionState.DISCONNECTED)
		return
	if _state == ConnectionState.DISCONNECTED:
		return
	_set_state(ConnectionState.RECONNECTING)
	_reconnect.start(_time_sec)
	if _reconnect.due(_time_sec):
		bridge.connect_peripheral(device_id)


func _on_bridge_error(id: String, code: int, message: String) -> void:
	if id != "" and id != device_id:
		return
	match code:
		BleBridge.ErrorCode.CONNECTION_FAILED, BleBridge.ErrorCode.DEVICE_NOT_FOUND, \
		BleBridge.ErrorCode.TIMEOUT, BleBridge.ErrorCode.ADAPTER_UNAVAILABLE:
			if _state == ConnectionState.CONNECTING:
				_set_state(ConnectionState.DISCONNECTED)
				error.emit(ErrorCode.CONNECTION_FAILED, message)
			# В RECONNECTING — следующая попытка по таймеру.
		BleBridge.ErrorCode.READ_FAILED, BleBridge.ErrorCode.CHARACTERISTIC_NOT_FOUND:
			push_warning("BleTrainer: необязательное чтение не удалось: %s" % message)
		BleBridge.ErrorCode.WRITE_FAILED:
			error.emit(ErrorCode.WRITE_FAILED, message)
		BleBridge.ErrorCode.SUBSCRIBE_FAILED, BleBridge.ErrorCode.SERVICE_NOT_FOUND:
			error.emit(ErrorCode.CONNECTION_FAILED, message)
		_:
			push_warning("BleTrainer: ошибка моста %d: %s" % [code, message])


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _set_state(state: int) -> void:
	if state == _state:
		return
	_state = state
	connection_state_changed.emit(state)


func _write_control_point(bytes: PackedByteArray) -> void:
	_pending_writes[BleUuids.FTMS_CONTROL_POINT] = {"bytes": bytes, "retried": false}
	bridge.write(device_id, FTMS, BleUuids.FTMS_CONTROL_POINT, bytes, true)


func _write_resistance() -> void:
	var level: float = FtmsCodec.percent_to_resistance_level(resistance_percent, resistance_range)
	_write_control_point(FtmsCodec.encode_set_resistance_level(level))


## Есть ли характеристика в списке сервисов; при неизвестном списке — пробуем.
func _has_characteristic(service_uuid: String, char_uuid: String) -> bool:
	if services.is_empty():
		return true
	var svc := BleUuids.normalize(service_uuid)
	if not services.has(svc):
		return false
	var ch := BleUuids.normalize(char_uuid)
	for c in services[svc]:
		if BleUuids.normalize(c) == ch:
			return true
	return false
