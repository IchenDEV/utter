# Plan: Xiaomi Remote 2 Pro connection and settings page

**Status:** approved
**Approved-by:** User (conversation: "完成调研后开始实现，无需审批")
**Approved-date:** 2026-10-07
**Upstream:** `spec.md` (approved 2026-10-07)

## Work items

- [x] Add `RemoteMicDeviceMatcher`, discovery/capture enums, and diagnostics.
- [x] Add `lowNibbleFirst` to `RemoteMicADPCMDecoder`.
- [x] Retrieve connected peripherals, scan unfiltered, filter candidates.
- [x] Read the Device Information model and select the nibble order.
- [x] Record the capture source; add `reconnectNow()`.
- [x] Add the Remote settings tab, move controls out of General, localize.
- [x] Add unit tests for matching, nibble order, discovery routing, stale model
      reads, and settings text.
- [x] Revision: host-initiated sessions, `MIC_EXTEND`, silence fallback, and the
      updated Remote tab text and diagnostics.
- [x] Review corrections: model/capability readiness gate, unnamed connected
      ATVV devices, truthful local/cloud audio copy, and callback regressions.
- [x] Run SDLC/CI checks, `swift test`, and a release-style app build.
- [x] Open PR #122 and build the local downloadable test DMG; final hosted CI and
      real-device verification remain separate acceptance steps.
- [x] 2026-10-10: merge main, migrate the feature into its scoped plugin modules,
      resolve all conflicts, and verify the signed release app before pushing.
      The unchanged OCR test failure and pending UI/hardware checks are recorded
      separately in verification.md.

## Verification plan

- Automated: `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`,
  `swift test`.
- Build: `bash scripts/build-app.sh --app-only`, or the PR's release-style build.
- Manual (needs the real remote): pair the remote, enable the feature, confirm
  the Remote tab reaches Connected with its model, hold the voice key, and
  confirm "Last recording" reports the remote microphone and the text is
  intelligible.
