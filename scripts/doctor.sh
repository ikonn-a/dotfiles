#!/bin/sh
# Проверка окружения. Ничего не меняет.
set -u

. "$(dirname "$0")/lib.sh"
REPO_ROOT=$(repo_root_from "$0")
SRC=$REPO_ROOT/src
detect_os

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

head_ "система"
log "  $OS/$ARCH, shell: ${SHELL:-?}, zsh: $(zsh --version 2>/dev/null || echo нет)"

head_ "zsh"
# ZDOTDIR может прийти из родительского процесса (VS Code ставит его в $HOME).
# В новом терминале его переопределит ~/.zshenv, поэтому это не ошибка, а заметка.
if [ "${ZDOTDIR:-}" = "$HOME/.config/zsh" ]; then
  pass "ZDOTDIR=$ZDOTDIR"
elif [ "${ZDOTDIR:-}" = "$HOME" ]; then
  warn "ZDOTDIR=$HOME унаследован от родительского процесса (VS Code)"
  dim "  ~/.zshenv переопределит его при старте zsh; в новом терминале будет верно"
elif [ -z "${ZDOTDIR:-}" ]; then
  warn "ZDOTDIR не задан в этом процессе"
  dim "  это нормально для не-zsh оболочки; задаётся в ~/.zshenv"
else
  fail "ZDOTDIR=$ZDOTDIR (ожидалось $HOME/.config/zsh)"
fi
if [ -f "$HOME/.zshenv" ]; then
  case $(cat "$HOME/.zshenv" 2>/dev/null) in
    *'.config/zsh'*) pass "~/.zshenv задаёт ZDOTDIR" ;;
    *) warn "~/.zshenv не задаёт ZDOTDIR" ;;
  esac
fi
for f in "$HOME/.zshenv" "$HOME/.config/zsh/.zshrc" "$HOME/.config/zsh/.zprofile"; do
  if [ -L "$f" ]; then
    pass "$f -> $(readlink "$f")"
  elif [ -e "$f" ]; then
    warn "$f существует, но не симлинк (запустите make install)"
  else
    fail "$f отсутствует"
  fi
done

head_ "симлинки"
missing=0
list=$(mktemp); trap 'rm -f "$list"' EXIT INT TERM
find "$SRC" -type f | sed "s|^$SRC||" > "$list"
while IFS= read -r rel; do
  [ -L "$HOME$rel" ] || { missing=$((missing + 1)); }
done < "$list"
if [ "$missing" -eq 0 ]; then
  pass "все файлы из src/ залинкованы"
else
  warn "не залинковано файлов: $missing (make install)"
fi

head_ "PATH"
if [ -n "${PATH:-}" ]; then
  dups=$(printf '%s\n' "$(echo "$PATH" | tr ':' '\n')" | sort | uniq -d | grep -v '^$' || true)
  if [ -z "$dups" ]; then
    pass "без дублей"
  else
    dim "  дубли (их уберёт typeset -U в новом терминале):"
    printf '%s\n' "$dups" | sed 's/^/    /'
  fi
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) pass "~/.local/bin в PATH" ;;
    *) warn "~/.local/bin нет в PATH этого процесса (появится после exec zsh)" ;;
  esac
else
  warn "PATH пуст в этом процессе"
fi

head_ "инструменты"
for t in git make curl jq zsh; do
  if have "$t"; then pass "$t $(command -v "$t")"; else fail "$t не найден"; fi
done
for t in rg fd bat eza delta fzf starship yq gh tmux uv shellcheck nvim qsv; do
  if have "$t"; then
    pass "$t"
  elif [ "$t" = nvim ]; then
    dim "  --  nvim отсутствует (make bin PKGS=nvim)"
  else
    dim "  --  $t отсутствует (make bin PKGS=\"$t\")"
  fi
done

# nvim должен быть деревом, иначе нет runtime.
# headless-эхо пишет в stderr, поэтому читаем его.
if have nvim; then
  vr=$(nvim --headless -c 'echo $VIMRUNTIME' -c 'q' 2>&1 >/dev/null | tr -d '\r\n')
  case $vr in
    "")            warn "nvim не сообщает VIMRUNTIME" ;;
    *nvim-dist*)   pass "nvim runtime: $vr" ;;
    *)             warn "nvim runtime вне nvim-dist: $vr" ;;
  esac
fi

