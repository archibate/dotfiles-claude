#!/usr/bin/env bash
# Bundle claude-dm (lib/*.sh + bin/claude-dm) into one self-contained script.
# Output: portable/portable-claude-dm — rsync to any host, run via ssh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"          # skill root: contains lib/ and bin/
OUT="$HERE/portable-claude-dm"
SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo dirty)"

{
  echo '#!/usr/bin/env bash'
  echo "# portable-claude-dm  build=$SHA  built=$(date -Iseconds)"
  echo '# bundled from lib/{common,read,safety,write}.sh + bin/claude-dm'
  echo 'set -euo pipefail'
  echo
  echo '# ---- runtime dependency check ----'
  echo '# Covers commands invoked by lib/{common,read,safety,write}.sh and the dispatcher.'
  echo 'for _c in tmux jq awk sed pgrep ps find tr wc head tail cat grep stat date sleep cp; do'
  echo '  command -v "$_c" >/dev/null 2>&1 || { echo "portable-claude-dm: missing dep: $_c" >&2; exit 127; }'
  echo 'done'
  echo 'unset _c'
  echo

  for f in lib/common.sh lib/read.sh lib/safety.sh lib/write.sh; do
    [[ -f "$ROOT/$f" ]] || { echo "build: missing $f" >&2; exit 1; }
    echo "# ==================== $f ===================="
    # drop shebang line if present; keep everything else verbatim
    sed '1{/^#!/d;}' "$ROOT/$f"
    echo
  done

  echo "# ==================== bin/claude-dm (dispatcher) ===================="
  # Drop everything up to and including the BEGIN_DISPATCHER sentinel
  # (shebang + set -e + HERE= + source block). The bundled libs above
  # already provide those symbols.
  if ! grep -q '^# BEGIN_DISPATCHER' "$ROOT/bin/claude-dm"; then
    echo "build: bin/claude-dm missing '# BEGIN_DISPATCHER' sentinel" >&2
    exit 1
  fi
  sed '1,/^# BEGIN_DISPATCHER/d' "$ROOT/bin/claude-dm"
} > "$OUT"

chmod +x "$OUT"

LINES=$(wc -l <"$OUT")
BYTES=$(wc -c <"$OUT")
printf 'built %s\n  sha   = %s\n  lines = %s\n  bytes = %s\n' "$OUT" "$SHA" "$LINES" "$BYTES"

# Smoke: bash --noprofile --norc -n catches syntax errors from a stale concat.
if bash -n "$OUT"; then
  printf '  syntax OK\n'
else
  printf '  syntax FAILED\n' >&2
  exit 2
fi
