---
name: pueue
description: This skill should be used before running non-interactive long-running tasks, computation intensive tasks, background tasks, or needs guidance on the pueue CLI tool usage. TRIGGER when user says "use pueue", "run in background", or when about to queue any long-running (>2 min) task.
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "bash ${CLAUDE_PLUGIN_ROOT}/hooks/no-sleep-pueue.sh"
          timeout: 5
compatibility: Claude Code
---

# Pueue - Background Task Manager

## When to Use

- Non-interactive long-running tasks expected to run for >2 minutes
- Computation intensive tasks with parallel job scheduling (prevent resource exhaustion)

## When NOT to Use

- Short tasks (<2 minutes): run in Bash directly
- Interactive commands: `tmux` instead for TUI access

## Workflow

Before start, go through the pre-launch checklist as described in the `/preflight-check` skill.

Start tasks with `${CLAUDE_PLUGIN_ROOT}/scripts/run_in_pueue.sh '...'` in background (`run_in_background: true`) — do not poll after this, just stop and wait.

When task completes, you will receive `<task-notification>` from it.

### Flags

- `-p <N>` — Set max parallel tasks for this project group (prevents CPU/memory exhaustion)
- `-a <ID>` — Run after task ID completes (repeatable for multiple dependencies)

### Examples

```bash
# Basic usage
${CLAUDE_PLUGIN_ROOT}/scripts/run_in_pueue.sh 'uv run python -u train.py'

# With parallel limit (max 2 concurrent tasks)
${CLAUDE_PLUGIN_ROOT}/scripts/run_in_pueue.sh -p 2 -- 'uv run python -u train.py'

# With dependency (run after task 3)
${CLAUDE_PLUGIN_ROOT}/scripts/run_in_pueue.sh -a 3 -- 'uv run python -u evaluate.py'

# Combined
${CLAUDE_PLUGIN_ROOT}/scripts/run_in_pueue.sh -p 4 -a 3 -a 5 -- 'uv run python -u analyze.py'
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
Bash(command: "${CLAUDE_PLUGIN_ROOT}/scripts/run_in_pueue.sh 'uv run python -u train.py'", run_in_background: true)
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

## Skill Files

- `${CLAUDE_PLUGIN_ROOT}/scripts/run_in_pueue.sh` — wraps pueue add with auto daemon start, per-project grouping, and follow
- `scripts/list_pueue_tasks.sh` — list existing pueue tasks and their status
- `references/pueue.md` — comprehensive pueue CLI usage documentation
- `references/internally-multi-task-pattern.md` — pattern for when a command internally spawns pueue sub-tasks (orchestrator → workers); requires a second `pueue wait` step to get notified when workers complete
