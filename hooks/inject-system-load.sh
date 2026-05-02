#!/usr/bin/bash
# Inject system-load context only when resources are actually elevated.
# Silent on idle/normal systems. Reminds the agent to be careful before
# launching heavy work (builds, training, parallel agents, pueue jobs)
# when the box is already loaded.
#
# Cooldown: time-based, per session_id. After an emit, suppress further
# load warnings for SYSLOAD_COOLDOWN_SEC seconds regardless of how the
# metrics shift. The cache file holds a single epoch timestamp at
# /tmp/claude-system-load/<session_id>; on each invocation we exit silent
# if (now - cached) < cooldown, otherwise emit and refresh the timestamp.
#
# Thresholds are env-overridable (also lets tests force trip/silent paths):
#   SYSLOAD_CPU_FACTOR   load5 / nproc threshold (default 0.7)
#   SYSLOAD_MEM_PCT      memory %used threshold (default 80)
#   SYSLOAD_SWAP_PCT     swap %used threshold (default 50)
#   SYSLOAD_DISK_PCT     disk %used threshold on / (default 90)
#   SYSLOAD_GPU_UTIL     per-GPU %util threshold (default 70)
#   SYSLOAD_GPU_MEM      per-GPU mem% threshold (default 80)
#   SYSLOAD_COOLDOWN_SEC seconds to suppress repeat emits  (default 600)
set -euo pipefail
export LC_ALL=C

# Linux-only: relies on /proc/loadavg, /proc/meminfo, GNU `nproc`, and
# GNU `ps` flags (`etimes`, `--no-headers`, `--sort=`) that BSD ps
# (macOS) doesn't support. Stay silent on other kernels rather than
# emit garbage or abort under set -e.
[ "$(uname)" = "Linux" ] || exit 0

CPU_FACTOR="${SYSLOAD_CPU_FACTOR:-0.7}"
MEM_THRESH="${SYSLOAD_MEM_PCT:-80}"
SWAP_THRESH="${SYSLOAD_SWAP_PCT:-50}"
DISK_THRESH="${SYSLOAD_DISK_PCT:-90}"
GPU_UTIL_THRESH="${SYSLOAD_GPU_UTIL:-70}"
GPU_MEM_THRESH="${SYSLOAD_GPU_MEM:-80}"
COOLDOWN_SEC="${SYSLOAD_COOLDOWN_SEC:-600}"

# Read session_id from stdin (same pattern as inject-git-status). Default
# to "unknown" if stdin is a TTY (manual run) or jq fails on non-JSON.
PAYLOAD=""
if ! [ -t 0 ]; then
  PAYLOAD=$(cat || true)
fi
SID=$(printf '%s' "$PAYLOAD" | jq -r '.session_id // "unknown"' 2>/dev/null) || SID="unknown"
[ -z "$SID" ] && SID="unknown"

WARN=()
LOAD_TRIPPED=0

# --- CPU 5-min load avg ---
NPROC=$(nproc)
LOAD5=$(awk '{print $2}' /proc/loadavg)
LOAD_THRESH=$(awk -v n="$NPROC" -v f="$CPU_FACTOR" 'BEGIN{printf "%.2f", n*f}')
if awk -v l="$LOAD5" -v t="$LOAD_THRESH" 'BEGIN{exit !(l+0>t+0)}'; then
  WARN+=("CPU: load5=${LOAD5} on ${NPROC} cores (warn>${LOAD_THRESH})")
  LOAD_TRIPPED=1
fi

# --- Memory & swap (locale-independent via /proc/meminfo) ---
read -r MEM_TOTAL MEM_AVAIL SWAP_TOTAL SWAP_FREE < <(awk '
  /^MemTotal:/      {m=$2}
  /^MemAvailable:/  {a=$2}
  /^SwapTotal:/     {st=$2}
  /^SwapFree:/      {sf=$2}
  END {print m+0, a+0, st+0, sf+0}
' /proc/meminfo)

if [ "$MEM_TOTAL" -gt 0 ]; then
  MEM_USED=$((MEM_TOTAL - MEM_AVAIL))
  MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))
  if [ "$MEM_PCT" -gt "$MEM_THRESH" ]; then
    USED_GB=$(awk -v u="$MEM_USED" 'BEGIN{printf "%.1f", u/1048576}')
    TOT_GB=$(awk -v t="$MEM_TOTAL" 'BEGIN{printf "%.1f", t/1048576}')
    WARN+=("MEM: ${MEM_PCT}% used (${USED_GB}/${TOT_GB} GiB)")
  fi
fi

