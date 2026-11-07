# Секреты и адреса сервисов

Этот каталог — шаблон. Реальные значения живут вне репозитория:

```
~/.config/secrets.d/secrets.env     # чей-то chmod 600, не коммитится
```

Создать: `make secrets` (копирует `env.example` -> `secrets.env`).
Подключается автоматически из `~/.config/zsh/.zshrc`.

## Правила

- В репозиторий попадает только `env.example` без значений.
- Не экспортируйте ключи в общие файлы (`~/.zshrc`, `local.zsh`).
- Для агентов и CLI ссылайтесь на переменные, а не на литералы:
  `{env:OPENAI_API_KEY}` в `opencode.jsonc`, `${OPENAI_API_KEY}` в MCP-конфиге.
- Один шлюз — пара `OPENAI_BASE_URL` + `OPENAI_API_KEY`. Несколько шлюзов —
  пары с префиксом по смыслу (`TEAM_*`, `PERSONAL_*`).
- Токены с истечением (Jira/Confluence PAT, Bitbucket) удобно обновлять здесь же,
  без правки конфигов агентов.

Соответствие «сервис -> переменные -> URL» — в [`docs/ai-providers.md`](../../../docs/ai-providers.md).
