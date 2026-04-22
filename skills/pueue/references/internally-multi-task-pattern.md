# Internally Multi-Task Pattern

## Problem

When a command spawns its own pueue sub-tasks internally (e.g. a Python script that calls `pueue add` via subprocess), `run_in_pueue.sh` only follows the **orchestrator** task, which exits in seconds. The actual worker tasks run unmonitored — no `<task-notification>` arrives when they finish.

## Solution

After the orchestrator's `<task-notification>` arrives, immediately start a background `pueue wait` on the worker group:

```
Bash(command: "pueue wait --group <group-name>", run_in_background: true)
```

This produces a second `<task-notification>` when **all workers** in the group complete.

## Full Example

Step 1 — Run orchestrator in background:
```
Bash(command: "scripts/run_in_pueue.sh 'uv run python -u src/optimize_backtest.py optimize --n-jobs 4'", run_in_background: true)
```

Step 2 — Orchestrator completes (spawns workers, exits). Notification arrives:
```
<task-notification>... completed (exit code 0)</task-notification>
```

Read orchestrator output to get the group name (printed by the script), then immediately:
```
Bash(command: "pueue wait --group home-alice-myproj", run_in_background: true)
```

Step 3 — Workers finish. Second notification arrives:
```
<task-notification>... completed</task-notification>
```

Now check progress, read logs, run the report.

## How to Get the Group Name

The group name is derived from the working directory:
```python
group = str(Path.cwd())[1:].replace("/", "-")
# /home/alice/myproj → home-alice-myproj
```

Or read it from the orchestrator output, which always prints:
```
Pueue group: home-alice-myproj  parallel=4
```
