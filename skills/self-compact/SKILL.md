---
name: self-compact
description: >
  Invoke context compaction on current session.
disable-model-invocation: true
---

# Self-triggered Compaction

Proactively invoke context compaction when context usage high and a milestone archived and ready to handover.

> This skill depends on the /claude-dm skill to work.

## Steps

Before compact, first run `/claude-dm self /context` to get current context status. No need to compact if context usage is low.

If you confirm that:

1. milestone archived.
2. key findings concluded.
3. could safely handover.
4. context usage high.
5. prior context is noisy.
6. no unresolved immediate next.

Run `/claude-dm self /compact` to trigger compaction on yourself.

- Pros: fresh context, save tokens, less cogonition overhead, reduce noisy context reducing model intellegence
- Cons: loss of detail information, harmful if currently on a critical middle-way
