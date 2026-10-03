# ovosch_ble — нативный BLE-мост (GDExtension)

Реализация контракта `BleBridge` (`src/devices/ble/ble_bridge.gd`) в виде класса
`OvoschBle : RefCounted`, который `NativeBleBridge` находит через
`ClassDB.class_exists("OvoschBle")`. Весь платформозависимый код живёт здесь
(REQ-NFR-06 крит. 2); игровая часть видит только GDScript-контракт.

## Структура

```
native/
  .gdignore              — каталог закрыт от Godot, пока библиотеки не собраны (см. ниже)
  ble/
    godot-cpp/           — клон godot-cpp (не в репозитории, см. «Зависимости»)
    SConstruct           — сборка на godot-cpp
    ovosch_ble.gdextension
    src/register_types.{h,cpp}
    src/ovosch_ble.{h,cpp}    — класс OvoschBle: методы и сигналы 1:1 с BleBridge
    src/ble_backend.h         — чистый C++ интерфейс платформенного backend'а
    src/null_backend.{h,cpp}  — заглушка (is_available() == false), собирается везде
    src/platform/apple/apple_backend.{h,mm} — CoreBluetooth-backend (T-022, Objective-C++, ARC)
```

## Зависимости

- Python 3 + SCons: `pip install scons`
- godot-cpp. Ветки godot-cpp соответствуют минорным версиям движка; на момент
  написания самая новая стабильная ветка — `4.5` (ветки `4.7` в апстриме ещё нет),
  расширение, собранное с ней, загружается в Godot ≥ 4.5 (`compatibility_minimum = 4.5`).
  Когда появится ветка `4.7`, замените её в командах ниже и в CI.

```sh
cd native/ble
git clone --depth 1 -b 4.5 https://github.com/godotengine/godot-cpp godot-cpp
```

Клон лежит **внутри `native/ble`** (`native/ble/godot-cpp`, в `.gitignore`): SConstruct ищет
его там по относительному пути, затем в `native/godot-cpp`; другой путь — `scons godot_cpp_path=…`.
Относительный путь важен: при `../godot-cpp` SCons делает пути объектов абсолютными, и линковка
`libgodot-cpp.a` падала на CI с «Argument list too long» (лимит 128 КБ на аргумент `sh -c`).

## Сборка

Сначала собирается godot-cpp **в своём каталоге**, затем расширение — так же устроены CI-jobs
`native-linux` и `native-macos`.

```sh
cd native/ble/godot-cpp
scons platform=linux   target=template_debug -j4     # один раз (кэшируется)
cd ..
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

Локальный клон godot-cpp внутри `native/ble` виден GUT-тестам как `res://native/ble/godot-cpp`;
архитектурные тесты это учитывают (сторонний код внутри `native/ble/`), но прогонять тесты
лучше без собранных артефактов — они в `.gitignore` и в репозиторий не попадают.

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

## macOS / iOS: CoreBluetooth-backend

`src/platform/apple/apple_backend.mm` реализует `BleBackend` поверх `CBCentralManager`
(macOS 10.13+/iOS 10+, без API новее macOS 12/iOS 15). SConstruct подхватывает его
автоматически для `platform=macos|ios`, определяет `OVOSCH_BLE_HAS_PLATFORM_BACKEND`,
линкует `CoreBluetooth` и `Foundation`, компилирует `.mm` с ARC.

Поведение:
- сканирование — `scanForPeripheralsWithServices:` с `AllowDuplicates = NO`; если адаптер ещё
  не `poweredOn`, запрос откладывается и стартует в `centralManagerDidUpdateState`;
- `is_available()` — состояние `poweredOn`; `adapter_state_changed` — из `didUpdateState`;
- идентификатор устройства — `peripheral.identifier.UUIDString`; `connect_peripheral` для
  запомненного id, не виденного в рекламе, пробует `retrievePeripheralsWithIdentifiers:`;
- `discover_services` — `discoverServices:nil`, затем `discoverCharacteristics:nil` для каждого
  сервиса; `services_discovered` приходит после последнего; UUID нормализованы как
  `BleUuids.normalize` (16-битные → `XXXX`);
- чтение и нотификация различаются по флагу ожидающего чтения на характеристике
  (`pendingReads`), поэтому `readValueForCharacteristic` даёт `characteristic_read`,
  а `setNotifyValue:YES` — `notification`;
- `write` без ответа (Write Command) подтверждения в CoreBluetooth не имеет —
  `write_done(ok=true)` отдаётся сразу после постановки;
