---
name: memory-add
description: Append a single bullet to memory/staging.md for the next weekly distill cycle to triage. Use when a durable fact emerged mid-conversation that's worth persisting into long-term memory.
compatibility: Claude Code
---

# /memory-add &lt;bullet text&gt;

Append one bullet to `~/.claude/memory/staging.md`. Weekly distill (BUILD.md UPDATE pipeline) drains, triages, and promotes — staging carries no theme, marker, or citation; those are assigned during weekly TRIAGE.

## Args

`/memory-add <bullet text>` — full input after the command name becomes the bullet. Empty input → ask the user for it once, then proceed.

## Action

1. Append `- <bullet text>` (leading dash + space) to `~/.claude/memory/staging.md`. Create the file if missing.
2. Reply with the one-line confirmation: `Staged to memory/staging.md (line N) for next weekly distill.`

## Don't

- Don't load BUILD.md, don't read promoted.md, don't infer themes — weekly TRIAGE handles all of that.
- Don't run pages.py. Staging entries don't enter promoted.md until weekly PROMOTE.
- Don't commit. User controls git.
- Don't add timestamps, citations, or session refs. Staging.md is ephemeral working storage, not an audit log.

## When NOT to invoke

- Updating or deleting an existing memory entry — that's a CLEAN/AUDIT-pass concern; edit `promoted.md` directly during the weekly cycle.
- Logging in-flight project state, hypotheses, or one-off observations — those don't belong in long-term memory at all (BUILD.md DROP rules).

## Anti-patterns

- Calling `/memory-add` before verifying the fact is durable — staging is cheap but reviewing during weekly distill costs your future-self attention.
- Padding the bullet with preamble that EXTRACT would strip — keep it dense, one fact per bullet.
- Multiple bullets in a single invocation — one fact per call. Run the skill again for the next.
