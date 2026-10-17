#!/usr/bin/env bash
# Throwaway signing identity for release-style rehearsals. It never touches the
# login keychain, the keychain search list or any trust settings: the identity
# lives in a temporary keychain and a PATH shim adds `--keychain` to codesign.
#
#   rehearsal-keychain.sh create DIR   create DIR/{rehearsal.keychain-db,bin/codesign}
#   rehearsal-keychain.sh destroy DIR  delete the keychain and DIR
set -euo pipefail

NAME="Utter Rehearsal Signing"

create() {
    local dir="$1" pass
    mkdir -p "$dir/bin"
    pass="$(openssl rand -hex 16)"
    cat > "$dir/openssl.cnf" <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_codesign
[ dn ]
CN = ${NAME}
[ v3_codesign ]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = critical, CA:false
EOF
    /usr/bin/openssl req -x509 -newkey rsa:2048 -config "$dir/openssl.cnf" -days 3 -nodes \
        -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -inkey "$dir/key.pem" -in "$dir/cert.pem" \
        -passout "pass:$pass" -out "$dir/identity.p12" 2>/dev/null
    security create-keychain -p "$pass" "$dir/rehearsal.keychain-db"
    security set-keychain-settings "$dir/rehearsal.keychain-db"
    security unlock-keychain -p "$pass" "$dir/rehearsal.keychain-db"
    security import "$dir/identity.p12" -k "$dir/rehearsal.keychain-db" -P "$pass" -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple: -s -k "$pass" "$dir/rehearsal.keychain-db" >/dev/null
    rm -f "$dir/key.pem" "$dir/identity.p12"
    cat > "$dir/bin/codesign" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
    if [ "\$arg" = "--sign" ] || [ "\$arg" = "-s" ]; then
        exec /usr/bin/codesign --keychain "$dir/rehearsal.keychain-db" "\$@"
    fi
done
exec /usr/bin/codesign "\$@"
EOF
    chmod +x "$dir/bin/codesign"
    echo "identity: ${NAME}"
}

destroy() {
    local dir="$1"
    security delete-keychain "$dir/rehearsal.keychain-db" 2>/dev/null || true
    rm -rf "$dir"
}

case "${1:-}" in
    create) create "${2:?directory required}" ;;
    destroy) destroy "${2:?directory required}" ;;
    *) echo "usage: $0 create|destroy DIR" >&2; exit 2 ;;
esac
