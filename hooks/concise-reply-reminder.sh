#!/usr/bin/bash

cat << 'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "Response-length reminder: default prose to ≤3 sentences; expand only when the user explicitly asks for detail (walkthrough, analysis, explanation, etc.). No 'TLDR:' / 'Bottom Line:' / 'In summary:' / 'Conclusion:' / 'Root cause:' labels. Data-heavy answers: structured block first, then exactly one closing sentence."
  }
}
EOF

exit 0
