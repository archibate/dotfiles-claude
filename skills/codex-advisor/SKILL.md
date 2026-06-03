---
name: codex-advisor
description: Get a cross-model second opinion from gpt-5.5 on your current approach. Use before substantive work (writing, editing, committing to an interpretation), when stuck (errors recurring, approach not converging), when changing approach, or before declaring a task done. The reviewer sees your opening task plus recent work from the session transcript.
compatibility: Claude Code
allowed-tools: Bash(*consult.py:*)
---

# codex-advisor

Run the consult script and read its output:

```bash
scripts/consult.py
```

It locates this session's transcript, forwards it to a stronger cross-model
reviewer (gpt-5.5 by default, via Codex), and prints the verdict (~20s). Weigh the second
opinion against your own reasoning and adapt if it surfaces a flaw — it is an
independent hypothesis, not a mandate. If you have primary-source evidence that
contradicts it, keep your evidence.
