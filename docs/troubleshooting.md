# Проблемы и решения

## После `make install` настройки не применились

Симлинки создаются, но текущая оболочка о них не знает.

```sh
exec zsh          # перезапустить shell
```

Если и это не помогло — проверьте, что `~/.zshenv` действительно симлинк:

```sh
ls -l ~/.zshenv ~/.config/zsh/.zshrc
make doctor
```

Отдельно: `install.sh` убирает в `backup/<дата>/` старые `~/.zshrc` и
`~/.zprofile`. При `ZDOTDIR` они всё равно больше не читаются, и если в них
осталось что-то нужное (например, пути конкретной машины), перенесите это в
`~/.config/zsh/local.zsh` — шаблон лежит рядом как `local.example.zsh`.

## `ZDOTDIR` не задан

`~/.zshenv` читается zsh всегда, поэтому `ZDOTDIR` задаётся только там.
Если переменная пустая:

```sh
echo $ZDOTDIR                 # должно быть /Users/<user>/.config/zsh
ls -l ~/.zshenv               # должен вести в репозиторий
```

Важно: не задавайте `ZDOTDIR` в `.zprofile` или `.zshrc` — они читаются уже
из `$ZDOTDIR` и получится замкнутый круг.

## `make doctor` пишет `ZDOTDIR=/Users/<user> унаследован от родительского процесса`

Это VS Code. Он передаёт `ZDOTDIR=$HOME` в терминал. Ничего сломано:

- в вашем терминале/новом окне `~/.zshenv` сработает и выставит правильный путь;
- в терминале VS Code переменная тоже переопределяется, если zsh запускается
  как login- или интерактивный shell.

Если хочется убрать сообщение насовсем, добавьте в `settings.json` VS Code:

```json
{ "terminal.integrated.env.osx": { "ZDOTDIR": null } }
```

## `HISTFILE` или история ведут себя странно

На macOS есть `/etc/zshrc`, который выполняется раньше пользовательского
и сам назначает `HISTFILE`. В `.zshrc` переменная задаётся повторно, поэтому
история окажется в `~/.config/zsh/history`. Если видите старый путь — проверьте,
что не осталось постороннего `HISTFILE` в `local.zsh`:

```sh
printenv HISTFILE
zsh -i -c 'echo $HISTFILE'
```

## `command not found: compdef` при старте

Значит, какой-то файл автодополнения подключён раньше `compinit`.
В этих dotfiles `compinit` вызывается в `.zshrc` до подключения
`yandex-cloud/completion.zsh.inc`. Если добавляете свои плагины — делайте то же:

```zsh
# сначала
autoload -Uz compinit && compinit
# потом — всё, что вызывает compdef
```

## Дубли в `PATH`

`make doctor` показывает дубли. В новых dotfiles путь собирается через
`typeset -U path`, что убирает повторы. Дубли, которые добавляют сторонние
инсталляторы (VS Code, yandex-cloud, Docker), видны в `doctor`, но на работу
не влияют.

Проверить вручную:

```sh
echo $PATH | tr ':' '\n' | sort | uniq -d
```

## `python3` — это не та версия

Сначала смотрим, откуда:

```sh
which -a python3
python3 -V
```

Частые причины:

| Симптом | Причина | Решение |
| --- | --- | --- |
| `python3` = 3.11 из `/Library/Frameworks/...` | старая строка в `.zprofile` | в этих dotfiles её нет; уберите из `local.zsh`, если добавляли |
| `python3` = путь внутри `.../.venv/bin` | активирован venv | `deactivate` |
| `uv python find` пусто | интерпретатор не скачан | `uv python install 3.13` |

`uv` не подменяет `python3` в `PATH` — он используется явно (`uv run`, `uv venv`,
`uvx`). Это осознанно: системный и проектный Python не конфликтуют.

## Node.js: `node -v` показывает старую версию

Порядок поиска в `PATH`: `~/.local/bin` → `~/bin` → `/usr/local/bin` → `/usr/bin`.
Если nvm завёл версии, его `node` оказывается раньше.

```sh
which -a node
node -v
```

| Ситуация | Решение |
| --- | --- |
| Первым идёт `~/.nvm/versions/node/...` | отключите nvm: `export DOTFILES_NO_NVM=1` в `local.zsh` |
| Первым идёт `/usr/local/bin/node` | `hash -r`, затем `exec zsh`; проверьте, что `make node` выполнен |
| Есть несколько версий | `make doctor` покажет все |

Поставить/обновить без sudo:

```sh
make node
hash -r
node -v
```

## `npm install -g` требует sudo

Значит `prefix` указывает на `/usr/local`, принадлежащий root. Это задаёт `~/.npmrc`:

```sh
npm config get prefix    # должно быть /Users/<user>/.local
cat ~/.npmrc             # должен содержать: prefix=${HOME}/.local
```

Если файла нет — `make install` (он линкует `src/.npmrc`).
Если файл есть, но не тот — вероятно, его перезаписал установщик:

```sh
cp ~/projects/dotfiles/src/.npmrc ~/.npmrc
```

Если старый пакет уже стоит под root, обновить его можно так:

