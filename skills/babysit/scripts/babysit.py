#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "typer>=0.12",
#   "rich>=13",
#   "psutil>=7",
# ]
# ///
"""babysit — supervised background task runner.

Single-file daemon + CLI. Spawns tasks under per-user systemd scopes (cgroup v2)
and enforces memory / CPU / observability rules per ./babysit.md.

Setup: enable user-systemd lingering so daemon survives logout:
    loginctl enable-linger $USER
"""

from __future__ import annotations

import contextlib
import json
import os
import re
import selectors
import shlex
import shutil
import signal
import socket
import sqlite3
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable

import psutil
import typer
from rich.console import Console
from rich.table import Table


# ──────────────────────────────────────────────────────────────────────────────
# Paths & constants
# ──────────────────────────────────────────────────────────────────────────────

STATE_DIR = Path(os.environ.get("BABYSIT_STATE", str(Path.home() / ".local/state/babysit")))
LOG_DIR = STATE_DIR / "logs"
DB_PATH = STATE_DIR / "state.db"
SOCK_PATH = STATE_DIR / "sock"
DAEMON_PID_PATH = STATE_DIR / "daemon.pid"
DAEMON_LOG_PATH = STATE_DIR / "daemon.log"

DEFAULTS = {
    "estimated_time": "10m",
    "kill_timeout": "20m",
    "observability_interval": "5m",
    "mem_pct_limit": 40.0,
    "cpu_pct_limit": 90.0,
    "max_sys_mem_pct": 70.0,
    "max_sys_disk_pct": 90.0,
    "max_sys_cpu_pct": 90.0,
    "monitor_interval": "1m",
    "monitor_tolerance_count": 3,
    "monitor_disk_infer_by_dir": str(Path.home()),
}

STATUSES = ("pending", "running", "completed", "failed", "manual_killed", "timeout_killed", "oom_killed", "system_killed", "unknown")
TERMINAL = {"completed", "failed", "manual_killed", "timeout_killed", "oom_killed", "system_killed", "unknown"}

SPEC_COLUMNS = (
    "name", "pid", "status", "command",
    "elapsed_time", "estimated_time", "kill_timeout", "observability_interval",
    "last_observed_log", "time_since_last_observe",
    "cpu_cores", "cpu_pct",
    "mem_bytes", "mem_pct",
    "disk_write_bytes", "disk_read_bytes",
    "num_procs", "num_threads",
    "claude_session_id",
)

console = Console()


# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

_DURATION_RE = re.compile(r"^\s*([0-9]*\.?[0-9]+)\s*([smhd]?)\s*$")


def parse_duration(s: str | float | int) -> float:
    if isinstance(s, (int, float)):
        return float(s)
    m = _DURATION_RE.match(s)
    if not m:
        raise ValueError(f"bad duration: {s!r}")
    n = float(m.group(1))
    unit = m.group(2) or "s"
    return n * {"s": 1, "m": 60, "h": 3600, "d": 86400}[unit]


def fmt_duration(secs: float | None) -> str:
    if secs is None:
        return "-"
    secs = int(secs)
    if secs < 60:
        return f"{secs}s"
    if secs < 3600:
        return f"{secs // 60}m{secs % 60}s"
    h, rem = divmod(secs, 3600)
    return f"{h}h{rem // 60}m"


def fmt_bytes(n: int | None) -> str:
    if n is None:
        return "-"
    for unit in ("B", "K", "M", "G", "T"):
        if abs(n) < 1024:
            return f"{n:.1f}{unit}" if unit != "B" else f"{int(n)}{unit}"
        n /= 1024
    return f"{n:.1f}P"


def now() -> float:
    return time.time()


# ──────────────────────────────────────────────────────────────────────────────
# Storage
# ──────────────────────────────────────────────────────────────────────────────

SCHEMA = """
CREATE TABLE IF NOT EXISTS tasks (
    name TEXT PRIMARY KEY,
    command TEXT NOT NULL,
    status TEXT NOT NULL,
    pid INTEGER,
    scope_unit TEXT,
    estimated_time REAL,
    kill_timeout REAL,
    observability_interval REAL,
    mem_pct_limit REAL,
    cpu_pct_limit REAL,
    created_at REAL NOT NULL,
    started_at REAL,
    ended_at REAL,
    exit_code INTEGER,
    kill_reason TEXT,
    log_path TEXT NOT NULL,
    claude_session_id TEXT
);

CREATE TABLE IF NOT EXISTS daemon_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
"""


def open_db() -> sqlite3.Connection:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH, isolation_level=None, timeout=10.0)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.row_factory = sqlite3.Row
    conn.executescript(SCHEMA)
    return conn


def row_to_dict(r: sqlite3.Row | None) -> dict[str, Any] | None:
    return dict(r) if r is not None else None


# ──────────────────────────────────────────────────────────────────────────────
# systemd-run wrapper
# ──────────────────────────────────────────────────────────────────────────────


def _systemd_env() -> dict[str, str]:
    env = os.environ.copy()
    uid = os.getuid()
    env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{uid}")
    env.setdefault("DBUS_SESSION_BUS_ADDRESS", f"unix:path=/run/user/{uid}/bus")
    return env


