---
name: preflight-check
description: Resource-aware pre-launch checklist for long-running or heavy tasks — prevents OOM, wasted compute, and daytime disruption.
allowed-tools:
  - Bash
  - Read
  - Grep
when_to_use: >
  Use BEFORE launching any long-running task via pueue, background workers, parallel jobs,
  or any computation estimated >10 minutes.
---

# Preflight Check

Pre-launch checklist to prevent OOM kills, wasted compute, and daytime disruption. Run this mentally before every heavy task.

Project-specific data tables (cost lookup, I/O dependencies) should be maintained in a file like `references/task-costs.md` in the project root. If the project has no such file, initialize one from the template at `${CLAUDE_PLUGIN_ROOT}/examples/task-costs.md`.

## Steps

### 1. Classify Task Cost

Look up the task in the project's **Cost Lookup Table** and determine its category:

| Category | Runtime | Memory/worker | Action |
|---|---|---|---|
| Light | <10 min | <2 GB | Proceed freely |
| Moderate | 10-60 min | 2-5 GB | Check server load (Step 2) |
| Heavy | >1 hr | >5 GB/worker | Full checklist (Steps 2-5) |
| Unknown | ? | ? | Probe first (Step 1a) |

For batches of N instances, compute aggregate cost:
- **Aggregate runtime** = per_instance_runtime × count / parallelism
- **Aggregate memory** = per_instance_memory × parallelism
- Any batch with aggregate runtime >1 hr or memory >10 GB is Heavy.

### 1a. Probe Unknown Tasks

When a task is not in the lookup table:

1. **Run a minimal probe** — 1-2 iterations, 1 worker, smallest input possible
2. **Measure immediately** after probe starts:
   ```bash
   ps aux --sort=-%mem | grep <keyword> | awk '{printf "PID=%s RSS=%.0fMB\n", $2, $6/1024}'
   ```
3. **Time the probe** — note wall clock for the minimal run
4. **Extrapolate** — estimate full runtime from probe
5. **Classify** — based on measured RSS and extrapolated runtime, assign Light/Moderate/Heavy
6. **Record** — add to the project's Cost Lookup Table so future runs skip probing

### 1b. Check Data Race Conflicts

Check for running tasks (e.g., `pueue status`) and compare I/O dependencies using the project's **I/O Dependency Table**:

1. **Identify what the planned task reads and writes**
2. **Check if any running task writes to files the planned task reads, or vice versa**
3. **If conflict exists → BLOCK. Schedule after the conflicting task completes**

If the task is not in the I/O table, **assume it may conflict with anything** until verified. Check the script source for file reads/writes and CLI `--help` for I/O flags, then add to the table.

### 2. Check Timing and Server Load

Run `free -m` and check task queue status to assess current state.

- **Other sessions running heavy tasks?** → Do NOT stack. Wait or schedule for later.
- **Daytime (user active)?** → Avoid heavy tasks. Prefer light/moderate only.
- **Swap usage >50%?** → Server is already under pressure. Do not add load.
- **Night/idle server?** → Safe to launch heavy tasks.

**Rule:** Heavy tasks run at night or when the server is confirmed idle. Never assume — always check.

### 3. Smoke Test First

For any sweep or optimization (hyperparameter search, grid search, parallel workers):

1. Run **1-2 trials** with the exact same code path before launching the full sweep
2. Verify the output makes sense (correct sign, reasonable magnitude, no NaN)
3. Only then launch the full run

**Why:** A bug discovered after hundreds of trials wastes hours. A couple of trials take minutes and catch sign errors, data loading issues, wrong configurations, and misconfigured objectives.

### 4. Shortcut Check

Ask: **Can I skip this step entirely and still get useful results?**

Common shortcuts:
- **Reuse existing results** instead of re-running from scratch
- **Run a single evaluation** before committing to a full sweep
- **Spot-check with 1 worker** before launching N parallel workers

The fastest path to a result is always preferred. Only run expensive steps when the cheap alternative is insufficient.

### 5. Launch with Guardrails

When launching heavy tasks:

- **Set parallelism conservatively** — start with fewer workers than the max. 2 workers is safer than 3 if memory is tight.
- **Know per-worker memory** — multiply by N workers and compare to available RAM.
- **Minimize data loading** — load only the columns/rows needed, not the entire dataset.
- **Set up monitoring** (cron or follow) for tasks >1 hour.
- **Plan for OOM restarts** — use shared state (databases, checkpoints) so killed workers don't lose all progress.

### 6. Verify Assumptions Periodically

After launching, periodically check actual resource usage against your initial estimate:

```bash
ps aux --sort=-%mem | grep <task_keyword> | awk '{printf "PID=%s RSS=%.0fMB\n", $2, $6/1024}'
free -m
```

**If reality breaks your assumption:**
- Estimated <5 min but elapsed >10 min → re-classify as moderate/heavy
- Estimated <5 GB but grew to >10 GB → investigate (e.g., data accumulation, memory leak)
- **Update the project's Cost Lookup Table** with the corrected estimate

**If a "lightweight" task turns heavy and competes with other tasks:**
1. Consider killing or pausing it
2. Re-schedule behind actual lightweight tasks
3. Re-run later when resources are free
