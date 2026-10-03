# Порт на Android: BLE, разрешения, Google Play (REQ-NFR-06 крит. 4, REQ-NFR-07 крит. 3, 4; этап 9)

Общая схема — `docs/ports/README.md`. Заготовка манифеста — `platform/android/AndroidManifest.template.xml`.
Политика конфиденциальности — `docs/publishing/privacy_policy.md`, лицензии — `docs/publishing/licenses.md`.

## 1. Как подключить Android BLE API к контракту `BleBackend`

Android BLE доступен только из Java/Kotlin (`android.bluetooth.*`), а GDExtension-библиотека на Android
загружается движком через `dlopen`, поэтому `JNI_OnLoad` не вызывается, `JavaVM`/`Context` из C++ взять
нечем без хаков. Отсюда два варианта; **рекомендуется вариант A**.

**Вариант A — Godot Android plugin v2 (Kotlin) с тем же контрактом.**
`native/android/ble/` — Gradle-модуль, класс `OvoschBlePlugin : GodotPlugin` с `getPluginName() = "OvoschBle"`,
методами `@UsedByGodot` и сигналами `SignalInfo`, **имена и аргументы 1:1 с `OvoschBle`** из `native/ble/src/ovosch_ble.cpp`
(тот же список, что проверяет `test_native_contract.gd`). Внутри — Kotlin-реализация интерфейса, зеркального `BleBackend`
(`interface BleBackend { fun startScan(uuids: List<String>) … }`, `interface BleListener`), чтобы структура совпадала с C++.
GDScript-обёртка `NativeBleBridge` на Android берёт объект через `Engine.has_singleton("OvoschBle")` /
`Engine.get_singleton("OvoschBle")` (дополнение к `ClassDB.class_exists("OvoschBle")` — единственная правка в `src/`,
допустимая по REQ-NFR-06 крит. 1 и 5, т.к. `OvoschBle` упоминается только в `NativeBleBridge`). События плагина
`emitSignal(...)` уже доставляются в главный поток Godot — маршалинг делает движок.
Подключение: `addons/ovosch_ble_android/` с `EditorExportPlugin` (`_supports_platform` → Android,
`_get_android_libraries` → `.aar` из `native/android/ble/build/outputs/aar/`, `_get_android_manifest_element_contents`
или манифест внутри `.aar` → разрешения из шаблона).

**Вариант B — GDExtension `.so` + JNI.** Собрать `libovosch_ble.android.*.so` с бэкендом, который получает `JNIEnv`
через глобальный `JavaVM`, переданный из крошечного Kotlin-плагина (`System.loadLibrary` той же `.so`, чтобы сработал
`JNI_OnLoad`). Плюс — один C++ класс `OvoschBle` на всех платформах; минус — две библиотеки с одной `.so`, JNI-обвязка
вокруг `BluetoothGattCallback` (callbacks в Binder-потоках, `AttachCurrentThread`), сложная отладка. Оставить как запасной.

Соответствие методов контракта Android API (вариант A и B одинаково):

