# ovosch-rider — бэклог MVP

Ведёт: менеджер разработки. Источник критериев — `docs/requirements.md` (74 REQ). Этапы — раздел 7 `docs/tz.md`.
Задача закрывается (`done`) только по отчёту tester с подтверждением всех критериев `[авто]` указанных REQ. Критерии `[ручная проверка]` и `[вне контейнера]` в закрытии задачи не участвуют — они собраны в разделе «Ручные проверки владельца».

Среда: Linux-контейнер, Godot 4.7 headless, без GUI, без macOS/Xcode, без Tacx Neo, без реальных аккаунтов Intervals.icu/Strava. Задачи `[native-ble]` пишутся и проверяются только статически и по контракту моста; сразу после написания кода они переводятся в `blocked: нужен macOS`. Задачи этапов 8–10 — только документы и заготовки конфигурации.

## 1. Легенда

### Статусы

| Статус | Значение |
| --- | --- |
| `todo` | Не начата. |
| `in-progress` | Взята developer. |
| `review` | Developer сдал, ждёт проверки tester. |
| `done` | Tester подтвердил все критерии `[авто]` указанных REQ. |
| `blocked` | Нельзя продолжить; причина указана рядом (например, `blocked: нужен macOS`). |

### Зоны

| Зона | Что входит |
| --- | --- |
| `[game]` | GDScript, сцены, UI, доменный слой (`src/domain/`, `src/devices/` без нативной части, `src/profiles/`, `src/ui/`, `src/scene3d/`). |
| `[native-ble]` | GDExtension: C++/Objective-C++ в `native/ble/`, CoreBluetooth. Собрать в контейнере нельзя. |
| `[integration]` | Intervals.icu, Strava, парсеры ZWO/.erg/.mrc, FIT, хранилище заездов (`src/integrations/`, `src/storage/`). |
| `[docs]` | Документы, чеклисты, заготовки конфигурации (`docs/`, `export_presets.cfg`, шаблоны манифестов). |

### Правила ведения

- Коммиты с REQ-ID в сообщении (REQ-INF-03). Норма — один коммит на задачу: «код + юнит-тесты developer». Если приёмка нашла дефекты, допускается второй коммит: «фиксы developer + приёмочные тесты tester».
- Тесты. Developer пишет свои юнит-тесты вместе с кодом (`tests/unit/**/test_<модуль>.gd`). Tester пишет независимые приёмочные тесты `tests/**/test_*_acceptance.gd` с именами `test_req_<area>_<nn>_c<k>_...` (REQ и номер критерия в имени) и не правит код в `src/`. Никто не правит чужие тесты: если тест кажется неверным — об этом пишут в отчёт. Задача переходит в `done` только по отчёту tester.
- Если при реализации выяснилось, что задачу нельзя сделать за один заход, — developer не расширяет её, а пишет в отчёт; менеджер режет.
- Допуски с пометкой «(допуск предложен, подтвердить)» действуют как есть, пока владелец не заменил их (см. «Открытые решения» в requirements.md).

## 2. Таблица задач

Порядок строк — порядок выполнения. Этап 1 первым; в нём первыми интерфейс `TrainerDevice` и `FakeTrainer` (главный риск — связь со станком и ERG), затем модель тренировки и исполнитель интервалов, затем профили.

