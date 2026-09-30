# Intent: Record through an external mic when the MacBook lid is closed

**Status:** approved
**Approved-by:** User (conversation)
**Approved-date:** 2026-10-01
**Upstream:** User report in this conversation, 2026-10-01

## Problem

When a MacBook is used with an external display and the lid closed (clamshell
mode), the built-in microphone is physically disconnected in hardware, but
macOS still lists it in CoreAudio as a connected input device. Utter therefore
selects it, records silence, and never surfaces an error: the user speaks, sees
the overlay, and gets no text. This is the docked-at-a-desk case, which is a
primary usage context for a menu-bar dictation app.

## Outcome

While docked with the lid closed, Utter records from a usable external input
instead of the disconnected built-in microphone. If the lid closes mid-session,
capture moves to a working external input and the session continues. If no
usable input exists at all, the session ends immediately with a clear, localized
message instead of silently producing nothing.

## Scope

- Detect that the MacBook lid is closed, both before a session starts and while
  one is recording.
- Treat the built-in microphone as unavailable when the lid is closed, and
  classify CoreAudio input devices as built-in or external (including
  Continuity/iPhone, USB, Bluetooth, display, and aggregate inputs).
- Resolve a fallback: when the preferred input is the built-in mic and the lid
  is closed, automatically choose an available external input; otherwise honor
  the user's selected or system-default input.
- Fail over mid-recording when the active device becomes unusable, preserving
  the session so speech on both sides of the switch is transcribed.
- Fail fast with a localized error when no usable microphone exists.
- Leave the existing wireless-remote (Xiaomi) capture path unchanged.
- No change to model, LLM, insertion, or release behavior.

## Constraints

- Apple's built-in-mic disconnect on lid close is a hardware guarantee; no
  software (including Utter) can re-enable it. The fix is failover, not override.
- Never present silence as success: an unusable input must end in an error or a
  successful switch, never a silent no-op.
- Do not persist or log audio samples or transcript content; diagnostics stay
  numeric, consistent with `AudioCaptureDiagnostics`.
- Preserve existing consent and permission behavior; no new TCC prompts.
- Behavior on desktops without a lid (Mac mini/Studio) and on unlocked lids must
  not regress.

## Acceptance criteria

- With the built-in mic selected and the lid closed, a started session records
  from an available external input rather than the built-in mic (deterministic
  test over the resolver decision plus a docked real-device check).
- When the lid is closed and no external input is available, the session fails
  fast with a distinct localized message; it does not insert text, write the
  clipboard, or create a history entry.
- During a local session, if the active input stops being usable (lid closes
  over the built-in mic, or the device is removed), capture switches to an
  available external input without ending the session, and the final transcript
  includes speech captured on both sides of the switch.
- Continuity/iPhone and other non-built-in inputs are eligible fallback targets.
- With the lid open, the configured/system-default input is still used exactly
  as before.
- The wireless-remote path and its selection precedence are unchanged.
- `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, and
  `swift test` pass; en and zh-Hans localization keys stay in parity.

## Open questions

- When several external inputs exist, which should win? Current decision: the
  first available non-built-in input in CoreAudio enumeration order.
- Should an automatic switch show a transient status message, or only be logged?
  Current decision: log always; surface a brief status message only when the
  session continues, to be confirmed in spec.
- Mid-recording format change (device sample rate/channels differ): append to a
  single recording via conversion, or keep segments and concatenate at stop.
  Design detail for the spec stage.
