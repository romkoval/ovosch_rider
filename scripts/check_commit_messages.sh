#!/usr/bin/env bash
# Проверка сообщений коммитов (REQ-INF-03 крит. 1, 2): каждое сообщение в диапазоне
# содержит REQ-ID вида REQ-XXX-NN или начинается с docs:/ci:/tests:/chore:.
# Использование: check_commit_messages.sh [<range>]  (по умолчанию — только HEAD).
# На shallow clone или без истории — предупреждение и выход 0.
set -uo pipefail
cd "$(dirname "$0")/.."
RANGE="${1:-HEAD~0..HEAD}"
if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
  echo "check_commit_messages: shallow clone — проверка истории пропущена (нужен fetch-depth: 0)" >&2
  exit 0
fi
if ! git rev-list "$RANGE" >/dev/null 2>&1; then
  echo "check_commit_messages: диапазон '$RANGE' недоступен — проверяю только HEAD" >&2
  RANGE="HEAD~0..HEAD"
fi
mapfile -t COMMITS < <(git rev-list --no-merges "$RANGE" 2>/dev/null)
if [ "${#COMMITS[@]}" -eq 0 ]; then
  COMMITS=("$(git rev-parse HEAD)")
fi
bad=0
for c in "${COMMITS[@]}"; do
  msg="$(git log -1 --format='%B' "$c")"
  subject="$(git log -1 --format='%s' "$c")"
  if grep -Eq 'REQ-[A-Z0-9]+-[0-9]+' <<<"$msg" || grep -Eq '^(docs|ci|tests|chore):' <<<"$subject"; then
    continue
  fi
  echo "BAD COMMIT ${c:0:9}: $subject"
  bad=1
done
if [ "$bad" -ne 0 ]; then
  echo "check_commit_messages: сообщение коммита должно содержать REQ-ID или начинаться с docs:/ci:/tests:/chore:" >&2
  exit 1
fi
echo "check_commit_messages: OK (${#COMMITS[@]} коммит(ов))"
