# Background Task Babysitting Rule

Every background running task must satisfies:

1. never consuming >40% system memory (recursively into child-process) -> optimize memory footprint
2. output at least one line of log every 5 minutes -> add observability logs
3. never consume >90% of CPU cores -> limit parallel number
4. elapsed more than 2x of prior estimated time -> suspect if task stuck

Kill immediately when one of above are violated, and follow the mitigation after `->`.

> Observability logs prevents blind of progress (look like stuck). The user care about progress and ETA, add metrics when appliable. Include progress tick like `[3/42]`, `ETA ~3m`, `loss=1e-4` in log entries. This helps diagnose issues mid-flight when a task is stuck or flaw. So that you can fix and restart flaw tasks immediately without having to wait for infinity for a stuck task before fixing. Avoid generic meanless `Keep-alive` prints against the intent of observability rule.


Keep monitoring system resource exhaustion risk:

1. system memory usage exceeds >70% -> kill top-memory task -> reduce memory footprint, avoid running multiple memory-consuming tasks in parallel
2. system disk usage exceeds >90% -> kill any disk writing task -> reduce disk footprint, wait for user to clean up space
3. system CPU usage exceeds >90% -> kill top-CPU task -> reduce parallelism, left at least 1~2 CPU cores for user

Follow mitigation on violation for more than 30 consecutive seconds. Restart task after system usage dropped.

> System exhaust will cause constant ssh login failure, making user unable to use the computer. Memory runaway is the biggest sin, it make ssh process imposdible to spawn, and user will find their ssh stuck, unable to make any futher instructions to assistant. Optimize program memory footprint before re-run.


These rules can be enforced by running with the wrapper:
```bash
babysit run --name="some-heavy-task" --command="uv run python -u some_heavy_task.py" --estimated_time="10m"
# equivalant to:
babysit run --name="some-heavy-task" --command="uv run python -u some_heavy_task.py" --estimated_time="10m" --mem_pct_limit=40 --cpu_pct_limit=90 --kill_timeout="20m" --observability_interval="5m"
```

The `babysit run` is non-blocking, push into queue. Once started

> `-u` or `PYTHONUNBUFFERED=1` avoids python buffering stdout which can break observability rule.

Optionally declare peak-resource estimates so the daemon can (a) warn you mid-flight when actual exceeds your prediction and (b) treat your task fairly under system pressure:
```bash
babysit run --name="train-mlp" --command="uv run python -u train.py" --estimated_time="30m" --estimated_mem_bytes="4G" --estimated_cpu_cores=8
```

> `--estimated_mem_bytes` accepts `4G`, `512M`, `1.5T`, raw bytes (default `4G`). `--estimated_cpu_cores` is a float (default `4`). Override explicitly for heavy ML training, big-data scans, or single-threaded scripts — the defaults are tuned for a typical 10m task. Values exceeding host total RAM / cores are rejected at `babysit run` time.
>
> `--cwd` (existing absolute path; default current shell cwd) is the task's working directory, shown as `PROJECT` in `babysit list` / `tui`.
>
> Soft warn at 1× (a `{"event":"runaway_risk","dim":"mem|cpu", ...}` line on `babysit wait` stderr — sanity-check on the fly). Hard kill at 2× sustained for the monitor tolerance window (default 30s) with `kill_reason="estimated_mem_exceeded"` / `"estimated_cpu_exceeded"`.
>
> Under system pressure (memory/CPU), the daemon picks the kill victim by tier: (1) tasks exceeding their declared estimate first, (2) tasks with no declared estimate, (3) tasks within their estimate last. This protects sunk progress of well-behaved long-running tasks against runaway newcomers. The killed task's spawning agent reads `kill_reason="system_{mem,cpu}_pressure"` and should wait for system load to drop before retrying (use `babysit wait_for_capacity`).
>
> Soft-deny on queue: `babysit run` checks `current_sys_used + sum_of_pending_estimates + 2 × your_estimate ≤ max_sys_{mem,cpu}_pct × total` before accepting. On deny, exits 2 with a `{"error":"capacity_exceeded","dim":"mem|cpu","projected_*","limit_*","hint","suggested_command":"babysit wait_for_capacity --mem_bytes=… --cpu_cores=…"}` JSON line on stderr. `babysit wait_for_capacity` runs the same check on a poll loop, emitting `{"event":"waiting_for_capacity","phase":"pressured|debounce", ...}` on stderr per poll. It only exits 0 after the gate stays open for a **random sustained window** in `[--debounce_min, --debounce_max]` (default 1–3 min) — desynchronizes concurrent waiters so they don't all race to `babysit run` the moment capacity opens; any pressure tick during the window resets it. Pass `--force` on `babysit run` to skip the gate entirely.

