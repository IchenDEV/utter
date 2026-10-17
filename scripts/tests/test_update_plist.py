#!/usr/bin/env python3
"""Prove the update-key gate separates inert builds from updater builds."""
import base64
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("check_update_plist", ROOT / "scripts/check-update-plist.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

KEY = base64.b64encode(bytes(range(32))).decode()


def template(**overrides):
    values = {
        "SUFeedURL": "https://github.com/IchenDEV/utter/releases/latest/download/appcast.xml",
        "SUPublicEDKey": KEY,
        "SURequireSignedFeed": True,
        "SUVerifyUpdateBeforeExtraction": True,
        "SUEnableAutomaticChecks": True,
        "SUAllowsAutomaticUpdates": False,
        "SUAutomaticallyUpdate": False,
        "SUScheduledCheckInterval": 86400,
        "SUSendProfileInfo": False,
    }
    values.update(overrides)
    return {key: value for key, value in values.items() if value is not None}


class UpdatePlistTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def write_app(self, info):
        app = self.root / "Utter.app"
        (app / "Contents").mkdir(parents=True, exist_ok=True)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        return app

    def write_template(self, values):
        path = self.root / "UpdateInfo.plist"
        path.write_bytes(plistlib.dumps(values))
        return path

    def run_gate(self, *args):
        return gate.main([str(arg) for arg in args])

    def test_complete_template_lints_clean(self):
        self.assertEqual(gate.lint(template()), [])

    def test_each_required_key_is_enforced(self):
        for key in gate.REQUIRED_KEYS:
            with self.subTest(key=key):
                self.assertIn(f"missing {key}", gate.lint(template(**{key: None})))

    def test_security_switches_cannot_be_relaxed(self):
        for key, relaxed in (("SURequireSignedFeed", False), ("SUVerifyUpdateBeforeExtraction", False),
                             ("SUAllowsAutomaticUpdates", True), ("SUAutomaticallyUpdate", True),
                             ("SUSendProfileInfo", True)):
            with self.subTest(key=key):
                self.assertTrue(gate.lint(template(**{key: relaxed})))

    def test_atsexception_and_helper_services_are_forbidden(self):
        for key in gate.FORBIDDEN_KEYS:
            with self.subTest(key=key):
                self.assertTrue(gate.lint(template(**{key: True})))

    def test_feed_must_be_https_except_a_loopback_rehearsal(self):
        self.assertTrue(gate.lint(template(SUFeedURL="http://example.com/appcast.xml")))
        self.assertTrue(gate.lint(template(SUFeedURL="not a url")))
        loopback = template(SUFeedURL="http://127.0.0.1:8080/appcast.xml")
        self.assertTrue(gate.lint(loopback))
        self.assertEqual(gate.lint(loopback, allow_loopback=True), [])
        self.assertTrue(gate.lint(template(SUFeedURL="http://127.0.0.1.example.com/a.xml"), allow_loopback=True))

    def test_public_key_must_be_a_thirty_two_byte_base64_value(self):
        for bad in ("", "***", base64.b64encode(b"short").decode(), base64.b64encode(bytes(33)).decode(), 7):
            with self.subTest(bad=bad):
                self.assertTrue(gate.lint(template(SUPublicEDKey=bad)))

    def test_check_interval_cannot_become_a_tight_loop(self):
        self.assertTrue(gate.lint(template(SUScheduledCheckInterval=60)))
        self.assertTrue(gate.lint(template(SUScheduledCheckInterval="86400")))
        self.assertEqual(gate.lint(template(SUScheduledCheckInterval=None)), [])

    def test_app_must_carry_exactly_the_template(self):
        info = {"CFBundleIdentifier": "x", **template()}
        self.assertEqual(self.run_gate("--app", self.write_app(info), "--update-info", self.write_template(template())), 0)
        for broken in (
            {**info, "SUFeedURL": "https://example.com/other.xml"},
            {**info, "SUScheduledCheckInterval": 3600},
            {**info, "SUSkipVersionsAutomatically": True},
            {**info, "NSAppTransportSecurity": {"NSAllowsArbitraryLoads": True}},
            {key: value for key, value in info.items() if key != "SUPublicEDKey"},
        ):
            with self.subTest(broken=sorted(broken)):
                app = self.write_app(broken)
                self.assertEqual(self.run_gate("--app", app, "--update-info", self.write_template(template())), 1)

    def test_type_confusion_between_template_and_app_is_a_difference(self):
        info = {"CFBundleIdentifier": "x", **template(SUScheduledCheckInterval=1)}
        self.assertTrue(gate.app_matches_template(info, {**template(), "SUScheduledCheckInterval": True}))

    def test_inert_build_must_carry_no_update_key_at_all(self):
        self.assertEqual(self.run_gate("--app", self.write_app({"CFBundleIdentifier": "x"}), "--forbid"), 0)
        self.assertEqual(self.run_gate("--app", self.write_app({"CFBundleIdentifier": "x", "SUFeedURL": "https://a/b"}), "--forbid"), 1)
        self.assertEqual(self.run_gate("--app", self.write_app({"CFBundleIdentifier": "x", "SUEnableAutomaticChecks": False}), "--forbid"), 1)

    def test_merge_replaces_stale_update_keys_and_keeps_everything_else(self):
        info_path = self.write_app({"CFBundleIdentifier": "x", "SUFeedURL": "https://stale/a.xml",
                                    "SUSkipVersionsAutomatically": True,
                                    "NSAppTransportSecurity": {"NSAllowsArbitraryLoads": True}}) / "Contents/Info.plist"
        self.assertEqual(self.run_gate("--update-info", self.write_template(template()), "--merge-into", info_path), 0)
        merged = plistlib.loads(info_path.read_bytes())
        self.assertEqual({k: v for k, v in merged.items() if k.startswith("SU")}, template())
        self.assertEqual(merged["CFBundleIdentifier"], "x")
        self.assertNotIn("NSAppTransportSecurity", merged)

    def test_merge_refuses_an_invalid_template_and_leaves_the_plist_alone(self):
        app = self.write_app({"CFBundleIdentifier": "x"})
        info_path = app / "Contents/Info.plist"
        before = info_path.read_bytes()
        bad = self.write_template(template(SUFeedURL="http://example.com/a.xml"))
        self.assertEqual(self.run_gate("--update-info", bad, "--merge-into", info_path), 1)
        self.assertEqual(info_path.read_bytes(), before)

    def test_loopback_flag_reaches_the_lint(self):
        loopback = self.write_template(template(SUFeedURL="http://localhost:9/appcast.xml"))
        self.assertEqual(self.run_gate("--update-info", loopback), 1)
        self.assertEqual(self.run_gate("--update-info", loopback, "--allow-loopback-feed"), 0)


if __name__ == "__main__":
    unittest.main()
