#!/usr/bin/env bash
# Снимки 3D-сцены заезда в PNG (см. scripts/dev/ride_screenshot.gd). Нужен Godot 4.7 и дисплей.
# Рендерер — переменная RENDERER: gl_compatibility (по умолчанию; без дисплея на Linux —
# под xvfb-run, Mesa llvmpipe), forward_plus (как приложение на macOS/десктопе) или mobile
# (как на iOS). Forward+ и Mobile требуют GPU (Metal/Vulkan) — на macOS запускаются в своём
# окне поверх остальных (окно, перекрытое другими, не перерисовывается).
# Использование:
#   [RENDERER=forward_plus] ./scripts/screenshot.sh [каталог=screenshots] [скорость_кмч=32] [каденс=90] [дистанции_м=0,400,900,1500] [трасса] [вторая_трасса]
#   вторая_трасса — ещё одна сцена этой трассы в своём SubViewport, построенная после снимаемой (T-112).
#   Ключи в любом месте после каталога (T-106a1): --views=all|work,side_r,… — эталонные ракурсы гонщика
#   (RiderRig.VIEWS, файлы rider_<view>_<φ>.png; дистанция — первая из списка), --crank=0,90,… — углы
#   шатуна вместо углов ракурса, --bike-only — без гонщика (bike_<view>_<φ>.png). Обёртка — rider_views.sh.
#   --figure=m|f, --hair=short|tail (T-106a2) — фигура и причёска манекена (по умолчанию m, short).
#   --series=<с> [--fps=30] (T-106a2) — серия кадров ракурсов --views в движении (скорость и каденс из
#   аргументов): series_<view>/<view>_<NNN>.png и series.csv; пример — rear_low 2 с при 100 об/мин:
#   ./scripts/screenshot.sh shots 32 100 0 flat --views=rear_low --series=2.0 --fps=30 --figure=f --hair=tail
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo /opt/godot/godot)}"
RENDERER="${RENDERER:-gl_compatibility}"
OUT="${1:-screenshots}"
IS_MACOS=0
[[ "$(uname -s)" == "Darwin" ]] && IS_MACOS=1
case "$RENDERER" in
  gl_compatibility) driver=(--rendering-driver opengl3) ;;
  forward_plus | mobile) driver=() ;;
  *)
    echo "screenshot.sh: RENDERER='$RENDERER' — ожидается forward_plus, mobile или gl_compatibility" >&2
    exit 2
    ;;
esac
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
run=("$GODOT" --path . --rendering-method "$RENDERER" "${driver[@]+"${driver[@]}"}" --resolution 1280x720)
if [[ "$IS_MACOS" == 1 ]]; then
  run+=(--always-on-top)
fi
run+=(-s res://scripts/dev/ride_screenshot.gd -- "$OUT" "${@:2}")
# xvfb — только Linux без дисплея; на macOS всегда своё окно.
if [[ "$IS_MACOS" == 0 && -z "${DISPLAY:-}" ]] && command -v xvfb-run >/dev/null; then
  xvfb-run -a -s "-screen 0 1280x720x24" "${run[@]}"
else
  "${run[@]}"
fi
