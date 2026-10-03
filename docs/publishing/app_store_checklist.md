# Чеклист публикации в App Store и Mac App Store (REQ-NFR-07, REQ-IMP-03 крит. 3, этап 8)

Что должно быть сделано владельцем вне контейнера, чтобы сборки iOS и macOS прошли ревью.
Заготовки Info.plist и entitlements — в `platform/` (см. `platform/README.md`), политика —
`docs/publishing/privacy_policy.md`, лицензии — `docs/publishing/licenses.md`.
Пункты с `[ ]` — чеклист владельца; `[авто]` — проверяется тестом
`tests/unit/arch/test_publishing_docs.gd`.

## 1. Учётные записи и идентификаторы

- [ ] Apple Developer Program (индивидуальный или организация; для организации нужен D-U-N-S).
- [ ] Bundle ID зарегистрирован в Certificates, Identifiers & Profiles: один для iOS, один для macOS
      (рекомендация: `<BUNDLE_ID_PREFIX>.ovoschrider` и `<BUNDLE_ID_PREFIX>.ovoschrider.mac`, либо один
      общий ID, если планируется Universal Purchase). Capabilities на ID не нужны: CoreBluetooth
      capability не требует включения в портале; App Sandbox — только entitlement в бинарнике.
- [ ] Записи приложения в App Store Connect (iOS и macOS отдельно или одна запись при Universal Purchase).
- [ ] Сертификаты: `Apple Distribution` (оба магазина), provisioning profile `App Store` для iOS;
      для macOS — `Mac App Distribution` + `Mac Installer Distribution` (подпись `.pkg`), если
      экспорт идёт не через Xcode Organizer.

## 2. App Privacy («Nutrition label», App Store Connect → App Privacy)

Основание — `privacy_policy.md`: у приложения нет серверов и аналитики; данные покидают
устройство только в Intervals.icu и Strava по действию пользователя. Apple считает «собранными»
данные, переданные с устройства приложением (в т.ч. третьей стороне), поэтому выгрузку в Strava
декларируем консервативно. Ответ на вопрос «Do you or your third-party partners collect data?» — **Yes**.

| Категория Apple | Тип данных | Собирается? | Linked to user | Used for tracking | Purpose |
| --- | --- | --- | --- | --- | --- |
| **Health & Fitness** | Health (пульс) | Да — только при выгрузке в Strava | Да (аккаунт Strava пользователя) | Нет | App Functionality |
| **Health & Fitness** | Fitness (мощность, каденс, скорость, длительность) | Да — при выгрузке в Strava; план из Intervals.icu — чтение | Да | Нет | App Functionality |
| User Content | Other User Content (файл заезда FIT, название заезда) | Да — при выгрузке в Strava | Да | Нет | App Functionality |
| Identifiers | User ID, Device ID | **Нет** | — | — | — |
| Usage Data | Product Interaction, Advertising Data, Other | **Нет** | — | — | — |
| Diagnostics | Crash Data, Performance Data | **Нет** (нет crash-репортинга; системные отчёты Apple не декларируются) | — | — | — |
| Location | — | **Нет** (Bluetooth без геолокации) | — | — | — |
| Contact Info, Financial Info, Purchases, Browsing/Search History, Contacts, Sensitive Info | — | **Нет** | — | — | — |

Пояснения для ревью:
- Профиль (имя, FTP, вес) хранится только локально → не «collected». Если появится синхронизация
  между устройствами (открытый вопрос ТЗ), таблицу пересмотреть.
- Athlete ID и API-ключ Intervals.icu передаются только самому Intervals.icu как учётные данные
  к аккаунту пользователя. Позиция: это не идентификатор, собираемый нами. Если ревьюер потребует —
  добавить Identifiers → User ID, Linked, Not tracking, App Functionality.
- «Tracking» по определению Apple (связывание с данными других компаний для рекламы) — нет;
  `NSUserTrackingUsageDescription` и App Tracking Transparency не нужны.
- Privacy Policy URL — обязателен; указать адрес опубликованного `privacy_policy.md`.
- Privacy manifest (`PrivacyInfo.xcprivacy`) для iOS: Godot ≥ 4.3 генерирует его из настроек пресета
  (`privacy/*`). Для приложения указать `NSPrivacyTracking = false`, `NSPrivacyCollectedDataTypes` —
  те же категории, что в таблице; `NSPrivacyAccessedAPITypes` — то, что экспортер подставит сам
  (file timestamps, user defaults). Сверить, что сторонних SDK с собственными manifest нет.

## 3. Разрешения и тексты (Info.plist)

- [ ] `NSBluetoothAlwaysUsageDescription` — обязателен для iOS 13+ и macOS 11+ при использовании
      CoreBluetooth; без него приложение падает при создании `CBCentralManager`. `[авто]` — наличие
      ключа в `platform/ios/Info.plist.template` и `platform/macos/Info.plist.template`.
      Текст (en — значение по умолчанию, ru — через `InfoPlist.strings` для `ru.lproj`):
      - en: `ovosch-rider uses Bluetooth to connect to your smart trainer and to heart-rate, cadence and power sensors.`
      - ru: `ovosch-rider использует Bluetooth для подключения к велостанку и датчикам пульса, каденса и мощности.`
