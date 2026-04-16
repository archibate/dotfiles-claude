#!/usr/bin/bash
# PostToolUse hook: prompt cache keep-alive hint on every background launch.
# Bash → use Monitor (~270s timeout); Agent → load /cache-hygiene.
# Fires on every background task (explicit run_in_background or auto-backgrounded).
set -euo pipefail

input=$(cat)

# Detect background: explicit flag or auto-backgrounded via timeout
run_in_bg=$(echo "$input" | jq -r '.tool_input.run_in_background // false')
bg_id=$(echo "$input" | jq -r '.tool_response.backgroundTaskId // empty')

if [ "$run_in_bg" != "true" ] && [ -z "$bg_id" ]; then
    exit 0
fi

tool_name=$(echo "$input" | jq -r '.tool_name // ""')

if [ "$tool_name" = "Bash" ]; then
    printf 'Background Bash task launched. Arm a Monitor (~270s timeout) filtering for completion + error signatures. This keeps the prompt cache (5-minute TTL) warm.\n' >&2
else
    printf 'Background agent launched. Load /cache-hygiene now and follow its keep-alive protocol. This keeps prompt cache (5-minute TTL) warm.\n' >&2
fi
exit 2
