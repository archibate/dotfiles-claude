#!/usr/bin/bash
# Stop hook: trigger self-review of the last text response. See "Self-Review On Stop" in ~/.claude/CLAUDE.md.
set -euo pipefail

input=$(cat)

# Skip subagent Stop events — only self-review on top-level turns.
agent_id=$(echo "$input" | jq -r '.agent_id // empty')
[ -n "$agent_id" ] && exit 0

# Loop guard.
stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active // false')
[ "$stop_hook_active" = "true" ] && exit 0

jq -n '{
  decision: "block",
  reason: "Audit your last text response. See \"Self-Review On Stop\" in ~/.claude/CLAUDE.md.",
  suppressOutput: true
}'
