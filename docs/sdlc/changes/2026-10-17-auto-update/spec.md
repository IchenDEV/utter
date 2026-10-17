# Spec: Add in-app auto-update support

**Status:** approved
**Approved-by:** User, explicit chat decision: 批准 (the design and its five reviewer decisions)
**Approved-date:** 2026-10-17
**Upstream:** [intent](intent.md)
**Risk:** High, release distribution, signing identity, new dependency/network path

## Context

Facts below were checked against the repository, Sparkle 2.10.0 source, and a
throwaway SwiftPM spike (`swift build` and `xcodebuild` Release of an executable
depending on Sparkle 2.10.0).

Repository:

- `release-artifact.yml` is the one pipeline for both the tag and nightly entry
  points. It signs, verifies, notarizes, checksums, creates a **draft** release,
  uploads, re-downloads and compares, then publishes with `--draft=false --latest`.
- `scripts/build-app.sh` hand-assembles the `.app` from an `xcodebuild` product,
  signs it once with `codesign --force --deep --options runtime --entitlements`,
  then builds the DMG. `scripts/build-and-run.sh` is the separate `swift build`
  development path and copies only the binary. `verify-release-artifact.sh`
  checks arm64-only for the executable and CLI helper, and compares the DMG app
  to the built app.
- Services are `ServiceKey`s in `UtterContracts`; owner targets register them as
  `PluginRegistration`s; only `UtterBuiltins` imports siblings; native code sits
  under `Native/` and is excluded from the portable build.
- Busy signals already exist: `SessionExecutionSnapshot.isBusy` and
  `ModelCatalogSnapshot.isBusy`. Termination already runs `application.stop()`
  under `.terminateLater` in `AppDelegate`.
- The app is an `LSUIElement` agent that types into other apps, so a window that
  steals focus mid-dictation is a real defect.

Sparkle 2.10.0:

- Distributed as an SPM binary target (checksum pinned in its own manifest).
  `swift build` leaves `Sparkle.framework` beside the binary with rpath
  `@loader_path`; `xcodebuild` leaves it in `Products/Release/` with rpath
  `@executable_path/../lib`. Neither places it inside an `.app`, so packaging
  must copy it and add an rpath.
- The framework is universal (x86_64 + arm64, 2.9 MB), ships `XPCServices`
  (needed only by sandboxed hosts), `Autoupdate`, and `Updater.app`, all ad-hoc
  signed.
- Validation accepts an update when either its EdDSA signature or its Apple code
  signature matching the installed app is valid. Without any EdDSA key it logs
  that code-signing-only is deprecated, and `SURequireSignedFeed` plus
  `SUVerifyUpdateBeforeExtraction` cannot be enabled. This confirms decision B.
- A signed feed is a trailing `<!-- sparkle-signatures: ... -->` comment.
  `sign_update` accepts the key on stdin (`--ed-key-file -`).
- For agent apps, Sparkle's default shows a scheduled update window immediately
  behind other apps. The delegate can take over presentation (gentle reminders)
  and `checkForUpdates()` then brings the standard alert forward on demand.

## Design

### 1. Dependency and ownership

- `Package.swift`: add `Sparkle` with `exact: "2.10.0"`, only in the `#if os(macOS)`
  branch. The portable (non-macOS) graph stays Sparkle-free. The license and
  bundled notices are recorded in `verification.md`.
- New target `UtterUpdates` (+ `UtterUpdatesTests`). Portable files hold the
  status reducer, busy gate, configuration gate and settings sync. The Sparkle
  adapter lives in `Native/`. It depends on `UtterRuntime` and `UtterContracts`
  (and Sparkle on macOS). Only `UtterBuiltins` imports it. `AGENTS.md`'s module
  map gets one row.
