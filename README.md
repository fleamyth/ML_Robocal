# ML_Robocal

## Google Drive uploads

`START.bat` uploads archived logs from `D:\logs\<device serial>` to the
configured Google Drive folder under `yyyyMMdd/<device serial>`.
The `Robocal` subfolder is uploaded as `Robocal.zip`.

Set `GOOGLE_DRIVE_URL` in `START.bat` to the destination folder ID (recommended).
The shared uploader also accepts `https://drive.google.com/drive/folders/<ID>`
and account-specific URLs such as `https://drive.google.com/drive/u/2/folders/<ID>`.
The `/u/2/` account selector does not select the rclone account: uploads use the
account authorized for the `gdrive` remote.

Upload logs are in `ML_Robocal_1.00a_20260804\Tools\logs\rclone-upload-<device serial>.log`.
To check destination access without uploading files:

```powershell
rclone lsd "gdrive:" --drive-root-folder-id "1U9hKoGkFsbvxEMnuKuYXAAUKrL1CcUBn"
```

A `404` with the correct folder ID requires checking that the rclone account
has access to that folder. A `403 rateLimitExceeded` is a Google API quota
failure, not an upload success. Wait before retrying; if the shared-client quota
continues to block uploads, configure your own Google OAuth client ID and secret
for the `gdrive` remote using `rclone config`, then reauthorize it as instructed.
Do not store OAuth secrets or tokens in this repository.
See https://rclone.org/drive/#making-your-own-client-id.

Run the offline uploader regression tests on Windows with:

```powershell
python -m unittest discover -s tests -p test_google_drive_upload.py
```