# Intent: Upgrade the GitHub Actions runtime to Node 24

**Status:** approved
**Approved-by:** User, explicit approval in this conversation: 批准
**Approved-date:** 2026-10-26
**Upstream:** —
**Risk:** Medium, dependency and automation maintenance

## Problem

The requested Node upgrade concerns CI. Updating the local Node installation does
not change the JavaScript runtime used by GitHub Actions.

The six workflows under `.github/workflows/` reference `actions/checkout@v4`,
`actions/upload-artifact@v4`, `actions/configure-pages@v5`,
`actions/upload-pages-artifact@v3`, and `actions/deploy-pages@v4`. These references
include actions that declare Node 20 directly or through a composite action.
GitHub has removed Node 20 from its runners and recommends action releases that
support Node 24.

## Outcome

All JavaScript actions used by these workflows declare Node 24, including actions
called by the Pages upload action. CI continues to check, test, and build Utter.

## Scope

- Update action references in `pr.yml`, `pages.yml`, `manual-app-artifact.yml`,
  `nightly-release.yml`, `release.yml`, and `release-artifact.yml`.
- Review the selected actions' inputs, outputs, runner requirements, and nested
  action references before implementation.
- Record local validation and the remote CI result after the authorized push.

## Constraints

- Keep workflow triggers, permissions, protected environments, concurrency,
  signing, publishing commands, and artifact names intact.
- Use published official action releases that explicitly support Node 24.
- Do not add a `setup-node` step or a runtime override to change an action's
  declared runtime.
- Validate locally before push. This change does not authorize a production
  release or a manual deployment.
- Keep every stage pending until the user approves that stage.

## Acceptance criteria

- Every direct JavaScript action and nested Pages upload action declares
  `runs.using: node24` in the selected release's metadata.
- Review confirms that existing inputs and outputs remain compatible and the
  configured runners meet the selected actions' requirements.
- The workflow diff changes action references only.
- `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, and `swift test`
  pass before push.
- After push, the remote branch matches the local commit. Record the fresh PR
  workflow result separately from local checks and production workflow results.
- Rollback consists of reverting this change's action references.

## Evidence

- [GitHub's Node 20 removal notice](https://github.blog/changelog/2026-09-23-node-20-is-no-longer-available-in-github-actions/).
- [Checkout v5 metadata](https://raw.githubusercontent.com/actions/checkout/v5/action.yml) declares Node 24.
- [Upload Artifact v6 metadata](https://raw.githubusercontent.com/actions/upload-artifact/v6/action.yml) declares Node 24.
- [Configure Pages v6 metadata](https://raw.githubusercontent.com/actions/configure-pages/v6/action.yml) declares Node 24.
- [Deploy Pages v5 metadata](https://raw.githubusercontent.com/actions/deploy-pages/v5/action.yml) declares Node 24.
- [Upload Pages Artifact v5 metadata](https://raw.githubusercontent.com/actions/upload-pages-artifact/v5/action.yml) calls Upload Artifact v7. Its pinned dependency requires review during design.

## Open questions

None for intent approval. Exact action versions and compatibility belong to the
design stage.
