#!/usr/bin/env bash
set -euo pipefail

# List tasks in the current project's pueue group

# 1. Derive project group name from current working directory
group_name="$(pwd | sed 's|/|-|g; s|^-||')"

# 2. Ensure pueue daemon is running (with memory cap via cgroup)
if ! pueue status &>/dev/null; then
    mem_cap="${PUEUE_MEMORY_MAX:-$(awk '/MemTotal/{printf "%d\n", $2/2}' /proc/meminfo)K}"
    echo "🔄 Starting pueue daemon (MemoryMax=$mem_cap)..."
    systemd-run --user --unit=pueued-limited -p MemoryMax="$mem_cap" /home/ubuntu/.local/bin/pueued
    sleep 1
    if ! pueue status &>/dev/null; then
        echo "❌ Failed to start pueue daemon" >&2
        exit 1
    fi
    echo "✅ Daemon started under systemd with MemoryMax=$mem_cap"
fi

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
