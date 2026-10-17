# Plan: Add in-app auto-update support

**Status:** approved
**Approved-by:** User, explicit chat decision: 批准 (the plan and its four reviewer decisions)
**Approved-date:** 2026-10-17
**Upstream:** [spec](spec.md)
**Risk:** High, release distribution, signing identity, new dependency/network path

## Delivery shape

Two PRs from one bundle, so the riskiest packaging change reaches production
before anything is turned on:

- **PR A, dormant integration.** Sparkle is linked, embedded, signed and
  verified, with the service, settings, and UI behind a configuration gate. No
  update keys exist anywhere, so every artifact is inert. Merging it makes the
  nightly pipeline propose a release that exercises real Developer ID signing and
  Apple notarization of the new nested code with no behavior change for users.
- **PR B, enable.** Appcast generation and signing, the committed update keys,
  the release-workflow steps, and the docs. It needs the owner's key ceremony.
  It is stacked on A and retargeted to `main` after A merges.

## Work items

### Phase 0, baseline (no repository behavior change)

- [ ] **P0.1** Download the published v0.0.55 DMG and record, for the main
  executable, the CLI helper, and every resource bundle: entitlements, signature
  flags, timestamp, architecture, and the rpath list. Save sanitized output to
  `evidence/baseline-v0.0.55.json`. Pass 1 of the new signing flow must reproduce
  these for existing content.
- [ ] **P0.2** Record local capabilities in `evidence/preflight.json`: Xcode and
  Metal toolchain availability, code-signing identities (none are present now),
  Python version (new scripts stay Python 3.9-compatible, standard library only),
  and whether the owner's installed `Utter.app` is running.
- [ ] **P0.3** Run `bash scripts/ci-basic-checks.sh` and `swift test` on the
  unchanged branch and record the result, so later failures are attributable.

### PR A, dormant integration

- [ ] **A1 Package and target.** `Package.swift`: Sparkle `exact: "2.10.0"` in the
  macOS branch; targets `UtterUpdates` and `UtterUpdatesTests`; `UtterUpdates`
  added to `builtinDependencies`; `Native/` excluded on non-macOS like siblings;
  `Package.resolved` updated. Record Sparkle's license and bundled notices.
- [ ] **A2 Contracts and setting.** `UtterContracts/UpdateService.swift`
  (`UpdateStatus`, `UpdateService`, `UpdateServices.updater`);
  `SettingsValues.automaticUpdateChecks` (default `true` when the key is absent)
  with `SettingsStore` load and persist and the `AppSettings` projection.
- [ ] **A3 Portable logic** in `Sources/UtterUpdates/`: `UpdateConfiguration`
  (the gate: `.app` bundle, https feed or loopback http, public key present, not
  ad-hoc), `UpdateStatusReducer` (driver events to status), `UpdateBusyGate`
  (postpone while busy, release exactly once, never after revoke). No AppKit or
  Sparkle imports in these files.
- [ ] **A4 Sparkle adapter.** `Native/SparkleUpdateDriver` (`SPUUpdater` with
  `SPUStandardUserDriver`, gentle-reminder delegate, postpone-relaunch hook) behind
  an `UpdateDriver` protocol; `Native/UpdatePlugins` registering `updates.sparkle`;
  add it to the platform group in `BuiltinPlugins`. The setting is applied before
  `startUpdater` and on change. Keep each file under 300 lines.
- [ ] **A5 Presentation.** `UpdateProjection` (optional service, so the UI hides
  when `unavailable`), an Updates section split into its own view file, the menu
  row, and `update.*` strings in `en` and `zh-Hans`.
- [ ] **A6 Packaging.** `build-app.sh`: embed, drop `XPCServices`, `lipo -thin`,
  add rpath before any signing, three-pass signing, and `--updates` with
  `--update-info <plist>` (required until PR B commits a default), which refuses
  ad-hoc signing and makes the internal verify call pass `--require-updater`.
  `build-and-run.sh`: embed, rpath, sign; never `--updates`.
  `verify-release-artifact.sh`: framework presence, no XPC, every Mach-O arm64,
  an `@rpath` resolution check that proves dyld can find Sparkle inside the
  bundle, certificate equality and hardened runtime for components under the
  existing signing flags, no entitlements on Sparkle components, `--require-updater`
  checks, and no `SU*` feed keys without it. Extend the fixtures in
  `scripts/tests/test_release_artifact.py` (missing framework, XPC present, x86_64
  slice, unresolved rpath, entitled component, stray `SU*` keys, ATS exception,
  feed or key mismatch).
- [ ] **A7 Docs.** One row in `AGENTS.md`'s module map and a Build & Release note.
- [ ] **A8 Verify and ship A** (see Verification plan, Part A).

### Gate: owner key ceremony (parallel to A, blocks B3)

- [ ] **G1** Owner follows spec section 6. The agent receives only the public key.

### PR B, enable updates

- [ ] **B1 Appcast generator.** `scripts/generate-appcast.py` (standard library
  only) plus `scripts/tests/test_generate_appcast.py`: golden XML, enclosure URL
  built from a validated tag, version mismatch rejected, XML escaping, plain-text
  notes from `git log` over the tag range.
- [ ] **B2 Independent signature verifier.** `scripts/verify-update-signature.swift`
  (CryptoKit) plus a test using a throwaway key generated in the test: valid,
  tampered, wrong key, malformed input, and the feed signature block.
