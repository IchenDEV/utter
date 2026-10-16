# Verification: Configure Developer ID signing for CI

**Status:** approved
**Approved-by:** User, explicit chat request after verification handoff: 帮我发版
**Approved-date:** 2026-10-16
**Upstream:** [Plan](plan.md)

## Current state

Configuration completed on 2026-10-16. Intent, design, and plan have separate
human approvals. Apple credential validation and GitHub configuration passed.
After receiving this verification and its disclosed limitations, the user
requested a release on 2026-10-16. That request accepts this configuration
verification and authorizes preparation of the separate production release.
The original configuration operation did not dispatch a release.

## Remote result

- `notarytool store-credentials` validated the supplied credentials, and the
  read-only `notarytool history` request succeeded for team `G9L7H3T3D5`.
- The `production` environment contains all five approved `APPLE_*` secret
  names. Values were sent through standard input and cannot be read back.
- Production requires reviewer `IchenDEV`. The owner can review their own
  triggered runs. Administrator bypass is disabled.
- Custom deployment restrictions are active and contain exactly branch `main`
  and tags `v*`. Both release entry points retain their shared workflow.
- Both original repository secret metadata records are unchanged. Workflow
  source and `Package.resolved` remain unchanged.
- The temporary credential keychain and private directory were removed. The
  original user keychain search list matches byte for byte.
- The helper exited 0 with `configuration_success` and `success` true and no
  cleanup errors. No tag, publishing dispatch, or production approval was sent.
- Independent post-configuration verification passed. Fresh GitHub API reads
  match the approved settings and saved evidence. The verifier reconfirmed
  workflow hashes, test identity coverage, bundle hashes, and cleanup records.

Public readbacks and summaries are saved in [evidence](evidence/). They contain
secret names and public metadata, never secret values.

## Local evidence

| Check | Result |
|---|---|
| `bash scripts/sdlc-checks.sh` | Pass |
| `bash scripts/ci-basic-checks.sh` | Pass |
| `bash scripts/tests/test_release_workflow_contract.sh` | Pass |
| Native SwiftPM test build, four jobs | Pass, native SwiftPM sandbox retained |
| Protected `swift test --skip-build` | Setup failure before tests: nested `sandbox_apply` denied |
| All 14 native XCTest bundles | 1,143 cases complete, 1,126 passed, 17 conditional skips, zero failures |
| Swift Testing | One unique case passed |
| Test bundle integrity | All 300 recorded files unchanged after execution |
| Workflow and `Package.resolved` hashes | Unchanged |
| Developer ID export, isolated import, signing | Pass |
| Disposable executable signature, team, certificate, hardened runtime | Pass |
| Independent local verification | Pass, discovery identities match all completed cases |
| Configuration helper failure-path checks | Pass, rollback preserves unrelated secrets and cancellation ends its child |

The full native test run uses Xcode's `xctest` and `swiftpm-testing-helper`
against every complete bundle built from this checkout. The latter runs the
sole Swift Testing case again as a cross-check. Count that case once.
Thirteen bundles declare no Swift Testing cases; their helper invocations
report empty suites and exit 69. These are not extra passed test cases.

The original protected `swift test` command did not pass. Its wrapper failed
before test execution. The complete native run establishes the actual test
results without placing the build process inside the runtime policy.

The runtime policy blocks production preference, keychain, Contacts, and app
storage paths and the corresponding sensitive Mach services. It permits the
AppKit and UUID-named pasteboard services required by the tests. A fresh-domain
canary cannot persist real user preferences. Opening the real keychain file
returns `EPERM`. A separate nonexistent-keychain-item query returned item not
found and does not prove broker denial. Test processes receive a minimal
environment with no inherited API credentials.

The selected Developer ID certificate SHA-256 is
`1B499618154DEB0204896CDB199AA65D25EDA2188FEDBB0E29A73063728E4112`,
with team `G9L7H3T3D5`. The signed executable's embedded certificate matches.
Its verification enables hardened runtime; it is a local signing check, not a
release artifact or notarization result.

## Corrected setup failures

- Blanket denial of Mach services prevented named pasteboard tests and
  interrupted the recovery-composition test. The corrected policy preserves
  sensitive-service denial while allowing those required native services.
- Loader variables assigned before `sandbox-exec` were stripped. Assigning
  framework and library paths inside the guard loads the native test engines.
- The first configuration preflight used Homebrew OpenSSL 4, which rejects
  Apple's RC2-40-CBC PKCS#12 encoding. It attempted no secret writes and fully
  cleaned up. System LibreSSL decodes the export and verifies its fingerprint.
  The configuration helper now explicitly uses `/usr/bin/openssl`.

## Remaining verification

- The separately authorized release run for real CI signing, accepted
  notarization of software, stapling, Gatekeeper, mounted-DMG verification, and
  published-checksum evidence. Successful authentication alone proves none of
  those release results.

The user requested that run on 2026-10-16. Its state and evidence are tracked
in [release](release.md). GitHub's human production approval remains required.

## Rollback

Remove only the five `production` environment secrets listed in
`evidence/configuration-state.json`. This restores selection of the unchanged
repository-level certificate credentials. Preserve the production reviewer and
deployment restrictions. Restoring weaker protection requires separate human
authorization. No release artifact needs rollback because none was published.

## Security note

An unsuccessful XCTest help invocation unexpectedly printed its inherited
environment, including an existing API token, in tool output. The token was
not copied into repository files or evidence. The user was notified and
advised to rotate it. Subsequent test and credential operations use minimal
environments. Token rotation has not been performed by this task.

## Evidence location

Public task evidence is at
`TASK_TMP/utter-developer-id-ci-evidence-8lm_1sy5/`.
The complete passing run is `native-run-9d5cbdd1/`, with per-bundle discovery,
commands, completion records, and logs. No credential values belong in this
verification document.