| `BleBackend` | Android | Примечания |
| --- | --- | --- |
| `set_listener` | сохранить ссылку; в варианте A роль listener'а играет сам плагин (`emitSignal`) | |
| `is_available` | `BluetoothAdapter.getDefaultAdapter() != null` && `PackageManager.hasSystemFeature(FEATURE_BLUETOOTH_LE)` | |
| `get_adapter_state` | `adapter.state` → `STATE_ON` = POWERED_ON, `STATE_OFF/TURNING_*` = POWERED_OFF; нет разрешений → UNAUTHORIZED | `BroadcastReceiver` на `ACTION_STATE_CHANGED` → `on_adapter_state_changed` |
| `start_scan(uuids)` | `BluetoothLeScanner.startScan(filters, settings, callback)`; `ScanFilter.Builder().setServiceUuid(ParcelUuid)` на каждый UUID; `ScanSettings.SCAN_MODE_LOW_LATENCY` | `onScanResult` → `on_device_found(address, name ?: "", rssi, scanRecord.serviceUuids)`; ограничение: >5 стартов за 30 с → система молча троттлит |
| `stop_scan` | `scanner.stopScan(callback)` | |
| `connect_peripheral(id)` | `adapter.getRemoteDevice(address).connectGatt(ctx, false, gattCallback, TRANSPORT_LE)` | `autoConnect=false`; `onConnectionStateChange(STATE_CONNECTED)` → `on_connected`; сразу `requestMtu(185)` для пакетов FTMS |
| `disconnect_peripheral` | `gatt.disconnect()` → в `onConnectionStateChange(DISCONNECTED)` → `gatt.close()` | `status != GATT_SUCCESS` при обрыве → `LINK_LOSS`, по запросу → `REQUESTED`; статус 133 — повторить connect один раз |
| `discover_services` | `gatt.discoverServices()` → `onServicesDiscovered` → `on_services_discovered` из `gatt.services` | |
| `subscribe` | `gatt.setCharacteristicNotification(ch, true)` + запись дескриптора CCCD `0x2902` (`ENABLE_NOTIFICATION_VALUE` или `INDICATION`, по свойствам характеристики) | ответ в `onDescriptorWrite`; ошибка → `SUBSCRIBE_FAILED` |
| `unsubscribe` | то же с `DISABLE_NOTIFICATION_VALUE` | |
| `write(..., with_response)` | API 33+: `gatt.writeCharacteristic(ch, bytes, WRITE_TYPE_DEFAULT / NO_RESPONSE)`; ниже — `ch.value = bytes; ch.writeType = …; gatt.writeCharacteristic(ch)` | `onCharacteristicWrite` → `on_write_done`; GATT допускает **одну** операцию за раз → очередь операций в бэкенде (общая для write/read/descriptor) |
| `read_characteristic` | `gatt.readCharacteristic(ch)` → `onCharacteristicRead(…, value, status)` → `on_characteristic_read` | через ту же очередь |
| уведомления | `onCharacteristicChanged(gatt, ch, value)` → `on_notification` | API 33+ передаёт `value`, старые — `ch.value` |

Особенности: все callback'и `BluetoothGattCallback` приходят в Binder-поток — не трогать UI, только `emitSignal`
(вариант A) или маршалинг (вариант B). Bonding для FTMS/HRS не нужен. Фильтр сканирования по UUID на части прошивок
не находит устройства с длинным advertisement — предусмотреть fallback «сканировать без фильтра и отбирать по UUID в коде».

## 2. Разрешения

| Разрешение | API | Зачем | Запрос |
| --- | --- | --- | --- |
| `BLUETOOTH_SCAN` (`usesPermissionFlags="neverForLocation"`) | 31+ | сканирование | runtime (группа Nearby devices) |
| `BLUETOOTH_CONNECT` | 31+ | подключение, имя устройства | runtime |
| `BLUETOOTH`, `BLUETOOTH_ADMIN` (`maxSdkVersion=30`) | ≤ 30 | legacy | install-time |
| `ACCESS_FINE_LOCATION` (`maxSdkVersion=30`) | 23–30 | без него `startScan` молча не возвращает результатов | runtime; объяснить пользователю, что геолокация не используется |
| `INTERNET` | все | Intervals.icu, Strava | install-time |
| `android.hardware.bluetooth_le` `required=true` | — | фильтр устройств в Play | — |

`neverForLocation` означает: приложение заявляет, что не выводит местоположение из BLE-сканирования; система
фильтрует beacons с location-данными, а Google Play не требует декларацию «Location» в Data safety и обоснование
доступа к геолокации на API 31+. На API ≤ 30 геолокация запрашивается технически, в Data safety это **не** сбор данных
о местоположении (данные не читаются и не передаются) — указать в примечаниях формы.

