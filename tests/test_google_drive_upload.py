import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile


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
    def run_upload(
        self, destination, rclone_exitcode=0, folders=(), fail_command="",
        zip_failure=False, retention_failure=False, cleanup_failure=False,
    ):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            source = directory / "Device logs"
            source.mkdir()
            old_zip = source / "Robocal_20200101_000000_000.zip"
            old_zip.write_bytes(b"previous archive")
            for folder in folders:
                component = source / folder
                component.mkdir()
                (component / "result.txt").write_text("test data", encoding="ascii")
            calls = directory / "calls.txt"
            stub = directory / "rclone.bat"
            stub.write_text(
                '@echo off\n'
                'echo %*>>"%UPLOAD_TEST_CALLS%"\n'
                'if /i "%~1"=="%UPLOAD_TEST_FAIL_COMMAND%" exit /b 1\n'
                'exit /b %UPLOAD_TEST_EXITCODE%\n',
                encoding="ascii",
            )
            # CALL lets the batch stub return like the real rclone executable.
            script = directory / "upload.bat"
            script.write_text(
                UPLOADER.read_text(encoding="utf-8")
                .replace("rclone ", "call rclone ")
                .replace(
                    r"%~dp07z\7za.exe",
                    str(UPLOADER.parent / "7z" / "7za.exe")
                    if not zip_failure else str(directory / "missing-7za.exe"),
                )
                .replace(
                    'move /-Y "%ZIP_FILE%" "%SOURCE%\\%ZIP_NAME%" <nul',
                    "cmd /c exit 1" if retention_failure else
                    'move /-Y "%ZIP_FILE%" "%SOURCE%\\%ZIP_NAME%" <nul',
                )
                .replace(
                    'rmdir /s /q "%SOURCE%\\Robocal"',
                    "cmd /c exit 1" if cleanup_failure else
                    'rmdir /s /q "%SOURCE%\\Robocal"',
                ),
                encoding="utf-8",
            )
            environment = os.environ.copy()
            environment["PATH"] = str(directory) + os.pathsep + environment["PATH"]
            environment["UPLOAD_TEST_CALLS"] = str(calls)
            environment["UPLOAD_TEST_EXITCODE"] = str(rclone_exitcode)
            environment["UPLOAD_TEST_FAIL_COMMAND"] = fail_command
            result = subprocess.run(
                f'"{environment.get("COMSPEC", "cmd.exe")}" /d /s /c '
                f'""{script}" "{source}" "{destination}" '
                '"gdrive" "20261025/DEVICE""',
                env=environment,
                cwd=directory,
                capture_output=True,
                text=True,
                timeout=30,
            )
            recorded = calls.read_text().splitlines() if calls.exists() else []
            self.retained_zips = {}
            for archive in (directory / ".upload-temp").glob("*/*.zip"):
                with zipfile.ZipFile(archive) as zipped:
                    self.retained_zips[archive.name] = zipped.namelist()
            self.local_zips = {}
            for archive in source.glob("Robocal_*.zip"):
                if archive != old_zip:
                    with zipfile.ZipFile(archive) as zipped:
                        self.local_zips[archive.name] = zipped.namelist()
            self.remaining_folders = [
                folder for folder in folders if (source / folder).exists()
            ]
            self.assertEqual(old_zip.read_bytes(), b"previous archive")
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

    def test_zip_uploads_are_verified_before_remaining_files(self):
        result, calls = self.run_upload(
            FOLDER_ID, folders=("Robocal", "PostProcess")
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            [call.split()[0] for call in calls],
            ["lsd", "mkdir", "copyto", "check", "copyto", "check", "copy"],
        )
        self.assertEqual(len(self.local_zips), 1)
        name = next(iter(self.local_zips))
        self.assertRegex(name, r"^Robocal_\d{8}_\d{6}_\d{3}\.zip$")
        self.assertEqual(self.local_zips[name], ["Robocal/", "Robocal/result.txt"])
        for index, folder in ((2, "Robocal"), (4, "PostProcess")):
            zip_name = name if folder == "Robocal" else "PostProcess.zip"
            self.assertIn(f'"gdrive:20261025/DEVICE/{zip_name}"', calls[index])
            self.assertIn("--retries 10", calls[index])
            self.assertIn("--retries-sleep 30s", calls[index])
            self.assertIn(f'--include "/{zip_name}"', calls[index + 1])
            self.assertIn("--one-way", calls[index + 1])
        self.assertEqual(self.retained_zips, {})
        self.assertEqual(self.remaining_folders, ["PostProcess"])
        self.assertIn('--exclude "/Robocal_*.zip"', calls[-1])

    def test_failed_zip_upload_or_verification_keeps_recovery_archive(self):
        for command in ("copyto", "check"):
            with self.subTest(command=command):
                result, calls = self.run_upload(
                    FOLDER_ID, folders=("Robocal",), fail_command=command
                )
                self.assertEqual(result.returncode, 6, result.stdout + result.stderr)
                self.assertIn("ZIP retained for recovery", result.stdout)
                self.assertIn("Retry: call", result.stdout)
                self.assertNotIn("Upload completed successfully", result.stdout)
                self.assertEqual(calls[-1].split()[0], command)
                self.assertEqual(len(self.retained_zips), 1)
                name = next(iter(self.retained_zips))
                self.assertRegex(name, r"^Robocal_\d{8}_\d{6}_\d{3}\.zip$")
                self.assertEqual(
                    self.retained_zips[name], ["Robocal/", "Robocal/result.txt"]
                )
                self.assertEqual(self.local_zips, {})
                self.assertEqual(self.remaining_folders, ["Robocal"])

    def test_zip_packaging_failure_stops_before_upload(self):
        result, calls = self.run_upload(
            FOLDER_ID, folders=("Robocal",), zip_failure=True
        )
        self.assertEqual(result.returncode, 6, result.stdout + result.stderr)
        self.assertRegex(
            result.stdout, r"Could not create or verify Robocal_\d{8}_\d{6}_\d{3}\.zip"
        )
        self.assertEqual(len(calls), 2)
        self.assertEqual(self.retained_zips, {})
        self.assertEqual(self.remaining_folders, ["Robocal"])

    def test_retention_failure_preserves_folder_and_recovery_zip(self):
        result, calls = self.run_upload(
            FOLDER_ID, folders=("Robocal",), retention_failure=True
        )
        self.assertEqual(result.returncode, 6, result.stdout + result.stderr)
        self.assertIn("Could not retain the verified ZIP", result.stdout)
        self.assertEqual(self.remaining_folders, ["Robocal"])
        self.assertEqual(len(self.retained_zips), 1)
        self.assertEqual(self.local_zips, {})
        self.assertEqual(calls[-1].split()[0], "check")

    def test_cleanup_failure_reports_error_and_keeps_verified_zip(self):
        result, calls = self.run_upload(
            FOLDER_ID, folders=("Robocal",), cleanup_failure=True
        )
        self.assertEqual(result.returncode, 6, result.stdout + result.stderr)
        self.assertIn("Could not remove the backed-up Robocal folder", result.stdout)
        self.assertEqual(self.remaining_folders, ["Robocal"])
        self.assertEqual(len(self.local_zips), 1)
        self.assertEqual(self.retained_zips, {})
        self.assertEqual(calls[-1].split()[0], "check")

    def test_remaining_file_failure_is_not_success(self):
        result, calls = self.run_upload(FOLDER_ID, fail_command="copy")
        self.assertEqual(result.returncode, 6, result.stdout + result.stderr)
        self.assertIn("Upload did not complete", result.stdout)
        self.assertNotIn("Upload completed successfully", result.stdout)


