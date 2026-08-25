# Spec: Adopt an artifact-driven, fail-closed SDLC

## Context

The repository already has architecture guidance in `AGENTS.md`, historical
specs/plans, a lightweight linked-file check, a release-style app builder, and
unit tests. It lacks a single lifecycle contract tying those pieces together.
The current GitHub repository has an inactive `main` ruleset and no branch
protection. Only certificate secrets are configured; Apple notarization secrets
are absent.

## Design

Add a vendor-neutral lifecycle under `docs/sdlc/`. A change bundle contains a
small JSON state record plus Markdown intent, optional/required design, plan,
and verification artifacts. `scripts/sdlc.py` validates status values,
required headings, placeholder removal, path containment, and whether governed
diffs are covered by a changed verified bundle.

Risk controls the artifact weight. Prose-only work uses the PR fast path. Low
risk skips a design artifact. Medium/high risk requires it. Verified work must
have current evidence; release and closure remain later states.

GitHub issue forms capture raw intent and incidents. The PR template links the
bundle and exposes risk, tests, visual/runtime evidence, and residual risk. PR CI
uses a stable aggregate job so a future ruleset needs only one required check.

Release CI reruns repository checks and tests, verifies the tag and main
ancestry, imports the configured signing identity, builds the DMG, and proves
the app authority matches that identity. It then classifies the actual app
signature. Developer ID proceeds through Apple notarization, stapling, and
Gatekeeper assessment. The existing project self-signed identity skips Apple-
only checks but retains mounted-DMG, signature, binary-equality, checksum, draft
round-trip, and immutable publication checks, with an explicit release warning.

## Safety and failure modes

- Markdown cannot prove human approval. Approval is enforced by an active
  GitHub ruleset and protected environment, both documented as external gates.
- An agent could write weak evidence. Required CI and independent high-risk
  review reduce but do not eliminate this risk.
- Missing or unusable signing credentials block every release instead of
  falling back to an ad-hoc artifact. Apple credentials are required only when
  the built app is signed with Developer ID.
- A self-signed artifact is not Apple-trusted; the workflow and release notes
  preserve that distinction even though the existing distribution path remains
  supported.
- Existing docs and research do not retroactively require bundles; governed
  implementation, test, automation, and product-site paths do.
- The release verifier proves bundle/signature/notarization invariants, not
  clean-machine behavior or App Store acceptance.

## Test strategy

- Unit-test bundle validation, missing artifacts, fast-path detection, and the
  governed-path gate with Python's standard library.
- Run the validator against the actual worktree.
- Run existing linked checks and the complete Swift test suite.
- Parse workflow YAML and inspect the final diff.
- Build and verify an ad-hoc app locally as packaging evidence.
- Verify the current GitHub self-signed release artifact against the strict
  non-notarized branch and statically exercise both workflow branches.
- Developer ID and notarization checks require the protected GitHub environment.

## Rollout and rollback

Merge repository controls first, then enable the `main` ruleset and configure
the `production` environment. Existing repository-level self-signing secrets
remain compatible; add the three Apple notarization secrets when migrating to
Developer ID. Roll back by reverting the workflow/control commit; do not weaken
a failing release job inline or publish its unverified DMG manually. If the
artifact gate proves too heavy, narrow governed paths through a reviewed low-
risk change instead of bypassing validation.
