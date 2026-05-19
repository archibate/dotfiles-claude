#!/usr/bin/bash
# PostToolUse hook: mark /babysit skill as loaded so hint-skill-babysit.sh allows
# subsequent babysit commands. Also syncs gen-seen so a post-compact skill load
# isn't wiped by the pre-bash hook's reset_on_compact call.
set -euo pipefail

input=$(cat)
skill=$(jq -r '.tool_input.skill // ""' <<< "$input")
case "$skill" in *babysit*) ;; *) exit 0 ;; esac

SID=$(jq -r '.session_id // "unknown"' <<< "$input")
SKILL_CACHE_DIR=/tmp/claude-${UID}-state/babysit-skill-loaded
mkdir -p -m 700 "$SKILL_CACHE_DIR"

COMPACT_GEN="/tmp/claude-${UID}-state/compact-events/$SID.gen"
if [ -f "$COMPACT_GEN" ]; then
    cp "$COMPACT_GEN" "$SKILL_CACHE_DIR/$SID.gen-seen"
fi

touch "$SKILL_CACHE_DIR/$SID"
