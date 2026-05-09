---
name: forkpick
description: Spawn 2-4 parallel forks answering the same question, then judge and pick the best. User-invoked via /forkpick only.
compatibility: Claude Code
disable-model-invocation: true
user-invocable: true
---

# /forkpick

Generate-and-judge: spawn N parallel forks of yourself on the same prompt, then pick the best response.

Forks share the prompt cache (cheap) and inherit full context, so this is a low-cost way to draw N independent samples for tasks where divergence is the value.

## Args

`/forkpick [N=3] [rubric:...] <question>`

- `N` — optional integer, clamp to [2, 4]. Default 3.
- `rubric:` — optional inline rubric, ends at first blank line. Used to score replies. Default rubric: correctness > specificity > brevity.
- `<question>` — the rest of the input, sent verbatim to every fork.

If `<question>` is empty, ask the user for it instead of dispatching.

## Triage — when NOT to fork

Refuse with one line and stop if the question is:

- A deterministic lookup (single file path, single fact, single regex) — one fork is enough.
- A trivial yes/no the model already knows.
- Anything that fits `[verified: ...]` from a single tool call.

Refusal line: `forkpick is for divergent answers — one direct answer suffices here.`

Fork only when there's a real best-of-N judgment call: design choices, prose drafting, code style, naming, tradeoff analysis, open-ended planning.

## Protocol

### 1. Dispatch

In a **single message**, emit N `Agent` tool calls. Forks (omit `subagent_type`) so they inherit context and share the prompt cache.

- Identical prompts across forks. Do NOT pre-bias with "be creative", "try a different angle", etc — that's `/fresh-arch`, not forkpick.
- Each fork prompt should explicitly tell it to answer self-contained (no follow-up Qs) and end with the answer.
- Name the forks `fork-1` … `fork-N` for traceable output files.

### 2. Wait

After dispatch, end the turn or do unrelated work. **Do NOT Read the `output_file` paths mid-flight** — that pulls each fork's tool noise into your context and defeats the whole point. The runtime delivers a `<task-notification>` when each completes.

If asked about results before all forks land: report status, do not fabricate.

### 3. Judge

Once all N return, score against the rubric. One line per fork:

```
| Fork | Score | One-line rationale |
|---|---|---|
| 1 | 8/10 | concrete, cites file:line |
| 2 | 6/10 | hedges, no citations |
| 3 | 7/10 | tight but missed edge case |
```

Pick the winner. Mark verdict explicitly: `Winner: fork-N [opinion]`.

If two are within 1 point, surface both with a one-line "either works, differ on X" note rather than forcing a pick.

### 4. Output

Single response:

1. Scoreboard table (above).
2. Winner verdict line with `[opinion]` marker.
3. Winner's full reply, verbatim.
4. Optional: one-line note on what each loser missed (only if the user asked or if a loser surfaced a unique point worth keeping).

Do not paste full loser content unless the user asks.

## Anti-patterns

- Forking a fact lookup. One Agent call, or zero, is right.
- Reading `output_file` mid-flight to "check progress".
- Varying the prompt across forks. Use `/fresh-arch` for deliberate diversity.
- Skipping the verdict — "all three were good" is not a pick.
- Re-running `/forkpick` on its own output to "best-of-best". Diminishing returns past N=4.

## Sketch

```
Agent({ name: "fork-1", description: "forkpick sample", prompt: "<question>" })
Agent({ name: "fork-2", description: "forkpick sample", prompt: "<question>" })
Agent({ name: "fork-3", description: "forkpick sample", prompt: "<question>" })
```

All three in one message. Wait for notifications. Score. Pick.
