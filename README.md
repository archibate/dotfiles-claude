# dotfiles-claude

Personal [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configuration: settings, hooks, skills, and shell integrations.

## Install

**Linux / macOS only.** Claude Code itself runs on Windows, but `setup.sh`, the integration shims, and every hook in this pack are bash. WSL works; native Windows shells are not supported.

```bash
curl -fsSL https://raw.githubusercontent.com/archibate/dotfiles-claude/main/setup.sh | bash
```

> Prerequisites: `claude`, `git`, `jq`, `uv`, `node`, `npm`.

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
- **skills/** — 53 skill packs (browser automation, translation, shader dev, and more)
- **plugins/** — installed plugins via marketplaces (`claude-hud`, `claude-plugins-official`, `openai-codex`)
- **integration.sh / .fish** — `claude` wrapper, model shortcuts, and `commit` helper
- **integration-providers.sh / .fish** — optional shortcuts that route claude through third-party Anthropic-compatible endpoints (see the file header for the provider list and prerequisites; the `gpt` shortcut needs the [codex-to-claude](https://github.com/archibate/codex-to-claude) proxy running locally).
- **CLAUDE.md** — global coding preferences and rules

## Defaults you should know

**`permissions.defaultMode: "bypassPermissions"`** — every tool call runs without a Yes/No modal. The reasoning: prompts don't actually protect you. After a workday of clicking through them, your brain auto-accepts — you train the reflex without the judgment, and once you're burned out you're no different from `bypassPermissions`, except you spent your attention to get there. Either accept the risk and let claude work, or stay on web ChatGPT; the middle ground (prompts on, fingers on Enter) is the worst of both worlds.

The actual safety layer lives in `hooks/no-*.sh` — mkfs / partition edits, writes to `/dev`, `/etc`, `/proc`, `/sys`, `/boot`, secure-delete, power-state, recursive chmod/chown, firewall flush, force-push, `git --amend`, `crontab -r`, `killall`, etc. All gates are soft reminders — there are explicit `# BYPASS_*_CHECK` markers so Claude can bypass one specific hazard to avoid trying bizarre workarounds. They are safety nets preventing accidental irreversible mistakes, in the belief that LLMs are not deliberately evil. Locking LLMs into a cage makes them do nothing but chat.

To restore standard prompts: set `"defaultMode": "default"` in `settings.json`.

## Audit Hook

An audit stop hook fires on Claude's final response after several edits, to review correctness and AI slop patterns, both in code and docs.

It starts `claude` and `codex` headless; when issues are flagged, it reports to the main agent to ask it to fix them.

> Bypass `codex` if not installed or not logged in.

After used for a couple of weeks, you may show history audit stats:

```bash
~/.claude/hooks/audit-edits.py stats
```

Tweak `"env"` in `~/.claude/settings.json` to edit `"AUDIT_BACKEND": "both"` to `none|claude|codex|both` to configure.
