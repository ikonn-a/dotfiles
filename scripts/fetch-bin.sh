#!/bin/sh
# Скачивает статические релизы CLI в ~/.local/bin. Без brew, без root.
#
#   sh scripts/fetch-bin.sh               все из списка по умолчанию
#   sh scripts/fetch-bin.sh rg fd         только указанные
#   sh scripts/fetch-bin.sh --list        что умеет
#   sh scripts/fetch-bin.sh --dry-run     показать план
#
# Требуется curl; unzip нужен только для gh на macOS.
set -eu

. "$(dirname "$0")/lib.sh"
detect_os

DEST="$HOME/.local/bin"
SHARE="$HOME/.local/share"
DEFAULT="rg fd bat eza delta yq starship fzf gh uv zoxide direnv nvim qsv"

DRY=0
TOOLS=""
for a in "$@"; do
  case $a in
    --list) TOOLS="--list" ;;
    --dry-run|-n) DRY=1 ;;
    -*) die "неизвестный флаг: $a" ;;
    *) TOOLS="$TOOLS $a" ;;
  esac
done

if [ "$TOOLS" = "--list" ]; then
  head_ "Доступно"
  printf '  rg fd bat eza delta yq starship fzf gh uv zoxide direnv\n'
  printf '  nvim qsv\n\n'
  dim "  nvim ставится деревом в ~/.local/share/nvim-dist (нужен runtime)"
  dim "  qsv ставит qsvlite из zip (17M вместо 152M)"
  printf '\n'
  exit 0
fi

[ -n "$TOOLS" ] || TOOLS=$DEFAULT

have curl || die "нужен curl"

if [ -z "$DEST" ]; then DEST="$HOME/.local/bin"; fi
[ "$DRY" -eq 1 ] || mkdir -p "$DEST"

# --- вспомогательное ---
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT INT TERM

latest_tag() { # $1 = owner/repo -> vX.Y.Z
  curl -fsSI "https://github.com/$1/releases/latest" 2>/dev/null \
    | tr -d '\r' \
    | awk 'tolower($1)=="location:" {print $2}' \
    | sed 's|.*/tag/||'
}

# arch-токены для разных проектов
a_gnu()  { [ "$ARCH" = arm64 ] && echo aarch64 || echo x86_64; }
a_go()   { [ "$ARCH" = arm64 ] && echo arm64 || echo x86_64; }      # eza, fzf, gh, yq
a_amd()  { [ "$ARCH" = arm64 ] && echo arm64 || echo amd64; }

install_tar() { # $1 = url, $2 = бинарь внутри архива
  url=$1 bin=$2
  if [ "$DRY" -eq 1 ]; then dim "  plan $bin <- $(basename "$url")"; return 0; fi
  info "скачиваю $bin"
  curl -fsSL "$url" -o "$tmpdir/dl.tar.gz" || { warn "не удалось скачать $bin"; return 1; }
  tar -xzf "$tmpdir/dl.tar.gz" -C "$tmpdir" 2>/dev/null || { warn "битый архив $bin"; return 1; }
  found=$(find "$tmpdir" -type f -name "$bin" -perm -u+x | head -1)
  [ -n "$found" ] || found=$(find "$tmpdir" -type f -name "$bin" | head -1)
  [ -n "$found" ] || { warn "в архиве нет $bin"; return 1; }
  mv "$found" "$DEST/$bin"
  chmod +x "$DEST/$bin"
  ok "$DEST/$bin"
  rm -f "$tmpdir/dl.tar.gz"
  find "$tmpdir" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} + 2>/dev/null || true
}

install_raw() { # $1 = url, $2 = имя бинаря
  url=$1 bin=$2
  if [ "$DRY" -eq 1 ]; then dim "  plan $bin <- $(basename "$url")"; return 0; fi
  info "скачиваю $bin"
  curl -fsSL "$url" -o "$DEST/$bin" || { warn "не удалось скачать $bin"; rm -f "$DEST/$bin"; return 1; }
  chmod +x "$DEST/$bin"
  ok "$DEST/$bin"
}

