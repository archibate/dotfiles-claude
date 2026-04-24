---
name: claude-headless
description: >
  Programmatic/headless Claude Code usage: CLI flags, stream-json protocol, Agent
  SDKs, session management. This skill should be used when spawning Claude as a
  subprocess, testing a skill or agent behavior, running `claude -p`, building with
  the Agent SDK, or the user says "test in claude", "claude headless", "claude in
  background".
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
| `--bare` | Skip CLAUDE.md, hooks, skills, plugins, MCP, auto-memory, OAuth/keychain (fast CI; see `auth.md`) |
| `--allowedTools "Bash,Read"` | Pre-approve specific tools |
| `--max-budget-usd N` | Cost cap |
| `--json-schema '{...}'` | Structured output extraction |

For complete flag reference, read `references/cli-flags.md`.

## Deep References

Load these on demand based on what the user needs:

- **`references/cli-flags.md`** — Complete CLI flags: headless, permissions, budget, session, system prompt, subcommands
- **`references/auth.md`** — Authentication: subscription OAuth, API key, apiKeyHelper, `--bare` caveat, token storage
- **`references/env-vars.md`** — Complete environment variables: auth, models, thinking, bash/network timeouts, telemetry, TLS, session, plugins, MCP, detection
- **`references/stream-json.md`** — Stream JSON protocol: stdout events, stdin messages, pipe-chaining
- **`references/permissions.md`** — Headless permission modes, --allowedTools, --permission-prompt-tool MCP
- **`references/sdks.md`** — TypeScript and Python Agent SDKs: API, options, streaming, multi-turn
- **`references/patterns.md`** — Real-world patterns: CI/CD, bot bridges, structured extraction, Agent Teams headless
