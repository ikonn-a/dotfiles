# ~/.config/zsh/.zshrc — интерактивный shell.
# Режим emacs (vi-mode намеренно не включаем).

# --- история ---
# macOS /etc/zshrc выставляет HISTFILE по-своему и читается раньше нас,
# поэтому фиксируем путь здесь ещё раз.
export HISTFILE="$ZDOTDIR/history"
mkdir -p "$ZDOTDIR" 2>/dev/null

setopt INC_APPEND_HISTORY
setopt HIST_FIND_NO_DUPS
setopt HIST_SAVE_NO_DUPS
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY
setopt SHARE_HISTORY
HISTSIZE=100000
SAVEHIST=$HISTSIZE

# --- клавиши ---
bindkey -e
stty stop undef 2>/dev/null

# --- автодополнение ---
autoload -Uz colors && colors
autoload -Uz compinit
zmodload zsh/complist 2>/dev/null
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS COMPLETE_IN_WORD
_comp_options+=(globdots)
compinit -C

# Дополнение yandex-cloud требует compinit, поэтому подключается здесь
if [ -f "$HOME/yandex-cloud/completion.zsh.inc" ]; then
  . "$HOME/yandex-cloud/completion.zsh.inc"
fi

# --- промпт ---
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
else
  NEWLINE=$'\n'
  PS1="%B%{$fg[red]%}[%{$fg[yellow]%}%*%{$fg[red]%}] %{$fg[magenta]%}%~%b${NEWLINE}  %{$fg[magenta]%}%#%{$fg[red]%} %{$reset_color%}"
fi

# --- загрузка файлов ---
[ -f "$ZDOTDIR/aliasrc" ] && . "$ZDOTDIR/aliasrc"
[ -f "$ZDOTDIR/functions.zsh" ] && . "$ZDOTDIR/functions.zsh"

# Секреты и адреса сервисов (вне репозитория)
[ -f "$HOME/.config/secrets.d/secrets.env" ] && . "$HOME/.config/secrets.d/secrets.env"

# Машинные доработки (вне репозитория)
[ -f "$ZDOTDIR/local.zsh" ] && . "$ZDOTDIR/local.zsh"

# --- интеграции, если установлены ---
if command -v fzf >/dev/null 2>&1; then
  if [ -n "${FZF_INIT_SH:-}" ]; then
    . "$FZF_INIT_SH"
  elif [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]; then
    . /usr/share/doc/fzf/examples/key-bindings.zsh
  else
    eval "$(fzf --zsh 2>/dev/null)" 2>/dev/null || true
  fi
  export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:---height 40% --layout=reverse --border}"
fi

command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook zsh)"
command -v thefuck >/dev/null 2>&1 && eval "$(thefuck --alias 2>/dev/null)" 2>/dev/null

# --- zsh-плагины из системных каталогов (Linux) ---
for _f in /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
          /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
          /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
          /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh; do
  [ -f "$_f" ] && . "$_f"
done
unset _f
