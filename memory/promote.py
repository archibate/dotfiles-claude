#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""promote: split a triaged nugget library into per-status memory files.

Reads ~/.claude/memory/distilled/extracted/_triaged.md (each bullet prefixed with
`[+]`/`[-]`/`[?]`) and writes:
  ~/.claude/memory/promoted.md  — accepted, citations stripped (compact)
  ~/.claude/memory/pending.md   — needs review, citations kept
  ~/.claude/memory/rejected.md  — explicitly dropped, citations kept
"""

from __future__ import annotations

import re
import sys
from collections import defaultdict
from pathlib import Path

SRC = Path.home() / ".claude" / "memory" / "distilled" / "extracted" / "_triaged.md"
OUT = Path.home() / ".claude" / "memory"

H2_RE = re.compile(r"^## (.+)$")
BULLET_RE = re.compile(r"^- \[([+\-?])\] (.+)$")
META_TAIL_RE = re.compile(r"\s*(?:\[[^\]]+\]\s*)*\(×\d+\s+sources?\)\s*$")


def parse(text: str):
    """Yield (theme, [marker, primary_line, continuation_lines])."""
    theme = None
    cur = None  # [marker, primary, [cont_lines]]
    for line in text.splitlines():
        m = H2_RE.match(line)
        if m:
            if cur:
                yield theme, cur
                cur = None
            theme = m.group(1)
            continue
        m = BULLET_RE.match(line)
        if m:
            if cur:
                yield theme, cur
            cur = [m.group(1), m.group(2), []]
            continue
        if cur is not None:
            if line.startswith("  ") and line.strip():
                cur[2].append(line)
            else:
                yield theme, cur
                cur = None
    if cur:
        yield theme, cur


def render(buckets: dict[str, list[tuple[str, list[str]]]], header: str, with_cites: bool) -> str:
    lines = [header, ""]
    for theme, items in buckets.items():
        if not items:
            continue
        lines.append(f"## {theme}")
        lines.append("")
        for primary, cont in items:
            text = primary if with_cites else META_TAIL_RE.sub("", primary)
            lines.append(f"- {text}")
            if with_cites:
                lines.extend(cont)
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> None:
    if not SRC.exists():
        sys.exit(f"missing {SRC}")
    OUT.mkdir(parents=True, exist_ok=True)
    text = SRC.read_text()

    buckets: dict[str, dict[str, list]] = {
        "+": defaultdict(list),
        "-": defaultdict(list),
        "?": defaultdict(list),
    }
    for theme, (mk, primary, cont) in parse(text):
        if not theme or theme.startswith("dropped"):
            continue
        buckets[mk][theme].append((primary, cont))

    plan = [
        ("+", "promoted.md", "# Promoted memory", False),
        ("?", "pending.md", "# Pending review", True),
        ("-", "rejected.md", "# Rejected (audit)", True),
    ]
    counts = {}
    for mk, name, hdr, cites in plan:
        (OUT / name).write_text(render(buckets[mk], hdr, cites))
        counts[mk] = sum(len(v) for v in buckets[mk].values())

    print(f"[+] {counts['+']:>3}  ->  {OUT}/promoted.md  (citations stripped)")
    print(f"[?] {counts['?']:>3}  ->  {OUT}/pending.md")
    print(f"[-] {counts['-']:>3}  ->  {OUT}/rejected.md")
    if counts["?"]:
        print(f"\n{counts['?']} pending - re-run after you flip [?] markers in {SRC}")


if __name__ == "__main__":
    main()
