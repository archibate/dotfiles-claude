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

If babysit daemon not started:
```bash
babysit daemon-start
# equivalant to:
babysit daemon-start --max_sys_mem_pct=70 --max_sys_disk_pct=90 --max_sys_cpu_pct=90 --monitor_interval="10s" --monitor_tolerance_count=3 --monitor_disk_infer_by_dir="$HOME"
```

> `babysit` monitors resource usage via psutil and kills violating processes. All spawned task processes run at lower priority (`nice +10`) so that the monitor thread stays responsive.

To show current tasks:
```bash
babysit list
# equivalant to:
babysit list --columns="name,pid,status,command,elapsed_time,estimated_time,kill_timeout,observability_interval,last_observed_log,time_since_last_observe,cpu_cores,cpu_pct,mem_bytes,mem_pct,disk_write_bytes,disk_read_bytes,num_procs,num_threads,claude_session_id" --format=json
```

> `status` can be: pending, running, completed, failed, manual_killed, timeout_killed

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

`wait` blocks until terminal status. stdout: single terminal-status JSON object. stderr: zero-or-more event JSON lines, currently `{"event":"runaway_risk", ...}` emitted once when `elapsed_time` first exceeds `estimated_time`. Combine with `run_in_background=true` + `Monitor` to subscribe — the harness merges both streams.

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


Use `babysit --help` or `babysit <subcommand> --help` for help.
