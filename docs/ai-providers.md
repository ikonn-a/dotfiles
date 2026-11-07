# Адреса и ключи для AI-агентов

Цель: одно место, где лежат URL и токены, и любой агент (Claude Code,
claude-code-router, OpenCode, Codex, Continue, Copilot или что-то новое)
подключается к ним без копирования секретов в конфиги.

## Где что хранится

```
~/.config/secrets.d/secrets.env     # значения, chmod 600, не в git
~/.config/secrets.d/env.example     # шаблон, в git
~/.config/ai/mcp.json               # список MCP-серверов, только ${VAR}, в git
```

`secrets.env` подключается из `~/.config/zsh/.zshrc`. Все переменные становятся
доступны интерактивной оболочке и любому процессу, запущенному из неё.
`mcp.json` — канон MCP: правится в репозитории, раскладывается по клиентам
командой `make ai-sync`.

## Именование

Схема: `<СЕРВИС>_<ЧТО>`. Для OpenAI-совместимых шлюзов используется общая пара
`OPENAI_BASE_URL` + `OPENAI_API_KEY` — её понимают почти все SDK без
дополнительной настройки.

| Сервис | Переменные |
| --- | --- |
| OpenAI-совместимый шлюз | `OPENAI_BASE_URL`, `OPENAI_API_KEY` |
| claude-code-router | `CCR_GATEWAY_URL`, `CCR_MANAGEMENT_URL` |
| Jira | `JIRA_URL`, `JIRA_PERSONAL_TOKEN` |
| Confluence | `CONFLUENCE_URL`, `CONFLUENCE_PERSONAL_TOKEN` |
| Bitbucket | `BITBUCKET_BASE_URL`, `BITBUCKET_USERNAME`, `BITBUCKET_TOKEN` |
| Context7 | `CONTEXT7_API_KEY` |
| TLS | `NODE_EXTRA_CA_CERTS`, `NODE_TLS_REJECT_UNAUTHORIZED` |

Правила:

- URL всегда с `https://`, без завершающего слэша (кроме Bitbucket-сервера,
  которому нужен `/`).
- Токены не оборачиваются в кавычки с `Bearer`, если клиент добавляет префикс сам.
- `OPENAI_BASE_URL` и `OPENAI_API_KEY` — пара «адрес + ключ» одного шлюза.
  Если шлюзов несколько, добавляйте отдельные пары с префиксом по смыслу:
  `TEAM_BASE_URL` / `TEAM_API_KEY`, `PERSONAL_BASE_URL` / `PERSONAL_API_KEY`.
- `OPENAI_API_KEY` читают openai-SDK сами. Без `OPENAI_BASE_URL` они пойдут в
  `api.openai.com`, поэтому задавайте обе переменные вместе.

## Как подхватывают разные клиенты

### Канон MCP — `~/.config/ai/mcp.json`

Единственное место, где перечислены MCP-серверы. Файл лежит в репозитории
(`src/.config/ai/mcp.json`) и линкуется в `$HOME`. Секретов в нём нет — только
ссылки `${VAR}` на `secrets.env`:

```json
{
  "mcpServers": {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp",
      "headers": { "CONTEXT7_API_KEY": "${CONTEXT7_API_KEY}" }
    },
    "atlassian": {
      "type": "stdio",
      "command": "uvx",
      "args": ["mcp-atlassian"],
      "env": { "JIRA_URL": "${JIRA_URL}", "JIRA_PERSONAL_TOKEN": "${JIRA_PERSONAL_TOKEN}" }
    }
  }
}
```

`make ai-sync` (`scripts/ai-sync.sh`):

1. Подставляет `${VAR}` и `${VAR:-default}` из `secrets.env`.
2. Мержит `mcpServers` в конфиги Claude Code — `~/.claude/.claude.json`
   (запуск через CCR) и `~/.claude.json` (прямой запуск), плюс в профили
   `~/.claude-code-router/profiles/*/claude/.claude.json`, если они уже созданы.
3. Переписывает блок между маркерами `// >>> MCP-BEGIN` и `// <<< MCP-END`
   в `~/.config/opencode/opencode.jsonc`, конвертируя схему.

В JSON-файлах Claude Code другие ключи (`oauthAccount`, `projects`,
`pluginUsage`, кэши) не трогаются: меняется только `mcpServers`.
В `opencode.jsonc` вне маркеров ничего не меняется — провайдеры и
комментарии остаются. Перед записью — бэкап в `backup/ai-sync/<дата>/`.

Флаги: `--dry-run` (показать diff), `--prune` (удалить серверы, убранные из
канона), `--allow-empty` (писать даже с незаполненными переменными). Без
`--allow-empty` скрипт откажется писать пустые токены поверх рабочих.

### OpenCode (`~/.config/opencode/opencode.jsonc`)

