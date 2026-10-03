# Intent: Utter promo video series (offline, features, day-in-the-life)

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** Creative brief and follow-up feedback from the user in conversation, 2026-10-03

## Problem

Utter's strongest differentiator, fully local speech recognition and text
cleanup once models are installed, is stated in text on the site and README
but never demonstrated. Privacy-minded Mac users have no short, credible
artefact that shows dictation still working with the network switched off.

## Outcome

Three 16:9, 1920×1080, Simplified Chinese promos for the website and social
media, sharing one look and one render engine:

1. **Offline** (about 26 s, revised from 40 s after feedback that the pacing
   was loose and the background audio busy).
2. **Features** (about 45 s): smart format, voice command, translation
   dictation, industry lexicon, style presets, local or remote models.
3. **Day in the life** (about 52 s): scenario-driven office story ad.

For the offline cut, From it a viewer understands: with no network, natural speech
becomes clean text written straight into the current app, and the voice and
text stay on the Mac. The core line is "离线语音输入。你的声音，留在你的 Mac。"

## Scope

- In scope: the videos, their editable source (`marketing/`), a render entry
  point (`scripts/render-promo.sh`), storyboards and copy.
- Out of scope: app code, website changes, publishing to any channel, paid
  media, voice-over recording.

## Constraints

- Privacy claims are limited to local processing mode, with local models
  installed beforehand.
- No speed or performance numbers without real-device measurement. Any
  reconstructed or sped-up footage is labelled as such on screen.
- Real brand, real features, and assets cleared for public release. End card
  points to utter.idevlab.dev.
- Visual direction: bright, native-Mac look, off-white and silver base, blue-violet
  accent matching the icon, crisp motion.

## Acceptance criteria

- Each MP4 is H.264 + AAC, 1920×1080, 30 fps, at its planned length (26 / 45 / 52.5 s).
- Each story is readable without sound (captions, tags, on-screen spoken text).
- The background audio is a single pad, a soft pulse and sparse UI sounds tied
  to visible actions; the bed ducks under effects.
- Every on-screen product claim maps to source code or a real UI capture
  (see the fact table in each `marketing/promo-*/storyboard.md`).
- On-screen disclosure that the UI is a reconstruction and the sample text is
  illustrative. Local-mode and pre-installed-model disclosure wherever offline
  is claimed. A screen-recording permission note on voice-command scenes. A
  data-destination note for remote APIs.
- Voice-over (requested in the second feedback round) comes from the
  ElevenLabs CLI on the user's paid workspace. Every clip passes a
  speech-to-text round trip, and dictation captions are synced to the real
  audio. All other audio is synthesised in-repo.
- The editable source re-renders deterministically with one command.

## Open questions

- Should a real-device screen capture replace the reconstructed demo before
  public release? This is recommended for speed and offline proof.
- Voice-over: resolved by using ElevenLabs Voice Library voices ShanShan
  (speaker) and Evan Zhao (narrator).
