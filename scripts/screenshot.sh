#!/usr/bin/env bash
# Снимки 3D-сцены заезда в PNG (см. scripts/dev/ride_screenshot.gd). Нужен Godot 4.7 и
# дисплей: без него запускается под xvfb-run, рендер — gl_compatibility (Mesa llvmpipe),
# поэтому картинка близка к Forward+, но не идентична (нет SDFGI/объёмного тумана и т.п.).
# Использование: ./scripts/screenshot.sh [каталог=screenshots] [скорость_кмч=32] [каденс=90] [дистанции_м=0,400,900,1500]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo /opt/godot/godot)}"
OUT="${1:-screenshots}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
run=("$GODOT" --path . --rendering-method gl_compatibility --rendering-driver opengl3
  --resolution 1280x720 -s res://scripts/dev/ride_screenshot.gd -- "$OUT" "${@:2}")
if [[ -z "${DISPLAY:-}" ]] && command -v xvfb-run >/dev/null; then
  xvfb-run -a -s "-screen 0 1280x720x24" "${run[@]}"
else
  "${run[@]}"
fi
