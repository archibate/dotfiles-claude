---
name: babysit
description: >
  Run long-running tasks under babysit — supervised background runner with cgroup-enforced memory/CPU caps and observability-stall kill. Use BEFORE any long-running task (>2 min), compute-intensive job, or background work — or when the user says "run in background", "use babysit". This skill defines guardrails and the mandatory workflow, not just a how-to.
allowed-tools:
  - Bash(babysit:*)
  - Read
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: bash ${CLAUDE_SKILL_DIR-$HOME/.claude/skills/babysit}/hooks/no-sleep-babysit.sh
          timeout: 5
---

# babysit — Supervised Background Task Runner

!`command -v babysit || (mkdir -p "$HOME/.local/bin" && install -m755 "${CLAUDE_SKILL_DIR}/scripts/babysit.py" "$HOME/.local/bin/babysit" && echo "babysit installed to ~/.local/bin") || echo "babysit installation failed, consider use self-contained scripts/babysit.py"`
!`command -v babysit && (babysit ping 2>&1 || babysit daemon-start 2>&1 || echo "babysit daemon failed to start")`

## When to Use

- Non-interactive long-running tasks expected to run for >2 minutes
- Compute-intensive tasks: per-task cgroup caps (mem ≤40%, cpu ≤90%) prevent runaway resource use
- Tasks that must survive the Claude session: daemon runs detached under user systemd

## When NOT to Use

- Short tasks (<2 minutes): run in Bash directly
- Interactive commands: use `tmux` instead
- IO-bound polling loops: babysit's scheduler does not help
- Tasks fine to die with Claude: use Bash `run_in_background: true`

## Workflow

Before launching heavy work, run the `/preflight-check` skill.

### 1. Enqueue

```bash
babysit run \
  --name="<unique-name>" \
  --command="PYTHONUNBUFFERED=1 uv run python -u path/to/script.py" \
  --estimated_time="30m"
```

The call is non-blocking: returns immediately with `queued: <name>`. The daemon dispatches as soon as system has capacity.

Required: `--name` (unique), `--command` (single shell string). Optional: `--estimated_time` (default 10m), `--kill_timeout` (default 2× estimated), `--observability_interval` (default 5m), `--mem_pct_limit` (default 40), `--cpu_pct_limit` (default 90).

### 2. Wait for completion (background)

```bash
babysit wait --name="<unique-name>"
```

Run with `run_in_background: true`. You'll get a `<task-notification>` on terminal status. **Do not poll** with `babysit status` in a sleep loop — the daemon already knows; subscribe instead of polling.

### 3. Check log / progress at any time

```bash
babysit log --tail=15 --name="<unique-name>"
babysit log --follow --name="<unique-name>"   # stream; use with run_in_background: true
```

### 4. List / kill

```bash
babysit list                           # all tasks, JSON
babysit status --name="<name>"         # one task, JSON
babysit kill --name="<name>"           # SIGTERM, then scope-stop fallback
```

## The Observability Contract

babysit **kills tasks that go silent** for longer than `observability_interval` (default 5m). Your command MUST print at least one line every 5 minutes. Use:

- `PYTHONUNBUFFERED=1` (or `python -u`) to defeat block-buffering
- Periodic progress markers with real signal: `[3/42] ETA ~3m loss=1.2e-4`
- LightGBM / native C++ stdout under pipes: write a custom Python callback with `flush=True` — `lgb.log_evaluation` is silent under non-tty stdout
- Generic keep-alives (`Keep-alive`, dots) defeat the purpose; emit progress, not noise

## Conversation Example

<example>
<user-msg>Start training in the background.</user-msg>
<assistant-msg>
```
Bash(command: "babysit run --name=train-maker-200t --command='PYTHONUNBUFFERED=1 uv run python -u src/train_maker_twohead.py' --estimated_time=2h", run_in_background: false)
Bash(command: "babysit wait --name=train-maker-200t", run_in_background: true)
```
Training enqueued; will notify on completion.
[STOP AND WAIT]
</assistant-msg>
<system-msg>~2h later: &lt;task-notification&gt;Background command "babysit wait ..." completed (exit code 0)&lt;/task-notification&gt;</system-msg>
<assistant-msg>
[`babysit log --tail=40 --name=train-maker-200t` to inspect final metrics]
Training complete. Sharpe 2.74, AR 20.55%.
</assistant-msg>
</example>

## Pitfalls

### `babysit status` showing `completed` does NOT guarantee success

Exit code 0 ≠ success when the inner runner swallows errors. A `just <recipe>` whose inner step fails with exit 1 may still return 0 to babysit. Always verify expected output files exist before chaining downstream tasks.

### Bash-wrapper double-quoting

`--command` is passed to `bash -c` internally. Do NOT nest a `bash -c '...'` inside:

```bash
# WRONG — bash -c sees only "VAR=1"
babysit run --name=x --command="bash -c 'VAR=1 uv run python -u s.py'"

# RIGHT
babysit run --name=x --command="VAR=1 uv run python -u s.py"
```

### Unbuffered Python under `uv`

`uv run -u` is rejected (`-u` flag goes to uv, not python). Use either:

```
PYTHONUNBUFFERED=1 uv run python script.py
uv run python -u script.py
```

### Native C++ stdout is unaffected by `PYTHONUNBUFFERED`

LightGBM, XGBoost, sklearn's joblib workers, etc. write to stdout from C/C++ and ignore Python's buffering. Under babysit's pipe stdout, the native iter-loggers appear silent and the observability watchdog will kill the task. Wrap with a Python callback that reads metrics and prints with `flush=True`.

### `babysit ping` failure means daemon is down

If commands return `babysit daemon not running`, run `babysit daemon-start`. One-time setup per host: `loginctl enable-linger $USER` so the daemon survives logout.

### Names must be unique across active tasks

`babysit run` rejects a name that matches an existing non-terminal task. Pick descriptive names (`maker-cv-200t-2026-05-19`), or `babysit kill` the prior one first.

## Skill Files

- `references/babysit.md` — full babysit spec (CLI flags, daemon config, resource rules)
- `hooks/no-sleep-babysit.sh` — blocks `sleep N && babysit log/status` anti-pattern
- `scripts/babysit.py` — self-contained babysit implementation (installed in `~/.local/bin`)
