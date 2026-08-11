#!/usr/bin/env bash
#
# create-signing-cert.sh — Create a self-signed code-signing certificate
#
# This is a FREE alternative to the paid Apple Developer ID ($699/yr).
# Apps signed with this cert will show "unverified developer" on first launch,
# but TCC permissions (Microphone, Accessibility, etc.) will persist across updates.
#
# Usage:
#   ./scripts/create-signing-cert.sh                  # install to login keychain
#   ./scripts/create-signing-cert.sh --export cert.p12 # also export .p12 for CI
#

set -euo pipefail

CERT_NAME="Utter Signing"
DAYS_VALID=3650   # ~10 years
P12_PASSWORD="opentype"
EXPORT_PATH=""

for arg in "$@"; do
    case "$arg" in
        --export=*) EXPORT_PATH="${arg#*=}" ;;
        --export)   EXPORT_PATH="Utter-Signing.p12" ;;
        --help|-h)
            echo "Usage: $0 [--export[=path.p12]]"
            echo ""
            echo "  Creates a self-signed code-signing certificate '${CERT_NAME}'"
            echo "  and installs it to your login keychain."
            echo ""
            echo "  --export[=path]  Also export as .p12 (for GitHub Actions secrets)"
            echo "                   Default export name: Utter-Signing.p12"
            echo "                   P12 password: ${P12_PASSWORD}"
            exit 0
            ;;
    esac
done

TMPDIR_CERT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_CERT"' EXIT

KEY_FILE="${TMPDIR_CERT}/key.pem"
CERT_FILE="${TMPDIR_CERT}/cert.pem"
P12_FILE="${TMPDIR_CERT}/cert.p12"
CONF_FILE="${TMPDIR_CERT}/cert.conf"

# Check if certificate already exists
if security find-identity -v -p codesigning 2>/dev/null | grep -q "${CERT_NAME}"; then
    echo "✓ Certificate '${CERT_NAME}' already exists in keychain."
    if [ -n "$EXPORT_PATH" ]; then
        echo ""
        echo "To export the existing cert, use Keychain Access:"
        echo "  1. Open Keychain Access"
        echo "  2. Find '${CERT_NAME}'"
        echo "  3. Right-click → Export Items → Save as .p12"
    fi
    exit 0
fi

echo "▶ Creating self-signed code-signing certificate: '${CERT_NAME}'"

cat > "$CONF_FILE" << EOF
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
distinguished_name = dn
x509_extensions    = v3_codesign

[ dn ]
CN = ${CERT_NAME}

[ v3_codesign ]
keyUsage         = critical, digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = critical, CA:false
EOF

openssl req -x509 -newkey rsa:2048 \
    -config "$CONF_FILE" \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -days "$DAYS_VALID" \
    -nodes 2>/dev/null

openssl pkcs12 -export \
    -out "$P12_FILE" \
    -inkey "$KEY_FILE" \
    -in "$CERT_FILE" \
    -passout "pass:${P12_PASSWORD}" 2>/dev/null

echo "  ✓ Certificate generated"

echo "▶ Importing to login keychain…"
security import "$P12_FILE" \
    -k ~/Library/Keychains/login.keychain-db \
    -P "$P12_PASSWORD" \
    -T /usr/bin/codesign 2>/dev/null

echo "  ✓ Imported to keychain"

# Allow codesign to use this cert without prompting for password
security set-key-partition-list -S apple-tool:,apple: \
    -k "" ~/Library/Keychains/login.keychain-db 2>/dev/null || true

if [ -n "$EXPORT_PATH" ]; then
    cp "$P12_FILE" "$EXPORT_PATH"
    echo ""
    echo "  ✓ Exported to: ${EXPORT_PATH}"
    echo "    Password: ${P12_PASSWORD}"
    echo ""
    echo "  For GitHub Actions, run:"
    echo "    base64 -i '${EXPORT_PATH}' | pbcopy"
    echo "  Then paste into GitHub Secret: APPLE_CERTIFICATE_P12"
    echo "  Set APPLE_CERTIFICATE_PASSWORD to: ${P12_PASSWORD}"
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Done! Certificate '${CERT_NAME}' is ready."
echo ""
echo "  Build with:  ./scripts/build-app.sh"
echo "  (auto-detects the certificate)"
echo "═══════════════════════════════════════════════════"
