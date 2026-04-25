#!/usr/bin/bash
# PostToolUse hook: enqueue edited file paths into a session-scoped queue.
# The actual audit runs once at Stop time (see audit-on-stop.sh) — batches all
# edits in a turn into a single subagent call instead of one per Edit.
set -euo pipefail

input=$(cat /dev/stdin)
file_path=$(jq -r '.tool_input.file_path // empty' <<< "${input}")
session_id=$(jq -r '.session_id // empty' <<< "${input}")

[ -z "${file_path}" ] && exit 0
[ -z "${session_id}" ] && exit 0

queue_dir="/tmp/claude-audit-queue"
mkdir -p "${queue_dir}"
queue_file="${queue_dir}/${session_id}.txt"

# Append unique file_path (dedup keeps the queue small)
grep -qxF "${file_path}" "${queue_file}" 2>/dev/null || echo "${file_path}" >> "${queue_file}"

exit 0
