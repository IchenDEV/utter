# Spec: Restore the release workflow input contract

**Status:** approved
**Approved-by:** chenli (explicit confirmation in this chat)
**Approved-date:** 2026-09-28
**Upstream:** docs/sdlc/changes/2026-09-28-release-input-contract/intent.md

## Context

The reusable release pipeline already defines the correct contract: a numeric
bundle version and a stable `vMAJOR.MINOR.PATCH` tag that normalize to the same
value through `scripts/release-version.sh`. Both callers violate that contract.
The shared pipeline also applies an existing-tag check to the new-tag path.

The planner and signing pipeline have distinct, usable boundaries. Recent
worktree and permission fixes did not address these boundary values. Repairing
the caller wiring and tag-path condition has the smallest implementation,
verification, and maintenance cost. Replacing the planner would not repair its
callers; rewriting release automation would add signing and migration risk
without improving this contract. No stored data or published asset migration
is required.

## Design

### Version and tag ownership

- Keep `release-version.sh` as the sole stable-tag normalization authority.
- In the nightly output adapter, preserve `version=0.0.47` and additionally
  emit `tag=v0.0.47` when the planner emits a nonempty version. Keep the
  existing job outputs and reusable-workflow inputs. A no-change plan emits
  neither candidate field and continues to skip validation and release.
- In the manual tag workflow, expose the existing `steps.version.outputs.value`
  as a `validate` job output. Pass that numeric output to `inputs.version`
  and continue to pass `github.ref_name` to `inputs.tag`.
- Keep shared validation strict: missing tags, malformed tags, and mismatched
  numeric versions fail before tag creation, signing, or publishing.
- Remove obsolete comments claiming a reusable workflow cannot create tags.
  Keep one shared implementation for signing, artifact checks, and publishing.

### Commit validation before tag creation

Apply the existing-tag ancestry step only when
`inputs.require_ancestor && !inputs.create_tag`. The manual path retains its
ancestry check and missing-tag failure. The nightly path continues through
the existing create-tag step, which independently fetches main, refuses an
existing remote tag, and requires `HEAD == origin/main` before tagging HEAD.
Do not turn off `require_ancestor` in the nightly caller or weaken validation
to accept arbitrary commits.

The checked-out run commit is the candidate; a moved main tip aborts. This
change introduces no additional checkout, branch selection, or public input.
The no-force tag push is the remote mutation boundary. If another actor
creates the same tag between the existence check and push, the push must fail.

## Safety and failure modes

- Production environment approval, least-privilege caller permissions,
  signing identity verification, notarization policy, and immutable assets
  retain their existing behavior.
- Tests use disposable local repositories and stub the remote push operation;
  they must never use production remotes or signing credentials.
- A failure after tag creation can leave a tag without a published release.
  This pre-existing behavior remains fail-closed; never automatically move or
  delete the tag, overwrite assets, or retry using weaker signing.
- A successful local test proves the contract and fixture behavior only.
  GitHub workflow evaluation, protected environment approval, and a signed
  release require separate evidence.

## Test strategy

Extend existing release regression coverage before changing workflow behavior.
Execute the actual named workflow shell blocks against fixture repositories
and temporary `GITHUB_OUTPUT` files; verify the step-to-job-to-caller output
references separately. Use existing shell tools for bounded block extraction,
failing if a required block is missing. Do not build a general Actions emulator
or introduce a YAML/runtime dependency for this repair.

Cover both input paths through the shared version validator, including the
reported `0.0.47` example, first release, no-change skip, missing tag,
malformed tag, and mismatched numeric version. Exercise a new-tag candidate,
an existing tag on main, an off-main tag, a moved main tip, and a conflicting
remote tag. Assert that rejected cases never reach the push stub. Verify the
new/existing-tag condition and retained production/signing controls.

Demonstrate that the new contract tests fail on the current wiring and pass
after repair. Run SDLC checks, basic repository checks, Swift tests, and the
release-style app build. An independent read-only verifier inspects the
accepted contract and final diff and reruns the risk-critical checks before
the human verification gate. CI and production evidence are recorded separately.

## Rollout and rollback

After design and plan approvals, implement and verify on a dedicated branch.
Submit a conflict-free PR with passing checks for human approval. Production
execution remains behind the existing environment approval; do not treat
this design approval as authority to publish a release.

Observe the next approved release for the correct numeric/tag inputs,
successful candidate validation, and the existing artifact verification and
publication checks. Stop on any contract or signing failure.

Rollback is a revert of this scoped workflow/test change. If a release is in
progress, stop further execution before reverting automation. Already pushed
tags and published artifacts remain immutable; no automatic cleanup or
replacement is part of rollback.
