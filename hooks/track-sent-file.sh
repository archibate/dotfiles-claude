#!/usr/bin/bash
# PostToolUse hook: after SendUserFile, write the latest delivered file as a
# plain `file://user@ip/path` URL into a per-session state file that the Claude
# Code statusline renderer reads and displays. The statusline is owned by
# Claude's TUI so it persists across redraws; kitty's hints kitten
# (ctrl+shift+e, --type=url) finds the URL there for keyboard-only opening.
# Netloc is derived from SSH_CONNECTION so the local handler can ssh back.
set -euo pipefail

input=$(cat)

tool_name=$(jq -r '.tool_name // ""' <<< "$input")
[ "$tool_name" = "SendUserFile" ] || exit 0

files=$(jq -r '.tool_input.files[]? // empty' <<< "$input")
[ -z "$files" ] && exit 0

session_id=$(jq -r '.session_id // empty' <<< "$input")
[ -n "$session_id" ] || exit 0

cwd=$(jq -r '.cwd // empty' <<< "$input")

# Build a netloc the user's local machine can ssh back to: prefer the server IP
# the SSH client used to reach us (from SSH_CONNECTION), with our own username.
# When Claude runs on localhost (no SSH) or under loopback SSH (127.*, ::1) —
# i.e. the user is already on the same box — leave host empty so the URL is the
# hostless `file:///path` form and the local handler opens it directly without a
# redundant scp round-trip.
host=""
if [ -n "${SSH_CONNECTION:-}" ]; then
    server_ip=$(awk '{print $3}' <<< "$SSH_CONNECTION")
    case "$server_ip" in
        ""|127.*|::1|0:0:0:0:0:0:0:1|localhost) ;;
        *) host="$(whoami)@${server_ip}" ;;
    esac
fi

last_url=""
while IFS= read -r f; do
    [ -z "$f" ] && continue
    abs="$f"
    if [[ "$abs" != /* ]] && [ -n "$cwd" ]; then
        abs="$cwd/$f"
    fi
    if command -v realpath >/dev/null 2>&1; then
        abs=$(realpath -m -- "$abs") || true
    fi
    [ -f "$abs" ] || continue
    last_url="file://${host}${abs}"
done <<< "$files"

[ -z "$last_url" ] && exit 0

state_dir=/tmp/claude-${UID}-state/last-file-url
mkdir -p "$state_dir"
printf '%s\n' "$last_url" > "$state_dir/$session_id"

exit 0
