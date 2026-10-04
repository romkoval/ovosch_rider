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
# Свой каталог данных на прогон (T-115, REQ-INF-01): иначе параллельные прогоны из разных
# worktree пишут в общий user:// (app_userdata/ovosch-rider) и мешают друг другу.
# Флага «каталог пользователя» у Godot нет; user:// строится от HOME (macOS:
# $HOME/Library/Application Support; Linux: $XDG_DATA_HOME или $HOME/.local/share),
# поэтому подменяем их только для процесса GUT — импорт и само приложение
# работают с настоящим каталогом. После прогона каталог удаляется;
# OVOSCH_TEST_KEEP_USERDATA=1 — оставить для разбора.
# Без завершающего «/» у TMPDIR (macOS: …/T/): «//» в пути user:// ломает обход каталогов
# DirAccess (list_dir_begin перечисляет не тот каталог).
tmp_root="${TMPDIR:-/tmp}"
tmp_root="${tmp_root%/}"
run_home="$(mktemp -d "$tmp_root/ovosch-gut.XXXXXX")"
cleanup() {
  rm -f "$log"
  if [ "${OVOSCH_TEST_KEEP_USERDATA:-}" = "1" ]; then
    echo "test.sh: каталог данных прогона сохранён: $run_home" >&2
  else
    rm -rf "$run_home"
  fi
}
trap cleanup EXIT
mkdir -p "$run_home/.local/share" "$run_home/.config" "$run_home/.cache"
set +e
HOME="$run_home" \
XDG_DATA_HOME="$run_home/.local/share" \
XDG_CONFIG_HOME="$run_home/.config" \
XDG_CACHE_HOME="$run_home/.cache" \
OVOSCH_TEST_RUN_HOME="$run_home" \
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
