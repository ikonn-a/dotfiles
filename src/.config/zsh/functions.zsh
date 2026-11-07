# Функции оболочки.

# mkdir + cd
mkcd() {
  [ -n "${1:-}" ] || { echo "usage: mkcd <dir>" >&2; return 2; }
  mkdir -p "$1" && cd "$1"
}

# Быстрое извлечение архивов
extract() {
  [ -f "${1:-}" ] || { echo "extract: нет файла: ${1:-}" >&2; return 1; }
  case "$1" in
    *.tar.bz2|*.tbz2) tar xjf "$1" ;;
    *.tar.gz|*.tgz)   tar xzf "$1" ;;
    *.tar.xz|*.txz)   tar xJf "$1" ;;
    *.tar)            tar xf  "$1" ;;
    *.zip)            unzip "$1" ;;
    *.gz)             gunzip "$1" ;;
    *) echo "extract: неизвестный формат: $1" >&2; return 1 ;;
  esac
}

# git: создать ветку из Jira-ключа или имени
gbr() {
  [ -n "${1:-}" ] || { echo "usage: gbr <name>" >&2; return 2; }
  git checkout -b "$1"
}

# служебное: что занимает место в текущем каталоге
biggest() {
  du -xhd1 "${1:-.}" 2>/dev/null | sort -h | tail -20
}

# показать порт процесса
portpid() {
  [ -n "${1:-}" ] || { echo "usage: portpid <port>" >&2; return 2; }
  lsof -nP -iTCP:"$1" -sTCP:LISTEN 2>/dev/null
}
