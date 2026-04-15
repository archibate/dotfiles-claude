#!/usr/bin/bash
# PreToolUse hook: block background python tasks without unbuffered output
# CLAUDE.md: "Background tasks: always PYTHONUNBUFFERED=1 or uv run python -u"
# Also resolves `just` recipes to detect indirect python invocations.
set -euo pipefail

input=$(cat)
run_in_bg=$(echo "$input" | jq -r '.tool_input.run_in_background // false')

# Only check explicit run_in_background (auto-bg caught by PostToolUse counterpart)
if [ "$run_in_bg" != "true" ]; then
    exit 0
fi

command=$(jq -r '.tool_input.command // ""' <<< "$input")

# Skip if empty
[ -n "$command" ] || exit 0

# Bypass marker
if echo "$command" | grep -qF 'BYPASS_UNBUFFERED_CHECK'; then
    exit 0
fi

cwd=$(echo "$input" | jq -r '.cwd // "."')

source "$(dirname "$0")/lib/check-python-unbuffered.sh"
if check_python_unbuffered "$command" "$cwd"; then
    printf 'Background python task must use unbuffered output.\n' >&2
    printf 'Claude launches processes with stdout as a pipe, causing Python to buffer output instead of flushing in real time — making it look stuck or empty.\n' >&2
    printf 'Either: PYTHONUNBUFFERED=1 uv run python script.py\n' >&2
    printf '    or: uv run python -u script.py\n' >&2
    printf 'If you believe this is a false positive, add comment `BYPASS_UNBUFFERED_CHECK` to the first line of command.\n' >&2
    exit 2
fi

exit 0
