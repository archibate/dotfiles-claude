#!/usr/bin/env bash
# Ensure pueue daemon is running (with memory cap via cgroup).
# Source this file; it exits the caller on failure.

if ! pueue status &>/dev/null; then
    mem_cap="${PUEUE_MEMORY_MAX:-$(awk '/MemTotal/{printf "%d\n", $2/2}' /proc/meminfo)K}"
    echo "🔄 Starting pueue daemon (MemoryMax=$mem_cap)..."
    systemd-run --user --unit=pueued-limited -p MemoryMax="$mem_cap" "$(command -v pueued)"
    sleep 1
    if ! pueue status &>/dev/null; then
        echo "❌ Failed to start pueue daemon" >&2
        exit 1
    fi
    echo "✅ Daemon started under systemd with MemoryMax=$mem_cap"
fi
