"""Round-trip QA for generated voice-over: transcribe each clip with ElevenLabs
speech-to-text and report the character error rate against the script.

    python3 marketing/promo-kit/voice_check.py marketing/promo-offline
"""
import json
import re
import subprocess
import sys
from pathlib import Path

KEEP = re.compile(r"[一-鿿A-Za-z0-9]")
DIGITS = str.maketrans("0123456789", "零一二三四五六七八九")


def norm(text):
    return "".join(KEEP.findall(text.translate(DIGITS))).lower()


def cer(ref, hyp):
    prev = list(range(len(hyp) + 1))
    for i, a in enumerate(ref, 1):
        cur = [i]
        for j, b in enumerate(hyp, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a != b)))
        prev = cur
    return prev[-1] / max(1, len(ref))


def main(promo):
    manifest = json.loads((promo / "voice" / "manifest.json").read_text())
    results, worst = [], 0.0
    for m in manifest:
        out = subprocess.run(["elevenlabs", "speech-to-text", "convert", "--file", str(promo / "voice" / m["file"]),
                              "--model-id", "scribe_v1", "--format", "json"], check=True, capture_output=True, text=True).stdout
        heard = json.loads(out).get("text", "")
        score = cer(norm(m["text"]), norm(heard))
        worst = max(worst, score)
        results.append({"id": m["id"], "script": m["text"], "heard": heard, "cer": round(score, 3)})
        print(f"{m['id']:<14} CER {score:5.1%}  {heard}")
    (promo / "voice" / "check.json").write_text(json.dumps(results, ensure_ascii=False, indent=1))
    print(f"worst CER {worst:.1%}")


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve())
