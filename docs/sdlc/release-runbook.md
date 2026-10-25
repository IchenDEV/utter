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
- build the app and DMG with the tagged version and `--updates`;
- verify the app signature, architecture, identifiers, version, helper, mounted
  DMG contents, and binary equality;
- sign the DMG and the generated `appcast.xml` with `SPARKLE_ED_PRIVATE_KEY`,
  then re-verify both with `scripts/verify-update-signature.swift` against the
  public key taken from the app inside the mounted DMG;
- publish the DMG, its SHA-256 checksum and the appcast only after artifact
  checks; require human environment approval once the external `production`
  protection is active.

For Developer ID, the run must additionally verify the Apple team identifier and
hardened runtime, receive an accepted notarization result, staple the ticket,
and pass Gatekeeper assessment. For the project self-signed identity, the
release notes must warn that the build is not Apple-notarized and may require
manual approval on macOS.

Keep the workflow URL, release URL, commit SHA, signing mode, checksum,
appcast URL, and any notarization result as release evidence.

## Update metadata

`scripts/generate-appcast.py` writes a one-item feed from the verified DMG: the
enclosure URL comes from the validated tag, the version comes from the app plist
inside the mounted DMG, and the release notes come from
`git log --no-merges --pretty=format:'- %s' <previous-tag>..<tag>` as plain text.
`bin/sign_update` from the pinned `Sparkle-2.10.0.tar.xz`
(`scripts/sparkle-tools.sha256`, cross-checked against the GitHub asset digest)
signs the DMG and then the feed. The secret reaches `sign_update` only through
the step environment and stdin: never argv, never `set -x`, never a file.

If the secret is missing or does not match `Resources/UpdateInfo.plist`, the
`Sign update metadata` step fails and the release stays a draft.

Withdrawing a bad release, rolling the code back and rotating the key are in
`github-controls.md`. Nothing is ever deleted; a published same-version release
is never replaced. Users install the first updater release manually once; the
release after it is the first real in-app update.

## Stop conditions

Stop without publishing if the commit is not on `main`, a required check is not
green, the version's release already exists, the configured identity is missing
or does not match the app, Developer ID notarization fails, the mounted artifact
differs, the update secret is missing or does not match the shipped public key,
or a reviewer does not accept residual risk. Diagnose through a normal change
bundle and PR; do not edit the tag, replace published same-version assets, or
silently fall back to ad-hoc signing.

If an upload or download verification fails, the workflow leaves a draft. Record
the failure and inspect its assets before deleting that draft and rerunning; a
published same-version release is never replaced.

## Remote voice-key remap

A release that carries `remoteKeyRemapEnabled` (change bundle `2026-10-24-swallow-remote-dictation-key`) writes a
device-level `UserKeyMapping` on the Xiaomi remote's HID service while Utter runs. Before releasing, confirm the
bundle's `verification.md` records the independent verifier's hardware run (A/B, lifecycle read-backs, other keys).

- **Release note line:** "Remote page: Utter now keeps the Xiaomi remote's voice key from opening macOS Dictation
  (new setting, on by default)."
- **Kill switch, no new build:** turn the setting off on the Remote page, or
  `defaults write com.opentype.voiceinput remoteKeyRemapEnabled -bool false` and relaunch. Both restore the mapping.
- **Manual clear:** `hidutil property --matching '{"VendorID":10007,"ProductID":12984}' --set '{"UserKeyMapping":[]}'`.
  A remote reconnect or reboot also clears a leftover mapping after a crash.
- **Stop and revert** on any report that another key or device stopped working, that a mapping stayed after quit,
  or that another tool conflicts with the mapping; give kill-switch guidance first.

## Remote button mapping

A release that carries `remoteButtonMappingEnabled` and `remoteButtonProfile` (change bundle
`2026-10-25-remote-button-mapping`, high risk) silences the Xiaomi RC003's mapped keys at the device level through the
same `UserKeyMapping` as the voice-key remap, and reads the remote's presses through a non-seizing `IOHIDManager`. It
adds one permission, **Input Monitoring**, requested only when the user turns the setting on. Before releasing, confirm:

- PR #130 (voice-key remap) is merged. This feature builds on it and is not released before it.
- The bundle's `verification.md` records the independent verifier's run on the release-style build, with the verifier's
  identity: each key and trigger once, native key never reaching the frontmost app, crash then relaunch, sleep and wake,
  permission denied then granted then revoked while running, volume-key silence, and the voice key with the feature on and
  off. Anything the user waived is recorded as a waiver.
- The licensing owner has decided that the clean-room disclosure in the intent is sufficient.

- **Release note line:** "Remote page: remap the Xiaomi remote's keys to shortcuts, media keys, Show Desktop, the app
  switcher or an app (new setting, off by default; asks for Input Monitoring when you turn it on)."
- **What the prompt looks like:** a system dialog from macOS asking to receive keystrokes from any application, once, after
  the user turns the setting on. Nothing is requested at launch or before. If the system has already denied it, the page
  shows "Needs permission" with a button that opens System Settings → Privacy & Security → Input Monitoring. If it still
  does not work after the user allows it, the page says to restart Utter (whether a restart is needed is measured by the
  verifier on the signed build).
- **Kill switch, no new build:** turn the setting off on the Remote page, or
  `defaults write com.opentype.voiceinput remoteButtonMappingEnabled -bool false` and relaunch. Turning off the voice-key remap
  also turns the button mapping off. Both restore the mapping.
- **Withdraw the permission:** System Settings → Privacy & Security → Input Monitoring, or
  `tccutil reset ListenEvent com.opentype.voiceinput`. With the permission gone no key is silenced.
- **What a crash looks like:** while Utter is not running, some of the remote's keys (up, down, left, right, OK, back, home,
  menu, TV, volume) do nothing, not only the voice key. The next launch with the voice-key remap on removes leftover
  button entries the current profile does not own and adopts the ones that match it (unit tested against a fake device).
  Without a relaunch, a remote reconnect or a restart is expected to clear them; that heal time is for the verifier to
  measure on hardware.
- **Manual clear:** `hidutil property --matching '{"VendorID":10007,"ProductID":12984}' --set '{"UserKeyMapping":[]}'`.
  It clears every entry on the remote, including the voice key's; relaunching Utter sets the voice key's entry again.
- **Stop and revert** on any report that another key or device stopped working, that keys stayed silenced after quit,
  that a mapped action fired twice or fired into a password field, or that another tool conflicts with the mapping; give
  kill-switch guidance first.

## Rollback

1. Mark the affected release as non-latest or remove it from the public download
   path without deleting evidence.
2. Restore the previous known-good release as the recommended download.
3. Publish user guidance for settings, history, and model-cache compatibility.
4. Open an incident, link a corrective intent, and add a regression control.
5. Rehearse this path at least quarterly and after release-system changes.
