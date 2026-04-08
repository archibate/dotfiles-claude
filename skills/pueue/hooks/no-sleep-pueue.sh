#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""')

# Skip if empty
if [ -z "$command" ]; then
    exit 0
fi

# Bypass marker
if echo "$command" | grep -qF 'BYPASS_SLEEP_PUEUE_CHECK'; then
    exit 0
fi

# Normalize whitespace for robust matching (collapse newlines/spaces)
normalized=$(echo "$command" | tr '\n' ' ' | tr -s ' ')

# Detect anti-pattern: sleep <N> followed by pueue log/status/follow
# Matches: sleep 60 && pueue log 5, sleep 30; pueue status, sleep 120 || pueue log 3 --json
if ! echo "$normalized" | grep -qE 'sleep\s+[0-9]+\s*(&&|;|\|\|)\s*pueue\s+(log|status|follow)\b'; then
    exit 0
fi

# Extract the task ID from the pueue subcommand (if present)
# Pattern: pueue (log|status|follow) <id> where id is a number
task_id=$(echo "$normalized" | grep -oE 'pueue\s+(log|status|follow)\s+[0-9]+' | grep -oE '[0-9]+$' || true)

# Build suggestion message
printf 'Blocked: sleeping to poll pueue task status is an anti-pattern.\n' >&2
printf 'Pueue tasks notify you when they complete via <task-notification>.\n' >&2
printf '\n' >&2

if [ -n "$task_id" ]; then
    printf 'To follow task #%s output in real-time:\n' "$task_id" >&2
    printf '  Bash("pueue follow %s", run_in_background: true)\n' "$task_id" >&2
    printf '\n' >&2
    printf 'Or to start a new background task with auto-follow:\n' >&2
    printf '  Bash("${CLAUDE_PLUGIN_ROOT}/scripts/run_in_pueue.sh '\''your-command'\''", run_in_background: true)\n' >&2
else
    printf 'Use pueue follow <id> in background instead:\n' >&2
    printf '  Bash("pueue follow <task_id>", run_in_background: true)\n' >&2
    printf '\n' >&2
    printf 'Or start tasks with auto-follow:\n' >&2
    printf '  Bash("${CLAUDE_PLUGIN_ROOT}/scripts/run_in_pueue.sh '\''your-command'\''", run_in_background: true)\n' >&2
fi

printf '\nIf you must sleep+poll, add comment `BYPASS_SLEEP_PUEUE_CHECK` to the first line of command.\n' >&2

exit 2
