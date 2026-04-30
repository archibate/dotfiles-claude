#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Stage 1+2 of auto-memory pipeline: filter noisy JSONL transcripts to a
signal-only per-session corpus suitable for LLM distillation."""

from __future__ import annotations

import json
import re
import sys
from collections import defaultdict
from pathlib import Path

PROJECTS = Path.home() / ".claude" / "projects"
OUT_DIR = Path("/tmp/distilled")
SYSTEM_REMINDER_RE = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)
COMMAND_TAG_RE = re.compile(r"<(command-name|command-message|command-args|local-command-stdout|local-command-caveat|task-notification)>.*?</\1>", re.S)
CACHE_TICK_RE = re.compile(r"^Cache keep-alive\. Idle tick \d+/\d+\.\s*$")
AUTONOMOUS_RE = re.compile(r"<<autonomous-loop(?:-dynamic)?>>")


def clean_user_text(s: str) -> str:
    s = SYSTEM_REMINDER_RE.sub("", s)
    s = COMMAND_TAG_RE.sub("", s)
    s = AUTONOMOUS_RE.sub("", s)
    s = s.strip()
    if CACHE_TICK_RE.match(s):
        return ""
    return s


def extract_assistant_text(content) -> str:
    if isinstance(content, str):
        return content.strip()
    if not isinstance(content, list):
        return ""
    parts = []
    for block in content:
        if not isinstance(block, dict):
            continue
        if block.get("type") == "text":
            parts.append(block.get("text", ""))
    return "\n".join(p for p in parts if p).strip()


def process(jsonl_path: Path, since_iso: str | None) -> dict | None:
    """Distill one transcript file. If `since_iso` is YYYY-MM-DD, only keep
    user/assistant messages whose timestamp is >= that date (inclusive
    lower bound, no upper bound). Sessions with zero in-window user prompts
    after slicing are dropped. Lexicographic compare on ISO-8601 timestamps
    sorts correctly without parsing."""
    user_msgs: list[str] = []
    asst_msgs: list[str] = []
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
                in_slice = (not since_iso) or (ts >= since_iso)
                if t == "user":
                    msg = ev.get("message") or {}
                    content = msg.get("content")
                    if isinstance(content, str):
                        cleaned = clean_user_text(content)
                        if cleaned and len(cleaned) > 3:
                            total_user += 1
                            if in_slice:
                                user_msgs.append(cleaned)
                                started = started or ts
                                ended = ts
                elif t == "assistant":
                    if in_slice:
                        msg = ev.get("message") or {}
                        text = extract_assistant_text(msg.get("content"))
                        if text:
                            asst_msgs.append(text)
                            started = started or ts
                            ended = ts
                if cwd is None and ev.get("cwd"):
                    cwd = ev["cwd"]
                if git_branch is None and ev.get("gitBranch"):
                    git_branch = ev["gitBranch"]
    except OSError:
        return None

    if not user_msgs:
        return None

    is_carryover = bool(since_iso) and bool(session_started) and (session_started < since_iso)

    return {
        "session": jsonl_path.stem,
        "cwd": cwd,
        "branch": git_branch,
        "started": started,
        "ended": ended,
        "session_started": session_started,
        "session_ended": session_ended,
        "is_carryover": is_carryover,
        "n_user": len(user_msgs),
        "n_asst": len(asst_msgs),
        "n_user_total": total_user,
        "user": user_msgs,
        "asst": asst_msgs,
        "raw_bytes": jsonl_path.stat().st_size,
    }


def main(since_iso: str | None) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    files = sorted(PROJECTS.glob("**/*.jsonl"))
    if since_iso:
        files = [f for f in files if f.stat().st_mtime >= _mtime_floor(since_iso)]

    by_cwd: dict[str, list[dict]] = defaultdict(list)
    raw_total = 0
    distilled_total = 0
    n_sessions = 0

    for f in files:
        if f.name.startswith("agent-"):
            continue  # subagent files; their content is also in parent
        rec = process(f, since_iso)
        if not rec:
            continue
        n_sessions += 1
        raw_total += rec["raw_bytes"]
        # crude byte-count of distilled content
        d = sum(len(m) for m in rec["user"]) + sum(len(m) for m in rec["asst"])
        distilled_total += d
        by_cwd[rec["cwd"] or "<unknown>"].append(rec)

    # Write per-cwd summary corpora
    for cwd, recs in by_cwd.items():
        slug = cwd.strip("/").replace("/", "_") or "root"
        out = OUT_DIR / f"{slug}.jsonl"
        with out.open("w") as wf:
            for r in recs:
                wf.write(json.dumps(r, ensure_ascii=False) + "\n")

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


def _mtime_floor(date: str) -> float:
    import datetime as dt
    d = dt.datetime.strptime(date, "%Y-%m-%d").replace(tzinfo=dt.timezone.utc)
    return d.timestamp()


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