def spawn_under_scope(
    name: str,
    command: str,
    mem_pct_limit: float,
    cpu_pct_limit: float,
    log_path: Path,
) -> tuple[subprocess.Popen, str]:
    """Spawn `command` inside a transient systemd --user scope (cgroup v2).

    Returns (Popen, scope_unit_name). Popen.pid is the task PID — systemd-run
    --scope sets up the cgroup then execs in place, preserving PID.
    """
    n_cores = os.cpu_count() or 1
    cpu_quota = int(round(cpu_pct_limit * n_cores))  # 90% × 64 cores = 5760%
    mem_total = psutil.virtual_memory().total
    mem_bytes = int(mem_total * mem_pct_limit / 100)
    scope_unit = f"babysit-{re.sub(r'[^A-Za-z0-9_-]', '_', name)}.scope"

    cmd = [
        "systemd-run", "--user", "--scope", "--quiet", "--collect",
        f"--unit={scope_unit}",
        f"--property=MemoryMax={mem_bytes}",
        f"--property=CPUQuota={cpu_quota}%",
        "--",
        "bash", "-c", command,
    ]

    log_path.parent.mkdir(parents=True, exist_ok=True)
    fp = open(log_path, "ab", buffering=0)
    proc = subprocess.Popen(
        cmd,
        stdout=fp,
        stderr=subprocess.STDOUT,
        stdin=subprocess.DEVNULL,
        start_new_session=True,
        env=_systemd_env(),
        close_fds=True,
        preexec_fn=lambda: os.nice(10),  # demote task vs monitor
    )
    fp.close()  # child holds the FD now
    return proc, scope_unit


def stop_scope(scope_unit: str) -> None:
    """Best-effort scope teardown via systemctl --user stop."""
    with contextlib.suppress(Exception):
        subprocess.run(
            ["systemctl", "--user", "stop", scope_unit],
            env=_systemd_env(),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )


# ──────────────────────────────────────────────────────────────────────────────
# Resource probes
# ──────────────────────────────────────────────────────────────────────────────


@dataclass
class TaskStats:
    cpu_pct: float = 0.0
    cpu_cores: float = 0.0
    mem_bytes: int = 0
    mem_pct: float = 0.0
    disk_read_bytes: int = 0
    disk_write_bytes: int = 0
    num_procs: int = 0
    num_threads: int = 0


def probe_task(
    pid: int,
    prev_cpu_times: dict[int, tuple[float, float]],
) -> tuple[TaskStats, dict[int, tuple[float, float]]] | None:
    """Recursive process-tree probe with accurate per-PID CPU%.

    `prev_cpu_times` maps PID → (cpu_seconds, wall_time) from prior probe.
    CPU% per PID = (cur_cpu - prev_cpu) / (now_wall - prev_wall) * 100.
    Returns (stats, new_cpu_times) or None if root PID is gone.
    """
    try:
        root = psutil.Process(pid)
    except psutil.NoSuchProcess:
        return None
    procs = [root]
    with contextlib.suppress(psutil.NoSuchProcess):
        procs.extend(root.children(recursive=True))

    mem_total = psutil.virtual_memory().total
    now_wall = time.time()
    cpu_sum = 0.0
    mem_sum = threads_sum = read_sum = write_sum = 0
    new_cpu_times: dict[int, tuple[float, float]] = {}
    for p in procs:
        try:
            ct = p.cpu_times()
            cur_cpu = ct.user + ct.system
            mem_sum += p.memory_info().rss
            threads_sum += p.num_threads()
            try:
                io = p.io_counters()
                read_sum += io.read_bytes
                write_sum += io.write_bytes
            except (psutil.AccessDenied, AttributeError):
                pass
            new_cpu_times[p.pid] = (cur_cpu, now_wall)
            prev = prev_cpu_times.get(p.pid)
            if prev is not None:
                dw = now_wall - prev[1]
                if dw > 0:
                    cpu_sum += (cur_cpu - prev[0]) / dw * 100.0
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue

    stats = TaskStats(
        cpu_pct=cpu_sum,
        cpu_cores=cpu_sum / 100.0,
        mem_bytes=mem_sum,
        mem_pct=(mem_sum / mem_total * 100) if mem_total else 0.0,
        disk_read_bytes=read_sum,
        disk_write_bytes=write_sum,
        num_procs=len(procs),
        num_threads=threads_sum,
    )
    return stats, new_cpu_times


@dataclass
class SysStats:
    mem_pct: float
    cpu_pct: float
    disk_pct: float


def probe_system(disk_dir: str) -> SysStats:
    du = shutil.disk_usage(disk_dir)
    return SysStats(
        mem_pct=psutil.virtual_memory().percent,
        cpu_pct=psutil.cpu_percent(interval=None),
        disk_pct=du.used / du.total * 100.0 if du.total else 0.0,
    )


def log_last_mtime(log_path: Path) -> float | None:
    try:
        return log_path.stat().st_mtime
    except FileNotFoundError:
        return None


def tail_n(path: Path, n: int) -> str:
    """Last n lines of a (possibly large) log file."""
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            end = f.tell()
            block = 8192
            data = b""
            while end > 0 and data.count(b"\n") <= n:
                read = min(block, end)
                end -= read
                f.seek(end)
                data = f.read(read) + data
            lines = data.splitlines()[-n:]
            return b"\n".join(lines).decode("utf-8", "replace")
    except FileNotFoundError:
        return ""


# ──────────────────────────────────────────────────────────────────────────────
# RPC protocol — newline-delimited JSON over Unix socket
# ──────────────────────────────────────────────────────────────────────────────


