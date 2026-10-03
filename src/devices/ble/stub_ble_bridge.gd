class_name StubBleBridge
extends BleBridge
## Скриптуемая заглушка BLE-моста для тестов и разработки без железа
## (REQ-DEV-01..08 контракт, REQ-NFR-06 крит. 5).
##
## Поведение:
## - каждый вызов контракта журналируется в `calls` словарём `{method, id, ...}`;
## - ответы ставятся в очередь `pending` и доставляются вызовом `pump()` —
##   как у настоящего моста, результат приходит асинхронно; тест сам решает,
##   когда «проходит время»;
## - `connect_peripheral` → `connected(id)` (или ошибка после `fail_next_connect()`);
## - `discover_services` → `services_discovered(id, services)` из `set_device_services`;
## - `write` → `write_done(id, char, ok)` (ok, пока не вызван `fail_next_write()`);
##   отказ записи, как у нативного моста, — только `write_done(ok = false)`, без `error`;
##   `legacy_double_write_failure = true` воспроизводит старый нативный мост, который на
##   один отказ слал и `write_done(false)`, и следом `error(WRITE_FAILED)`;
##   запись в FTMS Control Point `2AD9` при `auto_control_point_response` дополнительно
##   даёт индикацию `notification(id, "2AD9", [0x80, opcode, result])`, где result —
##   0x01 (успех) или код из `fail_next_control_point(result)`;
## - `read_characteristic` → `characteristic_read` байтами из `set_read_value`,
##   иначе `error(CHARACTERISTIC_NOT_FOUND)`; `fail_next_read()` → `error(READ_FAILED)`;
## - `emit_*` хелперы испускают сигналы сразу — для сценариев «устройство найдено»,
##   «обрыв», «пришла нотификация».
## - `dispose()` очищает очередь `pending`: её замыкания держат заглушку, и без
##   `pump()` объект не освобождается (утечка ObjectDB при выходе).

var calls: Array[Dictionary] = []
var pending: Array[Callable] = []
var adapter_state: int = AdapterState.POWERED_ON
## Доступность моста. `StubBleBridge.new()` доступен (тесты); заглушка из
## `BleBridge.create_default()` — нет (REQ-DEV-01 крит. 7: без нативного модуля приложение
## показывает «Bluetooth недоступен», а не подключает фантомные устройства).
var available: bool = true
var scanning: bool = false
var scan_filter: PackedStringArray = PackedStringArray()
var connected_ids: Array[String] = []
## id → Array[String] ключей "SERVICE/CHAR" (нормализованных).
var subscriptions: Dictionary = {}
## id → {service_uuid: PackedStringArray(char_uuids)}.
var device_services: Dictionary = {}
## Нормализованный char_uuid → байты для `read_characteristic`.
var read_values: Dictionary = {}
var auto_connect: bool = true
var auto_control_point_response: bool = true
## Старое поведение нативного моста: отказ записи → `write_done(false)` и `error(WRITE_FAILED)`.
var legacy_double_write_failure: bool = false

var _fail_next_write: bool = false
var _fail_next_connect: bool = false
var _fail_next_read: bool = false
var _next_cp_result: int = FtmsCodec.RESULT_SUCCESS


func is_available() -> bool:
	return available


## Включить/выключить заглушку: вместе с флагом переключается состояние адаптера
## (POWERED_ON / UNSUPPORTED) с сигналом `adapter_state_changed`.
func set_available(enabled: bool) -> void:
	available = enabled
	set_adapter_state(AdapterState.POWERED_ON if enabled else AdapterState.UNSUPPORTED)


# ---------------------------------------------------------------------------
# Контракт BleBridge
# ---------------------------------------------------------------------------

func start_scan(service_uuids: PackedStringArray) -> void:
	_log("start_scan", "", {"service_uuids": service_uuids})
	scanning = true
	scan_filter = service_uuids.duplicate()


func stop_scan() -> void:
	_log("stop_scan", "")
	scanning = false


func connect_peripheral(id: String) -> void:
	_log("connect_peripheral", id)
	if _fail_next_connect:
		_fail_next_connect = false
		pending.append(func() -> void:
			error.emit(id, ErrorCode.CONNECTION_FAILED, "StubBleBridge: сценарий «ошибка подключения» %s" % id))
		return
	if auto_connect:
		pending.append(func() -> void: emit_connected(id))


func disconnect_peripheral(id: String) -> void:
	_log("disconnect_peripheral", id)
	pending.append(func() -> void: emit_disconnected(id, DisconnectReason.REQUESTED))


func discover_services(id: String) -> void:
	_log("discover_services", id)
	var services: Dictionary = device_services.get(id, {})
	pending.append(func() -> void: services_discovered.emit(id, services))


func subscribe(id: String, service_uuid: String, char_uuid: String) -> void:
	_log("subscribe", id, {"service": BleUuids.normalize(service_uuid), "char": BleUuids.normalize(char_uuid)})
	var list: Array = subscriptions.get(id, [])
	var key := _key(service_uuid, char_uuid)
	if not list.has(key):
		list.append(key)
	subscriptions[id] = list


func unsubscribe(id: String, service_uuid: String, char_uuid: String) -> void:
	_log("unsubscribe", id, {"service": BleUuids.normalize(service_uuid), "char": BleUuids.normalize(char_uuid)})
	var list: Array = subscriptions.get(id, [])
	list.erase(_key(service_uuid, char_uuid))
	subscriptions[id] = list


