# Utter SDLC operating model

Utter uses a risk-scaled, artifact-driven development loop. The artifacts keep
product intent, implementation context, and verification evidence attached to
the change instead of leaving them in a chat or issue timeline.

```text
request / bug / incident
        -> intent
        -> design (medium and high risk)
        -> plan
        -> implementation + tests
        -> verification
        -> pull request + human gate
        -> verified signed release (notarized for Developer ID)
        -> observation / incident
        -> new intent
```

## Change lanes

| Lane | Typical scope | Required repository artifacts | Human gate |
|---|---|---|---|
| Trivial | Prose-only docs, comments, typo-only copy | PR description | PR review when repository rules require it |
| Low | Isolated implementation or test change with no privacy, security, data, release, or UI-behavior impact | `intent.md`, `plan.md`, `verification.md` | PR approval |
| Medium | User-visible behavior, UI, model/runtime behavior, dependencies, automation | Low-risk artifacts plus `spec.md` | Intent/design review and PR approval |
| High | Permissions, privacy, security boundary, signing, release, destructive migration, public API compatibility | Full bundle, independent verification, explicit rollback | Intent/design approval, independent verifier, protected production approval |

When uncertain, choose the higher lane. A large diff is not automatically high
risk, and a one-line permission or release change can be high risk.

## Change bundle

Non-trivial work lives at `docs/sdlc/changes/<yyyy-mm-dd-slug>/`:

```text
state.json       Machine-readable identity, risk, status, governed paths, and artifact paths
intent.md        Problem, outcome, scope, constraints, and acceptance criteria
spec.md          Design and failure analysis; required for medium/high risk
plan.md          Executable work items and verification plan
verification.md  Commands, results, visual/runtime evidence, and residual risk
```

Copy starting points from `docs/sdlc/templates/`. Status transitions are:
`intent -> designed -> planned -> implementing -> verified -> released -> closed`.
Only change the status when the corresponding artifact exists and its evidence
is current. An agent may record evidence, but may not represent its own output as
human approval.

`python3 scripts/sdlc.py validate --worktree` validates local work. Pull-request
CI compares the branch to its base and requires a changed verified bundle when
governed paths change. Trivial documentation-only changes stay on the fast path.

The validator also enforces a minimum risk for deterministic control surfaces:
entitlements, workflows, signing/build/release verification, the SDLC validator,
and its CI guard are high risk; dependencies, agent context, issue/review policy,
and other automation are at least medium risk.

## Definition of ready

Implementation can start when:

- the problem and desired outcome are observable;
- affected users/systems, scope, constraints, and open questions are recorded;
- acceptance criteria are testable;
- medium/high-risk design choices and rollback are reviewed;
- the plan names both automated and manual verification.

## Definition of done

A change is ready for PR approval when:

- each acceptance criterion has evidence in `verification.md`;
- `bash scripts/ci-basic-checks.sh` and `swift test` pass;
- a release-style app build passes for packaging, dependency, or runtime changes;
- user-visible macOS UI changes have real-window light/dark and relevant narrow-
  width evidence, not only unit or component tests;
- privacy, permission, external-service, and failure paths were exercised or are
  explicitly listed as residual risk;
- reviewer findings are resolved and rollback remains possible.

## Deterministic controls

Repository instructions and this document are guidance. Enforcement lives in:

- `scripts/sdlc.py`: artifact schema and governed-change check;
- `scripts/ci-basic-checks.sh`: linked resources, localization, identifiers, and
  repository invariants;
- `.github/workflows/pr.yml`: artifact validation, unit tests, and release-style
  app build, summarized by the stable `SDLC Gate` job;
- `.github/workflows/release.yml`: main-ancestry, tests, explicit signing-mode
  detection, artifact verification, checksum, and Developer ID notarization.

Local success is evidence for a commit, not proof that a GitHub check, Apple
notarization, or clean-machine path passed. A verified self-signed release is
still not Apple-trusted or notarized and must say so in its release notes.

## Human control points

Humans own outcome, risk acceptance, and production authorization. Agents may
draft artifacts, implement, test, review, and diagnose, but must stop for:

- unresolved product intent or a material scope choice;
- a security/privacy tradeoff not already approved;
- credentials or a protected production action;
- acceptance of known residual risk.

The repository-side controls need matching GitHub settings. See
[`github-controls.md`](github-controls.md); those settings must be verified in
GitHub and are not made effective by committing YAML alone.

Use [`review-policy.md`](review-policy.md) for the independent verification pass
and [`release-runbook.md`](release-runbook.md) for signed releases.

## Feedback and maintenance

Use the incident issue form or `templates/incident.md`. Detection should remain
deterministic wherever possible. An incident can trigger agent diagnosis, but
write actions stay limited to approved tools and paths.

Every production incident must produce at least one of:

- a regression test;
- a deterministic guardrail;
- an explicit eval case once a model-based eval runner exists;
- a documented reason the failure cannot be reproduced automatically.

The corrective work starts as a new intent and links back to the incident. Do
not close the incident until the new control has verification evidence.

## Research basis

See [`../research/ai-native-sdlc-utter-2026-08-25.md`](../research/ai-native-sdlc-utter-2026-08-25.md)
for the primary-source audit, verified Anthropic claims, Utter baseline, and the
boundary between source facts and project-specific decisions.
