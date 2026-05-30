# Workflow — <PROJECT NAME>

**Goal:** <one-line description of the end state>
**DoA:** low | medium | high
**Session ref:** <branch or session id> / <YYYY-MM-DD>
**Last updated:** <YYYY-MM-DD HH:MM>

---

## Task Board

| ID | Task | Status | Deps | Gate |
|---|---|---|---|---|
| T1 | <task> | [ ] | — | — |
| T2 | <task> | [ ] | T1 | GATE-1 |
| T3 | <task> | [ ] | T2 | — |

<!--
Status symbols:
  [ ]  pending      [·]  running (add ETA)
  [x]  done         [!]  blocked     [~]  skipped
-->

---

## Decision Gates

### GATE-1 · <name>
**Input:** <what data/result feeds this gate>
**Question:** <the yes/no or pick-one decision>
**Threshold:** <quantitative pass/fail criterion, if appliable>
**Status:** pending
**Result:** —
**On pass →** T3
**On fail →** <stop / diagnose / alternate task>

---

## Dependency Graph

```
T1 → T2 ──[GATE-1]──→ T3
                ↘ <fail path>
```

---

## Session State (survives compaction)

<!--
Keep ≤10 lines. Rewrite at every milestone.
Must answer: what is running, what is blocked, what gate is next,
and the minimal domain context needed to reconstruct intent.
-->

```
WORKFLOW RESUME:
- T? running: <what command / process, where output goes>
- T? blocked on T?: <what join/analysis step, on what data>
- GATE-? pending: <threshold condition>
- On GATE-? pass: <next action>
- Key context: <1-2 lines of domain state needed to re-orient>
```

---

## Auto-Update Protocol

Update this file when:
1. **Task starts** — set `[·]` + ETA; update Session State
2. **Task completes** — set `[x]`; update Session State
3. **Gate fires** — fill Result; route to pass/fail path
4. **Blocker hits** — set `[!]`; note blocker in task row
5. **Before compaction / commit** — sync full board; refresh Session State

This file is the canonical state. "Where are we?" → read this file first.

---

## Friction Log

*Append one line per recurrence — feeds `/memory-add` at session end.*

<!-- - YYYY-MM-DD — <pattern>. Fix: <what resolves it>. -->
