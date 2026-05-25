#!/usr/bin/bash
# Periodic single-purpose nudges for long-term memory.
#
# Every N user turns (default 3), fires ONE of two single-purpose
# reminders, alternating on a 1-0-1-0 pattern (odd fires = memorize,
# even fires = recall). So each individual prompt arrives every 6
# turns. Single-purpose prompts are shorter and harder to pattern-skip
# than the previous multi-purpose blob; the 3-turn cadence boosts
# density vs the older 9-turn interval to reduce missed capture windows.
#
# State: /tmp/claude-${UID}-state/recall-reminder/
#   <session_id>        — turn counter since last fire, reset on fire
#   <session_id>.fires  — total fires this session (parity → alternation)
#
# The companion hook recall-reminder-reset.sh (PostToolUse on Read|Skill)
# zeros the turn counter when the agent Reads a memory page or invokes
# the memory-add skill — mirroring how TodoWrite resets the built-in
# reminder on actual tool use.
#
# Env override: RECALL_REMINDER_INTERVAL (default 3).
set -euo pipefail

RECALL_INTERVAL="${RECALL_REMINDER_INTERVAL:-3}"
STATE_DIR="/tmp/claude-${UID}-state/recall-reminder"
mkdir -p -m 700 "$STATE_DIR"

PAYLOAD=""
if ! [ -t 0 ]; then
  PAYLOAD=$(cat || true)
fi
SID=$(printf '%s' "$PAYLOAD" | jq -r '.session_id // "unknown"' 2>/dev/null) || SID="unknown"
[ -z "$SID" ] && SID="unknown"

COUNTER_FILE="$STATE_DIR/$SID"
FIRES_FILE="$STATE_DIR/$SID.fires"

COUNT=0
if [ -f "$COUNTER_FILE" ]; then
  COUNT=$(cat "$COUNTER_FILE")
fi
COUNT=$((COUNT + 1))

if [ "$COUNT" -ge "$RECALL_INTERVAL" ]; then
  echo 0 > "$COUNTER_FILE"

  FIRES=0
  if [ -f "$FIRES_FILE" ]; then
    FIRES=$(cat "$FIRES_FILE")
  fi
  FIRES=$((FIRES + 1))
  echo "$FIRES" > "$FIRES_FILE"

  if [ $((FIRES % 2)) -eq 1 ]; then
    MSG="Memory-worthy lesson this turn? Mistake corrected, durable fact emerged, design decision made? Call /memory-add now."
  else
    MSG="Memory not consulted recently. Read memory/pitfalls.md before risky actions; memory/pages/index.md for relevant facts."
  fi

  jq -nc --arg msg "$MSG" '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: $msg
    }
  }'
else
  echo "$COUNT" > "$COUNTER_FILE"
fi
