class_name BleBridge
extends RefCounted
## Контракт нативного BLE-моста (REQ-DEV-01..08, REQ-NFR-06).
##
## Единственный способ игровой части общаться с BLE. Реализации:
## - `NativeBleBridge` — обёртка над GDExtension-классом `OvoschBle` (native/ble/);
## - `StubBleBridge` — скриптуемая заглушка для тестов и разработки без железа.
## Выбор делает `create_default()` — единственная точка проверки доступности
## нативного модуля в `src/devices/`.
##
## Все операции асинхронны: метод только ставит запрос, результат приходит
## сигналом (`connected`, `services_discovered`, `write_done`, `characteristic_read`,
## `error`). UUID передаются строками; реализации обязаны принимать как короткую
## ("2AD2"), так и полную форму (см. `BleUuids.normalize`). Байты — `PackedByteArray`.
## Чтение характеристик — только через `read_characteristic` с ответом
## `characteristic_read` (REQ-NFR-06 крит. 5, REQ-DEV-07 крит. 2, REQ-WRK-04 крит. 2).

## Состояние адаптера Bluetooth.
enum AdapterState { UNKNOWN, UNSUPPORTED, UNAUTHORIZED, POWERED_OFF, POWERED_ON }

## Причина `disconnected`.
enum DisconnectReason { REQUESTED, LINK_LOSS, TIMEOUT, ERROR }

## Коды сигнала `error`.
enum ErrorCode {
	NONE,
	## Нативный модуль/адаптер недоступен (нет GDExtension, Bluetooth выключен, нет разрешения).
	ADAPTER_UNAVAILABLE,
	DEVICE_NOT_FOUND,
	CONNECTION_FAILED,
	SERVICE_NOT_FOUND,
	CHARACTERISTIC_NOT_FOUND,
	WRITE_FAILED,
	READ_FAILED,
	SUBSCRIBE_FAILED,
	NOT_CONNECTED,
	TIMEOUT,
}

## Изменилось состояние адаптера; `state` — `AdapterState`.
signal adapter_state_changed(state: int)
## Найдено/обновлено устройство при сканировании.
signal device_found(id: String, name: String, rssi: int, service_uuids: PackedStringArray)
signal connected(id: String)
## `reason` — `DisconnectReason`.
signal disconnected(id: String, reason: int)
## Сервисы устройства: `{service_uuid: PackedStringArray(char_uuids)}`.
signal services_discovered(id: String, services: Dictionary)
## Нотификация/индикация характеристики.
signal notification(id: String, char_uuid: String, bytes: PackedByteArray)
## Ответ на `read_characteristic`.
signal characteristic_read(id: String, char_uuid: String, bytes: PackedByteArray)
## Результат `write`.
signal write_done(id: String, char_uuid: String, ok: bool)
## Ошибка; `id` может быть пустым для ошибок адаптера. `code` — `ErrorCode`.
signal error(id: String, code: int, message: String)


## Реализация готова к работе (нативный модуль загружен / заглушка всегда готова).
func is_available() -> bool:
	return false


func start_scan(_service_uuids: PackedStringArray) -> void:
	push_error("BleBridge.start_scan: not implemented")


func stop_scan() -> void:
	push_error("BleBridge.stop_scan: not implemented")


func connect_peripheral(_id: String) -> void:
	push_error("BleBridge.connect_peripheral: not implemented")


func disconnect_peripheral(_id: String) -> void:
	push_error("BleBridge.disconnect_peripheral: not implemented")


func discover_services(_id: String) -> void:
	push_error("BleBridge.discover_services: not implemented")


func subscribe(_id: String, _service_uuid: String, _char_uuid: String) -> void:
	push_error("BleBridge.subscribe: not implemented")


func unsubscribe(_id: String, _service_uuid: String, _char_uuid: String) -> void:
	push_error("BleBridge.unsubscribe: not implemented")


## Запись характеристики; результат — `write_done`. `with_response` — Write Request
## (true) или Write Command (false). Control Point FTMS пишется с ответом.
func write(_id: String, _service_uuid: String, _char_uuid: String, _bytes: PackedByteArray,
		_with_response: bool) -> void:
	push_error("BleBridge.write: not implemented")


## Чтение характеристики; результат — `characteristic_read` или `error`.
func read_characteristic(_id: String, _service_uuid: String, _char_uuid: String) -> void:
	push_error("BleBridge.read_characteristic: not implemented")


## Текущее состояние адаптера (`AdapterState`).
func get_adapter_state() -> int:
	push_error("BleBridge.get_adapter_state: not implemented")
	return AdapterState.UNKNOWN


## Мост по умолчанию: нативный, если GDExtension загружен, иначе заглушка.
static func create_default() -> BleBridge:
	if NativeBleBridge.is_native_available():
		return NativeBleBridge.new()
	return StubBleBridge.new()


static func adapter_state_name(state: int) -> String:
	match state:
		AdapterState.UNSUPPORTED:
			return "unsupported"
		AdapterState.UNAUTHORIZED:
			return "unauthorized"
		AdapterState.POWERED_OFF:
			return "powered_off"
		AdapterState.POWERED_ON:
			return "powered_on"
	return "unknown"
