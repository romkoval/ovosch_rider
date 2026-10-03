# Порты BLE: один GDExtension, N бэкендов `BleBackend` (REQ-NFR-06 крит. 2, 4; этапы 9–10)

Игровая часть видит только GDScript-контракт `BleBridge` (`src/devices/ble/ble_bridge.gd`) и его реализации
`StubBleBridge` (тесты) и `NativeBleBridge` (обёртка над нативным классом `OvoschBle`). Нативная часть устроена
как один класс `OvoschBle` на godot-cpp, который делегирует платформенному бэкенду через чистый C++ интерфейс
`ovosch::BleBackend` (`native/ble/src/ble_backend.h`) и получает события через `ovosch::BleListener`,
маршалируя их в главный поток Godot (`call_deferred`). Портирование на платформу = реализация одного
бэкенда + платформенная конфигурация разрешений. Ничего в `src/` не меняется.

```
src/devices/ble/ble_bridge.gd        контракт (методы + сигналы)            — не трогаем
src/devices/ble/native_ble_bridge.gd обёртка: ClassDB.class_exists("OvoschBle") — не трогаем (Android: + Engine.has_singleton)
native/ble/src/ovosch_ble.{h,cpp}    OvoschBle: биндинги 1:1, маршалинг в главный поток — общий код
native/ble/src/ble_backend.h         BleBackend / BleListener — контракт порта
native/ble/src/null_backend.*        заглушка: is_available() == false — собирается везде
native/ble/src/platform/apple/       CoreBluetooth (macOS, iOS)            — этап 2, T-022
native/ble/src/platform/linux/       BlueZ D-Bus                           — этап 10, docs/ports/linux_windows.md
native/ble/src/platform/windows/     WinRT Bluetooth LE                    — этап 10, docs/ports/linux_windows.md
native/android/ble/                  Android BLE API (Kotlin, плагин v2)   — этап 9, docs/ports/android.md
```

## Контракт порта

Методы `BleBackend` (все асинхронные, результат — в `BleListener`):

| Метод | Событие-ответ |
| --- | --- |
| `set_listener`, `is_available`, `get_adapter_state` | `on_adapter_state_changed(AdapterState)` при изменениях |
| `start_scan(service_uuids)`, `stop_scan()` | `on_device_found(id, name, rssi, service_uuids)` — повторно при каждом advertisement |
| `connect_peripheral(id)`, `disconnect_peripheral(id)` | `on_connected(id)`, `on_disconnected(id, DisconnectReason)` |
| `discover_services(id)` | `on_services_discovered(id, [ServiceInfo{uuid, characteristic_uuids}])` |
| `subscribe(id, svc, chr)`, `unsubscribe(...)` | `on_notification(id, chr, bytes)` на каждое уведомление; ошибка — `on_error(id, SUBSCRIBE_FAILED, …)` |
| `write(id, svc, chr, bytes, with_response)` | `on_write_done(id, chr, ok)` (без ответа — сразу `ok = true` после постановки в очередь) |
| `read_characteristic(id, svc, chr)` | `on_characteristic_read(id, chr, bytes)` — отличать от `on_notification` |
| любая ошибка | `on_error(id, ErrorCode, message)` |

Инварианты, одинаковые для всех портов (из приёмки Apple-бэкенда и `test_native_contract.gd`):
- Идентификатор устройства `id` — стабильная строка на время сессии (UUID у Apple, MAC у Android/BlueZ, 64-битный адрес у WinRT в hex).
  Запоминание устройства (REQ-DEV-06) опирается на этот `id` — на Android/Linux/Windows это MAC, который у приватных адресов меняется;
  Tacx Neo и большинство датчиков используют публичные адреса, но при обрыве «запомненного» — делать fallback на поиск по имени.
- UUID в контракте — строки нижнего регистра в полной 128-битной форме (`0000180d-0000-1000-8000-00805f9b34fb`); короткие `0x180D`
  приводятся к полной форме в `OvoschBle`, бэкенд получает уже полные.
- События из callback-потоков платформы попадают в `BleListener` из любого потока; `OvoschBle` отвечает за `call_deferred`.
  Бэкенд не должен блокировать поток вызова (все платформенные API — асинхронные или выносятся в рабочий поток).
- Повторный `start_scan` во время сканирования — перезапуск с новым фильтром; `stop_scan` без сканирования — no-op.
- После `disconnect_peripheral` обязательно приходит `on_disconnected(id, REQUESTED)`; при потере связи — `LINK_LOSS`.
- `NullBackend` возвращает `is_available() == false`, `get_adapter_state() == UNSUPPORTED`; CI собирает его на каждой платформе.

## Порядок работ для нового бэкенда

1. `native/ble/src/platform/<os>/<os>_backend.{h,cpp}` — класс `<Os>Backend : BleBackend`, `create_platform_backend()` под `#ifdef`.
2. `SConstruct` — ветка `platform == "<os>"`: включить файлы, определить `OVOSCH_BLE_HAS_PLATFORM_BACKEND`, добавить системные библиотеки.
3. `tests/unit/arch/test_native_contract.gd` — добавить файл бэкенда в проверку «все чистые виртуальные методы реализованы с `override`».
4. CI-job сборки на соответствующем раннере (`.github/workflows`), артефакт в `native/ble/bin/` (пути уже прописаны в `ovosch_ble.gdextension`).
5. Платформенные разрешения — `platform/<os>/…` и `docs/publishing/*`/`docs/ports/*`.
6. Ручные проверки из `docs/backlog.md` → «Ручные проверки владельца» на реальном Tacx Neo.

Подробности: `android.md` (Android BLE API, плагин v2, разрешения, Google Play), `linux_windows.md` (BlueZ, WinRT, каналы распространения).
Аналогичная схема «интерфейс + N бэкендов» для защищённого хранилища — `docs/secure_store.md`.
