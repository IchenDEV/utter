# Run 2 retained increment

**Status:** draft
**Owner:** lead recovery after bounded Codex cancellation

Base ed4234b41764be8346ae58cdc63011c8f26a0f1e; uncommitted diff SHA256 06424f638677956353ff65fcfef6745fdfa08fa9df7ce93f44be4f242df39d8b. No package candidate/hash. Six owner files changed, +55/-7: DeliveryServices, SessionOutputStateService, NativeOutputBackend, ScopedOutputService, VoiceSessionJob+Editing, SessionOutputState.

SelectionEditReceipt carries operationID/originalSelection/replacement/anchor; DeliveryReceipt retains only accepted targetValue and matching operation/anchor. Native backend captures selection before existing transaction and attaches only after readback. Session remembers confirmed receipt; consume removes anchor before restore attempt. Selection undo uses replaceAnchor(originalSelection); ordinary insertion keeps existing empty undo. Replay ScopedOutput receipt strips anchors and new selectionEdit by default.

Lead inspected exact diff and Swift frontend parse passed. Not typechecked/built, no real behavioral acceptance. SDLC passed. basic and swift-test skip-build each bounded8s, SIGTERM exit-15, terminal confirmed; lexicon check/dependency working copy incomplete. No release-style build or signed package; no device/private host/clipboard access. UI preview not wired into product; existing automatic spoken edit path still exists. Need pending-proposal integration before complete behavior can ship.

Remaining code review: receipt validation original/replacement integrity, consume-on-failed-delivery semantics, lifetime of consumed operation set, focus-return/readback/secure fields, independent behavior E2E. No claim of product pass.
