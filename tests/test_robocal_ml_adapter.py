import csv
import importlib.util
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
ADAPTER = ROOT / "ML_Robocal_1.00a_20260804" / "robocal_ml_adapter.py"
SPEC = importlib.util.spec_from_file_location("robocal_ml_adapter", ADAPTER)
adapter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(adapter)


class RobocalMlAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.template = self.directory / "template.csv"
        self.report = self.directory / "report.csv"
        self.output = self.directory / "output.csv"
        self.headers = [
            "TSRID", "TestName", "Value", "LowerLimit", "UpperLimit",
            "ErrorCode", "ErrorDescription", "SerialNumber", "Operator",
        ]
        self.boot = self.row("Boot Status Check", error="0")
        self.robocal = self.row("Robocal", error="0")
        self.post = self.row("DCC.post_calibration.white_point_error.right")
        self.pre = self.row("DCC.pre_calibration.white_residual.right", "0.5")
        self.final = self.row("Log", error="0")
        self.control = ["2"] + [""] * (len(self.headers) - 1)
        self.write_csv(
            self.template, self.headers,
            [self.boot, self.robocal, self.post, self.pre, self.final, self.control],
        )
        self.write_csv(
            self.report, ["Test Name", "Reading", "Minimum Spec", "Maximum Spec"],
            [
                ["DCC.post_calibration.white_point_error.right", "2.5", "", "10"],
                ["DCC.pre_calibration.white_residual.right", "0.75", "", "7"],
                ["DGC.right.red.depth_m", "1.5", "", ""],
                ["DCC.post_cal.integration_time_us", "66664", "", ""],
            ],
        )

    def row(self, name, value="", error=""):
        return ["run-id", name, value, "", "", error, "", "OLD-SN", "operator"]

    def write_csv(self, path, headers, rows):
        with path.open("w", encoding="utf-8-sig", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(headers)
            writer.writerows(rows)

    def read_rows(self):
        with self.output.open(encoding="utf-8-sig", newline="") as handle:
            rows = list(csv.reader(handle))
        self.assertEqual(rows[0], self.headers)
        self.assertEqual(rows[-2:], [self.final, self.control])
        return rows[1:-2]

    def test_exclusion_removes_existing_and_generated_post_tests(self):
        count = adapter.append_report(
            self.template, self.report, self.output,
            replace_tests=True, serial_number="NEW-SN",
            exclude_dcc_post_calibration=True,
        )
        self.assertEqual(count, 3)
        rows = self.read_rows()
        self.assertEqual(rows[:2], [self.boot, self.robocal])
        self.assertFalse(any(row[1].startswith("DCC.post_calibration.") for row in rows))
        generated = {row[1]: row for row in rows[2:]}
        self.assertEqual(generated[self.pre[1]][2], "0.75")
        self.assertEqual(generated[self.pre[1]][4], "7")
        self.assertEqual(generated["DGC.right.red.depth_m"][2], "1.5")
        self.assertIn("DCC.post_cal.integration_time_us", generated)
        for row in generated.values():
            self.assertEqual(row[5:7], ["", ""])
            self.assertEqual(row[7:], ["NEW-SN", "operator"])

    def test_exclusion_cleans_template_even_when_report_has_no_post_tests(self):
        self.write_csv(
            self.report, ["Test Name", "Reading", "Minimum Spec", "Maximum Spec"],
            [["DGC.right.red.depth_m", "1.5", "", ""]],
        )
        adapter.append_report(
            self.template, self.report, self.output,
            exclude_dcc_post_calibration=True,
        )
        rows = self.read_rows()
        self.assertEqual(rows[:3], [self.boot, self.robocal, self.pre])
        self.assertNotIn(self.post, rows)

    def test_default_preserves_post_process_readings(self):
        adapter.append_report(self.template, self.report, self.output, replace_tests=True)
        rows = {row[1]: row for row in self.read_rows()}
        self.assertEqual(rows[self.post[1]][2], "2.5")
        self.assertEqual(rows[self.post[1]][4], "10")

    def test_repeated_in_place_exclusion_does_not_duplicate_tests(self):
        for template in (self.template, self.output):
            adapter.append_report(
                template, self.report, self.output,
                replace_tests=True, exclude_dcc_post_calibration=True,
            )
        names = [row[1] for row in self.read_rows()]
        self.assertEqual(len(names), len(set(names)))
        self.assertNotIn(self.post[1], names)

    def test_cli_wires_exclusion(self):
        result = adapter.main([
            str(self.report), "--template", str(self.template),
            "--output", str(self.output), "--replace-tests",
            "--exclude-dcc-post-calibration",
        ])
        self.assertEqual(result, 0)
        self.assertFalse(
            any(row[1].startswith("DCC.post_calibration.") for row in self.read_rows())
        )


if __name__ == "__main__":
    unittest.main()
