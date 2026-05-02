#!/usr/bin/bash
# Silently default model: "sonnet" for Explore subagents when omitted,
# but only when the calling (main) agent is itself running on opus.
# Sonnet/Haiku parents are left alone so we don't downgrade haiku → sonnet.
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

# Determine the main agent's model from the transcript's most recent
# assistant turn. PreToolUse payloads don't include a `model` field, so we
# read transcript_path and pull `.message.model` from the last assistant line.
transcript_path=$(jq -r '.transcript_path // ""' <<< "$input")
if [ -z "$transcript_path" ] || [ ! -r "$transcript_path" ]; then
    exit 0
fi

main_model=$(jq -rs 'map(select(.type == "assistant" and (.message.model // "") != "" and (.message.model // "") != "<synthetic>")) | last | .message.model // ""' "$transcript_path" 2>/dev/null || true)
if [[ "$main_model" != *opus* ]]; then
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
