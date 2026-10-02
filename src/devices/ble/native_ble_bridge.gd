class_name NativeBleBridge
extends BleBridge
## Обёртка над нативным GDExtension-классом `OvoschBle` (native/ble/, задачи T-021/T-022).
##
## Нативный класс обязан иметь методы и сигналы контракта `BleBridge` 1:1
## (имена и порядок аргументов). Обёртка вызывает его через `Object.call`,
## чтобы проект открывался и без GDExtension: тогда `is_available() == false`,
## все вызовы — no-op с предупреждением и сигналом `error(ADAPTER_UNAVAILABLE)`.
## Платформенных ветвлений здесь нет — только проверка наличия класса.

const NATIVE_CLASS: StringName = &"OvoschBle"

## Сигналы контракта, которые пробрасываются из нативного объекта.
const FORWARDED_SIGNALS: Array[StringName] = [
	&"adapter_state_changed", &"device_found", &"connected", &"disconnected",
	&"services_discovered", &"notification", &"characteristic_read", &"write_done", &"error",
]

var _native: Object = null


static func is_native_available() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


func _init() -> void:
	if not is_native_available():
		return
	_native = ClassDB.instantiate(NATIVE_CLASS)
	if _native == null:
		push_warning("NativeBleBridge: не удалось создать %s" % NATIVE_CLASS)
		return
	_wire_signals()


func is_available() -> bool:
	return _native != null


func start_scan(service_uuids: PackedStringArray) -> void:
	if _unavailable("start_scan"):
		return
	_native.call("start_scan", service_uuids)


func stop_scan() -> void:
	if _unavailable("stop_scan"):
		return
	_native.call("stop_scan")


func connect_peripheral(id: String) -> void:
	if _unavailable("connect_peripheral", id):
		return
	_native.call("connect_peripheral", id)


func disconnect_peripheral(id: String) -> void:
	if _unavailable("disconnect_peripheral", id):
		return
	_native.call("disconnect_peripheral", id)


func discover_services(id: String) -> void:
	if _unavailable("discover_services", id):
		return
	_native.call("discover_services", id)


func subscribe(id: String, service_uuid: String, char_uuid: String) -> void:
	if _unavailable("subscribe", id):
		return
	_native.call("subscribe", id, service_uuid, char_uuid)


func unsubscribe(id: String, service_uuid: String, char_uuid: String) -> void:
	if _unavailable("unsubscribe", id):
		return
	_native.call("unsubscribe", id, service_uuid, char_uuid)


func write(id: String, service_uuid: String, char_uuid: String, bytes: PackedByteArray,
		with_response: bool) -> void:
	if _unavailable("write", id):
		return
	_native.call("write", id, service_uuid, char_uuid, bytes, with_response)


func read_characteristic(id: String, service_uuid: String, char_uuid: String) -> void:
	if _unavailable("read_characteristic", id):
		return
	_native.call("read_characteristic", id, service_uuid, char_uuid)


func get_adapter_state() -> int:
	if _native == null:
		return AdapterState.UNSUPPORTED
	return int(_native.call("get_adapter_state"))


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

## true, если нативного модуля нет: предупреждение + `error(ADAPTER_UNAVAILABLE)`.
func _unavailable(method: String, id: String = "") -> bool:
	if _native != null:
		return false
	var msg := "NativeBleBridge.%s: нативный модуль %s не загружен" % [method, NATIVE_CLASS]
	push_warning(msg)
	error.emit(id, ErrorCode.ADAPTER_UNAVAILABLE, msg)
	return true


func _wire_signals() -> void:
	for sig in FORWARDED_SIGNALS:
		if not _native.has_signal(sig):
			push_warning("NativeBleBridge: у %s нет сигнала %s" % [NATIVE_CLASS, sig])
			continue
		_native.connect(sig, Callable(self, "_fwd_" + String(sig)))


func _fwd_adapter_state_changed(state: int) -> void:
	adapter_state_changed.emit(state)


func _fwd_device_found(id: String, name: String, rssi: int, service_uuids: PackedStringArray) -> void:
	device_found.emit(id, name, rssi, service_uuids)


func _fwd_connected(id: String) -> void:
	connected.emit(id)


func _fwd_disconnected(id: String, reason: int) -> void:
	disconnected.emit(id, reason)


func _fwd_services_discovered(id: String, services: Dictionary) -> void:
	services_discovered.emit(id, services)


func _fwd_notification(id: String, char_uuid: String, bytes: PackedByteArray) -> void:
	notification.emit(id, char_uuid, bytes)


func _fwd_characteristic_read(id: String, char_uuid: String, bytes: PackedByteArray) -> void:
	characteristic_read.emit(id, char_uuid, bytes)


func _fwd_write_done(id: String, char_uuid: String, ok: bool) -> void:
	write_done.emit(id, char_uuid, ok)


func _fwd_error(id: String, code: int, message: String) -> void:
	error.emit(id, code, message)
