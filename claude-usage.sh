#!/usr/bin/env python3
"""claude-usage — print Claude Code's 5h / 7d quota utilization.

Reads the OAuth access token from ~/.claude/.credentials.json (or macOS
Keychain), calls the private `/api/oauth/usage` endpoint, caches the result
for 5 minutes, and renders bars. JSON output via --json.

Endpoint and headers reverse-engineered from claude-hud 0.0.10
(src/usage-api.ts). Undocumented — may break.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
USER_AGENT = "claude-code/2.1"
BETA_HEADER = "oauth-2025-04-20"
KEYCHAIN_SERVICE = "Claude Code-credentials"

CACHE_TTL = 300        # 5 min — matches Anthropic rate-limit window
FAILURE_TTL = 15
RATE_LIMIT_BASE = 60
RATE_LIMIT_MAX = 300


def config_dir() -> Path:
    return Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude")).expanduser()


def cache_path() -> Path:
    return config_dir() / ".claude-usage-cache.json"


def using_custom_endpoint() -> bool:
    base = os.environ.get("ANTHROPIC_BASE_URL") or os.environ.get("ANTHROPIC_API_BASE_URL")
    if not base:
        return False
    try:
        from urllib.parse import urlparse
        return urlparse(base).netloc not in ("api.anthropic.com", "")
    except Exception:
        return True


def read_token_from_file() -> str | None:
    cred = config_dir() / ".credentials.json"
    if not cred.exists():
        return None
    try:
        data = json.loads(cred.read_text())
        return data.get("claudeAiOauth", {}).get("accessToken")
    except (json.JSONDecodeError, OSError):
        return None


def read_token_from_keychain() -> str | None:
    if sys.platform != "darwin" or not shutil.which("security"):
        return None
    try:
        out = subprocess.run(
            ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
            capture_output=True, text=True, timeout=3, check=False,
        )
        if out.returncode != 0:
            return None
        # Keychain returns either raw token or a JSON blob containing it.
        raw = out.stdout.strip()
        try:
            return json.loads(raw).get("claudeAiOauth", {}).get("accessToken") or raw
        except json.JSONDecodeError:
            return raw or None
    except subprocess.TimeoutExpired:
        return None


def get_token() -> str:
    for src in (read_token_from_file, read_token_from_keychain):
        tok = src()
        if tok:
            return tok
    sys.exit("error: no OAuth token found in credentials file or Keychain")


def load_cache() -> dict | None:
    p = cache_path()
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text())
    except (json.JSONDecodeError, OSError):
        return None


def save_cache(payload: dict) -> None:
    try:
        cache_path().write_text(json.dumps(payload))
    except OSError:
        pass


def parse_retry_after(value: str | None) -> int:
    if not value:
        return RATE_LIMIT_BASE
    try:
        return max(int(value), 1)
    except ValueError:
        try:
            ts = datetime.strptime(value, "%a, %d %b %Y %H:%M:%S %Z").timestamp()
            return max(int(ts - time.time()), 1)
        except ValueError:
            return RATE_LIMIT_BASE


def fetch_usage(token: str) -> tuple[dict | None, str | None, int | None]:
    req = urllib.request.Request(
        USAGE_URL,
        headers={
            "Authorization": f"Bearer {token}",
            "anthropic-beta": BETA_HEADER,
            "User-Agent": USER_AGENT,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.loads(r.read()), None, None
    except urllib.error.HTTPError as e:
        retry = parse_retry_after(e.headers.get("Retry-After")) if e.code == 429 else None
        return None, f"http-{e.code}", retry
    except (urllib.error.URLError, TimeoutError):
        return None, "network", None
    except json.JSONDecodeError:
        return None, "parse", None


def get_usage(force: bool = False) -> tuple[dict, bool]:
    """Return (data, fresh). `fresh=False` means data is cached or stale."""
    now = time.time()
    cache = load_cache() or {}

    if not force:
        retry_until = cache.get("retry_until", 0)
        if retry_until > now and cache.get("last_good"):
            return cache["last_good"], False
        ts = cache.get("timestamp", 0)
        ttl = CACHE_TTL if cache.get("data") else FAILURE_TTL
        if cache.get("data") and now - ts < ttl:
            return cache["data"], False

    data, err, retry = fetch_usage(get_token())
    if data:
        save_cache({"data": data, "last_good": data, "timestamp": now})
        return data, True

    if err == "http-429" and retry:
        count = cache.get("rl_count", 0) + 1
        backoff = min(retry, RATE_LIMIT_BASE * (2 ** (count - 1)), RATE_LIMIT_MAX)
        save_cache({
            **cache,
            "timestamp": now,
            "retry_until": now + backoff,
            "rl_count": count,
        })
        if cache.get("last_good"):
            return cache["last_good"], False
    sys.exit(f"error: usage API failed ({err})")


def render_bar(pct: int, width: int = 20) -> str:
    pct = max(0, min(100, pct))
    fill = round(pct / 100 * width)
    color = "\033[32m" if pct < 70 else "\033[33m" if pct < 85 else "\033[31m"
    reset = "\033[0m"
    return f"{color}{'█' * fill}{'░' * (width - fill)}{reset}"


def humanize_resets(iso: str | None) -> str:
    if not iso:
        return "?"
    try:
        when = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    except ValueError:
        return iso
    delta = when - datetime.now(timezone.utc)
    secs = int(delta.total_seconds())
    if secs <= 0:
        return "now"
    d, rem = divmod(secs, 86400)
    h, m = rem // 3600, (rem % 3600) // 60
    if d:
        return f"{d}d{h:02d}h"
    return f"{h}h{m:02d}m" if h else f"{m}m"


def main() -> None:
    ap = argparse.ArgumentParser(description="Show Claude Code quota usage.")
    ap.add_argument("--json", action="store_true", help="Emit raw JSON.")
    ap.add_argument("--force", action="store_true", help="Bypass cache.")
    args = ap.parse_args()

    if using_custom_endpoint():
        sys.exit("error: custom ANTHROPIC_BASE_URL set — OAuth usage API unavailable")

    data, fresh = get_usage(force=args.force)

    if args.json:
        print(json.dumps({**data, "_cached": not fresh}))
        return

    fh = data.get("five_hour") or {}
    sd = data.get("seven_day") or {}
    fh_pct = int(fh.get("utilization", 0))
    sd_pct = int(sd.get("utilization", 0))
    suffix = "" if fresh else "  \033[2m(cached)\033[0m"
    print(f" 5h  {render_bar(fh_pct)} {fh_pct:>3}%  resets in {humanize_resets(fh.get('resets_at'))}{suffix}")
    print(f" 7d  {render_bar(sd_pct)} {sd_pct:>3}%  resets in {humanize_resets(sd.get('resets_at'))}")


if __name__ == "__main__":
    main()