if [ "$SWAP_TOTAL" -gt 0 ]; then
  SWAP_USED=$((SWAP_TOTAL - SWAP_FREE))
  SWAP_PCT=$((SWAP_USED * 100 / SWAP_TOTAL))
  if [ "$SWAP_PCT" -gt "$SWAP_THRESH" ]; then
    SU_GB=$(awk -v u="$SWAP_USED" 'BEGIN{printf "%.1f", u/1048576}')
    WARN+=("SWAP: ${SWAP_PCT}% used (${SU_GB} GiB) — thrashing risk")
  fi
fi

# --- Disk on / ---
DISK_PCT=$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5+0}')
if [ -n "$DISK_PCT" ] && [ "$DISK_PCT" -gt "$DISK_THRESH" ]; then
  WARN+=("DISK /: ${DISK_PCT}% used")
fi

# --- GPU (if nvidia-smi present) ---
if command -v nvidia-smi >/dev/null 2>&1; then
  GPU_INFO=$(nvidia-smi --query-gpu=index,utilization.gpu,memory.used,memory.total \
             --format=csv,noheader,nounits 2>/dev/null || true)
  if [ -n "$GPU_INFO" ]; then
    while IFS=',' read -r idx util mused mtotal; do
      idx=$(echo "$idx" | tr -d ' '); util=$(echo "$util" | tr -d ' ')
      mused=$(echo "$mused" | tr -d ' '); mtotal=$(echo "$mtotal" | tr -d ' ')
      # Skip rows where any field is non-numeric — `nvidia-smi` returns
      # "[N/A]" or "[Not Supported]" when MIG, locked clocks, or driver
      # errors hide a metric, and `-gt`/`$((...))` would abort under set -e.
      [[ "$util" =~ ^[0-9]+$ ]] && [[ "$mused" =~ ^[0-9]+$ ]] && [[ "$mtotal" =~ ^[0-9]+$ ]] || continue
      [ "$mtotal" -gt 0 ] || continue
      mpct=$((mused * 100 / mtotal))
      if [ "$util" -gt "$GPU_UTIL_THRESH" ] || [ "$mpct" -gt "$GPU_MEM_THRESH" ]; then
        WARN+=("GPU${idx}: ${util}% util, mem ${mpct}% (${mused}/${mtotal} MiB)")
      fi
    done <<< "$GPU_INFO"
  fi
fi

# --- Long-running CPU hog (only when load5 already tripped, to skip
#     well-behaved services that don't actually saturate the box) ---
if [ "$LOAD_TRIPPED" -eq 1 ]; then
  HOG_LINE=$(ps -eo pid,pcpu,etimes,comm --no-headers --sort=-pcpu | awk '
    $2+0 > 50 && $3+0 > 300 && $4 !~ /^(claude|codex|node)$/ {
      print $1, $2, $3, $4
      exit
    }')
  if [ -n "$HOG_LINE" ]; then
    HOG_PID=$(echo "$HOG_LINE" | awk '{print $1}')
    HOG_PCPU=$(echo "$HOG_LINE" | awk '{print $2}')
    HOG_ETIMES=$(echo "$HOG_LINE" | awk '{print $3}')
    HOG_COMM=$(echo "$HOG_LINE" | awk '{print $4}')
    WARN+=("Hog: PID ${HOG_PID} ${HOG_COMM} @ ${HOG_PCPU}% avg CPU for ${HOG_ETIMES}s")
  fi
fi

# Nothing tripped → silent, but leave the cache alone. A re-trip within the
# cooldown window is still suppressed (the prior emit's timestamp is what
# gates it). The point of NOT refreshing on clean ticks is to anchor the
# cooldown to the last *emit* (T_last_emit + COOLDOWN_SEC) rather than the
# last invocation — otherwise every clean prompt would push the next emit
# further out, effectively never re-emitting on a steadily-flapping box.
[ "${#WARN[@]}" -eq 0 ] && exit 0

# --- Cooldown: time-based. Suppress repeat emits within COOLDOWN_SEC of the
#     last one for this session, regardless of which metrics tripped. ---
CACHE_DIR=/tmp/claude-system-load
CACHE_FILE="${CACHE_DIR}/${SID}"
mkdir -p "$CACHE_DIR"
NOW=$(date +%s)
if [ -f "$CACHE_FILE" ]; then
  LAST=$(cat "$CACHE_FILE" 2>/dev/null || echo 0)
  [[ "$LAST" =~ ^[0-9]+$ ]] || LAST=0
  if [ $((NOW - LAST)) -lt "$COOLDOWN_SEC" ]; then
    exit 0
  fi
fi
TMP="${CACHE_FILE}.tmp.$$"
printf '%s' "$NOW" > "$TMP"
mv "$TMP" "$CACHE_FILE"

CTX="System load elevated — be careful before launching heavy work (builds, training, parallel agents, pueue):"
for line in "${WARN[@]}"; do
  CTX="${CTX}
  - ${line}"
done

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