install_zip() { # $1 = url, $2 = бинарь внутри
  url=$1 bin=$2
  have unzip || { warn "для $bin нужен unzip"; return 1; }
  if [ "$DRY" -eq 1 ]; then dim "  plan $bin <- $(basename "$url")"; return 0; fi
  info "скачиваю $bin"
  curl -fsSL "$url" -o "$tmpdir/dl.zip" || { warn "не удалось скачать $bin"; return 1; }
  unzip -qo "$tmpdir/dl.zip" -d "$tmpdir" || { warn "битый архив $bin"; return 1; }
  found=$(find "$tmpdir" -type f -name "$bin" | head -1)
  [ -n "$found" ] || { warn "в архиве нет $bin"; return 1; }
  mv "$found" "$DEST/$bin"
  chmod +x "$DEST/$bin"
  ok "$DEST/$bin"
  rm -f "$tmpdir/dl.zip"
  find "$tmpdir" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} + 2>/dev/null || true
}

# Распаковать ЦЕЛОЕ дерево (бинарник + lib/ + share/) и залинковать бинарь.
# Нужно для nvim: одному бинарнику не хватает runtime.
# $1 = url, $2 = каталог назначения в ~/.local/share, $3 = бинарь внутри bin/
install_tree() {
  url=$1 name=$2 bin=$3
  if [ "$DRY" -eq 1 ]; then dim "  plan $bin <- дерево $(basename "$url") -> $SHARE/$name"; return 0; fi
  info "скачиваю $bin (дерево)"
  curl -fsSL "$url" -o "$tmpdir/tree.tar.gz" || { warn "не удалось скачать $bin"; return 1; }
  mkdir -p "$tmpdir/tree"
  tar -xzf "$tmpdir/tree.tar.gz" -C "$tmpdir/tree" 2>/dev/null || { warn "битый архив $bin"; return 1; }
  top=$(find "$tmpdir/tree" -mindepth 1 -maxdepth 1 -type d | head -1)
  [ -n "$top" ] || { warn "пустой архив $bin"; return 1; }
  [ -x "$top/bin/$bin" ] || { warn "в архиве нет bin/$bin"; return 1; }
  rm -rf "$SHARE/$name"
  mkdir -p "$SHARE"
  mv "$top" "$SHARE/$name"
  mkdir -p "$DEST"
  ln -sf "$SHARE/$name/bin/$bin" "$DEST/$bin"
  ok "$DEST/$bin -> $SHARE/$name/bin/$bin"
  rm -f "$tmpdir/tree.tar.gz"
  rm -rf "$tmpdir/tree"
}

# Достать ОДИН файл из zip под нужным именем (qsv: 309M архив, нужен qsvlite 17M).
# $1 = url, $2 = имя внутри архива, $3 = имя в ~/.local/bin
install_zip_member() {
  url=$1 member=$2 as=$3
  have unzip || { warn "для $as нужен unzip"; return 1; }
  if [ "$DRY" -eq 1 ]; then dim "  plan $as <- $member из $(basename "$url")"; return 0; fi
  info "скачиваю $as (архив $(basename "$url"))"
  curl -fsSL "$url" -o "$tmpdir/member.zip" || { warn "не удалось скачать $as"; return 1; }
  rm -rf "$tmpdir/member"
  mkdir -p "$tmpdir/member"
  unzip -qo "$tmpdir/member.zip" "$member" -d "$tmpdir/member" || { warn "в архиве нет $member"; return 1; }
  [ -f "$tmpdir/member/$member" ] || { warn "в архиве нет $member"; return 1; }
  mv "$tmpdir/member/$member" "$DEST/$as"
  chmod +x "$DEST/$as"
  ok "$DEST/$as"
  rm -f "$tmpdir/member.zip"
  rm -rf "$tmpdir/member"
}

