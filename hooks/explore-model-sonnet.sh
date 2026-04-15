#!/usr/bin/bash
# Enforce model: "sonnet" for Explore subagents (CLAUDE.md: "Always spawn Explore subagents with model: sonnet")
set -euo pipefail

input=$(cat)

subagent_type=$(jq -r '.tool_input.subagent_type // ""' <<< "$input")
if [ "$subagent_type" != "Explore" ]; then
    exit 0
fi

model=$(jq -r '.tool_input.model // ""' <<< "$input")
if [ "$model" != "sonnet" ]; then
    printf 'BLOCKED: Explore subagents must use model: "sonnet". Add model: "sonnet" to the Agent call.\n' >&2
    exit 2
fi

exit 0
