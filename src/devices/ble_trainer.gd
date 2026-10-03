class_name BleTrainer
extends TrainerDevice
## Станок по FTMS поверх `BleBridge` (REQ-DEV-02, REQ-DEV-07, REQ-DEV-08, REQ-WRK-02/03/04, REQ-NFR-01).
##
## Последовательность подключения (REQ-DEV-02 крит. 1):
## `connect_device(id)` → `connect_peripheral` → `connected` → `discover_services` →
## подписки 2AD2 (Indoor Bike Data), 2ADA (Status), 2AD9 (Control Point) →
## запись Request Control `00` → чтение 2AD6 (Supported Resistance Level Range,
## если характеристика заявлена или список сервисов неизвестен) →
## **CONNECTED только после ответа `80 00 01`**. Отказ в Request Control
## → `error(CONTROL_POINT_REJECTED)` и DISCONNECTED без переподключения.
##
## Срыв подключения (REQ-DEV-07 крит. 1): CONNECTING длится не дольше
## `CONNECT_TIMEOUT_SEC` (по часам `tick`); по тайм-ауту, а также при ошибках моста
## `SUBSCRIBE_FAILED`, `SERVICE_NOT_FOUND`, `NOT_CONNECTED` или двойном отказе записи
## Request Control в CONNECTING — `disconnect_peripheral` (отмена подключения в мосте),
## DISCONNECTED и `error(CONNECTION_FAILED)`.
##
## Control Point — очередь (FTMS: новая процедура только после ответа на предыдущую).
## В полёте не больше одной команды; следующая уходит после индикации `80 <opcode> …`
## по ней или через `CP_RESPONSE_TIMEOUT_SEC` без ответа. Неотправленная команда того же
## опкода заменяется новой и встаёт в конец; команда режима (`04` уровень / `05` цель)
## вытесняет и неотправленные команды другого режима — в очереди остаётся только
## последний режим. Команда, совпадающая с последней ожидающей (в очереди или, при
## пустой очереди, в полёте), не дублируется — кроме возврата режима (цель в полёте →
## уровень в очереди → та же цель): тогда цель ставится заново и уходит по ответу
## или тайм-ауту, не позже `CP_RESPONSE_TIMEOUT_SEC` (REQ-WRK-03 крит. 3).
##
## Команды: Set Target Power `05 <s16 LE>`, Set Target Resistance
## Level `04 <uint8>` (процент → уровень по 2AD6 через `FtmsCodec.percent_to_resistance_level`),
## всегда `with_response = true`. Вне CONNECTED значения запоминаются, на станок
## не пишутся (сессия повторяет цель после CONNECTED, REQ-DEV-08 крит. 3).
## Ответ Control Point с `result != 0x01` → `error(CONTROL_POINT_REJECTED)`.
## Отказ записи (`write_done(ok = false)` или — для мостов, сообщающих только так, —
## `error(WRITE_FAILED)`) → один немедленный повтор той же команды (REQ-NFR-01 крит. 2,
## решение 24); второй отказ → один `error(WRITE_FAILED)`. `error(WRITE_FAILED)`,
## пришедший сразу за `write_done(false)` (старый нативный мост слал оба события
## на один отказ), считается дублем и игнорируется.
##
## Включение ERG пишет запомненную цель, если она > 0 (явная цель 0 Вт пишется
## через `set_target_power(0)`).
##
## Управление: `Control Permission Lost` (2ADA `FF`) → повторный Request Control;
## после его успеха заново уходит текущий режим (цель/уровень), если с подключения
## на станок уже отправлялась команда режима. Диапазон 2AD6,
## прочитанный после CONNECTED, при выключенном ERG переотправляет уровень в новом масштабе.
##
## Батарея (REQ-DEV-07 крит. 2 для станка): если в сервисах есть 180F (или список
## неизвестен), после Request Control читается 2A19 и оформляется подписка;
## значение — сигналом `battery_level(percent)`, `battery_percent == -1` — нет данных.
##
## Обрыв не по запросу → RECONNECTING, `connect_peripheral` сразу и далее каждые
## 5 с через `tick(delta)` без лимита попыток (REQ-DEV-08 крит. 1, решение 12);
## после `connected` — заново discover/subscribe/Request Control → CONNECTED.
## `disconnect_device()` → DISCONNECTED, переподключение не выполняется.
##
## `set_erg_enabled` с текущим значением — no-op: при повторной отправке режима
## сессией (возобновление, реконнект: `erg=true` + цель) цель не дублируется.
## `dispose()` отключает обработчики сигналов моста и обнуляет ссылку на него —
## разрывает цикл мост ↔ станок (иначе объекты не освобождаются).

