"""Release metadata and bounded registry/consumer verification; never uploads."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import urlopen


VERSION = re.compile(
    r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
)


def _version(version):
    match = VERSION.fullmatch(version)
    if not match or any(
        part.isdigit() and len(part) > 1 and part.startswith('0')
        for part in (match[1] or '').split('.')
    ):
        raise ValueError('Require a valid exact semantic version')
    return match


def metadata(root, ref):
    pubspec = (root / "pubspec.yaml").read_text(encoding="utf-8")
    names = re.findall(r"^name: ([^\r\n]+)$", pubspec, re.M)
    versions = re.findall(r"^version: ([^\r\n]+)$", pubspec, re.M)
    if names != ["flutter_true_time"] or len(versions) != 1:
        raise ValueError("Require the expected package name and one version")
    version = versions[0]
    match = _version(version)
    if re.search(r"^publish_to:", pubspec, re.M):
        raise ValueError("Publication must target the default pub.dev registry")
    if ref.startswith("refs/tags/") and ref != f"refs/tags/v{version}":
        raise ValueError("Tag must exactly match v<pubspec version>")
    changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")
    heading = f"## {version}"
    sections = re.split(r"(?m)^## ", changelog)
    entries = [entry for entry in sections[1:] if entry.splitlines()[0] == version]
    if len(entries) != 1:
        raise ValueError(f"Require one changelog heading: {heading}")
    notes = "\n".join(entries[0].splitlines()[1:]).strip()
    if not notes:
        raise ValueError("Release notes must not be empty")
    notes += f"\n\n[Install from pub.dev](https://pub.dev/packages/flutter_true_time/versions/{version})\n"
    return version, bool(match[1]), notes


def smoke_versions(requested='', *, release=False, fetch=urlopen):
    """Freeze one current version, retaining advisory history only outside releases."""
    if not requested and release:
        raise ValueError('Reusable release smoke tests require an exact version')
    if requested:
        _version(requested)
        version = requested
    else:
        with fetch('https://pub.dev/api/packages/flutter_true_time', timeout=20) as response:
            index = json.load(response)
        if (not isinstance(index, dict) or index.get('name') != 'flutter_true_time' or
                not isinstance(index.get('latest'), dict) or
                not isinstance(index['latest'].get('version'), str) or
                not isinstance(index['latest'].get('pubspec'), dict) or
                index['latest']['pubspec'].get('name') != 'flutter_true_time' or
                not isinstance(index.get('versions'), list) or
                any(not isinstance(item, dict) or not isinstance(item.get('version'), str)
                    for item in index['versions'])):
            raise ValueError('Registry returned malformed latest-release metadata')
        version = index['latest']['version']
        if _version(version)[1]:
            raise ValueError('Registry latest release must be stable')
        if not any(isinstance(item, dict) and item.get('version') == version and
                   not item.get('retracted', False) for item in index['versions']):
            raise ValueError('Registry latest release is unavailable or retracted')
        if index['latest'].get('retracted', False):
            raise ValueError('Registry latest release is retracted')
    lanes = [{'lane': 'release' if release else 'current', 'version': version,
              'advisory': False}]
    if not release:
        lanes.append({'lane': 'historical', 'version': '2.0.0', 'advisory': True})
    return lanes


class _NotVisible(Exception):
    """Only a recognized propagation/transient registry condition is retryable."""


def _log(message):
    print(message, flush=True)


def _retry(action, *, label, attempts, budget, pause, now, log):
    if attempts < 1 or budget <= 0:
        raise ValueError('Retry attempts and time budget must be positive')
    deadline = now() + budget

    def timeout(limit):
        remaining = deadline - now()
        if remaining <= 0:
            raise RuntimeError(f'{label} exhausted its time budget')
        return min(limit, remaining)

    for attempt in range(attempts):
        remaining = deadline - now()
        if remaining <= 0:
            break
        log(f'{label} attempt {attempt + 1}/{attempts} ({remaining:.1f}s remaining)')
        try:
            result = action(timeout)
        except _NotVisible as error:
            log(f'Waiting for propagation: {error}')
        else:
            if now() < deadline:
                return result
            break
        remaining = deadline - now()
        if attempt + 1 < attempts and remaining > 0:
            pause(min(10, remaining))
    raise RuntimeError(f'{label} did not complete within its attempt/time budget')


def verify(version, attempts=60, fetch=urlopen, pause=time.sleep, *,
           budget=600, now=time.monotonic, log=_log):
    _version(version)
    index_url = 'https://pub.dev/api/packages/flutter_true_time'

    def check(timeout):
        try:
            with fetch(f'{index_url}/versions/{version}', timeout=timeout(20)) as response:
                record = json.load(response)
            if (not isinstance(record, dict) or record.get('version') != version or
                    not isinstance(record.get('pubspec'), dict) or
                    record['pubspec'].get('name') != 'flutter_true_time'):
                raise ValueError("Registry returned an unexpected package/version")
            with fetch(index_url, timeout=timeout(20)) as response:
                index = json.load(response)
            if (not isinstance(index, dict) or index.get('name') != 'flutter_true_time' or
                    not isinstance(index.get('versions'), list) or
                    any(not isinstance(item, dict) or not isinstance(item.get('version'), str)
                        for item in index['versions'])):
                raise ValueError('Registry returned a malformed package index')
            if not any(item['version'] == version for item in index['versions']):
                raise _NotVisible(f'flutter_true_time {version} is absent from the package index')
            return record
        except HTTPError as error:
            if error.code not in (404, 429, 500, 502, 503, 504):
                raise
            raise _NotVisible(f'registry HTTP {error.code}') from error
        except (URLError, TimeoutError) as error:
            raise _NotVisible(f'registry connection failed: {error}') from error

    return _retry(check, label=f'Registry verification for {version}', attempts=attempts,
                  budget=budget, pause=pause, now=now, log=log)


def resolve(version, attempts=6, pause=time.sleep, *, budget=180,
            now=time.monotonic, log=_log):
    """Resolve the current consumer; retry only an exact-version absence diagnostic."""
    _version(version)
    missing = re.compile(
        r'\bdepends on flutter_true_time ' + re.escape(version) +
        r" which doesn't match any versions, version solving failed\."
    )

    def check(timeout):
        result = subprocess.run(['flutter', 'pub', 'get'], stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, timeout=timeout(60))
        log(result.stdout)
        if result.returncode == 0:
            return
        if result.returncode == 1 and missing.search(' '.join(result.stdout.split())):
            raise _NotVisible(f'consumer cannot yet resolve flutter_true_time {version}')
        raise subprocess.CalledProcessError(result.returncode, result.args, output=result.stdout)

    _retry(check, label=f'Consumer resolution for {version}', attempts=attempts,
           budget=budget, pause=pause, now=now, log=log)


def main():
    if sys.argv[1:] == ['smoke-versions']:
        lanes = smoke_versions(os.environ.get('REQUESTED_VERSION', ''),
                               release=os.environ.get('RELEASE_SMOKE') == 'true')
        if os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
                output.write(f'lanes={json.dumps(lanes)}\n')
        summary = '\n'.join(
            f"- {lane['lane']}: flutter_true_time {lane['version']} "
            f"({'advisory' if lane['advisory'] else 'required'})" for lane in lanes)
        if os.environ.get('GITHUB_STEP_SUMMARY'):
            with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as output:
                output.write(f'## Published package versions\n\n{summary}\n')
        print(summary)
    elif sys.argv[1:] == ["metadata"]:
        root = Path.cwd()
        version, prerelease, notes = metadata(root, os.environ.get("GITHUB_REF", ""))
        destination = root / ".dart_tool" / "release-notes.md"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(notes, encoding="utf-8")
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
                output.write(f"version={version}\nprerelease={str(prerelease).lower()}\n")
        print(f"Validated flutter_true_time {version}")
    elif len(sys.argv) == 3 and sys.argv[1] == "verify":
        record = verify(sys.argv[2])
        print(f"Registry confirmed flutter_true_time {record['version']}")
    elif len(sys.argv) == 3 and sys.argv[1] == 'resolve':
        resolve(sys.argv[2])
    else:
        raise SystemExit("Use metadata, smoke-versions, verify <version>, or resolve <version>")


if __name__ == "__main__":
    main()
