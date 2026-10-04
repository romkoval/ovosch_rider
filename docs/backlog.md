# ovosch-rider — бэклог MVP

Ведёт: менеджер разработки. Источник критериев — `docs/requirements.md` (74 REQ MVP + 18 REQ ред. 2: HUD-10..14, D3D-08, FRD-01..07, UIX-01..05). Этапы — раздел 7 `docs/tz.md`.
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
| `[visual]` | 3D-мир и визуал: окружение, рельеф, небо, свет, материалы и шейдеры, процедурные объекты, модель велосипедиста, камера (`src/scene3d/`, `.tres`, `.gdshader`, `assets/`) — technical-artist. |
| `[design]` | Дизайн-документ, арт-библия, реестр ассетов, макеты HUD и экранов (`docs/game/`) — game-designer, без кода. |

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
| T-040 | `[game]` | 4 | Экран выбора тренировки и предпросмотра (план на сегодня + библиотека, график профиля, импорт файла) | REQ-INT-04 (п.1–3), REQ-INT-05 (п.1–3 — отображение), REQ-IMP-03 (п.2) | T-030, T-036, T-039 | `done` (e17d604 + фиксы D1–D3; приёмка 28/28) |
| T-041 | `[integration]` | 5 | `RideRepository`: сохранение и чтение заездов с сэмплами и событиями в рамках профиля (+ `RideSummary`) | REQ-LOC-01 (п.1–4), REQ-PRF-04 (п.1), REQ-LOC-04 (п.1–6 — `RideSummary`) | T-023, T-027, T-009 | `done` (коммит 59f1fe1; приёмка 45/45) |
| T-042 | `[integration]` | 5 | Потоковая запись заезда на диск и восстановление после сбоя | REQ-LOC-07 (п.1–4) | T-041 | `done` (коммит 59f1fe1; Н-2 исправлен; приёмка 45/45) |
| T-043 | `[game]` | 5 | Серии для графиков (`RideSeries`): точки без «нет данных», прореживание ≤ 3600, серия цели | REQ-LOC-03 (п.1–3) (LOC-04 — закрыт `RideSummary` в T-041) | T-041, T-008 | `done` (коммиты e17d604 и фиксы приёмки; В-18; приёмка 9/9) |
| T-044 | `[integration]` | 5 | Кодировщик FIT | REQ-LOC-05 (п.1–4), REQ-STR-02 (п.2), REQ-NFR-09 (п.1 — FIT) | T-041 | `done` (коммит 59f1fe1; Д-2 округление пауз исправлено; приёмка 16/16) |
| T-045 | `[game]` | 5 | Экраны истории: список, карточка с графиками и сводкой, удаление, экспорт FIT | REQ-LOC-02 (п.1, 2), REQ-LOC-06 (п.1, 2), REQ-LOC-05 (п.6 — вызов диалога) | T-043, T-044 | `done` (коммиты e17d604 и фиксы приёмки; приёмка 23/23, в т.ч. TZ=Europe/Moscow) |
| T-046 | `[integration]` | 6 | Strava OAuth 2.0: URL авторизации, обмен кода, обновление токенов, отвязка | REQ-STR-01 (п.1–6), REQ-PRF-03 (закрытие), REQ-NFR-05 (п.1, 2 — закрытие) | T-010, T-032 | `done` (коммит ce85da4; дефекты D-1..D-4 исправлены; приёмка 38/38) |
| T-047 | `[integration]` | 6 | Выгрузка заезда в Strava: multipart FIT, VirtualRide, опрос статуса, название/описание | REQ-STR-02 (п.1, 3, 4), REQ-STR-03 (п.1–3) | T-044, T-046 | `done` ядро (коммит ce85da4; приёмка 38/38; STR-02 п.1 через `StravaService` — приёмка T-049) |
| T-048 | `[integration]` | 6 | Очередь выгрузки с повторами и статусы заезда | REQ-STR-04 (п.1–6), REQ-STR-05 (п.1–3), REQ-LOC-06 (п.3), REQ-NFR-03 (п.3) | T-047, T-042 | `done` (коммит ce85da4; приёмка 38/38; Н-11, Н-12 — подтвердить владельцу) |
| T-049 | `[game]` | 6 | `StravaService` (связка очереди, репозитория и настроек), привязка Strava на экране настроек, действия Strava в карточке заезда | REQ-STR-04 (п.1 — автопостановка, п.5 — UI), REQ-STR-03 (п.3 — UI), REQ-STR-05 (п.2 — UI), REQ-STR-01 (п.7 — кнопка по брендбуку, вне контейнера) | T-057, T-048, T-045 | `done` (e17d604 + фиксы D-1..D-4; приёмка 19/19) |
| T-057 | `[game]` | 4–8 | Экран настроек: язык, профиль (FTP/вес/max HR/зоны с источником), привязка и синхронизация Intervals.icu, источник мощности в профиле, заглушка Strava, «О программе» | REQ-NFR-08 (п.3, 4), REQ-INT-06 (п.5–7), REQ-PRF-03 (п.2), REQ-DEV-05 (п.2 — хранение в профиле, Н-8), REQ-PRF-02 (п.1 — UI) | T-033, T-009, T-010, T-012 | `done` (e17d604 + фиксы D1–D3, O1, O2; приёмка 26/26) |
| T-050 | `[game]` | 7 | Модель скорости v(P, m): установившаяся скорость, инерция, ограничение изменения | REQ-D3D-02 (п.1–4), REQ-WRK-08 (п.5 — альтернативный источник) | T-023 | `done` (код bdddd4d; приёмка 973b7c0) |
| T-051 | `[game]` | 7 | Интерфейс трассы `Track`, зацикленная трасса, тестовая трасса, `docs/scene3d.md` | REQ-D3D-03 (п.1, 2), REQ-D3D-06 (п.1–3) | T-050 | `done` (коммит 65715d4; D-8 исправлен; приёмка 30/30) |
| T-052 | `[game]` | 7 | Сцена велосипедиста и камеры, анимация педалирования по каденсу, бюджет производительности | REQ-D3D-01 (п.1, 2), REQ-D3D-04 (п.1–3), REQ-D3D-05 (п.2; п.1, 3 — ручной замер) | T-051 | `done` (коммит 65715d4; D-8 исправлен; приёмка 30/30) |
| T-058 | `[visual]` | 7 | Переработка мира по референсу владельца: тун-свет и контуры, асфальт с разметкой, обочина/бордюр/отбойник, рельеф с холмами, растительность, небо с облаками, модель велосипедиста с IK ног, наклон в поворотах, камера в три четверти | REQ-D3D-07 (п.1–5; п.6 — снимки; п.7 — ручная), REQ-D3D-03 (п.3 — внешний вид) | T-052 | `done` (код 34adc61 + фиксы D3D-07-A/B/C; приёмка tester d9cee0d 25/25; п.6 — 9–11/12 без блокирующих, п.7 — ручная) |
| T-053 | `[docs]` | 8 | Пакет публикации iOS/macOS: `docs/publishing/*` (политика, чеклисты App Store и Strava API, OAuth Intervals.icu, лицензии), шаблоны `platform/ios|macos/*`, `docs/secure_store.md` | REQ-NFR-07 (п.1, 2, 4), REQ-IMP-03 (п.3), REQ-INT-01 (п.5), REQ-STR-01 (п.7), REQ-NFR-05 (п.3) | T-046 | `done` (коммит 7319347; приёмка `test_publishing_docs_acceptance` 11/11) |
| T-054 | `[game]` | 8 | Локализация ru/en: финальная инвентаризация переводов и литералов после всех экранов (выбор языка — в T-057) | REQ-NFR-08 (п.1, 2; п.3, 4 — подтверждение после T-057) | T-040, T-045, T-049, T-057 | `done` (инвентаризация; test_i18n 7/7; п.3, 4 подтверждены приёмкой T-057) |
| T-055 | `[docs]` | 9–10 | Порты BLE: `docs/ports/{README,android,linux_windows}.md`, `platform/android/AndroidManifest.template.xml`, Data safety Google Play, открытый вопрос о каналах Linux/Windows | REQ-NFR-06 (п.4), REQ-NFR-07 (п.3, 4 — Android) | T-022 | `done` (коммит 7319347; приёмка `test_publishing_docs_acceptance` 11/11) |

Итого 101 задача: MVP — 58 (ниже), доработка ред. 2 (этап 7р2) — 43 (T-059..T-101: `[game]` — 30, `[visual]` — 8, `[integration]` — 4 (T-064, T-069, T-099, T-101), `[design]` — 1 (T-091), `[native-ble]` — 0; волны 1–6, см. «Этап 7р2»; T-091, T-092 добавлены по итогам волны 1, T-093..T-097 — по ходу волн 2–4, T-098..T-101 — хвосты волн 3–4). Статусы 7р2 на 2026-10-04: `done` — 28, `review` — 6 (T-078, T-079, T-083, T-085, T-087, T-095 — см. строки; T-078 и T-085 с дефектами в T-097), `in-progress` — 3 (T-088, T-096, T-097), `todo` — 6 (T-089, T-090, T-098..T-101). MVP: этап 1 — 15 (T-001..T-014, T-056), этап 2 — 8 (+ T-024 выполняется в этапе 3), этап 3 — 9, этап 4 — 9 (+ T-057, экран настроек, сквозная для этапов 4–8), этап 5 — 5, этап 6 — 4, этап 7 — 4, этап 8 — 2, этапы 9–10 — 1. T-056 добавлена после приёмки T-014 (NFR-09 п.2 не покрыт); T-057 выделена из T-049/T-054, когда стало ясно, что экран настроек нужен раньше Strava (язык, синхронизация Intervals.icu, источник мощности по Н-8).

### Этап 7р2 — Доработка ред. 2 (ТЗ ред. 2, коммит 4f0aa82; REQ — коммит 5d028e7)

Источники: REQ-HUD-10..14, REQ-HUD-01 (новая редакция: крупнее всего факт мощности), REQ-D3D-08, REQ-FRD-01..07, REQ-UIX-01..05; дизайн — `docs/game/hud.md` (п. 14, 15), `docs/game/ui.md` (п. 9, 12), `docs/game/tracks.md` (п. 2, 5, 9), `docs/game/assets.md`; макеты — `docs/game/shots/2026-10-03-ui-mockups/`, снимки «до» — `docs/game/shots/2026-10-03-ui-before/`.
Главный риск этапа — качество игрового UI и мира, поэтому первыми идут инструмент снимков (без него tester не принимает визуал), тема и шрифт (меняют все экраны сразу), затем HUD тренировки, трассы и свободная езда, в конце меню и окружения.

Решения, на которые опирается нарезка. Владелец: SIM только в свободной езде; езда без лимита, стоп вручную; трассы — равнина, холмы, горы (петля), приморье; факт мощности крупнее цели; только тёмная тема, акцент `#2CC9B4`; крутизна по умолчанию 50 %. Оркестратор: тренировка по плану идёт на трассе `flat` без учёта уклона (станку уклон не уходит, скорость по D3D-02); скорость свободной езды — модель с уклоном; станок без SIM → фиксированное сопротивление и сообщение; свободная езда требует станка (в dev-режиме `FakeTrainer`); окно графика свободной езды 30 мин; `lap` на круг; FIT с distance, altitude, grade.
Технические выводы менеджера. `[native-ble]` не нужен: `BleBridge.write(id, service, char, bytes)` и `read_characteristic` — универсальные, команда SIM `0x11`, чтение `0x2ACC`/`0x2AD5` — это кодеки GDScript и `BleTrainer`, нативный мост байты не разбирает. Профиль трассы — чистая математика, поэтому он живёт в `src/domain/` (сессия читает уклон, не завися от `src/scene3d/`).

