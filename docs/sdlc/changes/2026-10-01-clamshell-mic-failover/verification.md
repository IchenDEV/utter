# Verification: Record through an external mic when the MacBook lid is closed

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `plan.md` (approved 2026-10-01)

## Evidence

| Check | Result | Evidence |
|---|---|---|
| `bash scripts/sdlc-checks.sh` | Pass | `SDLC checks passed.` |
| `bash scripts/ci-basic-checks.sh` | Pass | `Basic CI checks passed.`; both `Localizable.strings` lint OK and key parity holds |
| `swift test` | Pass | `808 tests, 18 skipped, 0 failures` (20.4s); run with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` because the CommandLineTools SDK has no XCTest |
| Docked MacBook manual check | Not run | Requires physical docked hardware; see residual risk |

## Acceptance criteria

- Built-in mic selected + lid closed records from an external input — covered by
  the resolver tests (`testLidClosedReplacesPreferredBuiltInWithExternal`) and
  the `MicFailoverDecision` test; real-device check not run.
- Lid closed + no external input fails fast with a localized message and no
  insertion/clipboard/history side effect — `testLidClosedWithOnlyBuiltInIsUnavailable`
  and `testFailoverFailsWhenActiveLostWithNoAlternative`; the pipeline sets
  `.error` and returns before `commitRecording`, so no output path runs. Real
  device not run.
- Mid-session lid close continues the session and transcribes both sides —
  decision logic covered by `testFailoverSwitchesWhenLidClosesOverBuiltIn`; the
  engine restart and `AVAudioConverter` path is not exercised by hardware here.
- Continuity/iPhone and other non-built-in inputs are eligible fallbacks —
  `testContinuityIPhoneIsEligibleFallback` and
  `testPreferredExternalAlwaysWinsWhenUsable`.
- Lid open preserves the configured/default input; remote path unchanged —
  `testLidOpenHonorsPreferredBuiltIn`, `testLidOpenWithNoDefaultStillUsesBuiltIn`;
  the remote branch in `start` is untouched.
- Localization parity and repository checks pass — Pass (`ci-basic-checks.sh`).

## Residual risk

- Bluetooth/Continuity fallback may add latency or lower fidelity.
- A failover seam may drop up to the watchdog interval (≤0.5s) of audio.
- The real capture failover (engine restart + format conversion) and the
  localized no-input message have not been exercised on physical docked
  hardware in this environment; a maintainer must run the docked check before
  merge.
- `swift test` needs the Xcode toolchain in this environment; plain `swift test`
  fails before compiling because the CommandLineTools SDK lacks XCTest.

## Decision

Implementation complete; awaiting human verification approval and the real
docked-device check before PR approval.
