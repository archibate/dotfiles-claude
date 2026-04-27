#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Per-session audit of Write / Edit / MultiEdit tool calls.

Subcommands:
  hook            PreToolUse hook. Reads payload JSON on stdin and, on the
                  first time a file is touched in the session, snapshots the
                  current on-disk content into /tmp/claude-audit/<SID>.json.
  show [SID]      Print git-style unified diff (with surrounding context) of
                  the recorded original vs current content for every file in
                  session SID. Defaults to the most recent session.
  list            One line per recorded session: id, file count, mtime.

Always exits 0 from the hook subcommand — never blocks a tool call.
"""

import argparse
import fcntl
import io
import json
import os
import re
import signal
import stat as stat_mod
import subprocess
import sys
import time
import difflib
from contextlib import redirect_stdout
from pathlib import Path

if hasattr(signal, "SIGPIPE"):
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)

AUDIT_DIR = Path("/tmp/claude-audit")
MAX_SNAPSHOT_BYTES = 5 * 1024 * 1024  # skip files larger than 5 MB
BINARY_SENTINEL = "\0BINARY\0"
TOOLBIG_SENTINEL = "\0TOOBIG\0"


# ---------- storage ----------

def session_file(sid: str) -> Path:
    return AUDIT_DIR / f"{sid}.json"


def read_text_safely(path: Path) -> str | None:
    """None = file does not exist. Sentinels for binary / oversized."""
    if not path.exists() or not path.is_file():
        return None
    try:
        if path.stat().st_size > MAX_SNAPSHOT_BYTES:
            return TOOLBIG_SENTINEL
        return path.read_text()
    except UnicodeDecodeError:
        return BINARY_SENTINEL
    except OSError:
        return None


def git_mode_of(path: Path) -> str | None:
    """Translate stat mode to git's blob mode string. None if path is absent
    or not a representable kind."""
    try:
        st = path.lstat()
    except OSError:
        return None
    if stat_mod.S_ISLNK(st.st_mode):
        return "120000"
    if not stat_mod.S_ISREG(st.st_mode):
        return None
    return "100755" if (st.st_mode & 0o111) else "100644"


def with_session_locked(sid: str, mutate):
    """Load session JSON under flock, call mutate(data), persist atomically."""
    AUDIT_DIR.mkdir(parents=True, exist_ok=True)
    target = session_file(sid)
    lock_path = AUDIT_DIR / f"{sid}.lock"
    with open(lock_path, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if target.exists():
            try:
                data = json.loads(target.read_text())
            except (json.JSONDecodeError, OSError):
                data = {"session_id": sid, "started": time.time(), "files": {}}
        else:
            data = {"session_id": sid, "started": time.time(), "files": {}}
        mutate(data)
        tmp = target.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False))
        os.replace(tmp, target)


# ---------- hook ----------

def cmd_hook() -> int:
    try:
        payload = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, ValueError):
        return 0

    if payload.get("tool_name") not in ("Write", "Edit", "MultiEdit"):
        return 0

    tin = payload.get("tool_input") or {}
    raw_path = tin.get("file_path") or tin.get("file") or ""
    if not raw_path:
        return 0

    cwd = payload.get("cwd") or os.getcwd()
    p = Path(raw_path)
    if not p.is_absolute():
        p = Path(cwd) / p
    try:
        abs_path = str(p.resolve())
    except OSError:
        abs_path = str(p)

    # never audit our own audit dir
    if abs_path.startswith(str(AUDIT_DIR)):
        return 0

    sid = payload.get("session_id") or "unknown"
    tool = payload["tool_name"]

    src = Path(abs_path)
    try:
        if src.is_file() and src.stat().st_size > MAX_SNAPSHOT_BYTES:
            return 0  # bypass — don't bloat audit JSON
    except OSError:
        pass

    def mutate(data: dict) -> None:
        files = data.setdefault("files", {})
        if abs_path in files:
            return
        files[abs_path] = {
            "original": read_text_safely(src),
            "original_mode": git_mode_of(src),
            "first_seen": time.time(),
            "tool": tool,
        }

    try:
        with_session_locked(sid, mutate)
    except OSError:
        pass  # never block the tool call
    return 0


# ---------- show ----------

GREEN, RED, CYAN, BOLD, DIM, RESET = (
    "\033[32m", "\033[31m", "\033[36m", "\033[1m", "\033[2m", "\033[0m",
)


def colorize(line: str, color: bool) -> str:
    if not color:
        return line
    if (line.startswith("diff --git")
            or line.startswith("new file mode")
            or line.startswith("deleted file mode")
            or line.startswith("index ")
            or line.startswith("Binary files")
            or line.startswith("+++")
            or line.startswith("---")):
        return f"{BOLD}{line}{RESET}"
    if line.startswith("+"):
        return f"{GREEN}{line}{RESET}"
    if line.startswith("-"):
        return f"{RED}{line}{RESET}"
    if line.startswith("@@"):
        return f"{CYAN}{line}{RESET}"
    return line


def latest_session_id() -> str | None:
    if not AUDIT_DIR.exists():
        return None
    files = [p for p in AUDIT_DIR.glob("*.json") if not p.name.endswith(".tmp.json")]
    if not files:
        return None
    return max(files, key=lambda p: p.stat().st_mtime).stem


def emit_diff(path: str,
              original: str | None, original_mode: str | None,
              current: str | None, current_mode: str | None,
              context: int, color: bool) -> bool:
    if original == current and original_mode == current_mode:
        return False

    rel = path.lstrip("/")
    a_path = f"a/{rel}"
    b_path = f"b/{rel}"
    header = f"diff --git {a_path} {b_path}\n"

    if original in (BINARY_SENTINEL, TOOLBIG_SENTINEL) or current in (BINARY_SENTINEL, TOOLBIG_SENTINEL):
        sys.stdout.write(colorize(header, color))
        if BINARY_SENTINEL in (original, current):
            sys.stdout.write(colorize(f"Binary files {a_path} and {b_path} differ\n", color))
        else:
            sys.stdout.write(f"Files {a_path} and {b_path} differ (skipped, >5MB)\n")
        sys.stdout.write("\n")
        return True

    prefix_lines: list[str] = []
    if original is None:
        a_label, b_label = "/dev/null", b_path
        prefix_lines.append(f"new file mode {current_mode or '100644'}\n")
    elif current is None:
        a_label, b_label = a_path, "/dev/null"
        prefix_lines.append(f"deleted file mode {original_mode or '100644'}\n")
    else:
        a_label, b_label = a_path, b_path
        if original_mode and current_mode and original_mode != current_mode:
            prefix_lines.append(f"old mode {original_mode}\n")
            prefix_lines.append(f"new mode {current_mode}\n")

    diff_lines: list[str] = []
    if original != current:
        a = (original or "").splitlines(keepends=True)
        b = (current or "").splitlines(keepends=True)
        diff_lines = list(difflib.unified_diff(a, b, fromfile=a_label, tofile=b_label, n=context))

    if not prefix_lines and not diff_lines:
        return False

    sys.stdout.write(colorize(header, color))
    for line in prefix_lines:
        sys.stdout.write(colorize(line, color))
    for line in diff_lines:
        if not line.endswith("\n"):
            line += "\n"
        sys.stdout.write(colorize(line, color))
    sys.stdout.write("\n")
    return True


def cmd_show(sid: str | None, context: int, color: bool) -> int:
    if sid is None:
        sid = latest_session_id()
        if sid is None:
            print("No audit data in /tmp/claude-audit.", file=sys.stderr)
            return 1

    f = session_file(sid)
    if not f.exists():
        print(f"No audit file for session {sid}.", file=sys.stderr)
        return 1

    data = json.loads(f.read_text())
    files = data.get("files") or {}
    if not files:
        print(f"Session {sid}: no files recorded.", file=sys.stderr)
        return 0

    shown = 0
    for path, info in sorted(files.items()):
        current = read_text_safely(Path(path))
        current_mode = git_mode_of(Path(path))
        if emit_diff(path, info.get("original"), info.get("original_mode"),
                     current, current_mode, context, color):
            shown += 1

    if shown == 0:
        print(f"Session {sid}: {len(files)} file(s) tracked, no current diffs.")
    return 0


# Category tag set — source of truth lives in ~/.claude/agents/audit-fresh-eye.md;
# this set only validates that the subagent's verdict uses a known tag.
ALL_CATEGORIES = frozenset({
    "DOC-contradiction", "DOC-over-emphasis", "DOC-tonal-drift",
    "DOC-justifying-aside", "DOC-defensive-caveat", "DOC-hallucinated-ref",
    "DOC-stale-reference", "DOC-audience-mismatch", "DOC-incident-leak",
    "DOC-style-drift", "DOC-inverted-phrasing", "DOC-patch-over-restructure",
    "DOC-positional-fit",
    "CODE-contradiction", "CODE-comment-mismatch", "CODE-structural-drift",
    "CODE-defensive", "CODE-bandaid", "CODE-hallucinated-ref",
    "CODE-scope-creep", "CODE-style-drift", "CODE-debug-leftover",
    "CODE-patch-over-refactor", "CODE-missed-extraction", "CODE-misplacement",
    "CODE-sync-not-updated",
})


def render_diff_from_path(json_path: Path) -> str:
    """Read the audit JSON at json_path and render its diff. Empty string if
    file missing, malformed, or has no current diffs."""
    if not json_path.exists():
        return ""
    try:
        data = json.loads(json_path.read_text())
    except (json.JSONDecodeError, OSError):
        return ""
    files = data.get("files") or {}
    if not files:
        return ""

    buf = io.StringIO()
    with redirect_stdout(buf):
        for path, info in sorted(files.items()):
            current = read_text_safely(Path(path))
            current_mode = git_mode_of(Path(path))
            emit_diff(path, info.get("original"), info.get("original_mode"),
                      current, current_mode, context=3, color=False)
    return buf.getvalue()


# Header pattern: a line whose only word content is CLEAN or FIXES, allowing
# markdown decoration around it (`**FIXES**`, `# CLEAN`, `[FIXES]`, etc.).
# This is lenient by design: some models emit free-form preamble before the
# structured verdict, and a strict line-1 check would drop their reports.
_VERDICT_HEADER_RE = re.compile(r"^\W*(CLEAN|FIXES)\W*$")


def _parse_verdict(raw: str) -> tuple[str, list[dict]]:
    """Parse the subagent's tab-separated verdict.

    Scans for the first line whose only word content is CLEAN or FIXES
    (preamble before it is ignored). After a FIXES header, parses
    tab-separated 3-field lines and skips any line that doesn't fit (so
    trailing prose or markdown code fences are dropped). Returns
    ("UNKNOWN", []) only when no header is found at all."""
    lines = [ln for ln in (raw or "").splitlines() if ln.strip()]

    header_idx = -1
    header = ""
    for i, ln in enumerate(lines):
        m = _VERDICT_HEADER_RE.match(ln.strip())
        if m:
            header = m.group(1)
            header_idx = i
            break

    if not header:
        return ("UNKNOWN", [])
    if header == "CLEAN":
        return ("CLEAN", [])

    issues: list[dict] = []
    for ln in lines[header_idx + 1:]:
        parts = ln.split("\t")
        if len(parts) != 3:
            continue  # skip prose, code fences, blank lines, etc.
        path, category, fix = (p.strip() for p in parts)
        if not path or category not in ALL_CATEGORIES or not fix:
            continue
        issues.append({"file": path, "category": category, "fix": fix})
    return ("FIXES", issues)


def _render_fixes(issues: list[dict]) -> str:
    """Format parsed issues into the stable agent-facing layout. Issues are
    grouped by file, ordered as the subagent emitted them."""
    out: list[str] = ["FIXES:"]
    last_file: str | None = None
    for it in issues:
        if it["file"] != last_file:
            out.append(f"  {it['file']}:")
            last_file = it["file"]
        out.append(f"    [{it['category']}] {it['fix']}")
    return "\n".join(out)


def _stop_log(sid: str, msg: str) -> None:
    AUDIT_DIR.mkdir(parents=True, exist_ok=True)
    try:
        with open(AUDIT_DIR / f"{sid}.stop.log", "a") as f:
            f.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}\n")
    except OSError:
        pass


def cmd_stop_hook() -> int:
    """Stop hook handler. Spawns a fresh-eye audit subagent over the diff of
    files edited this turn. asyncRewake-compatible:
        exit 0 → silent
        exit 2 → wakes Claude with stderr (the verdict) as a system reminder.
    Recursion guard via CLAUDE_AUDIT_SUBAGENT env var."""
    if os.environ.get("CLAUDE_AUDIT_SUBAGENT") == "1":
        return 0

    try:
        payload = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, ValueError):
        payload = {}

    sid = payload.get("session_id") or "unknown"
    cwd = payload.get("cwd") or os.getcwd()

    # Atomically claim this turn's audit window. Concurrent Stops fire their
    # own asyncRewake processes; without this, they all read the same JSON and
    # produce duplicate verdicts. The rename moves the snapshot aside so the
    # next PreToolUse hook starts a fresh JSON for the next turn.
    # The pid + timestamp suffix lets two near-simultaneous Stops both claim
    # without collision (only one wins the rename, the other gets ENOENT).
    src = session_file(sid)
    pending = AUDIT_DIR / f"{sid}.json.auditing-{os.getpid()}-{int(time.time())}"
    try:
        os.rename(src, pending)
    except FileNotFoundError:
        _stop_log(sid, "no audit file; another Stop hook already claimed it")
        return 0
    except OSError as e:
        _stop_log(sid, f"claim failed: {e}")
        return 0
    # Lock file is per-session; safe to leave for next turn's PreToolUse hooks.

    try:
        diff = render_diff_from_path(pending)
        if not diff:
            _stop_log(sid, "claimed JSON had no diffs; skipping audit")
            return 0

        _stop_log(sid, f"spawning audit subagent ({len(diff)} bytes diff)")

        env = {
            **os.environ,
            "CLAUDE_AUDIT_SUBAGENT": "1",
            "CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT": "1",
            "ENABLE_CLAUDEAI_MCP_SERVERS": "false",
            "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1",
        }

        try:
            result = subprocess.run(
                ["claude", "-p", diff,
                 "--agent", "audit-fresh-eye",
                 "--model", "sonnet",
                 "--permission-mode", "dontAsk",
                 "--max-budget-usd", "0.20",
                 "--output-format", "json",
                 "--disable-slash-commands",
                 "--exclude-dynamic-system-prompt-sections",
                 "--no-session-persistence"],
                cwd=cwd,
                env=env,
                capture_output=True,
                text=True,
                timeout=240,
            )
        except FileNotFoundError:
            _stop_log(sid, "claude CLI not found on PATH")
            return 0
        except subprocess.TimeoutExpired:
            _stop_log(sid, "subagent timed out")
            return 0
        except Exception as e:
            _stop_log(sid, f"subagent failed: {type(e).__name__}: {e}")
            return 0

        raw_stdout = (result.stdout or "").strip()
        verdict = raw_stdout
        try:
            payload = json.loads(raw_stdout)
            verdict = (payload.get("result") or "").strip()
            usage = payload.get("usage") or {}
            inp = usage.get("input_tokens", 0)
            out = usage.get("output_tokens", 0)
            cache_read = usage.get("cache_read_input_tokens", 0)
            cache_create = usage.get("cache_creation_input_tokens", 0)
            cost = payload.get("total_cost_usd") or payload.get("cost_usd")
            _stop_log(
                sid,
                f"usage: in={inp} out={out} cache_read={cache_read} "
                f"cache_create={cache_create} cost={cost}"
            )
        except (json.JSONDecodeError, ValueError, AttributeError):
            _stop_log(sid, "stdout was not JSON; treating as raw text verdict")
        _stop_log(sid, f"verdict: {verdict[:500]!r}")

        status, issues = _parse_verdict(verdict)
        if status != "FIXES" or not issues:
            return 0

        print(_render_fixes(issues), file=sys.stderr)
        return 2
    finally:
        try:
            pending.unlink(missing_ok=True)
        except OSError:
            pass


def cmd_list() -> int:
    if not AUDIT_DIR.exists():
        return 0
    rows = []
    for p in AUDIT_DIR.glob("*.json"):
        try:
            data = json.loads(p.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        n = len(data.get("files") or {})
        rows.append((p.stat().st_mtime, p.stem, n))
    for mtime, sid, n in sorted(rows):
        ts = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(mtime))
        print(f"{sid}\t{n} files\t{ts}")
    return 0


# ---------- entry ----------

def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("hook", help="PreToolUse hook (reads JSON on stdin)")
    sub.add_parser("stop-hook", help="Stop hook (reads JSON on stdin, always exits 0)")
    s = sub.add_parser("show", help="Show diff of recorded session")
    s.add_argument("session_id", nargs="?", help="default: most recent")
    s.add_argument("-U", "--context", type=int, default=3, help="diff context lines (default 3)")
    s.add_argument("--no-color", action="store_true")
    sub.add_parser("list", help="List recorded sessions")
    args = p.parse_args()

    if args.cmd == "hook":
        try:
            return cmd_hook()
        except Exception:
            return 0  # never block tool calls
    if args.cmd == "stop-hook":
        try:
            return cmd_stop_hook()
        except Exception:
            return 0  # never block stop
    if args.cmd == "show":
        color = (not args.no_color) and sys.stdout.isatty()
        return cmd_show(args.session_id, args.context, color)
    if args.cmd == "list":
        return cmd_list()
    return 0


if __name__ == "__main__":
    sys.exit(main())
