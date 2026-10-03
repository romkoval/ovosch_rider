# Политика конфиденциальности ovosch-rider / Privacy Policy

Документ в двух языковых версиях (REQ-NFR-07 крит. 1, ТЗ раздел 3). Публикуется по URL,
который указывается в App Store Connect («Privacy Policy URL») и Google Play Console
(«Privacy policy»). Плейсхолдеры `<...>` заполняет владелец перед публикацией; обе версии
обязаны совпадать по смыслу. Любое изменение сбора/передачи данных в приложении требует
правки этого файла в том же коммите.

---

## Политика конфиденциальности

**Приложение:** ovosch-rider — тренировки на умном велостанке.
**Разработчик / оператор данных:** `<ИМЯ_ИЛИ_ОРГАНИЗАЦИЯ>`, `<АДРЕС_ПРИ_НЕОБХОДИМОСТИ>`.
**Контакт по вопросам данных:** `<EMAIL_ДЛЯ_ПРИВАТНОСТИ>`.
**Дата редакции:** `<ДАТА>`.

### 1. Общие положения

ovosch-rider работает локально на вашем устройстве. У приложения нет собственного сервера,
учётных записей и аналитики. Мы не собираем данные о вас на свои серверы — их у нас нет.
Данные покидают устройство только тогда, когда вы сами подключаете сторонний сервис
(Intervals.icu, Strava) и инициируете обмен с ним.

### 2. Какие данные обрабатывает приложение

| Категория | Данные | Источник | Зачем |
| --- | --- | --- | --- |
| **Данные о здоровье** | частота сердечных сокращений (пульс) | Bluetooth-датчик пульса, если вы его подключили | показ на экране тренировки, запись в файл заезда (FIT) |
| Фитнес-данные | мощность (Вт), каденс (об/мин), скорость, пройденная дистанция, длительность, выполненный план интервалов | велостанок и датчики по Bluetooth, расчёт в приложении | ведение тренировки (ERG), история заездов, файл FIT |
| Профиль | имя профиля, FTP, вес, зоны мощности и пульса, настройки | вводите вы | расчёт целей и зон; несколько профилей на одном устройстве |
| Учётные данные сервисов | API-ключ и Athlete ID Intervals.icu; OAuth-токены Strava | вводите вы / выдаёт сервис при входе | доступ к вашему аккаунту в этих сервисах по вашей команде |
| Файлы тренировок | импортированные планы `.zwo`, `.erg`, `.mrc` | выбираете вы | проигрывание плана |

Приложение **не** использует Apple HealthKit, Google Health Connect, геолокацию, камеру,
микрофон, контакты, рекламные идентификаторы и не ведёт аналитику использования.
Bluetooth используется исключительно для связи с велостанком и датчиками.

### 3. Где хранятся данные

- История заездов, профили и настройки — локально на устройстве, в каталоге данных приложения.
- API-ключи и токены — в защищённом хранилище платформы: Keychain (iOS, macOS), Android
  Keystore (Android), системное хранилище учётных данных (Linux, Windows). До появления
  нативного модуля на платформе используется зашифрованный файл в каталоге данных приложения.
- Резервные копии устройства (iCloud, Google) могут включать локальные данные приложения
  согласно настройкам вашей системы; этим управляете вы, а не приложение.

### 4. Куда и когда передаются данные

Передача происходит **только по вашему действию** и только в сервисы, которые вы подключили:

- **Intervals.icu** (`intervals.icu`) — по вашему запросу приложение загружает план
  тренировки и настройки (FTP, зоны) из вашего аккаунта. Для этого на сервер передаются ваши
  учётные данные Intervals.icu. Данные тренировок в Intervals.icu не выгружаются, если вы
  не включили такую функцию явно.
- **Strava** (`strava.com`) — после того как вы подключили аккаунт Strava и нажали «выгрузить»
  (или включили автоматическую выгрузку), файл заезда FIT с мощностью, пульсом, каденсом,
  скоростью и длительностью передаётся в ваш аккаунт Strava. Пульс — это данные о здоровье;
  вы можете отключить датчик пульса или удалить его из заезда до выгрузки.

Обработка данных этими сервисами регулируется их политиками:
Intervals.icu — `https://intervals.icu/privacy`, Strava — `https://www.strava.com/legal/privacy`.
Другим третьим лицам данные не передаются и не продаются. Соединения — только по HTTPS.

### 5. Удаление данных