# --- рецепт для каждого тула ---
get_rg() {
  tag=$(latest_tag BurntSushi/ripgrep); ver=${tag#v}
  if [ "$OS" = darwin ]; then
    url="https://github.com/BurntSushi/ripgrep/releases/download/$tag/ripgrep-$ver-$(a_gnu)-apple-darwin.tar.gz"
  else
    url="https://github.com/BurntSushi/ripgrep/releases/download/$tag/ripgrep-$ver-$(a_gnu)-unknown-linux-musl.tar.gz"
  fi
  install_tar "$url" rg
}

get_fd() {
  tag=$(latest_tag sharkdp/fd); ver=${tag#v}
  if [ "$OS" = darwin ]; then
    url="https://github.com/sharkdp/fd/releases/download/$tag/fd-v$ver-$(a_gnu)-apple-darwin.tar.gz"
  else
    url="https://github.com/sharkdp/fd/releases/download/$tag/fd-v$ver-$(a_gnu)-unknown-linux-musl.tar.gz"
  fi
  install_tar "$url" fd
}

get_bat() {
  tag=$(latest_tag sharkdp/bat); ver=${tag#v}
  if [ "$OS" = darwin ]; then
    url="https://github.com/sharkdp/bat/releases/download/$tag/bat-v$ver-$(a_gnu)-apple-darwin.tar.gz"
  else
    url="https://github.com/sharkdp/bat/releases/download/$tag/bat-v$ver-$(a_gnu)-unknown-linux-musl.tar.gz"
  fi
  install_tar "$url" bat
}

get_eza() {
  tag=$(latest_tag eza-community/eza); ver=${tag#v}
  if [ "$OS" = darwin ]; then
    url="https://github.com/eza-community/eza/releases/download/$tag/eza_v${ver}_$(a_go)-macos.tar.gz"
  else
    url="https://github.com/eza-community/eza/releases/download/$tag/eza_v${ver}_$(a_gnu)-unknown-linux-musl.tar.gz"
  fi
  install_tar "$url" eza
}

get_delta() {
  tag=$(latest_tag dandavison/delta); ver=${tag#v}
  if [ "$OS" = darwin ]; then
    url="https://github.com/dandavison/delta/releases/download/$tag/delta-$ver-$(a_gnu)-apple-darwin.tar.gz"
  else
    url="https://github.com/dandavison/delta/releases/download/$tag/delta-$ver-$(a_gnu)-unknown-linux-musl.tar.gz"
  fi
  install_tar "$url" delta
}

get_yq() {
  tag=$(latest_tag mikefarah/yq)
  if [ "$OS" = darwin ]; then
    url="https://github.com/mikefarah/yq/releases/download/$tag/yq_darwin_$(a_go)"
  else
    url="https://github.com/mikefarah/yq/releases/download/$tag/yq_linux_$(a_amd)"
  fi
  install_raw "$url" yq
}

get_starship() {
  tag=$(latest_tag starship/starship)
  if [ "$OS" = darwin ]; then
    url="https://github.com/starship/starship/releases/download/$tag/starship-$(a_gnu)-apple-darwin.tar.gz"
  else
    url="https://github.com/starship/starship/releases/download/$tag/starship-$(a_gnu)-unknown-linux-musl.tar.gz"
  fi
  install_tar "$url" starship
}

get_fzf() {
  tag=$(latest_tag junegunn/fzf); ver=${tag#v}
  if [ "$OS" = darwin ]; then
    url="https://github.com/junegunn/fzf/releases/download/$tag/fzf-$ver-darwin_$(a_go).tar.gz"
  else
    url="https://github.com/junegunn/fzf/releases/download/$tag/fzf-$ver-linux_$(a_amd).tar.gz"
  fi
  install_tar "$url" fzf
}

get_gh() {
  tag=$(latest_tag cli/cli); ver=${tag#v}
  if [ "$OS" = darwin ]; then
    case $ARCH in
      arm64)  url="https://github.com/cli/cli/releases/download/$tag/gh_${ver}_macOS_arm64.zip" ;;
      *)      url="https://github.com/cli/cli/releases/download/$tag/gh_${ver}_macOS_amd64.zip" ;;
    esac
    install_zip "$url" gh
  else
    url="https://github.com/cli/cli/releases/download/$tag/gh_${ver}_linux_$(a_go).tar.gz"
    install_tar "$url" gh
  fi
}

get_uv() {
  tag=$(latest_tag astral-sh/uv)
  if [ "$OS" = darwin ]; then
    url="https://github.com/astral-sh/uv/releases/download/$tag/uv-$(a_gnu)-apple-darwin.tar.gz"
  else
    url="https://github.com/astral-sh/uv/releases/download/$tag/uv-$(a_gnu)-unknown-linux-gnu.tar.gz"
  fi
  install_tar "$url" uv
}

get_zoxide() {
  tag=$(latest_tag ajeetdsouza/zoxide); ver=${tag#v}
  if [ "$OS" = darwin ]; then
    url="https://github.com/ajeetdsouza/zoxide/releases/download/$tag/zoxide-$ver-$(a_gnu)-apple-darwin.tar.gz"
  else
    url="https://github.com/ajeetdsouza/zoxide/releases/download/$tag/zoxide-$ver-$(a_gnu)-unknown-linux-musl.tar.gz"
  fi
  install_tar "$url" zoxide
}

get_direnv() {
  tag=$(latest_tag direnv/direnv)
  if [ "$OS" = darwin ]; then
    url="https://github.com/direnv/direnv/releases/download/$tag/direnv.darwin-$(a_go)"
  else
    url="https://github.com/direnv/direnv/releases/download/$tag/direnv.linux-$(a_amd)"
  fi
  install_raw "$url" direnv
}

# neovim: нужен весь каталог (bin + lib + share/nvim/runtime),
# поэтому ставим деревом и линкуем только бинарь.
get_nvim() {
  tag=$(latest_tag neovim/neovim); ver=${tag#v}
  case $OS-$ARCH in
    darwin-arm64)  asset="nvim-macos-arm64" ;;
    darwin-x86_64) asset="nvim-macos-x86_64" ;;
    linux-arm64)   asset="nvim-linux-arm64" ;;
    linux-x86_64)  asset="nvim-linux-x86_64" ;;
    *) warn "нет сборки nvim для $OS/$ARCH"; return 1 ;;
  esac
  url="https://github.com/neovim/neovim/releases/download/$tag/$asset.tar.gz"
  install_tree "$url" "nvim-dist" nvim
}

# qsv: активная замена xsv. Zip огромный (309M на macOS), внутри несколько
# бинарников — берём только qsvlite (17M), он покрывает select/stats/join/sort
# /headers/frequency/schema/count/slice/search/dedup.
get_qsv() {
  tag=$(latest_tag dathere/qsv)
  case $OS-$ARCH in
    darwin-arm64)
      asset="qsv-$tag-aarch64-apple-darwin.zip" ;;
    darwin-x86_64)
      warn "qsv не публикует сборку для macOS x86_64 — пропускаю"
      dim "  варианты: собрать из исходников (cargo install qsv) или взять xsv (x86_64, через Rosetta)"
      return 1 ;;
    linux-arm64)
      asset="qsv-$tag-aarch64-unknown-linux-musl.zip" ;;
    linux-x86_64)
      asset="qsv-$tag-x86_64-unknown-linux-musl.zip" ;;
    *) warn "нет сборки qsv для $OS/$ARCH"; return 1 ;;
  esac
  url="https://github.com/dathere/qsv/releases/download/$tag/$asset"
  install_zip_member "$url" qsvlite qsv
}

head_ "CLI -> $DEST  ($OS/$ARCH)"
fails=""
for t in $TOOLS; do
  if have "$t"; then
    ok "$t уже есть ($(command -v "$t"))"
    continue
  fi
  case $t in
    rg|fd|bat|eza|delta|yq|starship|fzf|gh|uv|zoxide|direnv|nvim|qsv) "get_$t" || fails="$fails $t" ;;
    *) warn "неизвестный тул: $t (см. --list)" ;;
  esac
done

printf '\n'
if [ -n "$fails" ]; then
  warn "не установилось:$fails"
  dim "  проверьте сеть/прокси; можно поставить вручную в $DEST"
else
  ok "готово"
fi
printf '\n'
