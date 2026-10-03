# Spec: Utter promo video series (offline, features, day-in-the-life)

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** [intent.md](intent.md)

## Context

The build host is Linux, so the macOS app cannot be launched or screen-recorded
here. The real HUD geometry, copy, colours, waveform maths, menu-bar
recording icon and start/stop tones are defined in Swift source
(`OverlayPanelContent.swift`, `WaveformView.swift`, `OverlayActionButton.swift`,
`AppDelegate+Icons.swift`, `SoundPlayer.swift`). A real light-mode capture of
the Models settings exists in `review-evidence/2026-09-23-confucius4-r2t2-mlx/light.png`.

## Design

- **Shared kit**: `marketing/promo-kit/` holds the engine (desk, windows, HUD,
  spoken words, overlay, renderer, synth). Each promo keeps only `cues.json`,
  its scene scripts and `score.py`.
- **Scene**: each `marketing/promo-*/scene/` is a static HTML page.
  `window.renderAt(t)` sets every style from time `t` alone. It uses no CSS
  transitions or real-time animation, so every frame is deterministic.
  `cues.json` is the single timing source for picture and sound.
- **Fidelity**: the HUD is rebuilt from `OverlayLayout` metrics, with the
  waveform ported line-for-line from `WaveformView` (light palette) and status
  strings taken from `zh-Hans.lproj`. Settings imagery comes from crops of the
  real screenshot. The host app ("团队聊天") is a neutral fictional chat client,
  so no third-party trademarks appear.
- **Render**: `promo-kit/render.mjs` drives Chromium (puppeteer-core) and pipes
  PNG frames to ffmpeg (x264 CRF 14). `promo-*/score.py` composes the
  soundtrack with `promo-kit/synth.py`: one pad, a kick + sub pulse during demos,
  one bell per section, UI sounds tied to visible actions, and bed ducking
  under effects. The start/stop tones reproduce `SoundPlayer.playTone`.
- **Day-in-the-life**: flat SVG environments (`promo-day/scene/illus.js`), with
  the desktop rendered inside the laptop screen and a nested camera that
  pushes from the wide shot into the screen. The mux applies EBU R128 loudness normalisation
  (-16 LUFS, -1.5 dBTP).
- **Voice-over**: `promo-kit/voice.py` turns each promo's `voice.json` into
  clips via `elevenlabs text-to-speech convert_with_timestamps` (`eleven_v4`,
  `language_code=zh`). API output is cached by request hash, and tempo is
  applied locally with ffmpeg `atempo` because v4 ignores `speed`. Character
  timestamps re-time the dictation tokens and move key-up and everything after
  it; narration that would overrun pushes the next beat. `voice_check.py`
  transcribes each clip back with `scribe_v1` and reports the CER.
- **Non-goals**: no speed claims, no real-time screen recording.

## Safety and failure modes

- **Overclaiming offline or privacy**: the video carries a persistent footnote
  ("本地处理模式 · 需预先安装本地模型"), and the copy avoids absolute
  statements beyond local mode.
- **Implying measured speed**: the footnote "界面为动画重建，非实时录屏 ·
  实际速度取决于设备与模型" is on screen for the entire demo, and the video
  shows no numbers.
- **Feature claims**: translation, voice command, lexicon, style and
  model claims map to code (fact tables in each storyboard). Voice command
  scenes disclose the screen-recording permission. The models scene states
  that remote APIs send text to the chosen provider.
- **Illustrative cleanup output**: labelled "示例文本". The sample follows
  documented prompt rules, but it is not a captured model output.
- **Licensing**: icon and screenshots are project-owned, and the font is Noto
  Sans CJK SC (SIL OFL). Voice-over uses ElevenLabs Voice Library voices on a
  paid plan. ShanShan has a 90-day notice period and Evan Zhao a 730-day one;
  the clips already generated stay usable. All other audio is generated
  in-repo. The existing site sample
  `zh-sample.m4a` (macOS `say` output) is deliberately not used.

## Test strategy

Render QA stills at each beat and inspect them for legibility, overlap and
fact accuracy. Probe the final MP4 for format and duration. Measure loudness
and check that sound cues line up with `cues.json` events.

## Rollback

The work adds files only (voice clips are cached under each promo's `voice/`); delete `marketing/`, `scripts/render-promo.sh` and
this bundle. Nothing is published.