- **Удаление профиля** в приложении удаляет его заезды, настройки и все связанные
  учётные данные (ключи, токены) из защищённого хранилища.
- **Отвязка сервиса** в настройках профиля удаляет его токены/ключ.
- **Удаление отдельного заезда** удаляет его файл и запись из истории.
- **Удаление приложения** удаляет все локальные данные.
- Данные, уже отправленные в Intervals.icu или Strava, удаляются средствами этих сервисов.
  Отзыв доступа приложения к аккаунту Strava: Settings → My Apps на strava.com.

### 6. Дети

Приложение не предназначено для детей младше 13 лет (16 — в ЕС) и не собирает их данные осознанно.

### 7. Изменения

Новая редакция публикуется по тому же адресу с обновлённой датой. Существенные изменения
(новые категории данных, новые получатели) отражаются в описании версии в магазине.

---

## Privacy Policy

**App:** ovosch-rider — smart trainer workouts.
**Developer / data controller:** `<NAME_OR_ORGANIZATION>`, `<ADDRESS_IF_REQUIRED>`.
**Privacy contact:** `<PRIVACY_EMAIL>`.
**Last updated:** `<DATE>`.

### 1. Overview

ovosch-rider runs locally on your device. The app has no server of its own, no user
accounts and no analytics. We do not collect your data on our servers — there are none.
Data leaves your device only when you connect a third-party service yourself
(Intervals.icu, Strava) and trigger an exchange with it.

### 2. Data the app processes

| Category | Data | Source | Purpose |
| --- | --- | --- | --- |
| **Health data** | heart rate | a Bluetooth heart-rate sensor, if you pair one | display during the workout, recorded in the ride file (FIT) |
| Fitness data | power (W), cadence (rpm), speed, distance, duration, the executed interval plan | trainer and sensors via Bluetooth, computed in the app | running the workout (ERG), ride history, FIT file |
| Profile | profile name, FTP, weight, power and heart-rate zones, settings | entered by you | targets and zones; several profiles on one device |
| Service credentials | Intervals.icu API key and Athlete ID; Strava OAuth tokens | entered by you / issued by the service on sign-in | access to your account at those services on your command |
| Workout files | imported `.zwo`, `.erg`, `.mrc` plans | chosen by you | playing the plan |

The app does **not** use Apple HealthKit, Google Health Connect, location, camera,
microphone, contacts or advertising identifiers, and has no usage analytics.
Bluetooth is used solely to talk to the trainer and sensors.

### 3. Where data is stored

- Ride history, profiles and settings — locally on the device, in the app's data directory.
- API keys and tokens — in the platform's secure storage: Keychain (iOS, macOS), Android
  Keystore (Android), the system credential store (Linux, Windows). Until a native module
  exists for a platform, an encrypted file in the app's data directory is used instead.
- Device backups (iCloud, Google) may include the app's local data according to your system
  settings; that is controlled by you, not by the app.

### 4. Where and when data is transmitted

Transmission happens **only on your action** and only to services you have connected:

- **Intervals.icu** (`intervals.icu`) — on your request the app downloads the workout plan
  and settings (FTP, zones) from your account. Your Intervals.icu credentials are sent to
  its server for that. Workout data is not uploaded to Intervals.icu unless you explicitly
  enable such a feature.
- **Strava** (`strava.com`) — after you connect a Strava account and tap "upload" (or enable
  automatic upload), the FIT ride file with power, heart rate, cadence, speed and duration
  is sent to your Strava account. Heart rate is health data; you may disconnect the heart-rate
  sensor or remove it from the ride before uploading.

Processing by those services is governed by their own policies:
Intervals.icu — `https://intervals.icu/privacy`, Strava — `https://www.strava.com/legal/privacy`.
Data is not shared with or sold to any other third party. All connections use HTTPS.

### 5. Deleting data

- **Deleting a profile** in the app removes its rides, settings and all linked credentials
  (keys, tokens) from secure storage.
- **Disconnecting a service** in the profile settings removes its tokens/key.
- **Deleting a ride** removes its file and history entry.
- **Uninstalling the app** removes all local data.
- Data already sent to Intervals.icu or Strava is deleted using those services.
  To revoke the app's access to your Strava account: Settings → My Apps on strava.com.

### 6. Children

The app is not directed at children under 13 (16 in the EU) and does not knowingly collect their data.

### 7. Changes

A new revision is published at the same address with an updated date. Material changes
(new data categories, new recipients) are noted in the store release notes.
