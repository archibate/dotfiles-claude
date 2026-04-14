# Headless Permission Handling

## Permission Modes

| Mode | Behavior | Best For |
|---|---|---|
| `default` | Prompts on first use of dangerous tools — aborts in headless if no handler | Development |
| `acceptEdits` | Auto-approves file edits and common filesystem commands (`mkdir`, `touch`, `mv`, `cp`, `rm`, `rmdir`, `sed`) | Trusted scripts |
| `plan` | Read-only analysis, no modifications | Code review |
| `auto` | Background classifier approves/blocks; repeated blocks abort in `-p` mode | Semi-trusted automation |
| `dontAsk` | Auto-denies anything not in `permissions.allow` | Locked CI |
| `bypassPermissions` | Skips everything except protected paths (`.git`, `.vscode`, `.idea`, `.husky`, `.claude` core dirs) | Full trust |

## Pre-Approving Tools

Use `--allowedTools` to pre-approve specific tools without prompting:

```bash
claude -p "Run tests and fix failures" \
  --allowedTools "Bash(npm test),Read,Edit" \
  --permission-mode dontAsk
```

This approves only `npm test` via Bash, Read, and Edit. All other tools are denied.

## Restricting Tools

`--tools` restricts which tools the model can see (others are removed from context):

```bash
claude -p "Analyze this codebase" --tools "Read,Grep,Glob"
```

`--disallowedTools` removes specific tools:

```bash
claude -p "Review code" --disallowedTools "Bash,Write"
```

## Programmatic Permission Decisions

**CLI**: `--permission-prompt-tool <mcp-tool>` delegates permission prompts to an MCP tool (hidden flag, not in `--help`):

```bash
claude -p "Deploy to staging" \
  --permission-prompt-tool stdio \
  --mcp-config mcp-config.json
```

**Python SDK**: `can_use_tool` callback:

```python
def can_use_tool(tool_name: str, tool_input: dict) -> bool:
    if tool_name == "Bash" and "rm" in tool_input.get("command", ""):
        return False
    return True

options = ClaudeAgentOptions(can_use_tool=can_use_tool)
```

For simpler cases, combine `--allowedTools` with `--permission-mode dontAsk` to pre-approve specific tools and deny everything else.

## CI/CD Recommended Setup

Minimal, locked-down CI configuration:

```bash
claude --bare -p "Run tests and report failures" \
  --allowedTools "Bash(npm test),Read" \
  --permission-mode dontAsk \
  --max-budget-usd 1.00 \
  --output-format json
```

Key choices:
- `--bare`: skip CLAUDE.md/hooks/plugins for speed and determinism
- `--permission-mode dontAsk`: abort on unexpected tool use
- `--max-budget-usd`: cost cap as safety net
- `--output-format json`: machine-parseable result
