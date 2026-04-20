#!/usr/bin/bash
# PreToolUse hook: block pip and npm in favor of uv and pnpm
# CLAUDE.md: "uv not pip", "pnpm not npm"
set -euo pipefail

input=$(cat)
command=$(jq -r '.tool_input.command // ""' <<< "$input")

[ -n "$command" ] || exit 0

# Bypass marker
if echo "$command" | grep -qF 'BYPASS_PACKAGE_MANAGER_CHECK'; then
    exit 0
fi

source "$(dirname "$0")/lib/emit.sh"

# Detect pip usage (pip install, pip freeze, pip list, etc.)
# Match pip at command position, not as substring (e.g. "pipenv" should not match)
if echo "$command" | grep -qP '(^|&&|;|\|)\s*pip3?\s'; then
    emit_pre_tool_deny 'Use uv instead of pip.
  pip install pkg  →  uv add pkg (project) or uv pip install pkg (venv)
  pip freeze       →  uv pip freeze
If you believe this is a false positive, add comment `BYPASS_PACKAGE_MANAGER_CHECK` to the first line of command.'
    exit 0
fi

# Detect npm usage (npm install, npm run, npm ci, etc.)
# Match npm at command position, not as substring (e.g. "pnpm" should not match)
if echo "$command" | grep -qP '(^|&&|;|\|)\s*npm\s'; then
    emit_pre_tool_deny 'Use pnpm instead of npm.
  npm install  →  pnpm install
  npm run      →  pnpm run
If you believe this is a false positive, add comment `BYPASS_PACKAGE_MANAGER_CHECK` to the first line of command.'
    exit 0
fi

exit 0
