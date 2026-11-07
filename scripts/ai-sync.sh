#!/bin/sh
# Раскладывает канон MCP (src/.config/ai/mcp.json) по конфигам клиентов.
#
#   sh scripts/ai-sync.sh               применить
#   sh scripts/ai-sync.sh --dry-run     показать diff, ничего не менять
#   sh scripts/ai-sync.sh --prune       удалить серверы, которых уже нет в каноне
#   sh scripts/ai-sync.sh --allow-empty писать даже с незаполненными переменными
#
# Цели: ~/.claude/.claude.json, ~/.claude.json, профили CCR и блок mcp
# в ~/.config/opencode/opencode.jsonc. В JSON-файлах меняется только
# mcpServers, в opencode.jsonc — только текст между маркерами MCP-BEGIN/MCP-END.
set -u

. "$(dirname "$0")/lib.sh"
REPO_ROOT=$(repo_root_from "$0") || die "не удалось найти корень репозитория"

DRY=0
PRUNE=false
ALLOW_EMPTY=0
for arg in "$@"; do
  case "$arg" in
    -n|--dry-run)  DRY=1 ;;
    --prune)       PRUNE=true ;;
    --allow-empty) ALLOW_EMPTY=1 ;;
    -h|--help)     sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             die "неизвестный аргумент: $arg" ;;
  esac
done

CANON=$REPO_ROOT/src/.config/ai/mcp.json
[ -f "$CANON" ] || die "нет канона: $CANON"
have jq || die "нужен jq: make bin  (или apt-get install jq)"

SECRETS=${DOTFILES_SECRETS:-$HOME/.config/secrets.d/secrets.env}
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles
MANIFEST=$STATE/ai-sync.manifest.json
STAMP=$(date +%Y_%m_%d-%H_%M_%S)
BACKUP_DIR=$REPO_ROOT/backup/ai-sync/$STAMP

TMPD=$(mktemp -d) || die "нет временного каталога"
trap 'rm -rf "$TMPD"' EXIT INT TERM

