# SPDX-License-Identifier: AGPL-3.0-only
"""An APK path passed to the bundler is relative to the caller, not the script."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("bundle-android-apk.sh")


def bash_executable():
    if os.name == "nt":
        executable = Path(r"C:\Program Files\Git\bin\bash.exe")
        if executable.is_file():
            return str(executable)
    return shutil.which("bash") or "/bin/sh"


def posix(path):
    value = str(path.resolve()).replace("\\", "/")
    return "/" + value[0].lower() + value[2:] if len(value) > 1 and value[1] == ":" else value


class BundleAndroidApkTests(unittest.TestCase):
    def bundle(self, use_relative, version_line="versionName '0.9.73'"):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo, caller = root / "repo", root / "caller"
            (repo / "scripts").mkdir(parents=True)
            (repo / "tv-android/app").mkdir(parents=True)
            (repo / "tv-android/app/build.gradle").write_text(version_line + "\n", encoding="utf-8")
            shutil.copy2(SCRIPT, repo / "scripts/bundle-android-apk.sh")
            (caller / "build").mkdir(parents=True)
            (caller / "build/source.apk").write_bytes(b"new apk bytes")
            arg = "build/source.apk" if use_relative else posix(caller / "build/source.apk")
            process = subprocess.run([bash_executable(), posix(repo / "scripts/bundle-android-apk.sh"), arg],
                                     cwd=caller, capture_output=True, text=True, errors="replace")
            output = repo / "dist/tv-app/couchsubs-androidtv_0.9.73.apk"
            return process, output.read_bytes() if output.exists() else None

    def test_caller_relative_source_path(self):
        process, content = self.bundle(True)
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        self.assertEqual(content, b"new apk bytes")

    def test_absolute_source_path_still_works(self):
        process, content = self.bundle(False)
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        self.assertEqual(content, b"new apk bytes")

    def test_double_quoted_gradle_version_produces_the_correct_apk_filename(self):
        process, content = self.bundle(False, 'versionName "0.9.73"')
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        self.assertEqual(content, b"new apk bytes", "release script must not publish unversioned APK")

    def test_missing_gradle_version_does_not_publish_unversioned_apk(self):
        process, content = self.bundle(False, 'applicationId "com.couchsubs.tv"')
        self.assertNotEqual(process.returncode, 0, "missing versionName must stop release packaging")
        self.assertIsNone(content)

    def test_rebundling_an_existing_release_apk_does_not_delete_its_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "scripts").mkdir()
            (root / "tv-android/app").mkdir(parents=True)
            (root / "tv-android/app/build.gradle").write_text("versionName '0.9.73'\n", encoding="utf-8")
            shutil.copy2(SCRIPT, root / "scripts/bundle-android-apk.sh")
            release = root / "dist/tv-app/couchsubs-androidtv_0.9.73.apk"
            release.parent.mkdir(parents=True)
            release.write_bytes(b"last good release")
            process = subprocess.run([bash_executable(), posix(root / "scripts/bundle-android-apk.sh"),
                                      posix(release)], cwd=root, capture_output=True, text=True, errors="replace")
            self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
            self.assertEqual(release.read_bytes(), b"last good release")


if __name__ == "__main__":
    unittest.main()