- [ ] **B3 Committed configuration.** `Resources/UpdateInfo.plist` with the real
  public key; `scripts/sparkle-tools.sha256` computed from a downloaded
  `Sparkle-2.10.0.tar.xz` and cross-checked against the GitHub asset digest;
  `ci-basic-checks.sh` lints the plist (https URL, key decodes to 32 bytes, every
  required key at its specified value). `--updates` then defaults to this file.
- [ ] **B4 Workflow.** `release-artifact.yml`: add the secret to the credentials
  check; build with `--updates`; verify with `--require-updater`; the **Sign update
  metadata** step; upload the appcast to the draft; extend the download-and-compare
  check. Extend `test_release_workflow_contract.sh`: step order, secret required,
  no key in argv or traces, and no `--update-info` in any workflow.
- [ ] **B5 Docs.** `github-controls.md` (secret, ceremony), `release-runbook.md`
  (withdraw, rotation, first-release note, rehearsal), and both READMEs (network
  contents, and that the first updater release is installed manually once).
- [ ] **B6 Rehearsal** (below) and evidence.
- [ ] **B7 Verify and ship B** (see Verification plan, Part B).

### Rehearsal procedure

The owner's installed `Utter.app`, settings, permissions, and production signing
key are never touched.

- Use a temporary keychain holding a throwaway self-signed identity and a
  throwaway EdDSA key under a distinct `--account`. Delete both afterwards. The
  login keychain and production key are not used.
- Re-identify the rehearsal builds (`CFBundleIdentifier` and bundle name), install
  them under a temporary directory, and run them only while the owner's Utter is
  quit, because the hotkey and XPC names are shared.
- Serve the feed and DMGs from `127.0.0.1` with a rehearsal-only plist passed via
  `--update-info`, adding local-networking ATS for that plist only.
- Scenarios: S1 up to date; S2 newer version, consent, install, relaunch, new
  version shown; S3 permissions and launch-at-login persist; S4 tampered DMG;
  S5 bad EdDSA signature; S6 unsigned feed; S7 older version; S8 feed over remote
  http refused; S9 toggle off gives zero server requests, toggle on gives one;
  S10 restart held during an active recording, released at idle; S11 process killed
  mid-install leaves a working app; S12 App Management prompt observed for the
  self-signed identity; S13 rollback (swap the served "latest") offers the
  earlier release; S14 launch smoke of the packaged app.
- Capture sanitized evidence: logs, server request log, `codesign -dvv` and
  entitlements, and real-window screenshots (light, dark, narrow; `en` and
  `zh-Hans`, including Sparkle's own alert).

## Verification plan

Part A (before PR A):

- [ ] `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, `swift test`.
- [ ] Release-style local build with the throwaway self-signed identity (if the
  Metal toolchain and identity allow), then `verify-release-artifact.sh` passes;
  otherwise rely on the CI `build` job and disclose the gap.
- [ ] Nested signatures, entitlements, and flags of the helper and resource bundles
  equal the P0.1 baseline; Sparkle components carry none.
- [ ] Default build has no `SU*` keys; `--updates` with ad-hoc signing is refused.
- [ ] Packaged app launches (S14) and the Updates UI is hidden when inert.
- [ ] Independent verifier reruns the risk-critical checks and reports.
- [ ] PR CI, including `SDLC Gate`, is green on the exact head.
- [ ] After merge, the dormant release run passes real Developer ID signing,
  Apple notarization, stapling, and Gatekeeper; the installed result launches and
  dictates normally.

Part B (before PR B; `verification.md` returns to `pending approval`):

- [ ] The same three commands, plus the new script tests, workflow contract test,
  and `--require-updater` fixture cases.
- [ ] Rehearsal S1 to S14 recorded, with a captured update request matching the docs.
- [ ] A dry run of the new workflow steps against fixture inputs with a throwaway
  key proves fail-closed behavior: missing secret, wrong key, tampered DMG.
- [ ] Independent verifier reruns the risk-critical checks and reports, covering
  the rollback steps.
- [ ] PR CI is green on the exact head.
- [ ] After merge, the first updater release passes its protected run, and the next
  release is observed updating a real Developer ID install, recording permissions,
  launch-at-login, and restart behavior.

## Human gates

- Approval of this plan, then of `verification.md` before each PR.
- The key ceremony (G1) and handing over the public key.
- Owner quitting Utter before the GUI rehearsal, and consent to a temporary
  keychain (not the login keychain).
- Independent verification and the owner's explicit merge authorization for each PR.
- A concrete protected `production` approval for the dormant release and again
  for the first updater release. Each must name the run.
- The owner performing the first real update on their own install.

## Stop conditions

Stop and report, without working around it, if: P0.1 shows the baseline cannot be
reproduced by pass 1; signing or notarization of the nested code fails; the
packaged app does not launch; a verifier check cannot be made deterministic; the
rehearsal loses a permission or mishandles a busy restart; any pre-publish check
fails; the secret is missing; or the shipped public key does not match the signature.

## Plan decisions for the reviewer

1. **Two PRs and a dormant release.** This adds one release before updates turn
   on, in exchange for proving the nested-code signing and notarization in
   production first. Say if you prefer a single PR.
2. **Rehearsal isolation.** Re-identified builds and a temporary keychain mean the
   rehearsal proves the mechanism with a different identity. Production-identity
   permission persistence is proven only by the first real update.
3. **Release notes** in the appcast come from `git log` subjects over the tag
   range, as plain text, rather than the GitHub-generated notes.
4. **One bundle, two verifications.** `verification.md` is approved once per PR
   and reopens for Part B.