@unittest.skipUnless(os.name == "nt", "Requires Windows cmd.exe")
class BackgroundUploadTests(unittest.TestCase):
    def run_worker(self, upload_exitcode=0, missing_source=False):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            source = directory / "logs" / "DEVICE" / "Robocal"
            if not missing_source:
                source.mkdir(parents=True)
            uploader = directory / "uploader.bat"
            uploader.write_text(
                f"@echo off\nexit /b {upload_exitcode}\n", encoding="ascii"
            )
            screen = directory / "screen.bat"
            screen.write_text("@echo Upload failure notification\n", encoding="ascii")
            script = directory / "start.bat"
            script.write_text(
                (ROOT / "START.bat").read_text(encoding="utf-8").replace(
                    r"Tools\Screen-diag.exe", f'call "{screen}"'
                ),
                encoding="utf-8",
            )
            environment = os.environ.copy()
            environment.update(
                LOG_ARCHIVE_ROOT=str(directory / "logs"),
                LOG_IDENTIFIER="DEVICE",
                GOOGLE_DRIVE_UPLOAD_BAT=str(uploader),
                GOOGLE_DRIVE_URL=FOLDER_ID,
                GOOGLE_DRIVE_DATE="20261025",
            )
            return subprocess.run(
                f'"{environment.get("COMSPEC", "cmd.exe")}" /d /s /c '
                f'""{script}" __UPLOAD_GRR_WORKER"',
                env=environment, cwd=directory, capture_output=True,
                text=True, timeout=15,
            )

    def test_success_does_not_notify_failure(self):
        result = self.run_worker()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("Upload failure notification", result.stdout)

    def test_background_failure_notifies_operator(self):
        result = self.run_worker(upload_exitcode=6)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("Upload failure notification", result.stdout)

    def test_missing_robocal_is_failure_not_skipped_success(self):
        result = self.run_worker(missing_source=True)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("Required Google Drive upload source is missing", result.stdout)
        self.assertIn("Upload failure notification", result.stdout)


if __name__ == "__main__":
    unittest.main()
