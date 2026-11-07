#!/bin/sh
# VS Code из dotfiles: установка, настройки, расширения. Без brew и без sudo.
#
#   sh scripts/vscode.sh install        поставить VS Code и команду code
#   sh scripts/vscode.sh settings       залинковать settings.json в профиль VS Code
#   sh scripts/vscode.sh pull           забрать правки из VS Code обратно в репозиторий
#   sh scripts/vscode.sh ext            поставить расширения из extensions.txt
#   sh scripts/vscode.sh ext-pull       перегенерировать extensions.txt по факту
#
#   --dry-run  показать план, ничего не менять
#   --force    переустановить VS Code, даже если он уже стоит
set -eu

. "$(dirname "$0")/lib.sh"
REPO_ROOT=$(repo_root_from "$0") || die "не удалось найти корень репозитория"

SRC=$REPO_ROOT/src/.config/vscode
SETTINGS=$SRC/User/settings.json
EXTLIST=$SRC/extensions.txt
DEST=$HOME/.local/bin
SHARE=$HOME/.local/share

DRY=0
FORCE=0
CMD=""
for a in "$@"; do
  case $a in
    --dry-run|-n) DRY=1 ;;
    --force|-f)   FORCE=1 ;;
    -h|--help)    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    install|settings|pull|ext|ext-pull) CMD=$a ;;
    *) die "неизвестный аргумент: $a (см. --help)" ;;
  esac
done

[ -n "$CMD" ] || { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[ -f "$SETTINGS" ] || die "нет $SETTINGS"
[ -f "$EXTLIST" ]  || die "нет $EXTLIST"

detect_os

STAMP=$(date +%Y_%m_%d-%H_%M_%S)
BACKUP=$REPO_ROOT/backup/$STAMP/vscode

# Каталог профиля по умолчанию. Профили (--profile) не поддерживаются.
user_dir() {
  if [ "$OS" = darwin ]; then
    printf '%s/Library/Application Support/Code/User' "$HOME"
  else
    printf '%s/Code/User' "${XDG_CONFIG_HOME:-$HOME/.config}"
  fi
}
USERDIR=$(user_dir)

backup_path() { # $1 = файл, $2 = имя внутри backup
  [ "$DRY" -eq 1 ] && return 0
  mkdir -p "$(dirname "$BACKUP/$2")"
  mv "$1" "$BACKUP/$2"
}

# ---------------------------------------------------------------- install ---
cmd_install() {
  head_ "VS Code"

  if have code && [ "$FORCE" -eq 0 ]; then
    ok "уже установлен: $(code --version 2>/dev/null | head -1) ($(command -v code))"
    if [ "$OS" = darwin ] && [ ! -e "$DEST/code" ]; then
      existing=$(link_existing_macos_app)
      if [ -n "$existing" ]; then
        if [ "$DRY" -eq 1 ]; then
          dim "  plan симлинк $DEST/code -> $existing/Contents/Resources/app/bin/code"
        else
          mkdir -p "$DEST"
          ln -sf "$existing/Contents/Resources/app/bin/code" "$DEST/code"
          ok "$DEST/code -> $existing/Contents/Resources/app/bin/code"
        fi
      fi
    fi
    dim "  обновить: make vscode FORCE=1"
    return 0
  fi

  if [ "$FORCE" -eq 1 ] && [ "$OS" = darwin ] && pgrep -f "Visual Studio Code.app/Contents/MacOS/Electron" >/dev/null 2>&1; then
    die "VS Code запущен — закройте его и повторите make vscode FORCE=1"
  fi

  case $OS in
    darwin) install_macos ;;
    linux)  install_linux ;;
    *)      die "неизвестная ОС: $OS" ;;
  esac
}

