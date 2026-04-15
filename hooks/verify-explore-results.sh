#!/usr/bin/bash
# PostToolUse hook: remind to verify Explore subagent results before acting on them
set -euo pipefail

input=$(cat)
subagent_type=$(echo "$input" | jq -r '.tool_input.subagent_type // ""')

# Only fire for Explore subagents
if [ "$subagent_type" != "Explore" ]; then
    exit 0
fi

printf 'Verify Explore results: check key claims (file paths, function signatures, line numbers) with a direct Read or Grep before acting on them.\n' >&2
exit 2
