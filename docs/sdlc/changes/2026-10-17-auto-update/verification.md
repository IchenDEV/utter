# Verification: Add in-app auto-update support

**Status:** approved
**Approved-by:** User, explicit chat instruction `pr & merge & release` after the verification handoff; dormant delivery corrections only
**Approved-date:** 2026-10-21
**Upstream:** [plan](plan.md)

This file is approved once per PR (plan, "One bundle, two verifications"). It
currently holds **Part A, PR A (dormant integration)**. Part B returns it to
`pending approval` before PR B.

## Dormant delivery corrections, 2026-10-21

The original Part A release has not been published. Delivery preflight found
the known missing Sparkle license notices still present on main. The obsolete
waiting release runs were cancelled before approval. This follow-up carries
the already reviewed license and native Settings corrections before the dormant
release, preserving the approved order before Part B enables update feeds.

The complete pinned Sparkle LICENSE is copied before signing, and the release
verifier rejects a missing notice before mounting. The regression fixture is
included. Settings menu/Cmd+, routing and command restoration, native grouped
navigation, language-change rehosting, semantic privacy text, and the manually
handled bundle languages are copied byte-for-byte from the validated Part B
candidate. No UpdateInfo.plist or release-workflow change is included. The
build remains inert and the release verifier still rejects feed keys.

The matching Swift sources passed 1194 XCTest tests with 18 skips and zero
failures plus one Swift Testing test. The Part B candidate also passed a signed
release-style build and actual update installation/relaunch. Those are results
on the full candidate, not a new signed build of this isolated subset. Native
CI must test and build this exact dormant head before merge. The language and
appearance evidence is in
[`evidence/part-b-gui-20261020.json`](evidence/part-b-gui-20261020.json) and
[`evidence/part-b-ui-audit.md`](evidence/part-b-ui-audit.md); update-feed scenarios
in those snapshots apply to Part B only.

The owner explicitly kept permission persistence and recording-busy restart
pending, then requested PR, merge and release. Those tests, protected-path App
Management, complete keyboard/focus checks and the Aqua same-version alert
capture remain unverified. Production signing/notarization and published
artifact verification remain separate gates. The later historical license
gap below is resolved by this follow-up; the remaining gaps are retained.
The exact source hashes, 13 passing artifact fixtures, inert-configuration
guards and delivery-review task are recorded in
[`evidence/dormant-delivery-20261021.json`](evidence/dormant-delivery-20261021.json).
The completed [independent review](evidence/dormant-independent-review-20261021.md)
found no actionable issue and independently passed all 13 artifact fixtures.
Its source hashes remain unchanged; exact-head CI and production proof are
still required.

## Scope of PR A

Sparkle 2.10.0 is linked, embedded, signed and verified in every build, and the
code that would drive it exists, but **no build carries a feed**: the `SU*` keys
live only in a plist passed to `build-app.sh --updates --update-info`, and no such
plist is committed. A dev, PR, manual or release-pipeline build is therefore
inert: the configuration gate resolves to `unavailable`, no driver is created,
nothing contacts a server, and the Updates UI is hidden. PR B adds the plist,
the pipeline steps and the rehearsal.

## Environment

Two execution contexts were used and are named where it matters. The restricted
sandbox (Command Line Tools only, no signing identities, no network) ran the
Python tests and `sdlc-checks.sh`. Everything else ran unrestricted on the
maintainer's Mac (Xcode 27.1, Swift 6.4, macOS 27, arm64). The owner's installed
`Utter.app`, login keychain, signing identities, trust settings and the keychain
search list were not touched. Release-style builds used a throwaway self-signed
identity in a temporary keychain created by
[`evidence/rehearsal-keychain.sh`](evidence/rehearsal-keychain.sh) (a `PATH`
shim adds `--keychain` to `codesign`; no trust settings, no search-list change;
deleted afterwards). Builds always passed `--sign` explicitly.

## Evidence

Baseline (unchanged branch at `8dc9547`) is in
[`evidence/baseline-checks.json`](evidence/baseline-checks.json); the v0.0.55
nested-signature baseline is in
[`evidence/baseline-v0.0.55.json`](evidence/baseline-v0.0.55.json).