- Contract in `UtterContracts`: `UpdateStatus` (`unavailable`, `idle`, `checking`,
  `upToDate`, `available(version)`, `pendingRestart`, `failed(message)`) and an
  `UpdateService` protocol (`status`, `observe`, `checkForUpdates()`), keyed
  `UpdateServices.updater`. Presentation depends only on this.
- Plugin `updates.sparkle` requires `DataServices.settings` and
  `IntegrationServices.diagnostics`, optionally `SessionServices.execution` and
  `ModelServices.catalog`. It starts in `onReady`, stops scheduling in `onRevoke`,
  and releases the updater in `onDispose`. It is added to the platform group in
  `BuiltinPlugins`.
- `SettingsValues.automaticUpdateChecks` (default `true`, key absent means true)
  follows the `remoteMicEnabled` path through `SettingsStore` load/persist and the
  `AppSettings` projection.
- Presentation: an `UpdateProjection` observable (as `PlatformProjection` does),
  an "Updates" section on the About page (Check for Updates… button, status line,
  automatic-checks toggle), and one menu row that reads "Check for Updates…" or
  "Update Available — vX". All strings are `L("update.*")` in `en` and `zh-Hans`.
  The projection is optional, so a build without an updater hides the section.

### 2. Runtime behavior

- **Configuration gate.** The updater is created only when the main bundle is a
  `.app` carrying an `https` `SUFeedURL` (plain `http` accepted only for a
  loopback host, for the staged rehearsal) and a `SUPublicEDKey`, and is not
  ad-hoc signed. Otherwise status is `unavailable`, no Sparkle object exists, and
  there is zero network activity.
- **Opt-in by construction.** The update keys are not in `Resources/Info.plist`.
  They live in a committed, linted `Resources/UpdateInfo.plist` that
  `build-app.sh --updates` merges into the app plist. A development, PR, or
  manual build therefore cannot update itself into a production release, which
  would otherwise destroy a developer's build. `--updates` refuses ad-hoc signing.
- **Keys in `UpdateInfo.plist`:** `SUFeedURL`
  (`https://github.com/IchenDEV/utter/releases/latest/download/appcast.xml`),
  `SUPublicEDKey`, `SURequireSignedFeed=true`, `SUVerifyUpdateBeforeExtraction=true`,
  `SUEnableAutomaticChecks=true` (stops Sparkle's own permission prompt; the About
  toggle is the consent surface), `SUAllowsAutomaticUpdates=false`,
  `SUAutomaticallyUpdate=false`, `SUScheduledCheckInterval=86400`,
  `SUSendProfileInfo=false`. No `SUEnableInstallerLauncherService`,
  `SUEnableDownloaderService`, or ATS exceptions.
- **Consent and scheduling.** `SettingsService` is the source of truth: it sets
  `automaticallyChecksForUpdates` before `startUpdater` and on every change,
  overriding Sparkle's own stored value. With the toggle off no scheduled check
  runs. Nothing downloads or installs without the user choosing Install Update in
  Sparkle's standard alert, which also offers Skip This Version and Remind Me
  Later.
- **Gentle presentation.** The user-driver delegate sets
  `supportsGentleScheduledUpdateReminders`, returns `NO` from
  `standardUserDriverShouldHandleShowingScheduledUpdate`, and records status
  `available`. A scheduled find only changes the menu row and About status: no
  window, no focus change, no notification permission. A user-initiated check or
  clicking the row calls `checkForUpdates()` and Sparkle shows the standard alert.
- **Safe restart.** `shouldPostponeRelaunchForUpdate` holds the relaunch while the
  session or model-catalog snapshot is busy, shows `pendingRestart`, and releases
  exactly once when both go idle. Relaunch goes through the existing
  `applicationShouldTerminate` drain. If the drain fails, the staged update
  applies at the next quit; nothing is force-killed.
- **Network disclosure.** A check is one HTTPS GET of the feed, redirected by
  GitHub to its CDN, with Sparkle's User-Agent (app name, version, Sparkle
  version) and the IP address inherent to any request. A download is one GET of
  the DMG. Nothing else is sent: no profile, no identifier, no usage data. The
  README and About text say so.

