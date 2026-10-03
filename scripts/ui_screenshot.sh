#!/usr/bin/env bash
# Снимки экранов UI и HUD тренировки в PNG (см. scripts/dev/ui_screenshot.gd, docs/game/hud.md п. 14).
# Нужен Godot 4.7 и дисплей: без него (Linux) запускается под xvfb-run, рендер — gl_compatibility.
# На macOS окно открывается поверх остальных (--always-on-top): окно, перекрытое другими,
# не перерисовывается, и проход зависает. Размер каждого кадра проверяет сам скрипт: кадр не
# того размера (Retina, растянутое окно) не сохраняется, код выхода ≠ 0.
# Использование:
#   ./scripts/ui_screenshot.sh [каталог=screenshots/ui] [разрешение=all] [язык=all] [--safe-area]
# разрешение — WxH, список через запятую или all (1280x720,1024x768,1280x590);
# язык — ru, en, список через запятую или all (ru,en); --safe-area — имитация безопасной
# зоны 100/100/0/13 lp (слева/справа/сверху/снизу). На каждую пару «разрешение × язык» —
# отдельный запуск Godot с окном нужного размера. Код выхода ≠ 0, если упал хоть один запуск.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo /opt/godot/godot)}"
ALL_RESOLUTIONS="1280x720,1024x768,1280x590"
ALL_LANGS="ru,en"
IS_MACOS=0
[[ "$(uname -s)" == "Darwin" ]] && IS_MACOS=1

safe=0
positional=()
for arg in "$@"; do
  if [[ "$arg" == "--safe-area" ]]; then
    safe=1
  else
    positional+=("$arg")
  fi
done
OUT="${positional[0]:-screenshots/ui}"
RESOLUTIONS="${positional[1]:-all}"
LANGS="${positional[2]:-all}"
[[ "$RESOLUTIONS" == "all" ]] && RESOLUTIONS="$ALL_RESOLUTIONS"
[[ "$LANGS" == "all" ]] && LANGS="$ALL_LANGS"

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
status=0
for res in ${RESOLUTIONS//,/ }; do
  if [[ ! "$res" =~ ^[0-9]+x[0-9]+$ ]]; then
    echo "ui_screenshot.sh: разрешение '$res' не в формате WxH" >&2
    exit 2
  fi
  for lang in ${LANGS//,/ }; do
    run=("$GODOT" --path . --rendering-method gl_compatibility --rendering-driver opengl3
      --resolution "$res")
    if [[ "$IS_MACOS" == 1 ]]; then
      run+=(--always-on-top)
    fi
    run+=(-s res://scripts/dev/ui_screenshot.gd -- "$OUT" "$res" "$lang")
    if [[ "$safe" == 1 ]]; then
      run+=(--safe-area)
    fi
    # xvfb — только Linux без дисплея; на macOS всегда своё окно (даже если стоит XQuartz).
    if [[ "$IS_MACOS" == 0 && -z "${DISPLAY:-}" ]] && command -v xvfb-run >/dev/null; then
      xvfb-run -a -s "-screen 0 ${res}x24" "${run[@]}" || status=1
    else
      "${run[@]}" || status=1
    fi
  done
done
exit "$status"
