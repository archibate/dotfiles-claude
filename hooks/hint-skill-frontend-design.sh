#!/usr/bin/bash
# PreToolUse hook: when Claude is about to Write an HTML file, nudge it to
# load the `frontend-design` skill before authoring the page. Fires at most
# once per session_id to avoid re-prompting on iterative edits.
#
# Pattern: hooks of the form `hint-skill-<name>.sh` boost skill recall by
# turning "the agent should remember to load skill X when doing Y" from a
# soft instruction into an environment-driven nudge tied to Y's tool call.
set -euo pipefail

source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"

read_file_path

case "$file_path" in
    *.html|*.htm) ;;
    *) exit 0 ;;
esac

SID=$(jq -r '.session_id // "unknown"' <<< "$input")
CACHE_DIR=/tmp/claude-skill-hint-frontend-design
CACHE="$CACHE_DIR/$SID"
mkdir -p "$CACHE_DIR"
[ -f "$CACHE" ] && exit 0
touch "$CACHE"

emit_pre_tool_warn 'About to write an HTML file. Load the /frontend-design skill via the Skill tool before authoring the page — it has guidance on avoiding generic AI-slop aesthetics. Skip if the file is a throwaway test or non-visual fixture.'
