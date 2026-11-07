# Установка

Поддерживаются macOS и Linux. Homebrew не используется.
На Linux пакеты ставятся через `apt-get` или `dnf`; на macOS — `make bin`
(статические бинарники в `~/.local/bin`, без root).

## Новая машина

```sh
git clone https://github.com/ikonn-a/dotfiles.git ~/projects/dotfiles
cd ~/projects/dotfiles
make bootstrap
```

`bootstrap` = `deps` + `secrets` + `install` + `doctor`.

Затем заполните `~/.config/secrets.d/secrets.env`, `~/.config/git/work.gitconfig`
(рабочая identity) и `~/.config/git/personal.gitconfig` (личная для `~/projects/`),
откройте новый терминал.

VS Code ставится отдельно — он не входит в `bootstrap` (скачивание ~340 МБ):

```sh
make vscode
```

## Пошагово

| Команда | Что делает |
| --- | --- |
| `make dry-run` | печатает план линковки, ничего не меняет |
| `make install` | симлинкует `src/` в `$HOME`; старое уходит в `backup/<дата>/` |
| `make uninstall` | снимает только симлинки, ведущие в этот репозиторий |
| `make deps` | ставит пакеты из `packages/packages.csv` (apt/dnf) |
| `make bin` | тянет CLI в `~/.local/bin` (`rg fd bat eza delta yq starship fzf gh uv zoxide direnv nvim qsv`) |
| `make node` | ставит Node.js LTS в `~/.local/share/nodejs` (без sudo) |
| `make npmrc` | настраивает npm: глобальные пакеты в `~/.local` |
| `make secrets` | создаёт `secrets.env` (chmod 600) и `local/work/personal.gitconfig` |
| `make vscode` | ставит VS Code, линкует `settings.json`, ставит расширения |
| `make doctor` | проверяет окружение |
| `make check` | `zsh -n`, `sh -n`, shellcheck, Makefile, gitconfig |
| `make update` | `git pull --ff-only` + `install` |

Повторный `make install` идемпотентен: уже корректные симлинки не трогаются.

## macOS

Пакетного менеджера нет намеренно. Что уже есть в системе (`git`, `make`, `curl`,
`jq`, `zsh`, `unzip`) — используется как есть. Остальное:

```sh
make bin                      # всё
make bin PKGS="rg bat fzf"    # выборочно
```

Скрипт качает релиз с GitHub под `uname -s`/`uname -m` и кладёт в `~/.local/bin`.
Файлы, скачанные через `curl`, не получают карантинный флаг macOS, дополнительный
`xattr` не нужен. `gh` качается как `.zip` и требует `unzip` (в системе есть).

`make deps` на macOS не падает: печатает таблицу «есть / нет / как добрать» и
возвращает 0.

## Linux

```sh
sudo apt-get update
make deps
```

Скрипт определяет `apt-get`/`dnf`, ставит только отсутствующее, `sudo` вызывает
только если вы не root (полезно в контейнерах). Debian-переименования
компенсируются автоматически: `fd-find` -> `fdfind`, `bat` -> `batcat`,
и скрипт создаёт симлинки `fd`/`bat` в `~/.local/bin`.

Принудительный менеджер: `PACKAGE_MANAGER=dnf make deps`.
Посмотреть план: `sh scripts/install-packages.sh --dry-run`.

## Node.js и npm

Ставятся без brew, nvm и root — прямо с nodejs.org, с проверкой SHA256:

```sh
make node                     # последняя LTS
make node NODE_VERSION=24.22.2
sh scripts/install-node.sh --list     # что доступно
sh scripts/install-node.sh --current  # последний Current вместо LTS
```

Распаковывается в `~/.local/share/nodejs/<версия>/`, а `node`, `npm`, `npx`
симлинкуются в `~/.local/bin`. Этот каталог идёт в `PATH` раньше `/usr/local/bin`,
поэтому выбранная версия становится основной.

Требование «выше 22» проверяется: скрипт предупредит при более старой версии,
`make doctor` покажет текущую и подсветит несоответствие.

### npm без sudo

Глобальные пакеты ставятся в `~/.local` вместо `/usr/local` — это задаёт
`~/.npmrc` (лежит в репозитории, линкуется как есть):

```sh
npm config get prefix         # должно быть /Users/<user>/.local
npm install -g some-cli       # без sudo
```

`:prefix` в npmrc вычисляется на месте, поэтому файл переносим между машинами.
`NPM_CONFIG_PREFIX` в `.zshenv` дублирует настройку на случай, если `~/.npmrc`
перезаписан сторонним установщиком.

Если пакет уже стоит в `/usr/local` под root (так было с `claude` и `ccr`),
sudo понадобится только для его обновления:

```sh
sudo npm i -g @anthropic-ai/claude-code
```

Либо переустановите в `~/.local` и уберите старую копию — тогда sudo не нужен
никогда:

```sh
npm i -g @anthropic-ai/claude-code
sudo npm rm -g @anthropic-ai/claude-code
hash -r && which -a claude
```

### nvm

Если в `~/.nvm/versions/node` есть версии, `nvm.sh` из `.zprofile` поставит свой
`node` **раньше** `~/.local/bin` и перекроет версию из `make node`. Варианты:

- не заводить версий в nvm — тогда используется `~/.local/bin/node`;
- отключить nvm целиком: `export DOTFILES_NO_NVM=1` в `~/.config/zsh/local.zsh`;
- оставить nvm основным: `nvm alias default 24` и не использовать `make node`.