- [ ] `NSBluetoothPeripheralUsageDescription` — устаревший ключ (iOS ≤ 12); добавить тот же текст,
      если `min_ios_version` < 13 (рекомендация — минимум iOS 15, тогда ключ не нужен).
- [ ] Не добавлять `NSHealthShareUsageDescription`/`NSHealthUpdateUsageDescription`: HealthKit не
      используется; наличие ключа без использования — повод для вопросов на ревью.
- [ ] `UIBackgroundModes` → `bluetooth-central` — **вопрос владельцу**: нужен только если тренировка
      должна продолжать запись с погашенным экраном. По REQ-NFR-04 экран не гаснет во время тренировки,
      поэтому по умолчанию режим не включаем (фоновый BLE требует обоснования на ревью).
- [ ] `CFBundleURLTypes` со схемой `ovoschrider` (redirect Strava `ovoschrider://strava`, решение В-6).
- [ ] `CFBundleDocumentTypes` + `UTExportedTypeDeclarations` для `.zwo`, `.erg`, `.mrc` (REQ-IMP-03 крит. 3):
      «Открыть в…» на iOS и двойной клик на macOS. `LSSupportsOpeningDocumentsInPlace = NO`
      (файл копируется в контейнер приложения, что и нужно для импорта).
- [ ] `ITSAppUsesNonExemptEncryption = NO` — приложение использует только стандартный HTTPS
      (освобождённая категория), это снимает вопрос экспортного соответствия при каждой загрузке в TestFlight.
- [ ] `LSApplicationCategoryType = public.app-category.healthcare-fitness` (macOS).

## 4. Entitlements (macOS, Mac App Store)

Mac App Store принимает только приложения с App Sandbox. Заготовка —
`platform/macos/entitlements.template.plist`. `[авто]` — наличие `com.apple.security.device.bluetooth`.

| Entitlement | Значение | Зачем |
| --- | --- | --- |
| `com.apple.security.app-sandbox` | true | обязателен для Mac App Store |
| `com.apple.security.device.bluetooth` | true | CoreBluetooth внутри sandbox |
| `com.apple.security.network.client` | true | HTTPS к Intervals.icu и Strava |
| `com.apple.security.network.server` | true | loopback-приём redirect OAuth `http://127.0.0.1:<port>/callback` (В-6): прослушивание порта в sandbox требует этого entitlement |
| `com.apple.security.files.user-selected.read-only` | true | импорт `.zwo/.erg/.mrc` через системный диалог |
| `com.apple.security.files.user-selected.read-write` | true | сохранение FIT «Сохранить как…» (REQ-LOC-05); заменяет read-only, оба держать не нужно |
| `com.apple.security.cs.disable-library-validation` | **не включать** | GDExtension подписывается тем же Team ID, валидация библиотек не мешает |

Для сборки вне Mac App Store (прямая загрузка, Developer ID) sandbox не обязателен, но нужны
Hardened Runtime и нотаризация; Bluetooth-entitlement при этом не требуется.

## 5. Категория, рейтинг, метаданные

- [ ] Primary category: **Health & Fitness**; secondary — Sports.
- [ ] Возрастной рейтинг: анкета даёт **4+** (нет контента для ограничений). В вопросе
      «Medical/Treatment Information» — None: приложение не даёт медицинских рекомендаций.
      «Unrestricted Web Access» — No (встроенного браузера нет; OAuth открывается в системном браузере).
- [ ] Описание: не использовать слова «медицинский», «диагностика»; пульс — «показатель тренировки».
- [ ] Упоминание Strava в описании/скриншотах — по брендбуку (`strava_api_checklist.md`).
- [ ] Поддержка: URL страницы поддержки и контакт (можно тот же, что в политике).
- [ ] Review notes для Apple: как проверить без велостанка — демо-режим с `FakeTrainer`
      (ревьюер не имеет Tacx Neo); описать, что Bluetooth-экран покажет пустой список без устройств.
      Для Strava/Intervals.icu — тестовые аккаунты не передавать (секреты), указать, что функции
      необязательны.

## 6. Скриншоты (App Store Connect → Media Manager)

Актуальные размеры — «Screenshot specifications» в App Store Connect Help; на момент написания:

| Устройство | Обязательно | Размеры (px, портрет/ландшафт) |
| --- | --- | --- |
| iPhone 6.9" (15 Pro Max и новее) | да, если есть iPhone-сборка | 1320×2868 / 2868×1320 (принимаются и 1290×2796) |
| iPhone 6.5" | опционально (масштабируется из 6.9") | 1284×2778 / 1242×2688 |
| iPad 13" | да, если `TARGETED_DEVICE_FAMILY` включает iPad | 2064×2752 / 2752×2064 |
| Mac | да для Mac App Store | 1280×800, 1440×900, 2560×1600 или 2880×1800 (16:10) |

Экраны для набора: HUD тренировки с зонами, 3D-сцена, список устройств (с подключённым станком),
план из Intervals.icu, история заездов. Тренировка должна быть в ландшафте — снимать ландшафт.
Не показывать чужие бренды кроме Strava по брендбуку; имена профилей — вымышленные.

