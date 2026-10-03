# SecureStore: архитектура и платформенные реализации (REQ-NFR-05 крит. 3, REQ-NFR-06, REQ-PRF-03)

## 1. Текущее состояние

Интерфейс — `src/storage/secure_store.gd` (`class_name SecureStore extends RefCounted`), единственная
точка записи/чтения токенов и API-ключей (REQ-NFR-05 крит. 1). Ключи — `"<profile_id>/<service>/<item>"`
(`SecureStore.key_for`), `service ∈ {intervals, strava}`, `item ∈ {api_key, athlete_id, access_token, refresh_token, expires_at}`.

| Метод | Назначение |
| --- | --- |
| `set_secret(key, value) -> bool` | записать; пустое значение запрещено |
| `get_secret(key) -> String` | прочитать, `""` если нет |
| `delete_secret(key) -> bool`, `has_secret(key) -> bool` | удалить/проверить |
| `list_keys(prefix) -> Array[String]` | перечислить (нужен для `delete_prefix`) |
| `delete_prefix(prefix) -> int`, `delete_profile_secrets(profile_id)`, `delete_service_secrets(profile_id, service)` | каскадное удаление (REQ-PRF-03) |
| `attach_to_profiles(repo)` | подписка на удаление профиля |
| `static create_default(dir_path) -> SecureStore` | выбор реализации для текущей сборки |

Реализации:
- `MemorySecureStore` — память; тесты и dev-режим (REQ-NFR-05 крит. 2).
- `EncryptedFileSecureStore` — `user://secrets.bin`, AES-256 из ядра Godot, пароль из `derive_device_password()`
  (SHA-256 от `OS.get_unique_id()` + соль). **Временная переносимая реализация**: защищает от чтения файла «как есть»
  и от попадания секретов в бэкап открытым текстом, но не от злоумышленника с доступом к устройству — ключ
  выводим из идентификатора устройства, который тоже лежит на устройстве. На магазинных платформах **не считается**
  выполнением REQ-NFR-05 крит. 1/3 (см. комментарии в `secure_store.gd` и `docs/backlog.md`, «Ручные проверки»).

Платформозависимый код в `src/` допустим только в `src/storage/secure_store*`, `src/devices/ble/` и `src/app/locale.gd`
(REQ-NFR-06 крит. 1); нативный код — только в `native/` (крит. 2). Нативные хранилища не нарушают это правило:
GDScript-слой знает лишь факт наличия нативного класса.

## 2. Целевая архитектура

```
SecureStore (интерфейс, GDScript)              src/storage/secure_store.gd
 ├─ MemorySecureStore                           тесты
 ├─ EncryptedFileSecureStore                    fallback: Linux без libsecret, dev-сборки, контейнер
 └─ NativeSecureStore (GDScript-обёртка)        src/storage/native_secure_store.gd — ClassDB.class_exists("OvoschSecure")
      └─ OvoschSecure : RefCounted (GDExtension) native/secure/  — один класс, N бэкендов
           ├─ KeychainBackend         macOS, iOS       Security.framework (SecItem*)
           ├─ DpapiBackend / CredBackend  Windows      Credential Manager (CredWrite/CredRead) поверх DPAPI
           ├─ LibsecretBackend       Linux             libsecret (Secret Service D-Bus API)
           └─ AndroidBackend         Android           через Android-плагин: Keystore + EncryptedSharedPreferences
```

**Рекомендация: отдельный GDExtension `OvoschSecure` в `native/secure/`**, а не расширение `OvoschBle`:
- разные системные фреймворки и права (Security.framework / Keychain Sharing vs CoreBluetooth; на Linux —
  libsecret vs BlueZ); сборка Linux-BLE не должна тащить GLib/libsecret, и наоборот;
- разный жизненный цикл: хранилище нужно на всех платформах с первого экрана, BLE — только на экране устройств;
  на Linux без Bluetooth-адаптера `OvoschBle` может быть недоступен, а секреты — нужны;
- REQ-NFR-06 называет два отдельных модуля изоляции («BLE-слой и модуль защищённого хранения») — это естественно
  отражается двумя каталогами `native/ble/` и `native/secure/` с общим шаблоном (SConstruct, `*_backend.h`, null-backend, CI-job);
- `test_native_contract.gd` можно скопировать как `test_native_secure_contract.gd` (сверка биндингов с методами `SecureStore`).

Контракт C++ (`native/secure/src/secure_backend.h`, по образцу `native/ble/src/ble_backend.h`):

