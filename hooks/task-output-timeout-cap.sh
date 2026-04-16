#!/usr/bin/bash
# PreToolUse hook: cap TaskOutput timeout at 240s to prevent cache busting.
# A blocking call >4 min risks exceeding the 5-min prompt cache TTL.
set -euo pipefail

input=$(cat)
timeout=$(jq -r '.tool_input.timeout // 30000' <<< "$input")

if [ "$timeout" -gt 240000 ] 2>/dev/null; then
    # Silently clamp to 240000
    updated=$(jq '.tool_input + {"timeout": 240000}' <<< "$input")
    jq -n --argjson u "$updated" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        updatedInput: $u
      }
    }'
fi

exit 0
