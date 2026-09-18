#!/usr/bin/env bash
#
# Tests for scripts/nightly-release-plan.sh: change detection, patch bumping,
# and the workflow wiring that consumes it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLANNER="$SCRIPT_DIR/nightly-release-plan.sh"
REPOSITORY="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKFLOW="$REPOSITORY/.github/workflows/nightly-release.yml"
ARTIFACT_WORKFLOW="$REPOSITORY/.github/workflows/release-artifact.yml"
RELEASE_WORKFLOW="$REPOSITORY/.github/workflows/release.yml"

FIXTURE="$(mktemp -d)"
trap 'rm -r "$FIXTURE"' EXIT

fail() {
    echo "error: $*" >&2
    exit 1
}

field() {
    # field <output> <key>
    printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1
}

git -C "$FIXTURE" init -q -b main
git -C "$FIXTURE" -c user.name=Test -c user.email=test@example.com \
    commit --allow-empty -qm base

# No stable tag yet -> first release, version 0.0.1.
out="$("$PLANNER" "$FIXTURE" main)"
[ "$(field "$out" changed)" = "true" ] || fail "expected changed=true without a tag"
[ "$(field "$out" version)" = "0.0.1" ] || fail "first release must be 0.0.1"
[ "$(field "$out" latest_tag)" = "" ] || fail "latest_tag must be empty without a tag"

# Stable tag on the tip -> nothing to release.
git -C "$FIXTURE" tag v0.0.45
out="$("$PLANNER" "$FIXTURE" main)"
[ "$(field "$out" changed)" = "false" ] || fail "expected changed=false at the tagged tip"
[ "$(field "$out" commit_count)" = "0" ] || fail "expected commit_count=0"
printf '%s\n' "$out" | grep -q '^reason=' || fail "skipped runs must state a reason"

# One new commit -> patch bump.
git -C "$FIXTURE" -c user.name=Test -c user.email=test@example.com \
    commit --allow-empty -qm "feat: nightly"
out="$("$PLANNER" "$FIXTURE" main)"
[ "$(field "$out" changed)" = "true" ] || fail "expected changed=true after a new commit"
[ "$(field "$out" version)" = "0.0.46" ] || fail "expected patch bump to 0.0.46"
[ "$(field "$out" latest_tag)" = "v0.0.45" ] || fail "expected latest_tag=v0.0.45"
[ "$(field "$out" commit_count)" = "1" ] || fail "expected commit_count=1"
[ "$(field "$out" head_sha)" = "$(git -C "$FIXTURE" rev-parse HEAD)" ] \
    || fail "head_sha must be the branch tip"
printf '%s\n' "$out" | grep -q '^commit_summary=.*feat: nightly' \
    || fail "commit_summary must list the new commit"

# Patch bump keeps major/minor and rolls over 9 -> 10.
git -C "$FIXTURE" tag v0.0.46
git -C "$FIXTURE" tag v0.1.9
git -C "$FIXTURE" -c user.name=Test -c user.email=test@example.com \
    commit --allow-empty -qm "fix: rollover"
out="$("$PLANNER" "$FIXTURE" main)"
[ "$(field "$out" version)" = "0.1.10" ] || fail "expected 0.1.10, got $(field "$out" version)"
[ "$(field "$out" latest_tag)" = "v0.1.9" ] || fail "expected v0.1.9 to win version ordering"

# Version ordering is numeric, not lexicographic (v0.0.9 < v0.0.10).
FIXTURE2="$(mktemp -d)"
git -C "$FIXTURE2" init -q -b main
git -C "$FIXTURE2" -c user.name=Test -c user.email=test@example.com \
    commit --allow-empty -qm base
git -C "$FIXTURE2" tag v0.0.9
git -C "$FIXTURE2" tag v0.0.10
out="$("$PLANNER" "$FIXTURE2" main)"
[ "$(field "$out" latest_tag)" = "v0.0.10" ] || fail "expected v0.0.10 as latest"
rm -r "$FIXTURE2"

# Prerelease/build tags are never treated as release tags.
FIXTURE3="$(mktemp -d)"
git -C "$FIXTURE3" init -q -b main
git -C "$FIXTURE3" -c user.name=Test -c user.email=test@example.com \
    commit --allow-empty -qm base
git -C "$FIXTURE3" tag v1.2.3-beta
out="$("$PLANNER" "$FIXTURE3" main)"
[ "$(field "$out" version)" = "0.0.1" ] || fail "prerelease tags must be ignored"
rm -r "$FIXTURE3"

# Unknown branch and non-repository paths fail closed.
if "$PLANNER" "$FIXTURE" does-not-exist >/dev/null 2>&1; then
    fail "unknown branch must fail"
fi
if "$PLANNER" >/dev/null 2>&1; then
    fail "missing repository argument must fail"
fi

# The nightly workflow must be scheduled and dispatchable, must serialize runs,
# and must tag a main commit through the shared artifact pipeline.
grep -Fq 'cron: "0 12 * * *"' "$WORKFLOW" || fail "nightly schedule must be 12:00 UTC"
grep -Fq 'workflow_dispatch:' "$WORKFLOW" || fail "nightly workflow needs workflow_dispatch"
grep -Fq 'group: nightly-release' "$WORKFLOW" || fail "nightly workflow needs a concurrency group"
grep -Fq 'cancel-in-progress: false' "$WORKFLOW" || fail "nightly runs must not cancel a publishing run"
grep -Fq "if: \${{ needs.plan.outputs.changed == 'true' }}" "$WORKFLOW" \
    || fail "release jobs must be gated on detected changes"
grep -Fq 'create_tag: true' "$WORKFLOW" || fail "nightly must create the tag through the reusable workflow"
grep -Fq './scripts/nightly-release-plan.sh . origin/main' "$WORKFLOW" \
    || fail "nightly must plan through the script, not inline logic"

# Both release entry points must share the artifact pipeline.
for workflow in "$RELEASE_WORKFLOW" "$WORKFLOW"; do
    grep -Fq 'uses: ./.github/workflows/release-artifact.yml' "$workflow" \
        || fail "$workflow must call the reusable artifact workflow"
done

# Guardrails copied from the tag workflow must survive in the shared pipeline.
grep -Fq 'SIGNING_MODE=self-signed' "$ARTIFACT_WORKFLOW"
[ "$(grep -Fc 'VERIFY_ARGS+=(--require-self-signed)' "$ARTIFACT_WORKFLOW")" -eq 2 ]
grep -Fq 'VERIFY_ARGS+=(--require-developer-id --require-notarization)' "$ARTIFACT_WORKFLOW"
[ "$(grep -Fc -- '--expected-cert-sha256 "$SIGN_CERT_SHA256"' "$ARTIFACT_WORKFLOW")" -eq 2 ]
grep -Fq "if: env.SIGNING_MODE == 'developer-id'" "$ARTIFACT_WORKFLOW"
grep -Fq 'This release is signed with the project self-signed certificate' "$ARTIFACT_WORKFLOW"
grep -Fq 'refusing to replace immutable assets' "$ARTIFACT_WORKFLOW"
if grep -Eq -- '--clobber|--sign=-|will use ad-hoc' "$ARTIFACT_WORKFLOW"; then
    fail "release pipeline can replace assets or fall back to ad-hoc signing"
fi

echo "Nightly release plan tests passed."
