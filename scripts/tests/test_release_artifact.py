#!/usr/bin/env python3
"""Exercise the actual release verifier with controlled native-tool boundaries."""
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

import test_resource_bundles as resource_fixtures

ROOT = Path(__file__).resolve().parents[2]
CERT = "A" * 64
TOOLS = r'''#!/usr/bin/env python3
import os
from pathlib import Path
import shutil
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
case = os.environ['SIGNATURE_CASE']
with open(os.environ['TOOL_TRACE'], 'a') as trace:
    trace.write(name + ' ' + ' '.join(args) + '\n')
if name == 'lipo':
    print('arm64')
elif name == 'codesign':
    dmg = args[-1].endswith('.dmg')
    if '--verify' in args:
        sys.exit(1 if dmg and case == 'unsigned' else 0)
    extract = next((a for a in args if a.startswith('--extract-certificates=')), None)
    if extract:
        if dmg and case == 'extract-failure':
            sys.exit(1)
        marker = 'B' if dmg and case == 'mismatch' else 'A'
        if dmg and case in ('fingerprint-failure', 'empty-fingerprint'):
            marker = case
        Path(extract.split('=', 1)[1] + '0').write_text(marker)
    elif dmg and case == 'adhoc':
        print('Signature=adhoc\nTeamIdentifier=not set')
    else:
        print('CodeDirectory flags=0x10000(runtime)')
        print('Authority=Developer ID Application: Fixture (ABC1234567)')
        print('TeamIdentifier=ABC1234567')
        if not (dmg and case == 'untimestamped'):
            print('Timestamp=Oct 16, 2026 at 12:00:00 AM')
elif name == 'openssl':
    marker = Path(args[args.index('-in') + 1]).read_text()
    if marker == 'fingerprint-failure':
        sys.exit(1)
    if marker == 'empty-fingerprint':
        sys.exit(0)
    print('sha256 Fingerprint=' + marker * 64)
elif name == 'hdiutil':
    if args[0] == 'attach':
        mount = Path(args[args.index('-mountpoint') + 1])
        shutil.copytree(os.environ['FIXTURE_APP'], mount / 'Utter.app')
    elif args[0] == 'detach':
        shutil.rmtree(Path(args[1]) / 'Utter.app')
'''


class ReleaseArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "Utter.app"
        resource_fixtures.ResourceBundleTests().populate(self.app)
        plist = {
            "CFBundleIdentifier": "com.opentype.voiceinput",
            "CFBundleShortVersionString": "0.0.54",
            "CFBundleVersion": "0.0.54",
        }
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps(plist))
        self.dmg = self.root / "Utter.dmg"
        self.dmg.write_bytes(b"controlled disk image fixture")
        self.trace = self.root / "tools.log"
        tools = self.root / "bin"
        tools.mkdir()
        stub = tools / "native-tool"
        stub.write_text(TOOLS)
        stub.chmod(0o755)
        for name in ("codesign", "openssl", "lipo", "hdiutil", "xcrun", "spctl"):
            (tools / name).symlink_to(stub)
        self.env = {
            "PATH": str(tools) + ":/usr/bin:/bin:/usr/sbin:/sbin",
            "FIXTURE_APP": str(self.app), "TOOL_TRACE": str(self.trace),
            "TMPDIR": str(self.root), "LANG": "C.UTF-8",
        }

    def verify(self, case, expected=True, notarization=False, developer_id=True):
        command = ["bash", str(ROOT / "scripts/verify-release-artifact.sh"),
                   "--app", str(self.app), "--dmg", str(self.dmg),
                   "--version", "0.0.54"]
        if developer_id:
            command += ["--require-developer-id"]
        if expected:
            command += ["--expected-cert-sha256", CERT]
        if notarization:
            command += ["--require-notarization"]
        self.trace.write_text("")
        return subprocess.run(command, env={**self.env, "SIGNATURE_CASE": case},
                              capture_output=True, text=True, timeout=30)

    def test_signed_matching_timestamped_image_reaches_distribution_checks(self):
        result = self.verify("valid", notarization=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        trace = self.trace.read_text()
        self.assertIn("hdiutil attach", trace)
        self.assertIn("xcrun stapler validate", trace)
        self.assertIn("spctl --assess --type open", trace)
        self.assertIn("spctl --assess --type execute", trace)

    def test_invalid_container_stops_before_mounting(self):
        for case, message in (
            ("unsigned", "DMG signature is invalid"),
            ("adhoc", "DMG is not signed with a Developer ID Application identity"),
            ("untimestamped", "DMG signature has no secure timestamp"),
            ("mismatch", "DMG signing certificate does not match the app certificate"),
            ("extract-failure", "could not extract the DMG signing certificate"),
            ("fingerprint-failure", "could not extract the DMG signing certificate"),
            ("empty-fingerprint", "could not extract the DMG signing certificate"),
        ):
            with self.subTest(case=case):
                result = self.verify(case)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(message, result.stderr)
                self.assertNotIn("hdiutil attach", self.trace.read_text())
                self.assertNotIn("xcrun", self.trace.read_text())

    def test_certificate_match_is_required_without_expected_fingerprint(self):
        result = self.verify("mismatch", expected=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("DMG signing certificate does not match the app certificate", result.stderr)
        self.assertNotIn("hdiutil attach", self.trace.read_text())

    def test_generic_packaging_keeps_its_unsigned_container_contract(self):
        result = self.verify("unsigned", expected=False, developer_id=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("hdiutil attach", self.trace.read_text())


if __name__ == "__main__":
    unittest.main()
