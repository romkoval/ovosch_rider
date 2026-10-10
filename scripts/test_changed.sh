#!/usr/bin/env bash
# Прицельный прогон GUT: только тесты, затронутые изменениями, одним запуском Godot.
# Использование: ./scripts/test_changed.sh [база]   (база по умолчанию — merge-base с origin/main)
#   ./scripts/test_changed.sh --list [база]        — только показать набор, не запускать
# В набор входят: изменённые тестовые файлы; тесты, которые ссылаются на изменённый файл
# (путь res://…) или на его class_name; все тесты tests/unit/arch. Изменения считаются
# по коммитам от базы плюс незакоммиченные правки. Полный прогон — ./scripts/test.sh
# (правило, когда он обязателен, — CLAUDE.md, «Прогоны тестов»).
set -euo pipefail
cd "$(dirname "$0")/.."
list_only=0
if [ "${1:-}" = "--list" ]; then
  list_only=1
  shift
fi
base="${1:-$(git merge-base HEAD origin/main 2>/dev/null || echo HEAD)}"
changed="$( { git diff --name-only "$base" -- ; git ls-files --others --exclude-standard; } | sort -u)"
declare -A pick=()
for f in tests/unit/arch/test_*.gd; do
  pick["$f"]=1
done
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  case "$f" in
    tests/*/test_*.gd)
      pick["$f"]=1
      continue
      ;;
    *.uid|*.import|docs/*|*.md)
      continue
      ;;
  esac
  needles=("res://$f")
  if [[ "$f" == *.gd ]]; then
    cls="$(sed -n 's/^class_name[[:space:]]\+\([A-Za-z0-9_]\+\).*/\1/p' "$f" | head -1)"
    [ -n "$cls" ] && needles+=("$cls")
  fi
  for n in "${needles[@]}"; do
    while IFS= read -r t; do
      [ -n "$t" ] && pick["$t"]=1
    done < <(grep -rlwF --include='test_*.gd' -- "$n" tests/unit tests/integration 2>/dev/null || true)
  done
done <<<"$changed"
files=("${!pick[@]}")
IFS=$'\n' files=($(sort <<<"${files[*]}"))
unset IFS
echo "test_changed.sh: база $(git rev-parse --short "$base"), тестовых файлов: ${#files[@]}" >&2
if [ "$list_only" = 1 ]; then
  printf '%s\n' "${files[@]}"
  exit 0
fi
cfg="$(mktemp --suffix=.json 2>/dev/null || mktemp)"
trap 'rm -f "$cfg"' EXIT
{
  printf '{"dirs": [], "tests": ['
  sep=""
  for t in "${files[@]}"; do
    printf '%s"res://%s"' "$sep" "$t"
    sep=", "
  done
  printf '], "should_exit": true, "should_exit_on_success": true, "log_level": 1}\n'
} >"$cfg"
cp "$cfg" .gutconfig.changed.json
trap 'rm -f "$cfg" .gutconfig.changed.json' EXIT
# test.sh передаёт -gconfig=res://.gutconfig.json; второй -gconfig в аргументах GUT берёт последним.
./scripts/test.sh -gconfig=res://.gutconfig.changed.json
