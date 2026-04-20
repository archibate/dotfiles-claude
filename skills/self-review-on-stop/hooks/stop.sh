#!/usr/bin/bash
# Skill-local Stop hook: triggers self-review of the last text response.
# Audit procedure lives in ../SKILL.md (load via Skill tool when this fires).
set -euo pipefail

# Skip chat-focused workspaces where cc-connect's single-space "clean" reply
# overwrites the pre-stop message in the UI (claudy_workspace 2026-04-20 incident).
project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
case "$project_dir" in
    */claudy_workspace|*/claudy_workspace/*) exit 0 ;;
esac

input=$(cat)

# Skip subagent Stop events — only self-review on top-level turns.
agent_id=$(echo "$input" | jq -r '.agent_id // empty')
[ -n "$agent_id" ] && exit 0

# Loop guard.
stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active // false')
[ "$stop_hook_active" = "true" ] && exit 0

# Skip review for short responses — under 10 words isn't worth auditing.
last_text=$(echo "$input" | jq -r '.last_assistant_message // ""')
word_count=$(echo "$last_text" | wc -w)
[ "$word_count" -lt 10 ] && exit 0

jq -n '{
  decision: "block",
  continue: true,
  reason: "Audit your last text response. Load the `self-review-on-stop` skill via the Skill tool for the complete audit procedure and reply format.",
  suppressOutput: true
}'
