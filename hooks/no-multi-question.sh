#!/usr/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib/emit.sh"

input=$(cat)
n=$(jq -r '.tool_input.questions | length // 0' <<< "$input")
n=${n:-0}

if [ "$n" -le 1 ]; then
    exit 0
fi

emit_pre_tool_deny "AskUserQuestion called with $n questions in one call. Per CLAUDE.md 'Ask one question at a time': split into sequential calls — present one decision, get an answer, then the next."