| ID | Зона | Волна | Задача | REQ-ID | Зависит от | Файлы (владение) | Статус |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T-059 | `[game]` | 1 | Скрипт снимков UI (меню, HUD, пауза, сводка) + синтетический пульс эмулятора | инструмент приёмки для HUD-10..14, FRD-06, UIX-01..05; DEV-09 (п.5 — расширение) | — | `scripts/ui_screenshot.sh`, `scripts/dev/ui_screenshot.gd`, `src/devices/fake_heart_rate_curve.gd`, `src/devices/trainer_factory.gd` | `done` (коммит 88b30da; приёмка 83dd2b0) |
| T-060 | `[game]` | 1 | Растяжение `canvas_items`, масштаб интерфейса, Inter и Lucide, тема `app_theme.tres` и `UiTokens`, файлы переводов по областям | UIX-01 (п.1, 3, 4), HUD-14 (п.1, 2), NFR-08 (п.2) | — | `project.godot`, `assets/fonts/**`, `assets/icons/**`, `src/ui/theme/**`, `src/app/ui_scale.gd`, `assets/i18n/strings_*.csv` (создание), `tests/unit/app/test_i18n.gd` | `done` (коммит 1f37ec7; приёмка 83dd2b0; хвосты — в T-093, T-089) |
| T-061 | `[game]` | 1 | Навигационный каркас ред. 2: экраны `ROUTE_SELECT`/`FREE_RIDE`, стек «назад», Esc и Android «назад», заготовки сцен, поля профиля `last_route_id`, `sim_steepness_pct` | UIX-04 (п.1, 2 — навигация), UIX-02 (п.3), FRD-02 (п.3 — хранение), FRD-05 (п.1 — хранение) | — | `src/app/app_state.gd`, `src/app/main.gd`, `src/profiles/profile.gd`, `src/profiles/profile_repository.gd`, заготовки `src/ui/tracks/route_select_screen.*`, `src/ui/free_ride/free_ride_screen.*` | `done` (коммит 231b84a; приёмка 83dd2b0) |
| T-062 | `[game]` | 1 | Профиль трассы (PCHIP, выборка 10 м, уклон по окну 100 м, набор, подъёмы) и каталог четырёх трасс | D3D-08 (п.1, 2 — профиль, 3) | — | `src/domain/route_profile.gd`, `src/domain/route_catalog.gd` | `done` (коммит c60c9d1; приёмка f84b12b; ориентиры D3D-08 п.12 — T-091, T-092) |
| T-063 | `[game]` | 1 | SIM в FTMS: кодек `0x11`, `0x2AD5`, бит `0x2ACC`; `TrainerDevice.set_simulation`, `BleTrainer`, `FakeTrainer` | FRD-04 (п.1, 3 — чтение диапазона, 6 — определение поддержки) | — | `src/devices/ble/codecs/ftms_codec.gd`, `src/devices/ble/ble_uuids.gd`, `src/devices/trainer_device.gd`, `src/devices/ble_trainer.gd`, `src/devices/fake_trainer.gd` | `done` (коммит c1b5624; приёмка f84b12b) |
| T-064 | `[integration]` | 1 | Хранилище свободной езды: дистанция, высота и уклон в сэмплах, метаданные, сводка без цели, название для Strava | FRD-07 (п.3, 4 — хранение и набор, 6 — сводка, 7) | — | `src/session/sample_stream.gd`, `src/storage/{ride,ride_recorder,file_ride_repository,ride_summary,ride_series}.gd`, `src/integrations/strava/strava_service.gd` | `done` (коммит 2bdd110; приёмка f84b12b) |
| T-065 | `[game]` | 1 | Модели нижнего графика HUD (headless): сегменты плана, оси, курсор, серии мощности и пульса, скользящее окно | HUD-10 (п.1–5), HUD-11 (п.1–5), HUD-12 (п.1, 2, 5–7), FRD-06 (п.4 — модель) | — | `src/ui/hud/plan_chart_model.gd`, `src/ui/hud/effort_series.gd`, `src/ui/hud/time_axis.gd` | `done` (коммит 3d79191; приёмка 83dd2b0) |
| T-066 | `[visual]` | 1 | Длинные трассы: коридорный рельеф кусками, MultiMesh кусками по ~500 м с `visibility_range`, бюджет на 20 км | D3D-08 (п.6 — бюджет), D3D-05 (п.2, 4), D3D-07 (п.1–5 — регрессия) | — | `src/scene3d/terrain_field.gd`, `src/scene3d/scenery_builder.gd`, `src/scene3d/roadside_builder.gd`, `src/scene3d/perf_budget.gd`, `docs/perf_budget.md` | `done` (коммит 6871a91; приёмка f84b12b, правка теста под трассу по умолчанию edbeef9) |
| T-067 | `[game]` | 2 | Модель скорости с уклоном и позиция на трассе (s по модулю L, круги, дистанция, набор) | FRD-04 (п.2 — позиция, 7, 8), FRD-07 (п.1, 4 — расчёт), D3D-02 (регрессия) | T-062 | `src/domain/speed_model.gd`, `src/domain/route_position.gd` | `done` (коммит e057f74; приёмка d62b281) |
| T-068 | `[game]` | 2 | `SimController`: крутизна, округление, ограничение диапазоном, частота и порог, принудительная отправка, SIM ↔ фиксированное сопротивление, откат без SIM | FRD-04 (п.2–6), FRD-05 (п.1–4), FRD-01 (п.2) | T-063 | `src/session/sim_controller.gd`, `src/devices/sensor_hub.gd` (делегирование SIM) | `done` (коммит c9762f9; приёмка d62b281) |
| T-069 | `[integration]` | 2 | FIT свободной езды: distance, altitude, grade в `record`, total_distance и total_ascent в `session`, `lap` на круг | FRD-07 (п.5), LOC-05 (п.1–4 — регрессия) | T-064 | `src/integrations/fit/{fit_encoder,fit_definitions,fit_decoder}.gd` | `done` (коммит a7405a8; приёмка d62b281) |
| T-070 | `[visual]` | 2 | `ProfiledTrack`: план-схемы четырёх трасс, дорога по h(s), рельеф относительно полотна, наклон гонщика на уклоне, камера; `RideScene.set_route(id)` | D3D-08 (п.2 — геометрия стыка, 4, 5, 7), D3D-03 (п.1, 2) | T-062, T-066 | `src/scene3d/profiled_track.gd`, `src/scene3d/route_world.gd`, `src/scene3d/{road_builder,roadside_builder,terrain_field,rider,ride_scene}.gd`, `docs/scene3d.md` | `done` (коммит 431b324; приёмка d62b281) |
| T-071 | `[game]` | 2 | Рисовальщик `HudChart` (сегменты, рампы по зонам, штриховка, курсор, линии с обводкой) и `PlanPreview` на том же коде | HUD-10 (п.6), HUD-11 (п.6), HUD-12 (п.3, 4), UIX-03 (п.4 — план) | T-060, T-065 | `src/ui/hud/hud_chart.gd`, `src/ui/common/plan_preview.gd` | `done` (коммит ca89bea; приёмка 6e84ef1) |
| T-072 | `[game]` | 2 | Компонент «Список интервалов» (модель строк, состояния, прокрутка к текущей) | HUD-13 (п.2, 3 — компонент) | T-060 | `src/ui/hud/interval_list_model.gd`, `src/ui/hud/interval_list.gd` | `done` (коммит cf77938; приёмка 6e84ef1) |
| T-073 | `[game]` | 2 | Каркас экрана тренировки: HUD в `CanvasLayer`, 3D в физическом разрешении, геометрия `HudLayout`, панель цифр (факт — герой), подложки, фишки статусов | HUD-01 (новая редакция), HUD-13 (п.1, 5, 6), HUD-14 (п.3–5), HUD-02..06 (регрессия) | T-059, T-060 | `src/ui/workout/workout_screen.{tscn,gd}`, `src/ui/hud/hud_layout.gd`, `src/ui/hud/hud_metric_panel.{tscn,gd}`, `assets/i18n/strings_hud.csv` | `done` (коммит 588e978; приёмка bb178af) |
| T-074 | `[game]` | 2 | Компоненты управления HUD: фишка «ДАЛЕЕ», вуаль и карточка паузы, скрываемая панель инструментов (план/свободная езда), горячие клавиши | HUD-06 (п.2 — отображение), WRK-05 (UI), WRK-03 (п.1 — UI), FRD-05 (п.4, 6 — UI) | T-060 | `src/ui/hud/next_chip.gd`, `src/ui/hud/pause_overlay.{tscn,gd}`, `src/ui/hud/hud_toolbar.{tscn,gd}`, `assets/i18n/strings_hud_controls.csv` | `done` (коммит 06ab853; приёмка 6e84ef1) |
| T-075 | `[game]` | 2 | Превью трассы: модель серии (s, h), шкалы, палитра уклона, цифры; миниатюра и крупный профиль | FRD-03 (п.1–3), UIX-03 (п.2, 4 — трасса) | T-060, T-062 | `src/ui/tracks/route_preview_model.gd`, `src/ui/tracks/route_preview.gd`, `assets/i18n/strings_tracks.csv` | `done` (коммит 002b3bb; приёмка 6e84ef1) |
| T-076 | `[game]` | 2 | Общие компоненты меню: AppBar с «назад», Stat, Banner, ListRow, пустое состояние | UIX-01 (п.3 — использование вариаций), UIX-04 (п.1 — компонент) | T-060, T-061 | `src/ui/common/{app_bar,stat_view,banner,list_row,empty_state,touch_target}.*`, `assets/i18n/strings_menu.csv` | `done` (коммит 6391da8; приёмка 6e84ef1) |
| T-077 | `[game]` | 3 | `FreeRideSession`: сессия без плана — тики, модель скорости с уклоном, позиция, `SimController`, пауза, события, запись, без лимита | FRD-01 (п.1 — сессия, 2, 3), FRD-04 (п.5, 9), FRD-05 (п.5, 6 — события), FRD-07 (п.1–4) | T-064, T-067, T-068 | `src/session/free_ride_session.gd` | `done` (коммит 013a0d8; приёмка d62b281) |
| T-078 | `[game]` | 3 | Сборка HUD тренировки: график внизу, список слева, «ДАЛЕЕ», пауза, панель инструментов; полоса прогресса снята; трасса `flat` без уклона | HUD-10 (п.7), HUD-11 (п.7), HUD-12 (п.8), HUD-13 (п.2–4, 7), HUD-07 (замена) | T-071, T-072, T-073, T-074 | `src/ui/workout/workout_screen.{tscn,gd}`, `src/ui/workout/workout_progress_bar.gd` (удаление), `assets/i18n/strings_hud.csv` | `review` (коммит b2d48da; приёмка 6e84ef1 — дефекты HUD-13 п.5, 6, 9 на телефоне, исправляет T-097) |
| T-079 | `[game]` | 3 | Компоненты HUD свободной езды: панель рельефа (круг и «впереди 2 км»), режим панели цифр с карточкой уклона, график истории усилия 30 мин | FRD-06 (п.1–4), FRD-05 (п.6 — отображение) | T-071, T-073, T-075 | `src/ui/hud/relief_panel.gd`, `src/ui/hud/hud_metric_panel.gd`, `src/ui/hud/hud_chart.gd`, `assets/i18n/strings_free_ride.csv` | `review` (коммит 36452a1; отдельного отчёта tester нет — FRD-06 п.1–4 проверялись на экране T-084 в 6e84ef1, подтвердить) |
| T-080 | `[game]` | 3 | Экран выбора трассы: четыре карточки, деталь с крупным профилем, слайдер крутизны, запуск | FRD-02 (п.1–3), FRD-03 (п.4), FRD-05 (п.1 — UI), UIX-03 (п.2, 3, 5 — трасса), D3D-08 (п.1 — названия) | T-061, T-075, T-076 | `src/ui/tracks/route_select_screen.{tscn,gd}`, `assets/i18n/strings_tracks.csv` | `done` (коммит c36d3d1; приёмка 6e84ef1) |
| T-081 | `[game]` | 3 | Главный экран: два сценария, статус устройств, история и настройки, профиль, кнопка разработчика только в отладке | UIX-02 (п.1–5), FRD-01 (п.1 — вход) | T-061, T-076 | `src/ui/home/home.{tscn,gd}`, `src/app/main.gd` (проводка, если нужна), `assets/i18n/strings_menu.csv` | `done` (коммит 9f68583; приёмка 6e84ef1) |
| T-082 | `[game]` | 3 | Выбор тренировки карточками с превью плана, длительностью и максимальной целью | UIX-03 (п.1, 3, 4, 5 — тренировка), INT-04, INT-05 (регрессия) | T-071, T-076 | `src/ui/plan/plan_screen.{tscn,gd}`, `src/ui/plan/workout_chart.gd` (снятие), `assets/i18n/strings_menu_lists.csv` | `done` (коммит b443372; приёмка 6e84ef1) |
| T-083 | `[visual]` | 3 | Окружения «равнина» и «холмы»: свои `EnvironmentSet`, поля-лоскуты, тополя, ветряки, ориентиры | D3D-08 (п.6, 8 — `flat`, `hills`) | T-070 | `src/scene3d/environment_set.gd`, `src/scene3d/tracks/env_{flat,hills}.tres`, `src/scene3d/props/**`, `src/scene3d/mesh_kit.gd`, `src/scene3d/route_world.gd` | `review` (коммит cf6fec6; визуально принято game-designer по снимкам, `[авто]` — тесты исполнителя зелёные; приёмка tester — в цикле T-088/T-089) |
| T-084 | `[game]` | 4 | Экран свободной езды и запуск из меню: сцена по трассе, сессия, HUD, пауза, стоп, «нет SIM», сохранение и Strava; снимки свободной езды | FRD-01 (п.1, 4), FRD-06 (п.5, 6), FRD-05 (п.6), FRD-07 (п.2, 6, 7 — сквозная), UIX-04 (п.2 — свободная езда; п.1 — Android «назад» на главном закрывает приложение) | T-070, T-074, T-077, T-079, T-080 | `src/ui/free_ride/free_ride_screen.{tscn,gd}`, `src/app/main.gd`, `scripts/dev/ui_screenshot.gd`, `assets/i18n/strings_free_ride.csv` | `done` (коммит 68a89e6; приёмка 6e84ef1) |
| T-085 | `[game]` | 4 | История и карточка заезда в новой системе; свободная езда — профиль по дистанции, без цели | UIX-04 (п.3–5 — история), FRD-07 (п.6 — UI), LOC-02, LOC-03 (регрессия) | T-064, T-076 | `src/ui/history/**`, `assets/i18n/strings_menu_lists.csv` | `review` (коммит da90ba3; приёмка 6e84ef1 — дефект LOC-03 п.2: в истории сглаженная мощность; исправляет T-097) |
| T-086 | `[game]` | 4 | Настройки (группы), устройства (строки, пустое состояние), выбор профиля, «О программе» (Inter OFL, Lucide ISC) | UIX-04 (п.3–5 — настройки, устройства), PRF-05 (регрессия) | T-076 | `src/ui/settings/**`, `src/ui/devices/**`, `src/ui/profile_select/**`, `assets/i18n/strings_menu.csv` | `done` (коммит 58c7fed; приёмка 6e84ef1) |
| T-087 | `[visual]` | 4 | Окружение «горы»: камень, снег, высокий горизонт, серпантин, таблички, ориентиры | D3D-08 (п.6, 8 — `mountains`) | T-083 | `src/scene3d/tracks/env_mountains.tres`, `src/scene3d/props/**`, `src/scene3d/environment_set.gd`, `src/scene3d/mesh_kit.gd` | `review` (коммит 5576c36; визуально принято game-designer по снимкам, `[авто]` — тесты исполнителя зелёные; приёмка tester — в цикле T-088/T-089) |
| T-088 | `[visual]` | 5 | Приморье, часть 1: вода (шейдер), берег и пляж, зонтичные сосны, маяк, ориентиры | D3D-08 (п.6 — вода, 8 — `seaside` без моста) | T-087 | `src/scene3d/shaders/water.gdshader`, `src/scene3d/materials/water.tres`, `src/scene3d/tracks/env_seaside.tres`, `src/scene3d/props/**`, `src/scene3d/environment_set.gd`, `src/scene3d/terrain_field.gd` | `in-progress` |
| T-089 | `[game]` | 5 | Финальная проверка UI: адаптивность и цели нажатия, обрезка текста ru/en, статическая проверка `theme_override_*`, инвентаризация переводов, снимки всех экранов | UIX-01 (п.2, 5), UIX-05 (п.1–5), NFR-08 (п.1, 2) | T-078, T-080, T-081, T-082, T-084, T-085, T-086, T-095, T-097 | все `src/ui/**` и `assets/i18n/**` (после T-097 — единственный исполнитель в UI) | `todo` (хвосты волн 3–4 — в карточке) |
| T-090 | `[visual]` | 6 | Приморье, часть 2: мост над рекой на диапазоне `bridges`, река под мостом, выемка рельефа, перила | D3D-08 (п.3 — мост в сцене, 6, 8 — `seaside`) | T-088 | `src/scene3d/props/bridge_builder.gd`, `src/scene3d/{road_builder,roadside_builder,terrain_field}.gd`, `src/scene3d/tracks/env_seaside.tres` | `todo` |
| T-091 | `[design]` | 2 | Ориентиры трасс не реже 1.5 км в `tracks.md`, уточнение PCHIP (Fritsch–Butland), `assets.md` (Inter и Lucide в проекте), оценка состояний кнопок темы T-060 | D3D-08 (п.12 — данные дизайна), UIX-01 (п.3 — вердикт по вариациям) | T-060, T-062 | `docs/game/tracks.md`, `docs/game/assets.md`, `docs/game/ui.md` (только если нужна правка состояний) | `done` (коммит 44f5ea9) |
| T-092 | `[game]` | 2–3 | Ориентиры в данных `RouteCatalog` по новой таблице `tracks.md` (разрыв ≤ 1.5 км на всех трассах) | D3D-08 (п.12) | T-091 | `src/domain/route_catalog.gd`, `tests/unit/domain/test_route_catalog.gd` | `done` (коммит 94f8f2c; приёмка d62b281) |
| T-093 | `[game]` | 2–3 | Доработка темы перед волной 3: `danger_hover`/`danger_pressed`, нажатие `GhostButton`, `NumLabel`, `Stack0`, `Row0/8/12/16/24`, `HudPauseCard`/`HudChipLabel`/`HudPauseTitle`, шрифт цифр `SpinBox`, разрядка `Overline`, иконки баннера info/triangle-alert/circle-alert, помощник `UiIcons` | UIX-01 (п.1, 3), UIX-05, HUD-14 | T-060, T-091 | `src/ui/theme/**` (в т.ч. `ui_icons.gd`), `assets/icons/lucide/**` | `done` (коммит 64d24eb; приёмка 6e84ef1) |
| T-094 | `[game]` | 3 | `y_max` графика плана с нижней границей 1.1 × FTP (У-2), сдвиг линий факта по журналу пропусков, проверка размера кадра снимков UI, окно поверх всех на macOS | HUD-10 (п.2, 5), HUD-11 (п.1) | T-065, T-059 | `src/ui/hud/plan_chart_model.gd`, `src/ui/hud/effort_series.gd`, `scripts/dev/ui_screenshot.gd`, `scripts/ui_screenshot.sh` | `done` (коммит ad349e9; приёмка d62b281) |
| T-095 | `[game]` | 4 | `tnum` у подписей HUD с цифрами, недостающие вариации темы (`HudHeroUnit`, `HudTargetUnit`, `HudCountdown`, `HudDelta`, `HudGradeValue`, `HudGradeUnit`, `HudModeLabel`, `HudStepLabel`, `OverlineAccent`, `OverlineSim`, `LogoLabel`, `LogoAccentLabel`, `SheetPanel`), нагрузка Intervals.icu в строке карточки плана, удалены `WorkoutChart` и скрытый `WorkoutList` | HUD-14 (п.2), INT-04 (п.2), UIX-01 (п.3), UIX-03 | T-073, T-082, T-093 | `src/ui/theme/**`, `src/ui/hud/**` (подписи), `src/ui/plan/**` | `review` (коммит c85e98c; приёмка tester — вместе с T-097) |
| T-096 | `[visual]` | 5 | Пересвет 3D в `SubViewport` экранов заезда (тренировка и свободная езда): экспозиция, тонмаппинг и окружение сцены в `SubViewport` совпадают со снимками `screenshot.sh` | D3D-07 (п.1–5 — регрессия на экранах заезда), HUD-13 (п.10 — 3D под HUD) | T-084 | `src/scene3d/ride_scene.gd`, окружение сцены; в `src/ui/{workout,free_ride}/*_screen.tscn` — только узел `SubViewport` (уточнить в отчёте исполнителя, сцены экранов одновременно правит T-097) | `in-progress` |
| T-097 | `[game]` | 5 | Дефекты приёмки UI (HUD-13 п.5, 6, 9 на телефоне; LOC-03 п.2 в истории), Esc → подтверждение на обоих экранах заезда, удаление узлов совместимости, кэш подписей `HudChart`, вариации T-095 на панели цифр, подвал панели рельефа на телефоне, «На эмуляторе» на экране плана, ожидание анимаций в `ui_screenshot` | HUD-13 (п.5, 6, 9), LOC-03 (п.2), UIX-04 (п.2), HUD-14 (п.2), FRD-06 (п.1), FRD-01 (п.4) | T-078, T-084, T-085, T-095 | `src/ui/workout/**` (в т.ч. удаление `workout_progress_bar.gd`), `src/ui/free_ride/**`, `src/ui/hud/{hud_layout,hud_metric_panel,hud_chart,relief_panel}.*`, `src/ui/history/**`, `src/ui/profile_select/**`, `src/ui/plan/plan_screen.*`, `scripts/dev/ui_screenshot.gd` | `in-progress` |
| T-098 | `[game]` | 6 | Последняя выбранная тренировка в профиле: поле `last_workout_id`, предвыбор на экране плана между запусками (по образцу `last_route_id`) | UIX-03 (п.3) — прямого критерия нет, вопрос Н-17 | T-097 | `src/profiles/profile.gd`, `src/profiles/profile_repository.gd`, `src/ui/plan/plan_screen.gd` | `todo` |
| T-099 | `[integration]` | 6 | Свёртка повторов Intervals.icu «3x»: метаданные блоков повторов в `Workout` при разборе (сейчас `expand_repeat` разворачивает блок без следа), список интервалов показывает блок одной строкой, как у ZWO `IntervalsT` | HUD-13 (п.8 — для планов Intervals.icu), INT-03 (регрессия) | T-072 | `src/domain/workout.gd`, `src/domain/workout_step.gd`, `src/integrations/workouts/intervals_icu_workout_parser.gd`, `src/ui/hud/interval_list_model.gd` (только чтение метаданных) | `todo` |
| T-100 | `[visual]` | 6 | Статический кэш `RouteWorld._tracks`: в одиночном прогоне — «resources still in use at exit»; кэш с очисткой (или не статический) | INF-01 (п.2, 5 — чистый одиночный прогон) | T-088, T-090 (файлы `src/scene3d/` заняты) | `src/scene3d/route_world.gd` | `todo` |
| T-101 | `[integration]` | 6 | Нестабильные по времени тесты: `test_storage_acceptance::loc_07_c4_tick_budget_50ms`, `test_strava_hardening::idle_connection_5s` — подменяемые часы или устойчивый замер | LOC-07 (п.4), STR-04 (регрессия), INF-01 (п.1) | — | `tests/**/test_storage_acceptance.gd` (правит tester), `tests/**/test_strava_hardening.gd` (developer), при необходимости шов часов в `src/storage/`, `src/integrations/strava/` | `todo` |

