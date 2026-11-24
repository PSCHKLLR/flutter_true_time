import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import subprocess
from urllib.error import HTTPError

from release import metadata, verify


class RetryClock:
    def __init__(self):
        self.elapsed = 0
        self.pauses = []

    def now(self):
        return self.elapsed

    def pause(self, seconds):
        self.pauses.append(seconds)
        self.elapsed += seconds


class PropagationTests(unittest.TestCase):
    version = '2.0.4'

    def setUp(self):
        self.clock = RetryClock()
        self.logs = []
        self.identity = {'version': self.version, 'pubspec': {'name': 'flutter_true_time'}}
        self.index = {'name': 'flutter_true_time', 'versions': [{'version': self.version}]}

    def verify(self, fetch, **options):
        return verify(self.version, fetch=fetch, pause=self.clock.pause,
                      now=self.clock.now, log=self.logs.append, **options)

    def response(self, value):
        return io.StringIO(json.dumps(value))

    def test_identity_visible_before_index_is_not_success(self):
        calls = []

        def fetch(url, timeout):
            calls.append(url)
            if '/versions/' in url:
                return self.response(self.identity)
            return self.response(self.index if len(calls) >= 4 else
                                 {'name': 'flutter_true_time', 'versions': []})

        self.assertEqual(self.verify(fetch), self.identity)
        self.assertEqual(len(calls), 4)
        self.assertEqual(self.clock.pauses, [10])
        self.assertTrue(any('attempt 2' in line for line in self.logs))

    def test_missing_index_version_exhausts_attempt_budget(self):
        def fetch(url, timeout):
            return self.response(self.identity if '/versions/' in url else
                                 {'name': 'flutter_true_time', 'versions': []})

        with self.assertRaises(RuntimeError):
            self.verify(fetch, attempts=3)
        self.assertEqual(self.clock.pauses, [10, 10])

    def test_registry_uses_one_deadline_for_both_requests_and_pauses(self):
        timeouts = []

        def fetch(url, timeout):
            timeouts.append(timeout)
            self.clock.elapsed += 3
            return self.response(self.identity if '/versions/' in url else
                                 {'name': 'flutter_true_time', 'versions': []})

        with self.assertRaises(RuntimeError):
            self.verify(fetch, budget=8)
        self.assertEqual(timeouts, [8, 5])
        self.assertEqual(self.clock.pauses, [2])
        self.assertEqual(self.clock.elapsed, 8)

    def test_permanent_registry_errors_and_malformed_index_do_not_retry(self):
        for malformed in [{}, {'name': 'other', 'versions': []},
                          {'name': 'flutter_true_time', 'versions': 'wrong'},
                          {'name': 'flutter_true_time', 'versions': [None]}]:
            calls = []

            def fetch(url, timeout):
                calls.append(url)
                return self.response(self.identity if '/versions/' in url else malformed)

            with self.assertRaises(ValueError):
                self.verify(fetch)
            self.assertEqual(len(calls), 2)
        for code in [400, 401, 403, 410]:
            with self.assertRaises(HTTPError):
                self.verify(lambda url, timeout: self.raise_http(url, code))
        self.assertEqual(self.clock.pauses, [])

    @staticmethod
    def raise_http(url, code):
        raise HTTPError(url, code, 'registry failure', None, None)

    def test_consumer_retries_only_exact_missing_version(self):
        from release import resolve
        missing = "Because example depends on flutter_true_time 2.0.4 which doesn't match any versions, version solving failed."
        results = [subprocess.CompletedProcess([], 1, missing),
                   subprocess.CompletedProcess([], 0, 'Got dependencies!')]
        with patch('release.subprocess.run', side_effect=results) as run:
            resolve(self.version, pause=self.clock.pause, now=self.clock.now,
                    log=self.logs.append)
        self.assertEqual(run.call_count, 2)
        self.assertEqual(run.call_args.args[0], ['flutter', 'pub', 'get'])
        self.assertEqual(self.clock.pauses, [10])

    def test_consumer_permanent_errors_and_timeouts_do_not_retry(self):
        from release import resolve
        for message in ["depends on other_package 2.0.4 which doesn't match any versions, version solving failed.",
                        "depends on flutter_true_time ^2.0.4 which doesn't match any versions, version solving failed.",
                        "depends on flutter_true_time 2.0.3 which doesn't match any versions, version solving failed.",
                        'Authorization failed', 'Compilation failed', 'SDK constraint not satisfied']:
            with patch('release.subprocess.run', return_value=subprocess.CompletedProcess([], 1, message)) as run:
                with self.assertRaises(subprocess.CalledProcessError):
                    resolve(self.version, pause=self.clock.pause, log=self.logs.append)
                self.assertEqual(run.call_count, 1)
        with patch('release.subprocess.run', side_effect=subprocess.TimeoutExpired('flutter', 60)) as run:
            with self.assertRaises(subprocess.TimeoutExpired):
                resolve(self.version, pause=self.clock.pause, log=self.logs.append)
            self.assertEqual(run.call_count, 1)
        self.assertEqual(self.clock.pauses, [])

    def test_consumer_missing_version_is_bounded_by_attempts_and_time(self):
        from release import resolve
        missing = "depends on flutter_true_time 2.0.4 which doesn't match any versions, version solving failed."
        with patch('release.subprocess.run', return_value=subprocess.CompletedProcess([], 1, missing)) as run:
            with self.assertRaises(RuntimeError):
                resolve(self.version, attempts=3, pause=self.clock.pause,
                        now=self.clock.now, log=self.logs.append)
            self.assertEqual(run.call_count, 3)
        self.assertEqual(self.clock.pauses, [10, 10])
        self.clock = RetryClock()
        with patch('release.subprocess.run', return_value=subprocess.CompletedProcess([], 1, missing)) as run:
            with self.assertRaises(RuntimeError):
                resolve(self.version, budget=5, pause=self.clock.pause,
                        now=self.clock.now, log=self.logs.append)
            self.assertEqual(run.call_count, 1)
            self.assertEqual(run.call_args.kwargs['timeout'], 5)
        self.assertEqual(self.clock.pauses, [5])

    def test_registry_stops_before_a_request_without_remaining_time(self):
        calls = []

        def fetch(url, timeout):
            calls.append(url)
            self.clock.elapsed += timeout
            return self.response(self.identity)

        with self.assertRaises(RuntimeError):
            self.verify(fetch, budget=3)
        self.assertEqual(len(calls), 1)
        self.assertEqual(self.clock.pauses, [])

    def test_malformed_json_is_not_retried(self):
        calls = []

        def fetch(url, timeout):
            calls.append(url)
            return io.StringIO('not JSON')

        with self.assertRaises(ValueError):
            self.verify(fetch)
        self.assertEqual(len(calls), 1)
        self.assertEqual(self.clock.pauses, [])

    def test_invalid_versions_fail_before_any_io(self):
        from release import resolve
        for version in ['^2.0.4', '2.0', '2.0.4-dev.01', '2.0.4\ninvalid']:
            with patch('release.subprocess.run') as run:
                with self.assertRaises(ValueError):
                    resolve(version)
                run.assert_not_called()
            with self.assertRaises(ValueError):
                verify(version, fetch=lambda *args, **kwargs: self.fail('unexpected registry I/O'))

    def test_wrapped_missing_version_diagnostic_is_recognized(self):
        from release import resolve
        missing = "Because example depends on flutter_true_time 2.0.4 which doesn't match\n  any versions, version solving failed."
        with patch('release.subprocess.run', side_effect=[
            subprocess.CompletedProcess([], 1, missing),
            subprocess.CompletedProcess([], 0, 'Resolved'),
        ]) as run:
            resolve(self.version, pause=self.clock.pause, now=self.clock.now,
                    log=self.logs.append)
        self.assertEqual(run.call_count, 2)

    def test_non_solver_exit_codes_do_not_retry_a_matching_diagnostic(self):
        from release import resolve
        missing = "depends on flutter_true_time 2.0.4 which doesn't match any versions, version solving failed."
        with patch('release.subprocess.run', return_value=subprocess.CompletedProcess([], 64, missing)) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                resolve(self.version, pause=self.clock.pause, log=self.logs.append)
            self.assertEqual(run.call_count, 1)


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
            if url.endswith('/flutter_true_time'):
                return io.StringIO(json.dumps({'name': 'flutter_true_time', 'versions': [{'version': '2.0.4'}]}))
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