If babysit daemon not started:
```bash
babysit daemon-start
# equivalant to:
babysit daemon-start --max_sys_mem_pct=70 --max_sys_disk_pct=90 --max_sys_cpu_pct=90 --monitor_interval="10s" --monitor_tolerance_count=3 --monitor_disk_infer_by_dir="$HOME"
```

> `babysit` monitors resource usage via psutil and kills violating processes. All spawned task processes run at lower priority (`nice +10`) so that the monitor thread stays responsive.

To show current tasks:
```bash
babysit list                              # default: running/pending + terminal ended within 24h
babysit list --since=7d                   # broaden the terminal window
babysit list --all                        # full history (every row)
# default expands to:
babysit list --columns="name,pid,status,kill_reason,kill_hint,exit_code,command,elapsed_time,estimated_time,kill_timeout,observability_interval,last_observed_log,time_since_last_observe,cpu_cores,cpu_pct,estimated_cpu_cores,mem_bytes,mem_pct,estimated_mem_bytes,disk_write_bytes,disk_read_bytes,num_procs,num_threads,cwd,claude_session_id" --format=json --since=24h
```

> `status` can be: pending, running, completed, failed, killed, unknown
>
> Terminal statuses are `completed` / `failed` / `killed` / `unknown`. For `killed`, `kill_reason` names the trigger (e.g. `manual`, `mem_exceeded`, `cpu_exceeded`, `estimated_mem_exceeded`, `estimated_cpu_exceeded`, `cgroup_oom_killed`, `elapsed_exceeded`, `observability_stall`, `system_cpu_pressure`/`system_mem_pressure`/`system_disk_pressure`, `daemon_shutdown`) and `kill_hint` gives a one-line remediation. A plain `failed` exit (process returned non-zero on its own) has `kill_reason=null` — check `exit_code` instead. `failed`/`unknown` from daemon-restart or spawn corner cases do carry a `kill_reason` (e.g. `process_vanished`, `adopted_exited`, `daemon_restart_dead`, `spawn_error: …`).
>
> The cgroup envelope for memory is sized at `min(3 × --estimated_mem_bytes, --mem_pct_limit × total_ram)` (similar for CPU vs `os.cpu_count()`). An explosive allocation that outpaces the daemon's 30s soft-watch hits the kernel OOM boundary at 3× the declared estimate and is reported as `kill_reason="cgroup_oom_killed"` (distinct from the graceful `estimated_mem_exceeded`).

To peek a task progress:

```bash
babysit status --name="<task name>"
# equivalant to:
babysit status --name="<task name>" --columns="..." --format=json
```

To wait until a task complete:

```bash
babysit wait --name="<task name>"
# equivalant to:
babysit wait --name="<task name>" --columns="..." --format=json
```

`wait` blocks until terminal status. stdout: single terminal-status JSON object. stderr: zero-or-more event JSON lines — `{"event":"runaway_risk","dim":"elapsed|mem|cpu", ...}` emitted once per dim when actual first exceeds the declared estimate. Combine with `run_in_background=true` + `Monitor` to subscribe — the harness merges both streams.

To peek log:

```bash
babysit log --tail=15 --name="<task name>"
babysit log --head=15 --name="<task name>"
babysit log --full --name="<task name>" | rg ...
```

To subscribe for log update, run with `run_in_background=true` + `Monitor`:

```bash
babysit log --follow --name="<task name>"
```

you will be notified on log update.


For humans only (do not invoke from an agent), there is a `babysit tui` dashboard built on `textual` that renders the task list with live progress, sortable resource columns, log peek, and confirm-to-kill. Agent-facing subcommands above remain the API surface.


To purge stale finished tasks and their logs:

```bash
babysit clean                                        # default: purge terminal rows older than 24h + their log files
babysit clean --older_than=0s                        # purge all terminal rows immediately
babysit clean --status=killed,failed --dry_run       # preview without deleting
```

> The daemon also auto-purges terminal rows past `--cleanup_ttl` (default `7d`) once per minute on its tick loop, unlinking the corresponding `log_path` file. Override with `babysit daemon-start --cleanup_ttl=30d` etc.


Use `babysit --help` or `babysit <subcommand> --help` for help.
