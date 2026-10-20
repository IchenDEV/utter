# Independent review, 2026-10-19

Reviewer: fresh-context read-only agent `independent_update_review`.
Scope: `077f6d8..e7ba800` plus the current correction diff. No approval supplied.
The reviewer changed no repository files, accessed no keychain, launched no
apps, and ran no SwiftPM build or package commands.

The review found the omitted updater-verification arguments, plain-text notes
format, signed-feed rotation delay, README disclosure and verification-order
errors, and missing packaged license. Those corrections were inspected with
no remaining actionable finding in the release implementation.

Checks rerun independently:

| Command | Result |
|---|---|
| `python3 -m unittest scripts.tests.test_generate_appcast scripts.tests.test_update_lock` | 14 passed |
| `bash scripts/tests/test_verify_update_signature.sh` | Passed |
| `bash evidence/part-b-sign-metadata-dryrun.sh` | Real sign_update; valid and four rejection cases passed |
| `bash scripts/tests/test_release_workflow_contract.sh` | Both signing modes passed |
| `python3 -m unittest discover -s scripts/tests -p test_release_artifact.py` | 13 passed, including missing-license refusal |
| `bash -n scripts/embed-sparkle.sh scripts/verify-sparkle.sh scripts/tests/test_release_workflow_contract.sh` | Passed |
| `git diff --check` | Passed |
| `bash evidence/part-b-tools-lock.sh` | Downloaded archive checksum passed; GitHub digest API returned HTTP 403 rate limit |

`evidence/` above means this change bundle's evidence directory.
The metadata dry run was repeated after the plain-text fix.

A temporary fixture extracted the literal `Publish GitHub Release` run block.
A `gh` stub recorded operations and copied fixture assets for the real download
comparison commands. No remote writes occurred.

| Input | Exit | Last operation |
|---|---:|---|
| Valid assets | 0 | edit release public |
| Existing release | 1 | view |
| Upload failure | 1 | upload |
| Corrupted downloaded feed | 1 | download |
| Corrupted downloaded DMG | 1 | download |

Only the valid case reached publication. This does not prove a GitHub rollback.

Isolation recommendations were applied to rehearsal fixtures: private
`HF_HOME` and `HF_HUB_CACHE`, developer XPC disabled, and no text-output test
without a dedicated scratch target. GUI, exact-head CI, verification approval,
merge authorization, protected production approval, and real Developer ID
upgrade evidence remain separate gates.

The same verifier subsequently inspected `scripts/rehearse-updates.py` and
the keychain-path correction. All prepared app plists use the rehearsal bundle
identifier, loopback feed, and private home/cache paths. Work is mode 0700 and
key files exclude group and other access. Keys are outside the served tree,
which contains no symlinks. Signing names the supplied keychain and identity,
and fixture seeds reach `sign_update` on stdin. No concrete isolation finding
remained. The exact-process guard runs only at preparation time, so owner app
shutdown must still be confirmed immediately before launch.
