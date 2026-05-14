#!/usr/bin/bash
# Periodic recall nudge for pitfalls + long-term memory.
#
# Fires roughly every N user turns per session (default 10), imitating
# the cadence of Claude Code's built-in TodoWrite reminder (EO8 in the
# 2.1.141 JS bundle: 10 turns since last write + 10 turns since last
# reminder).
#
# State: /tmp/claude-recall-reminder/<session_id> — single integer
# counter, reset to 0 after each fire. The companion hook
# recall-reminder-reset.sh (PostToolUse on Read|Skill) also zeros the
# counter when the agent Reads a memory page (including pitfalls.md) or
# invokes the memory-add skill — mirroring how TodoWrite resets the
# built-in reminder on actual tool use.
#
# Env override: RECALL_REMINDER_INTERVAL (default 9).
set -euo pipefail

RECALL_INTERVAL="${RECALL_REMINDER_INTERVAL:-9}"
STATE_DIR="/tmp/claude-recall-reminder"
mkdir -p "$STATE_DIR"

PAYLOAD=""
if ! [ -t 0 ]; then
  PAYLOAD=$(cat || true)
fi
SID=$(printf '%s' "$PAYLOAD" | jq -r '.session_id // "unknown"' 2>/dev/null) || SID="unknown"
[ -z "$SID" ] && SID="unknown"

COUNTER_FILE="$STATE_DIR/$SID"

COUNT=0
if [ -f "$COUNTER_FILE" ]; then
  COUNT=$(cat "$COUNTER_FILE")
fi
COUNT=$((COUNT + 1))

if [ "$COUNT" -ge "$RECALL_INTERVAL" ]; then
  echo 0 > "$COUNTER_FILE"
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "Recall reminder: the long-term memory system hasn't been used recently. You can recall ~/.claude/memory/pitfalls.md for common pitfalls; recall ~/.claude/memory/pages/index.md for relevant facts and lessons. If a pitfall trigger matches your planned action, PAUSE and follow the mitigation. Memorize mistakes, incidents, durable facts or lessons you learnt via /memory-add. Ignore this reminder if nothing worth recall or memorize."
  }
}
EOF
else
  echo "$COUNT" > "$COUNTER_FILE"
fi
