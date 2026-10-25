import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
UPLOADER = (
    ROOT
    / "ML_Robocal_1.00a_20260804"
    / "Tools"
    / "upload_Folder_to_google_drive.bat"
)
FOLDER_ID = "1U9hKoGkFsbvxEMnuKuYXAAUKrL1CcUBn"


@unittest.skipUnless(os.name == "nt", "Requires Windows cmd.exe")
class GoogleDriveUploadTests(unittest.TestCase):
    def run_upload(self, destination, rclone_exitcode=0):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            source = directory / "Device logs"
            source.mkdir()
            calls = directory / "calls.txt"
            stub = directory / "rclone.bat"
            stub.write_text(
                '@echo off\n'
                'echo %*>>"%UPLOAD_TEST_CALLS%"\n'
                'exit /b %UPLOAD_TEST_EXITCODE%\n',
                encoding="ascii",
            )
            # CALL lets the batch stub return like the real rclone executable.
            script = directory / "upload.bat"
            script.write_text(
                UPLOADER.read_text(encoding="utf-8").replace(
                    "rclone ", "call rclone "
                ),
                encoding="utf-8",
            )
            environment = os.environ.copy()
            environment["PATH"] = str(directory) + os.pathsep + environment["PATH"]
            environment["UPLOAD_TEST_CALLS"] = str(calls)
            environment["UPLOAD_TEST_EXITCODE"] = str(rclone_exitcode)
            result = subprocess.run(
                f'"{environment.get("COMSPEC", "cmd.exe")}" /d /s /c '
                f'""{script}" "{source}" "{destination}" '
                '"gdrive" "20261025/DEVICE""',
                env=environment,
                cwd=directory,
                capture_output=True,
                text=True,
                timeout=15,
            )
            recorded = calls.read_text().splitlines() if calls.exists() else []
            return result, recorded

    def test_supported_folder_formats(self):
        for destination in (
            FOLDER_ID,
            f"https://drive.google.com/drive/folders/{FOLDER_ID}",
            f"https://drive.google.com/drive/u/2/folders/{FOLDER_ID}",
            f"https://drive.google.com/drive/u/0/folders/{FOLDER_ID}?usp=sharing",
            f"https://drive.google.com/drive/folders/{FOLDER_ID}/",
            f"https://drive.google.com/drive/folders/{FOLDER_ID}#fragment",
        ):
            with self.subTest(destination=destination):
                result, calls = self.run_upload(destination)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(len(calls), 3, calls)
                for call in calls:
                    self.assertIn(f'--drive-root-folder-id "{FOLDER_ID}"', call)
                self.assertIn('"gdrive:20261025/DEVICE"', calls[1])
                self.assertIn('"gdrive:20261025/DEVICE"', calls[2])

    def test_invalid_folder_rejected_before_rclone(self):
        for destination in (
            "https://drive.google.com/drive/u/2/",
            "https://example.com/drive/folders/invalid",
            "invalid folder",
        ):
            with self.subTest(destination=destination):
                result, calls = self.run_upload(destination)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("Invalid Google Drive", result.stdout)
                self.assertEqual(calls, [])

    def test_destination_access_failure_stops_upload(self):
        result, calls = self.run_upload(FOLDER_ID, rclone_exitcode=1)
        self.assertEqual(result.returncode, 4, result.stdout + result.stderr)
        self.assertIn("Cannot access the Google Drive destination", result.stdout)
        self.assertEqual(len(calls), 1, calls)


if __name__ == "__main__":
    unittest.main()