```sh
sudo npm i -g <package>
```

или переустановить в `~/.local` и удалить root-копию:

```sh
npm i -g <package> && sudo npm rm -g <package>
hash -r && which -a <package>
```

## `corepack: command not found`

Начиная с Node 25 `corepack` не поставляется вместе с Node:

```sh
npm i -g corepack
```

## `qsv` не устанавливается на macOS x86_64

qsv публикует сборки только для `aarch64-apple-darwin`. На Intel-маках скрипт
предупредит и пропустит установку. Варианты:

- собрать из исходников: `cargo install qsv --locked`;
- использовать `xsv` (x86_64, работает под Rosetta) — но проект заархивирован
  с 2018 года;
- `brew install qsv` (Homebrew здесь не используется, но вариант существует).

## `nvim` запускается, но без runtime и плагинов

Значит бинарник скопирован без дерева. Правильная установка:

```sh
rm -f ~/.local/bin/nvim
rm -rf ~/.local/share/nvim-dist
make bin PKGS=nvim
~/.local/bin/nvim --headless -c 'echo $VIMRUNTIME' -c 'q'
```

`$VIMRUNTIME` должен указывать в `~/.local/share/nvim-dist/share/nvim/runtime`.

## `uv: command not found`

```sh
make bin PKGS=uv
exec zsh
```

`~/.local/bin` должен быть в `PATH` (это делает `.zshenv`).

## Docker: `Cannot connect to the Docker daemon`

```sh
docker context ls
docker context use desktop-linux    # macOS, Docker Desktop
```

На Linux проверьте, что сервис запущен: `sudo systemctl start docker`.
Пользователь должен быть в группе `docker` (или используйте rootless-режим).

## `docker compose` не найден, хотя Docker Desktop стоит

Плагины лежат в `~/.docker/bin`. Каталог добавляется в `PATH` из `.zprofile`,
но только если существует на момент входа. Проверка:

```sh
ls ~/.docker/bin
exec zsh -l
docker compose version
```

## `make deps` ничего не ставит на macOS

Так и задумано: на macOS нет `apt-get`/`dnf`, а brew мы не используем.
`make deps` печатает отчёт и выходит с кодом 0. Используйте `make bin`.

## `make bin` не может скачать (`curl` падает)

- Проверьте прокси: `echo $HTTPS_PROXY`.
- Корпоративный TLS: `export NODE_EXTRA_CA_CERTS=...` не влияет на curl;
  при необходимости `curl --cacert`.
- Скачайте бинарник вручную и положите в `~/.local/bin` с `chmod +x` —
  остальная часть dotfiles от этого не зависит.

## `fd` или `bat` не находятся на Debian/Ubuntu

Пакеты называются `fd-find` и `bat`, а бинарники — `fdfind` и `batcat`.
`make deps` создаёт симлинки `fd`/`bat` в `~/.local/bin` автоматически.
Вручную:

```sh
ln -sf "$(command -v fdfind)" ~/.local/bin/fd
ln -sf "$(command -v batcat)" ~/.local/bin/bat
```

## git не видит моё имя и почту

Identity намеренно не в репозитории. Логика identity описана в `~/.gitconfig`
и в подключаемых файлах:

| Файл | Когда применяется | Назначение |
| --- | --- | --- |
| `~/.config/git/work.gitconfig` | по умолчанию и в `~/work/` | рабочая identity |
| `~/.config/git/personal.gitconfig` | в `~/projects/` | личная identity (GitHub) |
| `~/.config/git/local.gitconfig` | всегда, последним | правки для этой машины |

Проверить, что подхватилось в конкретном репозитории:

```sh
cd ~/projects/my-repo && git config user.email   # личная
cd ~/work/my-repo      && git config user.email  # рабочая
```

Заполнить/поправить:

```sh
make secrets                                     # создаст шаблоны
$EDITOR ~/.config/git/work.gitconfig
$EDITOR ~/.config/git/personal.gitconfig
```

Рабочий клон, лежащий в `~/projects/`, переключается на рабочую identity по
remote (`hasconfig:remote.*.url` в `local.gitconfig`) — remote важнее каталога.

## `make install` сделал бэкап, я хочу вернуть как было

```sh
ls ~/projects/dotfiles/backup/          # каталоги по датам
make uninstall                          # снять мои симлинки
cp -a ~/projects/dotfiles/backup/<дата>/. ~/   # вернуть файлы
```

## Секреты не подхватились

```sh
ls -l ~/.config/secrets.d/secrets.env   # должен быть -rw-------
printenv OPENAI_API_KEY                 # пусто => не подключился
. ~/.config/secrets.d/secrets.env       # проверить вручную
```

Файл подключается из `.zshrc`, то есть только в интерактивной оболочке.
Для скриптов и cron экспортируйте переменные самостоятельно.

## Изменения в конфиге не попадают в git

Файлы в `$HOME` — симлинки в репозиторий, поэтому правки видны сразу:

```sh
cd ~/projects/dotfiles && git status
```

Если `git status` чист, а правка была — вероятно, файл был перезаписан
приложением (это признак того, что его не надо было линковать).
