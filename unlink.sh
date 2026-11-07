#!/bin/sh
# Снимает симлинки в $HOME, указывающие внутрь этого репозитория.
# Ничего, что указывает в другие места, не трогает.
set -eu

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

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

removed=0
kept=0
list=$(mktemp)
trap 'rm -f "$list"' EXIT INT TERM

find "$SRC" -type f | sed "s|^$SRC||" > "$list"

while IFS= read -r rel; do
  target=$HOME$rel
  [ -L "$target" ] || continue
  link=$(readlink "$target")
  case $link in
    "$SRC"/*) ;;
    *) kept=$((kept + 1)); continue ;;
  esac
  if [ "$DRY" -eq 1 ]; then
    printf '  plan rm ~%s\n' "$rel"
  else
    rm "$target"
    printf '  rm   ~%s\n' "$rel"
  fi
  removed=$((removed + 1))
done < "$list"

printf '\nудалено симлинков: %d\n' "$removed"
[ "$kept" -gt 0 ] && printf 'пропущено чужих симлинков: %d\n' "$kept"
printf 'бэкапы в %s/backup не тронуты\n\n' "$REPO_ROOT"
