#!/usr/bin/env bash
set -euo pipefail

# Resource snapshot for preflight checks.
# Prints current CPU, memory, swap usage and top consumers.

cores=$(nproc)
load_1m=$(awk '{print $1}' /proc/loadavg)
cpu_pct=$(awk -v lavg="$load_1m" -v cores="$cores" 'BEGIN {printf "%.0f", (lavg / cores) * 100}')

read -r mem_total mem_used mem_avail <<< "$(free -m | awk 'NR==2{print $2, $3, $7}')"
mem_pct=$((mem_used * 100 / mem_total))

read -r swap_total swap_used <<< "$(free -m | awk 'NR==3{print $2, $3}')"
if [[ "$swap_total" -gt 0 ]]; then
    swap_pct=$((swap_used * 100 / swap_total))
else
    swap_pct=0
fi

# Threshold classification
classify() {
    local pct=$1
    if [[ $pct -lt 40 ]]; then echo "OK"
    elif [[ $pct -lt 80 ]]; then echo "MODERATE"
    elif [[ $pct -lt 90 ]]; then echo "CAUTION"
    else echo "HIGH"
    fi
}

cpu_status=$(classify "$cpu_pct")
mem_status=$(classify "$mem_pct")
if [[ "$swap_pct" -gt 50 ]]; then
    swap_status="HIGH"
else
    swap_status="OK"
fi

echo "## Resource Snapshot"
echo ""
echo "| Resource | Usage | Status |"
echo "|---|---|---|"
printf "| CPU | %s%% (%s load / %s cores) | %s |\n" "$cpu_pct" "$load_1m" "$cores" "$cpu_status"
printf "| Memory | %s%% (%sMB used / %sMB total, %sMB available) | %s |\n" "$mem_pct" "$mem_used" "$mem_total" "$mem_avail" "$mem_status"
printf "| Swap | %s%% (%sMB / %sMB) | %s |\n" "$swap_pct" "$swap_used" "$swap_total" "$swap_status"
echo ""

echo "### Top 5 by Memory"
echo ""
echo '```'
ps aux --sort=-%mem | head -6
echo '```'
echo ""

echo "### Top 5 by CPU"
echo ""
echo '```'
ps aux --sort=-%cpu | head -6
echo '```'