head_ "node"
if have node; then
  nv=$(node -v 2>/dev/null)
  nmajor=$(printf '%s' "$nv" | sed 's/^v//; s/\..*//')
  if [ "${nmajor:-0}" -ge 22 ]; then
    pass "node $nv -> $(command -v node)"
  else
    warn "node $nv ниже 22 (make node)"
  fi
  if have npm; then
    pass "npm $(npm -v 2>/dev/null) -> $(command -v npm)"
    prefix=$(npm config get prefix 2>/dev/null)
    case $prefix in
      "$HOME"/*) pass "npm prefix $prefix (без sudo)" ;;
      *) warn "npm prefix $prefix (глобальные установки потребуют sudo; make npmrc)" ;;
    esac
  else
    fail "npm не найден"
  fi
  if [ -d "$HOME/.nvm/versions/node" ] && [ -n "$(ls -A "$HOME/.nvm/versions/node" 2>/dev/null)" ]; then
    dim "  nvm активен, его версии перекрывают ~/.local/bin: nvm ls"
  fi
  dupes=$(printf '%s\n' "$PATH" | tr ':' '\n' | grep -E '/node$|/nodejs' | sort -u | wc -l | tr -d ' ')
  [ "$dupes" -gt 1 ] && dim "  в PATH несколько node: which -a node"
else
  warn "node не найден (make node)"
fi

head_ "python"
if have uv; then
  pass "uv $(uv --version 2>/dev/null | awk '{print $2}')"
  py=$(uv python find 2>/dev/null || true)
  if [ -n "$py" ]; then pass "uv python: $py"; else warn "uv не видит интерпретатор (uv python install 3.13)"; fi
else
  warn "uv не найден (make bin PKGS=uv)"
fi
if command -v python3 >/dev/null 2>&1; then
  log "  python3: $(python3 -V 2>&1) -> $(command -v python3)"
  case $(python3 -V 2>&1) in
    *3.11*) dim "  похоже на системный 3.11 из python.org или venv; для новых проектов используйте uv" ;;
  esac
fi

head_ "docker"
if have docker; then
  pass "docker $(docker --version 2>/dev/null | sed 's/Docker version //; s/,.*//')"
  ctx=$(docker context show 2>/dev/null || echo "?")
  case $ctx in
    desktop-linux|default|"") log "  context: $ctx" ;;
    *) warn "docker context = $ctx (для Docker Desktop: docker context use desktop-linux)" ;;
  esac
  if docker info >/dev/null 2>&1; then pass "daemon доступен"; else warn "daemon не запущен"; fi
else
  dim "  --  docker отсутствует (ставится Docker Desktop, не пакетным менеджером)"
fi

head_ "MCP"
if [ -f "$HOME/.config/ai/mcp.json" ] || [ -L "$HOME/.config/ai/mcp.json" ]; then
  pass "канон ~/.config/ai/mcp.json"
  count=$(jq '.mcpServers | length' "$HOME/.config/ai/mcp.json" 2>/dev/null || echo "?")
  log "  серверов в каноне: $count"
else
  warn "нет ~/.config/ai/mcp.json (make install + make ai-sync)"
fi
for f in "$HOME/.claude/.claude.json" "$HOME/.claude.json"; do
  if [ -f "$f" ]; then
    n=$(jq '.mcpServers | length' "$f" 2>/dev/null || echo "?")
    pass "$(printf '~/%s' "${f#"$HOME"/}"): $n серверов"
  else
    dim "  --  ~/${f#"$HOME"/} нет (make ai-sync)"
  fi
done
OC=${OPENCODE_CONFIG_FILE:-$HOME/.config/opencode/opencode.jsonc}
if [ -f "$OC" ]; then
  if grep -q 'MCP-BEGIN' "$OC"; then
    pass "~/${OC#"$HOME"/}: блок MCP сгенерирован"
  else
    warn "~/${OC#"$HOME"/}: нет блока MCP-BEGIN (make ai-sync)"
  fi
else
  dim "  --  ~/${OC#"$HOME"/} нет"
fi

head_ "прочее"
if [ -f "$HOME/.config/secrets.d/secrets.env" ]; then
  pass "secrets.env есть"
  perms=$(ls -l "$HOME/.config/secrets.d/secrets.env" | awk '{print $1}' | tr -d '@+')
  case $perms in
    -rw-------) pass "права 600" ;;
    *) warn "права $perms (ожидалось 600: chmod 600 ~/.config/secrets.d/secrets.env)" ;;
  esac
else
  warn "нет ~/.config/secrets.d/secrets.env (make secrets)"
fi
if [ -f "$HOME/.config/git/local.gitconfig" ]; then
  pass "local.gitconfig есть"
else
  warn "нет ~/.config/git/local.gitconfig (make secrets)"
fi
for id in work personal; do
  f=$HOME/.config/git/$id.gitconfig
  if [ -f "$f" ]; then
    email=$(git config -f "$f" user.email 2>/dev/null || true)
    case $email in
      ""|*example.com*|*example*) warn "$id.gitconfig: заполните user.email" ;;
      *) pass "$id identity: $email" ;;
    esac
  else
    warn "нет ~/.config/git/$id.gitconfig (make secrets)"
  fi
done

printf '\n'
if [ "$fails" -eq 0 ]; then
  ok "проверка пройдена"
else
  err "проблем: $fails"
fi
printf '\n'
exit 0
