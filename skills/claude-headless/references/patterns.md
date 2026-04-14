# Real-World Patterns

## CI/CD — GitHub Actions

```yaml
- uses: anthropics/claude-code-action@v1
  with:
    prompt: "Review this PR for security vulnerabilities"
    claude_args: "--model claude-sonnet-4-6"
    anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

Supports Bedrock (`use_bedrock: "true"`) and Vertex AI (`use_vertex: "true"`).

## Structured Extraction

Extract structured data with JSON Schema validation:

```bash
cat logs.txt | claude --bare -p \
  --output-format json \
  --json-schema '{"type":"object","properties":{"errors":{"type":"array","items":{"type":"string"}}}}' \
  "Extract all error messages" | jq '.structured_output'
```

## PR Review

```bash
gh pr diff "$1" | claude --bare -p \
  --append-system-prompt "You are a security engineer." \
  --allowedTools "" \
  --output-format json | jq -r '.result'
```

## Cost-Capped Autonomous Run

```bash
claude --bare -p "Implement feature X from the issue" \
  --permission-mode bypassPermissions \
  --max-budget-usd 2.00 \
  --max-budget-usd 5.00 \
  --output-format json
```

## Session Management

**Named sessions** (recommended for programmatic use):
```bash
# Create with a name
claude -p "Start reviewing auth.py" --name "auth-review" --output-format json

# Resume by name
claude -p "Continue, focus on SQL injection" --resume "auth-review"

# Fork into a new session from an existing one
claude -p "Try alternative approach" --resume "auth-review" --fork-session
```

**UUID-based resume** (capture from output):
```bash
session_id=$(claude -p "Start review" --output-format json | jq -r '.session_id')
claude -p "Continue" --resume "$session_id"
```

**No listing command**: there is no `claude sessions list`. Sessions are `.jsonl` files under `~/.claude/projects/<encoded-cwd>/`. Use `--name` for human-readable handles instead of UUIDs.

## Bare Mode for Deterministic CI

Skip CLAUDE.md, hooks, plugins, MCP for fast, reproducible runs:

```bash
claude --bare -p "Run tests and summarize failures" \
  --allowedTools "Bash(npm test),Read" \
  --output-format stream-json \
  --verbose
```

## Agent Teams in Headless Mode

Agent Teams work in `-p` mode. Teammates spawn via tmux under the hood:

```bash
echo 'Create a team with 2 reviewers. One reviews security, another reviews performance. Merge findings.' | \
  claude -p \
  --allowedTools 'Agent,TeamCreate,SendMessage,TaskCreate,TaskList,TaskUpdate,Bash,Read,Grep' \
  --output-format json
```

Key findings from testing:
- Teammates run headless (no TTY attached)
- Tmux sessions are created automatically even in `-p` mode
- Lead can create teams, spawn teammates, exchange messages, and shut down — all via JSON stream
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` env var required

## Bot Bridge / Proxy

Wrap Claude Code as an HTTP endpoint (e.g., OpenAI-compatible API):

```python
import subprocess, json

proc = subprocess.Popen(
    ["claude", "-p",
     "--output-format", "stream-json",
     "--input-format", "stream-json",
     "--verbose"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    text=True,
)

# Send message
msg = {"type": "user", "message": {"role": "user", "content": "hello"}, "session_id": "default"}
proc.stdin.write(json.dumps(msg) + "\n")
proc.stdin.flush()

# Read events
for line in proc.stdout:
    event = json.loads(line)
    if event["type"] == "result":
        print("Done:", event["result"])
        break
```

## Prompt Cache Optimization

For multi-user scripted workflows sharing the same system prompt:

```bash
claude -p "..." \
  --exclude-dynamic-system-prompt-sections \
  --system-prompt "$(cat shared-prompt.txt)"
```

`--exclude-dynamic-system-prompt-sections` moves machine-specific sections to the first user message, keeping the system prompt identical across invocations for better cache hit rates.