Runtime-запросы из GDScript (это единственное место платформенного кода вне `native/` — допустимо в `src/devices/ble/`):
`OS.request_permissions()` запрашивает все dangerous-разрешения из манифеста разом; точечно —
`OS.request_permission("android.permission.BLUETOOTH_SCAN")`, результат — сигнал `MainLoop.on_request_permissions_result`;
проверка — `OS.get_granted_permissions()`. Логика: перед `start_scan` проверить разрешения → если нет, запросить → отказ →
состояние `UNAUTHORIZED` и сообщение «Bluetooth недоступен» (REQ-DEV-01 крит. 7, тот же путь, что `POWERED_OFF`).
Экран устройств должен объяснить, зачем нужен доступ к «устройствам поблизости»/геолокации до запроса (требование Play
«prominent disclosure» относится к геолокации на API ≤ 30).

## 3. Целевой API level и совместимость

- Google Play требует, чтобы новые приложения и обновления целились в API не старше года от последнего major-релиза
  Android; на октябрь 2026 это **targetSdk 36 (Android 16)** — проверять актуальное требование в Play Console → Policy status.
  Экспортные шаблоны Godot 4.7 собраны под совместимый `targetSdk`; при расхождении — Gradle-сборка с переопределением
  `targetSdkVersion` в `android/build/config.gradle`.
- `minSdk` — **24** (Android 7): ниже — нет смысла (нет BLE-устройств такого возраста у аудитории), и `writeCharacteristic`
  без `value` в API < 24 нестабилен. Если владелец согласится на `minSdk = 31`, legacy-блок разрешений и ветка `ACCESS_FINE_LOCATION`
  исчезают — упрощает Data safety; решение владельца.
- ABI: `arm64-v8a` обязательно (Play требует 64-bit), `armeabi-v7a` — по желанию; x86_64 — только для эмулятора.
- Формат поставки — AAB (App Bundle), подпись — Play App Signing; upload key хранится вне репозитория.

## 4. Google Play: Data safety и декларации

Форма Play Console → App content → Data safety (основание — `privacy_policy.md`):

| Категория | Тип | Собирается / передаётся | Обязательно? | Обработка | Назначение |
| --- | --- | --- | --- | --- | --- |
| Health and fitness | Health info (пульс) | собирается — только при выгрузке в Strava; передаётся третьей стороне по действию пользователя | опционально (пользователь может не подключать Strava) | шифруется при передаче; удаляется по запросу (удаление профиля/отвязка) | App functionality |
| Health and fitness | Fitness info (мощность, каденс, скорость, длительность) | то же; план из Intervals.icu — чтение в приложение | опционально | то же | App functionality |
| Files and docs | файлы тренировок (импорт) | обрабатываются только на устройстве → **не собираются** | — | — | — |
| Personal info | имя профиля | только на устройстве → не собирается | — | — | — |
| App activity, App info and performance, Device or other IDs, Location, Contacts, Financial, Messages, Photos, Audio | — | **нет** | — | — | — |

Google определяет «collected» как передачу с устройства; передача третьей стороне по явному действию пользователя
формально подпадает под исключение из «sharing», но данные о здоровье лучше задекларировать явно (консервативно) и описать
в примечании: «uploaded only to the user's own Strava account on user action». Указать: данные шифруются в пути (HTTPS),
пользователь может запросить удаление (удаление профиля в приложении; данные в Strava — средствами Strava), приложение
не передаёт данные для рекламы/аналитики.

Другие декларации Play Console:
- **Health apps** (Health Content and Services): объявить функции «Fitness and wellness → Activity/workout tracking»
  и «Health monitoring → heart rate (от внешнего датчика)». Приложение не медицинское, диагнозов не ставит — не выбирать «Medical».
- **Privacy policy URL** — обязателен (тот же, что для App Store).
- **Account deletion** — не применимо: приложение не создаёт аккаунтов (профили локальные). Если появится облачная синхронизация — пересмотреть.
- **Permissions declaration**: для `ACCESS_FINE_LOCATION` (API ≤ 30) Play может запросить объяснение → «required by Android for BLE scanning on Android 11 and below, location is not used»;
  для `BLUETOOTH_SCAN` с `neverForLocation` декларация не требуется.
