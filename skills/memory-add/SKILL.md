---
name: memory-add
description: Append a single bullet to staging memory. Use when a durable fact emerged mid-conversation that's potentially worth persisting into long-term memory.
compatibility: Claude Code
argument-hint: "<durable fact to remember>"
---

# /memory-add

!```bash
MEMADD_ARG="$(cat <<'__MEMADD_EOF__'
$ARGUMENTS
__MEMADD_EOF__
)"
MEMADD_ARG="$MEMADD_ARG" bash "${CLAUDE_SKILL_DIR}/append.sh"
```

Bullet must be single-line, avoid triple backticks (`` ``` ``), and not contain a line consisting solely of `__MEMADD_EOF__` — multi-line input is hard-rejected; the other two close the embedding heredoc/fence.
