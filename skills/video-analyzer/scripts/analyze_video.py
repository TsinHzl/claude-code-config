#!/usr/bin/env python3
"""
Video data extractor: fetch metadata + subtitles from a URL and write
the result as JSON so the calling agent can analyze and report.

Dependencies (install once):
    pip install yt-dlp

Optional (audio transcription fallback when no subtitles exist):
    pip install openai-whisper
    brew install ffmpeg

Usage:
    python3 analyze_video.py <URL> [options]

    --cookies-from-browser BROWSER   e.g. chrome, firefox, safari
    --no-transcribe                  skip Whisper fallback
    --output  PATH                   where to write the JSON (default: /tmp/video_extract.json)
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

_AUDIO_CACHE_DIR = Path.home() / ".cache" / "video-analyzer-skill" / "audio"
_CACHE_TTL_SECS = 30 * 24 * 3600


def _cached_audio(video_id: str | None) -> str | None:
    if not video_id:
        return None
    cached = _AUDIO_CACHE_DIR / f"{video_id}.mp3"
    if cached.exists() and (time.time() - cached.stat().st_mtime) < _CACHE_TTL_SECS:
        return str(cached)
    return None


def _save_audio_cache(video_id: str | None, src: str) -> None:
    if not video_id:
        return
    _AUDIO_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, _AUDIO_CACHE_DIR / f"{video_id}.mp3")


# ── helpers ──────────────────────────────────────────────────────────────────


def check_dep(name: str) -> bool:
    return subprocess.run(["which", name], capture_output=True).returncode == 0


def run(cmd: list, **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def safe_filename(s: str) -> str:
    return re.sub(r"[^\w一-鿿\-. ]", "_", s)[:80].strip()


def seconds_to_hms(s) -> str:
    try:
        s = int(float(s))
        return f"{s//3600:02d}:{(s%3600)//60:02d}:{s%60:02d}"
    except (TypeError, ValueError):
        return str(s)


# ── extraction ────────────────────────────────────────────────────────────────


def _cookie_flags(browser: str | None) -> list:
    return ["--cookies-from-browser", browser] if browser else []


def fetch_metadata(url: str, cookie_browser: str | None = None) -> dict:
    result = run(
        [
            "yt-dlp",
            "--dump-json",
            "--no-playlist",
            "--no-warnings",
            *_cookie_flags(cookie_browser),
            url,
        ]
    )
    if result.returncode != 0:
        print(f"[ERROR] yt-dlp metadata failed:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)
    return json.loads(result.stdout)


def fetch_subtitles(
    url: str, tmp_dir: str, cookie_browser: str | None = None
) -> str | None:
    run(
        [
            "yt-dlp",
            "--write-subs",
            "--write-auto-subs",
            "--skip-download",
            "--no-playlist",
            "--sub-langs",
            "ai-zh,zh,zh-Hans,zh-Hant,en",
            "--sub-format",
            "best",
            "--convert-subs",
            "srt",
            "--no-warnings",
            *_cookie_flags(cookie_browser),
            "-o",
            os.path.join(tmp_dir, "sub"),
            url,
        ]
    )
    sub_files = (
        sorted(Path(tmp_dir).glob("sub*.srt"))
        + sorted(Path(tmp_dir).glob("sub*.vtt"))
        + sorted(Path(tmp_dir).glob("sub*.json"))
        + sorted(Path(tmp_dir).glob("sub*.ass"))
    )
    if not sub_files:
        all_files = [f.name for f in Path(tmp_dir).iterdir()]
        print(f"      [debug] no subtitle files found; tmp contains: {all_files}")
        return None
    sf = sub_files[0]
    text = sf.read_text(encoding="utf-8", errors="replace")
    if sf.suffix == ".srt":
        return _srt_to_text(text)
    elif sf.suffix == ".vtt":
        return _vtt_to_text(text)
    elif sf.suffix == ".json":
        return _json_sub_to_text(text)
    else:
        return _srt_to_text(text)


def _srt_to_text(srt: str) -> str:
    lines, seen = [], None
    for raw in srt.splitlines():
        line = raw.strip()
        if not line or "-->" in line or re.match(r"^\d+$", line):
            continue
        line = re.sub(r"<[^>]+>", "", line).strip()
        if line and line != seen:
            lines.append(line)
            seen = line
    return "\n".join(lines)


def _json_sub_to_text(raw: str) -> str:
    """Bilibili JSON subtitle format: {"body": [{"content": "...", ...}, ...]}"""
    try:
        data = json.loads(raw)
        body = data.get("body") or data.get("data", {}).get("body") or []
        lines, seen = [], None
        for item in body:
            content = str(item.get("content") or item.get("text") or "").strip()
            if content and content != seen:
                lines.append(content)
                seen = content
        return "\n".join(lines) or None
    except (json.JSONDecodeError, AttributeError, TypeError):
        return None


def _vtt_to_text(vtt: str) -> str:
    lines, seen = [], None
    for raw in vtt.splitlines():
        line = raw.strip()
        if (
            not line
            or "-->" in line
            or line.startswith("WEBVTT")
            or re.match(r"^\d+$", line)
        ):
            continue
        line = re.sub(r"<[^>]+>", "", line).strip()
        if line and line != seen:
            lines.append(line)
            seen = line
    return "\n".join(lines)


def transcribe_audio(
    url: str,
    tmp_dir: str,
    cookie_browser: str | None = None,
    model: str = "medium",
    video_id: str | None = None,
) -> str | None:
    cached = _cached_audio(video_id)
    if cached:
        print(f"      [cache hit] {cached}")
        audio_file = cached
    else:
        audio_path = os.path.join(tmp_dir, "audio.%(ext)s")
        dl = run(
            [
                "yt-dlp",
                "--extract-audio",
                "--audio-format",
                "mp3",
                "--audio-quality",
                "5",
                "--no-playlist",
                "--no-warnings",
                *_cookie_flags(cookie_browser),
                "-o",
                audio_path,
                url,
            ]
        )
        mp3_files = list(Path(tmp_dir).glob("audio.*"))
        if not mp3_files or dl.returncode != 0:
            return None
        audio_file = str(mp3_files[0])
        _save_audio_cache(video_id, audio_file)
    for backend in [
        ["faster-whisper", audio_file, "--model", model],
        [
            "whisper",
            audio_file,
            "--model",
            model,
            "--output_dir",
            tmp_dir,
            "--output_format",
            "txt",
        ],
    ]:
        try:
            result = run(backend)
        except FileNotFoundError:
            continue
        if result.returncode == 0:
            if "faster-whisper" in backend[0]:
                return result.stdout.strip()
            txt_files = list(Path(tmp_dir).glob("audio*.txt"))
            if txt_files:
                return (
                    txt_files[0].read_text(encoding="utf-8", errors="replace").strip()
                )

    try:
        from faster_whisper import WhisperModel  # type: ignore

        whisper_model = WhisperModel(model, device="cpu", compute_type="int8")
        segments, _ = whisper_model.transcribe(audio_file, beam_size=5)
        return " ".join(seg.text.strip() for seg in segments).strip() or None
    except ImportError:
        pass

    try:
        import whisper as openai_whisper  # type: ignore

        whisper_model = openai_whisper.load_model(model)
        return whisper_model.transcribe(audio_file).get("text", "").strip()
    except ImportError:
        return None


# ── main ──────────────────────────────────────────────────────────────────────


def main():
    parser = argparse.ArgumentParser(
        description="Extract video metadata and subtitles to JSON."
    )
    parser.add_argument("url", help="Video URL (YouTube, Bilibili, etc.)")
    parser.add_argument(
        "--output",
        default="/tmp/video_extract.json",
        help="Path to write extracted JSON (default: /tmp/video_extract.json)",
    )
    parser.add_argument(
        "--no-transcribe",
        action="store_true",
        help="Skip Whisper audio transcription fallback",
    )
    parser.add_argument(
        "--cookies-from-browser",
        default=None,
        metavar="BROWSER",
        help="Read cookies from browser (e.g. chrome, firefox, safari)",
    )
    parser.add_argument(
        "--model",
        default="medium",
        metavar="MODEL",
        help="Whisper model to use for transcription (default: medium)",
    )
    args = parser.parse_args()

    if not check_dep("yt-dlp"):
        print("[ERROR] yt-dlp not found. Install: pip install yt-dlp", file=sys.stderr)
        sys.exit(1)

    cb = args.cookies_from_browser
    if cb:
        print(f"[cookies] browser: {cb}")

    print(f"[1/3] Fetching metadata: {args.url}")
    meta = fetch_metadata(args.url, cb)

    # extract only the fields we need (full info dict can be very large)
    chapters = meta.get("chapters") or []
    summary = {
        "title": meta.get("title", ""),
        "channel": meta.get("uploader") or meta.get("channel") or "",
        "platform": meta.get("extractor_key") or meta.get("extractor", ""),
        "url": meta.get("webpage_url") or meta.get("original_url", ""),
        "upload_date": meta.get("upload_date", ""),
        "duration": seconds_to_hms(meta.get("duration")),
        "view_count": meta.get("view_count"),
        "like_count": meta.get("like_count"),
        "description": (meta.get("description") or "").strip(),
        "tags": meta.get("tags") or [],
        "categories": meta.get("categories") or [],
        "chapters": [
            {
                "start": seconds_to_hms(c.get("start_time", 0)),
                "title": c.get("title", ""),
            }
            for c in chapters
        ],
        "transcript": None,
        "transcript_source": "none",
        "whisper_model": None,
    }

    transcript = None
    source = "none"

    with tempfile.TemporaryDirectory() as tmp:
        print("[2/3] Fetching subtitles...")
        transcript = fetch_subtitles(args.url, tmp, cb)
        if transcript:
            source = "subtitles"
            print(f"      ✓ subtitles ok ({len(transcript)} chars)")
        elif not args.no_transcribe:
            print("      no subtitles — trying Whisper...")
            transcript = transcribe_audio(
                args.url, tmp, cb, model=args.model, video_id=meta.get("id")
            )
            if transcript:
                source = "whisper"
                print(f"      ✓ whisper ok ({len(transcript)} chars)")
            else:
                print("      ✗ whisper unavailable")
        else:
            print("      skipped (--no-transcribe)")

    summary["transcript"] = transcript
    summary["transcript_source"] = source
    summary["whisper_model"] = args.model if source == "whisper" else None

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    print(f"[3/3] Saved extract → {out_path}")
    print(f"EXTRACT_JSON={out_path}")  # machine-readable marker for the agent


if __name__ == "__main__":
    main()
