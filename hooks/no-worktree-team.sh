#!/bin/bash
# Block isolation: "worktree" + team_name combo (silently broken, GitHub #33045)
# Workaround: pre-create worktrees, tell teammates to EnterWorktree(path:)
set -euo pipefail
input=$(cat)
has_worktree=$(echo "$input" | jq -r 'select(.tool_input.isolation == "worktree" and .tool_input.team_name != null) // empty')
if [ -n "$has_worktree" ]; then
  echo "BLOCKED: isolation: worktree silently fails with team_name (#33045). Pre-create worktrees under .claude/worktrees/ and tell teammates to EnterWorktree(path:)." >&2
  exit 2
fi
exit 0
