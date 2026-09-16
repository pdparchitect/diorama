#!/usr/bin/env python3
"""Validate versions and publish the exact artifacts prepared by CI."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = "pdparchitect/diorama"
SEMVER = r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
ASSETS = ("Diorama-arm64.zip", "Diorama-arm64.zip.sha256", "appcast.xml", "release-notes.md")
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def git(*args):
    return run("git", *args)


def version():
    value = (ROOT / "VERSION").read_text().strip()
    if not re.fullmatch(SEMVER, value):
        raise ValueError(f"VERSION must be X.Y.Z, found {value!r}")
    return value


def number(value):
    return tuple(map(int, value.split(".")))


def notes():
    value = version()
    text = (ROOT / "CHANGELOG.md").read_text()
    headers = list(re.finditer(rf"^## \[{re.escape(value)}\] - (\d{{4}}-\d{{2}}-\d{{2}})$", text, re.M))
    if len(headers) != 1:
        raise ValueError(f"CHANGELOG.md needs exactly one dated section for {value}")
    header = headers[0]
    datetime.date.fromisoformat(header[1])
    body = re.split(r"^## ", text[header.end():], maxsplit=1, flags=re.M)[0].strip()
    if not re.search(r"^[-*] \S", body, re.M):
        raise ValueError(f"No release notes for {value}")
    return body + "\n"


def released_versions():
    return [tag[1:] for tag in git("tag", "--list", "v*").splitlines()
            if re.fullmatch("v" + SEMVER, tag)]


def check_version_order():
    previous = released_versions()
    if previous and number(version()) < max(map(number, previous)):
        raise ValueError("VERSION would roll back a released version")
    return previous


def plan():
    value = version()
    previous = check_version_order()
    if value in previous:
        return False
    # Keep the initial checkout in development until its first notes are dated.
    if not previous and not re.search(r"^## \[.*\] - ", (ROOT / "CHANGELOG.md").read_text(), re.M):
        return False
    notes()
    return True


def mint():
    value = version()
    notes()
    previous = check_version_order()
    if git("status", "--porcelain", "--untracked-files=no"):
        raise ValueError("Refusing to tag modified tracked files")
    head = git("rev-parse", "HEAD")
    tag = "v" + value
    if value in previous:
        if git("rev-parse", f"refs/tags/{tag}^{{commit}}") != head:
            raise ValueError(f"{tag} already identifies another commit")
    else:
        git("-c", "user.name=github-actions[bot]", "-c",
            "user.email=41898282+github-actions[bot]@users.noreply.github.com",
            "tag", "-a", tag, "-m", tag, head)
    git("push", "origin", f"refs/tags/{tag}")


def digest(path):
    with path.open("rb") as file:
        result = hashlib.sha256()
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            result.update(chunk)
        return result.hexdigest()


def validate_assets(directory):
    value = version()
    archive = directory / ASSETS[0]
    checksum = (directory / ASSETS[1]).read_text().split()
    if checksum != [digest(archive), ASSETS[0]]:
        raise ValueError("Archive checksum does not match")
    if (directory / "release-notes.md").read_text() != notes():
        raise ValueError("Release notes do not match CHANGELOG.md")
    feed = ET.parse(directory / "appcast.xml")
    items = feed.findall("./channel/item")
    if len(items) != 1:
        raise ValueError("Expected exactly one release in appcast")
    item = items[0]
    enclosure = item.find("enclosure")
    expected_url = f"https://github.com/{REPOSITORY}/releases/download/v{value}/{ASSETS[0]}"
    if enclosure is None or enclosure.get("url") != expected_url:
        raise ValueError("Appcast must use the immutable release archive URL")
    if item.findtext(SPARKLE + "version") != value or item.findtext(SPARKLE + "shortVersionString") != value:
        raise ValueError("Appcast version does not match VERSION")
    if item.findtext(SPARKLE + "minimumSystemVersion") != "15.0":
        raise ValueError("Unexpected minimum macOS version")
    if not enclosure.get(SPARKLE + "edSignature") or enclosure.get("length") != str(archive.stat().st_size):
        raise ValueError("Appcast archive signature or size is missing")
    return enclosure.get(SPARKLE + "edSignature")


def manifest(directory):
    validate_assets(directory)
    return {"version": version(), "commit": git("rev-parse", "HEAD"),
            "sha256": {name: digest(directory / name) for name in ASSETS}}


def gh(*args):
    return run("gh", *args)


def publish(directory):
    # Only a trusted main-branch workflow may mint tags or change the public feed.
    if os.environ.get("GITHUB_REPOSITORY") != REPOSITORY or os.environ.get("GITHUB_REF") != "refs/heads/main":
        raise ValueError("Publication requires the upstream main-branch workflow")
    if os.environ.get("GITHUB_EVENT_NAME") not in ("push", "workflow_dispatch"):
        raise ValueError("This event cannot publish releases")
    if gh("api", f"repos/{REPOSITORY}", "--jq", ".private") != "false":
        raise ValueError("Diorama downloads and update feeds must be public")
    expected = manifest(directory)
    if json.loads((directory / "release.json").read_text()) != expected:
        raise ValueError("Prepared assets do not match the checked commit and hashes")
    if os.environ.get("GITHUB_SHA") != expected["commit"]:
        raise ValueError("Checkout does not match the workflow commit")
    git("fetch", "origin", "--tags")
    check_version_order()
    tag = "v" + version()
    pages = json.loads(gh("api", f"repos/{REPOSITORY}/releases", "--paginate", "--slurp"))
    releases = [release for page in pages for release in page]
    for release in releases:
        other = release["tag_name"]
        if not release["draft"] and re.fullmatch("v" + SEMVER, other) and number(other[1:]) > number(version()):
            raise ValueError("Refusing to replace a newer public release")
    existing = next((release for release in releases if release["tag_name"] == tag), None)
    if existing:
        # Retry after an interrupted upload/promotion, using byte-identical assets.
        # Never clobber an asset or rebuild a tag that already exists.
        if git("rev-parse", f"refs/tags/{tag}^{{commit}}") != expected["commit"]:
            raise ValueError("Existing release tag does not match prepared artifacts")
        if existing["prerelease"]:
            raise ValueError("Refusing to promote an existing prerelease")
        expected_names = set(ASSETS) | {"release.json"}
        assets = json.loads(gh("api", f"repos/{REPOSITORY}/releases/{existing['id']}/assets", "--paginate", "--slurp"))
        assets = [asset for page in assets for asset in page]
        if any(asset["name"] not in expected_names for asset in assets):
            raise ValueError("Existing release has unexpected assets; inspect it before retrying")
        present = {asset["name"] for asset in assets}
        import tempfile
        with tempfile.TemporaryDirectory() as temporary:
            for name in sorted(present):
                gh("release", "download", tag, "--repo", REPOSITORY, "--pattern", name, "--dir", temporary)
                if digest(Path(temporary) / name) != digest(directory / name):
                    raise ValueError(f"Published asset differs: {name}; refusing replacement")
        missing = sorted(expected_names - present)
        if missing and not existing["draft"]:
            raise ValueError("Published release is incomplete; manual inspection required")
        if missing:
            gh("release", "upload", tag, *[str(directory / name) for name in missing], "--repo", REPOSITORY)
    else:
        mint()
        gh("release", "create", tag, *[str(directory / name) for name in (*ASSETS, "release.json")],
           "--repo", REPOSITORY, "--draft", "--verify-tag", "--title", f"Diorama {version()}",
           "--notes-file", str(directory / "release-notes.md"))
    gh("release", "edit", tag, "--repo", REPOSITORY, "--draft=false", "--latest",
       "--title", f"Diorama {version()}", "--notes-file", str(directory / "release-notes.md"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("version", "plan", "notes", "manifest", "signature", "publish"))
    parser.add_argument("--directory", type=Path, default=ROOT / "dist/release")
    args = parser.parse_args()
    if args.command == "version":
        print(version())
    elif args.command == "notes":
        print(notes(), end="")
    elif args.command == "plan":
        output = f"release={str(plan()).lower()}\nversion={version()}\n"
        print(output, end="")
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a") as file:
                file.write(output)
    elif args.command == "manifest":
        (args.directory / "release.json").write_text(json.dumps(manifest(args.directory), indent=2) + "\n")
    elif args.command == "signature":
        print(validate_assets(args.directory))
    else:
        publish(args.directory.resolve())


if __name__ == "__main__":
    main()
