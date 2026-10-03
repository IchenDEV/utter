# Plan: Utter promo video series (offline, features, day-in-the-life)

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** [spec.md](spec.md)

## Work items

- [x] Gather product facts from source and real UI captures; review the references.
- [x] Offline promo v1 (40 s): storyboard, deterministic scene, renderer, soundtrack.
- [x] Feedback round: extract the shared engine into `marketing/promo-kit/`;
      rebuild the soundtrack synth (single pad, pulse, sparse UI sounds, ducking).
- [x] Offline promo recut to 26 s on the shared engine.
- [x] Features promo (45 s): six numbered segments plus a settings side card.
- [x] Day-in-the-life promo (52.5 s): five illustrated office moments with a push-in to the laptop screen.
- [x] Single entry point `scripts/render-promo.sh <promo>`; storyboards and the `marketing/README.md` index.
- [x] Render all three MP4s and run QA (stills, contact sheets, probe, loudness).
- [x] Voice-over round: ElevenLabs CLI pipeline (`voice.py`, `voice_check.py`), voice scripts, model choice (eleven_v4 over multilingual_v2 after a mispronunciation of 离线), timeline re-fit, voice bus with ducking, re-render.
- [x] Feedback round 4: offline cut toned down (Wi-Fi-off act removed; offline mentioned once plus the end card); supported models named in all three cuts (diagram + screenshots, model wall, train chip + end card); day cut redrawn with a recurring protagonist, colleagues, detailed laptop, desk and props; end-card periods removed.
- [x] Punctuation pass: on-screen titles, captions, tags and end cards carry no trailing period or comma; message and dictation body text keeps full punctuation (rule in `marketing/README.md`).
- [x] Final cuts copied to `marketing/videos/` for the push.
- [x] Llama 4 removed from all three cuts (user decision 2026-10-03): model diagram, model wall, narration, end card; the LLM-types screenshot replaced with the real "Qwen3.5 2B 当前" row.
- [ ] Real-device pass: run the same utterances on an Apple Silicon Mac
      (Wi-Fi off for the offline scenes) and replace illustrative outputs with
      captured ones (needs a human and a Mac).

## Verification plan

- [x] `bash scripts/sdlc-checks.sh`
- [ ] `bash scripts/ci-basic-checks.sh` (needs macOS `plutil`/`PlistBuddy`)
- [ ] `swift test` (needs a macOS Swift toolchain; no app code changed)
- [x] Visual QA stills and 1 fps contact sheets of each final MP4; probe and EBU R128 loudness.

## Human gates

- Approve intent, spec and plan. The user requested immediate execution and
  the feedback round, so implementation ran ahead of formal approval; this is
  recorded here.
- Decide whether to swap in real-device capture and/or voice-over before
  public release.
- Publishing to the website or social channels is a separate human action.
