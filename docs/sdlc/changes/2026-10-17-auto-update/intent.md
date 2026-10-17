# Intent: Add in-app auto-update support

**Status:** approved
**Approved-by:** User, explicit chat decision: 批准 (after choosing Sparkle 2, EdDSA key B, background check with ask-before-install, single nightly channel)
**Approved-date:** 2026-10-17
**Upstream:** [Release runbook](../../release-runbook.md)
**Risk:** High, release distribution, signing identity, new dependency/network path

## Problem

Utter is distributed only as a DMG attached to a GitHub Release. An installed
copy has no way to learn that a newer version exists and no way to install it.
The only version signal is the static `v<CFBundleShortVersionString>` text in
the About page. Users must visit GitHub, download the DMG, and replace the app
by hand.

The release cadence makes this costly. The nightly pipeline publishes a new
patch release whenever `main` moves (v0.0.48 on 2026-09-30 through v0.0.55 on
2026-10-16), and recent releases carry reliability fixes. Users who do not
notice a release keep running fixed bugs.

## Outcome

An installed Utter can discover a newer official release, show what changed,
and — with the user's consent — download, verify, install, and relaunch into it.
The user's existing macOS permissions (Accessibility, Microphone, Speech,
Screen Recording, Automation), settings, history, and downloaded models survive
the update. An update that cannot be proven authentic is never installed.

## Scope

In scope:

- A manual "Check for Updates…" action reachable from the menu bar and the
  Settings About page, with visible checking / up-to-date / available / error
  states.
- Background checking, on by default and controlled by a persisted setting.
  The app always asks before downloading and installing; it never installs
  silently. "Skip this version" and "Remind me later" are available.
- A single update channel: every published release, whether produced by the
  nightly pipeline or its manual-tag fallback, is offered to all installed
  copies. There is no stable/beta split.
- Authenticated update delivery from the existing signed, notarized GitHub
  release artifacts, including the release-pipeline steps that produce the
  update metadata from the already-verified DMG.
- Safe-moment installation: no install or relaunch while recording, processing a
  session, or committing text output into another app.
- English and Simplified Chinese user-facing strings, and documentation of what
  the update check sends over the network.

Non-goals:

- Updating downloaded models, dictionaries, or lexicons.
- Mac App Store distribution, sandboxing, or Intel support.
- Telemetry, analytics, crash reporting, or any unique-identifier collection.
- Downgrades, beta/nightly channel selection UI, or delta updates in the first
  version.
- Retrofitting already-shipped versions (v0.0.55 and earlier); they have no
  updater and must be updated manually once.
- Changing the bundle identifier, signing identity, or release trigger model.

## Constraints

- macOS 26+, Apple Silicon only, `LSUIElement` menu bar app, not sandboxed,
  hardened runtime. The app is assembled by hand in `scripts/build-app.sh`, so
  any embedded framework must be placed, signed, notarized, and verified there.
- Updates must keep the same signing identity and designated requirement so
  TCC permissions are not reset. The self-signed and Developer ID release modes
  must stay explicit; never fall back to ad-hoc signing.
- Authenticity must not depend on TLS or GitHub alone. Each update is bound to
  two independent proofs: the Apple Developer ID code signature matching the
  installed app, and an EdDSA signature verified against a public key embedded
  in the app. The EdDSA private key is a credential held only as a protected
  `production` secret. Only the owner may generate and install it; the agent
  will not generate, hold, print, or commit it.
- The release pipeline must stay fail-closed: no update metadata is published
  for an artifact that failed verification, none is published before its release
  is public, same-version assets are never replaced, and a missing or unusable
  EdDSA key stops the run instead of publishing unsigned metadata.
- Both release entry points (tag push and nightly) must use the same reusable
  workflow so they cannot drift.
- Privacy: the check sends no audio, text, history, dictionary, or persistent
  identifier. Turning background checks off must produce no automatic requests.
