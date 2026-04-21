# CLI Flags Reference

Source: `claude --help` (v2.1.116) cross-checked against [code.claude.com/docs/en/cli-reference](https://code.claude.com/docs/en/cli-reference). Covers programmatic/headless and interactive-mode flags.

**Voice when editing**: descriptive cataloguing only. Each row matches the neutral tone of its siblings. Forbidden phrases: "useful for X", "critical for", "recommended for", "fire-and-forget", "scriptable from", "great for", or any audience-guidance / selling language. If a new row visibly stands out tonally from its neighbors, prune until it doesn't. Mirror docs phrasing where one exists; cite `--help` only for behavior the docs page omits.

## Core Headless Flags

| Flag | Description |
|---|---|
| `-p` / `--print` | Non-interactive mode; print response and exit |
| `--output-format text\|json\|stream-json` | Output format (default: `text`) |
| `--input-format text\|stream-json` | Input format for print mode (default: `text`) |
| `--model <model>` | Model alias (`sonnet`, `opus`) or full name (`claude-sonnet-4-6`) |
| `--verbose` | Full turn-by-turn output (needed with `stream-json` for event details) |
| `--include-partial-messages` | Stream token-level partial events; requires `-p` + `stream-json` |
| `--include-hook-events` | Emit hook lifecycle events into output stream; requires `stream-json` |
| `--replay-user-messages` | Re-echo stdin user messages on stdout; requires both `--input-format stream-json` and `--output-format stream-json` |
| `--bare` | Skip auto-discovery of CLAUDE.md, hooks, skills, plugins, MCP servers, auto-memory. Sets `CLAUDE_CODE_SIMPLE=1` |
| `--betas <betas...>` | Beta API headers (API key users only), e.g. `interleaved-thinking` |
| `--effort low\|medium\|high\|xhigh\|max` | Effort level (max = Opus 4.7 only) |

## Permission Control

| Flag | Description |
|---|---|
| `--permission-mode <mode>` | `default\|acceptEdits\|plan\|auto\|dontAsk\|bypassPermissions` |
| `--allowedTools "Bash(git:*) Edit"` | Pre-approve specific tools (space or comma separated) |
| `--disallowedTools "..."` | Deny specific tools |
| `--tools "..."` | Restrict to only these tools (`""` disables all, `"default"` enables all) |
| `--dangerously-skip-permissions` | Bypass all permission checks (sandboxed environments only) |
| `--allow-dangerously-skip-permissions` | Add `bypassPermissions` to the `Shift+Tab` mode cycle without starting in it (e.g. begin in `plan`, switch later) |
| `--permission-prompt-tool <mcp-tool>` | Delegate permission prompts to an MCP tool. Hidden flag |

## Budget Control

| Flag | Description |
|---|---|
| `--max-budget-usd <amount>` | Maximum USD spend (print mode only) |
| `--max-turns N` | Limit agentic turns (print mode only). Hidden flag — not in `--help` but works |
| `--fallback-model <model>` | Fallback model when default is overloaded (print mode only) |

## Session Management

| Flag | Description |
|---|---|
| `-c` / `--continue` | Continue most recent conversation in cwd |
| `-r` / `--resume [value]` | Resume by session ID/name, or open picker |
| `--fork-session` | Branch into new session ID when resuming |
| `--no-session-persistence` | Don't write session to disk (print mode only) |
| `--session-id <uuid>` | Use a specific session UUID |
| `-n` / `--name <name>` | Name the session for later `--resume <name>` |
| `--from-pr [value]` | Resume session linked to a PR |

## System Prompt and Context

| Flag | Description |
|---|---|
| `--system-prompt "..."` | Replace default system prompt entirely |
| `--system-prompt-file <path>` | Same, from file. Hidden flag |
| `--append-system-prompt "..."` | Append to default system prompt |
| `--append-system-prompt-file <path>` | Same, from file. Hidden flag |
| `--settings <path-or-json>` | Load additional settings |
| `--mcp-config <configs...>` | Load MCP servers from JSON files or strings |
| `--strict-mcp-config` | Only use MCP servers from `--mcp-config`, ignore all others |
| `--agents <json>` | Define subagents dynamically |
| `--agent <agent>` | Agent for the current session (overrides setting) |
| `--add-dir <directories...>` | Grant file access to additional directories |
| `--exclude-dynamic-system-prompt-sections` | Move machine-specific sections to first user message (improves cross-user cache reuse) |
| `--plugin-dir <path>` | Load plugins from directory (repeatable) |
| `--disable-slash-commands` | Disable all skills |
| `--setting-sources <user,project,local>` | Comma-separated list of settings tiers to load |

## Structured Output

| Flag | Description |
|---|---|
| `--json-schema '<schema>'` | Validate output against JSON Schema; result in `structured_output` field |

## File and Resource

| Flag | Description |
|---|---|
| `--file <specs...>` | File resources to download at startup. Format: `file_id:relative_path` (in `--help`, undocumented in public CLI reference page) |

## Worktree and IDE

| Flag | Description |
|---|---|
| `-w` / `--worktree [name]` | Create a new git worktree for this session |
| `--tmux` | Create tmux session for worktree (requires `--worktree`) |
| `--ide` | Auto-connect to IDE on startup |
| `--chrome` / `--no-chrome` | Enable/disable Chrome integration |

## Remote, Web, and Agent-Team Modes

| Flag | Description |
|---|---|
| `--remote "<task>"` | Create a new web session on claude.ai with the given task description |
| `--teleport` | Resume a claude.ai web session in your local terminal |
| `--remote-control` / `--rc [name]` | Start an interactive session with Remote Control enabled so it can also be driven from claude.ai or the Claude app |
| `--remote-control-session-name-prefix <prefix>` | Prefix for auto-generated Remote Control session names (default: hostname). Same as `CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX` |
| `--teammate-mode <auto\|in-process\|tmux>` | Display mode for agent-team teammates (preview) |
| `--channels <plugin:name@market...>` | (Research preview) Listen for MCP channel notifications. Requires Claude.ai auth |
| `--dangerously-load-development-channels` | Enable channels not on the approved allowlist (local dev). Prompts for confirmation |

## Init Hooks

| Flag | Description |
|---|---|
| `--init` | Run initialization hooks then start interactive mode |
| `--init-only` | Run initialization hooks and exit (no interactive session) |
| `--maintenance` | Run maintenance hooks then start interactive mode |

## Debug

| Flag | Description |
|---|---|
| `-d` / `--debug [filter]` | Debug mode with optional category filter (e.g., `"api,hooks"`) |
| `--debug-file <path>` | Write debug logs to file |
| `-v` / `--version` | Print CLI version and exit |

## CLI Subcommands (headless-relevant)

| Command | Purpose |
|---|---|
| `claude setup-token` | Generate a long-lived OAuth token for CI/scripts (subscription auth). Prints to stdout, does not save |
| `claude auth status` | Check login state — exits `0` if logged in, `1` otherwise. `--text` for human-readable; default JSON |
| `claude auth login [--console] [--sso] [--email <addr>]` | Sign in. `--console` uses Anthropic Console (API billing) instead of subscription |
| `claude auth logout` | Log out |
| `claude update` | Update CLI to latest |
| `claude agents` | List all configured subagents, grouped by source (user / project / plugin) |
| `claude auto-mode defaults` | Print built-in auto-mode classifier rules as JSON. `claude auto-mode config` prints the effective config with settings applied |
| `claude remote-control` | Start a Remote Control server (no local interactive session) so claude.ai or the Claude app can drive it. Distinct from the `--remote-control` flag above, which keeps a local interactive session |
| `claude mcp` | Manage MCP servers (see [MCP documentation](https://code.claude.com/docs/en/mcp) for subcommands) |
| `claude plugin <subcmd>` | Manage plugins (alias: `plugins`, see [plugin reference](https://code.claude.com/docs/en/plugins-reference#cli-commands-reference) for subcommands) |

## Hidden Flags (NOT in v2.1.116 `--help`, but documented in CLI reference page)

The official docs note: *"`claude --help` does not list every flag, so a flag's absence from `--help` does not mean it is unavailable."* These flags work but are not shown by `claude --help`:
- `--max-turns N` — limit agentic turns
- `--permission-prompt-tool <mcp-tool>` — delegate permission prompts to MCP
- `--system-prompt-file <path>` — system prompt from file
- `--append-system-prompt-file <path>` — append system prompt from file
- `--init`, `--init-only`, `--maintenance` — init/maintenance hook entry points
