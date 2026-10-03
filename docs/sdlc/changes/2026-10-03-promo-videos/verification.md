# Verification: Utter promo video series (offline, features, day-in-the-life)

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan.md](plan.md)

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `bash scripts/sdlc-checks.sh` | Pass | Bundle validates; all stages `pending approval` |
| `bash scripts/ci-basic-checks.sh` | Not run (host) | The Linux host stops at `swift package dump-package` and has no `plutil`/`PlistBuddy`. The portable steps were run by hand: no conflict markers, no broken symlinks, no secret-bearing files added |
| `swift test` | Not run (host) | No Swift toolchain on this host; no Swift, resource or plist files changed |
| Syntax | Pass | `node --check` on every kit/scene script; `py_compile` on `synth.py` and each `score.py`; `bash -n scripts/render-promo.sh` |
| File size | Pass | Largest source file is 221 lines (`promo-kit/synth.py`); every file stays under 300 lines |
| A/V sync | Pass | Status-change and release transients land within +2–3 ms of their `cues.json` events. The key-down peak trails by about 170 ms because Utter's own start tone follows the key by 50 ms, as in the app |
| Voice-over (round 3) | Pass | 30 ElevenLabs clips (eleven_v4, zh). Per-clip speech-to-text round trip (`voice_check.py`, scribe_v1): CER 0% on every clip. `eleven_multilingual_v2` was rejected because it read 离线 as 吃线 on two different voices |
| Final cuts (`marketing/videos/`) | Pass | `utter-offline-28s-zh-vo.mp4` 28.10 s, `utter-features-51s-zh-vo.mp4` 50.94 s, `utter-day-58s-zh-vo.mp4` 58.23 s; all H.264 1920×1080 30 fps + AAC 48 kHz stereo; -16.3 / -15.9 / -16.0 LUFS, true peak about -1.5 dBFS |
| Full-mix intelligibility | Pass | Speech-to-text on each final mix against the voice script: CER 3.1% / 1.6% / 0.0%. The non-zero values are most likely the recogniser hearing "Utter" as "Otter" (seen before in per-line checks), but this was not confirmed line by line. Re-recorded lines on their own: 0%. No mention of "Llama" in any cut |
| Voice vs music | Pass | About 14 dB of voice-to-music separation during speech (span-based ducking from the manifest). Per-line voice level within ±1 dB |
| Visual QA | Pass | 1–2 fps contact sheets of every final MP4 plus targeted stills. Found and fixed during the feedback round: a window-in NaN that hid windows, a headline/window overlap, a privacy-diagram fade that flashed the desktop before the end card, a style card that split “10 分钟” across lines, a gap and a tag/caption mismatch around 0:30 in the features cut, and establishing shots in the day cut that were too short |

## Acceptance criteria

- Format and length: **pass** for all three.
- Readable without sound: **pass**. Captions, numbered or time tags, on-screen
  spoken text and settings cards carry every beat.
- Audio: **pass**. One pad, a pulse only during demos, one bell per section, UI
  sounds tied to visible actions, and the bed ducks under effects. The per-word
  plinks, 8th-note arpeggio and strike swipes of the 40 s cut are gone.
- Claims map to code or real UI: **pass**. See the fact tables in each storyboard.
- Disclosures: **pass**. Reconstruction/sample-text footnotes appear on every
  demo; local-mode and installed-model notes appear wherever offline is shown;
  the screen-recording note is on voice-command scenes; the remote-API data
  note is on the models scene.
- Deterministic one-command re-render: **pass** (`scripts/render-promo.sh <promo>`).

## Residual risk

- **No real-device recording.** Offline behaviour, feature outputs and timing
  are reconstructed from source. Before public release, run the same utterances
  on an Apple Silicon Mac (Wi-Fi off for the offline scenes) and swap in the
  captured outputs. Owner: maintainer.
- **Illustrative outputs.** The voice-command, translation and lexicon outputs
  are plausible results written against the prompt rules, not model captures.
- **Approximated look.** The HUD material and the Noto Sans CJK typeface stand
  in for SwiftUI materials and PingFang.
- **Voice licensing.** ElevenLabs Voice Library voices on a paid plan;
  ShanShan has a 90-day notice period and Evan Zhao a 730-day one. Clips are
  cached in the repo, so re-renders do not depend on the voices staying
  available.
- **Longer runtimes.** Natural speech sets the voiced cuts' length (28 / 51 / 58 s).
  The earlier silent cuts were removed because their content is out of date.
- **Illustration, not photography.** People are hand-drawn vector figures seen
  from behind. Photoreal AI imagery would need an ElevenLabs Pro plan (the
  workspace is on Creator; image generation returned 402).
- **Model names in copy.** Taken from `ModelCatalog.defaultLLMModels` and
  `ModelCatalogASR.defaultASRModels`; they must be refreshed when the catalogue changes.

## Decision

Ready for human review. The bundle and the three final cuts are committed on
branch `t3code/offline-voice-promo-video` and submitted as a pull request.
Nothing has been published to the website or social channels.
