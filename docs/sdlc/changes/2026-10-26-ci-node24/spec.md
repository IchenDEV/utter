# Design: Upgrade the GitHub Actions runtime to Node 24

**Status:** approved
**Approved-by:** User, explicit approval in this conversation: 批准
**Approved-date:** 2026-10-26
**Upstream:** [intent.md](intent.md)

## Context

The user approved [intent.md](intent.md) on 2026-10-26. The six workflows contain
eight Checkout references and four other action references. All jobs use
GitHub-hosted `macos-26` or `ubuntu-latest` runners.

The application builds with Swift. Its workflows have no Node application build
or `setup-node` step. This change updates the runtime declared by their actions.

## Design

Change these twelve `uses:` values and keep every existing action input and job
setting intact:

| Action | Current | Selected | Coverage |
|---|---|---|---|
| `actions/checkout` | `v4` | `v5` | Eight references across all six workflows |
| `actions/upload-artifact` | `v4` | `v6` | Manual app artifact workflow |
| `actions/configure-pages` | `v5` | `v6` | Pages workflow |
| `actions/upload-pages-artifact` | `v3` | `v5` | Pages workflow |
| `actions/deploy-pages` | `v4` | `v5` | Pages workflow |

Retain the repository's major-tag reference format. Checkout v5 provides Node 24
and the existing checkout interface. Upload Artifact v6 explicitly declares Node
24; v5 still declares Node 20. No runtime override or additional dependency is
required.

### Direct action compatibility

- Checkout v5 retains `fetch-depth`, `fetch-tags`, `ref`, and
  `persist-credentials`. Preserve the manual workflow's approved commit
  `7d3bbf3d45744c760714f955cf6c04a0f190904d` and
  `persist-credentials: false`. Other workflows retain their current credential
  defaults for authenticated fetch and tag operations.
- Upload Artifact v6 retains the manual workflow's `name`, `path`,
  `if-no-files-found`, `retention-days`, and `compression-level` inputs. It also
  retains `artifact-id`, `artifact-url`, and `artifact-digest`, which the delivery
  record consumes.
- Configure Pages v6 retains its default token and `enablement: false`. The
  workflow supplies no custom inputs and consumes none of its outputs.
- Deploy Pages v5 retains the default `github-pages` artifact name, `page_url`
  output, and existing Pages and OIDC permissions. Its polling now uses backoff
  and jitter; its default deployment timeout remains ten minutes.

Checkout v5 and Upload Artifact v6 require Actions Runner 2.327.1 or newer. The
configured runner labels use GitHub-hosted images, and GitHub now runs JavaScript
actions on Node 24. The actual runner version remains a remote-run check.

### Pages dependency and payload

Upload Pages Artifact v5 is a composite action. It calls
`actions/upload-artifact@bbbca2ddaa5d8feaa63e36b76fdaad77386f024f`, identified
upstream as v7.0.0. That exact commit declares `runs.using: node24`. Its archive
input defaults to `true`, so the existing `github-pages` artifact name and
archived `artifact.tar` delivery remain compatible.

The selected Pages upload action excludes hidden paths by default. The current
tracked file list and working-tree inventory under `docs/` contain no hidden
files or directories. This default therefore removes no current site files.
Keep `path: docs` and all existing inputs intact.

## Failure modes and containment

- An unsupported input, missing output, or incompatible runner can fail a job.
  Compare metadata before implementation and require fresh CI after push.
- Local tests cannot establish artifact-upload or Pages-deployment success.
  Record those workflows as untested until their normal authorized runs occur.
- Major tags can move upstream. Recheck the selected metadata and nested Pages
  dependency before implementation; pause if they no longer match this design.

Workflow triggers, credentials, permissions, protected environments, signing,
publishing commands, artifact names, and the `SDLC Gate` job remain intact.

## Test strategy

- Inspect the diff to confirm that workflow changes are limited to the twelve
  approved action references.
- Check every selected action's runtime metadata, including the pinned nested
  Pages dependency, and verify the consumed input and output names.
- Run `actionlint -no-color -shellcheck=` over the six workflows. ShellCheck is
  excluded from this syntax check; the repository's shell checks remain separate.
- Run `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, and
  `swift test` before push.
- After the authorized push, verify the remote commit and record the fresh PR
  workflow result. A passing PR does not establish release, manual artifact, or
  Pages deployment success.

The unmodified workflows passed the actionlint command during design review on
2026-10-26. No workflow changes or application tests have run for this change yet.

## Rollout and rollback

After design and plan approvals, implement the reference updates and complete
local validation. Review verification evidence at its approval gate before the
previously requested push. Preserve production and deployment authorization
boundaries.

If the updated actions fail, revert this change's action references. This restores
the prior action versions, but cannot restore Node 20 on GitHub's runners.

## Sources

- [Checkout v5 metadata](https://raw.githubusercontent.com/actions/checkout/v5/action.yml) and [runner requirement](https://github.com/actions/checkout/releases/tag/v5.0.0).
- [Upload Artifact v5 metadata](https://raw.githubusercontent.com/actions/upload-artifact/v5/action.yml), [v6 metadata](https://raw.githubusercontent.com/actions/upload-artifact/v6/action.yml), and [v6 runner requirement](https://raw.githubusercontent.com/actions/upload-artifact/v6/README.md).
- [Configure Pages v6 metadata](https://raw.githubusercontent.com/actions/configure-pages/v6/action.yml).
- [Deploy Pages v5 metadata](https://raw.githubusercontent.com/actions/deploy-pages/v5/action.yml).
- [Upload Pages Artifact v3 metadata](https://raw.githubusercontent.com/actions/upload-pages-artifact/v3/action.yml) and [v5 metadata](https://raw.githubusercontent.com/actions/upload-pages-artifact/v5/action.yml).
- [Pinned nested Upload Artifact metadata](https://raw.githubusercontent.com/actions/upload-artifact/bbbca2ddaa5d8feaa63e36b76fdaad77386f024f/action.yml).
- [GitHub's Node 20 removal notice](https://github.blog/changelog/2026-09-23-node-20-is-no-longer-available-in-github-actions/).
