# dotfiles-claude

Personal [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configuration: settings, hooks, skills, and shell integrations.

## Install

Prerequisites: `claude`, `git`, `jq`, `uv`, `node`, `npx` (ships with `npm`). The setup script aborts upfront with install hints if any are missing — install Claude Code first via:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Then run:

```bash
curl -fsSL https://raw.githubusercontent.com/archibate/dotfiles-claude/main/setup.sh | bash
```

The setup script is idempotent — re-run the same one-liner anytime to pull updates (it does `git pull --ff-only` on the existing checkout).

## Optional next steps

After `setup.sh` finishes, a few commands cover the remaining one-time setup. Run whichever you want:

```bash
# Wire the shell integration into your rc file (detects your shell, idempotent).
bash ~/.claude/integration-install.sh

# Tally the modern CLI tools preferred by CLAUDE.md against what's installed.
claude "which CLI tools in ~/.claude/CLAUDE.md am I missing?"

# Install kitty (if in a graphical session) and tmux if missing, then show best
# practices for using Claude Code with them (inline image previews via the
# show-image-on-read hook, peer-to-peer messaging via the claude-dm skill,
# persistent sessions, etc.).
claude "Check whether kitty (only if I'm in a graphical X/Wayland session) and tmux are installed. Install whichever is missing using my system package manager, then show best practices for using Claude Code with kitty and tmux. For reference, archibate's personal kitty and tmux configs live at https://github.com/archibate/dotfiles (kitty.conf) and https://github.com/archibate/dotfiles-tmux — fetch them and suggest cherry-picking what fits."
```

For reference, my personal configs that pair well with this setup:

- **[archibate/dotfiles-tmux](https://github.com/archibate/dotfiles-tmux)** — tmux config tuned for the `claude-dm` peer-to-peer messaging skill and multi-session orchestration.
- **[archibate/dotfiles](https://github.com/archibate/dotfiles)** — the rest (kitty, shell, neovim, etc.). Browse and cherry-pick what you want; there's no single one-liner installer — `kitty.conf`, `.zshrc`, etc.

## What's included

- **settings.json** — permissions, hooks, MCP plugins, environment variables
- **hooks/** — guardrails for safe tool use (block heredocs, enforce Write tool, etc.)
- **skills/** — 40 skill packs (browser automation, translation, shader dev, and more)
- **plugins/** — installed plugins via marketplaces (`claude-hud`, `claude-plugins-official`, `openai-codex`)
- **integration.sh / .fish** — `claude` wrapper, model shortcuts, and `commit` helper
- **integration-providers.sh / .fish** — optional shortcuts that route claude through third-party Anthropic-compatible endpoints.
- **CLAUDE.md** — global coding preferences and rules
