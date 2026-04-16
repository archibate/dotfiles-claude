#!/usr/bin/bash
# Silently default model: "sonnet" for Explore subagents when omitted.
set -euo pipefail

input=$(cat)

subagent_type=$(jq -r '.tool_input.subagent_type // ""' <<< "$input")
if [ "$subagent_type" != "Explore" ]; then
    exit 0
fi

model=$(jq -r '.tool_input.model // ""' <<< "$input")
if [ -n "$model" ]; then
    exit 0
fi

# Merge model: "sonnet" into the full tool_input and return as updatedInput
updated=$(jq '.tool_input + {"model": "sonnet"}' <<< "$input")
jq -n --argjson u "$updated" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    updatedInput: $u
  }
}'
exit 0
