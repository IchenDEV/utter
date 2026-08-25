## Outcome

<!-- State the observable user/system outcome. Link the originating issue. -->

## SDLC bundle and risk

- Bundle: `docs/sdlc/changes/...`
- Risk: trivial / low / medium / high
- Human decisions still required:

## Verification

<!-- Link committed evidence. Do not claim checks that were not run. -->

- [ ] `python3 scripts/sdlc.py validate --worktree`
- [ ] `bash scripts/ci-basic-checks.sh`
- [ ] `swift test`
- [ ] Release-style app build when packaging/runtime is affected
- [ ] Real-window light/dark and narrow-width QA when macOS UI is affected
- [ ] Privacy, permission, external-service, and failure paths checked when affected

## Residual risk and rollback

<!-- Write None only when there is genuinely no known residual risk. -->

## Reviewer focus

<!-- Point reviewers to the highest-risk assumption, boundary, or behavior. -->