| ID | Зона | Этап | Задача | REQ-ID | Зависит от | Статус |
| --- | --- | --- | --- | --- | --- | --- |
| T-001 | `[game]` | 1 | Инфраструктура тестов и CI (GUT headless, workflow) | REQ-INF-01, REQ-INF-02 | — | `done` (подтверждено CI run #3; коммит dd23677) |
| T-002 | `[game]` | 1 | Интерфейс `TrainerDevice`, `TrainerSample`, `TrainerFactory` | REQ-DEV-09 (п.1), REQ-NFR-06 (п.3) | T-001 | `done` (коммиты 26ef1b4, 68e7064) |
| T-003 | `[game]` | 1 | `FakeTrainer`: ядро, ERG-сходимость, сценарии «постоянная», «рывки», «нулевой каденс» | REQ-DEV-09 (п.1, 2, 3 частично, 4) | T-002 | `done` (коммиты 26ef1b4, 68e7064) |
| T-004 | `[game]` | 1 | `FakeTrainer`: сценарии сбоев (пропуск пакетов, обрыв/восстановление, ошибка Control Point) и эмуляция пульса/каденса | REQ-DEV-09 (п.3, 5) | T-003 | `done` (коммиты 26ef1b4, 68e7064) |
| T-005 | `[game]` | 1 | Доменная модель тренировки: `Workout`, `WorkoutStep`, `TextCue`, `PowerSmoother` | REQ-WRK-01 (входная модель), REQ-NFR-09 (п.1 — модель), REQ-HUD-09 (п.1–3 — `PowerSmoother`), REQ-INT-05 (п.1, 2 — `power_points`), REQ-HUD-07 (п.1 — `segments`) | T-001 | `done` (коммиты 0ca2af5, 1e19252) |
| T-006 | `[game]` | 1 | Исполнитель интервалов `IntervalExecutor` (тики 1 Гц, события переходов, завершение) | REQ-WRK-01 (п.1–4), REQ-NFR-02 (п.1 — исполнитель), REQ-NFR-09 (п.1, 4) | T-005 | `done` (коммит 1e19252) |
| T-007 | `[game]` | 1 | `WorkoutSession`: связка исполнителя и `TrainerDevice`, прогон плана на `FakeTrainer` | REQ-WRK-01 (п.5), REQ-DEV-09 (п.6) | T-003, T-006 | `done` (коммит 1e19252) |
| T-008 | `[game]` | 1 | Зоны мощности (7, Coggan) и пульса (5), функция определения зоны | REQ-PRF-02 (п.2, 3, 5) | T-001 | `done` (коммиты 0ca2af5, 1e19252) |
| T-009 | `[game]` | 1 | Модель профиля, валидация, `ProfileRepository` (JSON в `user://`) | REQ-PRF-01 (п.1, 2, 5, 6), REQ-PRF-02 (п.1, 4) | T-008 | `done` (коммиты f06193f, f3a8f0f) |
| T-010 | `[game]` | 1 | `SecureStore`: интерфейс, in-memory реализация, ключи с идентификатором профиля | REQ-NFR-05 (п.1, 2), REQ-PRF-03 (п.1, 2, 3) | T-009 | `done` (коммиты f06193f, f3a8f0f) |
| T-011 | `[game]` | 1 | Реестр запомненных устройств: датчики в профиле, общий станок; каскадное удаление профиля | REQ-PRF-04 (п.2, 3, 4), REQ-PRF-01 (п.3, 4), REQ-DEV-06 (п.1 — хранение) | T-009, T-010 | `done` (коммиты f3a8f0f, 71aca4c) |
| T-012 | `[game]` | 1 | Оболочка приложения: состояние навигации, экран выбора профиля, создание первого профиля, каркас переводов | REQ-PRF-05 (п.1–3), REQ-NFR-08 (п.1 — заделка) | T-009 | `done` (коммиты f3a8f0f, 71aca4c) |
| T-013 | `[game]` | 1 | `SessionTicker` (1 Гц от системных часов, не от кадров) и экран разработчика «Проиграть на FakeTrainer» | REQ-DEV-09 (п.6), REQ-WRK-01 (п.5), REQ-NFR-02 (п.1) | T-007, T-012 | `done` (коммиты e0a9ae4, 9d14313, приёмка 52d2261) |
| T-014 | `[game]` | 1 | Архитектурные и инфраструктурные проверки: тест архитектуры, скрипты секретов и сообщений коммитов, `fetch-depth: 0` | REQ-INF-03, REQ-INF-04 (п.1 — warning-only, см. T-056), REQ-NFR-06 (п.1–3), REQ-NFR-09 (п.4) | T-013 | `done` (коммиты e0a9ae4, 9d14313, приёмка 52d2261) |
| T-056 | `[game]` | 1 | Инвентаризация публичных методов домена и перевод проверки трассируемости из warning в fail | REQ-NFR-09 (п.2), REQ-INF-04 (п.1, 2 — строгий режим) | T-014 | `done` (коммит 52a59dd, 69/69) |
| T-015 | `[game]` | 2 | Контракт нативного моста `BleBridge` в GDScript, `StubBleBridge`, `NativeBleBridge`, `BleUuids` | REQ-DEV-01..08 (контракт), REQ-NFR-06 (п.1) | T-002 | `done` (коммит 03cce42, приёмка a6889af) |
| T-016 | `[game]` | 2 | Кодеки BLE-характеристик: FTMS (Indoor Bike Data, Control Point, Status), HRS, CSC, CPS, Battery | REQ-DEV-02 (п.2–5), REQ-DEV-03 (п.1), REQ-DEV-04 (п.1–3), REQ-DEV-05 (п.1), REQ-DEV-07 (п.2) | T-015 | `done` (коммиты 03cce42, 5c2e62f, приёмка a6889af 38/38) |
| T-017 | `[game]` | 2 | `BleTrainer`: `TrainerDevice` поверх `BleBridge` — последовательность подключения, телеметрия, команды, ошибки Control Point | REQ-DEV-02 (п.1, 3) | T-016 | `done` (коммиты 5c2e62f, 851c724; приёмка 327144b, 38/38) |
| T-018 | `[game]` | 2 | BLE-датчики (`BleHeartRateSensor`, `BleCadenceSensor`, `BlePowerMeter`) и `SensorHub` с приоритетами источников | REQ-DEV-03 (п.2, 3), REQ-DEV-04 (п.3 по Н-4, 4), REQ-DEV-05 (п.2, 3) | T-017 | `done` (коммиты 5c2e62f, 851c724; приёмка 327144b, 38/38) |
| T-019 | `[game]` | 2 | Сканер и модель списка устройств | REQ-DEV-01 (п.1–4, п.7 — UX-3) | T-015 | `done` (коммиты 851c724, fce771b; приёмка экрана устройств 12/12) |
| T-020 | `[game]` | 2 | Состояния подключения, заряд, запоминание, автоподключение, «забыть» | REQ-DEV-06 (п.1–4), REQ-DEV-07 (п.1–3) | T-011, T-018, T-019 | `done` (коммиты 851c724, fce771b; приёмка 12/12) |
| T-021 | `[native-ble]` | 2 | Каркас GDExtension: godot-cpp, сборка, `.gdextension`, класс `OvoschBle` с контрактом, `BleBackend`/`null_backend` | REQ-DEV-01 (п.6), REQ-NFR-06 (п.2) | T-015 | `blocked: нужен macOS` (код 851c724, 1c75404; Linux-сборка в CI зелёная, контракт сверен) |
| T-022 | `[native-ble]` | 2 | Реализация контракта на CoreBluetooth (Objective-C++) для macOS/iOS | REQ-DEV-01 (п.5, 6), REQ-DEV-02 (п.6, 7) | T-021 | `blocked: нужен macOS` (код fce771b; статическая сверка `test_native_contract.gd`; вопрос Н-10) |
| T-023 | `[game]` | 3 | `SampleRecorder`: сэмплы 1 Гц, «последнее за секунду», «нет данных» через 5 с, независимость от кадров | REQ-WRK-08 (п.1–6), REQ-NFR-02 (п.1, 2) | T-007, T-013 | `done` (коммиты bdddd4d, c5d7c59; приёмка 48/48) |
| T-024 | `[game]` | 2→3 | Переподключение без потери данных сессии | REQ-DEV-08 (п.1–4) | T-017, T-020, T-023 | `done` (коммит c5d7c59; приёмка 30/30 в 65715d4) |
| T-025 | `[game]` | 3 | `ErgController`: расчёт и отправка цели (% FTP, ватты, рампа, без цели), множитель интенсивности, задержка ≤ 1 с, повтор при ошибке записи | REQ-WRK-02 (п.1–5), REQ-WRK-07 (п.1, 2, 3, 5), REQ-NFR-01 (п.1, 2) | T-007, T-023 | `done` (коммиты bdddd4d, c5d7c59; приёмка 48/48) |
| T-026 | `[game]` | 3 | Режим фиксированного сопротивления и переключатель ERG | REQ-WRK-04 (п.1–3), REQ-WRK-03 (п.1–5) | T-025 | `done` (коммиты bdddd4d, c5d7c59; приёмка 48/48) |
| T-027 | `[game]` | 3 | Управление сессией: пауза/возобновление, досрочное завершение, пропуск шага, журнал событий, запрет гашения экрана | REQ-WRK-05 (п.1–4), REQ-WRK-06 (п.1–4), REQ-NFR-04 (п.1, 2) | T-025, T-026 | `done` (коммиты bdddd4d, c5d7c59 — фикс D-6; приёмка 48/48) |
| T-028 | `[game]` | 3 | Модель HUD «мощность»: сглаживание 3 с, отклонение от цели, зона мощности, зона пульса | REQ-HUD-09, REQ-HUD-02 (п.1–3), REQ-HUD-03 (п.1–3), REQ-HUD-04 (п.1, 2) | T-008, T-023 | `done` (коммит bcbbe7c; приёмка 973b7c0) |
| T-029 | `[game]` | 3 | Модель HUD «время и подсказки»: форматы, обратный отсчёт, «скоро смена», подсказки с таймаутом | REQ-HUD-05 (п.1–3), REQ-HUD-06 (п.1, 2), REQ-HUD-08 (п.1–3) | T-027 | `done` (коммит bcbbe7c; приёмка 973b7c0) |
| T-030 | `[game]` | 3 | Профиль плана: сегменты для полосы прогресса и точки (t, Вт) для предпросмотра | REQ-HUD-07 (п.1–3), REQ-WRK-07 (п.4), REQ-INT-05 (п.1–3) | T-025, T-027 | `done` (коммит bcbbe7c; приёмка 973b7c0) |
| T-031 | `[game]` | 3 | Сцена экрана тренировки (HUD): раскладка, привязка к моделям, кнопки ERG/множитель/сопротивление/пауза/пропуск/завершить | REQ-HUD-01 (п.1–3), REQ-WRK-03 (п.1 — состояние на HUD) | T-028, T-029, T-030 | `done` (коммит c5d7c59; приёмка 30/30 в 65715d4) |
| T-032 | `[integration]` | 4 | `HttpTransport`: интерфейс, реальная реализация на `HTTPRequest`, `MockHttpTransport` (журнал запросов, заготовленные ответы, режим «нет сети») | REQ-NFR-03 (п.1, 2 — основа) | T-001 | `done` (коммит ad5b364; приёмка 33/33 в 4b049e9) |
| T-033 | `[integration]` | 4 | Клиент Intervals.icu: авторизация по API-ключу, проверка ключа, профиль атлета (FTP, зоны) с локальным переопределением | REQ-INT-01 (п.1–3), REQ-INT-06 (п.1–4, 8 — по В-13) | T-010, T-032 | `done` (коммит ad5b364; приёмка 33/33 в 4b049e9) |
| T-034 | `[integration]` | 4 | Intervals.icu: события календаря на сегодня, фильтр, пустой ответ, 5xx/сеть, 429 | REQ-INT-02 (п.1–5) | T-033 | `done` (коммит ad5b364; приёмка 33/33 в 4b049e9) |
| T-035 | `[integration]` | 4 | Разбор структурированной тренировки Intervals.icu в `Workout` | REQ-INT-03 (п.1–9, п.9 — по В-15), REQ-NFR-09 (п.3 — Intervals) | T-005 | `done` (коммиты f5a628e, 24a99a4, 4b049e9; приёмка 87/87) |
| T-036 | `[integration]` | 4 | Кэш плана и работа без сети | REQ-INT-07 (п.1–4), REQ-NFR-03 (п.1, 2) | T-034, T-035, T-027 | `done` (коммит ad5b364; D-7 исправлен; приёмка 33/33 в 4b049e9) |
| T-037 | `[integration]` | 4 | Парсер ZWO | REQ-IMP-01 (п.1–7, п.2 — по В-12), REQ-NFR-09 (п.3 — ZWO) | T-005 | `done` (коммиты f5a628e, 24a99a4, 4b049e9; приёмка 87/87) |
| T-038 | `[integration]` | 4 | Парсер .erg/.mrc | REQ-IMP-02 (п.1–6), REQ-NFR-09 (п.3 — erg/mrc) | T-005 | `done` (коммиты f5a628e, 24a99a4, 4b049e9; приёмка 87/87) |
| T-039 | `[integration]` | 4 | Точка входа импорта по расширению, модель ошибок импорта, библиотека тренировок профиля (без UI) | REQ-IMP-03 (п.1), REQ-IMP-05 (п.1–4), REQ-IMP-04 (п.1–5, п.4 — по В-14) | T-037, T-038, T-009 | `done` (коммиты f5a628e, 24a99a4, 4b049e9; приёмка 87/87) |
| T-040 | `[game]` | 4 | Экран выбора тренировки и предпросмотра (план на сегодня + библиотека, график профиля, импорт файла) | REQ-INT-04 (п.1–3), REQ-INT-05 (п.1–3 — отображение), REQ-IMP-03 (п.2) | T-030, T-036, T-039 | `review` (коммит screens; 24/24 разработческих) |
| T-041 | `[integration]` | 5 | `RideRepository`: сохранение и чтение заездов с сэмплами и событиями в рамках профиля (+ `RideSummary`) | REQ-LOC-01 (п.1–4), REQ-PRF-04 (п.1), REQ-LOC-04 (п.1–6 — `RideSummary`) | T-023, T-027, T-009 | `done` (коммит 59f1fe1; приёмка 45/45) |
| T-042 | `[integration]` | 5 | Потоковая запись заезда на диск и восстановление после сбоя | REQ-LOC-07 (п.1–4) | T-041 | `done` (коммит 59f1fe1; Н-2 исправлен; приёмка 45/45) |
| T-043 | `[game]` | 5 | Серии для графиков (`RideSeries`): точки без «нет данных», прореживание ≤ 3600, серия цели | REQ-LOC-03 (п.1–3) (LOC-04 — закрыт `RideSummary` в T-041) | T-041, T-008 | `review` (коммит screens; 10/10) |
| T-044 | `[integration]` | 5 | Кодировщик FIT | REQ-LOC-05 (п.1–4), REQ-STR-02 (п.2), REQ-NFR-09 (п.1 — FIT) | T-041 | `done` (коммит 59f1fe1; Д-2 округление пауз исправлено; приёмка 16/16) |
| T-045 | `[game]` | 5 | Экраны истории: список, карточка с графиками и сводкой, удаление, экспорт FIT | REQ-LOC-02 (п.1, 2), REQ-LOC-06 (п.1, 2), REQ-LOC-05 (п.6 — вызов диалога) | T-043, T-044 | `review` (коммит screens; 22/22) |
| T-046 | `[integration]` | 6 | Strava OAuth 2.0: URL авторизации, обмен кода, обновление токенов, отвязка | REQ-STR-01 (п.1–6), REQ-PRF-03 (закрытие), REQ-NFR-05 (п.1, 2 — закрытие) | T-010, T-032 | `done` (коммит ce85da4; дефекты D-1..D-4 исправлены; приёмка 38/38) |
| T-047 | `[integration]` | 6 | Выгрузка заезда в Strava: multipart FIT, VirtualRide, опрос статуса, название/описание | REQ-STR-02 (п.1, 3, 4), REQ-STR-03 (п.1–3) | T-044, T-046 | `done` ядро (коммит ce85da4; приёмка 38/38; STR-02 п.1 через `StravaService` — приёмка T-049) |
| T-048 | `[integration]` | 6 | Очередь выгрузки с повторами и статусы заезда | REQ-STR-04 (п.1–6), REQ-STR-05 (п.1–3), REQ-LOC-06 (п.3), REQ-NFR-03 (п.3) | T-047, T-042 | `done` (коммит ce85da4; приёмка 38/38; Н-11, Н-12 — подтвердить владельцу) |
| T-049 | `[game]` | 6 | `StravaService` (связка очереди, репозитория и настроек), привязка Strava на экране настроек, действия Strava в карточке заезда | REQ-STR-04 (п.1 — автопостановка, п.5 — UI), REQ-STR-03 (п.3 — UI), REQ-STR-05 (п.2 — UI), REQ-STR-01 (п.7 — кнопка по брендбуку, вне контейнера) | T-057, T-048, T-045 | `review` (коммит screens; 20/20; дефекты ядра D-1..D-4 от приёмки T-046..048 → developer) |
| T-057 | `[game]` | 4–8 | Экран настроек: язык, профиль (FTP/вес/max HR/зоны с источником), привязка и синхронизация Intervals.icu, источник мощности в профиле, заглушка Strava, «О программе» | REQ-NFR-08 (п.3, 4), REQ-INT-06 (п.5–7), REQ-PRF-03 (п.2), REQ-DEV-05 (п.2 — хранение в профиле, Н-8), REQ-PRF-02 (п.1 — UI) | T-033, T-009, T-010, T-012 | `review` (коммит screens; 23/23; приёмка идёт) |
| T-050 | `[game]` | 7 | Модель скорости v(P, m): установившаяся скорость, инерция, ограничение изменения | REQ-D3D-02 (п.1–4), REQ-WRK-08 (п.5 — альтернативный источник) | T-023 | `done` (код bdddd4d; приёмка 973b7c0) |
| T-051 | `[game]` | 7 | Интерфейс трассы `Track`, зацикленная трасса, тестовая трасса, `docs/scene3d.md` | REQ-D3D-03 (п.1, 2), REQ-D3D-06 (п.1–3) | T-050 | `done` (коммит 65715d4; D-8 исправлен; приёмка 30/30) |
| T-052 | `[game]` | 7 | Сцена велосипедиста и камеры, анимация педалирования по каденсу, бюджет производительности | REQ-D3D-01 (п.1, 2), REQ-D3D-04 (п.1–3), REQ-D3D-05 (п.2; п.1, 3 — ручной замер) | T-051 | `done` (коммит 65715d4; D-8 исправлен; приёмка 30/30) |
| T-053 | `[docs]` | 8 | Пакет публикации iOS/macOS: `docs/publishing/*` (политика, чеклисты App Store и Strava API, OAuth Intervals.icu, лицензии), шаблоны `platform/ios|macos/*`, `docs/secure_store.md` | REQ-NFR-07 (п.1, 2, 4), REQ-IMP-03 (п.3), REQ-INT-01 (п.5), REQ-STR-01 (п.7), REQ-NFR-05 (п.3) | T-046 | `done` (коммит 7319347; приёмка `test_publishing_docs_acceptance` 11/11) |
| T-054 | `[game]` | 8 | Локализация ru/en: финальная инвентаризация переводов и литералов после всех экранов (выбор языка — в T-057) | REQ-NFR-08 (п.1, 2; п.3, 4 — подтверждение после T-057) | T-040, T-045, T-049, T-057 | `todo` |
| T-055 | `[docs]` | 9–10 | Порты BLE: `docs/ports/{README,android,linux_windows}.md`, `platform/android/AndroidManifest.template.xml`, Data safety Google Play, открытый вопрос о каналах Linux/Windows | REQ-NFR-06 (п.4), REQ-NFR-07 (п.3, 4 — Android) | T-022 | `done` (коммит 7319347; приёмка `test_publishing_docs_acceptance` 11/11) |

Итого 57 задач: этап 1 — 15 (T-001..T-014, T-056), этап 2 — 8 (+ T-024 выполняется в этапе 3), этап 3 — 9, этап 4 — 9 (+ T-057, экран настроек, сквозная для этапов 4–8), этап 5 — 5, этап 6 — 4, этап 7 — 3, этап 8 — 2, этапы 9–10 — 1. T-056 добавлена после приёмки T-014 (NFR-09 п.2 не покрыт); T-057 выделена из T-049/T-054, когда стало ясно, что экран настроек нужен раньше Strava (язык, синхронизация Intervals.icu, источник мощности по Н-8).

**Этап 2 закрыт в контейнере** (коммит fce771b): T-015..T-020, T-024 — `done`; T-021, T-022 — `blocked: нужен macOS` (код написан, Linux-сборка каркаса в CI зелёная, контракт `OvoschBle` ⇔ `BleBridge` сверен статически; сборка и проверка на Tacx Neo — у владельца, раздел 4).

**Этап 1 завершён** (коммит e0a9ae4, экран разработчика T-013): результат «тренировка проигрывается без железа» подтверждён — план проигрывается на `FakeTrainer` через `SessionTicker` без зависимости от кадров. Открытые хвосты этапа: приёмка T-013/T-014, T-056 (строгая трассируемость), решения Н-1/Н-2.

## 3. Карточки задач

### Этап 1 — Каркас. Результат: тренировка проигрывается без железа

#### T-001 — Инфраструктура тестов и CI `[game]` — `done`
Сделано: `scripts/test.sh`, `.gutconfig.json`, `.github/workflows/ci.yml` (push в любую ветку и PR; шаги «Project opens headless», «Run GUT tests», артефакт `gut-junit` с `if: always()`; Godot 4.7-stable), `tests/unit/test_smoke.gd`. Подтверждено CI run #3.
Коммит dd23677: одиночный тестовый файл запускается `./scripts/test.sh -gselect=<имя файла>` (а не `-gtest=`, как в CLAUDE.md и REQ-INF-01 п.2 — расхождение формулировки, см. раздел 5, Н-1).
Закрывает: REQ-INF-01 (п.1–5), REQ-INF-02 (п.1–5) — все `[авто]`.

#### T-002 — Интерфейс `TrainerDevice`, телеметрия, часы, фабрика устройств `[game]` — `done`
Факт. Реализовано вместе с T-003/T-004 одним заходом: коммит 26ef1b4 (в сообщении ошибочно помечен «T-001» — ошибка нумерации главного агента; содержательно это T-002..T-004) и коммит 68e7064 (фиксы по приёмке + 73 приёмочных теста tester, `tests/unit/devices/test_fake_trainer_acceptance.gd`). Отличия от плана ниже: вместо `TrainerTelemetry` с `NO_DATA` — `src/devices/trainer_sample.gd` (`TrainerSample` с флагами `has_power/has_cadence/has_speed`, конструкторы `full()`/`empty()`); вместо инъецируемого `Clock` — внешний `tick(delta_sec)` на самом устройстве (время продвигает исполнитель из своего источника, не `_process`); фабрика — `src/devices/trainer_factory.gd` (`TrainerFactory`). В интерфейс добавлен `set_erg_enabled(enabled)` (ERG-переключение — на уровне устройства, как в developer.md), сигналы `telemetry(sample)`, `heart_rate(bpm)`, `error(code, message)` с `ErrorCode {CONNECTION_FAILED, CONTROL_POINT_REJECTED, WRITE_FAILED, NOT_CONNECTED}`, состояние `SCANNING` в `ConnectionState`. Последующие карточки (T-006, T-007, T-013, T-015..T-018, T-023..T-026) читать с поправкой на эти имена.
Tester подтвердил: REQ-DEV-09 п.1; устройство-часть REQ-DEV-08 (п.1, 2 — состояние RECONNECTING, «нет данных» вместо 0), REQ-WRK-02/03/04/08 (сторона устройства), REQ-NFR-02 (тики извне).

Исходный план. Зафиксировать контракт, через который вся игровая часть общается со станком; никакого кода вне `src/devices/` не должно знать, какая реализация подключена.
- `src/domain/clock.gd` — `class_name Clock extends RefCounted`: `now_ms() -> int`. `src/domain/manual_clock.gd` — `ManualClock extends Clock`: `advance_ms(delta)`, `set_ms(t)`. Используется исполнителем, сэмплером и `FakeTrainer`, чтобы тесты шли быстрее реального времени.
- `src/devices/trainer_telemetry.gd` — `TrainerTelemetry extends RefCounted`: `timestamp_ms: int`, `power_w: int`, `cadence_rpm: float`, `speed_kmh: float`, `heart_rate_bpm: int`. Константа `NO_DATA = -1` (для float — `-1.0`): отсутствие значения — не ноль.
- `src/devices/trainer_device.gd` — `TrainerDevice extends RefCounted`, базовый класс-интерфейс (методы с `push_error("not implemented")`):
  - `enum ConnectionState { DISCONNECTED, CONNECTING, CONNECTED, RECONNECTING }` (совпадает с REQ-DEV-07.1);
  - сигналы `connection_state_changed(state: ConnectionState)`, `telemetry_received(sample: TrainerTelemetry)`, `command_result(opcode: int, ok: bool, result_code: int)`;
  - методы `connect_device() -> void`, `disconnect_device() -> void`, `get_connection_state() -> ConnectionState`, `request_control() -> void`, `set_target_power(watts: int) -> void`, `set_resistance_level(percent: float) -> void` (0–100 %), `get_device_info() -> Dictionary` (id, name).
  - Переключение ERG — решение доменного слоя (T-025/T-026): устройство лишь получает `set_target_power` или `set_resistance_level`; это соответствует FTMS, где ERG = режим целевой мощности.
- `src/devices/device_factory.gd` — единственная точка выбора реализации: `create_trainer(kind: StringName) -> TrainerDevice` (`&"fake"` / `&"ble"`); в этой задаче возвращает только `FakeTrainer`-заглушку (реальный класс появится в T-003, здесь — пустая реализация интерфейса, чтобы фабрика компилировалась).
Файлы: `src/domain/clock.gd`, `src/domain/manual_clock.gd`, `src/devices/trainer_telemetry.gd`, `src/devices/trainer_device.gd`, `src/devices/device_factory.gd` (+ `.uid`).
Закрывает: REQ-DEV-09 п.1 (часть «интерфейс»; полностью — в T-003), REQ-NFR-06 п.3 (домен не зависит от `src/devices/`: `Clock` живёт в `src/domain/`, `TrainerDevice` — в `src/devices/`, обратных ссылок нет).
Критерии авто: интерфейс инстанцируется, базовые методы не падают; `ManualClock.advance_ms` меняет `now_ms`; домен не ссылается на `src/devices/` (проверка `preload`/`class_name`). Ручных нет.

#### T-003 — `FakeTrainer`: ядро и ERG-сходимость `[game]` — `done`
Факт. Коммиты 26ef1b4, 68e7064. `src/devices/fake_trainer.gd`: `FakeTrainer.new(seed)`, `tick(delta_sec)`, `get_time_sec()`; журнал команд с метками времени (`CMD_TARGET_POWER`, `CMD_ERG`, `CMD_RESISTANCE`); сценарии через методы, а не через отдельный класс сценариев: `set_rider_power(w)` (постоянная / рывки — сменой значения между тиками), `set_rider_cadence(rpm)`, `set_zero_cadence()`. Оговорка tester: отдельного API «рывок всадника поверх ERG» нет — в ERG мощность сходится к цели, рывок моделируется только вне ERG через `set_rider_power`. Tester подтвердил REQ-DEV-09 п.1, 2, 3 (в части постоянная/рывки/нулевой каденс), 4 (время управляется извне через `tick`).

Исходный план. Симулятор станка, реализующий `TrainerDevice` целиком, время — из инъецированного `Clock`.
- `src/devices/fake_trainer.gd` — `FakeTrainer extends TrainerDevice`. Конструктор `FakeTrainer.new(clock: Clock)`. `tick()` или `advance_to(now_ms)` — симулятор выдаёт один `TrainerTelemetry` на каждую секунду модельного времени. Состояния подключения переключаются синхронно (`connect_device()` → `CONNECTING` → `CONNECTED` на следующем тике).
- ERG-модель: при полученной цели мощность экспоненциально сходится к цели так, что через 3 с |P − цель| ≤ 5 % цели (REQ-DEV-09.2); без цели — мощность по сценарию.
- Журнал команд: `get_command_log() -> Array[Dictionary]` с `{opcode, payload, timestamp_ms}` — именно по этим меткам времени tester проверяет NFR-01/WRK-02. `set_target_power` пишет opcode `0x05`, `set_resistance_level` — `0x04`, `request_control` — `0x00`; через тик эмитит `command_result(opcode, true, 0x01)`.
- Сценарии (`src/devices/fake_scenarios.gd`, `FakeScenario extends RefCounted` с методом `sample_at(t_s) -> TrainerTelemetry` или настройкой параметров): `constant(power, cadence, speed)`, `surges(base, peak, period_s)`, `zero_cadence(from_s)`. Сценарий назначается `set_scenario(s)`.
Файлы: `src/devices/fake_trainer.gd`, `src/devices/fake_scenarios.gd`; `device_factory.gd` возвращает `FakeTrainer` для `&"fake"`.
Закрывает: REQ-DEV-09 п.1 (полностью), п.2, п.4, п.3 (постоянная, рывки, нулевой каденс).
Критерии авто: все `[авто]` по перечисленным пунктам. Ручных нет.

#### T-004 — `FakeTrainer`: сценарии сбоев и симуляторы датчиков `[game]` — `done`
Факт. Коммиты 26ef1b4, 68e7064. Сценарии сбоев — методы `FakeTrainer`: `inject_dropout(duration_sec)` (обрыв → `RECONNECTING` → восстановление), `inject_packet_loss(ratio)`, `inject_silence(duration_sec)` (N секунд без данных), `fail_next_command()` (ошибка Control Point → `error(CONTROL_POINT_REJECTED)`), `fail_next_connect()`. Отдельных классов датчиков пульса/каденса (`SensorDevice`, `FakeHeartRateSensor`, `FakeCadenceSensor`) нет: пульс и каденс эмулируются внутри `FakeTrainer` — `set_heart_rate_sequence(values)`, `set_heart_rate(bpm)`, `set_cadence_sequence(values)`, по одному значению на секунду. Следствие для T-018: интерфейс `SensorDevice` появится вместе с BLE-датчиками, а не в этапе 1. Tester подтвердил REQ-DEV-09 п.3, 5.

Исходный план.
- В `fake_scenarios.gd` добавить: `packet_loss(from_s, duration_s)` — N секунд без телеметрии; `disconnect_at(t_s, reconnect_after_s)` — эмитит `connection_state_changed(DISCONNECTED)`, при вызове `connect_device()` после `reconnect_after_s` восстанавливает `CONNECTED`; `control_point_error(opcode, result_code)` — на указанную команду отвечает `command_result(opcode, false, result_code)` (например, `0x02` «не поддерживается», `0x03` «неверный параметр»).
- `src/devices/sensor_device.gd` — базовый интерфейс датчика: сигналы `connection_state_changed`, `value_received(value: int, timestamp_ms: int)`, `battery_level_changed(percent: int)`; методы `connect_device`, `disconnect_device`.
- `src/devices/fake_heart_rate_sensor.gd`, `src/devices/fake_cadence_sensor.gd` — выдают заданную последовательность значений (`set_sequence(values: Array[int])`) по 1 значению на секунду модельного времени `Clock`; `NO_DATA` в последовательности — пропуск.
Файлы: `src/devices/fake_scenarios.gd`, `src/devices/sensor_device.gd`, `src/devices/fake_heart_rate_sensor.gd`, `src/devices/fake_cadence_sensor.gd`.
Закрывает: REQ-DEV-09 п.3 (пропуск пакетов, обрыв/восстановление, ошибка Control Point), п.5.
Критерии авто: все. Ручных нет.

#### T-005 — Доменная модель тренировки `[game]` — `done`
Приёмка tester — коммит 1e19252: D-1 закрыт через `Workout.power_points()` (ломаная с начальной и конечной точками рамп — REQ-INT-05 п.1, 2) и `Workout.segments()` (сегменты для полосы прогресса — REQ-HUD-07 п.1). T-030 строится на этих методах.
Факт. Коммит 0ca2af5 (вместе с T-008). Файлы: `src/domain/text_cue.gd` (`TextCue`), `src/domain/workout_step.gd` (`WorkoutStep` с `TargetKind`/`StepKind`, конструкторы `percent/watts/ramp_percent/ramp_watts/free_ride`, `target_watts_at(offset, ftp, intensity)`), `src/domain/workout.gd` (`Workout.make`, `expand_repeat`, `total_duration_sec`, `step_index_at`, `target_watts_at`, `power_profile`, `validate`), `src/domain/power_smoother.gd` (`PowerSmoother` — сглаживание 3 с, относится к REQ-HUD-09 п.1–3; учтено в T-028 и трассируемости). Отдельного класса `WorkoutTarget` нет — цель хранится в `WorkoutStep`.
Приёмка tester (`tests/unit/domain/test_domain_acceptance.gd`): дефект **D-1** — REQ-INT-05 п.2: `Workout.power_profile()` возвращает поминутные/посекундные значения без конечной точки рампы, поэтому ломаная для графика не содержит точку «конец рампы». Решение: добавить `Workout.power_points()` (ломаная (t, Вт) для графика предпросмотра, с начальной и конечной точками каждой рампы) и `Workout.segments()` (сегменты для полосы прогресса HUD-07). Исправление — у developer A в одном заходе с T-006/T-007; после фикса T-005 возвращается на приёмку. T-030 при этом сокращается: «профиль плана» строится на `Workout.power_points()`/`segments()`.

Исходный план. Чистый GDScript (`RefCounted`), без узлов сцены.
- `src/domain/workout_target.gd` — `WorkoutTarget`: `enum Kind { NONE, PERCENT_FTP, WATTS }`, `kind`, `start_value: float`, `end_value: float` (рампа, если `start_value != end_value`), `is_ramp() -> bool`, `watts_at(progress: float, ftp: int) -> int` (округление до целого).
- `src/domain/workout_cue.gd` — `WorkoutCue`: `offset_s: int`, `text: String`.
- `src/domain/workout_step.gd` — `WorkoutStep`: `duration_s: int` (> 0), `target: WorkoutTarget`, `cadence_rpm: int` (`-1` — не задан), `cues: Array[WorkoutCue]`, `name: String`.
- `src/domain/workout.gd` — `Workout`: `name`, `description`, `author`, `source: String` («intervals», «zwo», «erg», «mrc»), `source_ref` (id события/имя файла), `steps: Array[WorkoutStep]`, `total_duration_s() -> int`, `is_valid() -> bool` (непустой список, все длительности > 0), `metadata: Dictionary` (например, FTP из заголовка .erg).
- Плоская последовательность шагов: повторы разворачивают парсеры, модель повторов не хранит.
Файлы: четыре файла выше.
Закрывает: входная модель для REQ-WRK-01 и всех парсеров; REQ-NFR-09 п.1 в части «модель тренировки».
Критерии авто: `total_duration_s`, `watts_at` для % FTP/ватт/рампы, `is_valid`. Ручных нет.

#### T-006 — Исполнитель интервалов `IntervalExecutor` `[game]` — `done`
Приёмка tester — коммит 1e19252 (`tests/unit/session/test_session_acceptance.gd`): подтверждены REQ-WRK-01 п.1–4, REQ-NFR-02 п.1, REQ-NFR-09 п.1, 4; попутно сторона исполнителя для WRK-05/06/07 (пауза, пропуск, множитель) — окончательное закрытие этих REQ остаётся за T-025..T-027.
Факт. `src/domain/interval_executor.gd` (`IntervalExecutor.new(plan, ftp, intensity)`, `tick(delta_sec)`, сигналы `step_changed`, `target_changed`, `second_elapsed`, `cue`, `finished`, методы `pause/resume/skip_step/stop/set_intensity`) и `tests/unit/domain/test_interval_executor.gd`. Время — через `tick(delta_sec)`, а не через `Clock` (согласовано с T-002). На приёмку — после сдачи developer.

Исходный план. `src/domain/interval_executor.gd` — `IntervalExecutor extends RefCounted`.
- Конструктор `(workout: Workout, clock: Clock)`; `start()`, `tick()` — вызывается внешним источником 1 Гц; исполнитель сам считает `elapsed_s` по `clock.now_ms()` (не по числу вызовов), так что пропущенные тики догоняются.
- Сигналы: `step_started(index: int, step: WorkoutStep)`, `step_finished(index: int)`, `workout_finished()` — ровно один раз; `tick_processed(elapsed_s: int, step_elapsed_s: int)`.
- Переход на том тике, где `step_elapsed_s >= duration_s`; план «60, 30, 90» завершается на тике 180.
- Геттеры: `current_step_index()`, `step_elapsed_s()`, `step_remaining_s()`, `total_elapsed_s()`, `total_remaining_s()`, `is_finished()`.
- Заделы для этапа 3 (без реализации логики UI): `skip_step()` (переход на следующем тике), `pause()`/`resume()` (на паузе `tick()` не продвигает время шага; учёт времени паузы — через смещение по часам), `stop()`.
- Никаких `Node`, `SceneTree`, `_process`.
Файлы: `src/domain/interval_executor.gd`.
Закрывает: REQ-WRK-01 п.1–4; REQ-NFR-02 п.1 (часть «исполнитель»); REQ-NFR-09 п.1 (исполнитель), п.4.
Критерии авто: все. Ручных нет.

#### T-007 — `WorkoutSession`: прогон плана на `FakeTrainer` `[game]` — `done`
Приёмка tester — коммит 1e19252: подтверждены REQ-WRK-01 п.5, REQ-DEV-09 п.6 (результат этапа 1 — тренировка проигрывается без железа), а также стороны сессии для REQ-WRK-02, WRK-05, WRK-06, WRK-07, WRK-08, REQ-DEV-08 п.2, 3, REQ-NFR-01 п.1, REQ-NFR-02 п.1, 2. Эти REQ окончательно закрываются в T-023..T-027 (HUD-привязка, рампы, FreeRide по В-10, сопротивление по `0x2AD6`, журнал событий). Открытый при приёмке вопрос WRK-02 п.5 (FreeRide в ERG) решён как В-10: на FreeRide станок переводится в режим сопротивления, на следующем шаге с целью ERG возвращается — реализация в T-025/T-026.
Факт. `src/session/workout_session.gd` (`WorkoutSession.new(workout, device, ftp, intensity)`, `start/tick/pause/resume/skip_step/stop`, `set_intensity`, `set_erg_enabled`, `set_resistance_level`, повторная отправка цели при возобновлении) и `src/session/sample_stream.gd` (`SampleStream.append(t, sample, hr, target, step, erg)`, `is_monotonic`, `count_with_power`), тесты `tests/unit/session/test_workout_session.gd`. Замечания менеджера для приёмки: (а) каталог `src/session/` отсутствует в структуре CLAUDE.md — либо вернуть в `src/domain/`, либо дополнить CLAUDE.md (вопрос Н-2 в разделе 5); (б) сессия уже содержит заделы этапа 3 (ERG вкл/выкл, сопротивление, пауза, `SampleStream`) — задачи T-023, T-025..T-027 переформулируются как «довести до критериев», а не «создать»; закрытие их REQ остаётся за соответствующими задачами. Критерий REQ-DEV-09 п.6 закрывается здесь.

Исходный план. `src/domain/workout_session.gd` — `WorkoutSession extends RefCounted`: собирает `IntervalExecutor`, `TrainerDevice`, `Clock`, FTP профиля.
- `start()` подключает устройство (`connect_device`, `request_control`), стартует исполнитель; `tick()` продвигает исполнитель и симулятор (если устройство — `FakeTrainer`, вызывает его `advance_to(now_ms)`; иначе ничего).
- На `step_started` отправляет `set_target_power(target.watts_at(0, ftp))` — минимальный ERG, нужный для результата этапа 1 (полные критерии WRK-02 закрываются в T-025, здесь — заделка).
- Накопление телеметрии в памяти (`get_telemetry_log()`), чтобы тест мог убедиться, что станок «ехал».
- Сигналы `session_finished()`, `state_changed(state)` (`IDLE`, `RUNNING`, `PAUSED`, `FINISHED`).
- Точка расширения для T-023/T-025/T-027: сессия владеет исполнителем и устройством, контроллеры подключаются к её сигналам.
Файлы: `src/domain/workout_session.gd`. Внимание: `src/domain/` не должен импортировать `src/devices/` — `TrainerDevice` передаётся как `RefCounted` с утиной типизацией или интерфейс `TrainerDevice` переносится в `src/domain/trainer_port.gd`, а `src/devices/trainer_device.gd` его наследует. Developer выбирает второй вариант, если статическая типизация иначе невозможна; решение отразить в отчёте.
Закрывает: REQ-WRK-01 п.5, REQ-DEV-09 п.6 (запуск сессии с `FakeTrainer` в тесте).
Критерии авто: план из 3 шагов проигрывается до `session_finished` на `FakeTrainer` с `ManualClock`; в журнале команд станка есть `0x05` на каждом переходе. Ручных нет.

#### T-008 — Зоны мощности и пульса `[game]` — `done`
Приёмка tester — коммит 1e19252: риск закрыт добавлением `HrZones.custom_bpm(boundaries_bpm)` (абсолютные границы в уд/мин для зон из Intervals.icu по В-5). Подтверждены REQ-PRF-02 п.2, 3, 5.
Факт. Коммит 0ca2af5 (вместе с T-005). Файлы: `src/domain/power_zones.gd` (`PowerZones.coggan(ftp)`, `PowerZones.custom(ftp, boundaries)`, `zone_of`, `zone_lower_watts`, `validate`), `src/domain/hr_zones.gd` (`HrZones.five_zone(max_bpm)`, `HrZones.custom(max_bpm, boundaries)`, `zone_of`), `src/domain/zones.gd` (фасад `Zones.power_zone(power, ftp)`, `Zones.hr_zone(bpm, max_hr)`); тесты `tests/unit/domain/test_zones.gd`. Токены цвета зон (`zone_color_token`) не реализованы — переносятся в T-028/T-031.
Риск по приёмке: `HrZones` задаёт границы только в % от `max_hr`, а по решению В-5 зоны пульса могут приходить из Intervals.icu в абсолютных уд/мин — добавить `HrZones.custom_bpm(boundaries_bpm)`. В работе у developer A вместе с D-1; после фикса — повторная приёмка.

Исходный план. `src/domain/zones.gd` — `Zones extends RefCounted`.
- `static func default_power_zones() -> PackedFloat32Array` — верхние границы Z1–Z6 в % FTP: 55, 75, 90, 105, 120, 150 (Z7 — выше 150).
- `static func default_hr_zones() -> PackedFloat32Array` — верхние границы Z1–Z4 в % от максимального пульса: 60, 70, 80, 90 (Z5 — ≥ 90). Границы трактовать так, чтобы при max HR 180: 107 → Z1, 108 → Z2, 126 → Z3, 144 → Z4, 162 → Z5 (REQ-HUD-04.1).
- `static func power_zone(watts: int, ftp: int, bounds: PackedFloat32Array) -> int` (1–7); при FTP 200: 110 → 1, 111 → 2, 150 → 2, 151 → 3, 180 → 3, 181 → 4, 210 → 4, 211 → 5, 240 → 5, 241 → 6, 300 → 6, 301 → 7. `watts <= 0` или `NO_DATA` → 1.
- `static func hr_zone(bpm: int, max_hr: int, bounds) -> int` (1–5); `NO_DATA` → 0 («—»).
- `static func zone_color_token(zone: int) -> StringName` — токены палитры `&"zone_1"`…`&"zone_7"` (серый, синий, зелёный, жёлтый, оранжевый, красный, фиолетовый); сами цвета — в теме UI (T-031).
Файлы: `src/domain/zones.gd`.
Закрывает: REQ-PRF-02 п.2, 3, 5 (п.1, 4 — в T-009). Основа для HUD-03/04, INT-05.3, LOC-04.5.
Критерии авто: все. Ручных нет.

#### T-009 — Модель профиля, валидация, `ProfileRepository` `[game]` — `done`
Факт. Коммиты f06193f (код + юнит-тесты) и f3a8f0f (фиксы по приёмке + приёмочные тесты `tests/unit/profiles/test_profiles_acceptance.gd`). Файлы: `src/profiles/profile.gd` (`Profile.validate()` возвращает коды `ERR_*` — ключи для переводов, не тексты; `max_hr` 100–220, по умолчанию не задан — В-1), `src/profiles/profile_repository.gd` (value-семантика: `get`/`list` возвращают копии, изменения применяются только через `update(profile)` после успешной валидации). Приёмка tester нашла 4 дефекта, все исправлены в f3a8f0f: (1) отклонённые валидацией правки утекали на диск; (2) `from_dict(null)` падал; (3) HR-зоны хранились в абсолютных уд/мин вместо объектов зон с `max_hr`; (4) см. T-010. Подтверждены REQ-PRF-01 п.1, 2, 5, 6; REQ-PRF-02 п.1, 4.

Исходный план.
- `src/profiles/profile.gd` — `Profile extends RefCounted`: `id: String` (UUID-подобный, генерируется один раз), `name`, `ftp: int` (50–600), `weight_kg: float` (20.0–250.0, шаг 0.1), `max_hr: int` (100–220, по умолчанию не задан — решение В-1), `power_zone_bounds`, `hr_zone_bounds`, `ftp_override_local: bool`, `ftp_source: String` («local» / «intervals:<дата>»), `resistance_level_pct: float` (для WRK-04, по умолчанию 50), `to_dict()/from_dict()`.
- `src/profiles/profile_validator.gd` — функции валидации, возвращающие `ValidationResult {ok: bool, message_key: StringName}`: имя 1–40 символов после `strip_edges()`, уникальность без учёта регистра, диапазоны FTP/веса. Сообщения — ключи переводов, не русские литералы.
- `src/profiles/profile_repository.gd` — `ProfileRepository extends RefCounted`: `list()`, `create(name) -> Profile`, `update(profile)`, `delete(id)` (отказ, если профиль последний), `set_active(id)`, `get_active() -> Profile`, `load()/save()` в `user://profiles.json` (путь инъецируется для тестов). Удаление каскадно чистит данные профиля через колбэки, регистрируемые T-010/T-011/T-041 (`add_on_delete_hook(callable)`), чтобы `src/profiles/` не зависел от хранилищ.
Файлы: три файла выше.
Закрывает: REQ-PRF-01 п.1, 2, 5, 6 (п.3, 4 — после T-011); REQ-PRF-02 п.1, 4.
Критерии авто: все перечисленные. Ручных нет.

#### T-010 — `SecureStore` `[game]` — `done`
Факт. Коммиты f06193f, f3a8f0f. Файлы: `src/storage/secure_store.gd` (интерфейс: `set_secret(key, value)`, `get_secret(key)`, `delete_secret(key)`, `has_secret(key)`; `create_default()` — выбор реализации; `attach_to_profiles(repository)` — регистрация хука каскадного удаления секретов профиля), `src/storage/memory_secure_store.gd` (`MemorySecureStore` — тесты), `src/storage/encrypted_file_secure_store.gd` (`EncryptedFileSecureStore` — `user://secrets.bin`, шифрование ключом устройства; **временная** реализация для dev-сборок в контейнере: не закрывает REQ-NFR-05 п.1/п.3 на магазинных платформах — Keychain/Keystore остаются `[вне контейнера]`, см. T-053 и раздел «Ручные проверки»). Дефект приёмки (4): при неверном ключе шифрования `secrets.bin` перезаписывался пустым — исправлено (файл не трогается, возвращается ошибка). Подтверждены REQ-NFR-05 п.1, 2 (контейнерная часть); REQ-PRF-03 п.1, 2, 3.

Исходный план. `src/storage/secure_store.gd` — интерфейс `SecureStore extends RefCounted`: `put(key: String, value: String)`, `get_value(key) -> String` (пусто, если нет), `delete(key)`, `delete_prefix(prefix)`, `has(key)`. Ключи формируются хелпером `SecureStore.key_for(profile_id, service, item)` → `"<profile_id>/<service>/<item>"` (`service` ∈ `intervals`, `strava`; `item` ∈ `api_key`, `access_token`, `refresh_token`, `expires_at`). `src/storage/in_memory_secure_store.gd` — реализация в памяти (тесты и dev-режим в контейнере). `src/storage/secure_store_factory.gd` — выбирает реализацию; в контейнере всегда in-memory; платформенные реализации описываются в `docs/secure_store.md` (T-053) и будут добавлены вне контейнера. Единственный модуль в `src/`, где допустимы проверки платформы помимо `src/devices/ble_*`. Регистрирует хук удаления профиля (`delete_prefix(profile_id + "/")`).
Файлы: три файла выше.
Закрывает: REQ-NFR-05 п.1, 2; REQ-PRF-03 п.1, 2, 3 (окончательно подтверждаются вместе с T-046, когда появляются реальные записи токенов).
Критерии авто: изоляция ключей по профилю, удаление только своего сервиса, отсутствие значений в файлах `user://`. Ручные: REQ-PRF-03 п.4, REQ-NFR-05 п.4.

#### T-011 — Реестр запомненных устройств `[game]` — `done`
Приёмка tester — коммит 71aca4c, дефектов нет; подтверждены REQ-PRF-04 п.2, 3, 4; REQ-PRF-01 п.3, 4; REQ-DEV-06 п.1 (хранение). Факт: `src/profiles/remembered_devices.gd` (`RememberedDevices`), хук каскадного удаления подключён к `ProfileRepository`.
Что сделать. `src/profiles/remembered_devices.gd` — `RememberedDevices extends RefCounted`: `remember_trainer(id, name)` (общий для устройства, хранится в `user://devices.json`), `remember_sensor(profile_id, id, name, kind)` (в данных профиля), `forget(profile_id_or_null, id)`, `trainer() -> Dictionary`, `sensors_for(profile_id) -> Array`. Хук удаления профиля удаляет только его датчики. В `ProfileRepository.delete` подключить хуки T-010 и T-011 — тем самым закрыть REQ-PRF-01 п.3, 4.
Файлы: `src/profiles/remembered_devices.gd`, правка `profile_repository.gd` (подтверждение удаления — флаг `confirmed: bool` в `delete(id, confirmed)`).
Закрывает: REQ-PRF-04 п.2, 3, 4; REQ-PRF-01 п.3, 4; REQ-DEV-06 п.1 (часть «хранение»).
Критерии авто: все. Ручных нет.

#### T-012 — Оболочка приложения и экран выбора профиля `[game]` — `done`
Приёмка tester — коммит 71aca4c, дефектов нет; подтверждены REQ-PRF-05 п.1, 2, 3. Наблюдения tester (не дефекты по критериям, вынесены владельцу как вопросы UX, раздел 5): имя длиннее 40 символов молча обрезается полем ввода вместо сообщения; после создания первого профиля нет автоперехода на HOME. Факт (имена отличаются от плана): `src/app/main.tscn` + `src/app/main.gd` (корневая сцена; `run/main_scene` задан в `project.godot`), `src/app/app_state.gd` (`AppState` — модель навигации, проверяется headless), `src/app/locale.gd` (выбор языка — задел NFR-08 п.3), `src/ui/profile_select/profile_select.tscn/.gd`, `src/ui/home/home.tscn/.gd`, `assets/i18n/strings.csv` (+ сгенерированные `strings.ru.translation`, `strings.en.translation`). Каталог `src/app/` — ещё один вне структуры CLAUDE.md (см. Н-2: предложить признать `src/app/` и `src/session/`).
Что сделать. `src/ui/app_shell.gd` + `src/ui/app_shell.tscn` — корневая сцена, `src/ui/navigation_state.gd` — чистая модель навигации (`enum Screen { CREATE_FIRST_PROFILE, SELECT_PROFILE, MAIN, DEV_WORKOUT, ... }`, `initial_screen(profile_count) -> Screen`, `can_open_main() -> bool`), проверяемая headless без сцены. Сцены `src/ui/profile_select.tscn` (+`.gd`) и `src/ui/profile_create.tscn` (+`.gd`), минимальная вёрстка `Control`. Все строки через `tr()`; завести `assets/i18n/translations.csv` (ключи, `ru`, `en`) и подключить в `project.godot` — задел для NFR-08. `project.godot`: главная сцена `app_shell.tscn`.
Файлы: перечисленные выше, `assets/i18n/translations.csv`, правка `project.godot`.
Закрывает: REQ-PRF-05 п.1, 2, 3; REQ-NFR-08 п.1 (заделка; закрытие — T-054).
Критерии авто: `initial_screen` для 0/1/2 профилей; главный экран недоступен без выбора. Ручные: REQ-PRF-05 п.4.

#### T-013 — `SessionTicker` и экран разработчика `[game]` — `done`
Приёмка tester — коммит 52d2261; подтверждены REQ-DEV-09 п.6, REQ-WRK-01 п.5, REQ-NFR-02 п.1. Сдано developer B в коммите e0a9ae4 (вместе с T-014). Факт: `src/session/session_ticker.gd` (`SessionTicker` — узел, вызывает `tick()` сессии по подставляемым часам, догон пропущенных секунд; системные часы по умолчанию), `src/ui/dev/dev_screen.tscn` + `dev_screen.gd` (экран разработчика: старт плана на `FakeTrainer`, метки шага/цели/мощности/каденса/остатка). Этим подтверждён результат этапа 1.
Что сделать. `src/ui/session_ticker.gd` — `Node`, который на каждом кадре (или по `Timer`) сравнивает `Time.get_ticks_msec()` с последней отметкой и вызывает `tick()` сессии столько раз, сколько полных секунд прошло (догон после заморозки кадра — основа REQ-NFR-02.2). `src/devices/system_clock.gd` — `Clock` на `Time.get_ticks_msec()`. `src/ui/dev_workout_screen.tscn` (+`.gd`) — кнопка «Старт», текстовые метки: шаг, цель, мощность, каденс, осталось; план — встроенный тестовый (3 шага) или из `tests/fixtures/`; устройство — `DeviceFactory.create_trainer(&"fake")` со сценарием «постоянная». Доступ с главного экрана при включённом `OS.is_debug_build()` или настройке `ovosch/dev_mode`.
Файлы: `src/ui/session_ticker.gd`, `src/devices/system_clock.gd`, `src/ui/dev_workout_screen.tscn/.gd`.
Закрывает: REQ-DEV-09 п.6, REQ-WRK-01 п.5 (в приложении), REQ-NFR-02 п.1.
Критерии авто: 60 вызовов `tick()` без `_process` дают корректные переходы; сцена инстанцируется headless. Ручных нет.

#### T-014 — Архитектурные и инфраструктурные проверки `[game]` — `done`
Приёмка tester — коммит 52d2261; дефекты приёмки (скрипт секретов пропускал шаблон; REQ-ID в части тестовых файлов) исправлены в 9d14313. Решение Н-5 (`AppState` — контракт навигации, от которого `src/ui/` зависеть может; оболочка `main.*`/`locale.gd` — ни от кого) внесено в REQ-NFR-06 п.3 и CLAUDE.md; тест архитектуры проверяет именно эту схему слоёв (включая `src/session/`). Сдано developer B в коммите e0a9ae4 (вместе с T-013). Факт (отличия от плана): вместо bash-скриптов `check_arch.sh`/`check_uids.sh` — GUT-тест `tests/unit/arch/test_architecture.gd` (15 проверок: платформенные вызовы только в `src/devices/ble*`/`src/storage/secure_store*`, домен без ссылок на `devices/ui/scene3d`, нативный код только в `native/ble/`, осиротевшие `.gd` без `.uid`, REQ-ID в тестовых файлах и т.д. — один источник правды, запускается в CI вместе с остальными тестами); `scripts/check_secrets.sh` (REQ-INF-03 п.4) и `scripts/check_commit_messages.sh` (REQ-INF-03 п.1); `ci.yml` — `fetch-depth: 0` (В-9) и два новых шага для этих скриптов. Инвентаризация REQ-INF-04 п.1 (REQ-ID в каждом тестовом файле) пока warning-only. REQ-NFR-09 п.2 (каждый публичный метод домена вызван тестом) не делался — выделено в отдельную задачу T-056 (исполнитель — tester). Из «Закрывает» этой задачи NFR-09 п.2 убран. До решения Н-2 тест архитектуры считает допустимыми `src/session/` и `src/app/`.
Что сделать (developer — скрипты, tester — тесты поверх них). `scripts/check_secrets.sh` — grep по шаблонам `client_secret`, `api_key=`, `Bearer `, `refresh_token` в `src/`, `tests/fixtures/`, `project.godot` с белым списком плейсхолдеров; `scripts/check_uids.sh` — осиротевшие `.gd` без `.gd.uid`; `scripts/check_arch.sh` — `OS.get_name()`/`OS.has_feature()` только в `src/devices/ble_*` и `src/storage/secure_store*`, в `src/domain/` нет `preload`/`load` на `src/devices|ui|scene3d`, C++/ObjC только в `native/ble/`. Для REQ-NFR-09.2 — `src/domain/` экспортирует список публичных методов через `ClassDB`/рефлексию скрипта, тест-инвентаризация (tester) сверяет с вызовами в тестах. Для REQ-INF-03.1 — `fetch-depth: 0` в `actions/checkout` (решение В-9, теперь критерий; правка `ci.yml` входит в задачу). Архитектурная проверка учитывает решение по Н-2 (`src/session/`).
Файлы: `scripts/check_secrets.sh`, `scripts/check_uids.sh`, `scripts/check_arch.sh`, правка `.github/workflows/ci.yml`.
Закрывает: REQ-INF-03 п.1–4, REQ-INF-04 п.1–3 (п.1 — в мягком режиме; строгий — T-056), REQ-NFR-06 п.1–3, REQ-NFR-09 п.4.
Критерии авто: все. Ручных нет.

#### T-056 — Инвентаризация публичных методов домена и строгая трассируемость `[game]` — `done`
Факт. Коммит 52a59dd (tester): 69/69 публичных методов `src/domain/` упоминаются в тестах; проверка REQ-INF-04 п.1 переведена в fail. Ограничение способа зафиксировано: проверка по имени метода — общие имена (`validate`, `reset`, `push`, `value`) могут быть «покрыты» вызовом одноимённого метода другого класса; строгий вариант (учёт класса-владельца через рефлексию скрипта в самом тесте) предложен владельцу как возможное ужесточение NFR-09 п.2 — см. раздел 5, Н-7. Подтверждены REQ-NFR-09 п.2; REQ-INF-04 п.1, 2.
Исходный план. Решение менеджера: REQ-NFR-09 п.2 — отдельная задача, а не хвост T-014, потому что это тест-инвентаризация (зона tester), а не код приложения. `tests/unit/arch/test_domain_inventory.gd`: собрать список публичных методов (`get_script().get_script_method_list()`, без `_`-префикса) для всех классов `src/domain/` и проверить, что каждый упоминается хотя бы в одном файле `tests/**/test_*.gd` (поиск по имени через `FileAccess`/`DirAccess`); список исключений — явный и пустой на старте. Перевести проверку REQ-INF-04 п.1 в `test_architecture.gd` из warning в fail (каждый `test_*.gd` содержит `REQ-[A-Z0-9]+-[0-9]+`). Добавить проверку REQ-INF-04 п.2: для каждого REQ, помеченного в `docs/backlog.md` как `done`, существует тест с его ID (парсинг таблицы задач бэклога). Если инвентаризация выявит непокрытые методы домена — не писать тесты «для галочки», а вынести список в отчёт: менеджер решит, нужны тесты или метод лишний.
Файлы: `tests/unit/arch/test_domain_inventory.gd`, правка `tests/unit/arch/test_architecture.gd`.
Закрывает: REQ-NFR-09 п.2; REQ-INF-04 п.1, 2 (строгий режим). Критерии авто: все. Ручных нет. Зависит от T-014; выполняется параллельно этапу 2.

### Этап 2 — BLE для iOS и macOS. Результат: реальное подключение к Tacx Neo

#### T-015 — Контракт `BleBridge` и `StubBleBridge` `[game]` — `done`
Приёмка tester — коммит a6889af (38/38 вместе с T-016). Н-3 закрыт: вводный абзац DEV в requirements.md приведён к именам кода. Сдано developer A в коммите 03cce42. Факт — каталог `src/devices/ble/`:
- `ble_bridge.gd` — `BleBridge`: методы `is_available()`, `start_scan(service_uuids)`, `stop_scan()`, `connect_peripheral(id)`, `disconnect_peripheral(id)`, `discover_services(id)`, `subscribe(id, service_uuid, char_uuid)`, `unsubscribe(...)`, `write(id, service_uuid, char_uuid, bytes, with_response)`, `read_characteristic(id, service_uuid, char_uuid)`, `get_adapter_state()`, `static create_default()`; сигналы `adapter_state_changed(state)`, `device_found(id, name, rssi, service_uuids)`, `connected(id)`, `disconnected(id, reason)`, `services_discovered(id, services)`, `notification(id, char_uuid, bytes)`, `characteristic_read(id, char_uuid, bytes)`, `write_done(id, char_uuid, ok)`, `error(id, code, message)`.
- `stub_ble_bridge.gd` — `StubBleBridge`: журнал вызовов (`calls_of`, `writes_to`), `emit_*` для всех событий, `set_device_services`, `set_read_value`, `fail_next_write/connect/read/control_point`, `pump()`.
- `native_ble_bridge.gd` — `NativeBleBridge`: обёртка над нативным классом `OvoschBle` (`ClassDB.class_exists(&"OvoschBle")`), пробрасывает сигналы 1:1.
- `ble_uuids.gd` — `BleUuids`: константы сервисов/характеристик, `SCAN_SERVICES`, `normalize/to_full/equals`, `device_kind(service_uuids)`.
Имена отличаются от вводного абзаца раздела DEV в requirements.md (`connect`/`value`/`write_result`) — вопрос Н-3. Карточки T-017..T-022 читать с этими именами; нативный класс в T-021 — `OvoschBle`, а не `BleBridgeNative`.

Исходный план. `src/devices/ble_bridge.gd` — `BleBridge extends RefCounted`, контракт из requirements.md (раздел DEV): методы `start_scan(service_uuids: PackedStringArray)`, `stop_scan()`, `connect_device(device_id)`, `disconnect_device(device_id)`, `subscribe(device_id, char_uuid)`, `write(device_id, char_uuid, bytes: PackedByteArray, with_response: bool)`, `read_characteristic(device_id, service_uuid, char_uuid)` (решение В-2); сигналы `device_found(id, name, rssi, service_uuids)`, `connected(id)`, `disconnected(id, reason)`, `value(id, char_uuid, bytes)`, `write_result(id, char_uuid, ok)`, `characteristic_read(device_id, char_uuid, bytes)`. `src/devices/stub_ble_bridge.gd` — скриптуемая заглушка: `emit_device_found(...)`, `emit_value(...)`, журнал вызовов `calls: Array[Dictionary]`, настраиваемые ответы на `write` (ok/fail) и автоматический ответ Control Point. `src/devices/ble_bridge_factory.gd` — выбирает `BleBridgeNative` (если `ClassDB.class_exists("BleBridgeNative")`) или заглушку; единственное место платформенной проверки в `src/devices/`.
Закрывает: контракт для REQ-DEV-01..08; REQ-NFR-06 п.1.
Критерии авто: заглушка реализует весь контракт; журнал вызовов. Ручных нет.

#### T-016 — Кодеки BLE-характеристик `[game]` — `done`
Приёмка tester — коммит a6889af, 38/38; D-2 и насыщение 25.5 исправлены в 5c2e62f (В-11). Подтверждены REQ-DEV-02 п.2–5, REQ-DEV-03 п.1, REQ-DEV-04 п.1–3, REQ-DEV-05 п.1, REQ-DEV-07 п.2. Сдано developer A в коммите 03cce42 (вместе с T-015). Факт — `src/devices/ble/codecs/`: `ftms_codec.gd` (`FtmsCodec.decode_indoor_bike_data`, `encode_request_control/set_target_power/set_resistance_level/start/stop/pause`, `decode_control_point_response`, `decode_resistance_range`, `percent_to_resistance_level(percent, range)`, `decode_machine_status`, плюс `encode_*` для тестов), `hrs_codec.gd` (`HrsCodec`), `csc_codec.gd` + `csc_cadence_calculator.gd` (`CscCadenceCalculator.push/current/reset`), `cps_codec.gd` (`CpsCodec`), `battery_codec.gd` (`BatteryCodec`), `ble_bytes.gd` (`BleBytes` — чтение/запись LE). Приёмка tester нашла дефект **D-2** (в работе у developer A): (а) `CscCadenceCalculator` не выдаёт 0 после 3 с без оборотов (REQ-DEV-04 п.3); (б) `percent_to_resistance_level` без диапазона `0x2AD6` насыщается на 25.5 (переполнение uint8 в единицах 0.1 — 100 % должно давать уровень по `DEFAULT_RESISTANCE_MAX_LEVEL`, не 255×0.1; REQ-WRK-04 п.2). После фикса — повторная приёмка.

Исходный план. Чистые функции без состояния (кроме CSC, которому нужны предыдущие значения).
- `src/devices/ftms_codec.gd`: `parse_indoor_bike_data(bytes) -> Dictionary` по флагам (мощность sint16, каденс uint16×0.5, скорость uint16×0.01, пульс uint8), `parse_control_point_response(bytes) -> {opcode, result}`, `encode_request_control() -> [0x00]`, `encode_set_target_power(w) -> [0x05, lo, hi]` (250 → `05 FA 00`), `encode_set_resistance_level(level) -> [0x04, uint8 ×0.1]` (5.0 → `04 32`), `parse_resistance_range(bytes)` для `0x2AD6`, `parse_machine_status(bytes)`. UUID-константы `0x1826`, `0x2AD2`, `0x2AD9`, `0x2ADA`, `0x2AD6`.
- `src/devices/hrs_codec.gd`: `parse_heart_rate_measurement(bytes) -> {bpm, sensor_contact: int}` (`00 48` → 72; `01 48 00` → 72).
- `src/devices/csc_codec.gd`: `CscCadenceCalculator` с переполнением uint16/uint32, Δоборотов 3 при Δвремени 2048 → 90 rpm, 3 с без оборотов → 0.
- `src/devices/cps_codec.gd`: `parse_power_measurement(bytes)` (sint16 по смещению 2; `00 00 FA 00` → 250), crank data для каденса.
- `src/devices/battery_codec.gd`: `parse_level(bytes)`.
Закрывает: REQ-DEV-02 п.2–5; REQ-DEV-03 п.1; REQ-DEV-04 п.1–3; REQ-DEV-05 п.1; REQ-DEV-07 п.2 (разбор). Критерии авто: все. Ручных нет.

#### T-017 — `BleTrainer` `[game]` — `done`
Приёмка tester — перепрогон 38/38, коммит 327144b; подтверждены REQ-DEV-02 п.1, 3. Сдано developer A в коммите 5c2e62f (вместе с T-018); в 851c724 исправлены замечания приёмки — D-4, утечки подписок на сигналы моста, дедупликация событий. Факт: `src/devices/ble_trainer.gd` (не в `ble/`) — `BleTrainer.new(bridge: BleBridge)`; `TrainerFactory.create("ble")` возвращает `BleTrainer` только при доступном нативном мосте (`NativeBleBridge.is_native_available()`), иначе — `FakeTrainer`; `TrainerFactory.create_ble(bridge)` — для инъекции `StubBleBridge` в тестах.
Исходный план. `src/devices/ble/ble_trainer.gd` — `BleTrainer extends TrainerDevice` поверх `BleBridge`: `connect_device(id)` → `connect_peripheral` → на `connected` — `discover_services`, затем `subscribe` на `BleUuids.INDOOR_BIKE_DATA`, `FTMS_STATUS`, `FTMS_CONTROL_POINT`, затем `write` Request Control; `read_characteristic(SUPPORTED_RESISTANCE_RANGE)` → диапазон для `percent_to_resistance_level`; `notification` Indoor Bike Data → сигнал `telemetry(TrainerSample)`, пульс из IBD → `heart_rate`; `set_target_power`/`set_erg_enabled`/`set_resistance_level` → `write` с `FtmsCodec`; ответ CP с `result != 0x01` → `error(CONTROL_POINT_REJECTED, …)`; `write_done(ok=false)` → `error(WRITE_FAILED, …)`; `disconnected` во время работы → `RECONNECTING` (логика повторов — T-024). `TrainerFactory` возвращает `BleTrainer` для BLE. Уточнение DEV-08.3 (requirements.md): после `connected` на паузе — только Request Control, цель уходит при `resume`.
Закрывает: REQ-DEV-02 п.1, 3. Критерии авто: последовательность подписок и Request Control на `StubBleBridge`, маппинг ошибок. Ручные: REQ-DEV-02 п.6, 7.

#### T-018 — BLE-датчики и `SensorHub` `[game]` — `done`
Приёмка tester — перепрогон 38/38 под Н-4, коммит 327144b; подтверждены REQ-DEV-03 п.2, 3; REQ-DEV-04 п.3 (по Н-4), 4; REQ-DEV-05 п.2, 3. Сдано developer A в коммите 5c2e62f (вместе с T-017); в 851c724 реализовано решение Н-4 (CSC: пакеты идут, обороты стоят → 0; пакеты пропали 3 с → «нет данных», `SensorHub` сразу уступает каденс следующему источнику), исправлены D-4, утечки, дедуп. Известное ограничение (не критерий этой задачи): `power_source` хранится в `SensorHub`, а не в профиле — по решению Н-8 сохранение закрывается в T-049. Факт: `src/devices/sensors/` — `sensor_device.gd` (`SensorDevice`: `kind()`, `connect_device(id)`, `disconnect_device()`, `tick(delta)`, `get_connection_state()`, `get_battery_level()`; сигналы `connection_state_changed`, `battery_level`, `error`), `ble_sensor_base.gd` (`BleSensorBase(bridge)` — общая логика discover/subscribe/battery/reconnect), `ble_heart_rate_sensor.gd` (сигнал `heart_rate`), `ble_cadence_sensor.gd` (сигнал `cadence`), `ble_power_meter.gd` (сигналы `power`, `cadence`), `ble_reconnect_policy.gd` (`BleReconnectPolicy(interval=5.0)`: `start/due/stop/next_attempt_sec` — переиспользовать в T-024). `src/devices/sensor_hub.gd` — `SensorHub extends TrainerDevice`: оборачивает станок и датчики в один `TrainerDevice` с приоритетами (пульс HRS > станок; каденс CSC > CPS > станок) и `power_source` («станок» / «измеритель»); для сессии прозрачен — `WorkoutSession` получает `SensorHub` как обычное устройство. Вопрос разработчика к requirements — Н-4 (DEV-04 п.3: «обороты стоят» и «пакеты пропали» неразличимы).
Исходный план. `src/devices/sensor_device.gd` (интерфейс датчика: сигналы `connection_state_changed`, `value_received(value, timestamp_sec)`, `battery_level_changed(percent)`; `connect_device/disconnect_device/tick`), `src/devices/ble/ble_heart_rate_sensor.gd`, `src/devices/ble/ble_cadence_sensor.gd`, `src/devices/ble/ble_power_meter.gd` (подписки `HEART_RATE_MEASUREMENT`, `CSC_MEASUREMENT`, `CYCLING_POWER_MEASUREMENT` через `subscribe(id, service, char)`; пульс без контакта → недостоверный, не эмитится). `src/devices/sensor_hub.gd` — объединяет источники в одну «текущую телеметрию»: пульс HRS > станок; каденс CSC > CPS > станок; мощность — `set_power_source(&"trainer" | &"power_meter")`, по умолчанию станок; выбор сохраняется в профиле. Выход — сигнал `merged_telemetry(sample)` для сэмплера T-023 и HUD.
Закрывает: REQ-DEV-03 п.2, 3; REQ-DEV-04 п.4; REQ-DEV-05 п.2, 3. Критерии авто: все. Ручные: REQ-DEV-03 п.4, REQ-DEV-04 п.5, REQ-DEV-05 п.4.

#### T-019 — Сканер и список устройств `[game]` — `done`
Приёмка tester экрана устройств — 12/12 на fce771b; подтверждены REQ-DEV-01 п.1–4, п.7. Сдано developer A в коммите 851c724 (вместе с T-020, T-021); дефект **D-5** (REQ-DEV-01 п.4: уход с экрана не останавливал сканирование) и п.7 (адаптер выключен / нативного модуля нет → «Bluetooth недоступен» по `BleBridge.is_available()`/`get_adapter_state()`, сканирование и подключение заблокированы — UX-3) исправлены в fce771b. Факт: `src/devices/ble/ble_scanner.gd` (`BleScanner` на `BleBridge.start_scan(BleUuids.SCAN_SERVICES)`, тип по `BleUuids.device_kind`, «недоступно» через 10 с), `src/ui/devices/devices_screen.gd/.tscn` (`DevicesScreen`), `AppState.Screen.DEVICES` (навигация по Н-5).
Что сделать. `src/devices/ble/ble_scanner.gd` — `start()` вызывает `start_scan(["1826","180D","1816","1818"])`; `device_found` → добавить/обновить запись `{id, name ("Без имени" — ключ перевода), rssi, kind по сервисам, last_seen_ms}`; `prune(now_ms)` — не было событий 10 с → `unavailable`; `stop()` при уходе с экрана и при подключении. `src/ui/devices_screen.tscn/.gd` — список с кнопками «подключить»/«забыть» (минимальная вёрстка).
Закрывает: REQ-DEV-01 п.1–4, п.7 (UX-3). Критерии авто: все. Ручные: REQ-DEV-01 п.5.

#### T-020 — Состояния подключения, заряд, автоподключение `[game]` — `done`
Приёмка tester — 12/12 на fce771b; подтверждены REQ-DEV-06 п.1–4, REQ-DEV-07 п.1–3. Сдано developer A в коммите 851c724 (вместе с T-019, T-021); мелочи приёмки (`ConnectionManager.connect_sensor()`/`set_power_source()` → `bool` вместо `push_error`; `trainer_id` очищается после `forget`) исправлены в fce771b. Факт: `src/devices/connection_manager.gd` (`ConnectionManager`; флаг `ticks_devices` — менеджер сам тикает устройства или оставляет это сессии, чтобы не тикать дважды). Ограничение: флаг автоподключения на устройство не сохраняется — по решению Н-8 хранится в реестре/профиле, закрывается в T-049. Заряд датчиков берётся из `SensorDevice.battery_level` (T-018), запоминание — через `RememberedDevices` (T-011, done).
Что сделать. `src/devices/connection_manager.gd`: состояния по REQ-DEV-07.1 от событий моста; после `connected` — `read_characteristic` Battery Level при наличии `0x180F` и подписка на нотификации, иначе «—»; после успешного подключения — `RememberedDevices.remember_*`; при открытии экрана тренировки — `start()` сканера и `connect_device` на запомненные сразу после `device_found`; таймер 30 с → «устройство не найдено»; «забыть» → `forget`.
Закрывает: REQ-DEV-06 п.1–4; REQ-DEV-07 п.1–3. Критерии авто: все. Ручные: REQ-DEV-06 п.5, REQ-DEV-07 п.4.

#### T-021 — Каркас GDExtension `[native-ble]` — `blocked: нужен macOS`
Статус. Код написан (851c724), приёмка в контейнере исчерпана: статическая сверка контракта `OvoschBle` ⇔ `BleBridge` пройдена (методы и сигналы 1:1), каркас собирается на Linux в CI `native-linux`. godot-cpp вендорится в `native/ble/godot-cpp` (1c75404, там же фикс «Argument list too long»). Блокер: критерий REQ-DEV-01 п.6 (сборка для macOS/iOS) — `[вне контейнера]`; снимается владельцем или CI job `native-macos` на macOS-раннере. Факт: `native/ble/SConstruct`, `native/ble/godot-cpp/`, `native/ble/ovosch_ble.gdextension` (`compatibility_minimum = 4.5` — у godot-cpp в апстриме нет ветки 4.7, используется godot-cpp 4.5), `native/ble/src/ovosch_ble.h/.cpp` (класс `OvoschBle`), `native/ble/src/ble_backend.h` (абстракция платформенного бэкенда — точка подключения CoreBluetooth/JNI/BlueZ/WinRT), `native/ble/src/null_backend.h/.cpp` (заглушка), `register_types.*`, `README.md`, `.gitignore` для `bin/`, `*.os`, `.sconsign.dblite`. Отличие от плана в лучшую сторону: каркас **собирается в контейнере** — CI job `native-linux` (Linux x86_64, `template_debug`), так что REQ-NFR-06 п.2 и целостность контракта проверяются автоматически; сборка для macOS/iOS остаётся `[вне контейнера]`. После написания T-022 обе задачи → `blocked: нужен macOS`.
Исходный план. `native/ble/SConstruct` (или `CMakeLists.txt`) с godot-cpp как git submodule или задокументированной зависимостью; `native/ble/ble_bridge.gdextension` с `entry_symbol` и путями библиотек для `macos`, `ios`; `native/ble/src/register_types.cpp`, `native/ble/src/ovosch_ble.h/.cpp` — класс `OvoschBle : public RefCounted` (имя ожидает `NativeBleBridge.NATIVE_CLASS`) с методами `start_scan`, `stop_scan`, `connect_peripheral`, `disconnect_peripheral`, `discover_services`, `subscribe`, `unsubscribe`, `write`, `read_characteristic`, `get_adapter_state` и сигналами `adapter_state_changed`, `device_found`, `connected`, `disconnected`, `services_discovered`, `notification`, `characteristic_read`, `write_done`, `error` — сигнатуры 1:1 с `src/devices/ble/ble_bridge.gd`; платформонезависимая реализация-заглушка (все методы — no-op с `UtilityFunctions::push_warning`), чтобы код компилировался на любой платформе; `native/ble/README.md` — как собрать на macOS (`scons platform=macos target=template_debug`), куда кладётся `.framework`/`.dylib`. В контейнере проверяется только статически: соответствие сигнатур контракту, наличие файлов. После написания — `blocked: нужен macOS`.
Закрывает: REQ-DEV-01 п.6 (`[вне контейнера]`), REQ-NFR-06 п.2. Критерии авто: нет. Вне контейнера: сборка для macOS и iOS.

#### T-022 — CoreBluetooth-реализация `[native-ble]` — `blocked: нужен macOS`
Статус. Код написан developer A в коммите fce771b: `native/ble/src/platform/apple/apple_backend.h/.mm` — бэкенд `BleBackend` на CoreBluetooth, выбирается в `SConstruct` для `platform=macos|ios`; `null_backend` остаётся для прочих платформ (CI `native-linux` зелёный). В контейнере проверено статически: `tests/unit/.../test_native_contract.gd` (соответствие методов/сигналов контракту `BleBridge`, наличие файлов, маршалинг событий через `call_deferred`). Компиляция Objective-C++ — только CI job `native-macos` (macOS-раннер) или владелец локально; затем ручные REQ-DEV-01 п.5, DEV-02 п.6–7 на Tacx Neo (раздел 4). Открытый вопрос владельцу Н-10: включать ли в iOS-сборку фоновый режим `bluetooth-central` (UIBackgroundModes), чтобы связь со станком не рвалась при сворачивании приложения — влияет на `Info.plist`/экспортный пресет (T-053) и на ревью App Store (NFR-07).
Исходный план. `native/ble/src/platform/apple/ble_bridge_apple.mm` (+ `.h`): `CBCentralManager` + делегаты; `adapter_state_changed` из `centralManagerDidUpdateState`; `start_scan` с `CBUUID` из `service_uuids`; `connect_peripheral` → `connected`; `discover_services` → discover services/characteristics → `services_discovered(id, {service: [chars]})`; `subscribe` → `setNotifyValue`; `write` → `writeValue:type:` с `withResponse`/`withoutResponse`, `write_done` из `didWriteValueForCharacteristic`; `read_characteristic` → `readValueForCharacteristic`, ответ — `characteristic_read` (отличать от нотификаций `notification` по ожидающему запросу чтения); `notification` из `didUpdateValueForCharacteristic`; `disconnected(id, reason)` из `didDisconnectPeripheral`; ошибки CoreBluetooth → `error(id, code, message)`. Все события маршалятся в главный поток Godot через `call_deferred`. Описание разрешений (`NSBluetoothAlwaysUsageDescription`) — в T-053. После написания — `blocked: нужен macOS`.
Закрывает: REQ-DEV-01 п.5, 6; REQ-DEV-02 п.6, 7 — все ручные/вне контейнера. Критерии авто: нет.

### Этап 3 — Тренировка и ERG. Результат: можно тренироваться

**Этап 3 закрыт по коду** (коммит c5d7c59): T-023, T-025..T-030 — `done`; T-024 и T-031 — в `review`. После их приёмки все REQ этапа 3 (WRK-02..08, HUD-01..09, NFR-01, NFR-03 п.1–2 — вместе с T-036, NFR-04) закрыты в контейнере; ручные проверки на Tacx Neo — в разделе 4.

#### T-023 — `SampleRecorder` 1 Гц `[game]` — `done`
Приёмка tester — 48/48 на пакет T-023/T-025/T-026/T-027, закоммичена в c5d7c59 вместе с фиксом D-6. Подтверждены REQ-WRK-08 п.1–6, REQ-NFR-02 п.1, 2. Сдано developer B в коммите bdddd4d. Факт: отдельного `SampleRecorder` нет — всё внутри `src/session/sample_stream.gd` и `src/session/workout_session.gd`; расчётная скорость — `src/domain/speed_model.gd` (`SpeedModel`, решение В-8; это же закрывает REQ-D3D-02 п.1–4 — T-050 сокращается до проверки опорных значений, см. карточку T-050).
Что сделать. `src/domain/sample.gd` — `Sample`: `t_s`, `power_w`, `heart_rate_bpm`, `cadence_rpm`, `speed_kmh`, `target_w`, `step_index`, `erg_on` (`NO_DATA` для отсутствующих). `src/domain/sample_recorder.gd` — принимает телеметрию (`on_power(value, ts)`, `on_heart_rate`, `on_cadence`, `on_speed`), на каждом тике сессии фиксирует сэмпл с последним значением за секунду; значение старше 5 с → «нет данных» (флаги `has_*`, как в `TrainerSample`); на паузе сэмплы не пишутся; метки монотонны с шагом 1 с; 600 с → 600 ± 1 сэмплов; время — через `tick(delta_sec)` без `_process`. При догоне после заморозки (T-013) записывает пропущенные секунды постфактум. Источник скорости (решение В-8): FTMS, если `has_speed`, иначе `SpeedModel` (T-050); `speed_source` фиксируется для метаданных заезда. Отправная точка — уже существующий `src/session/sample_stream.gd` (T-007): довести до критериев, не создавать заново.
Закрывает: REQ-WRK-08 п.1–6; REQ-NFR-02 п.1, 2. Критерии авто: все. Ручные: REQ-NFR-02 п.3.

#### T-024 — Переподключение без потери данных `[game]` (REQ этапа 2, выполняется после T-023) — `done`
Приёмка tester — 30/30 (вместе с T-031), закоммичена в 65715d4; подтверждены REQ-DEV-08 п.1–4. Сдано developer B в коммите c5d7c59. Факт: интеграционный сценарий `tests/integration/test_reconnect_flow.gd` (обрыв → RECONNECTING → восстановление → повторные Request Control / Set Target Power, сэмплы до обрыва целы); индикация обрыва на HUD — `HudModel.connection_text` (отображение — ручная DEV-08 п.5). Использованы `BleReconnectPolicy` (T-018) и уточнение DEV-08 п.3 (на паузе после `connected` — только Request Control).
Что сделать. В `connection_manager.gd`/`ble_trainer.gd`: `disconnected` во время сессии → `RECONNECTING`, `connect_device` каждые 5 с до успеха или конца сессии; сессия и `SampleRecorder` не останавливаются (`NO_DATA`, не 0); после `connected` в ERG — Request Control и Set Target Power текущей цели ≤ 1 с; сэмплы до обрыва сохраняются. Проверяется на `FakeTrainer` со сценарием `disconnect_at`.
Закрывает: REQ-DEV-08 п.1–4. Критерии авто: все. Ручные: REQ-DEV-08 п.5, 6.

#### T-025 — `ErgController`: цели, рампы, множитель, задержка ≤ 1 с `[game]` — `done`
Приёмка tester — 48/48, коммит c5d7c59; подтверждены REQ-WRK-02 п.1–5, REQ-WRK-07 п.1, 2, 3, 5, REQ-NFR-01 п.1, 2. Сдано developer B в коммите bdddd4d. Факт: отдельного `ErgController` нет — логика целей, рамп, множителя, FreeRide (В-10) и повтора при ошибке записи — внутри `WorkoutSession`.
Что сделать. `src/domain/erg_controller.gd`: подписан на `step_started` и `tick_processed` сессии; цель = `target.watts_at(progress, ftp) × multiplier`, округление до целого; на границе шага отправка немедленно (≤ 1 с по журналу `FakeTrainer`); рампа — пересчёт каждую секунду, отправка при изменении ≥ 1 Вт и не чаще 1 раза в секунду; шаг без цели (FreeRide) — по решению В-10: `set_erg_enabled(false)` + `set_resistance_level(уровень пользователя)` не позже 1 с после начала шага, на следующем шаге с целью — `set_erg_enabled(true)` + цель в ту же секунду, переключатель ERG на HUD остаётся «вкл» (режим шага, не выбор пользователя); `error(WRITE_FAILED)`/`error(CONTROL_POINT_REJECTED)` → один повтор в пределах той же секунды. База — `WorkoutSession` из T-007 (довести, не создавать). Множитель: `set_intensity(pct)` 50–150 с шагом 5, по умолчанию 100; изменение в ERG → новая цель ≤ 1 с; значение сохраняется в сессии для заезда. Проверка на 20-интервальном плане и при «нагрузке на кадр» 200 мс (эмулируется задержкой тика).
Закрывает: REQ-WRK-02 п.1–5; REQ-WRK-07 п.1, 2, 3, 5; REQ-NFR-01 п.1, 2. Критерии авто: все. Ручные: REQ-WRK-02 п.6, REQ-NFR-01 п.3.

#### T-026 — Режим сопротивления и переключатель ERG `[game]` — `done`
Приёмка tester — 48/48, коммит c5d7c59; подтверждены REQ-WRK-03 п.1–5 (п.1 — состояние), REQ-WRK-04 п.1–3 (с учётом В-10, В-11). Сдано developer B в коммите bdddd4d. Факт: внутри `WorkoutSession` (`set_erg_enabled`, `set_resistance_level`), маппинг уровня — `FtmsCodec.percent_to_resistance_level`. Решение В-11: пользовательский уровень 0–100 % масштабируется линейно на кодируемый FTMS-диапазон 0..25.5 единиц (uint8 × 0.1) — если станок отдал `0x2AD6`, то на его `[min; max]`, иначе на 0..25.5; 100 % → максимум диапазона, насыщения на промежуточных значениях нет.
Что сделать. В `erg_controller.gd` (или `src/domain/load_mode.gd`): `erg_enabled` (по умолчанию `true`); `toggle_erg()` — одно действие; выключение → Set Target Resistance Level текущего уровня ≤ 1 с; включение → Set Target Power цели ≤ 1 с (с множителем); таймер и сэмплы не прерываются; уровень 0–100 % шаг 5, хранится в профиле; перевод % в единицы станка — `FtmsCodec.percent_to_resistance_level(percent, range)` с диапазоном из `0x2AD6` (читается `BleTrainer` в T-017) или `DEFAULT_RESISTANCE_MAX_LEVEL` без него (после фикса D-2); при включённом ERG изменение уровня сохраняется, но не отправляется. Различать пользовательское «ERG выкл» и режим FreeRide по В-10 (второе не меняет состояние переключателя). Переключения ERG записываются в журнал событий сессии (для LOC-01.4).
Закрывает: REQ-WRK-04 п.1–3; REQ-WRK-03 п.1 (состояние), 2–5. Критерии авто: все. Ручные: REQ-WRK-03 п.1 (отображение), REQ-WRK-04 п.4.

#### T-027 — Управление сессией: пауза, завершение, пропуск, события, экран `[game]` — `done`
Приёмка tester — 48/48, коммит c5d7c59; подтверждены REQ-WRK-05 п.1–4, REQ-WRK-06 п.1–4, REQ-NFR-04 п.1, 2. Дефект **D-6** (REQ-WRK-05 п.2: у события паузы `until_sec == at_sec`) исправлен в c5d7c59: событие паузы хранит `at_sec`, `until_sec` и `duration_sec` по реальному времени, в метаданных сессии — `paused_total_sec` (нужно T-044 для `total_elapsed_time` vs `total_timer_time` в FIT). Формулировка критерия — Н-9 у requirements. Сдано developer B в коммите bdddd4d. Факт: пауза/возобновление/досрочное завершение/пропуск и журнал событий — внутри `WorkoutSession`; адаптер запрета гашения экрана вынесен в `src/ui/hud/keep_awake.gd` (`KeepAwake`, коммит bcbbe7c вместе с T-028) — REQ-NFR-04 п.1, 2 принимать по нему.
Что сделать. В `workout_session.gd` + `interval_executor.gd`: `pause()`/`resume()` (остаток шага сохраняется; при возобновлении повторная отправка цели/уровня ≤ 1 с; на паузе на станок ничего не посылается, телеметрия не пишется, время паузы не входит в elapsed — решение В-4; базовая реализация уже есть в `WorkoutSession` из T-007 — довести до критериев); `finish_early(confirmed)` — заезд помечается `ended_early`; `skip_step()` — переход на ближайшем тике, новая цель ≤ 1 с, пропуск последнего завершает тренировку; `src/domain/session_events.gd` — журнал событий `{type: PAUSE_START|PAUSE_END|SKIP|ERG_ON|ERG_OFF|DISCONNECT|RECONNECT, t_s, step_index}`. `src/ui/screen_keep_awake.gd` — адаптер с инъецируемым вызовом `DisplayServer.screen_set_keep_on`; включается на старте сессии, сохраняется на паузе, снимается при завершении и уходе с экрана.
Закрывает: REQ-WRK-05 п.1–4; REQ-WRK-06 п.1–4; REQ-NFR-04 п.1, 2. Критерии авто: все. Ручные: REQ-WRK-05 п.5, REQ-NFR-04 п.3.

#### T-028 — Модель HUD «мощность» `[game]` — `done`
Приёмка tester — коммит 973b7c0 (31 тест на T-028..T-030, дефектов нет); подтверждены REQ-HUD-02 п.1–3, HUD-03 п.1–3, HUD-04 п.1–2, HUD-09 п.1–4. Сдано developer B в коммите bcbbe7c (одним заходом с T-029, T-030). Факт: вместо четырёх файлов карточек T-028..T-030 — один `src/ui/hud/hud_model.gd` (`HudModel`: сглаживание через `PowerSmoother`, отклонение, зоны, форматы времени, обратный отсчёт, подсказки, сегменты прогресса на `Workout.segments()`), `src/ui/hud/zone_palette.gd` (`ZonePalette` — токены/цвета зон Z1–Z7, REQ-HUD-03 п.2), `src/ui/hud/keep_awake.gd` (`KeepAwake`, для T-027/NFR-04). Приёмка — по REQ каждой из трёх задач, тесты могут быть в одном файле.
Исходный план. `PowerSmoother` уже реализован в T-005 (`src/domain/power_smoother.gd`: `push`, `push_missing`, `value`, `has_value`) — здесь только подключить его к HUD и подтвердить REQ-HUD-09 п.4 (в поток WRK-08 и FIT идут несглаженные значения). По решению В-1: если `max_hr` профиля не задан — зона пульса «—» без цвета. `src/ui/hud_power_model.gd` — `deviation_state(actual, target)`: `IN_TARGET` при |факт − цель| ≤ max(5 % цели, 10 Вт), иначе `ABOVE`/`BELOW`, `HIDDEN` при цели «—»; `power_zone` и `hr_zone` через `Zones` профиля; 0/`NO_DATA` → Z1 / «—»; `NO_DATA` пульса → «—» без цвета.
Закрывает: REQ-HUD-09 п.1–4; REQ-HUD-02 п.1–3; REQ-HUD-03 п.1–3; REQ-HUD-04 п.1, 2. Критерии авто: все. Ручные: REQ-HUD-02 п.4, REQ-HUD-03 п.4, REQ-HUD-04 п.3.

#### T-029 — Модель HUD «время и подсказки» `[game]` — `done`
Приёмка tester — коммит 973b7c0; подтверждены REQ-HUD-05 п.1–3, HUD-06 п.1–2, HUD-08 п.1–3. Сдано в коммите bcbbe7c как часть `HudModel` (см. T-028).
Исходный план. `src/ui/hud_time_model.gd`: `format_elapsed(s)` (`мм:сс` до часа, далее `ч:мм:сс`), `format_countdown(remaining_s)` (`мм:сс`, на тике перехода — длительность нового шага), `is_about_to_change(remaining_s) -> remaining_s <= 5`, целочисленные пульс/каденс, скорость с одним знаком, «—» для `NO_DATA`; прошедшее время — без пауз (из исполнителя). `src/ui/hud_cue_model.gd`: подсказка шага с его начала, подсказка с `offset_s` — с указанной секунды; скрытие через 10 с или при смене шага; обрезка > 120 символов с «…».
Закрывает: REQ-HUD-05 п.1–3; REQ-HUD-06 п.1, 2; REQ-HUD-08 п.1–3. Критерии авто: все. Ручные: REQ-HUD-05 п.4, REQ-HUD-06 п.3, REQ-HUD-08 п.4.

#### T-030 — Профиль плана: сегменты и точки `[game]` — `done`
Приёмка tester — коммит 973b7c0; подтверждены REQ-HUD-07 п.1–3, WRK-07 п.4, INT-05 п.1–3 (функции; отображение — T-040). Сдано в коммите bcbbe7c как часть `HudModel` поверх `Workout.power_points()`/`segments()` (T-005).
Исходный план. `src/domain/workout_profile.gd`: `segments(workout, ftp, multiplier) -> Array[{start_s, duration_s, target_w, zone}]` (сумма длительностей = длительность плана; рампа — сегмент с `start_w/end_w`); `points(workout, ftp) -> PackedVector2Array` (t, Вт) — ступени для постоянных шагов («10 мин 50 %, 5 мин 100 %» при FTP 200 → 100 Вт на [0; 600), 200 Вт на [600; 900)), линейный участок для рампы; `cursor(elapsed_s, total_s) -> float`. `src/ui/hud_progress_model.gd`: состояние сегментов `UPCOMING|CURRENT|DONE|SKIPPED` из событий сессии; пересчёт зон при изменении множителя.
Закрывает: REQ-HUD-07 п.1–3; REQ-WRK-07 п.4; REQ-INT-05 п.1–3 (функции; отображение — T-040). Критерии авто: все. Ручные: REQ-HUD-07 п.4.

#### T-031 — Сцена экрана тренировки (HUD) `[game]` — `done`
Приёмка tester — 30/30, закоммичена в 65715d4; подтверждены REQ-HUD-01 п.1–3, REQ-WRK-03 п.1 (состояние на HUD). Дефект приёмки — подпись состояния подключения формировалась во view на русском литерале — исправлен там же: `HudModel.connection_text` возвращает ключ перевода, `tr()` — во view (NFR-08 п.1). Сдано developer B в коммите c5d7c59 (вместе с T-024). Этап 3 закрыт полностью. Факт: `src/ui/workout/workout_screen.tscn/.gd` (экран тренировки на `HudModel`, `KeepAwake`, `SessionTicker`), `src/ui/workout/workout_progress_bar.gd` (полоса прогресса по `HudModel`/`Workout.segments()`), `HudModel.connection_text` (строка состояния связи — для DEV-08 п.5), кнопка «Тренировка на эмуляторе» на Home (`FakeTrainer` через `TrainerFactory`), хуки `session_finished` (точка подключения сохранения заезда — T-041/T-042) и `profile_updated` (FTP/зоны меняются без перезапуска экрана). Закрытие этапа 3 по коду: после приёмки T-031/T-024 все REQ этапа 3 закрыты.
Что сделать. `src/ui/workout_screen.tscn/.gd`: узлы `TargetPowerLabel` (главный, крупный), `ActualPowerLabel` с индикатором отклонения, `PowerZoneBadge`, `HrZoneBadge`, `HeartRateLabel`, `CadenceLabel`, `SpeedLabel`, `ElapsedLabel`, `CountdownLabel`, `ProgressBar` (кастомный `Control` по модели T-030), `CueLabel`, кнопки `ErgToggle`, `IntensityMinus/Plus`, `ResistanceMinus/Plus`, `Pause`, `Skip`, `Finish` (с подтверждением). Тема `assets/theme/hud_theme.tres`: размер шрифта цели ≥ 2× размера пульса/каденса; цвета зон `zone_1..zone_7`. Привязка к моделям T-028..T-030, `SessionTicker` из T-013, `ScreenKeepAwake` из T-027. Строки через `tr()`.
Закрывает: REQ-HUD-01 п.1–3; REQ-WRK-03 п.1 (состояние ERG на HUD). Критерии авто: тексты узлов после подачи сэмплов headless; сравнение размеров шрифта из темы. Ручные: REQ-HUD-01 п.4 и все «внешний вид» HUD-02..08.

### Этап 4 — Источники плана. Результат: план подтягивается автоматически или из файла

**Этап 4 закрыт по коду** (коммит 4b049e9): T-032..T-039 — `done` (приёмки 33/33 и 87/87); остаётся только экран T-040 (`in-progress`, developer B). Н-6 (сериализация `Workout` в домене) — выполнено.

#### T-032 — `HttpTransport` и мок `[integration]` — `done`
Приёмка tester — 33/33 на пакет T-032/T-033/T-034/T-036, закоммичена в 4b049e9. Сдано developer C в коммите ad5b364. Второй потребитель (Strava, T-046) уже использует этот транспорт — перенос в `src/integrations/http/` остаётся рекомендацией на рефакторинг, не блокирует. Факт: `src/integrations/intervals/http_transport.gd` (`HttpTransport` — интерфейс), `godot_http_transport.gd` (`GodotHttpTransport` на `HTTPRequest` — единственное место сетевого ввода-вывода), `mock_http_transport.gd` (`MockHttpTransport` — журнал, заготовленные ответы, offline, `Retry-After`). Размещение в `intervals/` допустимо до появления второго потребителя (Strava, T-046) — тогда перенести в `src/integrations/http/` без изменения API.
Что сделать. `src/integrations/http_transport.gd` — интерфейс `request(method, url, headers, body) -> HttpResponse {status, headers, body, error}` (асинхронно через `await`); `src/integrations/godot_http_transport.gd` — реализация на `HTTPRequest` (единственное место сетевого ввода-вывода в `src/`); `src/integrations/mock_http_transport.gd` — журнал запросов, очередь заготовленных ответов (по методу+URL-шаблону), режим `offline = true` (всегда сетевая ошибка), поддержка заголовка `Retry-After`, подменяемые часы. Фикстуры — `tests/fixtures/intervals/`, `tests/fixtures/strava/` (tester).
Закрывает: основа REQ-NFR-03 п.1, 2 (закрытие — T-036). Критерии авто: мок считает запросы, отдаёт ответы, offline. Ручных нет.

#### T-033 — Клиент Intervals.icu: авторизация и профиль атлета `[integration]` — `done`
Приёмка tester — 33/33 в 4b049e9; подтверждены REQ-INT-01 п.1–3, REQ-INT-06 п.1–4, 8 (в редакции В-13; п.5–7 — UI, T-057). Замечание приёмки учтено: при > 9 зон пульса в ответе — предупреждение и откат на зоны от `max_hr`, не ошибка. Сдано developer C в коммите ad5b364. Факт: `src/integrations/intervals/intervals_icu_client.gd` (`IntervalsIcuClient` — Basic-auth `API_KEY:<ключ>`, проверка ключа, события, атлет), `intervals_sync.gd` (`IntervalsSync` — перенос FTP/зон в `Profile` с учётом локального переопределения), поля профиля `Profile.ftp_source`, `zones_source`, `intervals_*` (athlete id, дата синхронизации). Решения разработчика приняты как **В-13**: зоны мощности из Intervals.icu приводятся к % FTP (если API отдаёт ватты — автоопределение по значениям > 100 и пересчёт через FTP атлета); зоны пульса — границы +1 (API отдаёт верхние границы включительно, модель `HrZones` — нижние); допускается 2–9 зон. Фикстуры `tests/fixtures/intervals/` (синтетические — Б-3). Парсер события — `IntervalsIcuWorkoutParser` (T-035).
Что сделать. `src/integrations/intervals/intervals_client.gd`: `set_credentials(athlete_id, api_key)` → заголовок `Authorization: Basic base64("API_KEY:<ключ>")` в каждом запросе; `verify() -> Result`: 401/403 → «ключ не принят», ключ не сохраняется; успех → ключ в `SecureStore` под ключом профиля; текст любой ошибки не содержит подстроку ключа, ключ не логируется. `fetch_athlete()` → FTP и зоны из ответа → `Profile` (если `ftp_override_local` — не менять; иначе обновить и выставить `ftp_source = "intervals:<дата>"`); по решению В-5: зоны мощности — список границ в ваттах любого количества (1–9) → `PowerZones.custom`, зоны пульса — из `sportSettings` в уд/мин → `HrZones.custom_bpm` (T-008), иначе от `max_hr`; нет FTP в ответе → локальное значение + предупреждение. Фикстура `tests/fixtures/intervals/athlete.json` (синтетическая до получения реальной — см. В-5).
Закрывает: REQ-INT-01 п.1–3; REQ-INT-06 п.1, 2, 3, 5. Критерии авто: все. Ручные: REQ-INT-01 п.4, REQ-INT-06 п.4.

#### T-034 — Intervals.icu: события календаря `[integration]` — `done`
Приёмка tester — 33/33 в 4b049e9; подтверждены REQ-INT-02 п.1–5. Сдано developer C в коммите ad5b364. Факт: в `IntervalsIcuClient` + `src/integrations/intervals/intervals_plan_service.gd` (`IntervalsPlanService` — «план на сегодня»: запрос событий за локальную дату, фильтр велотренировок, состояния «нет тренировок» / «не удалось загрузить» / «повторить позже» по `Retry-After`, связка с `PlanCache`).
Что сделать. `intervals_client.fetch_today_events(today: String)` — `oldest = newest = YYYY-MM-DD` локальной даты; фильтр: категория «тренировка» с велосипедным типом; `[]` → `NO_WORKOUTS_TODAY`; 5xx/сетевая ошибка → `LOAD_FAILED` с возможностью повтора; 429 → `RETRY_LATER` не раньше `Retry-After` (или 60 с). Фикстура со смешанными событиями `tests/fixtures/intervals/events_mixed.json`.
Закрывает: REQ-INT-02 п.1–5. Критерии авто: все. Ручные: REQ-INT-02 п.6.

#### T-035 — Разбор тренировки Intervals.icu `[integration]` — `done`
Приёмка tester — 87/87 на пакет T-035/T-037/T-038/T-039, коммит 4b049e9; подтверждены REQ-INT-03 п.1–9 (п.9 — в редакции В-15: неподдерживаемыми считаются только токены цели — пульс, зона как цель, темп, `press lap`; свободные слова после валидной цели — подсказка шага), REQ-NFR-09 п.3. Дефекты приёмки Д-1/Д-2 исправлены в 4b049e9. Сдано в коммитах f5a628e, 24a99a4. Выполнено раньше T-034 — парсер не зависит от HTTP-клиента, зависимость в таблице скорректирована (только T-005). Факт: `src/integrations/workouts/intervals_icu_workout_parser.gd` (`IntervalsIcuWorkoutParser`), общий результат разбора `src/integrations/workouts/parse_result.gd` (`ParseResult` — `Workout` или ошибка с позицией/предупреждениями); фикстуры `tests/fixtures/workouts/intervals_event_doc.json`, `intervals_event_text.json`, `intervals_event_unsupported.json` (синтетические — Б-3).
Исходный план. `src/integrations/intervals/intervals_workout_parser.gd`: текстовое описание шагов Intervals.icu (`10m 65%`, `5m 250w`, `60-70%`, рампы `50-80%` с признаком ramp, повторы `3x`, каденс `85rpm`, текстовые строки как подсказки) → `Workout` с плоским списком шагов; диапазон → середина; суммарная длительность = заявленной ±1 с; неподдерживаемый элемент → `ParseError {line, column, message_key}`, частичный план не возвращается. Фикстуры `tests/fixtures/intervals/workout_*.json`.
Закрывает: REQ-INT-03 п.1–9; REQ-NFR-09 п.3 (Intervals). Критерии авто: все. Ручных нет.

#### T-036 — Кэш плана и работа без сети `[integration]` — `done`
Приёмка tester — 33/33 в 4b049e9; подтверждены REQ-INT-07 п.1–4, REQ-NFR-03 п.1, 2. Дефект приёмки D-7 исправлен там же; `cache_label` («из кэша, загружен <время>») — в локальном времени устройства. Факт: `src/integrations/intervals/plan_cache.gd` (`PlanCache`, файлы `user://plans/intervals_cache_<profile_id>/<дата>.json` — по файлу на дату, кэш другой даты не предлагается), пометка через `IntervalsPlanService`. Сдано developer C в коммите ad5b364.
Н-6 — выполнено (4b049e9): `Workout.to_dict()/from_dict()` и `Workout.metadata: Dictionary` в `src/domain/workout.gd` как чистые функции; `WorkoutSerializer` и `PlanCache` делегируют им; формат файлов не изменился, тесты T-035..T-039 зелёные.
Что сделать. `src/integrations/intervals/plan_cache.gd`: после успешной загрузки — план + `loaded_at` + дата в `user://profiles/<id>/plan_cache.json`; при ошибке сети — кэш на сегодняшнюю дату с пометкой «из кэша, загружен <время>»; кэш другой даты не предлагается; запуск/пауза/завершение по кэшированному плану — 0 запросов в моке (включая проверки токенов). Прогон сценария NFR-03 с `MockHttpTransport.offline = true` до сохранения заезда (сохранение появится в T-041 — критерий NFR-03.1 «сохранение» подтверждается повторно после T-041).
Закрывает: REQ-INT-07 п.1–4; REQ-NFR-03 п.1, 2. Критерии авто: все. Ручные: REQ-NFR-03 п.4.

#### T-037 — Парсер ZWO `[integration]` — `done`
Приёмка tester — 87/87, коммит 4b049e9; подтверждены REQ-IMP-01 п.1–7 (п.2 — в редакции В-12: `MaxEffort` → FreeRide с предупреждением; `SolidState` и прочие неизвестные — ошибка), REQ-NFR-09 п.3. Факт: `src/integrations/workouts/zwo_parser.gd` (`ZwoParser`), фикстуры `tests/fixtures/workouts/simple.zwo`, `intervals_textevent.zwo`, `unknown_element.zwo`, `truncated.zwo`, `not_xml.zwo`. В-12 внесено в requirements.md (cadf416). Сдано в коммитах f5a628e, 24a99a4.
Исходный план. `src/integrations/import/zwo_parser.gd` на `XMLParser`: `Warmup`/`Cooldown`/`Ramp` → рампа `PowerLow→PowerHigh`; `SteadyState` → постоянная; `IntervalsT` → `Repeat` × (on/off); `FreeRide` → `Target.NONE`; доли FTP → %; `Cadence`, `CadenceLow/High` (середина) → каденс; `textevent` → `WorkoutCue(offset, message)`; `name/description/author` → метаданные; невалидный XML и неизвестный элемент (`MaxEffort`, `SolidState`) → `ImportError` с именем элемента и номером строки. Фикстуры `tests/fixtures/zwo/*.zwo` с ожидаемыми длительностями и числом шагов (tester).
Закрывает: REQ-IMP-01 п.1–7; REQ-NFR-09 п.3 (ZWO); основа REQ-IMP-05 п.2. Критерии авто: все. Ручных нет.

#### T-038 — Парсер .erg/.mrc `[integration]` — `done`
Приёмка tester — 87/87, коммит 4b049e9; подтверждены REQ-IMP-02 п.1–6, REQ-NFR-09 п.3. Сдано в коммитах f5a628e, 24a99a4. Факт: `src/integrations/workouts/erg_mrc_parser.gd` (`ErgMrcParser`), фикстуры `tests/fixtures/workouts/ramp_jump.erg`, `decimal_comma.erg` (запятая как десятичный разделитель — сверх критериев), `no_course_data.erg`, `non_monotonic.erg`, `empty.erg`, `sweet_spot_text.mrc`.
Исходный план. `src/integrations/import/erg_parser.gd`: секции `[COURSE HEADER]`/`[COURSE DATA]`/`[COURSE TEXT]`; пары «минуты значение» → шаги (равные значения — постоянный, разные — рампа); `.erg` — ватты, `.mrc` — % FTP по расширению; дробные минуты (2.5 → 150 с); `FTP` заголовка → `metadata`, не в профиль; `[COURSE TEXT]` → подсказки; нет `[COURSE DATA]` или немонотонное время → `ImportError`. Фикстуры `tests/fixtures/erg/`.
Закрывает: REQ-IMP-02 п.1–6; REQ-NFR-09 п.3 (erg/mrc). Критерии авто: все. Ручных нет.

#### T-039 — Точка входа импорта, ошибки, библиотека `[integration]` — `done` (без UI)
Приёмка tester — 87/87, коммит 4b049e9; подтверждены REQ-IMP-03 п.1, REQ-IMP-05 п.1–4, REQ-IMP-04 п.1–5 (п.4 — в редакции В-14: тот же файл с другим содержимым — отдельная запись; идентичное содержимое по хэшу — замена с сохранением `id` и предупреждением). Факт: `src/integrations/workouts/workout_library.gd` (`WorkoutLibrary`), `workout_serializer.gd` (`WorkoutSerializer` — после Н-6 делегирует `Workout.to_dict()/from_dict()`; фикстура `tests/fixtures/workouts/corrupted.json`), ошибки — через `ParseResult`. UI импорта (кнопка, `FileDialog`) — в T-040. Сдано в коммитах f5a628e, 24a99a4.
Исходный план. `src/integrations/import/workout_importer.gd`: `import_file(path) -> Result` — выбор парсера по расширению без учёта регистра, иное → ошибка; `src/integrations/import/import_error.gd` — `{file_name, kind, element, line, message_key}` и `to_user_message(tr)` без стека и внутренних имён классов; ошибки не вызывают ошибок движка. `src/profiles/workout_library.gd`: записи `{id, name, duration_s, source_file, imported_at, workout}` в данных профиля; библиотека A не видна в B; повторный импорт — отдельная запись; удаление не трогает заезды; запуск из библиотеки создаёт тот же `WorkoutSession`.
Закрывает: REQ-IMP-03 п.1; REQ-IMP-05 п.1–4; REQ-IMP-04 п.1–5. Критерии авто: все. Ручные: REQ-IMP-03 п.2 (диалог — вызывается из T-040). Вне контейнера: REQ-IMP-03 п.3, 4.

#### T-040 — Экран выбора тренировки и предпросмотра `[game]` — `in-progress`
Статус. У developer B (после T-051/T-052). Источники: `IntervalsPlanService` (план на сегодня / кэш с пометкой, T-034/T-036), `WorkoutLibrary` (T-039); график — `Workout.power_points()` + `ZonePalette`; импорт файла — `FileDialog` с фильтром `*.zwo, *.erg, *.mrc` (REQ-IMP-03 п.2); запуск → `WorkoutScreen` (T-031). Размещать в `src/ui/workout_picker/`, навигация через `AppState`.
Что сделать. `src/ui/workout_picker.tscn/.gd`: источники — план на сегодня (Intervals или кэш с пометкой) и библиотека (пометка источника); одна тренировка → сразу карточка без списка; две и более → список (название, длительность `мм:сс`/`ч:мм:сс`, нагрузка если есть); кнопка «Импортировать файл» → `FileDialog` с фильтром `*.zwo, *.erg, *.mrc`. `src/ui/workout_preview.tscn/.gd`: график по `WorkoutProfile.points` с окраской сегментов по зонам, ось времени в минутах, кнопка «Старт». Модель списка (`src/ui/workout_picker_model.gd`) проверяется headless.
Закрывает: REQ-INT-04 п.1–3; REQ-INT-05 п.1–3 (отображение). Критерии авто: модель списка/выбора. Ручные: REQ-INT-04 п.4, REQ-INT-05 п.4, REQ-IMP-03 п.2.

### Этап 5 — Хранилище. Результат: заезды сохраняются и экспортируются

Состояние: T-041, T-042, T-044 — сданы в 59f1fe1, в `review`; T-043 (серии графиков) и T-045 (экраны) — `in-progress` у developer D. `RideSummary` реализован в T-041 — REQ-LOC-04 принимается там.

#### T-041 — `RideRepository` `[integration]` — `review`
Статус. Сдано developer D в коммите 59f1fe1 (одним заходом с T-042, T-044), ждёт приёмки tester по REQ-LOC-01 п.1–4, REQ-PRF-04 п.1 и REQ-LOC-04 п.1–6 (`RideSummary` сделан здесь, а не в T-043). Факт: `src/storage/ride.gd` (`Ride` — метаданные, сэмплы, события, `paused_total_sec`, `speed_source`, поля Strava), `src/storage/ride_summary.gd` (`RideSummary` — средняя, NP, работа, средние пульс/каденс, время в зонах), `src/storage/ride_repository.gd` (интерфейс), `src/storage/file_ride_repository.gd` (В-3: `user://rides/<profile>/<id>/meta.json` + `samples.bin`, индекс `index.json`). Замер: `list()` для 500 заездов — 26 мс (REQ-LOC-02 п.2 с запасом). План в заезде — через `Workout.to_dict()` (Н-6). Хук `session_finished` экрана тренировки (T-031) — точка входа сохранения.
Что сделать. `src/storage/ride.gd` — `Ride {id, profile_id, started_at, workout_name, workout_source, ftp, weight_kg, intensity_pct, ended_early, samples: Array[Sample], events, strava_status, strava_activity_id, strava_error}`. `src/storage/ride_repository.gd` — интерфейс `save(ride)`, `get_ride(id)`, `list(profile_id) -> Array[RideSummary]` (по дате убыв.), `delete(id)`, `list` для 500 заездов ≤ 1 с. Реализация `src/storage/file_ride_repository.gd` (решение В-3): каталог заезда `user://profiles/<id>/rides/<ride_id>/` с `meta.json` (метаданные, включая `speed_source` по В-8) и бинарными потоками (`samples.bin`, `events.json`), плюс индекс `rides_index.json` для быстрого списка. SQLite — допустимая замена реализации того же интерфейса позже. Хук удаления профиля — удалить его заезды.
Закрывает: REQ-LOC-01 п.1–4; REQ-PRF-04 п.1. Критерии авто: все. Ручных нет.

#### T-042 — Потоковая запись и восстановление `[integration]` — `review`
Статус. Сдано developer D в коммите 59f1fe1 (вместе с T-041, T-044), ждёт приёмки tester по REQ-LOC-07 п.1–4. Факт: `src/storage/ride_recorder.gd` (`RideRecorder` — подписан на `SampleStream`, сброс порциями не реже 10 с, маркер незавершённого заезда, восстановление). Замеры: тик со сбросом — 1 мс, финализация заезда на 3600 сэмплов — ≤ 16 мс (REQ-LOC-07 п.4 ≤ 50 мс с запасом).
Что сделать. `src/storage/ride_writer.gd`: подписан на `SampleRecorder`; сброс накопленных сэмплов в файл заезда не реже чем раз в 10 с сессионного времени, дозапись (append) без перезаписи; тик ≤ 50 мс при 600 сэмплах (запись маленьких порций, без сериализации всего заезда); маркер `in_progress`. `RideRepository.find_unfinished(profile_id)` — при старте приложения предлагается «сохранить как завершённый досрочно» или «удалить» (модель решения в `src/ui/recovery_prompt_model.gd`, диалог — минимальный). Тест сбоя: прервать сессию, создать новый экземпляр репозитория, проверить потерю ≤ 10 с.
Закрывает: REQ-LOC-07 п.1–4. Критерии авто: все. Ручные: REQ-LOC-07 п.5.

#### T-043 — Серии для графиков `[game]` — `in-progress`
Статус. У developer D (вместе с T-045). Сводка (`RideSummary`) уже реализована в T-041 (`src/storage/ride_summary.gd`) и принимается там по REQ-LOC-04; здесь остаётся `RideSeries` (REQ-LOC-03 п.1–3): серии (t, значение) без «нет данных», прореживание до ≤ 3600 точек с сохранением min/max, серия целевой мощности плана. Размещение — рядом с `RideSummary` в `src/storage/` или в `src/domain/` (чистые функции над сэмплами — предпочтительно домен).
Исходный план. `src/domain/ride_summary.gd`: средняя мощность (нули учитываются, `NO_DATA` — нет), NP (скользящее 30 с → ^4 → среднее → корень 4-й степени; 200 Вт 10 мин → 200; NP ≥ средней), работа кДж (200 Вт × 3600 с → 720), средний пульс/каденс, время в 7 зонах мощности и 5 зонах пульса по зонам на момент заезда (сумма = число сэмплов с данными), «—» без пульса. `src/domain/ride_series.gd`: серии (t, значение) без `NO_DATA`; прореживание до ≤ 3600 точек с сохранением min/max (LTTB или min-max по корзинам); серия целевой мощности плана.
Закрывает: REQ-LOC-03 п.1–3 (REQ-LOC-04 п.1–6 — в T-041). Критерии авто: все. Ручные: REQ-LOC-03 п.4.

#### T-044 — Кодировщик FIT `[integration]` — `review`
Статус. Сдано developer D в коммите 59f1fe1 (вместе с T-041, T-042), ждёт приёмки tester по REQ-LOC-05 п.1–4, REQ-STR-02 п.2, REQ-NFR-09 п.1. Факт: `src/integrations/fit/` — `fit_crc.gd` (`FitCrc`), `fit_definitions.gd` (`FitDefinitions` — номера сообщений/полей, invalid-значения), `fit_encoder.gd` (`FitEncoder` — `file_id`, `record`, `event` start/stop и паузы, `lap` на шаг, `session` с `sport=2`/`sub_sport=58`/`total_timer_time` без пауз по `paused_total_sec`/`avg_power`/`normalized_power`/`total_work` из `RideSummary`, `activity`), `fit_decoder.gd` (`FitDecoder` — для проверок; tester может использовать его в приёмочных тестах вместо собственного). Сигнатура для T-047 — `FitEncoder.encode(ride, summary) -> PackedByteArray`.
Что сделать. `src/integrations/fit/fit_encoder.gd` (+ `fit_crc.gd`, `fit_definitions.gd`): заголовок 14 байт с сигнатурой `.FIT` и CRC заголовка; сообщения `file_id` (type=activity), `record` на каждый сэмпл (`timestamp`, `power`, `heart_rate`, `cadence`, `speed`, `distance`), `event` start/stop (в т.ч. паузы), `lap` на каждый шаг, `session` (`sport=2`, `sub_sport=58`, `total_elapsed_time`, `total_timer_time` без пауз, `avg_power`, `normalized_power`, `total_work`), `activity`; отсутствующие значения — invalid по спецификации (0xFF/0xFFFF/…), не 0; CRC-16 файла. `encode(ride, summary) -> PackedByteArray`. Декодер для проверок пишет tester в `tests/`.
Закрывает: REQ-LOC-05 п.1–4; REQ-STR-02 п.2; REQ-NFR-09 п.1 (FIT). Критерии авто: все. Ручные: REQ-LOC-05 п.5.

#### T-045 — Экраны истории `[game]` — `in-progress`
Статус. У developer D (вместе с T-043). Данные — `RideRepository`/`RideSummary` (T-041), серии — T-043, экспорт — `FitEncoder` (T-044); статус Strava в списке/карточке — поля `Ride` + `UploadStatusStore` (T-048); действия Strava в карточке — T-049 (developer C), согласовать точку расширения карточки. Размещать в `src/ui/history/`, навигация через `AppState`.
Что сделать. `src/ui/history_list.tscn/.gd` (дата, название, длительность, средняя мощность, статус Strava), `src/ui/ride_detail.tscn/.gd` (графики мощности с целью, пульса, каденса по сериям T-043; сводка; кнопки «Экспорт FIT» → `FileDialog` сохранения с именем `<дата>_<название>.fit`, «Удалить» с подтверждением, «Выгрузить в Strava» — активируется в T-049). Удаление: заезд и сэмплы отсутствуют в репозитории, элемент очереди Strava удаляется (хук для T-048), запросов на удаление активности нет.
Закрывает: REQ-LOC-02 п.1, 2; REQ-LOC-06 п.1, 2; REQ-LOC-05 п.6 (вызов диалога). Критерии авто: модель списка, удаление. Ручные: REQ-LOC-02 п.3, REQ-LOC-06 п.4, REQ-LOC-05 п.6.

### Этап 6 — Strava. Результат: цикл замкнут

Состояние: T-046, T-048 — сданы в ce85da4, в `review`; T-047 — `review` каркаса (без FIT до приёмки T-044); T-049 — `in-progress` у developer C. Решение по секретам: переменные окружения читаются через `SecureStore.read_env()` в `src/storage/` — единственная точка доступа к окружению за секретами (NFR-05 п.1), `StravaConfig` обращается к ней, а не к `OS.get_environment()` напрямую.

#### T-046 — Strava OAuth 2.0 `[integration]` — `review`
Статус. Сдано developer C в коммите ce85da4 (одним заходом с T-048 и каркасом T-047), ждёт приёмки tester по REQ-STR-01 п.1–6, REQ-PRF-03 п.1–3, REQ-NFR-05 п.1, 2. Факт: `src/integrations/strava/strava_config.gd` (`StravaConfig` — `client_id`/`client_secret` из `user://secrets.cfg` или окружения через `SecureStore.read_env()`; в репозитории — `secrets.example.cfg.txt` с плейсхолдерами), `strava_oauth.gd` (`StravaOAuth` — URL авторизации с `activity:write`, обмен кода, обновление за 60 с до `expires_at`, один повтор при 401, отвязка; redirect — loopback `TCPServer` на `127.0.0.1:<port>/callback`, В-6), `strava_branding.gd` (`StravaBranding` — размеры/цвета кнопки и логотипа по брендбуку для T-049). Фикстуры `tests/fixtures/strava/` (tester).
Что сделать. `src/integrations/strava/strava_auth.gd`: `authorization_url(client_id, redirect_uri)` с `response_type=code`, `scope=activity:write,read`; `exchange_code(code)` — POST `grant_type=authorization_code`, сохранение `access_token`, `refresh_token`, `expires_at` в `SecureStore` профиля; `ensure_fresh_token()` — если до `expires_at` < 60 с → `grant_type=refresh_token`; 401 на API → одно обновление и повтор, повторный 401 → `REAUTH_REQUIRED`; `disconnect()` → удаление токенов; `client_id`/`client_secret` — по решению В-6: в dev-сборках из `user://secrets.cfg` или переменных окружения, в репозитории только `secrets.example.cfg` с плейсхолдерами; секрет не логируется. Приём redirect (В-6): на macOS/Linux/Windows — временный HTTP-сервер на `http://127.0.0.1:<port>/callback` (`TCPServer`), на iOS/Android — схема `ovoschrider://strava` (регистрация схемы — T-053).
Закрывает: REQ-STR-01 п.1–6; REQ-PRF-03 п.1–3 и REQ-NFR-05 п.1, 2 (окончательно). Критерии авто: все. Ручные: REQ-STR-01 п.8. Вне контейнера: REQ-STR-01 п.7, REQ-PRF-03 п.4.

#### T-047 — Выгрузка в Strava `[integration]` — `review` (каркас)
Статус. Каркас сдан developer C в коммите ce85da4: `src/integrations/strava/strava_uploader.gd` (`StravaUploader` — multipart с `file`/`data_type=fit`/`external_id`/`name`/`description`/`trainer=1`, опрос статуса), `upload_result.gd` (`UploadResult` — `PROCESSING/UPLOADED(activity_id)/FAILED(text)/DUPLICATE`), правила названия/описания по умолчанию. Тело FIT — через `FitEncoder.encode(ride, summary)` из T-044 (в `review`); tester принимает REQ-STR-02 п.3, 4 и REQ-STR-03 п.1–3 сейчас, REQ-STR-02 п.1 (реальный FIT в поле `file`) — после приёмки T-044 и подключения кодировщика (одна правка в `StravaService`, T-049). Полное `done` — вместе с T-049.
Что сделать. `src/integrations/strava/strava_uploader.gd`: `upload(ride) -> UploadResult` — multipart с `file` (FIT из T-044), `data_type=fit`, `external_id=<ride_id>`, `name`, `description`, `trainer=1`; 201 с `id` → `PROCESSING`; `poll_status(upload_id)` до `activity_id` → `UPLOADED` или `error` → `FAILED(text)`; ошибка с «duplicate» → `DUPLICATE` без повторов. Название: план или «Тренировка <дата>» (ключ перевода); описание: описание плана + строка с названием приложения; пользовательские правки `name/description` до выгрузки — параметры `upload`.
Закрывает: REQ-STR-02 п.1, 3, 4; REQ-STR-03 п.1–3. Критерии авто: все. Ручные: REQ-STR-02 п.5, REQ-STR-03 п.4.

#### T-048 — Очередь выгрузки и статусы `[integration]` — `review`
Статус. Сдано developer C в коммите ce85da4, ждёт приёмки tester по REQ-STR-04 п.1–6, REQ-STR-05 п.1–3, REQ-LOC-06 п.3, REQ-NFR-03 п.3. Факт: `src/integrations/strava/upload_queue.gd` (`UploadQueue` — `user://upload_queue_<profile>.json`, повторы 1/5/15/60 мин, далее ежечасно, `Retry-After`, одна выгрузка одновременно, порядок по дате заезда, пауза во время активной сессии), `upload_status_store.gd` + `memory_upload_status_store.gd` (`UploadStatusStore`/`MemoryUploadStatusStore` — интерфейс статусов и реализация для тестов; адаптер к `RideRepository` — в T-049). Открытые вопросы от приёмки: Н-11 (`Retry-After` в формате HTTP-даты), Н-12 (предел ежечасных повторов).
Что сделать. `src/integrations/strava/upload_queue.gd`: элемент очереди создаётся по завершении заезда в профиле с привязкой; хранится в `user://profiles/<id>/strava_queue.json`; повторы при сетевой ошибке/5xx через 1, 5, 15, 60 мин, далее каждые 60 мин (подменяемые часы); 429 → не раньше `Retry-After`; не более одной выгрузки одновременно, порядок по дате заезда; `enqueue_now(ride_id)` для ручной выгрузки; очередь не работает во время активной сессии. Статусы заезда `NOT_UPLOADED | QUEUED | PROCESSING | UPLOADED(activity_id) | FAILED(text) | DUPLICATE` пишутся в `RideRepository`; ссылка `https://www.strava.com/activities/<id>`. Удаление заезда удаляет элемент очереди.
Закрывает: REQ-STR-04 п.1–6; REQ-STR-05 п.1–3; REQ-LOC-06 п.3; REQ-NFR-03 п.3. Критерии авто: все. Ручные: REQ-STR-05 п.4.

#### T-049 — `StravaService`, привязка Strava на экране настроек и действия Strava в истории `[game]` — `in-progress`
Статус. У developer C. Состав по факту: `StravaService` (связка `StravaOAuth` + `UploadQueue` + `StravaUploader` + `FitEncoder`; адаптер `UploadStatusStore` → `RideRepository`; автопостановка заезда в очередь при сохранении, если профиль привязан и включён `Profile.strava_auto_upload` — REQ-STR-04 п.1), `StravaConnectButton` (по `StravaBranding`), раздел Strava на экране настроек T-057 (вместо заглушки), действия в карточке заезда T-045. Точки согласования: с developer D — хук сохранения заезда (`RideRepository.save` → `StravaService.on_ride_saved`) и слот действий в карточке; с developer A — слот раздела на экране настроек.
Пересечение с T-057. Экран настроек, привязка Intervals.icu, источник FTP/зон и настройки устройств (Н-8) ушли в T-057; здесь остаётся только Strava: раздел «Strava» на экране настроек (вместо заглушки из T-057 — кнопка «Connect with Strava» по брендбуку, статус привязки, «Отвязать») и действия в карточке заезда (`ride_detail`, T-045): «Выгрузить в Strava», правка названия/описания, статус и ссылка на активность.
Что сделать. `src/ui/accounts_screen.tscn/.gd`: ввод Athlete ID и API-ключа Intervals.icu с проверкой (T-033), отображение имени атлета, источник FTP («из Intervals.icu (дата)» / «локально») и переключатель «переопределить локально»; кнопка «Connect with Strava» (ассет и размеры по брендбуку, логотип «Powered by Strava»), статус привязки, «Отвязать». В `ride_detail`: «Выгрузить в Strava» для заездов не в статусе «выгружено», редактирование названия/описания перед выгрузкой, статус и ссылка на активность.
Закрывает: UI-части REQ-STR-04 п.5, REQ-STR-03 п.3, REQ-STR-05 п.2, REQ-INT-06 п.4. Критерии авто: модель экрана (headless). Ручные: REQ-INT-01 п.4, REQ-INT-06 п.4, REQ-STR-01 п.8, REQ-STR-05 п.4.

### Этап 7 — 3D-сцена. Результат: MVP готов

Состояние: T-050 — `done`; T-051, T-052 — сданы в 65715d4, в `review` у tester. Ручной замер FPS/draw calls (D3D-05 п.1, 3) — по методике `docs/perf_budget.md`, у владельца.

#### T-050 — Модель скорости `[game]` — `done`
Приёмка tester — коммит 973b7c0: REQ-D3D-02 п.1–4 подтверждены на `src/domain/speed_model.gd` (`SpeedModel`, создан в bdddd4d по В-8); REQ-WRK-08 п.5 (расчётная ветка) — там же. Нового кода не потребовалось. Ручная: REQ-D3D-02 п.5.
Исходный план. `src/domain/speed_model.gd`: `steady_speed_kmh(power_w, rider_kg)` — ровная дорога, CdA 0.32, Crr 0.004, велосипед 8 кг, ρ 1.225 (200 Вт/75 кг → 34 ± 3; 100 Вт → 26 ± 3; 300 Вт → 40 ± 3; 95 кг — меньше); `step(current_kmh, power_w, rider_kg, dt_s)` — инерционное приближение к установившейся: при 0 Вт с 30 км/ч до 0 за ≤ 30 с, изменение за сэмпл ≤ 5 км/ч при скачке 0 → 400 Вт. По решению В-8 — источник скорости в потоке WRK-08, когда станок не даёт `has_speed`; `SampleRecorder` (T-023) переключается на модель автоматически.
Закрывает: REQ-D3D-02 п.1–4; REQ-WRK-08 п.5 (расчётная ветка). Критерии авто: все. Ручные: REQ-D3D-02 п.5.

#### T-051 — Интерфейс трассы и зацикленная трасса `[game]` — `review`
Статус. Сдано developer B в коммите 65715d4 (вместе с T-052). Приёмка tester по REQ-D3D-03, D3D-06: один дефект **D-8** — `RideScene.set_track()` до `_ready()` не строит дорогу (трасса, заданная до входа в дерево, игнорируется `RoadBuilder`; ломает подмену трассы в тесте D3D-06 п.2). У developer B; после фикса → `done` вместе с T-052. Факт: `src/scene3d/track.gd` (`Track` — интерфейс), `track_sample.gd` (`TrackSample` — позиция/направление/нормаль в точке `s`), `loop_track.gd` (`LoopTrack` — замкнутая петля, ограниченное число активных секций), `environment_set.gd` (`EnvironmentSet` — ресурс окружения: материалы, параметры дороги/неба) + `default_environment.tres`, `road_builder.gd` (`RoadBuilder` — геометрия дороги по `Track`); `docs/scene3d.md` — абзац и схема интерфейсов. Подмена трассы/окружения — через ресурс и интерфейс, игровой цикл (`Rider`/`RideScene`) на конкретную сцену не ссылается.
Что сделать. `src/scene3d/track.gd` — интерфейс `Track`: `transform_at(s_m: float) -> Transform3D`, `length_m()`, `wrap(s_m)`; `src/scene3d/loop_track.gd` — замкнутая петля из сегментов с ограниченным числом активных секций (`MAX_ACTIVE_SEGMENTS`), 80 км непрерывного движения без «конца»; `src/scene3d/environment_loop.tscn` — простое окружение; `src/scene3d/rider_mover.gd` — переводит скорость (км/ч) в `s_m` и ставит велосипедиста по `Track.transform_at`, не зная конкретной сцены. `tests/` получат `TestTrack` (прямая) от tester. `docs/scene3d.md` — абзац и схема интерфейсов `Track` / `RiderMover` / телеметрия.
Закрывает: REQ-D3D-03 п.1, 2; REQ-D3D-06 п.1–3. Критерии авто: все. Ручные: REQ-D3D-03 п.3.

#### T-052 — Велосипедист, камера, педалирование, бюджет производительности `[game]` — `review`
Статус. Сдано developer B в коммите 65715d4 (вместе с T-051). Приёмка по REQ-D3D-01 п.1–2, D3D-04 п.1–3, D3D-05 п.2 пройдена; `done` вместе с фиксом D-8 (T-051). Факт: `src/scene3d/rider.gd` (`Rider` — движение по `Track`, анимация шатунов по каденсу), `ride_scene.tscn/.gd` (`RideScene` — велосипедист, дорога, камера от третьего лица), `perf_budget.gd` (`PerfBudget` — подсчёт узлов/материалов сцены против бюджета, проверка per-frame кода); `WorkoutScreen` (T-031) хостит `RideScene` в `SubViewport` — 3D идёт фоном под HUD; `project.godot`: `application/run/max_fps = 0`, `physics/common/physics_ticks_per_second = 60`; `docs/perf_budget.md` — бюджет и методика ручного замера. REQ-D3D-05 п.1 и п.3 (FPS и draw calls на устройстве) — ручной замер владельца по `docs/perf_budget.md`.
Что сделать. `src/scene3d/ride_scene.tscn` с узлами `Rider` (простая модель/капсула + шатуны), `Road`, `FollowCamera` (постоянное расстояние и высота ±0.1 м, велосипедист в frustum при 0–60 км/ч); `src/scene3d/pedal_animator.gd` — скорость анимации = каденс/60 об/с (90 → 1.5; 60 → 1.0), 0/`NO_DATA` → остановка, применение не позже следующего сэмпла. `project.godot`: `physics/common/physics_ticks_per_second` ≥ 60, `application/run/max_fps` = 0 или ≥ 60. `docs/perf_budget.md` — по решению В-7: бюджет узлов/материалов сцены (проверяется headless подсчётом `MeshInstance3D`/материалов), статическая проверка отсутствия аллокаций в per-frame коде (`_process`/`_physics_process` без `new()`/создания массивов), бюджет draw calls — для ручного замера на устройстве.
Закрывает: REQ-D3D-01 п.1, 2; REQ-D3D-04 п.1–3; REQ-D3D-05 п.2, 3 (в редакции В-7). Критерии авто: все перечисленные. Ручные: REQ-D3D-01 п.3, REQ-D3D-04 п.4, REQ-D3D-05 п.1 и замер draw calls.

### Этап 8 — Публикация iOS и macOS (в контейнере — документы и заготовки)

#### T-053 — Пакет публикации iOS/macOS `[docs]` — `in-progress`
Статус. У отдельного docs-агента (вместе с T-055). Учесть: Н-10 (фоновый режим `bluetooth-central` для iOS — пока не решён владельцем, в пресете заложить как переключаемый пункт с пояснением), UX-3 (сборки без нативного BLE-модуля не публикуются), схема `ovoschrider://strava` для iOS (В-6), `secrets.example.cfg.txt` и `SecureStore.read_env()` — описать в `secure_store.md` как dev-путь, не для магазинных сборок.
Что сделать. `docs/publishing/privacy_policy.md` (какие данные: пульс как данные о здоровье, мощность, каденс; где хранятся; куда передаются — Intervals.icu, Strava; как удалить); `docs/publishing/app_store_checklist.md` (Privacy Nutrition Labels, данные о здоровье, лицензии: Godot MIT, GUT MIT, godot-cpp MIT, прочие); `docs/ports/android.md` (Data Safety — заготовка, дополняется в T-055); `docs/publishing/app_store_checklist.md` и заготовка `export_presets.cfg` для macOS и iOS с `NSBluetoothAlwaysUsageDescription` (ru и en, непустые), типами документов `.zwo`, `.erg`, `.mrc`; `docs/publishing/intervals_icu_oauth.md` (шаги согласования, redirect URI, scope); `docs/publishing/strava_api_checklist.md` (брендбук кнопки/логотипа, заявка на ревью, лимит одного атлета до ревью); `docs/secure_store.md` (Keychain, Android Keystore, libsecret/Credential Manager — границы платформенной части).
Закрывает: REQ-NFR-07 п.1, 2, 4; REQ-IMP-03 п.3; REQ-INT-01 п.5; REQ-STR-01 п.7; REQ-NFR-05 п.3 — наличие файлов и разделов `[авто]`, остальное `[вне контейнера]`. Критерии авто: существование файлов/разделов, непустые строки описания BLE в пресете.

#### T-057 — Экран настроек `[game]` — `in-progress`
Статус. У developer A. Выделена из T-049/T-054: экран настроек нужен раньше Strava — для языка, синхронизации Intervals.icu и источника мощности. Замечания tester по WIP переданы developer: соблюдать Н-5 (экран зависит от `AppState`, не от `main.gd`/`locale.gd` напрямую — язык через модель настроек), NFR-05 (API-ключ Intervals.icu — только через `SecureStore`, не в `user://settings.json`), i18n (все строки через `tr()`, ключи в `strings.csv`). Раздел Strava — слот для `StravaConnectButton` из T-049 (developer C).
Что сделать. `src/ui/settings/settings_screen.tscn/.gd` (+ модель `settings_model.gd`, проверяемая headless), вход с Home, навигация через `AppState`. Разделы:
- **Язык** — ru/en через `Locale` (`src/app/locale.gd`): по умолчанию системный, если ru/en, иначе en; выбор сохраняется (`user://settings.json`) и применяется без перезапуска (REQ-NFR-08 п.3); форматы чисел/времени одинаковы в обоих языках (п.4 — на моделях T-029).
- **Профиль** — имя, FTP, вес, max HR, зоны мощности/пульса через `Profile.validate()` с кодами `ERR_*` → ключи переводов (REQ-PRF-02 п.1 — UI-часть); у FTP и зон — источник «из Intervals.icu (дата)» / «локально» по `ftp_source`/`zones_source` (REQ-INT-06 п.7 — ручная) и переключатель «переопределить локально» (`intervals_override_local`, REQ-INT-06 п.5, 6).
- **Intervals.icu** — Athlete ID и API-ключ → `IntervalsIcuClient.verify()` (401/403 → «ключ не принят», ключ не сохраняется), имя атлета после успеха, кнопка «Синхронизировать» → `IntervalsSync`, «Отвязать» → удаление только ключа Intervals.icu этого профиля из `SecureStore` (REQ-PRF-03 п.2).
- **Устройства** — источник мощности «станок»/«измеритель мощности» и флаг автоподключения на устройство — сохраняются в профиле/`RememberedDevices` и восстанавливаются при запуске; `SensorHub`/`ConnectionManager` читают их оттуда (решение Н-8, REQ-DEV-05 п.2).
- **Strava** — заглушка-раздел «скоро» (заполняется в T-049).
- **О программе** — версия, лицензии (Godot MIT, GUT MIT, godot-cpp MIT), ссылка на политику конфиденциальности (T-053).
Все строки — через `tr()`, ключи в `assets/i18n/strings.csv`.
Закрывает: REQ-NFR-08 п.3, 4; REQ-INT-06 п.5, 6 (авто), п.7 (ручная); REQ-PRF-03 п.2; REQ-DEV-05 п.2 (хранение); REQ-PRF-02 п.1 (UI). Критерии авто: модель настроек headless, сохранение/восстановление, изоляция удаления привязки. Ручные: REQ-INT-01 п.4 (имя атлета на реальном аккаунте), REQ-INT-06 п.7, REQ-NFR-08 п.5.

#### T-054 — Локализация ru/en: финальная инвентаризация `[game]`
Что сделать (после всех экранов: T-040, T-045, T-049, T-057). Выбор языка и его сохранение уже закрыты T-057; здесь — финальный проход: каждый ключ в `assets/i18n/strings.csv` имеет непустые `ru` и `en` (REQ-NFR-08 п.2); аудит `src/ui/` и `src/scene3d/` на кириллицу в литералах (`scripts/check_i18n.sh` или проверка в `test_architecture.gd`, REQ-NFR-08 п.1); подтверждение п.3, 4 на финальном наборе экранов; снятие неиспользуемых ключей.
Закрывает: REQ-NFR-08 п.1, 2 (п.3, 4 — подтверждение). Критерии авто: все. Ручные: REQ-NFR-08 п.5.

### Этапы 9–10 — Android, Linux и Windows (в контейнере — документы и заготовки)

#### T-055 — Порты BLE и Android-заготовки `[docs]` — `in-progress`
Статус. У отдельного docs-агента (вместе с T-053). Опираться на фактический контракт `BleBridge`/`BleBackend` (`native/ble/src/ble_backend.h`) и на `apple_backend.mm` как образец реализации бэкенда.
Что сделать. `docs/ports/README.md`: для Android (JNI, `BluetoothLeScanner`, `BluetoothGatt`), Linux (BlueZ D-Bus: `org.bluez.Adapter1`, `Device1`, `GattCharacteristic1`), Windows (WinRT `BluetoothLEAdvertisementWatcher`, `GattCharacteristic`) — точки реализации каждого метода и события контракта `BleBridge`, маршалинг событий в главный поток, различия в разрешениях; `native/ble/platform/android/AndroidManifest.xml.template` с `BLUETOOTH_SCAN` (`android:usesPermissionFlags="neverForLocation"`), `BLUETOOTH_CONNECT`, legacy `BLUETOOTH`, `BLUETOOTH_ADMIN`, `ACCESS_FINE_LOCATION` с `maxSdkVersion="30"`; дополнение `docs/ports/android.md` (Data Safety, данные о здоровье); раздел «Каналы распространения Linux/Windows — открытый вопрос» с вариантами (Steam, Flathub, Microsoft Store, прямая загрузка) и критериями выбора.
Закрывает: REQ-NFR-06 п.4; REQ-NFR-07 п.3, 4 (Android). Критерии авто: наличие файлов и разрешений. Вне контейнера: порты, ревью Google Play.

## 4. Ручные проверки владельца

Критерии, которые нельзя закрыть в контейнере. Tester не отмечает их пройденными; владелец проверяет на реальном Tacx Neo, датчиках, macOS и реальных аккаунтах. Группировка — по моменту, когда проверка становится возможной.

### После сборки GDExtension на macOS (T-021, T-022) — `[вне контейнера]`
- Сборка: `cd native/ble && scons platform=macos target=template_debug` (и `platform=ios`) по `native/ble/README.md`; компиляция `src/platform/apple/apple_backend.mm` в контейнере не выполнялась — первая реальная компиляция Objective-C++ будет у владельца или в CI `native-macos`. Ошибки компиляции возвращать developer как дефект T-022 (не блокирует остальной бэклог).
- Фоновый режим iOS (Н-10): если включён `bluetooth-central` — проверить, что при сворачивании приложения на iPhone телеметрия и ERG продолжают работать 5 мин; если не включён — что приложение корректно переподключается после возврата (T-024).
- REQ-D3D-05 п.1, 3 — ручной замер FPS и draw calls по методике `docs/perf_budget.md` (20-минутная тренировка с 3D в `SubViewport`, средний FPS ≥ 60, кадров > 33 мс ≤ 1 %; draw calls в бюджете) на эталонных устройствах (открытое решение 16).
- REQ-DEV-01 п.6 — GDExtension собирается для macOS и iOS (`scons platform=macos`/`ios` по `native/ble/README.md`; в контейнере подтверждена только сборка Linux в CI `native-linux` с godot-cpp 4.5, `compatibility_minimum = 4.5` — проверить, что Godot 4.7 загружает модуль и `NativeBleBridge.is_native_available()` возвращает `true`).
- REQ-PRF-03 п.4, REQ-NFR-05 п.3 — реализация Keychain хранит значение после перезапуска (после `docs/secure_store.md`).

### Из приёмки T-002..T-004 (отчёт tester, коммит 68e7064) — на Tacx Neo после сборки BLE
- REQ-DEV-08 п.5 — на HUD видна индикация обрыва (состояние RECONNECTING).
- REQ-DEV-08 п.6 — выключить и включить Tacx Neo во время тренировки: связь восстанавливается, заезд целый, цель повторно отправлена.
- REQ-WRK-02 п.6 — Neo реально меняет нагрузку на границе интервала.
- REQ-WRK-03 п.1 (отображение) — состояние ERG видно на HUD после одного действия.
- REQ-WRK-04 п.4 — изменение уровня сопротивления ощущается при педалировании.
- REQ-NFR-02 п.3 — при принудительном FPS 15 поток 1 Гц без пропусков.
- Сверка модели эмулятора с реальным Neo: время выхода на целевую мощность после Set Target Power (в `FakeTrainer` — ≤ 3 с до ±5 %); если у Neo заметно иначе — скорректировать константы эмулятора, чтобы приёмочные тесты NFR-01/WRK-02 отражали реальность.

### Из приёмки T-009/T-010 (коммит f3a8f0f) — защищённое хранилище
- REQ-PRF-03 п.4 — на macOS/iOS реализация Keychain хранит и возвращает ключ Intervals.icu и токены Strava после перезапуска приложения (в контейнере — только `EncryptedFileSecureStore`, временная реализация).
- REQ-NFR-05 п.3 — платформенные реализации (Keychain, Android Keystore, libsecret/Credential Manager) существуют и описаны в `docs/secure_store.md`; `EncryptedFileSecureStore` не считается выполнением этого критерия для магазинных сборок.
- REQ-NFR-05 п.4 — на macOS значение видно в Keychain Access после привязки и исчезает после отвязки.

### Из приёмки T-015/T-016 (коммит 03cce42) — после сборки GDExtension, на реальных устройствах
- REQ-DEV-01 п.5 — Tacx Neo появляется в списке сканирования в течение 5 с; п.6 — GDExtension (`OvoschBle`) собирается для macOS и iOS и подхватывается `NativeBleBridge`.
- REQ-DEV-02 п.6 — мощность, каденс, скорость из Indoor Bike Data реального Neo соответствуют педалированию (проверить разбор флагов `FtmsCodec.decode_indoor_bike_data` на реальных пакетах, снять дамп в `tests/fixtures/ble/`); п.7 — сопротивление меняется после Set Target Power.
- REQ-DEV-03 п.4 — реальный нагрудный датчик: формат uint8/uint16 и флаг контакта.
- REQ-DEV-04 п.5 — реальный датчик каденса: переполнение счётчиков, каденс 0 при остановке (после фикса D-2).
- REQ-DEV-05 п.4 — реальный измеритель мощности (crank data при наличии).
- REQ-DEV-07 п.4 — заряд батареи датчиков через `read_characteristic` Battery Level на экране устройств.
- REQ-WRK-04 п.4 — уровень сопротивления ощущается при педалировании. Замечание: прочитать у реального Neo `0x2AD6` (Supported Resistance Level Range) и сверить с `DEFAULT_RESISTANCE_MAX_LEVEL`; если Neo не отдаёт `0x2AD6` или даёт иной диапазон — скорректировать константу/маппинг в `FtmsCodec`.

### Из приёмок этапа 3 (коммиты 973b7c0, bdddd4d) и подключений (327144b, 851c724) — на macOS с Tacx Neo
- REQ-WRK-02 п.5 — FreeRide по В-10: при входе в шаг без цели Neo реально переходит в режим сопротивления (педалирование «свободное», нагрузка — уровень пользователя), на следующем шаге с целью ERG возвращается в ту же секунду; переключатель ERG на HUD при этом остаётся «вкл».
- REQ-WRK-02 п.6 — Neo меняет нагрузку на границе интервала; при рампе нагрузка растёт плавно, без рывков от посекундных команд.
- REQ-WRK-03 п.1 — одно нажатие переключает ERG, состояние видно на HUD; при выключении Neo переходит на фиксированное сопротивление ≤ 1 с.
- REQ-WRK-04 п.4 — уровни 0/25/50/75/100 % различимы на Neo; сверить с `0x2AD6` (В-11).
- REQ-WRK-05 п.5 (и п.6, если появится после Н-9) — на паузе Neo держит последнюю цель (В-4), при возобновлении цель уходит повторно; длительность паузы в заезде совпадает с реальной по часам.
- REQ-HUD-01 п.4, HUD-02 п.4, HUD-03 п.4, HUD-04 п.3, HUD-05 п.4, HUD-06 п.3, HUD-07 п.4, HUD-08 п.4 — внешний вид HUD (модель принята в 973b7c0; сцена — T-031): читаемость цели с 1.5 м, цвета зон `ZonePalette`, индикация отклонения, акцент «скоро смена» за 5 с, полоса прогресса с пройденными/пропущенными сегментами, подсказки 10 с.
- REQ-NFR-04 п.3 — `KeepAwake`: 15 мин без касаний во время тренировки — экран macOS/iOS не гаснет; после завершения — гаснет по системным настройкам.
- REQ-D3D-02 п.5 — визуальное ощущение скорости по `SpeedModel` (принято в bdddd4d): 200 Вт при 75 кг ≈ 34 км/ч выглядит правдоподобно; торможение до 0 за ≤ 30 с.
- REQ-DEV-01 п.5 — Tacx Neo в списке ≤ 5 с (`BleScanner`); п.6 — `OvoschBle` собирается для macOS/iOS из `native/ble/` с вендорённым godot-cpp (`compatibility_minimum = 4.5`) и загружается Godot 4.7.
- REQ-DEV-06 п.5 — повторный запуск с включённым Neo: `ConnectionManager` подключает запомненный станок без действий пользователя, датчики профиля — тоже; таймаут 30 с → «устройство не найдено».
- REQ-DEV-07 п.4 — состояния «подключение/подключено/переподключение» и заряд датчиков (Battery Level через `read_characteristic`) на экране устройств и HUD; у Neo без Battery Service — «—».

### На Tacx Neo и датчиках (этапы 2–3)
- REQ-DEV-01 п.5 — Tacx Neo в списке в течение 5 с после начала сканирования.
- REQ-DEV-02 п.6 — мощность, каденс, скорость меняются при педалировании; п.7 — сопротивление меняется после Set Target Power.
- REQ-DEV-03 п.4 — нагрудный датчик пульса на HUD.
- REQ-DEV-04 п.5 — реальный датчик каденса.
- REQ-DEV-05 п.4 — реальный измеритель мощности.
- REQ-DEV-06 п.5 — повторный запуск с включённым Tacx Neo подключается без ручных действий.
- REQ-DEV-07 п.4 — индикация подключения и заряда на HUD и экране устройств.
- REQ-DEV-08 п.5, 6 — индикация обрыва; выключить/включить Tacx Neo во время тренировки — связь восстанавливается, заезд целый.
- REQ-WRK-02 п.6 — Tacx Neo меняет нагрузку на границе интервала.
- REQ-WRK-03 п.1 (отображение) — состояние ERG видно на HUD.
- REQ-WRK-04 п.4 — изменение уровня сопротивления ощущается.
- REQ-WRK-05 п.5 — поведение станка на паузе соответствует решению владельца (В-4).
- REQ-NFR-01 п.3 — смена 150 → 250 Вт ощущается не позже 1 с (измерение по видео).
- REQ-NFR-02 п.3 — при FPS 15 поток 1 Гц без пропусков.
- REQ-NFR-04 п.3 — 15 мин без касаний, экран не гаснет (iOS/macOS).
- REQ-NFR-03 п.4 — тренировка до конца с выключенным Wi-Fi.
- REQ-LOC-07 п.5 — принудительное завершение приложения на macOS, заезд восстанавливается.

### Внешний вид экранов (на устройстве)
- REQ-PRF-05 п.4 — экран выбора профиля.
- REQ-HUD-01 п.4 — читаемость цели с 1.5 м; REQ-HUD-02 п.4, REQ-HUD-03 п.4, REQ-HUD-04 п.3, REQ-HUD-05 п.4, REQ-HUD-06 п.3, REQ-HUD-07 п.4, REQ-HUD-08 п.4 — внешний вид элементов HUD.
- REQ-INT-04 п.4 — список тренировок; REQ-INT-05 п.4 — график предпросмотра, ось в минутах; REQ-INT-06 п.4 — источник FTP на экране профиля.
- REQ-IMP-03 п.2 — системный диалог с фильтром `*.zwo, *.erg, *.mrc`.
- REQ-LOC-02 п.3, REQ-LOC-03 п.4, REQ-LOC-06 п.4 — список, графики, карточка заезда; REQ-LOC-05 п.6 — диалог сохранения с именем `<дата>_<название>.fit`.
- REQ-STR-05 п.4 — статусы выгрузки на экране.
- REQ-D3D-01 п.3, REQ-D3D-02 п.5, REQ-D3D-03 п.3, REQ-D3D-04 п.4 — качество камеры, ощущение скорости, окружение, синхронность педалирования.
- REQ-D3D-05 п.1 — 20-минутная тренировка на эталонных устройствах: средний FPS ≥ 60, кадров > 33 мс ≤ 1 %.
- REQ-NFR-08 п.5 — переполнение текста на ru и en.

### На реальных аккаунтах Intervals.icu и Strava
- REQ-INT-01 п.4 — после ввода ключа отображается имя атлета.
- REQ-INT-02 п.6 — реальная загрузка плана на сегодня.
- REQ-STR-01 п.8 — реальный вход и получение токена.
- REQ-STR-02 п.5 — активность типа Virtual Ride с мощностью, пульсом, каденсом.
- REQ-STR-03 п.4 — название и описание видны в Strava.
- REQ-LOC-05 п.5 — FIT принимается Strava и открывается в стороннем просмотрщике.
- REQ-NFR-05 п.4 — значение в Keychain Access появляется после привязки и исчезает после отвязки.

### Публикация — `[вне контейнера]`
- REQ-INT-01 п.5 — реализация OAuth Intervals.icu после согласования.
- REQ-STR-01 п.7 — брендбук, заявка на ревью Strava.
- REQ-IMP-03 п.3, 4 — типы документов в пресетах; «Открыть в…»/Share на устройстве.
- REQ-NFR-06 п.4 — порты BLE на Android, Linux, Windows.
- REQ-NFR-07 п.5 — ревью App Store, Mac App Store, Google Play.

## 5. Блокеры и вопросы к requirements

Блокеры среды (не требуют решения, фиксируются):
- Б-1. Задачи T-021, T-022 `[native-ble]` после написания кода переходят в `blocked: нужен macOS`; все критерии DEV-01 п.5, 6 и DEV-02 п.6, 7 — у владельца.
- Б-2. REQ-DEV-08 (этап 2) зависит от `SampleRecorder` (REQ-WRK-08, этап 3), поэтому T-024 выполняется после T-023; этап 2 формально закрывается только вместе с T-024.
- Б-3. Фикстуры Intervals.icu (открытое решение 19) — до получения реальных ответов с аккаунта владельца тесты INT идут на синтетических данных по публичной документации API; при получении реальных фикстур задачи T-033..T-035 возвращаются в `review`.

Открытые вопросы агенту requirements (Н-1..Н-6, Н-8, Н-9 решены — см. «Решено»):
- Н-11 (владельцу/requirements; от developer C, T-048). `Retry-After` поддерживается только в секундах; формат HTTP-даты (`Retry-After: Wed, 21 Oct 2026 07:28:00 GMT`) не разбирается — Strava и Intervals.icu отдают секунды. Предложение: подтвердить, что поддержка HTTP-даты не нужна в MVP (при неразобранном заголовке — откат на 60 с), и зафиксировать в REQ-INT-02 п.5 / REQ-STR-04 п.3.
- Н-12 (владельцу/requirements; от developer C, T-048). REQ-STR-04 п.2: «далее каждые 60 мин до успеха или ручной отмены» — очередь повторяет бесконечно, пока пользователь не отменит. Нужен ли предел (предложение менеджера: 7 суток, после — статус «ошибка: превышено число попыток» с возможностью ручной постановки заново из карточки заезда, STR-04 п.5)? Влияет на критерий п.2 и перечень статусов STR-05 п.1.
- Н-7 (от tester, T-056). Инвентаризация NFR-09 п.2 проверяет вызов метода по имени, без учёта класса-владельца — общие имена могут давать ложное покрытие. Предложить владельцу: ужесточить критерий до «каждый публичный метод каждого класса `src/domain/` вызывается в тесте именно на экземпляре/классе-владельце» (проверка через рефлексию скрипта) или оставить текущий способ как достаточный для MVP.
- Н-10 (владельцу; от developer A, T-022). Фоновый режим iOS `bluetooth-central` (UIBackgroundModes в `Info.plist`): без него при сворачивании приложения на iPhone/iPad связь со станком и датчиками прерывается и ERG перестаёт управляться; с ним — обязательное обоснование при ревью App Store (NFR-07) и дополнительная строка в описании использования Bluetooth. Предложение менеджера: включить для iOS (тренировка 1 ч — реалистично уводить экран в фон на звонок), на macOS не требуется; решение нужно до T-053 (экспортные пресеты).

### Вопросы UX владельцу (наблюдения tester при приёмке T-012, коммит 71aca4c; критериям не противоречат)
- UX-1. Поле имени профиля молча обрезает ввод длиннее 40 символов (`max_length`), сообщения нет. REQ-PRF-01 п.1 требует сообщение только для пустого имени. Оставить обрезку или показывать подсказку «не более 40 символов»?
- UX-2. После создания первого профиля приложение остаётся на экране создания/выбора, автоперехода на HOME нет; REQ-PRF-05 п.3 говорит только «показывается создание первого профиля». Сделать автопереход после создания?
- UX-3 — принято, перенесено в «Решено» (реализуется в фиксе D-5, T-019).

### Решено (агент requirements, коммит a023c87; внесено в requirements.md с пометкой «решение менеджера, подтвердить владельцу»)
- В-1 (PRF-02, HUD-04) — поле профиля `max_hr`, валидация 100–220, по умолчанию пусто → зоны пульса недоступны, HUD-04 показывает «—»; по умолчанию 5 зон от max HR (60/70/80/90 %), переопределяются вручную или из Intervals.icu. Учтено в T-009, T-028.
- В-2 (контракт моста) — добавлена операция `read_characteristic(device_id, service_uuid, char_uuid)` с ответом `characteristic_read(device_id, char_uuid, bytes)`; для Battery Level `0x2A19` и Supported Resistance Level Range `0x2AD6`. Учтено в T-015, T-020, T-021, T-022, T-026.
- В-3 (LOC) — отклонение от ТЗ зафиксировано: MVP — файловое хранилище за интерфейсом `RideRepository` (каталог заезда: `meta.json` + бинарные потоки); SQLite — допустимая реализация того же интерфейса позже; критерии — через интерфейс. Учтено в T-041.
- В-4 (WRK-05) — на паузе на станок ничего не посылается (цель — последняя отправленная), телеметрия не пишется, время паузы не идёт в elapsed; при возобновлении цель отправляется повторно. Учтено в T-027 (и уже в `WorkoutSession`).
- В-5 (INT-06) — зоны мощности из Intervals.icu — список границ в ваттах любого количества (1–9) → `PowerZones.custom`; зоны пульса — из `sportSettings`, если есть, иначе от `max_hr` (нужен `HrZones.custom_bpm`, см. T-008); локальное переопределение в приоритете. Учтено в T-033.
- В-6 (STR-01) — `client_id`/`client_secret` не в репозитории: в dev-сборках из `user://secrets.cfg` или переменных окружения, в магазинных — из конфигурации сборки вне репо; redirect на macOS/Linux/Windows — loopback `http://127.0.0.1:<port>/callback` через временный HTTP-сервер, на iOS/Android — `ovoschrider://strava`; альтернатива владельцу — серверный обмен кода. Учтено в T-046.
- В-7 (D3D-05) — замер draw calls переведён в `[ручная проверка]`; в `[авто]` — бюджет узлов/материалов сцены и статическая проверка отсутствия аллокаций в per-frame коде. Учтено в T-052.
- В-8 (WRK-08, LOC-01, LOC-05, STR-02) — источник скорости: FTMS Indoor Bike Data, если станок её даёт, иначе расчёт по модели D3D-02; `speed_source` фиксируется в метаданных заезда. Учтено в T-023, T-041, T-050.
- В-9 (INF-03) — `fetch-depth: 0` в `actions/checkout` добавлен как критерий. Учтено в T-014.
- В-10 (WRK-02 п.5, IMP-01 п.2; по наблюдению tester при приёмке T-007) — на шаге FreeRide при включённом ERG станок переводится в режим сопротивления (`set_erg_enabled(false)` + `set_resistance_level(уровень пользователя)`) не позже 1 с после начала шага; на следующем шаге с целью ERG возвращается (`set_erg_enabled(true)` + цель) в ту же секунду; переключатель ERG на HUD остаётся «вкл» — это режим шага, не выбор пользователя. Учтено в T-025, T-026.
- В-11 (WRK-04 п.2; по дефекту приёмки T-016 «насыщение 25.5») — уровень сопротивления 0–100 % масштабируется линейно на кодируемый диапазон FTMS Set Target Resistance Level: на `[min; max]` из `0x2AD6`, если станок его отдаёт, иначе на 0..25.5 единиц (uint8 × 0.1); 100 % → максимум, без насыщения на промежуточных значениях. Учтено в T-026 (и в фиксе `FtmsCodec.percent_to_resistance_level`, коммит 5c2e62f). Внесено в REQ-WRK-04 п.2 (requirements.md, «Статус внесения»: В-1..В-11, Н-1..Н-5 отражены).
- В-12 (IMP-01 п.2, IMP-05 п.2; T-037) — элемент ZWO `MaxEffort` разбирается как FreeRide (шаг без цели) с предупреждением в `ParseResult`, а не как ошибка импорта; прочие неизвестные элементы (`SolidState` и т.п.) — по-прежнему ошибка «элемент не поддерживается (строка N)». Внесено в requirements.md (коммит cadf416).
- Н-6 (сериализация `Workout`) — выполнено (4b049e9): `Workout.to_dict()/from_dict()` и `Workout.metadata: Dictionary` в домене как чистые функции без файлового ввода-вывода; `WorkoutSerializer` и `PlanCache` делегируют им; `Ride` (T-041) хранит план в том же формате.
- В-14 (IMP-04 п.4; T-039) — повторный импорт файла с тем же названием, но другим содержимым — отдельная запись; с идентичным содержимым (по хэшу) — замена существующей записи с сохранением `id` и предупреждением «тренировка уже в библиотеке, обновлена». Внесено в requirements.md.
- В-15 (INT-03 п.9; T-035) — неподдерживаемыми считаются только токены цели шага (пульс `140bpm`/`70% hr`, зона `Z2` как цель, темп `4:30/km`, `press lap` без длительности); свободные слова после валидной цели («Keep HR low») — текстовая подсказка шага, не ошибка. Внесено в requirements.md.
- Н-9 (WRK-05 п.2, D-6) — внесено в requirements.md: событие паузы с сессионным временем начала и длительностью по реальным часам; `paused_total_sec` в метаданных заезда.
- Секреты из окружения (T-046) — единственная точка чтения переменных окружения за секретами — `SecureStore.read_env()` в `src/storage/`; интеграции (`StravaConfig`) не вызывают `OS.get_environment()` напрямую. Поддерживает REQ-NFR-05 п.1 (единственная точка доступа к секретам) и проверку T-014 (`test_architecture.gd` — добавить запрет `OS.get_environment` вне `src/storage/secure_store*`).
- В-13 (INT-06 п.1, 3; T-033) — решения developer C приняты: зоны мощности из Intervals.icu хранятся в профиле в % FTP; если API отдаёт границы в ваттах (автоопределение: значения > 100), пересчёт через FTP атлета из того же ответа; зоны пульса — границы +1 (API отдаёт верхние границы включительно, `HrZones` ждёт нижние); допускается 2–9 зон мощности (`PowerZones.custom`). Агент requirements вносит в REQ-INT-06 (на момент записи в requirements.md нет).
- Н-8 (персистентность настроек устройств) — принято: `power_source` и флаг автоподключения на устройство хранятся в профиле/реестре запомненных устройств (`RememberedDevices`), как `resistance_level_pct`; закрывается в T-057 (экран настроек, developer A). До T-057 значения живут в `SensorHub`/`ConnectionManager` в памяти — не блокировало `done` T-018/T-020.
- UX-3 («Bluetooth недоступен») — принято: по `BleBridge.is_available() == false` или выключенному адаптеру (`get_adapter_state()`) экран устройств показывает состояние «Bluetooth недоступен» и блокирует сканирование/подключение; `FakeTrainer` остаётся доступен в режиме разработчика. Оформлено как REQ-DEV-01 п.7, входит в фикс D-5 (T-019); чеклист T-053 — сборки без нативного модуля не публикуются.
- D-6 (REQ-WRK-05 п.2, T-027) — событие паузы хранит `at_sec` (сессионное время начала) и `duration_sec` по реальному времени; в метаданных сессии/заезда — `paused_total_sec`. Требует правки формулировки критерия — Н-9.
- Н-1..Н-5 — закрыты агентом requirements (см. «Статус внесения» в requirements.md): Н-1 — `-gselect` в REQ-INF-01 п.2 и CLAUDE.md; Н-2 и Н-5 — слои `src/session/` и `src/app/` (`AppState` — контракт навигации для `src/ui/`; оболочка `main.*`/`locale.gd` — ни от кого не зависима) в REQ-NFR-06 п.3 и CLAUDE.md; Н-3 — контракт моста в документе приведён к именам кода (`connect_peripheral`, `notification`, `write_done`, `read_characteristic`/`characteristic_read`, `discover_services`/`services_discovered`); Н-4 — DEV-04 п.3: «обороты стоят» → 0, «пакеты пропали 3 с» → «нет данных» (реализовано в 851c724).
- Уточнение DEV-08 п.3 (наблюдение tester, приоритет В-4) — при обрыве и восстановлении на паузе цель уходит при `resume`, а не ≤ 1 с после `connected`; после `connected` на паузе — только Request Control. Учтено в T-017, T-024.

## 6. Трассируемость REQ → задачи

| REQ | Задачи |
| --- | --- |
| INF-01, INF-02 | T-001 |
| INF-03 | T-014 |
| INF-04 | T-014 (п.1 мягко, п.3), T-056 (п.1, 2 строго) |
| PRF-01 | T-009, T-011 |
| PRF-02 | T-008, T-009 |
| PRF-03 | T-010, T-046, T-057 (п.2 — UI отвязки Intervals.icu) |
| PRF-04 | T-011, T-041 |
| PRF-05 | T-012 |
| INT-01 | T-033 (ключ), T-053 (OAuth-документ) |
| INT-02 | T-034 |
| INT-03 | T-035 |
| INT-04 | T-040 |
| INT-05 | T-005 (`Workout.power_points` — фикс D-1), T-030, T-040 |
| INT-06 | T-033 (п.1–4, 8 по В-13), T-057 (п.5–7) |
| INT-07 | T-036 |
| IMP-01 | T-037 |
| IMP-02 | T-038 |
| IMP-03 | T-039 (п.1), T-040 (п.2), T-053 (п.3) |
| IMP-04, IMP-05 | T-039 |
| STR-01 | T-046, T-053 |
| STR-02 | T-044 (п.2), T-047 (п.1, 3, 4; п.1 — после подключения `FitEncoder` в T-049) |
| STR-03 | T-047, T-049 |
| STR-04 | T-048 (п.2–4, 6), T-049 (п.1 — автопостановка в `StravaService`, п.5 — UI) |
| STR-05 | T-048, T-049 |
| DEV-01 | T-019, T-021, T-022 |
| DEV-02 | T-016, T-017, T-022 |
| DEV-03, DEV-04, DEV-05 | T-016, T-018 (DEV-04 п.3 — уточнение Н-4), T-057 (DEV-05 п.2 — хранение в профиле, Н-8) |
| DEV-06 | T-011, T-020 |
| DEV-07 | T-016, T-020 |
| DEV-08 | T-024 |
| DEV-09 | T-002, T-003, T-004, T-007, T-013 |
| WRK-01 | T-005, T-006, T-007, T-013 |
| WRK-02 | T-025 |
| WRK-03 | T-026, T-031 |
| WRK-04 | T-026 |
| WRK-05, WRK-06 | T-027 |
| WRK-07 | T-025, T-030 |
| WRK-08 | T-023, T-050 |
| HUD-01 | T-031 |
| HUD-02, HUD-03, HUD-04 | T-028 |
| HUD-09 | T-005 (`PowerSmoother`, п.1–3), T-028 (п.4 — только для HUD) |
| HUD-05, HUD-06, HUD-08 | T-029 |
| HUD-07 | T-005 (`Workout.segments` — фикс D-1), T-030 |
| D3D-01, D3D-04, D3D-05 | T-052 |
| D3D-02 | T-050 |
| D3D-03, D3D-06 | T-051 |
| LOC-01 | T-041 |
| LOC-02 | T-045 |
| LOC-03 | T-043 (`RideSeries`) |
| LOC-04 | T-041 (`RideSummary`) |
| LOC-05 | T-044, T-045 |
| LOC-06 | T-045, T-048 |
| LOC-07 | T-042 |
| NFR-01 | T-025 |
| NFR-02 | T-006, T-013, T-023 |
| NFR-03 | T-032, T-036, T-048 |
| NFR-04 | T-027 |
| NFR-05 | T-010 (п.1, 2 — контейнер; `EncryptedFileSecureStore` временная), T-046, T-053 (п.3 — платформенные реализации, вне контейнера) |
| NFR-06 | T-002, T-014, T-015, T-021, T-055 |
| NFR-07 | T-053, T-055 |
| NFR-08 | T-012 (заделка), T-057 (п.3, 4), T-054 (п.1, 2 — финальная инвентаризация) |
| NFR-09 | T-005, T-006, T-014 (п.4), T-056 (п.2), T-035, T-037, T-038, T-044 |