# Приложение уже стоит, но команды code в PATH нет — нужен только симлинк.
link_existing_macos_app() {
  if [ -d /Applications/Visual\ Studio\ Code.app ]; then
    printf '%s' /Applications/Visual\ Studio\ Code.app
  elif [ -d "$HOME/Applications/Visual Studio Code.app" ]; then
    printf '%s' "$HOME/Applications/Visual Studio Code.app"
  fi
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT INT TERM

# Заменить каталог/пакет целиком, не оставляя систему без редактора при сбое.
# $1 = новый путь, $2 = целевой путь, $3 = подпись для сообщений
swap_in() {
  new=$1 dst=$2 label=$3
  if [ -e "$dst" ]; then
    old="$dst.old.$$"
    info "заменяю существующую установку"
    mv "$dst" "$old" || die "не удалось отодвинуть $dst"
    if ! mv "$new" "$dst"; then
      mv "$old" "$dst" 2>/dev/null || true
      die "не удалось установить $label (старая версия восстановлена)"
    fi
    rm -rf "$old"
  else
    mv "$new" "$dst" || die "не удалось установить $label"
  fi
}

install_macos() {
  case $ARCH in
    arm64)  asset=darwin-arm64 ;;
    x86_64) asset=darwin-x64 ;;
    *)      die "нет сборки VS Code для macOS/$ARCH" ;;
  esac
  url="https://update.code.visualstudio.com/latest/$asset/stable"

  if [ -w /Applications ]; then APPDIR=/Applications; else APPDIR=$HOME/Applications; fi
  APP="$APPDIR/Visual Studio Code.app"

  # Приложение уже на месте: без --force не качаем, а только чиним команду code.
  if [ "$FORCE" -eq 0 ]; then
    existing=$(link_existing_macos_app)
    if [ -n "$existing" ]; then
      if [ "$DRY" -eq 1 ]; then
        dim "  plan симлинк $DEST/code -> $existing/Contents/Resources/app/bin/code"
        return 0
      fi
      mkdir -p "$DEST"
      ln -sf "$existing/Contents/Resources/app/bin/code" "$DEST/code"
      ok "VS Code уже стоит: $existing"
      ok "$DEST/code -> $existing/Contents/Resources/app/bin/code"
      dim "  обновить: make vscode FORCE=1"
      return 0
    fi
  fi

  if [ "$DRY" -eq 1 ]; then
    dim "  plan скачать $asset -> $APP"
    dim "  plan симлинк $DEST/code -> $APP/Contents/Resources/app/bin/code"
    return 0
  fi

  info "скачиваю VS Code ($asset)"
  curl -fsSL "$url" -o "$tmpdir/vscode.zip" || die "не удалось скачать VS Code"
  unzip -qo "$tmpdir/vscode.zip" -d "$tmpdir/unpacked" || die "битый архив VS Code"
  newapp=$(find "$tmpdir/unpacked" -maxdepth 1 -name '*.app' -print | head -1)
  [ -n "$newapp" ] || die "в архиве нет .app"

  if [ -d "$APP" ]; then
    info "заменяю существующую установку ($APP)"
  fi
  mkdir -p "$APPDIR"
  swap_in "$newapp" "$APP" "Visual Studio Code"
  # curl не ставит карантин, но архив может принести расширенные атрибуты
  xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

  mkdir -p "$DEST"
  ln -sf "$APP/Contents/Resources/app/bin/code" "$DEST/code"
  ok "$APP"
  ok "$DEST/code -> $APP/Contents/Resources/app/bin/code"
  dim "  запуск: code .   (или открыть через Launchpad)"
}

install_linux() {
  case $ARCH in
    x86_64) asset=linux-x64 ;;
    arm64)  asset=linux-arm64 ;;
    *)      die "нет сборки VS Code для linux/$ARCH" ;;
  esac
  url="https://update.code.visualstudio.com/latest/$asset/stable"
  target=$SHARE/vscode

  if [ "$DRY" -eq 1 ]; then
    dim "  plan скачать $asset -> $target"
    dim "  plan симлинк $DEST/code -> $target/bin/code"
    return 0
  fi

  info "скачиваю VS Code ($asset)"
  curl -fsSL "$url" -o "$tmpdir/vscode.tar.gz" || die "не удалось скачать VS Code"
  mkdir -p "$tmpdir/unpacked"
  tar -xzf "$tmpdir/vscode.tar.gz" -C "$tmpdir/unpacked" || die "битый архив VS Code"
  top=$(find "$tmpdir/unpacked" -mindepth 1 -maxdepth 1 -type d | head -1)
  [ -n "$top" ] || die "пустой архив VS Code"
  [ -x "$top/bin/code" ] || die "в архиве нет bin/code"

  mkdir -p "$SHARE"
  swap_in "$top" "$target" "Visual Studio Code"

  mkdir -p "$DEST"
  ln -sf "$target/bin/code" "$DEST/code"
  ok "$target"
  ok "$DEST/code -> $target/bin/code"

  write_desktop_entry "$target"

  if ! "$DEST/code" --version >/dev/null 2>&1; then
    warn "code не запускается — вероятно, не хватает системных библиотек"
    dim "  Debian/Ubuntu: sudo apt-get install -y libnss3 libgtk-3-0 libgbm1 libasound2 libxss1 xdg-utils"
    dim "  Fedora:        sudo dnf install -y nss gtk3 mesa-libgbm alsa-lib libXScrnSaver xdg-utils"
  fi
}

write_desktop_entry() { # $1 = каталог установки
  apps=$SHARE/applications
  icon=$1/resources/app/resources/linux/code.png
  [ "$DRY" -eq 1 ] && { dim "  plan $apps/code.desktop"; return 0; }
  mkdir -p "$apps"
  {
    printf '[Desktop Entry]\n'
    printf 'Type=Application\n'
    printf 'Name=Visual Studio Code\n'
    printf 'Comment=Code Editing. Redefined.\n'
    printf 'Exec=%s/bin/code --unity-launch %%F\n' "$1"
    printf 'Icon=%s\n' "$icon"
    printf 'Terminal=false\n'
    printf 'Categories=TextEditor;Development;IDE;\n'
    printf 'StartupNotify=true\n'
  } > "$apps/code.desktop"
  ok "$apps/code.desktop"
}