Состояние волн (2026-10-04, ветка `claude/quirky-goldberg-m8r1ro`, голова 6e84ef1). Волны 1–4 слиты. Приёмки tester: 83dd2b0 (T-059, T-060, T-061, T-065), f84b12b (T-062, T-063, T-064, T-066; правка edbeef9), d62b281 (T-067, T-068, T-069, T-070, T-077, T-092, T-094), bb178af (T-073), 6e84ef1 (T-071, T-072, T-074, T-075, T-076, T-078, T-080, T-081, T-082, T-084, T-085, T-086, T-093); T-091 — 44f5ea9 (документ). В `review`: T-078 и T-085 — дефекты приёмки, исправляет T-097; T-083 и T-087 — визуально приняты game-designer, приёмка tester в цикле T-088/T-089; T-079 и T-095 — нет отдельного отчёта tester. Инфраструктура вне задач: bb13332, 065d41c, 2a201e8 (проверка ключей UI читает все `strings*.csv`). Последний полный прогон GUT: 3208 тестов, 4 красных — дефекты T-097. Волна 5 в работе: T-088, T-096, T-097; затем T-089 (после T-097), T-090 (после T-088), мелкие T-098..T-101 — волна 6.

#### Параллельная работа в git worktree

Каждая задача делается в своём worktree и своей ветке от актуальной главной ветки и сливается отдельным коммитом с REQ-ID. Задачи одной волны не зависят друг от друга и не меняют одни и те же файлы. Исполнитель, которому понадобился файл из чужой колонки «Файлы», его не правит, а пишет в отчёт; менеджер переносит правку в задачу-владельца или в следующую волну.

Предлагаемые дорожки (четыре исполнителя): **A** (developer: устройства и сессия) — T-063 → T-068 → T-077 → T-084; **B** (developer: домен трасс и хранилище) — T-062, T-064 → T-067, T-069 → T-085; **C** (developer: UI и HUD) — T-059, T-060, T-061, T-065 → T-073, T-071, T-072, T-074, T-075, T-076 → T-078, T-079, T-080, T-081, T-082 → T-086 → T-089; **TA** (technical-artist) — T-066 → T-070 → T-083 → T-087 → T-088 → T-090. В волнах 1–3 у дорожки C больше задач, чем у остальных: свободные исполнители A и B берут из той же волны задачи C (например, T-061 и T-065 в волне 1, T-075 и T-076 в волне 2, T-080 и T-082 в волне 3). Первой в работу идёт T-059.

Владение общими файлами по волнам:

| Файл | Волна 1 | Волна 2 | Волна 3 | Волна 4 | Волна 5–6 |
| --- | --- | --- | --- | --- | --- |
| `project.godot` | T-060 | — | — | — | — |
| `src/app/app_state.gd` | T-061 | — | — | — | — |
| `src/app/main.gd` | T-061 | — | T-081 | T-084 | T-089 (только если нужно) |
| `src/ui/workout/workout_screen.{tscn,gd}` | — | T-073 | T-078 | — | T-089 |
| `src/ui/hud/hud_metric_panel.*` | — | T-073 (создаёт) | T-079 | — | T-089 |
| `src/ui/hud/hud_chart.gd` | — | T-071 (создаёт) | T-079 | — | T-089 |
| `scripts/dev/ui_screenshot.gd` | T-059 (создаёт) | — | — | T-084 | T-089 |
| `src/profiles/profile.gd`, `profile_repository.gd` | T-061 | — | — | — | — |
| `src/devices/fake_trainer.gd`, `trainer_device.gd`, `ble_trainer.gd` | T-063 | — | — | — | — |
| `src/devices/trainer_factory.gd` | T-059 | — | — | — | — |
| `src/devices/sensor_hub.gd` | — | T-068 | — | — | — |
| `src/domain/route_catalog.gd` | T-062 | T-092 (после T-091) | — | — | — |
| `docs/game/tracks.md`, `assets.md` | — | T-091 | — | — | — |
| `src/session/sample_stream.gd`, `src/storage/*` | T-064 | — | — | — | — |
| `src/domain/speed_model.gd` | — | T-067 | — | — | — |
| `src/scene3d/*` (кроме `tracks/`, `props/`) | T-066 | T-070 | T-083 | T-087 | T-088, T-090 |
| `tests/unit/app/test_i18n.gd` | T-060 | — | — | — | T-089 |

Переводы. `assets/i18n/strings.csv` (действующий файл) в волнах 1–4 не меняется. T-060 создаёт и регистрирует в `project.godot` файлы по областям и учит `test_i18n.gd` проверять все `strings*.csv` с глобальной уникальностью ключей. Каждый файл в каждой волне правит одна задача:

| Файл | Волна 1 | Волна 2 | Волна 3 | Волна 4 |
| --- | --- | --- | --- | --- |
| `strings_hud.csv` | T-060 (создаёт) | T-073 | T-078 | — |
| `strings_hud_controls.csv` | T-060 (создаёт) | T-074 | — | — |
| `strings_free_ride.csv` | T-060 (создаёт + ключ названия заезда для Strava) | — | T-079 | T-084 |
| `strings_tracks.csv` | T-060 (создаёт + названия и типы трасс) | T-075 | T-080 | — |
| `strings_menu.csv` | T-060 (создаёт) | T-076 | T-081 | T-086 |
| `strings_menu_lists.csv` | T-060 (создаёт) | — | T-082 | T-085 |

Ключи, которые нужны задачам волны 1 до появления файлов, T-060 заводит сам по контракту: `track.<id>.name`, `track.<id>.kind` (ru/en по `tracks.md` п. 3) и `ride.free_ride.default_name` («Свободная езда — %s» / «Free ride — %s»). T-062 и T-064 ссылаются на эти ключи и не правят CSV. Если при слиянии всё же возник конфликт в CSV, допустим только один способ разрешения: объединить строки обеих веток (префиксы ключей у задач не пересекаются) и прогнать `test_i18n`.

Волны и зависимости:

| Волна | Задачи (параллельно) | Что должно быть слито до начала |
| --- | --- | --- |
| 1 | T-059, T-060, T-061, T-062, T-063, T-064, T-065, T-066 | — |
| 2 | T-067, T-068, T-069, T-070, T-071, T-072, T-073, T-074, T-075, T-076, T-091 (game-designer), T-092 (после T-091) | T-091 ← T-060, T-062; T-092 ← T-091; T-067 ← T-062; T-068 ← T-063; T-069 ← T-064; T-070 ← T-062, T-066; T-071 ← T-060, T-065; T-072, T-074 ← T-060; T-073 ← T-059, T-060; T-075 ← T-060, T-062; T-076 ← T-060, T-061 |
| 3 | T-077, T-078, T-079, T-080, T-081, T-082, T-083 | T-077 ← T-064, T-067, T-068; T-078 ← T-071..T-074; T-079 ← T-071, T-073, T-075; T-080 ← T-061, T-075, T-076; T-081 ← T-061, T-076; T-082 ← T-071, T-076; T-083 ← T-070 |
| 4 | T-084, T-085, T-086, T-087 | T-084 ← T-070, T-074, T-077, T-079, T-080; T-085 ← T-064, T-076; T-086 ← T-076; T-087 ← T-083 |
| 5 | T-088, T-096, T-097, затем T-089 | T-088 ← T-087; T-096 ← T-084; T-097 ← T-078, T-084, T-085, T-095; T-089 ← все UI-задачи (T-078, T-080..T-082, T-084..T-086) и T-097 |
| 6 | T-090, T-098, T-099, T-100, T-101 | T-090 ← T-088; T-098 ← T-097 (экран плана); T-099 ← T-072; T-100 ← T-088, T-090 (`src/scene3d/` занят); T-101 — без зависимостей |

Вне исходной нарезки (по ходу волн 2–4): T-093 (тема перед волной 3), T-094 (уточнение У-2 и снимки), T-095 (вариации и `tnum`, волна 4); волна 5 добавила T-096 и T-097 (дефекты приёмки и хвосты). Владение в волне 5: сцены экранов заезда (`src/ui/{workout,free_ride}/**`) — T-097, T-096 трогает в них только узел `SubViewport`; `src/scene3d/**` — T-088 и T-096 (T-096 — только `ride_scene.gd` и окружение сцены; при пересечении — сначала T-096, потом T-088); `scripts/dev/ui_screenshot.gd` — T-097, затем T-089.

Задача из следующей волны может стартовать раньше, как только слиты её зависимости и её файлы не заняты задачей, которая ещё в работе (например, T-075 — сразу после T-060 и T-062).

Вопросы к requirements (не блокируют старт волны 1):
- Н-13 (FRD-06 п.4). Решение оркестратора — окно графика свободной езды 30 мин, в REQ — 20 мин. Шкала мощности: в REQ `max(1.25 × FTP, максимум)`, в `hud.md` п. 8 — `max(1.5 × FTP, ⌈максимум/50⌉·50)`, уменьшается не чаще раза в 60 с. Нужна одна редакция до T-065 (модель) — до решения T-065 делает окно и коэффициент параметрами, по умолчанию 30 мин и 1.5.
- Н-14 (FRD-02 п.3). Трасса по умолчанию: в REQ — равнина, в `tracks.md` п. 3 — холмы. Нарезка следует REQ (`flat`; тренировка по плану тоже на `flat`). Подтвердить.
- Н-15 (HUD-06, WRK-05, HUD-13). Критерии `hud.md` п. 12 (9 — фишка «ДАЛЕЕ», 10 — карточка паузы, 11 — панель инструментов скрывается через 4 с) — перенесены ли в REQ? Если нет, T-074 закрывается только по существующим HUD-06 п.2 и WRK-05, а эти пункты остаются требованиями дизайна без приёмки tester.
- Н-16 (HUD-01). T-073 делается по новой редакции HUD-01 (герой — факт мощности); до внесения правки в requirements.md tester принимает HUD-01 по `hud.md` п. 5.

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

#### T-058 — Мир по референсу владельца `[visual]` — `done`
Статус. Сделано по запросу владельца с референсом (видео 2026-10-03; кадры — `docs/game/shots/2026-10-03-reference/`). Факт: шейдеры `src/scene3d/shaders/` (общий тун-свет `toon_light.gdshaderinc`, контур `outline.gdshader`, асфальт `road.gdshader`, трава `grass.gdshader`, небо `sky.gdshader`), материалы `src/scene3d/materials/`; `MeshKit` (меши с цветом вершин), `RiderModel` + `rider.tscn/.gd` (велосипедист: IK ног, покачивание корпуса, наклон `set_lean`), `RoadsideBuilder` (кромка, бордюр, полоса травы с кюветом, отбойник на внешней стороне поворотов), `TerrainField` (рельеф с холмами), `SceneryBuilder` (деревья, ели, кусты, трава; сигнальные столбики — `props()`); `RideScene` — камера в три четверти, наклон atan(v²·κ/g), сборка мира в `set_track()`; `EnvironmentSet` — новые поля. Правка чужого теста: в `tests/integration/test_ride_scene.gd` ожидаемое направление вращения колеса сменено на «вперёд» (раньше колесо крутилось назад). Арт-библия — `docs/game/art-bible.md`.
Приёмка tester (d9cee0d, `tests/integration/test_scene3d_world_acceptance.gd`): п.3–5 приняты сразу; дефекты D3D-07-C (стопа отставала от педали на кадр — AnimationPlayer обрабатывался после сцены; шатуны теперь продвигаются вручную в `Rider.advance`), D3D-07-A (на маршруте ≥ 25 км столбики занимали весь бюджет MultiMesh — потолок `MAX_PROPS_PER_SIDE`, шаг растёт), D3D-07-B (на маршруте ≥ 10 км крупная ячейка рельефа поднимала землю над дорогой — радиусы ровной зоны масштабируются ячейкой) исправлены, приёмка 25/25. Чек-лист кадра п.6 — 9–11/12 без блокирующих: щель в 1 px по стыку асфальта и кромки, гранёная кромка на повороте, ступенчатая тень (llvmpipe); п.7/8 (HUD поверх мира) — на устройстве.
Закрывает: REQ-D3D-07 п.1–5 (авто), п.6 (снимки «до/после»); REQ-D3D-03 п.3. Ручные: REQ-D3D-07 п.7 (тени и FPS на устройстве — в контейнере только gl_compatibility на llvmpipe).

### Этап 7р2 — Доработка ред. 2. Результат: HUD по референсу Zwift, свободная езда с SIM на четырёх трассах, меню в единой системе

Общее для всех карточек. Правила параллельной работы, владение файлами и волны — раздел 2, «Этап 7р2». Визуальные критерии (`[визуальная проверка]`) сдаются со снимками «до/после»: HUD и меню — `scripts/ui_screenshot.sh` (T-059), мир — `scripts/screenshot.sh`. Tester проверяет `[авто]` и однозначные визуальные пункты, спорные визуальные пункты передаёт game-designer. Для `done` нужен положительный вердикт tester, а для задач с `[визуальная проверка]` ещё и game-designer. Размер: S — полдня, M — один полный заход, L не допускается.

#### T-059 — Скрипт снимков UI и синтетический пульс эмулятора `[game]` — `done` (88b30da; приёмка 83dd2b0)
Волна 1, первая в работу. Зависит: —. Размер M.
Что сделать. По `hud.md` п. 14: `scripts/ui_screenshot.sh [каталог] [разрешение] [язык] [--safe-area]` → `scripts/dev/ui_screenshot.gd` (`extends SceneTree`, по образцу `ride_screenshot.gd`; без дисплея — `xvfb-run`). Скрипт поднимает `main.tscn` с временным `data_dir`, `trainer_kind = "fake"`, `env_reader = Callable()`, заводит два профиля, импортирует `tests/fixtures/workouts_acceptance/acc_full.zwo` и снимает каждый экран, зарегистрированный в `AppState` (после `navigate` — 6 кадров и `frame_post_draw`). HUD тренировки снимается с ускоренными часами (`WorkoutScreen.clock_usec`, ×30) на моментах 0:30, 17:00, «за 5 с до смены», пауза, последний шаг, сводка. Разрешения: 1280×720, 1024×768, 1280×590. Флаг `--safe-area` имитирует безопасную зону 100/100/0/13 lp через `Engine.set_meta("ui_debug_safe_area", …)`, который читает `UiScale` (T-060). Сценарии хранятся в таблице внутри скрипта: T-084 добавит в неё свободную езду (ровно, подъём, спуск), не переписывая остальное. Синтетический пульс: `FakeHeartRateCurve` (95 → 165 уд/мин за 20 мин, затем плато, детерминированный шум ±2) и `TrainerFactory.create("fake")` подключает его к `FakeTrainer` через существующий `set_heart_rate_sequence`. Тесты, которые ждут эмулятор без пульса, должны получить его через `FakeTrainer.new()` напрямую, а не через фабрику, — developer проверяет это по `tests/` и пишет в отчёт.
Файлы: `scripts/ui_screenshot.sh`, `scripts/dev/ui_screenshot.gd` (+ `.uid`), `src/devices/fake_heart_rate_curve.gd`, `src/devices/trainer_factory.gd`, `tests/unit/devices/test_fake_heart_rate_curve.gd`. `main.gd`, `workout_screen.*` и `fake_trainer.gd` не трогать.
Закрывает: инструмент приёмки (REQ не закрывает); REQ-DEV-09 п.5 (расширение: пульс в dev-режиме).
Критерии авто: кривая пульса монотонна на 0–20 мин, значения 95 и 165 на концах (±2); фабрика `fake` отдаёт пульс в первые 2 с; полный набор GUT зелёный. Tester запускает скрипт: код выхода 0, на каждый экран и момент HUD есть PNG ненулевого размера для трёх разрешений и двух языков, на снимке HUD середины тренировки пульс — число, а не «—».

#### T-060 — Растяжение, масштаб, шрифт Inter, иконки Lucide, тема, переводы по областям `[game]` — `done` (1f37ec7; приёмка 83dd2b0)
Волна 1. Зависит: —. Размер M.
Что сделать. `project.godot`: `display/window/stretch/mode = "canvas_items"`, `aspect = "expand"`, базовый размер 1280×720, `gui/theme/custom = app_theme.tres`, шрифт по умолчанию — `inter_400.tres` (`hud.md` п. 3, `ui.md` п. 9). `src/app/ui_scale.gd` (`UiScale`): множитель 1.0 / 1.2 (телефон), `content_scale_factor`, безопасная зона в lp с отладочной подменой `ui_debug_safe_area`. Применяется без правки `main.gd`, через автозагрузку, которую регистрирует `project.godot`. Ресурсы: `assets/fonts/inter/Inter-Variable.ttf` + `OFL.txt`, `assets/icons/lucide/*.svg` + `LICENSE` (только нужные иконки из `ui.md` п. 7), `FontVariation` по `ui.md` п. 9 (включая `tnum`-варианты для HUD), `app_theme.tres` с базовыми типами п. 9.1 и вариациями п. 9.2 (включая `Hud*`), `UiTokens` (палитра `ui.md` п. 4 и `hud.md` п. 11, только тёмная тема, акцент `#2CC9B4`). Переводы: создать и зарегистрировать `assets/i18n/strings_{hud,hud_controls,free_ride,tracks,menu,menu_lists}.csv`, заранее завести ключи `track.<id>.name`/`track.<id>.kind` (ru/en по `tracks.md` п. 3) и `ride.free_ride.default_name`; `test_i18n.gd` проверяет все `strings*.csv`, ключи уникальны во всех файлах сразу. Экраны не перекраивать: существующие `theme_override_*` снимаются в задачах экранов (T-073, T-080..T-082, T-085, T-086), итоговая статическая проверка — в T-089.
Файлы: `project.godot`, `assets/fonts/**`, `assets/icons/**`, `src/ui/theme/**`, `src/app/ui_scale.gd`, `assets/i18n/strings_*.csv` (создание), `tests/unit/app/test_i18n.gd`, `tests/unit/ui/test_app_theme.gd`, `tests/unit/app/test_ui_scale.gd`. `strings.csv`, `main.gd` и сцены экранов не трогать.
Закрывает: REQ-UIX-01 п.1, 3, 4 (часть «шрифт»); REQ-HUD-14 п.1, 2 (ресурсы шрифтов и `tnum`; применение на узлах HUD — T-073); REQ-NFR-08 п.2 (на новых файлах).
Критерии авто: тема назначена проекту, её получает каждый существующий экран; вариации типов из `ui.md` п. 9.2 существуют; цвета стилей совпадают с `UiTokens` (±1/255); все `FontVariation` ссылаются на один файл Inter; «0000» = «1111» = «8888» по ширине (±0.5 px) для размеров 11–88; `UiScale` даёт 1.2 на «мобильном» и 1.0 иначе; переводы из новых файлов загружаются. Визуально: снимки всех экранов «до/после» (T-059) — шрифт Inter, тёмный фон; поломки раскладки допустимы, их исправляют задачи экранов.

