#!/usr/bin/bash
# PostToolUse hook: warn when auto-backgrounded python task lacks unbuffered output
# Catches the case PreToolUse can't: foreground python that got auto-backgrounded by timeout
# Also resolves `just` recipes to detect indirect python invocations.
set -euo pipefail

input=$(cat)

# Only fire when command was backgrounded (explicit or auto)
bg_id=$(echo "$input" | jq -r '.tool_response.backgroundTaskId // empty')
[ -n "$bg_id" ] || exit 0

# Skip if it was explicit run_in_background (already caught by PreToolUse)
run_in_bg=$(echo "$input" | jq -r '.tool_input.run_in_background // false')
if [ "$run_in_bg" = "true" ]; then
    exit 0
fi

command=$(echo "$input" | jq -r '.tool_input.command // ""')
cwd=$(echo "$input" | jq -r '.cwd // "."')

source "$(dirname "$0")/lib/check-python-unbuffered.sh"
if check_python_unbuffered "$command" "$cwd"; then
    printf 'If this is a Python task, stdout is connected to a pipe, so Python buffers output instead of flushing in real time — making it look stuck or empty. Re-run with unbuffered output for easier real-time monitoring: PYTHONUNBUFFERED=1 uv run python script.py\n' >&2
    exit 2
fi

exit 0
