#!/usr/bin/env python3
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("resource_bundles", ROOT / "scripts/check-resource-bundles.py")
CHECKS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKS)
MANIFEST = json.loads((ROOT / "scripts/resource-bundles.json").read_text())


class ResourceBundleTests(unittest.TestCase):
    def populate(self, app):
        for owner in MANIFEST["bundles"]:
            base = app / "Contents/Resources" / owner["bundle"] / "Contents/Resources"
            for relative in owner["files"]:
                path = base / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"fixture")
        for relative in MANIFEST["appFiles"] + MANIFEST["executables"]:
            path = app / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"fixture")
            if relative in MANIFEST["executables"]:
                path.chmod(0o755)
        metal = app / "Contents/Resources/fixture-metal.bundle/default.metallib"
        metal.parent.mkdir(parents=True)
        metal.write_bytes(b"fixture")
        return metal

    def test_every_owned_file_is_required_in_the_assembled_app(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary)
            self.populate(app)
            self.assertEqual(CHECKS.resource_errors(MANIFEST, ROOT, app), [])
            for owner in MANIFEST["bundles"]:
                for relative in owner["files"]:
                    with self.subTest(owner=owner["target"], resource=relative):
                        path = app / "Contents/Resources" / owner["bundle"] / "Contents/Resources" / relative
                        original = path.read_bytes()
                        path.unlink()
                        self.assertTrue(CHECKS.resource_errors(MANIFEST, ROOT, app))
                        path.write_bytes(original)

    def test_helper_and_shader_removal_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary)
            metal = self.populate(app)
            metal.unlink()
            self.assertTrue(CHECKS.resource_errors(MANIFEST, ROOT, app))
            metal.write_bytes(b"fixture")
            (app / "Contents/MacOS/opentype-cli").chmod(0o644)
            self.assertTrue(CHECKS.resource_errors(MANIFEST, ROOT, app))

    def test_resources_cannot_be_substituted_by_the_old_root_bundle(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary)
            self.populate(app)
            owner = next(item for item in MANIFEST["bundles"] if item["target"] == "UtterMacServices")
            source = app / "Contents/Resources" / owner["bundle"] / "Contents/Resources/Sounds/start.caf"
            old = app / "Contents/Resources/OpenType_OpenType.bundle/Contents/Resources/Sounds/start.caf"
            old.parent.mkdir(parents=True)
            source.rename(old)
            self.assertTrue(CHECKS.resource_errors(MANIFEST, ROOT, app))

    def test_duplicate_bundle_and_unknown_schema_are_rejected(self):
        manifest = copy.deepcopy(MANIFEST)
        manifest["bundles"].append(manifest["bundles"][0])
        self.assertTrue(CHECKS.resource_errors(manifest, ROOT))
        manifest["schemaVersion"] = 2
        self.assertTrue(CHECKS.resource_errors(manifest, ROOT))


if __name__ == "__main__":
    unittest.main()