const RECONNECT_INTERVAL_SEC: float = 5.0
## Предельная длительность CONNECTING, с (REQ-DEV-07 крит. 1).
const CONNECT_TIMEOUT_SEC: float = 15.0
## Ожидание индикации Control Point по команде в полёте, с; потом уходит следующая.
const CP_RESPONSE_TIMEOUT_SEC: float = 1.0
const FTMS: String = BleUuids.FTMS_SERVICE

## Заряд батареи станка 0..100 % (если есть Battery Service).
signal battery_level(percent: int)

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
## Последний известный заряд, %; -1 — неизвестен / сервиса нет.
var battery_percent: int = -1

var _state: int = ConnectionState.DISCONNECTED
var _time_sec: float = 0.0
var _reconnect := BleReconnectPolicy.new(RECONNECT_INTERVAL_SEC)
var _disconnect_requested: bool = false
## Момент входа в CONNECTING по часам `tick`.
var _connecting_since_sec: float = 0.0
## Команда Control Point в полёте: `{bytes, opcode, retried, sent_at}`; {} — нет.
var _cp_inflight: Dictionary = {}
## Неотправленные команды Control Point (PackedByteArray) в порядке отправки.
var _cp_queue: Array[PackedByteArray] = []
## Последний отказ записи пришёл как `write_done(false)`: следующий `error(WRITE_FAILED)`
## моста — его дубль (старый нативный мост слал оба события).
var _write_failure_seen: bool = false
## С подключения на станок уходила команда режима (цель/уровень) — её восстанавливаем
## после повторного Request Control.
var _mode_sent: bool = false


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
	if bridge == null or _state == ConnectionState.CONNECTED or _state == ConnectionState.CONNECTING:
		return
	if _state == ConnectionState.RECONNECTING and id == device_id:
		return
	if id != device_id:
		battery_percent = -1
	device_id = id
	_disconnect_requested = false
	control_granted = false
	_reset_control_point()
	_reconnect.stop()
	_connecting_since_sec = _time_sec
	_set_state(ConnectionState.CONNECTING)
	bridge.connect_peripheral(id)


func disconnect_device() -> void:
	_disconnect_requested = true
	_reconnect.stop()
	_reset_control_point()
	control_granted = false
	if bridge != null and device_id != "" and _state != ConnectionState.DISCONNECTED:
		bridge.disconnect_peripheral(device_id)
	_set_state(ConnectionState.DISCONNECTED)


## Отключить обработчики сигналов моста и забыть мост. После вызова объект
## неработоспособен; состояние — DISCONNECTED без сигнала. Очередь ответов
## `StubBleBridge` очищается (её замыкания держат заглушку — утечка при выходе).
func dispose() -> void:
	if bridge == null:
		return
	for pair in [[bridge.connected, _on_connected], [bridge.disconnected, _on_disconnected],
			[bridge.services_discovered, _on_services_discovered], [bridge.notification, _on_notification],
			[bridge.characteristic_read, _on_characteristic_read], [bridge.write_done, _on_write_done],
			[bridge.error, _on_bridge_error]]:
		var sig: Signal = pair[0]
		var cb: Callable = pair[1]
		if sig.is_connected(cb):
			sig.disconnect(cb)
	if bridge is StubBleBridge:
		(bridge as StubBleBridge).dispose()
	_reconnect.stop()
	_reset_control_point()
	_state = ConnectionState.DISCONNECTED
	bridge = null


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
	if enabled == erg_enabled:
		return
	erg_enabled = enabled
	if _state != ConnectionState.CONNECTED:
		return
	_write_current_mode()


