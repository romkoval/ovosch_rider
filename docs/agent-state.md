# Состояние цикла оркестрации

Файл ведёт менеджер. Это единственная «память» между циклами: следующий цикл
начинается с чтения этого файла, `docs/backlog.md` и нужных записей
`docs/requirements.md`, а не с истории диалога.

## Текущий цикл

Дата: 2026-10-03. Ветка `claude/festive-mayer-w41i04`. Последний коммит: 99f1b1e. Решения В-16, В-17 внесены в requirements.

Этапы 0–4 — `done` (приёмка закоммичена). Этапы 5–7 — код закоммичен (59f1fe1, ce85da4, 65715d4), идёт приёмка и доводка экранов. Этапы 8–10 — документы закоммичены (7319347), ждут приёмки.

### Задачи в работе (незакоммиченный WIP в дереве)

| Задача | Роль | Зона файлов | Состояние |
|---|---|---|---|
| T-057 экран настроек | tester (приёмка, `test_settings_acceptance`) | `src/ui/settings/`, `src/app/app_settings.gd`, `src/ui/common/intervals_key_dialog.*`, `src/profiles/profile.gd` (power_source, set_*_local), тесты `test_settings_screen`, `test_app_settings`, `test_profile_sources` | разработчик сдал (23/23); идёт приёмка |
| T-049 StravaService + UI | developer | `src/integrations/strava/strava_service.gd`, `ride_repository_upload_store.gd`, `src/ui/common/strava_connect_button.*`, `secure_store.read_env`, `ride_repository.ride_saved`, `profile.strava_auto_upload`, тесты `test_strava_service`, `test_strava_connect_button` | разработчик сдал (20/20); ядро поправлено по 3 дефектам; 2 спорных ассерта у tester |
| T-040 план + D-8 | developer | `src/ui/plan/`, `test_plan_screen`, `src/scene3d/ride_scene.gd`, `test_ride_scene` | проверка полноты по критериям |
| T-043/T-045 история | developer | `src/storage/ride_series.gd`, `src/ui/history/`, правки `file_ride_repository`, `ride_recorder`, `ride_summary`, тесты `test_history_screen`, `test_ride_series` | проверка полноты по критериям |
| Приёмка оболочки (D-8 и docs закоммичены fb015a2, 99f1b1e) | tester | `test_app_shell_acceptance`, `test_profile_select_screen` (устаревшие ожидания заглушек), `test_scene3d_acceptance`, новый `test_publishing_docs_acceptance` | сдано: `test_app_shell_acceptance` 22/22, `test_profile_select_screen` 15/15 — коммит вместе с экранами |
| Приёмка T-046..T-048 | tester | `tests/unit/integrations/strava/test_strava_acceptance.gd` | в работе, 4 дефекта переданы developer |
| Приёмка T-041/T-042/T-044 | tester | `test_storage_acceptance`, `test_fit_acceptance` | сдано: 44/45 и 15/16; дефекты Д-1, Д-2, Н-2 → developer E (`fit_encoder`, `workout_session`) |

### Общие файлы с параллельными правками
`src/app/main.gd`, `src/app/app_state.gd`, `assets/i18n/strings.csv` (+ `.translation`), `src/profiles/profile.gd`, `src/storage/ride_repository.gd`. Коммитить по задачам, стадируя только строки своей задачи (`git add -p`), либо одним коммитом с перечислением REQ-ID, если разделить невозможно.

### Правило коммита
Задача коммитится после отчёта tester о зелёной приёмке; разработческий код может быть закоммичен раньше со статусом `review` в бэклоге. Полный прогон `./scripts/test.sh` перед каждым коммитом; CI на каждом push.

### Открытые решения для владельца
В-1..В-15, Н-1..Н-5, Н-9, Н-11, Н-12 — см. `docs/requirements.md` и `docs/backlog.md`.

### Следующие шаги после закрытия WIP
1. T-054 — финальная инвентаризация локализации (после T-040, T-045, T-049, T-057).
2. Закрытие статусов в бэклоге (manager), итоговая сводка владельцу.
