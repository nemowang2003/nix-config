"""Transcribe a local audio file to plain text."""

import argparse
import os
import sys
from pathlib import Path


def default_cache_dir() -> Path:
    cache_home = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    return cache_home / "faster-whisper" / "models"


def format_timestamp(seconds: float) -> str:
    milliseconds = round(seconds * 1000)
    hours, remainder = divmod(milliseconds, 3_600_000)
    minutes, remainder = divmod(remainder, 60_000)
    seconds, milliseconds = divmod(remainder, 1000)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}.{milliseconds:03d}"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="audio-transcribe", description="Transcribe an audio file with faster-whisper."
    )
    parser.add_argument("audio", type=Path, help="local audio or video file")
    parser.add_argument("-o", "--output", type=Path, help="write text to a file instead of stdout")
    parser.add_argument("--model", default="large-v3", help="model name or local model directory")
    parser.add_argument(
        "--model-cache", type=Path, default=default_cache_dir(), help="model cache directory"
    )
    parser.add_argument(
        "--device",
        choices=("cuda", "cpu"),
        default=os.environ.get("AUDIO_TRANSCRIBE_DEFAULT_DEVICE", "cpu"),
    )
    parser.add_argument(
        "--compute-type", help="CTranslate2 compute type (default: float16 on CUDA, int8 on CPU)"
    )
    parser.add_argument("--language", help="language code, for example zh or en (default: detect)")
    parser.add_argument("--task", choices=("transcribe", "translate"), default="transcribe")
    parser.add_argument("--timestamps", action="store_true", help="include segment timestamps")
    parser.add_argument("--vad", action="store_true", help="filter long non-speech regions")
    return parser


def run(args: argparse.Namespace) -> int:
    if not args.audio.is_file():
        raise ValueError(f"audio file does not exist: {args.audio}")

    from faster_whisper import WhisperModel

    compute_type = args.compute_type or ("float16" if args.device == "cuda" else "int8")
    print(
        f"Model: {args.model}; device: {args.device}; compute: {compute_type}; "
        f"model cache: {args.model_cache}",
        file=sys.stderr,
    )
    model = WhisperModel(
        args.model,
        device=args.device,
        compute_type=compute_type,
        download_root=str(args.model_cache),
    )
    segments, info = model.transcribe(
        str(args.audio), language=args.language, task=args.task, vad_filter=args.vad
    )
    print(f"Detected language: {info.language}", file=sys.stderr)
    lines = []
    for segment in segments:
        text = segment.text.strip()
        if text:
            if args.timestamps:
                text = (
                    f"[{format_timestamp(segment.start)} -> {format_timestamp(segment.end)}] {text}"
                )
            lines.append(text)

    result = "\n".join(lines) + ("\n" if lines else "")
    if args.output:
        args.output.write_text(result, encoding="utf-8")
        print(f"Wrote: {args.output}", file=sys.stderr)
    else:
        sys.stdout.write(result)
    return 0


def main() -> int:
    args = build_parser().parse_args()
    try:
        return run(args)
    except (OSError, ValueError, RuntimeError) as error:
        print(f"audio-transcribe: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