Файл с провайдерами остаётся ручным и в git не переезжает. Блок MCP
генерируется между маркерами — его править не нужно:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  // >>> MCP-BEGIN — генерируется scripts/ai-sync.sh из src/.config/ai/mcp.json
  "mcp": {
    "context7": {
      "type": "remote",
      "url": "https://mcp.context7.com/mcp",
      "headers": { "CONTEXT7_API_KEY": "ctx7sk-..." }
    }
  },
  // <<< MCP-END
  "provider": { /* ваши провайдеры, не трогается */ }
}
```

В OpenCode 2.x отдельного файла через `OPENCODE_CONFIG` нет: переменная
окружения не читается, `mcp` берётся только из `opencode.jsonc` (и проектного
`opencode.json`). Поэтому скрипт правит сам `opencode.jsonc`, заменяя
исключительно текст между маркерами. Комментарии и провайдеры остаются как были.

После `make ai-sync` выполните `opencode reload` — без этого запущенный демон
продолжит работать со старым конфигом. Проверка: `opencode mcp list`.

Значения подставляются скриптом как литералы: GUI-запуски macOS переменные
окружения из `.zshenv` не получают, и `{env:VAR}` дал бы пустые токены.

Соответствие схем:

| Канон | OpenCode |
| --- | --- |
| `"type": "http"` / `"sse"` | `"type": "remote"` |
| `"type": "stdio"` | `"type": "local"` |
| `command` + `args` | `command: [command, ...args]` |
| `env` | `environment` |

### Claude Code MCP (`claude mcp add-json --scope user`)

Для разовой правки руками:

```sh
claude mcp add-json --scope user context7 \
  '{"type":"http","url":"https://mcp.context7.com/mcp",
    "headers":{"CONTEXT7_API_KEY":"${CONTEXT7_API_KEY}"}}'
```

Разворачивание `${VAR}` работает в `command`, `args`, `env`, `url`, `headers`,
дефолт — `${VAR:-fallback}`. Но при наличии канона правьте `src/.config/ai/mcp.json`
и запускайте `make ai-sync`.

### claude-code-router

CCR 3.x хранит конфигурацию в `~/.claude-code-router/config.sqlite` и позволяет
экспортировать/импортировать JSON через UI (`ccr ui`). В провайдере указывайте
URL и ключ, а не литералы, если клиент это поддерживает; иначе держите
`api_key` синхронным с `secrets.env`.

Профиль Claude Code (`~/.claude/settings.json`) CCR перезаписывает сам — этот файл
не версионируется намеренно. MCP в CCR не заводится: ToolHub выключен, серверы
Claude Code берёт из `.claude.json`, который готовит `make ai-sync`.

Wrapper CCR выставляет `CLAUDE_CONFIG_DIR=~/.claude`, поэтому при запуске через
CCR читается `~/.claude/.claude.json`, а при прямом запуске `claude` — файл
`~/.claude.json` в домашнем каталоге. Скрипт ведёт оба.

### Skills

Skills — это каталоги с `SKILL.md`, которые Claude Code, OpenCode и VS Code
читают из `~/.claude/skills/`. Конвертация не нужна: путь у всех трёх общий.

```
src/.claude/skills/<name>/SKILL.md  ->  ~/.claude/skills/<name>/SKILL.md
```

Симлинк делает обычный `make install`. Проектные skills кладите в
`.claude/skills/` внутри репозитория — их подхватят все три клиента.

### Любой другой агент

Общее правило: конфиг ссылается на переменную, а не содержит секрет.

| Клиент | Синтаксис ссылки |
| --- | --- |
| OpenCode | `{env:VAR}` |
| Claude Code / MCP JSON | `${VAR}`, `${VAR:-default}` |
| shell-обёртки | `$VAR` |
| Docker Compose | `${VAR}` из `.env`/окружения |

## Чек-лист при добавлении нового сервиса

1. Добавить `SERVICE_BASE_URL` и `SERVICE_API_KEY` в `env.example` (без значений).
   Для OpenAI-совместимого шлюза достаточно `OPENAI_BASE_URL` / `OPENAI_API_KEY`
   либо пары `<ИМЯ>_BASE_URL` / `<ИМЯ>_API_KEY` при нескольких шлюзах.
2. Добавить строку в таблицу выше.
3. Записать значения в `secrets.env`.
4. В конфиге агента использовать ссылку на переменную.
5. Проверить: `exec zsh && printenv SERVICE_API_KEY`.

## Чек-лист при добавлении MCP-сервера

1. Дописать сервер в `src/.config/ai/mcp.json` (формат `mcpServers`,
   значения — `${VAR}`).
2. Если нужны новые переменные — добавить их в `env.example` и в `secrets.env`.
3. `make ai-sync-dry` — посмотреть diff, `make ai-sync` — применить.
4. `claude mcp list` и `/mcp` в OpenCode должны показать сервер.
5. Удаление: убрать из `mcp.json` → `make ai-sync --prune`.
   Без `--prune` сервер останется в целевых файлах (защита от случайной потери).
