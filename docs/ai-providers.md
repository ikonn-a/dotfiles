# Адреса и ключи для AI-агентов

Цель: одно место, где лежат URL и токены, и любой агент (Claude Code,
claude-code-router, OpenCode, Codex, Continue, Copilot или что-то новое)
подключается к ним без копирования секретов в конфиги.

## Где что хранится

```
~/.config/secrets.d/secrets.env     # значения, chmod 600, не в git
~/.config/secrets.d/env.example     # шаблон, в git
```

`secrets.env` подключается из `~/.config/zsh/.zshrc`. Все переменные становятся
доступны интерактивной оболочке и любому процессу, запущенному из неё.

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

### OpenCode (`~/.config/opencode/opencode.jsonc`)

Подстановка переменных окружения — `{env:VAR}`:

```jsonc
{
  "provider": {
    "openai": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "{env:OPENAI_BASE_URL}",
        "apiKey": "{env:OPENAI_API_KEY}"
      },
      "models": {
        "just-ai/open-router/anthropic/claude-opus-4.8": {
          "name": "claude-opus-4.8"
        }
      }
    }
  },
  "mcp": {
    "context7": {
      "type": "remote",
      "url": "https://mcp.context7.com/mcp",
      "headers": { "CONTEXT7_API_KEY": "{env:CONTEXT7_API_KEY}" }
    }
  }
}
```

### Claude Code MCP (`claude mcp add-json --scope user`)

Разворачивание `${VAR}` работает в `command`, `args`, `env`, `url`, `headers`:

```sh
claude mcp add-json --scope user atlassian \
  '{"type":"stdio","command":"uvx","args":["mcp-atlassian"],"env":{
     "JIRA_URL":"${JIRA_URL}",
     "JIRA_PERSONAL_TOKEN":"${JIRA_PERSONAL_TOKEN}",
     "CONFLUENCE_URL":"${CONFLUENCE_URL}",
     "CONFLUENCE_PERSONAL_TOKEN":"${CONFLUENCE_PERSONAL_TOKEN}",
     "JIRA_SSL_VERIFY":"false","CONFLUENCE_SSL_VERIFY":"false"}}'

claude mcp add-json --scope user context7 \
  '{"type":"http","url":"https://mcp.context7.com/mcp","headers":{"CONTEXT7_API_KEY":"${CONTEXT7_API_KEY}"}}'
```

Дефолт на случай отсутствия переменной: `${VAR:-fallback}`.

### claude-code-router

CCR 3.x хранит конфигурацию в `~/.claude-code-router/config.sqlite` и позволяет
экспортировать/импортировать JSON через UI (`ccr ui`). В провайдере указывайте
URL и ключ, а не литералы, если клиент это поддерживает; иначе держите
`api_key` синхронным с `secrets.env`.

Профиль Claude Code (`~/.claude/settings.json`) CCR перезаписывает сам — этот файл
не версионируется намеренно.

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
