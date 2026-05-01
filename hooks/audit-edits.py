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
import calendar
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
CODEX_PROMPT_FILE = Path(__file__).parent / "audit-fresh-eye-codex.md"


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

    # /tmp paths are typically one-off scripts (smoke tests, scratch files,
    # downloaded artifacts) not worth long-term audit attention. The
    # AUDIT_DIR exclusion below this is now subsumed but kept for clarity.
    if abs_path.startswith("/tmp/"):
        return 0
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
    grouped by file, ordered as the subagent emitted them. When issues carry
    a 'source' field (multi-reviewer mode), the source is shown per line and
    a note about possible overlap is added to the preamble."""
    sources = {it["source"] for it in issues if it.get("source")}
    multi = len(sources) > 1
    preamble = (
        "Suggestions from a fresh-eye audit of this turn's edits. The auditor "
        "sees the diff and can Read/Grep the repo, but not the conversation "
        "or the user's intent — treat each item as a hypothesis to verify, "
        "not a mandatory fix. Apply genuine issues, dismiss false positives."
    )
    if multi:
        preamble += (
            " Findings come from two independent reviewers and may overlap "
            "or duplicate; dedup at your discretion."
        )
    out: list[str] = [preamble, "", "FIXES:"]
    last_file: str | None = None
    for it in issues:
        if it["file"] != last_file:
            out.append(f"  {it['file']}:")
            last_file = it["file"]
        src = f" ({it['source']})" if multi and it.get("source") else ""
        out.append(f"    [{it['category']}]{src} {it['fix']}")
    return "\n".join(out)


def _stop_log(sid: str, msg: str) -> None:
    AUDIT_DIR.mkdir(parents=True, exist_ok=True)
    try:
        with open(AUDIT_DIR / f"{sid}.stop.log", "a") as f:
            f.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}\n")
    except OSError:
        pass


HISTORY_DIR = Path.home() / ".claude" / "audit-history"


def _slug(path: str) -> str:
    """Mirror ~/.claude/projects/ slug convention: replace '/' and '.' in the
    cwd with '-'. e.g. /home/ubuntu/.claude → -home-ubuntu--claude."""
    return path.replace("/", "-").replace(".", "-") or "unknown"


def _iso_now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _diff_stats(diff: str) -> tuple[int, int, int, list[dict]]:
    """Count totals + per-file breakdown from a unified diff produced by
    render_diff_from_path. Returns (files_changed, lines_added, lines_removed,
    files) where files is a list of {path, lines_added, lines_removed} dicts.

    Uses a small state machine: the area between 'diff --git' and the first
    '@@' hunk header is the file-header zone (mode/index/+++/--- lines, all
    skipped). Lines after '@@' are content. This means a content line that
    happens to start with '+++ ' or '--- ' is correctly counted as added/removed,
    not mistaken for a header."""
    files: list[dict] = []
    cur: dict | None = None
    in_hunk = False
    for line in diff.splitlines():
        if line.startswith("diff --git a/"):
            if cur:
                files.append(cur)
            # 'diff --git a/PATH b/PATH' — split on ' b/' (handles paths w/ spaces)
            rest = line[len("diff --git a/"):]
            sep = rest.find(" b/")
            path = rest[:sep] if sep > 0 else rest
            cur = {"path": path, "lines_added": 0, "lines_removed": 0}
            in_hunk = False
        elif line.startswith("@@"):
            in_hunk = True
        elif not in_hunk:
            continue  # mode/index/+++/--- in the file-header zone
        elif line.startswith("+"):
            if cur:
                cur["lines_added"] += 1
        elif line.startswith("-"):
            if cur:
                cur["lines_removed"] += 1
    if cur:
        files.append(cur)
    return (len(files),
            sum(f["lines_added"] for f in files),
            sum(f["lines_removed"] for f in files),
            files)


def _append_history(record: dict, cwd: str, sid: str) -> None:
    """Append one row to ~/.claude/audit-history/<slug>/<sid>.jsonl, where
    slug is derived from cwd (mirrors ~/.claude/projects/). Linux O_APPEND
    with sub-PIPE_BUF writes is kernel-atomic; failures are swallowed."""
    target = HISTORY_DIR / _slug(cwd or "unknown") / f"{sid or 'unknown'}.jsonl"
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("a") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
    except OSError as e:
        _stop_log(sid or "unknown", f"failed to append history: {e}")


def _write_result(sid: str, verdict: str, claude_n: int = 0,
                  codex_n: int = 0, reason: str | None = None) -> None:
    """Write the terminal-state marker read by `cmd_statusline` (which any
    statusLine renderer can call via `audit-edits.py statusline <sid>`).
    Atomic via tmp+os.replace so the renderer never reads a partial file.
    Schema is stable; readers consume .verdict / .claude_issues / .codex_issues."""
    AUDIT_DIR.mkdir(parents=True, exist_ok=True)
    target = AUDIT_DIR / f"{sid}.json.audit-result"
    tmp = AUDIT_DIR / f"{sid}.json.audit-result.tmp"
    payload = {
        "verdict": verdict,
        "claude_issues": claude_n,
        "codex_issues": codex_n,
        "failure_reason": reason,
    }
    try:
        tmp.write_text(json.dumps(payload, ensure_ascii=False))
        os.replace(tmp, target)
    except OSError as e:
        _stop_log(sid, f"failed to write audit-result: {e}")


def _spawn_audit_claude(
    diff: str, cwd: str, sid: str
) -> tuple[str | None, dict | None]:
    """Spawn `claude -p` with the audit-fresh-eye agent. Returns
    (verdict, usage) — verdict is the raw text ("CLEAN" / "FIXES\\n…") or
    None on failure; usage is a dict with tokens_in/out/cache_read/cache_create
    /cost_usd parsed from the --output-format json payload, or None when the
    payload is missing or unparseable."""
    env = {
        **os.environ,
        "CLAUDE_AUDIT_SUBAGENT": "1",
        "CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT": "1",
        "ENABLE_CLAUDEAI_MCP_SERVERS": "false",
        "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1",
    }
    model = os.environ.get("AUDIT_CLAUDE_MODEL", "sonnet")
    effort = os.environ.get("AUDIT_CLAUDE_EFFORT")
    cmd = ["claude", "-p", diff,
           "--agent", "audit-fresh-eye",
           "--model", model,
           "--permission-mode", "dontAsk",
           "--max-budget-usd", "0.30",
           "--output-format", "json",
           "--disable-slash-commands",
           "--exclude-dynamic-system-prompt-sections",
           "--no-session-persistence"]
    if effort:
        cmd += ["--effort", effort]
    _stop_log(sid, f"claude args: model={model} effort={effort or '<default>'}")
    try:
        result = subprocess.run(
            cmd, cwd=cwd, env=env, capture_output=True, text=True, timeout=240,
        )
    except FileNotFoundError:
        _stop_log(sid, "claude CLI not found on PATH")
        return None, None
    except subprocess.TimeoutExpired:
        _stop_log(sid, "claude audit timed out")
        return None, None
    except Exception as e:
        _stop_log(sid, f"claude audit failed: {type(e).__name__}: {e}")
        return None, None

    raw_stdout = (result.stdout or "").strip()
    verdict = raw_stdout
    usage_info: dict | None = None
    try:
        payload = json.loads(raw_stdout)
        verdict = (payload.get("result") or "").strip()
        usage = payload.get("usage") or {}
        cost = payload.get("total_cost_usd") or payload.get("cost_usd")
        usage_info = {
            "tokens_in": usage.get("input_tokens", 0),
            "tokens_out": usage.get("output_tokens", 0),
            "cache_read": usage.get("cache_read_input_tokens", 0),
            "cache_create": usage.get("cache_creation_input_tokens", 0),
            "cost_usd": cost,
        }
        _stop_log(
            sid,
            f"claude usage: in={usage_info['tokens_in']} "
            f"out={usage_info['tokens_out']} "
            f"cache_read={usage_info['cache_read']} "
            f"cache_create={usage_info['cache_create']} "
            f"cost={cost}"
        )
    except (json.JSONDecodeError, ValueError, AttributeError):
        _stop_log(sid, "claude stdout was not JSON; treating as raw text")
    return verdict, usage_info


def _spawn_audit_both(
    diff: str, cwd: str, sid: str
) -> tuple[str, list[dict], str | None, float, float, dict | None]:
    """Run both backends concurrently. Returns (status, issues, fail_reason,
    claude_dur_s, codex_dur_s, claude_usage) where each issue dict is tagged
    with 'source'. Status is 'FAILED' when both backends were unavailable OR
    when neither produced a parseable verdict (fail_reason distinguishes the
    two cases), 'FIXES' if either produced issues, else 'CLEAN'."""
    import concurrent.futures

    def timed_claude():
        t0 = time.monotonic()
        v, u = _spawn_audit_claude(diff, cwd, sid)
        return v, u, time.monotonic() - t0

    def timed_codex():
        t0 = time.monotonic()
        v = _spawn_audit_codex(diff, cwd, sid)
        return v, time.monotonic() - t0

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
        f_claude = ex.submit(timed_claude)
        f_codex = ex.submit(timed_codex)
        v_claude, claude_usage, claude_dur = f_claude.result()
        v_codex, codex_dur = f_codex.result()

    if v_claude is None and v_codex is None:
        return ("FAILED", [], "both backends unavailable",
                claude_dur, codex_dur, claude_usage)

    issues: list[dict] = []
    parseable = False
    for verdict, source in ((v_claude, "claude"), (v_codex, "codex")):
        if verdict is None:
            continue
        _stop_log(sid, f"{source} verdict: {verdict[:300]!r}")
        status, parsed = _parse_verdict(verdict)
        if status != "UNKNOWN":
            parseable = True
        for it in parsed:
            it["source"] = source
            issues.append(it)
    if not parseable:
        return ("FAILED", [], "no parseable verdict from either backend",
                claude_dur, codex_dur, claude_usage)
    return (("FIXES" if issues else "CLEAN"), issues, None,
            claude_dur, codex_dur, claude_usage)


def _spawn_audit_codex(diff: str, cwd: str, sid: str) -> str | None:
    """Spawn `codex exec` as a fresh-eye auditor. Returns the raw verdict
    text (e.g. "CLEAN" or "FIXES\\n...") or None on failure."""
    try:
        prompt_body = CODEX_PROMPT_FILE.read_text()
    except OSError as e:
        _stop_log(sid, f"codex prompt file unreadable: {e}")
        return None

    out_file = AUDIT_DIR / f"{sid}.codex.out"
    out_file.unlink(missing_ok=True)

    env = {**os.environ, "CODEX_AUDIT_SUBAGENT": "1"}
    prompt = f"{prompt_body}\n\n---\n\n{diff}"

    cmd = ["codex", "exec",
           "--ephemeral",
           "--skip-git-repo-check",
           "--ignore-rules",
           "-s", "read-only",
           "-C", cwd,
           "-o", str(out_file)]
    model = os.environ.get("AUDIT_CODEX_MODEL")
    if model:
        cmd += ["-m", model]
    effort = os.environ.get("AUDIT_CODEX_EFFORT")
    if effort:
        cmd += ["-c", f"model_reasoning_effort={effort}"]
    cmd.append(prompt)
    _stop_log(sid, f"codex args: model={model or '<config>'} effort={effort or '<config>'}")

    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            env=env,
            capture_output=True,
            text=True,
            timeout=240,
        )
    except FileNotFoundError:
        _stop_log(sid, "codex CLI not found on PATH")
        return None
    except subprocess.TimeoutExpired:
        _stop_log(sid, "codex audit timed out")
        return None
    except Exception as e:
        _stop_log(sid, f"codex audit failed: {type(e).__name__}: {e}")
        return None

    _stop_log(sid, f"codex exit={result.returncode}")
    if not out_file.exists():
        _stop_log(sid, "codex produced no -o output file")
        return None
    try:
        verdict = out_file.read_text().strip()
    except OSError as e:
        _stop_log(sid, f"failed to read codex output: {e}")
        return None
    finally:
        out_file.unlink(missing_ok=True)
    return verdict


def cmd_stop_hook() -> int:
    """Stop hook handler. Spawns a fresh-eye audit subagent over the diff of
    files edited this turn. asyncRewake-compatible:
        exit 0 → silent
        exit 2 → wakes Claude with stderr (the verdict) as a system reminder.
    Recursion guard via CLAUDE_AUDIT_SUBAGENT / CODEX_AUDIT_SUBAGENT env var.
    Backend selected by AUDIT_BACKEND={claude,codex,both}; defaults to claude."""
    if os.environ.get("CLAUDE_AUDIT_SUBAGENT") == "1":
        return 0
    if os.environ.get("CODEX_AUDIT_SUBAGENT") == "1":
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
            return 0  # no audit ran; leave any prior result-marker alone

        backend = os.environ.get("AUDIT_BACKEND", "claude").lower()
        _stop_log(sid, f"spawning audit ({backend}, {len(diff)} bytes diff)")

        files_changed, lines_added, lines_removed, files_list = _diff_stats(diff)
        started_at = _iso_now()
        claude_dur: float | None = None
        codex_dur: float | None = None
        claude_usage: dict | None = None
        claude_list: list[dict] = []
        codex_list: list[dict] = []

        def write_row(verdict_label: str, c_n: int, x_n: int,
                      reason: str | None) -> None:
            row = {
                "session_id": sid,
                "started_at": started_at,
                "completed_at": _iso_now(),
                "backend": backend,
                "claude_model": os.environ.get("AUDIT_CLAUDE_MODEL", "sonnet"),
                "claude_effort": os.environ.get("AUDIT_CLAUDE_EFFORT"),
                "codex_model": os.environ.get("AUDIT_CODEX_MODEL"),
                "codex_effort": os.environ.get("AUDIT_CODEX_EFFORT"),
                "diff_bytes": len(diff),
                "files_changed": files_changed,
                "lines_added": lines_added,
                "lines_removed": lines_removed,
                "files": files_list,
                "verdict": verdict_label,
                "claude_dur_s": round(claude_dur, 2) if claude_dur is not None else None,
                "codex_dur_s": round(codex_dur, 2) if codex_dur is not None else None,
                "claude_issues": c_n,
                "codex_issues": x_n,
                "claude_issues_list": claude_list,
                "codex_issues_list": codex_list,
                "claude_cost_usd": claude_usage.get("cost_usd") if claude_usage else None,
                "claude_tokens_in": claude_usage.get("tokens_in") if claude_usage else None,
                "claude_tokens_out": claude_usage.get("tokens_out") if claude_usage else None,
                "claude_cache_read": claude_usage.get("cache_read") if claude_usage else None,
                "claude_cache_create": claude_usage.get("cache_create") if claude_usage else None,
                "failure_reason": reason,
            }
            _append_history(row, cwd, sid)

        if backend == "both":
            (status, issues, fail_reason,
             claude_dur, codex_dur, claude_usage) = _spawn_audit_both(diff, cwd, sid)
            if status == "FAILED":
                _write_result(sid, "failed", reason=fail_reason)
                write_row("failed", 0, 0, fail_reason)
                return 0
        elif backend == "codex":
            t0 = time.monotonic()
            verdict = _spawn_audit_codex(diff, cwd, sid)
            codex_dur = time.monotonic() - t0
            used_source = "codex"
            if verdict is None:
                _stop_log(sid, "codex unavailable; falling back to claude")
                t1 = time.monotonic()
                verdict, claude_usage = _spawn_audit_claude(diff, cwd, sid)
                claude_dur = time.monotonic() - t1
                used_source = "claude"
                if verdict is None:
                    reason = "codex and claude unavailable"
                    _write_result(sid, "failed", reason=reason)
                    write_row("failed", 0, 0, reason)
                    return 0
            _stop_log(sid, f"verdict: {verdict[:500]!r}")
            status, issues = _parse_verdict(verdict)
            if status == "UNKNOWN":
                reason = "verdict could not be parsed"
                _write_result(sid, "failed", reason=reason)
                write_row("failed", 0, 0, reason)
                return 0
            for it in issues:
                it.setdefault("source", used_source)
        else:
            t0 = time.monotonic()
            verdict, claude_usage = _spawn_audit_claude(diff, cwd, sid)
            claude_dur = time.monotonic() - t0
            if verdict is None:
                reason = "claude unavailable"
                _write_result(sid, "failed", reason=reason)
                write_row("failed", 0, 0, reason)
                return 0
            _stop_log(sid, f"verdict: {verdict[:500]!r}")
            status, issues = _parse_verdict(verdict)
            if status == "UNKNOWN":
                reason = "verdict could not be parsed"
                _write_result(sid, "failed", reason=reason)
                write_row("failed", 0, 0, reason)
                return 0
            for it in issues:
                it.setdefault("source", "claude")

        claude_n = sum(1 for it in issues if it.get("source") == "claude")
        codex_n = sum(1 for it in issues if it.get("source") == "codex")
        claude_list = [
            {"file": it.get("file"), "category": it.get("category"),
             "fix": it.get("fix")}
            for it in issues if it.get("source") == "claude"
        ]
        codex_list = [
            {"file": it.get("file"), "category": it.get("category"),
             "fix": it.get("fix")}
            for it in issues if it.get("source") == "codex"
        ]

        if status != "FIXES" or not issues:
            _write_result(sid, "clean")
            write_row("clean", claude_n, codex_n, None)
            return 0

        _write_result(sid, "fixes", claude_n=claude_n, codex_n=codex_n)
        write_row("fixes", claude_n, codex_n, None)
        print(_render_fixes(issues), file=sys.stderr)
        return 2
    finally:
        try:
            pending.unlink(missing_ok=True)
        except OSError:
            pass


def cmd_statusline(session_id: str, color: bool = True) -> int:
    """Render the audit segment for a session_id, or empty string. Includes
    leading whitespace so callers can plain-concat. Mirrors the priority order
    in the original statusline.sh: in-flight marker > result marker (TTL'd)
    > nothing. Self-heals stale auditing-markers (dead pid or age > 600s).

    TTLs: clean 60s, fixes 300s, failed 60s.
    """
    if not session_id:
        return 0

    if color:
        RED = "\033[31m"
        GREEN = "\033[32m"
        YELLOW = "\033[33m"
        CYAN = "\033[36m"
        RESET = "\033[0m"
    else:
        RED = GREEN = YELLOW = CYAN = RESET = ""

    now = int(time.time())

    # 1. In-flight marker
    for f in sorted(AUDIT_DIR.glob(f"{session_id}.json.auditing-*")):
        suffix = f.name[len(f"{session_id}.json.auditing-"):]
        try:
            pid_str, ts_str = suffix.rsplit("-", 1)
            pid, ts = int(pid_str), int(ts_str)
        except ValueError:
            continue
        elapsed = now - ts
        if elapsed > 600:
            try:
                f.unlink()
            except OSError:
                pass
            continue
        try:
            os.kill(pid, 0)
        except (ProcessLookupError, PermissionError, OSError):
            try:
                f.unlink()
            except OSError:
                pass
            continue
        sys.stdout.write(f"  {CYAN}auditing… {elapsed}s{RESET}")
        return 0

    # 2. Result marker
    result_file = AUDIT_DIR / f"{session_id}.json.audit-result"
    if not result_file.exists():
        return 0
    try:
        mtime = int(result_file.stat().st_mtime)
        data = json.loads(result_file.read_text())
    except (OSError, json.JSONDecodeError):
        return 0
    age = now - mtime
    verdict = data.get("verdict")
    if verdict == "clean" and age <= 60:
        sys.stdout.write(f"  {GREEN}audit ✓{RESET}")
    elif verdict == "fixes" and age <= 300:
        c = data.get("claude_issues") or 0
        x = data.get("codex_issues") or 0
        parts = []
        if c > 0:
            parts.append(f"claude:{c}")
        if x > 0:
            parts.append(f"codex:{x}")
        tail = f" {' '.join(parts)}" if parts else ""
        sys.stdout.write(f"  {YELLOW}audit ⚠{tail}{RESET}")
    elif verdict == "failed" and age <= 60:
        sys.stdout.write(f"  {RED}audit ✗{RESET}")
    return 0


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


def cmd_stats(days: int | None, last: int,
              top_files: int = 5, min_audits: int = 3,
              slug: str | None = None) -> int:
    """Aggregate ~/.claude/audit-history/<slug>/<sid>.jsonl files. Walks the
    directory tree, sorts rows chronologically, and skips malformed lines
    silently (a torn last line from a crashed write is normal).

    --slug accepts either a path ('/home/ubuntu/.claude') or a slug fragment
    ('claude', '-home-ubuntu--claude'); inputs are normalized via _slug() then
    substring-matched against folder names so both forms work."""
    from statistics import mean, median

    if not HISTORY_DIR.exists():
        print(f"No audit history at {HISTORY_DIR}.", file=sys.stderr)
        return 1

    cutoff: float | None = None
    if days is not None:
        cutoff = time.time() - days * 86400

    # Normalize the --slug input so users can pass either path-form or slug-form.
    slug_needle = _slug(slug) if slug else None

    rows: list[dict] = []
    for jsonl in sorted(HISTORY_DIR.rglob("*.jsonl")):
        if slug_needle and slug_needle not in jsonl.parent.name:
            continue
        try:
            content = jsonl.read_text()
        except OSError:
            continue
        for line in content.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except json.JSONDecodeError:
                continue
            if cutoff is not None:
                # started_at is in UTC via time.gmtime(); compare as UTC.
                try:
                    started = calendar.timegm(time.strptime(
                        r["started_at"], "%Y-%m-%dT%H:%M:%SZ"))
                except (KeyError, ValueError):
                    continue
                if started < cutoff:
                    continue
            rows.append(r)
    # Rows from rglob are walk-ordered; sort chronologically for "Last N runs".
    rows.sort(key=lambda r: r.get("started_at") or "")

    if not rows:
        print("No audit rows in history.")
        return 0

    n = len(rows)
    parts = []
    if days:
        parts.append(f"last {days}d")
    if slug_needle:
        parts.append(f"slug~{slug_needle!r}")
    label = (", " + ", ".join(parts)) if parts else ""
    print(f"=== audit history (n={n}{label}) ===\n")

    # --- Verdict mix ---------------------------------------------------------
    verdict_counts: dict[str, int] = {}
    for r in rows:
        v = r.get("verdict") or "?"
        verdict_counts[v] = verdict_counts.get(v, 0) + 1
    print("Verdicts:")
    for v in ("clean", "fixes", "failed"):
        c = verdict_counts.get(v, 0)
        if c:
            print(f"  {v:7s} {c:5d}  ({c / n * 100:5.1f}%)")
    print()

    def pctile(values: list[float], p: int) -> float:
        s = sorted(values)
        k = max(0, min(len(s) - 1, int(p / 100 * len(s))))
        return s[k]

    def fmt_row(name: str, vals: list[float]) -> str:
        if not vals:
            return f"  {name:24s}     n=0"
        return (f"  {name:24s}  n={len(vals):4d}  "
                f"p50={pctile(vals, 50):5.0f}s  "
                f"p90={pctile(vals, 90):5.0f}s  "
                f"max={max(vals):5.0f}s  mean={mean(vals):5.0f}s")

    # --- Per-backend latency overall ----------------------------------------
    claude_durs = [r["claude_dur_s"] for r in rows
                   if r.get("claude_dur_s") is not None]
    codex_durs = [r["codex_dur_s"] for r in rows
                  if r.get("codex_dur_s") is not None]
    print("Per-backend latency:")
    print(fmt_row("claude", claude_durs))
    print(fmt_row("codex", codex_durs))
    print()

    # --- Latency grouped by (backend, model, effort) ------------------------
    groups: dict[tuple[str, str, str], list[float]] = {}
    for r in rows:
        if r.get("claude_dur_s") is not None:
            key = ("claude", r.get("claude_model") or "?",
                   r.get("claude_effort") or "default")
            groups.setdefault(key, []).append(r["claude_dur_s"])
        if r.get("codex_dur_s") is not None:
            key = ("codex", r.get("codex_model") or "?",
                   r.get("codex_effort") or "default")
            groups.setdefault(key, []).append(r["codex_dur_s"])
    if len(groups) > 2:
        print("Latency by (backend, model, effort):")
        for key in sorted(groups):
            print(fmt_row(f"{key[0]}/{key[1]}/{key[2]}", groups[key]))
        print()

    # --- 'both'-mode head-to-head + agreement contingency -------------------
    both = [r for r in rows
            if r.get("backend") == "both"
            and r.get("claude_dur_s") is not None
            and r.get("codex_dur_s") is not None]
    if both:
        c_wins = sum(1 for r in both if r["claude_dur_s"] < r["codex_dur_s"])
        x_wins = sum(1 for r in both if r["codex_dur_s"] < r["claude_dur_s"])
        deltas = [r["claude_dur_s"] - r["codex_dur_s"] for r in both]
        print(f"'both' mode latency head-to-head (n={len(both)}):")
        print(f"  codex faster:  {x_wins:4d}  ({x_wins / len(both) * 100:.0f}%)")
        print(f"  claude faster: {c_wins:4d}  ({c_wins / len(both) * 100:.0f}%)")
        print(f"  median delta:  claude {median(deltas):+.0f}s vs codex")
        print()

        # Issue-detection 2x2 contingency over both-mode runs (excl. failed)
        bm = [r for r in both if (r.get("verdict") or "") != "failed"]
        if bm:
            both_flag = sum(
                1 for r in bm
                if (r.get("claude_issues") or 0) > 0
                and (r.get("codex_issues") or 0) > 0)
            claude_only = sum(
                1 for r in bm
                if (r.get("claude_issues") or 0) > 0
                and (r.get("codex_issues") or 0) == 0)
            codex_only = sum(
                1 for r in bm
                if (r.get("claude_issues") or 0) == 0
                and (r.get("codex_issues") or 0) > 0)
            both_clean = len(bm) - both_flag - claude_only - codex_only

            cf = both_flag + claude_only  # claude flagged
            xf = both_flag + codex_only   # codex flagged
            print(f"Issue-detection in 'both' mode (n={len(bm)}, excl. failed):")
            print(f"  both flagged:       {both_flag:4d}  "
                  f"({both_flag / len(bm) * 100:.0f}%)")
            print(f"  claude only:        {claude_only:4d}  "
                  f"({claude_only / len(bm) * 100:.0f}%)  "
                  f"← codex missed")
            print(f"  codex only:         {codex_only:4d}  "
                  f"({codex_only / len(bm) * 100:.0f}%)  "
                  f"← claude missed")
            print(f"  both clean:         {both_clean:4d}  "
                  f"({both_clean / len(bm) * 100:.0f}%)")
            print(f"  flag rate — claude: {cf / len(bm) * 100:5.1f}%   "
                  f"codex: {xf / len(bm) * 100:5.1f}%")

            # Cohen's kappa: agreement beyond chance
            po = (both_flag + both_clean) / len(bm)
            pc = cf / len(bm)
            px = xf / len(bm)
            pe = pc * px + (1 - pc) * (1 - px)
            kappa = (po - pe) / (1 - pe) if pe < 1 else 0
            print(f"  Cohen's κ:          {kappa:+.2f}  "
                  f"(0=chance, 1=perfect, <0=worse than chance)")

            # Mean issues per flagged run (per backend)
            cf_issues = [r["claude_issues"] for r in bm
                         if (r.get("claude_issues") or 0) > 0]
            xf_issues = [r["codex_issues"] for r in bm
                         if (r.get("codex_issues") or 0) > 0]
            if cf_issues:
                print(f"  mean issues/flagged: claude {mean(cf_issues):.1f}   "
                      f"codex {mean(xf_issues) if xf_issues else 0:.1f}")
            print()

        # Issue-grain overlap (Jaccard) over both-mode FIXES runs that have
        # persisted issue lists. Older rows without lists are silently skipped.
        jacc_fc: list[float] = []
        jacc_f: list[float] = []
        for r in bm:
            cl = r.get("claude_issues_list") or []
            xl = r.get("codex_issues_list") or []
            if not cl and not xl:
                continue
            c_set = {(i.get("file"), i.get("category")) for i in cl}
            x_set = {(i.get("file"), i.get("category")) for i in xl}
            union_fc = c_set | x_set
            if union_fc:
                jacc_fc.append(len(c_set & x_set) / len(union_fc))
            cf_set = {i.get("file") for i in cl}
            xf_set = {i.get("file") for i in xl}
            union_f = cf_set | xf_set
            if union_f:
                jacc_f.append(len(cf_set & xf_set) / len(union_f))
        if jacc_fc:
            print(f"Issue-grain overlap (n={len(jacc_fc)} runs with issues):")
            print(f"  Jaccard@(file,category): mean {mean(jacc_fc):.2f}  "
                  f"med {median(jacc_fc):.2f}")
            print(f"  Jaccard@file:            mean {mean(jacc_f):.2f}  "
                  f"med {median(jacc_f):.2f}")
            print()

    # --- Cost ----------------------------------------------------------------
    costs = [r["claude_cost_usd"] for r in rows
             if r.get("claude_cost_usd") is not None]
    if costs:
        print(f"Claude cost (n={len(costs)}):  total ${sum(costs):.2f}   "
              f"mean ${mean(costs):.4f}/run   max ${max(costs):.4f}")
        print()

    # --- Top files by issue count -------------------------------------------
    # Skip rows with verdict 'failed' (no real audit signal). Match issue paths
    # to files[].path after lstrip('/') normalization (renderer drops leading /
    # but issue strings keep it).
    def _norm(p: str | None) -> str:
        return (p or "").lstrip("/")

    file_stats: dict[str, dict] = {}
    for r in rows:
        if (r.get("verdict") or "") == "failed":
            continue
        files_in_row = r.get("files") or []
        if not files_in_row:
            continue
        # Pre-issue-list-schema rows can't attribute issues per file; skip
        # them so they don't inflate `audited` while contributing zero flags.
        # New rows always carry both keys (possibly as []), so absence = legacy.
        if "claude_issues_list" not in r and "codex_issues_list" not in r:
            continue
        cl = r.get("claude_issues_list") or []
        xl = r.get("codex_issues_list") or []
        c_flagged = {_norm(i.get("file")) for i in cl}
        x_flagged = {_norm(i.get("file")) for i in xl}
        c_per_file: dict[str, int] = {}
        for i in cl:
            f = _norm(i.get("file"))
            c_per_file[f] = c_per_file.get(f, 0) + 1
        x_per_file: dict[str, int] = {}
        for i in xl:
            f = _norm(i.get("file"))
            x_per_file[f] = x_per_file.get(f, 0) + 1
        for fd in files_in_row:
            path = fd.get("path")
            if not path:
                continue
            s = file_stats.setdefault(path, {
                "audited": 0,
                "c_flag_runs": 0, "c_iss": 0,
                "x_flag_runs": 0, "x_iss": 0,
            })
            s["audited"] += 1
            if path in c_flagged:
                s["c_flag_runs"] += 1
            s["c_iss"] += c_per_file.get(path, 0)
            if path in x_flagged:
                s["x_flag_runs"] += 1
            s["x_iss"] += x_per_file.get(path, 0)

    eligible = [(p, s) for p, s in file_stats.items()
                if s["audited"] >= min_audits]
    if eligible:
        eligible.sort(key=lambda kv: kv[1]["c_iss"] + kv[1]["x_iss"], reverse=True)
        shown = eligible[:top_files]
        print(f"Top files by issue count (≥{min_audits} audits, top {len(shown)}):")
        print(f"  {'audits':>6}  {'c_flag':>9}  {'c_iss':>5}  "
              f"{'x_flag':>9}  {'x_iss':>5}  {'total':>5}  path")
        for path, s in shown:
            a = s["audited"]
            cfr = f"{s['c_flag_runs']}({s['c_flag_runs'] / a * 100:.0f}%)"
            xfr = f"{s['x_flag_runs']}({s['x_flag_runs'] / a * 100:.0f}%)"
            total = s["c_iss"] + s["x_iss"]
            print(f"  {a:>6}  {cfr:>9}  {s['c_iss']:>5}  "
                  f"{xfr:>9}  {s['x_iss']:>5}  {total:>5}  {path}")
        print()

    # --- Recent runs ---------------------------------------------------------
    show = min(last, n)
    print(f"Last {show} runs:")
    for r in rows[-last:]:
        ts = (r.get("started_at") or "?")[:16].replace("T", " ")
        backend = r.get("backend") or "?"
        v = r.get("verdict") or "?"
        c = r.get("claude_dur_s")
        x = r.get("codex_dur_s")
        c_s = f"c={c:>3.0f}s" if c is not None else "c=  - "
        x_s = f"x={x:>3.0f}s" if x is not None else "x=  - "
        files = r.get("files_changed") or 0
        plus = r.get("lines_added") or 0
        minus = r.get("lines_removed") or 0
        ci = r.get("claude_issues") or 0
        xi = r.get("codex_issues") or 0
        print(f"  {ts}  {backend:5s}  {v:6s}  {c_s}  {x_s}  "
              f"{files}f +{plus}/-{minus}  c{ci}/x{xi}")
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
    sl = sub.add_parser("statusline",
                        help="Print audit segment for a session ID")
    sl.add_argument("session_id", help="session ID to look up audit state for")
    sl.add_argument("--no-color", action="store_true")
    st = sub.add_parser("stats", help="Aggregate audit history")
    st.add_argument("--days", type=int, default=None,
                    help="filter to last N days (default: all-time)")
    st.add_argument("--last", type=int, default=10,
                    help="show N most-recent runs (default 10)")
    st.add_argument("--top-files", type=int, default=5,
                    help="show top N files by issue count (default 5)")
    st.add_argument("--min-audits", type=int, default=3,
                    help="min audits per file to be eligible (default 3)")
    st.add_argument("--slug", default=None,
                    help="filter to slugs containing this fragment "
                         "(accepts paths like '/home/ubuntu/.claude' or "
                         "fragments like 'claude' or '-home-ubuntu--claude')")
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
    if args.cmd == "statusline":
        return cmd_statusline(args.session_id, color=not args.no_color)
    if args.cmd == "stats":
        return cmd_stats(days=args.days, last=args.last,
                         top_files=args.top_files,
                         min_audits=args.min_audits,
                         slug=args.slug)
    return 0


if __name__ == "__main__":
    sys.exit(main())
