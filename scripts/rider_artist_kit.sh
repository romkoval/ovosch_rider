#!/usr/bin/env bash
# Пакет художнику (T-106a1): bike_reference.glb, rider_rig_reference.glb, атласы регионов —
# из кода проекта (RiderRig, RiderModel, RiderRegions), см. scripts/dev/rider_artist_kit.gd.
# Нужен Godot 4.7; дисплей не нужен (headless).
# Использование: ./scripts/rider_artist_kit.sh [каталог=res://assets/rider/reference]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo /opt/godot/godot)}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
exec "$GODOT" --headless --path . -s res://scripts/dev/rider_artist_kit.gd -- "$@"
