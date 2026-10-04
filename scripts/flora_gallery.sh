#!/usr/bin/env bash
# Хвойные (T-107, арт-библия «Растительность: хвойные»): галерея форм и замер кадра
# (см. scripts/dev/flora_gallery.gd). Нужен Godot 4.7 и дисплей; рендерер — переменная RENDERER
# (gl_compatibility по умолчанию, forward_plus, mobile), как у screenshot.sh.
# Использование:
#   [RENDERER=forward_plus] ./scripts/flora_gallery.sh gallery [каталог=screenshots/flora] [трассы=mountains,seaside]
#     — все формы × все уровни детализации в ряд на траве при свете трассы: vegetation_<трасса>.png
#       (три ряда — LOD0, LOD1, LOD2 — друг под другом, 1280 × 2160) и кадры рядов vegetation_<трасса>_lod<k>.png.
#   [RENDERER=forward_plus] ./scripts/flora_gallery.sh stats [трасса=mountains] [шаг_м=100]
#     — проезд трассы рабочей камерой: draw calls и треугольники кадра, доля хвойных (кадр
#       с хвойными и без), максимум по трассе; строки «flora_stats: …».
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo /opt/godot/godot)}"
RENDERER="${RENDERER:-gl_compatibility}"
IS_MACOS=0
[[ "$(uname -s)" == "Darwin" ]] && IS_MACOS=1
case "$RENDERER" in
  gl_compatibility) driver=(--rendering-driver opengl3) ;;
  forward_plus | mobile) driver=() ;;
  *)
    echo "flora_gallery.sh: RENDERER='$RENDERER' — ожидается forward_plus, mobile или gl_compatibility" >&2
    exit 2
    ;;
esac
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
run=("$GODOT" --path . --rendering-method "$RENDERER" "${driver[@]+"${driver[@]}"}" --resolution 1280x720)
if [[ "$IS_MACOS" == 1 ]]; then
  run+=(--always-on-top)
fi
run+=(-s res://scripts/dev/flora_gallery.gd -- "$@")
if [[ "$IS_MACOS" == 0 && -z "${DISPLAY:-}" ]] && command -v xvfb-run >/dev/null; then
  xvfb-run -a -s "-screen 0 1280x720x24" "${run[@]}"
else
  "${run[@]}"
fi