| Check | Result | Evidence |
|---|---|---|
| `bash scripts/sdlc-checks.sh` | Pass | all bundles, including this one |
| `bash scripts/ci-basic-checks.sh` | Pass (exit 0) | script tests 31 → 52 (+13 plist gate, +8 release-artifact), module boundaries, localization key parity, workflow contract all pass |
| `swift test` | Pass (exit 0) | XCTest 1143 → 1193 across 15 bundles, 0 failures, same 18 skips as baseline |
| `swift build`, `xcodebuild` Release (arm64) | Pass | Sparkle linked; no new warnings from `UtterUpdates` |
| `build-app.sh --app-only`, inert, throwaway identity | Pass | internal `verify-release-artifact.sh` passed ("Update keys passed" = no `SU*` keys) |
| `build-app.sh --app-only --updates --update-info=<temp plist>` | Pass | internal verifier ran with `--require-updater`; template equals the merged keys |
| Armed vs inert build | Same nested-code facts; the only intended difference is the `SU*` keys in `Info.plist` | [`evidence/part-a-packaging.json`](evidence/part-a-packaging.json); two separate builds are not byte-identical (signatures, `Assets.car`), so this compares layout, signing identifiers, flags, entitlements, rpaths and Sparkle component facts, not bytes |
| PR-CI style build `build-app.sh --app-only --sign=-` | Pass | ad-hoc app and ad-hoc Sparkle components pass the verifier (`flags=0x10002(adhoc,runtime)`); `--updates` with `--sign=-` is refused |
| Dev path (`build-and-run.sh` logic, copy without `pkill`/`open`) | Pass | assembled, three-pass signed, `codesign --verify --deep --strict` ok, no `SU*` keys, arm64-only, no XPC |

New automated tests: `UtterUpdatesTests` 36 (configuration gate, status
reducer, busy gate, busy signals, controller with a fake driver),
`OpenTypeTests` +13 (plugin wiring with fake session and model catalog,
presentation, registration/recovery allowlist), `UtterDataTests` +1 (setting
default and persistence), scripts +19.

### Packaging checks on real builds

- Framework: `Contents/Frameworks/Sparkle.framework`, `XPCServices` removed,
  `Sparkle`, `Autoupdate` and `Updater` thinned to arm64-only, 2.2 MB.
- Signing: `Autoupdate`, `Updater.app` and the framework are signed inside-out by
  the app's identity with the hardened runtime and **no entitlements**; the app is
  then re-sealed. All pass `codesign --verify --strict`. The verifier checks
  this on **every** build, armed or not (hardened runtime, same signer as the app
  or ad-hoc together with an ad-hoc app, no entitlements, timestamp for Developer
  ID). Real-artifact proof: an otherwise correct inert app whose `Autoupdate` is
  re-signed with the app's entitlements, framework and app re-sealed (so
  `codesign --verify --deep --strict` passes) fails with "Sparkle component must
  carry no entitlements".
- Nested signatures against the v0.0.55 baseline
  (`record_signatures.py`): same entries, same signing identifiers, same flags
  (`0x10000(runtime)`) and **identical entitlements** for the app and the CLI
  helper. Two intended or incidental differences: the app gains the rpath
  `@executable_path/../Frameworks`; the local CLI helper has no `@loader_path`
  rpath (local Swift 6.4 toolchain; `otool -L` shows it links no `@rpath`
  library, and the verifier asserts it does not link Sparkle).
- Refusals, all exit 1 before any build starts: `--updates` with `--sign=-`,
  `--updates` without `--update-info`, `--update-info` without `--updates`,
  nonexistent plist, `--allow-loopback-feed` alone, and a plist with an http
  feed or missing keys (linted before the long build). Log:
  [`evidence/part-a-negative-args.log`](evidence/part-a-negative-args.log).
- Verifier cross-checks on real artifacts: the armed app fails without
  `--require-updater` ("must carry no update keys") and passes with it; the
  inert app fails `--require-updater` ("app is missing …").
- Load test without running Utter (the owner's Utter is running; see gaps): a
  probe app signed with the same identity, hardened runtime and entitlements as
  Utter embeds the real thinned framework and resolves it through
  `@executable_path/../Frameworks`. It loads `SPUUpdater` and
  `SPUStandardUserDriver` (exit 0); with the framework removed dyld fails with
  "Library not loaded" (negative control).
  Source: [`evidence/sparkle-load-probe.m`](evidence/sparkle-load-probe.m).

### Dependency record

Sparkle 2.10.0, revision `eef1a539a373c1f1a320624b1130fc5de7b2e100`, pinned
`exact` in `Package.swift` and in `Package.resolved`. `Package.resolved` differs
from the base only by the Sparkle pin and the new `originHash`; an earlier local
resolution had also bumped three transitive pins (swift-atomics, swift-huggingface,
swift-jinja). That was reverted and every number above was re-run on the minimal
file, which `swift test`, `xcodebuild` and `build-app.sh` leave unchanged.
License: MIT (Sparkle, Andy Matuschak and others) plus bundled third-party
notices in the artifact's `LICENSE` (bsdiff/bspatch and `SUSignatureVerifier.m`
BSD-style, sais-lite MIT, an ed25519 zlib-style license), SHA-256
`389a4e4e…127cfe`. No third-party notice file is shipped for any dependency in
this repository today; see residual risk 5.

