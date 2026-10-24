#!/usr/bin/env bash
# Execute release workflow shell blocks without credentials or remote writes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NIGHTLY="$ROOT/.github/workflows/nightly-release.yml"
MANUAL="$ROOT/.github/workflows/release.yml"
ARTIFACT="$ROOT/.github/workflows/release-artifact.yml"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
failures=0

check() {
    if ! "$@"; then
        echo "FAIL: $*" >&2
        failures=$((failures + 1))
    fi
}

# Only the named step's literal run block, never a copied implementation.
step_script() {
    awk -v name="$2" '
        $0 == "      - name: " name { found = 1; next }
        found && /^      - / { exit }
        found && /^        run: / {
            code = substr($0, 14)
            if (code != "|") { print code; emitted = 1; exit }
            block = 1; next
        }
        block && /^          / { print substr($0, 11); emitted = 1; next }
        block && /^[[:space:]]*$/ { print ""; next }
        block { exit }
        END { if (!emitted) exit 1 }
    ' "$1"
}

job_text() {
    awk -v job="$2" '
        $0 == "  " job ":" { found = 1; next }
        found && /^  [a-z_-]+:$/ { exit }
        found { print }
    ' "$1"
}

field() { sed -n "s/^$2=//p" "$1"; }

step_script "$NIGHTLY" 'Decide whether main moved since the latest release' > "$FIXTURE/plan.sh"
step_script "$MANUAL" 'Resolve version from tag' > "$FIXTURE/manual.sh"
step_script "$ARTIFACT" 'Validate version and tag' > "$FIXTURE/validate.sh"
step_script "$ARTIFACT" 'Require a SemVer tag on main' > "$FIXTURE/ancestor.sh"
step_script "$ARTIFACT" 'Create and push release tag' > "$FIXTURE/create.sh"

# Verify the values emitted by shell steps actually reach the reusable caller.
job_text "$NIGHTLY" plan > "$FIXTURE/plan-job"
job_text "$NIGHTLY" release > "$FIXTURE/nightly-call"
job_text "$MANUAL" validate > "$FIXTURE/manual-job"
job_text "$MANUAL" release > "$FIXTURE/manual-call"
check grep -Fq 'version: ${{ steps.plan.outputs.version }}' "$FIXTURE/plan-job"
check grep -Fq 'tag: ${{ steps.plan.outputs.tag }}' "$FIXTURE/plan-job"
check grep -Fq 'version: ${{ needs.plan.outputs.version }}' "$FIXTURE/nightly-call"
check grep -Fq 'tag: ${{ needs.plan.outputs.tag }}' "$FIXTURE/nightly-call"
check grep -Fq "if: \${{ needs.plan.outputs.changed == 'true' }}" "$FIXTURE/nightly-call"
check grep -Fq 'version: ${{ steps.version.outputs.value }}' "$FIXTURE/manual-job"
check grep -Fq 'version: ${{ needs.validate.outputs.version }}' "$FIXTURE/manual-call"
check grep -Fq 'tag: ${{ github.ref_name }}' "$FIXTURE/manual-call"
ancestor_condition="$(awk '
    /      - name: Require a SemVer tag on main/ { found = 1; next }
    found && /^      - / { exit }
    found && /^        if: / { print substr($0, 13); exit }
' "$ARTIFACT")"
check test "$ancestor_condition" = '${{ inputs.require_ancestor && !inputs.create_tag }}'

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
export REAL_GIT="$(command -v git)"
git init -q -b main "$FIXTURE/seed"
git -C "$FIXTURE/seed" commit --allow-empty -qm base
git clone -q --bare "$FIXTURE/seed" "$FIXTURE/origin.git"
git clone -q "$FIXTURE/origin.git" "$FIXTURE/work"
mkdir -p "$FIXTURE/bin" "$FIXTURE/work/scripts"
cp "$ROOT/scripts/release-version.sh" "$ROOT/scripts/nightly-release-plan.sh" "$FIXTURE/work/scripts/"
export PUSH_LOG="$FIXTURE/push.log"
cat > "$FIXTURE/bin/git" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = push ]; then
    printf '%s\n' "$*" >> "$PUSH_LOG"
    exit 0
fi
exec "$REAL_GIT" "$@"
STUB
chmod +x "$FIXTURE/bin/git"
export PATH="$FIXTURE/bin:$PATH"
cd "$FIXTURE/work"
export GITHUB_OUTPUT="$FIXTURE/output"

