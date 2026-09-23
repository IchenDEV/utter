# Common vocabulary import and bounded context

Status: draft

## Source and rights

Use [THUOCL](https://github.com/thunlp/THUOCL), MIT, Copyright (c) 2018 THUNLP, revision `a30ce79d895d01ab5132a5c74c29703ff7efb4cc`. Import IT, medical, law and caijing files. These are historical corpus-frequency lists, not up-to-date professional standards or clinically/legal-reviewed advice. Keep modern curated entries, including AI terminology. Each pack remains explicitly marked as needing domain review.

`scripts/import-industry-lexicons.py` contains pinned SHA-256 checksums, supports verified offline originals, preserves curated entries, and deterministically ranks by descending document frequency then lexical order. Exclude malformed frequency rows, blank/control/whitespace-containing terms, numeric-only terms and terms outside 2–40 characters. Exclude duplicates of curated terms, aliases and correction inputs. Select 2,000 additional terms per pack; imported entries have no invented aliases or correction mappings. The importer is idempotent. Bundle the original MIT notice as `THUOCL-LICENSE.txt`.

## Runtime contract

The catalog is the only data source for browsing, recognition context and prompt selection. Curated terms retain order and precedence. ASR receives at most 100 industry phrases before the existing personal-first combined cap. LLM hints prioritize exact case-insensitive matches from the full active pack, longest first, then fill from the leading common/curated entries, with hard limits of 80 entries and 2,000 characters. Normal formatting and command processing, including image-model fallback, provide the current transcript for this selection. Other callers receive the bounded default hints.

Imported broad words such as “发展” are hints only: they must not become mandatory literal-output constraints that reject ordinary model formatting. Existing curated protected terms and replacement mappings retain their behavior. No fuzzy phonetic matching, new inference layer, or second vocabulary store is introduced.

## Failure and rollback

Checksum mismatch fails the import before writing resources. Existing catalog validation rejects malformed sources/packs. Tests exercise catalog loading, license packaging, personal priority, long-tail selection and prompt budgets. Roll back this isolated vocabulary commit to restore seed-only data and prompt construction; no user data migration is involved.
