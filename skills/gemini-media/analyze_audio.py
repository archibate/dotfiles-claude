# /// script
# requires-python = ">=3.11"
# dependencies = ["requests"]
# ///
"""Delegate AUDIO understanding to Gemini on ofox — for a Claude agent that has
no native ear. Transcribe lyrics/speech, identify genre/mood/tempo, summarize
what is said or sung.

    uv run analyze_audio.py SONG.mp3
    uv run analyze_audio.py voice.m4a -p "Transcribe the speech, then summarize."
    uv run analyze_audio.py long.wav --max-cost 0.30 --confirm --json

Any ffmpeg-decodable audio is accepted; it is re-encoded to mono mp3 to keep the
request under ofox's 32 MB inline cap (Gemini bills by duration, so shrinking
bytes costs nothing). Requires ffmpeg/ffprobe. Reads the API key from $OFOX_API_KEY.
"""
import argparse
import os
import subprocess
import tempfile

import lib_gemini as G

DEFAULT_PROMPT = ("Listen to this audio and describe it: if there is speech or "
                  "singing, transcribe it (keep the original language); then "
                  "summarize the content, and note genre/mood if it is music.")
BITRATE_LADDER = ("64k", "48k", "32k", "24k")


def to_mono_mp3(src: str, dst: str, bitrate: str) -> None:
    subprocess.run(["ffmpeg", "-y", "-i", src, "-ac", "1", "-b:a", bitrate, dst],
                   check=True, capture_output=True)


def fit_audio(src: str, workdir: str) -> str:
    """Mono mp3, dropping bitrate until it fits the inline cap (HARD limit)."""
    dst = os.path.join(workdir, "audio.mp3")
    for bitrate in BITRATE_LADDER:
        to_mono_mp3(src, dst, bitrate)
        if G.fits_inline(dst):
            return dst
    G.die("audio too long to fit ofox's 32 MB inline limit even at 24k mono; "
          "split it into shorter chunks first", 5)


def main() -> None:
    p = argparse.ArgumentParser(
        description="Understand audio via Gemini on ofox (Claude has no native audio).")
    G.add_common_args(p)
    args = p.parse_args()

    duration = G.ffprobe_duration(args.input)
    tokens, est_usd = G.estimate_cost(duration, with_video=False)
    G.eprint(f"[plan] {duration:.0f}s audio, ~{tokens['audio_tokens']} audio "
             f"tokens, est ${est_usd:.4f}")
    G.enforce_cost_gate(est_usd, args.max_cost, args.confirm)

    with tempfile.TemporaryDirectory() as workdir:
        small = fit_audio(args.input, workdir)
        part = {"type": "input_audio",
                "input_audio": {"data": G.b64_encode_file(small), "format": "mp3"}}
        data = G.call_gemini(part, args.prompt or DEFAULT_PROMPT, args)
    G.emit(data, args.as_json, args.model)


if __name__ == "__main__":
    main()
