# Verification: Adopt an artifact-driven, fail-closed SDLC

## Evidence

Environment: baseline commit `c5ee6a6525aae820329e034e64cbe835f1232712`,
branch `codex/ai-native-sdlc`, macOS 27.0 build 26A5416b, Xcode 27.0 beta
build 27A5237l, Swift 6.4, arm64.

| Check | Result | Evidence |
|---|---|---|
| Primary-source research | Pass | Anthropic title/date/author, six stages, Artifact triggers, eval guidance, control bands, and human production boundary verified in `docs/research/ai-native-sdlc-utter-2026-08-25.md` |
| `python3 scripts/tests/test_sdlc.py` | Pass | 13 tests; includes missing/distinct/alias/symlink artifacts, delete/rename/divergent diffs, governed coverage, and minimum risks |
| Build/release version regressions | Pass | Tagless checkout falls back to `0.0.0`; stable tags resolve; leading-zero and prerelease/public build tags are rejected |
| Dual signing workflow regressions | Pass | Release workflow YAML and every `run` block parsed; tests require both self-signed verifier calls, final Developer ID notarization verification, certificate fingerprint binding, immutable assets, and no ad-hoc fallback |
| Current GitHub self-signed release | Pass | v0.0.43 DMG (`sha256:2737cd9bb55224d03130822ba316fd6ea12db3793bfbc766184aa12048de8e74`) passed strict signature, hardened runtime, certificate SHA-256, mounted-DMG, full bundle manifest/content/permission, and binary checks; `Authority=OpenType Signing`, `TeamIdentifier=not set`, certificate `8DEC72880E13997A022BB5C446E8B54378FE2D17A7211FDAB6C01BBA860C4B9D` |
| Self-signed negative control | Pass | The local ad-hoc app was rejected by `--require-self-signed` because it has no signing authority |
| `bash scripts/ci-basic-checks.sh` | Pass | SDLC tests, release workflow guards, plist/localization, identifiers, industry lexicon, resources, conflict, credential-file, and symlink checks passed |
| `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test` | Pass | 564 XCTest tests passed, 8 environment-gated tests skipped; 1 Swift Testing test also passed |
| `./scripts/build-app.sh --app-only --sign=- --version=0.0.43` | Pass as local evidence | Rebuilt with xcodebuild/Metal; arm64 app/helper, bundle resources, hardened-runtime ad-hoc signature, and artifact verification passed; not distribution evidence |
| Local DMG digest | Pass | `54f07dab0e28c0172ba19cc53403862ac013adb37a991de7b8dc30a99b130077`; local ad-hoc artifact only, not a release digest |
| Shell/YAML/diff validation | Pass | Changed shell scripts passed `bash -n`; workflows and issue forms parsed as YAML; `git diff --check` passed |
| Independent fresh-context verification | Pass | Dual-signing review found incomplete DMG comparison, missing certificate fingerprint binding, weak workflow assertions, stale evidence, and an unprotected-environment gap; all fixes were applied and final re-review reported no actionable findings |
| Live GitHub controls | Partial | Repository secrets contain the current P12 and password, so the self-signed path remains usable. `main` ruleset is disabled, branch is unprotected, `production` has no verified required reviewer, and Developer ID/notarization credentials are absent |

The first bare `swift test` attempt failed before compilation because the machine
selected Command Line Tools and could not find `metal`. Re-running with the full
Xcode beta developer directory succeeded. PR/release workflows explicitly
install the Metal toolchain before tests/builds.

## Acceptance criteria

- Non-trivial governed diffs require a changed verified bundle that covers every
  governed path and meets its deterministic minimum risk — pass.
- Medium/high-risk verified bundles require distinct, safe, non-symlink intent,
  spec, plan, and verification files — pass.
- PR CI defines artifact checks, Swift tests, an xcodebuild-backed app build, and
  one stable `SDLC Gate`; direct pushes compare against the previous SHA and fail
  closed when it is unavailable — pass by code/tests, pending first GitHub run.
- Release CI restricts stable numeric tags to commits on `main`, requires the
  configured certificate and exact app certificate fingerprint, verifies both
  the built and mounted apps plus the complete bundle, round-trips draft assets
  and checksum, then publishes immutably. The existing self-signed identity is
  explicitly labeled; Developer ID additionally requires notarization, stapling,
  and Gatekeeper assessment — pass by code and current self-signed artifact,
  pending a live run of the new workflow and a future Developer ID run.
- Incident intake requires impact, deterministic detection, containment,
  corrective intent, and a regression control — pass.
- GitHub-side human controls are documented without claiming they are active —
  pass; external setup remains open.

## Residual risk

- The repository cannot enforce review or block a direct/force push until an
  administrator activates the documented `main` ruleset.
- The repository's current P12/password are sufficient for the explicit self-
  signed path. Because `production` does not yet have a verified required
  reviewer, GitHub may create/use it without protected approval; this preserves
  the existing chain but remains an external governance gap.
- Developer ID and its notarization secrets are not configured. That optional
  branch will fail closed if a Developer ID certificate is used without them.
- The self-signed release is not Apple-trusted or notarized and may require
  manual macOS approval; the workflow must preserve the release warning.
- Developer ID, Apple notarization, Gatekeeper `spctl`, GitHub draft asset
  round-trip, and final publication require a live protected run.
- Eight environment-gated Swift integration tests were skipped; their existing
  opt-in requirements are unchanged by this SDLC-only change.
- Model-based Agent Evals need 20–50 accepted, sanitized real tasks and a stable
  runner; current CI covers deterministic harness regressions only.

## Decision

Ready for human review as a verified high-risk repository-control change. The
current self-signed artifact path is validated and final independent re-review
reported no actionable findings. Protected production approval, GitHub control
activation, Developer ID credentials, and a live run of the updated workflow
remain separate human/external gates.
