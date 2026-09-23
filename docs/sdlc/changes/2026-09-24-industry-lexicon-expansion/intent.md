# Expand common industry vocabulary

Status: draft
Risk: medium

## Request and scope

On 2026-09-24 the user requested downloading common industry dictionaries and explicitly selected the existing software technology, medical, legal and finance/accounting categories. Preserve local-first voice input, cloud support, existing curated aliases/corrections and personal-dictionary priority. This is an additional commit on PR #113. Stage statuses do not represent human review of these artifacts.

## Acceptance criteria

- Each existing pack retains its 30 curated entries and gains 2,000 deduplicated, frequency-ranked terms from an identified redistributable source.
- Pin and verify source content; distribute its license with the application. No runtime downloads or new dependencies.
- Imported terms introduce no automatic replacement mappings and no additional mandatory verbatim-output constraints.
- ASR context remains limited to 100 phrases with personal entries first. Industry LLM context is bounded to 80 entries and 2,000 characters; relevant terms can be selected from the entire pack.
- Existing correction and non-target-preservation tests pass; verify bundled resources and release-style packaging.
