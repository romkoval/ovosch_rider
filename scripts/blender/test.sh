#!/usr/bin/env bash
# Тесты конвейера доводки модели гонщика (T-143) в Blender/bpy: данные конвейера против спеки и
# контракта, арматура из контракта, A-поза, шаги на синтетике, rider.glb (Т1–Т7), детерминизм,
# фикстура для GUT; плюс проверка пакета assets/rider/reference в Blender.
# Использование: scripts/blender/test.sh [-k шаблон] [--update-fixture]
# Blender: BLENDER_PY (Python с bpy или бинарник blender) — scripts/blender/env.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/blender/env.sh
status=0
if [ "$#" -eq 0 ]; then
  echo "== пакет assets/rider/reference в Blender (scripts/dev/check_rider_pack_blender.py)"
  bpy_run scripts/dev/check_rider_pack_blender.py | grep -E "^(FAIL|ИТОГ)" || status=1
fi
echo "== тесты конвейера (scripts/blender/tests)"
bpy_run scripts/blender/tests/run.py "$@" 2>&1 | grep -vE "^[0-9:]+ \| INFO|Draco mesh compression|^$" || status=1
exit $status
