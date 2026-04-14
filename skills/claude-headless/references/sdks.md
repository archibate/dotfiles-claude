# Agent SDKs

Official SDKs that wrap the Claude Code CLI subprocess via the NDJSON stdin/stdout protocol.

**Migration note:** The package was previously `@anthropic-ai/claude-code` (deprecated). Use the new names below.

## TypeScript SDK

```bash
npm install @anthropic-ai/claude-agent-sdk
```

### One-shot query

```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";

const messages = query({
  prompt: "Fix the failing test in auth.py",
  options: {
    allowedTools: ["Read", "Edit", "Bash"],
    permissionMode: "acceptEdits",
    maxTurns: 10,
    maxBudgetUsd: 2.0,
    cwd: "/path/to/project",
  },
});

for await (const message of messages) {
  if (message.type === "assistant") {
    console.log(message.message.content);
  } else if (message.type === "result") {
    console.log("Cost:", message.total_cost_usd);
  }
}
```

### Multi-turn (streaming input)

```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";

async function* userMessages() {
  yield "Start reviewing auth.py";
  // ... wait for some condition ...
  yield "Now focus on SQL injection risks";
}

const messages = query({
  prompt: userMessages(),
  options: { permissionMode: "acceptEdits" },
});

for await (const message of messages) {
  // handle messages
}
```

### Resume session

```typescript
const messages = query({
  prompt: "Continue the review",
  options: { resume: "<session-uuid>" },
});
```

## Python SDK

```bash
pip install claude-agent-sdk
```

### One-shot query

```python
from claude_agent_sdk import query, ClaudeAgentOptions

async def main():
    options = ClaudeAgentOptions(
        allowed_tools=["Read", "Edit", "Bash"],
        permission_mode="acceptEdits",
        max_turns=10,
        max_budget_usd=2.0,
        cwd="/path/to/project",
    )

    async for message in query(prompt="Fix the failing test", options=options):
        if message.type == "assistant":
            print(message.message)
        elif message.type == "result":
            print(f"Cost: {message.total_cost_usd}")
```

### Stateful multi-turn client

```python
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions

async with ClaudeSDKClient(options=ClaudeAgentOptions(...)) as client:
    # First turn
    async for msg in client.send("Analyze auth.py"):
        handle(msg)

    # Follow-up turn (same session)
    async for msg in client.send("Now check for XSS"):
        handle(msg)
```

### Permission callback

```python
def can_use_tool(tool_name: str, tool_input: dict) -> bool:
    if tool_name == "Bash" and "rm" in tool_input.get("command", ""):
        return False
    return True

options = ClaudeAgentOptions(can_use_tool=can_use_tool)
```

## Key Options Reference

| Option | TypeScript | Python | Description |
|---|---|---|---|
| Tools allowlist | `allowedTools` | `allowed_tools` | Pre-approve tools |
| Permission mode | `permissionMode` | `permission_mode` | default/acceptEdits/plan/auto/dontAsk/bypassPermissions |
| Max turns | `maxTurns` | `max_turns` | Agentic turn limit |
| Cost cap | `maxBudgetUsd` | `max_budget_usd` | USD spending limit |
| System prompt | `systemPrompt` | `system_prompt` | Replace default |
| Append prompt | `appendSystemPrompt` | `append_system_prompt` | Append to default |
| Working dir | `cwd` | `cwd` | Project directory |
| Resume | `resume` | `resume` | Session UUID or name |
| Continue | `continueConversation` | `continue_conversation` | Resume most recent |
| Fork | `forkSession` | `fork_session` | Branch on resume |
| Streaming | `includePartialMessages` | `include_partial_messages` | Token-level events |
| Permission CB | N/A | `can_use_tool` | Permission callback |
| Hooks | `hooks` | `hooks` | PreToolUse/PostToolUse/etc. |
| MCP servers | `mcpServers` | `mcp_servers` | Inline MCP server defs |
| Agents | `agents` | `agents` | Dynamic subagent defs |
| Bare mode | `bare` | `bare` | Skip CLAUDE.md/hooks/MCP |
| No persist | `noSessionPersistence` | N/A | In-memory session (TS only) |

## Message Types

Both SDKs yield the same message types:

| Type | Description |
|---|---|
| `SystemMessage` | Session init, API retries |
| `AssistantMessage` | Model output (text + tool_use) |
| `ResultMessage` | Final result with cost/usage |
| `StreamEvent` | Token-level deltas (if enabled) |
| `RateLimitEvent` | Rate limit notifications |
