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

!`[ "${CLAUDE_CODE_FORK_SUBAGENT:-0}" = "1" ] || echo "**⚠️ Prerequisite — STOP before dispatching:** CLAUDE_CODE_FORK_SUBAGENT is not set to 1. Agent forks (omitting subagent_type) won't inherit context — they spawn as fresh subagents, defeating /forkpick. Set CLAUDE_CODE_FORK_SUBAGENT=1 in your settings.json env block, then restart Claude Code (env block doesn't hot-reload) before dispatching."`

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

## Mutable tasks (worktree isolation)

If the request asks forks to edit files (create/fix/refactor/implement/edit/add), each fork must run in its own git worktree — otherwise concurrent `Edit`/`Write` calls clobber each other and reads see torn state.

**Worktree base mode (live):** !`jq -r '"Mode: " + (.worktree.baseRef // "fresh (default)") + (if (.worktree.baseRef // "fresh") == "head" then " — Agent worktrees branch from local HEAD, so forks inherit unpushed commits on this branch (uncommitted/staged edits still invisible, commit first)." else " — worktrees branch from the local origin/<default> remote-tracking ref, which can be stale until you git fetch; forks see only commits already on that ref. Easiest fix: set worktree.baseRef to head in ~/.claude/settings.json so forks branch from your current HEAD." end)' ~/.claude/settings.json`

- Pass `isolation: "worktree"` on every `Agent` call. Each fork gets its own path + branch (`cwd` inside the fork is the worktree path); the harness auto-cleans worktrees that produced no changes and returns `path` + `branch` for the rest. Auto-cleanup only applies to interactive runs — non-interactive (`claude -p ...`) leaves worktrees behind.
- Tell each fork to leave the change committed on its branch and end with a one-paragraph summary — judging works off diffs, not chat.
- Judge from the parent by comparing **diffs** (`git -C <path> diff <base>` or `git log <base>..<branch>`) plus the summary, not just reply text.
- After picking the winner, cherry-pick or merge the winner's branch into the user's working tree as a separate step. Confirm before landing if DoA is low. Leave loser worktrees alone — they self-clean or stay for inspection.
- Refuse fan-out when forks would race on shared external state (DB writes, network calls, deploys, package publishes) — worktrees isolate the filesystem only.
- A fork **cannot spawn further forks**, so if your `/forkpick` invocation is itself running inside a fork (e.g. nested via another skill), the inner forks will fail — flag and stop instead of dispatching.

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
- Mutable forks without `isolation: "worktree"` — concurrent `Edit`/`Write` calls clobber.
- Mutable forks for tasks that mutate shared external state (DB rows, network endpoints, deploys, package registries) — worktrees do not isolate those.

## Sketch

Read-only (questions, design comparisons, prose):
```
Agent({ name: "fork-1", description: "forkpick sample", prompt: "<question>" })
Agent({ name: "fork-2", description: "forkpick sample", prompt: "<question>" })
Agent({ name: "fork-3", description: "forkpick sample", prompt: "<question>" })
```

Mutable (file edits — add `isolation: "worktree"` to every fork):
```
Agent({ name: "fork-1", description: "forkpick sample", prompt: "<question>", isolation: "worktree" })
Agent({ name: "fork-2", description: "forkpick sample", prompt: "<question>", isolation: "worktree" })
Agent({ name: "fork-3", description: "forkpick sample", prompt: "<question>", isolation: "worktree" })
```

All N in one message. Wait for notifications. Score. Pick. For mutable forks, cherry-pick or merge the winner's branch as a separate landing step.
