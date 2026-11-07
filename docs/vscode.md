# VS Code

VS Code ставится без Homebrew и без `sudo`: на macOS — приложение из zip,
на Linux — переносной tarball в `~/.local/share`.

```sh
make vscode          # установить + настройки + расширения
make vscode-settings # только settings.json
make vscode-ext      # только расширения
make vscode FORCE=1  # переустановить (обновить) VS Code
```

## Что где лежит

| Путь в репозитории | Куда попадает | Комментарий |
| --- | --- | --- |
| `src/.config/vscode/User/settings.json` | профиль VS Code, `User/settings.json` | симлинк, правки из UI сразу в git |
| `src/.config/vscode/extensions.txt` | — | список id для `make vscode-ext` |

Каталог профиля по умолчанию:

| ОС | Путь |
| --- | --- |
| macOS | `~/Library/Application Support/Code/User` |
| Linux | `~/.config/Code/User` |

Сам `src/.config/vscode/` линкуется в `~/.config/vscode/` обычным `make install`;
платформенный путь VS Code создаёт `make vscode-settings`. Профили VS Code
(`--profile`) не поддерживаются — только профиль по умолчанию.

## Установка

### macOS

```sh
make vscode
code --version
```

Скрипт качает `VSCode-darwin-<arch>.zip` с `update.code.visualstudio.com`,
распаковывает в `/Applications` (если каталог недоступен для записи — в
`~/Applications`) и делает симлинк `~/.local/bin/code` на
`…/Visual Studio Code.app/Contents/Resources/app/bin/code`.

Симлинк нужен потому, что штатная команда «Install 'code' command in PATH»
пишет в `/usr/local/bin` и требует `sudo`. Наш вариант работает без него и
живёт в `PATH` из `~/.zshenv`.

Запуск: `code .`, либо иконка в Launchpad/Finder.

### Linux

```sh
make vscode
```

Tarball `code-stable-<arch>-<build>.tar.gz` распаковывается целиком в
`~/.local/share/vscode` (дерево, как `nvim`), `~/.local/bin/code` — симлинк на
`~/.local/share/vscode/bin/code`. Дополнительно создаётся
`~/.local/share/applications/code.desktop`, чтобы редактор был в меню.

Системные библиотеки ставятся пакетным менеджером (в `packages.csv` их нет:
там проверка идёт по имени бинарника, для библиотек она не работает):

```sh
sudo apt-get install -y libnss3 libgtk-3-0 libgbm1 libasound2 libxss1 xdg-utils  # Debian/Ubuntu
sudo dnf install -y nss gtk3 mesa-libgbm alsa-lib libXScrnSaver xdg-utils       # Fedora
```

Если после установки `code` не запускается, скрипт сам подскажет эту команду.

Портативная установка не обновляется сама (нет apt-репозитория Microsoft):
обновление — `make vscode FORCE=1`.

## settings.json

Файл — обычный JSON, **без комментариев**: `make check` валидирует его через
`jq`, а `jq` комментариев не понимает.

Линковка:

```sh
make vscode-settings
# ~/Library/Application Support/Code/User/settings.json -> src/.config/vscode/User/settings.json
```

Существующий файл уходит в `backup/<дата>/vscode/settings.json` (не удаляется).

### Симлинк и атомарная запись

VS Code сохраняет `settings.json` атомарно (временный файл + `rename`), поэтому
после правки через UI симлинк может превратиться в обычный файл. Признак —
`make doctor` пишет «settings.json не симлинк».

Порядок восстановления:

```sh
make vscode-pull      # перенести правки из VS Code в репозиторий (покажет diff)
git diff              # посмотреть, что изменилось
make vscode-settings  # вернуть симлинк
```

`make vscode-pull` ничего не делает, если файл уже симлинк (правки и так в
репозитории) или если содержимое совпадает.

## Расширения

`src/.config/vscode/extensions.txt` — по одному id на строку, без версий
(версии различаются между платформами и ломают установку).

```sh
make vscode-ext        # поставить недостающие (уже установленные пропускаются)
make vscode-ext-pull   # перегенерировать список по факту
```

Проверить, что стоит: `code --list-extensions`.

## Что не синхронизируется

| Путь | Почему |
| --- | --- |
| `~/.vscode/argv.json` | машинные аргументы запуска, содержит `crash-reporter-id` |
| `User/globalStorage/` | состояние расширений, `state.vscdb` |
| `User/History/`, `User/workspaceStorage/` | локальная история и состояние воркспейсов |
| `User/profiles/` | профили (`--profile`), у каждого свои настройки |
| `~/.vscode/extensions/` | сами расширения ставятся из `extensions.txt` |

## Проверка

```sh
make doctor   # code --version, состояние симлинка, число расширений
make check    # валидность settings.json и extensions.txt
```
