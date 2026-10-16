# Spec: Sign the Developer ID distribution DMG

**Status:** approved
**Approved-by:** User, explicit chat decision: 批准修复设计
**Approved-date:** 2026-10-16
**Upstream:** [Intent](intent.md)

## Context

Both tag and nightly releases use `.github/workflows/release-artifact.yml`.
It imports one selected identity, records its SHA-256 fingerprint, builds the
App and DMG, classifies the app signature, and verifies the artifacts before
notarization. The v0.0.53 run proved that app signing and Apple credentials
work, but its outer DMG had no signature. Gatekeeper rejected that container
after Apple accepted the submission and the ticket was stapled.

The shared workflow already owns distribution signing policy and has the
exact identity and fingerprint. Put the correction there, alongside its
Developer ID classification. This is smaller than adding identity discovery
to the generic packaging script or maintaining two release entry-point fixes.

## Sign before the first Developer ID verification

In the shared `Classify and verify signed artifact` run block, once the app is
classified as Developer ID, sign `dist/Utter-$RELEASE_VERSION.dmg` with:

- The existing exact `SIGN_IDENTITY` selected from the imported CI identity.
- A secure timestamp, requested explicitly with `--timestamp`.
- A stable container identifier, `com.opentype.voiceinput.dmg`, distinct from
  the app's unchanged bundle identifier.

Use native `codesign` directly in the existing run block. A disk image does
not receive the app's entitlements, runtime options, or recursive signing.
Let a nonzero signing command stop that step under the workflow's existing
`bash -e` behavior. Verify the signed image before uploading it to Apple.

The resulting order is build -> classify app -> sign Developer ID DMG ->
verify app and DMG -> notarize DMG -> staple -> verify distribution -> checksum
and download verification -> publish. The existing public release gates remain
in that order. The self-signed branch does not enter the Developer ID DMG step.

## Verify the container at the existing boundary

Extend `scripts/verify-release-artifact.sh` only when a DMG is supplied with
`--require-developer-id`. Before mounting the image or submitting it for
notarization, require:

1. `codesign --verify --strict` succeeds for the DMG itself.
2. Its primary authority is Developer ID Application and it has a secure
   timestamp.
3. The DMG certificate fingerprint matches the app certificate. When
   `--expected-cert-sha256` is supplied, both must also match that imported
   certificate fingerprint.

Reuse the existing `certificate_sha256` extraction helper for both signed
paths. Keep signature parsing and validation in the verifier rather than
duplicating them in workflow YAML. The CLI arguments stay unchanged.

The first shared workflow verification catches a missing, ad-hoc, mismatched,
or untimestamped DMG signature before Apple submission. The same verification
also runs after stapling. The existing ticket validation, DMG open assessment,
app execute assessment, mounted-app equality, and checksum gates still apply.

## Safety and failure modes

| Failure | Required result |
|---|---|
| App authority differs from imported identity | Existing classification stops |
| DMG signing or timestamp service fails | Stop before notarization |
| DMG has no usable signature | Reject before notarization |
| DMG uses another certificate or lacks secure timestamp | Reject before notarization |
| Image or app changes after signing | Signature or mounted equality check rejects |
| Apple rejects submission, staple fails, or Gatekeeper rejects | Existing workflow stops before publication |

No new credentials, dependencies, signing exports, or GitHub permissions are
needed. Diagnostic output contains public signing metadata, never private
keys or passwords. Preserve the current configured-identity failure behavior.

## Test strategy

- Extend `scripts/tests/test_release_workflow_contract.sh` to execute the
  shared workflow's actual classification/signing shell block in its existing
  disposable, credential-free fixture. Assert signing occurs with the chosen
  identity, explicit timestamp, and container identifier before verification.
- Prove the regression check fails against the old unsigned-DMG run block.
  Exercise signing failure and the self-signed branch; signing failure must
  prevent progression, and self-signed behavior must stay explicit.
- Invoke the actual `verify-release-artifact.sh` with a real packaged app and
  task-owned Developer ID DMG fixtures. Prove a valid image passes and the
  unsigned, mismatched, and missing-secure-timestamp cases reach and fail the
  intended container guard. Native signing/extraction alone is insufficient.
  Identify fixture-based certificate cases separately from native results.
- Run required SDLC/basic checks, complete Swift tests, and release-style
  packaging. Separate native runtime evidence from any wrapper setup failure.
- Obtain independent verification of the diff and results. The approved new
  production run must still prove Apple acceptance, stapling, both Gatekeeper
  checks, mounted equality, and the published asset checksum/download equality.

Fixtures do not claim Apple acceptance or public release success. Only the
actual authorized production run can provide that evidence.

## Rollout and rollback

Implementation begins only after design and plan approval. Deliver the scoped
fix through a PR and protected main. Verify `SDLC Gate` on the exact merged
candidate. Recheck remote tags and use the next unused stable version, expected
to be v0.0.54. Retain the failed v0.0.53 tag and its first-failure evidence.

Current GitHub readback lists only `IchenDEV` as a collaborator and sensitive
path code owner. Main requires a separate approving review, code-owner review,
and last-push approval, with no bypass actors. Before merge, the concrete PR
must have an eligible human approval path. This is a rollout prerequisite;
changing collaborators, code owners, or protection rules is outside this fix.
Do not represent an agent review as satisfying that human gate.

The new run requires its own human production decision. Preserve v0.0.52 and
its assets until the new release is verified. Revert the scoped fix through a
PR if it regresses packaging; keep protections and failure evidence. If a
published release is defective, restore the previous latest recommendation
without replacing same-version assets, and state its older signing status.

## Review state

The user approved intent, design, [implementation plan](plan.md), and
[local verification](verification.md) on 2026-10-16. Independent design and
implementation reviews found no blocker. Their reports record technical
verification; human approvals are recorded in the artifact headers. The PR
approval and new run-specific production decision remain separate gates.

## References

- [First-run independent diagnosis](../2026-10-15-developer-id-ci/evidence/release-final-independent-verification.json)
- [Apple packaging and container signing](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
