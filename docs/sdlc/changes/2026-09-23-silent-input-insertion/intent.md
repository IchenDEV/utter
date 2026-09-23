# Intent: Prevent unsolicited text insertion when no one speaks

**Status:** approved
**Approved-by:** User (conversation)
**Approved-date:** 2026-09-23
**Upstream:** User report in this conversation, 2026-09-23

## Problem

The user observed Utter inserting a long list of unrelated technical terms into the focused input field while the user was not speaking. The list included “Do anything” and terms that resemble the technology industry lexicon. This is an unsolicited output and can expose text to whichever application has focus. The specific microphone, recognition engine, and recording mode involved have not yet been identified.

## Outcome

An input session without user speech ends with no text insertion, clipboard write, spoken-edit action, or history entry. Intended speech still produces text, including legitimately spoken technical terms.

## Scope

- Trace local and remote microphone capture, streaming and recorded recognition, vocabulary context, transcript preparation, and every insertion path reachable from voice input.
- Reproduce the reported vocabulary-list output with a deterministic test or a privacy-safe captured trace before changing behavior.
- Fix the shared boundary responsible for unsolicited output and remove any bypass that permits the same failure.
- Keep microphone audio and transcript content out of diagnostic logs and repository fixtures unless the user explicitly supplies a safe sample.
- No change to cloud deployment, billing, or unrelated product features.

## Constraints

- Preserve correctly spoken short phrases, deliberate repetition, and vocabulary terms.
- Treat unintended insertion as a privacy-sensitive failure; avoid a broad phrase blacklist that would erase legitimate dictation.
- Follow the repository's staged approval, regression-test, independent-verification, and rollback requirements for a high-risk change.

## Acceptance criteria

- A deterministic regression check reproduces a no-speech session that currently inserts the reported kind of technical-term list; it passes after the fix and verifies that insertion and clipboard side effects do not occur.
- Silence and ambient non-speech audio cannot trigger final text insertion in direct, processed, command, or translation mode, including streaming and remote-microphone paths where applicable.
- Tests show that audible, intentionally spoken “Do anything” and representative technology terms remain insertable.
- The affected privacy and permission paths, repository checks, and a release-style app build pass; an independent verifier reviews the high-risk change before PR approval.

## Open questions

- Which microphone source, recognition engine, output mode, and trigger produced the observed list? Diagnosis can begin without these details, but they are needed to match the user's exact runtime path.
- Did the list appear in the Utter overlay before insertion, or only in the target application?
