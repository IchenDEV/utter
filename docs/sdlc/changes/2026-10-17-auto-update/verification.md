# Verification: Add in-app auto-update support (Part B, enable updates)

**Status:** approved
**Approved-by:** User, explicit chat instruction `pr & merge & release` after the verification handoff and deferred-test list
**Approved-date:** 2026-10-21
**Upstream:** [plan](plan.md)
**Risk:** High, release distribution, signing secret, new network path

`verification.md` is approved once per PR (plan, "One bundle, two
verifications"). It holds **Part B, enable updates**. Part A (PR #127, dormant
integration) is merged as `077f6d8`; its approved record is in git history and in
PR #127. Part B starts at `d994b9b` on `t3/enable-auto-update`, with the
2026-10-19 corrections recorded below. The owner authorized PR creation and
merge on 2026-10-21 after receiving the results and remaining test list.
Deferred tests remain unverified. A protected production approval must name
the actual workflow run separately.

## Delivery progress, 2026-10-21

PR #129 merged the independently reviewed dormant packaging and Settings
corrections as `39391a6224c3e3c09cedf2e5069ab8663ec87254`. Its exact source head
`1edb28da76e9e2e55a29d2c1ebacb6445c0df6fd` passed Contract & Tests,
Release-style App Build and SDLC Gate in
[run 39460559529](https://github.com/IchenDEV/utter/actions/runs/39460559529).
The dormant [delivery record](evidence/dormant-delivery-20261021.json) and
[independent review](evidence/dormant-independent-review-20261021.md) are retained.
Production signing, notarization and published-artifact verification remain
pending. PR #128 stays draft until that release is verified.

PR #128 source head `ca7356cc3d69f37a42c822153529caf69ad768a8` passed the same
three checks in
[run 39459653509](https://github.com/IchenDEV/utter/actions/runs/39459653509).
Merging current main changes documentation only relative to that candidate;
CI must pass again on the resulting head. The owner repeated the instruction
to merge and release automatically; protected approvals still name each run.

## Scope of Part B

Updates are turned on for release builds only. `Resources/UpdateInfo.plist`
commits the feed URL and the public key; `build-app.sh --updates` now defaults to
it, so the release pipeline arms the updater without naming a plist. The pipeline
generates a one-item `appcast.xml` from the verified DMG, signs the DMG and the
feed with `SPARKLE_ED_PRIVATE_KEY`, and re-verifies both with CryptoKit against
the public key inside the mounted DMG before anything is published.

A development, PR or manual build is still inert: the keys only reach an artifact
through the `--updates` path, whose ad-hoc refusal is unchanged.

## Environment

Two execution contexts, named where it matters. The restricted sandbox (Command
Line Tools only, no `swift test`, no signing identities, no Xcode) ran the Python
tests, `sdlc-checks.sh` and `ci-basic-checks.sh`. Everything else ran
unrestricted on the maintainer's Mac (Xcode 27.1, macOS 27, arm64) with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

The owner's installed `Utter.app`, its keychain items, the signing identities and
the login keychain search list were not modified. The release-style build used
the throwaway self-signed identity from
[`evidence/rehearsal-keychain.sh`](evidence/rehearsal-keychain.sh), created and
deleted by this change's runs. `sign_update` read the real EdDSA private key from
the login keychain for the key-match and pipeline checks; the key was never
exported, printed or written to the repository.

## Key ceremony

The owner explicitly instructed the agent to generate the key pair and then
install the secret. Generation used Sparkle's tool and the login keychain.
This overrides the approved intent's owner-only ceremony for this task. The
private key never entered the transcript or repository:

1. `generate_keys -x <0600 temp file>` wrote the private key to a temporary file
   that was never read into the transcript, then
   `tr -d '\n' < file | gh secret set SPARKLE_ED_PRIVATE_KEY --env production`
   installed it and the file was deleted. `gh secret list --env production`
   confirms `SPARKLE_ED_PRIVATE_KEY` (2026-10-17).
2. `generate_keys -p` printed the public key, which is committed in
   `Resources/UpdateInfo.plist`: `XbBUmoegXl8DL7141ASPz4CHVrkAk6CyGiHkUfkLUww=`.
3. [`evidence/part-b-key-match.sh`](evidence/part-b-key-match.sh) proves the
   committed key is the keychain key: `sign_update` signed a fixture with the
   keychain private key and `verify-update-signature.swift` accepted it against
   the committed public key, while a wrong public key was rejected.

**Offline backup is the owner's to make.** The agent's export was deleted after
the secret was set, so the login keychain remains the only local copy. Recorded
as residual risk 1.

## Resume verification, 2026-10-19

The current run uses Xcode 27.1 explicitly through `DEVELOPER_DIR`. The remote
`main` is still `077f6d8`; the production environment lists
`SPARKLE_ED_PRIVATE_KEY`, last updated 2026-10-17. No production key was exported
or used during this run. Results are in
[`evidence/part-b-resume-checks.json`](evidence/part-b-resume-checks.json).

Resolved findings from the independent review:

- Both release-workflow verifier calls omitted `--require-updater`, causing
  armed builds to fail as inert. Both now name the committed update template.
  The literal-step fixture fails four cases on the old workflow and passes on
  the correction. See
  [`evidence/part-b-workflow-before-fix.txt`](evidence/part-b-workflow-before-fix.txt).
- Release notes now declare `sparkle:format="plain-text"`. The golden test
  failed before this correction and now checks both format and decoded text.
- The complete pinned Sparkle `LICENSE`, including its external notices, now
  ships inside the framework before signing. The artifact verifier rejects a
  missing notice, covered by a fixture test.
- Rotation docs account for signed-feed rejection and Sparkle's default
  20-day recovery delay. READMEs distinguish feed validation from archive
  validation and disclose IP address, User-Agent, and CDN redirects.

Fresh checks passed: `sdlc-checks.sh`; `ci-basic-checks.sh` with 67 Python tests;
`swift test --skip-update --disable-automatic-resolution -j 4`, with 1193 XCTest
tests, 18 skips, zero failures, plus one Swift Testing test; a release-style
armed app and DMG build with a throwaway self-signed identity; mounted-DMG
verification with `--require-updater` and plist extraction; and the literal
metadata-step dry run with a throwaway EdDSA key. `Package.resolved` retained
SHA-256 `a4443ef840b345d8873b9c0f0a37d8c7dfc6ed6c6045e25f76965cb6d3e484e9`.
The build and native tests did not use the owner's Developer ID identity.

The independent verifier reran the generator, lock, signature, workflow, and
artifact fixtures, and tested publication failures without remote writes. Its
archive checksum check passed; a fresh GitHub asset-digest comparison was
blocked by an unauthenticated HTTP 403 rate limit. See
[`evidence/part-b-independent-review.md`](evidence/part-b-independent-review.md).

The owner approved temporary keychains and isolated GUI rehearsal in chat.
`scripts/rehearse-updates.py` prepared signed versions 0.0.55, 0.0.56, and 0.0.57
with a distinct bundle identifier, private home and model caches, and loopback
feed. The packaged 0.0.56 process launched and automatically fetched the signed
same-version feed. The captured request has no query or body and includes
`Accept-Language` and `User-Agent: Utter Rehearsal/0.0.56 Sparkle/2.10.0`. See
[`evidence/part-b-rehearsal-request.json`](evidence/part-b-rehearsal-request.json).
This proves launch and a real feed request, not an installation or UI result.

GUI interaction is blocked by the locked macOS session, confirmed by
`CGSSessionScreenIsLocked=true`. CUA returned `cgWindowNotFound` for the
rehearsal app and System Settings, and timed out on another window lookup.
The owner was asked to unlock the desktop. No install button or permission
prompt has been clicked. S1-S13 and visual acceptance remain pending.
The rehearsal app and server were stopped before handoff. Both temporary
keychains and generated private fixture seeds were deleted. The user keychain
search list still contains only the login keychain. Signed fixture apps and
feeds remain under `.build/auto-update-resume-20261019/gui` for resumption.

`ANTI_SLOP.md` was reread completely before handoff. This correction adds no
custom interface, font, layout, or motion. Release-note text format is checked,
and localization parity passes. Real control behavior, contrast, alignment,
clipping, keyboard operation, both languages, and light/dark/narrow-window QA
remain unverified while locked. No visual acceptance is claimed.

### Settings command correction and deferred GUI run

The desktop was briefly unlocked. The rehearsal onboarding completed without
granting permissions or downloading models. `Cmd+,` opened an empty window,
because the app menu invoked the empty SwiftUI Settings scene. The command now
routes through `NativeDesktopHost.openSettings()`, with its original target and
action restored when the host closes.

`DesktopSettingsCommandTests` reproduced the bug before the fix and passed after
it. The full rerun passed 1194 XCTest tests, with 18 skips and zero failures,
plus one Swift Testing test. Basic CI and a release-style armed app and mounted
DMG verification passed. `Package.resolved` retained its recorded hash. An
independent source review found no concrete ownership or lifecycle issue.
Actual keyboard dispatch after launch and reactivation remains unverified.
See [`evidence/part-b-settings-resume.json`](evidence/part-b-settings-resume.json)
for log paths, hashes, and cleanup results.

The fixture helper now initializes only the distinct rehearsal defaults domain
through `defaults import`, because CFPreferences uses the user's daemon despite
the private home override. New signed fixtures are preserved under
`.build/auto-update-resume-20261019/gui-settings`, using loopback port 18740.

The Mac locked again before the corrected window could be inspected. CUA
returned `cgWindowNotFound`, and `CGSSessionScreenIsLocked=true` was confirmed.
The owner then asked to defer the GUI run. The rehearsal app, both loopback
servers, and the wake assertion were stopped. The temporary signing keychain,
fixture private seeds, and rehearsal defaults domain were deleted. Signed apps,
feeds, and logs remain available. The code corrections remain uncommitted.

To resume after the owner unlocks the desktop, first confirm the installed
production app is stopped. Import the preserved preferences file from
`gui-settings/home/Library/Preferences/com.opentype.voiceinput.rehearsal.20261019.plist`
into the rehearsal domain, then serve the existing fixtures with
`python3 scripts/rehearse-updates.py serve --work .build/auto-update-resume-20261019/gui-settings --port 18740`.
Open the installed rehearsal app through CUA, complete onboarding without new
permissions, and inspect the real Settings window before S1-S13. Existing
signed fixtures require no new keychain or private seed. Check certificate
validity before reusing them after a long delay.

At that handoff, no visual acceptance or successful installation was claimed.
The following run supersedes those deferred results.

### GUI resume, 2026-10-20 to 2026-10-21

The owner unlocked the desktop and asked the agent to operate the rehearsal
directly. The actual Settings menu and `Cmd+,` now open the owned settings
window, including after app restart. The rehearsal found two more interface
defects: automatic tab styling hid navigation in toolbar overflow, and changing
English to Chinese left native tab titles as ellipses. Native grouped tabs make
all eight sections visible. Replacing the hosting view on a language change
clears the tab-size cache while retaining the window, settings and selection.
The update privacy footnote now uses secondary foreground for readability.

The latest candidate passed `ci-basic-checks.sh`, all 1194 XCTest tests across
15 bundles with 18 skips and zero failures, and one Swift Testing test. Its
armed release-style app and mounted DMG passed verification with the temporary
self-signed identity. `Package.resolved` retained the hash above. The settings
command regression test covers command routing and restoration. It does not
cover the native language-change layout cache.

The native English dark Settings window showed eight complete tabs, and About
opened with one click. On the latest candidate, switching English to Chinese
without closing the window kept all eight Chinese labels visible. General and
About were inspected. The Chinese privacy sentence was fully visible; English
wrapped into two complete lines. These are visual observations, not a measured
contrast ratio. `Ctrl+Tab` did not switch tabs, so complete keyboard traversal
is not accepted. The fixed 760 by 680 content size is the supported width;
there is no narrower resizable Settings window in this implementation.

Actual Sparkle rehearsal results:

- S1 and S7: same and older feeds report up to date, with no downgrade offer.
- S2 and S14: a signed 0.0.56 to 0.0.57 update downloaded only after Install
  Update, reached Install and Relaunch, replaced the isolated bundle, and
  launched a new process. About showed 0.0.57 and deep strict signature
  verification passed. This run preceded the final navigation/cache correction;
  a complete update on the latest UI candidate remains pending.
- S3, partial: Chinese language and automatic checks survived the update.
  Permissions stayed ungranted and launch at login stayed off. Granted TCC
  persistence and enabled login registration are unverified.
- S4 to S6: a tampered DMG, a bad archive EdDSA signature, and an unsigned feed
  were rejected. The original 0.0.56 executable hash remained unchanged.
- S8: a separately signed fixture with a remote HTTP feed omitted the entire
  Updates section and manual-check button. Configuration tests reject this URL.
  No remote packet capture was made.
- S9: the off preference survived restart. With only the rehearsal's last-check
  timestamp removed to make the check due, off produced zero requests over
  434.3 seconds. Enabling produced one feed GET, a version-available status,
  and no automatic archive download or alert.
- S11: after Install and Relaunch committed and the host exited, the exact
  isolated Autoupdate process was killed. The resulting 0.0.56 bundle passed
  deep strict signature verification and displayed a native window. This tests
  one observed interruption point, not every instruction during replacement.
- S12: no App Management prompt appeared for the writable rehearsal path.
  The protected-path permission flow remains unverified.
- S13: a 0.0.55 client first saw 0.0.57. After withdrawing that feed item and
  serving the signed 0.0.56 feed, checking offered 0.0.56. The installed client
  stayed at 0.0.55. This proves feed withdrawal for older clients.

Two independent source reviews found no actionable command, restoration,
observer-lifetime or locale-refresh defect. The reviewers did not reproduce
the GUI or run the native build/tests. The detailed results, log hashes and
review task identifiers are in
[`evidence/part-b-gui-20261020.json`](evidence/part-b-gui-20261020.json).
Screenshots and accessibility trees are in this thread's native CUA transcript;
no standalone screenshot files were saved.

The Mac locked again before the prepared Aqua-only clone could be inspected.
CUA returned `cgWindowNotFound`; `CGSSessionScreenIsLocked=true` was confirmed.
The light/dark and language matrix, Sparkle's Chinese alerts, full keyboard
traversal and real busy-recording restart hold remain pending. The point-by-point
applicability audit is in
[`evidence/part-b-ui-audit.md`](evidence/part-b-ui-audit.md). No complete visual
acceptance is claimed.

Before handoff, the isolated app, all three loopback servers and the bounded
wake assertion were stopped. The temporary signing keychain and both new
fixtures' private seeds were deleted. The rehearsal defaults were cleared;
exporting the domain returned an empty dictionary. The user keychain search
list still contains only the login keychain. Production identity and installed
app data were not used by this resumed run.

The latest signed samples remain in
`.build/auto-update-resume-20261020/gui-final`. Its `resume-preferences.plist`
holds the separate rehearsal preferences captured before cleanup. On an
unlocked desktop, confirm production Utter is stopped, import that snapshot
into `com.opentype.voiceinput.rehearsal.20261019`, and serve that root on port
18742. The normal clone is under `installed/Utter Rehearsal.app`; the prepared
Aqua-only clone is under `light/Utter Rehearsal.app`. The active feed is the
signed same-version 0.0.56 item. Existing samples require no private key or
keychain, but their temporary certificate validity must be checked before
reuse after a delay.

### Final localized candidate, 2026-10-21

The desktop became available again and native QA resumed. Chinese to English
switching passed without reopening the settings window. About, all eight tab
labels, and the privacy sentence were inspected in both languages and both
appearances. Aqua-only signed clones provided light appearance without changing
the owner's system theme. The changed surfaces had no observed text clipping.
The English privacy sentence wraps into two complete lines. This is a visual
legibility check, not a numerical contrast measurement.

One further packaging defect was reproduced: the main app reported
`Bundle.localizations == []`, and Foundation selected `en` for a Chinese
preference. Sparkle remained English even with rehearsal-only
`AppleLanguages = [zh-Hans]`. The main Info.plist now declares the manually
handled `en` and `zh-Hans` languages with `CFBundleLocalizations`, as specified
by [Apple's key reference](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundlelocalizations).
The rebuilt real bundle reports both languages and selects `zh-Hans` for that
preference. Sparkle's native update offer, download/install action, and
install/relaunch confirmation then displayed Chinese. The update-offer window
was inspected in all four language/appearance combinations.

Sparkle uses the process's native language selection. This correction does not
make it follow a live change to Utter's separate `uiLanguage` preference.
The language matrix used the separate rehearsal domain's native language
preference and restarted between native-language configurations.

The final metadata candidate passed basic CI, an armed release-style build and
mounted-DMG verification. Swift sources and the 1194-test suite are unchanged
from the passing locale-refresh run. A further actual 0.0.56 to 0.0.57 update
completed through the Chinese UI, relaunched in dark appearance, and showed
0.0.57 in About. Deep strict signature verification passed. This supersedes
the earlier pending latest-candidate installation and Chinese-alert gaps.

A third independent source review found no actionable issue and confirmed the
metadata-only plist change. It inspected pinned Sparkle Chinese translations,
validated the plist, parsed Python, and checked the diff. It did not reproduce
the parent's GUI results or perform builds, tests or key operations.

The four combinations cover Settings/About and the update offer, not every
pre-existing settings section or every Sparkle failure dialog. The same-version
alert had valid accessibility text but a blank CUA image during the Aqua run;
visual acceptance of that particular alert is not claimed. Keyboard focus and
complete tab traversal also remain unverified.

The native microphone request was triggered, without granting access, before
the real recording-busy test. The tool refused access to
`com.apple.UserNotificationCenter` with "for safety reasons". The owner was
asked to confirm rehearsal microphone, accessibility and local Apple Speech
permissions. The owner explicitly declined and requested keeping those tests
pending. No system Allow control was clicked by the agent and no recording
started. At exit, About showed microphone granted. The exact rehearsal bundle's
Microphone status was reset with `tccutil`, and a fresh native About inspection
showed Grant again. Accessibility, Speech and Screen controls also showed Grant.
S3 granted TCC/login, S10 and protected-path S12 remain pending.

The rehearsal app, remaining loopback servers and wake assertion are stopped.
All temporary signing keychains and fixture private seeds are deleted. Rehearsal
defaults are cleared after saving a separate resume snapshot. The latest signed
fixtures are under `.build/auto-update-resume-20261021/gui-localized`, port 18743.
Its `installed` clone is 0.0.56; `light` was updated to the normal dark 0.0.57
bundle; `light-baseline` retains the Aqua-only 0.0.56 clone. The active feed is
the signed newer 0.0.57 item. The user keychain search list still contains only
the login keychain. No production update or PR B was created.

## Earlier evidence, 2026-10-17

| Check | Result | Evidence |
|---|---|---|
| `bash scripts/sdlc-checks.sh` | Pass | all bundles, including this one |
| `bash scripts/ci-basic-checks.sh` | Pass (exit 0) | script tests 52 → 66 (+9 appcast generator, +5 update lock), new `test_verify_update_signature.sh`, update-template lint, module boundaries, localization parity, workflow contract |
| `swift test` | Pass (exit 0) | 1193 tests across 15 bundles, 0 failures, the same 18 skips as the Part A baseline |
| Release-style armed build (`build-app.sh --updates --sign="Utter Rehearsal Signing"`, throwaway identity) | Pass | internal `verify-release-artifact.sh --require-updater --update-info Resources/UpdateInfo.plist` passed; DMG built and mounted-verified; [`evidence/part-b-pipeline.sh`](evidence/part-b-pipeline.sh) |
| App carries exactly the committed keys | Pass | nine `SU*` keys; `check-update-plist.py --app … --update-info` clean; an inert verifier run on the same app fails with "must carry no update keys" |
| Appcast generated from the verified DMG | Pass | enclosure `https://github.com/IchenDEV/utter/releases/download/v0.0.56/Utter-0.0.56.dmg`; the plist dumped out of the mounted DMG is byte-equal to the built app's plist |
| DMG and feed signatures | Pass | `sign_update` with the keychain key; both accepted by `verify-update-signature.swift` against the committed public key |
| Pinned tools archive | Pass | [`evidence/part-b-tools-lock.sh`](evidence/part-b-tools-lock.sh): the committed SHA-256 equals the download and the GitHub asset digest (`c2bf58aa…da0c`); the tarball's `sign_update` is byte-identical to the SwiftPM artifact's |
| Workflow step contract | Pass | `test_release_workflow_contract.sh`: step order, `SPARKLE_ED_PRIVATE_KEY` in the credentials check, `--updates` in the build, `--dump-app-plist` in the verify step, the key only through stdin, no `set -x`, no `--update-info` in any workflow, the appcast uploaded and compared |
| Workflow steps dry run with a throwaway key | Pass | [`evidence/part-b-sign-metadata-dryrun.sh`](evidence/part-b-sign-metadata-dryrun.sh) runs the extracted `Sign update metadata` step against fixture inputs and rejects a missing secret, a wrong key, a tampered DMG and an unsigned feed |
| Refusals | Pass | [`evidence/part-b-negative-args.log`](evidence/part-b-negative-args.log): `--require-updater` without `--update-info`, `--dump-app-plist` without `--dmg`, `--updates --sign=-`, `--update-info` without `--updates`, a missing plist, and a tag/version mismatch all exit 1 |

New tests: `scripts/tests/test_generate_appcast.py` (9),
`scripts/tests/test_update_lock.py` (5),
`scripts/tests/test_verify_update_signature.sh` (19 assertions, throwaway key
generated per run), and the workflow-contract additions.

### Nested signing and packaging

Unchanged from Part A and re-checked here on the armed build: the framework is
present with `XPCServices` removed, `Autoupdate` is arm64-only, hardened runtime,
signed by the app's certificate and carries no entitlements, and the CLI helper
does not link Sparkle.

## Acceptance criteria (Part B share)

| Criterion | Status |
|---|---|
| Newer feed version reported with version; same or older is up to date | Real Sparkle S1, S2 and S7 passed. |
| Menu and About manual check, four states, `en` and `zh-Hans`, real-window evidence | Settings command and About checks passed. Settings/About and update offers inspected in English/Chinese and light/dark. Native Chinese alert/install text passed after metadata correction. Keyboard traversal and the Aqua same-version alert's blank capture remain gaps. |
| Background checks on by default, persisted, off means no request, consent before install | Default/configuration tests pass. S9 passed with a controlled due timestamp: zero requests for 434.3 seconds while off; one feed request when enabled. No automatic archive download. S2 required both install actions. |
| Negative cases leave the install untouched | S4 to S8 passed within the boundaries above. The original executable survived archive/feed rejection. Remote HTTP UI was disabled. No mismatched-code-signing-identity GUI case or packet trace was run. |
| New version shown after relaunch; permissions persist | S2 and S3 preferences passed, including a complete update on the final metadata candidate. Granted TCC, enabled login persistence and first production update remain pending. |
| No relaunch during recording, processing, output commit or model work | Busy-gate and controller tests pass. Real active-recording S10 remains pending. |
| Network request matches the docs | Actual loopback feed and consented archive requests observed. No body or query on the feed request. Production GitHub/CDN redirects remain unverified. |
| Release workflow fail-closed metadata | Done: secret required before any build, tools digest verified before execution, the key only on stdin, both signatures independently verified against the shipped public key, appcast uploaded to the draft and compared after download. |
| Rollback written | Runbooks present. S13 feed withdrawal passed for an older installed client; this does not downgrade newer installed clients. |
| Independent verifier | Risk-critical local checks and two further source reviews complete. GUI evidence remains parent-observed, with production gaps listed below. |

## Rehearsal (S1 to S14)

S1, S2, S4 to S9, S13 and S14 have native-app evidence. S11 passed at one bounded
interruption point. S3 is partial, S10 is pending, and S12 showed no prompt on
the writable fixture path. Visual acceptance remains partial. The procedure is
in the approved plan. These gaps remain before verification approval and PR B.

## Spec and plan discrepancies to confirm

1. **Release-notes generation.** Plan B1 lists "plain-text notes from `git log`
   over the tag range" as a generator test case. The generator takes a
   plain-text notes file; the workflow produces it with
   `git log --no-merges --pretty=format:'- %s' <previous-tag>..<tag>`. The tests
   cover the plain-text embedding and XML escaping, not the `git log`
   invocation itself. No behavior change; the plan wording is one step off.
2. **`--require-updater` still requires `--update-info`.** The workflow passes the
   committed path explicitly even though `build-app.sh --updates` now defaults to
   it. That keeps the verifier's contract explicit and lets it compare the app
   against a named file. Plan B3's "`--updates` then defaults to this file"
   applies to the build, not the verifier.

## Residual risk and gaps

1. **No offline backup of the EdDSA private key.** The login keychain is the only
   local copy; the GitHub environment secret is the only remote one. Rotation is
   documented but only rehearsable through a Developer ID release. Owner action.
2. **Developer ID signing and notarization of the armed artifact are still
   unproven until CI.** Every local build used a throwaway self-signed identity;
   the ARM64/notarization branches of the verifier are covered by fixtures and by
   the Part A release run. The first armed release must pass signing,
   notarization, stapling and Gatekeeper.
3. **Rehearsal coverage remains incomplete.** Download, installation and relaunch
   passed on the isolated identity. Granted TCC, enabled login, a real busy
   restart, protected-path App Management, complete keyboard/focus operation
   and the Aqua same-version alert's visual acceptance remain pending. The first
   production
   Developer ID update is a separate gate.
4. **The first updater release must be installed manually once**, as both READMEs
   now say.
5. **Signed-feed key recovery is delayed.** The single-key pipeline has no
   immediate in-app key-rotation bridge. Manual installation is the immediate
   fallback, documented in `github-controls.md`.

## Decision

Implementation corrections, tests, signed local packaging, independent source
reviews and the completed GUI scenarios are recorded. The owner explicitly
deferred permission-related tests, then instructed `pr & merge & release` after
the verification handoff. This records authorization to deliver Part B with the
listed gaps; it does not mark those tests as passed.

The approved two-stage plan still requires the dormant Part A release before
merging and releasing Part B. At delivery preflight, main was `077f6d8` and the
last published release was v0.0.55. Its waiting nightly release and duplicate
queued runs were cancelled before approval because the original dormant
candidate still omitted the Sparkle license notices. The reviewed license and
Settings corrections are being delivered first as a dormant follow-up PR,
without UpdateInfo.plist or release-workflow changes. Part B can be committed,
opened and checked in parallel. Each actual production run retains its own
human approval and artifact verification gate.
The fresh 2026-10-21 pre-PR rerun passed all 1194 XCTest cases with the same
18 skips, plus one Swift Testing test, basic CI and SDLC checks. Delivery
authority, log hashes and deferred tests are recorded in
[`evidence/part-b-delivery-20261021.json`](evidence/part-b-delivery-20261021.json).
