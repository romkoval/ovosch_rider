#!/usr/bin/env bash
# Приёмочные тесты tester для конвейера доводки модели гонщика (T-143) — отдельно от GUT:
# нужен Python с модулем bpy или Blender (scripts/blender/env.sh). Конвейер запускается
# `scripts/rider_refine.sh` отдельными процессами, рабочие каталоги — во временном каталоге.
# Использование: tests/blender/run.sh [-k шаблон]
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/blender/env.sh
exec "$BLENDER_PY" -m unittest discover -s tests/blender -p "test_*.py" -v "$@"
