# Skills

Скиллы — это каталоги с `SKILL.md`, которые Claude Code, OpenCode и VS Code
(Copilot) читают из `~/.claude/skills/`. Путь у всех трёх общий, поэтому
конвертация не нужна.

Храните их в репозитории:

```
src/.claude/skills/<name>/SKILL.md
```

`make install` залинкует каждый файл в `~/.claude/skills/<name>/SKILL.md`.

Требования к скиллу:

- имя каталога совпадает с `name:` во frontmatter `SKILL.md`;
- `description` объясняет, когда скилл применять — по нему агент решает,
  загружать ли его;
- остальные файлы (скрипты, шаблоны) кладутся рядом с `SKILL.md`
  и читаются по относительным путям.

Проектные скиллы кладите в `.claude/skills/` внутри проекта — их подхватят
все три клиента без установки.

Если нужно спрятать `~/.claude` от OpenCode, есть переменные:
`OPENCODE_DISABLE_CLAUDE_CODE=1` (полностью), `..._PROMPT=1` (только
`~/.claude/CLAUDE.md`), `..._SKILLS=1` (только `.claude/skills`).
