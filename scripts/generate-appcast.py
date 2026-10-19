#!/usr/bin/env python3
"""Write the one-item Sparkle appcast for a signed Utter release.

Standard library only. The feed is emitted unsigned; the release pipeline signs
it with Sparkle's `sign_update` and then verifies it independently with
`scripts/verify-update-signature.swift`.
"""
import argparse
import base64
import binascii
import datetime
import plistlib
import re
import sys
from pathlib import Path
from urllib.parse import quote
from xml.sax.saxutils import escape, quoteattr

REPOSITORY = "IchenDEV/utter"
ENCLOSURE_URL_BASE = f"https://github.com/{REPOSITORY}/releases/download"
TAG_PATTERN = re.compile(r"^v(\d+\.\d+\.\d+)$")
DMG_NAME_PATTERN = "Utter-{version}.dmg"
MINIMUM_SYSTEM_VERSION = "26.0"
HARDWARE_REQUIREMENTS = "arm64"


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def parse_version(tag, version):
    match = TAG_PATTERN.match(tag)
    if not match:
        fail(f"release tag is not vMAJOR.MINOR.PATCH: {tag}")
    tagged = match.group(1)
    if tagged != version:
        fail(f"tag {tag} does not match version {version}")
    return tagged


def read_app_plist(path, version):
    try:
        with open(path, "rb") as handle:
            info = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        fail(f"cannot read the app Info.plist: {error}")
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        actual = info.get(key)
        if actual != version:
            fail(f"app {key} is {actual!r}, expected {version!r}")
    return info


def signature_bytes(signature):
    try:
        raw = base64.b64decode(signature, validate=True)
    except (binascii.Error, ValueError):
        fail("the EdDSA signature is not valid base64")
    if len(raw) != 64:
        fail(f"the EdDSA signature must be 64 bytes, got {len(raw)}")
    return raw


def enclosure_url(base, tag, dmg):
    name = DMG_NAME_PATTERN.format(version=tag[1:])
    if dmg.name != name:
        fail(f"the DMG must be named {name}, got {dmg.name}")
    return f"{base}/{quote(tag)}/{quote(dmg.name)}"


def read_notes(path):
    if path is None:
        return ""
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError as error:
        fail(f"cannot read the release notes: {error}")


def rfc822(when):
    return when.astimezone(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")


def build(tag, version, url, signature, length, notes, pub_date, title):
    lines = [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"'
        ' xmlns:dc="http://purl.org/dc/elements/1.1/">',
        "  <channel>",
        f"    <title>{escape(title)}</title>",
        f"    <description>{escape(title)} release feed.</description>",
        "    <language>en</language>",
        "    <item>",
        f"      <title>{escape(title)} {escape(version)}</title>",
        f"      <pubDate>{pub_date}</pubDate>",
        f"      <sparkle:version>{escape(version)}</sparkle:version>",
        f"      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>",
        f"      <sparkle:minimumSystemVersion>{MINIMUM_SYSTEM_VERSION}</sparkle:minimumSystemVersion>",
        f"      <sparkle:hardwareRequirements>{HARDWARE_REQUIREMENTS}</sparkle:hardwareRequirements>",
    ]
    if notes:
        lines.append(f'      <description sparkle:format="plain-text">{escape(notes)}</description>')
    lines.append(
        f"      <enclosure url={quoteattr(url)} sparkle:edSignature={quoteattr(signature)}"
        f' length="{length}" type="application/octet-stream"/>'
    )
    lines += ["    </item>", "  </channel>", "</rss>"]
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True, help="release tag, vMAJOR.MINOR.PATCH")
    parser.add_argument("--version", required=True, help="numeric bundle version")
    parser.add_argument("--app-plist", type=Path, required=True,
                        help="Info.plist of the verified app inside the DMG")
    parser.add_argument("--dmg", type=Path, required=True, help="the signed release DMG")
    parser.add_argument("--signature", required=True, help="EdDSA signature of the DMG")
    parser.add_argument("--release-notes", type=Path, help="plain-text notes to embed")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--pub-date", help="RFC 822 publication date (default: now, UTC)")
    parser.add_argument("--title", default="Utter")
    parser.add_argument("--enclosure-url-base", default=ENCLOSURE_URL_BASE)
    args = parser.parse_args(argv)

    version = parse_version(args.tag, args.version)
    read_app_plist(args.app_plist, version)
    signature_bytes(args.signature)
    if not args.dmg.is_file():
        fail(f"the DMG does not exist: {args.dmg}")
    url = enclosure_url(args.enclosure_url_base, args.tag, args.dmg)
    if args.pub_date:
        pub_date = args.pub_date
    else:
        pub_date = rfc822(datetime.datetime.now(datetime.timezone.utc))

    feed = build(args.tag, version, url, args.signature, args.dmg.stat().st_size,
                 read_notes(args.release_notes), pub_date, args.title)
    args.output.write_text(feed, encoding="utf-8")
    print(f"Wrote {args.output} for {args.tag} ({url})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
