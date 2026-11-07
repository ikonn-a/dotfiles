#!/bin/sh
# Ставит Node.js в ~/.local/share/nodejs без brew, nvm и root.
#
#   sh scripts/install-node.sh                  последняя LTS
#   sh scripts/install-node.sh 24.22.2          конкретная версия
#   sh scripts/install-node.sh --current        последний Current (не LTS)
#   sh scripts/install-node.sh --dry-run        показать план
#   sh scripts/install-node.sh --list           последние версии
#
# Бинарники node/npm/npx/corepack попадают в ~/.local/bin, который идёт в PATH
# раньше /usr/local/bin — то есть выбранная версия становится основной.
set -eu

. "$(dirname "$0")/lib.sh"
detect_os

PREFIX="${NODE_PREFIX:-$HOME/.local/share/nodejs}"
BINDIR="$HOME/.local/bin"
INDEX_URL="https://nodejs.org/dist/index.json"
MIN_MAJOR=22

DRY=0
WANT=""
CHANNEL=lts
for a in "$@"; do
  case $a in
    --dry-run|-n) DRY=1 ;;
    --list) CHANNEL=list ;;
    --current) CHANNEL=current ;;
    --lts) CHANNEL=lts ;;
    -*) die "неизвестный флаг: $a" ;;
    *) WANT=$a ;;
  esac
done

need_curl() { have curl || die "нужен curl"; }

# --- версии с nodejs.org ---
fetch_index() {
  need_curl
  curl -fsSL "$INDEX_URL" -o "$tmpdir/index.json" || die "не удалось получить список версий"
}

pick_version() {
  if [ -n "$WANT" ]; then
    v=${WANT#v}
    printf 'v%s' "$v"
    return
  fi
  fetch_index
  case $CHANNEL in
    current)
      jq -r '[.[] | select(.version | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))][0].version' "$tmpdir/index.json"
      ;;
    *)
      jq -r '[.[] | select(.lts != false) | select(.version | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))][0].version' "$tmpdir/index.json"
      ;;
  esac
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT INT TERM

if [ "$CHANNEL" = list ]; then
  fetch_index
  head_ "Node.js на nodejs.org"
  log "  LTS:"
  jq -r '[.[] | select(.lts != false) | select(.version | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))][:5][] | "    \(.version)  \(.lts)  npm=\(.npm)"' "$tmpdir/index.json"
  log "  Current:"
  jq -r '[.[] | select(.version | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))][:3][] | "    \(.version)"' "$tmpdir/index.json"
  printf '\n'
  exit 0
fi

VERSION=$(pick_version)
[ -n "$VERSION" ] && [ "$VERSION" != "null" ] || die "не удалось определить версию"

major=${VERSION#v}
major=${major%%.*}
[ "$major" -ge "$MIN_MAJOR" ] || warn "версия $VERSION ниже требуемой $MIN_MAJOR"

case $OS-$ARCH in
  darwin-arm64)  plat=darwin-arm64 ;;
  darwin-x86_64) plat=darwin-x64 ;;
  linux-arm64)   plat=linux-arm64 ;;
  linux-x86_64)  plat=linux-x64 ;;
  *) die "нет сборки для $OS/$ARCH" ;;
esac

NAME="node-$VERSION-$plat"
DIR="$PREFIX/$VERSION"
URL="https://nodejs.org/dist/$VERSION/$NAME.tar.gz"
SHASUM_URL="https://nodejs.org/dist/$VERSION/SHASUMS256.txt"

head_ "Node.js $VERSION ($OS/$ARCH)"
log "  каталог: $DIR"

if [ -x "$DIR/bin/node" ] && [ "$DRY" -eq 0 ]; then
  ok "уже установлено: $("$DIR/bin/node" -v)"
else
  if [ "$DRY" -eq 1 ]; then
    dim "  plan скачать $URL"
    dim "  plan проверить SHA256 по SHASUMS256.txt"
    dim "  plan распаковать в $DIR"
  else
    info "скачиваю $(basename "$URL")"
    curl -fsSL "$URL" -o "$tmpdir/node.tar.gz" || die "ошибка загрузки"
    info "проверяю SHA256"
    expected=$(curl -fsSL "$SHASUM_URL" | awk -v n="$NAME.tar.gz" '$2==n {print $1}')
    if [ -n "$expected" ]; then
      actual=$(shasum -a 256 "$tmpdir/node.tar.gz" 2>/dev/null | awk '{print $1}')
      [ "$actual" = "$expected" ] || die "контрольная сумма не совпала"
      ok "SHA256 совпала"
    else
      warn "нет записи в SHASUMS256.txt, пропускаю проверку"
    fi
    mkdir -p "$DIR"
    tar -xzf "$tmpdir/node.tar.gz" -C "$DIR" --strip-components=1 || die "ошибка распаковки"
    ok "распаковано в $DIR"
  fi
fi

# --- симлинки в ~/.local/bin ---
# corepack исключён из Node начиная с 25.x; линкуем только то, что есть.
if [ "$DRY" -eq 1 ]; then
  for b in node npm npx corepack; do
    if [ -x "$DIR/bin/$b" ]; then
      dim "  plan link ~/.local/bin/$b"
    elif [ "$b" = corepack ]; then
      dim "  --   corepack не входит в Node $VERSION (npm i -g corepack)"
    fi
  done
else
  mkdir -p "$BINDIR"
  for b in node npm npx corepack; do
    if [ -x "$DIR/bin/$b" ]; then
      ln -sf "$DIR/bin/$b" "$BINDIR/$b"
      ok "~/.local/bin/$b -> $DIR/bin/$b"
    elif [ "$b" = corepack ]; then
      dim "  corepack не поставляется с Node $VERSION (при необходимости: npm i -g corepack)"
    fi
  done
fi

if [ "$DRY" -eq 0 ]; then
  printf '\n'
  if [ -x "$BINDIR/node" ]; then
    log "  node: $("$BINDIR/node" -v)   npm: $("$BINDIR/npm" -v 2>/dev/null || echo '?')"
  fi
  log "  в текущей оболочке:  hash -r  (или exec zsh)"
  dim "  проверка:  which -a node && node -v"
fi
printf '\n'
