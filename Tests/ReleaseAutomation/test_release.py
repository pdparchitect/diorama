import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("release", Path(__file__).resolve().parents[2] / "scripts/release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.addCleanup(patch.stopall)
        patch.object(release, "ROOT", self.root).start()
        self.git("init", "-q")
        self.git("config", "user.name", "Release Test")
        self.git("config", "user.email", "test@example.invalid")
        self.write_version("0.1.0")
        self.git("add", ".")
        self.git("commit", "-qm", "Initial")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True, stderr=subprocess.DEVNULL).strip()

    def write_version(self, value, dated=True):
        (self.root / "VERSION").write_text(value + "\n")
        section = f"## [{value}] - 2026-09-16" if dated else "## [Unreleased]"
        (self.root / "CHANGELOG.md").write_text(f"# Changelog\n\n{section}\n\n- Ship the desktop.\n")

    def assets(self):
        directory = self.root / "assets"
        directory.mkdir()
        archive = directory / release.ASSETS[0]
        archive.write_bytes(b"prepared archive")
        (directory / release.ASSETS[1]).write_text(f"{release.digest(archive)}  {archive.name}\n")
        (directory / "release-notes.md").write_text(release.notes())
        (directory / "appcast.xml").write_text('''<?xml version="1.0"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
<sparkle:version>0.1.0</sparkle:version><sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
<enclosure url="https://github.com/pdparchitect/diorama/releases/download/v0.1.0/Diorama-arm64.zip" sparkle:edSignature="fixture" length="16"/>
</item></channel></rss>''')
        (directory / "release.json").write_text(json.dumps(release.manifest(directory)))
        return directory

    def environment(self):
        patch.dict(os.environ, {"GITHUB_REPOSITORY": release.REPOSITORY, "GITHUB_REF": "refs/heads/main",
                                "GITHUB_EVENT_NAME": "push", "GITHUB_SHA": self.git("rev-parse", "HEAD")}).start()

    def test_first_version_waits_for_dated_notes(self):
        self.write_version("0.1.0", dated=False)
        self.assertFalse(release.plan())
        self.write_version("0.1.0")
        self.assertTrue(release.plan())

    def test_unchanged_version_skips_publication(self):
        self.git("tag", "v0.1.0")
        self.assertFalse(release.plan())

    def test_numeric_version_order(self):
        self.git("tag", "v0.9.0")
        self.write_version("0.10.0")
        self.assertTrue(release.plan())

    def test_rollback_is_rejected_even_to_an_existing_tag(self):
        self.git("tag", "v0.1.0")
        self.git("tag", "v0.2.0")
        with self.assertRaisesRegex(ValueError, "roll back"):
            release.plan()

    def test_invalid_versions_fail(self):
        for value in ["1.0", "01.0.0", "v1.0.0", "1.0.0-beta", "1.0.0\nmalicious"]:
            with self.subTest(value=value):
                self.write_version(value)
                with self.assertRaises(ValueError):
                    release.version()

    def test_new_version_requires_dated_notes(self):
        self.git("tag", "v0.1.0")
        self.write_version("0.2.0", dated=False)
        with self.assertRaisesRegex(ValueError, "dated section"):
            release.plan()

    def test_notes_require_real_date_and_nonempty_content(self):
        for content in ["## [0.1.0] - 2026-02-30\n\n- Invalid date", "## [0.1.0] - 2026-09-16\n"]:
            (self.root / "CHANGELOG.md").write_text(content)
            with self.assertRaises(ValueError):
                release.notes()

    def test_notes_do_not_include_adjacent_sections(self):
        (self.root / "CHANGELOG.md").write_text("## [Unreleased]\n\n- Later\n\n## [0.1.0] - 2026-09-16\n\n- Ship\n\n## [0.0.1] - 2026-09-01\n\n- Older\n")
        self.assertEqual(release.notes(), "- Ship\n")

    def test_duplicate_notes_are_rejected(self):
        p = self.root / "CHANGELOG.md"
        p.write_text(p.read_text() * 2)
        with self.assertRaises(ValueError):
            release.notes()

    def test_tag_never_moves_to_another_commit(self):
        self.git("tag", "v0.1.0")
        self.git("commit", "--allow-empty", "-qm", "Another commit")
        with self.assertRaisesRegex(ValueError, "another commit"):
            release.mint()

    def test_dirty_tree_cannot_be_tagged(self):
        self.write_version("0.2.0")
        with self.assertRaisesRegex(ValueError, "modified tracked"):
            release.mint()

    def test_tag_retry_is_idempotent(self):
        origin = self.root / "origin.git"
        subprocess.run(["git", "init", "--bare", "-q", str(origin)], check=True)
        self.git("remote", "add", "origin", str(origin))
        release.mint()
        tag = self.git("rev-parse", "refs/tags/v0.1.0")
        release.mint()
        self.assertEqual(self.git("rev-parse", "refs/tags/v0.1.0"), tag)

    def test_manifest_binds_all_assets_and_commit(self):
        directory = self.assets()
        manifest = release.manifest(directory)
        self.assertEqual(set(manifest["sha256"]), set(release.ASSETS))
        self.assertEqual(manifest["commit"], self.git("rev-parse", "HEAD"))
        (directory / release.ASSETS[0]).write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "checksum"):
            release.manifest(directory)

    def test_feed_rejects_wrong_archive_version_size_or_signature(self):
        directory = self.assets()
        feed = directory / "appcast.xml"
        original = feed.read_text()
        for old, new in [("releases/download/v0.1.0", "releases/latest/download"),
                         ("<sparkle:version>0.1.0", "<sparkle:version>0.2.0"),
                         ('length="16"', 'length="17"'), ('sparkle:edSignature="fixture"', ''),
                         ("<sparkle:minimumSystemVersion>15.0", "<sparkle:minimumSystemVersion>26.0")]:
            with self.subTest(old=old):
                feed.write_text(original.replace(old, new))
                with self.assertRaises(ValueError):
                    release.validate_assets(directory)
        feed.write_text(original)
        self.assertEqual(release.validate_assets(directory), "fixture")

    def test_publication_refuses_prs_and_forks(self):
        self.environment()
        gh = patch.object(release, "gh").start()
        for key, value in [("GITHUB_EVENT_NAME", "pull_request"), ("GITHUB_REPOSITORY", "someone/fork"),
                           ("GITHUB_REF", "refs/heads/feature")]:
            with patch.dict(os.environ, {key: value}), self.assertRaises(ValueError):
                release.publish(self.root)
        gh.assert_not_called()

    def test_publication_refuses_private_repository(self):
        self.environment()
        patch.object(release, "gh", return_value="true").start()
        with self.assertRaisesRegex(ValueError, "public"):
            release.publish(self.root)

    def test_publication_refuses_changed_prepared_assets(self):
        self.environment()
        directory = self.assets()
        path = directory / "appcast.xml"
        path.write_text(path.read_text() + "\n")
        patch.object(release, "gh", return_value="false").start()
        with self.assertRaisesRegex(ValueError, "hashes"):
            release.publish(directory)

    def test_publication_refuses_wrong_workflow_commit(self):
        self.environment()
        directory = self.assets()
        patch.object(release, "gh", return_value="false").start()
        with patch.dict(os.environ, {"GITHUB_SHA": "wrong"}), self.assertRaisesRegex(ValueError, "workflow commit"):
            release.publish(directory)

    def test_complete_draft_retry_checks_bytes_without_overwriting(self):
        self.environment()
        directory = self.assets()
        self.git("tag", "v0.1.0")
        original_git = release.git
        patch.object(release, "git", side_effect=lambda *args: "" if args[0] == "fetch" else original_git(*args)).start()
        names = (*release.ASSETS, "release.json")

        def fake_gh(*args):
            if args[:2] == ("api", f"repos/{release.REPOSITORY}"):
                return "false"
            if args[:2] == ("api", f"repos/{release.REPOSITORY}/releases"):
                return json.dumps([[{"id": 1, "tag_name": "v0.1.0", "draft": True, "prerelease": False}]])
            if args[:2] == ("api", f"repos/{release.REPOSITORY}/releases/1/assets"):
                return json.dumps([[{"name": name} for name in names]])
            if args[:2] == ("release", "download"):
                name = args[args.index("--pattern") + 1]
                target = Path(args[args.index("--dir") + 1]) / name
                target.write_bytes((directory / name).read_bytes())
            return ""

        gh = patch.object(release, "gh", side_effect=fake_gh).start()
        release.publish(directory)
        calls = [call.args[:2] for call in gh.call_args_list]
        self.assertNotIn(("release", "create"), calls)
        self.assertNotIn(("release", "upload"), calls)
        self.assertIn(("release", "edit"), calls)

    def test_new_release_tags_before_upload_and_promotes_only_after(self):
        self.environment()
        directory = self.assets()
        original_git = release.git
        patch.object(release, "git", side_effect=lambda *args: "" if args[0] == "fetch" else original_git(*args)).start()
        events = []
        patch.object(release, "mint", side_effect=lambda: events.append("tag")).start()

        def fake_gh(*args):
            if args[0] == "api":
                return "false" if args[1] == f"repos/{release.REPOSITORY}" else "[[]]"
            events.append(args[1])
            if args[1] == "create":
                self.assertIn("--draft", args)
                self.assertIn("--verify-tag", args)
            return ""

        patch.object(release, "gh", side_effect=fake_gh).start()
        release.publish(directory)
        self.assertEqual(events, ["tag", "create", "edit"])

    def test_mismatched_draft_asset_is_never_overwritten_or_promoted(self):
        self.environment()
        directory = self.assets()
        self.git("tag", "v0.1.0")
        original_git = release.git
        patch.object(release, "git", side_effect=lambda *args: "" if args[0] == "fetch" else original_git(*args)).start()

        def fake_gh(*args):
            if args[:2] == ("api", f"repos/{release.REPOSITORY}"):
                return "false"
            if args[:2] == ("api", f"repos/{release.REPOSITORY}/releases"):
                return json.dumps([[{"id": 1, "tag_name": "v0.1.0", "draft": True, "prerelease": False}]])
            if args[0] == "api":
                return '[[{"name": "appcast.xml"}]]'
            if args[:2] == ("release", "download"):
                (Path(args[args.index("--dir") + 1]) / "appcast.xml").write_text("different")
            return ""

        gh = patch.object(release, "gh", side_effect=fake_gh).start()
        with self.assertRaisesRegex(ValueError, "refusing replacement"):
            release.publish(directory)
        for call in gh.call_args_list:
            self.assertNotIn(call.args[:2], [("release", "upload"), ("release", "edit")])


if __name__ == "__main__":
    unittest.main()
