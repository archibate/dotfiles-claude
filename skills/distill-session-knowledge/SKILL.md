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
  - Bash(uv run *scripts/distill.py:*)
  - Bash(rg:*)
  - Bash(wc:*)
  - Bash(date:*)
  - Bash(mkdir:*)
  - Bash(cat:*)
  - Bash(git diff:*)
  - Bash(git status:*)
  - Read
  - Edit
  - Write
  - AskUserQuestion
---

# Distill Session Knowledge

Scan the last 5 days of substantive Claude conversations in the current
project and land durable facts (pitfalls, costs, calibrated results) into
the project's reference docs. The 5-day window straddles 00:00 so facts
discovered around midnight don't fall through; dedup catches facts repeated
across sessions and facts already documented by a prior run.

## Goal

At least one merged or cleanly-proposed edit to one of the project's
existing reference docs (whatever convention this project uses —
discovered in step 4, not assumed), scoped strictly to facts that will
still be true next month **and not already documented**.

## Steps

### 1. Inventory recent transcripts

**Read the project's distill state first** — use the Read tool on
`.claude/state/distill.json` so the full state (both `last_distilled_at`
and `convention`) lands in context. Step 4 reuses the `convention` field
without re-reading. If the file doesn't exist, this is a first run.

Then compute the window floor and list candidates. Pick **one** value
for `$FLOOR` based on the state Read above, then substitute it into a
single bash run:

- `$FLOOR = '<last_distilled_at> -5 hours'` when state exists (5h
  overlap tolerance — `date -d` accepts the arithmetic inline).
- `$FLOOR = '5 days ago'` on first run.

```
since=$(date -I -d "$FLOOR")
fd -e jsonl --changed-within "$since 00:00:00" . ~/.claude/projects
```

The 5h backstep guards against context loss when transcripts straddle the
previous run's exit; step 5's dedup catches the resulting overlap. If the
user explicitly asks for a different window ("distill last week"), set
`since` directly and skip the state read.

Note the count. Most files will be one-prompt automated probes — that's
normal; cut them in step 3.

**Success criteria**: file list scoped to the current project's encoded cwd
slug under `~/.claude/projects/`.

### 2. Distill (with window slicing)

Run the bundled filter, passing the same `$since` date as the inclusive
lower bound:

```
uv run scripts/distill.py "$since"
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

### 4. Inventory project docs, then categorize

Before reading transcripts, **discover what reference-doc shape this
project actually has**. Read `CLAUDE.md` for layout hints, then list
whichever of `references/`, `docs/`, `notes/`, `specs/` exist at the
project root. For each doc found, read just the heading + intro paragraph
(not the whole file) and note its role in one phrase. The result is a
project-specific routing table — the categories the project already uses
to organize durable knowledge:

| Doc | Role (paraphrased from heading/intro) |
|---|---|
| (e.g.) `references/pitfalls.md` | tool / syntax gotchas |
| (e.g.) `references/task-costs.md` | measured runtime/memory/I/O |
| (e.g.) `specs/feature-X.md` | calibrated outcomes for feature X |

**Bootstrap branch — empty project**: if zero reference docs exist
anywhere AND `.claude/state/distill.json` has no `convention` field,
pause and ask **one** AskUserQuestion before drafting: "no reference-doc
convention yet — where should durable facts live?" Offer 2–3 concrete
options (e.g. `references/*.md` per-role files, a single `NOTES.md`,
"don't write durable docs"). Step 7 persists the answer into the state
file's `convention` field; later runs read it back without asking. This
is the rare coin-flip case where pre-asking is correct: the answer
changes the file path itself, not just wording. **Do not fabricate a
tree without asking.**

Now for each surviving session, pull `user[]` and `asst[]`. Read prompts
for intent; scan assistant first-lines for the engineering arc. For each
candidate fact, ask: **which row of the routing table does this serve?**

- **Matches a role** → candidate, with that doc as the draft target.
- **Matches no role** → set aside. Don't manufacture a new doc just to
  land the fact; surface these as "facts with no obvious home" at the end
  and let the user decide whether to create a new doc.
- **Pattern / preference / one-off** (workflow tendencies, terse-style
  notes, "fix this", "rename that") → skip; those belong in
  skills/hooks/CLAUDE.md, not reference docs.

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

### 5. Read target format, dedup against existing docs

Each surviving candidate already has a draft target from step 4. For each,
**read the target file's adjacent section before drafting**. The existing
rhythm dictates the addition's shape — a
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

Pick the strongest 1–3 candidates. Two sources feed this:

- **Routed candidates** (step 4 matched a routing-table role; step 5
  classified as `none` or `contradict`) — draft against the existing doc.
- **Orphan groups** (set aside in step 4 with no matching role) — if ≥2
  share a missing role, treat the group as one **CREATE** candidate.
  Single orphans don't qualify; surface them in step 7 as an open
  question.

Draft each edit in the matching format observed in step 5, make the
Edits, then show `git diff` plus a short routing table:

| File | Edit type | Section | Durability / recurrence rationale |
|---|---|---|---|

**Edit types**:

- **ADD** — new entry in an existing doc. Default for `none`-class
  candidates from step 5; land if the fact survives the durability filter.
- **UPDATE** — replace a stale value or claim in an existing doc. Required
  for `contradict`-class candidates. **Verifiability-gated, not
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

- **CREATE** — propose a new reference doc when ≥2 orphans share a
  missing role. Use the convention recorded in
  `.claude/state/distill.json` (path + format) — or, on bootstrap, the
  path the user just chose in step 4. Seed the new doc with the
  triggering orphans in the shape later runs should extend (table-of-
  rows, bulleted entries, etc.), not free-form prose. Do not create a
  doc to land a single fact; the per-doc bitrot cost is too high.

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

### 7. Audit, persist state, finalize

After Edits, the project's Stop hook runs `audit-edits.py` automatically.
For each FIXES entry: judge whether it's a true issue (DOC-contradiction,
incident-leak, scope creep) or a false positive; apply or dismiss explicitly.

Persist state for the next run — read-modify-write so any pre-existing
`convention` field survives untouched:

```
mkdir -p .claude/state
{ cat .claude/state/distill.json 2>/dev/null || echo '{}'; } \
  | jq --arg ts "$(date -Iseconds)" '.last_distilled_at = $ts' \
  > .claude/state/distill.json.tmp \
  && mv .claude/state/distill.json.tmp .claude/state/distill.json
```

If step 4 hit the bootstrap branch, also merge the user's answer into
`.convention` (keys: `path`, `format`) in the same write so subsequent
runs read it back rather than re-asking. Surface the final `git diff`
plus any single-orphan facts ("no obvious home for: X, Y") as a closing
question. Do not commit unless asked.

## Rules

- **No fabrication** — every fact must trace back to actual prompt or
  assistant output in the transcript. If you can't quote it, drop it.
- **Preferences are not facts** — terse confirmation style, codex habits,
  etc. live in CLAUDE.md or hooks, not distilled docs.
- **One bad edit > zero edits is the wrong tradeoff here.** Skipping a
  borderline fact is always correct; landing a wrong one pollutes the
  reference doc.
