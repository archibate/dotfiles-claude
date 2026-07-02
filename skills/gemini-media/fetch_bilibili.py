# /// script
# requires-python = ">=3.11"
# dependencies = ["bilibili-api-python", "curl_cffi"]
# ///
"""Companion to the Gemini analyzers: fetch a bilibili video's metadata and
download it to a local mp4, ready to feed into analyze_video.py.

    uv run fetch_bilibili.py BV1ZA64BiEV2                 # -> <BV>.mp4 + metadata
    uv run fetch_bilibili.py BV1ZA64BiEV2 -o clip.mp4
    uv run fetch_bilibili.py BV1ZA64BiEV2 --metadata-only

Metadata JSON -> stdout. Download progress + saved path -> stderr.
Anonymous works for metadata and ~480p; export SESSDATA into an env var and pass
--sessdata-env NAME for HD. Requires ffmpeg (merges DASH video+audio streams).
"""
import argparse
import asyncio
import json
import os
import subprocess
import sys
import tempfile

from bilibili_api import Credential, HEADERS, get_client, video

STAT_KEYS = ("view", "like", "coin", "favorite", "danmaku")


def eprint(*a):
    print(*a, file=sys.stderr)


async def download_file(url: str, out: str, label: str) -> None:
    client = get_client()
    dwn_id = await client.download_create(url, HEADERS)
    total = client.download_content_length(dwn_id)
    got = 0
    with open(out, "wb") as f:
        while True:
            try:
                chunk = await client.download_chunk(dwn_id)
            except StopAsyncIteration:
                break  # curl_cffi backend signals EOF by raising
            if not chunk:
                break
            got += f.write(chunk)
            eprint(f"{label} {got}/{total}", end="\r")
    eprint()


async def download(v: "video.Video", output: str) -> None:
    data = await v.get_download_url(page_index=0)
    det = video.VideoDownloadURLDataDetecter(data=data)
    streams = det.detect_best_streams()
    with tempfile.TemporaryDirectory() as d:
        if det.check_flv_mp4_stream():
            flv = os.path.join(d, "s.flv")
            await download_file(streams[0].url, flv, "flv")
            subprocess.run(["ffmpeg", "-y", "-i", flv, output], check=True)
        else:
            vpath, apath = os.path.join(d, "v.m4s"), os.path.join(d, "a.m4s")
            await download_file(streams[0].url, vpath, "video")
            await download_file(streams[1].url, apath, "audio")
            subprocess.run(["ffmpeg", "-y", "-i", vpath, "-i", apath,
                            "-c", "copy", output], check=True)
    eprint(f"saved: {output}")


async def run(args) -> None:
    sess = os.environ.get(args.sessdata_env) if args.sessdata_env else None
    cred = Credential(sessdata=sess) if sess else None
    v = video.Video(bvid=args.bvid, credential=cred)

    info = await v.get_info()
    meta = {
        "title": info["title"],
        "bvid": info["bvid"],
        "duration_s": info["duration"],
        "owner": info["owner"]["name"],
        "pubdate": info["pubdate"],
        "desc": info["desc"],
        "stat": {k: info["stat"][k] for k in STAT_KEYS},
    }
    try:
        meta["tags"] = [t["tag_name"] for t in await v.get_tags()]
    except Exception as e:
        meta["tags"] = f"<unavailable: {e}>"

    if not args.metadata_only:
        output = args.output or f"{args.bvid}.mp4"
        await download(v, output)
        meta["output"] = output

    json.dump(meta, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")


def main() -> None:
    p = argparse.ArgumentParser(
        description="Fetch bilibili metadata + download the video to mp4.")
    p.add_argument("bvid", help="the BV id, e.g. BV1ZA64BiEV2")
    p.add_argument("-o", "--output", help="output mp4 path (default: <BV>.mp4)")
    p.add_argument("--metadata-only", action="store_true",
                   help="print metadata and skip the download")
    p.add_argument("--sessdata-env",
                   help="env var holding SESSDATA cookie, for HD streams")
    asyncio.run(run(p.parse_args()))


if __name__ == "__main__":
    main()
