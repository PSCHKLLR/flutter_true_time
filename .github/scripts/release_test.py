import io
import json
from pathlib import Path
import tempfile
import unittest
from urllib.error import HTTPError

from release import metadata, verify


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.write("2.0.4")

    def write(self, version, extra=""):
        (self.root / "pubspec.yaml").write_text(
            f"name: flutter_true_time\nversion: {version}\n{extra}", encoding="utf-8"
        )
        (self.root / "CHANGELOG.md").write_text(
            f"# Changes\n\n## {version}\n\n- Fix an issue.\n\n## 1.0.0\n\n- Older change.\n",
            encoding="utf-8",
        )

    def test_stable_tag_and_notes(self):
        version, prerelease, notes = metadata(self.root, "refs/tags/v2.0.4")
        self.assertEqual(version, "2.0.4")
        self.assertFalse(prerelease)
        self.assertIn("Fix an issue.", notes)
        self.assertNotIn("Older change", notes)

    def test_prerelease_and_build_metadata(self):
        self.write("2.1.0-dev.1+build.2")
        self.assertTrue(metadata(self.root, "refs/tags/v2.1.0-dev.1+build.2")[1])

    def test_invalid_version_or_tag_is_rejected(self):
        for version in ["02.0.4", "2.0", "2.0.4-dev.01", "2.0.4\nversion: 3.0.0"]:
            self.write(version)
            with self.assertRaises(ValueError):
                metadata(self.root, "refs/heads/main")
        self.write("2.0.4")
        with self.assertRaises(ValueError):
            metadata(self.root, "refs/tags/v2.0.5")

    def test_publication_guard_and_custom_registry_are_rejected(self):
        for target in ["none", "https://other.example"]:
            self.write("2.0.4", f"publish_to: {target}\n")
            with self.assertRaises(ValueError):
                metadata(self.root, "refs/tags/v2.0.4")

    def test_missing_or_empty_notes_are_rejected(self):
        for text in ["## Unreleased\n- Change", "## 2.0.4\n\n"]:
            (self.root / "CHANGELOG.md").write_text(text, encoding="utf-8")
            with self.assertRaises(ValueError):
                metadata(self.root, "refs/tags/v2.0.4")

    def test_registry_retries_then_checks_identity(self):
        calls, pauses = [], []

        def fetch(url, timeout):
            calls.append((url, timeout))
            if len(calls) == 1:
                raise HTTPError(url, 404, "Not visible yet", None, None)
            return io.StringIO(json.dumps({"version": "2.0.4", "pubspec": {"name": "flutter_true_time"}}))

        self.assertEqual(verify("2.0.4", fetch=fetch, pause=pauses.append)["version"], "2.0.4")
        self.assertEqual(pauses, [10])

    def test_registry_retry_budget_is_bounded(self):
        def fetch(url, timeout):
            raise HTTPError(url, 429, "Rate limited", None, None)

        pauses = []
        with self.assertRaises(RuntimeError):
            verify("2.0.4", attempts=3, fetch=fetch, pause=pauses.append)
        self.assertEqual(pauses, [10, 10])

    def test_wrong_registry_version_is_not_success(self):
        def fetch(url, timeout):
            return io.StringIO(json.dumps({"version": "2.0.3", "pubspec": {"name": "flutter_true_time"}}))

        with self.assertRaises(ValueError):
            verify("2.0.4", fetch=fetch, pause=lambda _: None)


if __name__ == "__main__":
    unittest.main()
