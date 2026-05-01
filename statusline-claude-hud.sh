#!/usr/bin/env bash
# claude-hud + audit segment statusLine variant.
#
# Runs the third-party claude-hud bun script (model / cost / git / context /
# usage rendering) and appends our audit segment at the tail. Demonstrates the
# value of extracting the audit logic into `audit-edits.py statusline` —
# arbitrary statusLine renderers can compose it in a single line of bash.
#
# To activate, point settings.json.statusLine.command at this script.

set -o pipefail

input=$(cat)
session_id=$(jq -r '.session_id // empty' 2>/dev/null <<<"$input")

# Locate latest claude-hud plugin version on disk.
plugin_root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/claude-hud/claude-hud"
hud_version=$(ls -d "${plugin_root}/"*/ 2>/dev/null | xargs -n1 basename | sort -V | tail -1)
hud_entry="${plugin_root}/${hud_version}/src/index.ts"

hud_output=""
bun_bin=$(command -v bun)
if [[ -n "$hud_version" && -f "$hud_entry" && -n "$bun_bin" ]]; then
  hud_output=$(printf '%s' "$input" | "$bun_bin" "$hud_entry" 2>/dev/null || true)
fi

audit_segment=""
if [[ -n "$session_id" ]]; then
  audit_segment=$(~/.claude/hooks/audit-edits.py statusline "$session_id" 2>/dev/null || true)
fi

printf '%s%s\n' "$hud_output" "$audit_segment"