- Any third-party dependency must be version-pinned, license-reviewed, and fit
  the module boundary rules (`scripts/check-module-boundaries.py`) and the
  300-line file limit. Any new entitlement or permission must be called out
  explicitly in the spec.
- Follow intent, design, plan, verification, PR, and protected production gates.
  High risk additionally requires an independent verifier and explicit rollback.

## Acceptance criteria

- Given a controlled feed that advertises a newer version, the app reports an
  update with its version and release notes; for the same or an older version it
  reports up to date. Covered by automated tests that use a local feed, with no
  dependency on the real GitHub endpoint.
- The menu bar and About page each expose a working manual check with all four
  states, localized in `en` and `zh-Hans`, with real-window light/dark and
  narrow-width evidence.
- Background checking is on by default, the setting persists through
  `SettingsService`, and with it off an automated test proves no update request
  is made until the user checks manually. Finding an update never downloads or
  installs without the user's explicit consent, and "Skip this version" and
  "Remind me later" behave as labeled.
- A negative test exists and passes for each rejected case, leaving the running
  install untouched: tampered archive, invalid or missing signature, feed
  served over non-HTTPS, version downgrade, and a replacement signed by a
  different identity.
- Installing an update shows the new version after relaunch, and Accessibility,
  Microphone, Speech, and Screen Recording permissions remain granted. Evidence
  comes from a real Developer ID signed install updated to a newer signed build.
- No install or relaunch occurs during recording, session processing, or output
  commit; the update is deferred or the user is asked. An in-flight model
  download is not corrupted.
- The documented network request contents match what is actually sent, verified
  by a captured request in the evidence.
- The release workflow generates update metadata only from the verified,
  notarized DMG after its checksum passes, signs it with the EdDSA key, fails
  closed when any required signing input is missing, never exposes the private
  key in logs or artifacts, and publishes metadata only after the release is
  public.
- `build-app.sh` and `verify-release-artifact.sh` verify any embedded updater
  component's signature, identity, hardened runtime, and notarization.
- `bash scripts/sdlc-checks.sh`, `bash scripts/ci-basic-checks.sh`, `swift test`,
  and a release-style app build pass, with unavailable checks disclosed.
- A written rollback exists in the release runbook and is rehearsed: a bad
  release can be withdrawn from the update feed so it is no longer offered,
  without deleting evidence or replacing published assets.
- An independent verifier confirms the change, rollback, and real results.

## Evidence and rollback

Rollback is a revert PR for the app and workflow change plus withdrawing the
affected release from the update feed per the runbook. Versions installed before
this change are unaffected because they contain no updater. A version that
shipped with the updater and is later found bad is superseded by a newer
release; the feed is the control point for stopping its distribution.

## Open questions

None. The four product decisions below were made by the owner in chat.

## Decisions

All recorded 2026-10-17 from the owner's chat replies.

- **Mechanism:** use Sparkle 2, pinned to an exact version, rather than a
  bespoke downloader/installer. The design must still record how it fits the
  hand-assembled `.app`, the module boundaries, and the notarization pipeline.
- **Independent EdDSA key: yes.** Sparkle accepts an update when either a valid
  EdDSA signature or a valid matching Apple code signature is present, so the
  Developer ID alone would have sufficed. The owner chose to add the EdDSA key
  for continuity across a signing-identity change, independent key rotation,
  and signature checking before the archive is opened.
- **Default behavior:** automatic background check, always ask before
  installing, with skip and remind-later.
- **Channel:** one channel only. The owner said "only the nightly channel";
  this is recorded as every published release, since the nightly pipeline and
  its manual-tag fallback share one workflow and publish the same way. Correct
  this if a narrower meaning was intended.

## References

- [Release runbook](../../release-runbook.md)
- [GitHub controls](../../github-controls.md)
- [Release artifact workflow](../../../../.github/workflows/release-artifact.yml)
