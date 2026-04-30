---
name: distill-session-knowledge
description: >
  Periodic distillation: scan the last 5 days of high-quality Claude
  transcripts in the current project, dedup facts seen across sessions and
  against existing docs, and propose surgical edits to the right reference
  docs. Wider-than-daily window avoids 00:00 boundary loss. This skill
  should be used when the user says "distill recent", "distill session",
  "distill last week", or asks "what should we learn from recent work".
disable-model-invocation: true
allowed-tools:
  - Bash(fd:*)
  - Bash(jq:*)
  - Bash(uv run:*)
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

Scan the last 5 days of substantive Claude conversations in the current
project and land durable facts (pitfalls, costs, calibrated results) into
the project's reference docs. The 5-day window straddles 00:00 so facts
discovered around midnight don't fall through; dedup catches facts repeated
across sessions and facts already documented by a prior run.

## Goal

At least one merged or cleanly-proposed edit to a `references/*.md` (or
equivalent) doc, scoped strictly to facts that will still be true next month
**and not already documented**.

## Steps

### 1. Inventory recent transcripts

Compute the window floor and list candidate transcript files:

```
since=$(date -I -d '5 days ago')
fd -e jsonl --changed-within "$since 00:00:00" . ~/.claude/projects
```

Note the count. Most files will be one-prompt automated probes — that's
normal; cut them in step 3. Adjust the `5 days ago` to a different N if the
user asks for a different window.

**Success criteria**: file list scoped to the current project's encoded cwd
slug under `~/.claude/projects/`.

### 2. Distill (with window slicing)

Run the bundled filter, passing the same `$since` date as the inclusive
lower bound:

```
uv run ~/.claude/skills/distill-session-knowledge/distill.py "$since"
```

The script keeps only messages whose timestamp is `>= $since`. A session
that started before the window but continued into it contributes only its
**in-window events**; its `n_user`, `started`, and `ended` reflect the
in-window slice. Sessions with zero in-window user prompts are dropped.

Output: `/tmp/distilled/<cwd-slug>.jsonl`. Each record has
`{session, cwd, branch, started, ended, session_started, session_ended,
is_carryover, n_user, n_asst, n_user_total, user[], asst[]}` — with
`<system-reminder>`, `<command-*>`, `<task-notification>`,
`<local-command-caveat>`, and cache-keepalive ticks already stripped.

### 3. Cut to high-quality

Filter the project's file to sessions where `n_user >= 3`:

```
jq -r 'select(.n_user >= 3) | "\(.n_user)/\(.n_user_total)\t\(.is_carryover)\t\(.session)\t\(.started)..\(.ended)"' /tmp/distilled/<cwd-slug>.jsonl
```

The `n_user / n_user_total` ratio shows in-window prompts vs the whole-session
total. The `is_carryover` flag (true when the session started before the
window) tells you the engineering arc may extend earlier — useful context
for step 4 but not a reason to exclude the session.

If zero remain, tell the user "no substantive sessions in the last N days"
and stop. Do not invent material from low-quality sessions.

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

**Rule**: if a fact embeds an ephemeral path, session ID, run ID, or
"today's commit X", strip those references before considering durability.
If nothing remains after stripping, it isn't a fact.

**Within-window dedup**: with a multi-day window the same fact often
surfaces in several sessions (a discovery on day 1 gets re-confirmed on
day 3, etc.). Collapse such duplicates into one canonical candidate before
proceeding — keep the cleanest phrasing. Recurrence across sessions is a
secondary durability signal (worth noting in the routing table for the
user), but is NOT a gate: a single session is sufficient to land an ADD or
an UPDATE provided the fact survives the durability filter and (for
UPDATE) the verifiability check in step 6. Do not draft N near-identical
edits.

### 5. Discover targets, read their format, dedup against existing docs

Locate candidate target files by filename heuristic and `CLAUDE.md` layout
hints. For each candidate, **read the target file's adjacent section
before drafting**. The existing rhythm dictates the addition's shape — a
doc built around tables takes a row, a doc built around formula blocks
takes a formula block, a doc built around prose takes a paragraph. Picking
the wrong shape produces an addition that visibly doesn't belong, and the
user has to redirect.

**Cross-doc classification (three-way, not two-way)**: before drafting,
grep the candidate target (and neighbouring doc files) for the candidate
fact's discriminating terms — symbol name, error message, function/recipe
name, or numeric threshold. Pick discriminators specific enough to
distinguish the fact from neighbours; a single broad term ("filter") will
false-positive everywhere. Then read the surrounding section and classify:

| Outcome | Meaning | Action in step 6 |
|---|---|---|
| **none** | No hit on the discriminator | ADD a new entry |
| **match** | Hit, and the existing entry agrees with the candidate (same number, same conclusion, same formula) | drop — already covered |
| **contradict** | Hit on the same subject, but the existing entry's number / conclusion / formula differs from what the transcripts now say | UPDATE — see step 6 |

Silent dedup against stale docs is the worst failure mode: every distill
run reinforces the staleness by dropping the corrections. Always classify
before dropping.

### 6. Draft inline, edit, show diff

Pick the strongest 1–3 candidates and the recommended target file for each
without asking. Draft each edit in the matching format observed in step 5,
make the Edits, then show `git diff` plus a short routing table:

| File | Edit type | Section | Durability / recurrence rationale |
|---|---|---|---|

**Edit types** (from step 5's classification):

- **ADD** — new entry where there was none. Default for `none`-class
  candidates; land if the fact survives the durability filter.
- **UPDATE** — replace a stale value or claim. Required for
  `contradict`-class candidates. **Verifiability-gated, not
  recurrence-gated**: before auto-drafting, independently verify the
  contradiction against the codebase right now — `ls`/`fd` for file
  existence, `rg`/`ast-grep` for symbol or recipe definitions, a quick
  command run for fast checks. If verification confirms the doc's claim
  is no longer true, auto-draft the UPDATE; a single session is sufficient
  when the contradiction is verifiable. Surface for verify (no auto-Edit)
  only when the contradiction is about a continuous measurement (perf
  number, metric value) that can't be cheaply re-checked from the repo.

When drafting an UPDATE, prefer minimal replacement (the specific number,
phrase, or formula that changed) over rewriting the surrounding section.
Keep the heading, surrounding bullets, and "Promoted from" line untouched
unless they are themselves contradicted.

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
