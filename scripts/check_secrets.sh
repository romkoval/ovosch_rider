#!/usr/bin/env bash
# Поиск секретов в репозитории (REQ-INF-03 крит. 5, REQ-NFR-05). Код выхода 1 при находках.
#
# Что сканируется: все отслеживаемые git файлы (плюс неотслеживаемые и не игнорируемые),
# кроме бинарных и addons/gut/. Вне git-репозитория (изолированная копия в тестах) — все
# файлы каталога, кроме .git/ и .godot/.
#
# Шаблоны:
#   - присваивания client_secret / refresh_token / access_token / api_key (без учёта
#     регистра, ключ может быть частью имени и в кавычках, оператор =, := или :, значение
#     ≥ 8 символов в "…", '…' или без кавычек — тогда в нём есть цифра и это не вызов/индекс);
#   - -----BEGIN … PRIVATE KEY-----, токены GitHub (ghp_/gho_/ghu_/ghs_/ghr_, github_pat_),
#     AKIA + 16 символов (AWS), sk_<8+>, Basic <base64 ≥ 20>, Bearer <токен ≥ 8>.
#
# Белый список применяется к ЗНАЧЕНИЮ (не к строке целиком): <…>, YOUR_, PLACEHOLDER, xxx,
# "...", example, dummy, fixture-… (без учёта регистра). Точечные исключения для заведомо
# фиктивных образцов в тестах самого сканера — файл scripts/check_secrets.allow, строки
# «путь<TAB>значение» (исключение действует только для этого значения в этом файле).
set -uo pipefail
cd "$(dirname "$0")/.."
shopt -s nocasematch

ALLOW_FILE="scripts/check_secrets.allow"
# Плейсхолдеры (по значению, без учёта регистра).
VALUE_ALLOW='<[^>]*>|your_|placeholder|xxx|\.\.\.|example|dummy|^fixture-'

# Присваивания (grep -i). Значение — группа после оператора.
Q="'"
ASSIGN_KEY="[\"$Q]?(client_secret|refresh_token|access_token|api_key)[\"$Q]?"
ASSIGN_OP='[[:space:]]*(:=|=|:)[[:space:]]*'
ASSIGN_VAL="(\"[^\"[:space:]]{8,}\"|$Q[^$Q[:space:]]{8,}$Q|[A-Za-z0-9._~+/=-]{8,}([^[(A-Za-z0-9._~+/=-]|\$))"
ASSIGN_RE="$ASSIGN_KEY$ASSIGN_OP$ASSIGN_VAL"
# Литеральные форматы (с учётом регистра).
LITERAL_RE='-----BEGIN [A-Z ]*PRIVATE KEY-----|(^|[^A-Za-z0-9_])(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})|AKIA[0-9A-Z]{16}|(^|[^A-Za-z0-9_])sk_[A-Za-z0-9_-]{8,}|Basic [A-Za-z0-9+/]{20,}={0,2}|Bearer [A-Za-z0-9._~+/-]{8,}=*'

# Список файлов.
list_files() {
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ] && [ "$(cd "$top" && pwd -P)" = "$(pwd -P)" ]; then
    git ls-files -z --cached --others --exclude-standard
  else
    find . -type f -not -path './.git/*' -not -path './.godot/*' -print0 | sed -z 's#^\./##'
  fi
}

# Извлечь значение из найденного фрагмента.
value_of() {
  local kind="$1" m="$2"
  if [ "$kind" = assign ]; then
    if [[ $m =~ $ASSIGN_OP(.*)$ ]]; then
      m="${BASH_REMATCH[2]}"
    fi
    # Снять кавычки и завершающий символ-разделитель у значения без кавычек.
    case "$m" in
      \"*\") m="${m:1:${#m}-2}" ;;
      "$Q"*"$Q") m="${m:1:${#m}-2}" ;;
      *) [[ $m =~ ^([A-Za-z0-9._~+/=-]+) ]] && m="${BASH_REMATCH[1]}" ;;
    esac
  else
    m="${m#"${m%%[A-Za-z0-9-]*}"}"   # убрать ведущий разделитель
    m="${m#Bearer }"; m="${m#Basic }"
  fi
  printf '%s' "$m"
}

is_allowed() {
  local path="$1" value="$2"
  [[ $value =~ $VALUE_ALLOW ]] && return 0
  if [ -f "$ALLOW_FILE" ]; then
    local p v
    while IFS=$'\t' read -r p v; do
      [[ -z $p || $p == \#* ]] && continue
      [ "$p" = "$path" ] && [ "$v" = "$value" ] && return 0
    done <"$ALLOW_FILE"
  fi
  return 1
}

found=0
report() {
  local kind="$1" path="$2" lineno="$3" match="$4" value
  value="$(value_of "$kind" "$match")"
  if [ "$kind" = assign ]; then
    # Значение без кавычек — только если в нём есть цифра (иначе это имя переменной).
    if [[ $match =~ $ASSIGN_OP[^\"$Q] ]] && ! [[ $value =~ [0-9] ]]; then
      return
    fi
  fi
  is_allowed "$path" "$value" && return
  echo "SECRET? $path:$lineno: $value"
  found=1
}

files=()
while IFS= read -r -d '' f; do
  case "$f" in addons/gut/*|scripts/check_secrets.allow) continue ;; esac
  [ -f "$f" ] && files+=("$f")
done < <(list_files)

scan() {
  local kind="$1"; shift
  local line path rest lineno match
  [ "${#files[@]}" -eq 0 ] && return
  while IFS= read -r line; do
    path="${line%%:*}"; rest="${line#*:}"
    lineno="${rest%%:*}"; match="${rest#*:}"
    report "$kind" "$path" "$lineno" "$match"
  done < <(printf '%s\0' "${files[@]}" | xargs -0 grep -HnoIE "$@" 2>/dev/null || true)
}
scan assign -i -e "$ASSIGN_RE"
scan literal -e "$LITERAL_RE"

if [ "$found" -ne 0 ]; then
  echo "check_secrets: найдены строки, похожие на секреты (см. выше)" >&2
  exit 1
fi
echo "check_secrets: OK"
