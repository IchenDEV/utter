"""Soundtrack for the local voice input promo; timings come from scene/cues.json."""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "promo-kit"))
from synth import Mix, place_voice, dictation, end_bloom, load_cues, pad, pulse, section_bells, whoosh  # noqa: E402

C = load_cues(HERE)
E = C["events"]
CHORDS = [
    (0.0, [50, 57, 64, 66]),          # Dadd9
    (E["windowIn"], [47, 54, 62, 66]),  # Bm
    (E["keyDown"], [43, 50, 59, 66]),  # Gmaj7
    ((E["keyDown"] + E["keyUp"]) / 2, [45, 52, 61, 64]),  # A
    (E["keyUp"], [47, 54, 62, 66]),    # Bm
    (E["done"], [43, 50, 59, 62]),     # G
    (E["zoomOut"], [45, 52, 59, 64]),  # Asus
    (E["endCard"], [50, 57, 62, 66]),  # D
]

mix = Mix(C["duration"])
pad(mix, CHORDS, C["duration"])
pulse(mix, [(E["keyDown"], E["zoomOut"])], 100, CHORDS)
section_bells(mix, [0.15, E["windowIn"], E["zoomOut"]], [81, 78, 83])

mix.place(E["windowIn"] - 0.1, whoosh(0.5, 250, 2500), 0.08)
dictation(mix, E["keyDown"], E["keyUp"], [E["keyUp"] + 0.1, E["processing"], E["inserting"]], E["done"], land=E["inserting"] + 0.45)
mix.place(E["processing"] + 0.7, whoosh(0.6, 400, 4000), 0.06)
mix.place(E["zoomOut"], whoosh(1.2, 150, 2000), 0.1)
end_bloom(mix, E["endCard"] + 0.2)
place_voice(mix, HERE)
mix.write(sys.argv[1] if len(sys.argv) > 1 else HERE / "dist" / "soundtrack.wav")