### 3. Packaging

Both packaging paths always embed the framework, because the executable links it.
`build-app.sh`, after assembly:

1. `ditto` `Sparkle.framework` into `Contents/Frameworks/`.
2. Delete `Versions/B/XPCServices`.
3. `lipo -thin arm64` every Mach-O in it (Sparkle, `Autoupdate`,
   `Updater.app/Contents/MacOS/Updater`) to keep the arm64-only invariant.
4. `install_name_tool -add_rpath @executable_path/../Frameworks` on the main
   executable, before any signing. The CLI helper must not link Sparkle.
5. Sign in three explicit passes: (1) the existing `--deep` pass, unchanged, so
   the helper and resource bundles keep today's flags; (2) re-sign Sparkle's
   nested code inside-out (`Autoupdate`, `Updater.app`, `Sparkle.framework`) with
   `--options runtime` and the same timestamp policy as the app but **no
   entitlements**; (3) re-seal the app without `--deep`, same entitlements and
   options as pass 1. `--deep` alone would hand `Autoupdate`, the process that
   replaces the installed app, JIT, unsigned-memory and library-validation-off
   entitlements it does not need.

`build-and-run.sh` copies the framework, adds the rpath, and signs likewise, but
never passes `--updates`, so the development app is inert.

`verify-release-artifact.sh` gains `--require-updater`. It checks that the
framework is present with no `XPCServices`; every Mach-O is arm64-only, signed by
the app's certificate SHA-256, hardened-runtime, and (Developer ID) timestamped;
Sparkle components carry no entitlements; the main executable has the rpath; the
CLI helper does not link Sparkle; and the plist update keys equal the committed
`UpdateInfo.plist`, are https, and have no ATS exception. Without the flag it
requires that no `SU*` feed keys exist, so non-release builds are provably inert.
`check-resource-bundles.py` must still pass with the framework present.

### 4. Release pipeline

- New protected secret `SPARKLE_ED_PRIVATE_KEY` in the `production` environment,
  checked in the existing credentials step so a missing key fails before any
  build or draft. The build step passes `--updates`.
- New step **Sign update metadata**, after "Verify distribution and checksum" and
  before "Publish GitHub Release":
  1. Download `Sparkle-2.10.0.tar.xz` from Sparkle's release, require its pinned
     SHA-256 (committed in the repo) before unpacking, and use only `sign_update`.
  2. Sign the DMG: `printf '%s' "$KEY" | sign_update --ed-key-file - <dmg>`. The key
     is passed only through this step's environment, never argv, never `set -x`.
  3. `scripts/generate-appcast.py` writes a one-item `appcast.xml`: enclosure URL
     built from the validated tag, `sparkle:version` and `shortVersionString` read
     from the verified DMG's app plist and cross-checked against the release
     version, `minimumSystemVersion` 26.0, `hardwareRequirements` arm64, embedded
     release notes in a non-HTML format, and the DMG's EdDSA signature and length.
  4. Sign the feed with `sign_update`.
  5. **Independent verification.** A pinned `scripts/verify-update-signature.swift`
     using CryptoKit verifies the DMG signature and the feed signature against the
     `SUPublicEDKey` taken from the app inside the mounted DMG. This proves
     the secret matches the public key shipped to clients, so a wrong or rotated
     key cannot silently strand every installed copy.
- The appcast is uploaded to the **draft** release beside the DMG and checksum.
  The existing download-and-compare check covers it. `--draft=false --latest`
  then makes the DMG and feed reachable in one atomic step. Any failure leaves a
  draft, as today. Both entry points inherit this because they share the workflow.
  `test_release_workflow_contract.sh` is extended for step order, the required
  secret, and the absence of the key from argv and traces.

### 5. Hosting and rollback model

