#!/usr/bin/env bash
# Конвейер доводки ИИ-модели гонщика в Blender (T-143; арт-библия «Гонщик» → «Вариант Г»):
# шаги 1–5, 7, 8, 11 — от сырого GLB до rider.glb. Промежуточные .blend и отчёт — вне git,
# по умолчанию reference/ai/work/<имя сырого>/ (NN_<шаг>.blend, report.txt, report.json).
# Использование:
#   ./scripts/rider_refine.sh <сырой.glb> [--landmarks J] [--from N] [--to M] [--work DIR] [--retopo project|decimate]
#   ./scripts/rider_refine.sh --compare a.glb b.glb c.glb     # шаг 1 по вариантам сырья
# Blender: BLENDER_PY (Python с bpy или бинарник blender) — scripts/blender/env.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/blender/env.sh
if [ "${1:-}" = "--compare" ]; then
  shift
  bpy_run scripts/blender/refine.py --compare "$@"
else
  bpy_run scripts/blender/refine.py "$@"
fi
