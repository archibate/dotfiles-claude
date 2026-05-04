#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""pages: explode promoted.md into a topic-indexed page tree.

Reads ~/.claude/memory/promoted.md and writes:
  ~/.claude/memory/pages/index.md    — verbatim topic titles + relative paths
  ~/.claude/memory/pages/<slug>.md   — one file per H2 topic, bullets verbatim

Slug rule: strip trailing parenthetical (e.g. " (NEW theme)"), lowercase,
collapse non-alphanumeric runs to `-`, trim leading/trailing dashes.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

SRC = Path.home() / ".claude" / "memory" / "promoted.md"
OUT_DIR = Path.home() / ".claude" / "memory" / "pages"

H2_RE = re.compile(r"^## (.+)$")
TRAIL_PAREN_RE = re.compile(r"\s*\([^)]*\)\s*$")
NONALNUM_RE = re.compile(r"[^a-z0-9]+")


def slugify(title: str) -> str:
    base = TRAIL_PAREN_RE.sub("", title).lower()
    return NONALNUM_RE.sub("-", base).strip("-")


def parse_sections(text: str):
    """Yield (title, body_lines) per H2 section."""
    title = None
    body: list[str] = []
    for line in text.splitlines():
        m = H2_RE.match(line)
        if m:
            if title is not None:
                yield title, body
            title = m.group(1)
            body = []
            continue
        if title is not None:
            body.append(line)
    if title is not None:
        yield title, body


def main() -> None:
    if not SRC.exists():
        sys.exit(f"missing {SRC}")
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    sections = list(parse_sections(SRC.read_text()))
    if not sections:
        sys.exit("no H2 sections found in promoted.md")

    seen: dict[str, str] = {}
    index_lines = ["# Memory pages index", ""]
    for title, body in sections:
        slug = slugify(title)
        if slug in seen:
            sys.exit(f"slug collision: {slug!r} from {title!r} and {seen[slug]!r}")
        seen[slug] = title

        while body and not body[0].strip():
            body.pop(0)
        page = [f"# {title}", "", *body]
        text = "\n".join(page).rstrip() + "\n"
        (OUT_DIR / f"{slug}.md").write_text(text)
        index_lines.append(f"- {title} — {slug}.md")

    (OUT_DIR / "index.md").write_text("\n".join(index_lines).rstrip() + "\n")

    # Drop stale page files (slugs no longer present).
    for path in OUT_DIR.glob("*.md"):
        if path.name == "index.md":
            continue
        if path.stem not in seen:
            path.unlink()

    print(f"[pages] {len(sections)} topics -> {OUT_DIR}/")


if __name__ == "__main__":
    main()
