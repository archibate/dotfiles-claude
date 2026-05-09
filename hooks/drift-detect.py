#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""Drift detection hook for Claude Code Stop event.

Computes a 5-turn windowed tokens-per-grounding-event ratio (metric B) over
the current session transcript. Fires asyncRewake exit 2 with a system-reminder
when 3+ consecutive turns have windowed B above the p90 threshold AND the hook
is not currently in 'warned' state. Resets when windowed B drops below p75.

Threshold values (393 = p90, 225 = p75) calibrated over 2275 historical sessions
under the evaluable view (n=18751 windowed ratios from 319 sessions with ≥
MIN_TURNS=5 *significant* turns at MIN_NUM=30) — i.e. the distribution of
ratios the hook would actually evaluate against thresholds, not raw windowed
output from short sessions that can never fire. Cross-verified at MIN_NUM=0:
recovers p90=144 over 583 evaluable sessions, matching the prior (143, 73)
calibration over 547 sessions. Prior calibration on raw turns no longer
applies under filtering.

Numerator: assistant text + Bash command + Write content + Edit new_string (tokens).
Denominator: count of user-tagged transcript entries since previous assistant entry.
Token approximation: chars / 4.

Turns with numerator below MIN_NUM are filtered before windowing — small loop
ticks (e.g. /cache-hygiene) would otherwise dilute a neighboring high-density
turn out of the P90 band.
"""

import json
import os
import sys
from pathlib import Path

P90 = 393
P75 = 225
SUSTAINED = 3
WINDOW = 5
MIN_TURNS = 5
# Filter floor: turns with numerator below this are excluded from the window so
# that loop-tick noise can't dilute a neighboring high-density turn out of the
# P90 band. Calibrated over 1402 sessions with /cache-hygiene + /loop markers:
# loop-tick num distribution had p99=28, max=54 across 314 ticks; setting the
# floor above p99 filters effectively all loop ticks while preserving
# substantive turns (substantive p75=40, p90=164 across 40k turns).
# NOTE: changing MIN_NUM invalidates P90/P75 above — recalibrate together.
MIN_NUM = 30
STATE_DIR_TMPL = "/tmp/.claude-hooks-{session_id}"
STATE_FILE = "drift-state.json"
STATUSLINE_CACHE_FILE = "drift-statusline.cache"


def load_state(session_id):
    state_dir = Path(STATE_DIR_TMPL.format(session_id=session_id))
    state_path = state_dir / STATE_FILE
    if state_path.exists():
        try:
            return json.loads(state_path.read_text())
        except Exception:
            pass
    return {"warned": False}


def save_state(session_id, state):
    state_dir = Path(STATE_DIR_TMPL.format(session_id=session_id))
    state_dir.mkdir(parents=True, exist_ok=True)
    (state_dir / STATE_FILE).write_text(json.dumps(state))


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


def run():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    session_id = payload.get("session_id", "")
    if not session_id:
        return 0

    transcript_path = find_transcript(session_id)
    if not transcript_path or not os.path.exists(transcript_path):
        return 0

    turns = compute_per_turn(transcript_path)
    ratios = windowed_b(turns)
    if len(ratios) < MIN_TURNS:
        return 0

    last = ratios[-SUSTAINED:]
    sustained_above = all(r > P90 for r in last)
    most_recent = ratios[-1]

    state = load_state(session_id)

    if state.get("warned"):
        if most_recent < P75:
            state["warned"] = False
            save_state(session_id, state)
        return 0

    if sustained_above:
        state["warned"] = True
        save_state(session_id, state)
        sys.stderr.write(
            f"Drift signal: 5-turn windowed tokens-per-grounding-event sustained above "
            f"p90 ({P90}) for {SUSTAINED}+ turns (current: {most_recent:.0f}). "
            f"You may be generating output (text, code, edits) without enough verification. "
            f"Refresh grounding (current docs, real-world usage, existing substrate, fresh "
            f"subagent audit) before continuing. "
            f"See Self-critique Protocol and Output Style — Epistemic Markers.\n"
        )
        return 2

    return 0


def _stat_key(path):
    try:
        st = os.stat(path)
        return f"{st.st_mtime_ns}:{st.st_size}"
    except OSError:
        return "missing"


def _compute_segment(transcript_path, session_id):
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

    state = load_state(session_id)
    warned = state.get("warned")

    label = "⚠⏚" if warned else "⏚"
    return f"  {color}[{label}:{most_recent:.0f}]{RESET}"


def statusline_segment(session_id):
    """Return a one-line statusline segment for the session's current drift ratio.

    Empty string when not enough turns. Color-codes by threshold and prefixes
    with ⚠ when the hook is currently in 'warned' state.

    Cached by (transcript stat, state stat) — status line refreshes every 5s
    but transcripts only grow at turn boundaries, so most ticks hit the cache.
    Hit path ~12µs; direct compute ~263µs at 100KB, ~11ms at 3MB.
    """
    if not session_id:
        return ""
    transcript_path = find_transcript(session_id)
    if not transcript_path or not os.path.exists(transcript_path):
        return ""

    state_dir = Path(STATE_DIR_TMPL.format(session_id=session_id))
    state_path = state_dir / STATE_FILE
    cache_path = state_dir / STATUSLINE_CACHE_FILE
    cache_key = f"{_stat_key(transcript_path)}|{_stat_key(state_path)}"

    try:
        if cache_path.exists():
            cached = cache_path.read_text()
            sep = cached.find("\n")
            if sep >= 0 and cached[:sep] == cache_key:
                return cached[sep + 1 :]
    except OSError:
        pass

    segment = _compute_segment(transcript_path, session_id)

    try:
        state_dir.mkdir(parents=True, exist_ok=True)
        tmp_path = cache_path.with_suffix(".tmp")
        tmp_path.write_text(f"{cache_key}\n{segment}")
        os.replace(tmp_path, cache_path)
    except OSError:
        pass

    return segment


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "statusline":
        sid = sys.argv[2] if len(sys.argv) > 2 else ""
        try:
            sys.stdout.write(statusline_segment(sid))
        except Exception:
            pass
        sys.exit(0)
    try:
        sys.exit(run())
    except Exception:
        sys.exit(0)
