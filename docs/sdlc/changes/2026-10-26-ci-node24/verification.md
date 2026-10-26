# Verification: Upgrade the GitHub Actions runtime to Node 24

**Status:** approved
**Approved-by:** User, explicit approval in this conversation: 批准
**Approved-date:** 2026-10-26
**Upstream:** [plan.md](plan.md)

## Candidate and environment

- Date: 2026-10-26.
- Branch: `t3/upgrade-node`.
- Base commit: `03e3288cb0518d80d51e23cbc538492b2a177ce6`.
- Workflow changes: twelve action references across six files, as approved in
  [spec.md](spec.md). No other workflow content changed.
- Local validation uses `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`,
  Xcode 27.1, build 27A9275, and Apple Swift 6.4. The system's default developer
  directory remains Command Line Tools.

## Local evidence

| Check | Result |
|---|---|
| Selected action metadata and nested Pages dependency | Rechecked; JavaScript actions declare Node 24 |
| Exact workflow diff comparison with the base commit | Passed; only twelve approved reference replacements |
| `actionlint -no-color -shellcheck=` on all six workflows | Passed, exit 0 |
| `bash scripts/sdlc-checks.sh` | Passed, exit 0 |
| `bash scripts/ci-basic-checks.sh` | Passed, exit 0, including release workflow contract checks |
| `swift test --jobs 4` | Passed, exit 0; 1,241 XCTest cases, 23 skipped, 0 failures; one Swift Testing test passed |
| `git diff --check` | Passed, exit 0 |

The diff comparison reconstructed each workflow from its base contents with the
five approved replacements, then required the complete resulting file to match.
It found twelve replacements across all six workflows. This checks change scope,
not action execution.

The Pages upload action still pins
`actions/upload-artifact@bbbca2ddaa5d8feaa63e36b76fdaad77386f024f`. That exact
commit declares Node 24. Metadata checks do not execute GitHub Actions.

The XCTest total sums the fifteen top-level `All tests` summaries. Nested
selected-test child runs are excluded from that sum. All fifteen primary test
bundles passed. The separate Swift Testing run passed one test.

The Swift test log includes compiler warnings and macOS `contactsd` connection
errors. These did not cause test failures. This run does not establish runtime
privacy isolation, Pages delivery, or release behavior.

Local logs:

- SDLC: `/private/tmp/utter-ci-node24-sdlc-implementation.log`.
- Repository checks: `/private/tmp/utter-ci-node24-basic-checks.log`.
- Swift tests: `/private/tmp/utter-ci-node24-swift-test.log`.

Log SHA-256 values:

- Repository checks: `224ca4e18beb54a944a4bd6170ee5fac06e7c58c4027e606a7a22ce57b4cd51b`.
- Swift tests: `07955df914e19ba7100f9595f04047ead57fabbaecd228c39a46bf65c53c3f2c`.

## Remote evidence and remaining work

At verification approval, the change is uncommitted and unpushed. Fresh PR CI,
the actual GitHub runner version, Pages deployment, manual artifact delivery, and
release workflows have not been exercised for this change.

The user approved local verification on 2026-10-26. Delivery proceeds under the
earlier push instruction. Record the pushed commit, remote SHA, and fresh CI state
in the PR and this thread after delivery.
