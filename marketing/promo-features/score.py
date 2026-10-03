"""Soundtrack for the feature promo; timings come from scene/cues.json."""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "promo-kit"))
from synth import Mix, place_voice, dictation, end_bloom, load_cues, pad, pulse, section_bells, soft_pop, whoosh  # noqa: E402

C = load_cues(HERE)
B = C["beats"]
STYLE, MODELS, END = C["style"], C["models"], C["endCard"]
PROG = [[50, 57, 64, 66], [47, 54, 62, 66], [43, 50, 59, 66], [45, 52, 61, 64]]  # D Bm Gmaj7 A
starts = [0.0] + [b["winIn"] for b in B.values()] + [STYLE["start"], MODELS["start"]]
CHORDS = [(t, PROG[i % 4]) for i, t in enumerate(starts)] + [(END, [50, 57, 62, 66])]

mix = Mix(C["duration"])
pad(mix, CHORDS, C["duration"])
pulse(mix, [(B["list"]["winIn"], END)], 104, CHORDS, gain=0.28)
section_bells(mix, starts[1:], [81, 83, 85, 86, 88, 86])

for b in B.values():
    mix.place(b["winIn"] - 0.05, whoosh(0.45, 300, 3000), 0.06)
    dictation(mix, b["keyDown"], b["keyUp"], [b["keyUp"] + 0.1, b["processing"], b["inserting"]], b["done"],
              land=b["inserting"] + 0.45, shift=b.get("kind") == "translating")
for t in (STYLE["start"] + 0.6, STYLE["casual"], STYLE["professional"], MODELS["start"] + 0.1, MODELS["start"] + 0.45):
    mix.place(t, soft_pop(), 0.18)
end_bloom(mix, END + 0.2)
place_voice(mix, HERE)
mix.write(sys.argv[1] if len(sys.argv) > 1 else HERE / "dist" / "soundtrack.wav")
