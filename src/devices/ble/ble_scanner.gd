class_name BleScanner
extends RefCounted
## Сканер BLE-устройств и модель списка (REQ-DEV-01 крит. 1–4).
##
## `start()` → `bridge.start_scan(BleUuids.SCAN_SERVICES)`; каждое `device_found`
## добавляет или обновляет запись `devices` (дедупликация по id, обновление имени/RSSI).
## Запись: `{id, name, rssi, kind, last_seen_sec, available}`; `kind` — в терминах
## `RememberedDevices.KIND_*` ("trainer"|"hr"|"cadence"|"power") либо "unknown".
## Время подаётся через `tick(delta)`: без рекламы 10 с → `available = false`,
## 30 с → запись удаляется. События после `stop()` игнорируются.
## Сортировка: сначала станки, затем по убыванию RSSI, затем по имени.

const UNAVAILABLE_AFTER_SEC: float = 10.0
const REMOVE_AFTER_SEC: float = 30.0
const KIND_UNKNOWN: String = "unknown"

## Список изменился (добавление, обновление, недоступность, удаление).
signal devices_changed()
## Пришла реклама устройства (копия записи) — для автоподключения.
signal device_found(device: Dictionary)

var bridge: BleBridge
var devices: Array[Dictionary] = []
var scanning: bool = false

var _time_sec: float = 0.0


func _init(ble_bridge: BleBridge) -> void:
	bridge = ble_bridge
	bridge.device_found.connect(_on_device_found)


## Тип устройства по сервисам рекламы в терминах реестра запомненных устройств.
static func kind_from_services(service_uuids: PackedStringArray) -> String:
	match BleUuids.device_kind(service_uuids):
		"trainer":
			return RememberedDevices.KIND_TRAINER
		"heart_rate":
			return RememberedDevices.KIND_HR
		"cadence":
			return RememberedDevices.KIND_CADENCE
		"power":
			return RememberedDevices.KIND_POWER
	return KIND_UNKNOWN


func start() -> void:
	if scanning:
		return
	scanning = true
	bridge.start_scan(BleUuids.SCAN_SERVICES)


func stop() -> void:
	if not scanning:
		return
	scanning = false
	bridge.stop_scan()


func is_scanning() -> bool:
	return scanning


func get_time_sec() -> float:
	return _time_sec


## Продвинуть часы: пометить недоступные и удалить давно не виденные.
func tick(delta_sec: float) -> void:
	if delta_sec <= 0.0:
		return
	_time_sec += delta_sec
	var changed: bool = false
	for i in range(devices.size() - 1, -1, -1):
		var age: float = _time_sec - float(devices[i]["last_seen_sec"])
		if age >= REMOVE_AFTER_SEC:
			devices.remove_at(i)
			changed = true
		elif age >= UNAVAILABLE_AFTER_SEC and devices[i]["available"]:
			devices[i]["available"] = false
			changed = true
	if changed:
		_sort()
		devices_changed.emit()


## Запись по id (копия) или {}.
func find(id: String) -> Dictionary:
	for d in devices:
		if d["id"] == id:
			return d.duplicate()
	return {}


func has(id: String) -> bool:
	return not find(id).is_empty()


func clear() -> void:
	if devices.is_empty():
		return
	devices.clear()
	devices_changed.emit()


## Отключиться от моста (разрыв цикла мост ↔ сканер).
func dispose() -> void:
	if bridge == null:
		return
	if bridge.device_found.is_connected(_on_device_found):
		bridge.device_found.disconnect(_on_device_found)
	scanning = false
	bridge = null


func _on_device_found(id: String, name: String, rssi: int, service_uuids: PackedStringArray) -> void:
	if not scanning or id.is_empty():
		return
	var kind: String = kind_from_services(service_uuids)
	var entry: Dictionary = {}
	for d in devices:
		if d["id"] == id:
			entry = d
			break
	if entry.is_empty():
		entry = {"id": id, "name": name, "rssi": rssi, "kind": kind, "last_seen_sec": _time_sec, "available": true}
		devices.append(entry)
	else:
		if not name.is_empty():
			entry["name"] = name
		entry["rssi"] = rssi
		entry["last_seen_sec"] = _time_sec
		entry["available"] = true
		if kind != KIND_UNKNOWN:
			entry["kind"] = kind
	_sort()
	devices_changed.emit()
	device_found.emit(entry.duplicate())


func _sort() -> void:
	devices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_tr: bool = a["kind"] == RememberedDevices.KIND_TRAINER
		var b_tr: bool = b["kind"] == RememberedDevices.KIND_TRAINER
		if a_tr != b_tr:
			return a_tr
		if a["rssi"] != b["rssi"]:
			return int(a["rssi"]) > int(b["rssi"])
		return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
