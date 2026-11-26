"""Run an Android build with bounded retries for explicit Maven Central 429s.

Linux CI only: each attempt owns a process group so a deadline also stops Gradle.
No shell interpolation, dependency changes, or publication commands are used.
"""

import argparse
from dataclasses import dataclass
import os
from pathlib import Path
import random
import re
import signal
import subprocess
import sys
import time


@dataclass
class Result:
    code: int
    output: str


def rate_limited(output):
    """Fail closed on unrelated HTTP statuses or mixed compiler failures."""
    if not re.search(r"Could not (?:GET|HEAD) 'https://repo\.maven\.apache\.org/maven2/[^'\n]+'\. Received status code 429\b", output):
        return False
    if any(code != '429' for code in re.findall(r'Received status code (\d+)', output)):
        return False
    return not re.search(
        r'(?im)(?:^\s*(?:e:|error:|Error:)|Compilation failed|'
        r'Could not find |Plugin \[.*\] was not found|'
        r'Script compilation error|What went wrong:\s*\n[^\n]*Syntax)', output)


def run_attempt(command, timeout, path):
    if os.name != 'posix':
        raise RuntimeError('Android CI build runner requires POSIX process groups')
    with path.open('w', encoding='utf-8') as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            log.write('\nAndroid build exceeded its overall deadline.\n')
            code = 124
    output = path.read_text(encoding='utf-8', errors='replace')
    print(output, end='', flush=True)
    return Result(code, output)


def build(command, logs, *, attempts=3, budget=1800, run=run_attempt,
          now=time.monotonic, pause=time.sleep, jitter=random.uniform,
          report=lambda message: print(message, flush=True)):
    if attempts < 1 or budget <= 0:
        raise ValueError('Attempts and budget must be positive')
    logs.mkdir(parents=True, exist_ok=True)
    deadline = now() + budget
    last_code = 124
    for attempt in range(1, attempts + 1):
        remaining = deadline - now()
        if remaining <= 0:
            return last_code
        report(f'Android build attempt {attempt}/{attempts}; {remaining:.1f}s remaining')
        result = run(command, remaining, logs / f'attempt-{attempt}.log')
        last_code = result.code
        if result.code == 0 or result.code == 124 or not rate_limited(result.output):
            return result.code
        if attempt == attempts:
            break
        delay = 30 * (2 ** (attempt - 1)) + jitter(0, 10)
        if delay >= deadline - now():
            break
        report(f'Maven Central HTTP 429; retrying in {delay:.1f}s with a fresh build invocation')
        pause(delay)
    report(f'Android build retries exhausted; retaining exit code {last_code}')
    return last_code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--logs', type=Path, required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if command[:3] not in [['flutter', 'build', 'apk'], ['flutter', 'build', 'appbundle']]:
        parser.error('Require flutter build apk or flutter build appbundle')
    return build(command, args.logs)


if __name__ == '__main__':
    sys.exit(main())
