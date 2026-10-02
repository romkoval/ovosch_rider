#!/usr/bin/env bash
# Запуск автотестов GUT headless. GODOT — путь к бинарнику Godot 4.7 (по умолчанию ищется в PATH).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo /opt/godot/godot)}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json "$@"