func is_erg_enabled() -> bool:
	return erg_enabled


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
	if bridge == null:
		return
	if _state == ConnectionState.RECONNECTING and _reconnect.due(_time_sec):
		bridge.connect_peripheral(device_id)
	if _state == ConnectionState.CONNECTING \
			and _time_sec - _connecting_since_sec >= CONNECT_TIMEOUT_SEC - BleReconnectPolicy.TIME_EPSILON:
		_fail_connecting("Станок не подключился за %d с" % int(CONNECT_TIMEOUT_SEC))
		return
	if not _cp_inflight.is_empty() \
			and _time_sec - float(_cp_inflight["sent_at"]) >= CP_RESPONSE_TIMEOUT_SEC - BleReconnectPolicy.TIME_EPSILON:
		push_warning("BleTrainer: нет ответа Control Point на %s за %.1f с, отправляем следующую команду" % [
			FtmsCodec.opcode_name(int(_cp_inflight["opcode"])), CP_RESPONSE_TIMEOUT_SEC])
		_cp_inflight = {}
		_pump_control_point()


## Число попыток переподключения в текущей серии.
func reconnect_attempts() -> int:
	return _reconnect.attempts


## Команды Control Point, ждущие отправки (без команды в полёте) — для тестов и журнала.
func pending_control_point_commands() -> Array[PackedByteArray]:
	return _cp_queue.duplicate()


## Есть ли команда Control Point, ждущая индикации.
func has_control_point_in_flight() -> bool:
	return not _cp_inflight.is_empty()


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
	if services.is_empty() or services.has(BleUuids.BATTERY_SERVICE):
		bridge.read_characteristic(id, BleUuids.BATTERY_SERVICE, BleUuids.BATTERY_LEVEL)
		bridge.subscribe(id, BleUuids.BATTERY_SERVICE, BleUuids.BATTERY_LEVEL)


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
		BleUuids.BATTERY_LEVEL:
			_on_battery(bytes)


func _on_control_point_response(bytes: PackedByteArray) -> void:
	var r := FtmsCodec.decode_control_point_response(bytes)
	if not r["ok"]:
		return
	var opcode: int = r["request_opcode"]
	# Ответ на команду в полёте освобождает Control Point; следующая уйдёт после обработки.
	if not _cp_inflight.is_empty() and int(_cp_inflight["opcode"]) == opcode:
		_cp_inflight = {}
	if opcode == FtmsCodec.OP_REQUEST_CONTROL:
		if r["success"]:
			var regained: bool = _state == ConnectionState.CONNECTED and not control_granted
			control_granted = true
			if _state == ConnectionState.CONNECTING or _state == ConnectionState.RECONNECTING:
				_reconnect.stop()
				_set_state(ConnectionState.CONNECTED)
			elif regained and _mode_sent:
				# После Control Permission Lost станок мог сбросить режим — повторяем его.
				_write_current_mode()
		else:
			error.emit(ErrorCode.CONTROL_POINT_REJECTED,
				"Станок не передал управление (Request Control: %s)" % FtmsCodec.result_name(r["result"]))
			if _state != ConnectionState.CONNECTED:
				disconnect_device()
		_pump_control_point()
		return
	if not r["success"]:
		error.emit(ErrorCode.CONTROL_POINT_REJECTED, "Станок отверг команду %s: %s" % [
			FtmsCodec.opcode_name(opcode), FtmsCodec.result_name(r["result"])])
	_pump_control_point()


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
			# Неотправленные команды без управления будут отвергнуты; текущий режим
			# уйдёт заново после успешного Request Control.
			_cp_queue.clear()
			_write_control_point(FtmsCodec.encode_request_control())


