class_name BleSensorBase
extends SensorDevice
## Общий BLE-жизненный цикл датчика поверх `BleBridge` (REQ-DEV-03/04/05, REQ-DEV-07, REQ-DEV-08).
##
## `connect_device(id)` → `connect_peripheral` → `connected` → `discover_services` →
## подписка на характеристику измерения → при наличии Battery Service 180F (или
## неизвестном списке сервисов) чтение 2A19 и подписка на него → CONNECTED.
## Обрыв не по запросу → RECONNECTING с попытками сразу и каждые 5 с через `tick`
## (`BleReconnectPolicy`). Наследники задают `_service_uuid()`, `_measurement_uuid()`,
## `_on_measurement(bytes)` и при необходимости `_on_time(now_sec)`.

const RECONNECT_INTERVAL_SEC: float = 5.0

var bridge: BleBridge
var device_id: String = ""
var services: Dictionary = {}
var battery_percent: int = -1

var _state: int = TrainerDevice.ConnectionState.DISCONNECTED
var _time_sec: float = 0.0
var _reconnect := BleReconnectPolicy.new(RECONNECT_INTERVAL_SEC)
var _disconnect_requested: bool = false


func _init(ble_bridge: BleBridge) -> void:
	bridge = ble_bridge
	bridge.connected.connect(_on_connected)
	bridge.disconnected.connect(_on_disconnected)
	bridge.services_discovered.connect(_on_services_discovered)
	bridge.notification.connect(_on_notification)
	bridge.characteristic_read.connect(_on_characteristic_read)
	bridge.error.connect(_on_bridge_error)


func get_time_sec() -> float:
	return _time_sec


# --- переопределяются наследниками ---

func _service_uuid() -> String:
	return ""


func _measurement_uuid() -> String:
	return ""


func _on_measurement(_bytes: PackedByteArray) -> void:
	pass


## Вызывается из `tick` после продвижения времени.
func _on_time(_now_sec: float) -> void:
	pass


# ---------------------------------------------------------------------------
# SensorDevice
# ---------------------------------------------------------------------------

func connect_device(id: String) -> void:
	if _state == TrainerDevice.ConnectionState.CONNECTED or _state == TrainerDevice.ConnectionState.CONNECTING:
		return
	if _state == TrainerDevice.ConnectionState.RECONNECTING and id == device_id:
		return
	device_id = id
	_disconnect_requested = false
	_reconnect.stop()
	_set_state(TrainerDevice.ConnectionState.CONNECTING)
	bridge.connect_peripheral(id)


func disconnect_device() -> void:
	_disconnect_requested = true
	_reconnect.stop()
	if device_id != "" and _state != TrainerDevice.ConnectionState.DISCONNECTED:
		bridge.disconnect_peripheral(device_id)
	_set_state(TrainerDevice.ConnectionState.DISCONNECTED)


func tick(delta_sec: float) -> void:
	if delta_sec <= 0.0:
		return
	_time_sec += delta_sec
	if _state == TrainerDevice.ConnectionState.RECONNECTING and _reconnect.due(_time_sec):
		bridge.connect_peripheral(device_id)
	_on_time(_time_sec)


func get_connection_state() -> int:
	return _state


func get_battery_level() -> int:
	return battery_percent


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
	bridge.subscribe(id, _service_uuid(), _measurement_uuid())
	if _has_service(BleUuids.BATTERY_SERVICE):
		bridge.read_characteristic(id, BleUuids.BATTERY_SERVICE, BleUuids.BATTERY_LEVEL)
		bridge.subscribe(id, BleUuids.BATTERY_SERVICE, BleUuids.BATTERY_LEVEL)
	_reconnect.stop()
	_set_state(TrainerDevice.ConnectionState.CONNECTED)


func _on_notification(id: String, char_uuid: String, bytes: PackedByteArray) -> void:
	if id != device_id:
		return
	var ch := BleUuids.normalize(char_uuid)
	if ch == BleUuids.normalize(_measurement_uuid()):
		_on_measurement(bytes)
	elif ch == BleUuids.BATTERY_LEVEL:
		_on_battery(bytes)


func _on_characteristic_read(id: String, char_uuid: String, bytes: PackedByteArray) -> void:
	if id != device_id:
		return
	if BleUuids.normalize(char_uuid) == BleUuids.BATTERY_LEVEL:
		_on_battery(bytes)


func _on_battery(bytes: PackedByteArray) -> void:
	var b := BatteryCodec.decode_level(bytes)
	if b["ok"]:
		battery_percent = b["level_pct"]
		battery_level.emit(battery_percent)


func _on_disconnected(id: String, reason: int) -> void:
	if id != device_id:
		return
	if _disconnect_requested or reason == BleBridge.DisconnectReason.REQUESTED:
		_set_state(TrainerDevice.ConnectionState.DISCONNECTED)
		return
	if _state == TrainerDevice.ConnectionState.DISCONNECTED:
		return
	_set_state(TrainerDevice.ConnectionState.RECONNECTING)
	_reconnect.start(_time_sec)
	if _reconnect.due(_time_sec):
		bridge.connect_peripheral(device_id)


func _on_bridge_error(id: String, code: int, message: String) -> void:
	if id != "" and id != device_id:
		return
	match code:
		BleBridge.ErrorCode.CONNECTION_FAILED, BleBridge.ErrorCode.DEVICE_NOT_FOUND, \
		BleBridge.ErrorCode.TIMEOUT, BleBridge.ErrorCode.ADAPTER_UNAVAILABLE:
			if _state == TrainerDevice.ConnectionState.CONNECTING:
				_set_state(TrainerDevice.ConnectionState.DISCONNECTED)
				error.emit(ErrorCode.CONNECTION_FAILED, message)
		BleBridge.ErrorCode.READ_FAILED, BleBridge.ErrorCode.CHARACTERISTIC_NOT_FOUND:
			# Батареи может не быть — это «—», не ошибка (REQ-DEV-07 крит. 3).
			pass
		BleBridge.ErrorCode.SUBSCRIBE_FAILED, BleBridge.ErrorCode.SERVICE_NOT_FOUND:
			error.emit(ErrorCode.SUBSCRIBE_FAILED, message)
		_:
			push_warning("%s: ошибка моста %d: %s" % [kind(), code, message])


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _set_state(state: int) -> void:
	if state == _state:
		return
	_state = state
	connection_state_changed.emit(state)


func _has_service(service_uuid: String) -> bool:
	if services.is_empty():
		return true
	return services.has(BleUuids.normalize(service_uuid))
