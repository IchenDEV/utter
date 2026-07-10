#!/usr/bin/env python3
import argparse
import json
import pathlib
import sys


def qwen_language(code):
    return {
        "zh": "Chinese",
        "en": "English",
        "ja": "Japanese",
        "ko": "Korean",
        "yue": "Cantonese",
    }.get(code)


def mimo_tag(code):
    return {
        "zh": "<chinese>",
        "en": "<english>",
    }.get(code)


def make_qwen_transcriber(args):
    try:
        from qwen3_asr_mlx import Qwen3ASR
    except ImportError as exc:
        raise RuntimeError(
            "Unable to import qwen3-asr-mlx or one of its native dependencies: "
            f"{exc}"
        ) from exc

    model = Qwen3ASR.from_pretrained(args.model)

    def transcribe(audio, language):
        kwargs = {}
        resolved = qwen_language(language)
        if resolved:
            kwargs["language"] = resolved
        result = model.transcribe(audio, **kwargs)
        return {"text": result.text}

    return transcribe


def make_mimo_transcriber(args):
    if not args.tokenizer:
        raise ValueError("MiMo-V2.5-ASR requires --tokenizer")
    if args.repo:
        sys.path.insert(0, args.repo)
    try:
        from src.mimo_audio.mimo_audio import MimoAudio
    except ImportError as exc:
        try:
            from mimo_audio.mimo_audio import MimoAudio
        except ImportError as fallback_exc:
            raise RuntimeError(
                "Missing Xiaomi MiMo-V2.5-ASR Python dependencies in the detected "
                f"Python environment. Import errors: {exc}; {fallback_exc}"
            ) from fallback_exc

    model = MimoAudio(model_path=args.model, mimo_audio_tokenizer_path=args.tokenizer)

    def transcribe(audio, language):
        tag = mimo_tag(language)
        if tag:
            return {"text": model.asr_sft(audio, audio_tag=tag)}
        return {"text": model.asr_sft(audio)}

    return transcribe


def make_transcriber(args):
    if args.provider == "qwen3":
        return make_qwen_transcriber(args)
    return make_mimo_transcriber(args)


def run_once(args):
    audio_path = pathlib.Path(args.audio)
    if not audio_path.exists():
        raise FileNotFoundError(f"Audio file not found: {audio_path}")
    transcribe = make_transcriber(args)
    print(json.dumps(transcribe(args.audio, args.language), ensure_ascii=False))


def serve(args):
    """Load the model once, then answer one JSON request per stdin line with
    one JSON response per stdout line. Exits when stdin closes."""
    transcribe = make_transcriber(args)
    print(json.dumps({"ready": True}), flush=True)
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
            audio = request["audio"]
            if not pathlib.Path(audio).exists():
                raise FileNotFoundError(f"Audio file not found: {audio}")
            response = transcribe(audio, request.get("language"))
        except Exception as exc:  # keep serving after a bad request
            response = {"error": str(exc)}
        print(json.dumps(response, ensure_ascii=False), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", choices=["qwen3", "mimo"], required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--audio")
    parser.add_argument("--language")
    parser.add_argument("--tokenizer")
    parser.add_argument("--repo")
    parser.add_argument("--serve", action="store_true")
    args = parser.parse_args()

    if args.serve:
        serve(args)
        return
    if not args.audio:
        raise ValueError("--audio is required unless --serve is set")
    run_once(args)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
