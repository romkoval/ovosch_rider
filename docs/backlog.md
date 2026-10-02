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

- Один коммит на задачу с REQ-ID в сообщении (REQ-INF-03). Тесты — в том же коммите; тесты пишет tester, developer их не правит.
- Если при реализации выяснилось, что задачу нельзя сделать за один заход, — developer не расширяет её, а пишет в отчёт; менеджер режет.
- Допуски с пометкой «(допуск предложен, подтвердить)» действуют как есть, пока владелец не заменил их (см. «Открытые решения» в requirements.md).

## 2. Таблица задач

Порядок строк — порядок выполнения. Этап 1 первым; в нём первыми интерфейс `TrainerDevice` и `FakeTrainer` (главный риск — связь со станком и ERG), затем модель тренировки и исполнитель интервалов, затем профили.

| ID | Зона | Этап | Задача | REQ-ID | Зависит от | Статус |
| --- | --- | --- | --- | --- | --- | --- |
| T-001 | `[game]` | 1 | Инфраструктура тестов и CI (GUT headless, workflow) | REQ-INF-01, REQ-INF-02 | — | `done` (подтверждено CI run #3) |
| T-002 | `[game]` | 1 | Интерфейс `TrainerDevice`, телеметрия, часы (`Clock`), фабрика устройств | REQ-DEV-09 (п.1), REQ-NFR-06 (п.3) | T-001 | `todo` |
| T-003 | `[game]` | 1 | `FakeTrainer`: ядро, ERG-сходимость, сценарии «постоянная», «рывки», «нулевой каденс» | REQ-DEV-09 (п.1, 2, 3 частично, 4) | T-002 | `todo` |
| T-004 | `[game]` | 1 | `FakeTrainer`: сценарии сбоев (пропуск пакетов, обрыв/восстановление, ошибка Control Point) и симуляторы пульса/каденса | REQ-DEV-09 (п.3, 5) | T-003 | `todo` |
| T-005 | `[game]` | 1 | Доменная модель тренировки: `Workout`, `Step`, `Target`, `Cue`, метаданные | REQ-WRK-01 (входная модель), REQ-NFR-09 (п.1 — модель) | T-001 | `todo` |
| T-006 | `[game]` | 1 | Исполнитель интервалов `IntervalExecutor` (тики 1 Гц, события переходов, завершение) | REQ-WRK-01 (п.1–4), REQ-NFR-02 (п.1 — исполнитель), REQ-NFR-09 (п.1, 4) | T-005 | `todo` |
| T-007 | `[game]` | 1 | `WorkoutSession`: связка исполнителя и `TrainerDevice`, прогон плана на `FakeTrainer` | REQ-WRK-01 (п.5), REQ-DEV-09 (п.6) | T-003, T-006 | `todo` |
| T-008 | `[game]` | 1 | Зоны мощности (7, Coggan) и пульса (5), функция определения зоны | REQ-PRF-02 (п.2, 3, 5) | T-001 | `todo` |
| T-009 | `[game]` | 1 | Модель профиля, валидация, `ProfileRepository` (JSON в `user://`) | REQ-PRF-01 (п.1, 2, 5, 6), REQ-PRF-02 (п.1, 4) | T-008 | `todo` |
| T-010 | `[game]` | 1 | `SecureStore`: интерфейс, in-memory реализация, ключи с идентификатором профиля | REQ-NFR-05 (п.1, 2), REQ-PRF-03 (п.1, 2, 3) | T-009 | `todo` |
| T-011 | `[game]` | 1 | Реестр запомненных устройств: датчики в профиле, общий станок; каскадное удаление профиля | REQ-PRF-04 (п.2, 3, 4), REQ-PRF-01 (п.3, 4), REQ-DEV-06 (п.1 — хранение) | T-009, T-010 | `todo` |
| T-012 | `[game]` | 1 | Оболочка приложения: состояние навигации, экран выбора профиля, создание первого профиля, каркас переводов | REQ-PRF-05 (п.1–3), REQ-NFR-08 (п.1 — заделка) | T-009 | `todo` |
| T-013 | `[game]` | 1 | `SessionTicker` (1 Гц от системных часов, не от кадров) и экран разработчика «Проиграть на FakeTrainer» | REQ-DEV-09 (п.6), REQ-WRK-01 (п.5), REQ-NFR-02 (п.1) | T-007, T-012 | `todo` |
| T-014 | `[game]` | 1 | Архитектурные и инфраструктурные проверки: скрипты поиска секретов/осиротевших `.gd`, инвентаризация публичных методов домена | REQ-INF-03, REQ-INF-04, REQ-NFR-06 (п.1–3), REQ-NFR-09 (п.2, 4) | T-013 | `todo` |
| T-015 | `[game]` | 2 | Контракт нативного моста `BleBridge` в GDScript и скриптуемая заглушка `StubBleBridge` | REQ-DEV-01..08 (контракт), REQ-NFR-06 (п.1) | T-002 | `todo` |
| T-016 | `[game]` | 2 | Кодеки BLE-характеристик: FTMS (Indoor Bike Data, Control Point, Status), HRS, CSC, CPS, Battery | REQ-DEV-02 (п.2–5), REQ-DEV-03 (п.1), REQ-DEV-04 (п.1–3), REQ-DEV-05 (п.1), REQ-DEV-07 (п.2) | T-015 | `todo` |
| T-017 | `[game]` | 2 | `BleTrainer`: `TrainerDevice` поверх `BleBridge` — последовательность подключения, телеметрия, команды, ошибки Control Point | REQ-DEV-02 (п.1, 3) | T-016 | `todo` |
| T-018 | `[game]` | 2 | BLE-датчики (`BleHeartRateSensor`, `BleCadenceSensor`, `BlePowerMeter`) и `SensorHub` с приоритетами источников | REQ-DEV-03 (п.2, 3), REQ-DEV-04 (п.4), REQ-DEV-05 (п.2, 3) | T-017 | `todo` |
| T-019 | `[game]` | 2 | Сканер и модель списка устройств | REQ-DEV-01 (п.1–4) | T-015 | `todo` |
| T-020 | `[game]` | 2 | Состояния подключения, заряд, запоминание, автоподключение, «забыть» | REQ-DEV-06 (п.1–4), REQ-DEV-07 (п.1–3) | T-011, T-018, T-019 | `todo` |
| T-021 | `[native-ble]` | 2 | Каркас GDExtension: godot-cpp, сборка, `.gdextension`, класс `BleBridgeNative` с контрактом, платформонезависимая заглушка | REQ-DEV-01 (п.6), REQ-NFR-06 (п.2) | T-015 | `todo` → `blocked: нужен macOS` после написания |
| T-022 | `[native-ble]` | 2 | Реализация контракта на CoreBluetooth (Objective-C++) для macOS/iOS | REQ-DEV-01 (п.5, 6), REQ-DEV-02 (п.6, 7) | T-021 | `todo` → `blocked: нужен macOS` после написания |
| T-023 | `[game]` | 3 | `SampleRecorder`: сэмплы 1 Гц, «последнее за секунду», «нет данных» через 5 с, независимость от кадров | REQ-WRK-08 (п.1–6), REQ-NFR-02 (п.1, 2) | T-007, T-013 | `todo` |
| T-024 | `[game]` | 2→3 | Переподключение без потери данных сессии | REQ-DEV-08 (п.1–4) | T-017, T-020, T-023 | `todo` |
| T-025 | `[game]` | 3 | `ErgController`: расчёт и отправка цели (% FTP, ватты, рампа, без цели), множитель интенсивности, задержка ≤ 1 с, повтор при ошибке записи | REQ-WRK-02 (п.1–5), REQ-WRK-07 (п.1, 2, 3, 5), REQ-NFR-01 (п.1, 2) | T-007, T-023 | `todo` |
| T-026 | `[game]` | 3 | Режим фиксированного сопротивления и переключатель ERG | REQ-WRK-04 (п.1–3), REQ-WRK-03 (п.1–5) | T-025 | `todo` |
| T-027 | `[game]` | 3 | Управление сессией: пауза/возобновление, досрочное завершение, пропуск шага, журнал событий, запрет гашения экрана | REQ-WRK-05 (п.1–4), REQ-WRK-06 (п.1–4), REQ-NFR-04 (п.1, 2) | T-025, T-026 | `todo` |
| T-028 | `[game]` | 3 | Модель HUD «мощность»: сглаживание 3 с, отклонение от цели, зона мощности, зона пульса | REQ-HUD-09, REQ-HUD-02 (п.1–3), REQ-HUD-03 (п.1–3), REQ-HUD-04 (п.1, 2) | T-008, T-023 | `todo` |
| T-029 | `[game]` | 3 | Модель HUD «время и подсказки»: форматы, обратный отсчёт, «скоро смена», подсказки с таймаутом | REQ-HUD-05 (п.1–3), REQ-HUD-06 (п.1, 2), REQ-HUD-08 (п.1–3) | T-027 | `todo` |
| T-030 | `[game]` | 3 | Профиль плана: сегменты для полосы прогресса и точки (t, Вт) для предпросмотра | REQ-HUD-07 (п.1–3), REQ-WRK-07 (п.4), REQ-INT-05 (п.1–3) | T-025, T-027 | `todo` |
| T-031 | `[game]` | 3 | Сцена экрана тренировки (HUD): раскладка, привязка к моделям, кнопки ERG/множитель/сопротивление/пауза/пропуск/завершить | REQ-HUD-01 (п.1–3), REQ-WRK-03 (п.1 — состояние на HUD) | T-028, T-029, T-030 | `todo` |
| T-032 | `[integration]` | 4 | `HttpTransport`: интерфейс, реальная реализация на `HTTPRequest`, `MockHttpTransport` (журнал запросов, заготовленные ответы, режим «нет сети») | REQ-NFR-03 (п.1, 2 — основа) | T-001 | `todo` |
| T-033 | `[integration]` | 4 | Клиент Intervals.icu: авторизация по API-ключу, проверка ключа, профиль атлета (FTP, зоны) с локальным переопределением | REQ-INT-01 (п.1–3), REQ-INT-06 (п.1, 2, 3, 5) | T-010, T-032 | `todo` |
| T-034 | `[integration]` | 4 | Intervals.icu: события календаря на сегодня, фильтр, пустой ответ, 5xx/сеть, 429 | REQ-INT-02 (п.1–5) | T-033 | `todo` |
| T-035 | `[integration]` | 4 | Разбор структурированной тренировки Intervals.icu в `Workout` | REQ-INT-03 (п.1–9), REQ-NFR-09 (п.3 — Intervals) | T-005, T-034 | `todo` |
| T-036 | `[integration]` | 4 | Кэш плана и работа без сети | REQ-INT-07 (п.1–4), REQ-NFR-03 (п.1, 2) | T-035, T-027 | `todo` |
| T-037 | `[integration]` | 4 | Парсер ZWO | REQ-IMP-01 (п.1–7), REQ-NFR-09 (п.3 — ZWO) | T-005 | `todo` |
| T-038 | `[integration]` | 4 | Парсер .erg/.mrc | REQ-IMP-02 (п.1–6), REQ-NFR-09 (п.3 — erg/mrc) | T-005 | `todo` |
| T-039 | `[integration]` | 4 | Точка входа импорта по расширению, модель ошибок импорта, библиотека тренировок профиля | REQ-IMP-03 (п.1), REQ-IMP-05 (п.1–4), REQ-IMP-04 (п.1–5) | T-037, T-038, T-009 | `todo` |
| T-040 | `[game]` | 4 | Экран выбора тренировки и предпросмотра (план на сегодня + библиотека, график профиля) | REQ-INT-04 (п.1–3), REQ-INT-05 (п.1–3 — отображение) | T-030, T-036, T-039 | `todo` |
| T-041 | `[integration]` | 5 | `RideRepository`: сохранение и чтение заездов с сэмплами и событиями в рамках профиля | REQ-LOC-01 (п.1–4), REQ-PRF-04 (п.1) | T-023, T-027, T-009 | `todo` |
| T-042 | `[integration]` | 5 | Потоковая запись заезда на диск и восстановление после сбоя | REQ-LOC-07 (п.1–4) | T-041 | `todo` |
| T-043 | `[game]` | 5 | Сводка заезда (средняя, NP, работа, время в зонах) и серии для графиков | REQ-LOC-04 (п.1–6), REQ-LOC-03 (п.1–3) | T-041, T-008 | `todo` |
| T-044 | `[integration]` | 5 | Кодировщик FIT | REQ-LOC-05 (п.1–4), REQ-STR-02 (п.2), REQ-NFR-09 (п.1 — FIT) | T-043 | `todo` |
| T-045 | `[game]` | 5 | Экраны истории: список, карточка с графиками и сводкой, удаление, экспорт FIT | REQ-LOC-02 (п.1, 2), REQ-LOC-06 (п.1, 2), REQ-LOC-05 (п.6 — вызов диалога) | T-043, T-044 | `todo` |
| T-046 | `[integration]` | 6 | Strava OAuth 2.0: URL авторизации, обмен кода, обновление токенов, отвязка | REQ-STR-01 (п.1–6), REQ-PRF-03 (закрытие), REQ-NFR-05 (п.1, 2 — закрытие) | T-010, T-032 | `todo` |
| T-047 | `[integration]` | 6 | Выгрузка заезда в Strava: multipart FIT, VirtualRide, опрос статуса, название/описание | REQ-STR-02 (п.1, 3, 4), REQ-STR-03 (п.1–3) | T-044, T-046 | `todo` |
| T-048 | `[integration]` | 6 | Очередь выгрузки с повторами и статусы заезда | REQ-STR-04 (п.1–6), REQ-STR-05 (п.1–3), REQ-LOC-06 (п.3), REQ-NFR-03 (п.3) | T-047, T-042 | `todo` |
| T-049 | `[game]` | 6 | Экран привязок (Intervals.icu, Strava) и действия Strava в карточке заезда | REQ-STR-04 (п.5 — UI), REQ-STR-03 (п.3 — UI), REQ-STR-05 (п.2 — UI), REQ-INT-06 (п.4 — UI) | T-033, T-048, T-045 | `todo` |
| T-050 | `[game]` | 7 | Модель скорости v(P, m): установившаяся скорость, инерция, ограничение изменения | REQ-D3D-02 (п.1–4), REQ-WRK-08 (п.5 — альтернативный источник) | T-023 | `todo` |
| T-051 | `[game]` | 7 | Интерфейс трассы `Track`, зацикленная трасса, тестовая трасса, `docs/scene3d.md` | REQ-D3D-03 (п.1, 2), REQ-D3D-06 (п.1–3) | T-050 | `todo` |
| T-052 | `[game]` | 7 | Сцена велосипедиста и камеры, анимация педалирования по каденсу, бюджет производительности | REQ-D3D-01 (п.1, 2), REQ-D3D-04 (п.1–3), REQ-D3D-05 (п.2, 3) | T-051 | `todo` |
| T-053 | `[docs]` | 8 | Пакет публикации iOS/macOS: политика конфиденциальности, чеклисты App Store, заготовка `export_presets.cfg` с описанием BLE и типами файлов, `intervals_oauth.md`, `strava_review.md`, `secure_store.md` | REQ-NFR-07 (п.1, 2, 4), REQ-IMP-03 (п.3), REQ-INT-01 (п.5), REQ-STR-01 (п.7), REQ-NFR-05 (п.3) | T-046 | `todo` |
| T-054 | `[game]` | 8 | Локализация ru/en: таблица переводов, аудит литералов, выбор языка | REQ-NFR-08 (п.1–4) | T-031, T-040, T-045, T-049 | `todo` |
| T-055 | `[docs]` | 9–10 | Порты BLE: `docs/ble_port_checklist.md` (Android/JNI, BlueZ, WinRT), заготовка Android-манифеста, чеклист Google Play, фиксация открытого вопроса о каналах Linux/Windows | REQ-NFR-06 (п.4), REQ-NFR-07 (п.3, 4 — Android) | T-022 | `todo` |

Итого 55 задач: этап 1 — 14, этап 2 — 8 (+ T-024 выполняется в этапе 3), этап 3 — 9, этап 4 — 9, этап 5 — 5, этап 6 — 4, этап 7 — 3, этап 8 — 2, этапы 9–10 — 1.

## 3. Карточки задач

### Этап 1 — Каркас. Результат: тренировка проигрывается без железа

#### T-001 — Инфраструктура тестов и CI `[game]` — `done`
Сделано: `scripts/test.sh`, `.gutconfig.json`, `.github/workflows/ci.yml` (push в любую ветку и PR; шаги «Project opens headless», «Run GUT tests», артефакт `gut-junit` с `if: always()`; Godot 4.7-stable), `tests/unit/test_smoke.gd`. Подтверждено CI run #3.
Закрывает: REQ-INF-01 (п.1–5), REQ-INF-02 (п.1–5) — все `[авто]`.

#### T-002 — Интерфейс `TrainerDevice`, телеметрия, часы, фабрика устройств `[game]`
Что сделать. Зафиксировать контракт, через который вся игровая часть общается со станком; никакого кода вне `src/devices/` не должно знать, какая реализация подключена.
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

#### T-003 — `FakeTrainer`: ядро и ERG-сходимость `[game]`
Что сделать. Симулятор станка, реализующий `TrainerDevice` целиком, время — из инъецированного `Clock`.
- `src/devices/fake_trainer.gd` — `FakeTrainer extends TrainerDevice`. Конструктор `FakeTrainer.new(clock: Clock)`. `tick()` или `advance_to(now_ms)` — симулятор выдаёт один `TrainerTelemetry` на каждую секунду модельного времени. Состояния подключения переключаются синхронно (`connect_device()` → `CONNECTING` → `CONNECTED` на следующем тике).
- ERG-модель: при полученной цели мощность экспоненциально сходится к цели так, что через 3 с |P − цель| ≤ 5 % цели (REQ-DEV-09.2); без цели — мощность по сценарию.
- Журнал команд: `get_command_log() -> Array[Dictionary]` с `{opcode, payload, timestamp_ms}` — именно по этим меткам времени tester проверяет NFR-01/WRK-02. `set_target_power` пишет opcode `0x05`, `set_resistance_level` — `0x04`, `request_control` — `0x00`; через тик эмитит `command_result(opcode, true, 0x01)`.
- Сценарии (`src/devices/fake_scenarios.gd`, `FakeScenario extends RefCounted` с методом `sample_at(t_s) -> TrainerTelemetry` или настройкой параметров): `constant(power, cadence, speed)`, `surges(base, peak, period_s)`, `zero_cadence(from_s)`. Сценарий назначается `set_scenario(s)`.
Файлы: `src/devices/fake_trainer.gd`, `src/devices/fake_scenarios.gd`; `device_factory.gd` возвращает `FakeTrainer` для `&"fake"`.
Закрывает: REQ-DEV-09 п.1 (полностью), п.2, п.4, п.3 (постоянная, рывки, нулевой каденс).
Критерии авто: все `[авто]` по перечисленным пунктам. Ручных нет.

#### T-004 — `FakeTrainer`: сценарии сбоев и симуляторы датчиков `[game]`
Что сделать.
- В `fake_scenarios.gd` добавить: `packet_loss(from_s, duration_s)` — N секунд без телеметрии; `disconnect_at(t_s, reconnect_after_s)` — эмитит `connection_state_changed(DISCONNECTED)`, при вызове `connect_device()` после `reconnect_after_s` восстанавливает `CONNECTED`; `control_point_error(opcode, result_code)` — на указанную команду отвечает `command_result(opcode, false, result_code)` (например, `0x02` «не поддерживается», `0x03` «неверный параметр»).
- `src/devices/sensor_device.gd` — базовый интерфейс датчика: сигналы `connection_state_changed`, `value_received(value: int, timestamp_ms: int)`, `battery_level_changed(percent: int)`; методы `connect_device`, `disconnect_device`.
- `src/devices/fake_heart_rate_sensor.gd`, `src/devices/fake_cadence_sensor.gd` — выдают заданную последовательность значений (`set_sequence(values: Array[int])`) по 1 значению на секунду модельного времени `Clock`; `NO_DATA` в последовательности — пропуск.
Файлы: `src/devices/fake_scenarios.gd`, `src/devices/sensor_device.gd`, `src/devices/fake_heart_rate_sensor.gd`, `src/devices/fake_cadence_sensor.gd`.
Закрывает: REQ-DEV-09 п.3 (пропуск пакетов, обрыв/восстановление, ошибка Control Point), п.5.
Критерии авто: все. Ручных нет.

#### T-005 — Доменная модель тренировки `[game]`
Что сделать. Чистый GDScript (`RefCounted`), без узлов сцены.
- `src/domain/workout_target.gd` — `WorkoutTarget`: `enum Kind { NONE, PERCENT_FTP, WATTS }`, `kind`, `start_value: float`, `end_value: float` (рампа, если `start_value != end_value`), `is_ramp() -> bool`, `watts_at(progress: float, ftp: int) -> int` (округление до целого).
- `src/domain/workout_cue.gd` — `WorkoutCue`: `offset_s: int`, `text: String`.
- `src/domain/workout_step.gd` — `WorkoutStep`: `duration_s: int` (> 0), `target: WorkoutTarget`, `cadence_rpm: int` (`-1` — не задан), `cues: Array[WorkoutCue]`, `name: String`.
- `src/domain/workout.gd` — `Workout`: `name`, `description`, `author`, `source: String` («intervals», «zwo», «erg», «mrc»), `source_ref` (id события/имя файла), `steps: Array[WorkoutStep]`, `total_duration_s() -> int`, `is_valid() -> bool` (непустой список, все длительности > 0), `metadata: Dictionary` (например, FTP из заголовка .erg).
- Плоская последовательность шагов: повторы разворачивают парсеры, модель повторов не хранит.
Файлы: четыре файла выше.
Закрывает: входная модель для REQ-WRK-01 и всех парсеров; REQ-NFR-09 п.1 в части «модель тренировки».
Критерии авто: `total_duration_s`, `watts_at` для % FTP/ватт/рампы, `is_valid`. Ручных нет.

#### T-006 — Исполнитель интервалов `IntervalExecutor` `[game]`
Что сделать. `src/domain/interval_executor.gd` — `IntervalExecutor extends RefCounted`.
- Конструктор `(workout: Workout, clock: Clock)`; `start()`, `tick()` — вызывается внешним источником 1 Гц; исполнитель сам считает `elapsed_s` по `clock.now_ms()` (не по числу вызовов), так что пропущенные тики догоняются.
- Сигналы: `step_started(index: int, step: WorkoutStep)`, `step_finished(index: int)`, `workout_finished()` — ровно один раз; `tick_processed(elapsed_s: int, step_elapsed_s: int)`.
- Переход на том тике, где `step_elapsed_s >= duration_s`; план «60, 30, 90» завершается на тике 180.
- Геттеры: `current_step_index()`, `step_elapsed_s()`, `step_remaining_s()`, `total_elapsed_s()`, `total_remaining_s()`, `is_finished()`.
- Заделы для этапа 3 (без реализации логики UI): `skip_step()` (переход на следующем тике), `pause()`/`resume()` (на паузе `tick()` не продвигает время шага; учёт времени паузы — через смещение по часам), `stop()`.
- Никаких `Node`, `SceneTree`, `_process`.
Файлы: `src/domain/interval_executor.gd`.
Закрывает: REQ-WRK-01 п.1–4; REQ-NFR-02 п.1 (часть «исполнитель»); REQ-NFR-09 п.1 (исполнитель), п.4.
Критерии авто: все. Ручных нет.

#### T-007 — `WorkoutSession`: прогон плана на `FakeTrainer` `[game]`
Что сделать. `src/domain/workout_session.gd` — `WorkoutSession extends RefCounted`: собирает `IntervalExecutor`, `TrainerDevice`, `Clock`, FTP профиля.
- `start()` подключает устройство (`connect_device`, `request_control`), стартует исполнитель; `tick()` продвигает исполнитель и симулятор (если устройство — `FakeTrainer`, вызывает его `advance_to(now_ms)`; иначе ничего).
- На `step_started` отправляет `set_target_power(target.watts_at(0, ftp))` — минимальный ERG, нужный для результата этапа 1 (полные критерии WRK-02 закрываются в T-025, здесь — заделка).
- Накопление телеметрии в памяти (`get_telemetry_log()`), чтобы тест мог убедиться, что станок «ехал».
- Сигналы `session_finished()`, `state_changed(state)` (`IDLE`, `RUNNING`, `PAUSED`, `FINISHED`).
- Точка расширения для T-023/T-025/T-027: сессия владеет исполнителем и устройством, контроллеры подключаются к её сигналам.
Файлы: `src/domain/workout_session.gd`. Внимание: `src/domain/` не должен импортировать `src/devices/` — `TrainerDevice` передаётся как `RefCounted` с утиной типизацией или интерфейс `TrainerDevice` переносится в `src/domain/trainer_port.gd`, а `src/devices/trainer_device.gd` его наследует. Developer выбирает второй вариант, если статическая типизация иначе невозможна; решение отразить в отчёте.
Закрывает: REQ-WRK-01 п.5, REQ-DEV-09 п.6 (запуск сессии с `FakeTrainer` в тесте).
Критерии авто: план из 3 шагов проигрывается до `session_finished` на `FakeTrainer` с `ManualClock`; в журнале команд станка есть `0x05` на каждом переходе. Ручных нет.

#### T-008 — Зоны мощности и пульса `[game]`
Что сделать. `src/domain/zones.gd` — `Zones extends RefCounted`.
- `static func default_power_zones() -> PackedFloat32Array` — верхние границы Z1–Z6 в % FTP: 55, 75, 90, 105, 120, 150 (Z7 — выше 150).
- `static func default_hr_zones() -> PackedFloat32Array` — верхние границы Z1–Z4 в % от максимального пульса: 60, 70, 80, 90 (Z5 — ≥ 90). Границы трактовать так, чтобы при max HR 180: 107 → Z1, 108 → Z2, 126 → Z3, 144 → Z4, 162 → Z5 (REQ-HUD-04.1).
- `static func power_zone(watts: int, ftp: int, bounds: PackedFloat32Array) -> int` (1–7); при FTP 200: 110 → 1, 111 → 2, 150 → 2, 151 → 3, 180 → 3, 181 → 4, 210 → 4, 211 → 5, 240 → 5, 241 → 6, 300 → 6, 301 → 7. `watts <= 0` или `NO_DATA` → 1.
- `static func hr_zone(bpm: int, max_hr: int, bounds) -> int` (1–5); `NO_DATA` → 0 («—»).
- `static func zone_color_token(zone: int) -> StringName` — токены палитры `&"zone_1"`…`&"zone_7"` (серый, синий, зелёный, жёлтый, оранжевый, красный, фиолетовый); сами цвета — в теме UI (T-031).
Файлы: `src/domain/zones.gd`.
Закрывает: REQ-PRF-02 п.2, 3, 5 (п.1, 4 — в T-009). Основа для HUD-03/04, INT-05.3, LOC-04.5.
Критерии авто: все. Ручных нет.

#### T-009 — Модель профиля, валидация, `ProfileRepository` `[game]`
Что сделать.
- `src/profiles/profile.gd` — `Profile extends RefCounted`: `id: String` (UUID-подобный, генерируется один раз), `name`, `ftp: int` (50–600), `weight_kg: float` (20.0–250.0, шаг 0.1), `max_hr: int` (см. вопрос В-1 в разделе 5; до решения — 100–230, по умолчанию 190), `power_zone_bounds`, `hr_zone_bounds`, `ftp_override_local: bool`, `ftp_source: String` («local» / «intervals:<дата>»), `resistance_level_pct: float` (для WRK-04, по умолчанию 50), `to_dict()/from_dict()`.
- `src/profiles/profile_validator.gd` — функции валидации, возвращающие `ValidationResult {ok: bool, message_key: StringName}`: имя 1–40 символов после `strip_edges()`, уникальность без учёта регистра, диапазоны FTP/веса. Сообщения — ключи переводов, не русские литералы.
- `src/profiles/profile_repository.gd` — `ProfileRepository extends RefCounted`: `list()`, `create(name) -> Profile`, `update(profile)`, `delete(id)` (отказ, если профиль последний), `set_active(id)`, `get_active() -> Profile`, `load()/save()` в `user://profiles.json` (путь инъецируется для тестов). Удаление каскадно чистит данные профиля через колбэки, регистрируемые T-010/T-011/T-041 (`add_on_delete_hook(callable)`), чтобы `src/profiles/` не зависел от хранилищ.
Файлы: три файла выше.
Закрывает: REQ-PRF-01 п.1, 2, 5, 6 (п.3, 4 — после T-011); REQ-PRF-02 п.1, 4.
Критерии авто: все перечисленные. Ручных нет.

#### T-010 — `SecureStore` `[game]`
Что сделать. `src/storage/secure_store.gd` — интерфейс `SecureStore extends RefCounted`: `put(key: String, value: String)`, `get_value(key) -> String` (пусто, если нет), `delete(key)`, `delete_prefix(prefix)`, `has(key)`. Ключи формируются хелпером `SecureStore.key_for(profile_id, service, item)` → `"<profile_id>/<service>/<item>"` (`service` ∈ `intervals`, `strava`; `item` ∈ `api_key`, `access_token`, `refresh_token`, `expires_at`). `src/storage/in_memory_secure_store.gd` — реализация в памяти (тесты и dev-режим в контейнере). `src/storage/secure_store_factory.gd` — выбирает реализацию; в контейнере всегда in-memory; платформенные реализации описываются в `docs/secure_store.md` (T-053) и будут добавлены вне контейнера. Единственный модуль в `src/`, где допустимы проверки платформы помимо `src/devices/ble_*`. Регистрирует хук удаления профиля (`delete_prefix(profile_id + "/")`).
Файлы: три файла выше.
Закрывает: REQ-NFR-05 п.1, 2; REQ-PRF-03 п.1, 2, 3 (окончательно подтверждаются вместе с T-046, когда появляются реальные записи токенов).
Критерии авто: изоляция ключей по профилю, удаление только своего сервиса, отсутствие значений в файлах `user://`. Ручные: REQ-PRF-03 п.4, REQ-NFR-05 п.4.

#### T-011 — Реестр запомненных устройств `[game]`
Что сделать. `src/profiles/remembered_devices.gd` — `RememberedDevices extends RefCounted`: `remember_trainer(id, name)` (общий для устройства, хранится в `user://devices.json`), `remember_sensor(profile_id, id, name, kind)` (в данных профиля), `forget(profile_id_or_null, id)`, `trainer() -> Dictionary`, `sensors_for(profile_id) -> Array`. Хук удаления профиля удаляет только его датчики. В `ProfileRepository.delete` подключить хуки T-010 и T-011 — тем самым закрыть REQ-PRF-01 п.3, 4.
Файлы: `src/profiles/remembered_devices.gd`, правка `profile_repository.gd` (подтверждение удаления — флаг `confirmed: bool` в `delete(id, confirmed)`).
Закрывает: REQ-PRF-04 п.2, 3, 4; REQ-PRF-01 п.3, 4; REQ-DEV-06 п.1 (часть «хранение»).
Критерии авто: все. Ручных нет.

#### T-012 — Оболочка приложения и экран выбора профиля `[game]`
Что сделать. `src/ui/app_shell.gd` + `src/ui/app_shell.tscn` — корневая сцена, `src/ui/navigation_state.gd` — чистая модель навигации (`enum Screen { CREATE_FIRST_PROFILE, SELECT_PROFILE, MAIN, DEV_WORKOUT, ... }`, `initial_screen(profile_count) -> Screen`, `can_open_main() -> bool`), проверяемая headless без сцены. Сцены `src/ui/profile_select.tscn` (+`.gd`) и `src/ui/profile_create.tscn` (+`.gd`), минимальная вёрстка `Control`. Все строки через `tr()`; завести `assets/i18n/translations.csv` (ключи, `ru`, `en`) и подключить в `project.godot` — задел для NFR-08. `project.godot`: главная сцена `app_shell.tscn`.
Файлы: перечисленные выше, `assets/i18n/translations.csv`, правка `project.godot`.
Закрывает: REQ-PRF-05 п.1, 2, 3; REQ-NFR-08 п.1 (заделка; закрытие — T-054).
Критерии авто: `initial_screen` для 0/1/2 профилей; главный экран недоступен без выбора. Ручные: REQ-PRF-05 п.4.

#### T-013 — `SessionTicker` и экран разработчика `[game]`
Что сделать. `src/ui/session_ticker.gd` — `Node`, который на каждом кадре (или по `Timer`) сравнивает `Time.get_ticks_msec()` с последней отметкой и вызывает `tick()` сессии столько раз, сколько полных секунд прошло (догон после заморозки кадра — основа REQ-NFR-02.2). `src/devices/system_clock.gd` — `Clock` на `Time.get_ticks_msec()`. `src/ui/dev_workout_screen.tscn` (+`.gd`) — кнопка «Старт», текстовые метки: шаг, цель, мощность, каденс, осталось; план — встроенный тестовый (3 шага) или из `tests/fixtures/`; устройство — `DeviceFactory.create_trainer(&"fake")` со сценарием «постоянная». Доступ с главного экрана при включённом `OS.is_debug_build()` или настройке `ovosch/dev_mode`.
Файлы: `src/ui/session_ticker.gd`, `src/devices/system_clock.gd`, `src/ui/dev_workout_screen.tscn/.gd`.
Закрывает: REQ-DEV-09 п.6, REQ-WRK-01 п.5 (в приложении), REQ-NFR-02 п.1.
Критерии авто: 60 вызовов `tick()` без `_process` дают корректные переходы; сцена инстанцируется headless. Ручных нет.

#### T-014 — Архитектурные и инфраструктурные проверки `[game]`
Что сделать (developer — скрипты, tester — тесты поверх них). `scripts/check_secrets.sh` — grep по шаблонам `client_secret`, `api_key=`, `Bearer `, `refresh_token` в `src/`, `tests/fixtures/`, `project.godot` с белым списком плейсхолдеров; `scripts/check_uids.sh` — осиротевшие `.gd` без `.gd.uid`; `scripts/check_arch.sh` — `OS.get_name()`/`OS.has_feature()` только в `src/devices/ble_*` и `src/storage/secure_store*`, в `src/domain/` нет `preload`/`load` на `src/devices|ui|scene3d`, C++/ObjC только в `native/ble/`. Для REQ-NFR-09.2 — `src/domain/` экспортирует список публичных методов через `ClassDB`/рефлексию скрипта, тест-инвентаризация (tester) сверяет с вызовами в тестах. Для REQ-INF-03.1 — проверка `git log` в CI требует `fetch-depth: 0` в `actions/checkout` (правка `ci.yml` допустима в этой задаче).
Файлы: `scripts/check_secrets.sh`, `scripts/check_uids.sh`, `scripts/check_arch.sh`, правка `.github/workflows/ci.yml`.
Закрывает: REQ-INF-03 п.1–4, REQ-INF-04 п.1–3, REQ-NFR-06 п.1–3, REQ-NFR-09 п.2, 4.
Критерии авто: все. Ручных нет.

### Этап 2 — BLE для iOS и macOS. Результат: реальное подключение к Tacx Neo

#### T-015 — Контракт `BleBridge` и `StubBleBridge` `[game]`
Что сделать. `src/devices/ble_bridge.gd` — `BleBridge extends RefCounted`, контракт из requirements.md (раздел DEV): методы `start_scan(service_uuids: PackedStringArray)`, `stop_scan()`, `connect_device(device_id)`, `disconnect_device(device_id)`, `subscribe(device_id, char_uuid)`, `write(device_id, char_uuid, bytes: PackedByteArray, with_response: bool)`, плюс `read(device_id, char_uuid)` (см. вопрос В-2); сигналы `device_found(id, name, rssi, service_uuids)`, `connected(id)`, `disconnected(id, reason)`, `value(id, char_uuid, bytes)`, `write_result(id, char_uuid, ok)`. `src/devices/stub_ble_bridge.gd` — скриптуемая заглушка: `emit_device_found(...)`, `emit_value(...)`, журнал вызовов `calls: Array[Dictionary]`, настраиваемые ответы на `write` (ok/fail) и автоматический ответ Control Point. `src/devices/ble_bridge_factory.gd` — выбирает `BleBridgeNative` (если `ClassDB.class_exists("BleBridgeNative")`) или заглушку; единственное место платформенной проверки в `src/devices/`.
Закрывает: контракт для REQ-DEV-01..08; REQ-NFR-06 п.1.
Критерии авто: заглушка реализует весь контракт; журнал вызовов. Ручных нет.

#### T-016 — Кодеки BLE-характеристик `[game]`
Что сделать. Чистые функции без состояния (кроме CSC, которому нужны предыдущие значения).
- `src/devices/ftms_codec.gd`: `parse_indoor_bike_data(bytes) -> Dictionary` по флагам (мощность sint16, каденс uint16×0.5, скорость uint16×0.01, пульс uint8), `parse_control_point_response(bytes) -> {opcode, result}`, `encode_request_control() -> [0x00]`, `encode_set_target_power(w) -> [0x05, lo, hi]` (250 → `05 FA 00`), `encode_set_resistance_level(level) -> [0x04, uint8 ×0.1]` (5.0 → `04 32`), `parse_resistance_range(bytes)` для `0x2AD6`, `parse_machine_status(bytes)`. UUID-константы `0x1826`, `0x2AD2`, `0x2AD9`, `0x2ADA`, `0x2AD6`.
- `src/devices/hrs_codec.gd`: `parse_heart_rate_measurement(bytes) -> {bpm, sensor_contact: int}` (`00 48` → 72; `01 48 00` → 72).
- `src/devices/csc_codec.gd`: `CscCadenceCalculator` с переполнением uint16/uint32, Δоборотов 3 при Δвремени 2048 → 90 rpm, 3 с без оборотов → 0.
- `src/devices/cps_codec.gd`: `parse_power_measurement(bytes)` (sint16 по смещению 2; `00 00 FA 00` → 250), crank data для каденса.
- `src/devices/battery_codec.gd`: `parse_level(bytes)`.
Закрывает: REQ-DEV-02 п.2–5; REQ-DEV-03 п.1; REQ-DEV-04 п.1–3; REQ-DEV-05 п.1; REQ-DEV-07 п.2 (разбор). Критерии авто: все. Ручных нет.

#### T-017 — `BleTrainer` `[game]`
Что сделать. `src/devices/ble_trainer.gd` — `BleTrainer extends TrainerDevice` поверх `BleBridge`: на `connected` подписывается на `0x2AD2`, `0x2ADA`, `0x2AD9`, затем `write` Request Control; телеметрия из Indoor Bike Data → `telemetry_received`; `set_target_power`/`set_resistance_level` → `write` с кодеками; ответ CP с `result != 0x01` → `command_result(opcode, false, result)` и сообщение пользователю (ключ перевода); `write_result=false` → `command_result(..., false, -1)`. `device_factory.gd` возвращает `BleTrainer` для `&"ble"`.
Закрывает: REQ-DEV-02 п.1, 3. Критерии авто: последовательность подписок и Request Control на `StubBleBridge`, маппинг ошибок. Ручные: REQ-DEV-02 п.6, 7.

#### T-018 — BLE-датчики и `SensorHub` `[game]`
Что сделать. `src/devices/ble_heart_rate_sensor.gd`, `src/devices/ble_cadence_sensor.gd`, `src/devices/ble_power_meter.gd` (реализуют `SensorDevice` из T-004; подписки `0x2A37`, `0x2A5B`, `0x2A63`; пульс без контакта → недостоверный, не эмитится). `src/devices/sensor_hub.gd` — объединяет источники в одну «текущую телеметрию»: пульс HRS > станок; каденс CSC > CPS > станок; мощность — `set_power_source(&"trainer" | &"power_meter")`, по умолчанию станок; выбор сохраняется в профиле. Выход — сигнал `merged_telemetry(sample)` для сэмплера T-023 и HUD.
Закрывает: REQ-DEV-03 п.2, 3; REQ-DEV-04 п.4; REQ-DEV-05 п.2, 3. Критерии авто: все. Ручные: REQ-DEV-03 п.4, REQ-DEV-04 п.5, REQ-DEV-05 п.4.

#### T-019 — Сканер и список устройств `[game]`
Что сделать. `src/devices/ble_scanner.gd` — `start()` вызывает `start_scan(["1826","180D","1816","1818"])`; `device_found` → добавить/обновить запись `{id, name ("Без имени" — ключ перевода), rssi, kind по сервисам, last_seen_ms}`; `prune(now_ms)` — не было событий 10 с → `unavailable`; `stop()` при уходе с экрана и при подключении. `src/ui/devices_screen.tscn/.gd` — список с кнопками «подключить»/«забыть» (минимальная вёрстка).
Закрывает: REQ-DEV-01 п.1–4. Критерии авто: все. Ручные: REQ-DEV-01 п.5.

#### T-020 — Состояния подключения, заряд, автоподключение `[game]`
Что сделать. `src/devices/connection_manager.gd`: состояния по REQ-DEV-07.1 от событий моста; после `connected` — `read` Battery Level при наличии `0x180F` и подписка на нотификации, иначе «—»; после успешного подключения — `RememberedDevices.remember_*`; при открытии экрана тренировки — `start()` сканера и `connect_device` на запомненные сразу после `device_found`; таймер 30 с → «устройство не найдено»; «забыть» → `forget`.
Закрывает: REQ-DEV-06 п.1–4; REQ-DEV-07 п.1–3. Критерии авто: все. Ручные: REQ-DEV-06 п.5, REQ-DEV-07 п.4.

#### T-021 — Каркас GDExtension `[native-ble]`
Что сделать. `native/ble/SConstruct` (или `CMakeLists.txt`) с godot-cpp как git submodule или задокументированной зависимостью; `native/ble/ble_bridge.gdextension` с `entry_symbol` и путями библиотек для `macos`, `ios`; `native/ble/src/register_types.cpp`, `native/ble/src/ble_bridge_native.h/.cpp` — класс `BleBridgeNative : public RefCounted` с методами и сигналами контракта (имена и сигнатуры 1:1 с `src/devices/ble_bridge.gd`); платформонезависимая реализация-заглушка (все методы — no-op с `UtilityFunctions::push_warning`), чтобы код компилировался на любой платформе; `native/ble/README.md` — как собрать на macOS (`scons platform=macos target=template_debug`), куда кладётся `.framework`/`.dylib`. В контейнере проверяется только статически: соответствие сигнатур контракту, наличие файлов. После написания — `blocked: нужен macOS`.
Закрывает: REQ-DEV-01 п.6 (`[вне контейнера]`), REQ-NFR-06 п.2. Критерии авто: нет. Вне контейнера: сборка для macOS и iOS.

#### T-022 — CoreBluetooth-реализация `[native-ble]`
Что сделать. `native/ble/src/platform/apple/ble_bridge_apple.mm` (+ `.h`): `CBCentralManager` + делегаты; `start_scan` с `CBUUID` из `service_uuids`; `connect` → discover services/characteristics → событие `connected`; `subscribe` → `setNotifyValue`; `write` → `writeValue:type:` с `withResponse`/`withoutResponse`, `write_result` из `didWriteValueForCharacteristic`; `read` → `readValueForCharacteristic`; `value` из `didUpdateValueForCharacteristic`; `disconnected(id, reason)` из `didDisconnectPeripheral`. Все события маршалятся в главный поток Godot через `call_deferred`. Описание разрешений (`NSBluetoothAlwaysUsageDescription`) — в T-053. После написания — `blocked: нужен macOS`.
Закрывает: REQ-DEV-01 п.5, 6; REQ-DEV-02 п.6, 7 — все ручные/вне контейнера. Критерии авто: нет.

### Этап 3 — Тренировка и ERG. Результат: можно тренироваться

#### T-023 — `SampleRecorder` 1 Гц `[game]`
Что сделать. `src/domain/sample.gd` — `Sample`: `t_s`, `power_w`, `heart_rate_bpm`, `cadence_rpm`, `speed_kmh`, `target_w`, `step_index`, `erg_on` (`NO_DATA` для отсутствующих). `src/domain/sample_recorder.gd` — принимает телеметрию (`on_power(value, ts)`, `on_heart_rate`, `on_cadence`, `on_speed`), на каждом тике сессии фиксирует сэмпл с последним значением за секунду; значение старше 5 с → `NO_DATA`; на паузе сэмплы не пишутся; метки монотонны с шагом 1 с; 600 с → 600 ± 1 сэмплов; работает от `Clock` без `_process`. При догоне после заморозки (T-013) записывает пропущенные секунды постфактум.
Закрывает: REQ-WRK-08 п.1–6; REQ-NFR-02 п.1, 2. Критерии авто: все. Ручные: REQ-NFR-02 п.3.

#### T-024 — Переподключение без потери данных `[game]` (REQ этапа 2, выполняется после T-023)
Что сделать. В `connection_manager.gd`/`ble_trainer.gd`: `disconnected` во время сессии → `RECONNECTING`, `connect_device` каждые 5 с до успеха или конца сессии; сессия и `SampleRecorder` не останавливаются (`NO_DATA`, не 0); после `connected` в ERG — Request Control и Set Target Power текущей цели ≤ 1 с; сэмплы до обрыва сохраняются. Проверяется на `FakeTrainer` со сценарием `disconnect_at`.
Закрывает: REQ-DEV-08 п.1–4. Критерии авто: все. Ручные: REQ-DEV-08 п.5, 6.

#### T-025 — `ErgController`: цели, рампы, множитель, задержка ≤ 1 с `[game]`
Что сделать. `src/domain/erg_controller.gd`: подписан на `step_started` и `tick_processed` сессии; цель = `target.watts_at(progress, ftp) × multiplier`, округление до целого; на границе шага отправка немедленно (≤ 1 с по журналу `FakeTrainer`); рампа — пересчёт каждую секунду, отправка при изменении ≥ 1 Вт и не чаще 1 раза в секунду; шаг без цели — не отправлять Set Target Power; `write_result=false`/`command_result(ok=false)` → один повтор в пределах той же секунды. Множитель: `set_intensity(pct)` 50–150 с шагом 5, по умолчанию 100; изменение в ERG → новая цель ≤ 1 с; значение сохраняется в сессии для заезда. Проверка на 20-интервальном плане и при «нагрузке на кадр» 200 мс (эмулируется задержкой тика).
Закрывает: REQ-WRK-02 п.1–5; REQ-WRK-07 п.1, 2, 3, 5; REQ-NFR-01 п.1, 2. Критерии авто: все. Ручные: REQ-WRK-02 п.6, REQ-NFR-01 п.3.

#### T-026 — Режим сопротивления и переключатель ERG `[game]`
Что сделать. В `erg_controller.gd` (или `src/domain/load_mode.gd`): `erg_enabled` (по умолчанию `true`); `toggle_erg()` — одно действие; выключение → Set Target Resistance Level текущего уровня ≤ 1 с; включение → Set Target Power цели ≤ 1 с (с множителем); таймер и сэмплы не прерываются; уровень 0–100 % шаг 5, хранится в профиле; перевод % в единицы станка по `0x2AD6` (если есть, через `get_capabilities()`) или линейно в 0–100 единиц 0.1; при включённом ERG изменение уровня сохраняется, но не отправляется. Переключения ERG записываются в журнал событий сессии (для LOC-01.4).
Закрывает: REQ-WRK-04 п.1–3; REQ-WRK-03 п.1 (состояние), 2–5. Критерии авто: все. Ручные: REQ-WRK-03 п.1 (отображение), REQ-WRK-04 п.4.

#### T-027 — Управление сессией: пауза, завершение, пропуск, события, экран `[game]`
Что сделать. В `workout_session.gd` + `interval_executor.gd`: `pause()`/`resume()` (остаток шага сохраняется; при возобновлении повторная отправка цели/уровня ≤ 1 с; поведение станка на паузе — по умолчанию «ничего не отправлять», см. вопрос В-4); `finish_early(confirmed)` — заезд помечается `ended_early`; `skip_step()` — переход на ближайшем тике, новая цель ≤ 1 с, пропуск последнего завершает тренировку; `src/domain/session_events.gd` — журнал событий `{type: PAUSE_START|PAUSE_END|SKIP|ERG_ON|ERG_OFF|DISCONNECT|RECONNECT, t_s, step_index}`. `src/ui/screen_keep_awake.gd` — адаптер с инъецируемым вызовом `DisplayServer.screen_set_keep_on`; включается на старте сессии, сохраняется на паузе, снимается при завершении и уходе с экрана.
Закрывает: REQ-WRK-05 п.1–4; REQ-WRK-06 п.1–4; REQ-NFR-04 п.1, 2. Критерии авто: все. Ручные: REQ-WRK-05 п.5, REQ-NFR-04 п.3.

#### T-028 — Модель HUD «мощность» `[game]`
Что сделать. `src/domain/power_smoother.gd` — скользящее среднее 3 последних сэмплов с исключением `NO_DATA` (100, 200, 300 → 200; затем 300 → 267; все три `NO_DATA` → «—»); сглаживание только для HUD. `src/ui/hud_power_model.gd` — `deviation_state(actual, target)`: `IN_TARGET` при |факт − цель| ≤ max(5 % цели, 10 Вт), иначе `ABOVE`/`BELOW`, `HIDDEN` при цели «—»; `power_zone` и `hr_zone` через `Zones` профиля; 0/`NO_DATA` → Z1 / «—»; `NO_DATA` пульса → «—» без цвета.
Закрывает: REQ-HUD-09 п.1–4; REQ-HUD-02 п.1–3; REQ-HUD-03 п.1–3; REQ-HUD-04 п.1, 2. Критерии авто: все. Ручные: REQ-HUD-02 п.4, REQ-HUD-03 п.4, REQ-HUD-04 п.3.

#### T-029 — Модель HUD «время и подсказки» `[game]`
Что сделать. `src/ui/hud_time_model.gd`: `format_elapsed(s)` (`мм:сс` до часа, далее `ч:мм:сс`), `format_countdown(remaining_s)` (`мм:сс`, на тике перехода — длительность нового шага), `is_about_to_change(remaining_s) -> remaining_s <= 5`, целочисленные пульс/каденс, скорость с одним знаком, «—» для `NO_DATA`; прошедшее время — без пауз (из исполнителя). `src/ui/hud_cue_model.gd`: подсказка шага с его начала, подсказка с `offset_s` — с указанной секунды; скрытие через 10 с или при смене шага; обрезка > 120 символов с «…».
Закрывает: REQ-HUD-05 п.1–3; REQ-HUD-06 п.1, 2; REQ-HUD-08 п.1–3. Критерии авто: все. Ручные: REQ-HUD-05 п.4, REQ-HUD-06 п.3, REQ-HUD-08 п.4.

#### T-030 — Профиль плана: сегменты и точки `[game]`
Что сделать. `src/domain/workout_profile.gd`: `segments(workout, ftp, multiplier) -> Array[{start_s, duration_s, target_w, zone}]` (сумма длительностей = длительность плана; рампа — сегмент с `start_w/end_w`); `points(workout, ftp) -> PackedVector2Array` (t, Вт) — ступени для постоянных шагов («10 мин 50 %, 5 мин 100 %» при FTP 200 → 100 Вт на [0; 600), 200 Вт на [600; 900)), линейный участок для рампы; `cursor(elapsed_s, total_s) -> float`. `src/ui/hud_progress_model.gd`: состояние сегментов `UPCOMING|CURRENT|DONE|SKIPPED` из событий сессии; пересчёт зон при изменении множителя.
Закрывает: REQ-HUD-07 п.1–3; REQ-WRK-07 п.4; REQ-INT-05 п.1–3 (функции; отображение — T-040). Критерии авто: все. Ручные: REQ-HUD-07 п.4.

#### T-031 — Сцена экрана тренировки (HUD) `[game]`
Что сделать. `src/ui/workout_screen.tscn/.gd`: узлы `TargetPowerLabel` (главный, крупный), `ActualPowerLabel` с индикатором отклонения, `PowerZoneBadge`, `HrZoneBadge`, `HeartRateLabel`, `CadenceLabel`, `SpeedLabel`, `ElapsedLabel`, `CountdownLabel`, `ProgressBar` (кастомный `Control` по модели T-030), `CueLabel`, кнопки `ErgToggle`, `IntensityMinus/Plus`, `ResistanceMinus/Plus`, `Pause`, `Skip`, `Finish` (с подтверждением). Тема `assets/theme/hud_theme.tres`: размер шрифта цели ≥ 2× размера пульса/каденса; цвета зон `zone_1..zone_7`. Привязка к моделям T-028..T-030, `SessionTicker` из T-013, `ScreenKeepAwake` из T-027. Строки через `tr()`.
Закрывает: REQ-HUD-01 п.1–3; REQ-WRK-03 п.1 (состояние ERG на HUD). Критерии авто: тексты узлов после подачи сэмплов headless; сравнение размеров шрифта из темы. Ручные: REQ-HUD-01 п.4 и все «внешний вид» HUD-02..08.

### Этап 4 — Источники плана. Результат: план подтягивается автоматически или из файла

#### T-032 — `HttpTransport` и мок `[integration]`
Что сделать. `src/integrations/http_transport.gd` — интерфейс `request(method, url, headers, body) -> HttpResponse {status, headers, body, error}` (асинхронно через `await`); `src/integrations/godot_http_transport.gd` — реализация на `HTTPRequest` (единственное место сетевого ввода-вывода в `src/`); `src/integrations/mock_http_transport.gd` — журнал запросов, очередь заготовленных ответов (по методу+URL-шаблону), режим `offline = true` (всегда сетевая ошибка), поддержка заголовка `Retry-After`, подменяемые часы. Фикстуры — `tests/fixtures/intervals/`, `tests/fixtures/strava/` (tester).
Закрывает: основа REQ-NFR-03 п.1, 2 (закрытие — T-036). Критерии авто: мок считает запросы, отдаёт ответы, offline. Ручных нет.

#### T-033 — Клиент Intervals.icu: авторизация и профиль атлета `[integration]`
Что сделать. `src/integrations/intervals/intervals_client.gd`: `set_credentials(athlete_id, api_key)` → заголовок `Authorization: Basic base64("API_KEY:<ключ>")` в каждом запросе; `verify() -> Result`: 401/403 → «ключ не принят», ключ не сохраняется; успех → ключ в `SecureStore` под ключом профиля; текст любой ошибки не содержит подстроку ключа, ключ не логируется. `fetch_athlete()` → FTP и границы зон мощности из ответа → `Profile` (если `ftp_override_local` — не менять; иначе обновить и выставить `ftp_source = "intervals:<дата>"`); нет FTP в ответе → локальное значение + предупреждение. Фикстура `tests/fixtures/intervals/athlete.json` (синтетическая до получения реальной — см. В-5).
Закрывает: REQ-INT-01 п.1–3; REQ-INT-06 п.1, 2, 3, 5. Критерии авто: все. Ручные: REQ-INT-01 п.4, REQ-INT-06 п.4.

#### T-034 — Intervals.icu: события календаря `[integration]`
Что сделать. `intervals_client.fetch_today_events(today: String)` — `oldest = newest = YYYY-MM-DD` локальной даты; фильтр: категория «тренировка» с велосипедным типом; `[]` → `NO_WORKOUTS_TODAY`; 5xx/сетевая ошибка → `LOAD_FAILED` с возможностью повтора; 429 → `RETRY_LATER` не раньше `Retry-After` (или 60 с). Фикстура со смешанными событиями `tests/fixtures/intervals/events_mixed.json`.
Закрывает: REQ-INT-02 п.1–5. Критерии авто: все. Ручные: REQ-INT-02 п.6.

#### T-035 — Разбор тренировки Intervals.icu `[integration]`
Что сделать. `src/integrations/intervals/intervals_workout_parser.gd`: текстовое описание шагов Intervals.icu (`10m 65%`, `5m 250w`, `60-70%`, рампы `50-80%` с признаком ramp, повторы `3x`, каденс `85rpm`, текстовые строки как подсказки) → `Workout` с плоским списком шагов; диапазон → середина; суммарная длительность = заявленной ±1 с; неподдерживаемый элемент → `ParseError {line, column, message_key}`, частичный план не возвращается. Фикстуры `tests/fixtures/intervals/workout_*.json`.
Закрывает: REQ-INT-03 п.1–9; REQ-NFR-09 п.3 (Intervals). Критерии авто: все. Ручных нет.

#### T-036 — Кэш плана и работа без сети `[integration]`
Что сделать. `src/integrations/intervals/plan_cache.gd`: после успешной загрузки — план + `loaded_at` + дата в `user://profiles/<id>/plan_cache.json`; при ошибке сети — кэш на сегодняшнюю дату с пометкой «из кэша, загружен <время>»; кэш другой даты не предлагается; запуск/пауза/завершение по кэшированному плану — 0 запросов в моке (включая проверки токенов). Прогон сценария NFR-03 с `MockHttpTransport.offline = true` до сохранения заезда (сохранение появится в T-041 — критерий NFR-03.1 «сохранение» подтверждается повторно после T-041).
Закрывает: REQ-INT-07 п.1–4; REQ-NFR-03 п.1, 2. Критерии авто: все. Ручные: REQ-NFR-03 п.4.

#### T-037 — Парсер ZWO `[integration]`
Что сделать. `src/integrations/import/zwo_parser.gd` на `XMLParser`: `Warmup`/`Cooldown`/`Ramp` → рампа `PowerLow→PowerHigh`; `SteadyState` → постоянная; `IntervalsT` → `Repeat` × (on/off); `FreeRide` → `Target.NONE`; доли FTP → %; `Cadence`, `CadenceLow/High` (середина) → каденс; `textevent` → `WorkoutCue(offset, message)`; `name/description/author` → метаданные; невалидный XML и неизвестный элемент (`MaxEffort`, `SolidState`) → `ImportError` с именем элемента и номером строки. Фикстуры `tests/fixtures/zwo/*.zwo` с ожидаемыми длительностями и числом шагов (tester).
Закрывает: REQ-IMP-01 п.1–7; REQ-NFR-09 п.3 (ZWO); основа REQ-IMP-05 п.2. Критерии авто: все. Ручных нет.

#### T-038 — Парсер .erg/.mrc `[integration]`
Что сделать. `src/integrations/import/erg_parser.gd`: секции `[COURSE HEADER]`/`[COURSE DATA]`/`[COURSE TEXT]`; пары «минуты значение» → шаги (равные значения — постоянный, разные — рампа); `.erg` — ватты, `.mrc` — % FTP по расширению; дробные минуты (2.5 → 150 с); `FTP` заголовка → `metadata`, не в профиль; `[COURSE TEXT]` → подсказки; нет `[COURSE DATA]` или немонотонное время → `ImportError`. Фикстуры `tests/fixtures/erg/`.
Закрывает: REQ-IMP-02 п.1–6; REQ-NFR-09 п.3 (erg/mrc). Критерии авто: все. Ручных нет.

#### T-039 — Точка входа импорта, ошибки, библиотека `[integration]`
Что сделать. `src/integrations/import/workout_importer.gd`: `import_file(path) -> Result` — выбор парсера по расширению без учёта регистра, иное → ошибка; `src/integrations/import/import_error.gd` — `{file_name, kind, element, line, message_key}` и `to_user_message(tr)` без стека и внутренних имён классов; ошибки не вызывают ошибок движка. `src/profiles/workout_library.gd`: записи `{id, name, duration_s, source_file, imported_at, workout}` в данных профиля; библиотека A не видна в B; повторный импорт — отдельная запись; удаление не трогает заезды; запуск из библиотеки создаёт тот же `WorkoutSession`.
Закрывает: REQ-IMP-03 п.1; REQ-IMP-05 п.1–4; REQ-IMP-04 п.1–5. Критерии авто: все. Ручные: REQ-IMP-03 п.2 (диалог — вызывается из T-040). Вне контейнера: REQ-IMP-03 п.3, 4.

#### T-040 — Экран выбора тренировки и предпросмотра `[game]`
Что сделать. `src/ui/workout_picker.tscn/.gd`: источники — план на сегодня (Intervals или кэш с пометкой) и библиотека (пометка источника); одна тренировка → сразу карточка без списка; две и более → список (название, длительность `мм:сс`/`ч:мм:сс`, нагрузка если есть); кнопка «Импортировать файл» → `FileDialog` с фильтром `*.zwo, *.erg, *.mrc`. `src/ui/workout_preview.tscn/.gd`: график по `WorkoutProfile.points` с окраской сегментов по зонам, ось времени в минутах, кнопка «Старт». Модель списка (`src/ui/workout_picker_model.gd`) проверяется headless.
Закрывает: REQ-INT-04 п.1–3; REQ-INT-05 п.1–3 (отображение). Критерии авто: модель списка/выбора. Ручные: REQ-INT-04 п.4, REQ-INT-05 п.4, REQ-IMP-03 п.2.

### Этап 5 — Хранилище. Результат: заезды сохраняются и экспортируются

#### T-041 — `RideRepository` `[integration]`
Что сделать. `src/storage/ride.gd` — `Ride {id, profile_id, started_at, workout_name, workout_source, ftp, weight_kg, intensity_pct, ended_early, samples: Array[Sample], events, strava_status, strava_activity_id, strava_error}`. `src/storage/ride_repository.gd` — интерфейс `save(ride)`, `get_ride(id)`, `list(profile_id) -> Array[RideSummary]` (по дате убыв.), `delete(id)`, `list` для 500 заездов ≤ 1 с. Реализация `src/storage/file_ride_repository.gd`: один файл на заезд в `user://profiles/<id>/rides/<ride_id>.ride` (метаданные JSON + сэмплы `PackedByteArray` через `FileAccess.store_var`) и индекс `rides_index.json` для быстрого списка. SQLite — см. вопрос В-3; интерфейс позволяет заменить реализацию. Хук удаления профиля — удалить его заезды.
Закрывает: REQ-LOC-01 п.1–4; REQ-PRF-04 п.1. Критерии авто: все. Ручных нет.

#### T-042 — Потоковая запись и восстановление `[integration]`
Что сделать. `src/storage/ride_writer.gd`: подписан на `SampleRecorder`; сброс накопленных сэмплов в файл заезда не реже чем раз в 10 с сессионного времени, дозапись (append) без перезаписи; тик ≤ 50 мс при 600 сэмплах (запись маленьких порций, без сериализации всего заезда); маркер `in_progress`. `RideRepository.find_unfinished(profile_id)` — при старте приложения предлагается «сохранить как завершённый досрочно» или «удалить» (модель решения в `src/ui/recovery_prompt_model.gd`, диалог — минимальный). Тест сбоя: прервать сессию, создать новый экземпляр репозитория, проверить потерю ≤ 10 с.
Закрывает: REQ-LOC-07 п.1–4. Критерии авто: все. Ручные: REQ-LOC-07 п.5.

#### T-043 — Сводка заезда и серии для графиков `[game]`
Что сделать. `src/domain/ride_summary.gd`: средняя мощность (нули учитываются, `NO_DATA` — нет), NP (скользящее 30 с → ^4 → среднее → корень 4-й степени; 200 Вт 10 мин → 200; NP ≥ средней), работа кДж (200 Вт × 3600 с → 720), средний пульс/каденс, время в 7 зонах мощности и 5 зонах пульса по зонам на момент заезда (сумма = число сэмплов с данными), «—» без пульса. `src/domain/ride_series.gd`: серии (t, значение) без `NO_DATA`; прореживание до ≤ 3600 точек с сохранением min/max (LTTB или min-max по корзинам); серия целевой мощности плана.
Закрывает: REQ-LOC-04 п.1–6; REQ-LOC-03 п.1–3. Критерии авто: все. Ручные: REQ-LOC-03 п.4.

#### T-044 — Кодировщик FIT `[integration]`
Что сделать. `src/integrations/fit/fit_encoder.gd` (+ `fit_crc.gd`, `fit_definitions.gd`): заголовок 14 байт с сигнатурой `.FIT` и CRC заголовка; сообщения `file_id` (type=activity), `record` на каждый сэмпл (`timestamp`, `power`, `heart_rate`, `cadence`, `speed`, `distance`), `event` start/stop (в т.ч. паузы), `lap` на каждый шаг, `session` (`sport=2`, `sub_sport=58`, `total_elapsed_time`, `total_timer_time` без пауз, `avg_power`, `normalized_power`, `total_work`), `activity`; отсутствующие значения — invalid по спецификации (0xFF/0xFFFF/…), не 0; CRC-16 файла. `encode(ride, summary) -> PackedByteArray`. Декодер для проверок пишет tester в `tests/`.
Закрывает: REQ-LOC-05 п.1–4; REQ-STR-02 п.2; REQ-NFR-09 п.1 (FIT). Критерии авто: все. Ручные: REQ-LOC-05 п.5.

#### T-045 — Экраны истории `[game]`
Что сделать. `src/ui/history_list.tscn/.gd` (дата, название, длительность, средняя мощность, статус Strava), `src/ui/ride_detail.tscn/.gd` (графики мощности с целью, пульса, каденса по сериям T-043; сводка; кнопки «Экспорт FIT» → `FileDialog` сохранения с именем `<дата>_<название>.fit`, «Удалить» с подтверждением, «Выгрузить в Strava» — активируется в T-049). Удаление: заезд и сэмплы отсутствуют в репозитории, элемент очереди Strava удаляется (хук для T-048), запросов на удаление активности нет.
Закрывает: REQ-LOC-02 п.1, 2; REQ-LOC-06 п.1, 2; REQ-LOC-05 п.6 (вызов диалога). Критерии авто: модель списка, удаление. Ручные: REQ-LOC-02 п.3, REQ-LOC-06 п.4, REQ-LOC-05 п.6.

### Этап 6 — Strava. Результат: цикл замкнут

#### T-046 — Strava OAuth 2.0 `[integration]`
Что сделать. `src/integrations/strava/strava_auth.gd`: `authorization_url(client_id, redirect_uri)` с `response_type=code`, `scope=activity:write,read`; `exchange_code(code)` — POST `grant_type=authorization_code`, сохранение `access_token`, `refresh_token`, `expires_at` в `SecureStore` профиля; `ensure_fresh_token()` — если до `expires_at` < 60 с → `grant_type=refresh_token`; 401 на API → одно обновление и повтор, повторный 401 → `REAUTH_REQUIRED`; `disconnect()` → удаление токенов; `client_id`/`client_secret` — из `user://strava_app.cfg` или переменных окружения, в репозитории только `strava_app.example.cfg` с плейсхолдерами; секрет не логируется. Приём redirect на macOS — локальный `TCPServer` на `127.0.0.1:<порт>` или custom URL scheme (решение — В-6).
Закрывает: REQ-STR-01 п.1–6; REQ-PRF-03 п.1–3 и REQ-NFR-05 п.1, 2 (окончательно). Критерии авто: все. Ручные: REQ-STR-01 п.8. Вне контейнера: REQ-STR-01 п.7, REQ-PRF-03 п.4.

#### T-047 — Выгрузка в Strava `[integration]`
Что сделать. `src/integrations/strava/strava_uploader.gd`: `upload(ride) -> UploadResult` — multipart с `file` (FIT из T-044), `data_type=fit`, `external_id=<ride_id>`, `name`, `description`, `trainer=1`; 201 с `id` → `PROCESSING`; `poll_status(upload_id)` до `activity_id` → `UPLOADED` или `error` → `FAILED(text)`; ошибка с «duplicate» → `DUPLICATE` без повторов. Название: план или «Тренировка <дата>» (ключ перевода); описание: описание плана + строка с названием приложения; пользовательские правки `name/description` до выгрузки — параметры `upload`.
Закрывает: REQ-STR-02 п.1, 3, 4; REQ-STR-03 п.1–3. Критерии авто: все. Ручные: REQ-STR-02 п.5, REQ-STR-03 п.4.

#### T-048 — Очередь выгрузки и статусы `[integration]`
Что сделать. `src/integrations/strava/upload_queue.gd`: элемент очереди создаётся по завершении заезда в профиле с привязкой; хранится в `user://profiles/<id>/strava_queue.json`; повторы при сетевой ошибке/5xx через 1, 5, 15, 60 мин, далее каждые 60 мин (подменяемые часы); 429 → не раньше `Retry-After`; не более одной выгрузки одновременно, порядок по дате заезда; `enqueue_now(ride_id)` для ручной выгрузки; очередь не работает во время активной сессии. Статусы заезда `NOT_UPLOADED | QUEUED | PROCESSING | UPLOADED(activity_id) | FAILED(text) | DUPLICATE` пишутся в `RideRepository`; ссылка `https://www.strava.com/activities/<id>`. Удаление заезда удаляет элемент очереди.
Закрывает: REQ-STR-04 п.1–6; REQ-STR-05 п.1–3; REQ-LOC-06 п.3; REQ-NFR-03 п.3. Критерии авто: все. Ручные: REQ-STR-05 п.4.

#### T-049 — Экран привязок и действия Strava в истории `[game]`
Что сделать. `src/ui/accounts_screen.tscn/.gd`: ввод Athlete ID и API-ключа Intervals.icu с проверкой (T-033), отображение имени атлета, источник FTP («из Intervals.icu (дата)» / «локально») и переключатель «переопределить локально»; кнопка «Connect with Strava» (ассет и размеры по брендбуку, логотип «Powered by Strava»), статус привязки, «Отвязать». В `ride_detail`: «Выгрузить в Strava» для заездов не в статусе «выгружено», редактирование названия/описания перед выгрузкой, статус и ссылка на активность.
Закрывает: UI-части REQ-STR-04 п.5, REQ-STR-03 п.3, REQ-STR-05 п.2, REQ-INT-06 п.4. Критерии авто: модель экрана (headless). Ручные: REQ-INT-01 п.4, REQ-INT-06 п.4, REQ-STR-01 п.8, REQ-STR-05 п.4.

### Этап 7 — 3D-сцена. Результат: MVP готов

#### T-050 — Модель скорости `[game]`
Что сделать. `src/domain/speed_model.gd`: `steady_speed_kmh(power_w, rider_kg)` — ровная дорога, CdA 0.32, Crr 0.004, велосипед 8 кг, ρ 1.225 (200 Вт/75 кг → 34 ± 3; 100 Вт → 26 ± 3; 300 Вт → 40 ± 3; 95 кг — меньше); `step(current_kmh, power_w, rider_kg, dt_s)` — инерционное приближение к установившейся: при 0 Вт с 30 км/ч до 0 за ≤ 30 с, изменение за сэмпл ≤ 5 км/ч при скачке 0 → 400 Вт. Используется как альтернативный источник скорости для WRK-08.5 при решении владельца.
Закрывает: REQ-D3D-02 п.1–4; REQ-WRK-08 п.5 (альтернатива). Критерии авто: все. Ручные: REQ-D3D-02 п.5.

#### T-051 — Интерфейс трассы и зацикленная трасса `[game]`
Что сделать. `src/scene3d/track.gd` — интерфейс `Track`: `transform_at(s_m: float) -> Transform3D`, `length_m()`, `wrap(s_m)`; `src/scene3d/loop_track.gd` — замкнутая петля из сегментов с ограниченным числом активных секций (`MAX_ACTIVE_SEGMENTS`), 80 км непрерывного движения без «конца»; `src/scene3d/environment_loop.tscn` — простое окружение; `src/scene3d/rider_mover.gd` — переводит скорость (км/ч) в `s_m` и ставит велосипедиста по `Track.transform_at`, не зная конкретной сцены. `tests/` получат `TestTrack` (прямая) от tester. `docs/scene3d.md` — абзац и схема интерфейсов `Track` / `RiderMover` / телеметрия.
Закрывает: REQ-D3D-03 п.1, 2; REQ-D3D-06 п.1–3. Критерии авто: все. Ручные: REQ-D3D-03 п.3.

#### T-052 — Велосипедист, камера, педалирование, бюджет производительности `[game]`
Что сделать. `src/scene3d/ride_scene.tscn` с узлами `Rider` (простая модель/капсула + шатуны), `Road`, `FollowCamera` (постоянное расстояние и высота ±0.1 м, велосипедист в frustum при 0–60 км/ч); `src/scene3d/pedal_animator.gd` — скорость анимации = каденс/60 об/с (90 → 1.5; 60 → 1.0), 0/`NO_DATA` → остановка, применение не позже следующего сэмпла. `project.godot`: `physics/common/physics_ticks_per_second` ≥ 60, `application/run/max_fps` = 0 или ≥ 60. `docs/perf_budget.md` — бюджет draw calls и способ замера (см. В-7); замер через `RenderingServer.get_rendering_info` в тесте.
Закрывает: REQ-D3D-01 п.1, 2; REQ-D3D-04 п.1–3; REQ-D3D-05 п.2, 3. Критерии авто: все перечисленные. Ручные: REQ-D3D-01 п.3, REQ-D3D-04 п.4, REQ-D3D-05 п.1.

### Этап 8 — Публикация iOS и macOS (в контейнере — документы и заготовки)

#### T-053 — Пакет публикации iOS/macOS `[docs]`
Что сделать. `docs/privacy_policy.md` (какие данные: пульс как данные о здоровье, мощность, каденс; где хранятся; куда передаются — Intervals.icu, Strava; как удалить); `docs/store/app_store_checklist.md` (Privacy Nutrition Labels, данные о здоровье, лицензии: Godot MIT, GUT MIT, godot-cpp MIT, прочие); `docs/store/google_play_checklist.md` (Data Safety — заготовка, дополняется в T-055); `docs/store/file_types.md` и заготовка `export_presets.cfg` для macOS и iOS с `NSBluetoothAlwaysUsageDescription` (ru и en, непустые), типами документов `.zwo`, `.erg`, `.mrc`; `docs/intervals_oauth.md` (шаги согласования, redirect URI, scope); `docs/store/strava_review.md` (брендбук кнопки/логотипа, заявка на ревью, лимит одного атлета до ревью); `docs/secure_store.md` (Keychain, Android Keystore, libsecret/Credential Manager — границы платформенной части).
Закрывает: REQ-NFR-07 п.1, 2, 4; REQ-IMP-03 п.3; REQ-INT-01 п.5; REQ-STR-01 п.7; REQ-NFR-05 п.3 — наличие файлов и разделов `[авто]`, остальное `[вне контейнера]`. Критерии авто: существование файлов/разделов, непустые строки описания BLE в пресете.

#### T-054 — Локализация ru/en `[game]`
Что сделать. Довести `assets/i18n/translations.csv` до полноты: каждый ключ с непустыми `ru` и `en`; аудит `src/ui/` и `src/scene3d/` на кириллицу в литералах (скрипт `scripts/check_i18n.sh`); `src/ui/locale_settings.gd` — язык по умолчанию системный, если ru/en, иначе en; переключение в настройках с сохранением (`user://settings.json`); единые форматы (`мм:сс`, точка как десятичный разделитель) — проверка на моделях T-029.
Закрывает: REQ-NFR-08 п.1–4. Критерии авто: все. Ручные: REQ-NFR-08 п.5.

### Этапы 9–10 — Android, Linux и Windows (в контейнере — документы и заготовки)

#### T-055 — Порты BLE и Android-заготовки `[docs]`
Что сделать. `docs/ble_port_checklist.md`: для Android (JNI, `BluetoothLeScanner`, `BluetoothGatt`), Linux (BlueZ D-Bus: `org.bluez.Adapter1`, `Device1`, `GattCharacteristic1`), Windows (WinRT `BluetoothLEAdvertisementWatcher`, `GattCharacteristic`) — точки реализации каждого метода и события контракта `BleBridge`, маршалинг событий в главный поток, различия в разрешениях; `native/ble/platform/android/AndroidManifest.xml.template` с `BLUETOOTH_SCAN` (`android:usesPermissionFlags="neverForLocation"`), `BLUETOOTH_CONNECT`, legacy `BLUETOOTH`, `BLUETOOTH_ADMIN`, `ACCESS_FINE_LOCATION` с `maxSdkVersion="30"`; дополнение `docs/store/google_play_checklist.md` (Data Safety, данные о здоровье); раздел «Каналы распространения Linux/Windows — открытый вопрос» с вариантами (Steam, Flathub, Microsoft Store, прямая загрузка) и критериями выбора.
Закрывает: REQ-NFR-06 п.4; REQ-NFR-07 п.3, 4 (Android). Критерии авто: наличие файлов и разрешений. Вне контейнера: порты, ревью Google Play.

## 4. Ручные проверки владельца

Критерии, которые нельзя закрыть в контейнере. Tester не отмечает их пройденными; владелец проверяет на реальном Tacx Neo, датчиках, macOS и реальных аккаунтах. Группировка — по моменту, когда проверка становится возможной.

### После сборки GDExtension на macOS (T-021, T-022) — `[вне контейнера]`
- REQ-DEV-01 п.6 — GDExtension собирается для macOS и iOS.
- REQ-PRF-03 п.4, REQ-NFR-05 п.3 — реализация Keychain хранит значение после перезапуска (после `docs/secure_store.md`).

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

Вопросы агенту requirements:
- В-1. REQ-PRF-02 п.1 перечисляет поля профиля (FTP, вес, границы зон), но зоны пульса по п.3 считаются «от максимального пульса профиля», а поле максимального пульса и его диапазон валидации в требованиях не заданы. Нужно добавить поле `max_hr` с диапазоном (предложение: 100–230, по умолчанию 190) или задать зоны пульса в абсолютных уд/мин.
- В-2. Контракт нативного моста (раздел DEV) содержит `subscribe` и `write`, но не содержит операции чтения характеристики, а REQ-DEV-07 п.2 (Battery Level) и REQ-WRK-04 п.2 (Supported Resistance Level Range `0x2AD6`) требуют именно чтения. Предлагаю дополнить контракт `read(device_id, char_uuid)` с ответом через событие `value(id, char_uuid, bytes)`. В бэклоге (T-015, T-021, T-022) заложено так.
- В-3. ТЗ (раздел 4) называет локальную БД SQLite; в Godot 4.7 нет встроенного SQLite, нужен сторонний GDExtension (`godot-sqlite`) с бинарниками под каждую платформу, включая macOS/iOS, которые в контейнере не собрать. Требования LOC формулируют «БД профиля» нейтрально. Предлагаю зафиксировать: MVP — файловое хранилище за интерфейсом `RideRepository` (T-041), SQLite — замена реализации позже без изменения требований. Нужно подтверждение, что это не противоречит ТЗ.
- В-4. REQ-WRK-05 п.5 ссылается на «выбранное решение» по поведению станка на паузе (открытое решение 10), но для разработки T-027 нужно значение по умолчанию. Предлагаю «на паузе ничего не отправлять, цель сохраняется», до решения владельца.
- В-5. REQ-INT-06 п.1 — «границы зон мощности» из Intervals.icu: в ответе API зоны могут быть заданы в ваттах, а профиль хранит их в % FTP; правило преобразования и обработка несовпадения числа зон (не 7) не заданы. Зоны пульса из Intervals.icu не упомянуты вовсе — нужно ли их синхронизировать?
- В-6. REQ-STR-01: обмен кода на токен в Strava требует `client_secret`; п.5 запрещает хранить его в репозитории, но не говорит, где он живёт в собранном приложении для магазина (внутри бинарника или через серверный прокси). Для MVP на macOS достаточно локального конфига вне репозитория (так и заложено в T-046), но для этапа 8 нужно решение. Также не задан способ приёма redirect на десктопе (локальный порт или custom URL scheme).
- В-7. REQ-D3D-05 п.3 — замер draw calls «в headless-замере»: в headless-режиме `RenderingServer` не выполняет отрисовку и `get_rendering_info` может возвращать 0, тогда тест будет вырожденным. Нужно либо уточнить критерий (например, подсчёт `MeshInstance3D`/материалов в сцене как прокси), либо перевести п.3 в `[ручная проверка]`.
- В-8. REQ-WRK-08 п.5 — источник скорости (открытое решение 14). До решения используется скорость станка; `SpeedModel` (T-050) готов как альтернатива. Просьба закрепить решение до этапа 5, так как от него зависит содержимое FIT (LOC-05) и Strava (STR-02).
- В-9. REQ-INF-03 п.1 — проверка `git log` в CI требует полной истории (`fetch-depth: 0` в `actions/checkout`); текущий `ci.yml` делает shallow clone. Правка заложена в T-014; просьба подтвердить, что это допустимо в рамках INF-02.

## 6. Трассируемость REQ → задачи

| REQ | Задачи |
| --- | --- |
| INF-01, INF-02 | T-001 |
| INF-03, INF-04 | T-014 |
| PRF-01 | T-009, T-011 |
| PRF-02 | T-008, T-009 |
| PRF-03 | T-010, T-046 |
| PRF-04 | T-011, T-041 |
| PRF-05 | T-012 |
| INT-01 | T-033 (ключ), T-053 (OAuth-документ) |
| INT-02 | T-034 |
| INT-03 | T-035 |
| INT-04 | T-040 |
| INT-05 | T-030, T-040 |
| INT-06 | T-033, T-049 |
| INT-07 | T-036 |
| IMP-01 | T-037 |
| IMP-02 | T-038 |
| IMP-03 | T-039, T-040, T-053 |
| IMP-04, IMP-05 | T-039 |
| STR-01 | T-046, T-053 |
| STR-02 | T-044, T-047 |
| STR-03 | T-047, T-049 |
| STR-04 | T-048, T-049 |
| STR-05 | T-048, T-049 |
| DEV-01 | T-019, T-021, T-022 |
| DEV-02 | T-016, T-017, T-022 |
| DEV-03, DEV-04, DEV-05 | T-016, T-018 |
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
| HUD-02, HUD-03, HUD-04, HUD-09 | T-028 |
| HUD-05, HUD-06, HUD-08 | T-029 |
| HUD-07 | T-030 |
| D3D-01, D3D-04, D3D-05 | T-052 |
| D3D-02 | T-050 |
| D3D-03, D3D-06 | T-051 |
| LOC-01 | T-041 |
| LOC-02 | T-045 |
| LOC-03, LOC-04 | T-043 |
| LOC-05 | T-044, T-045 |
| LOC-06 | T-045, T-048 |
| LOC-07 | T-042 |
| NFR-01 | T-025 |
| NFR-02 | T-006, T-013, T-023 |
| NFR-03 | T-032, T-036, T-048 |
| NFR-04 | T-027 |
| NFR-05 | T-010, T-046, T-053 |
| NFR-06 | T-002, T-014, T-015, T-021, T-055 |
| NFR-07 | T-053, T-055 |
| NFR-08 | T-012, T-054 |
| NFR-09 | T-005, T-006, T-014, T-035, T-037, T-038, T-044 |
