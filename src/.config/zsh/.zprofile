# ~/.config/zsh/.zprofile — только для login-shell'ов.
# Здесь всё, что нужно один раз на вход в систему и зависит от машины.

# Docker Desktop: плагины docker/compose живут тут
if [ -d "$HOME/.docker/bin" ]; then
  case ":$PATH:" in
    *":$HOME/.docker/bin:"*) ;;
    *) path=("$HOME/.docker/bin" $path) ;;
  esac
fi

# yandex-cloud CLI: PATH и автодополнение (если установлен).
# completion.zsh.inc вызывает compdef, поэтому грузим его только после compinit —
# то есть из .zshrc, а не здесь. Здесь только PATH.
if [ -f "$HOME/yandex-cloud/path.bash.inc" ]; then
  . "$HOME/yandex-cloud/path.bash.inc"
fi

# nvm (если есть и включён). Отключается: export DOTFILES_NO_NVM=1
# ВНИМАНИЕ: nvm.sh добавляет свой node в начало PATH и перекрывает
# версию из ~/.local/bin. Если nvm не нужен — не заводите в нём версий.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [ -z "${DOTFILES_NO_NVM:-}" ] && [ -s "$NVM_DIR/nvm.sh" ]; then
  . "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
fi

typeset -U path 2>/dev/null || true
export PATH