#### T-061 — Навигационный каркас ред. 2 и поля профиля `[game]` — `done` (231b84a; приёмка 83dd2b0)
Волна 1. Зависит: —. Размер M.
Что сделать. `AppState`: экраны `ROUTE_SELECT` и `FREE_RIDE`; стек переходов и `back()`: возврат на экран, с которого пришли, а для истории, настроек и устройств — на главный. `back()` на экранах `WORKOUT`/`FREE_RIDE` не уходит с экрана, а отдаёт запрос «досрочное завершение с подтверждением» (сигнал, который экран обрабатывает по WRK-05.4). `main.gd`: регистрирует новые экраны, ловит `ui_cancel` (Esc) и `NOTIFICATION_WM_GO_BACK_REQUEST` (Android) → `app_state.back()`. Заготовки сцен с итоговыми путями и контрактом `setup(...)` нужны, чтобы T-080 и T-084 не трогали `main.gd`: `src/ui/tracks/route_select_screen.{tscn,gd}` (сигнал `start_requested(route_id: String, steepness_pct: int)`) и `src/ui/free_ride/free_ride_screen.{tscn,gd}` (пустой экран с «назад»). Обработчик `start_requested` в `main.gd` — заглушка, настоящий запуск делает T-084. `Profile`: `last_route_id` (по умолчанию `"flat"`) и `sim_steepness_pct` (0–100, шаг 5, по умолчанию 50, валидация с кодом `ERR_*`); сериализация совместима со старыми профилями (поля по умолчанию). Ключи текстов заготовок — в `strings.csv` не добавлять, заготовки без текста или с уже существующими ключами.
Файлы: `src/app/app_state.gd`, `src/app/main.gd`, `src/profiles/profile.gd`, `src/profiles/profile_repository.gd`, заготовки `src/ui/tracks/route_select_screen.*`, `src/ui/free_ride/free_ride_screen.*`, `tests/unit/app/test_app_state_back.gd`, `tests/unit/profiles/test_profile_free_ride_fields.gd`.
Закрывает: REQ-UIX-04 п.1 (навигация «назад», Esc, Android), п.2 (контракт для экранов заезда); REQ-UIX-02 п.3 (переходы в историю и настройки — навигация); REQ-FRD-02 п.3 (хранение последней трассы, по умолчанию `flat`); REQ-FRD-05 п.1 (хранение крутизны, по умолчанию 50 %).
Критерии авто: цепочки переходов HOME → HISTORY → `back()` → HOME, HOME → PLAN → WORKOUT → `back()` → запрос подтверждения (экран не сменился); Esc и событие Android вызывают тот же `back()`; профиль без новых полей читается со значениями по умолчанию; некорректная крутизна (−5, 103, 7) не проходит валидацию. Ручные: REQ-UIX-04 п.1 — системный «назад» на реальном Android (вне контейнера).

#### T-062 — Профиль трассы и каталог четырёх трасс `[game]` — `done` (c60c9d1; приёмка f84b12b)
Волна 1. Зависит: —. Размер M.
Что сделать. Чистый GDScript (`RefCounted`) в `src/domain/` по `tracks.md` п. 2–4. `RouteProfile`: опорные точки (s, h) → периодическая PCHIP (Фрич–Карлсон, касательная на стыке по соседям через стык) → выборка с шагом 10 м; `height_at(s)`, `grade_at(s)` (Δh/Δs по окну 100 м, окно переходит через стык), `length_m()`, `ascent_m()`, `max_grade_pct()`, `min_grade_pct()`, `climbs()` (уклон > 2 %, длина ≥ 300 м: начало, длина, средний уклон, набор). `RouteCatalog`: четыре трассы `flat`, `hills`, `mountains` (петля по решению владельца), `seaside`; у каждой `name_key`/`kind_key` (ключи `track.<id>.name`/`.kind` заводит T-060), опорные точки, `bridges` (у `seaside` — 5820–6330 м), `water_level_m`, `landmarks`, параметры план-схемы `layout` + `seed` (для T-070), `mood_color`, идентификатор набора окружения (строка; маппинг на `.tres` — `src/scene3d/route_world.gd`, T-070). Трасса по умолчанию — `flat` (REQ FRD-02 п.3; вопрос Н-14).
Файлы: `src/domain/route_profile.gd`, `src/domain/route_catalog.gd`, `tests/unit/domain/test_route_profile.gd`, `tests/unit/domain/test_route_catalog.gd`.
Закрывает: REQ-D3D-08 п.1 (кроме отображения названий — T-080), п.2 (замкнутость профиля и уклона), п.3; основа для REQ-FRD-03 п.1.
Критерии авто: ровно четыре трассы с уникальными id; |h(L) − h(0)| ≤ 0.1 м, разрыв уклона на стыке ≤ 1 %; характеристики каждой трассы — в диапазонах D3D-08 п.3 и равны таблице `tracks.md` п. 3 (длина ±0.1 км, набор ±5 м, макс. уклон ±0.3 %); тестовый профиль FRD-03 п.1 (1000 м ровно, 1000 м +50 м, 1000 м −50 м) даёт 3.0 км, 50 м, 5.0 % (±0.1); у приморья мост в данных, полотно на мосту выше `water_level_m` не меньше чем на 10 м. Ручных нет.

#### T-063 — SIM в FTMS-кодеке и в `TrainerDevice` `[game]` — `done` (c1b5624; приёмка f84b12b)
Волна 1. Зависит: —. Размер M.
Что сделать. `FtmsCodec`: `encode_indoor_bike_simulation(wind_mps, grade_pct, crr, cw)` по вводному абзацу FRD (опкод `0x11`, sint16 LE ветер ×1000, sint16 LE уклон ×100, uint8 Crr ×10000, uint8 Cw ×100; вне диапазона → ошибка, без байтов), `decode_supported_inclination_range` (`0x2AD5`: min, max sint16 ×0.1 %, increment uint16), бит «Indoor Bike Simulation Parameters Supported» в Target Setting Features `0x2ACC`. `BleUuids` — константы `0x2AD5`, `0x2ACC`, если их нет. `TrainerDevice`: `set_simulation(grade_pct: float)` (ветер, Crr, Cw по умолчанию 0 / 0.004 / 0.20), `simulation_support() -> int` (`UNKNOWN`/`SUPPORTED`/`UNSUPPORTED`), `inclination_range() -> Vector2` (запасной диапазон −10…+20 %), код ошибки `SIMULATION_REJECTED`. `BleTrainer`: после подключения читает `0x2ACC` и `0x2AD5` (`read_characteristic`), пишет `0x11` в Control Point, результат ≠ `0x01` → `error(SIMULATION_REJECTED)` и `UNSUPPORTED`. `FakeTrainer`: команда `CMD_SIM` в журнале, `set_simulation_supported(bool)`, `set_inclination_range(min, max)`; мощность в SIM задаёт `set_rider_power` (ERG не включается). Контракт `BleBridge` и `native/ble/` не меняются — подтвердить в отчёте.
Файлы: `src/devices/ble/codecs/ftms_codec.gd`, `src/devices/ble/ble_uuids.gd`, `src/devices/trainer_device.gd`, `src/devices/ble_trainer.gd`, `src/devices/fake_trainer.gd`, `tests/unit/devices/test_ftms_sim_codec.gd`, `tests/unit/devices/test_ble_trainer_sim.gd`, `tests/unit/devices/test_fake_trainer_sim.gd`.
Закрывает: REQ-FRD-04 п.1; п.3 (чтение диапазона и запасной диапазон; ограничение уклона — T-068); п.6 (определение поддержки по `0x2ACC` и коду результата; переход на сопротивление и сообщение — T-068, T-084).
Критерии авто: все байтовые примеры FRD-04 п.1 (5.00 %, −3.00 %, 0 %, 12.34 %, ветер 1.5 м/с, Crr, Cw) и отклонение значений вне диапазона; на `StubBleBridge` после подключения есть чтения `0x2ACC` и `0x2AD5`, затем запись `0x11` по `set_simulation`; ответ `0x11` с кодом `0x02` → `UNSUPPORTED` и ошибка; `FakeTrainer` пишет `CMD_SIM` в журнал. Ручные: REQ-FRD-04 п.10 (Tacx Neo, вне контейнера).

#### T-064 — Хранилище свободной езды: потоки, метаданные, сводка, название для Strava `[integration]` — `done` (2bdd110; приёмка f84b12b)
Волна 1. Зависит: —. Размер M.
Что сделать. `SampleStream` и сэмпл заезда: необязательные поля `distance_m` (накопленная), `altitude_m`, `grade_pct`, которые у заездов по плану отсутствуют. `FileRideRepository`: запись и чтение этих потоков; старые заезды без них читаются без ошибок (миграция не нужна). Метаданные `Ride`: `ride_type` (`workout`/`free_ride`), `route_id`, `sim_steepness_start_pct`, `total_distance_m`, `total_ascent_m`; у свободной езды `speed_source = model`, названия плана нет. `RideSummary`: набор высоты — сумма положительных приращений `altitude_m` между соседними сэмплами; поля, связанные с целью, — «нет значения» без ошибок. `RideSeries`: без серии цели, без ошибки; серия высоты по дистанции (для T-085). `StravaService`: название по умолчанию для свободной езды — `tr("ride.free_ride.default_name") % <название трассы>` (ключи заводит T-060; CSV не править).
Файлы: `src/session/sample_stream.gd`, `src/storage/ride.gd`, `src/storage/ride_recorder.gd`, `src/storage/file_ride_repository.gd`, `src/storage/ride_summary.gd`, `src/storage/ride_series.gd`, `src/integrations/strava/strava_service.gd`, `tests/unit/storage/test_free_ride_storage.gd`, `tests/unit/integrations/test_strava_free_ride_name.gd`.
Закрывает: REQ-FRD-07 п.3 (метаданные), п.4 (хранение полей и расчёт набора по сэмплам), п.6 (сводка и серии без цели; список истории — T-085), п.7.
Критерии авто: сохранение и чтение заезда свободной езды через `RideRepository` возвращает дистанцию, высоту и уклон каждого сэмпла; старый заезд из фикстуры читается; набор по синтетическим сэмплам двух кругов = 2 × набор круга ± 5 %; сводка без цели без ошибок, поля цели «—»; название в очереди Strava — «Свободная езда — <трасса>» на ru и en; LOC-01..LOC-07 и STR-02..05 не регрессируют. Ручных нет.

#### T-065 — Модели нижнего графика HUD `[game]` — `done` (3d79191; приёмка 83dd2b0)
Волна 1. Зависит: —. Размер M.
Что сделать. Только модели, без отрисовки (`RefCounted`, headless) по `hud.md` п. 7, 8. `PlanChartModel`: сегменты из `Workout.segments()` с учётом множителя WRK-07 (начало, длительность, цели в начале и в конце, зона, признак «свободно»); рампа, пересекающая границы зон, режется на куски по зонам (`hud.md` п. 12.3); `y_max = 1.25 × максимальная цель`; пересчёт при смене множителя; состояния `пройдено`/`предстоит`/`пропущено`; курсор x(t), на паузе не двигается. `TimeAxis`: шаг подписей из ряда 1, 2, 5, 10, 15, 30, 60 мин, не больше 10 подписей, формат `мм` / `ч:мм`. `EffortSeries`: серия сглаженной мощности (HUD-09) и серия пульса по сэмплам; «нет данных» и пульс 0 дают разрыв; пауза не добавляет точек; обрезка по `y_max` с флагом; прореживание до ≤ 2 × ширины с сохранением min/max в корзине; своя шкала пульса 50…`max_hr` (или 200); токены цвета (`power_line`, `hr_line`), стиль серии пульса — «линия без площади»; подписи шкалы пульса на противоположной стороне. Режим скользящего окна для свободной езды: окно и коэффициент шкалы — параметры, по умолчанию 30 мин и 1.5 × FTP (решение оркестратора и `hud.md` п. 8; расхождение с FRD-06 п.4 — вопрос Н-13).
Файлы: `src/ui/hud/plan_chart_model.gd`, `src/ui/hud/effort_series.gd`, `src/ui/hud/time_axis.gd`, `tests/unit/ui/test_plan_chart_model.gd`, `tests/unit/ui/test_effort_series.gd`, `tests/unit/ui/test_time_axis.gd`.
Закрывает: REQ-HUD-10 п.1–5; REQ-HUD-11 п.1–5; REQ-HUD-12 п.1, 2, 5, 6, 7 (п.4 — токен, цвет проверяется в T-071); REQ-FRD-06 п.4 (модель окна и шкалы).
Критерии авто: все `[авто]` перечисленных пунктов на моделях (поток 100, 200, 300, 300 → 100, 150, 200, 267; план 3 ч на 1280 px → ≤ 2560 точек, пик 30-секундного спринта среди точек; план 60 мин → шаг 10 мин, 20 мин → 5 мин; рампа 40 → 70 % FTP → 2 куска). Ручных нет.

#### T-066 — Длинные трассы: коридорный рельеф и куски MultiMesh `[visual]` — `done` (6871a91; приёмка f84b12b, edbeef9)
Волна 1. Зависит: —. Размер M.
Что сделать. По `tracks.md` п. 5, на существующей `LoopTrack`, растянутой до 20 км (трассы и профиль появятся в T-062/T-070). `TerrainField`: вместо одной сетки на габарит — коридор вдоль трассы кусками (например, по 500 м, ширина видимой зоны), с LOD или крупной ячейкой вдали, форма рельефа на 20 км не хуже, чем сейчас на 2 км. `SceneryBuilder` и столбики `RoadsideBuilder`: MultiMesh кусками по ~500 м с `visibility_range` (видно ±1.5 км), плотность — на километр. `PerfBudget` и `docs/perf_budget.md`: бюджет «видимо с любой точки трассы» вместо «всего на трассе». Снимки «до/после» на 2 км и 20 км.
Файлы: `src/scene3d/terrain_field.gd`, `src/scene3d/scenery_builder.gd`, `src/scene3d/roadside_builder.gd`, `src/scene3d/perf_budget.gd`, `docs/perf_budget.md`, `tests/integration/test_long_route_world.gd`. `ride_scene.gd` — только если без него нельзя (сообщить в отчёте).
Закрывает: REQ-D3D-08 п.6 (бюджет на длинной трассе; состав окружений — T-083, T-087, T-088, T-090); REQ-D3D-05 п.2 (бюджет в редакции В-7); регрессия REQ-D3D-07 п.1–5 и дефектов D3D-07-A/B.
Критерии авто: на петле 20 км число видимых экземпляров MultiMesh с любой точки (шаг 250 м) ≤ бюджета; рельеф не выше полотна в пределах ширины дороги; приёмочные тесты D3D-07 зелёные на 2 и 20 км. Визуально: чек-лист `ride-visual-review` ≥ 10/12 на снимках 0/400/900/1500 м и на тех же точках петли 20 км. Ручные: FPS на устройстве (D3D-05 п.1).

#### T-067 — Модель скорости с уклоном и позиция на трассе `[game]` — `done` (e057f74; приёмка d62b281)
Волна 2. Зависит: T-062. Размер S–M.
Что сделать. `SpeedModel`: установившаяся скорость и шаг инерции с уклоном по вводному абзацу FRD (P = v · (m·g·(Crr·cos θ + sin θ) + 0.5·ρ·CdA·v²), m = вес + 8 кг); на уклоне 0 — прежние значения D3D-02. `RoutePosition` (`src/domain/`): по скорости и dt продвигает s по модулю L; накопленная дистанция, номер круга, h(s), g(s) из `RouteProfile`; набор по сэмплам. Тренировка по плану эту модель не использует (решение оркестратора: на `flat` без уклона).
Файлы: `src/domain/speed_model.gd`, `src/domain/route_position.gd`, `tests/unit/domain/test_speed_model_grade.gd`, `tests/unit/domain/test_route_position.gd`.
Закрывает: REQ-FRD-04 п.2 (позиция s как интеграл скорости), п.7, п.8 (модель берёт полный уклон, крутизна — только для станка); REQ-FRD-07 п.1 (оборачивание s и монотонная дистанция на модели); регрессия REQ-D3D-02 п.1–4.
Критерии авто: опорные значения FRD-04 п.7 (200 Вт: 0 % → 34 ± 3, 5 % → 15.2 ± 1.5, 10 % → 8.4 ± 1.0 км/ч; 0 Вт, −5 % → 49.8 ± 3); монотонность по P, g, m; 4 ч при 250 Вт на `flat`: дистанция > 10 L, скачок высоты на стыке ≤ 0.1 м. Ручных нет.

