#!/usr/bin/bash
# PreToolUse hook: block background python tasks without unbuffered output
# CLAUDE.md: "Background tasks: always PYTHONUNBUFFERED=1 or uv run python -u"
# Also resolves `just` recipes to detect indirect python invocations.
set -euo pipefail

source "$(dirname "$0")/lib/bypass.sh"
source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"

read_bash_command

# Only check explicit run_in_background (auto-bg caught by PostToolUse counterpart)
run_in_bg=$(jq -r '.tool_input.run_in_background // false' <<< "$input")
[ "$run_in_bg" = "true" ] || exit 0

bypass_check BYPASS_UNBUFFERED_CHECK

cwd=$(echo "$input" | jq -r '.cwd // "."')

source "$(dirname "$0")/lib/check-python-unbuffered.sh"
if check_python_unbuffered "$command" "$cwd"; then
    emit_pre_tool_deny_bypassable BYPASS_UNBUFFERED_CHECK 'Background python task must use unbuffered output.
Claude launches processes with stdout as a pipe, causing Python to buffer output instead of flushing in real time — making it look stuck or empty.
Either: PYTHONUNBUFFERED=1 uv run python script.py
    or: uv run python -u script.py'
fi

exit 0