def rpc_send(sock: socket.socket, obj: dict) -> None:
    sock.sendall((json.dumps(obj) + "\n").encode("utf-8"))


def rpc_recv(sock: socket.socket) -> dict | None:
    buf = b""
    while not buf.endswith(b"\n"):
        chunk = sock.recv(65536)
        if not chunk:
            return None
        buf += chunk
        if len(buf) > 16 * 1024 * 1024:
            raise RuntimeError("RPC message too large")
    line = buf.rstrip(b"\n")
    return json.loads(line.decode("utf-8")) if line else None


def daemon_alive() -> bool:
    if not DAEMON_PID_PATH.exists():
        return False
    try:
        pid = int(DAEMON_PID_PATH.read_text().strip())
        os.kill(pid, 0)
        return True
    except (ValueError, ProcessLookupError, PermissionError):
        return False


def rpc_call(op: str, **kwargs) -> dict:
    if not SOCK_PATH.exists() or not daemon_alive():
        raise RuntimeError(
            "babysit daemon not running. Start with: babysit daemon-start"
        )
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(10.0)
    try:
        s.connect(str(SOCK_PATH))
        rpc_send(s, {"op": op, **kwargs})
        resp = rpc_recv(s)
    finally:
        s.close()
    if resp is None:
        raise RuntimeError("empty response from daemon")
    if not resp.get("ok", False):
        raise RuntimeError(resp.get("error", "unknown daemon error"))
    return resp


# ──────────────────────────────────────────────────────────────────────────────
# Daemon
# ──────────────────────────────────────────────────────────────────────────────


@dataclass
class RunningTask:
    name: str
    popen: subprocess.Popen | None  # None for adopted (cross-daemon-restart) tasks
    pid: int
    scope_unit: str
    log_path: Path
    obs_interval: float
    kill_timeout: float
    mem_pct_limit: float
    cpu_pct_limit: float
    started_at: float
    obs_violation_count: int = 0
    last_log_mtime: float | None = None
    last_stats: TaskStats | None = None
    prev_cpu_times: dict[int, tuple[float, float]] = field(default_factory=dict)


