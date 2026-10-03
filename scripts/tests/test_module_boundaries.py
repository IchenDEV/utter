import importlib.util
from pathlib import Path
import tempfile
import unittest

script = Path(__file__).resolve().parent.parent / "check-module-boundaries.py"
spec = importlib.util.spec_from_file_location("module_boundaries", script)
boundaries = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boundaries)


class ModuleBoundaryTests(unittest.TestCase):
    def check(self, source, targets):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Fixture.swift").write_text(source)
            description = {"targets": [{"name": name, "path": ".", "sources": ["Fixture.swift"]} for name in targets]}
            return boundaries.violations(root, description)

    def test_runtime_accepts_foundation(self):
        self.assertEqual(self.check("import Foundation\n", ["UtterRuntime"]), [])

    def test_runtime_rejects_feature_import(self):
        self.assertTrue(self.check("import UtterMLX\n", ["UtterRuntime"]))

    def test_feature_rejects_sibling_import(self):
        self.assertTrue(self.check("@preconcurrency import UtterWhisper\n", ["UtterSession"]))

    def test_builtin_catalog_accepts_implementations(self):
        self.assertEqual(self.check("import UtterMLX\n", ["UtterBuiltins"]), [])

    def test_overlapping_ownership_is_rejected(self):
        self.assertTrue(self.check("import Foundation\n", ["UtterContracts", "UtterRuntime"]))


if __name__ == "__main__":
    unittest.main()