# --- 1. окружение для подстановки ${VAR} ---
if [ -f "$SECRETS" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$SECRETS"
  set +a
else
  warn "нет $SECRETS — значения переменных останутся пустыми (make secrets)"
fi

# --- 2. канон с раскрытыми ${VAR} и ${VAR:-default} ---
jq '
  def expand:
    if type == "string" then
      gsub("\\$\\{(?<n>[A-Za-z_][A-Za-z0-9_]*)(:-(?<d>[^}]*))?\\}"; (env[.n] // .d // ""))
    elif type == "object" then with_entries(.value |= expand)
    elif type == "array" then map(expand)
    else . end;
  expand
' "$CANON" > "$TMPD/canon.json" || die "канон не читается как JSON: $CANON"

# предупреждение про незаполненные переменные (дефолт считается заполненным)
missing=""
for name in $(jq -r '[.. | strings | scan("\\$\\{(?<n>[A-Za-z_][A-Za-z0-9_]*)(:-(?<d>[^}]*))?\\}")]
                    | map(select(.[1] == null)) | map(.[0]) | unique | .[]' "$CANON"); do
  eval "val=\${$name:-}"
  [ -n "$val" ] || missing="$missing $name"
done
[ -n "$missing" ] && warn "переменные не заданы:$missing — в конфиги уйдут пустые строки"

# Запись пустых значений затрёт рабочие токены: по умолчанию не пишем.
if [ -n "$missing" ] && [ "$DRY" -eq 0 ] && [ "$ALLOW_EMPTY" -eq 0 ]; then
  err "заполните $SECRETS или запустите с --allow-empty"
  err "ничего не изменено"
  exit 1
fi

# --- 3. список серверов прошлого запуска (для --prune) ---
printf '[]\n' > "$TMPD/manifest.json"
if [ -f "$MANIFEST" ] && jq -e . "$MANIFEST" >/dev/null 2>&1; then
  cp "$MANIFEST" "$TMPD/manifest.json"
fi

short() {
  case $1 in
    "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;;
    *)        printf '%s' "$1" ;;
  esac
}

BACKED=0
backup_target() {
  [ -f "$1" ] || return 0
  _b=$BACKUP_DIR/${1#"$HOME"/}
  mkdir -p "$(dirname "$_b")"
  cp -p "$1" "$_b"
  BACKED=$((BACKED + 1))
}

CHANGED=0
SAME=0
apply() {
  _target=$1
  _new=$2
  if [ -f "$_target" ] && cmp -s "$_target" "$_new"; then
    SAME=$((SAME + 1))
    dim "  =  $(short "$_target")"
    return 0
  fi
  CHANGED=$((CHANGED + 1))
  if [ "$DRY" -eq 1 ]; then
    if [ -f "$_target" ]; then
      printf '%s~  %s%s\n' "$C_YELLOW" "$(short "$_target")" "$C_RESET"
      diff -u -L "$(short "$_target")" -L "канон" "$_target" "$_new" 2>/dev/null \
        | sed -n '1,80p' | sed 's/^/     /'
    else
      printf '%s+  %s%s (новый, серверы: %s)\n' "$C_GREEN" "$(short "$_target")" "$C_RESET" \
        "$(jq -c '(.mcpServers // .mcp // {}) | keys' "$_new" 2>/dev/null)"
    fi
    return 0
  fi
  backup_target "$_target"
  mkdir -p "$(dirname "$_target")"
  cp "$_new" "$_target.tmp.$$"
  # сгенерированный блок — часть пользовательского конфига, права не сужаем
  case $_target in
    *.jsonc) ;;
    *) chmod 600 "$_target.tmp.$$" ;;
  esac
  mv "$_target.tmp.$$" "$_target"
  ok "$(short "$_target")"
}

# Собирает .mcpServers из базы (целевой файл или seed) и канона.
# $1 — целевой файл, $2 — результат, $3 — чем заполнить пустой файл
build_claude() {
  _base=$1
  _out=$2
  _seed=$3
  if [ -f "$_base" ] && jq -e . "$_base" >/dev/null 2>&1; then
    _src=$_base
  elif [ -n "$_seed" ] && [ -f "$_seed" ] && jq -e . "$_seed" >/dev/null 2>&1; then
    _src=$_seed
  else
    printf '{}\n' > "$TMPD/empty.json"
    _src=$TMPD/empty.json
  fi
  jq --slurpfile canon "$TMPD/canon.json" \
     --slurpfile managed "$TMPD/manifest.json" \
     --argjson prune "$PRUNE" '
    ($canon[0].mcpServers // {}) as $new
    | (($managed[0] // []) - ($new | keys)) as $gone
    | .mcpServers = (
        ((.mcpServers // {})
          | if $prune
            then with_entries(select(.key as $k | ($gone | index($k)) == null))
            else . end)
        + $new
      )
  ' "$_src" > "$_out" || die "не удалось собрать $(short "$_base")"
}

# --- 4. Claude Code ---
head_ "Claude Code"
build_claude "$HOME/.claude/.claude.json" "$TMPD/ccr.json" "$HOME/.claude.json"
apply "$HOME/.claude/.claude.json" "$TMPD/ccr.json"
build_claude "$HOME/.claude.json" "$TMPD/home.json" "$HOME/.claude/.claude.json"
apply "$HOME/.claude.json" "$TMPD/home.json"

# --- 5. профили claude-code-router ---
# CCR сам копирует базовый .claude.json в профиль при первом запуске сессии.
# Существующий файл не перезаписываем целиком — только mcpServers. Новый не
# создаём: иначе CCR решит, что шаблон уже есть, и не принесёт oauth/plugins.
PROFILES=$HOME/.claude-code-router/profiles
if [ -d "$PROFILES" ]; then
  head_ "claude-code-router: профили"
  found=0
  for pdir in "$PROFILES"/*/claude; do
    [ -d "$pdir" ] || continue
    found=$((found + 1))
    if [ ! -f "$pdir/.claude.json" ]; then
      dim "  --  $(short "$pdir/.claude.json") ещё не создан (появится после первого запуска сессии)"
      continue
    fi
    build_claude "$pdir/.claude.json" "$TMPD/profile-$found.json" ""
    apply "$pdir/.claude.json" "$TMPD/profile-$found.json"
  done
  [ "$found" -gt 0 ] || dim "  --  профилей с каталогом claude/ нет"
fi

# --- 6. OpenCode ---
# OPENCODE_CONFIG в 2.x не поддерживается: mcp читается только из
# ~/.config/opencode/opencode.jsonc. Поэтому подменяем блок между маркерами,
# не трогая остальное (провайдеры, комментарии).
head_ "OpenCode"
OC_CONF=${OPENCODE_CONFIG_FILE:-$HOME/.config/opencode/opencode.jsonc}
OC_BEGIN='  // >>> MCP-BEGIN — генерируется scripts/ai-sync.sh из src/.config/ai/mcp.json'
OC_END='  // <<< MCP-END'

jq -n --slurpfile canon "$TMPD/canon.json" '
  def to_opencode:
    if .type == "http" or .type == "sse" then
      {type: "remote", url: .url}
      + (if (.headers // {}) == {} then {} else {headers: .headers} end)
    elif .type == "stdio" or .command != null then
      {type: "local", command: ([.command] + (.args // [])), enabled: true}
      + (if (.env // {}) == {} then {} else {environment: .env} end)
      + (if .cwd then {cwd: .cwd} else {} end)
    else . end;
  {mcp: (($canon[0].mcpServers // {}) | with_entries(.value |= to_opencode))}
' > "$TMPD/oc-obj.json" || die "не удалось собрать блок mcp для OpenCode"

# Фрагмент JSONC: без запятой на закрывающей — блок ставится последним ключом.
{
  printf '%s\n' "$OC_BEGIN"
  sed '1d;$d' "$TMPD/oc-obj.json"
  printf '%s\n' "$OC_END"
} > "$TMPD/oc-block.jsonc"

if [ ! -f "$OC_CONF" ]; then
  warn "нет $(short "$OC_CONF") — блок mcp пропущен"
elif ! grep -q '^[[:space:]]*}[[:space:]]*$' "$OC_CONF"; then
  warn "$(short "$OC_CONF"): не найдена закрывающая } в отдельной строке — блок mcp пропущен"
else
  # Убираем старый блок (если был) и вставляем новый перед последней }.
  awk -v block="$TMPD/oc-block.jsonc" '
    { line[NR] = $0; n = NR }
    END {
      bs = 0; be = 0
      for (i = 1; i <= n; i++) {
        if (line[i] ~ /^[[:space:]]*\/\/ >>> MCP-BEGIN/) bs = i
        if (line[i] ~ /^[[:space:]]*\/\/ <<< MCP-END/)   be = i
      }

      # индекс последней значимой строки вне старого блока
      last = 0
      for (i = n; i >= 1; i--) {
        if (bs && i >= bs && i <= be) continue
        if (line[i] ~ /^[[:space:]]*$/) continue
        last = i; break
      }
      if (!last) { print "{}"; exit }

      # индекс последнего ключа/элемента перед закрывающей }
      prev = 0
      for (i = last - 1; i >= 1; i--) {
        if (bs && i >= bs && i <= be) continue
        if (line[i] ~ /^[[:space:]]*$/) continue
        prev = i; break
      }

      for (i = 1; i <= n; i++) {
        if (bs && i >= bs && i <= be) continue
        if (i == last) {
          while ((getline l < block) > 0) print l
          close(block)
        }
        # запятая нужна после последнего значения, если её ещё нет
        if (i == prev && prev > 0 &&
            line[i] !~ /,[[:space:]]*$/ && line[i] !~ /\{[[:space:]]*$/) {
          printf "%s,\n", line[i]
          continue
        }
        print line[i]
      }
    }
  ' "$OC_CONF" > "$TMPD/opencode.jsonc"

  if ! grep -q 'MCP-BEGIN' "$TMPD/opencode.jsonc"; then
    warn "$(short "$OC_CONF"): не удалось вставить блок mcp"
  else
    apply "$OC_CONF" "$TMPD/opencode.jsonc"
  fi
fi

# --- 7. манифест для следующего --prune ---
# Без --prune копим имена: сервер мог выпасть из канона, но всё ещё лежать в
# целевом файле — забыть про него нельзя, иначе следующий --prune его не найдёт.
if [ "$DRY" -eq 0 ]; then
  mkdir -p "$STATE"
  if [ "$PRUNE" = true ]; then
    jq '.mcpServers | keys' "$TMPD/canon.json" > "$MANIFEST"
  else
    jq '.mcpServers | keys' "$TMPD/canon.json" > "$TMPD/current.json"
    jq -s '((.[0] // []) + (.[1] // [])) | unique' \
      "$TMPD/manifest.json" "$TMPD/current.json" > "$MANIFEST"
  fi
fi

printf '\n'
count=$(jq '.mcpServers | length' "$TMPD/canon.json")
if [ "$DRY" -eq 1 ]; then
  printf '%sплан: %d серверов, %d файлов изменится, %d без изменений%s\n\n' \
    "$C_BOLD" "$count" "$CHANGED" "$SAME" "$C_RESET"
else
  printf '%sготово: %d серверов, %d файлов обновлено, %d без изменений%s\n' \
    "$C_BOLD" "$count" "$CHANGED" "$SAME" "$C_RESET"
  [ "$BACKED" -gt 0 ] && printf '  бэкапы: %s\n' "backup/ai-sync/$STAMP"
  if [ "$CHANGED" -gt 0 ]; then
    printf '  перезапустите клиенты: opencode reload, claude — новую сессию\n'
  fi
  printf '\n'
fi