class Daemon:
    def __init__(
        self,
        max_sys_mem_pct: float,
        max_sys_disk_pct: float,
        max_sys_cpu_pct: float,
        monitor_interval: float,
        monitor_tolerance_count: int,
        monitor_disk_infer_by_dir: str,
    ) -> None:
        self.max_sys_mem_pct = max_sys_mem_pct
        self.max_sys_disk_pct = max_sys_disk_pct
        self.max_sys_cpu_pct = max_sys_cpu_pct
        self.monitor_interval = monitor_interval
        self.monitor_tolerance_count = monitor_tolerance_count
        self.disk_dir = monitor_disk_infer_by_dir

        self.db = open_db()
        self.running: dict[str, RunningTask] = {}
        self.sys_pressure: dict[str, int] = {"mem": 0, "cpu": 0, "disk": 0}
        self.shutting_down = False

        # Adopt any tasks left running by a prior daemon (PID-reuse guarded)
        self._adopt_running()

        if SOCK_PATH.exists():
            SOCK_PATH.unlink()
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(str(SOCK_PATH))
        os.chmod(SOCK_PATH, 0o600)
        self.server.listen(64)
        self.server.setblocking(False)

        self.sel = selectors.DefaultSelector()
        self.sel.register(self.server, selectors.EVENT_READ, self._accept)

        # Save config snapshot
        for k, v in {
            "max_sys_mem_pct": max_sys_mem_pct,
            "max_sys_disk_pct": max_sys_disk_pct,
            "max_sys_cpu_pct": max_sys_cpu_pct,
            "monitor_interval": monitor_interval,
            "monitor_tolerance_count": monitor_tolerance_count,
            "monitor_disk_infer_by_dir": monitor_disk_infer_by_dir,
        }.items():
            self.db.execute(
                "INSERT OR REPLACE INTO daemon_config(key,value) VALUES(?,?)",
                (k, json.dumps(v)),
            )

    # ── PID adoption across daemon restart ─────────────────────────────────
    def _adopt_running(self) -> None:
        rows = self.db.execute("SELECT * FROM tasks WHERE status='running'").fetchall()
        for r in rows:
            name = r["name"]
            pid = r["pid"]
            started_at = r["started_at"]
            reason = None
            if pid is None or not psutil.pid_exists(pid):
                reason = "daemon_restart_dead"
            else:
                try:
                    proc = psutil.Process(pid)
                    # PID-reuse guard
                    if started_at and proc.create_time() > started_at + 5:
                        reason = "daemon_restart_pid_reuse"
                except psutil.NoSuchProcess:
                    reason = "daemon_restart_dead"
            if reason is not None:
                self.db.execute(
                    "UPDATE tasks SET status='failed', kill_reason=?, ended_at=? WHERE name=?",
                    (reason, now(), name),
                )
                self.log(f"[{name}] not adopted ({reason})")
                continue
            rt = RunningTask(
                name=name,
                popen=None,
                pid=pid,
                scope_unit=r["scope_unit"] or "",
                log_path=Path(r["log_path"]),
                obs_interval=r["observability_interval"] or parse_duration(DEFAULTS["observability_interval"]),
                kill_timeout=r["kill_timeout"] or parse_duration(DEFAULTS["kill_timeout"]),
                mem_pct_limit=r["mem_pct_limit"] or DEFAULTS["mem_pct_limit"],
                cpu_pct_limit=r["cpu_pct_limit"] or DEFAULTS["cpu_pct_limit"],
                started_at=started_at or now(),
            )
            # prime CPU baseline
            with contextlib.suppress(psutil.NoSuchProcess, psutil.AccessDenied):
                p = psutil.Process(pid)
                ct = p.cpu_times()
                rt.prev_cpu_times = {pid: (ct.user + ct.system, time.time())}
            self.running[name] = rt
            self.log(f"[{name}] adopted pid={pid} from prior daemon")

    # ── lifecycle ───────────────────────────────────────────────────────────
    def log(self, msg: str) -> None:
        ts = time.strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{ts}] {msg}", flush=True)

    def run_forever(self) -> None:
        signal.signal(signal.SIGTERM, lambda *_: self._begin_shutdown())
        signal.signal(signal.SIGINT, lambda *_: self._begin_shutdown())
        self.log(f"daemon up (pid={os.getpid()}) — monitor every {self.monitor_interval}s")
        psutil.cpu_percent(interval=None)  # prime
        last_tick = 0.0
        while not (self.shutting_down and not self.running):
            timeout = max(0.05, self.monitor_interval - (time.time() - last_tick))
            events = self.sel.select(timeout=timeout)
            for key, _mask in events:
                cb = key.data
                cb(key.fileobj)
            if time.time() - last_tick >= self.monitor_interval:
                self._tick()
                last_tick = time.time()
        self.log("daemon shutdown")

    def _begin_shutdown(self) -> None:
        if self.shutting_down:
            return
        self.shutting_down = True
        self.log("SIGTERM received — stopping running tasks")
        for name in list(self.running):
            self._kill_task(name, reason="daemon_shutdown", status="manual_killed")

    # ── socket I/O ──────────────────────────────────────────────────────────
    def _accept(self, sock: socket.socket) -> None:
        try:
            conn, _ = sock.accept()
        except BlockingIOError:
            return
        conn.settimeout(10.0)
        try:
            req = rpc_recv(conn)
            resp = self._dispatch(req or {})
        except Exception as e:  # noqa: BLE001
            resp = {"ok": False, "error": f"{type(e).__name__}: {e}"}
        try:
            rpc_send(conn, resp)
        except OSError:
            pass
        finally:
            conn.close()

    def _dispatch(self, req: dict) -> dict:
        op = req.get("op")
        handler = getattr(self, f"_op_{op}", None)
        if handler is None:
            return {"ok": False, "error": f"unknown op: {op}"}
        return handler(req)

    # ── RPC handlers ────────────────────────────────────────────────────────
    def _op_run(self, req: dict) -> dict:
        name = req["name"]
        command = req["command"]
        existing = self.db.execute(
            "SELECT status FROM tasks WHERE name=?", (name,)
        ).fetchone()
        if existing and existing["status"] not in TERMINAL:
            return {"ok": False, "error": f"task {name!r} already exists with status={existing['status']}"}
        if existing:
            # purge terminal record so name can be reused
            self.db.execute("DELETE FROM tasks WHERE name=?", (name,))

        log_path = LOG_DIR / f"{name}.log"
        log_path.parent.mkdir(parents=True, exist_ok=True)
        # Truncate to start fresh
        with open(log_path, "wb"):
            pass

        self.db.execute(
            "INSERT INTO tasks(name,command,status,estimated_time,kill_timeout,"
            "observability_interval,mem_pct_limit,cpu_pct_limit,created_at,log_path,"
            "claude_session_id) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
            (
                name,
                command,
                "pending",
                req.get("estimated_time"),
                req.get("kill_timeout"),
                req.get("observability_interval"),
                req.get("mem_pct_limit"),
                req.get("cpu_pct_limit"),
                now(),
                str(log_path),
                req.get("claude_session_id"),
            ),
        )
        # Dispatch immediately if system has capacity (don't wait for tick)
        if not self.shutting_down:
            s = probe_system(self.disk_dir)
            if not (s.mem_pct > self.max_sys_mem_pct
                    or s.cpu_pct > self.max_sys_cpu_pct
                    or s.disk_pct > self.max_sys_disk_pct):
                self._schedule_pending()
        return {"ok": True, "name": name}

    def _op_list(self, req: dict) -> dict:
        rows = self.db.execute("SELECT * FROM tasks ORDER BY created_at").fetchall()
        return {"ok": True, "tasks": [self._enrich(r) for r in rows]}

    def _op_status(self, req: dict) -> dict:
        r = self.db.execute("SELECT * FROM tasks WHERE name=?", (req["name"],)).fetchone()
        if r is None:
            return {"ok": False, "error": f"no such task: {req['name']!r}"}
        return {"ok": True, "task": self._enrich(r)}

    def _op_kill(self, req: dict) -> dict:
        name = req["name"]
        if name not in self.running:
            return {"ok": False, "error": f"task {name!r} not running"}
        self._kill_task(name, reason="manual", status="manual_killed")
        return {"ok": True}

    def _op_shutdown(self, req: dict) -> dict:
        self._begin_shutdown()
        return {"ok": True}

    def _op_ping(self, req: dict) -> dict:
        return {"ok": True, "pid": os.getpid(), "running": len(self.running)}

    # ── enrichment for list/status responses ───────────────────────────────
    def _enrich(self, r: sqlite3.Row) -> dict:
        d = dict(r)
        rt = self.running.get(d["name"])
        # runtime stats: present for running, None for terminal/pending
        stat_keys = ("cpu_pct", "cpu_cores", "mem_bytes", "mem_pct",
                     "disk_read_bytes", "disk_write_bytes", "num_procs", "num_threads")
        if rt and rt.last_stats:
            s = rt.last_stats
            for k in stat_keys:
                d[k] = getattr(s, k)
        else:
            for k in stat_keys:
                d.setdefault(k, None)
        # elapsed
        if d.get("started_at") and not d.get("ended_at"):
            d["elapsed_time"] = now() - d["started_at"]
        elif d.get("started_at") and d.get("ended_at"):
            d["elapsed_time"] = d["ended_at"] - d["started_at"]
        else:
            d["elapsed_time"] = None
        # observability
        if rt and rt.last_log_mtime:
            d["time_since_last_observe"] = now() - rt.last_log_mtime
            d["last_observed_log"] = time.strftime(
                "%Y-%m-%d %H:%M:%S", time.localtime(rt.last_log_mtime)
            )
        else:
            d.setdefault("last_observed_log", None)
            d.setdefault("time_since_last_observe", None)
        # ensure every spec column key exists
        for k in SPEC_COLUMNS:
            d.setdefault(k, None)
        return d

    # ── monitor tick ────────────────────────────────────────────────────────
    def _tick(self) -> None:
        # 1. reap completed tasks & enforce per-task limits
        for name in list(self.running):
            self._check_task(name)

        # 2. system-level checks (per-dimension counters, spec rule #3.x3)
        sys_stats = probe_system(self.disk_dir)
        dim_violated = {
            "mem": sys_stats.mem_pct > self.max_sys_mem_pct,
            "cpu": sys_stats.cpu_pct > self.max_sys_cpu_pct,
            "disk": sys_stats.disk_pct > self.max_sys_disk_pct,
        }
        for dim, v in dim_violated.items():
            self.sys_pressure[dim] = self.sys_pressure[dim] + 1 if v else 0
        for dim in ("disk", "cpu", "mem"):  # disk > cpu > mem priority
            if self.sys_pressure[dim] >= self.monitor_tolerance_count:
                self._enforce_system_dim(dim, sys_stats)
                self.sys_pressure[dim] = 0
                break  # at most one kill per tick; let system recover before next

        # 3. dispatch pending tasks
        if not self.shutting_down and not any(dim_violated.values()):
            self._schedule_pending()

        # 4. heartbeat
        if int(now()) % 60 < self.monitor_interval:
            self.log(
                f"tick: running={len(self.running)} "
                f"sys mem={sys_stats.mem_pct:.0f}% cpu={sys_stats.cpu_pct:.0f}% "
                f"disk={sys_stats.disk_pct:.0f}%"
            )

    def _check_task(self, name: str) -> None:
        rt = self.running[name]
        # liveness check — Popen.poll() if owned, psutil.pid_exists if adopted
        if rt.popen is not None:
            rc = rt.popen.poll()
            if rc is not None:
                status = "completed" if rc == 0 else "failed"
                self._finalize(name, status=status, exit_code=rc)
                return
        else:
            if not psutil.pid_exists(rt.pid):
                # PID gone — can't waitpid cross-process, so success/failure is unobservable
                self._finalize(name, status="unknown", exit_code=None,
                              reason="adopted_exited")
                return

        result = probe_task(rt.pid, rt.prev_cpu_times)
        if result is None:
            rc = rt.popen.poll() if rt.popen else None
            self._finalize(name, status="failed", exit_code=(rc if rc is not None else -1),
                          reason="process_vanished")
            return
        stats, new_cpu_times = result
        rt.last_stats = stats
        rt.prev_cpu_times = new_cpu_times

        # observability: log mtime (baseline = started_at if log never written)
        mtime = log_last_mtime(rt.log_path)
        if mtime is not None and (rt.last_log_mtime is None or mtime > rt.last_log_mtime):
            rt.last_log_mtime = mtime
            rt.obs_violation_count = 0
        else:
            baseline = rt.last_log_mtime if rt.last_log_mtime is not None else rt.started_at
            silent_for = now() - baseline
            if silent_for > rt.obs_interval:
                rt.obs_violation_count += 1
                self.log(f"[{name}] silent {fmt_duration(silent_for)} (> {fmt_duration(rt.obs_interval)}) — violation {rt.obs_violation_count}")

        # per-task rule enforcement (immediate kill per spec)
        elapsed = now() - rt.started_at
        if stats.mem_pct > rt.mem_pct_limit:
            self.log(f"[{name}] mem {stats.mem_pct:.1f}% > {rt.mem_pct_limit}% — KILL")
            self._kill_task(name, reason="mem_exceeded", status="oom_killed")
            return
        if stats.cpu_pct > rt.cpu_pct_limit * (os.cpu_count() or 1):
            self.log(f"[{name}] cpu {stats.cpu_pct:.0f}% > {rt.cpu_pct_limit * (os.cpu_count() or 1):.0f}% — KILL")
            self._kill_task(name, reason="cpu_exceeded", status="manual_killed")
            return
        if elapsed > rt.kill_timeout:
            self.log(f"[{name}] elapsed {fmt_duration(elapsed)} > kill_timeout {fmt_duration(rt.kill_timeout)} — KILL")
            self._kill_task(name, reason="elapsed_exceeded", status="timeout_killed")
            return
        if rt.obs_violation_count >= 1:
            self.log(f"[{name}] observability stall — KILL")
            self._kill_task(name, reason="observability_stall", status="timeout_killed")
            return

    def _enforce_system_dim(self, dim: str, sys_stats: SysStats) -> None:
        if not self.running:
            return
        # disk: rank by cumulative write bytes — write-volume heuristic
        # (per-pid disk footprint is not directly observable)
        key_map = {
            "disk": lambda rt: (rt.last_stats.disk_write_bytes if rt.last_stats else 0),
            "cpu": lambda rt: (rt.last_stats.cpu_pct if rt.last_stats else 0),
            "mem": lambda rt: (rt.last_stats.mem_bytes if rt.last_stats else 0),
        }
        ranked = sorted(self.running.values(), key=key_map[dim], reverse=True)
        victim = ranked[0]
        cur = {"mem": sys_stats.mem_pct, "cpu": sys_stats.cpu_pct, "disk": sys_stats.disk_pct}[dim]
        self.log(f"sys-{dim} pressure ({cur:.0f}%) sustained — KILL {victim.name}")
        self._kill_task(victim.name, reason=f"system_{dim}_pressure", status="system_killed")

    def _schedule_pending(self) -> None:
        rows = self.db.execute(
            "SELECT * FROM tasks WHERE status='pending' ORDER BY created_at"
        ).fetchall()
        for r in rows:
            if self.shutting_down:
                return
            self._start_task(r)

    def _start_task(self, r: sqlite3.Row) -> None:
        name = r["name"]
        mem_lim = r["mem_pct_limit"] or DEFAULTS["mem_pct_limit"]
        cpu_lim = r["cpu_pct_limit"] or DEFAULTS["cpu_pct_limit"]
        log_path = Path(r["log_path"])
        try:
            proc, scope_unit = spawn_under_scope(
                name=name,
                command=r["command"],
                mem_pct_limit=mem_lim,
                cpu_pct_limit=cpu_lim,
                log_path=log_path,
            )
        except Exception as e:  # noqa: BLE001
            self.log(f"[{name}] spawn failed: {e}")
            self.db.execute(
                "UPDATE tasks SET status='failed', kill_reason=?, ended_at=? WHERE name=?",
                (f"spawn_error: {e}", now(), name),
            )
            return
        started = now()
        rt = RunningTask(
            name=name,
            popen=proc,
            pid=proc.pid,
            scope_unit=scope_unit,
            log_path=log_path,
            obs_interval=r["observability_interval"] or parse_duration(DEFAULTS["observability_interval"]),
            kill_timeout=r["kill_timeout"] or parse_duration(DEFAULTS["kill_timeout"]),
            mem_pct_limit=mem_lim,
            cpu_pct_limit=cpu_lim,
            started_at=started,
        )
        # prime cpu_times baseline for accurate per-PID delta on first tick
        with contextlib.suppress(psutil.NoSuchProcess, psutil.AccessDenied):
            p = psutil.Process(proc.pid)
            ct = p.cpu_times()
            rt.prev_cpu_times = {proc.pid: (ct.user + ct.system, time.time())}
        self.running[name] = rt
        self.db.execute(
            "UPDATE tasks SET status='running', pid=?, scope_unit=?, started_at=? WHERE name=?",
            (proc.pid, scope_unit, started, name),
        )
        self.log(f"[{name}] started pid={proc.pid} scope={scope_unit}")

    def _kill_task(self, name: str, *, reason: str, status: str) -> None:
        rt = self.running.get(name)
        if rt is None:
            return
        # SIGTERM, grace, then SIGKILL via scope stop. Two code paths:
        # owned (have Popen → can wait()) vs adopted (psutil + polling).
        if rt.popen is not None:
            with contextlib.suppress(ProcessLookupError):
                rt.popen.terminate()
            try:
                rt.popen.wait(timeout=10)
            except subprocess.TimeoutExpired:
                stop_scope(rt.scope_unit)
                with contextlib.suppress(ProcessLookupError):
                    rt.popen.kill()
                with contextlib.suppress(subprocess.TimeoutExpired):
                    rt.popen.wait(timeout=5)
            rc = rt.popen.returncode if rt.popen.returncode is not None else -signal.SIGKILL
        else:
            with contextlib.suppress(psutil.NoSuchProcess):
                psutil.Process(rt.pid).terminate()
            deadline = time.time() + 10
            while time.time() < deadline and psutil.pid_exists(rt.pid):
                time.sleep(0.1)
            if psutil.pid_exists(rt.pid):
                if rt.scope_unit:
                    stop_scope(rt.scope_unit)
                with contextlib.suppress(psutil.NoSuchProcess):
                    psutil.Process(rt.pid).kill()
                deadline = time.time() + 5
                while time.time() < deadline and psutil.pid_exists(rt.pid):
                    time.sleep(0.1)
            rc = None  # adopted — can't waitpid cross-process
        self._finalize(name, status=status, exit_code=rc, reason=reason)

    def _finalize(self, name: str, *, status: str, exit_code: int, reason: str | None = None) -> None:
        rt = self.running.pop(name, None)
        if rt is not None:
            stop_scope(rt.scope_unit)
        self.db.execute(
            "UPDATE tasks SET status=?, exit_code=?, ended_at=?, kill_reason=? WHERE name=?",
            (status, exit_code, now(), reason, name),
        )
        self.log(f"[{name}] {status} exit={exit_code} reason={reason or '-'}")


