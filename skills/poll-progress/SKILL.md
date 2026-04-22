---
name: poll-progress
description: >
  Poll a running background task (pueue or Bash run_in_background) at cache-safe
  cadence and report one-line progress per tick, with a structured findings
  report on completion. Use when the user says "poll the task", "monitor the
  task", "report when done", "wake me when it finishes", or after launching a
  long-running background task the user wants status updates on.
allowed-tools:
  - Bash(pueue:*)
  - Bash(date:*)
  - Bash(grep:*)
  - Bash(cut:*)
  - Read
  - Grep
  - ScheduleWakeup
compatibility: Claude Code
disable-model-invocation: true
---

# Poll Progress

Watch a running background task, report one-line progress each tick at a
cache-safe cadence, and emit a structured findings report on completion.
Companion to `cache-hygiene` — this skill handles the reporting side; that skill
handles the cache TTL math.

## Goal

User sees:
- Concise progress updates (one line per tick)
- Accurate ETA that refines as pace data accumulates
- Immediate structured report when the task ends

No cache miss between ticks. No blocking calls that bust the TTL.

## Steps

> In the command snippets below, `<id>`, `<bash-output-file>`, and `<regexN>`
> are placeholders — substitute the actual task id and markers before running.
> Pasting the literal `<id>` regex will match nothing.

### 1. Identify target task

Ask the user for the task id/label if not already given. Determine backend:

- **pueue**: user gave an id (e.g. "1901") or label ("exp_130_ablation"). Verify:
  `pueue status | grep -E "^ <id>"`.
- **Bash run_in_background**: user gave a shell id from a prior `Bash` call.
  Poll via `Read` on the captured output file.

### 2. Extract progress-marker regexes (once, up front)

Tail the log and pick 2–3 regexes that match the task's repeating progress
lines. Do this once. Reuse every tick.

```bash
pueue log <id> --lines 50   # or Read <bash-output-file>
```

Examples of stable markers:
- `Processed N/M` — iteration counter
- `loss=\d+\.\d+` — training metric
- `IC:|ICIR:` — validation output
- `PASS|FAIL|Success|Failed` — terminal verdicts

### 3. Per tick: poll + one-line report

One command, one line of output. Never block.

```bash
date '+%H:%M'; \
pueue status | grep -E "^ <id>" | cut -c1-80; \
pueue log <id> --lines 5 | grep -E "<regex1>|<regex2>|<regex3>" | tail -3
```

Report schema:
```
**HH:MM:** progress (pct%), key_metric. ETA ≈ HH:MM.
```

### 4. Schedule next tick OR stop

Call `ScheduleWakeup(delaySeconds=270, prompt="Continue poll-progress for task <id>.")`
(substitute the actual task id so parallel loops stay distinguishable).

Stop (omit ScheduleWakeup) when any of:
- Task status is `Success`, `Failed`, `Killed`
- User cancels

### 5. On completion: findings report

Grep the full log for terminal markers + warnings + errors. Report:

1. **Verdict**: Success / Failed / \<reason\>
2. **Key numeric results**: extract via the same regexes
3. **Warnings / errors**: surface verbatim (`WARNING`, `ERROR`, `Traceback`)
4. (Optional) recommended next steps if the result warrants action

## Gotchas

- **Cap blocking at 4 min**. No `pueue wait`, no `pueue follow`, no `tail -f`,
  no `TaskOutput`/`Monitor` with timeout >4 min. Per `cache-hygiene`, any
  single tool call longer than 4 min risks busting the 5-min TTL. Always
  poll-and-schedule.
- **Use `cut -c1-N` over `awk`** for column extraction. Awk quoting inside Bash
  tool descriptions is fragile.

## Relationship to cache-hygiene

`cache-hygiene` defines the 270s cadence and TTL math. `poll-progress` inherits
that cadence and adds:
- Concrete poll commands for pueue / Bash-bg
- Progress-regex extraction pattern
- One-line report schema
- Structured completion report

When both apply (user launches a heavy task and wants progress), run
poll-progress — it covers cache warming as a side effect.
