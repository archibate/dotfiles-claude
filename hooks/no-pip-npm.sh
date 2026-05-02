#!/usr/bin/bash
# PreToolUse hook: block pip and npm in favor of uv and pnpm
# CLAUDE.md: "uv not pip", "pnpm not npm"
#
# Uses shared anchor lib so `sudo pip install`, `bash -c "pip install"`, etc.
# are also caught — `sudo pip install` is the most common form of this anti-
# pattern and was previously slipping through.
set -euo pipefail

source "$(dirname "$0")/lib/bypass.sh"
source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"
source "$(dirname "$0")/lib/anchors.sh"

read_bash_command
bypass_check BYPASS_PACKAGE_MANAGER_CHECK

ANCHORS="(${CMD_ANCHOR_SUDO}|${CMD_WRAPPER})"

# Detect pip usage (pip install, pip freeze, pip list, etc.)
# `pip3?` matches `pip` or `pip3`; CMD_TRAIL ensures it's a complete token
# (so `pipenv` and `pip-tools` don't trigger).
# Skip inside an active conda env — conda users may need pip for conda-managed interpreters.
# Skip if uv isn't installed — no point suggesting an unavailable alternative.
if [ -z "${CONDA_PREFIX:-}" ] && command -v uv >/dev/null 2>&1 && echo "$command" | grep -qP "${ANCHORS}pip3?${CMD_TRAIL}"; then
    emit_pre_tool_deny_bypassable BYPASS_PACKAGE_MANAGER_CHECK 'Use uv instead of pip.
  pip install pkg  →  uv add pkg (project) or uv pip install pkg (venv)
  pip freeze       →  uv pip freeze'
    exit 0
fi

# Detect npm usage (npm install, npm run, npm ci, etc.)
# CMD_TRAIL ensures `pnpm` (substring `npm`) doesn't trigger.
# Skip if pnpm isn't installed — no point suggesting an unavailable alternative.
if command -v pnpm >/dev/null 2>&1 && echo "$command" | grep -qP "${ANCHORS}npm${CMD_TRAIL}"; then
    emit_pre_tool_deny_bypassable BYPASS_PACKAGE_MANAGER_CHECK 'Use pnpm instead of npm.
  npm install  →  pnpm install
  npm run      →  pnpm run'
    exit 0
fi

exit 0
