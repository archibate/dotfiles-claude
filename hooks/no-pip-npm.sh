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

# Detect pip usage (pip install, pip freeze, pip list, etc.)
# Match pip at command position, not as substring (e.g. "pipenv" should not match)
if echo "$command" | grep -qP '(^|&&|;|\|)\s*pip3?\s'; then
    printf 'Use uv instead of pip.\n' >&2
    printf '  pip install pkg  →  uv add pkg (project) or uv pip install pkg (venv)\n' >&2
    printf '  pip freeze       →  uv pip freeze\n' >&2
    printf 'If you believe this is a false positive, add comment `BYPASS_PACKAGE_MANAGER_CHECK` to the first line of command.\n' >&2
    exit 2
fi

# Detect npm usage (npm install, npm run, npm ci, etc.)
# Match npm at command position, not as substring (e.g. "pnpm" should not match)
if echo "$command" | grep -qP '(^|&&|;|\|)\s*npm\s'; then
    printf 'Use pnpm instead of npm.\n' >&2
    printf '  npm install  →  pnpm install\n' >&2
    printf '  npm run      →  pnpm run\n' >&2
    printf 'If you believe this is a false positive, add comment `BYPASS_PACKAGE_MANAGER_CHECK` to the first line of command.\n' >&2
    exit 2
fi

exit 0
