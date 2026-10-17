#!/usr/bin/env python3
"""Prove the appcast generator emits exactly the feed the release pipeline signs."""
import base64
import importlib.util
import plistlib
import tempfile
import unittest
import xml.etree.ElementTree as ElementTree
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("generate_appcast", ROOT / "scripts/generate-appcast.py")
appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appcast)

TAG = "v0.0.56"
VERSION = "0.0.56"
SIGNATURE = base64.b64encode(bytes(range(64))).decode()
PUB_DATE = "Sat, 17 Oct 2026 12:00:00 +0000"
DMG_SIZE = 1234

EXPECTED = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Utter</title>
    <description>Utter release feed.</description>
    <language>en</language>
    <item>
      <title>Utter 0.0.56</title>
      <pubDate>{PUB_DATE}</pubDate>
      <sparkle:version>0.0.56</sparkle:version>
      <sparkle:shortVersionString>0.0.56</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
      <description>Fix A &amp; B
Add &lt;C&gt; "D"</description>
      <enclosure url="https://github.com/IchenDEV/utter/releases/download/v0.0.56/Utter-0.0.56.dmg" sparkle:edSignature="{SIGNATURE}" length="{DMG_SIZE}" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
"""


class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "Utter.app"
        (self.app / "Contents").mkdir(parents=True)
        self.write_plist(VERSION, VERSION)
        self.dmg = self.root / f"Utter-{VERSION}.dmg"
        self.dmg.write_bytes(b"x" * DMG_SIZE)
        self.notes = self.root / "notes.txt"
        self.notes.write_text('Fix A & B\nAdd <C> "D"\n', encoding="utf-8")
        self.output = self.root / "appcast.xml"

    def write_plist(self, short, build):
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.opentype.voiceinput",
            "CFBundleShortVersionString": short,
            "CFBundleVersion": build,
        }))

    def generate(self, **overrides):
        arguments = {
            "--tag": TAG,
            "--version": VERSION,
            "--app-plist": self.app / "Contents/Info.plist",
            "--dmg": self.dmg,
            "--signature": SIGNATURE,
            "--release-notes": self.notes,
            "--output": self.output,
            "--pub-date": PUB_DATE,
        }
        arguments.update(overrides)
        argv = []
        for key, value in arguments.items():
            if value is None:
                continue
            argv += [key, str(value)]
        return appcast.main(argv)

    def test_golden_feed(self):
        self.assertEqual(self.generate(), 0)
        self.assertEqual(self.output.read_text(encoding="utf-8"), EXPECTED)
        root = ElementTree.fromstring(self.output.read_text(encoding="utf-8"))
        namespace = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
        enclosure = root.find(".//enclosure")
        self.assertEqual(enclosure.get("length"), str(DMG_SIZE))
        self.assertEqual(
            root.find(".//sparkle:version", namespace).text, VERSION)

    def test_dmg_comes_from_the_verified_app_not_a_second_source(self):
        # The version in the feed is the app plist's, cross-checked against the tag.
        self.write_plist("0.0.57", VERSION)
        with self.assertRaises(SystemExit):
            self.generate()

    def test_tag_must_be_semver_and_match_the_version(self):
        for tag, version in (("0.0.56", VERSION), ("v00.0.56", VERSION),
                             ("v0.0.56", "0.0.57"), ("v0.0.56-rc1", VERSION)):
            with self.subTest(tag=tag, version=version):
                with self.assertRaises(SystemExit):
                    self.generate(**{"--tag": tag, "--version": version})

    def test_dmg_name_is_bound_to_the_version(self):
        other = self.root / "Utter-0.0.99.dmg"
        other.write_bytes(b"x")
        with self.assertRaises(SystemExit):
            self.generate(**{"--dmg": other})

    def test_signature_must_be_a_sixty_four_byte_base64_value(self):
        for bad in ("", "not base64!", base64.b64encode(b"short").decode(),
                    base64.b64encode(bytes(65)).decode()):
            with self.subTest(bad=bad):
                with self.assertRaises(SystemExit):
                    self.generate(**{"--signature": bad})

    def test_missing_inputs_fail_closed(self):
        with self.assertRaises(SystemExit):
            self.generate(**{"--dmg": self.root / "absent.dmg"})
        with self.assertRaises(SystemExit):
            self.generate(**{"--app-plist": self.root / "absent.plist"})

    def test_notes_are_optional_plain_text(self):
        self.assertEqual(self.generate(**{"--release-notes": None}), 0)
        self.assertIsNone(ElementTree.fromstring(
            self.output.read_text(encoding="utf-8")).find(".//item/description"))
        self.notes.write_text("\n", encoding="utf-8")
        self.assertEqual(self.generate(), 0)
        self.assertIsNone(ElementTree.fromstring(
            self.output.read_text(encoding="utf-8")).find(".//item/description"))

    def test_notes_keep_non_ascii_text(self):
        self.notes.write_text("修复听写\nNouvelle version\n", encoding="utf-8")
        self.assertEqual(self.generate(), 0)
        feed = self.output.read_text(encoding="utf-8")
        self.assertIn("修复听写\nNouvelle version", feed)

    def test_enclosure_base_can_be_redirected_for_a_rehearsal(self):
        self.assertEqual(self.generate(**{"--enclosure-url-base": "http://127.0.0.1:8000"}), 0)
        self.assertIn("url=\"http://127.0.0.1:8000/v0.0.56/Utter-0.0.56.dmg\"",
                      self.output.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