func write(id: String, service_uuid: String, char_uuid: String, bytes: PackedByteArray,
		with_response: bool) -> void:
	var ch := BleUuids.normalize(char_uuid)
	_log("write", id, {"service": BleUuids.normalize(service_uuid), "char": ch,
		"bytes": bytes.duplicate(), "with_response": with_response})
	var ok: bool = not _fail_next_write
	_fail_next_write = false
	pending.append(func() -> void: write_done.emit(id, ch, ok))
	if not ok and legacy_double_write_failure:
		pending.append(func() -> void:
			error.emit(id, ErrorCode.WRITE_FAILED, "StubBleBridge: writeValue %s failed (дубль write_done)" % ch))
	if ok and auto_control_point_response and ch == BleUuids.FTMS_CONTROL_POINT and bytes.size() > 0:
		var opcode: int = bytes[0]
		var result: int = _next_cp_result
		_next_cp_result = FtmsCodec.RESULT_SUCCESS
		pending.append(func() -> void:
			notification.emit(id, ch, FtmsCodec.encode_control_point_response(opcode, result)))


func read_characteristic(id: String, service_uuid: String, char_uuid: String) -> void:
	var ch := BleUuids.normalize(char_uuid)
	_log("read_characteristic", id, {"service": BleUuids.normalize(service_uuid), "char": ch})
	if _fail_next_read:
		_fail_next_read = false
		pending.append(func() -> void:
			error.emit(id, ErrorCode.READ_FAILED, "StubBleBridge: сценарий «ошибка чтения» %s" % ch))
		return
	if not read_values.has(ch):
		pending.append(func() -> void:
			error.emit(id, ErrorCode.CHARACTERISTIC_NOT_FOUND, "StubBleBridge: нет характеристики %s" % ch))
		return
	var bytes: PackedByteArray = (read_values[ch] as PackedByteArray).duplicate()
	pending.append(func() -> void: characteristic_read.emit(id, ch, bytes))


func get_adapter_state() -> int:
	return adapter_state


# ---------------------------------------------------------------------------
# Сценарий
# ---------------------------------------------------------------------------

## Доставить все отложенные ответы (включая добавленные по ходу). Возвращает их число.
func pump() -> int:
	var n: int = 0
	while not pending.is_empty():
		var cb: Callable = pending.pop_front()
		cb.call()
		n += 1
	return n


## Сбросить недоставленные ответы (разрыв цикла заглушка ↔ замыкания очереди).
func dispose() -> void:
	pending.clear()


func set_adapter_state(state: int) -> void:
	if state == adapter_state:
		return
	adapter_state = state
	adapter_state_changed.emit(state)


## Сервисы устройства для `discover_services`: `{service_uuid: PackedStringArray(chars)}`.
func set_device_services(id: String, services: Dictionary) -> void:
	var norm: Dictionary = {}
	for s in services:
		var chars := PackedStringArray()
		for c in services[s]:
			chars.append(BleUuids.normalize(c))
		norm[BleUuids.normalize(s)] = chars
	device_services[id] = norm


## Байты, которыми отвечать на `read_characteristic(…, char_uuid)`.
func set_read_value(char_uuid: String, bytes: PackedByteArray) -> void:
	read_values[BleUuids.normalize(char_uuid)] = bytes.duplicate()


func fail_next_write() -> void:
	_fail_next_write = true


func fail_next_connect() -> void:
	_fail_next_connect = true


func fail_next_read() -> void:
	_fail_next_read = true


## Следующая запись в Control Point получит ответ с кодом `result` (≠ 0x01).
func fail_next_control_point(result: int = FtmsCodec.RESULT_OPERATION_FAILED) -> void:
	_next_cp_result = result


func emit_device_found(id: String, name: String, rssi: int, service_uuids: PackedStringArray) -> void:
	device_found.emit(id, name, rssi, service_uuids)


func emit_connected(id: String) -> void:
	if not connected_ids.has(id):
		connected_ids.append(id)
	connected.emit(id)


func emit_disconnected(id: String, reason: int = DisconnectReason.LINK_LOSS) -> void:
	connected_ids.erase(id)
	subscriptions.erase(id)
	disconnected.emit(id, reason)


func emit_notification(id: String, char_uuid: String, bytes: PackedByteArray) -> void:
	notification.emit(id, BleUuids.normalize(char_uuid), bytes)


func emit_characteristic_read(id: String, char_uuid: String, bytes: PackedByteArray) -> void:
	characteristic_read.emit(id, BleUuids.normalize(char_uuid), bytes)


func emit_error(id: String, code: int, message: String) -> void:
	error.emit(id, code, message)


func is_subscribed(id: String, service_uuid: String, char_uuid: String) -> bool:
	return (subscriptions.get(id, []) as Array).has(_key(service_uuid, char_uuid))


## Вызовы метода `method` в порядке поступления.
func calls_of(method: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in calls:
		if c["method"] == method:
			out.append(c)
	return out


## Записи `write` в характеристику `char_uuid`.
func writes_to(char_uuid: String) -> Array[Dictionary]:
	var ch := BleUuids.normalize(char_uuid)
	var out: Array[Dictionary] = []
	for c in calls_of("write"):
		if c["char"] == ch:
			out.append(c)
	return out


func clear_calls() -> void:
	calls.clear()


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _log(method: String, id: String, extra: Dictionary = {}) -> void:
	var entry: Dictionary = {"method": method, "id": id}
	entry.merge(extra)
	calls.append(entry)


func _key(service_uuid: String, char_uuid: String) -> String:
	return BleUuids.normalize(service_uuid) + "/" + BleUuids.normalize(char_uuid)