#### T-068 — `SimController`: уклон на станок, крутизна, режимы `[game]` — `done` (c9762f9; приёмка d62b281)
Волна 2. Зависит: T-063. Размер M.
Что сделать. `src/session/sim_controller.gd` (`RefCounted`, время извне через `tick`). Вход: уклон трассы g(s) на каждом тике, крутизна k, режим `SIM`/`FIXED`, уровень сопротивления. Выход — команды `TrainerDevice`: `set_simulation(round(g·k/100, 0.01))`, ограниченный `inclination_range()`; не чаще раза в 1 с и только при изменении ≥ 0.1 %; принудительная отправка (не позже 1 с, без порога) при старте, `resume()`, восстановлении связи и смене крутизны; переключение `SIM` ↔ `FIXED` одним вызовом (в `FIXED` — `set_resistance_level` по WRK-04.2, команд `0x11` нет); при `UNSUPPORTED` или `SIMULATION_REJECTED` — переход в `FIXED` и сигнал `simulation_unavailable` (текст сообщения — T-084). Ни одной `set_target_power`. События для журнала заезда: смена режима, смена крутизны.
По итогам волны 1 (T-063). `SensorHub extends TrainerDevice` (`src/devices/sensor_hub.gd`) должен делегировать станку `set_simulation`, `simulation_support` и `inclination_range` — сейчас этого нет, и через хаб SIM не дойдёт до `BleTrainer`; файл добавлен в эту задачу. `BleTrainer` сам не блокирует `0x11` при `UNSUPPORTED` — решение «SIM или фиксированное сопротивление» целиком на `SimController` (проверить тестом: при `UNSUPPORTED` контроллер не шлёт `set_simulation`).
Файлы: `src/session/sim_controller.gd`, `src/devices/sensor_hub.gd` (делегирование SIM), `tests/unit/session/test_sim_controller.gd`, тест делегирования в `tests/unit/devices/` (новый файл).
Закрывает: REQ-FRD-04 п.2 (передаваемый уклон), п.3 (ограничение диапазоном), п.4, п.5, п.6 (переход на сопротивление); REQ-FRD-05 п.1 (применение крутизны), п.2, п.3, п.4; REQ-FRD-01 п.2 (нет `0x05`, первая команда — `0x11` или `0x04`).
Критерии авто: все `[авто]` перечисленных пунктов на `FakeTrainer` и `StubBleBridge` (g = 8 %, k = 50 % → 4.00 %; g = −4 %, k = 50 % → −2.00 %; 10 мин «гор» → ≤ 600 команд `0x11`, интервалы ≥ 1000 мс). Ручные: REQ-FRD-05 п.7 (Neo).

#### T-069 — FIT свободной езды `[integration]` — `done` (a7405a8; приёмка d62b281)
Волна 2. Зависит: T-064. Размер M.
Что сделать. `FitEncoder`: в `record` — `distance` (поле 5, м × 100), `enhanced_altitude` (поле 78) или `altitude` (поле 2; масштаб 5, смещение 500), `grade` (поле 9, % × 100), только если у сэмпла есть эти поля; в `session` — `total_distance` (9), `total_ascent` (22); `lap` — на каждый полный круг трассы и неполный последний (по `distance_m` и длине трассы из метаданных) вместо шагов плана. `FitDecoder` (тестовый) читает новые поля.
По итогам волны 1 (T-064). Источник данных: `distance_m`, `altitude_m`, `grade_pct` сэмплов и признак `has_route` — из `SampleStream`; итоги сессии — `Ride.total_distance_m()` и `Ride.total_ascent_m()`, свой подсчёт набора не делать.
Файлы: `src/integrations/fit/fit_encoder.gd`, `src/integrations/fit/fit_definitions.gd`, `src/integrations/fit/fit_decoder.gd`, `tests/unit/integrations/test_fit_free_ride.gd`.
Закрывает: REQ-FRD-07 п.5; регрессия REQ-LOC-05 п.1–4.
Критерии авто: декодированные значения совпадают с сэмплами (дистанция ±0.01 м, высота ±0.2 м, `total_ascent` ±1 м); 2.5 круга → 3 `lap`; FIT заезда по плану не изменился (те же тесты LOC-05 зелёные). Ручные: REQ-FRD-07 п.8 (реальный Strava).

#### T-070 — `ProfiledTrack`: дорога, гонщик и камера на профиле `[visual]` — `done` (431b324; приёмка d62b281)
Волна 2. Зависит: T-062, T-066. Размер M.
Что сделать. `ProfiledTrack extends Track`: план-схема каждой трассы по `layout` + `seed` из `RouteCatalog`, длина равна длине профиля, высота дороги — h(s); стык круга непрерывен. `RouteWorld` (`src/scene3d/route_world.gd`): id трассы → `ProfiledTrack` + `EnvironmentSet` (пока у всех `default_environment.tres`). `RideScene.set_route(id)`; по умолчанию `flat` (тренировка по плану не меняет `workout_screen`). `RoadBuilder`/`RoadsideBuilder`: полотно, кромка, трава, кювет — относительно высоты полотна; `TerrainField`: рельеф относительно дороги, поперечный склон вдоль подъёмов (`tracks.md` п. 5). `Rider`: продольный наклон atan(g/100); камера D3D-07.5 на подъёмах и переломах. Снимки по дистанциям `tracks.md` п. 8.8 для всех четырёх трасс (пока на общем окружении).
По итогам волны 1 (T-066). Дорогу (`RoadBuilder`) и обочину (`RoadsideBuilder`) строить кусками, без лимитов `RoadBuilder.MAX_SEGMENTS` и `RoadsideBuilder.MAX_RINGS`: на 20 км они дают шаг 50 м и 28.6 м — изломы полотна и щель асфальт–бордюр (критерий: шаг ≤ шага на 2 км, щели нет на кадрах 20 км). База рельефа `TerrainField._height` — относительно h(s) трассы, а не средней высоты. В `docs/scene3d.md` — абзац о рельефе-коридоре и кусках (дорога, обочина, MultiMesh, `visibility_range`).
Файлы: `src/scene3d/profiled_track.gd`, `src/scene3d/route_world.gd`, `src/scene3d/road_builder.gd`, `src/scene3d/roadside_builder.gd`, `src/scene3d/terrain_field.gd`, `src/scene3d/rider.gd`, `src/scene3d/ride_scene.gd`, `docs/scene3d.md`, `tests/integration/test_profiled_track.gd`.
Закрывает: REQ-D3D-08 п.2 (горизонтальная геометрия на стыке), п.4, п.5, п.7; REQ-D3D-03 п.1, 2 (на новых трассах).
Критерии авто: высота оси дороги и гонщика = h(s) ± 0.05 м с шагом 50 м по кругу на каждой трассе; рельеф не выше полотна в пределах ширины; наклон гонщика = atan(g/100) ± 1°; требования камеры D3D-07.5 на всех точках, включая максимальный уклон и перелом; тесты D3D-02, D3D-04, D3D-07.2–3 зелёные на всех четырёх трассах; бюджет T-066 соблюдён. Визуально: на кадрах подъёма дорога видимо уходит вверх, на спуске — вниз; чек-лист ≥ 10/12. Ручные: REQ-D3D-08 п.9.

#### T-071 — Рисовальщик `HudChart` и превью плана `[game]` — `done` (ca89bea; приёмка 6e84ef1)
Волна 2. Зависит: T-060, T-065. Размер M.
Что сделать. `HudChart` (`Control`, `_draw`) по `hud.md` п. 7 поверх моделей T-065: сегменты плана цветом `ZonePalette`, скруглённые верхние углы `min(5·s, w/2)`, зазор 1·s, рампы наклонным верхом кусками по зонам, FreeRide — нейтральный `hud.free` со штриховкой на 30 % высоты, пройденное приглушено, курсор; линия мощности `#F5F7FA` и линия пульса `#FF4757` толщиной 2·s с обводкой; порядок: план → пульс → мощность; у пульса только полилиния, без заливки; шкалы мощности и пульса по разные стороны. Режим «скользящее окно» (без плана) — заготовка API, наполнение в T-079. `PlanPreview` — тот же рисовальщик в компактном режиме для карточек (UIX-03.4); заменит `src/ui/plan/workout_chart.gd` в T-082.
Файлы: `src/ui/hud/hud_chart.gd`, `src/ui/common/plan_preview.gd`, `tests/unit/ui/test_hud_chart_draw.gd`.
Закрывает: REQ-HUD-10 п.6; REQ-HUD-11 п.6; REQ-HUD-12 п.3, 4; REQ-UIX-03 п.4 (план: превью и график из одной модели).
Критерии авто: токены цвета сегментов совпадают с зонами, «свободно» — нейтральный; порядок вызовов отрисовки; для пульса ни одного залитого полигона; цвет пульса в диапазоне тона 345–15°, насыщенность ≥ 0.6. Визуально — в T-078 (на экране); здесь снимок отдельной сцены-стенда с `acc_full.zwo`.

#### T-072 — Список интервалов `[game]` — `done` (cf77938; приёмка 6e84ef1)
Волна 2. Зависит: T-060. Размер S–M.
Что сделать. По `hud.md` п. 6. `IntervalListModel`: строка на шаг — длительность, цель в Вт с учётом множителя или «свободно», зона; состояния `текущий` (ровно один), `пройден`, `пропущен`, `предстоит`; повторы — каждый шаг отдельной строкой, пока владелец не решил иначе (открытое решение 27). `IntervalList` (`Control`): текущая строка выше и залита цветом зоны с текстом `hud.ink`, прокрутка к текущей (300 мс), ширина — из `HudLayout` (параметр). Ключи текстов — только существующие или в отчёт для T-078 (CSV `strings_hud.csv` в этой волне у T-073).
Файлы: `src/ui/hud/interval_list_model.gd`, `src/ui/hud/interval_list.gd`, `tests/unit/ui/test_interval_list_model.gd`.
Закрывает: REQ-HUD-13 п.2, 3 (компонент; размещение в левых 25 % — T-078).
Критерии авто: одна строка «текущий»; после смены шага выделение на новой строке не позже следующего сэмпла; при 30 шагах текущая строка в видимой области; пропущенный шаг — `пропущен`. Ручных нет.

#### T-073 — Каркас экрана тренировки и панель цифр `[game]` — `done` (588e978; приёмка bb178af)
Волна 2. Зависит: T-059, T-060. Размер M.
Что сделать. `WorkoutScreen`: `RideScene` рендерится в физическом разрешении окна (вариант из `hud.md` п. 3: сцена в корневом вьюпорте, HUD в `CanvasLayer`, или размер `SubViewport` = `get_window().size`); `HudLayout` — геометрия `hud.md` п. 4.1 (панель цифр, левый слот, слот графика, слот подсказки, статусы) с безопасной зоной из `UiScale`. `HudMetricPanel` по `hud.md` п. 5 и новой редакции HUD-01: герой — факт мощности (сглаженный, с полосой зоны и отклонением), карточка цели с зоной и обратным отсчётом, время, пульс, каденс, скорость; цифры — `Hud*`-вариации темы с `tnum`, поле резервирует ширину под максимум разрядов (`hud.md` п. 5.3); подложки `HudPlate` (альфа ≥ 0.78). Фишки статусов и кнопка паузы справа сверху. Режим панели «свободная езда» не делать (T-079), но API панели — с режимом. Слоты графика и списка пока пустые (наполняет T-078); старую полосу прогресса не удалять до T-078. Снять `theme_override_*` с HUD.
Файлы: `src/ui/workout/workout_screen.tscn`, `src/ui/workout/workout_screen.gd`, `src/ui/hud/hud_layout.gd`, `src/ui/hud/hud_metric_panel.{tscn,gd}`, `assets/i18n/strings_hud.csv`, `tests/unit/ui/test_hud_layout.gd`, `tests/unit/ui/test_hud_metric_panel.gd`.
Закрывает: REQ-HUD-01 (новая редакция, вопрос Н-16); REQ-HUD-13 п.1, 5, 6; REQ-HUD-14 п.3, 4, 5; регрессия REQ-HUD-02..06, HUD-09; критерий `hud.md` п. 12.1 (3D в физическом разрешении) — если перенесён в REQ.
Критерии авто: прямоугольники узлов на разрешениях из вводного абзаца HUD — панель в верхних 30 % и по центру (±5 %), центральная зона свободна, элементы не пересекаются; смена значений 9 → 99 → 100 → 999 (мощность до 9999, скорость 9.9 → 99.9, время 9:59 → 10:00 → 1:00:00) не сдвигает соседей (±1 px); контраст ≥ 4.5:1; размер текстуры 3D = размер окна ±1 px. Визуально (T-059): чек-лист `hud.md` п. 14 H1, H4, H5, H6 на 1280×720, 4:3 и телефоне. Ручные: REQ-HUD-14 п.6, HUD-01 п.4.

#### T-074 — Компоненты управления HUD `[game]` — `done` (06ab853; приёмка 6e84ef1)
Волна 2. Зависит: T-060. Размер M.
Что сделать. По `hud.md` п. 10. `NextChip` — фишка «ДАЛЕЕ · длительность · цель» с полосой цвета зоны следующего шага и секундами 5…1 (появление и исчезание 200 мс). `PauseOverlay` — вуаль `hud.ink` 0.35 и карточка «Пауза» с «Продолжить», «Пропустить шаг» (только план) и «Завершить» (→ подтверждение WRK-05.4). `HudToolbar` — колонка у правого края, появляется по вводу и скрывается через 4 с; режим «план» (ERG, интенсивность ±5 %, сопротивление ±5 при ERG выкл, пропуск, завершить) и режим «свободная езда» (SIM ↔ сопротивление, крутизна ±10 % или сопротивление ±5, завершить). Горячие клавиши: Пробел/Enter, Esc, E, `+`/`−`, N. Компоненты отдают сигналы и не знают о сессии; к экранам их подключают T-078 и T-084.
Файлы: `src/ui/hud/next_chip.gd`, `src/ui/hud/pause_overlay.{tscn,gd}`, `src/ui/hud/hud_toolbar.{tscn,gd}`, `assets/i18n/strings_hud_controls.csv`, `tests/unit/ui/test_hud_controls.gd`.
Закрывает: REQ-HUD-06 п.2 (отображение «скоро смена» — модель уже есть с T-029); REQ-WRK-05 и REQ-WRK-03 п.1 (UI-часть); REQ-FRD-05 п.4, 6 (органы управления); критерии `hud.md` п. 12.9–12.11, если requirements перенёс их в REQ (вопрос Н-15).
Критерии авто: панель скрыта через 4 ± 0.5 с без ввода; в режиме «свободная езда» нет «Пропустить шаг» и ERG; каждая кнопка и клавиша выдаёт свой сигнал; цели нажатия ≥ 44 lp. Визуально — на экранах в T-078 и T-084.

#### T-075 — Превью трассы `[game]` — `done` (002b3bb; приёмка 6e84ef1)
Волна 2. Зависит: T-060, T-062. Размер M.
Что сделать. По `tracks.md` п. 7. `RoutePreviewModel`: серия (s, h) по кругу, прореживание ≤ 2 × ширины с сохранением локальных экстремумов, ось Y крупного профиля — от min до max с полями ≥ 10 %, у миниатюры — размах `max(перепад, 150 м)`; куски заливки по палитре уклона (`hud.md` п. 11); подъёмы для подписей (не больше трёх); диапазон моста; цифры и форматы (км с 1 знаком, целые м, % с 1 знаком) через функции `RouteProfile`. `RoutePreview` (`Control`): режимы «миниатюра» и «крупный», без интерактива. Единицы — ключи в `strings_tracks.csv`.
Файлы: `src/ui/tracks/route_preview_model.gd`, `src/ui/tracks/route_preview.gd`, `assets/i18n/strings_tracks.csv`, `tests/unit/ui/test_route_preview_model.gd`.
Закрывает: REQ-FRD-03 п.1–3; REQ-UIX-03 п.2 (содержимое карточки трассы), п.4 (трасса: одна модель с HUD-панелью рельефа).
Критерии авто: тестовый профиль FRD-03 п.1 → «3.0 км», «50 м», «5.0 %» на ru и en; поля 10 %; число точек ≤ 2 × ширины, экстремумы среди точек. Визуально — в T-080.

#### T-076 — Общие компоненты меню `[game]` — `done` (6391da8; приёмка 6e84ef1)
Волна 2. Зависит: T-060, T-061. Размер S–M.
Что сделать. По `ui.md` п. 6, 9.2: `AppBar` (заголовок `H1Label`, «назад» → `app_state.go_back()` — так метод назван в T-061, слот действий справа), `StatView` (число `tnum` + единица `text2`), `Banner` (warn/error/info), `ListRow` (`ListRowButton` с колонками), `EmptyState` (иконка, текст, действие). Только вариации темы, без `theme_override_*`. Стенд-сцена для снимков.
По итогам волны 1 (T-060). Минимальный размер цели нажатия темой не задаётся: нужен общий хелпер `src/ui/common/touch_target.gd` (или аналог) — `custom_minimum_size` по `UiScale.touch_ui()` (52 lp на сенсорных устройствах, 40 lp на компьютере; HUD — `touch_hud()`); хелпер применяют компоненты этой задачи и экранные задачи (T-078, T-080..T-082, T-084..T-086), T-089 проверяет матрицей.
Файлы: `src/ui/common/app_bar.{tscn,gd}`, `src/ui/common/stat_view.{tscn,gd}`, `src/ui/common/banner.{tscn,gd}`, `src/ui/common/list_row.{tscn,gd}`, `src/ui/common/empty_state.{tscn,gd}`, `src/ui/common/touch_target.gd`, `assets/i18n/strings_menu.csv`, `tests/unit/ui/test_menu_components.gd`.
Закрывает: REQ-UIX-01 п.3 (компоненты используют вариации темы), REQ-UIX-04 п.1 (компонент «назад»).
Критерии авто: «назад» в `AppBar` вызывает `app_state.go_back()`; хелпер даёт 52 lp на телефоне и планшете и 40 lp на компьютере (подмена устройства через `ui_debug_device`); компоненты без локальных переопределений цвета и шрифта; цели нажатия ≥ 44 lp. Ручных нет.

