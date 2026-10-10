class_name BleSensorBase
extends SensorDevice
## Общий BLE-жизненный цикл датчика поверх `BleBridge` (REQ-DEV-03/04/05, REQ-DEV-07, REQ-DEV-08).
##
## `connect_device(id)` → `connect_peripheral` → `connected` → `discover_services` →
## проверка сервиса датчика → подписка на характеристику измерения → при наличии Battery
## Service 180F чтение 2A19 и подписка на него → CONNECTED.
##
## Срыв подключения (REQ-DEV-07 крит. 1, Н-55) — DISCONNECTED, `error(CONNECTION_FAILED)` и
## причина `last_failure()` (`SensorDevice.FailureReason`), которая хранится до следующей
## попытки или ручного отключения:
## - ошибка моста в CONNECTING: `CONNECTION_FAILED` → REFUSED; `TIMEOUT`, `DEVICE_NOT_FOUND` →
##   NO_RESPONSE; `ADAPTER_UNAVAILABLE` → BLUETOOTH_OFF; `SUBSCRIBE_FAILED` → REFUSED,
##   `SERVICE_NOT_FOUND` → NO_SERVICE, `NOT_CONNECTED` → LINK_LOST (последние три — с отменой
##   подключения в мосте, `disconnect_peripheral`);
## - ошибка подписки на измерение в CONNECTED (подписка уходит вместе с переходом в CONNECTED,
##   ответ моста — позже): `SERVICE_NOT_FOUND` → NO_SERVICE, `SUBSCRIBE_FAILED` с UUID сервиса
##   или характеристики датчика в сообщении → REFUSED; срыв с отменой в мосте (T-154). Ошибка,
##   в сообщении которой есть Battery Service 180F / 2A19, подключение не роняет: батареи может
##   не быть (REQ-DEV-07 крит. 3). `SUBSCRIBE_FAILED` без UUID в сообщении (CoreBluetooth
##   `setNotifyValue` его не называет) — как раньше, `error(SUBSCRIBE_FAILED)` без срыва;
## - `disconnected` не по запросу в CONNECTING (до `services_discovered`) → LINK_LOST
##   (`TIMEOUT` → NO_RESPONSE): устройство ещё ни разу не подключилось, переподключения нет;
## - в `services_discovered` нет сервиса датчика (у пульсометра — `0x180D`, REQ-DEV-03) →
##   NO_SERVICE, отмена в мосте; пустой список сервисов — тоже «нет сервиса» (нативный мост Apple
##   отдаёт пустой словарь, когда сервисов нет; T-154);
## - CONNECTING дольше `CONNECT_TIMEOUT_SEC` по часам `tick` → NO_RESPONSE, отмена в мосте.
## Обрыв из CONNECTED → RECONNECTING (REQ-DEV-08 крит. 1) с причиной LINK_LOST, попытки сразу
## и каждые 5 с через `tick` (`BleReconnectPolicy`); CONNECTED сбрасывает причину.
##
## UUID сервисов из моста сравниваются в нормализованном виде (`BleUuids.normalize`: короткая
## и полная 128-битная форма, любой регистр).
##
## Журнал (`DiagLog`, категория `ble`; T-154, T-116b не дублирует): `sensor_connect` (попытка,
## имя), `sensor_link_up` (`connected` моста), `sensor_services` (список UUID), `sensor_subscribe`,
## `sensor_error` (код и сообщение моста), `sensor_disconnected` (причина моста),
## `sensor_failed` (причина срыва), `sensor_state` (переход). Устройство помечено `dev` —
## первыми символами SHA-256 от id (id на Android — MAC-адрес, в журнал не пишется); id в
## сообщениях моста заменяется той же меткой.
##
## Наследники задают `_service_uuid()`, `_measurement_uuid()`, `_on_measurement(bytes)` и при
## необходимости `_on_time(now_sec)`.

const RECONNECT_INTERVAL_SEC: float = 5.0
## Предельная длительность CONNECTING, с (REQ-DEV-07 крит. 1).
const CONNECT_TIMEOUT_SEC: float = 15.0
## Длина метки устройства в журнале (символов SHA-256 от id).
const LOG_DEVICE_TAG_LENGTH: int = 8

var bridge: BleBridge
var device_id: String = ""
## Имя устройства из рекламы (задаёт `ConnectionManager`) — только для журнала.
var device_name: String = ""
## Сервисы из `services_discovered` с нормализованными UUID: `{service: PackedStringArray(chars)}`.
var services: Dictionary = {}
var battery_percent: int = -1

