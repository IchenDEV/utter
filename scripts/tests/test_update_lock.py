#!/usr/bin/env python3
"""Keep the committed update configuration locked to the pinned Sparkle release."""
import importlib.util
import plistlib
import re
import unittest
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("check_update_plist", ROOT / "scripts/check-update-plist.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

LOCK_ENTRY = re.compile(r"^([0-9a-f]{64})  (Sparkle-(\d+\.\d+\.\d+)\.tar\.xz)$")
SPARKLE_PIN = re.compile(r'url: "https://github\.com/sparkle-project/Sparkle", exact: "(\d+\.\d+\.\d+)"')


def pinned_version():
    match = SPARKLE_PIN.search((ROOT / "Package.swift").read_text(encoding="utf-8"))
    return match.group(1) if match else None


class UpdateLockTests(unittest.TestCase):
    def setUp(self):
        self.lock = (ROOT / "scripts/sparkle-tools.sha256").read_text(encoding="utf-8")
        self.template = plistlib.loads((ROOT / "Resources/UpdateInfo.plist").read_bytes())

    def test_tools_lock_is_one_pinned_archive(self):
        lines = [line for line in self.lock.splitlines() if line.strip()]
        self.assertEqual(len(lines), 1, "the tools lock must pin exactly one archive")
        match = LOCK_ENTRY.match(lines[0])
        self.assertIsNotNone(match, "the tools lock must be '<sha256>  Sparkle-X.Y.Z.tar.xz'")
        self.assertEqual(match.group(3), pinned_version(),
                         "the pinned tools version must match the Package.swift pin")

    def test_committed_template_passes_the_gate(self):
        self.assertEqual(gate.lint(self.template), [])

    def test_public_key_is_not_a_placeholder(self):
        self.assertNotIn("example", self.template["SUPublicEDKey"].lower())
        self.assertEqual(len(self.template["SUPublicEDKey"]), 44)

    def test_feed_is_this_repositorys_latest_release(self):
        feed = urlparse(self.template["SUFeedURL"])
        self.assertEqual(feed.scheme, "https")
        self.assertEqual(feed.netloc, "github.com")
        self.assertEqual(feed.path, "/IchenDEV/utter/releases/latest/download/appcast.xml")

    def test_updates_are_not_automatic(self):
        for key in ("SUAllowsAutomaticUpdates", "SUAutomaticallyUpdate", "SUSendProfileInfo"):
            with self.subTest(key=key):
                self.assertIs(self.template[key], False)


if __name__ == "__main__":
    unittest.main()
