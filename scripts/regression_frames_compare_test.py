# SPDX-License-Identifier: AGPL-3.0-only
"""The release gate must catch per-frame regressions even when aggregate rates tie."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("regression_frames_compare.py")


def frame(name, captured):
    return {
        "id": name, "captured": captured,
        "phoneExpected": False, "phoneDetected": False,
        "mapExpected": False, "mapDetected": False,
    }


def summary(core, first, second):
    return {
        "core": core,
        "capture": {"passed": 1, "total": 2},
        "frames": [frame("first", first), frame("second", second)],
        "scenarios": [],
    }


class RegressionFrameGateTests(unittest.TestCase):
    def compare(self, base, head):
        with tempfile.TemporaryDirectory() as directory:
            before = Path(directory) / "before.json"
            after = Path(directory) / "after.json"
            before.write_text(json.dumps(base), encoding="utf-8")
            after.write_text(json.dumps(head), encoding="utf-8")
            return subprocess.run(
                [sys.executable, "-X", "utf8", str(SCRIPT), str(before), str(after)],
                capture_output=True, text=True, encoding="utf-8",
            )

    def test_swapped_failing_frame_must_fail_release_gate(self):
        result = self.compare(summary("old", True, False), summary("new", False, True))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("first: altyazı yakalanmadı", result.stdout)

    def test_unchanged_failing_frames_remain_green(self):
        result = self.compare(summary("old", True, False), summary("new", True, False))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_omitted_baseline_frame_fails_the_release_gate(self):
        base = summary("old", True, True)
        base["capture"] = {"passed": 2, "total": 2}
        head = summary("new", True, True)
        head["frames"] = [frame("first", True)]
        head["capture"] = {"passed": 1, "total": 1}
        result = self.compare(base, head)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("second", result.stdout)

    def test_omitted_baseline_scenario_fails_the_release_gate(self):
        base = summary("old", True, True)
        base["capture"] = {"passed": 2, "total": 2}
        base["scenarios"] = [{"name": "phone subtitle", "passed": True, "detail": "OK"}]
        head = summary("new", True, True)
        head["capture"] = {"passed": 2, "total": 2}
        result = self.compare(base, head)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("phone subtitle", result.stdout)

    def test_new_failure_reason_on_already_failing_frame_is_regression(self):
        # Overall capture rates tie. The same frame already failed before,
        # but a newly introduced false acceptance must still fail the gate.
        base = summary("old", False, True)
        head = summary("new", False, True)
        head["frames"][0]["falseAccept"] = False
        result = self.compare(base, head)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("first: yanlış kabul", result.stdout)



if __name__ == "__main__":
    unittest.main()
