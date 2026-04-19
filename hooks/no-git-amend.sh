#!/usr/bin/bash
# Block destructive git operations (per Claude Code git safety protocol):
#   - git commit --amend  (always create new commits instead)
#   - git push --force / -f  (rewrites remote history; requires explicit user request)
set -euo pipefail

input=$(cat)
command=$(jq -r '.tool_input.command // ""' <<< "$input")

# Skip if empty
if [ -z "$command" ]; then
    exit 0
fi

# Match across the whole command string in case of chained commands (&&, ;, |)

# Check git commit --amend
if ! echo "$command" | grep -qF 'BYPASS_AMEND_CHECK'; then
    if echo "$command" | grep -qP 'git\s+commit\b.*--amend'; then
        printf 'Do not use git commit --amend. Always create new commits instead.\n' >&2
        printf 'If you believe this is a false positive, add comment `BYPASS_AMEND_CHECK` to the first line of command.\n' >&2
        exit 2
    fi
fi

# Check git push --force / -f / --force-with-lease / --force-if-includes
if ! echo "$command" | grep -qF 'BYPASS_FORCE_PUSH_CHECK'; then
    if echo "$command" | grep -qP 'git\s+push\b[^|;&]*(\s--force(-with-lease|-if-includes)?\b|\s-[a-zA-Z]*f\b)'; then
        printf 'Do not use git push --force (or -f). Force-push rewrites remote history and can destroy others'\'' work.\n' >&2
        printf 'If you believe this is a false positive, add comment `BYPASS_FORCE_PUSH_CHECK` to the first line of command.\n' >&2
        exit 2
    fi
fi

exit 0
