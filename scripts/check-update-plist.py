#!/usr/bin/env python3
"""Check Sparkle update keys: lint a template, require an app to carry exactly it, or forbid them."""
import argparse
import base64
import binascii
import plistlib
import sys
from pathlib import Path
from urllib.parse import urlparse

REQUIRED_VALUES = {
    "SURequireSignedFeed": True,
    "SUVerifyUpdateBeforeExtraction": True,
    "SUAllowsAutomaticUpdates": False,
    "SUAutomaticallyUpdate": False,
    "SUSendProfileInfo": False,
}
REQUIRED_KEYS = {"SUFeedURL", "SUPublicEDKey"} | set(REQUIRED_VALUES)
FORBIDDEN_KEYS = {"NSAppTransportSecurity", "SUEnableInstallerLauncherService", "SUEnableDownloaderService"}
LOOPBACK_HOSTS = {"127.0.0.1", "localhost", "::1"}
MINIMUM_INTERVAL_SECONDS = 3600


def load(path):
    with open(path, "rb") as handle:
        return plistlib.load(handle)


def update_keys(info):
    return {key: value for key, value in info.items() if key.startswith("SU")}


def feed_errors(feed, allow_loopback):
    parsed = urlparse(feed) if isinstance(feed, str) else None
    if not parsed or not parsed.hostname:
        return ["SUFeedURL is not a URL"]
    if parsed.scheme == "https":
        return []
    if allow_loopback and parsed.scheme == "http" and parsed.hostname in LOOPBACK_HOSTS:
        return []
    return ["SUFeedURL must use https"]


def key_errors(key):
    try:
        raw = base64.b64decode(key, validate=True) if isinstance(key, str) else b""
    except (binascii.Error, ValueError):
        raw = b""
    return [] if len(raw) == 32 else ["SUPublicEDKey must be base64 of a 32-byte Ed25519 public key"]


def lint(template, allow_loopback=False):
    errors = [f"missing {key}" for key in sorted(REQUIRED_KEYS - set(template))]
    errors += [f"{key} must be {want}" for key, want in REQUIRED_VALUES.items()
               if key in template and template[key] is not want]
    errors += [f"forbidden key {key}" for key in sorted(FORBIDDEN_KEYS & set(template))]
    if "SUFeedURL" in template:
        errors += feed_errors(template["SUFeedURL"], allow_loopback)
    if "SUPublicEDKey" in template:
        errors += key_errors(template["SUPublicEDKey"])
    interval = template.get("SUScheduledCheckInterval")
    if interval is not None and (isinstance(interval, bool) or not isinstance(interval, int)
                                 or interval < MINIMUM_INTERVAL_SECONDS):
        errors.append(f"SUScheduledCheckInterval must be an integer of at least {MINIMUM_INTERVAL_SECONDS}")
    return errors


def app_matches_template(info, template):
    errors = [f"app carries forbidden key {key}" for key in sorted(FORBIDDEN_KEYS & set(info))]
    carried = update_keys(info)
    for key in sorted(set(template) | set(carried)):
        if key not in carried:
            errors.append(f"app is missing {key}")
        elif key not in template:
            errors.append(f"app carries unexpected {key}")
        elif carried[key] != template[key] or type(carried[key]) is not type(template[key]):
            errors.append(f"app {key} differs from the committed template")
    return errors


def merge(template, info_path):
    info = load(info_path)
    for key in [key for key in info if key.startswith("SU") or key in FORBIDDEN_KEYS]:
        del info[key]
    info.update(template)
    with open(info_path, "wb") as handle:
        plistlib.dump(info, handle)


def forbid_errors(info):
    return [f"inert build must not carry {key}" for key in sorted(update_keys(info))]


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path)
    parser.add_argument("--update-info", type=Path)
    parser.add_argument("--forbid", action="store_true")
    parser.add_argument("--merge-into", type=Path, help="write the linted template into this Info.plist")
    parser.add_argument("--allow-loopback-feed", action="store_true")
    args = parser.parse_args(argv)
    if args.merge_into and (not args.update_info or args.app or args.forbid):
        parser.error("--merge-into takes only --update-info")
    if not args.merge_into and (args.forbid == bool(args.update_info) or (args.forbid and not args.app)):
        parser.error("use --app with exactly one of --forbid or --update-info, or --update-info alone to lint")
    errors = []
    if args.update_info:
        template = load(args.update_info)
        errors += lint(template, args.allow_loopback_feed)
        if args.merge_into and not errors:
            merge(template, args.merge_into)
        if args.app:
            errors += app_matches_template(load(args.app / "Contents/Info.plist"), template)
    else:
        errors += forbid_errors(load(args.app / "Contents/Info.plist"))
    for error in errors:
        print(error, file=sys.stderr)
    if not errors:
        print("Update keys merged." if args.merge_into else "Update keys passed.")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