# --------------------------------------------------------------- settings ---
cmd_settings() {
  head_ "settings.json"
  if [ "$DRY" -eq 1 ]; then dim "  профиль: $USERDIR"; fi

  # На машине без VS Code не создаём каталог профиля «на всякий случай».
  if ! have code && [ ! -d "$USERDIR" ]; then
    warn "VS Code не установлен (~/${USERDIR#"$HOME"/} нет — make vscode)"
    return 0
  fi

  live=$USERDIR/settings.json
  want=$(resolve_path "$SETTINGS")

  if [ -L "$live" ] && [ "$(readlink "$live")" = "$want" ]; then
    ok "~/${live#"$HOME"/} уже ведёт в репозиторий"
    return 0
  fi

  if [ "$DRY" -eq 1 ]; then
    dim "  plan backup ~/${live#"$HOME"/} -> backup/$STAMP/vscode/settings.json"
    dim "  plan link   ~/${live#"$HOME"/} -> src/.config/vscode/User/settings.json"
    return 0
  fi

  if [ -e "$live" ] || [ -L "$live" ]; then
    backup_path "$live" settings.json
    dim "  старый файл: backup/$STAMP/vscode/settings.json"
  fi
  mkdir -p "$USERDIR"
  ln -s "$want" "$live"
  ok "~/${live#"$HOME"/} -> src/.config/vscode/User/settings.json"
  dim "  правки из UI: изменения попадут в репозиторий (файл — симлинк)"
  dim "  если VS Code заменил симлинк обычным файлом: make vscode-pull"
}

# ------------------------------------------------------------------- pull ---
cmd_pull() {
  head_ "правки из VS Code"
  live=$USERDIR/settings.json

  if [ ! -e "$live" ]; then
    warn "нет ~/${live#"$HOME"/} — нечего забирать"
    return 0
  fi
  if [ -L "$live" ]; then
    ok "~/${live#"$HOME"/} — симлинк, правки уже в репозитории"
    return 0
  fi
  if cmp -s "$live" "$SETTINGS"; then
    ok "содержимое совпадает с репозиторием"
    return 0
  fi

  if [ "$DRY" -eq 1 ]; then
    diff -u -L "src/.config/vscode/User/settings.json" -L "~/${live#"$HOME"/}" \
      "$SETTINGS" "$live" 2>/dev/null | sed -n '1,60p' | sed 's/^/     /'
    dim "  plan скопировать ~/${live#"$HOME"/} -> src/.config/vscode/User/settings.json"
    return 0
  fi

  cp "$live" "$SETTINGS"
  ok "settings.json обновлён из VS Code"
  dim "  дальше: make vscode-settings (вернуть симлинк) и git diff"
}

# -------------------------------------------------------------------- ext ---
ext_ids() { # id из extensions.txt без комментариев
  sed 's/#.*//' "$EXTLIST" | tr -d ' \t\r' | grep -v '^$' || true
}

installed_ids() {
  code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]' | sort
}

cmd_ext() {
  head_ "расширения"
  have code || die "нет команды code (сначала: make vscode)"

  list=$(installed_ids)
  add=0
  skip=0
  fails=""
  for id in $(ext_ids); do
    lower=$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')
    if printf '%s\n' "$list" | grep -qx "$lower"; then
      skip=$((skip + 1))
      continue
    fi
    if [ "$DRY" -eq 1 ]; then
      dim "  plan install $id"
      add=$((add + 1))
      continue
    fi
    info "ставлю $id"
    if code --install-extension "$id" --force >/dev/null 2>&1; then
      add=$((add + 1))
    else
      fails="$fails $id"
    fi
  done

  [ -n "$fails" ] && warn "не установилось:$fails"
  if [ "$DRY" -eq 1 ]; then
    dim "  план: поставить $add, уже есть $skip"
  else
    ok "поставлено $add, уже было $skip"
  fi
}

# --------------------------------------------------------------- ext-pull ---
cmd_ext_pull() {
  head_ "extensions.txt"
  have code || die "нет команды code (сначала: make vscode)"

  new=$tmpdir/extensions.new
  {
    printf '# Расширения VS Code. Одна строка — один id (publisher.name), версия не пишется.\n'
    printf '# Ставится: make vscode-ext      Обновить список по факту: make vscode-ext-pull\n'
    printf '\n'
    code --list-extensions 2>/dev/null | sort
  } > "$new"

  if cmp -s "$new" "$EXTLIST"; then
    ok "список актуален"
    return 0
  fi
  if [ "$DRY" -eq 1 ]; then
    diff -u "$EXTLIST" "$new" 2>/dev/null | sed -n '1,60p' | sed 's/^/     /'
    dim "  plan перезаписать src/.config/vscode/extensions.txt"
    return 0
  fi
  cp "$new" "$EXTLIST"
  ok "src/.config/vscode/extensions.txt обновлён ($(ext_ids | wc -l | tr -d ' ') строк)"
}

case $CMD in
  install)  cmd_install ;;
  settings) cmd_settings ;;
  pull)     cmd_pull ;;
  ext)      cmd_ext ;;
  ext-pull) cmd_ext_pull ;;
esac
printf '\n'
