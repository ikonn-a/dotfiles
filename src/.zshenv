# ~/.zshenv — читается всеми shell'ами (в том числе неинтерактивными).
# Здесь только то, что должно быть доступно всегда: ZDOTDIR, XDG, PATH.

# zsh читает остальные конфиги из $ZDOTDIR
export ZDOTDIR="$HOME/.config/zsh"

# XDG
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"

# История живёт рядом с конфигом
export HISTFILE="$ZDOTDIR/history"

# PATH: пользовательские каталоги первыми.
# Дубли убираются через typeset -U в zsh; для sh-совместимости это no-op.
path=(
  "$HOME/.local/bin"
  "$HOME/bin"
  /usr/local/bin
  /usr/bin
  /bin
  /usr/sbin
  /sbin
  $path
)
# opencode ставит себя сюда
[ -d "$HOME/.opencode/bin" ] && path=("$HOME/.opencode/bin" $path)
typeset -U path 2>/dev/null || true
export PATH

# Редактор: nvim -> code --wait -> vi
if command -v nvim >/dev/null 2>&1; then
  export EDITOR=nvim VISUAL=nvim
elif command -v code >/dev/null 2>&1; then
  export EDITOR="code --wait" VISUAL="code --wait"
else
  export EDITOR=vi VISUAL=vi
fi

# Корпоративный корневой сертификат для Node (npm/npx/MCP-серверы).
# Файл машинно-зависимый, поэтому подключается только если существует.
if [ -f "$HOME/st-ca-root.pem" ]; then
  export NODE_EXTRA_CA_CERTS="$HOME/st-ca-root.pem"
fi

# npm: глобальные пакеты в ~/.local, без sudo.
# Сам конфиг — ~/.npmrc (он читается npm всегда, дополнительных переменных не нужно).
export NPM_CONFIG_PREFIX="$HOME/.local"

# Меньше шума и мусора
export LESS=-R
export LESSHISTFILE=-
