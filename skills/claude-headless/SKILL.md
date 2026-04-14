---
name: claude-headless
description: Programmatic/headless Claude Code usage: CLI flags, stream-json protocol, Agent SDKs, CI/CD patterns, session management. TRIGGER when working with Claude Code non-interactively — integrations, CI/CD, background spawning, or session file inspection.
---

# Claude Headless

Programmatic usage of Claude Code CLI. Three modes available:

## Quick Start

**One-shot** — single prompt, get result, exit:
```bash
claude -p "Explain this error" --output-format json
```

**Stream JSON** — bidirectional real-time NDJSON over stdin/stdout:
```bash
claude -p --output-format stream-json --input-format stream-json --verbose
# Send: {"type":"user","message":{"role":"user","content":"hello"}}
# Recv: {"type":"assistant","message":{...}}
# Recv: {"type":"result","subtype":"success",...}
```

**Resume** — continue a previous session:
```bash
claude -p "continue the review" --resume <session-id> --output-format json
```

## Key Flags

| Flag | Purpose |
|---|---|
| `-p` / `--print` | Non-interactive mode |
| `--output-format stream-json` | NDJSON event stream on stdout |
| `--input-format stream-json` | NDJSON messages on stdin (multi-turn) |
| `--bare` | Skip CLAUDE.md, hooks, plugins, MCP (fast CI) |
| `--allowedTools "Bash,Read"` | Pre-approve specific tools |
| `--max-budget-usd N` | Cost cap |
| `--json-schema '{...}'` | Structured output extraction |

For complete flag reference, read `${CLAUDE_PLUGIN_ROOT}/references/cli-flags.md`.

## Deep References

Load these on demand based on what the user needs:

- **`references/cli-flags.md`** — Complete CLI flags: headless, permissions, budget, session, system prompt
- **`references/stream-json.md`** — Stream JSON protocol: stdout events, stdin messages, pipe-chaining
- **`references/permissions.md`** — Headless permission modes, --allowedTools, --permission-prompt-tool MCP
- **`references/sdks.md`** — TypeScript and Python Agent SDKs: API, options, streaming, multi-turn
- **`references/patterns.md`** — Real-world patterns: CI/CD, bot bridges, structured extraction, Agent Teams headless
