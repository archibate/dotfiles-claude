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
if [ -z "${CONDA_PREFIX:-}" ] && echo "$command" | grep -qP "${ANCHORS}pip3?${CMD_TRAIL}"; then
    emit_pre_tool_deny 'Use uv instead of pip.
  pip install pkg  →  uv add pkg (project) or uv pip install pkg (venv)
  pip freeze       →  uv pip freeze
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_PACKAGE_MANAGER_CHECK` before the first line of command.'
    exit 0
fi

# Detect npm usage (npm install, npm run, npm ci, etc.)
# CMD_TRAIL ensures `pnpm` (substring `npm`) doesn't trigger.
if echo "$command" | grep -qP "${ANCHORS}npm${CMD_TRAIL}"; then
    emit_pre_tool_deny 'Use pnpm instead of npm.
  npm install  →  pnpm install
  npm run      →  pnpm run
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_PACKAGE_MANAGER_CHECK` before the first line of command.'
    exit 0
fi

exit 0