#### T-077 — `FreeRideSession` `[game]` — `done` (013a0d8; приёмка d62b281)
Волна 3. Зависит: T-064, T-067, T-068. Размер M.
Что сделать. `src/session/free_ride_session.gd` — сессия без плана, по образцу `WorkoutSession`, без `IntervalExecutor`. Тики 1 Гц извне (`SessionTicker`); скорость — `SpeedModel` с полным уклоном (`speed_source = model`); позиция — `RoutePosition`; станок — через `SimController` (старт: Request Control → `0x11` или `0x04`, если заранее выбран фиксированный режим); пауза и возобновление по WRK-05/В-4 (на паузе на станок ничего, дистанция и время стоят; при возобновлении — принудительная отправка); восстановление связи — принудительная отправка; события (пауза, смена режима и крутизны, обрывы); сэмплы с `distance_m`, `altitude_m`, `grade_pct`; без лимита; `stop()` — только явный вызов, затем сохранение через `RideRecorder` с метаданными T-064. Сеть не нужна.
По итогам волны 1 (T-064). Сессия реализует контракт, который ждёт `RideRecorder`: сигналы `state_changed(int)`, `event_logged(Dictionary)`, `second_elapsed(int)`; методы `get_state()`, `elapsed_sec()`, `metadata()`; свойства `samples`, `events`, `started_at_unix`. Метаданные — `Ride.free_ride_metadata(route, steepness)`. Сэмплы — `SampleStream.append(..., {distance_m, altitude_m, grade_pct})`. Подписки в `RefCounted` — только связанными методами, отключение в `dispose()`.
Файлы: `src/session/free_ride_session.gd`, `tests/unit/session/test_free_ride_session.gd`, `tests/integration/test_free_ride_long_run.gd`.
Закрывает: REQ-FRD-01 п.1 (сессия без исполнителя), п.2, п.3; REQ-FRD-04 п.5 (старт, пауза, переподключение), п.9; REQ-FRD-05 п.5, п.6 (события); REQ-FRD-07 п.1, п.2 (пауза и сохранение после stop), п.3, п.4.
Критерии авто: ускоренная симуляция 4 ч при 250 Вт на `flat` не завершается сама, дистанция > 10 L, стык без скачка высоты > 0.1 м; в журнале `FakeTrainer` нет `CMD_TARGET_POWER`; с мок-транспортом «нет сети» сессия стартует; смена режима и крутизны не меняет таймер, запись и позицию; набор N кругов = N × набор трассы ± 5 %. Ручных нет.

#### T-078 — Сборка HUD тренировки `[game]` — `review` (b2d48da; приёмка 6e84ef1 с дефектами → T-097)
Итог приёмки (6e84ef1). На телефоне (s = 1.2) не выполнены HUD-13 п.5 (центральная зона), п.6 (пересечения, зазор список — панель), п.9 (слот подсказки у низа над графиком). Исправляет T-097; `done` — по повторной приёмке tester после T-097. Полоса прогресса пока скрытым узлом — удаляет T-097.
Волна 3. Зависит: T-071, T-072, T-073, T-074. Размер M.
Что сделать. В `WorkoutScreen` встроить `HudChart` (слот снизу во всю ширину, 12–22 % высоты, градиент над графиком), `IntervalList` (левый слот), `NextChip` (слот подсказки, за 5 с до смены), `PauseOverlay` (между 3D и HUD) и `HudToolbar` (режим «план»), привязать к сессии; удалить `WorkoutProgressBar` (HUD-07 по смыслу заменён HUD-10). Тренировка по плану — трасса `flat` (умолчание `RideScene` из T-070), станку уклон не уходит, скорость — по D3D-02. Компоненты T-071..T-074 не менять: нужная правка → в отчёт.
Файлы: `src/ui/workout/workout_screen.{tscn,gd}`, удаление `src/ui/workout/workout_progress_bar.gd` (+ `.uid`), `assets/i18n/strings_hud.csv`, `tests/unit/ui/test_workout_screen_layout.gd`.
Закрывает: REQ-HUD-10 п.7; REQ-HUD-11 п.7; REQ-HUD-12 п.8; REQ-HUD-13 п.2, 3 (на экране), п.4, п.7; REQ-HUD-07 (замена полосы, тесты HUD-07 переносятся на модель графика — согласовать с tester).
Критерии авто: график прижат к низу, ширина окна, 12–22 % высоты; список в левых 25 %; центральная зона свободна, пересечений нет на всех разрешениях; при паузе курсор стоит; в тренировке по плану в журнале нет `CMD_SIM`. Визуально (T-059, `acc_full.zwo`): чек-лист `hud.md` п. 14 H1–H12 на моментах начало / 17:00 / −5 с / пауза / последний шаг на 1280×720, 4:3 и телефоне, сверка с `zwift_hud_workout.png`. Ручные: REQ-HUD-10 п.8 (1.5 м).

#### T-079 — Компоненты HUD свободной езды `[game]` — `review` (36452a1)
Итог. Отдельного отчёта tester по T-079 нет: FRD-06 и FRD-05 п.6 проверялись на экране T-084 (6e84ef1). Нужно подтверждение tester, что FRD-06 п.1–4 и FRD-05 п.6 закрыты, — тогда `done`. Подвал панели рельефа на телефоне — в T-097.
Волна 3. Зависит: T-071, T-073, T-075. Размер M.
Что сделать. По `hud.md` п. 8. `ReliefPanel` (левый слот): шапка с трассой и кругом, профиль круга целиком с пройденной частью и точкой позиции, строка «дистанция / длина круга · набор», профиль «впереди 2 км» (s − 200 … s + 2000 м, минимальный размах 40 м, подпись самого крутого места), подвал «до вершины … / подъём через …». Модель — на `RoutePreviewModel` (одна серия с превью). `HudMetricPanel` — режим «свободная езда»: время, дистанция (км, 2 знака, накопленная), скорость, набор; полоса прогресса круга; карточка «УКЛОН» (g(s) трассы, знак всегда, 1 знак, клин цвета уклона, строка `SIM 50 %` / `СОПР. 40 %`); герой — факт мощности без отклонения; пульс, каденс; цели, отсчёта и списка нет. `HudChart` — режим «история усилия»: окно из T-065, мощность площадью по зонам + белая линия, пульс красной линией, FTP пунктиром.
Файлы: `src/ui/hud/relief_panel.gd`, `src/ui/hud/hud_metric_panel.gd`, `src/ui/hud/hud_chart.gd`, `assets/i18n/strings_free_ride.csv`, `tests/unit/ui/test_relief_panel.gd`, `tests/unit/ui/test_free_ride_metric_panel.gd`.
Закрывает: REQ-FRD-06 п.1, п.2, п.3, п.4 (отрисовка); REQ-FRD-05 п.6 (режим и крутизна на HUD).
Критерии авто: маркер на x = (s mod L)/L × ширина (±1 px) и на высоте профиля, после круга — у левого края; на HUD уклон трассы, а не переданный станку; форматы FRD-06 п.1, «—» при отсутствии данных; правила HUD-11/12 на графике истории. Визуально — в T-084.

#### T-080 — Экран выбора трассы `[game]` — `done` (c36d3d1; приёмка 6e84ef1)
Волна 3. Зависит: T-061, T-075, T-076. Размер M.
Что сделать. По `ui.md` п. 8.4. Заполнить заготовку `route_select_screen` из T-061: `AppBar`, четыре карточки `CardButton` (название на языке интерфейса, тип, полоса `mood_color`, миниатюра `RoutePreview`, три цифры), состояние «выбрано» у одной, предвыбор — `profile.last_route_id`; деталь выбранной — крупный профиль, слайдер крутизны 0–100 % с шагом 5 (значение из профиля, сохраняется), основная кнопка «Старт» → `start_requested(route_id, steepness)`. Выбор сохраняется в профиле. Адаптивность: одна колонка на портретном телефоне.
Файлы: `src/ui/tracks/route_select_screen.{tscn,gd}`, `assets/i18n/strings_tracks.csv`, `tests/unit/ui/test_route_select_screen.gd`.
Закрывает: REQ-FRD-02 п.1, 2 (передача id), 3; REQ-FRD-03 п.4; REQ-FRD-05 п.1 (UI); REQ-UIX-03 п.2, 3, 5 (трасса); REQ-D3D-08 п.1 (названия ru/en на экране).
Критерии авто: четыре карточки, ровно одна «выбрано»; первый запуск — `flat`, далее — последняя выбранная; «Старт» отдаёт выбранный id и крутизну; названия на ru и en. Визуально (T-059): профили четырёх трасс различимы, цифры с единицами, чек-лист `ui.md` п. 11. Ручные: REQ-FRD-02 п.4.

#### T-081 — Главный экран `[game]` — `done` (9f68583; приёмка 6e84ef1)
Волна 3. Зависит: T-061, T-076. Размер M.
Что сделать. По `ui.md` п. 8.2 и макетам: две карточки сценариев `ScenarioCard` с основной кнопкой — «Тренировка по плану» (→ PLAN) и «Свободная езда» (→ ROUTE_SELECT), каждая по площади ≥ 2 × любой другой кнопки; фишки статуса станка и запомненных датчиков (состояние DEV-07.1, заряд DEV-07.2, обновление ≤ 1 с, нажатие → DEVICES); переходы в историю и настройки; имя профиля и смена профиля при ≥ 2 профилях; кнопка режима разработчика только в отладочной сборке. Если для статуса устройств экрану нужен `ConnectionManager`, его передаёт `main.gd` (владелец в волне 3 — эта задача, правка только проводки).
Файлы: `src/ui/home/home.{tscn,gd}`, `src/app/main.gd` (только проводка), `assets/i18n/strings_menu.csv`, `tests/unit/ui/test_home_screen.gd`.
Закрывает: REQ-UIX-02 п.1–4, п.5 (снимки); REQ-FRD-01 п.1 (вход с главного экрана).
Критерии авто: два основных действия ведут на PLAN и ROUTE_SELECT; соотношение площадей; смена состояния `FakeTrainer` видна ≤ 1 с; история и настройки — одно нажатие; dev-кнопка скрыта вне отладки. Визуально: снимки на телефоне, планшете и компьютере — сценарии самые заметные, история и настройки без прокрутки.

#### T-082 — Выбор тренировки карточками `[game]` — `done` (b443372; приёмка 6e84ef1; `WorkoutChart` удалён в T-095)
Волна 3. Зависит: T-071, T-076. Размер M.
Что сделать. По `ui.md` п. 8.3: `AppBar`, план на сегодня и библиотека — карточки `CardButton` с названием, `PlanPreview` (сегменты HUD-10.1 по зонам с FTP профиля), длительностью (`ч:мм` или `мм` мин) и максимальной целью (Вт); одна карточка «выбрано»; запуск одним действием; импорт файла и пустые состояния. `workout_chart.gd` заменить на `PlanPreview` и удалить.
По итогам волны 1 (T-061). Кнопка «назад» экрана → `app_state.go_back()` (через `AppBar`), а не `navigate(HOME)`. Цели нажатия — хелпером `touch_target.gd` из T-076.
Файлы: `src/ui/plan/plan_screen.{tscn,gd}`, удаление `src/ui/plan/workout_chart.gd` (+ `.uid`), `assets/i18n/strings_menu_lists.csv`, `tests/unit/ui/test_plan_cards.gd`.
Закрывает: REQ-UIX-03 п.1, 3, 4, 5 (тренировка); регрессия REQ-INT-04, INT-05, IMP-03 п.2.
Критерии авто: цифры карточки по плану из фикстуры; сегменты превью = модель HUD-10.1; ровно одна «выбрано»; запуск выбранной; приёмка T-040 зелёная (тесты, завязанные на `workout_chart.gd`, — согласовать с tester). Визуально: три тренировки разной структуры различимы.

#### T-083 — Окружения «равнина» и «холмы» `[visual]` — `review` (cf6fec6)
Итог. Визуально принято game-designer по снимкам; `[авто]` — тесты исполнителя зелёные. Приёмка tester (D3D-08 п.6, 8, 12 на `flat`, `hills`; бюджет D3D-05 п.4) — в цикле T-088/T-089, затем `done`.
Волна 3. Зависит: T-070. Размер M.
Что сделать. По `tracks.md` п. 4.1, 4.2, 6. Свои `EnvironmentSet` для `flat` и `hills` (новые поля `environment_set.gd` — с запасом под горы и приморье), поля-лоскуты, пашня, тополя, ветряки, деревни с крышами; ориентиры из списков трасс (не реже 1.5 км, в кадре одновременно не больше 2–3); `hills_height_m`: равнина < холмы. Новые меши — в `src/scene3d/props/` и `MeshKit`, контур и тун-палитра по арт-библии; источники ассетов — в отчёт для `docs/game/assets.md` (документ ведёт game-designer).
Файлы: `src/scene3d/environment_set.gd`, `src/scene3d/tracks/env_flat.tres`, `src/scene3d/tracks/env_hills.tres`, `src/scene3d/props/**`, `src/scene3d/mesh_kit.gd`, `src/scene3d/route_world.gd`, `src/scene3d/scenery_builder.gd`, `tests/integration/test_route_environments.gd`.
Закрывает: REQ-D3D-08 п.6 (`flat`, `hills`), п.8 (`flat`, `hills`).
Критерии авто: у трасс свои наборы окружения; ориентиры не реже 1.5 км; бюджет T-066 на обеих. Визуально: снимки `tracks.md` п. 8.8 — чек-лист ≥ 10/12 без блокирующих, трассы различимы без подписи.

#### T-084 — Экран свободной езды и запуск `[game]` — `done` (68a89e6; приёмка 6e84ef1; пересвет 3D — T-096, Esc → подтверждение — T-097)
Волна 4. Зависит: T-070, T-074, T-077, T-079, T-080. Размер M.
Что сделать. Заполнить заготовку `free_ride_screen` из T-061: `RideScene.set_route(id)`, `FreeRideSession`, `HudLayout` + `HudMetricPanel` (режим «свободная езда»), `ReliefPanel`, `HudChart` (история усилия), `PauseOverlay`, `HudToolbar` (режим «свободная езда»: SIM ↔ сопротивление, крутизна ±10 %, завершить), сообщение «станок не поддерживает SIM» по `simulation_unavailable`, «назад» → запрос завершения с подтверждением. `main.gd`: `start_free_ride(route_id, steepness)` — то же правило старта, что у плана (нужен подключённый станок, в dev-режиме — `FakeTrainer`; FRD-01 п.4), после завершения — сохранение, автопостановка в очередь Strava, переход на сводку и в историю. `ui_screenshot.gd`: сценарии свободной езды по id трассы и дистанции (ровно, подъём и спуск на `mountains`).
По итогам волны 1 (T-061; решение передано requirements, REQ-UIX-04 п.1). Android «назад» на главном экране (стек пуст, `go_back()` вернул `false`) закрывает приложение (`get_tree().quit()`); поведение Esc на главном — по редакции UIX-04 п.1. Реализация в `main.gd` (владелец в волне 4 — эта задача), тест — на обработчике `NOTIFICATION_WM_GO_BACK_REQUEST` с подменой выхода. Если редакция UIX-04 п.1 к началу задачи не внесена — делать по этому решению, tester принимает после внесения.
Файлы: `src/ui/free_ride/free_ride_screen.{tscn,gd}`, `src/app/main.gd`, `scripts/dev/ui_screenshot.gd`, `assets/i18n/strings_free_ride.csv`, `tests/integration/test_free_ride_flow.gd`.
Закрывает: REQ-FRD-01 п.1 (сквозной путь), п.4; REQ-FRD-06 п.5, п.6; REQ-FRD-05 п.6 (на экране); REQ-FRD-07 п.2 (подтверждение), п.6, п.7 (сквозная проверка); REQ-UIX-04 п.2 (свободная езда), п.1 (Android «назад» на главном — по новой редакции); REQ-FRD-04 п.6 (сообщение пользователю).
Критерии авто: HOME → ROUTE_SELECT → «Старт» → FREE_RIDE с выбранной трассой (профиль сессии и окружение совпадают); без станка — как у плана; `set_simulation_supported(false)` → фиксированное сопротивление и сообщение; «Завершить» с подтверждением → заезд в истории и в очереди Strava с названием «Свободная езда — <трасса>»; раскладка HUD-13.1, 13.4–13.6. Визуально (T-059): чек-лист `hud.md` п. 14 на «ровно / подъём / спуск», FRD-06 п.6. Ручные: REQ-FRD-01 п.5, FRD-04 п.10, FRD-05 п.7.

#### T-085 — История и карточка заезда `[game]` — `review` (da90ba3; приёмка 6e84ef1 с дефектом → T-097)
Итог приёмки (6e84ef1). LOC-03 п.2: в истории показана сглаженная мощность — экстремумы исходной серии (`RideSeries`, В-18) должны быть среди точек графика. Исправляет T-097; `done` — по повторной приёмке.
Волна 4. Зависит: T-064, T-076. Размер M.
Что сделать. По `ui.md` п. 8.5: `AppBar`, список заездов строками `ListRow` (дата, название, длительность, средняя мощность, статус Strava; у свободной езды — трасса и дистанция), пустое состояние; карточка заезда — `StatView`, графики в языке HUD (`HudChart` в режиме истории или `ride_chart.gd` на тех же токенах), у свободной езды — профиль высоты по дистанции (круги подряд, граница — пунктир, `tracks.md` п. 7.3), без серии цели. Снять `theme_override_*`.
По итогам волны 1 (T-061, T-064). «Назад» экранов истории и карточки → `app_state.go_back()` (через `AppBar`), а не `navigate(HOME)`. Данные из T-064: `RideSummary.ride_type`, `route_id`, `ascent_m`, `avg_target_w` (значение `NO_DATA` → «—»), профиль высоты — `RideSeries.altitude_by_distance()`. Цели нажатия — хелпером `touch_target.gd` (T-076).
Файлы: `src/ui/history/**`, `assets/i18n/strings_menu_lists.csv`, `tests/unit/ui/test_history_screens_r2.gd`.
Закрывает: REQ-UIX-04 п.3, 4, 5 (история); REQ-FRD-07 п.6 (в истории наравне с тренировками); регрессия REQ-LOC-02, LOC-03, LOC-06.
Критерии авто: заезд свободной езды в списке с дистанцией, карточка без ошибок, поля цели «—»; пустая история — поясняющий текст; приёмка T-045 зелёная. Визуально: 0 и 20 заездов, чек-лист `ui.md` п. 11.

