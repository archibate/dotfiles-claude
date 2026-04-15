#!/usr/bin/bash
# PostToolUse hook: hint when python3 is used directly instead of uv run
# CLAUDE.md: "uv run not python3"
set -euo pipefail

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""')

[ -n "$command" ] || exit 0

# Skip if command already uses uv run
if echo "$command" | grep -qP '\buv\s+run\b'; then
    exit 0
fi

# Detect bare python3/python at command position
if ! echo "$command" | grep -qP '(^|&&|;|\|)\s*python3?\s'; then
    exit 0
fi

# Skip common legitimate bare-python uses
if echo "$command" | grep -qP 'python3?\s+(-V|--version|--help|-c\s)'; then
    exit 0
fi

printf 'Use uv run python instead of python3 directly.\n' >&2
printf '  python3 script.py  →  uv run python script.py\n' >&2
exit 2
