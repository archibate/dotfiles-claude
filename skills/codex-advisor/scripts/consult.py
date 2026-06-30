#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Cross-model second opinion for the codex-advisor skill.

Run by the model when it invokes the skill. Locates this session's transcript
via $CLAUDE_CODE_SESSION_ID, renders it, forwards it to a stronger model
(gpt-5.5 by default, override with ADVISOR_CODEX_MODEL) through `codex exec`,
and prints the verdict to stdout for the model to read. No hooks, no settings
wiring — fully self-contained in the skill.

Disable globally by setting ADVISOR_CODEX=0.
"""

import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

if hasattr(signal, "SIGPIPE"):
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)

PROMPT_FILE = Path(__file__).parent / "advisor-prompt.md"
PROJECTS_DIR = Path.home() / ".claude" / "projects"

# Cap on rendered transcript chars (~3.3 ch/token). Measured: the median
# advisor-triggering session is ~195k chars, so 300k clears the median and fits
# comfortably in gpt-5.5's context. Long sessions are head+tail trimmed.
MAX_TRANSCRIPT_CHARS = int(os.environ.get("ADVISOR_CODEX_MAX_CHARS", "300000"))
CODEX_TIMEOUT_S = int(os.environ.get("ADVISOR_CODEX_TIMEOUT", "180"))
CODEX_MODEL = os.environ.get("ADVISOR_CODEX_MODEL", "gpt-5.5")


def find_transcript(sid: str) -> Path | None:
    """Locate <sid>.jsonl anywhere under ~/.claude/projects/. The active
    session is writing it right now, so the path is unique and unambiguous."""
    if not sid or not PROJECTS_DIR.is_dir():
        return None
    matches = list(PROJECTS_DIR.rglob(f"{sid}.jsonl"))
    return matches[0] if matches else None


# ---------- transcript rendering ----------

def _render_block(block: dict) -> str:
    btype = block.get("type")
    if btype == "text":
        return block.get("text", "")
    if btype == "thinking":
        return f"(thinking) {block.get('thinking', '')}"
    if btype == "tool_use":
        name = block.get("name", "?")
        inp = json.dumps(block.get("input", {}), ensure_ascii=False)
        if len(inp) > 2000:
            inp = inp[:2000] + " …(truncated)"
        return f"→ tool {name}({inp})"
    if btype == "tool_result":
        content = block.get("content", "")
        if isinstance(content, list):
            content = "\n".join(c.get("text", "") for c in content if isinstance(c, dict))
        content = str(content)
        if len(content) > 3000:
            content = content[:3000] + " …(truncated)"
        return f"← result: {content}"
    return ""


def _head_tail_trim(text: str, budget: int) -> str:
    """Keep the opening (the task statement + early context) and the most
    recent work, dropping the middle. Pure-tail trimming would lose what the
    task actually was; head+tail preserves both ends of a long session."""
    if budget <= 0:
        return ""
    if len(text) <= budget:
        return text
    marker = "\n\n…(middle of transcript truncated)…\n\n"
    if budget <= len(marker):
        return text[-budget:]     # too small for head+tail; keep recent (budget ≥ 1 here)
    avail = budget - len(marker)  # keep total output within budget
    head = avail // 4             # ~25% for the opening / task
    tail = avail - head           # ~75% for recent work
    return f"{text[:head]}{marker}{text[-tail:]}"


def render_transcript(path: Path) -> str:
    try:
        raw = path.read_text(errors="replace")
    except OSError:
        return ""
    lines: list[str] = []
    for ln in raw.splitlines():
        ln = ln.strip()
        if not ln:
            continue
        try:
            rec = json.loads(ln)
        except (json.JSONDecodeError, ValueError):
            continue
        msg = rec.get("message")
        if not isinstance(msg, dict):
            continue
        role = msg.get("role", rec.get("type") or "?")
        content = msg.get("content", "")
        if isinstance(content, str):
            body = content
        elif isinstance(content, list):
            body = "\n".join(
                s for s in (_render_block(b) for b in content if isinstance(b, dict)) if s
            )
        else:
            body = ""
        body = body.strip()
        if body:
            lines.append(f"## {role}\n{body}")
    return _head_tail_trim("\n\n".join(lines), MAX_TRANSCRIPT_CHARS)


# ---------- codex ----------

def run_codex(prompt: str, cwd: str) -> str | None:
    out_file = Path(os.environ.get("CLAUDE_CODE_TMPDIR", "/tmp")) / f"codex-advisor-{os.getpid()}.out"
    out_file.unlink(missing_ok=True)
    cmd = ["codex", "exec",
           "--ephemeral",
           "--skip-git-repo-check",
           "--ignore-rules",
           "-s", "read-only",
           "-C", cwd,
           "-o", str(out_file),
           "-m", CODEX_MODEL]
    effort = os.environ.get("ADVISOR_CODEX_EFFORT")
    if effort:
        cmd += ["-c", f"model_reasoning_effort={effort}"]
    cmd.append(prompt)
    env = {**os.environ, "CODEX_ADVISOR_CHILD": "1"}
    try:
        subprocess.run(
            cmd, cwd=cwd, env=env,
            stdin=subprocess.DEVNULL,
            capture_output=True, text=True, timeout=CODEX_TIMEOUT_S,
        )
    except FileNotFoundError:
        return "__codex CLI not found on PATH__"
    except subprocess.TimeoutExpired:
        return "__codex timed out__"
    except Exception as e:
        return f"__codex failed: {type(e).__name__}: {e}__"
    if not out_file.exists():
        return None
    try:
        return out_file.read_text().strip()
    except OSError:
        return None
    finally:
        out_file.unlink(missing_ok=True)


def main() -> int:
    # Recursion guard + global kill-switch.
    if os.environ.get("CODEX_ADVISOR_CHILD") == "1":
        return 0
    if os.environ.get("ADVISOR_CODEX") == "0":
        print("codex-advisor is disabled (ADVISOR_CODEX=0).")
        return 0

    sid = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    tp = find_transcript(sid)
    if tp is None:
        print(f"Could not locate this session's transcript (session_id={sid!r}). "
              "Cannot consult codex-advisor.")
        return 0

    transcript = render_transcript(tp)
    if not transcript:
        print("Transcript is empty; nothing to review.")
        return 0

    try:
        prompt_body = PROMPT_FILE.read_text()
    except OSError as e:
        print(f"Advisor prompt unreadable: {e}")
        return 0

    cwd = os.getcwd()
    t0 = time.monotonic()
    verdict = run_codex(f"{prompt_body}\n\n---\n\n{transcript}", cwd)
    dur = time.monotonic() - t0

    if not verdict or verdict.startswith("__"):
        reason = verdict.strip("_") if verdict else "no output"
        print(f"codex-advisor could not be reached ({reason}). "
              "Proceed on your own judgment.")
        return 0

    print(f"Second opinion from a cross-model advisor ({CODEX_MODEL} via Codex, "
          f"{dur:.0f}s), reviewing this session's transcript. Weigh it as an "
          f"independent hypothesis, not a mandate.\n")
    print(verdict)
    return 0


if __name__ == "__main__":
    sys.exit(main())
