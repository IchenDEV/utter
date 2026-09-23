# Verification: Input execution ownership

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** plan.md

User-authorized per-stage waiver: 2026-09-24. Local automated verification is complete; no independent human acceptance or release approval is claimed.

- Baseline before implementation: 756 XCTest cases, 16 skipped, zero failures; one Swift Testing case passed.
- New test scaffolding initially failed compilation because the ownership interface did not exist. This was not a runtime counterexample against the old implementation.
- Initial targeted pass: 26 tests, zero failures.
- Expanded targeted pass: 29 tests, zero failures.
- Intermediate full suite: 760 tests, 16 skipped, two assertions failed in a legacy test that fabricated recording UI state without starting a session. Updated the test to traverse the real pipeline start with a fake capture/engine, then cancel and await cleanup.
- Final full suite: `swift test` passed, 768 XCTest cases, 16 skipped, zero failures; one Swift Testing case passed. Log: `/tmp/utter-session-complete-tests.log`.
- Final focused ownership/cancellation/overlay pass: 26 cases, zero failures, including the isolated-clipboard tests. Log: `/tmp/utter-session-last-regression.log`.
- `xcodebuild -scheme OpenType -configuration Release -derivedDataPath .build/xcode -destination 'platform=macOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build -quiet`: exit 0. Log: `/tmp/utter-session-complete-release.log`. Verified Release/OpenType and mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib exist. Existing dependency/compiler-mode warnings remain; no build failure.
- `bash scripts/sdlc-checks.sh` and `bash scripts/ci-basic-checks.sh`: passed. Logs: `/tmp/utter-session-sdlc.log`, `/tmp/utter-session-basic.log`.
- `git diff --check`: passed. No dependency lockfile change or conflict markers. No PR created, so remote mergeability/CI were not evaluated.
- Application Swift source: 211 -> 215 files; 31,566 -> 31,675 physical lines (+109). This change fixes ownership and removes duplicate loading logic; it does not claim a broad file-count reduction.

## Contract evidence

| Contract | Evidence |
|---|---|
| Reserved during preparation/file work | testFilePreparationBlocksMenuBarAndCancellationCannotStartCapture |
| Cancellation drains before reuse | testCancelledLeaseRemainsBusyUntilWorkDrains; testCancelledTranscriptionCannotPublishOrReleaseNextSession |
| Key release during local preparation | testMenuBarReleaseDuringPreparationPreventsLateStart; existing remote pipeline regression suite |
| Client-scoped cleanup and authorization | testDisconnectOfAnotherClientDoesNotCancelOwner; testUnauthorizedCancelCannotReleaseResources |
| Frozen choices | testSettingsAndEngineSelectionAreFrozenAtAdmission |
| Terminal result/history commit | testTerminalCommitWritesHistoryExactlyOnce; testCancelledSessionCannotCommitPreparedHistory |
| Failure releases reservation | testMissingEngineReleasesReservationAndFailsSession |
| Cancel before paste and preserve clipboard | TextInsertionCancellationTests (unique test pasteboards and injected paste callback; no keyboard events sent) |
| Source-preserving fidelity fallback | TextProcessorFallbackTests now exercise validatedOutput rather than the removed identity wrapper |

## Review findings resolved

A cancelled caller previously could reach paste after target activation or the clipboard delay. Added boundary checks, preserve all clipboard types, and avoid overwriting newer clipboard changes. Already-posted keys are allowed to finish their key-up/clipboard-read interval; cancellation is not an undo operation.

Formatting preload participates in the shared reservation, and unload no longer discards the processing-task handle before drain. ASR preparation is retained and awaited through stop/cancel. Model selection and late audio-level/partial callbacks are bound to the recording rather than current mutable settings.


## Evidence boundaries

Controlled fake-engine tests exercise real coordinator and pipeline entry functions without model downloads, microphone permissions or typing into another app. They do not prove real ASR accuracy, physical Xiaomi remote operation, third-party XPC clients, or production signing/notarization. No dependency, stored-data, prompt, lexicon or API payload migration is performed.
