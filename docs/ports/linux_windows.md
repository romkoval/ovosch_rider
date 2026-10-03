# Порты на Linux и Windows: BlueZ, WinRT, каналы распространения (REQ-NFR-06 крит. 4; этап 10)

Общая схема — `docs/ports/README.md`: по одному бэкенду `ovosch::BleBackend` на платформу внутри того же
GDExtension `OvoschBle` (`native/ble/src/platform/linux/`, `native/ble/src/platform/windows/`). Пути библиотек
`linux.*.x86_64` и `windows.*.x86_64` уже прописаны в `native/ble/ovosch_ble.gdextension`; сейчас на этих платформах
собирается `NullBackend` (`is_available() == false`).

## 1. Linux — BlueZ через D-Bus

Единственный поддерживаемый BlueZ API для приложений — D-Bus (`org.bluez`, системная шина). Библиотека: **sdbus-c++**
(C++17, вендорить как submodule или использовать системную) либо GDBus из GLib; libdbus-1 напрямую — многословно.
D-Bus-цикл крутится в рабочем потоке бэкенда, события отдаются в `BleListener` (маршалинг в главный поток — в `OvoschBle`).

| `BleBackend` | BlueZ D-Bus | Примечания |
| --- | --- | --- |
| `set_listener` | сохранить ссылку; вызывать из потока D-Bus-цикла | |
| `is_available` | `org.freedesktop.DBus.ObjectManager.GetManagedObjects` на `/` содержит объект с `org.bluez.Adapter1` | нет службы `org.bluez` → false |
| `get_adapter_state` | свойство `Adapter1.Powered` → POWERED_ON/OFF; нет адаптера → UNSUPPORTED | `PropertiesChanged` на `Powered` → `on_adapter_state_changed` |
| `start_scan(uuids)` | `Adapter1.SetDiscoveryFilter({UUIDs: [...], Transport: "le", DuplicateData: true})` → `StartDiscovery` | устройства — `InterfacesAdded` с `org.bluez.Device1` и `PropertiesChanged` (`RSSI`, `Name`, `UUIDs`, `ServiceData`) → `on_device_found(path→MAC, Name/Alias, RSSI, UUIDs)` |
| `stop_scan` | `Adapter1.StopDiscovery` | `id` = `Device1.Address` (MAC); путь объекта `/org/bluez/hciX/dev_XX_XX_…` восстанавливается из MAC |
| `connect_peripheral` | `Device1.Connect` (асинхронно) | `Connected = true` → ждать `ServicesResolved = true`, затем `on_connected`; `org.bluez.Error.Failed` → `CONNECTION_FAILED` |
| `disconnect_peripheral` | `Device1.Disconnect` | `Connected = false` → `on_disconnected(REQUESTED|LINK_LOSS)` по тому, был ли запрос |
| `discover_services` | обход объектов `GattService1` (`Device` = путь устройства) и `GattCharacteristic1` (`Service`) из `GetManagedObjects` | BlueZ резолвит сервисы при подключении — ответ синтезируется сразу после `ServicesResolved` |
| `subscribe` / `unsubscribe` | `GattCharacteristic1.StartNotify` / `StopNotify` | данные — `PropertiesChanged` свойства `Value` → `on_notification`; BlueZ ≥ 5.51 с `AcquireNotify` — быстрее (fd), опционально |
| `write(..., with_response)` | `GattCharacteristic1.WriteValue(bytes, {type: "request"|"command"})` | `request` = with response; ответ метода → `on_write_done` |
| `read_characteristic` | `GattCharacteristic1.ReadValue({})` | ответ метода → `on_characteristic_read` (не путать с `PropertiesChanged Value`, который тоже придёт — отличать по ожидающему чтению) |
| ошибки | `org.bluez.Error.*` (`NotReady`, `InProgress`, `NotPermitted`, `NotSupported`, `Failed`) → `ErrorCode` | |

Нюансы: кэш устройств BlueZ хранит «несвежие» устройства — фильтровать `on_device_found` по наличию `RSSI` в сессии;
удалённые адаптером устройства — `InterfacesRemoved`. Повторное `StartDiscovery` во время сканирования → `InProgress` (игнорировать).
Права: по умолчанию политика D-Bus BlueZ разрешает обычным пользователям всё нужное; Flatpak — `--system-talk-name=org.bluez`;
Snap — plug `bluez`; Steam Runtime — `libdbus` есть, sdbus-c++ линковать статически. Steam Deck: BlueZ присутствует, Game Mode не мешает.
Сборка: `scons platform=linux` уже есть в CI (`native-linux`), добавить ветку с `OVOSCH_BLE_HAS_PLATFORM_BACKEND` и `-lsystemd`/sdbus-c++.

## 2. Windows — WinRT Bluetooth LE

