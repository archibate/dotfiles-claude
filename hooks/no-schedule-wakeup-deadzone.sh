#!/usr/bin/bash
# PreToolUse hook: deny ScheduleWakeup delays in the prompt-cache dead zone.
# [300, 1800] is past the 5-min cache TTL but too short to treat as long-idle.
# Policy: <=270s stays warm (split long waits into polls); >1800s accepts one
# miss. Bypass via BYPASS_WAKEUP_DEADZONE in reason.
set -euo pipefail

source "$(dirname "$0")/lib/emit.sh"

input=$(cat)
delay=$(jq -r '.tool_input.delaySeconds // 0' <<< "$input")
reason=$(jq -r '.tool_input.reason // ""' <<< "$input")

if echo "$reason" | grep -qF "BYPASS_WAKEUP_DEADZONE"; then
    exit 0
fi

if awk -v d="$delay" 'BEGIN { exit !(d >= 300 && d <= 1800) }'; then
    emit_pre_tool_deny "ScheduleWakeup delaySeconds=$delay is in the dead zone [300, 1800]: past the 5-min prompt-cache TTL, but too short to treat as long-idle. Drop to <=270s (cache stays warm — wake again if still waiting) or raise past 1800s (genuinely idle, accept one miss). Load /cache-hygiene for the full protocol. If you have legitimate reason, add \`BYPASS_WAKEUP_DEADZONE\` to the reason field."
fi

exit 0
