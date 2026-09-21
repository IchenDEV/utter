# Plan: Settings surface parity with System Settings

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** `spec.md`

## Work items

- [x] Add `SettingsSurface` with `page`, `card`, and `cardStroke` seams.
- [x] Point `SettingsView` and `settingsPageSurface()` at `SettingsSurface.page`.
- [x] Point `SettingsCardBackground` and the history overview cards at
      `SettingsSurface.card`.
- [x] Point the onboarding and permissions grouped boxes at the same seams.
- [x] Add `SettingsSurfaceTests` resolving the seams in sRGB and inside explicit
      light/dark appearances.
- [x] Capture real-window light and dark rendering from the running app.

## Verification plan

- [x] `bash scripts/ci-basic-checks.sh`
- [x] `bash scripts/sdlc-checks.sh`
- [x] `swift test` (full suite)
- [x] Real-window light and dark rendering of the Activity tab captured and
      inspected against System Settings.
- [ ] Reviewer confirms the remaining tabs and the onboarding window visually
      (they share the same seams; only the Activity tab was captured here).

## Human gates

- Intent, spec, and verification approval before merge.
- Reviewer confirms the remaining tabs and onboarding in light and dark.