# ──────────────────────────────────────────────────────────────────────────────
# Daemon entry — double-fork detach
# ──────────────────────────────────────────────────────────────────────────────


def daemonize() -> None:
    """Standard double-fork. Parent returns immediately; grandchild continues."""
    if os.fork() != 0:
        os._exit(0)
    os.setsid()
    if os.fork() != 0:
        os._exit(0)
    os.chdir("/")
    os.umask(0o077)
    sys.stdout.flush()
    sys.stderr.flush()
    DAEMON_LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    null = open("/dev/null", "rb")
    out = open(DAEMON_LOG_PATH, "ab", buffering=0)
    os.dup2(null.fileno(), 0)
    os.dup2(out.fileno(), 1)
    os.dup2(out.fileno(), 2)
    null.close()
    out.close()


# ──────────────────────────────────────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────────────────────────────────────

app = typer.Typer(
    add_completion=False,
    no_args_is_help=True,
    pretty_exceptions_enable=False,
    help="Supervised background task runner with cgroup-enforced caps.",
)


def _project(row: dict, columns: list[str]) -> dict:
    return {c: row.get(c) for c in columns}


def _print(out: Any, fmt: str, columns: list[str] | None = None) -> None:
    if columns:
        if isinstance(out, list):
            out = [_project(r, columns) for r in out]
        elif isinstance(out, dict):
            out = _project(out, columns)
    if fmt == "json":
        typer.echo(json.dumps(out, indent=2, default=str))
        return
    if isinstance(out, list):
        if not out:
            typer.echo("(no tasks)")
            return
        cols = columns or list(out[0].keys())
        tbl = Table(show_header=True, header_style="bold")
        for c in cols:
            tbl.add_column(c)
        for r in out:
            tbl.add_row(*[_fmt_cell(c, r.get(c)) for c in cols])
        console.print(tbl)
    elif isinstance(out, dict):
        cols = columns or list(out.keys())
        for k in cols:
            console.print(f"[bold]{k}[/]: {_fmt_cell(k, out.get(k))}")
    else:
        typer.echo(str(out))


