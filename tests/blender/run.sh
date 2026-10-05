#!/usr/bin/env bash
# Приёмочные тесты tester для конвейера доводки модели гонщика (T-143) — отдельно от GUT:
# нужен Python с модулем bpy или Blender (scripts/blender/env.sh). Конвейер запускается
# `scripts/rider_refine.sh` отдельными процессами, рабочие каталоги — во временном каталоге.
# Использование: tests/blender/run.sh [-k шаблон]
# BLENDER_PY — Python с bpy (облако: /opt/bpy/bin/python) или бинарник Blender
# (Mac: /Applications/Blender.app/Contents/MacOS/Blender) — тогда тесты идут во встроенном Python.
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/blender/env.sh
case "$(basename "$BLENDER_PY")" in
  blender|Blender|blender.exe)
    pattern=""
    if [ "${1:-}" = "-k" ] && [ -n "${2:-}" ]; then pattern="$2"; fi
    exec "$BLENDER_PY" -b --factory-startup --python-exit-code 1 --python-expr "
import sys, unittest
loader = unittest.TestLoader()
if '$pattern':
    loader.testNamePatterns = ['*$pattern*']
res = unittest.TextTestRunner(verbosity=2).run(loader.discover('tests/blender', pattern='test_*.py'))
sys.exit(0 if res.wasSuccessful() else 1)
" ;;
  *) exec "$BLENDER_PY" -m unittest discover -s tests/blender -p "test_*.py" -v "$@" ;;
esac
