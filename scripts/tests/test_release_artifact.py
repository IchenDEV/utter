#!/usr/bin/env python3
"""Exercise the actual release verifier with controlled native-tool boundaries."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

import test_resource_bundles as resource_fixtures
import test_update_plist as plist_fixtures

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
sparkle = 'Sparkle.framework' in (args[-1] if args else '')
if name == 'lipo':
    print('x86_64 arm64' if case == 'sparkle-fat' and sparkle else 'arm64')
elif name == 'file':
    path = Path(args[-1])
    print('Mach-O 64-bit executable arm64' if path.read_text(errors='ignore').startswith('MACHO') else 'ASCII text')
elif name == 'otool':
    if args[0] == '-l':
        if case != 'no-rpath':
            print('Load command 18\n          cmd LC_RPATH\n      cmdsize 48\n'
                  '         path @executable_path/../Frameworks (offset 12)')
    elif args[-1].endswith('opentype-cli') == (case == 'helper-links-sparkle') and case != 'unlinked':
        print('\t@rpath/Sparkle.framework/Versions/B/Sparkle (compatibility version 1.6.0)')
elif name == 'codesign':
    dmg = args[-1].endswith('.dmg')
    if '--verify' in args:
        sys.exit(1 if (dmg and case == 'unsigned') or (sparkle and case == 'sparkle-unsigned') else 0)
    if '--entitlements' in args:
        if sparkle and case == 'sparkle-entitled':
            print('<?xml version="1.0"?><plist><dict/></plist>')
        sys.exit(0)
    extract = next((a for a in args if a.startswith('--extract-certificates=')), None)
    adhoc = (case == 'app-adhoc' and not dmg) or (case == 'sparkle-adhoc' and sparkle)
    if extract:
        if (dmg and case == 'extract-failure') or adhoc:
            sys.exit(1)
        marker = 'B' if (dmg and case == 'mismatch') or (sparkle and case == 'sparkle-cert-mismatch') else 'A'
        if dmg and case in ('fingerprint-failure', 'empty-fingerprint'):
            marker = case
        Path(extract.split('=', 1)[1] + '0').write_text(marker)
    elif dmg and case == 'adhoc':
        print('Signature=adhoc\nTeamIdentifier=not set')
    elif adhoc:
        print('CodeDirectory flags=0x10000(runtime)\nSignature=adhoc\nTeamIdentifier=not set')
    else:
        print('CodeDirectory flags=0x0(none)' if sparkle and case == 'sparkle-unhardened'
              else 'CodeDirectory flags=0x10000(runtime)')
        print('Authority=Developer ID Application: Fixture (ABC1234567)')
        print('TeamIdentifier=ABC1234567')
        if not ((dmg and case == 'untimestamped') or (sparkle and case == 'sparkle-untimestamped')):
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
        shutil.copytree(os.environ['FIXTURE_APP'], mount / 'Utter.app', symlinks=True)
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
        self.populate_sparkle()
        self.dmg = self.root / "Utter.dmg"
        self.dmg.write_bytes(b"controlled disk image fixture")
        self.trace = self.root / "tools.log"
        tools = self.root / "bin"
        tools.mkdir()
        stub = tools / "native-tool"
        stub.write_text(TOOLS)
        stub.chmod(0o755)
        for name in ("codesign", "openssl", "lipo", "hdiutil", "xcrun", "spctl", "file", "otool"):
            (tools / name).symlink_to(stub)
        self.env = {
            "PATH": str(tools) + ":/usr/bin:/bin:/usr/sbin:/sbin",
            "FIXTURE_APP": str(self.app), "TOOL_TRACE": str(self.trace),
            "TMPDIR": str(self.root), "LANG": "C.UTF-8",
        }

    def populate_sparkle(self):
        framework = self.app / "Contents/Frameworks/Sparkle.framework"
        version = framework / "Versions/B"
        for relative in ("Sparkle", "Autoupdate", "Updater.app/Contents/MacOS/Updater"):
            (version / relative).parent.mkdir(parents=True, exist_ok=True)
            (version / relative).write_text("MACHO")
        (version / "Resources").mkdir()
        (version / "Resources/Info.plist").write_text("text")
        (framework / "Versions/Current").symlink_to("B")
        (framework / "Sparkle").symlink_to("Versions/Current/Sparkle")

    def arm_updater(self, **overrides):
        template = plist_fixtures.template(**overrides)
        self.update_info = self.root / "UpdateInfo.plist"
        self.update_info.write_bytes(plistlib.dumps(template))
        path = self.app / "Contents/Info.plist"
        info = plistlib.loads(path.read_bytes())
        info.update(template)
        path.write_bytes(plistlib.dumps(info))

    def verify(self, case, expected=True, notarization=False, developer_id=True, updater=False):
        command = ["bash", str(ROOT / "scripts/verify-release-artifact.sh"),
                   "--app", str(self.app), "--dmg", str(self.dmg),
                   "--version", "0.0.54"]
        if updater:
            command += ["--require-updater", "--update-info", str(self.update_info)]
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

    def test_framework_layout_is_checked_on_every_build(self):
        for case, message in (
            ("sparkle-fat", "Sparkle code must be arm64-only"),
            ("no-rpath", "Utter executable is missing the Frameworks rpath"),
            ("helper-links-sparkle", "CLI helper must not link Sparkle"),
        ):
            with self.subTest(case=case):
                result = self.verify(case, developer_id=False, expected=False)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(message, result.stderr)

    def test_missing_framework_or_bundled_xpc_services_fail(self):
        xpc = self.app / "Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
        xpc.mkdir(parents=True)
        result = self.verify("valid", developer_id=False, expected=False)
        self.assertIn("Sparkle XPC services must not be bundled", result.stderr)
        self.assertNotEqual(result.returncode, 0)
        shutil.rmtree(self.app / "Contents/Frameworks")
        result = self.verify("valid", developer_id=False, expected=False)
        self.assertIn("missing Sparkle.framework", result.stderr)

    def test_build_that_did_not_ask_for_updates_must_carry_no_update_keys(self):
        self.arm_updater()
        result = self.verify("valid", developer_id=False, expected=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must carry no update keys", result.stderr)

    def test_armed_updater_build_passes_every_updater_check(self):
        self.arm_updater()
        result = self.verify("valid", updater=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        trace = self.trace.read_text()
        for component in ("Autoupdate", "Updater.app"):
            self.assertIn(f"codesign --verify --strict {self.app}/Contents/Frameworks/Sparkle.framework/Versions/B/{component}", trace)

    def test_updater_build_needs_the_template_and_matching_keys(self):
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/verify-release-artifact.sh"), "--app", str(self.app), "--version", "0.0.54",
             "--require-updater"], env={**self.env, "SIGNATURE_CASE": "valid"}, capture_output=True, text=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--require-updater requires --update-info", result.stderr)
        self.arm_updater()
        info = plistlib.loads((self.app / "Contents/Info.plist").read_bytes())
        info["SUFeedURL"] = "https://example.com/other.xml"
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        result = self.verify("valid", updater=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("update keys do not match the committed template", result.stderr)

    def test_sparkle_code_must_be_signed_by_the_app_without_entitlements_in_every_build(self):
        cases = (
            ("sparkle-unsigned", "invalid signature"),
            ("sparkle-unhardened", "Sparkle component lacks the hardened runtime"),
            ("sparkle-cert-mismatch", "Sparkle component is not signed by the app certificate"),
            ("sparkle-adhoc", "Sparkle component is not signed by the app certificate"),
            ("sparkle-untimestamped", "Sparkle component has no secure timestamp"),
            ("sparkle-entitled", "Sparkle component must carry no entitlements"),
        )
        for case, message in cases:
            with self.subTest(case=case, armed=False):
                result = self.verify(case)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(message, result.stderr)
        self.arm_updater()
        result = self.verify("sparkle-entitled", updater=True)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Sparkle component must carry no entitlements", result.stderr)

    def test_armed_build_must_link_sparkle(self):
        self.arm_updater()
        result = self.verify("unlinked", updater=True)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Utter executable does not link Sparkle", result.stderr)

    def test_ad_hoc_app_needs_ad_hoc_sparkle_and_can_never_be_armed(self):
        result = self.verify("app-adhoc", developer_id=False, expected=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.arm_updater()
        result = self.verify("app-adhoc", developer_id=False, expected=False, updater=True)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("an updater build must be signed with an identity", result.stderr)

    def test_generic_packaging_keeps_its_unsigned_container_contract(self):
        result = self.verify("unsigned", expected=False, developer_id=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("hdiutil attach", self.trace.read_text())


if __name__ == "__main__":
    unittest.main()