def _fmt_cell(col: str, v: Any) -> str:
    if v is None:
        return "-"
    if col.endswith("_bytes"):
        return fmt_bytes(int(v))
    if col in ("elapsed_time", "estimated_time", "kill_timeout",
               "observability_interval", "time_since_last_observe"):
        return fmt_duration(float(v))
    if col in ("cpu_pct", "mem_pct"):
        return f"{float(v):.1f}"
    if col == "cpu_cores":
        return f"{float(v):.2f}"
    return str(v)


@app.command("daemon-start")
def cmd_daemon_start(
    max_sys_mem_pct: float = typer.Option(DEFAULTS["max_sys_mem_pct"]),
    max_sys_disk_pct: float = typer.Option(DEFAULTS["max_sys_disk_pct"]),
    max_sys_cpu_pct: float = typer.Option(DEFAULTS["max_sys_cpu_pct"]),
    monitor_interval: str = typer.Option(DEFAULTS["monitor_interval"]),
    monitor_tolerance_count: int = typer.Option(DEFAULTS["monitor_tolerance_count"]),
    monitor_disk_infer_by_dir: str = typer.Option(DEFAULTS["monitor_disk_infer_by_dir"]),
    foreground: bool = typer.Option(False, "--foreground", "-f", help="Run in foreground (no detach)."),
) -> None:
    """Start the babysit daemon (idempotent — exits 0 if already running)."""
    if daemon_alive():
        typer.echo(f"daemon already running (pid={DAEMON_PID_PATH.read_text().strip()})")
        return

    STATE_DIR.mkdir(parents=True, exist_ok=True)

    if not foreground:
        daemonize()

    DAEMON_PID_PATH.write_text(str(os.getpid()))
    try:
        d = Daemon(
            max_sys_mem_pct=max_sys_mem_pct,
            max_sys_disk_pct=max_sys_disk_pct,
            max_sys_cpu_pct=max_sys_cpu_pct,
            monitor_interval=parse_duration(monitor_interval),
            monitor_tolerance_count=monitor_tolerance_count,
            monitor_disk_infer_by_dir=monitor_disk_infer_by_dir,
        )
        d.run_forever()
    finally:
        with contextlib.suppress(FileNotFoundError):
            DAEMON_PID_PATH.unlink()
        with contextlib.suppress(FileNotFoundError):
            SOCK_PATH.unlink()


