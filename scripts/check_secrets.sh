#!/usr/bin/env bash
# Поиск секретов в репозитории (REQ-INF-03 крит. 5, REQ-NFR-05). Код выхода 1 при находках.
# Шаблоны: ключи вида sk_..., client_secret = "...", Bearer <token>, api_key = "...",
# refresh_token = "..."; строки с плейсхолдерами из белого списка игнорируются.
set -uo pipefail
cd "$(dirname "$0")/.."
PATTERN='(^|[^A-Za-z0-9_])sk_[A-Za-z0-9]{8,}|client_secret[[:space:]]*[=:][[:space:]]*"[^"]+"|Bearer [A-Za-z0-9._-]{8,}|api_key[[:space:]]*[=:][[:space:]]*"[^"]+"|refresh_token[[:space:]]*[=:][[:space:]]*"[^"]+"'
ALLOW='PLACEHOLDER|placeholder|example|EXAMPLE|<token>|<secret>|<key>|dummy|TEST_|test-|fixture'
TARGETS=(src tests/fixtures project.godot docs)
found=0
for t in "${TARGETS[@]}"; do
  [ -e "$t" ] || continue
  while IFS= read -r line; do
    if ! grep -Eq "$ALLOW" <<<"$line"; then
      echo "SECRET? $line"
      found=1
    fi
  done < <(grep -rnE --exclude='*.uid' --exclude='*.translation' "$PATTERN" "$t" 2>/dev/null || true)
done
if [ "$found" -ne 0 ]; then
  echo "check_secrets: найдены строки, похожие на секреты (см. выше)" >&2
  exit 1
fi
echo "check_secrets: OK"
