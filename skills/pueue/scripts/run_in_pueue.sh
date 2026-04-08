#!/bin/bash
set -euo pipefail

# Parse flags
parallel=""
after_ids=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p) parallel="$2"; shift 2 ;;
        -a) after_ids+=("$2"); shift 2 ;;
        --) shift; command="$*"; break ;;
        -h|--help)
            echo "Usage: $0 [-p <parallel>] [-a <task_id>]... -- 'command arg1 arg2'" >&2
            echo "  -p <N>  Max parallel tasks for this project group (default: unlimited)" >&2
            echo "  -a <ID> Run after task ID completes (repeatable)" >&2
            echo "  --      Separator before command (optional if command is a single arg)" >&2
            exit 0
            ;;
        *)  command="$*"; break ;;
    esac
done

if [[ -z "${command:-}" ]]; then
    echo "Usage: $0 [-p <parallel>] [-a <task_id>]... -- 'command arg1 arg2'" >&2
    echo "  -p <N>  Max parallel tasks for this project group (default: unlimited)" >&2
    echo "  -a <ID> Run after task ID completes (repeatable)" >&2
    echo "  --      Separator before command (optional if command is a single arg)" >&2
    exit 1
fi

# 1. Derive project group name from current working directory
#    Replace / with - and strip leading -
group_name="$(pwd | sed 's|/|-|g; s|^-||')"

# 2. Ensure pueue daemon is running
if ! pueue status &>/dev/null; then
    echo "🔄 Starting pueue daemon..."
    pueued -d
    sleep 1
    if ! pueue status &>/dev/null; then
        echo "❌ Failed to start pueue daemon" >&2
        exit 1
    fi
    echo "✅ Daemon started"
fi

# 3. Create project group if it doesn't exist (or update parallel limit)
if ! pueue group --json 2>/dev/null | jq -e --arg g "$group_name" '.[$g]' &>/dev/null; then
    pueue group add -p "${parallel:-0}" "$group_name"
    echo "✅ Created group: $group_name (parallel: ${parallel:-unlimited})"
elif [[ -n "$parallel" ]]; then
    pueue parallel -g "$group_name" "$parallel"
    echo "✅ Updated group: $group_name (parallel: $parallel)"
fi

# 4. Add the task (with optional dependencies)
after_args=()
for aid in "${after_ids[@]}"; do
    after_args+=(--after "$aid")
done
id=$(pueue add -g "$group_name" "${after_args[@]}" --print-task-id -- "$command")

if [[ -z "$id" ]]; then
    echo "❌ Failed to add task" >&2
    exit 1
fi

echo "✅ Task #$id added to group '$group_name'"

echo ""
echo "📝 Task output:"

# 5. Follow the task output
exec pueue follow "$id"
