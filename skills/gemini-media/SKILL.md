---
name: gemini-media
description: >-
  Claude has no native audio or video understanding — this skill delegates that
  to Google Gemini 3.1 Flash Lite (cheap multimodal) on the ofox gateway. Use
  when the user asks to analyze / transcribe / describe / understand a sound,
  song, voice memo, or video, or asks what is said, sung, shown, or played in a
  media file. Triggers: "analyze this audio", "transcribe the song/speech",
  "what does this voice say", "describe/understand this video/mp4/clip",
  "what's the music/story in this MV", "listen to", "watch this".
---

# gemini-media

Claude cannot hear audio or watch video. These scripts send the media to Gemini
on ofox and return Gemini's answer as plain text, so an agent can reason over
the result. Cost is a few cents; see the table below.

## Scripts

| Script | Purpose | Input |
|--------|---------|-------|
| `analyze_audio.py` | Transcribe / describe sound, songs, speech | any audio file |
| `analyze_video.py` | Describe frames **and** audio of a video | any video file |
| `fetch_bilibili.py` | Companion: download a bilibili video + metadata to feed the analyzers | a `BV` id |

Each is a standalone `uv run` script (PEP 723 inline deps). Requires `ffmpeg`
and `ffprobe` on PATH, and the ofox API key in `$OFOX_API_KEY`.

## Usage

```bash
# Audio — default prompt gives transcription + genre/mood, or ask your own
uv run analyze_audio.py song.mp3
uv run analyze_audio.py memo.m4a -p "Transcribe the speech, then summarize."

# Video — Gemini sees frames + hears the track
uv run analyze_video.py clip.mp4 -p "Describe the story and art style. 用中文."

# Bilibili end-to-end: download, then analyze
uv run fetch_bilibili.py BV1ZA64BiEV2 -o mv.mp4
uv run analyze_video.py mv.mp4
```

## Output contract (agent-friendly)

- **stdout** — the model's answer, and nothing else. Capture it directly.
- **stderr** — plan, cost, crush log, warnings. Ignore for the answer.
- `--json` — emit one object on stdout instead: `{text, usage, cost_usd, model}`.

```bash
answer=$(uv run analyze_audio.py song.mp3 2>/dev/null)      # just the text
uv run analyze_video.py clip.mp4 --json 2>/dev/null | jq -r .text
```

## Common flags (both analyzers)

| Flag | Meaning |
|------|---------|
| `-p, --prompt` | what to ask about the media (default: general description) |
| `--json` | structured output on stdout |
| `--max-cost USD` | refuse if the estimate exceeds this (default `0.10`) |
| `--confirm` | proceed past the cost warning |
| `--model` / `--base-url` / `--api-key-env` | override the ofox target |

`analyze_video.py` also takes `--fps` (default `1.0`), `--width`, `--vbitrate`.

## Size & cost guards

Two independent limits:

1. **Cost (soft, bypassable).** Before calling, the script estimates cost from
   the media's duration. If it exceeds `--max-cost`, it **refuses and exits 2**
   with an actionable message. Re-run with `--confirm` to proceed.
2. **32 MB inline cap (hard, not bypassable).** ofox rejects request bodies over
   32 MB. Video is crushed to ~1 fps low-res; audio is re-encoded to mono mp3 —
   both are duration-billed by Gemini, so shrinking bytes is free and lossless to
   what the model perceives. If it still won't fit, the script errors (exit 5) and
   tells you to split the file. `--confirm` does **not** wave this through.

## Typical cost (ofox gemini-3.1-flash-lite)

| Media | Duration | ≈ Cost |
|-------|----------|--------|
| Song / audio | 4 min | $0.003 (~0.02 元) |
| Music video | 4 min | $0.008 (~0.06 元) |

Audio ≈ 32 tok/s ($0.5/M); video adds ≈ 66 visual tok/s ($0.25/M).

## Exit codes

`0` ok · `2` cost gate (use `--confirm`) · `3` missing API key · `4` Gemini HTTP
error · `5` too large for 32 MB even after crushing · `6` input file not found.

## Gotchas (do not regress)

- Video **must** use the `file` content-part. The `video_url` and `input_video`
  shapes are silently accepted but ignored (model sees nothing).
- Audio uses the `input_audio` part with `format: "mp3"`. Keep audio and video on
  their own proven paths; do not route audio through `file`.
- ofox declares modalities `text+image+audio+file` — video rides in on `file`.
