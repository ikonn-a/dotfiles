#!/bin/sh
# Синтаксическая проверка конфигов и скриптов. Ничего не меняет.
set -u

. "$(dirname "$0")/lib.sh"
REPO_ROOT=$(repo_root_from "$0")

fails=0

head_ "zsh"
for f in "$REPO_ROOT"/src/.zshenv "$REPO_ROOT"/src/.config/zsh/.zshrc \
         "$REPO_ROOT"/src/.config/zsh/.zprofile "$REPO_ROOT"/src/.config/zsh/aliasrc \
         "$REPO_ROOT"/src/.config/zsh/functions.zsh \
         "$REPO_ROOT"/src/.config/zsh/local.example.zsh; do
  [ -f "$f" ] || { warn "нет файла $f"; fails=$((fails + 1)); continue; }
  if zsh -n "$f" 2>/dev/null; then
    ok "${f#$REPO_ROOT/}"
  else
    err "${f#$REPO_ROOT/}"
    zsh -n "$f" 2>&1 | sed 's/^/    /'
    fails=$((fails + 1))
  fi
done

head_ "sh"
for f in "$REPO_ROOT"/install.sh "$REPO_ROOT"/unlink.sh "$REPO_ROOT"/scripts/*.sh; do
  [ -f "$f" ] || continue
  if sh -n "$f" 2>/dev/null; then
    ok "${f#$REPO_ROOT/}"
  else
    err "${f#$REPO_ROOT/}"
    sh -n "$f" 2>&1 | sed 's/^/    /'
    fails=$((fails + 1))
  fi
done

head_ "shellcheck"
if have shellcheck; then
  if shellcheck -S warning "$REPO_ROOT"/install.sh "$REPO_ROOT"/unlink.sh "$REPO_ROOT"/scripts/*.sh; then
    ok "без замечаний"
  else
    warn "есть замечания (см. выше)"
  fi
else
  dim "  --  shellcheck не установлен (make bin не ставит; apt: shellcheck)"
fi

head_ "make"
if make -n -C "$REPO_ROOT" help >/dev/null 2>&1; then
  ok "Makefile читается"
else
  err "Makefile сломан"
  fails=$((fails + 1))
fi

head_ "gitconfig"
if git config -f "$REPO_ROOT/src/.gitconfig" --list >/dev/null 2>&1; then
  ok "src/.gitconfig"
else
  err "src/.gitconfig"
  fails=$((fails + 1))
fi

head_ "vscode"
vsc=$REPO_ROOT/src/.config/vscode
if [ -f "$vsc/User/settings.json" ]; then
  if have jq; then
    if jq -e . "$vsc/User/settings.json" >/dev/null 2>&1; then
      ok "settings.json (валидный JSON, без комментариев)"
    else
      err "settings.json — не JSON (комментарии в управляемом файле недопустимы)"
      jq -e . "$vsc/User/settings.json" 2>&1 | sed -n '1,3p' | sed 's/^/    /'
      fails=$((fails + 1))
    fi
  else
    dim "  --  jq не установлен, settings.json не проверен"
  fi
else
  err "нет $vsc/User/settings.json"
  fails=$((fails + 1))
fi
if [ -f "$vsc/extensions.txt" ]; then
  bad=$(sed 's/#.*//' "$vsc/extensions.txt" | tr -d ' \t\r' | grep -v '^$' \
        | grep -vE '^[A-Za-z0-9][A-Za-z0-9_-]*\.[A-Za-z0-9][A-Za-z0-9_.-]*$' || true)
  if [ -z "$bad" ]; then
    ok "extensions.txt ($(sed 's/#.*//' "$vsc/extensions.txt" | tr -d ' \t\r' | grep -c .) шт.)"
  else
    err "extensions.txt: странные строки:"
    printf '%s\n' "$bad" | sed 's/^/    /'
    fails=$((fails + 1))
  fi
else
  err "нет $vsc/extensions.txt"
  fails=$((fails + 1))
fi
if make -n -C "$REPO_ROOT" vscode-settings >/dev/null 2>&1; then
  ok "make vscode-settings"
else
  err "цель vscode-settings сломана"
  fails=$((fails + 1))
fi

printf '\n'
if [ "$fails" -eq 0 ]; then ok "проверка пройдена"; else err "ошибок: $fails"; fi
printf '\n'
[ "$fails" -eq 0 ]
