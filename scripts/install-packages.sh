#!/bin/sh
# Ставит пакеты из packages/packages.csv.
#
# Linux: apt-get -> dnf (первый найденный). sudo только если не root.
# macOS: пакетного менеджера нет, печатает отчёт и подсказывает `make bin`.
#
#   sh scripts/install-packages.sh             установить
#   sh scripts/install-packages.sh --dry-run   показать план
#   PACKAGE_MANAGER=apt sh scripts/install-packages.sh
set -eu

. "$(dirname "$0")/lib.sh"
REPO_ROOT=$(repo_root_from "$0")
CSV=$REPO_ROOT/packages/packages.csv

DRY=0
for a in "$@"; do
  case $a in
    --dry-run|-n) DRY=1 ;;
    *) die "неизвестный аргумент: $a" ;;
  esac
done

[ -f "$CSV" ] || die "нет файла $CSV"
detect_os

# --- выбор менеджера ---
PM=${PACKAGE_MANAGER:-}
if [ -z "$PM" ]; then
  if have apt-get; then PM=apt
  elif have dnf; then PM=dnf
  fi
fi

# --- чтение csv: name,apt,dnf,macos,description ---
rows=$(mktemp); trap 'rm -f "$rows"' EXIT INT TERM
tail -n +2 "$CSV" | grep -v '^[[:space:]]*$' > "$rows"

list_pkgs() { # $1 = колонка 2 или 3
  cut -d, -f1,3,4,5 "$rows" >/dev/null 2>&1 || true
}

if [ -z "$PM" ]; then
  head_ "Пакетный менеджер не найден"
  log "macOS и системы без apt/dnf: используйте статические бинарники."
  log ""
  while IFS=, read -r name apt dnf macos desc; do
    [ "$name" = name ] && continue
    [ -z "$name" ] && continue
    [ "$macos" = skip ] && continue
    case $name in
      fd-find)   bin=fdfind; tool=fd ;;
      bat)       bin=bat;    tool=bat ;;
      git-delta) bin=delta;  tool=delta ;;
      tealdeer)  bin=tldr;   tool=tldr ;;
      ripgrep)   bin=rg;     tool=rg ;;
      neovim)    bin=nvim;   tool=nvim ;;
      nodejs)    bin=node;   tool="" ;;
      qsv)       bin=qsv;    tool=qsv ;;
      *)         bin=$name;  tool=$name ;;
    esac
    if have "$bin" || [ "$macos" = system ]; then
      printf '  %sok%s  %-12s %s\n' "$C_GREEN" "$C_RESET" "$name" "$desc"
    elif [ "$name" = nodejs ]; then
      printf '  %s--%s  %-12s make node\n' "$C_YELLOW" "$C_RESET" "$name"
    else
      printf '  %s--%s  %-12s make bin PKGS="%s"\n' "$C_YELLOW" "$C_RESET" "$name" "$tool"
    fi
  done < "$rows"
  log ""
  log "Можно всё сразу:  make bin"
  log ""
  exit 0
fi

if [ "$PM" = apt ]; then
  if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
  col=2
else
  if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
  col=3
fi

# --- собрать отсутствующее ---
missing=""
count=0
while IFS=, read -r name apt dnf macos desc; do
  [ "$name" = name ] && continue
  [ -z "$name" ] && continue
  if [ "$PM" = apt ]; then pkg=$apt; else pkg=$dnf; fi
  [ -z "$pkg" ] && continue

  case $name in
    fd-find)   bin=fdfind ;;
    bat)       bin=bat ;;
    git-delta) bin=delta ;;
    tealdeer)  bin=tldr ;;
    shellcheck) bin=shellcheck ;;
    *)         bin=$name ;;
  esac

  if have "$bin"; then
    continue
  fi
  missing="$missing $pkg"
  count=$((count + 1))
done < "$rows"

head_ "Установка пакетов ($PM)"
if [ "$count" -eq 0 ]; then
  ok "всё уже установлено"
  exit 0
fi

log "не хватает: $count"
log " " $missing | tr ' ' '\n' | grep -v '^$' | sed 's/^/  - /'

if [ "$DRY" -eq 1 ]; then
  dim "  (dry-run: ничего не запускаю)"
  exit 0
fi

if [ "$PM" = apt ]; then
  $SUDO apt-get update -qq
  # shellcheck disable=SC2086
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $missing
else
  # shellcheck disable=SC2086
  $SUDO dnf install -y $missing
fi

# Debian переименовывает бинарники — даём привычные имена
mkdir -p "$HOME/.local/bin"
link_alias() { # $1 = реальный, $2 = желаемый
  if have "$1" && ! have "$2"; then
    ln -sf "$(command -v "$1")" "$HOME/.local/bin/$2"
    ok "$2 -> $(command -v "$1")"
  fi
}
link_alias fdfind fd
link_alias batcat bat

ok "готово"
