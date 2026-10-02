# ovosch_ble — нативный BLE-мост (GDExtension)

Реализация контракта `BleBridge` (`src/devices/ble/ble_bridge.gd`) в виде класса
`OvoschBle : RefCounted`, который `NativeBleBridge` находит через
`ClassDB.class_exists("OvoschBle")`. Весь платформозависимый код живёт здесь
(REQ-NFR-06 крит. 2); игровая часть видит только GDScript-контракт.

## Структура

```
native/
  .gdignore              — каталог закрыт от Godot, пока библиотеки не собраны (см. ниже)
  godot-cpp/             — клон godot-cpp (не в репозитории, см. «Зависимости»)
  ble/
    SConstruct           — сборка на godot-cpp
    ovosch_ble.gdextension
    src/register_types.{h,cpp}
    src/ovosch_ble.{h,cpp}    — класс OvoschBle: методы и сигналы 1:1 с BleBridge
    src/ble_backend.h         — чистый C++ интерфейс платформенного backend'а
    src/null_backend.{h,cpp}  — заглушка (is_available() == false), собирается везде
    src/platform/apple/       — CoreBluetooth-backend (T-022, Objective-C++)
```

## Зависимости

- Python 3 + SCons: `pip install scons`
- godot-cpp. Ветки godot-cpp соответствуют минорным версиям движка; на момент
  написания самая новая стабильная ветка — `4.5` (ветки `4.7` в апстриме ещё нет),
  расширение, собранное с ней, загружается в Godot ≥ 4.5 (`compatibility_minimum = 4.5`).
  Когда появится ветка `4.7`, замените её в командах ниже и в CI.

```sh
cd native
git clone --depth 1 -b 4.5 https://github.com/godotengine/godot-cpp godot-cpp
```

## Сборка

```sh
cd native/ble
scons platform=linux   target=template_debug -j4     # проверка каркаса (CI, job native-linux)
scons platform=macos   target=template_debug         # macOS (нужен Xcode CLT)
scons platform=macos   target=template_release
scons platform=ios     target=template_release arch=arm64
```

Результат — в `native/ble/bin/`:
- macOS: `libovosch_ble.macos.template_debug.framework/` (путь из `.gdextension`);
- Linux: `libovosch_ble.linux.template_debug.x86_64.so`;
- iOS: статическая библиотека `.a`; упаковать в `.xcframework` командой
  `xcodebuild -create-xcframework -library bin/libovosch_ble.ios.template_release.a -output bin/libovosch_ble.ios.template_release.xcframework`.

## Подключение к проекту

Пока библиотек нет, файл `native/.gdignore` скрывает каталог от Godot — иначе движок при
открытии проекта сообщал бы об отсутствующих библиотеках для текущей платформы, а
`NativeBleBridge.is_native_available()` корректно возвращает `false` и приложение
работает на заглушке `StubBleBridge`. После сборки для целевой платформы:

1. удалите `native/.gdignore`;
2. откройте проект — Godot подхватит `native/ble/ovosch_ble.gdextension`;
3. `NativeBleBridge.is_native_available()` станет `true`, `TrainerFactory.create("ble")`
   вернёт `BleTrainer` поверх нативного моста.

## Контракт

Методы: `is_available`, `start_scan(service_uuids)`, `stop_scan`, `connect_peripheral(id)`,
`disconnect_peripheral(id)`, `discover_services(id)`, `subscribe(id, service, char)`,
`unsubscribe(id, service, char)`, `write(id, service, char, bytes, with_response)`,
`read_characteristic(id, service, char)`, `get_adapter_state`.
Сигналы: `adapter_state_changed(state)`, `device_found(id, name, rssi, service_uuids)`,
`connected(id)`, `disconnected(id, reason)`, `services_discovered(id, services)`,
`notification(id, char, bytes)`, `characteristic_read(id, char, bytes)`,
`write_done(id, char, ok)`, `error(id, code, message)`.
Коды `AdapterState`, `DisconnectReason`, `ErrorCode` — те же числа, что в `BleBridge`
(`ble_backend.h`). UUID передаются строками в любой форме; backend обязан принимать
короткую («2AD2») и полную форму.

Потокобезопасность: callbacks CoreBluetooth приходят не из главного потока; `OvoschBle`
испускает сигналы через `call_deferred`, поэтому GDScript получает их в главном потоке.
