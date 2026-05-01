#!/usr/bin/env bash
# Custom Claude Code statusLine renderer.
#
# Reads stdin JSON (session_id, cwd, model.id, context_window, workspace),
# renders a single line with model + ctx% + cwd + git + an audit segment
# scoped to the current session.
#
# Audit segment priority:
#   1. <sid>.json.auditing-<pid>-<ts>  → "auditing… Ns" (cyan) while alive
#   2. <sid>.json.audit-result         → "audit ✓/⚠/✗" (within TTL)
#   3. nothing
#
# Wired in settings.json.statusLine with refreshInterval: 5.

set -o pipefail

input=$(cat)

j() { jq -r "$1" 2>/dev/null <<<"$input"; }

session_id=$(j '.session_id // empty')
cwd=$(j '.cwd // empty')
project_dir=$(j '.workspace.project_dir // empty')
model_id=$(j '.model.id // .model.display_name // empty')
ctx_pct=$(j '.context_window.used_percentage // empty')

RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
MAGENTA=$'\033[35m'
CYAN=$'\033[36m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

# --- model_short -------------------------------------------------------------
# claude-opus-4-7[1m] -> opus-4.7-1m  ;  display_name passes through.
model_segment=""
if [[ -n "$model_id" ]]; then
  if [[ "$model_id" == claude-* ]]; then
    m="${model_id#claude-}"
    m=$(sed -E 's/([0-9])-([0-9])/\1.\2/g; s/\[([^]]+)\]/-\1/g' <<<"$m")
  else
    m="$model_id"
  fi
  model_segment="${BOLD}${MAGENTA}${m}${RESET}"
fi

# --- ctx% --------------------------------------------------------------------
ctx_segment=""
if [[ "$ctx_pct" =~ ^[0-9]+$ ]] && (( ctx_pct > 0 )); then
  if   (( ctx_pct < 70 )); then color=$GREEN
  elif (( ctx_pct < 85 )); then color=$YELLOW
  else                          color=$RED
  fi
  ctx_segment=" ${color}[${ctx_pct}%]${RESET}"
fi

# --- cwd_short ---------------------------------------------------------------
cwd_segment=""
if [[ -n "$cwd" ]]; then
  if [[ -n "$project_dir" && "$cwd" == "$project_dir"* ]]; then
    rel="${cwd#$project_dir}"
    rel="${rel#/}"
    cwd_short="${rel:-$(basename "$project_dir")}"
  elif [[ "$cwd" == "$HOME" ]]; then
    cwd_short="~"
  elif [[ "$cwd" == "$HOME/"* ]]; then
    cwd_short="~/${cwd#$HOME/}"
  else
    cwd_short=$(basename "$cwd")
  fi
  cwd_segment="${BLUE}${cwd_short}${RESET}"
fi

# --- git ---------------------------------------------------------------------
git_segment=""
if [[ -n "$cwd" ]] && git -C "$cwd" rev-parse --git-dir &>/dev/null; then
  branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ -n "$branch" && "$branch" != "HEAD" ]]; then
    if [[ -n "$(git -C "$cwd" status --porcelain 2>/dev/null)" ]]; then
      git_segment="  ${YELLOW}${branch}*${RESET}"
    else
      git_segment="  ${GREEN}${branch}${RESET}"
    fi
  fi
fi

# --- audit segment -----------------------------------------------------------
# Logic and color/TTL contract live in audit-edits.py statusline subcommand.
# Output already includes leading whitespace; empty string when nothing applies.
audit_segment=""
if [[ -n "$session_id" ]]; then
  audit_segment=$(~/.claude/hooks/audit-edits.py statusline "$session_id" 2>/dev/null || true)
fi

# --- compose -----------------------------------------------------------------
left="${model_segment}${ctx_segment}"
[[ -n "$left" && -n "$cwd_segment" ]] && left+="  "
printf '%s%s%s%s\n' "$left" "$cwd_segment" "$git_segment" "$audit_segment"
