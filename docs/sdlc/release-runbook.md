# Signed release runbook

Release is a high-risk operation. The tag workflow accepts the configured
project self-signed identity and Apple Developer ID, but never falls back to
ad-hoc signing when certificate import or artifact verification fails.

## Prepare

1. Confirm the candidate commit is on protected `main` and its `SDLC Gate` is
   green.
2. Review the change bundle's acceptance evidence, skipped checks, residual risk,
   and rollback notes.
3. Confirm the `production` environment, required reviewer, tag restriction,
   signing certificate, and applicable secret names against
   `github-controls.md`.
4. Create a `vMAJOR.MINOR.PATCH` tag on the exact candidate commit.

## Authorize and verify

Every protected workflow run must:

- rerun repository checks and Swift tests;
- import the configured code-signing identity and prove the built app uses it;
- build the app and DMG with the tagged version;
- verify the app signature, architecture, identifiers, version, helper, mounted
  DMG contents, and binary equality;
- publish the DMG and its SHA-256 checksum only after artifact checks; require
  human environment approval once the external `production` protection is active.

For Developer ID, the run must additionally verify the Apple team identifier and
hardened runtime, receive an accepted notarization result, staple the ticket,
and pass Gatekeeper assessment. For the project self-signed identity, the
release notes must warn that the build is not Apple-notarized and may require
manual approval on macOS.

Keep the workflow URL, release URL, commit SHA, signing mode, checksum, and any
notarization result as release evidence.

## Stop conditions

Stop without publishing if the commit is not on `main`, a required check is not
green, the version's release already exists, the configured identity is missing
or does not match the app, Developer ID notarization fails, the mounted artifact
differs, or a reviewer does not accept residual risk. Diagnose through a normal
change bundle and PR; do not edit the tag, replace published same-version assets,
or silently fall back to ad-hoc signing.

If an upload or download verification fails, the workflow leaves a draft. Record
the failure and inspect its assets before deleting that draft and rerunning; a
published same-version release is never replaced.

## Rollback

1. Mark the affected release as non-latest or remove it from the public download
   path without deleting evidence.
2. Restore the previous known-good release as the recommended download.
3. Publish user guidance for settings, history, and model-cache compatibility.
4. Open an incident, link a corrective intent, and add a regression control.
5. Rehearse this path at least quarterly and after release-system changes.
