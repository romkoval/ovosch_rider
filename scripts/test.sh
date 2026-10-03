#!/usr/bin/env bash
# Запуск автотестов GUT headless. GODOT — путь к бинарнику Godot 4.7 (по умолчанию ищется в PATH).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo /opt/godot/godot)}"
# Окружение разработчика не должно влиять на тесты: фиксированная локаль (иначе при
# русской системной локали Godot выбирает другой язык интерфейса и тесты через
# main.tscn краснеют) и никаких секретов Strava из переменных окружения.
export LC_ALL=C.UTF-8
export LANG=C.UTF-8
unset OVOSCH_STRAVA_CLIENT_ID OVOSCH_STRAVA_CLIENT_SECRET
mkdir -p tests/reports
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
set +e
"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json "$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e
# GUT молча пропускает скрипты с ошибками разбора — ловим их по логу и валим прогон.
if grep -qE "SCRIPT ERROR: (Parse|Compile) Error" "$log"; then
  echo "test.sh: обнаружены ошибки разбора/компиляции скриптов (см. выше) — прогон считается упавшим" >&2
  exit 1
fi
# Опечатка в -gselect/-gtest или пустой набор: GUT выходит с 0, не запустив ни одного скрипта.
clean_log="$(sed 's/\x1b\[[0-9;]*m//g' "$log")"
if grep -q "Could not find script matching" <<<"$clean_log" \
  || ! grep -qE "^Scripts[[:space:]]+[1-9][0-9]*[[:space:]]*$" <<<"$clean_log"; then
  echo "test.sh: не запущено ни одного тестового скрипта (проверьте -gselect/-gtest) — прогон считается упавшим" >&2
  exit 1
fi
exit "$status"