## 7. Требования к `export_presets.cfg` (iOS и macOS)

Файл содержит Team ID, идентификаторы профилей и путь к сертификатам — **в репозиторий не коммитится**
(`.gitignore`, `[авто]`). Владелец создаёт его локально в редакторе Godot 4.7 (Project → Export).
Имена опций — по документации Godot «Exporting for iOS»/«Exporting for macOS»; сверять с версией редактора.

Пресет **iOS**:
- [ ] `application/bundle_identifier` = `<BUNDLE_ID_IOS>`, `application/team_id`, `application/short_version`, `application/version`.
- [ ] `application/export_method_release` = App Store; `code_sign_identity_release` / `provisioning_profile_specifier_release`.
- [ ] `application/min_ios_version` ≥ 15.0 (тогда достаточно `NSBluetoothAlwaysUsageDescription`).
- [ ] `application/additional_plist_content` — содержимое `platform/ios/Info.plist.template` между маркерами
      `<!-- ADDITIONAL_PLIST_CONTENT_BEGIN/END -->` (Bluetooth-описание, URL-схема, типы документов, `ITSAppUsesNonExemptEncryption`).
- [ ] `privacy/*` (privacy manifest) — tracking off, собранные типы данных как в разделе 2.
- [ ] `user_data/accessible_from_files_app` = true (экспорт FIT виден в «Файлах»), `accessible_from_itunes_sharing` — по желанию.
- [ ] Иконки всех размеров и launch screen; ориентация — landscape для тренировки (или все, если UI поддерживает).
- [ ] Исключить из экспорта `addons/gut/*`, `tests/*`, `docs/*`, `native/**/*.cpp|.h|.mm`, `platform/*` (фильтр ресурсов пресета).
- [ ] `native/.gdignore` удалён после сборки `libovosch_ble.ios.*.xcframework` (см. `native/ble/README.md`).

Пресет **macOS**:
- [ ] `application/bundle_identifier` = `<BUNDLE_ID_MACOS>`, версия, `application/min_macos_version` ≥ 12.0, `application/export_angle` — по умолчанию.
- [ ] Distribution type = **App Store**; `codesign/codesign` = Xcode codesign (или rcodesign); `codesign/identity` = `3rd Party Mac Developer Application: ...`;
      `codesign/installer_identity` = `3rd Party Mac Developer Installer: ...`; `codesign/provisioning_profile` — профиль Mac App Store.
- [ ] Entitlements: либо встроенные опции `codesign/entitlements/app_sandbox/enabled`, `device_bluetooth`, `network_client`, `network_server`,
      `files_user_selected` = read-write, либо `codesign/entitlements/custom_file` = путь к файлу, собранному из `platform/macos/entitlements.template.plist`.
- [ ] `application/additional_plist_content` — из `platform/macos/Info.plist.template` (Bluetooth, URL-схема, типы документов, категория).
- [ ] `notarization/notarization` = Disabled для Mac App Store (нотаризация нужна только для Developer ID).
- [ ] Иконка `.icns`; та же фильтрация ресурсов, что и для iOS; `native/.gdignore` удалён после сборки `.framework`.

## 8. TestFlight

1. Собрать iOS-экспорт из Godot (Xcode-проект), открыть в Xcode, Product → Archive → Distribute → App Store Connect → Upload
   (или загрузить `.ipa` через Transporter). Для macOS — экспорт `.pkg` из Godot с подписью installer identity → Transporter.
2. В App Store Connect → TestFlight: сборка проходит обработку (5–30 мин); вопрос Export Compliance
   закрывается ключом `ITSAppUsesNonExemptEncryption`.
3. Internal testing: до 100 тестировщиков из команды, без ревью. Проверить на реальном Tacx Neo и датчиках
   пункты из `docs/backlog.md` раздел «Ручные проверки владельца».
4. External testing: группа, описание «What to test», до 10 000 тестировщиков; первая сборка проходит Beta App Review (1–2 дня);
   в описании указать, что BLE-устройство обязательно для тренировки, демо-режим — для просмотра UI.
5. Сборки TestFlight живут 90 дней; каждая новая сборка с тем же `short_version` — увеличить `version` (build number).
6. После прохождения тестов — Submit for Review в App Store Connect с заполненными разделами 2, 5, 6.

## 9. Частые причины отказа (Guidelines)

- 5.1.1 — отсутствует Privacy Policy URL или тексты usage description не объясняют назначение.
- 5.1.2 — данные о здоровье переданы без явного действия пользователя → выгрузка в Strava только по кнопке/явной настройке.
- 2.1 — ревьюер не может проверить функцию без оборудования → демо-режим и review notes.
- 4.0 — приложение «просто обёртка» / неработающий UI на iPad → если iPad не поддерживается, ограничить `TARGETED_DEVICE_FAMILY`.
- 2.4.5 (Mac) — работа вне sandbox, лишние entitlements → раздел 4.
- 5.2.5 — чужие бренды: кнопка/логотип Strava строго по брендбуку, слово «Zwift» в описании форматов — только как имя формата файла.
