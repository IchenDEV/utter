# Intent: Restore the release workflow input contract

**Status:** approved
**Approved-by:** chenli (explicit approval in this chat)
**Approved-date:** 2026-09-28
**Upstream:** https://github.com/IchenDEV/utter/actions/runs/36334044094/job/108662657898
**Risk:** high — release automation

## Problem

Nightly Release run 36334044094 on main commit
`e3314bd649c0358a37d47087a7687af64213c056` passed candidate tests but failed
at `Validate version and tag`. Its reusable workflow inputs were
`version=v0.0.47` and an empty `tag`; the contract requires numeric
`version=0.0.47` and `tag=v0.0.47`.

The nightly output adapter prefixes the numeric version and never emits a
tag. The manual tag workflow also passes `github.ref_name` as the numeric
version, leaving its resolved numeric output unused. The shared workflow
additionally checks the new nightly tag's ancestry before creating it.

These defects originate in the shared-pipeline integration introduced by
`efec93e`. Later fixes addressed worktree detection and caller permissions,
but did not test the values crossing the workflow boundary. Existing nightly
tests pass even though executing the actual output adapter reproduces the
failure. This is a bounded integration defect; it does not require replacing
the planner, signing pipeline, or application architecture.

## Outcome

Both release entry points supply the shared pipeline with a matching numeric
bundle version and stable release tag. Nightly validates the intended main
commit without requiring its new tag to exist before creation.

## Scope

The nightly and manual release entry points, shared pre-tag validation, and
executable workflow contract regression coverage. Keep one shared signing,
verification, and publishing implementation.

## Constraints

- Preserve production approval, main ancestry, checked-out commit validation,
  existing-tag refusal, signing, notarization, and immutable-asset controls.
- Do not weaken the stable SemVer validator to accept missing or malformed inputs.
- Regression fixtures must not push tags, access signing secrets, or publish releases.
- A production run remains separate from local and PR verification.
- Follow the repository's explicit per-stage approval requirements.

## Acceptance criteria

- A nightly candidate of `0.0.47` reaches the shared validator as
  `version=0.0.47` and `tag=v0.0.47`; the shared validator accepts the pair.
- The manual `v0.0.47` entry point supplies the same numeric/tag pair.
- A new nightly tag can pass commit validation before it exists; invalid
  ancestry, a moved main tip, and existing remote tags still fail closed.
- A no-change nightly skips release; invalid and mismatched versions fail.
- Executable regression checks exercise the workflow boundary and fail on
  the current broken wiring, rather than checking only for YAML substrings.
- Repository SDLC/basic checks, Swift tests, release-style build, and an
  independent review provide evidence before PR approval; the PR is conflict-free.

## Open questions

None. The user approved this intent on 2026-09-28.
