# Plan: Prevent unsolicited Qwen vocabulary insertion

**Status:** approved
**Approved-by:** User (conversation; confirmed revised implementation plan)
**Approved-date:** 2026-09-24
**Upstream:** [spec.md](spec.md)

This plan supersedes the 2026-09-23 plan. Existing code and tests remain in the draft PR; the items below describe only the redesigned work.

## Implementation sequence

- [ ] First establish red contract tests at the real seams: all three recorded-audio entry points, Qwen context and echo handling, dictionary snapshot and learning. Represent the reported long-list and `嗯。 -> Do anything` failures without copying private data into fixtures. Assert zero insertion, clipboard, command, and history effects on rejection.
- [x] Trace every snapshot consumer and source of target app/language. Make one effective snapshot carry the same scoped personal entries through ASR context, replacement, formatter hints, and protected terms. Preserve global manual terms and industry post-processing. Test unknown scope and evidence from different scopes.
- [x] Restore a bounded Qwen term prompt with effective personal entries only. Keep the established ASR interface where possible. Retain the exact per-call context for echo comparison. Test priority, deduplication, budget, and empty context; compare rare-word recognition with the installed model.
- [x] Route menu-bar, live integration, and imported audio through one recorded-audio speech decision and final transcript acceptance boundary. Reuse the existing classifier. Ensure provisional streaming text cannot become final output after rejection.
- [x] On Qwen context echo, retry the same audio once without context. Reject a remaining echo or retry failure before any external effect. Delete stale duplicate guards and obsolete full-list context code after the common contract passes.
- [x] Tighten correction-candidate and persisted learned-entry eligibility for short filler/non-speech sources. Prevent cross-scope evidence merges. Keep the user's local dictionary intact; test that the observed learned mapping is inert and a manual mapping still works.
- [x] Add fault-injection and end-to-end tests for classifier failure/no window/cancellation, retry failure, each output mode, short intentional phrases, English/Chinese speech, scoped vocabulary, and imported audio. Review privacy logging and split touched Swift files at real responsibility boundaries to keep them below 300 lines.

## Verification and delivery

- [x] Run focused red/green tests, then `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, and `swift test`.
- [x] Replay generated silence/noise and repository-owned speech through installed Qwen. Measure recognition with zero, one, and bounded relevant terms; test prompt echo and fallback. Do not save private microphone recordings.
- [x] Build a release-style app with `bash scripts/build-app.sh` and verify the assembled artifact.
- [ ] Perform real-window QA with the computer microphone once competing Utter instances can be avoided without disrupting the user's work. Record unavailable paths as unverified.
- [ ] Update `verification.md` with fresh evidence and residual risks. Check the PR against current `main` and resolve conflicts. Keep it draft pending independent verification, PR approval, and the separate signed-release/production decision.

## Human gate

The user approved this revised plan on 2026-09-24. Verification, independent review, and release retain their separate gates.
