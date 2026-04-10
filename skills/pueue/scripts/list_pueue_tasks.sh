#!/usr/bin/env bash
set -euo pipefail

# List tasks in the current project's pueue group

# 1. Derive project group name from current working directory
group_name="$(pwd | sed 's|/|-|g; s|^-||')"

# 2. Ensure pueue daemon is running
source "$(dirname "${BASH_SOURCE[0]}")/ensure_daemon.sh"

# 3. Show status for this group as markdown table
echo "📁 Project group: $group_name"
echo ""

pueue status -g "$group_name" --json | jq -r '
  .tasks | to_entries | sort_by(.key | tonumber) |
  if length == 0 then
    ["_No tasks_"]
  else
    ["| Id | Status | Command | Path | Start | End |", "|---|---|---|---|---|---|"] +
    [.[] | {
      id: .value.id,
      status: (.value.status | keys[0] // "Unknown"),
      cmd: .value.original_command[:50],
      path: .value.path,
      start: ((.value.status.Start.start // .value.status.Done.start // "") | split("T")[1][:8]),
      end: ((.value.status.Done.end // "") | split("T")[1][:8])
    } | "| \(.id) | \(.status) | `\(.cmd)` | `\(.path)` | \(.start) | \(.end) |"]
  end | .[]
'
