"""Release metadata and bounded registry verification; never uploads a package."""

import json
import os
from pathlib import Path
import re
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import urlopen


VERSION = re.compile(
    r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
)


def metadata(root, ref):
    pubspec = (root / "pubspec.yaml").read_text(encoding="utf-8")
    names = re.findall(r"^name: ([^\r\n]+)$", pubspec, re.M)
    versions = re.findall(r"^version: ([^\r\n]+)$", pubspec, re.M)
    if names != ["flutter_true_time"] or len(versions) != 1:
        raise ValueError("Require the expected package name and one version")
    version = versions[0]
    match = VERSION.fullmatch(version)
    if not match or any(
        part.isdigit() and len(part) > 1 and part.startswith("0")
        for part in (match[1] or "").split(".")
    ):
        raise ValueError("Require a valid semantic version")
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


def verify(version, attempts=60, fetch=urlopen, pause=time.sleep):
    if not VERSION.fullmatch(version):
        raise ValueError("Invalid registry version")
    url = f"https://pub.dev/api/packages/flutter_true_time/versions/{version}"
    for attempt in range(attempts):
        try:
            with fetch(url, timeout=20) as response:
                record = json.load(response)
            if record.get("version") != version or record.get("pubspec", {}).get("name") != "flutter_true_time":
                raise ValueError("Registry returned an unexpected package/version")
            return record
        except HTTPError as error:
            if error.code not in (404, 429, 500, 502, 503, 504):
                raise
        except (URLError, TimeoutError):
            pass
        if attempt + 1 < attempts:
            pause(10)
    raise RuntimeError("Published version did not become available within the retry budget")


def main():
    if sys.argv[1:] == ["metadata"]:
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
    else:
        raise SystemExit("Use metadata or verify <version>")


if __name__ == "__main__":
    main()
