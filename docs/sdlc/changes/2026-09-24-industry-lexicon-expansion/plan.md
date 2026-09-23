# Implementation and validation

Status: draft

1. Verify upstream license, immutable revision and source checksums; import common vocabulary into the existing resource.
2. Preserve curated corrections and personal priority; bound recognition/prompt contexts and select transcript-relevant hints.
3. Add regression coverage for imported-data semantics, packaged license, long-tail hints and budget limits.
4. Run importer twice to check reproducibility, deterministic lexicon checks, SDLC/basic checks, full Swift tests and release-style build.
5. Push a separate commit to PR #113, update its final scope, and verify mergeability and remote checks. Physical ASR quality is not established by text-only tests.