@app.command("daemon-stop")
def cmd_daemon_stop() -> None:
    """Stop the daemon (kills all running tasks)."""
    if not daemon_alive():
        typer.echo("daemon not running")
        return
    try:
        rpc_call("shutdown")
    except Exception:
        pid = int(DAEMON_PID_PATH.read_text().strip())
        os.kill(pid, signal.SIGTERM)
    # wait up to 30s
    for _ in range(60):
        if not daemon_alive():
            typer.echo("daemon stopped")
            return
        time.sleep(0.5)
    typer.echo("daemon did not exit cleanly", err=True)
    raise typer.Exit(1)


@app.command("run")
def cmd_run(
    name: str = typer.Option(..., help="Unique task name."),
    command: str = typer.Option(..., help="Shell command to run."),
    estimated_time: str = typer.Option(DEFAULTS["estimated_time"]),
    kill_timeout: str | None = typer.Option(None, help="Default = 2 × estimated_time."),
    observability_interval: str = typer.Option(DEFAULTS["observability_interval"]),
    mem_pct_limit: float = typer.Option(DEFAULTS["mem_pct_limit"]),
    cpu_pct_limit: float = typer.Option(DEFAULTS["cpu_pct_limit"]),
) -> None:
    """Enqueue a task. Returns immediately (non-blocking)."""
    est = parse_duration(estimated_time)
    kt = parse_duration(kill_timeout) if kill_timeout else est * 2
    obs = parse_duration(observability_interval)
    resp = rpc_call(
        "run",
        name=name,
        command=command,
        estimated_time=est,
        kill_timeout=kt,
        observability_interval=obs,
        mem_pct_limit=mem_pct_limit,
        cpu_pct_limit=cpu_pct_limit,
        claude_session_id=os.environ.get("CLAUDE_CODE_SESSION_ID"),
    )
    typer.echo(f"queued: {resp['name']}")


