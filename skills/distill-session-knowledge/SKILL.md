---
name: distill-session-knowledge
description: >
  End-of-day routine: scan today's high-quality Claude transcripts in the
  current project, extract durable facts (pitfalls, resource costs, results),
  and propose surgical edits to the right reference docs. This skill should
  be used when the user says "distill today", "distill session", or asks
  "what should we learn from today's work".
allowed-tools:
  - Bash(fd:*)
  - Bash(jq:*)
  - Bash(uv:*)
  - Bash(rg:*)
  - Bash(wc:*)
  - Bash(date:*)
  - Bash(git diff:*)
  - Bash(git status:*)
  - Read
  - Edit
  - AskUserQuestion
---

# Distill Session Knowledge

Scan today's substantive Claude conversations in the current project and land
durable facts (pitfalls, costs, calibrated results) into the project's reference
docs. Aggressively filter session-specific noise and one-off opinions.

## Goal

At least one merged or cleanly-proposed edit to a `references/*.md` (or
equivalent) doc, scoped strictly to facts that will still be true next month.

## Steps

### 1. Inventory today's transcripts

Use `<today>` from `date -I`. Run:

```
fd -e jsonl --changed-within '<today> 00:00:00' . ~/.claude/projects
```

Note the count. Most files will be one-prompt automated probes — that's
normal; cut them in step 3.

**Success criteria**: file list scoped to the current project's encoded cwd
slug under `~/.claude/projects/`.

### 2. Distill (with date slicing)

Run the bundled filter, passing today's date as the slice:

```
uv run ~/.claude/skills/distill-session-knowledge/distill.py <today>
```

The script keeps only messages whose timestamp begins with `<today>`. A
session that started yesterday and continued today contributes only its
**today-events** to the output; its `n_user`, `started`, and `ended` reflect
the today-slice. Sessions with zero today-user-prompts are dropped entirely.

Output: `/tmp/distilled/<cwd-slug>.jsonl`. Each record has
`{session, cwd, branch, started, ended, session_started, session_ended,
is_carryover, n_user, n_asst, n_user_total, user[], asst[]}` — with
`<system-reminder>`, `<command-*>`, `<task-notification>`,
`<local-command-caveat>`, and cache-keepalive ticks already stripped.

### 3. Cut to high-quality

Filter the project's file to sessions where `n_user >= 3`. The date filter
is already applied by step 2, so a single threshold suffices:

```
jq -r 'select(.n_user >= 3) | "\(.n_user)/\(.n_user_total)\t\(.is_carryover)\t\(.session)\t\(.started)"' /tmp/distilled/<cwd-slug>.jsonl
```

The `n_user / n_user_total` ratio shows today's prompts vs the whole-session
total. The `is_carryover` flag (true when the session started before today)
tells you the engineering arc may extend earlier than the slice — useful
context for step 4 but not a reason to exclude the session.

If zero remain, tell the user "no substantive sessions today" and stop.
Do not invent material from low-quality sessions.

### 4. Read & categorize

For each surviving session, pull `user[]` and `asst[]`. Read prompts for
intent; scan assistant first-lines for the engineering arc.

Sort each candidate fact:

| Category | Looks like | Targets |
|---|---|---|
| **Pitfall** | Tool/syntax bug, gotcha, surprising behavior | `pitfalls.md`, tool-specific docs |
| **Cost** | Measured runtime / memory / I/O for a concrete task | `task-costs.md` |
| **Result** | Calibrated metric (IC, ICIR, σ vs null) of a permanent artifact | `specs/ablation.md`, `specs/feature.md` |
| **Pattern** | Workflow tendency, communication style | skip — belongs in skills/hooks |
| **One-off** | "Fix this", "rename that", task-specific | skip |

**Rule**: if a fact embeds a `temp/…` path, session ID, MLflow run ID, or
"today's commit X", strip those references before considering durability.
If nothing remains after stripping, it isn't a fact.

### 5. Discover targets, then read their format

Locate candidate target files by filename heuristic and `CLAUDE.md` layout
hints. For each candidate, **read the target file's adjacent section
before drafting**. The existing rhythm dictates the addition's shape — a
doc built around tables takes a row, a doc built around formula blocks
takes a formula block, a doc built around prose takes a paragraph. Picking
the wrong shape produces an addition that visibly doesn't belong, and the
user has to redirect.

### 6. Draft inline, edit, show diff

Pick the strongest 1–3 candidates and the recommended target file for each
without asking. Draft the addition in the matching format observed in
step 5, make the Edits, then show `git diff` plus a short routing table:

| File | Section added | Durability rationale |
|---|---|---|

**Do not gate step 6 on a pre-selection question.** Multi-choice questions
asked before the user sees a drafted diff are strictly worse than the agent
defaulting and the user redirecting from the diff: the user can't react to
phrasing they haven't seen, and the question collapses a continuous
judgment into 2–4 buckets. For low-blast-radius additive doc edits,
reverting an Edit is one tool call — cheaper than the question round-trip.

Ask only when the choice is genuinely a coin-flip AND changes the drafted
text substantively. In that case, draft both versions and use
AskUserQuestion's `preview` field to show them side-by-side.

**Never include in the body**: ephemeral paths (`temp/`, `/tmp/`), session
IDs, run IDs, specific commit hashes, dates inside the row, "today's"
wording. If stripping these leaves nothing, the candidate wasn't durable.

### 7. Audit & finalize

After Edits, the project's Stop hook runs `audit-edits.py` automatically.
For each FIXES entry: judge whether it's a true issue (DOC-contradiction,
incident-leak, scope creep) or a false positive; apply or dismiss explicitly.

Show the final `git diff` and stop. Do not commit unless asked.

## Rules

- **No fabrication** — every fact must trace back to actual prompt or
  assistant output in the transcript. If you can't quote it, drop it.
- **Preferences are not facts** — terse confirmation style, codex habits,
  etc. live in CLAUDE.md or hooks, not distilled docs.
- **One bad edit > zero edits is the wrong tradeoff here.** Skipping a
  borderline fact is always correct; landing a wrong one pollutes the
  reference doc.
