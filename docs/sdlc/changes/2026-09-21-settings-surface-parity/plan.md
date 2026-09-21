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
- [x] Add `SettingsSurfaceTests` rendering the seams with `ImageRenderer`.

## Verification plan

- [x] `bash scripts/ci-basic-checks.sh`
- [x] `bash scripts/sdlc-checks.sh`
- [x] `swift test` (full suite)
- [ ] Real-window light/dark inspection of every settings tab and onboarding
      (reviewer), compared against System Settings.

## Human gates

- Intent, spec, and verification approval before merge.
- Reviewer confirms light and dark real-window appearance; this environment
  cannot drive the signed app window for screenshots.
