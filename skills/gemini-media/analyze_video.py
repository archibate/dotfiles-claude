# /// script
# requires-python = ">=3.11"
# dependencies = ["requests"]
# ///
"""Delegate VIDEO understanding to Gemini on ofox — for a Claude agent that
cannot watch. Gemini sees both the frames and the audio track and can describe
action, on-screen text, style, and the music.

    uv run analyze_video.py clip.mp4
    uv run analyze_video.py mv.mp4 -p "Describe the story and art style. 用中文."
    uv run analyze_video.py lecture.mp4 --max-cost 0.50 --confirm --json

Any ffmpeg-decodable video works; it is crushed to ~1 fps low-res (Gemini
samples at ~1 fps anyway, so nothing it sees is lost) to fit ofox's 32 MB inline
cap. Requires ffmpeg/ffprobe. Reads the API key from $OFOX_API_KEY.
"""
import argparse
import os
import subprocess
import tempfile

import lib_gemini as G

DEFAULT_PROMPT = ("Describe this video: what happens visually (action, setting, "
                  "on-screen text) and the audio (speech, music, mood). "
                  "Be concrete and concise.")
# File size ≈ bitrate × duration (fps-independent), so to fit a long video we
# drop the video bitrate, not the frame rate.
VBITRATE_FALLBACKS = ("100k", "64k", "32k")


def crush(src: str, dst: str, fps: float, width: int, vbitrate: str) -> None:
    subprocess.run(
        ["ffmpeg", "-y", "-i", src, "-vf", f"scale={width}:-2", "-r", str(fps),
         "-c:v", "libx264", "-b:v", vbitrate, "-ac", "1", "-b:a", "48k", dst],
        check=True, capture_output=True,
    )


def fit_video(src: str, workdir: str, fps: float, width: int,
              vbitrate: str) -> tuple[str, str]:
    """Crush, dropping video bitrate until it fits the inline cap (HARD limit)."""
    dst = os.path.join(workdir, "video.mp4")
    for rate in (vbitrate, *VBITRATE_FALLBACKS):
        crush(src, dst, fps, width, rate)
        if G.fits_inline(dst):
            return dst, rate
    G.die("video too long to fit ofox's 32 MB inline limit even at 32k video "
          "bitrate; split it into shorter clips first", 5)


def main() -> None:
    p = argparse.ArgumentParser(
        description="Understand video (frames+audio) via Gemini on ofox "
                    "(Claude has no native video).")
    G.add_common_args(p)
    p.add_argument("--fps", type=float, default=1.0,
                   help="target sample rate; Gemini samples ~1 fps (default 1.0)")
    p.add_argument("--width", type=int, default=426,
                   help="downscaled frame width in px (default 426)")
    p.add_argument("--vbitrate", default="150k", help="video bitrate for the crush")
    args = p.parse_args()

    duration = G.ffprobe_duration(args.input)
    tokens, est_usd = G.estimate_cost(duration, with_video=True)
    G.eprint(f"[plan] {duration:.0f}s video, ~{tokens['visual_tokens']} visual + "
             f"{tokens['audio_tokens']} audio tokens, est ${est_usd:.4f}")
    G.enforce_cost_gate(est_usd, args.max_cost, args.confirm)

    with tempfile.TemporaryDirectory() as workdir:
        small, used_rate = fit_video(args.input, workdir, args.fps,
                                     args.width, args.vbitrate)
        G.eprint(f"[crush] {os.path.getsize(small) / 1e6:.1f} MB "
                 f"at {args.fps} fps, {used_rate} video bitrate")
        part = {"type": "file", "file": {
            "file_data": f"data:video/mp4;base64,{G.b64_encode_file(small)}",
            "filename": "video.mp4"}}
        data = G.call_gemini(part, args.prompt or DEFAULT_PROMPT, args)
    G.emit(data, args.as_json, args.model)


if __name__ == "__main__":
    main()
