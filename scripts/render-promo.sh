#!/usr/bin/env bash
#
# Renders an Utter promo from marketing/<promo>/ (1920x1080, 30 fps, zh-Hans).
# Needs Chromium, Node 18+, Python 3 + NumPy + SciPy, ffmpeg.
#   bash scripts/render-promo.sh promo-offline              full MP4
#   bash scripts/render-promo.sh promo-features --stills 3,12,20   QA stills only
#   bash scripts/render-promo.sh promo-day --audio-only            remix audio onto the last video render
# Output name comes from "output" in the promo's scene/cues.json.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:?usage: render-promo.sh <promo-dir-name> [--stills t1,t2,...]}"
KIT="$ROOT_DIR/marketing/promo-kit"
PROMO="$ROOT_DIR/marketing/$NAME"
DIST="$PROMO/dist"

[ -f "$PROMO/scene/cues.json" ] || { echo "error: $PROMO/scene/cues.json not found" >&2; exit 1; }
for tool in node python3 ffmpeg; do
    command -v "$tool" >/dev/null 2>&1 || { echo "error: $tool is required" >&2; exit 1; }
done
(cd "$KIT" && { [ -d node_modules ] || npm install --no-audit --no-fund; })

if [ "${2:-}" = "--stills" ]; then
    node "$KIT/render.mjs" "$PROMO" --stills "$3" --dir "$PROMO/qa"
    echo "Stills written to $PROMO/qa"
    exit 0
fi

OUT_NAME="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["output"])' "$PROMO/scene/cues.json")"
OUT="$DIST/$OUT_NAME"
mkdir -p "$DIST"
if [ "${2:-}" != "--audio-only" ] || [ ! -f "$DIST/video-only.mp4" ]; then
    node "$KIT/render.mjs" "$PROMO" --out "$DIST/video-only.mp4"
fi
python3 "$PROMO/score.py" "$DIST/soundtrack.wav"

ffmpeg -y -loglevel error -i "$DIST/video-only.mp4" -i "$DIST/soundtrack.wav" \
    -map 0:v -map 1:a -c:v copy \
    -af "loudnorm=I=-16:TP=-1.5:LRA=11" -c:a aac -b:a 192k -ar 48000 \
    -shortest -movflags +faststart "$OUT"

ffprobe -v error -show_entries format=duration:stream=codec_name,width,height,r_frame_rate -of compact "$OUT"
echo "Rendered $OUT"
