---
name: re-read
description: >
  Post-edit audit checklist applied to the ±30-line region after Edit/Write
  tool calls. TRIGGER only when the re-read-after-edit hook reason names
  this skill.
compatibility: Claude Code
---

# Re-Read After Edit

Check the ±30 lines around the edit for:

- **Contradictions** with surrounding statements in the same file.
- **Style/convention drift** — naming, formatting, list styles, heading levels, separators, patterns, idioms.

If issues → fix proactively in the same turn. If clean → proceed silently; never narrate the audit or preface your reply with its verdict ("Region clean", "Audit passed", etc.) — the audit is invisible to the user.
