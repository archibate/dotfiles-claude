#!/usr/bin/bash
# PostToolUse hook: remind to verify Explore subagent results before acting on them
set -euo pipefail

input=$(cat)
subagent_type=$(echo "$input" | jq -r '.tool_input.subagent_type // ""')

# Only fire for Explore subagents
if [ "$subagent_type" != "Explore" ]; then
    exit 0
fi

source "$(dirname "$0")/lib/emit.sh"
emit_post_tool_context 'Verify Explore results: check key claims (file paths, function signatures, line numbers) with a direct Read or Grep before acting on them.'