func _on_characteristic_read(id: String, char_uuid: String, bytes: PackedByteArray) -> void:
	if id != device_id:
		return
	match BleUuids.normalize(char_uuid):
		BleUuids.SUPPORTED_RESISTANCE_RANGE:
			var r := FtmsCodec.decode_resistance_range(bytes)
			if r["ok"]:
				var changed: bool = r != resistance_range
				resistance_range = r
				# Диапазон пришёл после CONNECTED: уровень мог уйти в масштабе по умолчанию.
				if changed and _state == ConnectionState.CONNECTED and not erg_enabled:
					_write_resistance()
		BleUuids.BATTERY_LEVEL:
			_on_battery(bytes)


func _on_battery(bytes: PackedByteArray) -> void:
	var b := BatteryCodec.decode_level(bytes)
	if b["ok"]:
		battery_percent = b["level_pct"]
		battery_level.emit(battery_percent)


func _on_write_done(id: String, char_uuid: String, ok: bool) -> void:
	if id != device_id or BleUuids.normalize(char_uuid) != BleUuids.FTMS_CONTROL_POINT:
		return
	_write_failure_seen = not ok
	if ok or _cp_inflight.is_empty():
		return  # успех: команда в полёте ждёт индикации
	_handle_write_failure("write_done(ok = false)")


## Отказ записи команды в полёте: один немедленный повтор тех же байт; при повторном
## отказе — `error(WRITE_FAILED)` (REQ-NFR-01 крит. 2) и следующая команда очереди.
## Двойной отказ Request Control в CONNECTING срывает подключение (REQ-DEV-07 крит. 1).
func _handle_write_failure(reason: String) -> void:
	if not _cp_inflight["retried"]:
		_cp_inflight["retried"] = true
		_cp_inflight["sent_at"] = _time_sec
		bridge.write(device_id, FTMS, BleUuids.FTMS_CONTROL_POINT, _cp_inflight["bytes"], true)
		return
	var opcode: int = _cp_inflight["opcode"]
	_cp_inflight = {}
	if opcode == FtmsCodec.OP_REQUEST_CONTROL and _state == ConnectionState.CONNECTING:
		_fail_connecting("Запись Request Control не удалась дважды (%s)" % reason)
		return
	error.emit(ErrorCode.WRITE_FAILED, "Запись %s не удалась дважды (%s)" % [FtmsCodec.opcode_name(opcode), reason])
	_pump_control_point()


func _on_disconnected(id: String, reason: int) -> void:
	if id != device_id:
		return
	control_granted = false
	_reset_control_point()
	if _disconnect_requested or reason == BleBridge.DisconnectReason.REQUESTED:
		_set_state(ConnectionState.DISCONNECTED)
		return
	if _state == ConnectionState.DISCONNECTED or _state == ConnectionState.RECONNECTING:
		return  # повторный обрыв во время переподключения серию не перезапускает
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
				_fail_connecting(message, false)  # попытка в мосте уже завершилась
			# В RECONNECTING — следующая попытка по таймеру.
		BleBridge.ErrorCode.READ_FAILED, BleBridge.ErrorCode.CHARACTERISTIC_NOT_FOUND:
			push_warning("BleTrainer: необязательное чтение не удалось: %s" % message)
		BleBridge.ErrorCode.WRITE_FAILED:
			if _write_failure_seen:
				# Дубль только что обработанного write_done(false): повтор уже в полёте
				# (или ошибка уже выдана) — второй раз не считаем.
				_write_failure_seen = false
			elif not _cp_inflight.is_empty():
				# Мост сообщает отказ только сигналом error; ожидающая запись у станка
				# одна — команда Control Point в полёте.
				_handle_write_failure(message)
			else:
				error.emit(ErrorCode.WRITE_FAILED, message)
		BleBridge.ErrorCode.SUBSCRIBE_FAILED, BleBridge.ErrorCode.SERVICE_NOT_FOUND, \
		BleBridge.ErrorCode.NOT_CONNECTED:
			if _state == ConnectionState.CONNECTING:
				_fail_connecting(message)
			elif code == BleBridge.ErrorCode.NOT_CONNECTED:
				push_warning("BleTrainer: %s" % message)
			else:
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


