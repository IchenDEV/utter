"""Voice-over for Utter promos via the ElevenLabs CLI.

    python3 marketing/promo-kit/voice.py marketing/promo-offline [--force]

Reads <promo>/voice.json, synthesises each line with
`elevenlabs text-to-speech convert_with_timestamps` (cached in <promo>/voice/,
re-generated only when text, voice or settings change), then fits the picture
to the real audio:

- dictation lines re-time their on-screen tokens from character timestamps and
  move key-up (and everything after it) to just after the last syllable;
- narration lines that would run into the next beat push that beat later.

Finally writes <promo>/voice/manifest.json, which score.py mixes in.
"""
import base64
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

SKIP_KEYS = {"fps", "width", "height", "t", "d"}
SKIP_LISTS = {"speech", "tokens"}
PUNCT = re.compile(r"[\s，。、；：？！,.;:?!…—“”\"'（）()]")


def resolve(cues, path):
    node = cues
    for part in path.split("."):
        node = node[int(part)] if isinstance(node, list) else node[part]
    return node


def anchor(cues, spec):
    """'events.keyUp+0.3' -> float seconds."""
    m = re.fullmatch(r"([A-Za-z0-9_.]+?)([+-][0-9.]+)?", spec.replace(" ", ""))
    base = float(m.group(1)) if re.fullmatch(r"[0-9.]+", m.group(1)) else resolve(cues, m.group(1))
    return base + float(m.group(2) or 0)


def shift_from(node, t0, delta, key=None):
    """Add delta to every timeline value >= t0 (token-relative times are left alone)."""
    if isinstance(node, dict):
        for k, v in node.items():
            if isinstance(v, (int, float)) and not isinstance(v, bool) and k not in SKIP_KEYS:
                if v >= t0 - 1e-6:
                    node[k] = round(v + delta, 3)
            elif k not in SKIP_LISTS:
                shift_from(v, t0, delta, k)
    elif isinstance(node, list):
        for item in node:
            shift_from(item, t0, delta, key)


def synthesize(line, voices, out_dir, force):
    """Calls the API only when the request changes; tempo is applied locally (eleven_v4 ignores speed)."""
    voice = voices[line["voice"]]
    settings = {**voice.get("settings", {}), **line.get("settings", {})}
    req = {"text": line["text"], "voice_id": voice["id"], "model_id": voice["model"], "settings": settings,
           "language": voice.get("language")}
    digest = hashlib.sha1(json.dumps(req, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:12]
    raw, meta = out_dir / f"{line['id']}.raw.mp3", out_dir / f"{line['id']}.json"
    cached = meta.exists() and raw.exists() and json.loads(meta.read_text()).get("hash") == digest
    if force or not cached:
        print(f"  synthesising {line['id']} ({len(line['text'])} chars)…", flush=True)
        cmd = ["elevenlabs", "text-to-speech", "convert_with_timestamps", "--voice-id", voice["id"],
               "--model-id", voice["model"], "--text", line["text"], "--output-format", "mp3_44100_192",
               "--voice-settings", json.dumps(settings), "--format", "json"]
        if voice.get("language"):
            cmd += ["--language-code", voice["language"]]
        res = json.loads(subprocess.run(cmd, check=True, capture_output=True, text=True).stdout)
        raw.write_bytes(base64.b64decode(res["audio_base64"]))
        a = res["alignment"]
        meta.write_text(json.dumps({"hash": digest, "request": req, "chars": a["characters"],
                                    "start": a["character_start_times_seconds"], "end": a["character_end_times_seconds"]},
                                   ensure_ascii=False, indent=1))
    data = json.loads(meta.read_text())
    tempo = line.get("tempo", voice.get("tempo", 1.0))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(raw), "-af", f"atempo={tempo}",
                    "-c:a", "libmp3lame", "-b:a", "192k", str(out_dir / f"{line['id']}.mp3")], check=True)
    data["start"] = [x / tempo for x in data["start"]]
    data["end"] = [x / tempo for x in data["end"]]
    return data


def speech_bounds(data):
    """First/last voiced character times (ignores punctuation and trailing silence)."""
    idx = [i for i, c in enumerate(data["chars"]) if not PUNCT.fullmatch(c)]
    return data["start"][idx[0]], data["end"][idx[-1]]


def token_times(tokens, data):
    """Map display tokens onto aligned characters, in order. Token 'say' overrides the spoken form."""
    chars = [(c.lower(), s, e) for c, s, e in zip(data["chars"], data["start"], data["end"]) if not PUNCT.fullmatch(c)]
    pos = 0
    for tok in tokens:
        target = PUNCT.sub("", tok.get("say", tok["w"])).lower()
        joined = "".join(c for c, _, _ in chars[pos:])
        k = joined.find(target)
        if k < 0:
            raise SystemExit(f"token {tok['w']!r} not found in spoken text")
        first, last = pos + k, pos + k + len(target) - 1
        tok["t"] = round(chars[first][1], 3)
        tok["d"] = round(max(0.12, chars[last][2] - chars[first][1]), 3)
        pos = last + 1


def fit(promo, force=False):
    cues_path = promo / "scene" / "cues.json"
    cues = json.loads(cues_path.read_text())
    script = json.loads((promo / "voice.json").read_text())
    out_dir = promo / "voice"
    out_dir.mkdir(exist_ok=True)
    manifest = []
    for line in script["lines"]:
        data = synthesize(line, script["voices"], out_dir, force)
        v0, v1 = speech_bounds(data)
        if line["role"] == "dictation":
            beat = resolve(cues, line["beat"])
            tokens = resolve(cues, line["tokensPath"]) if "tokensPath" in line else beat["tokens"]
            token_times(tokens, data)
            start = beat[line.get("startKey", "speechStart")]
            # Audio offset so the first syllable lands on speechStart.
            place = start - v0
            for tok in tokens:
                tok["t"] = round(tok["t"] - v0, 3)
            want = round(start + (v1 - v0) + line.get("release", 0.3), 3)
            old = beat[line.get("keyUpKey", "keyUp")]
            if abs(want - old) > 0.02:
                shift_from(cues, old, want - old)
        else:
            place = anchor(cues, line["at"]) - v0
            end = place + v1
            if "until" in line:
                limit = anchor(cues, line["until"])
                if end > limit:
                    shift_from(cues, anchor(cues, line["shiftFrom"]), round(end - limit + 0.05, 3))
        manifest.append({"id": line["id"], "role": line["role"], "file": f"{line['id']}.mp3",
                         "start": round(place, 3), "speech": [round(place + v0, 3), round(place + v1, 3)],
                         "text": line["text"], "gain": line.get("gain", 1.0)})
    cues_path.write_text(json.dumps(cues, ensure_ascii=False, indent=1))
    (out_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1))
    check_overlaps(manifest)
    print(f"  duration now {cues['duration']} s; {len(manifest)} lines")


def check_overlaps(manifest):
    spans = sorted((m["speech"][0], m["speech"][1], m["id"]) for m in manifest)
    for (a0, a1, ida), (b0, b1, idb) in zip(spans, spans[1:]):
        if b0 < a1 + 0.1:
            print(f"  warning: {ida} ({a0:.2f}-{a1:.2f}) overlaps {idb} ({b0:.2f}-{b1:.2f})")


if __name__ == "__main__":
    fit(Path(sys.argv[1]).resolve(), force="--force" in sys.argv)
