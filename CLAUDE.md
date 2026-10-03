# ovosch-rider — правила для агентов

Стек: Godot 4.7 (GDScript, статическая типизация), GUT 9.7.1 для тестов, GDExtension для BLE.
Язык документов и комментариев — русский. Имена в коде — английские.

## Команды
- Тесты: `./scripts/test.sh` (нужен Godot 4.7; локально бинарник `/opt/godot/godot`, в CI качается сам).
- Проверка, что проект открывается: `godot --headless --path . --import`.
- Один тестовый файл: `./scripts/test.sh -gselect=test_x` (фильтр по имени файла; `-gtest=` не ограничивает запуск, т.к. каталоги заданы в `.gutconfig.json`).
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
- `docs/tz.md` — ТЗ владельца (не менять). `docs/requirements.md` — требования с критериями. `docs/backlog.md` — задачи.
- `docs/game/` — дизайн-документ, арт-библия, реестр ассетов, эталонные снимки (ведёт game-designer).

## Агенты и скиллы
- `.claude/agents/`: requirements (критерии), manager (бэклог), game-designer (мир, игровой UI, стиль — без кода), developer (`[game]`, `[integration]`, `[native-ble]`), technical-artist (`[visual]` — 3D-мир), tester (приёмка).
- `.claude/skills/`: `ride-visual-review` (снимки + чек-лист кадра), `indoor-cycling-game-design` (предметная база геймдизайна).

## Правила
- Доменная логика не зависит от цикла отрисовки и от сцен: тестируется headless без `SceneTree`-зависимостей, где возможно.
- Секреты — никогда в репозитории. Токены — через модуль защищённого хранилища (`src/storage/secure_store.gd`), платформенная часть изолирована.
- Каждая задача закрывается отдельным коммитом с REQ-ID в сообщении. Тесты обязательны.
- Godot пишет `*.uid` рядом с каждым `.gd` — коммитить их вместе с кодом.
- В `RefCounted`-классах подписывайся на сигналы только связанными методами (`obj.signal.connect(_on_x)`), не лямбдами: лямбда захватывает `self` сильной ссылкой и образует цикл объект → сигнал → лямбда → объект (утечка). Для отключения — `dispose()`.