API: `Windows.Devices.Bluetooth` и `Windows.Devices.Bluetooth.GenericAttributeProfile` через **C++/WinRT** (header-only,
Windows SDK ≥ 10.0.17763; поддержка Windows 10 1809+). Асинхронные операции (`IAsyncOperation`) — `co_await` в корутинах либо `.get()`
в рабочем потоке бэкенда; callback'и приходят в потоки пула — отдаём в `BleListener`.

| `BleBackend` | WinRT | Примечания |
| --- | --- | --- |
| `set_listener` | сохранить ссылку; вызывать из потоков пула WinRT | |
| `is_available` | `BluetoothAdapter.GetDefaultAsync()` не null и `IsLowEnergySupported` | |
| `get_adapter_state` | `Radio.GetRadiosAsync()` → радио типа Bluetooth, `State == On` → POWERED_ON | `Radio.StateChanged` → `on_adapter_state_changed`; доступ к `Radio` требует capability `radios` только для управления, чтение свободно |
| `start_scan(uuids)` | `BluetoothLEAdvertisementWatcher` с `ScanningMode = Active`; фильтр `AdvertisementFilter.Advertisement.ServiceUuids` — один UUID на watcher, либо без фильтра и отбор в `Received` | `Received` → `on_device_found(hex(BluetoothAddress), LocalName, RawSignalStrengthInDBm, ServiceUuids)`; имя часто пустое в advertisement — брать из `BluetoothLEDevice.Name` после подключения |
| `stop_scan` | `watcher.Stop()` | |
| `connect_peripheral(id)` | `BluetoothLEDevice.FromBluetoothAddressAsync(addr)` → `GetGattServicesAsync(Uncached)` (фактическое подключение) | `ConnectionStatusChanged` → `on_connected` / `on_disconnected(LINK_LOSS)`; WinRT держит соединение, пока живы объекты `GattCharacteristic` с подпиской |
| `disconnect_peripheral` | нет явного метода: `Close()` на `BluetoothLEDevice` и всех `GattDeviceService`, сброс ссылок → система разрывает связь | синтезировать `on_disconnected(REQUESTED)` |
| `discover_services` | `GetGattServicesAsync` → для каждого `GetCharacteristicsAsync` | `GattCommunicationStatus != Success` → `SERVICE_NOT_FOUND` |
| `subscribe` | `WriteClientCharacteristicConfigurationDescriptorAsync(Notify|Indicate)` + `ValueChanged` | `ValueChanged` → `on_notification`; `unsubscribe` — `None` и отписка события |
| `write(..., with_response)` | `WriteValueWithResultAsync(buffer, WriteWithResponse|WriteWithoutResponse)` | `Status` → `on_write_done` |
| `read_characteristic` | `ReadValueAsync(BluetoothCacheMode.Uncached)` | → `on_characteristic_read` |
| ошибки | `GattCommunicationStatus` (`Unreachable`, `ProtocolError`, `AccessDenied`) → `ErrorCode` | `AccessDenied` на Windows 11 — нет разрешения Bluetooth в настройках приватности (десктоп-приложения по умолчанию разрешены) |

Сборка: C++/WinRT требует MSVC или clang-cl; **MinGW не подходит** (нет заголовков WinRT), поэтому CI-job `windows-latest`
с `scons platform=windows use_mingw=no`, линк `windowsapp.lib`. Для Microsoft Store (MSIX) в `Package.appxmanifest` —
`<DeviceCapability Name="bluetooth"/>` и `<Capability Name="internetClient"/>`; без MSIX capabilities не нужны.
Для unpackaged-приложения нет диалога разрешения Bluetooth — но Windows 11 позволяет пользователю запретить Bluetooth
для десктоп-приложений в Settings → Privacy, тогда `AccessDenied` → показывать «Bluetooth недоступен» (REQ-DEV-01 крит. 7).

## 3. Общее для обоих портов

- `id` устройства — MAC/адрес. Приватные (resolvable) адреса меняются — для REQ-DEV-06 держать fallback по имени (см. `docs/ports/README.md`).
- Хранилище секретов: libsecret / Credential Manager — `docs/secure_store.md`, разделы 3; при недоступности — `EncryptedFileSecureStore`.
- OAuth redirect — loopback-сервер уже реализован (В-6); на Linux в Flatpak нужен `--share=network`, на Windows брандмауэр
  не спрашивает о прослушивании `127.0.0.1`.
- Экран не гаснет (REQ-NFR-04): `DisplayServer.screen_set_keep_on` работает на Windows; на Linux под Wayland требует портала
  `org.freedesktop.portal.Inhibit` — Godot 4.x делает это сам при наличии портала; проверить на Steam Deck.
- Ручные проверки — `docs/backlog.md`, «Ручные проверки владельца», на Tacx Neo с Linux-ноутбуком и Windows-ПК.
- Тест контракта `test_native_contract.gd` дополняется файлами `linux_backend.cpp`/`windows_backend.cpp`.

## 4. Каналы распространения Linux и Windows — открытый вопрос владельца (ТЗ раздел 8)