```cpp
class SecureBackend {
public:
    virtual ~SecureBackend() = default;
    virtual bool is_available() const = 0;                     // false у NullBackend
    virtual bool set_secret(const std::string &key, const std::string &value) = 0;
    virtual bool get_secret(const std::string &key, std::string &out) = 0;
    virtual bool delete_secret(const std::string &key) = 0;
    virtual std::vector<std::string> list_keys(const std::string &prefix) = 0;
};
std::unique_ptr<SecureBackend> create_platform_backend();
```

Все операции синхронные (Keychain/libsecret/CredMan — синхронные API; libsecret имеет `_sync`-варианты), поэтому
сигналы не нужны; `OvoschSecure` биндит те же пять методов плюс `is_available()`. `NativeSecureStore` — тонкая
GDScript-обёртка, повторяющая подход `NativeBleBridge` (`ClassDB.class_exists`, иначе `null`).

`create_default()` после появления модуля:

```
if ClassDB.class_exists("OvoschSecure") and OvoschSecure.new().is_available():
    store = NativeSecureStore.new()
    _migrate_from_encrypted_file(store)   # раздел 4
else:
    store = EncryptedFileSecureStore.new(dir_path)   # fallback с предупреждением в лог
```

Единый «сервис/аккаунт» для записей: service = `"<BUNDLE_ID>"` (например `<BUNDLE_ID_PREFIX>.ovoschrider`),
account/label = полный ключ `"<profile_id>/<service>/<item>"`. `list_keys(prefix)` реализуется перечислением
записей нашего service и фильтрацией по префиксу — нужен для каскадного удаления профиля.

## 3. Платформенные реализации

### macOS и iOS — Keychain (Security.framework)

- API: `SecItemAdd` / `SecItemCopyMatching` / `SecItemUpdate` / `SecItemDelete`, класс `kSecClassGenericPassword`,
  `kSecAttrService` = bundle id, `kSecAttrAccount` = ключ, значение — `kSecValueData` (UTF-8).
- Доступность: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — токены нужны после разблокировки
  (возможный фон), но не должны переезжать в бэкап на другое устройство (`ThisDeviceOnly`); если владелец выберет
  синхронизацию профилей через iCloud Keychain (открытый вопрос ТЗ) — `kSecAttrSynchronizable` и аксессибилити без `ThisDeviceOnly`.
- macOS: в sandbox приложение автоматически получает доступ к своим записям (keychain-access-group = Team ID + bundle id);
  Keychain Sharing entitlement не нужен, пока нет общего доступа между iOS и macOS сборками. Для разработки без sandbox —
  записи попадают в login keychain, видны в Keychain Access (REQ-NFR-05 крит. 4 — ручная проверка).
- Ошибки: `errSecItemNotFound` → `get_secret` возвращает false без логирования; `errSecDuplicateItem` → `SecItemUpdate`;
  `errSecInteractionNotAllowed` (устройство заблокировано) → false, повтор позже.
- Сборка: Objective-C++ (`.mm`) с ARC, линк `-framework Security -framework Foundation`; iOS — static lib → xcframework, как у BLE.
- Тесты вне контейнера: записать/прочитать/удалить после перезапуска приложения; удалить профиль → записей нет.

### Android — Keystore + EncryptedSharedPreferences

- GDExtension на Android не имеет удобного доступа к JNI/Context, поэтому бэкенд реализуется как **Godot Android plugin v2**
  (Kotlin, `native/android/secure/`, см. `docs/ports/android.md` о структуре плагинов), а `NativeSecureStore` на Android
  обращается к `Engine.get_singleton("OvoschSecure")` с тем же набором методов.
- Реализация: `androidx.security:security-crypto` — `EncryptedSharedPreferences` с `MasterKey` (`AES256_GCM`) из Android Keystore;
  ключ записи = наш ключ, значение — строка. Альтернатива при deprecation security-crypto (библиотека переведена в maintenance):
  собственный AES-GCM с ключом из `AndroidKeyStore` (`KeyGenParameterSpec`, `setUserAuthenticationRequired(false)`), данные — в `SharedPreferences`.
- `setIsStrongBoxBacked(true)` — опционально при наличии; не требовать.
- `android:allowBackup="false"` или `dataExtractionRules` исключают файл префов из бэкапа (ключ Keystore в бэкап не попадает, и зашифрованные данные без него бесполезны — но проще исключить).
- Тесты: instrumented-тест плагина (запись/чтение/удаление), ручная проверка после перезапуска.

### Linux — libsecret (Secret Service, GNOME Keyring / KWallet через portal)

