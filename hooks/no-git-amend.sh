#!/usr/bin/bash
# Block git commit --amend (CLAUDE.md: "Never commit --amend. Always create new commits.")
set -euo pipefail

input=$(cat)
command=$(jq -r '.tool_input.command // ""' <<< "$input")

# Skip if empty
if [ -z "$command" ]; then
    exit 0
fi

# Bypass marker
if echo "$command" | grep -qF 'BYPASS_AMEND_CHECK'; then
    exit 0
fi

# Check if command contains git commit with --amend flag
# Match across the whole command string in case of chained commands (&&, ;, |)
if echo "$command" | grep -qP 'git\s+commit\b.*--amend'; then
    printf 'Do not use git commit --amend. Always create new commits instead.\n' >&2
    printf 'If you believe this is a false positive, add comment `BYPASS_AMEND_CHECK` to the first line of command.\n' >&2
    exit 2
fi

exit 0
