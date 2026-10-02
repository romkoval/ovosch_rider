#!/usr/bin/env bash
# Запуск автотестов GUT headless. GODOT — путь к бинарнику Godot 4.7 (по умолчанию ищется в PATH).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo /opt/godot/godot)}"
mkdir -p tests/reports
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
# GUT молча пропускает скрипты с ошибками разбора — ловим их по логу и валим прогон.
log="$(mktemp)"
set +e
"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json "$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e
if grep -qE "SCRIPT ERROR: (Parse|Compile) Error" "$log"; then
  echo "test.sh: обнаружены ошибки разбора/компиляции скриптов (см. выше) — прогон считается упавшим" >&2
  rm -f "$log"; exit 1
fi
rm -f "$log"; exit "$status"
