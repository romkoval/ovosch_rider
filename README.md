# ovosch-rider

Кроссплатформенное приложение для тренировок на умном велостанке (Tacx Neo по BLE/FTMS):
план на сегодня из Intervals.icu или из файлов ZWO/.erg/.mrc, ERG-режим, HUD с зонами,
3D-визуал, локальная история, выгрузка в Strava.

Стек: Godot 4.7, GDScript, нативный BLE через GDExtension.

## Документы
- `docs/tz.md` — исходное ТЗ владельца продукта.
- `docs/requirements.md` — требования с ID и критериями приёмки (источник правды).
- `docs/backlog.md` — задачи, статусы, зависимости.

## Разработка
```bash
# тесты (нужен Godot 4.7 в PATH или GODOT=/path/to/godot)
./scripts/test.sh
```
Тесты — GUT (`addons/gut`), лежат в `tests/`. CI — GitHub Actions (`.github/workflows/ci.yml`).
