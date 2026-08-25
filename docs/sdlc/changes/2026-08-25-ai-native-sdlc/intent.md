# Intent: Adopt an artifact-driven, fail-closed SDLC

## Problem

Utter's implementation speed is not matched by durable intent, verification,
and release controls. Product context is spread across chats, issues, old specs,
and code. Pull-request CI builds the app but does not run the unit-test suite.
The tag workflow supports the configured `OpenType Signing` self-signed identity
but does not distinguish its trust level from Apple Developer ID, and it can
fall back to ad-hoc signing when certificate import fails. GitHub's `main`
ruleset is disabled, so review and successful checks are not enforced before
merge.

## Outcome

Every material change advances through a compact chain of human- and
machine-readable artifacts. Agents receive explicit intent and acceptance
criteria, CI supplies deterministic feedback, reviewers see current evidence,
and the release path fails closed unless the exact artifact uses the configured
identity, is verified, labeled with its signing mode, and approved. Developer ID
releases additionally require Apple notarization; the existing self-signed
release path remains operational without being represented as Apple-trusted.

## Scope

In scope: repository instructions, change/incident templates, artifact schema,
local validation, PR checks, release gates, and documentation of GitHub-side
controls. A low-friction path remains for prose-only changes.

Out of scope: enabling GitHub rulesets or environment approvals through the API,
provisioning Apple credentials, adding product telemetry, or claiming App Store
readiness. Those actions need administrator or credential-holder control.

## Constraints

- Preserve the Swift Package architecture and existing source behavior.
- Use only tools already present on GitHub macOS runners and developer Macs.
- Keep agents from self-approving product or production decisions.
- Treat local builds, GitHub checks, Developer ID distribution, notarization,
  and App Store submission as distinct evidence.
- Do not force full design paperwork onto prose-only changes.

## Acceptance criteria

- Governed diffs without a changed verified SDLC bundle fail validation.
- Medium/high-risk verified bundles require intent, spec, plan, and verification.
- PR CI runs the validator tests, repository checks, `swift test`, and an
  xcodebuild-backed app bundle build, with a stable aggregate gate.
- Release CI accepts only a SemVer tag whose commit is on `origin/main`, requires
  the configured signing identity, verification, and a SHA-256 checksum, and
  preserves the existing self-signed release path with an explicit warning.
- A detected Developer ID identity additionally requires notarization
  credentials, Apple acceptance, stapling, and Gatekeeper verification.
- Incident intake requires impact, detection, containment, follow-up intent, and
  a regression control.
- External GitHub controls and their current unverified state remain explicit.

## Open questions

The maintainer still needs to decide who can approve the `production`
environment, whether emergency bypass is allowed, and when to migrate the
public default from project self-signing to Developer ID. Model-based continuous
evals also need a future runner and a corpus of real accepted/failed tasks;
deterministic harness regression tests are the initial control.
