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
step_script "$ARTIFACT" 'Classify and verify signed artifact' > "$FIXTURE/classify.sh"
step_script "$ARTIFACT" 'Verify distribution and checksum' > "$FIXTURE/distribution.sh"

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

# Run the literal distribution block with observable external signing state.
export SIGN_IDENTITY='Developer ID Application: Fixture (ABC1234567)'
export SIGN_CERT_SHA256="$(printf '%064d' 0)"
export RELEASE_VERSION=0.0.54 TEAM_IDENTIFIER=ABC1234567 FAIL_SIGN=0
export SIGNING_TRACE="$FIXTURE/signing-trace" SIGNED_DMG="$FIXTURE/signed-dmg"
export GITHUB_ENV="$FIXTURE/github-env" GITHUB_STEP_SUMMARY="$FIXTURE/summary"
cat > "$FIXTURE/bin/codesign" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = -dvvv ]; then
    printf 'Authority=%s\nTeamIdentifier=%s\n' "$SIGN_IDENTITY" "$TEAM_IDENTIFIER"
    exit 0
fi
echo sign >> "$SIGNING_TRACE"
[ "$FAIL_SIGN" = 0 ] || exit 42
timestamp=false identifier=false identity=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --timestamp) timestamp=true ;;
        --identifier|-i) [ "$2" = com.opentype.voiceinput.dmg ]; identifier=true; shift ;;
        --sign|-s) [ "$2" = "$SIGN_IDENTITY" ]; identity=true; shift ;;
        --deep|--entitlements|--options) exit 43 ;;
    esac
    last="$1"
    shift
done
$timestamp && $identifier && $identity
[ "$last" = dist/Utter-0.0.54.dmg ]
touch "$SIGNED_DMG"
STUB
cat > scripts/verify-release-artifact.sh <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
echo verify >> "$SIGNING_TRACE"
updater=false template=''
while [ "$#" -gt 0 ]; do
    if [ "$1" = --require-developer-id ] && [ ! -f "$SIGNED_DMG" ]; then
        echo 'unsigned Developer ID DMG reached verification' >&2
        exit 1
    fi
    case "$1" in
        --require-updater) updater=true ;;
        --update-info) template="$2"; shift ;;
    esac
    shift
done
$updater && [ "$template" = Resources/UpdateInfo.plist ]
STUB
chmod +x "$FIXTURE/bin/codesign" scripts/verify-release-artifact.sh
export RUNNER_TEMP="$FIXTURE"
mkdir -p dist
printf 'fixture DMG\n' > dist/Utter-0.0.54.dmg
: > "$SIGNING_TRACE"
check bash -e "$FIXTURE/classify.sh"
check test "$(cat "$SIGNING_TRACE")" = $'sign\nverify'
check grep -Fxq SIGNING_MODE=developer-id "$GITHUB_ENV"
check env SIGNING_MODE=developer-id bash -e "$FIXTURE/distribution.sh"

rm -f "$SIGNED_DMG"
: > "$SIGNING_TRACE"
export FAIL_SIGN=1
check reject_step classify unused
check test "$(cat "$SIGNING_TRACE")" = sign
check test ! -e "$SIGNED_DMG"

export FAIL_SIGN=0 SIGN_IDENTITY='Utter Signing' TEAM_IDENTIFIER='not set'
: > "$SIGNING_TRACE"
check bash -e "$FIXTURE/classify.sh"
check test "$(cat "$SIGNING_TRACE")" = verify
check grep -Fxq SIGNING_MODE=self-signed "$GITHUB_ENV"
check test ! -e "$SIGNED_DMG"
check env SIGNING_MODE=self-signed bash -e "$FIXTURE/distribution.sh"

# ─── Update metadata contract ─────────────────────────────────────────────────
line_of() { grep -n "^      - name: $1\$" "$ARTIFACT" | cut -d: -f1; }
verify_line="$(line_of 'Verify distribution and checksum')"
sign_line="$(line_of 'Sign update metadata')"
publish_line="$(line_of 'Publish GitHub Release')"
check test -n "$verify_line"
check test -n "$sign_line"
check test -n "$publish_line"
check test "$verify_line" -lt "$sign_line"
check test "$sign_line" -lt "$publish_line"

credentials_step="$(step_script "$ARTIFACT" 'Require release credentials')"
check grep -Fq 'SPARKLE_ED_PRIVATE_KEY' <<<"$credentials_step"

build_step="$(step_script "$ARTIFACT" 'Build signed app and DMG')"
check grep -Fq -- '--updates' <<<"$build_step"

verify_step="$(step_script "$ARTIFACT" 'Verify distribution and checksum')"
check grep -Fq -- '--dump-app-plist' <<<"$verify_step"

sign_step="$(step_script "$ARTIFACT" 'Sign update metadata')"
check grep -Fq 'scripts/sparkle-tools.sha256' <<<"$sign_step"
check grep -Fq 'shasum -a 256 -c' <<<"$sign_step"
check grep -Fq 'scripts/generate-appcast.py' <<<"$sign_step"
check grep -Fq 'scripts/verify-update-signature.swift' <<<"$sign_step"
# The key must only ever arrive through the environment and stdin.
check grep -Fq 'printf '\''%s'\'' "$SPARKLE_ED_PRIVATE_KEY"' <<<"$sign_step"
check grep -Fq -- '--ed-key-file -' <<<"$sign_step"
check test -z "$(grep -F -- '--ed-key-file "$SPARKLE_ED_PRIVATE_KEY"' <<<"$sign_step" || true)"
check test -z "$(grep -F 'set -x' <<<"$sign_step" || true)"

publish_step="$(step_script "$ARTIFACT" 'Publish GitHub Release')"
check grep -Fq 'dist/appcast.xml' <<<"$publish_step"
check grep -Fq 'cmp "dist/appcast.xml"' <<<"$publish_step"

# The build uses its committed default; verification names that template explicitly.
check test -z "$(grep -F -- '--update-info' <<<"$build_step" || true)"

[ "$failures" -eq 0 ] || { echo "$failures release contract checks failed." >&2; exit 1; }
echo "Release workflow contract tests passed."