## Срыв подключения в CONNECTING: отмена в мосте, DISCONNECTED, `error(CONNECTION_FAILED)`.
func _fail_connecting(message: String, cancel_in_bridge: bool = true) -> void:
	_disconnect_requested = true
	control_granted = false
	_reset_control_point()
	if cancel_in_bridge and bridge != null and device_id != "":
		bridge.disconnect_peripheral(device_id)
	_set_state(ConnectionState.DISCONNECTED)
	error.emit(ErrorCode.CONNECTION_FAILED, message)


func _reset_control_point() -> void:
	_cp_inflight = {}
	_cp_queue.clear()
	_write_failure_seen = false
	_mode_sent = false


## Поставить команду в очередь Control Point (см. шапку: объединение и дедупликация).
func _write_control_point(bytes: PackedByteArray) -> void:
	if bridge == null or bytes.is_empty():
		return
	if bytes[0] == FtmsCodec.OP_SET_TARGET_POWER or bytes[0] == FtmsCodec.OP_SET_TARGET_RESISTANCE:
		_mode_sent = true
	if _cp_inflight.is_empty() and _cp_queue.is_empty():
		_send_control_point(bytes)
		return
	var opcode: int = bytes[0]
	var is_mode: bool = _is_mode_opcode(opcode)
	var dropped_other_mode: bool = false
	for i in range(_cp_queue.size() - 1, -1, -1):
		var queued: int = _cp_queue[i][0]
		# Команда режима (цель/уровень) вытесняет неотправленные команды обоих режимов:
		# устаревшая команда другого режима, ушедшая по тайм-ауту первой, на время
		# перевела бы станок не в тот режим (REQ-WRK-03 крит. 3).
		if queued == opcode:
			_cp_queue.remove_at(i)
		elif is_mode and _is_mode_opcode(queued):
			_cp_queue.remove_at(i)
			dropped_other_mode = true
	var last: PackedByteArray = _cp_queue.back() if not _cp_queue.is_empty() else \
		(_cp_inflight["bytes"] as PackedByteArray)
	# Совпадение с командой в полёте после возврата режима (X → другой режим → X) не
	# считается дублем: ответ на X мог потеряться, режим подтверждается заново.
	if last == bytes and not (dropped_other_mode and _cp_queue.is_empty()):
		return
	_cp_queue.append(bytes)


static func _is_mode_opcode(opcode: int) -> bool:
	return opcode == FtmsCodec.OP_SET_TARGET_POWER or opcode == FtmsCodec.OP_SET_TARGET_RESISTANCE


func _send_control_point(bytes: PackedByteArray) -> void:
	_cp_inflight = {"bytes": bytes, "opcode": int(bytes[0]), "retried": false, "sent_at": _time_sec}
	bridge.write(device_id, FTMS, BleUuids.FTMS_CONTROL_POINT, bytes, true)


## Отправить следующую команду очереди, если Control Point свободен.
func _pump_control_point() -> void:
	if bridge == null or not _cp_inflight.is_empty() or _cp_queue.is_empty():
		return
	_send_control_point(_cp_queue.pop_front())


## Текущий режим на станок: цель (ERG, если > 0) или уровень сопротивления.
func _write_current_mode() -> void:
	if erg_enabled:
		if target_power_w > 0:
			_write_control_point(FtmsCodec.encode_set_target_power(target_power_w))
	else:
		_write_resistance()


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