`make doctor` предупреждает, если видит несколько `node` в `PATH`.

### corepack

В Node 25+ `corepack` больше не поставляется вместе с Node. Если нужен
(`pnpm`, `yarn` через `corepack enable`): `npm i -g corepack`.

## Neovim, qsv, feh

### neovim — деревом, не одним бинарником

`make bin PKGS=nvim` качает релиз с GitHub и распаковывает **весь каталог** в
`~/.local/share/nvim-dist/`, а в `~/.local/bin/nvim` кладёт симлинк.

Почему так: бинарнику nvim рядом нужны `lib/nvim/` и `share/nvim/runtime/`.
Если перенести только исполняемый файл, редактор запустится без runtime и
плагинов. Проверено: через симлинк `:echo $VIMRUNTIME` находит правильный путь.

| Платформа | Ассет |
| --- | --- |
| macOS arm64 / x86_64 | `nvim-macos-arm64` / `nvim-macos-x86_64` |
| Linux arm64 / x86_64 | `nvim-linux-arm64` / `nvim-linux-x86_64` |

В `apt`/`dnf` neovim есть, но старый (Debian bookworm — 0.7.2, trixie — 0.10.4),
поэтому свежий ставится через `make bin`. Строка в `packages.csv` оставлена как
fallback для систем без доступа к GitHub.

Обновить:

```sh
rm -rf ~/.local/share/nvim-dist
make bin PKGS=nvim
```

### qsv вместо xsv

`xsv` заархивирован (последний релиз 0.13.0 — май 2018), собирается только под
x86_64 и в Debian/Fedora отсутствует. Вместо него ставится **qsv** — активный
форк с нативным arm64.

```sh
make bin PKGS=qsv
qsv --version
```

Особенность: zip-архив qsv для macOS весит **309 МБ** и содержит пять бинарников
(`qsv`, `qsvmcp`, два `qsvpy`). Скрипт распаковывает **только `qsvlite`** (17 МБ)
и кладёт его как `qsv`. `qsvlite` покрывает повседневные операции:
`select`, `stats`, `join`, `sort`, `headers`, `frequency`, `schema`, `count`,
`slice`, `search`, `dedup`.

| Платформа | Поддержка |
| --- | --- |
| macOS arm64 | есть |
| macOS x86_64 | **нет сборки** (скрипт предупредит) |
| Linux arm64 / x86_64 | есть (musl) |

В `apt`/`dnf` пакета нет — ни `qsv`, ни `qsvlite`.

### feh — только Linux

`feh` требует `imlib2` и Xlib, порта для macOS не существует. В `packages.csv`
он помечен `macos=skip`: на Linux ставится через `apt`/`dnf`, на macOS
пропускается с пояснением в выводе `make deps`.

## Python: через uv, не системный

Системный Python не пинится в `PATH`. Версиями управляет `uv`:

```sh
uv python install 3.13     # скачать интерпретатор
uv python list             # что доступно
uv venv && . .venv/bin/activate
uv pip install -r requirements.txt
uv tool install ruff       # CLI-утилиты вместо pipx
uvx ruff check             # разовый запуск
```

В проекте версию фиксируют файлом:

```sh
uv python pin 3.13         # создаёт .python-version
```

Если нужно, чтобы `uv` не трогал системный интерпретатор:

```sh
echo 'export UV_PYTHON_PREFERENCE=only-managed' >> ~/.config/zsh/local.zsh
```

python.org-установка 3.11 не удаляется и не отключается — она просто больше не
попадает в `PATH` из dotfiles. Если она нужна какому-то проекту, добавьте её в
`local.zsh` (пример там есть).

## Docker

Docker ставится инсталлятором Docker Desktop (macOS) или из официального
репозитория (Linux) — **не** через `packages.csv`.

dotfiles делает только две вещи:

1. Добавляет `~/.docker/bin` в `PATH` (если каталог есть), иначе пропадают
   `docker compose` и CLI-плагины.
2. В `make doctor` проверяет контекст. Ожидаемый для Docker Desktop —
   `desktop-linux`.

`~/.docker/config.json` **не** симлинкуется: его перезаписывает Docker Desktop,
там хранится локальный контекст и настройки реестров.

Если `docker` не видит daemon:

```sh
docker context ls
docker context use desktop-linux    # macOS
```

## Что не линкуется

Намеренно вне репозитория:

| Путь | Почему |
| --- | --- |
| `~/.claude/settings.json` | перезаписывается при переключении профиля claude-code-router |
| `~/.claude.json` | содержит machineID, историю, MCP-серверы |
| `~/.claude-code-router/config.sqlite` | живая БД; копирование на работающей системе запрещено |
| `~/.config/opencode/opencode.jsonc` | содержит ключи провайдеров |
| `~/.docker/config.json` | пишется Docker Desktop |
| `~/Library/Application Support/Code/User/{argv.json,globalStorage,History,workspaceStorage}` | машинное состояние VS Code, см. [`vscode.md`](vscode.md) |

Ключи для этих инструментов берите из `~/.config/secrets.d/secrets.env` —
см. [`ai-providers.md`](ai-providers.md).

## Обновление

```sh
cd ~/projects/dotfiles
make update
```

Если вы правили конфиг прямо в `$HOME`, помните: это симлинк в репозиторий,
так что правка сразу попадает в рабочее дерево git.
