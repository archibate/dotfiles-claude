#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""Drift detection hook for Claude Code Stop event.

Computes a 5-turn windowed tokens-per-grounding-event ratio (metric B) over
the current session transcript. Fires asyncRewake exit 2 with a system-reminder
when 3+ consecutive turns have windowed B above the p90 threshold AND the hook
is not currently in 'warned' state. Resets when windowed B drops below p75.

Threshold values (143 = p90, 73 = p75) calibrated over 547 historical sessions.

Numerator: assistant text + Bash command + Write content + Edit new_string (tokens).
Denominator: count of user-tagged transcript entries since previous assistant entry.
Token approximation: chars / 4.
"""

import json
import os
import sys
from pathlib import Path

P90 = 143
P75 = 73
SUSTAINED = 3
WINDOW = 5
MIN_TURNS = 5
STATE_DIR_TMPL = "/tmp/.claude-hooks-{session_id}"
STATE_FILE = "drift-state.json"


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


def windowed_b(turns, window=WINDOW):
    ratios = []
    for i in range(len(turns)):
        lo = max(0, i + 1 - window)
        sub = turns[lo : i + 1]
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
    if len(turns) < MIN_TURNS:
        return 0

    ratios = windowed_b(turns)
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


def statusline_segment(session_id):
    """Return a one-line statusline segment for the session's current drift ratio.

    Empty string when not enough turns. Color-codes by threshold and prefixes
    with ⚠ when the hook is currently in 'warned' state.
    """
    if not session_id:
        return ""
    transcript_path = find_transcript(session_id)
    if not transcript_path or not os.path.exists(transcript_path):
        return ""
    turns = compute_per_turn(transcript_path)
    if len(turns) < MIN_TURNS:
        return ""
    ratios = windowed_b(turns)
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
    if warned:
        color = RED

    label = "⚠⏚" if warned else "⏚"
    return f"  {color}[{label}:{most_recent:.0f}]{RESET}"


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
