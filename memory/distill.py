#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""filter noisy JSONL transcripts to a signal-only per-session corpus suitable for LLM distillation."""

from __future__ import annotations

import datetime as dt
import json
import re
from collections import defaultdict
from pathlib import Path

PROJECTS = Path.home() / ".claude" / "projects"
OUT_DIR = Path.home() / ".claude" / "memory" / "distilled"
HISTORY = Path.home() / ".claude" / "memory" / "distill-history.md"
LOCAL_TZ = dt.timezone(dt.timedelta(hours=8))  # user lives in UTC+8
HISTORY_LINE_RE = re.compile(r"^- (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}[+-]\d{2}:\d{2})")
SYSTEM_REMINDER_RE = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)
COMMAND_TAG_RE = re.compile(r"<(command-name|command-message|command-args|local-command-stdout|local-command-caveat|task-notification)>.*?</\1>", re.S)
CACHE_TICK_RE = re.compile(r"^Cache keep-alive\. Idle tick \d+/\d+\.\s*$")
AUTONOMOUS_RE = re.compile(r"<<autonomous-loop(?:-dynamic)?>>")
STOP_HOOK_PREFIX = "Stop hook feedback:"
API_ERROR_PREFIX = "API Error"


def clean_user_text(s: str) -> str:
    s = SYSTEM_REMINDER_RE.sub("", s)
    s = COMMAND_TAG_RE.sub("", s)
    s = AUTONOMOUS_RE.sub("", s)
    s = s.strip()
    if CACHE_TICK_RE.match(s):
        return ""
    if s.startswith(STOP_HOOK_PREFIX):
        return ""
    return s


def extract_assistant_text(content) -> str:
    if isinstance(content, str):
        text = content.strip()
    elif isinstance(content, list):
        parts = []
        for block in content:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "text":
                parts.append(block.get("text", ""))
        text = "\n".join(p for p in parts if p).strip()
    else:
        return ""
    if text.startswith(API_ERROR_PREFIX):
        return ""
    return text


def _ts_to_seconds(ts: str) -> str:
    """Strip fractional seconds so lexical compare against second-precision cutoff_z stays correct."""
    return ts.split(".", 1)[0] + "Z" if "." in ts else ts


def process(jsonl_path: Path, cutoff_z: str | None) -> dict | None:
    """Distill one transcript file. `cutoff_z` is a seconds-precision UTC 'Z'
    string (e.g. '2026-05-06T07:24:00Z'); when set, only messages with
    timestamp >= cutoff_z are kept. Transcript timestamps are millisecond-
    precision UTC 'Z'; we trim fractional digits before lexical compare."""
    turns: list[dict] = []  # ordered {role, ts, text} for in-slice events
    cwd = None
    git_branch = None
    started = None  # first ts within the slice (or whole session if no slice)
    ended = None
    session_started = None  # first ts overall (for carryover detection)
    session_ended = None
    total_user = 0  # whole-session count, regardless of slice

    try:
        with jsonl_path.open() as f:
            for line in f:
                try:
                    ev = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if ev.get("isSidechain"):
                    continue  # sub-agent traces; not the user's voice
                t = ev.get("type")
                ts = ev.get("timestamp") or ""
                if ts:
                    session_started = session_started or ts
                    session_ended = ts
                in_slice = (not cutoff_z) or (_ts_to_seconds(ts) >= cutoff_z)
                if t == "user":
                    msg = ev.get("message") or {}
                    content = msg.get("content")
                    if isinstance(content, str):
                        cleaned = clean_user_text(content)
                        if cleaned and len(cleaned) > 3:
                            total_user += 1
                            if in_slice:
                                turns.append({"role": "user", "ts": ts, "text": cleaned})
                                started = started or ts
                                ended = ts
                elif t == "assistant":
                    if in_slice:
                        msg = ev.get("message") or {}
                        text = extract_assistant_text(msg.get("content"))
                        if text:
                            turns.append({"role": "assistant", "ts": ts, "text": text})
                            started = started or ts
                            ended = ts
                if cwd is None and ev.get("cwd"):
                    cwd = ev["cwd"]
                if git_branch is None and ev.get("gitBranch"):
                    git_branch = ev["gitBranch"]
    except OSError:
        return None

    n_user = sum(1 for x in turns if x["role"] == "user")
    n_asst = sum(1 for x in turns if x["role"] == "assistant")
    if n_user == 0:
        return None

    is_carryover = bool(cutoff_z) and bool(session_started) and (_ts_to_seconds(session_started) < cutoff_z)

    return {
        "session": jsonl_path.stem,
        "cwd": cwd,
        "branch": git_branch,
        "started": started,
        "ended": ended,
        "session_started": session_started,
        "session_ended": session_ended,
        "is_carryover": is_carryover,
        "n_user": n_user,
        "n_asst": n_asst,
        "n_user_total": total_user,
        "turns": turns,
        "raw_bytes": jsonl_path.stat().st_size,
    }


def _last_run_anchor() -> str | None:
    """Return the full ISO timestamp of the most recent distill-history entry, or None."""
    if not HISTORY.exists():
        return None
    last = None
    for line in HISTORY.read_text().splitlines():
        m = HISTORY_LINE_RE.match(line)
        if m:
            last = m.group(1)
    return last


