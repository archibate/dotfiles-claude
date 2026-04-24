---
name: evolink-image
description: Generate or edit images via the Evolink AI `gpt-image-2` model (async text-to-image, image-to-image, or edit-with-reference). Use whenever the user asks to generate, render, draw, or edit a bitmap image with AI.
---

# Evolink GPT Image 2

Async image generation via Evolink's `gpt-image-2` endpoint. Supports text→image, image→image, and edit-with-reference. All work goes through the bundled script — do not hand-roll HTTP calls unless the user asks for raw API use.

## When to reach for this skill

Trigger on requests to *produce* a bitmap image from a description: "generate", "create an image", "draw", "render", "make a picture of", "edit this photo", "change the background of this image", "turn this sketch into …". Applies equally when the user just drops a prompt ("A cinematic sunset over Shenzhen skyline") without the word "image" — the intent is clear.

Skip when the user wants vector/UI/code-driven art — frontend-design, algorithmic-art, shader-dev, or canvas-design handle those better.

## Environment

The script reads `EVOLINK_API_KEY` from the environment. It is already configured globally; no action needed on a fresh run. If the call returns `401`, tell the user their key is missing or expired rather than trying to patch it yourself.

## The script

```
scripts/generate_image.py --prompt "..." [options]
```

Full flag reference (all optional except `--prompt`):

| Flag | Meaning |
|---|---|
| `-p, --prompt` | Text prompt. Up to 32000 chars. Required. |
| `-i, --image` | Reference image URL for img2img / edit. Repeatable (1–16 total). |
| `-s, --size` | Ratio (`1:1`, `16:9`, `9:16`, `3:2`, `21:9`, …) or explicit pixels (`1024x1024`). Default `auto`. |
| `-r, --resolution` | `1K` / `2K` / `4K`. Only applies with ratio sizes. Default `1K`. |
| `-q, --quality` | `low` / `medium` / `high`. Cost scales ~0.1× / 1× / 4×. Default `medium`. |
| `-n, --n` | Number of images (1–10). Default 1. Each billed independently. |
| `-o, --output-dir` | Where to save downloaded images. Default `./evolink-out/`. |
| `--no-download` | Just print the result URLs; don't download. |
| `--poll-interval` | Seconds between status polls. Default 3. |
| `--timeout` | Max seconds to wait for completion. Default 600. |
| `--json` | Emit a single JSON object with `id`, `status`, `urls`, `paths` instead of human-readable output. Useful when chaining. |

The script blocks until the task finishes (or fails / times out), downloads each result to `<output-dir>/<task-id>-<index>.<ext>`, and prints the saved paths. Result URLs expire in 24 h, so always download unless the user explicitly just wants the URL.

## Common invocations

**Plain text-to-image**
```bash
uv run scripts/generate_image.py -p "A beautiful colorful sunset over the ocean"
```

**Widescreen, high quality**
```bash
uv run scripts/generate_image.py \
  -p "Cinematic wide shot of a futuristic city skyline at dusk" \
  -s 16:9 -r 4K -q high
```

**Image-to-image edit**
```bash
uv run scripts/generate_image.py \
  -p "Add a cute cat next to her" \
  -i https://example.com/input.png \
  -s 1:1 -q medium
```

**Batch of 4**
```bash
uv run scripts/generate_image.py \
  -p "A cute robot in pixel art style" \
  -s 1:1 -r 2K -q high -n 4
```

**Just want the URL (no download)**
```bash
uv run scripts/generate_image.py -p "..." --no-download
```

## Behaviour notes

- **Async under the hood.** The API returns a `task-unified-…` id; the script polls `/v1/tasks/{id}` every few seconds until `status` is `completed` or `failed`. The user sees only the final result.
- **Size vs resolution.** `resolution` (1K/2K/4K) is only a hint when `size` is a *ratio*. If the user gives explicit pixels (`1024x1024`), drop `--resolution`. Each side must be a multiple of 16; aspect ≤ 3:1; total pixels 0.65 MP – 8.29 MP.
- **Cost awareness.** `quality=high` is roughly 4× the token cost of `medium`, and `n=4` quadruples again. Don't bump both without a reason — default to `medium` + `n=1` unless the user asks otherwise.
- **Failures.** On `status=failed` the task response carries `error.code` / `error.message`; surface those verbatim. Common ones: `content_policy_violation` (rewrite prompt), `insufficient_quota` (402), `rate_limit_exceeded` (429, retry later).
- **Reference image input.** The URLs must be publicly reachable by Evolink's servers and end in an image extension, ≤ 50 MB each, `.jpg/.png/.webp`. If the user gives you a local file, upload it somewhere first (or tell them you need a URL) — don't try to base64 it; the API doesn't accept that here.

## Reporting back to the user

After a successful run, state the saved path(s) and, if relevant, the task id. Example: "Saved to `evolink-out/task-unified-1757156493-imcg5zqt-0.png`." Don't re-paste the full URL unless they asked for it — the file is what matters.
