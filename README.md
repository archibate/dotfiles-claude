# dotfiles-claude

Personal [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configuration: settings, hooks, skills, and shell integrations.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/archibate/dotfiles-claude/main/setup.sh | bash
```

Then add shell integration to your rc file:

```bash
# bash/zsh (~/.bashrc or ~/.zshrc)
source ~/.claude/integration.sh

# fish (~/.config/fish/config.fish)
source ~/.claude/integration.fish
```

## What's included

- **settings.json** — permissions, hooks, MCP plugins, environment variables
- **hooks/** — guardrails for safe tool use (block heredocs, enforce Write tool, etc.)
- **skills/** — 40 skill packs (browser automation, translation, shader dev, and more)
- **plugins/** — installed plugins via marketplaces (`claude-hud`, `claude-plugins-official`, `openai-codex`)
- **integration.sh / .fish** — `claude` wrapper (sets `PYTHONUNBUFFERED=1`) and `commit` helper
- **CLAUDE.md** — global coding preferences and rules
