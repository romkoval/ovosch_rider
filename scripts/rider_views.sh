#!/usr/bin/env bash
# Эталонные ракурсы гонщика (T-106a1; бриф художнику раздел 14; `RiderRig.VIEWS`):
# work, side_r, hips_r — при φ 0/90/180/270, rear34_l, front34_r, head_34 — при φ 90;
# rear_low (ред. 3, движение рядом с видео) — при φ 0, 45 … 315.
# Трасса flat, 0 м, скорость и каденс 0 (шатун стоит), 1280×720, файлы rider_<view>_<φ>.png.
# Использование:
#   [RENDERER=forward_plus] ./scripts/rider_views.sh [каталог=screenshots/rider] [ракурсы=all] [углы=по таблице]
#   ./scripts/rider_views.sh shots side_r,hips_r 0,90,180,270
#   BIKE_ONLY=1 ./scripts/rider_views.sh shots side_r,hips_r   # без гонщика: bike_<view>_<φ>.png
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-screenshots/rider}"
VIEWS="${2:-all}"
extra=()
if [[ "${BIKE_ONLY:-0}" == 1 ]]; then
  extra+=("--bike-only")
fi
if [[ -n "${3:-}" ]]; then
  extra+=("--crank=$3")
fi
exec ./scripts/screenshot.sh "$OUT" 0 0 0 flat "--views=$VIEWS" "${extra[@]+"${extra[@]}"}"
