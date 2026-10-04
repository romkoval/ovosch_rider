#!/usr/bin/env bash
# Настройка облачной среды Claude Code (claude.ai/code, Ubuntu 24.04, без GPU) для ovosch-rider.
# Вставить в поле «Setup script» окружения (или: bash scripts/cloud/setup.sh из корня клона).
# Ставит: Godot 4.7 (/opt/godot/godot — путь из CLAUDE.md, + godot в PATH), xvfb и Mesa
# (снимки gl_compatibility через xvfb-run, как в CI), Blender (доводка модели гонщика скриптами).
# Сеть: github.com (релизы Godot, python-build-standalone для uv) — в списке Trusted по умолчанию;
# Blender берётся с download.blender.org (добавить домен в Custom allowlist), иначе — пакет bpy
# с PyPI в отдельном venv на Python 3.11 (через uv).
# Идемпотентен: повторный запуск ничего не перекачивает.
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7-stable}"
BLENDER_SERIES="${BLENDER_SERIES:-4.2}"
BLENDER_VERSION="${BLENDER_VERSION:-4.2.9}"
SUDO=""
[ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null && SUDO="sudo"

log() { echo "[setup] $*"; }

# --- Godot -------------------------------------------------------------------------------
if [ ! -x /opt/godot/godot ]; then
  log "Godot ${GODOT_VERSION}"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/godot.zip" \
    "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip"
  $SUDO mkdir -p /opt/godot
  $SUDO unzip -q -o "$tmp/godot.zip" -d /opt/godot
  $SUDO mv "/opt/godot/Godot_v${GODOT_VERSION}_linux.x86_64" /opt/godot/godot
  $SUDO chmod +x /opt/godot/godot
  rm -rf "$tmp"
fi
$SUDO ln -sf /opt/godot/godot /usr/local/bin/godot

# --- xvfb и Mesa (снимки) ------------------------------------------------------------------
if ! command -v xvfb-run >/dev/null; then
  log "xvfb, Mesa"
  if $SUDO apt-get update -qq && $SUDO apt-get install -y -qq --no-install-recommends \
      xvfb xauth libgl1 libgl1-mesa-dri libglu1-mesa libxi6 libxrandr2 libxinerama1 \
      libxcursor1 libfontconfig1 >/dev/null; then
    :
  else
    log "ВНИМАНИЕ: apt недоступен (сеть?) — снимки ./scripts/screenshot.sh работать не будут, тесты — будут"
  fi
fi

# --- Blender ------------------------------------------------------------------------------
if [ ! -x /opt/blender/blender ] && [ ! -x /opt/bpy/bin/python ]; then
  url="https://download.blender.org/release/Blender${BLENDER_SERIES}/blender-${BLENDER_VERSION}-linux-x64.tar.xz"
  tmp="$(mktemp -d)"
  if curl -fsSL -o "$tmp/blender.tar.xz" "$url"; then
    log "Blender ${BLENDER_VERSION} (download.blender.org)"
    $SUDO mkdir -p /opt/blender
    $SUDO tar -xJf "$tmp/blender.tar.xz" -C /opt/blender --strip-components=1
    $SUDO ln -sf /opt/blender/blender /usr/local/bin/blender
  else
    log "download.blender.org недоступен — ставлю bpy ${BLENDER_SERIES} с PyPI (Python 3.11 через uv)"
    command -v uv >/dev/null || pip install -q uv
    uv python install 3.11
    $SUDO mkdir -p /opt/bpy && $SUDO chown "$(id -u)" /opt/bpy
    uv venv -q -p 3.11 /opt/bpy
    uv pip install -q -p /opt/bpy/bin/python "bpy==${BLENDER_SERIES}.*"
    log "Blender как модуль: /opt/bpy/bin/python -c 'import bpy'"
  fi
  rm -rf "$tmp"
fi

# --- Импорт проекта (кэшируется вместе со снимком среды) -----------------------------------
if [ -f project.godot ]; then
  log "godot --import"
  /opt/godot/godot --headless --path . --import >/dev/null 2>&1 || true
fi

log "готово: $(/opt/godot/godot --version 2>/dev/null | head -1)"
