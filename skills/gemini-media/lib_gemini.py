"""Shared helpers for delegating audio/video understanding to Gemini on ofox.

Claude Code has no native audio/video understanding; these helpers let it shell
out to Gemini 3.1 Flash Lite (a cheap multimodal model) on the ofox gateway.

No inline PEP 723 deps here on purpose — the *entry* CLI declares `requests`,
and this module runs inside that same `uv run` environment (script dir is on
sys.path, so `import lib_gemini` just works).

Output contract (agent-friendly):
    stdout -> the model's answer ONLY (or one JSON object with --json)
    stderr -> plans, warnings, usage, cost
"""
from __future__ import annotations

import base64
import json
import os
import subprocess
import sys

import requests

# --- Defaults (all overridable via CLI flags / env; none are magic literals) ---
DEFAULT_MODEL = "google/gemini-3.1-flash-lite"
DEFAULT_BASE_URL = "https://api.ofox.ai/v1/chat/completions"
DEFAULT_API_KEY_ENV = "OFOX_API_KEY"
DEFAULT_BASE_URL_ENV = "OFOX_BASE_URL"
DEFAULT_MAX_COST_USD = 0.10          # refuse pricier jobs unless --confirm
DEFAULT_TIMEOUT_S = 600.0
USD_TO_CNY = 7.2                     # rough, for a human-readable hint only

# ofox rejects request bodies over 32 MB; base64 inflates the file ~4/3, and the
# JSON envelope + data-URI prefix add a bit more, so aim below the raw cap.
INLINE_LIMIT_BYTES = 30 * 1024 * 1024
B64_OVERHEAD = 4 / 3

# ofox pricing for gemini-3.1-flash-lite, $/token.
PRICE_AUDIO, PRICE_TEXT, PRICE_OUTPUT = 5e-7, 2.5e-7, 1.5e-6
# Token rates are duration-driven (measured; Gemini samples video at ~1 fps).
AUDIO_TOK_PER_SEC = 32
VIDEO_VISUAL_TOK_PER_SEC = 66


def eprint(*args) -> None:
    print(*args, file=sys.stderr)


def die(msg: str, code: int) -> "NoReturn":  # type: ignore[name-defined]
    eprint(msg)
    sys.exit(code)


def ffprobe_duration(path: str) -> float:
    if not os.path.exists(path):
        die(f"no such file: {path}", 6)
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=nw=1:nk=1", path],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    return float(out)


def b64_encode_file(path: str) -> str:
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode()


def fits_inline(path: str) -> bool:
    return os.path.getsize(path) * B64_OVERHEAD < INLINE_LIMIT_BYTES


def estimate_cost(duration_s: float, with_video: bool) -> tuple[dict, float]:
    audio = duration_s * AUDIO_TOK_PER_SEC
    visual = duration_s * VIDEO_VISUAL_TOK_PER_SEC if with_video else 0.0
    usd = audio * PRICE_AUDIO + visual * PRICE_TEXT
    return {"audio_tokens": round(audio), "visual_tokens": round(visual)}, usd


def actual_cost(usage: dict) -> float:
    det = usage.get("prompt_tokens_details", {}) or {}
    audio = det.get("audio_tokens", 0)
    text = det.get("text_tokens", 0)
    visual = usage.get("prompt_tokens", 0) - audio - text
    out = usage.get("completion_tokens", 0)
    return audio * PRICE_AUDIO + (text + visual) * PRICE_TEXT + out * PRICE_OUTPUT


def enforce_cost_gate(est_usd: float, max_cost: float, confirm: bool) -> None:
    """The *soft* gate: bypassable with --confirm. Not the 32 MB hard limit."""
    if est_usd > max_cost and not confirm:
        die(f"refusing: estimated ${est_usd:.4f} exceeds --max-cost "
            f"${max_cost:.4f}; re-run with --confirm to proceed", 2)


def call_gemini(content_part: dict, prompt: str, args) -> dict:
    key = os.environ.get(args.api_key_env)
    if not key:
        die(f"missing API key: set ${args.api_key_env}", 3)
    payload = {"model": args.model, "messages": [{"role": "user", "content": [
        {"type": "text", "text": prompt}, content_part,
    ]}]}
    r = requests.post(args.base_url, headers={"Authorization": f"Bearer {key}"},
                      json=payload, timeout=args.timeout)
    if r.status_code != 200:
        die(f"gemini error HTTP {r.status_code}: {r.text[:500]}", 4)
    return r.json()


def emit(data: dict, as_json: bool, model: str) -> None:
    text = data["choices"][0]["message"]["content"]
    usage = data.get("usage", {})
    cost = actual_cost(usage)
    if as_json:
        json.dump({"text": text, "usage": usage,
                   "cost_usd": round(cost, 6), "model": model},
                  sys.stdout, ensure_ascii=False)
        sys.stdout.write("\n")
    else:
        print(text)  # clean stdout: the answer, alone
        eprint(f"[usage] {usage}")
        eprint(f"[cost] ${cost:.5f} (~{cost * USD_TO_CNY:.4f} CNY)")


def add_common_args(p) -> None:
    p.add_argument("input", help="path to the media file")
    p.add_argument("-p", "--prompt",
                   help="what to ask Gemini about the media (default: general description)")
    p.add_argument("--model", default=DEFAULT_MODEL, help="ofox model id")
    p.add_argument("--base-url",
                   default=os.environ.get(DEFAULT_BASE_URL_ENV, DEFAULT_BASE_URL),
                   help=f"chat-completions endpoint (or ${DEFAULT_BASE_URL_ENV})")
    p.add_argument("--api-key-env", default=DEFAULT_API_KEY_ENV,
                   help="name of the env var holding the ofox API key")
    p.add_argument("--max-cost", type=float, default=DEFAULT_MAX_COST_USD,
                   help="refuse if estimated USD cost exceeds this, unless --confirm")
    p.add_argument("--confirm", action="store_true",
                   help="proceed despite the cost warning")
    p.add_argument("--json", action="store_true", dest="as_json",
                   help="emit one {text,usage,cost_usd,model} object on stdout")
    p.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_S,
                   help="HTTP timeout in seconds")
