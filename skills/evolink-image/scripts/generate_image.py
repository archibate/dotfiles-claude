#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "requests",
# ]
# ///
"""Generate images via Evolink AI `gpt-image-2` (async).

Creates a task, polls until completion, downloads each result URL
to the output directory, and prints the saved paths.
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import sys
import time
from pathlib import Path
from typing import NoReturn
from urllib.parse import urlparse

import requests

API_BASE = "https://api.evolink.ai"
CREATE_PATH = "/v1/images/generations"
TASK_PATH = "/v1/tasks/{id}"


def die(msg: str, code: int = 1) -> NoReturn:
    print(msg, file=sys.stderr)
    sys.exit(code)


def get_key() -> str:
    key = os.environ.get("EVOLINK_API_KEY")
    if not key:
        die("EVOLINK_API_KEY is not set in the environment.")
    return key


def create_task(args: argparse.Namespace, key: str) -> dict:
    body: dict = {"model": "gpt-image-2", "prompt": args.prompt}
    if args.image:
        body["image_urls"] = args.image
    if args.size != "auto":
        body["size"] = args.size
    if args.resolution and _is_ratio(args.size):
        body["resolution"] = args.resolution
    if args.quality:
        body["quality"] = args.quality
    if args.n != 1:
        body["n"] = args.n

    r = requests.post(
        API_BASE + CREATE_PATH,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        json=body,
        timeout=30,
    )
    if r.status_code != 200:
        die(f"Create task failed [{r.status_code}]: {r.text}")
    return r.json()


def poll_task(task_id: str, key: str, interval: float, timeout: float) -> dict:
    url = API_BASE + TASK_PATH.format(id=task_id)
    headers = {"Authorization": f"Bearer {key}"}
    deadline = time.monotonic() + timeout
    last_status = None
    last_progress = -1
    while True:
        r = requests.get(url, headers=headers, timeout=30)
        if r.status_code != 200:
            die(f"Poll failed [{r.status_code}]: {r.text}")
        data = r.json()
        status = data.get("status")
        progress = data.get("progress", 0)
        if status != last_status or progress != last_progress:
            print(f"[{status}] progress={progress}%", file=sys.stderr)
            last_status = status
            last_progress = progress
        if status in ("completed", "failed"):
            return data
        if time.monotonic() > deadline:
            die(f"Timed out after {timeout}s; last status={status}, progress={progress}%")
        time.sleep(interval)


def _is_ratio(size: str) -> bool:
    return ":" in size


def _ext_for(url: str, content_type: str | None) -> str:
    path = urlparse(url).path
    ext = Path(path).suffix
    if ext:
        return ext
    if content_type:
        guess = mimetypes.guess_extension(content_type.split(";")[0].strip())
        if guess:
            return guess
    return ".png"


def download(urls: list[str], task_id: str, out_dir: Path) -> list[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    paths: list[Path] = []
    for i, url in enumerate(urls):
        with requests.get(url, stream=True, timeout=60) as r:
            if r.status_code != 200:
                die(f"Download failed [{r.status_code}] for {url}")
            ext = _ext_for(url, r.headers.get("Content-Type"))
            path = out_dir / f"{task_id}-{i}{ext}"
            with path.open("wb") as f:
                for chunk in r.iter_content(chunk_size=1 << 15):
                    if chunk:
                        f.write(chunk)
            paths.append(path)
    return paths


def main() -> int:
    p = argparse.ArgumentParser(description="Generate images via Evolink gpt-image-2.")
    p.add_argument("-p", "--prompt", required=True, help="Text prompt (up to 32000 chars).")
    p.add_argument("-i", "--image", action="append", default=[],
                   help="Reference image URL for img2img/edit. Repeatable.")
    p.add_argument("-s", "--size", default="auto",
                   help='Ratio ("1:1", "16:9", ...), explicit pixels ("1024x1024"), or "auto".')
    p.add_argument("-r", "--resolution", default="1K", choices=["1K", "2K", "4K"],
                   help="Resolution tier; only applies with ratio sizes.")
    p.add_argument("-q", "--quality", default="medium", choices=["low", "medium", "high"])
    p.add_argument("-n", "--n", type=int, default=1, help="Number of images (1-10).")
    p.add_argument("-o", "--output-dir", type=Path, default=Path("./evolink-out"))
    p.add_argument("--no-download", action="store_true", help="Print URLs only; don't save.")
    p.add_argument("--poll-interval", type=float, default=3.0)
    p.add_argument("--timeout", type=float, default=600.0)
    p.add_argument("--json", dest="as_json", action="store_true",
                   help="Emit a single JSON object instead of human-readable output.")
    args = p.parse_args()

    if not 1 <= args.n <= 10:
        die("--n must be in [1, 10].")

    key = get_key()

    created = create_task(args, key)
    task_id = created["id"]
    print(f"Created task {task_id}", file=sys.stderr)

    final = poll_task(task_id, key, args.poll_interval, args.timeout)

    if final.get("status") == "failed":
        err = final.get("error") or {}
        msg = err.get("message") or "task failed (no error message)"
        code = err.get("code") or "unknown"
        if args.as_json:
            print(json.dumps({"id": task_id, "status": "failed", "error": err}))
        else:
            print(f"Task failed: [{code}] {msg}", file=sys.stderr)
        return 2

    urls: list[str] = final.get("results") or []
    if not urls:
        die("Task completed but no result URLs were returned.")

    paths: list[Path] = []
    if not args.no_download:
        paths = download(urls, task_id, args.output_dir)

    if args.as_json:
        print(json.dumps({
            "id": task_id,
            "status": "completed",
            "urls": urls,
            "paths": [str(p) for p in paths],
        }))
    else:
        for url in urls:
            print(f"url: {url}")
        for path in paths:
            print(f"saved: {path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
