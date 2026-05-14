#!/usr/bin/bash
# PostToolUse hook: mark /pueue skill as loaded so hint-skill-pueue.sh allows
# subsequent pueue commands. Also syncs gen-seen so a post-compact skill load
# isn't wiped by the pre-bash hook's reset_on_compact call.
set -euo pipefail

input=$(cat)
skill=$(jq -r '.tool_input.skill // ""' <<< "$input")
case "$skill" in *pueue*) ;; *) exit 0 ;; esac

SID=$(jq -r '.session_id // "unknown"' <<< "$input")
SKILL_CACHE_DIR=/tmp/claude-pueue-skill-loaded
mkdir -p "$SKILL_CACHE_DIR"

COMPACT_GEN="/tmp/claude-compact-events/$SID.gen"
if [ -f "$COMPACT_GEN" ]; then
    cp "$COMPACT_GEN" "$SKILL_CACHE_DIR/$SID.gen-seen"
fi

touch "$SKILL_CACHE_DIR/$SID"
