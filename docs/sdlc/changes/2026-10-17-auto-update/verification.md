# Verification: Add in-app auto-update support (Part B, enable updates)

**Status:** pending approval
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan](plan.md)
**Risk:** High, release distribution, signing secret, new network path

`verification.md` is approved once per PR (plan, "One bundle, two
verifications"). It holds **Part B, enable updates**. Part A (PR #127, dormant
integration) is merged as `077f6d8`; its approved record is in git history and in
PR #127. Part B starts at `d994b9b` on `t3/enable-auto-update`, with the
2026-10-19 corrections recorded below. Verification approval is still pending.

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
| Newer feed version reported with version; same or older is up to date | Unit-level from Part A. **Real feed through Sparkle: rehearsal S1, S2, S7 — not run.** |
| Menu and About manual check, four states, `en` and `zh-Hans`, real-window evidence | Projection and presentation tests; localization parity passes. **Real-window evidence: blocked by lockscreen.** |
| Background checks on by default, persisted, off means no request, consent before install | Default and persistence tests from Part A; `SUEnableAutomaticChecks=true`, `SUAllowsAutomaticUpdates=false`, `SUAutomaticallyUpdate=false` in the committed template and enforced by the lint. **Zero requests when off: rehearsal S9 — not run.** |
| Negative cases leave the install untouched | Generator, verifier and workflow-level refusals above. **Tampered archive, bad EdDSA, unsigned feed, downgrade and different identity on a running app: rehearsal S4–S8 — not run.** |
| New version shown after relaunch; permissions persist | **Rehearsal S2, S3 and the first real update — not run.** |
| No relaunch during recording, processing, output commit or model work | Busy-gate and controller tests from Part A. **Real app: rehearsal S10 — not run.** |
| Network request matches the docs | **Rehearsal — not run.** |
| Release workflow fail-closed metadata | Done: secret required before any build, tools digest verified before execution, the key only on stdin, both signatures independently verified against the shipped public key, appcast uploaded to the draft and compared after download. |
| Rollback written | `github-controls.md` (withdraw, rotate, quarterly audit) and `release-runbook.md` (update metadata, stop conditions). **Rehearsed rollback (S13): not run.** |
| Independent verifier | Source and risk-critical local checks complete on 2026-10-19; GUI and production gaps remain. |

## Rehearsal (S1 to S14)

**Partially started on 2026-10-19.** Owner consent and app shutdown are complete,
and the isolated packaged app launches and fetches the local signed feed.
S14 launch is observed at process/network level. S1-S13, visible settings,
Sparkle alerts, App Management, and light/dark/narrow screenshots in `en` and
`zh-Hans` require an unlocked desktop. The procedure is in the plan. This remains
a gate before verification approval and opening PR B.

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
3. **The real update path has never run against a feed.** The rehearsal is the
   first end-to-end proof; the release after the first updater release is the
   first production proof.
4. **The first updater release must be installed manually once**, as both READMEs
   now say.
5. **Signed-feed key recovery is delayed.** The single-key pipeline has no
   immediate in-app key-rotation bridge. Manual installation is the immediate
   fallback, documented in `github-controls.md`.

## Decision

Implementation corrections, fresh tests, signed local packaging, and independent
technical review are recorded. GUI rehearsal is blocked by the locked desktop.
This file remains pending approval and is not yet ready for approval. No PR B,
merge, tag, or release has been created by this resumed run.