validate_pair() {
    RELEASE_VERSION="$1" RELEASE_TAG="$2" bash -e "$FIXTURE/validate.sh"
}

reject_pair() {
    ! validate_pair "$1" "$2" > "$FIXTURE/rejected.log" 2>&1
}

: > "$GITHUB_OUTPUT"
bash -e "$FIXTURE/plan.sh" >/dev/null
check test "$(field "$GITHUB_OUTPUT" version)" = 0.0.1
check test "$(field "$GITHUB_OUTPUT" tag)" = v0.0.1
check validate_pair "$(field "$GITHUB_OUTPUT" version)" "$(field "$GITHUB_OUTPUT" tag)"

git tag v0.0.46
: > "$GITHUB_OUTPUT"
bash -e "$FIXTURE/plan.sh" >/dev/null
check test "$(field "$GITHUB_OUTPUT" changed)" = false
check test -z "$(field "$GITHUB_OUTPUT" version)"
check test -z "$(field "$GITHUB_OUTPUT" tag)"

git commit --allow-empty -qm 'fix: candidate'
git update-ref refs/remotes/origin/main HEAD
: > "$GITHUB_OUTPUT"
bash -e "$FIXTURE/plan.sh" >/dev/null
check test "$(field "$GITHUB_OUTPUT" version)" = 0.0.47
check test "$(field "$GITHUB_OUTPUT" tag)" = v0.0.47
check validate_pair "$(field "$GITHUB_OUTPUT" version)" "$(field "$GITHUB_OUTPUT" tag)"

: > "$GITHUB_OUTPUT"
GITHUB_REF_NAME=v0.0.47 bash -e "$FIXTURE/manual.sh"
check test "$(field "$GITHUB_OUTPUT" value)" = 0.0.47
check validate_pair "$(field "$GITHUB_OUTPUT" value)" v0.0.47
check reject_pair 0.0.47 ''
check reject_pair 0.0.47 v00.0.47
check reject_pair 0.0.48 v0.0.47
check reject_pair v0.0.47 v0.0.47

# Match the local bare remote to the candidate without ever pushing.
git --git-dir="$FIXTURE/origin.git" fetch -q "$PWD" main:main
check env RELEASE_TAG=v0.0.46 bash -e "$FIXTURE/ancestor.sh"
check test ! -e "$PUSH_LOG"

# The create-tag path must work before its new tag exists.
check test -z "$(git tag -l v0.0.47)"
check env RELEASE_TAG=v0.0.47 bash -e "$FIXTURE/create.sh"
check test "$(git rev-parse 'v0.0.47^{commit}')" = "$(git rev-parse HEAD)"
check grep -Fxq 'push origin refs/tags/v0.0.47' "$PUSH_LOG"
rm -f "$PUSH_LOG"

reject_step() {
    ! RELEASE_TAG="$2" bash -e "$FIXTURE/$1.sh" > "$FIXTURE/rejected.log" 2>&1
}

check reject_step ancestor v9.9.9
# A tag from a divergent branch must fail the existing-tag ancestry check.
git checkout -qb side HEAD~1
git commit --allow-empty -qm side
git tag v0.0.48
git checkout -q main
check reject_step ancestor v0.0.48
check test ! -e "$PUSH_LOG"

# Main advanced after the checked-out candidate: reject before creating a tag.
git -C "$FIXTURE/seed" fetch -q "$FIXTURE/origin.git" main
git -C "$FIXTURE/seed" reset -q --hard FETCH_HEAD
git -C "$FIXTURE/seed" commit --allow-empty -qm advanced
git --git-dir="$FIXTURE/origin.git" fetch -q "$FIXTURE/seed" main:main
check reject_step create v0.0.49
check test -z "$(git tag -l v0.0.49)"
check test ! -e "$PUSH_LOG"

# Existing remote tag is refused even when the candidate equals main.
git fetch -q origin main
git reset -q --hard origin/main
git --git-dir="$FIXTURE/origin.git" tag v0.0.50
check reject_step create v0.0.50
check test -z "$(git tag -l v0.0.50)"
check test ! -e "$PUSH_LOG"

[ "$failures" -eq 0 ] || { echo "$failures release contract checks failed." >&2; exit 1; }
echo "Release workflow contract tests passed."
