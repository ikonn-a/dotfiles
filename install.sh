#!/bin/sh
# Симлинкует файлы из src/ в $HOME. POSIX sh, без внешних зависимостей.
#
#   sh install.sh            создать симлинки (старое -> backup/<дата>/)
#   sh install.sh --dry-run  показать план, ничего не менять
set -eu

DRY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY=1 ;;
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'install.sh: неизвестный аргумент: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

# --- корень репозитория (работает и через симлинк) ---
self=$0
while [ -L "$self" ]; do
  _dir=$(cd -P "$(dirname "$self")" >/dev/null 2>&1 && pwd)
  self=$(readlink "$self")
  case $self in
    /*) ;;
    *) self=$_dir/$self ;;
  esac
done
REPO_ROOT=$(cd -P "$(dirname "$self")" >/dev/null 2>&1 && pwd)
SRC=$REPO_ROOT/src

[ -d "$SRC" ] || { printf 'нет каталога %s\n' "$SRC" >&2; exit 1; }

STAMP=$(date +%Y_%m_%d-%H_%M_%S)
BACKUP=$REPO_ROOT/backup/$STAMP
# Два запуска в одну секунду не должны перезаписывать бэкапы друг друга.
_n=1
while [ -d "$BACKUP" ]; do
  _n=$((_n + 1))
  BACKUP=$REPO_ROOT/backup/$STAMP-$_n
done
[ "$_n" -gt 1 ] && STAMP=$STAMP-$_n
unset _n

if [ -t 1 ]; then
  B=$(printf '\033[1m'); R=$(printf '\033[0m')
  G=$(printf '\033[32m'); Y=$(printf '\033[33m'); C=$(printf '\033[36m')
else
  B=; R=; G=; Y=; C=
fi

say() { printf '%s\n' "$*"; }
act() { if [ "$DRY" -eq 1 ]; then printf '%s\n' "  ${Y}plan${R} $*"; else printf '%s\n' "  $*"; fi; }
act_say() { if [ "$DRY" -eq 1 ]; then printf '%s\n' "${Y}plan${R} $*"; else printf '%s\n' "$*"; fi; }

# Разрешить путь файла без перехода по симлинку (только нормализация каталога)
resolve() {
  d=$(cd -P "$(dirname "$1")" >/dev/null 2>&1 && pwd) || return 1
  printf '%s/%s' "$d" "$(basename "$1")"
}

# Развернуть симлинк в абсолютный путь (одно звено или вся цепочка)
resolve_link() {
  link=$1
  d=$(cd -P "$(dirname "$link")" >/dev/null 2>&1 && pwd) || return 1
  depth=0
  while [ -L "$link" ] && [ "$depth" -lt 40 ]; do
    t=$(readlink "$link")
    case $t in
      /*) link=$t ;;
      *)  link=$d/$t ;;
    esac
    d=$(cd -P "$(dirname "$link")" >/dev/null 2>&1 && pwd) || { printf '%s' "$link"; return 0; }
    depth=$((depth + 1))
  done
  printf '%s/%s' "$d" "$(basename "$link")"
}

DIRS=$(mktemp) || exit 1
FILES=$(mktemp) || exit 1
trap 'rm -f "$DIRS" "$FILES"' EXIT INT TERM

find "$SRC" -type d > "$DIRS"
find "$SRC" -type f > "$FILES"

printf '\n%s dotfiles %s\n' "$B" "$R"
printf '  source: %s\n  home:   %s\n' "$SRC" "$HOME"
[ "$DRY" -eq 1 ] && printf '  режим:  %sdry-run%s\n' "$Y" "$R"
printf '\n'

# --- 1. каталоги ---
say "${B}[1/2] каталоги${R}"
while IFS= read -r d; do
  rel=${d#"$SRC"}
  [ -n "$rel" ] || continue
  target=$HOME$rel
  if [ -d "$target" ] && [ ! -L "$target" ]; then
    continue
  fi
  if [ -L "$target" ]; then
    act_say "${Y}каталог-симлинк, пропускаю${R} ~$rel -> $(readlink "$target")"
    continue
  fi
  act "mkdir -p ~$rel"
  [ "$DRY" -eq 1 ] || mkdir -p "$target"
done < "$DIRS"

# --- 2. файлы ---
say ""
say "${B}[2/2] симлинки${R}"

linked=0
skipped=0
backed=0

while IFS= read -r f; do
  rel=${f#"$SRC"}
  [ -n "$rel" ] || continue
  target=$HOME$rel
  parent=$(dirname "$target")
  [ "$DRY" -eq 1 ] || mkdir -p "$parent"

  want=$(resolve "$f")

  if [ -L "$target" ]; then
    have=$(resolve_link "$target" 2>/dev/null || printf '%s' "$target")
    if [ "$have" = "$want" ]; then
      skipped=$((skipped + 1))
      continue
    fi
  fi

  if [ -e "$target" ] || [ -L "$target" ]; then
    dest=$BACKUP$rel
    act_say "${C}backup${R} ~$rel -> backup/$STAMP$rel"
    if [ "$DRY" -eq 0 ]; then
      mkdir -p "$(dirname "$dest")"
      mv "$target" "$dest"
    fi
    backed=$((backed + 1))
  fi

  act_say "${G}link${R}   ~$rel"
  if [ "$DRY" -eq 0 ]; then
    ln -s "$f" "$target"
  fi
  linked=$((linked + 1))
done < "$FILES"

# --- 3. старые zsh-файлы в $HOME, которые больше не читаются ---
# При ZDOTDIR zsh берёт .zshrc/.zprofile из $ZDOTDIR, поэтому файлы в $HOME
# становятся мёртвым грузом. Убираем их в бэкап, чтобы не путали.
stale=0
for f in .zshrc .zprofile .zlogin .zlogout; do
  target=$HOME/$f
  [ -e "$target" ] || [ -L "$target" ] || continue
  if [ -L "$target" ]; then
    case $(readlink "$target") in
      "$SRC"/*) continue ;;
    esac
  fi
  act_say "${C}archive${R}  ~/$f -> backup/$STAMP/$f"
  if [ "$DRY" -eq 0 ]; then
    mkdir -p "$(dirname "$BACKUP/$f")"
    mv "$target" "$BACKUP/$f"
  fi
  stale=$((stale + 1))
done

printf '\n'
if [ "$DRY" -eq 1 ]; then
  printf '%s план: %d ссылок, %d бэкапов, %d уже на месте%s\n\n' "$B" "$linked" "$backed" "$skipped" "$R"
else
  printf '%s готово: %d ссылок, %d бэкапов, %d уже на месте%s\n' "$B" "$linked" "$backed" "$skipped" "$R"
  [ "$backed" -gt 0 ] && printf '  старые файлы: %s\n' "$BACKUP"
  if [ "$stale" -gt 0 ]; then
    printf '  устаревшие файлы в $HOME убраны в бэкап: %d\n' "$stale"
    printf '  проверьте, не нужно ли что-то перенести в ~/.config/zsh/local.zsh\n'
    printf '  (шаблон: ~/.config/zsh/local.example.zsh)\n'
  fi
  printf '\n  дальше: exec zsh  (или откройте новый терминал)\n'
fi
printf '\n'
