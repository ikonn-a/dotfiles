#!/bin/sh
# Общие функции для скриптов dotfiles. Подключается через `. scripts/lib.sh`.
# POSIX sh, рассчитан на bash 3.2 (macOS) и dash.

if [ -t 1 ]; then
  C_RESET=$(printf '\033[0m')
  C_BOLD=$(printf '\033[1m')
  C_RED=$(printf '\033[31m')
  C_GREEN=$(printf '\033[32m')
  C_YELLOW=$(printf '\033[33m')
  C_BLUE=$(printf '\033[34m')
  C_DIM=$(printf '\033[2m')
else
  C_RESET=; C_BOLD=; C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=; C_DIM=
fi

log()  { printf '%s\n' "$*"; }
info() { printf '%s::%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s ok %s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%serr %s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
head_() { printf '\n%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }
dim()  { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }

die() { err "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# ОС и архитектура в нормализованном виде
detect_os() {
  case $(uname -s) in
    Darwin) OS=darwin ;;
    Linux)  OS=linux ;;
    *)      OS=unknown ;;
  esac
  case $(uname -m) in
    arm64|aarch64) ARCH=arm64 ;;
    x86_64|amd64)  ARCH=x86_64 ;;
    *)             ARCH=$(uname -m) ;;
  esac
  export OS ARCH
}

# Разрешить путь без перехода по симлинкам файла
resolve_path() {
  _d=$(cd -P "$(dirname "$1")" >/dev/null 2>&1 && pwd) || return 1
  printf '%s/%s' "$_d" "$(basename "$1")"
}

# Корень репозитория относительно текущего скрипта
repo_root_from() {
  _self=$1
  while [ -L "$_self" ]; do
    _dir=$(cd -P "$(dirname "$_self")" >/dev/null 2>&1 && pwd)
    _self=$(readlink "$_self")
    case $_self in
      /*) ;;
      *) _self=$_dir/$_self ;;
    esac
  done
  cd -P "$(dirname "$_self")/.." >/dev/null 2>&1 && pwd
}
