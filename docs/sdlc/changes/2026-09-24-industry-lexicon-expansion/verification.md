# Vocabulary expansion verification

Status: pending approval

## Local evidence — 2026-09-24

- Each pack contains 30 original curated entries plus 2,000 imported entries: 8,120 total. Resource size 1,116,835 bytes.
- Pinned source downloads and MIT license matched the checksums recorded in the importer. Repeated import was byte-identical: generated JSON SHA-256 `3e8ea045b8d6aff82e1ab2b305c6be40db10189253ac4f673b192e60200d1eb6`.
- Importer filtering/deduplication and checksum-rejection checks passed, including missing frequency, numeric-only and embedded-whitespace terms.
- `bash scripts/test-industry-lexicons.sh`: passed existing synthetic text correction and non-target preservation cases. These are not audio-recognition measurements.
- `bash scripts/sdlc-checks.sh`: exit 0.
- `bash scripts/ci-basic-checks.sh`: exit 0.
- `swift test`: 772 XCTest cases, 16 skipped, zero failures; one additional Swift Testing case passed. New coverage checks licensed imported-data semantics, long-tail selection through prompt construction, entry/character budgets and preservation of complete entries. Existing personal-first and curated-correction tests pass.
- Release-style `xcodebuild -scheme OpenType -configuration Release -derivedDataPath .build/xcode -destination 'platform=macOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build -quiet`: exit 0. Packaged JSON and MIT license match source bytes; Metal library exists.
- `git diff --check`: passed. After fetching origin, the branch contains the current main without divergence.

## Boundaries

No new UI layout was introduced. Physical audio recognition accuracy, domain-expert review, real-window browsing performance, signed installation and production acceptance were not tested. Historical THUOCL data may include broad or outdated terms; imported entries remain optional hints without new automatic replacement mappings. Local validation does not establish remote CI success or human approval. PR #113 carries this expansion separately from the session-lifecycle commit.
