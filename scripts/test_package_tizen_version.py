# SPDX-License-Identifier: AGPL-3.0-only
"""The Samsung WGT filename must use the widget version, independent of XML attribute order."""
import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPT = Path(__file__).with_name("package-tizen.sh")


def bash_executable():
    if os.name == "nt":
        executable = Path(r"C:\Program Files\Git\bin\bash.exe")
        if executable.is_file():
            return str(executable)
    return shutil.which("bash") or "/bin/sh"


def posix(path):
    value = str(path.resolve()).replace("\\", "/")
    return "/" + value[0].lower() + value[2:] if len(value) > 1 and value[1] == ":" else value


class PackageTizenTests(unittest.TestCase):
    def package(self, attrs, fail_archive=False):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "repo"
            for folder in ("scripts", "tv-webos", "tv-tizen"):
                (repo / folder).mkdir(parents=True)
            shutil.copy2(SCRIPT, repo / "scripts/package-tizen.sh")
            for name in ("app.js", "i18n.js", "config.js", "style.css", "largeIcon.png", "icon.png"):
                (repo / "tv-webos" / name).write_bytes(b"source")
            (repo / "tv-webos/index.html").write_text('<script src="platform.js"></script>', encoding="utf-8")
            for name in ("platform.js", "icon.png"):
                (repo / "tv-tizen" / name).write_bytes(b"source")
            (repo / "tv-tizen/config.xml").write_text(
                f'<widget xmlns="http://www.w3.org/ns/widgets" {attrs}></widget>', encoding="utf-8")
            dest = Path(tmp) / "output"
            env = {**os.environ, "COUCHSUBS_DIST": posix(dest), "TIZEN_PROFILE": ""}
            package = dest / "tv-app/couchsubs-samsung_0.9.73.wgt"
            if fail_archive:
                package.parent.mkdir(parents=True)
                with zipfile.ZipFile(package, "w") as prior:
                    prior.writestr("previous.txt", "Last known good TV installer")
                fakebin = Path(tmp) / "fake-bin"
                fakebin.mkdir()
                # Fail only the final archive write, after version extraction
                # and after the old script already deletes its previous WGT.
                wrapper = fakebin / "python3"
                wrapper.write_text(
                    '#!/bin/sh\n'
                    'if [ "$2" = "tv-tizen/config.xml" ]; then exec "' + posix(Path(__import__("sys").executable)) + '" "$@"; fi\n'
                    'exit 28\n', encoding="utf-8")
                wrapper.chmod(0o755)
                env["PATH"] = posix(fakebin) + ":/usr/bin:/bin"
            process = subprocess.run([bash_executable(), posix(repo / "scripts/package-tizen.sh")],
                                     cwd=repo, env=env, capture_output=True, text=True, errors="replace")
            return (process, package.exists(), zipfile.is_zipfile(package) if package.exists() else False,
                    package.read_bytes() if package.exists() else None)

    def test_works_when_version_precedes_viewmodes(self):
        process, exists, valid, _ = self.package('version="0.9.73" viewmodes="fullscreen"')
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        self.assertTrue(exists)
        self.assertTrue(valid)

    def test_works_when_version_follows_viewmodes(self):
        process, exists, valid, _ = self.package('viewmodes="fullscreen" version="0.9.73"')
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        self.assertTrue(exists, process.stdout + process.stderr)
        self.assertTrue(valid)


    def test_failed_archive_write_preserves_previous_signed_candidate(self):
        process, exists, valid, data = self.package(
            'version="0.9.73" viewmodes="fullscreen"', fail_archive=True)
        self.assertNotEqual(process.returncode, 0, "injected archive failure must abort")
        self.assertTrue(exists, "a failed build must not delete the last working WGT")
        self.assertTrue(valid, "the last working installer must still be a usable ZIP")
        self.assertIn(b"previous.txt", data, "do not replace the old archive with partial bytes")


if __name__ == "__main__":
    unittest.main()
