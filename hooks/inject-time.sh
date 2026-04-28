#!/usr/bin/bash
set -euo pipefail

TIME=$(date '+%Y-%m-%d %H:%M:%S %A')
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "Message time: ${TIME}"
  }
}
EOF