- `disconnected(reason)`: `REQUESTED` для наших `cancelPeripheralConnection`, `TIMEOUT` для
  `CBErrorConnectionTimeout`, иначе `LINK_LOSS`/`ERROR`;
- все колбэки — на серийной очереди `ovosch.ble`; `OvoschBle` переправляет сигналы в главный
  поток через `call_deferred`.

### Info.plist и entitlements (только документация, настраивается в экспорте Godot)

- `NSBluetoothAlwaysUsageDescription` — обязателен на macOS 11+/iOS 13+ (без него приложение
  завершается при первом обращении к CoreBluetooth); для iOS ≤ 12 дополнительно
  `NSBluetoothPeripheralUsageDescription`.
- Sandbox / Mac App Store: entitlement `com.apple.security.device.bluetooth = true`.
- iOS, фоновая работа: `UIBackgroundModes` → `bluetooth-central`, если тренировка должна
  продолжаться при свёрнутом приложении. **Вопрос владельцу**: нужен ли фоновый режим
  (влияет на ревью App Store и энергопотребление); по умолчанию не включаем.
- Хранить тексты описаний в экспорт-пресетах Godot (`export_presets.cfg` в `.gitignore`) или
  в документации — не в репозитории с ключами.

### Сборка на macOS

```sh
cd native/ble
git clone --depth 1 -b 4.5 https://github.com/godotengine/godot-cpp godot-cpp
cd godot-cpp
scons platform=macos target=template_debug arch=universal     # сначала godot-cpp в своём каталоге
scons platform=macos target=template_release arch=universal
cd ..
scons platform=macos target=template_debug arch=universal     # или arch=arm64 / x86_64
scons platform=macos target=template_release arch=universal
```

Проверка в редакторе:
1. убедиться, что в `native/ble/bin/` появился `libovosch_ble.macos.template_debug.framework/`;
2. удалить `native/.gdignore`;
3. открыть проект в Godot 4.7 — в Output не должно быть ошибок GDExtension;
4. в консоли редактора: `print(ClassDB.class_exists("OvoschBle"))` → `true`;
   `print(NativeBleBridge.is_native_available())` → `true`;
5. запустить приложение, экран «Устройства» → «Сканировать»: при включённом Bluetooth Tacx Neo
   появляется в списке (REQ-DEV-01 крит. 5).

### Состояние проверки

Собрать Apple-backend в контейнере разработки нельзя (нет SDK). Единственная проверка компиляции
до появления macOS у владельца — CI job `native-macos` (`macos-latest`,
`scons platform=macos target=template_debug arch=arm64`), помеченный `continue-on-error: true`:
на приватном репозитории macOS-минуты могут быть недоступны, тогда job не стартует или падает —
это допустимо и не блокирует остальные проверки. Статическое соответствие контракту
(`OvoschBle` ⇔ `BleBridge`, `AppleBackend` ⇔ `BleBackend`) проверяет GUT-тест
`tests/unit/arch/test_native_contract.gd`.

## Сборка в CI и артефакт macOS

CI (`.github/workflows/ci.yml`) на каждый push:

1. `native-macos` — собирает фреймворк `libovosch_ble.macos.<target>.framework` для `template_debug`
   и `template_release`, `arch=universal` (x86_64 + arm64), с `Resources/Info.plist`
   (без него `codesign` не распознаёт бандл). Артефакты: `ovosch-ble-macos-<target>`.
2. `macos-app` — кладёт фреймворки в `native/ble/bin/`, снимает `native/.gdignore`, проверяет
   скриптом `scripts/ci/check_native_ble.gd`, что расширение загружается и `OvoschBle`
   совпадает с контрактом `BleBridge`, генерирует `export_presets.cfg`
   (`scripts/ci/make_export_presets.py`, Info.plist — из `platform/macos/Info.plist.template`)
   и экспортирует универсальное приложение с ad-hoc подписью. Артефакт: `ovosch-rider-macos`.

Запуск скачанной сборки на Mac: распаковать архив артефакта, затем `ovosch-rider-macos.zip`.
Сборка подписана ad-hoc и не нотаризована, поэтому Gatekeeper её блокирует. Снять карантин:

```sh
xattr -dr com.apple.quarantine ovosch-rider.app
open ovosch-rider.app
```

При первом подключении к станку macOS спросит разрешение на Bluetooth
(текст — `NSBluetoothAlwaysUsageDescription`). Для распространения нужна подпись Developer ID
и нотаризация — см. `docs/publishing/app_store_checklist.md`.
