# Plan: Fix and deliver the preparation check

**Status:** approved
**Approved-by:** IchenDEV, explicit continuous scope authorization
**Approved-date:** 2026-10-16
**Upstream:** [spec](spec.md)

1. Preserve v0.0.54 first-failure and skipped-production evidence.
2. Add the internal callbacks and replace the timing probe with the shared gate.
3. Build fresh tests without dependency resolution or downloads. Retain native
   SwiftPM sandboxing, unchanged Package.resolved, and 10 GiB internal free disk.
4. Prove the focused test passes and detects a whole-worker MainActor mutation.
   Restore the exact intended source and rebuild before complete testing.
5. Freeze full bundles, resources, discovery identities, runtime policy, and
   hashes. Run both native engines under the existing privacy policy, then
   SDLC/basic checks and a release-style signed packaging build.
6. Obtain independent technical verification. Publish sanitized evidence only.
7. Commit, push, create a PR, and merge only after exact-head CI passes. Verify
   exact main CI before tagging the next unused stable version. Preserve failed
   tags and request separate production approval for that concrete run.

The owner explicitly authorized these stages and merge after checks pass in one
continuous decision. Record results and failures honestly; do not convert a new
failure into a passing result by retrying without diagnosis.

Build-cache handling preserved all files, hashes, modes and symlinks on a local
APFS volume, with the original logical path retained. Only the byte-verified
original cache copy was removed. Source, pins, complete old bundles, and all
private evidence remain preserved. New build temporary files stay on that volume.