## Acceptance criteria (PR A share)

PR A is dormant, so most behavior criteria are proven at unit level here and
end-to-end in PR B's rehearsal. Nothing is claimed as passing that was not run.

| Criterion | PR A status |
|---|---|
| Newer feed version reported with version; same or older is up to date | Unit-level: status reducer and controller map driver events (found, none, failed) and never regress. **Real feed through Sparkle: PR B (S1, S2, S7).** |
| Menu and About manual check, four states, `en` and `zh-Hans`, real-window evidence | Projection and presentation unit tests; localization key parity passes; both are hidden when inert. **Real-window evidence: PR B** (the UI is not reachable in any PR A build). |
| Background checks on by default, persisted, off means no request, consent before install, skip and remind later | Default `true` and persistence tested in `SettingsStoreTests` (an untouched install stores nothing); the controller applies the setting at start and on change; `automaticallyDownloadsUpdates=false` in the driver; `SUAllowsAutomaticUpdates` and `SUAutomaticallyUpdate` must be `false` in the plist lint and in the verifier. **"Zero requests when off": PR B (S9).** Skip handling is in the reducer (`skipped`). |
| Negative cases leave the install untouched | Unit-level: non-https and non-loopback http feed refused by the gate; the updater gate refuses an unsigned or ad-hoc app (ad-hoc inert apps, as PR CI builds them, remain allowed); bad key refused. Tampered archive, bad EdDSA, unsigned feed, downgrade and different identity: **PR B (S4 to S8)**. |
| New version shown after relaunch; permissions persist | **PR B and observation after the first updater release.** |
| No relaunch during recording, processing, output commit or model work | Gate unit tests (exactly once, replaced request, revoke drops it), controller and plugin tests with fake session and model catalog. Real app: **PR B (S10)**. |
| Network request matches the docs | **PR B.** |
| Release workflow fail-closed metadata | **PR B.** The release workflow is not modified in PR A. |
| `build-app.sh` and the verifier check embedded updater signature, identity, hardened runtime, notarization | Done and tested (fixtures and real builds above). Notarization covers the whole bundle and is asserted by the existing `--require-notarization` on the DMG; its first real run on the new nested code is the post-merge dormant release run (gap 2). |
| `sdlc-checks`, `ci-basic-checks`, `swift test`, release-style build | Pass, with gaps disclosed below. |
| Rollback written and rehearsed | PR A rollback is a revert PR; it is dormant, so no installed copy ever contacts a server and nothing needs withdrawing. The feed-withdrawal runbook and its rehearsal are **PR B**. |
| Independent verifier | PASS WITH FINDINGS on the first pass; the one high finding is fixed and the fix re-checked by the same verifier: resolved. See the section below. |

## Independent verification

A fresh-context, read-only verifier read the approved artifacts, the diff and this
file, then reran the checks (sdlc, `ci-basic-checks`, the relevant `swift test`
filters, the full `swift test`, real inert and armed builds with its own
throwaway identity, and negative mutations of the verifier). It confirmed
dormancy (no committed feed or key, workflows, `Info.plist`, entitlements and ATS
untouched, `Package.resolved` differs only by the Sparkle pin and `originHash`),
the plugin lifecycle, the recovery allowlist, localization parity, and the
numbers (1193 XCTest, 0 failures).

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | High | Nested Sparkle signing, entitlement and signer checks ran only with `--require-updater`, so an inert release could ship Sparkle's installer with the app's entitlements and still pass | Fixed. `verify_sparkle_signing` now runs for every build and handles ad-hoc apps (`signer_of`). New stub tests cover every case on an inert build, an ad-hoc app, an ad-hoc component under an identity-signed app, and the armed path. Reproduced and now caught on a real artifact (above). |
| 2 | Medium | "Identical except `Info.plist` keys" overstated; evidence implied the inert verifier checked Sparkle signing | Fixed in this file; the second half is now true because of fix 1. |
| 3 | Low | An injected `SUFeedURL` in a signed copy fails through `codesign --verify --deep` before the clearer "must carry no update keys" lint | Accepted. It still fails closed (exit 1); only the diagnostic is less specific. |

