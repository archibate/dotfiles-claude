# CLI Flags Reference

Source: `claude --help` (v2.1.105). Only flags relevant to programmatic/headless usage listed.

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
| `--bare` | Skip CLAUDE.md, hooks, plugins, MCP, LSP, auto-memory. Sets `CLAUDE_CODE_SIMPLE=1`. Recommended for CI |
| `--effort low\|medium\|high\|xhigh\|max` | Effort level (max = Opus 4.7 only) |

## Permission Control

| Flag | Description |
|---|---|
| `--permission-mode <mode>` | `default\|acceptEdits\|plan\|auto\|dontAsk\|bypassPermissions` |
| `--allowedTools "Bash(git:*) Edit"` | Pre-approve specific tools (space or comma separated) |
| `--disallowedTools "..."` | Deny specific tools |
| `--tools "..."` | Restrict to only these tools (`""` disables all, `"default"` enables all) |
| `--dangerously-skip-permissions` | Bypass all permission checks (sandboxed environments only) |
| `--allow-dangerously-skip-permissions` | Enable bypass as an option without enabling by default |
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

## Structured Output

| Flag | Description |
|---|---|
| `--json-schema '<schema>'` | Validate output against JSON Schema; result in `structured_output` field |

## File and Resource

| Flag | Description |
|---|---|
| `--file <specs...>` | File resources to download at startup. Format: `file_id:relative_path` |

## Worktree and IDE

| Flag | Description |
|---|---|
| `-w` / `--worktree [name]` | Create a new git worktree for this session |
| `--tmux` | Create tmux session for worktree (requires `--worktree`) |
| `--ide` | Auto-connect to IDE on startup |
| `--chrome` / `--no-chrome` | Enable/disable Chrome integration |

## Debug

| Flag | Description |
|---|---|
| `-d` / `--debug [filter]` | Debug mode with optional category filter (e.g., `"api,hooks"`) |
| `--debug-file <path>` | Write debug logs to file |

## Hidden Flags (not in --help, but functional)

These flags work in v2.1.105 but are not shown by `claude --help`:
- `--max-turns N` — limit agentic turns
- `--permission-prompt-tool <mcp-tool>` — delegate permission prompts to MCP
- `--system-prompt-file <path>` — system prompt from file
- `--append-system-prompt-file <path>` — append system prompt from file
