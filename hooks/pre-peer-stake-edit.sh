#!/usr/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"

# Cross-peer read-stake serialization for Edit / Write / MultiEdit.
#
# Multiple Claude sessions sharing a workspace race on the read→edit cycle:
#   peer A reads F → drafts old_string=…→new_string=…
#   peer B sneaks an edit on F in the meantime
#   peer A's Edit fails (old_string no longer matches), polls re-read & retry.
#
# This hook stamps a per-(file,sid) stake on every Read. On Edit / Write /
# MultiEdit, if a foreign peer's read-stake is still in the active drafting
# window (age < HARD_TTL) and they hold FIFO priority, we hard-deny — that's
# the only way to actually break the polling loop. Stakes older than HARD_TTL
# are ignored: the foreign peer either finished or moved on, and Claude can
# handle a "File has been modified" error from the tool itself in one re-read.
#
# Storage: /tmp/claude-read-stake/<sha1(path)[:16]>/<session_id>
# Stake mtime = read time; presence alone is the signal, no body needed.
# TTL safety net (SOFT_TTL=60) caps how long a crashed peer's stake lingers
# before the FS pruner could clean it up; we just ignore stakes past it.
#
# Subagents (audit reviewer, codex audit) are SID-distinct from their parent
# but operate on the same files within milliseconds — without an exemption
# they would routinely deny the parent's next Edit. We honor the existing
# CLAUDE_AUDIT_SUBAGENT / CODEX_AUDIT_SUBAGENT convention from audit-edits.py.

[ "${CLAUDE_AUDIT_SUBAGENT:-}" = "1" ] && exit 0
[ "${CODEX_AUDIT_SUBAGENT:-}" = "1" ] && exit 0

read_file_path

tool_name=$(jq -r '.tool_name // ""' <<< "$input")
sid=$(jq -r '.session_id // "unknown"' <<< "$input")
[ -n "$tool_name" ] || exit 0

# Per-session bypass sentinel — Edit/Write/MultiEdit have no natural string
# field for a `# BYPASS_…` comment, so the escape hatch is a marker file the
# agent can `touch` via Bash. Scoped to session_id so one peer's bypass cannot
# disable peer-stake protection for unrelated sessions sharing the workspace.
BYPASS_DIR=/tmp/claude-peer-stake-bypass
BYPASS_SENTINEL="${BYPASS_DIR}/${sid}"
[ -e "$BYPASS_SENTINEL" ] && exit 0

STAKE_ROOT=/tmp/claude-read-stake
# HARD_TTL — active drafting window. A foreign stake younger than this with
#            FIFO priority hard-denies our Edit; that is the only case we
#            actively block.
# SOFT_TTL — outer cutoff for stale-stake pruning during the foreign-stake
#            scan. Stakes older than SOFT_TTL are ignored entirely (TTL
#            safety net for crashed peers).
HARD_TTL=10
SOFT_TTL=60

hash=$(printf '%s' "$file_path" | sha1sum | cut -c1-16)
stake_dir="${STAKE_ROOT}/${hash}"

case "$tool_name" in
  Read)
    mkdir -p "$stake_dir"
    : > "${stake_dir}/${sid}"
    exit 0
    ;;
  Edit|Write|MultiEdit)
    [ -d "$stake_dir" ] || exit 0
    now=$(date +%s)

    # Own stake counts only if still fresh (within SOFT_TTL). A stale own stake
    # would otherwise spuriously beat a fresher foreign one for FIFO purposes —
    # but our content is stale too, so we have no claim to priority.
    own_mtime=0
    if [ -f "$stake_dir/$sid" ]; then
      m=$(stat -c %Y "$stake_dir/$sid" 2>/dev/null) || m=0
      [ $((now - m)) -lt "$SOFT_TTL" ] && own_mtime="$m"
    fi

    # Find the OLDEST fresh foreign stake (within SOFT_TTL). FIFO ordering
    # uses the file mtime; ties break by lexicographically-smaller SID so both
    # sides of a tied compare reach the same verdict.
    foreign=""
    foreign_age=""
    oldest_foreign_mtime=""
    for f in "$stake_dir"/*; do
      [ -e "$f" ] || break
      name=$(basename "$f")
      [ "$name" = "$sid" ] && continue
      mtime=$(stat -c %Y "$f" 2>/dev/null) || continue
      age=$((now - mtime))
      [ "$age" -lt "$SOFT_TTL" ] || continue
      if [ -z "$oldest_foreign_mtime" ] \
        || [ "$mtime" -lt "$oldest_foreign_mtime" ] \
        || { [ "$mtime" -eq "$oldest_foreign_mtime" ] && [ "$name" \< "$foreign" ]; }; then
        oldest_foreign_mtime="$mtime"
        foreign="$name"
        foreign_age="$age"
      fi
    done

    # Foreign in HARD band with FIFO priority: hard-deny so the active peer
    # can finish without our edit invalidating their old_string and triggering
    # a polling loop. Outside the hard band the foreign is treated as moved-on;
    # if our edit collides with stale content the tool's own "File has been
    # modified" error is sufficient diagnostic in one re-read.
    if [ -n "$foreign" ] && [ "$foreign_age" -lt "$HARD_TTL" ] && {
        [ "$own_mtime" -eq 0 ] \
        || [ "$oldest_foreign_mtime" -lt "$own_mtime" ] \
        || { [ "$oldest_foreign_mtime" -eq "$own_mtime" ] && [ "$foreign" \< "$sid" ]; };
    }; then
      emit_pre_tool_deny "Another Claude session (peer ${foreign}) read this file ${foreign_age}s ago and is likely drafting an edit. Letting your edit through now would invalidate their old_string and cause a polling loop.

Recommended: run \`sleep 15\` via Bash, then retry this exact Edit. Up to 5 attempts. A live peer typically finishes in <10s, and the lock auto-expires after ${SOFT_TTL}s — so even if the peer crashed, retries will succeed once the TTL passes. No need to clear locks manually.

If this is a legitimate use, or a false-positive match (e.g. you are certain there is no real read-edit conflict), bypass for this session only: mkdir -p ${BYPASS_DIR} && touch ${BYPASS_SENTINEL} (rm it when done).

File: ${file_path}"
      exit 0
    fi

    # We have priority (or no foreign in hard band). Sweep all stakes — the
    # file is about to change and every peer's pre-edit content is now stale;
    # subsequent peer Edits will re-stake naturally on Read.
    rm -f "$stake_dir"/*
    exit 0
    ;;
esac
exit 0