**Re-check of the fix** (same verifier, fresh reruns): `test_release_artifact`
12 tests OK; real inert build passes; `Autoupdate` re-signed with the app's
entitlements (framework and app re-sealed so `codesign --verify --deep --strict`
passes) fails with the no-entitlements message; `Autoupdate` ad-hoc, or signed by
a second throwaway identity, under an identity-signed app fails with "not signed
by the app certificate"; the PR-CI style `--sign=-` build passes and
`--updates --sign=-` is refused. Verdict: resolved, no new findings. One low
test-quality remark, accepted: the `app-adhoc` stub marks every path ad-hoc, so
the unit test does not model an identity-signed Sparkle under an ad-hoc app;
the real-artifact mutation above covers that. Not re-run by the verifier in this
pass (run by the author, see the table): the full `swift test`, `ci-basic-checks`
and the load probe.

Also noted by the verifier and accepted: the baseline JSON's "499 tests" was
the `OpenTypeTests` bundle line (now annotated with the 1143 total across 14
bundles); the verifier does not assert the embedded Sparkle version against the
pin, which SwiftPM's checksum-verified binary target already enforces; a
`swift test --filter UtterDataTests.SettingsStoreTests` without the method name
ran zero tests here, so the single-method form is used.

## Spec discrepancies and decisions to confirm

1. **Busy signal.** The spec cites `ModelCatalogSnapshot.isBusy`, which does not
   exist; the property is `CatalogModelStatus.isBusy` (`downloading`,
   `compiling`, `loading`). `UpdateBusySignals.isModelBusy` ORs it over the whisper,
   text and speech catalogs, so a relaunch is held during any model download,
   compile or load. No behavior beyond the spec's intent; the spec text was not
   edited.
2. **Different-identity negative test** keeps the reinterpretation approved in
   the spec ("different identity and no valid EdDSA signature"), to be exercised
   in PR B.

## Residual risk and gaps

1. **No GUI launch of the packaged Utter and no visual check (plan S14).** The
   owner's Utter (same hotkey, same keychain items, same defaults domain) is
   running, and the plan allows GUI runs only while it is quit. Mitigation: the
   load probe above and the verifier's rpath, framework and signature checks.
   The one launch-time behavior this PR changes for every build is dyld loading
   Sparkle. Needs the owner's consent to run, ideally before merge.
2. **Developer ID signing and notarization of the new nested code are
   unproven until CI.** Local builds used a self-signed identity. The
   timestamp and Developer ID branches of `verify-sparkle.sh` are covered by
   fixtures only. The post-merge dormant release run must pass signing,
   notarization, stapling and Gatekeeper, and the installed result must launch
   and dictate normally. Rollback if it does not: revert PR A.
3. **The real `SPUUpdater` path is compiled and driven by fakes, never run
   against a feed in PR A.** It cannot run in a shipped build until PR B. PR B's
   rehearsal is the first end-to-end proof.
4. **Script test runtime** for the unit-test group rose from about 10 s to about
   63 s, because every verifier case shells out to stubbed tools and the Sparkle
   checks multiply those calls. It runs in `ci-basic-checks.sh` and the PR
   workflow. Accepted; a lighter stub would be a separate change.
5. **Sparkle's license notice is not shipped inside the app.** MIT and the
   bundled licenses ask for notice retention in copies. This repository ships no
   notices for any dependency today, so PR A does not invent a mechanism.
   Owner decision: add a notices file to the app resources now or as a separate
   change.
6. **PR CI on the exact head** (including `SDLC Gate`) cannot exist before the PR
   does. It is recorded in the PR after opening, with the owner's merge
   authorization as the final gate.

## Decision

Evidence for PR A is recorded and independently verified. Ready for review. The
open items for the owner are the gaps above: the GUI launch smoke with Utter
quit, the Developer ID notarization proof after merge, the license notice
question, and PR CI after the PR opens. Human approval of this file is
recorded in the header for Part A (PR A) only; Part B returns this file to
`pending approval`. The owner's merge authorization for PR A is a separate gate
and has not been given.