- **Target audience** — 18+ или 13+ без детской аудитории (упрощает Families policy); **Content rating** (IARC) — анкета даёт «Everyone»/PEGI 3.
- **Ads** — нет. **App category** — Health & Fitness.
- **Open source notices** — экран «О программе» (`licenses.md`).

## 5. Фоновая запись — вопрос владельцу

На Android при выключенном экране процесс может быть приостановлен (Doze), BLE-соединение сохраняется, но данные 1 Гц
теряются. Варианты:
1. **Не поддерживать** фон (как и на iOS по умолчанию): REQ-NFR-04 держит экран включённым во время тренировки (`DisplayServer.screen_set_keep_on`);
   пользователь не блокирует телефон. Проще всего для ревью. — рекомендация по умолчанию.
2. **Foreground service** типа `connectedDevice` (`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE` на API 34+, уведомление с
   таймером тренировки, `POST_NOTIFICATIONS` на API 33+): GATT-соединение и поток данных живут в сервисе плагина, Godot-активность может уйти в фон.
   Требует: сервис в плагине, передача буфера сэмплов в активность при возврате, декларация foreground service в Play Console с видео.
   Это существенная работа в `native/android/` и в `SampleStream` (догон пропущенных секунд).

Решение зафиксировать в `docs/backlog.md`; шаблон манифеста содержит закомментированный блок для варианта 2.

## 6. Структура `native/android/` и сборка

```
native/android/
  settings.gradle, build.gradle          — Gradle (AGP версии, совместимой с экспортом Godot 4.7)
  ble/
    build.gradle                         — com.android.library, зависимость godot-lib (из экспортных шаблонов, compileOnly)
    src/main/AndroidManifest.xml         — из platform/android/AndroidManifest.template.xml (без <activity>-части, если она идёт через пресет)
    src/main/kotlin/.../OvoschBlePlugin.kt, BleBackend.kt, AndroidBleBackend.kt, GattQueue.kt
    src/androidTest/                     — instrumented-тесты очереди GATT на эмуляторе без BLE (моки) — минимум
  secure/                                — Keystore-бэкенд SecureStore (docs/secure_store.md), та же схема
addons/ovosch_ble_android/plugin.cfg, export_plugin.gd — регистрация .aar в экспорте
```

CI: job `android` на `ubuntu-latest` с Android SDK — `./gradlew :ble:assembleRelease`, артефакт `.aar`; сборка `.so` для варианта B — `scons platform=android arch=arm64`
с NDK. Проверка в контейнере ограничена компиляцией; всё остальное — `[вне контейнера]`.

## 7. Что остаётся `[вне контейнера]` — шаги владельца

| Критерий | Шаг |
| --- | --- |
| REQ-NFR-06 крит. 4 (порт) | реализовать плагин по разделу 1, прогнать ручные проверки `docs/backlog.md` → «Ручные проверки» на Android-устройстве с Tacx Neo |
| REQ-NFR-07 крит. 3 | убедиться, что итоговый `AndroidManifest.xml` в AAB содержит разрешения из шаблона (`aapt2 dump permissions`) и диалоги запрашиваются на API 31+ и на API 30 |
| REQ-NFR-07 крит. 4 (Google Play) | заполнить Data safety, Health apps, Content rating, Privacy policy по разделу 4 |
| REQ-NFR-07 крит. 5 | пройти ревью Google Play (internal testing → closed testing с 12 тестировщиками 14 дней — требование для новых личных аккаунтов разработчика → production) |
| REQ-NFR-05 крит. 3 (Keystore) | `native/android/secure/` по `docs/secure_store.md` |
| REQ-STR-01 крит. 7 (схема `ovoschrider://`) | проверить возврат из Chrome Custom Tab в приложение; на Android 12+ для `https`-ссылок нужен App Links — для custom scheme не нужен |
| Вопрос раздела 5 | решение о фоновой записи |