- API: `secret_password_store_sync` / `secret_password_lookup_sync` / `secret_password_clear_sync` со схемой
  (`SecretSchema` с атрибутами `app = <BUNDLE_ID>`, `key = <ключ>`); перечисление — `secret_service_search_sync` по атрибуту `app`.
- Зависимость: `libsecret-1`, GLib — линковать динамически; при отсутствии Secret Service на машине (нет keyring-демона, headless)
  вызовы завершаются ошибкой → `is_available() == false` → fallback `EncryptedFileSecureStore` с предупреждением в UI «секреты в зашифрованном файле».
- Flatpak: доступ через `--talk-name=org.freedesktop.secrets` (или portal `org.freedesktop.portal.Secret` — тогда хранить мастер-ключ от файла,
  а не записи по одной; решить при упаковке, см. `docs/ports/linux_windows.md`). Snap — интерфейс `password-manager-service`.
- Steam Deck / Steam runtime: libsecret в sniper-рантайме есть; keyring-демон в Game Mode может отсутствовать → fallback должен работать штатно.

### Windows — DPAPI / Credential Manager

- Рекомендуется **Credential Manager** (`CredWriteW` / `CredReadW` / `CredDeleteW` / `CredEnumerateW`, тип `CRED_TYPE_GENERIC`,
  `TargetName = "<BUNDLE_ID>/<ключ>"`, `Persist = CRED_PERSIST_LOCAL_MACHINE`): он сам шифрует DPAPI ключом пользователя,
  записи видны в «Диспетчере учётных данных» (аналог проверки REQ-NFR-05 крит. 4). Лимит blob — 512×5 байт, токенов хватает.
- Чистый DPAPI (`CryptProtectData`/`CryptUnprotectData`) — альтернатива: шифровать `secrets.bin` ключом пользователя Windows вместо
  `derive_device_password()`; меньше кода, но нет перечисления и нет видимости для пользователя.
- MSIX (Microsoft Store): Credential Manager доступен без дополнительных capabilities; альтернатива — `Windows.Security.Credentials.PasswordVault` (WinRT).
- Сборка: MSVC на Windows-раннере (как и WinRT-бэкенд BLE), линк `Advapi32.lib`.

## 4. Миграция из `EncryptedFileSecureStore` при первом запуске с нативным модулем

1. `create_default()` создаёт `NativeSecureStore`; если `is_available()`, проверяет наличие `user://secrets.bin`.
2. Если файл есть и расшифровывается (`loaded_ok()`): для каждого ключа из `list_keys("")` — `native.set_secret(key, value)`;
   после успешной записи **всех** ключей файл удаляется (`reset_store()`), в лог — число перенесённых записей без значений.
3. Если хотя бы одна запись не записалась — файл не трогать, работать через `EncryptedFileSecureStore`, повторить миграцию при следующем запуске.
4. Если файл есть, но не расшифровывается (`loaded_ok() == false`, например, сменился `OS.get_unique_id()`) — файл не удалять,
   миграция невозможна; UI показывает «привязки нужно выполнить заново» (как и сейчас при повреждённом файле).
5. Миграция идемпотентна и выполняется до первого обращения интеграций к хранилищу (в `main.gd` при инициализации).
6. Тест в контейнере возможен на `MemorySecureStore` как «нативном» (внедрение фабрики): файл с N записями → после миграции N записей в целевом хранилище и файла нет.

## 5. Что остаётся `[вне контейнера]` и шаги владельца

| Критерий | Шаг |
| --- | --- |
| REQ-NFR-05 крит. 3 (Keychain) | создать `native/secure/` по разделу 2, собрать на macOS (`scons platform=macos`), подключить `.gdextension`, проверить миграцию (раздел 4) |
| REQ-NFR-05 крит. 4 | на macOS: привязать Strava → запись видна в Keychain Access (service = bundle id); отвязать → записи нет |
| REQ-NFR-05 крит. 3 (Keystore) | плагин `native/android/secure/`, проверка на устройстве; `allowBackup=false` |
| REQ-NFR-05 крит. 3 (libsecret / Credential Manager) | бэкенды Linux/Windows после решения о каналах распространения (`docs/ports/linux_windows.md`) — права Flatpak/Snap влияют на реализацию |
| REQ-PRF-03 крит. 4 | значение сохраняется после перезапуска на каждой платформе с нативным модулем |

Порядок: Keychain (этап 8) → Keystore (этап 9) → libsecret/Credential Manager (этап 10). До каждого шага на соответствующей
платформе работает `EncryptedFileSecureStore`, и это должно быть честно отражено в описании версии (политика конфиденциальности,
раздел «Где хранятся данные», уже содержит оговорку).