var _state: int = TrainerDevice.ConnectionState.DISCONNECTED
var _time_sec: float = 0.0
var _reconnect := BleReconnectPolicy.new(RECONNECT_INTERVAL_SEC)
var _disconnect_requested: bool = false
## Момент входа в CONNECTING по часам `tick`.
var _connecting_since_sec: float = 0.0
var _failure: int = FailureReason.NONE
var _failure_message: String = ""
## Метка устройства для журнала (см. шапку).
var _device_tag: String = ""


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
	if bridge == null or _state == TrainerDevice.ConnectionState.CONNECTED \
			or _state == TrainerDevice.ConnectionState.CONNECTING:
		return
	if _state == TrainerDevice.ConnectionState.RECONNECTING and id == device_id:
		return
	device_id = id
	_device_tag = _tag_of(id)
	_disconnect_requested = false
	_clear_failure()
	_reconnect.stop()
	_connecting_since_sec = _time_sec
	_log("sensor_connect", {"name": device_name})
	_set_state(TrainerDevice.ConnectionState.CONNECTING)
	bridge.connect_peripheral(id)


func disconnect_device() -> void:
	_disconnect_requested = true
	_reconnect.stop()
	_clear_failure()
	if bridge != null and device_id != "" and _state != TrainerDevice.ConnectionState.DISCONNECTED:
		_log("sensor_disconnect", {})
		bridge.disconnect_peripheral(device_id)
	_set_state(TrainerDevice.ConnectionState.DISCONNECTED)


## Отключить обработчики сигналов моста и забыть мост (разрыв цикла мост ↔ датчик).
func dispose() -> void:
	if bridge == null:
		return
	for pair in [[bridge.connected, _on_connected], [bridge.disconnected, _on_disconnected],
			[bridge.services_discovered, _on_services_discovered], [bridge.notification, _on_notification],
			[bridge.characteristic_read, _on_characteristic_read], [bridge.error, _on_bridge_error]]:
		var sig: Signal = pair[0]
		var cb: Callable = pair[1]
		if sig.is_connected(cb):
			sig.disconnect(cb)
	_reconnect.stop()
	_state = TrainerDevice.ConnectionState.DISCONNECTED
	bridge = null


func tick(delta_sec: float) -> void:
	if delta_sec <= 0.0:
		return
	_time_sec += delta_sec
	if bridge != null and _state == TrainerDevice.ConnectionState.RECONNECTING and _reconnect.due(_time_sec):
		bridge.connect_peripheral(device_id)
	if bridge != null and _state == TrainerDevice.ConnectionState.CONNECTING \
			and _time_sec - _connecting_since_sec >= CONNECT_TIMEOUT_SEC - BleReconnectPolicy.TIME_EPSILON:
		_fail(FailureReason.NO_RESPONSE, "%s: датчик не подключился за %d с" % [kind(), int(CONNECT_TIMEOUT_SEC)])
	_on_time(_time_sec)


func get_connection_state() -> int:
	return _state


func get_battery_level() -> int:
	return battery_percent


func last_failure() -> int:
	return _failure


## Сообщение последнего срыва (текст моста или свой; для журнала и отладки, не для экрана).
func last_failure_message() -> String:
	return _failure_message


func reconnect_attempts() -> int:
	return _reconnect.attempts


# ---------------------------------------------------------------------------
# События моста
# ---------------------------------------------------------------------------

func _on_connected(id: String) -> void:
	if id != device_id or _disconnect_requested:
		return
	_log("sensor_link_up", {"state": TrainerDevice.state_name(_state)})
	bridge.discover_services(id)