The feed URL is GitHub's `releases/latest/download/appcast.xml`, resolved by the
release marked latest. Each release carries its own immutable one-item appcast,
so no asset is ever replaced.

- **Withdraw a bad release:** `gh release edit <bad> --prerelease` and
  `gh release edit <good> --latest`. Clients on older versions are then offered
  the good release. Clients already on the bad version see nothing newer and are
  not downgraded (Sparkle compares versions), so they are fixed forward with a
  higher version. Nothing is deleted.
- **Code rollback:** a revert PR removes the updater from future releases.
  Already-installed copies keep polling the feed; withdrawal above is the control
  point that decides what they are offered.
- **Key loss or compromise:** because either an EdDSA or a matching Developer ID
  signature validates, a release signed with Developer ID can carry a new
  `SUPublicEDKey`. The runbook records this rotation and the quarterly audit
  checks the secret exists.

### 6. Key ceremony (owner only)

The agent never sees the private key.

1. The owner downloads the same pinned Sparkle tools and runs `generate_keys`
   locally; the private key stays in the login keychain.
2. The owner exports it (`generate_keys -x`), runs
   `gh secret set SPARKLE_ED_PRIVATE_KEY --env production < file`, deletes the file,
   and keeps an offline backup.
3. The owner gives the agent only the public key (`generate_keys -p`), which is
   committed to `Resources/UpdateInfo.plist`.

The public key is needed before the PR is final; the secret is needed before the
first production run. Both gates fail closed. `github-controls.md` and
`release-runbook.md` document the secret and the rotation and withdrawal steps.

## Safety and failure modes

| Failure | Containment |
|---|---|
| Feed unreachable | Scheduled check stays silent, manual check reports a localized error, next interval retries. Dictation is unaffected. |
| Feed unsigned or signature invalid | Rejected by `SURequireSignedFeed`; install untouched. |
| DMG tampered or wrong EdDSA signature | Rejected before the archive is opened (`SUVerifyUpdateBeforeExtraction`). |
| Older or equal version advertised | Never offered; no downgrade. |
| Feed over plain http | Configuration gate refuses the updater; ATS blocks it; the verifier forbids it in release artifacts. |
| Wrong or missing key in CI | Step fails before publish, leaving a draft. |
| Mismatch between secret and shipped public key | Caught by the independent CryptoKit check before publish. |
| App not writable, translocated, or run from the DMG | Sparkle reports an error; install untouched; status `failed`. |
| Relaunch requested while recording, processing, committing output, or downloading a model | Relaunch is held until idle; the user keeps working. |
| Termination drain fails | Staged update applies at next quit; no force kill. |
| Power loss or crash during replacement | Relies on Sparkle's staged replace; rehearsed once with a kill in the staged run. Residual vendor-trust risk. |
| Development, PR, or manual build | Inert by omission; the verifier and `--updates` ad-hoc refusal enforce it. |
| Focus theft | Scheduled finds never open a window. |
| Self-signed release mode | Works with the EdDSA key, but macOS may show an App Management prompt for a non-Team-ID self-update. Observed in the staged run and documented. Developer ID is the production path. |
| Private key leak | Rotation and withdrawal runbooks. Anyone holding both the key and the Developer ID certificate is as powerful as the CI itself; this is accepted trust, not mitigated further. |

Entitlements, bundle identifier, signing identity, and permission prompts are
unchanged. No ATS exception, notification permission, or telemetry is added.

## Test strategy

