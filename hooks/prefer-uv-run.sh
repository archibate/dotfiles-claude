#!/usr/bin/bash
# PostToolUse hook: hint when python3 is used directly instead of uv run
# CLAUDE.md: "uv run not python3"
set -euo pipefail

source "$(dirname "$0")/lib/read_input.sh"

read_bash_command

# Skip if command already uses uv run
if echo "$command" | grep -qP '\buv\s+run\b'; then
    exit 0
fi

# Skip if an active venv/conda env already scopes bare python3 correctly
if [ -n "${VIRTUAL_ENV:-}" ] || [ -n "${CONDA_PREFIX:-}" ]; then
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

source "$(dirname "$0")/lib/emit.sh"
emit_post_tool_context 'Use uv run python instead of python3 directly.
  python3 script.py  →  uv run python script.py'
