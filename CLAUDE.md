# ovosch-rider — правила для агентов

Стек: Godot 4.7 (GDScript, статическая типизация), GUT 9.7.1 для тестов, GDExtension для BLE.
Language (owner's decision 2026-10-10):
- English: code, code comments, test names and assertion messages, commit messages, agent reasoning and agent reports, and every **new** entry in working docs (`docs/requirements.md`, `docs/backlog.md`, `docs/tasks/`, `docs/game/`, `docs/agent-state.md`).
- Russian: messages to the owner and the user story map (`docs/story-map.md`). User-facing UI text stays localized via `assets/i18n` (ru/en).
- Existing Russian text is not translated wholesale: translate a comment or doc passage only when you are changing that spot anyway.

## Команды
- Тесты: `./scripts/test.sh` (нужен Godot 4.7; локально бинарник `/opt/godot/godot`, в CI качается сам).
- Проверка, что проект открывается: `godot --headless --path . --import`.
- Один тестовый файл: `./scripts/test.sh -gselect=test_x` (фильтр по имени файла; `-gtest=` не ограничивает запуск, т.к. каталоги заданы в `.gutconfig.json`).
- Прицельный прогон: `./scripts/test_changed.sh [база]` — одним запуском тесты, затронутые изменениями от базы (по умолчанию merge-base с `origin/main`): изменённые тесты, тесты со ссылкой на изменённый файл или его `class_name`, все `tests/unit/arch`. `--list` — показать набор.
- Снимки 3D-сцены заезда: `./scripts/screenshot.sh [каталог] [км/ч] [каденс] [дистанции]` (без дисплея — через `xvfb-run`, рендер gl_compatibility). Любая визуальная правка сдаётся со снимками «до/после» (скилл `ride-visual-review`).

## Структура
- `src/domain/` — модель тренировки, исполнитель интервалов, зоны, расчёты. Без Node, без сцен, чистый GDScript (RefCounted).
- `src/devices/` — `TrainerDevice` (интерфейс), `FakeTrainer`, `BleTrainer`, датчики, `ble/` (контракт моста `BleBridge`, заглушка, кодеки). Только здесь известно, какая реализация подключена.
- `src/session/` — `WorkoutSession`, `SampleStream`: связка исполнителя с `TrainerDevice`, поток 1 Гц. Единственный слой, который знает и домен, и интерфейс устройства (не реализацию).
- `src/integrations/` — Intervals.icu, Strava, парсеры ZWO/.erg/.mrc, FIT.
- `src/app/` — оболочка: `AppState` (навигация, правило старта), `main.tscn` (корневая сцена), `locale.gd`.
- `src/profiles/`, `src/storage/`, `src/ui/`, `src/scene3d/`.
- `native/ble/` — GDExtension (C++/Objective-C++). Только задачи `[native-ble]`.
- `tests/unit/`, `tests/integration/`, `tests/fixtures/` — GUT. Файлы `test_*.gd`, `extends GutTest`.
- `docs/tz.md` — ТЗ владельца (не менять). `docs/requirements.md` — требования с критериями. `docs/backlog.md` — индекс задач (таблица: статус, приоритет, зависимости). `docs/tasks/<ID>.md` — описание задачи: что сделать, критерии приёмки, история, вердикты (шаблон `docs/tasks/_template.md`).
- `docs/game/` — дизайн-документ, арт-библия, реестр ассетов, эталонные снимки (ведёт game-designer).

## Агенты и скиллы
- `.claude/agents/`: requirements (критерии), manager (бэклог), game-designer (мир, игровой UI, стиль — без кода), developer (`[game]`, `[integration]`, `[native-ble]`), technical-artist (`[visual]` — 3D-мир), tester (приёмка).
- `.claude/skills/`: свои — `ride-visual-review` (снимки + чек-лист кадра), `indoor-cycling-game-design` (предметная база геймдизайна); сторонние (MIT/Apache-2.0, без правок) — список, источники и лицензии в `.claude/skills/THIRD_PARTY/README.md`.

## Прогоны тестов
Полный `./scripts/test.sh` идёт ~15 минут, а при параллельных прогонах — дольше; это почти половина времени агентов. Поэтому:
- Во время работы и перед промежуточными коммитами — только `./scripts/test_changed.sh` и `-gselect`.
- Полный прогон — **один на сдачу**: developer и technical-artist — на последнем коммите сдаваемой пачки (несколько задач подряд — один прогон в конце); tester — один в конце приёмки, на коммите со своими тестами, который пойдёт в `main`. Нашёл дефект — полный не нужен до исправления.
- В отчёте — хэш коммита, на котором был полный прогон, и строка итога. Этот прогон переиспользуется: координатор при слиянии полный не повторяет, если код (всё вне `docs/`) сливаемого дерева совпадает с деревом зелёного полного прогона; иначе достаточно `./scripts/test_changed.sh <коммит прогона>`, а полный — только когда слияние смешало код двух веток, не прогнанных вместе.
- Правки только `docs/` — `./scripts/test_changed.sh` (в набор входят тесты бэклога и трассируемости).
- Два полных прогона одновременно на одной машине не запускать без нужды: они тормозят друг друга. CI гоняет полный набор на каждый пуш — это страховка.

## Правила
- Доменная логика не зависит от цикла отрисовки и от сцен: тестируется headless без `SceneTree`-зависимостей, где возможно.
- Секреты — никогда в репозитории. Токены — через модуль защищённого хранилища (`src/storage/secure_store.gd`), платформенная часть изолирована.
- Каждая задача закрывается отдельным коммитом с REQ-ID в сообщении. Тесты обязательны.
- Задачи: работаешь по файлу `docs/tasks/<ID>.md` своей задачи, весь `docs/backlog.md` не читаешь. Статус, приоритет и очередь — только в таблице `docs/backlog.md` (раздел 2), в файле задачи статус не пишется. Новая задача = строка в таблице + файл задачи в одном коммите; расхождение ловит `tests/unit/arch/test_backlog_tasks.gd`.
- Godot пишет `*.uid` рядом с каждым `.gd` — коммитить их вместе с кодом.
- В `RefCounted`-классах подписывайся на сигналы только связанными методами (`obj.signal.connect(_on_x)`), не лямбдами: лямбда захватывает `self` сильной ссылкой и образует цикл объект → сигнал → лямбда → объект (утечка). Для отключения — `dispose()`.
