#!/usr/bin/env bash
# Поиск секретов в репозитории (REQ-INF-03 крит. 5, REQ-NFR-05). Код выхода 1 при находках.
# Шаблоны: ключи вида sk_<8+ символов>, client_secret = "...", Bearer <token>, api_key = "...",
# refresh_token = "...". Строка игнорируется, если В ЕЁ СОДЕРЖИМОМ (не в пути файла)
# есть явный плейсхолдер из белого списка.
set -uo pipefail
cd "$(dirname "$0")/.."
PATTERN='(^|[^A-Za-z0-9_])sk_[A-Za-z0-9_-]{8,}|client_secret[[:space:]]*[=:][[:space:]]*"[^"]+"|Bearer [A-Za-z0-9._-]{8,}|api_key[[:space:]]*[=:][[:space:]]*"[^"]+"|refresh_token[[:space:]]*[=:][[:space:]]*"[^"]+"'
ALLOW='PLACEHOLDER|placeholder|EXAMPLE|example\.com|<token>|<secret>|<key>|<api_key>|dummy|xxx+|\.\.\.'
TARGETS=(src tests/fixtures project.godot docs)
found=0
for t in "${TARGETS[@]}"; do
  [ -e "$t" ] || continue
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # Формат grep: путь:строка:содержимое — белый список проверяем только по содержимому.
    content="${line#*:}"
    content="${content#*:}"
    if grep -Eq "$ALLOW" <<<"$content"; then
      continue
    fi
    echo "SECRET? $line"
    found=1
  done < <(grep -rnE --exclude='*.uid' --exclude='*.translation' --exclude='*.import' "$PATTERN" "$t" 2>/dev/null || true)
done
if [ "$found" -ne 0 ]; then
  echo "check_secrets: найдены строки, похожие на секреты (см. выше)" >&2
  exit 1
fi
echo "check_secrets: OK"
