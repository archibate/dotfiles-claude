---
name: memory-add
description: Append a single bullet to staging memory. Use when a durable fact, knowledge, lesson, or pitfall (mistake-correction pattern) emerged mid-conversation that's potentially worth persisting into long-term memory. Also use when user corrected your mistake, says "remember X", "remember not to X", or "next time, do Y instead of X", "do not mistake on X again". Invoke with one line prose to memorize.
compatibility: Claude Code
argument-hint: "<durable fact to remember>"
---

# /memory-add

```!
MEMADD_ARG="$(cat <<'__MEMADD_EOF__'
$ARGUMENTS
__MEMADD_EOF__
)"
MEMADD_ARG="$MEMADD_ARG" bash "${CLAUDE_SKILL_DIR}/append.sh" || echo "This is a skill works by consuming arguments. Consider invoke with /memory-add <some fact to remember>"
```
