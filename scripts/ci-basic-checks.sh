#!/usr/bin/env bash
#
# Lightweight CI guardrails for pull-request checks.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
    echo "error: $*" >&2
    exit 1
}

step() {
    echo ""
    echo "==> $*"
}

step "Checking Package.swift"
package_description="$(swift package describe)"
if printf '%s\n' "$package_description" | grep -q 'Name: OpenTypeCLI'; then
    fail "offline industry edition must not publish the CLI product or target"
fi

step "Linting property lists and localized strings"
plutil -lint Resources/Info.plist
plutil -lint Resources/OpenType.entitlements
plutil -lint Sources/Resources/en.lproj/Localizable.strings
plutil -lint Sources/Resources/zh-Hans.lproj/Localizable.strings
swift -e 'import Foundation; for path in CommandLine.arguments.dropFirst() { _ = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) }' \
    Sources/Resources/MedicalLexicon.json \
    Sources/Resources/OfflineModelManifest.json

step "Checking brand and compatibility identifiers"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' Resources/Info.plist)" = "Utter Medical Offline" \
    || fail "CFBundleDisplayName must identify the medical offline edition"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' Resources/Info.plist)" = "Utter Medical Offline" \
    || fail "CFBundleExecutable must identify the medical offline edition"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' Resources/Info.plist)" = "Utter Medical Offline" \
    || fail "CFBundleName must identify the medical offline edition"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)" = "com.opentype.voiceinput.medical-offline" \
    || fail "medical offline edition must use its independent bundle identifier"

step "Checking localization key parity"
en_keys="$(mktemp)"
zh_keys="$(mktemp)"
trap 'rm -f "$en_keys" "$zh_keys"' EXIT

grep -E '^"[^"]+"\s*=' Sources/Resources/en.lproj/Localizable.strings \
    | sed -E 's/^"([^"]+)".*/\1/' \
    | sort >"$en_keys"
grep -E '^"[^"]+"\s*=' Sources/Resources/zh-Hans.lproj/Localizable.strings \
    | sed -E 's/^"([^"]+)".*/\1/' \
    | sort >"$zh_keys"

if ! diff -u "$en_keys" "$zh_keys"; then
    fail "localized string keys differ between en and zh-Hans"
fi

step "Checking required app resources"
test -f Sources/Resources/Sounds/start.caf || fail "missing start sound"
test -f Sources/Resources/Sounds/stop.caf || fail "missing stop sound"
test -s Resources/Info.plist || fail "missing Info.plist"
test -s Resources/OpenType.entitlements || fail "missing entitlements"
test -s Sources/Resources/AppIconLight.png || fail "missing light app icon"
test -s Sources/Resources/AppIconDark.png || fail "missing dark app icon"
test -s Sources/Resources/MedicalLexicon.json || fail "missing medical lexicon"
test -s Sources/Resources/OfflineModelManifest.json || fail "missing offline model manifest"
test -x scripts/build-industry-app.sh || fail "industry build script is not executable"
test -x scripts/verify-offline-model-bundle.sh || fail "offline bundle verifier is not executable"
test -s Sources/Resources/AppIcon.icon/Assets/AppIconLightForeground.png \
    || fail "missing light Icon Composer foreground"
test -s Sources/Resources/AppIcon.icon/Assets/AppIconDarkForeground.png \
    || fail "missing dark Icon Composer foreground"

step "Checking bundled helper names"
app_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' Resources/Info.plist)"
app_executable_lower="$(printf '%s' "$app_executable" | tr '[:upper:]' '[:lower:]')"
if command -v rg >/dev/null 2>&1; then
    helper_paths="$(rg --no-filename -o 'Contents/MacOS/[[:alnum:]._-]+' scripts Sources Tests || true)"
else
    helper_paths="$(grep -RhoE 'Contents/MacOS/[[:alnum:]._-]+' scripts Sources Tests || true)"
fi

while IFS= read -r helper_path; do
    [ -n "$helper_path" ] || continue
    helper_name="${helper_path##*/}"
    helper_name_lower="$(printf '%s' "$helper_name" | tr '[:upper:]' '[:lower:]')"
    if [ "$helper_name_lower" = "$app_executable_lower" ] && [ "$helper_name" != "$app_executable" ]; then
        fail "bundled helper '${helper_name}' conflicts with app executable '${app_executable}' on case-insensitive filesystems"
    fi
done <<< "$helper_paths"

step "Checking for conflict markers"
if command -v rg >/dev/null 2>&1; then
    conflict_markers="$(rg -n '^(<<<<<<<|=======|>>>>>>>)' --glob '!Package.resolved' . || true)"
else
    conflict_markers="$(grep -RInE '^(<<<<<<<|=======|>>>>>>>)' \
        --exclude=Package.resolved \
        --exclude-dir=.git \
        --exclude-dir=.build \
        --exclude-dir=.swiftpm \
        . || true)"
fi

if [ -n "$conflict_markers" ]; then
    echo "$conflict_markers"
    fail "found unresolved conflict markers"
fi

step "Checking for broken symlinks"
if find . \
    -path ./.git -prune -o \
    -path ./.build -prune -o \
    -path ./.swiftpm -prune -o \
    -type l ! -exec test -e {} \; -print | grep .; then
    fail "found broken symlinks"
fi

echo ""
echo "Basic CI checks passed."
