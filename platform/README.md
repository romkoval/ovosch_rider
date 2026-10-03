# platform/ — заготовки платформенной конфигурации экспорта

Здесь лежат **шаблоны**, которые владелец применяет при настройке экспорта в Godot 4.7. Это не код и не
ресурсы игры: каталог исключается из экспортных пресетов (фильтр `platform/*`). Сами пресеты
(`export_presets.cfg`) содержат Team ID, сертификаты и профили и **в репозиторий не коммитятся** (`.gitignore`).
Тест `tests/unit/arch/test_publishing_docs.gd` проверяет наличие шаблонов и ключевых записей в них.

| Файл | Для чего | Куда применяется |
| --- | --- | --- |
| `ios/Info.plist.template` | `NSBluetoothAlwaysUsageDescription`, URL-схема `ovoschrider`, типы документов `.zwo/.erg/.mrc`, `ITSAppUsesNonExemptEncryption` | пресет iOS → `application/additional_plist_content` |
| `macos/Info.plist.template` | то же для macOS + `LSApplicationCategoryType` | пресет macOS → `application/additional_plist_content` |
| `macos/entitlements.template.plist` | App Sandbox, Bluetooth, network client/server, файлы пользователя | пресет macOS → `codesign/entitlements/custom_file` (или одноимённые встроенные опции) |
| `android/AndroidManifest.template.xml` | разрешения BLE для API 31+ и legacy, `uses-feature`, intent-filter схемы | Android-плагин BLE (`native/android/`) — его `AndroidManifest.xml` сливается Gradle в манифест приложения |

## Как применять (iOS и macOS)

1. В редакторе Godot: Project → Export → Add… → iOS (и отдельно macOS). Заполнить идентификаторы и подпись по
   `docs/publishing/app_store_checklist.md`, раздел 7.
2. Открыть нужный `Info.plist.template`, скопировать всё между `<!-- ADDITIONAL_PLIST_CONTENT_BEGIN -->` и
   `<!-- ADDITIONAL_PLIST_CONTENT_END -->`, заменить `&lt;BUNDLE_ID_IOS&gt;`/`&lt;BUNDLE_ID_MACOS&gt;`
   (в plist это экранированные `<BUNDLE_ID_…>`) на фактический bundle id и вставить в опцию
   `application/additional_plist_content` пресета. Экспортер добавит фрагмент в генерируемый Info.plist.
   Альтернатива для iOS — отредактировать Info.plist в сгенерированном Xcode-проекте (но тогда правки живут вне репозитория).
3. Русские тексты описаний: из комментария в конце шаблона создать `ru.lproj/InfoPlist.strings` в Xcode-проекте
   (iOS) или положить в бандл (macOS). Текст на en — значение по умолчанию в plist. Оба непустые — REQ-NFR-07 крит. 2.
4. macOS: сохранить `entitlements.template.plist` как `entitlements.plist` вне репозитория (или прямо указать путь к шаблону —
   плейсхолдеров в нём нет) и выставить `codesign/entitlements/custom_file`. Либо включить встроенные опции пресета:
   `app_sandbox/enabled`, `device_bluetooth`, `network_client`, `network_server`, `files_user_selected = Read/Write`.
5. Удалить `native/.gdignore` после сборки GDExtension для целевой платформы (`native/ble/README.md`), иначе
   `OvoschBle` не попадёт в сборку и экран устройств покажет «Bluetooth недоступен».
6. Экспортировать, проверить `Info.plist` и entitlements в готовом бандле:
   `plutil -p ovosch-rider.app/Contents/Info.plist | grep -i bluetooth` и
   `codesign -d --entitlements :- ovosch-rider.app`.

## Android

`android/AndroidManifest.template.xml` — заготовка манифеста **плагина**, а не всего приложения: при экспорте с
Gradle-сборкой (Use Gradle Build) Godot сливает манифесты плагинов из `addons/*/` (`.aar` объявлен через
`EditorExportPlugin._get_android_libraries`/`_get_android_manifest_*`). Разрешения из шаблона появятся в итоговом
манифесте; runtime-запросы — из GDScript (`OS.request_permissions()`), см. `docs/ports/android.md`.

## Linux и Windows

Пресеты Linux/Windows не требуют платформенных манифестов для BLE; для Flatpak/MSIX-упаковки заготовки будут добавлены
после решения о каналах распространения (`docs/ports/linux_windows.md`).
