# Сторонние скиллы

Скиллы в `.claude/skills/` взяты из открытых наборов как есть (без правок текста), чтобы
агенты получали проверенные приёмы Godot 4.x и геймдизайна. Лицензии — рядом в этом каталоге.
Обновлять — заменой каталога скилла целиком из исходного репозитория с фиксацией коммита здесь.

| Скилл | Источник | Коммит | Лицензия |
|---|---|---|---|
| `3d-essentials`, `shader-basics`, `particles-vfx`, `godot-optimization`, `procedural-generation`, `camera-system`, `hud-system`, `responsive-ui`, `gdscript-advanced`, `godot-code-review` | [jame581/GodotPrompter](https://github.com/jame581/GodotPrompter) `skills/` | `3e8d0f0` | MIT (`GodotPrompter.LICENSE`) |
| `game-feel`, `level-design`, `create-game-assets`, `game-ui-ux` | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) `skills/disciplines/` | `d4b0e35` | Apache-2.0 (`awesome-gamedev-agent-skills.LICENSE`, `.NOTICE`) |

Из `create-game-assets` удалён каталог `agents/` (конфиг для другого инструмента). Скрипты
`create-game-assets/scripts/*.py` локальные (Pillow), сети не используют.

Собственные скиллы проекта (не сторонние): `ride-visual-review`, `indoor-cycling-game-design`.

Каталог `.claude/` исключён из импорта Godot файлом `.claude/.gdignore`.
