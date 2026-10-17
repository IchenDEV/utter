#!/usr/bin/env bash
#
# Prove scripts/sparkle-tools.sha256 pins the real Sparkle release asset, by
# cross-checking the downloaded archive against both the committed digest and
# the digest GitHub reports for the release asset.
#
# usage: part-b-tools-lock.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

LOCK="$ROOT/scripts/sparkle-tools.sha256"
ARCHIVE="$(awk '{print $2}' "$LOCK")"
PINNED="$(awk '{print $1}' "$LOCK")"
VERSION="${ARCHIVE#Sparkle-}"
VERSION="${VERSION%.tar.xz}"

curl -sSL -o "$WORK/$ARCHIVE" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/$ARCHIVE"
DOWNLOADED="$(shasum -a 256 "$WORK/$ARCHIVE" | awk '{print $1}')"
(cd "$WORK" && shasum -a 256 -c "$LOCK" >/dev/null)

ASSET_DIGEST="$(curl -sS "https://api.github.com/repos/sparkle-project/Sparkle/releases/tags/$VERSION" \
    | python3 -c 'import json,sys; name=sys.argv[1]; print(next(a["digest"] for a in json.load(sys.stdin)["assets"] if a["name"] == name))' \
    "$ARCHIVE")"

tar -xJf "$WORK/$ARCHIVE" -C "$WORK" bin/sign_update
SPM_TOOLS="$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"
if [ -x "$SPM_TOOLS" ]; then
    TARBALL_SIGN_UPDATE="$(shasum -a 256 "$WORK/bin/sign_update" | awk '{print $1}')"
    SPM_SIGN_UPDATE="$(shasum -a 256 "$SPM_TOOLS" | awk '{print $1}')"
    MATCHES_SPM=$([ "$TARBALL_SIGN_UPDATE" = "$SPM_SIGN_UPDATE" ] && echo true || echo false)
else
    MATCHES_SPM=null
fi

cat <<JSON
{
  "lock_file": "scripts/sparkle-tools.sha256",
  "archive": "$ARCHIVE",
  "sparkle_version": "$VERSION",
  "pinned_sha256": "$PINNED",
  "downloaded_sha256": "$DOWNLOADED",
  "github_asset_digest": "${ASSET_DIGEST#sha256:}",
  "lock_verifies_download": $([ "$PINNED" = "$DOWNLOADED" ] && echo true || echo false),
  "matches_github_asset_digest": $([ "${ASSET_DIGEST#sha256:}" = "$DOWNLOADED" ] && echo true || echo false),
  "tarball_sign_update_matches_swiftpm_artifact": $MATCHES_SPM
}
JSON
