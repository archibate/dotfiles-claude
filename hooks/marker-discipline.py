#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""Stop hook: flag opinion-style lines in the last assistant response that lack
an inline [opinion] marker.

Scans the final assistant text in the current session transcript for opinion
triggers:
- Line-anchored labels — Recommendation and TL;DR (each followed by `:`).
- Predicate-position evaluative comparatives (e.g. `is cheaper`,
  `would be cleaner`, `seems faster`, `is more idiomatic`).
- Bare certainty adverbs — `clearly`, `obviously`, `definitely`, `certainly`.

For each hit, checks for `[opinion]` within a ±120-char character window
(which may span the trigger's line and adjacent lines). If any opinion-style
line has no marker in that window, emits an asyncRewake exit-2 reminder so the
agent self-corrects on the next turn (the response already shipped; this is a
non-blocking nudge, not a rewrite).

Fenced code blocks are stripped before scanning so quoted snippets do not
trigger. Inline-code spans are kept because the user's marker style sometimes
wraps the marker in backticks.

See CLAUDE.md -> Output Style.
"""

import json
import os
import re
import sys
from pathlib import Path

_PRED_VERBS = (
    r"(?:is|was|are|were|seems?|looks?|feels?|stays?|gets?|"
    r"would\s+be|could\s+be|should\s+be|will\s+be)"
)
_COMPARATIVES = (
    r"(?:better|cleaner|cheaper|faster|safer|simpler|nicer|stronger|weaker|"
    r"more\s+(?:idiomatic|stable|reliable|robust|elegant|efficient|"
    r"consistent|maintainable|readable|correct))"
)

OPINION_PATTERNS = [
    # Line-anchored opinion labels.
    re.compile(
        r"^\s*(?:Recommendation|TL;DR)\b\s*:",
        re.IGNORECASE | re.MULTILINE,
    ),
    # Predicate-position evaluative comparative.
    re.compile(
        rf"\b{_PRED_VERBS}\s+{_COMPARATIVES}\b",
        re.IGNORECASE,
    ),
    # Bare certainty adverbs.
    re.compile(
        r"\b(?:clearly|obviously|definitely|certainly)\b",
        re.IGNORECASE,
    ),
]

MARKER_RE = re.compile(r"\[opinion\]", re.IGNORECASE)
MARKER_WINDOW = 120
FENCED_RE = re.compile(r"```.*?```", re.DOTALL)
MAX_REPORTED = 5


def find_transcript(session_id: str) -> str | None:
    base = Path.home() / ".claude" / "projects"
    for p in base.glob(f"*/{session_id}.jsonl"):
        return str(p)
    return None


def last_assistant_text(transcript_path: str) -> str:
    last_text = ""
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
            if obj.get("type") != "assistant":
                continue
            msg = obj.get("message", {})
            content = msg.get("content", [])
            if not isinstance(content, list):
                continue
            buf = [
                blk.get("text", "")
                for blk in content
                if isinstance(blk, dict) and blk.get("type") == "text"
            ]
            if buf:
                last_text = "\n".join(buf)
    return last_text


def find_unmarked_opinions(text: str) -> list[str]:
    scrubbed = FENCED_RE.sub(lambda m: " " * len(m.group(0)), text)
    hits: list[str] = []
    seen: set[str] = set()
    for pat in OPINION_PATTERNS:
        for m in pat.finditer(scrubbed):
            lo = max(0, m.start() - MARKER_WINDOW)
            hi = min(len(scrubbed), m.end() + MARKER_WINDOW)
            if MARKER_RE.search(scrubbed[lo:hi]):
                continue
            line_start = scrubbed.rfind("\n", 0, m.start()) + 1
            line_end = scrubbed.find("\n", m.end())
            if line_end == -1:
                line_end = len(scrubbed)
            snippet = scrubbed[line_start:line_end].strip()[:120]
            if snippet in seen:
                continue
            seen.add(snippet)
            hits.append(snippet)
    return hits


def run() -> int:
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

    text = last_assistant_text(transcript_path)
    if not text:
        return 0

    hits = find_unmarked_opinions(text)
    if not hits:
        return 0

    plural = "s" if len(hits) > 1 else ""
    lines = [f"Unmarked opinion line{plural} in last response:"]
    for snip in hits[:MAX_REPORTED]:
        lines.append(f"  - {snip}")
    if len(hits) > MAX_REPORTED:
        lines.append(f"  ... ({len(hits) - MAX_REPORTED} more)")
    lines.append(
        "Opinion / recommendation / evaluative judgment lines need an inline "
        "[opinion] marker. Verified claims are unmarked by default. "
        "See CLAUDE.md -> Output Style."
    )
    sys.stderr.write("\n".join(lines) + "\n")
    return 2


if __name__ == "__main__":
    try:
        sys.exit(run())
    except Exception:
        sys.exit(0)