| Acceptance criterion | Evidence |
|---|---|
| Newer / same / older feed outcomes | `UtterUpdatesTests`: Sparkle callbacks map to `UpdateStatus` through a fake driver. Staged rehearsal against real Sparkle with a local feed, a throwaway EdDSA key and a self-signed test identity. |
| Manual check, four states, localization, appearance | Menu and About views plus string-key parity (existing localization lint). Real-window light, dark, narrow-width, `en` and `zh-Hans` screenshots, including Sparkle's own alert in `zh-Hans`. |
| Setting persists; off means no request | Settings round-trip and default-true tests; fake driver proves no start or check when off; staged run counts local-server requests with the toggle off and on. |
| Negative cases leave install untouched | Pipeline level: `scripts/tests` for the appcast generator (golden XML, version mismatch, escaping) and the CryptoKit verifier (valid, tampered, wrong key). App level, in the staged run: tampered DMG, bad signature, unsigned feed, older version, http feed. |
| Update keeps permissions | Real Developer ID install updated to a newer signed build, checking Accessibility, Microphone, Speech, Screen Recording, and launch-at-login survive. First real evidence is N to N+1 after the first updater release. |
| No restart while busy | Busy-gate tests: postpone while busy, release exactly once at idle, no release after revoke. Staged run during an active recording. |
| Network contents match the docs | A captured request in the evidence. |
| Pipeline signs only verified artifacts, fails closed | `test_release_workflow_contract.sh` (order, secret, no key exposure), plus `test_release_artifact.py` fixture cases for `--require-updater` (missing framework, XPC present, x86_64 slice, ATS exception, wrong feed or key, entitled Sparkle component, `SU*` keys in a non-updater build). |
| Packaging verified | `verify-release-artifact.sh --require-updater` on a real release-style Developer ID build; `ci-basic-checks.sh`, `swift test`, SDLC checks. |
| Rollback rehearsed | The runbook steps run on the staged feed with a test release. |

Real-installer, relaunch and permission behavior cannot run in CI (it needs a GUI
session, signed apps, and minutes of builds). It is covered by the staged rehearsal
run by the implementer and repeated by the independent verifier, and by the
first production update. That gap is listed as residual risk, not hidden.

## Rollout and rollback

1. Owner key ceremony, then the public key is committed.
2. Implementation PR, CI, independent verification, staged rehearsal evidence.
3. Merge only with the owner's explicit authorization.
4. The next nightly run will build and propose the first updater release from
   `main`. It still needs the protected `production` approval, and fails closed
   without the secret. Users install that release manually once.
5. The release after it is the first real update. Observe it on a real install and
   record permissions, launch-at-login and restart behavior in `verification.md`.

Stop if any pre-publish check fails, the secret is missing, the shipped public
key does not match the signature, or the rehearsal loses a permission or
mishandles a busy restart. Rollback is the withdrawal and revert paths in the
Hosting section, with no deleted assets and no replaced same-version files.

## Reviewer decisions

These deviate from, or sharpen, the approved intent's wording. Please accept or
redirect each one explicitly.

1. **Different-identity negative test.** Sparkle accepts an update when its EdDSA
   signature is valid even if the code-signing identity differs. That is the
   continuity benefit chosen with decision B. The intent's "replacement signed
   by a different identity" case therefore means a replacement that is signed by
   a different identity **and** lacks a valid EdDSA signature. A validly
   EdDSA-signed update with a different identity is prevented upstream by the
   pipeline's existing certificate-fingerprint check, not by the client.
2. **Metadata timing.** The intent says metadata is published only after the
   release is public. Uploading the appcast to the draft and publishing with the
   DMG gives the same observable guarantee, since neither is reachable earlier. It
   avoids the alternative's gap, where `latest` would point at a release with no
   appcast and every client check would briefly fail.
3. **Discoverability.** With no notification permission and no change to the menu
   bar icon, an available update shows in the menu row and About page only. Say if
   you want an icon indicator or a notification, which would add an asset or a
   permission.
4. **Pinned tool download.** The pipeline fetches Sparkle's tool archive at run
   time and verifies a committed SHA-256, rather than vendoring the binaries.
5. **Arm64 thinning and XPC removal.** The framework is thinned and its XPC
   services removed to keep the arm64-only invariant and a smaller notarized
   surface. This modifies a vendor binary before re-signing.
