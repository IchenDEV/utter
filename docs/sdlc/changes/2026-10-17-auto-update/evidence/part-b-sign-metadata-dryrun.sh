#!/usr/bin/env bash
#
# Dry-run the release workflow's "Sign update metadata" step against fixture
# inputs with a throwaway Ed25519 key.
#
# The step script is extracted from the real workflow, and the real
# generate-appcast.py, verify-update-signature.swift and Sparkle sign_update are
# used. Only curl and git are stubbed. The login keychain, the production secret
# and any real release are never touched.
#
# usage: part-b-sign-metadata-dryrun.sh [SPARKLE_TOOLS_BIN]
#
# Prints a JSON report on stdout.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/release-artifact.yml"
TOOLS="${1:-$ROOT/.build/artifacts/sparkle/Sparkle/bin}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "dry run failed: $*" >&2; exit 1; }
[ -x "$TOOLS/sign_update" ] || fail "no sign_update in $TOOLS (pass SPARKLE_TOOLS_BIN)"

# ─── Extract the literal steps the workflow runs ─────────────────────────────
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

step_script "$WORKFLOW" 'Sign update metadata' > "$WORK/sign-metadata.sh"
step_script "$WORKFLOW" 'Require release credentials' > "$WORK/credentials.sh"

# ─── Fixture workspace and a throwaway key ───────────────────────────────────
mkdir -p "$WORK/work/scripts" "$WORK/work/dist" "$WORK/RUNNER_TEMP" "$WORK/bin" "$WORK/archive/bin"
cp "$ROOT/scripts/generate-appcast.py" "$ROOT/scripts/verify-update-signature.swift" "$WORK/work/scripts/"
cp "$TOOLS/sign_update" "$WORK/archive/bin/sign_update"

swift "$ROOT/scripts/tests/ed25519_fixture.swift" "$WORK/keys"
SEED="$(cat "$WORK/keys/seed.txt")"
OTHER_SEED="$(cat "$WORK/keys/other-seed.txt")"
PUBLIC="$(cat "$WORK/keys/public.txt")"

# The pinned archive is rebuilt locally so the step's own SHA-256 check is real.
tar -cJf "$WORK/work/Sparkle-2.10.0.tar.xz" -C "$WORK/archive" bin/sign_update
(cd "$WORK/work" && shasum -a 256 "Sparkle-2.10.0.tar.xz" > scripts/sparkle-tools.sha256)

# The verified DMG and the app plist the verifier dumps out of it.
head -c 65536 /dev/urandom > "$WORK/work/dist/Utter-0.0.56.dmg"
cat > "$WORK/RUNNER_TEMP/dmg-app-Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleShortVersionString</key><string>0.0.56</string>
  <key>CFBundleVersion</key><string>0.0.56</string>
  <key>SUPublicEDKey</key><string>$PUBLIC</string>
</dict></plist>
PLIST

# Only curl and git are replaced; shasum, tar, python3, swift and sign_update are real.
cat > "$WORK/bin/curl" <<STUB
#!/usr/bin/env bash
out=""
while [ "\$#" -gt 0 ]; do
    case "\$1" in
        -o|--output) out="\$2"; shift 2 ;;
        *) shift ;;
    esac
done
cp "$WORK/work/Sparkle-2.10.0.tar.xz" "\$out"
STUB
cat > "$WORK/bin/git" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
    describe) echo v0.0.55 ;;
    log) printf '%s\n' '- Fix a thing' '- Add another thing' ;;
    *) echo "unexpected git $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$WORK/bin/curl" "$WORK/bin/git"

run_step() {
    ( cd "$WORK/work" && \
      PATH="$WORK/bin:$PATH" \
      GITHUB_WORKSPACE="$WORK/work" \
      RUNNER_TEMP="$WORK/RUNNER_TEMP" \
      RELEASE_TAG=v0.0.56 \
      RELEASE_VERSION=0.0.56 \
      SPARKLE_ED_PRIVATE_KEY="$1" \
      bash -e "$WORK/sign-metadata.sh" )
}

# ─── The happy path, exactly as the workflow runs it ─────────────────────────
run_step "$SEED" > "$WORK/happy.log" 2>&1 \
    || { cat "$WORK/happy.log"; fail "the step failed on valid inputs"; }
[ -s "$WORK/work/dist/appcast.xml" ] || fail "the step produced no appcast"
grep -q 'sparkle-signatures' "$WORK/work/dist/appcast.xml" || fail "the feed is unsigned"
grep -q 'edSignature' "$WORK/work/dist/appcast.xml" || fail "the feed has no edSignature"
grep -q -- '--ed-key-file -' "$WORK/sign-metadata.sh" || fail "the step does not read the key from stdin"

# ─── Fail-closed cases ───────────────────────────────────────────────────────
missing_secret_rejected=false
if bash -e "$WORK/credentials.sh" > "$WORK/missing.log" 2>&1; then
    fail "the credentials step accepted a missing secret"
fi
grep -q 'SPARKLE_ED_PRIVATE_KEY' "$WORK/missing.log" || fail "the failure did not name the secret"
missing_secret_rejected=true

wrong_key_rejected=false
if run_step "$OTHER_SEED" > "$WORK/wrong.log" 2>&1; then
    fail "the step published a feed the shipped public key cannot validate"
fi
grep -q 'does not match' "$WORK/wrong.log" || fail "the wrong key was rejected for the wrong reason"
wrong_key_rejected=true

DMG_SIGNATURE="$(printf '%s' "$SEED" | "$TOOLS/sign_update" --ed-key-file - -p "$WORK/work/dist/Utter-0.0.56.dmg")"
head -c 65536 "$WORK/work/dist/Utter-0.0.56.dmg" > "$WORK/tampered.dmg"
printf 'x' >> "$WORK/tampered.dmg"
tampered_dmg_rejected=false
if swift "$WORK/work/scripts/verify-update-signature.swift" --public-key "$PUBLIC" \
        --dmg "$WORK/tampered.dmg" --signature "$DMG_SIGNATURE" > "$WORK/tamper.log" 2>&1; then
    fail "a tampered DMG verified"
fi
grep -q 'does not match' "$WORK/tamper.log" || fail "the tampered DMG was rejected for the wrong reason"
tampered_dmg_rejected=true

unsigned_feed_rejected=false
sed '/sparkle-signatures/,$d' "$WORK/work/dist/appcast.xml" > "$WORK/unsigned.xml"
if swift "$WORK/work/scripts/verify-update-signature.swift" --public-key "$PUBLIC" \
        --feed "$WORK/unsigned.xml" > "$WORK/unsigned.log" 2>&1; then
    fail "an unsigned feed verified"
fi
unsigned_feed_rejected=true

cat <<JSON
{
  "step": "Sign update metadata (extracted from .github/workflows/release-artifact.yml)",
  "tools": "$TOOLS/sign_update",
  "happy_path": "pass",
  "missing_secret_rejected": $missing_secret_rejected,
  "wrong_key_rejected": $wrong_key_rejected,
  "tampered_dmg_rejected": $tampered_dmg_rejected,
  "unsigned_feed_rejected": $unsigned_feed_rejected,
  "feed_bytes": $(wc -c < "$WORK/work/dist/appcast.xml" | tr -d ' '),
  "dmg_bytes": $(wc -c < "$WORK/work/dist/Utter-0.0.56.dmg" | tr -d ' ')
}
JSON