#### T-086 — Настройки, устройства, выбор профиля `[game]` — `done` (58c7fed; приёмка 6e84ef1)
Волна 4. Зависит: T-076. Размер M.
Что сделать. По `ui.md` п. 8.1, 8.6, 8.7: настройки — группы с подзаголовками (состав по `ui.md`; крутизна SIM по умолчанию — если game-designer поместил её в настройки, то пишется в `sim_steepness_pct` из T-061), «О программе» с лицензиями Inter (OFL 1.1) и Lucide (ISC); устройства — строки `ListRow`, состояния и заряд, пустое состояние «устройства не найдены», баннер «Bluetooth недоступен» (UX-3); выбор профиля — карточки. `AppBar` с «назад», снять `theme_override_*`.
По итогам волны 1 (T-061). «Назад» экранов настроек, устройств и выбора профиля → `app_state.go_back()` (через `AppBar`), а не `navigate(HOME)`. Цели нажатия — хелпером `touch_target.gd` (T-076).
Файлы: `src/ui/settings/**`, `src/ui/devices/**`, `src/ui/profile_select/**`, `assets/i18n/strings_menu.csv`, `tests/unit/ui/test_settings_devices_r2.gd`.
Закрывает: REQ-UIX-04 п.3, 4, 5 (настройки, устройства); регрессия REQ-PRF-05, DEV-01 п.7, NFR-08 п.3, T-057.
Критерии авто: группы с подзаголовками; строки устройств — вариация строки списка; 0 устройств — поясняющий текст; лицензии в «О программе»; приёмки T-019/T-057 зелёные. Визуально: настройки, устройства (0 и 3), выбор профиля.

#### T-087 — Окружение «горы» `[visual]` — `review` (5576c36)
Итог. Визуально принято game-designer по снимкам; `[авто]` — тесты исполнителя зелёные. Приёмка tester (D3D-08 п.6, 8, 10, 12 на `mountains`; D3D-05 п.4) — в цикле T-088/T-089, затем `done`.
Волна 4. Зависит: T-083. Размер M.
Что сделать. По `tracks.md` п. 4.3: `EnvironmentSet` гор — камень, альпийский луг, снег на вершинах, высокие склоны и горизонт выше, чем на равнине, серпантин на подъёме, таблички с высотой, ориентиры; петля (подъём по одному склону, спуск по другому).
Файлы: `src/scene3d/tracks/env_mountains.tres`, `src/scene3d/props/**`, `src/scene3d/environment_set.gd`, `src/scene3d/mesh_kit.gd`, `src/scene3d/route_world.gd`, `tests/integration/test_route_environments.gd` (дополнение).
Закрывает: REQ-D3D-08 п.6 (`mountains`: горизонт выше равнины, `hills_height_m` горы > холмы), п.8 (`mountains`).
Критерии авто: свой набор окружения; бюджет; ориентиры. Визуально: снимки 1000 / 6000 / 8600 / 10400 / 14500 м — чек-лист ≥ 10/12, подъём и спуск читаются.

#### T-088 — Приморье, часть 1: вода, берег, маяк `[visual]` — `in-progress`
Волна 5. Зависит: T-087. Размер M.
Что сделать. По `tracks.md` п. 4.4: шейдер воды в тун-стиле (глубокая, мелкая, пена у берега, без отражений в реальном времени), море и река как поверхности на `water_level_m`, рельеф берега и пляж, дюнная трава, зонтичные сосны, маяк, ориентиры. Мост — в T-090: пока на его участке дорога идёт по насыпи.
Файлы: `src/scene3d/shaders/water.gdshader`, `src/scene3d/materials/water.tres`, `src/scene3d/tracks/env_seaside.tres`, `src/scene3d/props/**`, `src/scene3d/environment_set.gd`, `src/scene3d/terrain_field.gd`, `tests/integration/test_route_environments.gd` (дополнение).
Закрывает: REQ-D3D-08 п.6 (вода на приморье), п.8 (`seaside`, кадры 1800 и 8600 м).
Критерии авто: в составе мира приморья есть водная поверхность; бюджет. Визуально: чек-лист ≥ 10/12, вода в кадре.

#### T-089 — Финальная проверка UI: адаптивность, тема, переводы `[game]` — `todo`
Волна 5. Зависит: T-078, T-080, T-081, T-082, T-084, T-085, T-086. Размер M (если дефектов больше, чем на заход, — менеджер режет по экранам).
Что сделать. Матричные тесты по всем экранам × разрешения UIX (390×844, 844×390, 1024×1366, 1366×1024, 1280×720, 1920×1080) × ru/en: цели нажатия ≥ 44 lp, ничего не выходит за окно, нет пересечений интерактивных элементов, нет обрезанного текста (кроме пользовательских данных с «…»), одна колонка на портретном телефоне, без горизонтальной прокрутки; статическая проверка `.tscn`/`.gd` в `src/ui/` на `theme_override_colors`/`fonts` и `add_theme_*_override` (исключения — данные: зона, статус, графики); инвентаризация переводов (ключи из всех `strings*.csv` используются, ru и en непустые, нет кириллицы в литералах); полный набор снимков `ui_screenshot.sh` на трёх разрешениях и двух языках. Исправления — точечно в `src/ui/**` (единственная UI-задача волны).
Хвосты T-060 (не сделаны в волне 1): letter-spacing оверлайна +6 % (`ui.md` п. 9; в `FontVariation` Godot трекинг задаётся через `spacing_glyph`, проверить на Inter) и шрифт `SpinBox` (поле ввода не наследует вариацию темы). Если game-designer в T-091 изменит состояния кнопок (hover/pressed `OptionButton`, `DangerButton`, `HudButton`, padding `GhostButton`) — правка `src/ui/theme/**` тоже здесь, если раньше её не взяла экранная задача.
По итогам волн 3–4 (стартует после T-097; хвосты T-060 по `Overline` и `SpinBox` закрыты T-093). Дополнительно:
- тема: у `TextEdit` (описание Strava в карточке заезда) нет стиля темы; разрывы `GridContainer`/`HFlowContainer` — вариациями separation; вариация `Caption` с `tnum`; `intervals_key_dialog.tscn` — `theme_override_colors` на `ErrorLabel` заменить вариацией `ErrorLabel`; `AcceptDialog` со скрытым OK оставляет пустое место снизу;
- вариации T-095 на узлах вне панели цифр (`OverlineAccent`, `LogoLabel`, `SheetPanel`; на панели цифр — T-097);
- `HudToolbar`: кнопки 56 lp + подпись 11 (сейчас ~84 lp), чтобы колонка помещалась на 16:9; `NextChip` без `add_theme_*_override`; API приглушения `HudMetricPanel` вместо доступа к `%Content`;
- переводы: неиспользуемые ключи `ui.history.*` и `ui.plan.item.load` в `strings.csv` — удалить; тексты `SettingsSections.TEXTS` — в `strings*.csv`, проверку ключей настроек расширить на все `strings*.csv` (приёмочный тест `test_settings_acceptance` правит tester);
- карточка заезда: легенда графика обрезана сверху;
- снимки: сценарии истории на 0 и 20 заездов в `ui_screenshot.gd`;
- матрица целей нажатия и обрезки текста — по всем экранам (основной пункт задачи); текстовые аксессоры истории `rows()`/`summary_text()` (только для тестов) — оставить или снять по решению tester;
- принять ограничение движка: разрядка `Overline` +8.3 % вместо +6 % (game-designer подтверждает в `ui.md`).
Файлы: `tests/unit/ui/test_ui_matrix.gd`, `tests/unit/ui/test_ui_static_theme.gd`, `tests/unit/app/test_i18n.gd`, точечные правки `src/ui/**`, `assets/i18n/**`.
Закрывает: REQ-UIX-01 п.2, п.5; REQ-UIX-05 п.1–5; REQ-NFR-08 п.1, 2 (на итоговом наборе экранов).
Критерии авто: все `[авто]` перечисленных пунктов. Визуально: чек-лист `ui.md` п. 11 и `hud.md` п. 14 по полному набору снимков. Ручные: REQ-UIX-05 п.6 (iPhone/iPad), NFR-08 п.5.

#### T-090 — Приморье, часть 2: мост над рекой `[visual]` — `todo`
Волна 6. Зависит: T-088. Размер M.
Что сделать. Мост на диапазоне `bridges` (5820–6330 м): полотно на h(s) ≥ `water_level_m` + 10 м, опоры, перила (палитра `tracks.md` п. 6), река под мостом, выемка рельефа под руслом; дорога, кромка и отбойник на мосту без щелей и травы; камера и гонщик на мосту по D3D-07.5.
Файлы: `src/scene3d/props/bridge_builder.gd`, `src/scene3d/road_builder.gd`, `src/scene3d/roadside_builder.gd`, `src/scene3d/terrain_field.gd`, `src/scene3d/tracks/env_seaside.tres`, `tests/integration/test_seaside_bridge.gd`.
Закрывает: REQ-D3D-08 п.3 (мост в сцене на участке из данных), п.6 (мост и вода под ним), п.8 (`seaside`, кадры 5600 и 6100 м).
Критерии авто: на диапазоне моста есть узел моста, полотно выше воды ≥ 10 м, под мостом водная поверхность, рельеф не выше полотна; бюджет. Визуально: мост и вода в кадре, четыре трассы различимы без подписи (сводная проверка D3D-08 п.8). Ручные: REQ-D3D-08 п.9.

#### T-091 — Дизайн по итогам волны 1: ориентиры, PCHIP, реестр ассетов, состояния кнопок `[design]` — `done` (44f5ea9)
Волна 2 (можно сразу). Зависит: T-060, T-062 (слиты, в приёмке). Исполнитель — game-designer, без кода. Размер S.
Что сделать. 1) `docs/game/tracks.md`: ориентиры каждой трассы с шагом не больше 1.5 км по кругу, включая стык круга (сейчас у `hills`, `mountains`, `seaside` разрывы 1.6–2.5 км — D3D-08 п.12 не выполняется), таблица «дистанция, тип, сторона дороги» в форме, которую T-092 перенесёт в `RouteCatalog.landmarks` без толкования. 2) `tracks.md`: уточнить, что PCHIP — вариант Fritsch–Butland (наклоны во внутренних точках — взвешенное гармоническое среднее, как `scipy.interpolate.PchipInterpolator`), а не исходный Fritsch–Carlson. 3) `docs/game/assets.md`: Inter и Lucide — статус «в проекте» (пути `assets/fonts/inter/`, `assets/icons/lucide/`, лицензии OFL 1.1 / ISC), иконки переключателя и слайдера генерируются темой (`app_theme_builder.gd`), файлов нет. 4) Оценить по снимкам T-059 состояния, которые T-060 выбрал сам: hover/pressed у `OptionButton`, `DangerButton`, `HudButton`, padding `GhostButton`; вердикт «принято» или правка значений в `ui.md`/`hud.md` (код правит T-089 или экранная задача).
Файлы: `docs/game/tracks.md`, `docs/game/assets.md`, `docs/game/ui.md` и `docs/game/hud.md` (только п. 4 при несогласии).
Закрывает: данные дизайна для REQ-D3D-08 п.12 (реализация в данных — T-092); вердикт game-designer по визуальной части REQ-UIX-01 п.3 для T-060.
Критерии: в таблице ориентиров `tracks.md` максимальный разрыв по кругу (с учётом стыка) ≤ 1.5 км на всех четырёх трассах — tester считает по таблице; `assets.md` без статуса «план» для Inter и Lucide; вердикт по четырём состояниям записан. Предложение критериев для requirements, если п.12 нужно уточнить, — в отчёт.

#### T-092 — Ориентиры трасс в `RouteCatalog` `[game]` — `done` (94f8f2c; приёмка d62b281)
Волна 2–3. Зависит: T-091. Исполнитель — developer. Размер S.
Что сделать. Перенести таблицу ориентиров из `tracks.md` (после T-091) в `RouteCatalog.landmarks` всех четырёх трасс; тест: максимальный разрыв между соседними ориентирами по кругу (включая стык) ≤ 1500 м. Профили и остальные данные каталога не менять.
Файлы: `src/domain/route_catalog.gd`, `tests/unit/domain/test_route_catalog.gd`.
Закрывает: REQ-D3D-08 п.12 (данные). Расстановка ориентиров в мире — T-083, T-087, T-088 по этим данным.
Критерии авто: разрыв ≤ 1500 м на `flat`, `hills`, `mountains`, `seaside`; приёмка T-062 (характеристики трасс) не регрессирует. Ручных нет.

#### T-093 — Доработка темы перед волной 3 `[game]` — `done` (64d24eb; приёмка 6e84ef1)
Волна 2–3 (вне исходной нарезки). Зависит: T-060, T-091. Размер S.
Что сделано. Состояния `danger_hover`/`danger_pressed` и нажатие `GhostButton` (вердикт T-091); вариации `NumLabel`, `Stack0`, `Row0/8/12/16/24`, `HudPauseCard`, `HudChipLabel`, `HudPauseTitle`; шрифт цифр `SpinBox`; разрядка `Overline` (хвосты T-060); иконки баннера info / triangle-alert / circle-alert; помощник `UiIcons` (`src/ui/theme/ui_icons.gd`).
Закрывает: REQ-UIX-01 п.1, 3; REQ-UIX-05 (основа целей и отступов); REQ-HUD-14 (вариации HUD).

#### T-094 — `y_max` графика плана, сдвиг по журналу пропусков, размер кадра снимков `[game]` — `done` (ad349e9; приёмка d62b281)
Волна 3 (вне исходной нарезки). Зависит: T-065, T-059. Размер S.
Что сделано. `y_max` графика плана с нижней границей 1.1 × FTP (уточнение У-2); линии факта сдвигаются по журналу пропусков шагов; `ui_screenshot` проверяет размер кадра и держит окно поверх всех на macOS.
Закрывает: REQ-HUD-10 п.2, 5; REQ-HUD-11 п.1.

#### T-095 — `tnum` у меток HUD, вариации темы, нагрузка на карточке Intervals.icu `[game]` — `review` (c85e98c)
Волна 4 (вне исходной нарезки). Зависит: T-073, T-082, T-093. Размер S–M.
Что сделано. `tnum` у подписей HUD с цифрами (фишки зон, подписи, номер шага); вариации `HudHeroUnit`, `HudTargetUnit`, `HudCountdown`, `HudDelta`, `HudGradeValue`, `HudGradeUnit`, `HudModeLabel`, `HudStepLabel`, `OverlineAccent`, `OverlineSim`, `LogoLabel`, `LogoAccentLabel`, `SheetPanel`; нагрузка Intervals.icu в строке карточки плана; удалены `WorkoutChart` и скрытый `WorkoutList`.
Закрывает: REQ-HUD-14 п.2; REQ-INT-04 п.2; REQ-UIX-01 п.3; REQ-UIX-03 (карточка плана).
Итог. Отдельного отчёта tester нет; приёмка — вместе с T-097. Применение вариаций на узлах: панель цифр — T-097, остальные экраны — T-089.

#### T-096 — Пересвет 3D в `SubViewport` экранов заезда `[visual]` — `in-progress`
Волна 5. Зависит: T-084. Исполнитель — technical-artist. Размер S–M.
Почему. Оркестратор по снимкам T-084 (`ui_screenshot`) нашёл, что 3D-сцена в `SubViewport` экранов тренировки и свободной езды пересвечена; эталон — снимки `screenshot.sh` той же трассы и дистанции.
Что сделать. Найти причину (окружение и тонмаппинг сцены внутри `SubViewport`, `own_world_3d`, прозрачный фон, HDR/цветовое пространство вьюпорта) и привести кадр экрана заезда к кадру `screenshot.sh` на тех же трассе, дистанции и разрешении. Сцены экранов одновременно правит T-097: в `src/ui/{workout,free_ride}/*_screen.tscn` T-096 трогает только узел `SubViewport` (иначе — в отчёт).
Файлы: `src/scene3d/ride_scene.gd` и окружение сцены (по отчёту исполнителя), узел `SubViewport` в `src/ui/workout/workout_screen.tscn`, `src/ui/free_ride/free_ride_screen.tscn`; тест — в `tests/integration/`.
Закрывает: регрессия REQ-D3D-07 п.1–5 на экранах заезда; REQ-HUD-13 п.10 (3D под HUD).
Критерии авто: средняя яркость и гистограмма кадра 3D экрана заезда совпадают с кадром `screenshot.sh` на той же точке (допуск — исполнитель предлагает, game-designer подтверждает); размер изображения сцены = размер окна ±1 px (HUD-13 п.10 не регрессирует). Визуально: снимки «до/после» `ui_screenshot` и `screenshot.sh` рядом, вердикт game-designer.

