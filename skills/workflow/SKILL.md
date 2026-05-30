---
name: workflow
description: >
  Create and manage a WORKFLOW.md task board with decision gates, dependency graph,
  and compaction-proof session state. TRIGGER when starting any multi-step project
  (≥3 tasks with gates or dependencies), or when the user says "create a workflow",
  "task board", or "project dashboard".
disable-model-invocation: true
---

# Workflow Skill

Lightweight PM board for multi-step agent tasks. Resolves three friction points:
progress opacity, gate re-engagement after compaction, and decision accountability.

## When to Use

- Starting a project with ≥3 sequential tasks and at least one decision gate
- User asks for a task board / project plan
- Resuming a session where a WORKFLOW.md exists — read it first, sync status

## Creating a New WORKFLOW.md

1. Copy `template.md` (this skill's directory) to the project working dir
2. Fill in: Goal, DoA, Session ref, task rows, gate thresholds, dependency graph
3. Populate Session State block with the minimal resume token
4. Commit or note the path so compaction survivors can find it

Location convention: `<project-root>/WORKFLOW.md` for single-track work,
`<project-root>/temp/<track>/WORKFLOW.md` for experimental branches.

## Update Protocol

Update WORKFLOW.md when any of these happen — no exceptions:

| Trigger | Action |
|---|---|
| Task starts | Set `[·]` + ETA; update Session State |
| Task completes | Set `[x]`; update Session State |
| Gate fires | Fill Result field; set next task `[·]` or route to fail path |
| Blocker hit | Set `[!]`; note blocker inline |
| Before compaction | Sync entire board; refresh Session State resume token |
| Before commit | Sync board; update Last Updated timestamp |

## Status Symbols

| Symbol | Meaning |
|---|---|
| `[ ]` | Pending — not started |
| `[·]` | Running — in progress (add ETA when known) |
| `[x]` | Done |
| `[!]` | Blocked — waiting on decision or external dependency |
| `[~]` | Skipped / cancelled |

## Gate Protocol

Gate fields are defined in `template.md` (this skill's directory). Setup fields
(Input, Question, Threshold, On pass, On fail) must be filled before the gate fires;
Status and Result are written when it fires.

Under DoA-high: evaluate gate autonomously using threshold; report outcome; proceed
or route to fail path without asking user. Under DoA-low: pause at gate, report
inputs and threshold met/missed, ask user for routing decision.

## Session State Block

The Session State block is a compaction-proof resume token. Keep it ≤10 lines.
It must answer: what is running, what is blocked, what gate is next, and what
the key domain context is (enough to reconstruct intent without the full transcript).

Rewrite it at every milestone — stale resume tokens are worse than none.

## Friction Log

Append one line per recurrence of a friction pattern. Feeds `/memory-add` at
session end. Format: `- YYYY-MM-DD — <pattern>. Fix: <what resolves it>.`
