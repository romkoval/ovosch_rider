# Поиск Blender для скриптов scripts/blender (T-143). Подключается через `source`.
# BLENDER_PY — интерпретатор: Python с модулем bpy (по умолчанию /opt/bpy/bin/python, облако)
# или бинарник Blender (Mac владельца: /Applications/Blender.app/Contents/MacOS/Blender).
# bpy_run <скрипт.py> [аргументы...] — запуск в любом из двух режимов.
if [ -z "${BLENDER_PY:-}" ]; then
  for cand in /opt/bpy/bin/python "$(command -v blender 2>/dev/null)" /opt/blender/blender \
      /Applications/Blender.app/Contents/MacOS/Blender; do
    if [ -n "$cand" ] && [ -x "$cand" ]; then BLENDER_PY="$cand"; break; fi
  done
fi
if [ -z "${BLENDER_PY:-}" ] || [ ! -x "$BLENDER_PY" ]; then
  echo "Blender не найден: задайте BLENDER_PY (Python с bpy или бинарник blender); облако — scripts/cloud/setup.sh" >&2
  return 2 2>/dev/null || exit 2
fi
export PYTHONDONTWRITEBYTECODE=1
bpy_run() {
  local script="$1"; shift
  case "$(basename "$BLENDER_PY")" in
    blender|Blender|blender.exe) "$BLENDER_PY" -b --factory-startup --python-exit-code 1 -P "$script" -- "$@" ;;
    *) "$BLENDER_PY" "$script" "$@" ;;
  esac
}
