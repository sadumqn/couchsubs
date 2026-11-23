# SPDX-License-Identifier: AGPL-3.0-only
"""The bundle version gate should parse source versions independently of formatting."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SOURCE = Path(__file__).with_name("check-tv-packages.py")
spec = importlib.util.spec_from_file_location("check_tv_packages", SOURCE)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class TVPackageVersionTests(unittest.TestCase):
    def sources(self, tizen_attrs, android):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "tv-webos").mkdir()
            (root / "tv-tizen").mkdir()
            (root / "tv-android/app").mkdir(parents=True)
            (root / "tv-webos/appinfo.json").write_text(json.dumps({"version": "0.9.77"}), encoding="utf-8")
            (root / "tv-tizen/config.xml").write_text(
                f'<widget xmlns="http://www.w3.org/ns/widgets" {tizen_attrs}></widget>', encoding="utf-8")
            (root / "tv-android/app/build.gradle").write_text(
                'android { defaultConfig { ' + android + ' } }', encoding="utf-8")
            return mod.source_versions(root)

    def test_tizen_version_is_found_when_attribute_order_changes(self):
        self.assertEqual(self.sources('viewmodes="fullscreen" version="0.9.77"', "versionName '0.9.77'"),
                         {"ipk": "0.9.77", "wgt": "0.9.77", "apk": "0.9.77"})

    def test_gradle_double_quoted_version_is_recognized(self):
        self.assertEqual(self.sources('version="0.9.77" viewmodes="fullscreen"', 'versionName "0.9.77"'),
                         {"ipk": "0.9.77", "wgt": "0.9.77", "apk": "0.9.77"})

    def test_current_single_quoted_sources_still_work(self):
        self.assertEqual(self.sources('version="0.9.77" viewmodes="fullscreen"', "versionName '0.9.77'"),
                         {"ipk": "0.9.77", "wgt": "0.9.77", "apk": "0.9.77"})

    def test_multiple_lg_packages_are_rejected_even_if_latest_version_matches(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            (folder / "com.couchsubs.tv_0.9.77_all.ipk").write_bytes(b"current")
            (folder / "legacy_com.couchsubs.tv_0.9.77_all.ipk").write_bytes(b"ambiguous")
            with patch.object(mod, "source_versions", return_value={"ipk": "0.9.77"}):
                issues = mod.problems(folder)
            self.assertEqual(len(issues), 1, issues)
            self.assertIn("birden fazla", issues[0], "a release must not silently choose one of two TV installers")

    def test_empty_desktop_tv_installers_are_rejected_even_if_versions_match(self):
        for kind, name in [
            ("ipk", "com.couchsubs.tv_0.9.77_all.ipk"),
            ("wgt", "couchsubs-samsung_0.9.77.wgt"),
            ("apk", "couchsubs-androidtv_0.9.77.apk"),
        ]:
            with self.subTest(platform=kind), tempfile.TemporaryDirectory() as temp:
                folder = Path(temp)
                (folder / name).write_bytes(b"")
                with patch.object(mod, "source_versions", return_value={kind: "0.9.77"}):
                    issues = mod.problems(folder)
                self.assertEqual(len(issues), 1, issues)
                self.assertIn("boş", issues[0], "correctly named zero-byte installer is not installable")

    def test_empty_iphone_tv_installer_is_rejected_even_if_properties_match(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            (folder / "couchsubs-samsung.wgt").write_bytes(b"")
            (folder / "tv-packages.properties").write_text(
                "couchsubs-samsung.wgt.version=0.9.77\n", encoding="utf-8")
            with patch.object(mod, "source_versions", return_value={"wgt": "0.9.77"}):
                issues = mod.problems(folder)
            self.assertEqual(len(issues), 1, issues)
            self.assertIn("boş", issues[0])

    def test_current_single_release_package_still_passes(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            (folder / "com.couchsubs.tv_0.9.77_all.ipk").write_bytes(b"current")
            with patch.object(mod, "source_versions", return_value={"ipk": "0.9.77"}):
                self.assertEqual(mod.problems(folder), [])


if __name__ == "__main__":
    unittest.main()