func _on_services_discovered(id: String, svc: Dictionary) -> void:
	if id != device_id or _disconnect_requested:
		return
	services = normalized_services(svc)
	var own: String = BleUuids.normalize(_service_uuid())
	var listed := PackedStringArray(services.keys())
	listed.sort()
	var has_own: bool = services.has(own)
	_log("sensor_services", {"services": listed, "required": own, "has_required": has_own})
	if not has_own:
		# REQ-DEV-03 (Н-55 (б)): без своего сервиса датчик не входит в CONNECTED.
		_fail(FailureReason.NO_SERVICE, "%s: у устройства нет сервиса %s (сервисы: %s)" % [kind(), own, ", ".join(listed)])
		return
	bridge.subscribe(id, _service_uuid(), _measurement_uuid())
	_log("sensor_subscribe", {"service": own, "char": BleUuids.normalize(_measurement_uuid())})
	if _has_service(BleUuids.BATTERY_SERVICE):
		bridge.read_characteristic(id, BleUuids.BATTERY_SERVICE, BleUuids.BATTERY_LEVEL)
		bridge.subscribe(id, BleUuids.BATTERY_SERVICE, BleUuids.BATTERY_LEVEL)
		_log("sensor_subscribe", {"service": BleUuids.BATTERY_SERVICE, "char": BleUuids.BATTERY_LEVEL})
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
	if id != device_id or device_id.is_empty():
		return
	var requested: bool = _disconnect_requested or reason == BleBridge.DisconnectReason.REQUESTED
	_log("sensor_disconnected", {"reason": disconnect_reason_name(reason), "requested": requested,
		"state": TrainerDevice.state_name(_state)})
	if requested:
		_set_state(TrainerDevice.ConnectionState.DISCONNECTED)
		return
	match _state:
		TrainerDevice.ConnectionState.DISCONNECTED, TrainerDevice.ConnectionState.RECONNECTING:
			return
		TrainerDevice.ConnectionState.CONNECTING:
			# Связь оборвалась до `services_discovered`: подключение не состоялось (REQ-DEV-07
			# крит. 1), переподключения нет — устройство ещё ни разу не было подключено.
			var why: int = FailureReason.NO_RESPONSE if reason == BleBridge.DisconnectReason.TIMEOUT \
				else FailureReason.LINK_LOST
			_fail(why, "%s: связь прервалась при подключении (%s)" % [kind(), disconnect_reason_name(reason)], false)
			return
	# Обрыв подключённого устройства — переподключение (REQ-DEV-08 крит. 1), причина видна.
	_failure = FailureReason.LINK_LOST
	_failure_message = "%s: связь прервалась (%s)" % [kind(), disconnect_reason_name(reason)]
	_set_state(TrainerDevice.ConnectionState.RECONNECTING)
	_reconnect.start(_time_sec)
	if _reconnect.due(_time_sec):
		bridge.connect_peripheral(device_id)


func _on_bridge_error(id: String, code: int, message: String) -> void:
	if id != "" and id != device_id:
		return
	if not id.is_empty() or _state != TrainerDevice.ConnectionState.DISCONNECTED:
		_log("sensor_error", {"code": bridge_error_name(code), "message": _safe(message),
			"state": TrainerDevice.state_name(_state)})
	var connecting: bool = _state == TrainerDevice.ConnectionState.CONNECTING
	match code:
		BleBridge.ErrorCode.CONNECTION_FAILED:
			if connecting:
				_fail(FailureReason.REFUSED, message, false)  # попытка в мосте уже завершилась
		BleBridge.ErrorCode.DEVICE_NOT_FOUND, BleBridge.ErrorCode.TIMEOUT:
			if connecting:
				_fail(FailureReason.NO_RESPONSE, message, false)
		BleBridge.ErrorCode.ADAPTER_UNAVAILABLE:
			if connecting:
				_fail(FailureReason.BLUETOOTH_OFF, message, false)
		BleBridge.ErrorCode.READ_FAILED, BleBridge.ErrorCode.CHARACTERISTIC_NOT_FOUND:
			# Батареи может не быть — это «—», не ошибка (REQ-DEV-07 крит. 3).
			pass
		BleBridge.ErrorCode.SUBSCRIBE_FAILED, BleBridge.ErrorCode.SERVICE_NOT_FOUND:
			var why: int = FailureReason.NO_SERVICE if code == BleBridge.ErrorCode.SERVICE_NOT_FOUND \
				else FailureReason.REFUSED
			if connecting:
				_fail(why, message)
			elif _state == TrainerDevice.ConnectionState.CONNECTED and _is_measurement_error(code, message):
				# Подписка на измерение не удалась: «подключено» без данных хуже, чем срыв с причиной.
				_fail(why, message)
			else:
				error.emit(ErrorCode.SUBSCRIBE_FAILED, message)
		BleBridge.ErrorCode.NOT_CONNECTED:
			if connecting:
				_fail(FailureReason.LINK_LOST, message)
			else:
				push_warning("%s: %s" % [kind(), message])
		_:
			push_warning("%s: ошибка моста %d: %s" % [kind(), code, message])


