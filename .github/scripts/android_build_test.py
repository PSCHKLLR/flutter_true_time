import os
from pathlib import Path
import sys
import tempfile
import unittest

from android_build import Result, build, rate_limited, run_attempt


THROTTLED = "Could not GET 'https://repo.maven.apache.org/maven2/org/example/lib/1/lib.pom'. Received status code 429 from server: Too Many Requests"


class RetryTests(unittest.TestCase):
    def exercise(self, results, *, budget=1800, elapsed=0):
        clock = [0]
        calls, pauses, reports = [], [], []

        def run(command, timeout, path):
            calls.append((command, timeout, path.name))
            clock[0] += elapsed
            return results[len(calls) - 1]

        def pause(delay):
            pauses.append(delay)
            clock[0] += delay

        with tempfile.TemporaryDirectory() as directory:
            code = build(['flutter', 'build', 'apk'], Path(directory), run=run,
                         now=lambda: clock[0], pause=pause, jitter=lambda a, b: 5,
                         report=reports.append, budget=budget)
        return code, calls, pauses, reports

    def test_rate_limit_then_success_uses_fresh_invocation_and_backoff(self):
        code, calls, pauses, _ = self.exercise([Result(1, THROTTLED), Result(0, '')])
        self.assertEqual(code, 0)
        self.assertEqual(pauses, [35])
        self.assertEqual([call[2] for call in calls], ['attempt-1.log', 'attempt-2.log'])
        self.assertEqual(calls[1][1], 1765)

    def test_exhaustion_preserves_last_exit_code(self):
        code, calls, pauses, reports = self.exercise([Result(n, THROTTLED) for n in [1, 2, 7]])
        self.assertEqual(code, 7)
        self.assertEqual(len(calls), 3)
        self.assertEqual(pauses, [35, 65])
        self.assertIn('exhausted', reports[-1])

    def test_permanent_and_mixed_failures_are_not_retried(self):
        for output in ['Compilation failed', 'network unavailable',
                       THROTTLED + '\nCompilation failed',
                       THROTTLED + '\ne: file:///src/main.kt:1: invalid',
                       THROTTLED + '\nReceived status code 404 from server',
                       THROTTLED.replace('repo.maven.apache.org', 'unrelated.example'),
                       THROTTLED.replace('429', '500')]:
            with self.subTest(output=output):
                code, calls, pauses, _ = self.exercise([Result(9, output)])
                self.assertEqual((code, len(calls), pauses), (9, 1, []))

    def test_deadline_does_not_start_another_attempt_or_sleep(self):
        code, calls, pauses, _ = self.exercise([Result(7, THROTTLED)], budget=40, elapsed=10)
        self.assertEqual((code, len(calls), pauses), (7, 1, []))

    def test_timeout_is_not_retried_even_with_earlier_429(self):
        code, calls, pauses, _ = self.exercise([Result(124, THROTTLED)])
        self.assertEqual((code, len(calls), pauses), (124, 1, []))

    def test_head_requests_are_recognized(self):
        self.assertTrue(rate_limited(THROTTLED.replace('GET', 'HEAD')))

    @unittest.skipUnless(os.name == 'posix', 'Linux CI process groups')
    def test_real_process_logs_and_timeout(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'attempt.log'
            result = run_attempt([sys.executable, '-c', "print('original'); raise SystemExit(7)"], 5, path)
            self.assertEqual(result.code, 7)
            self.assertIn('original', path.read_text())
            result = run_attempt([sys.executable, '-c', 'import time; time.sleep(5)'], .05, path)
            self.assertEqual(result.code, 124)
            self.assertIn('deadline', path.read_text())


if __name__ == '__main__':
    unittest.main()
