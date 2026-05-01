#!/usr/bin/bash
# Inject system-load context only when resources are actually elevated.
# Silent on idle/normal systems. Reminds the agent to be careful before
# launching heavy work (builds, training, parallel agents, pueue jobs)
# when the box is already loaded.
#
# Cooldown: each tripped metric contributes a coarse bucket token
# (mem 5%, swap 10%, load decile, GPU 10%-util/5%-mem, disk exact %,
# hog process-name only) joined into a signature and cached per
# session_id. If the signature matches the previous emit (state hasn't
# materially changed), the hook stays silent — avoiding repeated
# re-emissions for steady-state high load.
#
# Thresholds are env-overridable (also lets tests force trip/silent paths):
#   SYSLOAD_CPU_FACTOR   load5 / nproc threshold (default 0.7)
#   SYSLOAD_MEM_PCT      memory %used threshold (default 80)
#   SYSLOAD_SWAP_PCT     swap %used threshold (default 50)
#   SYSLOAD_DISK_PCT     disk %used threshold on / (default 90)
#   SYSLOAD_GPU_UTIL     per-GPU %util threshold (default 70)
#   SYSLOAD_GPU_MEM      per-GPU mem% threshold (default 80)
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

# Read session_id from stdin (same pattern as inject-git-status). Default
# to "unknown" if stdin is a TTY (manual run) or jq fails on non-JSON.
PAYLOAD=""
if ! [ -t 0 ]; then
  PAYLOAD=$(cat || true)
fi
SID=$(printf '%s' "$PAYLOAD" | jq -r '.session_id // "unknown"' 2>/dev/null) || SID="unknown"
[ -z "$SID" ] && SID="unknown"

WARN=()
SIG=()  # parallel bucketed signature for cooldown cache
LOAD_TRIPPED=0

# --- CPU 5-min load avg ---
NPROC=$(nproc)
LOAD5=$(awk '{print $2}' /proc/loadavg)
LOAD_THRESH=$(awk -v n="$NPROC" -v f="$CPU_FACTOR" 'BEGIN{printf "%.2f", n*f}')
if awk -v l="$LOAD5" -v t="$LOAD_THRESH" 'BEGIN{exit !(l+0>t+0)}'; then
  WARN+=("CPU: load5=${LOAD5} on ${NPROC} cores (warn>${LOAD_THRESH})")
  # Bucket: floor(load5 / (0.1 * nproc)) — decile of utilization fraction
  LOAD_BUCKET=$(awk -v l="$LOAD5" -v n="$NPROC" 'BEGIN{printf "%d", int(l*10/n)}')
  SIG+=("cpu:${LOAD_BUCKET}")
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
    SIG+=("mem:$((MEM_PCT / 5 * 5))")
  fi
fi

if [ "$SWAP_TOTAL" -gt 0 ]; then
  SWAP_USED=$((SWAP_TOTAL - SWAP_FREE))
  SWAP_PCT=$((SWAP_USED * 100 / SWAP_TOTAL))
  if [ "$SWAP_PCT" -gt "$SWAP_THRESH" ]; then
    SU_GB=$(awk -v u="$SWAP_USED" 'BEGIN{printf "%.1f", u/1048576}')
    WARN+=("SWAP: ${SWAP_PCT}% used (${SU_GB} GiB) — thrashing risk")
    SIG+=("swap:$((SWAP_PCT / 10 * 10))")
  fi
fi

# --- Disk on / ---
DISK_PCT=$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5+0}')
if [ -n "$DISK_PCT" ] && [ "$DISK_PCT" -gt "$DISK_THRESH" ]; then
  WARN+=("DISK /: ${DISK_PCT}% used")
  # Disk %used drifts very slowly; `df`'s native 1% granularity is
  # already coarse enough — no further bucketing.
  SIG+=("disk:${DISK_PCT}")
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
        SIG+=("gpu${idx}:u$((util / 10 * 10))m$((mpct / 5 * 5))")
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
    # Signature uses comm only — pcpu/etimes drift every turn for the
    # same long-running process, which would defeat the cooldown.
    SIG+=("hog:${HOG_COMM}")
  fi
fi

# --- Cooldown: skip if bucketed signature matches last emit for this session.
#     Always write the new signature (including empty), so the cache tracks
#     transitions correctly: clean→elevated and elevated→clean both invalidate. ---
SIG_STR=$(IFS=,; echo "${SIG[*]:-}")
CACHE_DIR=/tmp/claude-system-load
CACHE_FILE="${CACHE_DIR}/${SID}"
mkdir -p "$CACHE_DIR"
CACHED=""
[ -f "$CACHE_FILE" ] && CACHED=$(cat "$CACHE_FILE")
if [ "$CACHED" = "$SIG_STR" ]; then
  exit 0
fi
TMP="${CACHE_FILE}.tmp.$$"
printf '%s' "$SIG_STR" > "$TMP"
mv "$TMP" "$CACHE_FILE"

# Empty signature → state went from elevated to clean; cache updated, no emit.
[ "${#WARN[@]}" -eq 0 ] && exit 0

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
