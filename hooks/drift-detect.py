#!/usr/bin/env python3
"""Statusline component: 5-turn windowed tokens-per-grounding-event ratio.

Reads the current session transcript and emits a colored `[⏚:<ratio>]`
segment for the statusline. Color-codes by P75 / P90 thresholds calibrated
over 2275 historical sessions:
  green   ratio < P75 (225)
  yellow  P75 ≤ ratio < P90 (393)
  red     ratio ≥ P90

Numerator: assistant text + Bash command + Write content + Edit new_string
(approx tokens, chars / 4).
Denominator: count of user-tagged transcript entries since previous
assistant entry.

Turns with numerator below MIN_NUM=30 are filtered before windowing so
small loop ticks can't dilute a neighboring high-density turn.

Cached by (transcript stat) — statusline refreshes every 5s but transcripts
only grow at turn boundaries, so most ticks hit the cache.
Hit path ~12µs; direct compute ~263µs at 100KB, ~11ms at 3MB.

Pure statusline — no stderr, no exit-2, no enforcement.
"""

import json
import os
import sys
from pathlib import Path

P90 = 393
P75 = 225
WINDOW = 5
MIN_TURNS = 5
MIN_NUM = 30
CACHE_DIR_TMPL = "/tmp/.claude-hooks-{session_id}"
STATUSLINE_CACHE_FILE = "drift-statusline.cache"


def find_transcript(session_id):
    base = Path.home() / ".claude" / "projects"
    for p in base.glob(f"*/{session_id}.jsonl"):
        return str(p)
    return None


def tok(s):
    return max(0, len(s or "")) // 4


def compute_per_turn(transcript_path):
    """Per assistant entry, return (numerator_tokens, denominator_event_count)."""
    turns = []
    pending_user_count = 0

    with open(transcript_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            if obj.get("isSidechain"):
                continue

            t = obj.get("type")
            if t == "user":
                pending_user_count += 1
            elif t == "assistant":
                msg = obj.get("message", {})
                content = msg.get("content", [])
                if not isinstance(content, list):
                    continue

                num = 0
                for blk in content:
                    if not isinstance(blk, dict):
                        continue
                    bt = blk.get("type")
                    if bt == "text":
                        num += tok(blk.get("text", ""))
                    elif bt == "tool_use":
                        name = blk.get("name")
                        inp = blk.get("input", {}) or {}
                        if name == "Bash":
                            num += tok(inp.get("command", ""))
                        elif name == "Write":
                            num += tok(inp.get("content", ""))
                        elif name in ("Edit", "MultiEdit"):
                            if "new_string" in inp:
                                num += tok(inp.get("new_string", ""))
                            for e in inp.get("edits", []) or []:
                                if isinstance(e, dict):
                                    num += tok(e.get("new_string", ""))

                denom = max(1, pending_user_count)
                turns.append((num, denom))
                pending_user_count = 0

    return turns


def windowed_b(turns, window=WINDOW, min_num=MIN_NUM):
    sig = [(n, d) for (n, d) in turns if n >= min_num]
    ratios = []
    for i in range(len(sig)):
        lo = max(0, i + 1 - window)
        sub = sig[lo : i + 1]
        n_sum = sum(t[0] for t in sub)
        d_sum = sum(t[1] for t in sub)
        ratios.append(n_sum / d_sum if d_sum else 0.0)
    return ratios


def _stat_key(path):
    try:
        st = os.stat(path)
        return f"{st.st_mtime_ns}:{st.st_size}"
    except OSError:
        return "missing"


def _compute_segment(transcript_path):
    turns = compute_per_turn(transcript_path)
    ratios = windowed_b(turns)
    if len(ratios) < MIN_TURNS:
        return ""

    most_recent = ratios[-1]

    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    RED = "\033[31m"
    RESET = "\033[0m"

    if most_recent < P75:
        color = GREEN
    elif most_recent < P90:
        color = YELLOW
    else:
        color = RED

    return f"  {color}[⏚:{most_recent:.0f}]{RESET}"


def statusline_segment(session_id):
    """Return a one-line statusline segment for the session's current drift ratio.

    Empty string when not enough turns. Color-codes by threshold.
    """
    if not session_id:
        return ""
    transcript_path = find_transcript(session_id)
    if not transcript_path or not os.path.exists(transcript_path):
        return ""

    cache_dir = Path(CACHE_DIR_TMPL.format(session_id=session_id))
    cache_path = cache_dir / STATUSLINE_CACHE_FILE
    cache_key = _stat_key(transcript_path)

    try:
        if cache_path.exists():
            cached = cache_path.read_text()
            sep = cached.find("\n")
            if sep >= 0 and cached[:sep] == cache_key:
                return cached[sep + 1 :]
    except OSError:
        pass

    segment = _compute_segment(transcript_path)

    try:
        cache_dir.mkdir(parents=True, exist_ok=True)
        tmp_path = cache_path.with_suffix(".tmp")
        tmp_path.write_text(f"{cache_key}\n{segment}")
        os.replace(tmp_path, cache_path)
    except OSError:
        pass

    return segment


if __name__ == "__main__":
    # Usage: drift-detect.py statusline <session_id>
    # The leading "statusline" arg is kept for backward compat with the
    # existing statusline.sh invocation.
    sid = ""
    if len(sys.argv) > 2 and sys.argv[1] == "statusline":
        sid = sys.argv[2]
    elif len(sys.argv) > 1:
        sid = sys.argv[1]
    try:
        sys.stdout.write(statusline_segment(sid))
    except Exception:
        pass
    sys.exit(0)