ТЗ оставляет выбор открытым: Steam, Flathub, Microsoft Store или прямая загрузка. Ниже — сравнение без решения; выбор
фиксирует владелец (можно несколько каналов, они не исключают друг друга).

| Критерий | Steam (Linux + Windows) | Flathub (Linux) | Microsoft Store (Windows) | Прямая загрузка (сайт/GitHub Releases) |
| --- | --- | --- | --- | --- |
| Аудитория | большая, но игровая; велотренировки — нишевый запрос, Steam Deck как «ТВ-приставка у станка» — реальный сценарий | Linux-пользователи, SteamOS Desktop Mode, Discover/GNOME Software | пользователи Windows 10/11, поиск в Store | все; нужен собственный сайт и продвижение |
| Стоимость входа | $100 за Steam Direct (возвращаемая после $1000 продаж), ревью сборки 1–5 дней | бесплатно, ревью PR в flathub/ репозиторий (дни) | $19 разово за аккаунт, сертификация 1–3 дня | бесплатно; code-signing сертификат для Windows (OV ~$200/год или Azure Trusted Signing ~$10/мес), иначе SmartScreen-предупреждения |
| Монетизация (открытый вопрос ТЗ) | встроенная: разовая покупка, DLC; подписки нет; комиссия 30 % | нет; донаты/внешняя оплата; бесплатное приложение | разовая покупка, подписка, пробный период; комиссия 12 % (приложения) | любая: Paddle/Gumroad/лицензионный ключ; комиссия платёжки |
| Обновления | автоматически, дельта-патчи, ветки beta | автоматически через Flatpak | автоматически | нужен свой механизм проверки версии или ручная загрузка |
| BLE | Steam Runtime (Linux): sdbus-c++ статически, D-Bus доступен; Windows — без ограничений | `--system-talk-name=org.bluez` в манифесте, Flathub одобряет при обосновании | MSIX с `bluetooth` capability; WinRT в sandbox работает | без ограничений |
| Секреты (`SecureStore`) | Linux: keyring может отсутствовать в Game Mode → fallback-файл; Windows: Credential Manager | `--talk-name=org.freedesktop.secrets` или portal Secret | `PasswordVault`/Credential Manager | Credential Manager / libsecret |
| Ограничения контента/лицензий | нет требований к открытости; нужны магазинные ассеты (капсулы 6 размеров), возрастная анкета | предпочтительно open source; проприетарное — через `extra-data` или прямой бинарь с лицензией в AppStream `project_license`; требования к metainfo, иконкам, скриншотам | политики Store (10.x), приватность данных о здоровье — анкета | только закон и собственная политика |
| Удобство для владельца | один канал на обе ОС; Steamworks SDK необязателен | только Linux; манифест + metainfo | только Windows; MSIX-упаковка Godot-экспорта (`makeappx`, подпись) | минимум бюрократии, максимум ручной работы |
| Минусы | игровая витрина для неигрового приложения; 30 %; пользователи без Steam-аккаунта | нет монетизации; sandbox-ограничения | malware-сканер иногда задерживает GDExtension-dll; требования к MSIX | доверие и обнаружимость; SmartScreen; нет автообновлений |

Критерии для решения, которые стоит взвесить владельцу:
1. Модель монетизации (бесплатно / разовая / подписка) — Flathub отпадает для платной модели, Steam — для подписки.
2. Нужна ли единая точка для macOS/iOS/Android/Linux/Windows пользователя (синхронизация профилей — тоже открытый вопрос): если да, прямая загрузка + свой сайт
   проще согласуется с лицензионной моделью «одна покупка — все платформы».
3. Steam Deck как целевое устройство у станка — сильный аргумент за Steam (контроллер, Game Mode, экран 16:10 ландшафт).
4. Трудоёмкость: Flathub и Microsoft Store требуют отдельных упаковочных заготовок (`platform/linux/flatpak/`, `platform/windows/msix/`) — добавить после решения.

Решение заносится в `docs/tz.md`→«Открытые вопросы» (владельцем) и в `docs/backlog.md`; до этого этап 10 ограничивается бэкендами BLE и прямой загрузкой для тестирования.

## 5. Что остаётся `[вне контейнера]`

| Критерий | Шаг владельца |
| --- | --- |
| REQ-NFR-06 крит. 4 (порты) | бэкенды по разделам 1–2, CI-jobs `linux`/`windows-msvc`, ручные проверки с Tacx Neo |
| REQ-NFR-05 крит. 3 (libsecret / Credential Manager) | `docs/secure_store.md` раздел 3 |
| REQ-DEV-01 крит. 5–7 на Linux/Windows | Neo в списке ≤ 5 с; `AccessDenied`/нет `org.bluez` → «Bluetooth недоступен» |
| Открытый вопрос ТЗ | выбрать канал(ы) по таблице раздела 4, затем заготовки упаковки и лицензии приложения (`licenses.md` раздел 3) |