_DEFAULT_COLS = ",".join(SPEC_COLUMNS)


def _split_cols(s: str) -> list[str]:
    return [c.strip() for c in s.split(",") if c.strip()]


@app.command("list")
def cmd_list(
    columns: str = typer.Option(_DEFAULT_COLS, "--columns", help="Comma-separated columns."),
    format: str = typer.Option("json", "--format", help="json|table"),
) -> None:
    """List all tasks."""
    resp = rpc_call("list")
    _print(resp["tasks"], format, columns=_split_cols(columns))


@app.command("status")
def cmd_status(
    name: str = typer.Option(..., help="Task name."),
    columns: str = typer.Option(_DEFAULT_COLS, "--columns"),
    format: str = typer.Option("json", "--format"),
) -> None:
    """Show one task's status."""
    resp = rpc_call("status", name=name)
    _print(resp["task"], format, columns=_split_cols(columns))


@app.command("wait")
def cmd_wait(
    name: str = typer.Option(..., help="Task name."),
    poll_interval: float = typer.Option(0.5, help="Poll interval seconds."),
    columns: str = typer.Option(_DEFAULT_COLS, "--columns"),
    format: str = typer.Option("json", "--format"),
) -> None:
    """Block until a task reaches a terminal status.

    stdout: single terminal-status JSON object (unchanged contract).
    stderr: zero-or-more mid-flight event JSON lines, currently
        `{"event":"runaway_risk", ...}` emitted once when `elapsed_time`
        first crosses `estimated_time`. Pair with Monitor / Bash
        run_in_background=true — the harness merges both streams and
        surfaces each new line as a notification.
    """
    runaway_alerted = False
    while True:
        resp = rpc_call("status", name=name)
        t = resp["task"]
        if t["status"] in TERMINAL:
            _print(t, format, columns=_split_cols(columns))
            raise typer.Exit(0 if t["status"] == "completed" else 1)
        if not runaway_alerted:
            elapsed = t.get("elapsed_time")
            estimated = t.get("estimated_time")
            if elapsed is not None and estimated and elapsed > estimated:
                print(json.dumps({
                    "event": "runaway_risk",
                    "name": name,
                    "elapsed_time": elapsed,
                    "estimated_time": estimated,
                    "kill_timeout": t.get("kill_timeout"),
                    "hint": "elapsed exceeded estimated_time; inspect `babysit log --tail` or kill if stuck",
                }), file=sys.stderr, flush=True)
                runaway_alerted = True
        time.sleep(poll_interval)


@app.command("kill")
def cmd_kill(
    name: str = typer.Option(..., help="Task name."),
) -> None:
    """Kill a running task."""
    rpc_call("kill", name=name)
    typer.echo(f"killed: {name}")


@app.command("log")
def cmd_log(
    name: str = typer.Option(..., help="Task name."),
    tail: int | None = typer.Option(None, help="Last N lines."),
    head: int | None = typer.Option(None, help="First N lines."),
    full: bool = typer.Option(False, help="Print whole log to stdout."),
    follow: bool = typer.Option(False, "--follow", "-F", help="Stream new lines (tail -F)."),
) -> None:
    """Show task log."""
    resp = rpc_call("status", name=name)
    log_path = Path(resp["task"]["log_path"])
    if not log_path.exists():
        typer.echo(f"(no log file at {log_path})", err=True)
        raise typer.Exit(1)
    if follow:
        os.execvp("tail", ["tail", "-n", "+1", "-F", str(log_path)])
    if full:
        with open(log_path, "rb") as f:
            shutil.copyfileobj(f, sys.stdout.buffer)
        return
    if head is not None:
        with open(log_path, "rb") as f:
            for i, line in enumerate(f):
                if i >= head:
                    break
                sys.stdout.buffer.write(line)
        return
    if tail is None:
        tail = 15
    out = tail_n(log_path, tail)
    sys.stdout.write(out)
    if not out.endswith("\n"):
        sys.stdout.write("\n")


@app.command("ping")
def cmd_ping() -> None:
    """Check daemon liveness."""
    resp = rpc_call("ping")
    typer.echo(json.dumps({k: v for k, v in resp.items() if k != "ok"}))


def main() -> None:
    try:
        app()
    except RuntimeError as e:
        typer.echo(f"error: {e}", err=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
