#!/usr/bin/env bash
#
# Deterministic SDLC gate checks: stage artifacts must be approved in order,
# and every approval must carry an approver and a date.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
    echo "error: $*" >&2
    exit 1
}

CHANGES_DIR="docs/sdlc/changes"
INCIDENTS_DIR="docs/sdlc/incidents"

[ -d "$CHANGES_DIR" ] || fail "missing $CHANGES_DIR"

status_of() {
    sed -n 's/^\*\*Status:\*\*[[:space:]]*\([^#]*\).*/\1/p' "$1" | head -1 | tr -d '[:space:]'
}

field_of() {
    sed -n "s/^\\*\\*$1:\\*\\*[[:space:]]*//p" "$2" | head -1 | sed 's/[[:space:]]*$//'
}

check_change() {
    change_dir="$1"
    shift
    stage_order=(intent spec plan verification release)
    previous_approved=1

    for stage in "${stage_order[@]}"; do
        file="$change_dir/$stage.md"
        [ -f "$file" ] || fail "missing artifact $file"

        status="$(status_of "$file")"
        case "$status" in
        draft|pending|pendingapproval|approved|rejected|blocked) ;;
        *)
            fail "$file: Status must be one of draft|pending approval|approved|rejected|blocked (got '${status:-<empty>}')"
            ;;
        esac

        if [ "$status" = "approved" ]; then
            if [ "$previous_approved" -ne 1 ]; then
                fail "$file: approved while an earlier stage is not approved (order: intent -> spec -> plan -> verification -> release)"
            fi
            approver="$(field_of Approved-by "$file")"
            date="$(field_of Approved-date "$file")"
            [ -n "$approver" ] && [ "$approver" != "—" ] \
                || fail "$file: approved but Approved-by is missing"
            [ -n "$date" ] && [ "$date" != "—" ] \
                || fail "$file: approved but Approved-date is missing"
        else
            previous_approved=0
        fi
    done
}

for change_dir in "$CHANGES_DIR"/*/; do
    [ -d "$change_dir" ] || continue
    case "$change_dir" in */.) continue ;; esac
    echo "==> Checking $change_dir"
    check_change "${change_dir%/}"
done

if [ -d "$INCIDENTS_DIR" ]; then
    for incident in "$INCIDENTS_DIR"/*.md; do
        [ -f "$incident" ] || continue
        status="$(status_of "$incident")"
        case "$status" in
        open|mitigated|resolved) ;;
        *) fail "$incident: Status must be one of open|mitigated|resolved (got '${status:-<empty>}')" ;;
        esac
    done
fi

echo "SDLC checks passed."
