---
name: preflight-check
description: >
  Resource-aware pre-launch checklist for long-running or heavy tasks — prevents OOM,
  wasted compute, and daytime disruption. This skill should be used before launching any
  long-running task via pueue, background workers, parallel jobs, or any computation
  estimated >10 minutes.
allowed-tools:
  - Bash(free:*)
  - Bash(df:*)
  - Bash(nproc:*)
  - Bash(nvidia-smi:*)
  - Bash(ps aux:*)
  - Bash(pueue status:*)
  - Bash(*resource_snapshot*:*)
  - Read
  - Grep
compatibility: Claude Code
---

# Preflight Check

Pre-launch checklist to prevent OOM kills, wasted compute, and daytime disruption. Run this mentally before every heavy task.

Project-specific data tables (cost lookup, I/O dependencies) should be maintained in a file like `references/task-costs.md` in the project root. If the project has no such file, initialize one from the template at `${CLAUDE_PLUGIN_ROOT}/examples/task-costs.md`.

## When to Use

- Before launching any task via `pueue add` or background shell jobs
- Before starting parallel workers, sweeps, grid searches, or hyperparameter optimization
- Before running data pipelines, ETL jobs, or batch processing on large datasets
- Before any computation estimated to take >10 minutes or use >2 GB memory
- When stacking a new task while other heavy tasks are already running
- When resuming or re-launching a previously OOM-killed task
- When running an unfamiliar script or tool for the first time at scale

## When NOT to Use

- Quick interactive commands (e.g., `git status`, `ruff check`, `uv run pytest` on a small suite)
- One-off file reads, edits, or searches that complete in seconds
- Tasks with well-known, negligible resource footprint (linting, formatting, single-file compilation)
- When the task has already been classified as Light in the project's Cost Lookup Table and no other heavy tasks are running

## Steps

### 1. Classify Task Cost

Look up the task in the project's **Cost Lookup Table** and determine its category:

| Category | Runtime | Memory/worker | Action |
|---|---|---|---|
| Light | <10 min | <2 GB | Proceed freely |
| Moderate | 10-60 min | 2-5 GB | Check server load (Step 2) |
| Heavy | >1 hr | >5 GB/worker | Full checklist (Steps 2-5) |
| Unknown | ? | ? | Probe first (Step 1a) |

**Classification rule:** If runtime and memory point to different categories, take the **higher** one. A task that runs for 2 min but uses 5 GB is Moderate (memory), not Light.

**GPU tasks:** If the task offloads to GPU (PyTorch, TensorFlow, cuDF, CUDA kernels, etc.), also classify by VRAM: <2 GB Light, 2-8 GB Moderate, >8 GB/worker Heavy. VRAM has no swap fallback — an OOM on GPU kills the process instantly with no warning.

For batches of N instances, compute aggregate cost:
- **Aggregate runtime** = per_instance_runtime × count / parallelism
- **Aggregate memory** = per_instance_memory × parallelism
- Any batch with aggregate runtime >1 hr or memory >10 GB is Heavy.

**Note:** Runtime does not always scale as 1/parallelism. I/O-bound tasks (disk, network, shared locks) suffer contention under parallel execution, reducing the speedup. Assume parallelism buys at most 50-70% of ideal speedup unless measured otherwise. Be conservative in time estimates.

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

### 2. Check Server Resource Headroom

Measure current resource usage before adding load:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/resource_snapshot.sh
```

Assess current usage and decide:

| Current CPU/Mem Usage | Action |
|---|---|
| <40% | Proceed freely |
| 40–80% | Proceed, but estimate whether the planned task would push past 80% |
| 80–90% | Caution — only add Light tasks. Wait for running tasks to finish before launching Moderate/Heavy |
| >90% | Block — wait for the rush to pass, or suggest scheduling for later |

**Decision rule:** Estimate post-launch usage = current usage + planned task's cost (from the Cost Lookup Table). If that sum would push CPU or memory into a higher threshold band, do not launch — wait or reduce parallelism.

**Be conservative on cost estimates.** Tasks often use more resources than expected, especially under load. For unknown tasks (not yet documented in the Cost Lookup Table), assume worst-case memory and treat as Heavy until measured via Step 1a. It is far cheaper to wait unnecessarily than to OOM-kill a multi-hour job.

- **Swap usage >50%?** → Server is already under memory pressure. Do not add load regardless of the threshold table above.

**If the task uses GPU**, also check GPU headroom:
```bash
nvidia-smi --query-gpu=index,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits
```
Apply the same threshold logic: if GPU utilization >80% or free VRAM cannot fit the task's estimated VRAM, do not launch.

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
- **Know per-worker memory** — multiply by N workers and compare to available RAM (and VRAM for GPU tasks).
- **Minimize data loading** — load only the columns/rows needed, not the entire dataset.
- **Set up monitoring** (cron or follow) for tasks >1 hour.
- **Plan for OOM restarts** — use shared state (databases, checkpoints) so killed workers don't lose all progress. If a task is OOM-killed, follow `${CLAUDE_PLUGIN_ROOT}/references/post-oom-triage.md` before retrying.

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
