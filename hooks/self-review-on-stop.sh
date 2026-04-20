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

# Skip review for short responses — under 10 words isn't worth auditing.
# Use the hook's last_assistant_message payload (the transcript file may not be flushed yet).
last_text=$(echo "$input" | jq -r '.last_assistant_message // ""')
word_count=$(echo "$last_text" | wc -w)
[ "$word_count" -lt 10 ] && exit 0

jq -n '{
  decision: "block",
  continue: true,
  reason: "Audit your last text response. See \"Self-Review On Stop\" in ~/.claude/CLAUDE.md.",
  suppressOutput: true
}'
