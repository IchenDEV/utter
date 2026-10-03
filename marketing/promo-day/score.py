"""Soundtrack for the day-in-the-life promo; timings come from scene/cues.json."""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "promo-kit"))
from synth import Mix, place_voice, dictation, end_bloom, load_cues, lowpass, noise, pad, pulse, section_bells, whoosh  # noqa: E402

C = load_cues(HERE)
S, END = C["scenes"], C["endCard"]
# One chord colour per moment of the day; brighter in the morning, warmer at dusk.
PROG = {"morning": [50, 57, 64, 66], "meeting": [47, 54, 62, 66], "afternoon": [43, 50, 59, 66],
        "evening": [45, 52, 61, 64], "train": [47, 54, 59, 62]}
CHORDS = [(s["start"], PROG[s["place"]]) for s in S] + [(END, [50, 57, 62, 66])]

mix = Mix(C["duration"])
pad(mix, CHORDS, C["duration"])
pulse(mix, [(S[0]["dollyIn"], END)], 96, CHORDS, gain=0.26)
section_bells(mix, [0.2] + [s["start"] for s in S[1:]], [81, 83, 85, 81, 78])

for s in S:
    mix.place(s["dollyIn"], whoosh(1.1, 200, 2600), 0.07)
    dictation(mix, s["keyDown"], s["keyUp"], [s["keyUp"] + 0.1, s["processing"], s["inserting"]], s["done"],
              land=s["inserting"] + 0.45, shift=s.get("kind") == "translating")

train = S[-1]
rumble = lowpass(noise(END - train["start"] + 0.5), 140, order=4)
rumble /= abs(rumble).max()
mix.place(train["start"], rumble, 0.05, bus="bed")
end_bloom(mix, END + 0.25)
place_voice(mix, HERE)
mix.write(sys.argv[1] if len(sys.argv) > 1 else HERE / "dist" / "soundtrack.wav")
