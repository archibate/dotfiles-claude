#!/usr/bin/bash
# Stop hook: append a one-line TL;DR after a long response.
#
# Triggers when the latest assistant text spans more than TLDR_MIN_LINES lines
# (default 10). Outputs {"decision":"block","reason":...} so the agent
# continues with a short verdict-first summary instead of stopping.
#
# Safety against infinite loops:
#   1. stop_hook_active flag — Claude Code sets this true on the follow-up
#      Stop event after a hook-induced continuation. Always exit silent then.
#   2. Skip if the latest response already contains the /tldr skill's 📌
#      marker anywhere in the text (the skill's defined output format).
#
# The summary format / wording rules live in the `tldr` skill at
# ~/.claude/skills/tldr/SKILL.md, so this hook only emits a short pointer
# and the heavy prompt loads once per session via the Skill tool.
#
# Env override (useful for tests):
#   TLDR_MIN_LINES  threshold for "long" response in lines (default 10)
set -euo pipefail

PAYLOAD=$(cat)

# Skip cc-connect sessions (cc-connect behaves differently than Claude Code:
# it replaces last response by the TLDR message, which is confusing the user)
[ -z "${CC_PROJECT:-}" ] || exit 0

[ "$(jq -r '.stop_hook_active // false' <<< "$PAYLOAD")" = "true" ] && exit 0

LAST_TEXT=$(jq -r '.last_assistant_message // ""' <<< "$PAYLOAD")
[ -n "$LAST_TEXT" ] || exit 0

MIN_LINES="${TLDR_MIN_LINES:-10}"

# Skip short responses (count newlines, not chars — easier to eyeball).
LINE_COUNT=$(printf '%s\n' "$LAST_TEXT" | wc -l)
[ "$LINE_COUNT" -le "$MIN_LINES" ] && exit 0

# Skip if the response already contains the /tldr skill's marker (📌) anywhere
# — defensive fallback when stop_hook_active didn't fire (e.g. /tldr was
# invoked manually outside the Stop loop). Marker matches the format defined
# in ~/.claude/skills/tldr/SKILL.md.
printf '%s' "$LAST_TEXT" | grep -qF '📌' && exit 0

jq -n '{
  decision: "block",
  reason: "Use the /tldr skill."
}'