# ---------------------------------------------------------------------------
# Имена для журнала
# ---------------------------------------------------------------------------

## Имя кода `BleBridge.ErrorCode` в нижнем регистре ("connection_failed"); неизвестный — число.
static func bridge_error_name(code: int) -> String:
	var keys: Array = BleBridge.ErrorCode.keys()
	if code >= 0 and code < keys.size():
		return str(keys[code]).to_lower()
	return str(code)


## Имя `BleBridge.DisconnectReason` в нижнем регистре ("link_loss"); неизвестное — число.
static func disconnect_reason_name(reason: int) -> String:
	var keys: Array = BleBridge.DisconnectReason.keys()
	if reason >= 0 and reason < keys.size():
		return str(keys[reason]).to_lower()
	return str(reason)


## Сервисы моста с нормализованными UUID (ключи и характеристики): мост может отдать короткую
## или полную форму в любом регистре.
static func normalized_services(svc: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in svc:
		var chars := PackedStringArray()
		var raw: Variant = svc[key]
		if raw is PackedStringArray or raw is Array:
			for c: Variant in raw:
				chars.append(BleUuids.normalize(str(c)))
		out[BleUuids.normalize(str(key))] = chars
	return out


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _set_state(state: int) -> void:
	if state == _state:
		return
	var previous: int = _state
	_state = state
	if state == TrainerDevice.ConnectionState.CONNECTED:
		_clear_failure()
	_log("sensor_state", {"from": TrainerDevice.state_name(previous), "to": TrainerDevice.state_name(state),
		"reason": failure_name(_failure)})
	connection_state_changed.emit(state)


## Срыв подключения: причина, отмена в мосте (если попытка там ещё идёт), DISCONNECTED,
## `error(CONNECTION_FAILED)` (REQ-DEV-07 крит. 1). Причина ставится до смены состояния —
## подписчики `connection_state_changed` уже видят её в `last_failure()`.
func _fail(reason: int, message: String, cancel_in_bridge: bool = true) -> void:
	_disconnect_requested = true
	_reconnect.stop()
	_failure = reason
	_failure_message = message
	_log("sensor_failed", {"reason": failure_name(reason), "message": _safe(message)})
	if cancel_in_bridge and bridge != null and device_id != "":
		bridge.disconnect_peripheral(device_id)
	_set_state(TrainerDevice.ConnectionState.DISCONNECTED)
	error.emit(ErrorCode.CONNECTION_FAILED, message)


func _clear_failure() -> void:
	_failure = FailureReason.NONE
	_failure_message = ""


func _has_service(service_uuid: String) -> bool:
	return services.has(BleUuids.normalize(service_uuid))


## Ошибка моста относится к подписке на измерение датчика (а не к батарее): `SERVICE_NOT_FOUND`,
## если сообщение не называет Battery Service; `SUBSCRIBE_FAILED` — только если сообщение называет
## сервис или характеристику датчика.
func _is_measurement_error(code: int, message: String) -> bool:
	var text := message.to_upper()
	if _mentions(text, BleUuids.BATTERY_SERVICE) or _mentions(text, BleUuids.BATTERY_LEVEL):
		return false
	if code == BleBridge.ErrorCode.SERVICE_NOT_FOUND:
		return true
	return _mentions(text, _service_uuid()) or _mentions(text, _measurement_uuid())


## Упоминание UUID в сообщении (верхний регистр): короткая форма или полная 128-битная.
static func _mentions(upper_text: String, uuid: String) -> bool:
	var short := BleUuids.normalize(uuid).to_upper()
	if upper_text.contains(short):
		return true
	return short.length() == 4 and upper_text.contains("0000%s-" % short)


func _log(event_name: String, data: Dictionary) -> void:
	if DiagLog.shared() == null:
		return
	var record: Dictionary = {"sensor": kind(), "dev": _device_tag}
	record.merge(data)
	DiagLog.event(DiagLog.CAT_BLE, event_name, record)


## Сообщение моста без id устройства (id заменяется меткой журнала).
func _safe(message: String) -> String:
	if device_id.is_empty():
		return message
	return message.replace(device_id, _device_tag)


static func _tag_of(id: String) -> String:
	return id.sha256_text().substr(0, LOG_DEVICE_TAG_LENGTH) if not id.is_empty() else ""