#### T-097 — Дефекты приёмки UI и хвосты экранов заезда `[game]` — `in-progress`
Волна 5. Зависит: T-078, T-084, T-085, T-095. Исполнитель — developer. Размер M (если не помещается — режется по экранам: HUD тренировки, свободная езда, история).
Что сделать.
1. Дефекты приёмки 6e84ef1: HUD-13 п.5, 6, 9 на телефоне (s = 1.2) — центральная зона, пересечения и зазор список — панель, слот подсказки у низа над графиком (T-078); LOC-03 п.2 — график мощности в карточке заезда по серии `RideSeries` с экстремумами, а не по сглаженной мощности (T-085). Сейчас 4 красных теста полного прогона — это они.
2. Esc на экранах тренировки и свободной езды → подтверждение завершения (UIX-04 п.2 важнее `hud.md` 10.3), одинаково на обоих экранах.
3. Удаление узлов совместимости после перевода тестов: `LegacyControls` экрана тренировки (скрытые `%ErgButton`/`%SkipButton`/`%StopButton`/`%Intensity*`/`%Resistance*`/`%StopDialog`) и `workout_progress_bar.gd` (+ `.uid`); скрытые `%PowerChart`/`%HrChart` (`RideChart`) карточки заезда → `detail().effort_chart()`; скрытые `%ProfileList`/`%SelectButton`/`%DeleteButton` выбора профиля → `cards()`/`choose()`/`open_card_menu()`; переименованные в экран узлы `AppBar`/`Banner` (`%BackButton`, `%StoreWarningLabel`, `%ResetStoreButton`, `%NoticeLabel`) → `app_bar().back_button()` и т. п. Тесты, которые на них опираются, tester переводит до удаления (чужие тесты developer не правит).
4. `HudChart`: кэш подписей шкал (не пересоздавать текст каждый кадр).
5. Вариации T-095 на панели цифр (`HudHeroUnit`, `HudTargetUnit`, `HudCountdown`, `HudDelta`, `HudGrade*`, `HudModeLabel`, `HudStepLabel`).
6. Подвал панели рельефа на телефоне («до вершины / подъём через» не помещается).
7. Экран плана: кнопка «На эмуляторе» (запуск на `FakeTrainer` в отладочной сборке, как у свободной езды FRD-01 п.4).
8. `ui_screenshot.gd`: ожидание анимаций перед снимком (~0.5 с по времени, анимации 200–300 мс).
Файлы: `src/ui/workout/**` (удаление `workout_progress_bar.gd`), `src/ui/free_ride/**`, `src/ui/hud/{hud_layout,hud_metric_panel,hud_chart,relief_panel}.*`, `src/ui/history/**`, `src/ui/profile_select/**`, `src/ui/plan/plan_screen.*`, `scripts/dev/ui_screenshot.gd`, свои юнит-тесты.
Закрывает: REQ-HUD-13 п.5, 6, 9 (телефон) — для `done` T-078; REQ-LOC-03 п.2 — для `done` T-085; REQ-UIX-04 п.2 (Esc); REQ-HUD-14 п.2 (вариации на узлах); REQ-FRD-06 п.1 (подвал на телефоне); REQ-FRD-01 п.4 (эмулятор в отладке — на экране плана по тому же правилу).
Критерии авто: полный прогон GUT без красных; HUD-13 п.5, 6, 9 на 390×844 и 844×390 (s = 1.2); серия графика карточки содержит min/max исходной мощности (LOC-03 п.2); Esc на обоих экранах заезда открывает подтверждение, экран не меняется; в сценах нет `LegacyControls`, `WorkoutProgressBar`, `%PowerChart`, `%HrChart`, `%ProfileList`; «На эмуляторе» видна только в отладочной сборке. Визуально: снимки HUD тренировки и свободной езды на телефоне «до/после».

#### T-098 — Последняя выбранная тренировка в профиле `[game]` — `todo`
Волна 6. Зависит: T-097 (экран плана). Размер S.
Что сделать. Поле профиля `last_workout_id` (совместимо со старыми профилями, по образцу `last_route_id`), запись при выборе карточки на экране плана, предвыбор при следующем открытии и после перезапуска; если тренировки нет (удалена, план сменился) — предвыбор по прежнему правилу.
Файлы: `src/profiles/profile.gd`, `src/profiles/profile_repository.gd`, `src/ui/plan/plan_screen.gd`, юнит-тесты.
Закрывает: REQ-UIX-03 п.3 (состояние «выбрано») — прямого критерия «запоминать между запусками» нет, вопрос Н-17 к requirements.
Критерии авто: выбор → перезапуск (новый `ProfileRepository` на том же каталоге) → выбрана та же карточка; профиль без поля читается; несуществующий id не ломает экран.

#### T-099 — Свёртка повторов Intervals.icu «3x» `[integration]` — `todo`
Волна 6. Зависит: T-072. Размер S–M.
Что сделать. Сейчас `Workout.expand_repeat` разворачивает блок `3x …` при разборе Intervals.icu без следа, поэтому список интервалов не может свернуть его, как ZWO `IntervalsT` (HUD-13 п.8). Сохранить метаданные блока повторов в `Workout`/`WorkoutStep` в том же виде, что у ZWO, и проверить, что `IntervalListModel` сворачивает блок без правок логики (правка модели — только чтение метаданных).
Файлы: `src/domain/workout.gd`, `src/domain/workout_step.gd`, `src/integrations/workouts/intervals_icu_workout_parser.gd`, `src/ui/hud/interval_list_model.gd` (если нужно), тесты.
Закрывает: REQ-HUD-13 п.8 (для планов Intervals.icu); регрессия REQ-INT-03, REQ-NFR-09 п.3.
Критерии авто: план Intervals.icu «2 шага разминки + 4x (15 с, 45 с)» до начала блока — 3 строки, после — 2 + 8; сериализация `Workout.to_dict()/from_dict()` сохраняет метаданные; приёмка T-035 зелёная.

#### T-100 — Статический кэш `RouteWorld._tracks` `[visual]` — `todo`
Волна 6. Зависит: T-088, T-090 (`src/scene3d/` занят до их слияния). Размер S.
Что сделать. Одиночный прогон (`-gselect`) тестов сцены заканчивается сообщением «resources still in use at exit» из-за статического кэша `RouteWorld._tracks`. Кэш — с явной очисткой (например, при выходе/в `after_all`) или не статический.
Файлы: `src/scene3d/route_world.gd`, тест.
Закрывает: REQ-INF-01 п.2, 5 (одиночный прогон без предупреждений об утечках).
Критерии авто: `./scripts/test.sh -gselect=test_route_environments` без «resources still in use at exit»; время построения мира при смене трасс не выросло заметно (замер в отчёте).

#### T-101 — Нестабильные по времени тесты `[integration]` — `todo`
Волна 6. Зависит: —. Размер S.
Что сделать. `test_storage_acceptance::loc_07_c4_tick_budget_50ms` (бюджет тика 50 мс, LOC-07 п.4) и `test_strava_hardening::idle_connection_5s` периодически падают под нагрузкой. Перевести на подменяемые часы или устойчивый замер (медиана нескольких прогонов). Приёмочный тест — зона tester; developer правит `test_strava_hardening` и, если нужно, добавляет шов часов в `src/storage/` / `src/integrations/strava/`.
Файлы: `tests/**/test_storage_acceptance.gd` (tester), `tests/**/test_strava_hardening.gd`, при необходимости шов часов.
Закрывает: REQ-LOC-07 п.4; регрессия REQ-STR-04; REQ-INF-01 п.1 (стабильный прогон).
Критерии авто: 20 полных прогонов подряд без падений этих тестов.

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

### Ред. 2 (этап 7р2) — на устройстве и Tacx Neo
- REQ-FRD-04 п.10, FRD-05 п.7 — в подъём на Neo тяжелее, на спуске легче, смена ≤ 1–2 с; крутизна и переключение SIM ↔ сопротивление ощущаются. Сверить, что Neo отдаёт `0x2AD5` и бит SIM в `0x2ACC` (T-063).
- REQ-FRD-01 п.5, FRD-02 п.4 — запуск свободной езды с главного экрана касанием и кликом.
- REQ-FRD-07 п.8 — активность свободной езды в Strava: дистанция, профиль высоты и набор совпадают с приложением (±1 %).
- REQ-HUD-10 п.8, HUD-14 п.6, HUD-01 п.4 — график и цифры читаются с 1.5 м; 3D не мутное на iPad и Retina (T-073).
- REQ-D3D-08 п.9 — смена трасс, подъёмы и спуски без рывков высоты, 60 FPS (методика D3D-05).
- REQ-UIX-05 п.6 — iPhone и iPad: все действия пальцем без промахов; REQ-UIX-04 п.1 — системный «назад» на Android.

#### Ред. 2 — дополнение по итогам волн 2–4 (T-063, T-068, T-073, T-077, T-083..T-087, T-059/T-094)
- SIM на Tacx Neo (FRD-04 п.10, FRD-05 п.7): трасса `mountains` («Перевал»), крутизна 50 % — в подъём тяжелее, на спуске легче, смена ощущается за 1–2 с; то же при 100 %; переключение SIM ↔ сопротивление на ходу.
- Чтение у Neo `0x2ACC` (бит 13 «Indoor Bike Simulation Parameters Supported») и `0x2AD5` (Supported Inclination Range) — значения в логе совпадают с ожидаемыми (FRD-04 п.10).
- Strava, свободная езда: дистанция, профиль высоты и набор активности совпадают с приложением ±1 % (FRD-07 п.8).
- Устройство: смена трасс, подъёмы и спуски без рывков, 60 FPS (D3D-08 п.9, D3D-05); куски растительности и ориентиры не «выпрыгивают» на границе `visibility_range`.
- HUD с 1.5 м (HUD-01 п.5, HUD-14 п.6); 3D не мыльное на iPad и Retina (HUD-13 п.10); индикаторы ●/▲/▼ отклонения и «—» пульса при снятии нагрудного датчика.
- `ui_screenshot.sh` на Retina-маке: размеры кадров точные (проверка размера кадра T-094).
- Android: системный «назад» на главном не перехватывается — приложение сворачивается/закрывается системой (UIX-04 п.1, T-084).
- REQ-WRK-04 п.4 — уровень сопротивления ощущается при педалировании, в том числе в свободной езде в режиме «СОПР.».
- REQ-WRK-05 п.6 — на паузе (тренировка и свободная езда) нагрузка Neo не меняется, после возобновления — по цели интервала / по уклону.
- REQ-FRD-01 п.5 — реальный запуск свободной езды на Tacx Neo с главного экрана («Поехать» и «Сменить трассу» → «Поехать»).

## 5. Блокеры и вопросы к requirements

Блокеры среды (не требуют решения, фиксируются):
- Б-1. Задачи T-021, T-022 `[native-ble]` после написания кода переходят в `blocked: нужен macOS`; все критерии DEV-01 п.5, 6 и DEV-02 п.6, 7 — у владельца.
- Б-2. REQ-DEV-08 (этап 2) зависит от `SampleRecorder` (REQ-WRK-08, этап 3), поэтому T-024 выполняется после T-023; этап 2 формально закрывается только вместе с T-024.
- Б-3. Фикстуры Intervals.icu (открытое решение 19) — до получения реальных ответов с аккаунта владельца тесты INT идут на синтетических данных по публичной документации API; при получении реальных фикстур задачи T-033..T-035 возвращаются в `review`.

Открытые вопросы агенту requirements (Н-1..Н-6, Н-8, Н-9 решены — см. «Решено»):
- Н-17 (от оркестратора, хвост волн 3–4; T-098). Запоминать ли выбранную тренировку между запусками (поле профиля `last_workout_id`, по образцу FRD-02 п.3 для трассы)? Если да — нужен `[авто]`-критерий (например, в UIX-03 п.3 или INT-04): «после перезапуска выбрана последняя выбранная тренировка, если она есть в списке; иначе — правило INT-04 п.1».
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
| INF-01, INF-02 | T-001; ред. 2 — T-100 (INF-01 п.2, 5 — одиночный прогон без утечек), T-101 (INF-01 п.1 — стабильность) |
| INF-03 | T-014 |
| INF-04 | T-014 (п.1 мягко, п.3), T-056 (п.1, 2 строго) |
| PRF-01 | T-009, T-011 |
| PRF-02 | T-008, T-009 |
| PRF-03 | T-010, T-046, T-057 (п.2 — UI отвязки Intervals.icu) |
| PRF-04 | T-011, T-041 |
| PRF-05 | T-012 |
| INT-01 | T-033 (ключ), T-053 (OAuth-документ) |
| INT-02 | T-034 |
| INT-03 | T-035; регрессия — T-099 (метаданные повторов) |
| INT-04 | T-040; ред. 2 — T-082 (регрессия), T-095 (п.2 — нагрузка на карточке) |
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
| HUD-07 | T-005 (`Workout.segments` — фикс D-1), T-030; ред. 2 — полоса заменена графиком HUD-10 в T-078 |
| HUD-01 (новая редакция: герой — факт) | T-031 (MVP), T-073 (ред. 2) |
| HUD-10 | T-065 (п.1–5), T-071 (п.6), T-078 (п.7), T-094 (п.2, 5 — `y_max` ≥ 1.1 × FTP, сдвиг после пропуска); п.8 — ручная |
| HUD-11 | T-065 (п.1–5), T-071 (п.6), T-078 (п.7), T-094 (п.1) |
| HUD-12 | T-059 (синтетический пульс для приёмки), T-065 (п.1, 2, 5–7), T-071 (п.3, 4), T-078 (п.8) |
| HUD-13 | T-073 (п.1, 5, 6, 10), T-072 (п.2, 3, 8 — компонент), T-078 (п.2–4, 7, 9), T-084 (п.1, 4–6 — свободная езда), T-097 (п.5, 6, 9 — телефон, дефекты T-078), T-096 (п.10 — 3D в `SubViewport`), T-099 (п.8 — повторы Intervals.icu) |
| HUD-14 | T-060 (п.1, 2), T-073 (п.3–5), T-093 (вариации HUD), T-095 (п.2 — `tnum` у меток), T-097 (п.2 — вариации на панели цифр); п.6 — ручная |
| HUD-06 (п.2 — фишка «ДАЛЕЕ»), WRK-05 (UI паузы) | T-074, T-078 |
| D3D-01, D3D-04, D3D-05 | T-052; ред. 2 — T-066 (D3D-05 п.2, 4 на длинных трассах) |
| D3D-02 | T-050; регрессия — T-067 |
| D3D-03, D3D-06 | T-051; ред. 2 — T-070 (D3D-03 п.1, 2 на новых трассах) |
| D3D-07 | T-058; регрессия — T-066, T-070, T-083, T-087, T-096 (экраны заезда) |
| D3D-08 | T-062 (п.1–3), T-066 (п.6 — бюджет), T-070 (п.2, 4, 5, 7), T-080 (п.1 — названия), T-083 (п.6, 8, 12 — `flat`, `hills`), T-087 (п.6, 8, 10, 12 — `mountains`), T-088 (п.6, 8 — вода), T-090 (п.3, 6, 8 — мост), T-091 (п.12 — дизайн ориентиров), T-092 (п.12 — данные); п.9 — ручная |
| FRD-01 | T-061 (навигация), T-068 (п.2), T-077 (п.1–3), T-081 (п.1 — вход), T-084 (п.1, 4), T-097 (п.4 — «На эмуляторе» на экране плана по тому же правилу); п.5 — ручная |
| FRD-02 | T-061 (п.3 — хранение), T-080 (п.1–3); п.4 — ручная |
| FRD-03 | T-062 (функции характеристик), T-075 (п.1–3), T-080 (п.4) |
| FRD-04 | T-063 (п.1, 3 — чтение, 6 — определение), T-067 (п.2 — позиция, 7, 8), T-068 (п.2–6), T-077 (п.5, 9), T-084 (п.6 — сообщение); п.10 — ручная |
| FRD-05 | T-061 (п.1 — хранение), T-068 (п.1–4), T-074 (п.4, 6 — органы управления), T-077 (п.5, 6 — события), T-079 (п.6 — HUD), T-080 (п.1 — UI); п.7 — ручная |
| FRD-06 | T-065 (п.4 — модель), T-079 (п.1–4), T-084 (п.5–7), T-097 (п.1 — подвал панели рельефа на телефоне) |
| FRD-07 | T-064 (п.3, 4, 6, 7), T-067 (п.1 — модель), T-069 (п.5), T-077 (п.1–4), T-084 (п.2, 6, 7 — сквозная), T-085 (п.6 — UI); п.8 — ручная |
| UIX-01 | T-060 (п.1, 3, 4), T-076 (п.3 — компоненты), T-086 (п.2), T-089 (п.2, 5; хвосты волн 3–4), T-091 (п.3 — вердикт по состояниям кнопок), T-093 (п.1, 3), T-095 (п.3) |
| UIX-02 | T-061 (п.3 — навигация), T-081 (п.1–5) |
| UIX-03 | T-071 (п.4 — план), T-075 (п.2, 4 — трасса), T-080 (п.2, 3, 5 — трасса), T-082 (п.1, 3, 4, 5 — тренировка), T-095 (карточка плана), T-098 (п.3 — запоминание выбора, после Н-17) |
| UIX-04 | T-061 (п.1, 2 — навигация), T-076 (п.1 — AppBar), T-084 (п.2 — свободная езда; п.1 — Android «назад» на главном), T-082/T-085/T-086 (п.1 — «назад» через `go_back()`), T-085 (п.3–5 — история), T-086 (п.3–5 — настройки, устройства), T-097 (п.2 — Esc → подтверждение на обоих экранах заезда) |
| UIX-05 | T-076 (п.1 — хелпер целей), T-080, T-082, T-086 (п.1, 4), T-093 (основа), T-089 (п.1–5 — матрица); п.6 — ручная |
| LOC-01 | T-041 |
| LOC-02 | T-045 |
| LOC-03 | T-043 (`RideSeries`); ред. 2 — T-085 (регрессия UI), T-097 (п.2 — дефект: сглаженная мощность в истории) |
| LOC-04 | T-041 (`RideSummary`) |
| LOC-05 | T-044, T-045 |
| LOC-06 | T-045, T-048 |
| LOC-07 | T-042; T-101 (п.4 — стабильность теста) |
| NFR-01 | T-025 |
| NFR-02 | T-006, T-013, T-023 |
| NFR-03 | T-032, T-036, T-048 |
| NFR-04 | T-027 |
| NFR-05 | T-010 (п.1, 2 — контейнер; `EncryptedFileSecureStore` временная), T-046, T-053 (п.3 — платформенные реализации, вне контейнера) |
| NFR-06 | T-002, T-014, T-015, T-021, T-055 |
| NFR-07 | T-053, T-055 |
| NFR-08 | T-012 (заделка), T-057 (п.3, 4), T-054 (п.1, 2 — финальная инвентаризация); ред. 2 — T-060 (п.2 — файлы по областям), 2a201e8 (п.1 — проверка всех `strings*.csv`), T-089 (п.1, 2 — итоговый набор, неиспользуемые ключи `strings.csv`, тексты `SettingsSections`) |
| NFR-09 | T-005, T-006, T-014 (п.4), T-056 (п.2), T-035, T-037, T-038, T-044 |
