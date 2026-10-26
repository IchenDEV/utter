# Verification: Bound the shutdown drain so a stalled subsystem cannot strand the app

**Status:** draft
**Approved-by:** —
**Approved-date:** —
**Upstream:** [plan.md](plan.md) (approved 2026-10-26)

## Evidence

No implementation exists yet, so there is nothing to verify. The incident
investigation that motivated this change is recorded in [intent.md](intent.md).

## Residual risk

The stalled subsystem is not identified. Until it is, any update from an installed
version that has the stall can strand the app, and only a manual force-quit recovers it.
