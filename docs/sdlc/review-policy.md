# Review policy

Review the accepted intent and committed evidence before the diff. A passing CI
run proves only its named checks; it does not prove the product outcome.

## Review passes

1. **Intent and scope:** Does the diff satisfy each acceptance criterion without
   expanding scope or silently changing the product decision?
2. **Correctness:** Check state, concurrency, failure recovery, boundary cases,
   compatibility, and adjacent regressions.
3. **Privacy and security:** Check microphone, screen, selected text, history,
   remote requests, logs, credentials, authorization, and least privilege.
4. **macOS and release:** Check native interaction, localization, TCC behavior,
   signing, Metal resources, bundle contents, upgrade safety, and rollback.

## Finding contract

An actionable finding includes:

- a tight file/line location;
- the triggering condition;
- concrete user/system impact;
- a severity based on impact and likelihood;
- a way to reproduce or verify the correction.

Do not bury correctness or risk findings under style comments. If no actionable
finding remains, say so and list any evidence gap separately.

## Independent verification

Medium-risk work benefits from a fresh-context read-only review. High-risk work
requires one. The verifier reads the accepted artifacts, inspects the actual
diff and results, and reruns risk-critical checks. The verifier reports findings
and evidence gaps; it does not repair the change or approve production.

The author or implementation agent cannot satisfy the human approval gate.