def _to_utc_compare(iso_str: str) -> str:
    """Normalize any ISO-8601 timestamp to seconds-precision UTC 'Z' for lexical compare against transcript ts."""
    s = iso_str.replace("Z", "+00:00")
    return dt.datetime.fromisoformat(s).astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _append_history(since_iso: str | None, n_sessions: int, n_projects: int, raw_bytes: int, distilled_bytes: int) -> None:
    now = dt.datetime.now(LOCAL_TZ).isoformat(timespec="minutes")
    since_str = f"since {since_iso}" if since_iso else "full"
    line = (
        f"- {now} — {since_str} — "
        f"{n_sessions} sessions / {n_projects} projects / "
        f"{raw_bytes/1e6:.1f} MB raw → {distilled_bytes/1e6:.2f} MB distilled\n"
    )
    if not HISTORY.exists():
        HISTORY.write_text("# Distill history\n\n" + line)
    else:
        with HISTORY.open("a") as f:
            f.write(line)


def main(since_iso: str | None, project_filters: list[str]) -> None:
    if since_iso is None:
        since_iso = _last_run_anchor()
        if since_iso:
            print(f"(default --since {since_iso} from distill-history.md)")
        else:
            print("(no distill-history.md; doing full distill)")
    elif "T" not in since_iso:  # bare YYYY-MM-DD → local midnight
        since_iso = dt.datetime.fromisoformat(since_iso).replace(tzinfo=LOCAL_TZ).isoformat(timespec="minutes")
    cutoff_z = _to_utc_compare(since_iso) if since_iso else None
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    project_dirs = [p for p in sorted(PROJECTS.iterdir()) if p.is_dir()] if PROJECTS.is_dir() else []
    if project_filters:
        project_dirs = [p for p in project_dirs if any(f in p.name for f in project_filters)]
    files = sorted(f for pd in project_dirs for f in pd.glob("*.jsonl"))
    if since_iso:
        files = [f for f in files if f.stat().st_mtime >= _mtime_floor(since_iso)]

    by_cwd: dict[str, list[dict]] = defaultdict(list)
    raw_total = 0
    distilled_total = 0
    n_sessions = 0

    for f in files:
        if f.name.startswith("agent-"):
            continue  # subagent files; their content is also in parent
        rec = process(f, cutoff_z)
        if not rec:
            continue
        n_sessions += 1
        raw_total += rec["raw_bytes"]
        distilled_total += sum(len(t["text"]) for t in rec["turns"])
        by_cwd[rec["cwd"] or "<unknown>"].append(rec)

    # Write per-cwd corpora as both jsonl (machine) and md (human)
    for cwd, recs in by_cwd.items():
        slug = cwd.strip("/").replace("/", "_") or "root"
        with (OUT_DIR / f"{slug}.jsonl").open("w") as wf:
            for r in recs:
                wf.write(json.dumps(r, ensure_ascii=False) + "\n")
        with (OUT_DIR / f"{slug}.md").open("w") as wf:
            wf.write(_render_md(cwd, recs))

    print(f"sessions:    {n_sessions}")
    print(f"projects:    {len(by_cwd)}")
    print(f"raw bytes:   {raw_total:>12,}  ({raw_total/1e6:.1f} MB)")
    print(f"distilled:   {distilled_total:>12,}  ({distilled_total/1e6:.2f} MB)")
    if raw_total:
        print(f"compression: {distilled_total/raw_total*100:.1f}% of raw")
    print(f"output:      {OUT_DIR}/")
    print()
    print("top projects by session count:")
    for cwd, recs in sorted(by_cwd.items(), key=lambda kv: -len(kv[1]))[:10]:
        u = sum(r["n_user"] for r in recs)
        print(f"  {len(recs):>4} sessions  {u:>5} prompts  {cwd}")

    _append_history(since_iso, n_sessions, len(by_cwd), raw_total, distilled_total)


def _render_md(cwd: str, recs: list[dict]) -> str:
    """Render one project's distilled sessions as readable markdown.
    Sessions ordered by start time; turns interleaved in event order."""
    recs = sorted(recs, key=lambda r: r.get("started") or "")
    n_prompts = sum(r["n_user"] for r in recs)
    lines: list[str] = [
        f"# {cwd}",
        "",
        f"{len(recs)} sessions · {n_prompts} prompts",
        "",
    ]
    for r in recs:
        lines.append("---")
        lines.append("")
        head = f"## {r['session']}"
        when = " → ".join(x for x in (r.get("started"), r.get("ended")) if x)
        if when:
            head += f" · {when}"
        lines.append(head)
        meta = []
        if r.get("branch"):
            meta.append(f"branch `{r['branch']}`")
        if r.get("is_carryover"):
            meta.append("carryover")
        meta.append(f"{r['n_user']} user / {r['n_asst']} asst")
        lines.append("_" + " · ".join(meta) + "_")
        lines.append("")
        for t in r["turns"]:
            tag = "User" if t["role"] == "user" else "Assistant"
            ts = t.get("ts") or ""
            lines.append(f"### {tag}{(' · ' + ts) if ts else ''}")
            lines.append("")
            lines.append(t["text"])
            lines.append("")
    return "\n".join(lines)


def _mtime_floor(iso_str: str) -> float:
    s = iso_str.replace("Z", "+00:00")
    if "T" not in s:  # bare date → local midnight
        d = dt.datetime.fromisoformat(s).replace(tzinfo=LOCAL_TZ)
    else:
        d = dt.datetime.fromisoformat(s)
    return d.timestamp()


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--since", help="lower bound on message timestamps; YYYY-MM-DD (interpreted as local midnight) or full ISO with offset (e.g. 2026-05-06T15:24+08:00)")
    ap.add_argument("--project", action="append", default=[],
                    help="substring match against project folder name; repeatable; omit to include all")
    args = ap.parse_args()
    main(args.since, args.project)

