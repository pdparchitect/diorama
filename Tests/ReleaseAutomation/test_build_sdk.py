"""Prevent legacy SwiftUI behavior caused by an incorrect linked SDK stamp."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("verify_build_sdk", ROOT / "scripts/verify-build-sdk.py")
check = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check)


class BuildSDKTests(unittest.TestCase):
    def test_current_sdk_preserves_older_macos_support(self):
        check.verify("    minos 15.0\n      sdk 27.0\n", "27.0.0")

    def test_deployment_target_cannot_masquerade_as_sdk(self):
        with self.assertRaisesRegex(ValueError, "Linked SDK 15.0"):
            check.verify("    minos 15.0\n      sdk 15.0\n", "27.0")

    def test_all_architectures_must_match(self):
        with self.assertRaises(ValueError):
            check.verify("      sdk 27.0\n      sdk 15.0\n", "27.0")
        check.verify("      sdk 27.0\n      sdk 27.0\n", "27.0")

    def test_missing_sdk_is_rejected(self):
        with self.assertRaises(ValueError):
            check.verify("    minos 15.0\n", "27.0")

    def test_build_and_test_use_the_same_sdk_through_linking(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            sdk = root / "MacOSX27.0.sdk"
            swift = root / "swift"
            swift.write_text('#!/bin/sh\nprintf "%s\\n" "$SDKROOT" "$@"\n')
            xcrun = root / "xcrun"
            xcrun.write_text('''#!/bin/sh
if [ "$1" = "--find" ]; then
    printf '%s\n' "$DIORAMA_TEST_SWIFT"
else
    printf '%s\n' "$DIORAMA_TEST_SDK"
fi
''')
            swift.chmod(0o700)
            xcrun.chmod(0o700)
            env = dict(os.environ, PATH=f"{root}:/usr/bin:/bin",
                       DIORAMA_TEST_SWIFT=str(swift), DIORAMA_TEST_SDK=str(sdk),
                       SDKROOT="/wrong/inherited/sdk")
            for command in ["build", "test"]:
                with self.subTest(command=command):
                    result = subprocess.run(
                        ["/bin/zsh", str(ROOT / "scripts/swift.sh"), command, "--package-path", str(root)],
                        env=env, capture_output=True, text=True, check=True,
                    )
                    arguments = result.stdout.splitlines()
                    self.assertEqual(arguments[:2], [str(sdk), command])
                    self.assertEqual(arguments[arguments.index("--build-system") + 1], "native")
                    self.assertEqual(arguments[arguments.index("--sdk") + 1], str(sdk))
                    self.assertEqual(arguments[arguments.index("-syslibroot") + 2], str(sdk))
                    self.assertEqual(arguments[-2:], ["--package-path", str(root)])
