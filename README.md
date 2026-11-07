# dotfiles

Мои dotfiles: zsh (ZDOTDIR), git, алиасы, место под секреты и адреса AI-провайдеров.
Работают на macOS и Linux, без Homebrew.

## Быстрый старт

```sh
git clone https://github.com/ikonn-a/dotfiles.git ~/projects/dotfiles
cd ~/projects/dotfiles

make dry-run     # посмотреть, что будет залинковано
make install     # создать симлинки в $HOME (старое уходит в backup/)
make secrets     # создать secrets.env, local/work/personal.gitconfig
make doctor      # проверить окружение
```

На новой машине всё сразу: `make bootstrap`.

## Что где

| Путь в репозитории | Куда попадает | Комментарий |
| --- | --- | --- |
| `src/.zshenv` | `~/.zshenv` | `ZDOTDIR`, `XDG_*`, PATH |
| `src/.config/zsh/` | `~/.config/zsh/` | `.zshrc`, `.zprofile`, алиасы, функции |
| `src/.npmrc` | `~/.npmrc` | npm без sudo (`prefix=~/.local`) |
| `src/.gitconfig` | `~/.gitconfig` | без ФИО/почты — они в локальных файлах |
| `src/.config/git/` | `~/.config/git/` | `ignore`, шаблоны identity |
| `src/.config/git/local.gitconfig.example` | копия в `local.gitconfig` | машинные настройки, не коммитится |
| `src/.config/git/work.gitconfig.example` | копия в `work.gitconfig` | рабочая identity, не коммитится |
| `src/.config/git/personal.gitconfig.example` | копия в `personal.gitconfig` | личная identity для `~/projects/`, не коммитится |
| `src/.config/secrets.d/env.example` | копия в `secrets.env` | ключи и URL, не коммитится |

Ключи и адреса сервисов — только в `~/.config/secrets.d/secrets.env`.
Соглашение об именах описано в [`docs/ai-providers.md`](docs/ai-providers.md).

### git identity

Один компьютер — две личности. Выбор идёт по каталогу, а для рабочих клонов
внутри `~/projects/` — по remote:

| Где | Identity |
| --- | --- |
| по умолчанию, `~/work/` | рабочая (`work.gitconfig`) |
| `~/projects/` | личная, GitHub (`personal.gitconfig`) |
| remote рабочего хостинга (см. `local.gitconfig`) | рабочая, где бы ни лежал клон |

```sh
cd ~/projects/dotfiles && git config user.email
# 47638600+ikonn-a@users.noreply.github.com
cd ~/projects/some-work-repo && git config user.email
# you@company.example
```

## Цели make

```
make help        список целей
make install     симлинки src/ -> $HOME, старое в backup/<дата>/
make dry-run     показать план, ничего не менять
make uninstall   снять только симлинки, ведущие в этот репозиторий
make deps        поставить пакеты из packages/packages.csv (apt-get/dnf)
make bin         скачать недостающие CLI в ~/.local/bin (без brew и root)
                  rg fd bat eza delta yq starship fzf gh uv zoxide direnv nvim qsv
make node        поставить Node.js LTS в ~/.local (без sudo)
make npmrc       настроить npm: глобальные пакеты в ~/.local
make secrets     создать secrets.env и git-identity: local, work, personal
make doctor      проверка окружения
make check       синтаксис zsh/sh + shellcheck, если есть
make bootstrap   deps + secrets + install + doctor
make update      git pull --ff-only && make install
```

`make bin PKGS="rg bat"` — только выбранные тулы.
`make node NODE_VERSION=24.22.2` — конкретная версия Node.

## Документация

- [`docs/install.md`](docs/install.md) — установка на macOS и Linux, Python через `uv`, Docker
- [`docs/ai-providers.md`](docs/ai-providers.md) — где хранить URL и ключи для агентов
- [`docs/troubleshooting.md`](docs/troubleshooting.md) — частые проблемы

## Структура

```
install.sh          POSIX-линковка src/ -> $HOME с бэкапом
unlink.sh           снять свои симлинки
Makefile            единая точка входа
scripts/            пакеты, загрузка бинарей, doctor, check
packages/           packages.csv (apt/dnf/macos)
src/                зеркало $HOME
backup/             бэкапы от install.sh (в .gitignore)
```

Симлинкуются только файлы, каталоги создаются как настоящие.
`~/.claude*`, `~/.config/opencode`, `~/.claude-code-router` и `~/.docker/config.json`
намеренно не включены: их перезаписывают соответствующие приложения.
