---
name: pueue
description: >
  Guardrails and mandatory workflow for running long-running tasks via pueue.
  This skill MUST be used before using pueue to run any long-running task (>2 min),
  computation-intensive task, or background task — or when the user says
  "use pueue" or "run in background". This is a process gate, not a reference doc.
allowed-tools:
  - Bash(pueue:*)
  - Bash(*run_in_pueue*:*)
  - Bash(*list_pueue*:*)
  - Read
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: bash ~/.claude/skills/pueue/hooks/no-sleep-pueue.sh
          timeout: 5
compatibility: Claude Code
---

# Pueue - Background Task Manager

## When to Use

- Non-interactive long-running tasks expected to run for >2 minutes
- Computation intensive tasks with parallel job scheduling: pueue smart scheduler and resource limitation prevent resource exhaustion
- Jobs requires persistence: pueue daemonized in background, persist even after claude exists

## When NOT to Use

- Short tasks (<2 minutes): run in Bash directly
- Interactive commands: `tmux` instead for TUI access
- IO-bound tasks: pueue scheduler not helpful
- Jobs okay to exit by claude exit: use built-in `run_in_background` instead

## Workflow

Before start, go through the pre-launch checklist as described in the `/preflight-check` skill.

Start tasks with `scripts/run_in_pueue.sh '...'` in background (`run_in_background: true`) — do not poll after this, just stop and wait.

When task completes, you will receive `<task-notification>` from it.

### Flags

- `-p <N>` — Set max parallel tasks for this project group (prevents CPU/memory exhaustion)
- `-a <ID>` — Run after task ID completes (repeatable for multiple dependencies)

### Examples

```bash
# Basic usage
scripts/run_in_pueue.sh 'uv run python -u train.py'

# With parallel limit (max 2 concurrent tasks)
scripts/run_in_pueue.sh -p 2 -- 'uv run python -u train.py'

# With dependency (run after task 3)
scripts/run_in_pueue.sh -a 3 -- 'uv run python -u evaluate.py'

# Combined
scripts/run_in_pueue.sh -p 4 -a 3 -a 5 -- 'uv run python -u analyze.py'
```

### How It Works

The wrapper script orchestrates task execution through the following steps:

1. **Group Creation** — `pueue group add` creates a project-specific group if it doesn't exist, enabling isolated task management per project

2. **Task Queuing** — `pueue add` enqueues your command into the project group's queue, returning a task ID

3. **Completion Tracking** — `pueue follow [task_id]` subscribes to the task's output stream and blocks until completion, triggering the `<task-notification>` on finish

### Bypassing the Wrapper Script

If you use `pueue add` directly instead of the wrapper script, you **must** start `pueue follow` or `pueue wait` in the background to receive completion notifications. Without this, you will miss the `<task-notification>` when the task finishes.

**Do not poll** (`pueue status` in a loop). The background notification approach is more efficient and non-blocking.

## Conversation Example

User:
Start training in the background.

Assistant:
```
Bash(command: "scripts/run_in_pueue.sh 'uv run python -u train.py'", run_in_background: true)
```
I've started training in background, will notify you once complete.
[STOP AND WAIT]

[~10 minutes passed]

System:
<task-notification>Background command "..." completed (exit code 0)</task-notification>

Assistant:
[analyze the log and training metrics]
Training complete, here are the metrics:
...

## Pitfalls

### `pueue status` showing Success does NOT guarantee the task succeeded

Some task runners (e.g., `just`) do not propagate subprocess exit codes. A `just` recipe whose inner command fails with exit 1 may still exit 0 itself, causing pueue to report `Success`.

**Always verify task completion by checking actual outputs**, not just pueue status:
- Check `pueue log <id>` for error messages in stdout/stderr
- Verify expected output files exist (e.g., `ls dataset/raw/*/feature.csv`)
- For batch tasks, spot-check a few results rather than trusting the status of all

### Never use `run_in_pueue.sh` for pueue management commands

`run_in_pueue.sh` is for **work commands** only (python scripts, builds, etc.). Never use it to run pueue's own commands (`pueue wait`, `pueue follow`, `pueue status`, etc.).

The wrapper script adds tasks to the project group and then runs `pueue follow` internally. If you submit `pueue wait <id>` via the wrapper, the wait task occupies a group slot while blocking on the target task — if the group has limited parallelism, this deadlocks (the wait task holds the slot, the target task can never start).

To wait for or follow a task, use Bash directly:
```
Bash(command: "pueue follow <id>", run_in_background: true)
```

### Never `pueue add -- bash -c 'VAR=1 cmd'`

Pueue parses the command as a list of tokens. `bash -c 'VAR=1 cmd'` silently fails — pueue passes `VAR=1` as the command name. Use a single quoted string instead:

```bash
pueue add -- 'VAR=1 cmd'
```

### `pueue status` panics on EPIPE (4.0.4)

pueue 4.0.4 does not handle broken-pipe gracefully. Piping its output into an
early-closing consumer (`head`, `grep -m N`, `sed -n 1,Np`) prints a Rust panic
traceback to stderr, polluting the agent context. Read-to-EOF consumers
(`grep`, `cut`, `tail`, `sort`, `wc`) are safe.

### Displayed status ≠ filterable status

`pueue status --help` lists filterable values as `queued|stashed|paused|running|success|failed`,
but the status column can also render `Killed` (after `pueue kill`). When
writing status matchers, treat terminal states as `Success|Failed|Killed`.

### `pueue clean` removes finished task logs

`pueue clean` (or automatic cleanup) permanently removes logs of completed tasks. If you need to verify results later, check output files or save logs before cleaning.

## Skill Files

- `scripts/run_in_pueue.sh` — wraps pueue add with auto daemon start, per-project grouping, and follow
- `scripts/list_pueue_tasks.sh` — list existing pueue tasks and their status
- `references/pueue.md` — comprehensive pueue CLI usage documentation
- `references/internally-multi-task-pattern.md` — pattern for when a command internally spawns pueue sub-tasks (orchestrator → workers); requires a second `pueue wait` step to get notified when workers complete
